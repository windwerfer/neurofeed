#!/usr/bin/env bash
# Build the web (wasm) app with trunk and zip it: dist/neurofeed-web-<version>.zip
# Usage: scripts/package-web.sh [--version X.Y.Z]   (needs trunk + wasm32-unknown-unknown target)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) VERSION="${2#v}"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done
[[ -n "$VERSION" ]] || VERSION="$("$ROOT/scripts/version.sh")"
APP="$ROOT/apps/neurofeed-egui"
rm -rf "$APP/dist"
(cd "$APP" && trunk build --release)
mkdir -p "$ROOT/dist"
OUT="$ROOT/dist/neurofeed-web-$VERSION.zip"
rm -f "$OUT"
if command -v zip >/dev/null; then (cd "$APP/dist" && zip -qr9 "$OUT" .)
else (cd "$APP/dist" && python3 -m zipfile -c "$OUT" ./*); fi
echo "$OUT"
