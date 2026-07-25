#!/bin/bash
set -e

echo "==> Running android-setup for fl_muse_brainflow_MVP"

CACHE_DIR="/opt/backups"
ANDROID_HOME="$HOME/android-sdk"

# =====================
# OWNERSHIP (safe to run again)
# =====================
echo "==> Fixing ownership..."
sudo chown -R vscode:vscode \
    "${ANDROID_HOME}" \
    "${CACHE_DIR}"

# =====================
# CMDLINE-TOOLS (provides sdkmanager)
# =====================
CMDLINE_BUILD="14742923"
CMDLINE_ZIP="commandlinetools-linux-${CMDLINE_BUILD}_latest.zip"
CMDLINE_URL="https://dl.google.com/android/repository/${CMDLINE_ZIP}"
CMDLINE_TARGET="${ANDROID_HOME}/cmdline-tools/latest"

setup_cmdline_tools() {
    if [ -x "${CMDLINE_TARGET}/bin/sdkmanager" ]; then
        echo "    [x] cmdline-tools (sdkmanager) already present"
        return 0
    fi

    echo "    Setting up Android Command Line Tools..."
    mkdir -p "${ANDROID_HOME}/cmdline-tools"

    local cached_zip="${CACHE_DIR}/${CMDLINE_ZIP}"

    if [ -f "$cached_zip" ]; then
        echo "    Using cached ${CMDLINE_ZIP}"
        echo "    Verifying archive integrity..."
        if ! unzip -tq "$cached_zip" >/dev/null 2>&1; then
            echo "    Integrity check failed. Removing bad cached file."
            rm -f "$cached_zip"
            exit 1
        fi
    else
        local partial="${cached_zip}.part"

        if [ -f "$partial" ]; then
            echo "    Resuming previous interrupted download of cmdline-tools..."
        else
            echo "    Downloading cmdline-tools (~173 MB) to cache..."
        fi

        # -C - : resume if partial file exists (server must support Range requests — Google does)
        # --retry : be a bit more resilient to flaky networks
        if curl -fSL -C - --retry 3 --retry-delay 2 "$CMDLINE_URL" -o "$partial"; then
            mv -f "$partial" "$cached_zip"
            echo "    Verifying archive integrity..."
            if ! unzip -tq "$cached_zip" >/dev/null 2>&1; then
                echo "    Integrity check failed. Removing bad cached file."
                rm -f "$cached_zip"
                exit 1
            fi
            echo "    Cached for future container recreates."
        else
            echo "    Download failed or was interrupted."
            rm -f "$partial"   # clean up so next run starts fresh
            exit 1
        fi
    fi

    # Extract from cache
    unzip -q "$cached_zip" -d "${ANDROID_HOME}/cmdline-tools"

    # Modern zips contain a "cmdline-tools/" folder inside
    if [ -d "${ANDROID_HOME}/cmdline-tools/cmdline-tools" ]; then
        mv "${ANDROID_HOME}/cmdline-tools/cmdline-tools" "${CMDLINE_TARGET}"
    else
        # Fallback (rare)
        mkdir -p "${CMDLINE_TARGET}"
        mv "${ANDROID_HOME}/cmdline-tools"/* "${CMDLINE_TARGET}/" 2>/dev/null || true
    fi

    sudo chown -R vscode:vscode "${ANDROID_HOME}/cmdline-tools"
    echo "    [x] cmdline-tools installed"
}

# =====================
# ANDROID SDK COMPONENTS
# =====================
setup_android_components() {
    export PATH="${CMDLINE_TARGET}/bin:${ANDROID_HOME}/platform-tools:${PATH}"

    echo "==> Accepting Android licenses (non-interactive)..."
    yes | sdkmanager --licenses || true

    local packages=(
        "platform-tools"
        "build-tools;34.0.0"
        "platforms;android-34"
        # "ndk;28.2.13676358"
        "ndk;27.0.12077973"  # flet+flutter wants ndk 27.0.12077973 specifically
    )

    # Capture the installed list once (sdkmanager output is slow to produce)
    local installed_list
    installed_list=$(sdkmanager --list_installed 2>/dev/null || true)

    for pkg in "${packages[@]}"; do
        # Use fixed-string match (-F) on the distinctive package id.
        # This is more reliable than a plain substring grep against the
        # multi-column / sectioned output of --list_installed.
        if echo "$installed_list" | grep -F -q "$pkg"; then
            echo "    [x] $pkg already installed"
        else
            echo "    Installing $pkg ... (can take a while)"
            yes | sdkmanager "$pkg"
            echo "    [x] $pkg installed"
        fi
    done
}

# =====================
# RUST ANDROID (only needed for Android builds)
# =====================
setup_rust_android() {
    echo "==> Setting up Rust Android targets + cargo-ndk..."

    # Make sure Cargo environment is loaded
    [ -f "$HOME/.cargo/env" ] && source "$HOME/.cargo/env"

    # Rust targets (both arm64 + arm32 as requested)
    for target in aarch64-linux-android armv7-linux-androideabi; do
        if rustup target list --installed 2>/dev/null | grep -q "$target"; then
            echo "    [x] $target target present"
        else
            echo "    Adding $target..."
            rustup target add "$target"
        fi
    done

    # cargo-ndk (pinned for reproducibility + known good compatibility with NDK r28)
    # Unlike flutter_rust_bridge_codegen (which generates code and must match the exact
    # runtime version in Cargo.toml), cargo-ndk is "only" a build helper. However we still
    # pin it here because:
    # - the real Android .so build is invoked from Gradle via `cargo ndk ...`
    # - we use a very specific NDK (28.2.13676358)
    # - historical cargo-ndk <-> NDK version incompatibilities have bitten people before
    if [ -x "$HOME/.cargo/bin/cargo-ndk" ] || type -P cargo-ndk > /dev/null 2>&1; then
        echo "    [x] cargo-ndk already installed"
    else
        echo "    Installing cargo-ndk..."
        cargo install cargo-ndk --version 4.1.2 --locked
        echo "    [x] cargo-ndk installed"

        # Refresh PATH immediately
        [ -f "$HOME/.cargo/env" ] && source "$HOME/.cargo/env"
    fi
}

# =====================
# RUN EVERYTHING
# =====================
setup_cmdline_tools
setup_android_components
# setup_rust_android

sudo chown -R vscode:vscode "${ANDROID_HOME}"

echo ""
echo "==> Android setup complete!"
echo "    Run './verify-setup.sh' to see status."
