#!/bin/bash

echo "=============================================="
echo "   neurofeed  —  Setup Verification"
echo "=============================================="
echo ""

# Colors (optional, works in most terminals)
GREEN="\033[0;32m"
RED="\033[0;31m"
NC="\033[0m"   # No Color

print_check() {
    local label="$1"
    local state="$2"
    if [[ "$state" = "ok" ]]; then
        printf "  ${GREEN}[x]${NC} %-42s\n" "$label"
    else
        printf "  ${RED}[ ]${NC} %-42s\n" "$label"
    fi
}

# Portable command existence check (sh/bash/zsh compatible)
has_cmd() {
    command -v "$1" >/dev/null 2>&1
}

# =====================
# RUST / DESKTOP
# =====================
echo "Rust / desktop"
echo "----------------------------------------------"

if has_cmd rustc; then
    print_check "Rust (rustc)" "ok"
else
    print_check "Rust (rustc)" "missing"
fi

if has_cmd cargo; then
    print_check "Cargo" "ok"
else
    print_check "Cargo" "missing"
fi

if has_cmd cargo-clippy; then
    print_check "Clippy" "ok"
else
    print_check "Clippy" "missing"
fi

if has_cmd rustfmt; then
    print_check "rustfmt" "ok"
else
    print_check "rustfmt" "missing"
fi

if rustup target list --installed 2>/dev/null | grep -q '^wasm32-unknown-unknown$'; then
    print_check "Rust target: wasm32-unknown-unknown" "ok"
else
    print_check "Rust target: wasm32-unknown-unknown" "missing"
fi

if has_cmd trunk; then
    print_check "trunk (web, :8080)" "ok"
else
    print_check "trunk (web, :8080)" "missing"
fi

if pkg-config --exists alsa dbus-1 2>/dev/null; then
    print_check "libasound + libdbus (cpal, BlueZ)" "ok"
else
    print_check "libasound + libdbus (cpal, BlueZ)" "missing"
fi

echo ""

# =====================
# ANDROID
# =====================
echo "Android"
echo "----------------------------------------------"

if has_cmd java && java -version 2>&1 | grep -q "21"; then
    print_check "Java 21" "ok"
else
    print_check "Java 21" "missing/wrong version"
fi

if [[ -n "${ANDROID_HOME}" ]] && [[ -d "${ANDROID_HOME}" ]]; then
    print_check "ANDROID_HOME set + directory exists" "ok"
else
    print_check "ANDROID_HOME" "missing"
fi

if [[ -x "${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager" ]]; then
    print_check "cmdline-tools + sdkmanager" "ok"
else
    print_check "cmdline-tools + sdkmanager" "missing"
fi

if [[ -d "${ANDROID_HOME}/platform-tools" ]] && [[ -x "${ANDROID_HOME}/platform-tools/adb" ]]; then
    print_check "platform-tools (adb)" "ok"
else
    print_check "platform-tools (adb)" "missing"
fi

if [[ -d "${ANDROID_HOME}/build-tools/35.0.0" ]]; then
    print_check "build-tools;35.0.0" "ok"
else
    print_check "build-tools;35.0.0" "missing"
fi

if [[ -d "${ANDROID_HOME}/platforms/android-35" ]]; then
    print_check "platforms;android-35" "ok"
else
    print_check "platforms;android-35" "missing"
fi

if [[ -d "${ANDROID_HOME}/ndk/27.2.12479018" ]]; then
    print_check "NDK 27.2.12479018" "ok"
else
    print_check "NDK 27.2.12479018" "missing"
fi

if rustup target list --installed 2>/dev/null | grep -q "aarch64-linux-android"; then
    print_check "Rust target: aarch64-linux-android" "ok"
else
    print_check "Rust target: aarch64-linux-android" "missing"
fi

if rustup target list --installed 2>/dev/null | grep -q "armv7-linux-androideabi"; then
    print_check "Rust target: armv7-linux-androideabi" "ok"
else
    print_check "Rust target: armv7-linux-androideabi" "missing"
fi

if rustup target list --installed 2>/dev/null | grep -q "x86_64-linux-android"; then
    print_check "Rust target: x86_64-linux-android" "ok"
else
    print_check "Rust target: x86_64-linux-android" "missing"
fi

if has_cmd cargo-ndk; then
    print_check "cargo-ndk" "ok"
else
    print_check "cargo-ndk" "missing"
fi

echo ""
echo "=============================================="
echo "Desktop:  cargo run --release -p neurofeed-egui"
echo "Web:      cd apps/neurofeed-egui && trunk serve --release"
echo "Android:  cd apps/neurofeed-android/android && ./gradlew assembleDebug"
echo "=============================================="
