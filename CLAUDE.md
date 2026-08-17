# CLAUDE.md

Guidance for Claude Code working in this repo.

A macOS menu bar app that streams [BFF.fm](https://bff.fm/), San Francisco
community radio. Private repo: `github.com/csmb/menu-bar-frequencies-forever`.

- **Spec:** `docs/superpowers/specs/2026-08-16-menu-bar-frequencies-forever-design.md`
  — the binding authority. Where it and the plan disagree, the spec wins.
- **Plan:** `docs/superpowers/plans/2026-08-16-menu-bar-frequencies-forever.md`
  — how it was built. Contains a few errors the spec does not (see History).

## Build

SwiftPM only, no Xcode project. `BFFCore` holds everything; `BFFMenuBar` is a
one-line executable calling `BFFMenuBarApp.main()`.

```sh
make app      # build/BFF.FM – Menu Bar Frequencies Forever.app
make install  # copies it to /Applications
make dmg      # drag-to-install disk image
make test     # 60 tests
```

Keep the build at **zero warnings** and the suite green. `Makefile` recipes
need tab indentation. The app name contains spaces, so every path built from it
stays quoted; `Makefile` keeps it in `APP`/`DEST` for exactly that reason.

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
slug — and to poll gently. Metadata is fetched once every 30s and only while
playing or while the dropdown is open. All identity and URLs live in
`BFFAPI.swift` so they cannot drift apart.

| What | Where |
|---|---|
| Now playing | `data.bff.fm/api/data/onair/now.json` — all fields optional |
| Stream | `stream.bff.fm/1/mp3.mp3` → **302** to an Icecast CDN; `app_id` is dropped at the redirect |
| Schedule | `data.bff.fm/shows/all.ics` — the only place show names are paired with URLs |

`data.bff.fm/api/data/tracks/now.json` returns `{}`. Ignore it.

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
matches the presenter by name instead.

Soft-404 signature when checking any bff.fm URL: ~4.3KB and a
`Dead Air - Best Frequencies Forever` title. A real page is 40KB+ and titled
after its subject. **Status code alone proves nothing.**

## Testing

The spec scopes unit tests to `NowPlaying` decoding and poll gating; views and
playback are manual verification. Slug rules, the icon, and link composition
are covered because they are pure logic.

Make a test isolate what it claims. "The animation frames differ" passed while
the rock sat perfectly still, because the equalizer bars differ between every
pair — the real test compares the rock's half of the frame alone. Likewise the
clipped-bar test reads rendered pixels, because the arithmetic that produced
the bug would have produced the same wrong assertion.

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
clicking anything.

**Mute before testing playback** (`set volume output muted true`) and restore
the previous setting afterwards. Audio has started unintentionally more than
once.

## Distribution — current state

**Solved.** `make dmg` produces a Developer ID signed, notarized, stapled disk
image that opens on any Mac with no warning. Verified against a *quarantined*
copy, not just a local one — `spctl` on a file you built yourself proves very
little, because the flag Gatekeeper keys off is only set on download. To
re-check after changes:

```sh
xattr -w com.apple.quarantine "0083;0;Safari;" /tmp/copy.dmg
spctl --assess --type open --context context:primary-signature -vv /tmp/copy.dmg
```

Identity: `Developer ID Application: Christopher Bunting (2LKH737S2W)`, G2
sub-CA, expires Aug 2031. Notary credentials are in the keychain under the
profile `menu-bar-frequencies-forever`; override with `NOTARY_PROFILE`.

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

Open, unresolved: no `LICENSE` file, and the repo ships BFF.fm's Cool Rock
artwork, which the station has under no explicit licence. Their rules invite an
introduction at `tech@bff.fm`.

## History worth knowing

The plan contains three defects the spec does not: an `AVPlayer.TimeControlStatus`
case that does not exist, a fallback string the spec contradicts, and a static
icon where the spec asks for a spinner. Treat plan code blocks as drafts.

Layout has been iterated on with the user against browser mockups rather than
guessed. Motion and layout options are easier to settle by publishing an
interactive artifact than by describing them.
