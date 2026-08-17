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
# layout everyone recognises. The symlink is what gives Applications its own
# folder icon — an alias or a plain folder would not.
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

# Finder looks for a disk image's backdrop in a hidden folder on the image
# itself. One multi-resolution TIFF covers Retina and non-Retina; a plain PNG
# would be resampled and look soft on half the machines this lands on.
mkdir "$STAGE/.background"
swift Scripts/dmg-background.swift "$WORK" >/dev/null
tiffutil -cathidpicheck "$WORK/background.png" "$WORK/background@2x.png" \
    -out "$STAGE/.background/background.tiff" >/dev/null

# Whatever is in STAGE ships, and a stray file here is invisible until someone
# mounts the image and reads it. Exactly two entries belong: the app and the
# symlink you drag it onto. This check exists because app.zip once did not
# announce itself — it only showed up as a DMG that had quietly doubled in size.
UNEXPECTED="$(ls -A "$STAGE" \
    | grep -vxF -e "$(basename "$APP")" -e "Applications" -e ".background" || true)"
if [ -n "$UNEXPECTED" ]; then
    {
        echo "error: unexpected entries staged for the disk image; they would ship:"
        echo "$UNEXPECTED"
    } >&2
    exit 1
fi

VOLUME="BFF.FM – Menu Bar Frequencies Forever $VERSION"

# Window position, icon placement and the backdrop are all stored in the
# image's .DS_Store, and only Finder writes that file. So: build a writable
# image, open it, let Finder record the layout, then compress the result. The
# numbers below must match the constants in dmg-background.swift or the arrow
# will not line up with the icons it points between.
#
# Do not judge this step by the window that appears while it runs. Finder
# accepts `set background picture` without complaint and then does not paint it
# in the live window — it only writes the backgroundImageAlias into .DS_Store,
# and the backdrop appears when the finished image is mounted. Chasing that
# apparent failure costs an afternoon; verify by mounting the built DMG.
#
# The slack is for .DS_Store and Finder's own scratch; a UDRW sized exactly to
# its contents has nowhere to put them. It costs nothing in the end, as the
# UDZO conversion discards the empty space.
SIZE_KB=$(( $(du -sk "$STAGE" | cut -f1) + 20480 ))
rm -f "$WORK/rw.dmg"
hdiutil create \
    -volname "$VOLUME" \
    -srcfolder "$STAGE" \
    -fs HFS+ \
    -format UDRW \
    -size "${SIZE_KB}k" \
    -quiet \
    "$WORK/rw.dmg"

MOUNT="$(hdiutil attach "$WORK/rw.dmg" -readwrite -noverify -noautoopen \
    | grep -o '/Volumes/.*$' | tail -1)"
trap 'hdiutil detach "$MOUNT" -quiet -force 2>/dev/null || true; rm -rf "$STAGE" "$WORK"' EXIT

osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "$VOLUME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        -- {left, top, right, bottom} is the window FRAME, not its content:
        -- measured on this machine, the chrome eats 34pt of title bar and 26pt
        -- of status bar, leaving a 560x340 content area out of a 560x400
        -- frame. dmg-background.swift draws for exactly that, and oversizes the
        -- image vertically so the leftover crops instead of leaving a gap.
        set the bounds of container window to {240, 150, 800, 550}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 100
        set text size of viewOptions to 12
        -- Pin these rather than inheriting this Mac's Finder defaults, which
        -- get baked into the shipped .DS_Store and then travel to everyone
        -- else. Icon preview in particular must be off: with it on, Finder
        -- draws the Applications icon correctly and then replaces it with a
        -- generated preview of the link itself — 13 bytes, nothing to render —
        -- leaving an empty dotted outline. It looked like a broken symlink for
        -- an afternoon; the tell is that the right icon flashes first.
        set shows icon preview of viewOptions to false
        set shows item info of viewOptions to false
        set background picture of viewOptions to file ".background:background.tiff"
        set position of item "$(basename "$APP")" of container window to {150, 160}
        set position of item "Applications" of container window to {410, 160}
        update without registering applications
        delay 1
        close
    end tell
end tell
APPLESCRIPT

# Finder writes .DS_Store asynchronously once the window closes, and detaching
# before it lands produces a perfectly valid disk image with no layout at all:
# no error, no warning, just a plain Finder window on whoever opens it. That
# shipped once. A fixed sleep only moves the race, so wait for the file itself.
for _ in $(seq 1 60); do
    [ -f "$MOUNT/.DS_Store" ] && break
    sleep 0.25
done
sync

if [ ! -f "$MOUNT/.DS_Store" ]; then
    echo "error: Finder never wrote .DS_Store; the image would have no layout" >&2
    exit 1
fi

# Present is not the same as complete — .DS_Store exists the moment Finder
# touches the window, before the backdrop is recorded. Check for the thing that
# actually matters.
LAYOUT="$(strings "$MOUNT/.DS_Store" 2>/dev/null || true)"
case "$LAYOUT" in
    *backgroundImageAlias*) ;;
    *) echo "error: .DS_Store has no background reference; layout did not take" >&2
       exit 1 ;;
esac

hdiutil detach "$MOUNT" -quiet
trap 'rm -rf "$STAGE" "$WORK"' EXIT

rm -f "$DMG"
hdiutil convert "$WORK/rw.dmg" -format UDZO -quiet -o "$DMG"

if [ "$DISTRIBUTABLE" -eq 1 ]; then
    echo "Notarizing the disk image…"
    . Scripts/codesign-retry.sh
    sign_with_retry "$IDENTITY" "$DMG"
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
