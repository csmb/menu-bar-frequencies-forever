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
