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

    // MARK: Exponential backoff

    /// Each consecutive failure doubles the gap before the next poll, so a
    /// struggling station is asked less often, never more.
    func testBackoffDoublesOnConsecutiveFailures() async {
        let service = makeService(ProviderBox(.failure(URLError(.timedOut))))
        XCTAssertEqual(service.nextPollInterval, NowPlayingService.pollInterval,
                       "starts at the normal cadence with no failures")
        await service.fetch()
        XCTAssertEqual(service.nextPollInterval, 60)
        await service.fetch()
        XCTAssertEqual(service.nextPollInterval, 120)
        await service.fetch()
        XCTAssertEqual(service.nextPollInterval, 240)
    }

    /// The gap grows toward a ceiling and holds there — it never gives up, but
    /// it also never stretches past the cap.
    func testBackoffHoldsAtMax() async {
        let service = makeService(ProviderBox(.failure(URLError(.timedOut))))
        for _ in 0..<10 { await service.fetch() }
        XCTAssertEqual(service.nextPollInterval, NowPlayingService.maxPollInterval)
    }

    /// One success wipes the backoff, so recovery snaps straight back to the
    /// normal 30s cadence instead of crawling back down.
    func testSuccessResetsBackoff() async {
        let box = ProviderBox(.failure(URLError(.timedOut)))
        let service = makeService(box)
        await service.fetch()
        await service.fetch()
        XCTAssertEqual(service.nextPollInterval, 120)
        box.result = .success((payload, response(status: 200)))
        await service.fetch()
        XCTAssertEqual(service.nextPollInterval, NowPlayingService.pollInterval)
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

    /// After a failure the grown backoff gap — not the base 30s — governs the
    /// next attempt, so reopening the menu partway through it stays quiet even
    /// once the base interval has passed.
    func testBackoffGapThrottlesReopen() async {
        let counter = Counter()
        var seconds = 1_000.0
        let service = NowPlayingService(
            provider: { _ in
                counter.requests += 1
                throw URLError(.timedOut)
            },
            now: { Date(timeIntervalSince1970: seconds) })

        service.setMenuOpen(true)   // attempt #1 fails → gap grows to 60s
        service.setMenuOpen(false)
        try? await Task.sleep(nanoseconds: 50_000_000)

        seconds += 40               // past the 30s base, still inside the 60s gap
        service.setMenuOpen(true)
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(counter.requests, 1,
                       "a reopen inside the grown backoff gap must not refetch")
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

    /// The suffix test is only as good as the string it runs on. Each of these
    /// has a host ending in ".bff.fm" that is not a bff.fm name.
    func testRejectsHostsThatAreNotPlainNames() {
        // IPv6 addresses whose zone ID ends in .bff.fm. The network stack
        // ignores the zone and connects to the address — the first of these
        // reached a local listener before this check existed.
        XCTAssertNil(BFFAPI.trusted(URL(string: "https://[::ffff:203.0.113.7%25x.bff.fm]/a.png")))
        XCTAssertNil(BFFAPI.trusted(URL(string: "https://[::1%25x.bff.fm]/a.png")))
        // Escapes that decode to characters no hostname can hold.
        XCTAssertNil(BFFAPI.trusted(URL(string: "https://evil.example%00.bff.fm/a.png")))
        XCTAssertNil(BFFAPI.trusted(URL(string: "https://evil.example%2F.bff.fm/a.png")))
    }

    /// Credentials have no place in a link to bff.fm, and they are the classic
    /// way to make a URL read as one host while it goes to another.
    func testRejectsCredentials() {
        XCTAssertNil(BFFAPI.trusted(URL(string: "https://evil.example%5C@bff.fm/x")))
        XCTAssertNil(BFFAPI.trusted(URL(string: "https://user:pass@bff.fm/x")))
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
