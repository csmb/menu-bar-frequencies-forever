# BFF.fm Menu Bar App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A macOS menu bar app that streams BFF.fm live audio, with a dropdown showing the current show, current song, and album art.

**Architecture:** A SwiftPM package with a `BFFCore` library (model, polling service, player, icon, views), a thin `BFFMenuBar` executable that calls `BFFMenuBarApp.main()`, and a shell script that assembles the `.app` bundle. `NowPlayingService` polls one JSON endpoint; `PlayerController` wraps `AVPlayer`; SwiftUI `MenuBarExtra` renders the dropdown.

**Tech Stack:** Swift 5.10 tools / SwiftUI `MenuBarExtra` / AVFoundation / Combine / ServiceManagement / XCTest. No Xcode project files — `swift build`, `swift test`, and shell scripts only.

**Spec:** `docs/superpowers/specs/2026-08-16-bff-menubar-design.md`

## Global Constraints

- Minimum macOS: **14.0** (`platforms: [.macOS(.v14)]`, `LSMinimumSystemVersion 14.0`).
- Swift tools version: **5.10** (Swift 5 language mode — avoids strict-concurrency churn).
- Every request to a BFF.fm service sends `app_id=bffdotfm-menu-bar` (query param) and User-Agent `bffdotfm-menu-bar/1.0`.
- No third-party dependencies. No Xcode project files.
- Commits go directly to `main`. **Never add a `Co-Authored-By` line or any co-author to commit messages.**
- Bundle id: `com.bunting.bffdotfm-menu-bar`. App bundle name: `BFF.fm.app`.
- The Makefile uses **tab** indentation for recipes (make requirement).

---

### Task 1: Package scaffold + `NowPlaying` model

**Files:**
- Create: `Package.swift`
- Create: `.gitignore`
- Create: `Sources/BFFCore/NowPlaying.swift`
- Create: `Sources/BFFCore/Resources/coolrock.svg` (downloaded)
- Create: `Sources/BFFMenuBar/main.swift` (placeholder)
- Test: `Tests/BFFCoreTests/NowPlayingTests.swift`

**Interfaces:**
- Consumes: nothing (first task).
- Produces: `struct NowPlaying: Decodable, Equatable` with optional `String` properties `title`, `artist`, `album`, `label`, `url`, `image`, `program`, `presenter`, `programImage` (JSON key `program_image`); computed `var songLine: String?` ("Title — Artist" em-dash join, either half alone if the other is nil, nil if both nil); computed `var artworkURL: URL?` (`image` preferred, falling back to `programImage`, nil if neither parses).

- [ ] **Step 1: Create the package scaffold**

Create `Package.swift`:

```swift
// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "bffdotfm-menu-bar",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "BFFCore",
            resources: [.copy("Resources/coolrock.svg")]
        ),
        .executableTarget(
            name: "BFFMenuBar",
            dependencies: ["BFFCore"]
        ),
        .testTarget(
            name: "BFFCoreTests",
            dependencies: ["BFFCore"]
        ),
    ]
)
```

Create `.gitignore`:

```
.build/
build/
.DS_Store
```

Create `Sources/BFFMenuBar/main.swift` (real entry point arrives in Task 5):

```swift
// Entry point is wired up once BFFMenuBarApp exists (Task 5).
```

- [ ] **Step 2: Download the Cool Rock SVG**

Run (note `--compressed` — the server gzips the SVG and plain curl saves raw gzip bytes):

```bash
mkdir -p Sources/BFFCore/Resources
curl -s --compressed -o Sources/BFFCore/Resources/coolrock.svg \
  'https://aw.bff.fm/assets/art/coolrock/1b4090e648255af9e8eeede0ab4a9b9e289d2857.svg'
file Sources/BFFCore/Resources/coolrock.svg
```

Expected: `SVG Scalable Vector Graphics image`. If it says `gzip compressed data`, rename to `.gz`, `gunzip` it, and move it back.

- [ ] **Step 3: Write the failing model tests**

Create `Tests/BFFCoreTests/NowPlayingTests.swift`:

```swift
import XCTest
@testable import BFFCore

final class NowPlayingTests: XCTestCase {
    private let fullPayload = Data("""
    {"title":"Take Five","artist":"The Dave Brubeck Quartet","album":"Time Out",\
    "label":"Columbia","url":"https:\\/\\/bff.fm\\/now\\/20260816122123",\
    "image":"https:\\/\\/a.bff.fm\\/image\\/original\\/cover-art.jpg",\
    "program":"Luddite Radio","presenter":"the GeeZ'R",\
    "program_image":"https:\\/\\/a.bff.fm\\/image\\/original\\/luddide-high.jpg"}
    """.utf8)

    private let showOnlyPayload = Data("""
    {"program":"Luddite Radio","presenter":"the GeeZ'R",\
    "program_image":"https:\\/\\/a.bff.fm\\/image\\/original\\/luddide-high.jpg"}
    """.utf8)

    func testDecodesFullPayload() throws {
        let np = try JSONDecoder().decode(NowPlaying.self, from: fullPayload)
        XCTAssertEqual(np.title, "Take Five")
        XCTAssertEqual(np.artist, "The Dave Brubeck Quartet")
        XCTAssertEqual(np.album, "Time Out")
        XCTAssertEqual(np.label, "Columbia")
        XCTAssertEqual(np.program, "Luddite Radio")
        XCTAssertEqual(np.presenter, "the GeeZ'R")
        XCTAssertEqual(np.programImage, "https://a.bff.fm/image/original/luddide-high.jpg")
    }

    func testDecodesShowOnlyPayload() throws {
        let np = try JSONDecoder().decode(NowPlaying.self, from: showOnlyPayload)
        XCTAssertNil(np.title)
        XCTAssertNil(np.artist)
        XCTAssertEqual(np.program, "Luddite Radio")
    }

    func testDecodesEmptyObject() throws {
        let np = try JSONDecoder().decode(NowPlaying.self, from: Data("{}".utf8))
        XCTAssertNil(np.title)
        XCTAssertNil(np.program)
    }

    func testGarbageFailsToDecode() {
        XCTAssertThrowsError(try JSONDecoder().decode(NowPlaying.self, from: Data("<html>".utf8)))
    }

    func testSongLineJoinsTitleAndArtist() throws {
        let np = try JSONDecoder().decode(NowPlaying.self, from: fullPayload)
        XCTAssertEqual(np.songLine, "Take Five — The Dave Brubeck Quartet")
    }

    func testSongLineWithTitleOnly() throws {
        let np = try JSONDecoder().decode(NowPlaying.self, from: Data(#"{"title":"Take Five"}"#.utf8))
        XCTAssertEqual(np.songLine, "Take Five")
    }

    func testSongLineNilWhenNoTrack() throws {
        let np = try JSONDecoder().decode(NowPlaying.self, from: showOnlyPayload)
        XCTAssertNil(np.songLine)
    }

    func testArtworkPrefersTrackImage() throws {
        let np = try JSONDecoder().decode(NowPlaying.self, from: fullPayload)
        XCTAssertEqual(np.artworkURL, URL(string: "https://a.bff.fm/image/original/cover-art.jpg"))
    }

    func testArtworkFallsBackToProgramImage() throws {
        let np = try JSONDecoder().decode(NowPlaying.self, from: showOnlyPayload)
        XCTAssertEqual(np.artworkURL, URL(string: "https://a.bff.fm/image/original/luddide-high.jpg"))
    }

    func testArtworkNilWhenNoImages() throws {
        let np = try JSONDecoder().decode(NowPlaying.self, from: Data("{}".utf8))
        XCTAssertNil(np.artworkURL)
    }
}
```

- [ ] **Step 4: Run tests to verify they fail**

Run: `swift test 2>&1 | tail -20`
Expected: build FAILURE with "cannot find 'NowPlaying' in scope" (or similar).

- [ ] **Step 5: Implement the model**

Create `Sources/BFFCore/NowPlaying.swift`:

```swift
import Foundation

/// One record from https://data.bff.fm/api/data/onair/now.json.
/// The API returns track + show data when a track is logged, or show-only
/// data otherwise — every field is optional.
struct NowPlaying: Decodable, Equatable {
    var title: String?
    var artist: String?
    var album: String?
    var label: String?
    var url: String?
    var image: String?
    var program: String?
    var presenter: String?
    var programImage: String?

    enum CodingKeys: String, CodingKey {
        case title, artist, album, label, url, image, program, presenter
        case programImage = "program_image"
    }

    var songLine: String? {
        switch (title, artist) {
        case let (t?, a?): return "\(t) — \(a)"
        case let (t?, nil): return t
        case let (nil, a?): return a
        default: return nil
        }
    }

    var artworkURL: URL? {
        if let image, let parsed = URL(string: image) { return parsed }
        if let programImage, let parsed = URL(string: programImage) { return parsed }
        return nil
    }
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `swift test 2>&1 | tail -5`
Expected: all tests PASS.

- [ ] **Step 7: Commit**

```bash
git add Package.swift .gitignore Sources Tests
git commit -m "Scaffold SwiftPM package and add NowPlaying model"
```

---

### Task 2: `NowPlayingService` (polling + fetch)

**Files:**
- Create: `Sources/BFFCore/NowPlayingService.swift`
- Test: `Tests/BFFCoreTests/NowPlayingServiceTests.swift`

**Interfaces:**
- Consumes: `NowPlaying` from Task 1.
- Produces: `typealias DataProvider = @Sendable (URL) async throws -> (Data, URLResponse)`; `@MainActor final class NowPlayingService: ObservableObject` with `init(provider: @escaping DataProvider = NowPlayingService.liveProvider)`, published read-only `nowPlaying: NowPlaying?` and `fetchFailed: Bool`, methods `setPlaying(_ playing: Bool)`, `setMenuOpen(_ open: Bool)`, `fetchNow()`, `func fetch() async`, computed `isPolling: Bool`, statics `endpoint: URL`, `userAgent: String`, `pollInterval: TimeInterval`.

- [ ] **Step 1: Write the failing service tests**

Create `Tests/BFFCoreTests/NowPlayingServiceTests.swift`:

```swift
import XCTest
@testable import BFFCore

@MainActor
final class NowPlayingServiceTests: XCTestCase {
    /// Mutable result holder so one service can succeed, then fail, then recover.
    private final class ProviderBox: @unchecked Sendable {
        var result: Result<(Data, URLResponse), Error>
        init(_ result: Result<(Data, URLResponse), Error>) { self.result = result }
    }

    private let payload = Data("""
    {"title":"Take Five","artist":"The Dave Brubeck Quartet","program":"Luddite Radio"}
    """.utf8)

    private func response(status: Int) -> URLResponse {
        HTTPURLResponse(url: NowPlayingService.endpoint, statusCode: status,
                        httpVersion: nil, headerFields: nil)!
    }

    private func makeService(_ box: ProviderBox) -> NowPlayingService {
        NowPlayingService(provider: { _ in try box.result.get() })
    }

    private func okBox() -> ProviderBox {
        ProviderBox(.success((payload, response(status: 200))))
    }

    // MARK: Poll gating

    func testPollingStartsWhenPlaying() {
        let service = makeService(okBox())
        service.setPlaying(true)
        XCTAssertTrue(service.isPolling)
    }

    func testPollingStartsWhenMenuOpens() {
        let service = makeService(okBox())
        service.setMenuOpen(true)
        XCTAssertTrue(service.isPolling)
    }

    func testNoPollingWhenIdleAndClosed() {
        let service = makeService(okBox())
        XCTAssertFalse(service.isPolling)
        service.setPlaying(true)
        service.setPlaying(false)
        XCTAssertFalse(service.isPolling)
    }

    func testPollingContinuesWhileEitherIsActive() {
        let service = makeService(okBox())
        service.setPlaying(true)
        service.setMenuOpen(true)
        service.setPlaying(false)
        XCTAssertTrue(service.isPolling)
        service.setMenuOpen(false)
        XCTAssertFalse(service.isPolling)
    }

    // MARK: Fetch behavior

    func testFetchSuccessUpdatesNowPlaying() async {
        let service = makeService(okBox())
        await service.fetch()
        XCTAssertEqual(service.nowPlaying?.title, "Take Five")
        XCTAssertEqual(service.nowPlaying?.program, "Luddite Radio")
        XCTAssertFalse(service.fetchFailed)
    }

    func testFetchErrorKeepsLastDataAndSetsFlag() async {
        let box = okBox()
        let service = makeService(box)
        await service.fetch()
        box.result = .failure(URLError(.notConnectedToInternet))
        await service.fetch()
        XCTAssertTrue(service.fetchFailed)
        XCTAssertEqual(service.nowPlaying?.title, "Take Five")
    }

    func testFetchRecoveryClearsFlag() async {
        let box = okBox()
        let service = makeService(box)
        box.result = .failure(URLError(.timedOut))
        await service.fetch()
        XCTAssertTrue(service.fetchFailed)
        box.result = .success((payload, response(status: 200)))
        await service.fetch()
        XCTAssertFalse(service.fetchFailed)
    }

    func testNon200SetsFlag() async {
        let box = ProviderBox(.success((payload, response(status: 500))))
        let service = makeService(box)
        await service.fetch()
        XCTAssertTrue(service.fetchFailed)
        XCTAssertNil(service.nowPlaying)
    }

    func testGarbageBodySetsFlag() async {
        let box = ProviderBox(.success((Data("<html>".utf8), response(status: 200))))
        let service = makeService(box)
        await service.fetch()
        XCTAssertTrue(service.fetchFailed)
    }

    // MARK: BFF.fm identification rules

    func testEndpointCarriesAppID() {
        XCTAssertEqual(NowPlayingService.endpoint.query, "app_id=bffdotfm-menu-bar")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test 2>&1 | tail -20`
Expected: build FAILURE with "cannot find 'NowPlayingService' in scope".

- [ ] **Step 3: Implement the service**

Create `Sources/BFFCore/NowPlayingService.swift`:

```swift
import Foundation

typealias DataProvider = @Sendable (URL) async throws -> (Data, URLResponse)

/// Fetches BFF.fm's unified now-playing metadata and polls it every
/// `pollInterval` seconds — but only while the stream is playing or the
/// dropdown is open, so an idle app makes zero requests.
@MainActor
final class NowPlayingService: ObservableObject {
    static let appID = "bffdotfm-menu-bar"
    static let userAgent = "bffdotfm-menu-bar/1.0"
    static let endpoint = URL(string: "https://data.bff.fm/api/data/onair/now.json?app_id=\(appID)")!
    static let pollInterval: TimeInterval = 30

    @Published private(set) var nowPlaying: NowPlaying?
    @Published private(set) var fetchFailed = false

    private let provider: DataProvider
    private var timer: Timer?
    private var isPlaying = false
    private var menuOpen = false

    var isPolling: Bool { timer != nil }

    init(provider: @escaping DataProvider = NowPlayingService.liveProvider) {
        self.provider = provider
    }

    deinit { timer?.invalidate() }

    static let liveProvider: DataProvider = { url in
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return try await URLSession.shared.data(for: request)
    }

    func setPlaying(_ playing: Bool) {
        isPlaying = playing
        refreshGate()
    }

    func setMenuOpen(_ open: Bool) {
        menuOpen = open
        refreshGate()
    }

    func fetchNow() {
        Task { await self.fetch() }
    }

    func fetch() async {
        do {
            let (data, response) = try await provider(Self.endpoint)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                throw URLError(.badServerResponse)
            }
            nowPlaying = try JSONDecoder().decode(NowPlaying.self, from: data)
            fetchFailed = false
        } catch {
            fetchFailed = true
        }
    }

    private func refreshGate() {
        let shouldPoll = isPlaying || menuOpen
        if shouldPoll, timer == nil {
            fetchNow()
            let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.fetchNow() }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        } else if !shouldPoll {
            timer?.invalidate()
            timer = nil
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test 2>&1 | tail -5`
Expected: all tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/BFFCore/NowPlayingService.swift Tests/BFFCoreTests/NowPlayingServiceTests.swift
git commit -m "Add NowPlayingService with gated 30s polling"
```

---

### Task 3: `PlayerController` (AVPlayer wrapper)

Per the spec, playback has no unit tests (it needs a live network stream); the deliverable is verified by `swift build` here and by launching the app in Task 6.

**Files:**
- Create: `Sources/BFFCore/PlayerController.swift`

**Interfaces:**
- Consumes: `NowPlayingService.userAgent` from Task 2 (sent as the stream's User-Agent).
- Produces: `@MainActor final class PlayerController: ObservableObject` with nested `enum State: Equatable { case stopped, loading, playing, failed(String) }` exposing `var isActive: Bool` (true for `.loading`/`.playing`); published read-only `state: State`; methods `play()`, `stop()`, `toggle()`; static `streamURL: URL`.

- [ ] **Step 1: Implement the controller**

Create `Sources/BFFCore/PlayerController.swift`:

```swift
import AVFoundation
import Combine
import Foundation

/// Wraps AVPlayer on the BFF.fm live MP3 stream. Every play() builds a fresh
/// AVPlayerItem so playback rejoins the live edge instead of resuming a stale
/// buffer; stop() discards the player entirely.
@MainActor
final class PlayerController: ObservableObject {
    enum State: Equatable {
        case stopped
        case loading
        case playing
        case failed(String)

        var isActive: Bool { self == .loading || self == .playing }
    }

    static let streamURL = URL(string: "https://stream.bff.fm/1/mp3.mp3?app_id=bffdotfm-menu-bar")!

    @Published private(set) var state: State = .stopped

    private var player: AVPlayer?
    private var cancellables: Set<AnyCancellable> = []

    func toggle() {
        state.isActive ? stop() : play()
    }

    func play() {
        teardown()
        let asset = AVURLAsset(url: Self.streamURL,
                               options: [AVURLAssetHTTPUserAgentKey: NowPlayingService.userAgent])
        let item = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: item)
        self.player = player
        state = .loading

        player.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self, self.player === player else { return }
                switch status {
                case .playing:
                    self.state = .playing
                case .waitingToPlayAtRateOrBuffering:
                    self.state = .loading
                case .paused:
                    break // stop()/fail() own their state transitions
                @unknown default:
                    break
                }
            }
            .store(in: &cancellables)

        item.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self, self.player === player else { return }
                if status == .failed {
                    self.fail(item.error)
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default
            .publisher(for: AVPlayerItem.failedToPlayToEndTimeNotification, object: item)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.player === player else { return }
                self.fail(item.error)
            }
            .store(in: &cancellables)

        player.play()
    }

    func stop() {
        teardown()
        state = .stopped
    }

    private func fail(_ error: Error?) {
        teardown()
        state = .failed(error?.localizedDescription ?? "Stream failed")
    }

    private func teardown() {
        cancellables.removeAll()
        player?.pause()
        player = nil
    }
}
```

- [ ] **Step 2: Verify it builds and existing tests still pass**

Run: `swift test 2>&1 | tail -5`
Expected: build succeeds, all existing tests PASS.

- [ ] **Step 3: Commit**

```bash
git add Sources/BFFCore/PlayerController.swift
git commit -m "Add PlayerController wrapping AVPlayer on the live stream"
```

---

### Task 4: `StatusIcon` (Cool Rock, color + dimmed)

**Files:**
- Create: `Sources/BFFCore/StatusIcon.swift`
- Test: `Tests/BFFCoreTests/StatusIconTests.swift`

**Interfaces:**
- Consumes: the bundled `coolrock.svg` resource from Task 1 (via `Bundle.module`).
- Produces: `enum StatusIcon` with `static let pointSize: NSSize` (20×20), `static let active: NSImage`, `static let inactive: NSImage`, `static func image(active: Bool) -> NSImage`.

- [ ] **Step 1: Write the failing smoke tests**

Create `Tests/BFFCoreTests/StatusIconTests.swift`:

```swift
import XCTest
@testable import BFFCore

final class StatusIconTests: XCTestCase {
    func testIconsRenderAtMenuBarSize() {
        XCTAssertEqual(StatusIcon.active.size, StatusIcon.pointSize)
        XCTAssertEqual(StatusIcon.inactive.size, StatusIcon.pointSize)
    }

    func testActiveAndInactiveAreDistinctNonTemplateImages() {
        XCTAssertFalse(StatusIcon.active === StatusIcon.inactive)
        XCTAssertFalse(StatusIcon.active.isTemplate)
        XCTAssertFalse(StatusIcon.inactive.isTemplate)
    }

    func testImageSelectionFollowsPlaybackState() {
        XCTAssertTrue(StatusIcon.image(active: true) === StatusIcon.active)
        XCTAssertTrue(StatusIcon.image(active: false) === StatusIcon.inactive)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test 2>&1 | tail -20`
Expected: build FAILURE with "cannot find 'StatusIcon' in scope".

- [ ] **Step 3: Implement the icon**

Create `Sources/BFFCore/StatusIcon.swift`:

```swift
import AppKit
import CoreImage

/// The Cool Rock menu bar icon: full color while playing, desaturated and
/// dimmed while stopped. Rendered from the bundled SVG so it stays sharp on
/// Retina displays; never a template image (we want BFF.fm's colors).
enum StatusIcon {
    static let pointSize = NSSize(width: 20, height: 20)

    static let active: NSImage = renderBase()
    static let inactive: NSImage = renderDimmed()

    static func image(active isActive: Bool) -> NSImage {
        isActive ? active : inactive
    }

    private static func loadSVG() -> NSImage? {
        guard let url = Bundle.module.url(forResource: "coolrock", withExtension: "svg") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }

    private static func renderBase() -> NSImage {
        guard let svg = loadSVG() else { return fallback() }
        let image = NSImage(size: pointSize, flipped: false) { rect in
            svg.draw(in: rect)
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func renderDimmed() -> NSImage {
        guard let svg = loadSVG() else { return fallback() }
        // Rasterize at 2x, drop saturation to zero, then draw at reduced alpha.
        let pixels = 40
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: rep) else {
            return renderBase()
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        svg.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()

        guard let cgImage = rep.cgImage else { return renderBase() }
        let gray = CIImage(cgImage: cgImage)
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0.0])
        guard let grayCG = CIContext().createCGImage(gray, from: gray.extent) else {
            return renderBase()
        }
        let grayImage = NSImage(cgImage: grayCG, size: pointSize)

        let dimmed = NSImage(size: pointSize, flipped: false) { rect in
            grayImage.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 0.45)
            return true
        }
        dimmed.isTemplate = false
        return dimmed
    }

    private static func fallback() -> NSImage {
        NSImage(systemSymbolName: "radio", accessibilityDescription: "BFF.fm")
            ?? NSImage(size: pointSize)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test 2>&1 | tail -5`
Expected: all tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/BFFCore/StatusIcon.swift Tests/BFFCoreTests/StatusIconTests.swift
git commit -m "Add StatusIcon with color and dimmed Cool Rock variants"
```

---

### Task 5: UI + app glue (`MenuView`, `AppModel`, `BFFMenuBarApp`, entry point)

SwiftUI views and scene wiring — no unit tests per the spec; verified by build here and by launching the bundled app in Task 6.

**Files:**
- Create: `Sources/BFFCore/AppModel.swift`
- Create: `Sources/BFFCore/MenuView.swift`
- Create: `Sources/BFFCore/BFFMenuBarApp.swift`
- Modify: `Sources/BFFMenuBar/main.swift` (replace placeholder)

**Interfaces:**
- Consumes: `PlayerController` (`state`, `State.isActive`, `toggle()`), `NowPlayingService` (`nowPlaying`, `fetchFailed`, `setPlaying(_:)`, `setMenuOpen(_:)`), `NowPlaying` (`program`, `presenter`, `songLine`, `album`, `artworkURL`), `StatusIcon.image(active:)`.
- Produces: `public struct BFFMenuBarApp: App` with `public init()` — the only public symbol in `BFFCore`.

- [ ] **Step 1: Implement `AppModel`**

Create `Sources/BFFCore/AppModel.swift`:

```swift
import AppKit
import Combine

/// Owns the player and metadata service and bridges them: playback state
/// drives both the menu bar icon (via `playbackActive`, republished so the
/// MenuBarExtra label refreshes) and the service's poll gate.
@MainActor
final class AppModel: ObservableObject {
    let player = PlayerController()
    let service = NowPlayingService()

    @Published private(set) var playbackActive = false

    private var cancellables: Set<AnyCancellable> = []

    init() {
        // Menu bar only — no Dock icon, even when run outside a bundle.
        NSApplication.shared.setActivationPolicy(.accessory)

        player.$state
            .map(\.isActive)
            .removeDuplicates()
            .sink { [weak self] active in
                self?.playbackActive = active
                self?.service.setPlaying(active)
            }
            .store(in: &cancellables)
    }
}
```

- [ ] **Step 2: Implement `MenuView`**

Create `Sources/BFFCore/MenuView.swift`:

```swift
import ServiceManagement
import SwiftUI

struct MenuView: View {
    @ObservedObject var player: PlayerController
    @ObservedObject var service: NowPlayingService
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            showHeader
            artwork
            playButton
            if case .failed(let message) = player.state {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if service.fetchFailed {
                Text("Can’t reach BFF.fm — info may be stale.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Divider()
            Toggle("Launch at Login", isOn: $launchAtLogin)
                .toggleStyle(.checkbox)
                .onChange(of: launchAtLogin) { _, enabled in
                    setLaunchAtLogin(enabled)
                }
            Button("Quit BFF.fm") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(12)
        .frame(width: 280)
        .onAppear { service.setMenuOpen(true) }
        .onDisappear { service.setMenuOpen(false) }
    }

    @ViewBuilder
    private var showHeader: some View {
        Text(service.nowPlaying?.program ?? "BFF.fm — Best Frequencies Forever")
            .font(.headline)
        if let presenter = service.nowPlaying?.presenter {
            Text("with \(presenter)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        if let song = service.nowPlaying?.songLine {
            Text(song)
            if let album = service.nowPlaying?.album {
                Text(album)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var artwork: some View {
        if let url = service.nowPlaying?.artworkURL {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary)
            }
            .frame(width: 256, height: 256)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var playButton: some View {
        Button {
            player.toggle()
        } label: {
            switch player.state {
            case .stopped, .failed:
                Label("Play", systemImage: "play.fill")
            case .loading:
                Label("Connecting…", systemImage: "hourglass")
            case .playing:
                Label("Stop", systemImage: "stop.fill")
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Revert the toggle to what the system actually has.
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
```

- [ ] **Step 3: Implement the app scene and entry point**

Create `Sources/BFFCore/BFFMenuBarApp.swift`:

```swift
import SwiftUI

public struct BFFMenuBarApp: App {
    @StateObject private var model = AppModel()

    public init() {}

    public var body: some Scene {
        MenuBarExtra {
            MenuView(player: model.player, service: model.service)
        } label: {
            Image(nsImage: StatusIcon.image(active: model.playbackActive))
        }
        .menuBarExtraStyle(.window)
    }
}
```

Replace the entire contents of `Sources/BFFMenuBar/main.swift` with:

```swift
import BFFCore

BFFMenuBarApp.main()
```

- [ ] **Step 4: Verify build and tests**

Run: `swift test 2>&1 | tail -5`
Expected: build succeeds, all tests PASS.

- [ ] **Step 5: Smoke-run the unbundled binary**

Run:

```bash
swift build 2>&1 | tail -3
(.build/debug/BFFMenuBar &) && sleep 5 && pgrep -fl BFFMenuBar
pkill -f '.build/debug/BFFMenuBar'
```

Expected: the process is running (pgrep prints its pid) and no crash output. The Cool Rock icon should appear in the menu bar during the 5 seconds; full UI verification happens in Task 6.

- [ ] **Step 6: Commit**

```bash
git add Sources/BFFCore/AppModel.swift Sources/BFFCore/MenuView.swift \
        Sources/BFFCore/BFFMenuBarApp.swift Sources/BFFMenuBar/main.swift
git commit -m "Add menu bar UI, app model, and entry point"
```

---

### Task 6: App bundle, Makefile, README, end-to-end verification

**Files:**
- Create: `Scripts/Info.plist`
- Create: `Scripts/build-app.sh` (executable)
- Create: `Makefile`
- Create: `README.md`

**Interfaces:**
- Consumes: release build products `.build/release/BFFMenuBar` and `.build/release/bffdotfm-menu-bar_BFFCore.bundle` (SwiftPM's resource bundle — must be copied next to the binary or `Bundle.module` crashes at launch); `Sources/BFFCore/Resources/coolrock.svg` for the app icon.
- Produces: `build/BFF.fm.app` (ad-hoc signed, `LSUIElement`), `make app` / `make install` / `make run` / `make test` / `make clean`.

- [ ] **Step 1: Create the Info.plist**

Create `Scripts/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleDisplayName</key>
	<string>BFF.fm</string>
	<key>CFBundleExecutable</key>
	<string>BFFMenuBar</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundleIdentifier</key>
	<string>com.bunting.bffdotfm-menu-bar</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>BFF.fm</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
</dict>
</plist>
```

- [ ] **Step 2: Create the bundle script**

Create `Scripts/build-app.sh`:

```bash
#!/bin/bash
# Assembles build/BFF.fm.app from the SwiftPM release build.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP="build/BFF.fm.app"
BIN=".build/release/BFFMenuBar"
RESOURCE_BUNDLE=".build/release/bffdotfm-menu-bar_BFFCore.bundle"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/BFFMenuBar"
cp -R "$RESOURCE_BUNDLE" "$APP/Contents/Resources/"
cp Scripts/Info.plist "$APP/Contents/Info.plist"

# App icon: rasterize the SVG into an .icns. Best-effort — the app works
# without it, so a qlmanage hiccup must not fail the build.
TMP="$(mktemp -d)"
qlmanage -t -s 1024 -o "$TMP" Sources/BFFCore/Resources/coolrock.svg >/dev/null 2>&1 || true
MASTER="$TMP/coolrock.svg.png"
if [ -f "$MASTER" ]; then
    ICONSET="$TMP/AppIcon.iconset"
    mkdir -p "$ICONSET"
    for s in 16 32 128 256 512; do
        sips -z "$s" "$s" "$MASTER" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
        d=$((s * 2))
        sips -z "$d" "$d" "$MASTER" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
    done
    iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
else
    echo "warning: could not rasterize coolrock.svg; skipping AppIcon.icns" >&2
fi
rm -rf "$TMP"

codesign --force --deep --sign - "$APP"
echo "Built $APP"
```

Then run: `chmod +x Scripts/build-app.sh`

- [ ] **Step 3: Create the Makefile**

Create `Makefile` (recipes MUST be indented with tabs, not spaces):

```makefile
.PHONY: app install run test clean

app:
	Scripts/build-app.sh

install: app
	rm -rf /Applications/BFF.fm.app
	cp -R build/BFF.fm.app /Applications/
	@echo "Installed /Applications/BFF.fm.app"

run: app
	open build/BFF.fm.app

test:
	swift test

clean:
	rm -rf .build build
```

- [ ] **Step 4: Create the README**

Create `README.md`:

```markdown
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

Cool Rock artwork © [BFF.fm](https://bff.fm/). Not an official BFF.fm app.
```

- [ ] **Step 5: Build the app bundle**

Run: `make app`
Expected: ends with `Built build/BFF.fm.app` (a qlmanage icon warning is acceptable). Then verify the bundle contents:

```bash
ls build/BFF.fm.app/Contents/MacOS/BFFMenuBar \
   build/BFF.fm.app/Contents/Resources/bffdotfm-menu-bar_BFFCore.bundle \
   build/BFF.fm.app/Contents/Info.plist
codesign -dv build/BFF.fm.app 2>&1 | head -3
```

Expected: all three paths exist; codesign reports the bundle is signed (adhoc).

- [ ] **Step 6: Launch and verify end-to-end**

```bash
open build/BFF.fm.app && sleep 5 && pgrep -fl BFFMenuBar
curl -s 'https://data.bff.fm/api/data/onair/now.json' | head -c 300
```

Expected: process running; curl shows the metadata the dropdown should display. Confirm with the human partner (this part is audible/visual, not scriptable):
1. Cool Rock icon appears in the menu bar, dimmed.
2. Clicking opens the dropdown with show name, song, and album art matching the curl output.
3. Play starts audio within a few seconds; the icon switches to full color.
4. Stop halts audio; the icon dims again.
5. Launch at Login toggles without an error line appearing.
6. Quit removes the icon and the process exits.

- [ ] **Step 7: Commit**

```bash
git add Scripts Makefile README.md
git commit -m "Add app bundle script, Makefile, and README"
```
