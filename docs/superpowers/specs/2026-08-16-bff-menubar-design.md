# BFF.fm Menu Bar App — Design

**Date:** 2026-08-16
**Status:** Approved

## Overview

A macOS menu bar app that streams BFF.fm (San Francisco community radio) live audio. The menu bar shows BFF.fm's "Cool Rock" mascot icon; clicking it opens a dropdown with the current show, current song, album art, a play/stop button, a launch-at-login toggle, and Quit.

## Goals

- One-click access to the BFF.fm live stream from the menu bar.
- Always-visible play state: the Cool Rock icon is full color while playing, desaturated and dimmed while stopped.
- Dropdown shows show name, presenter, current song (title — artist, album), and album art.
- No Dock icon (`LSUIElement`), no windows — menu bar only.

## Non-Goals

- No show archives, scheduling, notifications, or scrobbling.
- No App Store distribution or notarization; ad-hoc signing for personal use.

## Stack

- Swift 6 / SwiftUI `MenuBarExtra` (`.menuBarExtraStyle(.window)`), AVFoundation for playback.
- Swift Package Manager executable target; no Xcode project files.
- Minimum macOS 14 (machine runs macOS 26).

## External APIs (BFF.fm developer platform, developer.bff.fm)

- **Stream:** `GET https://stream.bff.fm/1/mp3.mp3` — 128 kbps MP3, 44.1 kHz stereo.
- **Metadata:** `GET https://data.bff.fm/api/data/onair/now.json` — single endpoint returning:
  ```json
  {
    "title": "Take Five",
    "artist": "The Dave Brubeck Quartet",
    "album": "Time Out",
    "label": "Columbia",
    "url": "https://bff.fm/now/...",
    "image": "https://a.bff.fm/image/original/...-cover-art.jpg",
    "program": "Luddite Radio",
    "presenter": "the GeeZ'R",
    "program_image": "https://a.bff.fm/image/original/...jpg"
  }
  ```
  All fields are treated as optional when decoding — the API may return show-only data with no track.
- Per BFF.fm's developer rules, both requests send `app_id=bffdotfm-menu-bar` (query parameter) and a custom `User-Agent` (`bffdotfm-menu-bar/<version>`).
- **Icon:** `https://aw.bff.fm/assets/art/coolrock/1b4090e648255af9e8eeede0ab4a9b9e289d2857.svg`, committed to the repo as a bundled resource (not fetched at runtime).

## Architecture

Three units plus the app entry point:

### `NowPlayingService` (ObservableObject)

- Decodes `onair/now.json` into a `NowPlaying` model (all fields optional).
- Polls every 30 seconds **while playing or while the dropdown is open**; fires an immediate fetch when either becomes true. No polling when idle and closed.
- Publishes `nowPlaying: NowPlaying?` and `fetchFailed: Bool` (fetch failure keeps the last known data and sets the flag; the next successful poll clears it).

### `PlayerController` (ObservableObject)

- Wraps `AVPlayer`. On every play it creates a **fresh `AVPlayerItem`** on the stream URL so playback rejoins live rather than resuming a stale buffer; stop discards the item.
- Publishes state: `stopped`, `loading`, `playing`, `failed(message)` — driven by KVO/publisher observation of `timeControlStatus` and item status.

### `MenuView` (SwiftUI)

Dropdown content, top to bottom:
1. Show name + presenter (from `program` / `presenter`).
2. Song: title — artist, album line (hidden if no track data).
3. Album art via `AsyncImage` (`image`, falling back to `program_image`).
4. Play/Stop button reflecting `PlayerController` state (shows a spinner while loading, error text on failure).
5. "Can't reach BFF.fm" note when `fetchFailed` is set.
6. Launch at Login toggle via `SMAppService.mainApp`.
7. Quit button.

### App entry (`BFFMenuBarApp`)

- `@main` SwiftUI `App` with a `MenuBarExtra` whose label is the Cool Rock icon: `NSImage` loaded from the bundled SVG, rendered at menu bar size, `isTemplate = false` (full color). While stopped, a desaturated/dimmed variant (Core Image mono filter + reduced alpha) is shown instead.
- Tracks dropdown visibility and play state to drive `NowPlayingService` polling.

## App Bundle

SwiftPM can't emit a `.app`, so `Scripts/build-app.sh`:
1. `swift build -c release`
2. Assembles `build/BFF.fm.app` — copies the binary, bundle resources, and an `Info.plist` with `LSUIElement = true`, bundle id `com.bunting.bffdotfm-menu-bar`.
3. Generates the `.icns` app icon from the SVG (via `qlmanage`/`sips` + `iconutil`).
4. Ad-hoc codesigns the bundle.

A `Makefile` wraps it: `make app`, `make install` (copies to `/Applications`), `make run`.

## Error Handling

- Metadata fetch failure: keep showing last known info, add the "can't reach" note; next successful poll clears it.
- Stream failure/stall: `PlayerController` moves to `failed`, the button returns to the stopped state with a brief error line, and the icon dims. User retries by clicking play.
- Missing track fields: dropdown degrades gracefully (show-only, or "Live on BFF.fm" if nothing decodes).

## Testing

- `swift test` unit tests: `NowPlaying` decoding (full payload, show-only payload, empty/garbage payload) and poll-gating logic (plays × menu-open combinations).
- Manual verification: build the app, launch it, confirm icon appears, stream plays, metadata matches bff.fm, icon dims when stopped.
