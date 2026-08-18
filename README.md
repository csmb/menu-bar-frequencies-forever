# BFF.FM – Menu Bar Frequencies Forever

A tiny macOS menu bar app that streams [BFF.fm](https://bff.fm/). The Cool Rock
lives in your menu bar: click it for the current show, the song that's playing,
album art, a play/stop button, and a link to donate to the station. A second
page holds BFF.fm's own links, a Launch at Login toggle, and Quit. This is not
an official BFF.fm app, it's built using
[BFF.fm's Developer Platform](https://developer.bff.fm/). Cool Rock artwork ©
[BFF.fm](https://bff.fm/).

![The dropdown: the current show, the track playing, album art, and a play/stop
button](docs/screenshots/demo.gif)

## Download

**[Download the latest release](https://github.com/csmb/menu-bar-frequencies-forever/releases/latest)**
— open the DMG and drag the app onto Applications.

Requires macOS 14 or later. It is signed and notarized, so it opens with no
Gatekeeper warning. Use the in-app "Launch at Login" toggle once it's in
`/Applications`.

## Building it yourself

You only need this to change something — the release above is the same build.
It needs macOS 14 or later and Xcode's command line tools.

```sh
make install   # builds the app and copies it to /Applications
```

Other targets: `make app` (build only), `make run` (build and launch),
`make dmg` (drag-to-install disk image), `make release VERSION=1.1` (stamp a
new version, then build the image), `make test` (unit tests), `make clean`.

## How it works

- Streams `https://stream.bff.fm/1/mp3.mp3` (128 kbps MP3) with AVPlayer,
  rejoining the live edge on every play.
- Show + track metadata comes from BFF.fm's public API
  (`data.bff.fm/api/data/onair/now.json`), polled every 30 seconds — and only
  while playing or while the dropdown is open.
- Built with SwiftPM only; `Scripts/build-app.sh` assembles the `.app`.

## License

The code is [MIT licensed](LICENSE). The Cool Rock artwork belongs to BFF.fm
and is not covered by it.
