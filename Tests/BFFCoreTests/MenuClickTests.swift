import AppKit
import SwiftUI
import XCTest
@testable import BFFCore

/// Clicks on the real `MenuView`, delivered straight to its window in this
/// process. The window is a non-activating panel far off screen, so nothing
/// takes focus from whatever the user is doing, and no click goes anywhere
/// but here.
@MainActor
final class MenuClickTests: XCTestCase {
    override func setUp() {
        super.setUp()
        URLProtocol.registerClass(PortraitArt.self)
    }

    override func tearDown() {
        URLProtocol.unregisterClass(PortraitArt.self)
        super.tearDown()
    }

    /// The harness itself: with no artwork in the way, a click on "…" opens
    /// the More page.
    func testClickingTheEllipsisOpensMore() async throws {
        let menu = try await Menu(showing: nil)
        await menu.clickEllipsis()
        XCTAssertEqual(menu.navigation.page, .more)
    }

    /// A show photo in portrait, scaled to fill the 256pt square, hangs over
    /// the rows above it. Clipping hides the overhang, but a clip is for
    /// drawing only, so it went on catching clicks: the show name, the DJ and
    /// "…" all went dead while this 480×640 image was up. The test clicks
    /// "…", the one control that row always has; the links beside it sat
    /// under the same overhang.
    func testPortraitArtworkLeavesTheTopRowClickable() async throws {
        let menu = try await Menu(showing: "https://a.bff.fm/image/original/portrait.png")
        await menu.clickEllipsis()
        XCTAssertEqual(menu.navigation.page, .more)
    }
}

/// The dropdown as the app builds it, in an off-screen panel.
@MainActor
private final class Menu {
    let navigation = MenuNavigation()
    private let panel: NSPanel
    private let host: NSHostingView<MenuView>

    init(showing artwork: String?) async throws {
        let payload = artwork.map { #"{"program":"A Show","program_image":"\#($0)"}"# }
            ?? #"{"program":"A Show"}"#
        let service = NowPlayingService(provider: { url in
            (Data(payload.utf8), HTTPURLResponse(url: url, statusCode: 200,
                                                 httpVersion: nil, headerFields: nil)!)
        })
        await service.fetch()

        host = NSHostingView(rootView: MenuView(
            player: PlayerController(defaults: UserDefaults(suiteName: "menu-click-tests")!,
                                     workspaceNotifications: NotificationCenter()),
            service: service,
            shows: ShowDirectory(provider: { _ in throw URLError(.notConnectedToInternet) }),
            navigation: navigation,
            loginItem: LoginItem(service: FakeLoginItems(status: .notRegistered))))
        panel = NSPanel(contentRect: NSRect(x: -30_000, y: -30_000, width: 280, height: 600),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.contentView = host
        panel.orderFrontRegardless()

        if artwork != nil {
            let served = await waitUntil { PortraitArt.served > 0 }
            XCTAssertTrue(served, "the artwork was never requested")
        }
        try? await Task.sleep(for: .milliseconds(300))   // let the view take it in
        panel.setContentSize(host.fittingSize)
        host.layoutSubtreeIfNeeded()
    }

    deinit { MainActor.assumeIsolated { panel.orderOut(nil) } }

    /// "…" sits at the top-right: a 30×24 target inside 12pt of padding.
    func clickEllipsis() async {
        let size = host.bounds.size
        let point = NSPoint(x: size.width - 12 - 15, y: size.height - 12 - 12)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                                           timestamp: ProcessInfo.processInfo.systemUptime,
                                           windowNumber: panel.windowNumber, context: nil,
                                           eventNumber: 0, clickCount: 1,
                                           pressure: type == .leftMouseDown ? 1 : 0)!
            panel.sendEvent(event)
        }
        try? await Task.sleep(for: .milliseconds(200))
    }

    private func waitUntil(_ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(3)
        while !condition() {
            if ContinuousClock.now > deadline { return false }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return true
    }
}

/// Serves a 480×640 image — the shape of the photo that was up when the
/// clicks went dead — for any a.bff.fm request, inside `URLSession.shared`.
private final class PortraitArt: URLProtocol {
    nonisolated(unsafe) static var served = 0

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "a.bff.fm"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.served += 1
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 480, pixelsHigh: 640,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                   isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "image/png"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: rep.representation(using: .png, properties: [:])!)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
