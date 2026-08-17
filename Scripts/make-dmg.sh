#!/bin/bash
# Packages build/BFF.FM – Menu Bar Frequencies Forever.app into a drag-to-install disk image.
#
# When build-app.sh found a Developer ID certificate, this also notarizes and
# staples — both the app and the disk image around it. Stapling the app matters
# on its own: notarizing only the DMG leaves the copy a friend drags into
# /Applications without a ticket of its own, so it needs Apple's server to
# vouch for it and fails on a Mac that happens to be offline.
set -euo pipefail
cd "$(dirname "$0")/.."

Scripts/build-app.sh

APP="build/BFF.FM – Menu Bar Frequencies Forever.app"
DMG="build/BFF.FM – Menu Bar Frequencies Forever.dmg"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
NOTARY_PROFILE="${NOTARY_PROFILE:-menu-bar-frequencies-forever}"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

if codesign -dvv "$APP" 2>&1 | grep -q "Authority=Developer ID Application"; then
    DISTRIBUTABLE=1
else
    DISTRIBUTABLE=0
fi

# A Developer ID signature that has not been notarized is still refused, so
# there is no useful half-way state to ship. Check the credentials before the
# slow part rather than after it.
if [ "$DISTRIBUTABLE" -eq 1 ] &&
   ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    cat >&2 <<SETUP

  error: signed with a Developer ID certificate but no notarization
         credentials are stored, and a signed-but-unnotarized build is
         rejected by Gatekeeper just the same. Store them once with:

           xcrun notarytool store-credentials "$NOTARY_PROFILE" \\
               --apple-id <your-apple-id> \\
               --team-id <your-team-id> \\
               --password <app-specific-password>

         App-specific passwords come from appleid.apple.com > Sign-In and
         Security. Set NOTARY_PROFILE to use a differently named profile.

SETUP
    exit 1
fi

if [ "$DISTRIBUTABLE" -eq 1 ]; then
    echo "Notarizing the app…"
    ditto -c -k --keepParent "$APP" "$STAGE/app.zip"
    xcrun notarytool submit "$STAGE/app.zip" \
        --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$APP"
fi

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

if [ "$DISTRIBUTABLE" -eq 1 ]; then
    echo "Notarizing the disk image…"
    codesign --force --timestamp --sign "$(security find-identity -v -p codesigning \
        | awk -F'"' '/Developer ID Application/ { print $2; exit }')" "$DMG"
    xcrun notarytool submit "$DMG" \
        --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
fi

echo "Built $DMG ($(du -h "$DMG" | cut -f1))"

if [ "$DISTRIBUTABLE" -eq 1 ]; then
    # Prove it rather than assume it. --context matters: without it spctl
    # assesses a disk image against the wrong policy and reports a pass that
    # says nothing about what happens on a download.
    echo
    echo "Gatekeeper verdict:"
    xcrun stapler validate "$APP"
    xcrun stapler validate "$DMG"
    spctl --assess --type execute -vv "$APP"
    spctl --assess --type open --context context:primary-signature -vv "$DMG"
else
    # Ad-hoc signed builds are refused by Gatekeeper on anyone else's Mac, so say
    # so here rather than letting a friend discover it as "damaged".
    cat >&2 <<'WARNING'

  note: this app is ad-hoc signed, not Developer ID signed and notarized.
        Anyone who downloads it will be blocked by Gatekeeper and has to
        allow it by hand in System Settings > Privacy & Security.
        See README, "Sharing it with other people".
WARNING
fi
