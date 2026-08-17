#!/bin/bash
# Packages build/BFF.FM – Menu Bar Frequencies Forever.app into a drag-to-install disk image.
set -euo pipefail
cd "$(dirname "$0")/.."

Scripts/build-app.sh

APP="build/BFF.FM – Menu Bar Frequencies Forever.app"
DMG="build/BFF.FM – Menu Bar Frequencies Forever.dmg"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

# A copy of the app beside a shortcut to /Applications is the drag-to-install
# layout everyone recognises.
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
hdiutil create \
    -volname "BFF.FM – Menu Bar Frequencies Forever $VERSION" \
    -srcfolder "$STAGE" \
    -fs HFS+ \
    -format UDZO \
    -quiet \
    "$DMG"

echo "Built $DMG ($(du -h "$DMG" | cut -f1))"

# Ad-hoc signed builds are refused by Gatekeeper on anyone else's Mac, so say
# so here rather than letting a friend discover it as "damaged".
if ! codesign -dvv "$APP" 2>&1 | grep -q "Authority=Developer ID Application"; then
    cat >&2 <<'WARNING'

  note: this app is ad-hoc signed, not Developer ID signed and notarized.
        Anyone who downloads it will be blocked by Gatekeeper and has to
        allow it by hand in System Settings > Privacy & Security.
        See README, "Sharing it with other people".
WARNING
fi
