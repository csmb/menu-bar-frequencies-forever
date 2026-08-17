# BFF.FM – Menu Bar Frequencies Forever

A tiny macOS menu bar app that streams [BFF.fm](https://bff.fm/) — San
Francisco community radio. The Cool Rock lives in your menu bar: click it for
the current show, the song that's playing, album art, and a play/stop button.
The icon is full color while playing and dimmed while stopped.

## Requirements

- macOS 14 or later
- Xcode (or the command line tools) to build

## Build & install

```sh
make install   # builds the app and copies it to /Applications
```

Other targets: `make app` (build only), `make run` (build and launch),
`make dmg` (drag-to-install disk image), `make test` (unit tests), `make clean`.

## Sharing it with other people

`make dmg` produces `build/BFF.FM – Menu Bar Frequencies Forever.dmg` — the
app beside an `/Applications` shortcut, the layout everyone recognises.

**It will not open cleanly on anyone else's Mac as things stand.** The app is
ad-hoc signed, which is enough for the machine that built it and nothing more:
`spctl --assess` rejects a downloaded copy outright. A friend who opens the DMG
is told the app "cannot be opened because Apple cannot check it for malicious
software". On macOS 15 and later the old Control-click → Open shortcut no
longer clears this; they have to open the app, be refused, then go to **System
Settings → Privacy & Security** and press **Open Anyway**.

Three ways round it, cheapest first:

1. **Have them build it.** `git clone`, then `make install`. Nothing is
   downloaded, so nothing is quarantined and Gatekeeper never gets involved.
   Needs Xcode's command line tools and access to this repo.
2. **Send the DMG anyway** and warn them about the Open Anyway dance. Fine
   among friends who trust where it came from; a bad experience for anyone else.
3. **Sign with a Developer ID certificate and notarize.** The only route that
   opens with no warnings at all. `make dmg` already does the whole chain —
   hardened-runtime signing, notarizing the app, stapling it, then notarizing
   and stapling the disk image, then proving the result with `spctl`. It takes
   that path by itself the moment two things exist, and falls back to ad-hoc
   with a warning until then.

### Turning notarization on

Both steps are one-time, and neither can be scripted from here.

1. **A *Developer ID Application* certificate**, from
   [developer.apple.com](https://developer.apple.com/account/resources/certificates/list)
   → Certificates → `+` → Developer ID Application. It is free under an
   existing paid membership, but only a team's **Account Holder** may create
   one. This is a different certificate from the *Apple Development* and
   *Apple Distribution* ones Xcode and the App Store use — having those does
   not help.
2. **Notarization credentials**, stored once in the keychain:

   ```sh
   xcrun notarytool store-credentials "menu-bar-frequencies-forever" \
       --apple-id <your-apple-id> \
       --team-id <your-team-id> \
       --password <app-specific-password>
   ```

   App-specific passwords come from
   [appleid.apple.com](https://appleid.apple.com) → Sign-In and Security. Set
   `NOTARY_PROFILE` to use a differently named profile.

With both present, `make dmg` produces a disk image that opens on any Mac with
no warning. With the certificate but no credentials it stops and says so,
because a signed-but-unnotarized build is rejected exactly like an ad-hoc one.

Use the in-app "Launch at Login" toggle after installing to /Applications.

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
`app_id=com.bunting.menu-bar-frequencies-forever` — the reverse URI form the rules ask
for — plus a `menu-bar-frequencies-forever/1.0` User-Agent. Both URLs are built in
`Sources/BFFCore/BFFAPI.swift` so the two can't drift apart.

"Do not overwhelm our servers": metadata is polled once every 30 seconds, and
only while the stream is playing or the dropdown is open. An idle app in your
menu bar makes no requests at all.

BFF.fm has not applied an explicit license to its data, so this app only
displays it live and stores nothing.

Cool Rock artwork © [BFF.fm](https://bff.fm/). Not an official BFF.fm app.
