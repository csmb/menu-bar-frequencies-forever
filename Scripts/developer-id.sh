#!/bin/bash
# Prints the Developer ID Application identity, or nothing when the keychain
# holds none. build-app.sh signs the app with it and make-dmg.sh signs the disk
# image with it; deriving it in one place is what stops those two drifting into
# signatures the notary service would reject as mismatched.
#
# The awk deliberately does not `exit` on the first match. Both callers run
# under `set -o pipefail`, where an early exit closes the pipe underneath
# `security`, which then dies of SIGPIPE and drags the whole pipeline's status
# to 141 — a failure reported *because* the match succeeded. Draining the input
# and printing at END costs nothing and cannot misfire.
set -euo pipefail

security find-identity -v -p codesigning 2>/dev/null \
    | awk -F'"' '/Developer ID Application/ && !found { id = $2; found = 1 } END { print id }'
