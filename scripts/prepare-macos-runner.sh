#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
RUNNER="$ROOT/macos/Runner"
ICONSET="$RUNNER/Assets.xcassets/AppIcon.appiconset"
MASTER="$ROOT/assets/neurofeed_icon.png"

if [ ! -f "$RUNNER/Info.plist" ]; then
  echo "missing $RUNNER/Info.plist (run flutter create --platforms=macos first)" >&2
  exit 1
fi

write_entitlements() {
  dest=$1
  extra=$2
  cat > "$dest" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
${extra}</dict>
</plist>
EOF
}

SANDBOX='	<key>com.apple.security.app-sandbox</key>
	<true/>
	<key>com.apple.security.network.client</key>
	<true/>
	<key>com.apple.security.network.server</key>
	<true/>
	<key>com.apple.security.device.bluetooth</key>
	<true/>
	<key>com.apple.security.files.user-selected.read-write</key>
	<true/>
	<key>com.apple.security.files.bookmarks.app-scope</key>
	<true/>
'

write_entitlements "$RUNNER/Release.entitlements" "$SANDBOX"
write_entitlements "$RUNNER/DebugProfile.entitlements" "$SANDBOX	<key>com.apple.security.cs.allow-jit</key>
	<true/>
"

cp "$ROOT/scripts/macos/MainFlutterWindow.swift" "$RUNNER/MainFlutterWindow.swift"

python3 - "$RUNNER/Info.plist" << 'PY'
import plistlib
import sys

path = sys.argv[1]
with open(path, "rb") as fh:
    data = plistlib.load(fh)

bluetooth = "NeuroFeed uses Bluetooth to find and connect to Muse headsets."
data["NSBluetoothAlwaysUsageDescription"] = bluetooth
data["NSBluetoothPeripheralUsageDescription"] = bluetooth
data["NSLocalNetworkUsageDescription"] = (
    "NeuroFeed uses the local network for Neurosity Crown streams and for LSL and BrainFlow."
)

with open(path, "wb") as fh:
    plistlib.dump(data, fh, fmt=plistlib.FMT_XML, sort_keys=False)
PY

if command -v sips >/dev/null 2>&1 && [ -f "$MASTER" ] && [ -d "$ICONSET" ]; then
  for size in 16 32 64 128 256 512 1024; do
    sips -z "$size" "$size" "$MASTER" --out "$ICONSET/app_icon_${size}.png" >/dev/null
  done
fi
