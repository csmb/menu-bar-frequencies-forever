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
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
# Versioned, so a friend can tell two downloads apart and a browser does not
# quietly rename the second one to "… -2.dmg". Info.plist is the single source:
# `make release VERSION=1.1` stamps it there and it reaches the filename, the
# volume name, and the app's own About box from that one place.
DMG="build/BFF.FM – Menu Bar Frequencies Forever $VERSION.dmg"
NOTARY_PROFILE="${NOTARY_PROFILE:-menu-bar-frequencies-forever}"

# STAGE becomes the disk image root, so nothing may be written into it that is
# not meant to ship. The notarization zip goes in WORK instead — putting it in
# STAGE shipped a second copy of the app inside every DMG, doubling its size.
STAGE="$(mktemp -d)"
WORK="$(mktemp -d)"
trap 'rm -rf "$STAGE" "$WORK"' EXIT

IDENTITY="$(Scripts/developer-id.sh)"

# Read what build-app.sh actually produced rather than trusting that it found
# the same certificate this script did.
#
# Capture first, match in the shell. The obvious `codesign … | grep -q` cannot
# be used under `set -o pipefail`: grep -q exits on its first match, codesign
# dies of SIGPIPE writing into the closed pipe, and the pipeline reports 141 —
# so the test reads false precisely when the app *is* signed. That shipped once
# already, silently skipping notarization while printing the ad-hoc warning.
SIGNATURE="$(codesign -dvv "$APP" 2>&1 || true)"
if [[ "$SIGNATURE" == *"Authority=Developer ID Application"* ]]; then
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
    ditto -c -k --keepParent "$APP" "$WORK/app.zip"
    xcrun notarytool submit "$WORK/app.zip" \
        --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$APP"
fi

# A copy of the app beside a shortcut to /Applications is the drag-to-install
# layout everyone recognises.
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

# Whatever is in STAGE ships, and a stray file here is invisible until someone
# mounts the image and reads it. Exactly two entries belong: the app and the
# symlink you drag it onto. This check exists because app.zip once did not
# announce itself — it only showed up as a DMG that had quietly doubled in size.
UNEXPECTED="$(ls -A "$STAGE" | grep -vxF -e "$(basename "$APP")" -e "Applications" || true)"
if [ -n "$UNEXPECTED" ]; then
    {
        echo "error: unexpected entries staged for the disk image; they would ship:"
        echo "$UNEXPECTED"
    } >&2
    exit 1
fi

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
    codesign --force --timestamp --sign "$IDENTITY" "$DMG"
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
