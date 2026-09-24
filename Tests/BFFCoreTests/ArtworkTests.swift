import AppKit
import XCTest
@testable import BFFCore

/// Cover art is fetched through the same live provider as now.json and the
/// schedule. `ArtworkHost` answers for a test-only host inside
/// `URLSession.shared`, so the real request path runs without the network.
@MainActor
final class ArtworkTests: XCTestCase {
    private let artwork = URL(string: "https://artwork.invalid/image/original/cover-art.png")!

    override func setUp() {
        super.setUp()
        ArtworkHost.requests = []
        ArtworkHost.body = Data()
        URLProtocol.registerClass(ArtworkHost.self)
    }

    override func tearDown() {
        URLProtocol.unregisterClass(ArtworkHost.self)
        super.tearDown()
    }

    /// Artwork is the request the app makes most, and through `AsyncImage` it
    /// went out with the shared session's User-Agent and no app_id — the one
    /// request BFF.fm could not attribute to us.
    func testArtworkRequestIdentifiesTheApp() async throws {
        _ = await Artwork.image(at: artwork)
        let request = try XCTUnwrap(ArtworkHost.requests.first)
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), BFFAPI.userAgent)
        XCTAssertEqual(request.url?.query, "app_id=com.bunting.menu-bar-frequencies-forever")
    }

    /// And what comes back is the picture, as it was with `AsyncImage`.
    func testArtworkDecodesTheImageItIsSent() async {
        ArtworkHost.body = Self.png(width: 3, height: 2)
        let image = await Artwork.image(at: artwork)
        XCTAssertEqual(image?.size, NSSize(width: 3, height: 2))
    }

    private static func png(width: Int, height: Int) -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                   isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        return rep.representation(using: .png, properties: [:])!
    }
}

/// Answers for `artwork.invalid` inside `URLSession.shared`, recording each
/// request it is handed.
private final class ArtworkHost: URLProtocol {
    nonisolated(unsafe) static var requests: [URLRequest] = []
    nonisolated(unsafe) static var body = Data()

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "artwork.invalid"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.append(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "image/png"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
