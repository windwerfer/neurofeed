#!/usr/bin/env bash
# Linux x86_64 release artifacts (same steps as the `linux` job in .github/workflows/release.yml):
#   dist/neurofeed-<version>-linux-x86_64.tar.gz   bin/neurofeed + desktop file, icon, metainfo
#   dist/neurofeed-<version>-x86_64.AppImage
# Usage: scripts/package-linux.sh [--version 1.2.3] [--skip-build] [--no-appimage]
# Needs: libasound2-dev libdbus-1-dev pkg-config; the AppImage step downloads appimagetool.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="" SKIP_BUILD=0 APPIMAGE=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) VERSION="${2#v}"; shift 2 ;;
    --skip-build) SKIP_BUILD=1; shift ;;
    --no-appimage) APPIMAGE=0; shift ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
# Version: --version > $NEUROFEED_VERSION > git tag > Cargo.toml (scripts/version.sh); baked into the binary.
[[ -n "$VERSION" ]] && export NEUROFEED_VERSION="$VERSION"
VERSION="$("$ROOT/scripts/version.sh")"
export NEUROFEED_VERSION="$VERSION"
APPIMAGETOOL_VERSION=1.9.0
ID=org.windwerfer.neurofeed
export SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-$(git -C "$ROOT" log -1 --format=%ct)}"
TARGET_DIR="${CARGO_TARGET_DIR:-$ROOT/target}"
[[ "$SKIP_BUILD" = 1 ]] || (cd "$ROOT" && cargo build --release --locked -p neurofeed-egui)

DIST="$ROOT/dist"; WORK="$TARGET_DIR/linux-package"
NAME="neurofeed-$VERSION-linux-x86_64"
rm -rf "$WORK"; mkdir -p "$DIST" "$WORK/$NAME"
stage() { # $1 = prefix dir (usr layout)
  install -Dm755 "$TARGET_DIR/release/neurofeed-egui" "$1/bin/neurofeed"
  install -Dm644 "$ROOT/flatpak/$ID.desktop" "$1/share/applications/$ID.desktop"
  install -Dm644 "$ROOT/flatpak/$ID.png" "$1/share/icons/hicolor/512x512/apps/$ID.png"
  sed -e "s/VERSION_PLACEHOLDER/$VERSION/" -e "s/DATE_PLACEHOLDER/$(date -u -d "@$SOURCE_DATE_EPOCH" +%F)/" \
    "$ROOT/flatpak/$ID.metainfo.xml" | install -Dm644 /dev/stdin "$1/share/metainfo/$ID.metainfo.xml"
}
stage "$WORK/$NAME"
cp "$ROOT/LICENSE.txt" "$ROOT/THIRD_PARTY_NOTICES.md" "$ROOT/README.md" "$WORK/$NAME/"
tar --sort=name --mtime="@$SOURCE_DATE_EPOCH" --owner=0 --group=0 --numeric-owner \
  -C "$WORK" -czf "$DIST/$NAME.tar.gz" "$NAME"

if [[ "$APPIMAGE" = 1 ]]; then
  APPDIR="$WORK/NeuroFeed.AppDir"
  stage "$APPDIR/usr"
  cp "$ROOT/flatpak/$ID.desktop" "$APPDIR/"
  cp "$ROOT/flatpak/$ID.png" "$APPDIR/$ID.png"
  cp "$APPDIR/usr/share/metainfo/$ID.metainfo.xml" "$APPDIR/usr/share/metainfo/$ID.appdata.xml"
  printf '#!/bin/sh\nHERE="$(dirname "$(readlink -f "$0")")"\nexec "$HERE/usr/bin/neurofeed" "$@"\n' >"$APPDIR/AppRun"
  chmod 755 "$APPDIR/AppRun"
  TOOL="$WORK/appimagetool"
  curl -fsSL -o "$TOOL" "https://github.com/AppImage/appimagetool/releases/download/$APPIMAGETOOL_VERSION/appimagetool-x86_64.AppImage"
  chmod +x "$TOOL"
  # appimagetool passes its own mksquashfs timestamps, which conflict with SOURCE_DATE_EPOCH.
  env -u SOURCE_DATE_EPOCH ARCH=x86_64 APPIMAGE_EXTRACT_AND_RUN=1 "$TOOL" --no-appstream "$APPDIR" "$DIST/neurofeed-$VERSION-x86_64.AppImage"
fi
ls -lh "$DIST"/neurofeed-"$VERSION"-*
