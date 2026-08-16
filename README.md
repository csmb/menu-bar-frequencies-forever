# BFF.fm Menu Bar

A tiny macOS menu bar app that streams [BFF.fm](https://bff.fm/) — San
Francisco community radio. The Cool Rock lives in your menu bar: click it for
the current show, the song that's playing, album art, and a play/stop button.
The icon is full color while playing and dimmed while stopped.

## Requirements

- macOS 14 or later
- Xcode (or the command line tools) to build

## Build & install

```sh
make install   # builds build/BFF.fm.app and copies it to /Applications
```

Other targets: `make app` (build only), `make run` (build and launch),
`make test` (unit tests), `make clean`.

The app is ad-hoc signed for personal use. Use the in-app "Launch at Login"
toggle after installing to /Applications.

## How it works

- Streams `https://stream.bff.fm/1/mp3.mp3` (128 kbps MP3) with AVPlayer,
  rejoining the live edge on every play.
- Show + track metadata comes from BFF.fm's public API
  (`data.bff.fm/api/data/onair/now.json`), polled every 30 seconds — and only
  while playing or while the dropdown is open.
- Built with SwiftPM only; `Scripts/build-app.sh` assembles the `.app`.

## Playing by BFF.fm's rules

Per BFF.fm's [developer rules](https://developer.bff.fm/about/developer-rules),
every request to the API and the stream carries
`app_id=com.bunting.bffdotfm-menu-bar` — the reverse URI form the rules ask
for — plus a `bffdotfm-menu-bar/1.0` User-Agent. Both URLs are built in
`Sources/BFFCore/BFFAPI.swift` so the two can't drift apart.

"Do not overwhelm our servers": metadata is polled once every 30 seconds, and
only while the stream is playing or the dropdown is open. An idle app in your
menu bar makes no requests at all.

BFF.fm has not applied an explicit license to its data, so this app only
displays it live and stores nothing.

Cool Rock artwork © [BFF.fm](https://bff.fm/). Not an official BFF.fm app.
