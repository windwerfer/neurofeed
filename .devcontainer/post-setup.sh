#!/bin/bash
set -e

echo "==> Running post-setup for neurofeed"

# =====================
# OWNERSHIP (safe to run again)
# =====================
echo "==> Fixing volume permissions..."
mkdir -p "$HOME/.cargo" "$HOME/android-sdk"
sudo chown -R vscode:vscode \
    "$HOME/.cargo" \
    "$HOME/android-sdk" \
    /opt/backups

# Make shell scripts executable.
# Git does not reliably preserve +x after clone (especially cross-platform or via some UIs).
# This runs after the workspace is mounted, so it actually affects what you see.
chmod +x .devcontainer_rs/*.sh 2>/dev/null || true

echo ""
echo "==> Post-setup complete."
echo "    Next:"
echo "      bash .devcontainer_rs/rust-setup.sh"
echo "      bash .devcontainer_rs/android-setup.sh"
echo "      bash .devcontainer_rs/verify-setup.sh"
echo ""
