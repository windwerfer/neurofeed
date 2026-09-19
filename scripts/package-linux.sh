#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 <bundle-dir> <tar.gz-out> [appimage-out]"
  echo "  bundle-dir:  Flutter linux release bundle (build/linux/x64/release/bundle)"
  echo "  tar.gz-out:  output path for the deterministic tarball"
  echo "  appimage-out: optional output path for a best-effort AppImage"
  exit 1
}

BUNDLE_DIR="$1"
TARBALL_OUT="$2"
APPIMAGE_OUT="${3:-}"

if [ ! -d "$BUNDLE_DIR" ]; then
  echo "bundle dir not found: $BUNDLE_DIR" >&2
  usage
fi

if [ -n "$TARBALL_OUT" ]; then
  mkdir -p "$(dirname "$TARBALL_OUT")"
  tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner \
      --no-xattrs --no-acls --no-selinux -cf - -C "$BUNDLE_DIR" . \
    | gzip -n > "$TARBALL_OUT"
  echo "tarball: $TARBALL_OUT"
fi

if [ -z "$APPIMAGE_OUT" ]; then
  exit 0
fi

TOOL_DIR=$(mktemp -d)
trap 'rm -rf "$TOOL_DIR"' EXIT

curl -fsSL -o "$TOOL_DIR/appimagetool" \
  "https://github.com/AppImage/appimagetool/releases/download/1.9.1/appimagetool-x86_64.AppImage"
chmod +x "$TOOL_DIR/appimagetool"

pushd "$TOOL_DIR" >/dev/null
"$TOOL_DIR/appimagetool" --appimage-extract >/dev/null 2>&1
APPIMAGETOOL="$TOOL_DIR/squashfs-root/AppRun"
popd >/dev/null

APPDIR="$TOOL_DIR/AppDir"
mkdir -p "$APPDIR"
cp -a "$BUNDLE_DIR/." "$APPDIR/"

cat > "$APPDIR/AppRun" <<'EOF'
#!/bin/sh
exec "$APPDIR"/neurofeed "$@"
EOF
chmod +x "$APPDIR/AppRun"

cat > "$APPDIR/neurofeed.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=NeuroFeed
Exec=neurofeed
Icon=app
Categories=Audio;
Terminal=false
EOF

if [ -f "$BUNDLE_DIR/neurofeed.png" ]; then
  cp "$BUNDLE_DIR/neurofeed.png" "$APPDIR/app.png"
elif [ -f "$(dirname "$0")/../linux/neurofeed.png" ]; then
  cp "$(dirname "$0")/../linux/neurofeed.png" "$APPDIR/app.png"
else
  echo "neurofeed.png not found for AppImage icon" >&2
  exit 1
fi

SOURCE_DATE_EPOCH=0 ARCH=x86_64 "$APPIMAGETOOL" "$APPDIR" "$APPIMAGE_OUT" >/dev/null
echo "appimage: $APPIMAGE_OUT"
