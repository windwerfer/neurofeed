#!/bin/bash
set -euo pipefail

#  ====================
#
#   Muse dev container backup/restore script
#   Run this FROM INSIDE the container (as vscode user).
#
#   Backs up:
#     - ~/.cargo + ~/.rustup   → one file (rust)
#     - ~/.gradle              → one file (gradle)
#     - ~/.opencode + ~/.grok   → one file (agents)
#     - /usr/local/flutter     → one file
#     - /opt/android-sdk       → one file
#
#   Destination: /opt/download-cache/backups/
#
#   Excludes re-fetchable cache directories to keep backups smaller.
#
# ====================

# =====================
# Configuration
# =====================
DEFAULT_BACKUP_DIR="/opt/backups/flutter_muse_ml/"

# =====================
# Helper Functions
# =====================
log() {
    echo "==> $1"
}

# =====================
# Backup Function
# =====================
do_backup() {
    local backup_dir="${1:-${DEFAULT_BACKUP_DIR}}"
    local ts
    ts=$(date +%Y-%m-%d_%H%M)

    mkdir -p "${backup_dir}"
    local run_dir="${backup_dir}/${ts}"
    mkdir -p "${run_dir}"

    log "Starting backup (inside container)"
    log "Backup directory: ${backup_dir}"
    log "Run subfolder: ${ts}"
    echo

    # --- Rust: ~/.cargo + ~/.rustup (exclude cargo's download cache) ---
    local rust_file="${run_dir}/rust-backup-${ts}.tar.zst"
    local rust_paths=()
    [[ -d "$HOME/.cargo" ]] && rust_paths+=(".cargo")
    [[ -d "$HOME/.rustup" ]] && rust_paths+=(".rustup")

    if (( ${#rust_paths[@]} > 0 )); then
        log "Backing up Rust (~/.cargo + ~/.rustup)"
        tar -C "$HOME" \
            --exclude='.cargo/registry/cache' \
            --zstd -cf "$rust_file" "${rust_paths[@]}"

        local size
        size=$(du -h "${rust_file}" | cut -f1)
        log "✅ Created $(basename "${rust_file}") (${size})"
    else
        log "⚠ No Rust directories found — skipping rust backup"
    fi

    # --- Flutter: /usr/local/flutter (exclude heavy bin/cache) ---
    local flutter_file="${run_dir}/flutter-backup-${ts}.tar.zst"
    if [[ -d "/usr/local/flutter" ]]; then
        log "Backing up Flutter (/usr/local/flutter)"
        tar -C /usr/local \
            --exclude='flutter/bin/cache' \
            --zstd -cf "$flutter_file" flutter

        local size
        size=$(du -h "${flutter_file}" | cut -f1)
        log "✅ Created $(basename "${flutter_file}") (${size})"
    else
        log "⚠ /usr/local/flutter not found — skipping flutter backup"
    fi

    # --- Android SDK: /opt/android-sdk (exclude large emulator images + temps) ---
    local android_file="${run_dir}/android-sdk-backup-${ts}.tar.zst"
    if [[ -d "/opt/android-sdk" ]]; then
        log "Backing up Android SDK (/opt/android-sdk)"
        tar -C /opt \
            --exclude='android-sdk/system-images' \
            --exclude='android-sdk/temp' \
            --exclude='android-sdk/.tmp' \
            --zstd -cf "$android_file" android-sdk

        local size
        size=$(du -h "${android_file}" | cut -f1)
        log "✅ Created $(basename "${android_file}") (${size})"
    else
        log "⚠ /opt/android-sdk not found — skipping android-sdk backup"
    fi

    # --- Gradle: ~/.gradle (exclude build caches + daemon + transforms) ---
    local gradle_file="${run_dir}/gradle-backup-${ts}.tar.zst"
    if [[ -d "$HOME/.gradle" ]]; then
        log "Backing up Gradle (~/.gradle)"
        tar -C "$HOME" \
            --exclude='.gradle/daemon' \
            --exclude='.gradle/native' \
            --exclude='.gradle/caches/transforms-3' \
            --exclude='.gradle/caches/build-cache-*' \
            --exclude='.gradle/caches/journal-*' \
            --zstd -cf "$gradle_file" .gradle

        local size
        size=$(du -h "${gradle_file}" | cut -f1)
        log "✅ Created $(basename "${gradle_file}") (${size})"
    else
        log "⚠ ~/.gradle not found — skipping gradle backup"
    fi

    # --- Agents: ~/.opencode + ~/.grok (small config dirs, full backup) ---
    local agents_file="${run_dir}/agents-backup-${ts}.tar.zst"
    local agents_paths=()
    [[ -d "$HOME/.opencode" ]] && agents_paths+=(".opencode")
    [[ -d "$HOME/.grok" ]] && agents_paths+=(".grok")

    if (( ${#agents_paths[@]} > 0 )); then
        log "Backing up agents config (~/.opencode + ~/.grok)"
        tar -C "$HOME" \
            --zstd -cf "$agents_file" "${agents_paths[@]}"

        local size
        size=$(du -h "${agents_file}" | cut -f1)
        log "✅ Created $(basename "${agents_file}") (${size})"
    else
        log "⚠ No ~/.opencode or ~/.grok directories found — skipping agents backup"
    fi

    echo
    log "Backup complete."
}

# =====================
# Restore Function
# =====================
do_restore() {
    local backup_dir="${1:-${DEFAULT_BACKUP_DIR}}"

    if [[ ! -d "${backup_dir}" ]]; then
        log "Backup directory does not exist: ${backup_dir}"
        exit 1
    fi

    # List available run subfolders (yyyy-mm-dd_HHMM).
    local -a subdirs
    mapfile -t subdirs < <(find "${backup_dir}" -maxdepth 1 -mindepth 1 -type d -printf '%f\n' 2>/dev/null | sort -r)

    if (( ${#subdirs[@]} == 0 )); then
        log "No backup subfolders found in ${backup_dir}"
        exit 1
    fi

    echo "Available backup runs:"
    local i
    for i in "${!subdirs[@]}"; do
        echo "  [$((i + 1))] ${subdirs[$i]}"
    done
    echo

    local choice
    read -r -p "Select a backup run to restore from [1-${#subdirs[@]}]: " choice
    if ! [[ "${choice}" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#subdirs[@]} )); then
        log "Invalid selection: ${choice}"
        exit 1
    fi

    local run_dir="${backup_dir}/${subdirs[$((choice - 1))]}"
    log "Restore mode — using backup run: ${subdirs[$((choice - 1))]}"
    log "Restore source: ${run_dir}"
    echo

    # --- Rust ---
    local latest_rust
    latest_rust=$(ls -t "${run_dir}"/rust-backup-*.tar.zst 2>/dev/null | head -n1 || true)
    if [[ -n "${latest_rust}" ]]; then
        echo "Rust backup found: $(basename "${latest_rust}")"
        echo "  WARNING: This will erase ~/.cargo and ~/.rustup, then restore the backup."
        read -r -p "  Restore rust? (YES/no): " reply
        if [[ "${reply}" == "YES" ]]; then
            log "Erasing old Rust data..."
            rm -rf "$HOME/.cargo" "$HOME/.rustup" 2>/dev/null || true
            log "Restoring..."
            tar -C "$HOME" --zstd -xf "${latest_rust}"
            log "✅ Restored rust"
        else
            log "Skipped rust."
        fi
    else
        log "No rust backup found in ${run_dir}"
    fi
    echo

    # --- Flutter ---
    local latest_flutter
    latest_flutter=$(ls -t "${run_dir}"/flutter-backup-*.tar.zst 2>/dev/null | head -n1 || true)
    if [[ -n "${latest_flutter}" ]]; then
        echo "Flutter backup found: $(basename "${latest_flutter}")"
        echo "  WARNING: This will erase /usr/local/flutter, then restore the backup."
        read -r -p "  Restore flutter? (YES/no): " reply
        if [[ "${reply}" == "YES" ]]; then
            log "Erasing old Flutter directory contents..."
            sudo find /usr/local/flutter -mindepth 1 -delete 2>/dev/null || true
            log "Restoring..."
            sudo tar -C /usr/local --zstd -xf "${latest_flutter}"
            sudo chown -R vscode:vscode /usr/local/flutter
            log "✅ Restored flutter"
        else
            log "Skipped flutter."
        fi
    else
        log "No flutter backup found in ${run_dir}"
    fi
    echo

    # --- Android SDK ---
    local latest_android
    latest_android=$(ls -t "${run_dir}"/android-sdk-backup-*.tar.zst 2>/dev/null | head -n1 || true)
    if [[ -n "${latest_android}" ]]; then
        echo "Android SDK backup found: $(basename "${latest_android}")"
        echo "  WARNING: This will erase /opt/android-sdk, then restore the backup."
        read -r -p "  Restore android-sdk? (YES/no): " reply
        if [[ "${reply}" == "YES" ]]; then
            log "Erasing old Android SDK directory contents..."
            sudo find /opt/android-sdk -mindepth 1 -delete 2>/dev/null || true
            log "Restoring..."
            sudo tar -C /opt --zstd -xf "${latest_android}"
            sudo chown -R vscode:vscode /opt/android-sdk
            log "✅ Restored android-sdk"
        else
            log "Skipped android-sdk."
        fi
    else
        log "No android-sdk backup found in ${run_dir}"
    fi
    echo

    # --- Gradle ---
    local latest_gradle
    latest_gradle=$(ls -t "${run_dir}"/gradle-backup-*.tar.zst 2>/dev/null | head -n1 || true)
    if [[ -n "${latest_gradle}" ]]; then
        echo "Gradle backup found: $(basename "${latest_gradle}")"
        echo "  WARNING: This will erase ~/.gradle, then restore the backup."
        read -r -p "  Restore gradle? (YES/no): " reply
        if [[ "${reply}" == "YES" ]]; then
            log "Erasing old Gradle data..."
            rm -rf "$HOME/.gradle" 2>/dev/null || true
            log "Restoring..."
            tar -C "$HOME" --zstd -xf "${latest_gradle}"
            log "✅ Restored gradle"
        else
            log "Skipped gradle."
        fi
    else
        log "No gradle backup found in ${run_dir}"
    fi
    echo

    # --- Agents ---
    local latest_agents
    latest_agents=$(ls -t "${run_dir}"/agents-backup-*.tar.zst 2>/dev/null | head -n1 || true)
    if [[ -n "${latest_agents}" ]]; then
        echo "Agents backup found: $(basename "${latest_agents}")"
        echo "  WARNING: This will erase ~/.opencode and ~/.grok, then restore the backup."
        read -r -p "  Restore agents? (YES/no): " reply
        if [[ "${reply}" == "YES" ]]; then
            log "Erasing old agents data..."
            rm -rf "$HOME/.opencode" "$HOME/.grok" 2>/dev/null || true
            log "Restoring..."
            tar -C "$HOME" --zstd -xf "${latest_agents}"
            log "✅ Restored agents"
        else
            log "Skipped agents."
        fi
    else
        log "No agents backup found in ${run_dir}"
    fi

    echo
    log "Restore complete."
    echo "Note: some caches (cargo registry, flutter engine, emulator images) were not backed up and may need to be re-populated."
}

# =====================
# Main
# =====================
if [ $# -eq 0 ]; then
    echo "Usage: $0 [backup|restore] [backup_directory]"
    echo "   backup  - Create timestamped zstd-compressed tar backups of rust, gradle, agents, flutter, and android-sdk"
    echo "   restore - Selectively restore the most recent backup of each component"
    echo "   (second argument = path to backup folder, defaults to ${DEFAULT_BACKUP_DIR})"
    echo
    echo "This script is intended to run from *inside* the dev container."
    echo
    echo "Recommended ways to run (works after fresh git clone):"
    echo "    bash .devcontainer/backup.sh backup"
    echo "    bash .devcontainer/backup.sh restore"
    echo
    echo "If the script is executable you can also use:"
    echo "    ./.devcontainer/backup.sh backup"
    exit 1
fi

ACTION="${1}"
BACKUP_DIR="${2:-${DEFAULT_BACKUP_DIR}}"

case "${ACTION}" in
    backup)
        do_backup "${BACKUP_DIR}"
        ;;
    restore)
        do_restore "${BACKUP_DIR}"
        ;;
    *)
        echo "Error: Unknown action '${ACTION}'"
        echo "Usage: $0 [backup|restore] [backup_directory]"
        exit 1
        ;;
esac
