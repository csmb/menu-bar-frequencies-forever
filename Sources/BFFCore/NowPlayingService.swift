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
