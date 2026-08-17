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
        XCTAssertEqual(NowPlayingService.endpoint.query, "app_id=com.bunting.menu-bar-frequencies-forever")
    }

    /// The stream is a BFF.fm endpoint too, so the same rule binds it.
    func testStreamCarriesAppID() {
        XCTAssertEqual(PlayerController.streamURL.query, "app_id=com.bunting.menu-bar-frequencies-forever")
    }

    /// BFF.fm's developer rules ask for "a reverse URI form (e.g.
    /// com.example.bff.app)", so a bare slug would be non-compliant.
    func testAppIDIsReverseURIForm() {
        let segments = BFFAPI.appID.split(separator: ".")
        XCTAssertGreaterThanOrEqual(segments.count, 3, "expected reverse URI form, got \(BFFAPI.appID)")
        XCTAssertEqual(segments.first, "com")
    }
}

@MainActor
final class PollThrottleTests: XCTestCase {
    private final class Counter: @unchecked Sendable {
        var requests = 0
    }

    private func service(_ counter: Counter, clock: @escaping () -> Date)
        -> NowPlayingService
    {
        NowPlayingService(
            provider: { url in
                counter.requests += 1
                let response = HTTPURLResponse(url: url, statusCode: 200,
                                               httpVersion: nil, headerFields: nil)!
                return (Data("{}".utf8), response)
            },
            now: clock)
    }

    /// Fidgeting with the menu bar icon must not become a request per click.
    func testReopeningTheDropdownDoesNotRefetchWithinTheInterval() async {
        let counter = Counter()
        let clock = { Date(timeIntervalSince1970: 1_000) }
        let service = service(counter, clock: clock)

        for _ in 0..<10 {
            service.setMenuOpen(true)
            service.setMenuOpen(false)
        }
        await Task.yield()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(counter.requests, 1,
                       "ten opens inside one interval should cost one request")
    }

    /// But it must still refresh once the interval has genuinely passed.
    func testReopeningAfterTheIntervalDoesRefetch() async {
        let counter = Counter()
        var seconds = 1_000.0
        let service = service(counter, clock: { Date(timeIntervalSince1970: seconds) })

        service.setMenuOpen(true)
        service.setMenuOpen(false)
        try? await Task.sleep(nanoseconds: 50_000_000)

        seconds += NowPlayingService.pollInterval + 1
        service.setMenuOpen(true)
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(counter.requests, 2,
                       "a reopen after the interval should refresh")
    }

    /// A failing endpoint must not be retried faster than a working one.
    func testFailuresDoNotUnlockFasterRetries() async {
        let counter = Counter()
        let clock = { Date(timeIntervalSince1970: 1_000) }
        let service = NowPlayingService(
            provider: { _ in
                counter.requests += 1
                throw URLError(.notConnectedToInternet)
            },
            now: clock)

        for _ in 0..<5 {
            service.setMenuOpen(true)
            service.setMenuOpen(false)
        }
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(counter.requests, 1,
                       "a failing endpoint must not be hammered")
    }
}

final class TrustedURLTests: XCTestCase {
    func testAcceptsBFFOverTLS() {
        XCTAssertNotNil(BFFAPI.trusted(URL(string: "https://bff.fm/shows/x")))
        XCTAssertNotNil(BFFAPI.trusted(URL(string: "https://a.bff.fm/image/y.png")))
        XCTAssertNotNil(BFFAPI.trusted(URL(string: "https://BFF.FM/shows/x")))
    }

    func testRejectsOtherHosts() {
        XCTAssertNil(BFFAPI.trusted(URL(string: "https://evil.example/x")))
        // The one a bare hasSuffix check would wave through.
        XCTAssertNil(BFFAPI.trusted(URL(string: "https://notbff.fm/x")))
        XCTAssertNil(BFFAPI.trusted(URL(string: "https://bff.fm.evil.example/x")))
    }

    func testRejectsNonHTTPSSchemes() {
        XCTAssertNil(BFFAPI.trusted(URL(string: "http://bff.fm/x")))
        XCTAssertNil(BFFAPI.trusted(URL(string: "file:///etc/passwd")))
        XCTAssertNil(BFFAPI.trusted(URL(string: "javascript:alert(1)")))
    }
}

@MainActor
final class BorrowedURLTests: XCTestCase {
    /// A schedule entry pointing off-site must not become a link we open.
    func testScheduleURLsOffBFFAreDropped() {
        let ics = """
        BEGIN:VEVENT
        SUMMARY:Hostile Show on BFF.FM
        URL:https://evil.example/pwned
        END:VEVENT
        BEGIN:VEVENT
        SUMMARY:Real Show on BFF.FM
        URL:https://bff.fm/shows/real-show
        END:VEVENT
        """
        let parsed = ShowDirectory.parse(ics)
        XCTAssertNil(parsed["hostile show"])
        XCTAssertEqual(parsed["real show"]?.absoluteString,
                       "https://bff.fm/shows/real-show")
    }

    func testArtworkOffBFFIsDropped() {
        let hostile = NowPlaying(image: "https://evil.example/track.png")
        XCTAssertNil(hostile.artworkURL)

        let real = NowPlaying(image: "https://a.bff.fm/image/original/x.png")
        XCTAssertEqual(real.artworkURL?.host, "a.bff.fm")
    }
}
