#!/bin/bash
set -e

# Portable command existence check (sh/bash/zsh compatible)
has_cmd() {
    command -v "$1" >/dev/null 2>&1
}


echo "==> Running post-setup for fl_muse_brainflow_MVP"

CACHE_DIR="/opt/backups"
FLUTTER_VERSION="3.44.1"
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
# RUST
# =====================
echo "==> Setting up Rust..."

if has_cmd rustup; then
    echo "    [x] rustup already installed"
else
    echo "    Installing rustup..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
fi

rustup toolchain install stable
rustup component add clippy rustfmt

echo "==> Post-setup complete."
echo "    Run './verify-setup.sh' to see full status."

# Install flutter_rust_bridge_codegen if not already present (idempotent)
if has_cmd flutter_rust_bridge_codegen; then
    echo "    [x] flutter_rust_bridge_codegen already installed"
else
    echo "    Installing flutter_rust_bridge_codegen..."
    cargo install --locked flutter_rust_bridge_codegen --version 2.11.1
    echo "    [x] flutter_rust_bridge_codegen installed"
fi
