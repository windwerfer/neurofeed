#!/bin/bash
set -e

# Portable command existence check (sh/bash/zsh compatible)
has_cmd() {
    command -v "$1" >/dev/null 2>&1
}

echo "==> Running rust-setup for neurofeed"

# =====================
# OWNERSHIP (safe to run again)
# =====================
echo "==> Fixing volume permissions..."
mkdir -p "$HOME/.cargo" "$HOME/android-sdk"
sudo chown -R vscode:vscode \
    "$HOME/.cargo" \
    "$HOME/android-sdk" \
    /opt/backups

chmod +x .devcontainer_rs/*.sh 2>/dev/null || true

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

# shellcheck disable=SC1091
[[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"

rustup toolchain install stable
rustup default stable
rustup component add clippy rustfmt

if rustup target list --installed 2>/dev/null | grep -q '^wasm32-unknown-unknown$'; then
    echo "    [x] wasm32-unknown-unknown target present"
else
    echo "    Adding wasm32-unknown-unknown..."
    rustup target add wasm32-unknown-unknown
fi

# trunk serves the egui web app (apps/neurofeed-egui, port 8080).
if has_cmd trunk; then
    echo "    [x] trunk already installed"
else
    echo "    Installing trunk..."
    cargo install trunk --locked
    echo "    [x] trunk installed"
fi

echo "==> Rust setup complete."
echo "    Run 'bash .devcontainer_rs/android-setup.sh' next, then verify-setup.sh."
