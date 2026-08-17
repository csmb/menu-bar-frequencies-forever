#!/bin/bash
# Assembles build/BFF.FM – Menu Bar Frequencies Forever.app from the SwiftPM release build.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP="build/BFF.FM – Menu Bar Frequencies Forever.app"
BIN=".build/release/BFFMenuBar"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/BFFMenuBar"
# The SVG goes in loose, not as SwiftPM's resource bundle: that bundle's
# generated accessor resolves against Bundle.main.bundleURL (the .app itself)
# and otherwise falls back to an absolute .build/ path, so the app would load
# its icon from the build tree and crash once that tree went away.
cp Sources/BFFCore/Resources/coolrock.svg "$APP/Contents/Resources/coolrock.svg"
cp Scripts/Info.plist "$APP/Contents/Info.plist"

# StatusIcon reads this path via Bundle.main; without it the app falls through
# to Bundle.module, which fatalErrors outside the build tree. Fail loudly here
# rather than at some user's launch.
test -f "$APP/Contents/Resources/coolrock.svg" || {
    echo "error: coolrock.svg missing from app bundle" >&2
    exit 1
}

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

# Signing. A Developer ID Application certificate is the only thing that lets
# this open on someone else's Mac, so use one whenever the keychain has one and
# fall back to ad-hoc — good for this machine and nothing else — when it does
# not. The hardened runtime and a secure timestamp belong here rather than in
# make-dmg.sh: notarization rejects a build without them, and by then the
# signature is already set.
#
# No --deep on the Developer ID path. Apple deprecated it, and this bundle has
# no nested code for it to reach anyway: one Mach-O, an SVG, and an .icns.
IDENTITY="$(security find-identity -v -p codesigning \
    | awk -F'"' '/Developer ID Application/ { print $2; exit }')"

if [ -n "$IDENTITY" ]; then
    codesign --force --timestamp --options runtime --sign "$IDENTITY" "$APP"
    codesign --verify --strict --verbose=1 "$APP"
    echo "Signed with: $IDENTITY"
else
    codesign --force --deep --sign - "$APP"
fi

echo "Built $APP"
