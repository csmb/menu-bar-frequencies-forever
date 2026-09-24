# Review fixes, round 2 (2026-09-24)

Items 7–10 from the review's "Should fix", artwork identification, the
User-Agent bump, then the docs. One commit per item. Code changes go in
test-first; the Makefile and script changes are verified by running them
against controlled inputs in a scratch clone (a stand-in `security` that lists
no identity, a scratch `BUILD_DIR`) — never a real release or notarization.

## Todo

- [x] 7. DJ-page lookups: a failed lookup waits out `retryFloor` before trying
      again, like the schedule (8a5001c)
- [x] 8. Link text: decode HTML entities properly — `&#039;` (bff.fm's
      apostrophe), `&nbsp;`, numeric references in general (cce1bd1)
- [x] 9. `BUILD_DIR`: ignore one exported in the shell, refuse an empty one;
      `make clean` deletes only what the project writes (afc83ff)
- [x] 10. `make release`: refuse without a Developer ID signature, and from a
      tree with uncommitted changes (8ce64f1)
- [x] Artwork requests carry the User-Agent and `app_id` (replaces
      `AsyncImage`) (8d44617)
- [x] User-Agent bumped to 1.1 (174468d)
- [x] Docs: CLAUDE.md, README, the spec (Superseded notes), script headers,
      app-icon comments, the previous task's review
- [x] Full suite from a clean export of HEAD, zero warnings

## Review

The code changes went in test-first, each new test failing on the old code:

- 7: ten dropdown opens sent ten show-page requests.
- 8: `&#039;`, `&#x…;` and `&nbsp;` were left undecoded.
- Artwork: the request had no User-Agent and no `app_id`. RED here was taken
  against a stand-in that fetched the way `AsyncImage` does, with the request
  caught by a `URLProtocol` inside `URLSession.shared` so the real provider
  runs off the network.

The User-Agent bump has no test by design; one pinning the string could only
fail on a deliberate change.

The Makefile and script changes (9, 10) were verified by running them:
`make -n` for each `BUILD_DIR` case, a real `make clean` in a scratch clone
that left someone else's file alone, and `make release` in scratch clones with
a stand-in `security` (no identity) and a stand-in `tiffutil` so no disk image
was ever mounted. Before the fix, an ad-hoc release and one with an
uncommitted edit both reached image building. After it, each is refused, and a
re-run with only the version stamp uncommitted proceeds. No real release or
notarization was run.

Checked against real data:

- The 38 DJ names on the six cached show pages decode cleanly.
- a.bff.fm serves artwork with `app_id` attached: one request, 200,
  image/jpeg.

The docs now describe what ships: arm64 only, the `make test`-in-iCloud
problem and its workaround, three defaults keys and a CDN cookie, Unicode
slugs, and what the icon diff does and does not prove. The spec has a
Superseded note wherever it is stale, and the build plan is marked historical.

---

# Review fixes: "Fix before the next release" (2026-09-24)

The five release blockers from the full-repo review at 4f97b7f, one commit
each. Test-first: every new test is watched failing on the old code before the
fix goes in, and the full suite is green with zero warnings before each commit.

## Todo

- [x] 1. Stream end: a clean close by the server (AVPlayer's
      `didPlayToEndTime`) is a drop, not an end — reconnect instead of sitting
      in `.playing` over silence (b3991ea)
- [x] 2. Wake: rebuild without clearing `hasPlayedSinceIntent`, so a failed
      first connect after wake (Wi-Fi still rejoining) enters the backoff
      (68c77ca)
- [x] 3. Reconnect budget: a fresh budget per drop once playback has held for a
      minute; a stream that drops again straight away still runs out (cf6fc72)
- [x] 4. ICS: a feed starting with a space or tab no longer indexes an empty
      array (crash) (d378b2e)
- [x] 5. `trusted()`: plain DNS names only and no userinfo — closes the IPv6
      zone-ID bypass (`[::ffff:a.b.c.d%25x.bff.fm]`) (32a215e)
- [x] End-to-end: stream end → reconnect against a local, silent Icecast-style
      server with the real `PlayerController`

## Review

Each fix went in test-first. Every new test was watched failing on the old
code before the fix: `.playing` where `.reconnecting` was due (1), `.failed`
after a wake (2), no retry for a second drop (3), `Index out of range` (4),
and six hostile URLs accepted (5). The two guard tests, a wake during a first
connect (2) and quick re-drops (3), pass on old and new code alike. Each was
checked by planting the over-fix it guards against and watching it fail.
Clean export of 32a215e: 102 tests, 3 env-gated skips, 0 failures; zero
warnings in debug and release.

The fake player in `ReconnectTests` is now inert. A bare `AVPlayer()` told to
play reports waiting-to-play, which the controller read as a stall, so the
first stream-end test passed on the unfixed code. Recorded in CLAUDE.md,
Testing.

End to end, the real `PlayerController` played against a local server serving
~6s of silence per connection, at volume 0. With one retry in the budget and a
3s steady window, three clean closes gave three reconnects in 36s and it never
gave up. That needs both fix 1 and fix 3. The stricter `trusted()` accepts all
143 real URLs in the app's HTTP cache, exactly as the old one did.

Found along the way, not fixed: with Xcode 27, `make test` (`swift test`)
fails inside this iCloud folder, because the new build system code-signs the
`.xctest` bundle and iCloud stamps `com.apple.FinderInfo` on it. `swift build`
and `swift build -c release` still work in place, so `make app`/`make dmg` are
unaffected. Verification here ran with `--scratch-path` outside iCloud.

Still open from below: a real lid-close/reopen wake while playing.

---

# Auto-reconnect + AirPlay picker

Approved design: reconnect only after playback had reached `.playing` (drops,
not failed first connects); backoff gaps 2/4/8/16/32s, each attempt bounded by
the existing 20s watchdog; give up into the existing `.failed`. Wake from sleep
re-runs `play()` with a fresh budget when playback is active. AirPlay via
`AVRoutePickerView` at the trailing end of the volume row; `PlayerController`
re-points `picker.player` at every rebuilt player.

**Superseded:** `picker.player` stays nil — attaching it broke AirPlay on macOS,
as the Todo below records. And since 2026-09-24 wake rebuilds without going
through `play()`, so reconnect stays armed for the first connect after a wake.

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

**Superseded:** there is no `attachRoutePicker`; the picker's `player` stays
nil. Icon diffing proves the player is active, not that sound is playing —
it animates while connecting too (CLAUDE.md, Verifying UI changes).
