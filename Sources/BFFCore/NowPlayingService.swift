import Foundation

typealias DataProvider = @Sendable (URL) async throws -> (Data, URLResponse)

/// Fetches BFF.fm's unified now-playing metadata and polls it every
/// `pollInterval` seconds — but only while the stream is playing or the
/// dropdown is open, so an idle app makes zero requests.
@MainActor
final class NowPlayingService: ObservableObject {
    nonisolated static let endpoint = BFFAPI.nowPlaying
    static let pollInterval: TimeInterval = 30

    @Published private(set) var nowPlaying: NowPlaying?
    @Published private(set) var fetchFailed = false

    private let provider: DataProvider
    private let now: () -> Date
    private var timer: Timer?
    private var isPlaying = false
    private var menuOpen = false
    /// When we last *asked*, not when we last succeeded — a failing endpoint
    /// must not be retried faster than a working one.
    private var lastRequested: Date?

    var isPolling: Bool { timer != nil }

    /// `now` is injectable so the throttle can be tested without waiting out
    /// a real 30 seconds.
    init(provider: @escaping DataProvider = NowPlayingService.liveProvider,
         now: @escaping () -> Date = Date.init) {
        self.provider = provider
        self.now = now
    }

    deinit { timer?.invalidate() }

    nonisolated static let liveProvider: DataProvider = { url in
        var request = URLRequest(url: url)
        request.setValue(BFFAPI.userAgent, forHTTPHeaderField: "User-Agent")
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
        // Stamped here, synchronously, not inside fetch(). fetch() runs in a
        // Task, so a burst of clicks all read the old timestamp before the
        // first one has recorded anything and every click gets through — the
        // throttle looked right and did nothing.
        lastRequested = now()
        Task { await self.fetch() }
    }

    func fetch() async {
        lastRequested = now()
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
            // Opening the dropdown starts polling, and polling starts with a
            // fetch — so without this, every click on the menu bar icon was a
            // request. Idly opening and closing it a dozen times sent a dozen,
            // against a documented rate of one per 30s. The timer still runs on
            // schedule; only the eager first fetch is held back, which costs at
            // most one interval of staleness on data we just asked for anyway.
            if let last = lastRequested, now().timeIntervalSince(last) < Self.pollInterval {
                // Too soon. The timer below will catch up.
            } else {
                fetchNow()
            }
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
