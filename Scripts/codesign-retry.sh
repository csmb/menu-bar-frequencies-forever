#!/bin/bash
# Signing with a secure timestamp, retried.
#
# Notarization requires a secure timestamp, which means every signature depends
# on Apple's timestamp service being reachable. It intermittently is not —
# codesign reports "The timestamp service is not available." — and it fails
# late: by the time the disk image is signed, the app has already been through
# notarization, so giving up throws away several minutes of work for a blip
# that is usually over in seconds.
#
# Sourced rather than executed, so both build-app.sh and make-dmg.sh sign the
# same way and cannot drift into producing mismatched signatures.
#
# Usage: sign_with_retry <identity> <target> [extra codesign args...]

sign_with_retry() {
    local identity="$1" target="$2"
    shift 2

    local attempt
    for attempt in 1 2 3 4; do
        if codesign --force --timestamp --sign "$identity" "$@" "$target"; then
            return 0
        fi
        if [ "$attempt" -eq 4 ]; then
            echo "error: codesign failed four times for $target — giving up" >&2
            return 1
        fi
        echo "  signing failed; retrying in $((attempt * 5))s" >&2
        sleep $((attempt * 5))
    done
}
