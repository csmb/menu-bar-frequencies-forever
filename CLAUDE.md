# CLAUDE.md

Guidance for Claude Code working in this repo.

A macOS menu bar app that streams [BFF.fm](https://bff.fm/), San Francisco
community radio. Public repo: `github.com/csmb/menu-bar-frequencies-forever`,
with the notarized DMG attached to each release.

- **Spec:** `docs/superpowers/specs/2026-08-16-menu-bar-frequencies-forever-design.md`
  — the binding authority for anything it and the plan disagree on, *except*
  where it is marked **Superseded**. The shipped app has moved past it in
  several places — not `MenuBarExtra`, no dimmed icon, notarized distribution,
  auto-reconnect, a fuller dropdown — each annotated where it happens.
- **Plan:** `docs/superpowers/plans/2026-08-16-menu-bar-frequencies-forever.md`
  — how it was built. Contains a few errors the spec does not (see History).

## Build

SwiftPM only, no Xcode project. `BFFCore` holds everything; `BFFMenuBar` is a
one-line executable calling `BFFMenuBarApp.main()`.

```sh
make app      # $BUILD_DIR/BFF.FM – Menu Bar Frequencies Forever.app
make install  # copies it to /Applications
make dmg      # drag-to-install disk image, in $BUILD_DIR
make test     # 109 tests, 3 of them env-gated measurements that skip
```

**With Xcode 27, `make test` fails inside this folder**, with the same
"detritus not allowed" error described below: the new build system code-signs
the `.xctest` bundle, and iCloud stamps it. `swift build` and `swift build -c
release` still work in place, so `make app` and `make dmg` are unaffected. Until
the Makefile sends tests elsewhere, run them off iCloud with
`swift test --scratch-path /tmp/menu-bar-frequencies-forever-tests`.

Keep the build at **zero warnings** and the suite green. `Makefile` recipes
need tab indentation. The app name contains spaces, so every path built from it
stays quoted; `Makefile` keeps it in `NAME`/`APP`/`DEST` for exactly that
reason.

**Build output lives outside the repo, under `$BUILD_DIR`** (default
`~/Library/Caches/menu-bar-frequencies-forever`, set in the `Makefile` and
exported to the scripts). This repo is in iCloud Drive, whose file provider
stamps `com.apple.FinderInfo` on the built `.app` and re-adds it within a second
of any strip; codesign refuses to sign or `--strict`-verify a bundle carrying it
("resource fork, Finder information, or similar detritus not allowed"), so the
whole assemble/sign/notarize/staple path — and the DMG — must stay off iCloud.
Signing in place was measured losing the race outright. Override with
`make BUILD_DIR=/somewhere dmg`. Only a command-line override counts: a
`BUILD_DIR` exported in the shell is ignored on purpose, an empty one is
refused, and `make clean` removes only the `.app` and `.dmg`s this project
writes there. It used to `rm -rf` the whole directory, whatever that was.

**Never write `cmd | grep -q` in these scripts.** They run under `set -o
pipefail`, where `grep -q` exits on its first match, the producer dies of
SIGPIPE writing into the closed pipe, and the pipeline reports 141 — so the
test reads *false precisely when it matched*. This shipped once: `make dmg`
silently skipped notarization and printed the ad-hoc warning over a correctly
signed app. Capture first, match in the shell: `out="$(cmd 2>&1 || true)"`,
then `[[ "$out" == *needle* ]]`. Same trap applies to `awk '{…; exit}'` — see
`Scripts/developer-id.sh`, which drains its input on purpose.

## Architecture

`AppDelegate` → `StatusItemController` (AppKit) owns an `NSStatusItem` and an
`NSPopover`; `MenuView` (SwiftUI) is its content. `AppModel` bridges
`PlayerController` (AVPlayer) and `NowPlayingService` (polling).

**Not `MenuBarExtra`, deliberately.** That scene keeps a private notion of
whether its panel is showing and exposes no way to change it, so every route to
dismissing it desynced that state and cost the user a second click. Five
approaches failed — `orderOut`, `performClick`, `close`, a delayed resync, and
`hidesOnDeactivate` (which stopped the panel opening at all, an `.accessory`
app never being "active"). An `NSPopover` with `.transient` behaviour owns its
own presentation, closes itself on an outside click, and anchors under the
button — which also removed ~100 lines of hand-centring.

**The popover keeps one hosting controller for the app's life**, so SwiftUI's
`onAppear` fires *once, ever*. Anything that must happen on each open belongs
in `AppModel.dropdownWillOpen()`, called from `popoverWillShow`. A `@State`
page here silently stopped resetting and the dropdown reopened into settings.

## BFF.fm's APIs

Developer rules: <https://developer.bff.fm/about/developer-rules>. They ask for
`app_id` in **reverse URI form** — hence `com.bunting.menu-bar-frequencies-forever`, not a
slug — and to poll gently. Metadata is fetched once every 30s, backing off
toward 8 minutes while their info service fails, and only while playing or
while the dropdown is open. All identity and URLs live in `BFFAPI.swift` so
they cannot drift apart.

Every request to their data carries the User-Agent and `app_id`, artwork
included: cover art is loaded by `Artwork`, through the same live provider as
now.json. Until 2026-09 it went out through SwiftUI's `AsyncImage`, which can
set neither — so the request made most often was the one they could not
attribute. Show pages, being the website rather than an endpoint, get the
User-Agent only.

The User-Agent's version is the app's, read at runtime from the bundle's
Info.plist — the file `make release` stamps — so a release moves it with
everything else. Set by hand, it still said 1.0 in 1.4. Outside the app bundle
(`swift test`, a bare `swift run`) it says `dev`, because the main bundle there
is some other program's. A test builds a bundle from the real
`Scripts/Info.plist`, so the bundle identifier and `appID` cannot drift apart
— which would quietly send `dev` from the shipped app — without it failing.

| What | Where |
|---|---|
| Now playing | `data.bff.fm/api/data/onair/now.json` — all fields optional |
| Stream | `stream.bff.fm/1/mp3.mp3` → **302** to an Icecast CDN; `app_id` is dropped at the redirect |
| Schedule | `data.bff.fm/shows/all.ics` — the only place show names are paired with URLs |

`data.bff.fm/api/data/tracks/now.json` returns `{}`. Ignore it.

### Being a good guest

The station gets nothing from us but load, so the app is built not to cost them
more than it must. Two rules hold this up, and each has been broken twice:

- **Every URL we did not write goes through `BFFAPI.trusted`.** The schedule
  feed's `URL:` property, the `image`/`program_image` fields, and the
  `/people/` hrefs scraped from a show page are all data, and each ends up
  either fetched by us or opened in the user's browser. Unchecked, anything
  able to alter one of those responses could point every installed copy of this
  app at a URL of its choosing. `trusted` requires https and a `bff.fm` host —
  `hasSuffix(".bff.fm")` plus an exact match, because a bare suffix test
  accepts `notbff.fm`. The host must first be a plain DNS name, `[a-z0-9.-]`
  only, because the suffix test is only as good as the string it runs on:
  `https://[::ffff:203.0.113.7%25x.bff.fm]/` is an IPv6 address whose zone ID
  ends in `.bff.fm`, and the network stack ignores the zone and connects to
  the address. That one passed the check until 2026-09. Credentials in the URL
  are refused too.
- **A user cannot outpace the poll interval by clicking.** Opening the dropdown
  starts polling and polling starts with a fetch, so every click on the menu
  bar icon was a request — a dozen idle open/closes sent a dozen, against a
  documented one per 30s. `NowPlayingService` stamps `lastRequested`
  **synchronously in `fetchNow()`**, not inside the async `fetch()`: stamped in
  the Task, a burst of clicks all read the old value before the first one
  recorded anything, and the throttle looked right while doing nothing. The
  schedule feed has its own `retryFloor` for the same reason, and so does each
  DJ's show-page lookup — which went without one until 2026-09, so a dozen
  opens against a failing show page sent a dozen requests.

A third rule joined them with auto-reconnect: **a drop costs at most six
connection attempts.** The backoff runs 2→32s and then settles into `.failed`
rather than retrying forever; reconnect arms only after playback actually
started, so Play against a down stream still fails within one watchdog. The
budget is per drop, not per press of Play: once playback has held for a minute
(`steadyAfter`) the incident is over and the next drop gets its own retries.
It is never reset on reaching `.playing` alone, which would let a stream that
connects and drops straight away cycle forever. Wake from sleep restarts with
a fresh budget because the network story genuinely changed — but it is not a
press of Play. Whether playback had started survives the sleep, so the rebuild
right after a wake, which is the one most likely to fail while Wi-Fi rejoins,
backs off instead of giving up. Routing wake through `play()` once cleared that
and made the first post-wake failure final. Don't "improve" any of this into an
unbounded retry loop.

`MusicLinks.slug` is safe by construction — it splits on
`CharacterSet.alphanumerics.inverted` and joins what survives, so a slug holds
only letters, marks and digits and nothing that can end a path segment. That
means Unicode ones too, not `[a-z0-9]` as this file once claimed: `Røyksopp`
keeps its `ø` and `坂本龍一` stays as written. They reach the URL as
percent-encoded UTF-8, every byte of which is 0x80 or above, so no track title
can reach outside the path it is interpolated into. Do not "improve" it into
something that preserves punctuation.

The app writes one thing of its own to disk: `streamVolume`, its playback
level. Nothing of BFF.fm's is stored — no metadata, no schedule, no artwork
kept by us — so what was said to the station still holds. `defaults read
com.bunting.menu-bar-frequencies-forever` shows two more keys, both written by
Apple's frameworks rather than us: `AVRoutingControllerIRSessionServiceTokenKey`
(the AirPlay picker) and `NSStatusItem Preferred Position Item-0` (AppKit, where
the icon sits). If it grows beyond those, check whether the new key is theirs
before shipping it. The stream's CDN also sets a one-hour `DASSessionId`
cookie, which AVFoundation keeps in the app's `~/Library/HTTPStorages` jar —
framework-managed, like the HTTP cache below.

Responses do land in `URLSession`'s shared HTTP cache, which is not ours and
obeys their headers: `no-cache, must-revalidate` on the API, `immutable` on
artwork. Leave it alone — turning it off would re-download 185KB covers
repeatedly, which is worse for them, not better.

### Link slugs — the important part

**Music slugs are derivable** (`MusicLinks.swift`): fold accents, lowercase,
drop `the`/`a`/`and`, run the words together. `The Color of Rain` →
`colorofrain`. Checked against 61 name/slug pairs from bff.fm's own markup.

**Show slugs are not.** The schedule feed pairs `Weird Al Jazeera` with
`/shows/a-hairy-home-companion` and `Bitch Talk Podcast` with
`/shows/bitch-talk`. `ShowDirectory` reads `all.ics` once per launch.

**DJ slugs are not, and guessing them fails silently.** bff.fm answers an
unknown `/people/<slug>` with **HTTP 200** and its generic page — a derived
link looks like it worked and goes somewhere wrong. `Space Abuela` is
`/people/erikadelgato`; `Donna Arkee` is `/people/donna`, while
`/people/donnaarkee` is the decoy. `ShowDirectory` reads the show's page and
matches the presenter by name instead — by the name as it reads, after the
page's character references are decoded. bff.fm writes every apostrophe as
`&#039;`; decoding only `&#39;` left each DJ with one in their name unlinked.

Soft-404 signature when checking any bff.fm URL: ~4.3KB and a
`Dead Air - Best Frequencies Forever` title. A real page is 40KB+ and titled
after its subject. **Status code alone proves nothing.**

## Testing

The spec scoped unit tests to `NowPlaying` decoding and poll gating; the suite
has since grown to cover whatever can be driven without the UI: the reconnect
state machine (through `transition(to:)` and an inert fake player), the URL
trust check, schedule and show-page parsing, slugs, the icon's rendered
pixels, and how artwork requests identify us. Views are still verified by
screenshot, and real playback by the env-gated live tests.

Make a test isolate what it claims. "The animation frames differ" passed while
the rock sat perfectly still, because the equalizer bars differ between every
pair — the real test compares the rock's half of the frame alone. Likewise the
clipped-bar test reads rendered pixels, because the arithmetic that produced
the bug would have produced the same wrong assertion.

The fake player is part of that. A bare `AVPlayer()`, told to play, reports
`.waitingToPlayAtSpecifiedRate` — it has no item — which `PlayerController`
reads as a stall, so a reconnect test reached `.reconnecting` on the watchdog
alone, with or without the code it was named for. `ReconnectTests` hands the
controller an `InertPlayer` whose `play()` does nothing.

## SwiftUI/AppKit gotchas already paid for

- `.frame(maxWidth: .infinity)` on a `Button` widens the *frame*; the control
  stays intrinsically sized and centred. Put it on the label.
- `.fixedSize()` propagates up and defeats an ancestor's width constraint. Put
  the full-width content in an `overlay` so it cannot stretch its parent.
- An SF Symbol alone in a `.borderless` button has a ~12×2pt hit area. Give it
  an explicit frame and `contentShape`.
- `Bundle.module` `fatalError`s outside the bundle, so `StatusIcon` tries
  `Bundle.main` first and the app ships `coolrock.svg` in `Contents/Resources`.
  **Verify bundle changes with `.build/` moved aside** — otherwise the SwiftPM
  accessor's absolute fallback path masks the failure.
- The status item is a fixed width. Resizing it on play/stop shoves the menu
  bar around and drags the open popover sideways.
- **`UserDefaults.double(forKey:)` answers 0 for a key nobody has written.**
  Read the volume that way and every fresh install starts silent, presses
  Play, hears nothing and concludes the app is broken. `PlayerController`
  checks `object(forKey:)` for presence and falls back to full; there is a
  test named after that failure.
- **`play()` builds a new `AVPlayer` every time**, to rejoin the live edge —
  and a new player starts at full volume. Anything that must survive a
  stop/play cycle has to be re-applied there, not just set once. Auto-reconnect
  and wake-from-sleep rebuild through the same path with nobody pressing
  anything, so the list of re-applied things is load-bearing: today it is
  exactly the volume, re-applied in `open()`.
- **A live stream can end.** When Icecast or its CDN closes the connection
  cleanly — a source restart, a relay recycling listeners — AVPlayer plays out
  its buffer, posts `didPlayToEndTime` and pauses: no error, no stall.
  `PlayerController` treats that notification as a drop. Unobserved, it left
  the app in `.playing` over silence, never reconnecting. `.paused` on its own
  stays ignored; `stop()` and `fail()` own those transitions.
- **Never set `AVRoutePickerView.player` on macOS.** It is the obvious wiring
  and it shipped here once: the picker's checkboxes toggled and the audio
  never left the Mac (Apple Developer Forums threads 708248 and 744128, no
  acknowledgment from Apple). With `player` left nil the picker routes the
  app's CoreMedia audio as a whole — which is our one AVPlayer, works with
  HomePods, and needs no re-applying across rebuilds. `RoutePickerTests` pins
  `player == nil`; the caveats that come with app-scoped routing are that
  nothing can read or set the route programmatically, and `AVPlayer.volume`
  may not govern AirPlay output.

## Verifying UI changes

Screenshot and measure; do not eyeball. Geometry comes from
`osascript … position/size of menu bar item 1 of menu bar 2`.

**The popover is not an accessibility window.** It cannot be counted with
`count of windows` (that returns 0 while it is plainly visible) and cannot be
clicked via System Events, which targets the frontmost app — attempts land in
whatever is behind it. Coordinate clicks with CGEvent work but are fragile,
because the popover auto-dismisses whenever anything takes focus; several
strayed into the user's browser. Prefer: one bash invocation, no intervening
`osascript`, and a screenshot diff to confirm the popover is open *before*
clicking anything. Even that is not enough to press a button: a CGEvent click
at coordinates verified to be inside the confirmed-open popover has dismissed
it without the button firing. To check playback headless, skip the mouse. The
status icon animates while the player is active, so two icon-region captures
~0.7s apart differ when it is — but active includes connecting and
reconnecting, so a diff proves the player is trying, not that sound is coming
out. The env-gated live tests (`LIVE_RECONNECT=1`, `MEASURE_TIME_TO_AUDIO=1`)
exercise the real stream with no UI at all.

To exercise `PlayerController` end to end without sound and without the
station, point `BFFAPI.stream` — in a scratch copy — at a local Icecast-style
server: `HTTP/1.0 200`, `Content-Type: audio/mpeg`, no Content-Length, paced
at about 16KB/s, then a clean close. Serve silence (`lame -b 128` over a WAV
of zeros) and inject a defaults suite with `streamVolume` 0. AVFoundation
opens two connections at the start, a probe and then the stream. That is how
the stream-end and per-drop reconnect behaviour was verified.

**Mute before testing playback** (`set volume output muted true`) and restore
the previous setting afterwards. Audio has started unintentionally more than
once.

## Distribution — current state

**Solved.** `make dmg` produces a Developer ID signed, notarized, stapled disk
image that opens on any Apple silicon Mac with no warning. It does not open on
an Intel Mac at all: `swift build -c release` builds for the host only, so the
binary is arm64 (`lipo -archs` to check). `--arch arm64 --arch x86_64` builds a
universal one, though Xcode 27 warns that x86_64 is deprecated, and macOS 26
is the last release Intel Macs get. Verified against a *quarantined*
copy, not just a local one — `spctl` on a file you built yourself proves very
little, because the flag Gatekeeper keys off is only set on download. To
re-check after changes:

```sh
xattr -w com.apple.quarantine "0083;0;Safari;" /tmp/copy.dmg
spctl --assess --type open --context context:primary-signature -vv /tmp/copy.dmg
```

Identity: `Developer ID Application: Christopher Bunting (2LKH737S2W)`, G2
sub-CA, expires Aug 2031. Notary credentials live in the keychain under the
profile `menu-bar-frequencies-forever`; override with `NOTARY_PROFILE`. On a
new machine, or after an Apple ID password change revokes app-specific
passwords, store them again with:

```sh
xcrun notarytool store-credentials "menu-bar-frequencies-forever" \
    --apple-id <your-apple-id> --team-id 2LKH737S2W \
    --password <app-specific-password>   # appleid.apple.com > Sign-In and Security
```

`make dmg` prints this itself when the certificate is present and the
credentials are not, so the instruction arrives when it is needed.

`build-app.sh` signs with the Developer ID identity whenever the keychain holds
one — hardened runtime and secure timestamp included, because notarization
rejects a build without them and by then the signature is set — and drops to
ad-hoc otherwise. `make dmg` then notarizes and staples the app, builds the
image, notarizes and staples that too, and verifies with `stapler validate` and
`spctl`. Two Apple-side facts to keep in mind:

- **Stapling the app matters separately from stapling the DMG.** Notarize only
  the image and the copy dragged into `/Applications` carries no ticket, so it
  needs Apple's server to vouch for it and fails on an offline Mac.
- **A Developer ID signature without notarization is rejected exactly like an
  ad-hoc one**, so there is no useful half-way build. `make dmg` checks for
  notary credentials *before* the slow part and stops if they are missing.

`make dmg` still builds ad-hoc when there is no certificate, for local
testing. `make release` does not: it sets `REQUIRE_DISTRIBUTABLE`, so an
ad-hoc build stops with an error instead of ending in a correctly named DMG,
exit 0 and a note — which is what it did until 2026-09. It also refuses a tree
with uncommitted changes, because SwiftPM compiles every source file in this
iCloud-synced folder, committed or not. The version stamp is the one exception:
release writes it, and a re-run after a failed notarization must not trip over
it.

### The disk image window

Icon positions, window size and backdrop live in the image's `.DS_Store`, which
only Finder writes — hence the writable image, the AppleScript, and the
compress-afterwards dance in `make-dmg.sh`. Three things about it cost real
time to establish, all measured rather than assumed:

- **Finder accepts `set background picture` and does not paint it.** No error;
  the live window stays white. It *does* write `backgroundImageAlias` into
  `.DS_Store`, and the backdrop appears when the finished image is mounted.
  Judge this step by mounting the built DMG, never by the window on screen —
  `strings … /.DS_Store | grep backgroundImage` confirms it directly.
- **`bounds` is the window frame, not its content.** The chrome takes 34pt of
  title bar and 26pt of status bar, so a 560×400 frame yields 560×340 of usable
  area. `set statusbar visible to false` is accepted and ignored.
- **Finder draws the backdrop at natural size, anchored top-left.** So an image
  taller than the content crops harmlessly while a shorter one leaves a white
  band. `dmg-background.swift` therefore renders 420pt tall for a 340pt area
  and keeps everything meaningful in the top 340.

- **Pin every view option you care about; `.DS_Store` captures this Mac's
  Finder defaults and ships them to everyone.** Icon preview was left to
  inherit and came out `true`, which made the Applications icon draw correctly
  and then get replaced by a generated preview of the link itself — 13 bytes,
  nothing to render — leaving an empty dotted outline on other machines while
  looking fine here. Read back what shipped with
  `shows icon preview of icon view options of container window`.

The arrow lines up because `dmg-background.swift` and the AppleScript read the
same icon coordinates. Change one and you must change the other.

A blank icon that **flashes correct first** is being overwritten, not failed to
resolve. That distinction was the whole diagnosis: two rebuilds went into the
link type and the filesystem, neither of which was involved.

**Finder writes `.DS_Store` asynchronously, and losing that race ships an
unstyled image with no error at all** — `make dmg` succeeds, notarization
succeeds, and the DMG opens as a plain Finder window. It happened exactly that
way: one build was fine and the next silently had no `.DS_Store`, from
identical code. `make-dmg.sh` now waits for the file and then checks it
contains `backgroundImageAlias`, because the file appears the moment Finder
touches the window, before the backdrop is recorded. Never judge a disk image
by its exit code; mount it.

`Scripts/app-icon.swift` recentres the artwork before `iconutil`, because the
rock sits about 100px nearer the top of its own artboard than the bottom and
macOS 26 composites app icons onto a tile where that shows. Measure it against
the **backdrop colour, not alpha**: qlmanage composites onto opaque white, so
every pixel is alpha 255 and an alpha scan reports the full canvas as content —
a confident no-op crop.

Apple's timestamp service fails intermittently, and it fails late, after
notarization has already run. `Scripts/codesign-retry.sh` retries; both scripts
sign through it so their signatures cannot diverge.

Getting the certificate, if it ever has to be done again:

- **Developer ID Application, not Installer.** They sit next to each other in
  the portal and *Installer* signs `.pkg`s, which this project does not ship.
  That mistake was made once and costs a full round trip.
- **Keychain Access's Certificate Assistant fails** here with "The specified
  item could not be found in the keychain", and the keychain config is fine —
  login is default, unlocked, in the search list. Generate the CSR with
  `openssl req -new -newkey rsa:2048 -nodes` instead and import the key with
  `security import … -T /usr/bin/codesign`, which also spares you the signing
  prompt later. One CSR can be submitted for several certificate types.
- Two team IDs are in play: `2LKH737S2W` (the paid membership, Developer ID and
  Apple Distribution) and `D2G3X47LT7` (Apple Development).
- The App Store Connect keys in `~/.appstoreconnect/private_keys/` both return
  **401** to `notarytool history` — team keys needing `--issuer`, or lacking
  the role. An app-specific password is the simpler route.

The code is MIT licensed. **That covers the code only** — the repo also ships
BFF.fm's Cool Rock artwork, which the station has under no explicit licence and
which is therefore not ours to sublicense. The README says so; keep the two
distinct if the licence is ever revisited, and do not let a tidy-up fold the
artwork into the MIT grant.

Open with the station, introduced by email on 2026-08-17: whether the Cool Rock
may be used at all, whether the name may lean on theirs, and whether reading a
show's page for its `/people/` links is welcome. Their answer may mean changing
the icon, the app name, or `ShowDirectory`.

## History worth knowing

The plan contains three defects the spec does not: an `AVPlayer.TimeControlStatus`
case that does not exist, a fallback string the spec contradicts, and a static
icon where the spec asks for a spinner. Treat plan code blocks as drafts.

**The spec is stale wherever it is annotated Superseded, and it is annotated
wherever it is stale.** The first two departures were `MenuBarExtra`, where the
app uses `NSStatusItem`/`NSPopover`, and a desaturated, dimmed icon while
stopped, where it stays full colour and shows play as motion. Distribution,
reconnect, polling backoff, the dropdown's contents, the app_id and artwork
loading followed. The README described the dimmed behaviour for months after it
stopped being true — prose about the icon is worth checking against
`StatusIcon.swift`, which is short and states its own intent.

Layout has been iterated on with the user against browser mockups rather than
guessed. Motion and layout options are easier to settle by publishing an
interactive artifact than by describing them.
