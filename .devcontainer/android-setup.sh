#!/bin/bash
set -e

echo "==> Running android-setup for neurofeed"

CACHE_DIR="/opt/backups"
ANDROID_HOME="$HOME/android-sdk"
# Pinned by apps/neurofeed-android/android/app/build.gradle.kts
NDK_VERSION="27.2.12479018"

# =====================
# OWNERSHIP (safe to run again)
# =====================
echo "==> Fixing ownership..."
mkdir -p "${ANDROID_HOME}"
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
            rm -f "$partial"
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

    # compileSdk 35 + ndkVersion in apps/neurofeed-android.
    local packages=(
        "platform-tools"
        "build-tools;35.0.0"
        "platforms;android-35"
        "ndk;${NDK_VERSION}"
    )

    # Capture the installed list once (sdkmanager output is slow to produce)
    local installed_list
    installed_list=$(sdkmanager --list_installed 2>/dev/null || true)

    for pkg in "${packages[@]}"; do
        # Use fixed-string match (-F) on the distinctive package id.
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
# RUST ANDROID
# =====================
setup_rust_android() {
    echo "==> Setting up Rust Android targets + cargo-ndk..."

    if ! command -v rustup >/dev/null 2>&1; then
        echo "    rustup is missing. Run bash .devcontainer_rs/rust-setup.sh first."
        exit 1
    fi

    # Make sure Cargo environment is loaded
    # shellcheck disable=SC1091
    [ -f "$HOME/.cargo/env" ] && source "$HOME/.cargo/env"

    # ABIs in apps/neurofeed-android/android/gradle.properties:
    # arm64-v8a, armeabi-v7a, x86_64
    for target in aarch64-linux-android armv7-linux-androideabi x86_64-linux-android; do
        if rustup target list --installed 2>/dev/null | grep -q "$target"; then
            echo "    [x] $target target present"
        else
            echo "    Adding $target..."
            rustup target add "$target"
        fi
    done

    # cargo-ndk is the build helper Gradle calls (`cargo ndk -t <abi>`).
    # Pinned because this tree uses one NDK (27.2.12479018).
    if [ -x "$HOME/.cargo/bin/cargo-ndk" ] || type -P cargo-ndk > /dev/null 2>&1; then
        echo "    [x] cargo-ndk already installed"
    else
        echo "    Installing cargo-ndk..."
        cargo install cargo-ndk --version 4.1.2 --locked
        echo "    [x] cargo-ndk installed"
        # shellcheck disable=SC1091
        [ -f "$HOME/.cargo/env" ] && source "$HOME/.cargo/env"
    fi
}

# =====================
# RUN EVERYTHING
# =====================
setup_cmdline_tools
setup_android_components
setup_rust_android

sudo chown -R vscode:vscode "${ANDROID_HOME}"

echo ""
echo "==> Android setup complete!"
echo "    Run 'bash .devcontainer_rs/verify-setup.sh' to see status."
echo "    Build: cd apps/neurofeed-android/android && ./gradlew assembleDebug"
