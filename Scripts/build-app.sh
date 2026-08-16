#!/bin/bash
# Assembles build/BFF.fm.app from the SwiftPM release build.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP="build/BFF.fm.app"
BIN=".build/release/BFFMenuBar"
RESOURCE_BUNDLE=".build/release/bffdotfm-menu-bar_BFFCore.bundle"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/BFFMenuBar"
cp -R "$RESOURCE_BUNDLE" "$APP/Contents/Resources/"
cp Scripts/Info.plist "$APP/Contents/Info.plist"

# App icon: rasterize the SVG into an .icns. Best-effort — the app works
# without it, so a qlmanage hiccup must not fail the build.
TMP="$(mktemp -d)"
qlmanage -t -s 1024 -o "$TMP" Sources/BFFCore/Resources/coolrock.svg >/dev/null 2>&1 || true
MASTER="$TMP/coolrock.svg.png"
if [ -f "$MASTER" ]; then
    ICONSET="$TMP/AppIcon.iconset"
    mkdir -p "$ICONSET"
    for s in 16 32 128 256 512; do
        sips -z "$s" "$s" "$MASTER" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
        d=$((s * 2))
        sips -z "$d" "$d" "$MASTER" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
    done
    iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
else
    echo "warning: could not rasterize coolrock.svg; skipping AppIcon.icns" >&2
fi
rm -rf "$TMP"

codesign --force --deep --sign - "$APP"
echo "Built $APP"
