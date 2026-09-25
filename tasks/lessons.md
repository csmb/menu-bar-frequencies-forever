# Lessons

- **2026-08-23 — The "correct-looking" API attachment was the bug.** AirPlay
  routing failed (HomePods checked, audio stayed local) precisely because
  `AVRoutePickerView.player` was set — the macOS-only, forum-documented,
  Apple-unacknowledged failure mode (threads 708248, 744128). The tests I
  wrote for the attachment lifecycle all passed while pinning broken
  behaviour, because they tested our wiring, not the platform's routing.
  For platform-integration features, a working reference implementation
  (Radiola never sets `player`) is worth more than the API's apparent
  contract; when a system control mysteriously no-ops, search the developer
  forums for the exact symptom before adding more wiring.

- **2026-08-23 — Don't drive the popover with synthetic clicks at all.** The
  repo already warned CGEvent clicks were fragile; this session established
  they fail even when done by the book — popover confirmed open by screenshot
  diff, coordinates verified inside it, and the click still dismissed the
  popover without pressing the button under it. Also burned time twice on
  capture regions: screenshot pixel coordinates are 2× the screen-point
  coordinates `screencapture -R` wants, and a region that shows the terminal
  proves nothing about the popover unless the region actually covers the
  popover. The approaches that worked: judge playback by diffing two captures
  of the status-icon region ~0.7s apart (the icon animates only while active),
  and prove stream behaviour with env-gated live tests (`LIVE_RECONNECT=1`)
  instead of any UI automation. Recorded in CLAUDE.md's "Verifying UI changes".
- **2026-08-23 — `lsof` on the app process is not evidence about AVPlayer.**
  Its network activity did not show under the app's pid; absence of a
  connection there says nothing either way. Use the app's own signals.
- **2026-09-24 — Dead clicks in one region: look for what lies over it before
  blaming focus.** The "…" button, then the show and DJ links, ignored clicks.
  I guessed the dropdown was not getting focus (a deprecated activation
  call), which would have killed every control, not just the top row. The
  real cause was a portrait show photo, scaled to fill, overhanging its
  square: clipped from view but still catching clicks for everything above
  it. The shape of the symptom — only the rows above the artwork — was the
  clue, and the cached image's size (480×640 → 43pt of overhang) confirmed
  it. An in-process click harness (`MenuClickTests`: off-screen,
  non-activating panel, `window.sendEvent`) reproduced it and proved the
  fix, where clicking the live popover never could.
