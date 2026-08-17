# CLAUDE.md

Guidance for Claude Code working in this repo.

A macOS menu bar app that streams [BFF.fm](https://bff.fm/), San Francisco
community radio. Private repo: `github.com/csmb/bffdotfm-menu-bar`.

- **Spec:** `docs/superpowers/specs/2026-08-16-bff-menubar-design.md` — the
  binding authority. Where it and the plan disagree, the spec wins.
- **Plan:** `docs/superpowers/plans/2026-08-16-bff-menubar.md` — how it was
  built. Contains a few errors the spec does not (see History).

## Build

SwiftPM only, no Xcode project. `BFFCore` holds everything; `BFFMenuBar` is a
one-line executable calling `BFFMenuBarApp.main()`.

```sh
make app      # build/BFF.fm.app
make install  # copies it to /Applications
make dmg      # drag-to-install disk image
make test     # 60 tests
```

Keep the build at **zero warnings** and the suite green. `Makefile` recipes
need tab indentation.

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
`app_id` in **reverse URI form** — hence `com.bunting.bffdotfm-menu-bar`, not a
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

Ad-hoc signed, so `spctl --assess` **rejects** it on any other machine. The
next step is a *Developer ID Application* certificate: the account (Team
`2LKH737S2W`) has Apple Development and Apple Distribution certificates, which
are for Xcode and the App Store and cannot sign for outside distribution.
`notarytool` is installed with no stored credentials. `make dmg` warns when the
signature is ad-hoc.

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
