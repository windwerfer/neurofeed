#!/usr/bin/env bash
# macOS universal release artifact (same steps as the `macos` job in .github/workflows/release.yml):
#   dist/neurofeed-<version>-macos-universal.dmg   NeuroFeed.app (arm64 + x86_64, `lipo`) on a
#   drag-to-Applications DMG; runs on Apple Silicon and Intel Macs.
# Same layout as PhotoCraft (packaging/macos/package.sh there): .app bundle, signed inside-out,
# DMG built with `hdiutil makehybrid` + `convert` (no device attach, reliable on CI).
# Usage: scripts/package-macos.sh [--version 1.2.3] [--skip-build]
# Signing: MACOS_SIGN_IDENTITY (default "-" = ad-hoc; Gatekeeper asks the user to allow it
# via right-click > Open). No notarization yet (needs an Apple Developer ID).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="" SKIP_BUILD=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) VERSION="${2#v}"; shift 2 ;;
    --skip-build) SKIP_BUILD=1; shift ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
# Version: --version > $NEUROFEED_VERSION > git tag > Cargo.toml (scripts/version.sh); baked into the binary.
[[ -n "$VERSION" ]] && export NEUROFEED_VERSION="$VERSION"
VERSION="$("$ROOT/scripts/version.sh")"
export NEUROFEED_VERSION="$VERSION"
export MACOSX_DEPLOYMENT_TARGET=11.0 # keep in sync with LSMinimumSystemVersion
IDENTITY="${MACOS_SIGN_IDENTITY:--}"
TARGETS=(aarch64-apple-darwin x86_64-apple-darwin) # rustup target add both
TARGET_DIR="${CARGO_TARGET_DIR:-$ROOT/target}"
if [[ "$SKIP_BUILD" != 1 ]]; then
  for t in "${TARGETS[@]}"; do (cd "$ROOT" && cargo build --release --locked -p neurofeed-egui --target "$t"); done
fi

WORK="$TARGET_DIR/macos-package"; APP="$WORK/NeuroFeed.app"
DMG="$ROOT/dist/neurofeed-$VERSION-macos-universal.dmg"
rm -rf "$WORK"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$ROOT/dist"
BINS=(); for t in "${TARGETS[@]}"; do BINS+=("$TARGET_DIR/$t/release/neurofeed-egui"); done
lipo -create "${BINS[@]}" -output "$APP/Contents/MacOS/NeuroFeed"
lipo -info "$APP/Contents/MacOS/NeuroFeed"
for a in arm64 x86_64; do lipo "$APP/Contents/MacOS/NeuroFeed" -verify_arch "$a"; done
sed -e "s/@VERSION@/$VERSION/g" -e "s/@SHORT_VERSION@/${VERSION%%-*}/g" "$ROOT/packaging/macos/Info.plist.in" >"$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist"
printf 'APPL????' >"$APP/Contents/PkgInfo"
cp "$ROOT/LICENSE.txt" "$ROOT/THIRD_PARTY_NOTICES.md" "$APP/Contents/Resources/"

# Icon: .iconset from the 1024 px master, then iconutil.
SET="$WORK/NeuroFeed.iconset"; mkdir -p "$SET"
for s in 16 32 128 256 512; do
  sips -z $s $s "$ROOT/assets/neurofeed_icon.png" --out "$SET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s * 2)) $((s * 2)) "$ROOT/assets/neurofeed_icon.png" --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o "$APP/Contents/Resources/NeuroFeed.icns"

ts=(--timestamp); [[ "$IDENTITY" = "-" ]] && ts=(--timestamp=none)
codesign --force --sign "$IDENTITY" "${ts[@]}" --options runtime "$APP/Contents/MacOS/NeuroFeed"
codesign --force --sign "$IDENTITY" "${ts[@]}" --options runtime "$APP"
codesign --verify --strict --deep --verbose=2 "$APP"

STAGE="$WORK/dmg"; mkdir -p "$STAGE"
ditto "$APP" "$STAGE/NeuroFeed.app"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG" "$WORK/raw.dmg"
hdiutil makehybrid -hfs -hfs-volume-name "NeuroFeed" -hfs-openfolder "$STAGE" -o "$WORK/raw.dmg" "$STAGE"
hdiutil convert "$WORK/raw.dmg" -format UDZO -imagekey zlib-level=9 -o "$DMG"
codesign --force --sign "$IDENTITY" "${ts[@]}" "$DMG"
codesign --verify --strict --verbose=2 "$DMG"
# Check the binary inside the finished DMG really is universal.
MNT="$(mktemp -d)"; hdiutil attach -nobrowse -readonly -mountpoint "$MNT" "$DMG" >/dev/null
lipo -info "$MNT/NeuroFeed.app/Contents/MacOS/NeuroFeed"; hdiutil detach "$MNT" >/dev/null || true
ls -lh "$DMG"
