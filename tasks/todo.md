# Auto-reconnect + AirPlay picker

Approved design: reconnect only after playback had reached `.playing` (drops,
not failed first connects); backoff gaps 2/4/8/16/32s, each attempt bounded by
the existing 20s watchdog; give up into the existing `.failed`. Wake from sleep
re-runs `play()` with a fresh budget when playback is active. AirPlay via
`AVRoutePickerView` at the trailing end of the volume row; `PlayerController`
re-points `picker.player` at every rebuilt player.

## Todo

- [x] RED/GREEN: reconnect state machine tests (`ReconnectTests.swift`)
- [x] RED/GREEN: wake-from-sleep tests
- [x] RED/GREEN: route picker attachment tests (`RoutePickerTests.swift`)
- [x] MenuView: `.reconnecting` label, AirPlay button in `volumeRow`
      (`RoutePickerView.swift`)
- [x] `make test` green (91 tests), `make app` zero warnings, signed
- [x] Verification: popover screenshot shows the AirPlay button in the volume
      row; `LIVE_RECONNECT=1` gated test proves play → drop → `.reconnecting`
      → `.playing` against the real stream in ~5s
- [x] AirPlay routing bug found and fixed: `AVRoutePickerView.player` must
      stay nil on macOS (forum threads 708248/744128) — attachment removed,
      picker now routes app-scoped; `RoutePickerTests` pins `player == nil`
- [x] User re-test on HomePods (2026-08-23): routing works with the nil-player
      picker. Minor open question, cosmetic only: whether the volume slider
      governs AirPlay output (forum reports say AVPlayer.volume may not).
- [ ] A real lid-close/reopen wake while playing (unit- and live-tested via
      simulated paths only)

## Review

TDD throughout: 13 new unit tests plus one env-gated live test. The reconnect
logic is one guard in `fail(message:)` plus intent/budget bookkeeping;
`play()` split into user-intent `play()` and rebuild-only `open()`. The wake
observer lives outside `cancellables` because teardown clears those on every
rebuild. The AirPlay picker is pointed at each rebuilt player by the
controller (`attachRoutePicker`), keeping `player` private. UI clicking for
verification failed even done carefully — see lessons.md; icon-animation
diffing and the gated live test replaced it. CLAUDE.md and README updated.
