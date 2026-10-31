#!/usr/bin/env bash
# Flatpak bundle (same steps as the `flatpak` job in .github/workflows/release.yml):
#   dist/neurofeed-<version>-x86_64.flatpak
# Usage: scripts/package-flatpak.sh [--version 1.2.3] [--sources-only]
# Needs: flatpak-builder, org.freedesktop.Sdk//25.08 + rust-stable extension (flathub),
# python3 with aiohttp + tomlkit (flatpak-cargo-generator).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="" SOURCES_ONLY=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) VERSION="${2#v}"; shift 2 ;;
    --sources-only) SOURCES_ONLY=1; shift ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
[[ -n "$VERSION" ]] || VERSION="$(sed -n 's/^version = "\(.*\)"/\1/p' "$ROOT/Cargo.toml" | head -1)"
# Pinned flatpak-builder-tools commit for the generator.
GEN_REV=master
GEN="${TMPDIR:-/tmp}/flatpak-cargo-generator.py"
curl -fsSL -o "$GEN" "https://raw.githubusercontent.com/flatpak/flatpak-builder-tools/$GEN_REV/cargo/flatpak-cargo-generator.py"
python3 "$GEN" "$ROOT/Cargo.lock" -o "$ROOT/flatpak/cargo-sources.json"
# Release entry in the metainfo for this build.
DATE="$(date -u -d "@$(git -C "$ROOT" log -1 --format=%ct)" +%F)"
sed -i -e "s/VERSION_PLACEHOLDER/$VERSION/" -e "s/DATE_PLACEHOLDER/$DATE/" "$ROOT/flatpak/org.windwerfer.neurofeed.metainfo.xml"
[[ "$SOURCES_ONLY" = 1 ]] && exit 0
cd "$ROOT"
flatpak-builder --force-clean --user --install-deps-from=flathub --repo=.flatpak-repo .flatpak-builder/build flatpak/org.windwerfer.neurofeed.yml
mkdir -p dist
flatpak build-bundle .flatpak-repo "dist/neurofeed-$VERSION-x86_64.flatpak" org.windwerfer.neurofeed
ls -lh "dist/neurofeed-$VERSION-x86_64.flatpak"
