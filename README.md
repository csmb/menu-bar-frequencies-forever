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

**It opens cleanly on anyone's Mac.** The app is Developer ID signed with the
hardened runtime, notarized by Apple, and stapled — so a friend downloads it,
drags it across, and it just opens. No warning, no Control-click trick, no trip
through System Settings.

Both the app and the disk image are stapled, which matters more than it sounds:
staple only the image and the copy dragged into `/Applications` carries no
ticket of its own, so it has to ask Apple's server and fails on a Mac that
happens to be offline.

`make dmg` does the whole chain — signing, notarizing, stapling, then proving
it with `stapler validate` and `spctl`. It takes a few minutes, most of it
waiting on Apple.

To check it yourself the way a recipient's Mac would, set the quarantine flag
Gatekeeper actually keys off. Assessing a file you built locally proves very
little, because that flag is only set on download:

```sh
cp "build/BFF.FM – Menu Bar Frequencies Forever.dmg" /tmp/copy.dmg
xattr -w com.apple.quarantine "0083;0;Safari;" /tmp/copy.dmg
spctl --assess --type open --context context:primary-signature -vv /tmp/copy.dmg
# accepted / source=Notarized Developer ID
```

Friends who'd rather build it themselves can `git clone` and `make install` —
nothing is downloaded, so Gatekeeper never gets involved at all.

### Setting notarization up on a new machine

Both steps are one-time, and neither can be scripted from here.

1. **A *Developer ID Application* certificate**, from
   [developer.apple.com](https://developer.apple.com/account/resources/certificates/list)
   → Certificates → `+` → Developer ID Application. It is free under an
   existing paid membership, but only a team's **Account Holder** may create
   one. Take care with the name: *Developer ID **Installer*** sits right next
   to it and signs `.pkg`s, which this project does not ship. Both differ from
   the *Apple Development* and *Apple Distribution* certificates Xcode and the
   App Store use — having those does not help.

   If Keychain Access's Certificate Assistant fails with "The specified item
   could not be found in the keychain", skip it and make the CSR directly:

   ```sh
   openssl req -new -newkey rsa:2048 -nodes -keyout devid.key -out devid.csr \
       -subj "/emailAddress=<you>/CN=<your name>/C=US"
   security import devid.key -k ~/Library/Keychains/login.keychain-db \
       -T /usr/bin/codesign
   ```

   Upload `devid.csr`, then double-click the `.cer` Apple returns — it pairs
   with the imported key. Delete `devid.key` afterwards; the keychain holds the
   working copy, and an unencrypted private key should not linger on disk.
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
