#!/bin/bash
set -e

# Portable command existence check (sh/bash/zsh compatible)
has_cmd() {
    command -v "$1" >/dev/null 2>&1
}


echo "==> Running post-setup for fl_muse_brainflow_MVP"

CACHE_DIR="/opt/backups"
FLUTTER_VERSION="3.41.7"
FLUTTER_TAR="flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"
FLUTTER_DIR="$HOME/flutter"

# =====================
# OWNERSHIP (safe to run again)
# =====================
echo "==> Fixing volume permissions..."
sudo chown -R vscode:vscode \
    "$HOME/.cargo" \
    "$HOME/android-sdk" \
    "$HOME/flutter" \
    /opt/backups

# Make .devcontainer shell scripts executable.
# Git does not reliably preserve +x after clone (especially cross-platform or via some UIs).
# This runs after the workspace is mounted, so it actually affects what you see.
chmod +x .devcontainer/*.sh 2>/dev/null || true

# =====================
# FLUTTER
# =====================
echo "==> Setting up Flutter ${FLUTTER_VERSION}..."

if has_cmd flutter; then
    echo "    [x] Flutter already installed and executable — skipping download"
else
    cached_tar="${CACHE_DIR}/${FLUTTER_TAR}"

    if [ -f "$cached_tar" ]; then
        echo "    Using cached Flutter from ${CACHE_DIR}"
        echo "    Verifying archive integrity..."
        if ! tar -tJf "$cached_tar" >/dev/null 2>&1; then
            echo "    Integrity check failed. Removing bad cached file."
            rm -f "$cached_tar"
            exit 1
        fi
    else
        partial="${cached_tar}.part"

        if [ -f "$partial" ]; then
            echo "    Resuming previous interrupted download of Flutter..."
        else
            echo "    Downloading Flutter (~800 MB) to cache..."
        fi

        # -C - : resume partial download if possible
        # --retry : tolerate transient network hiccups
        if curl -fSL -C - --retry 3 --retry-delay 2 \
            "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/${FLUTTER_TAR}" \
            -o "$partial"; then
            mv -f "$partial" "$cached_tar"
            echo "    Verifying archive integrity..."
            if ! tar -tJf "$cached_tar" >/dev/null 2>&1; then
                echo "    Integrity check failed. Removing bad cached file."
                rm -f "$cached_tar"
                exit 1
            fi
            echo "    Cached for future container recreates."
        else
            echo "    Download failed or was interrupted."
            rm -f "$partial"
            exit 1
        fi
    fi

    # Extract from cache
    tar -xJf "$cached_tar" -C "$HOME"
fi
