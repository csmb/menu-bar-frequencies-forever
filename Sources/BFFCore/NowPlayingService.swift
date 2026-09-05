import Foundation

typealias DataProvider = @Sendable (URL) async throws -> (Data, URLResponse)

/// Fetches BFF.fm's unified now-playing metadata and polls it every
/// `pollInterval` seconds — but only while the stream is playing or the
/// dropdown is open, so an idle app makes zero requests.
@MainActor
final class NowPlayingService: ObservableObject {
    nonisolated static let endpoint = BFFAPI.nowPlaying
    static let pollInterval: TimeInterval = 30
    /// The ceiling the backoff climbs to and holds at. Eight minutes: a station
    /// whose info API is down is asked roughly seven times an hour, never given
    /// up on — so metadata catches up on its own once they recover.
    static let maxPollInterval: TimeInterval = 480

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
    /// Consecutive failed fetches, reset by any success. Drives the backoff.
    private var consecutiveFailures = 0

    var isPolling: Bool { timer != nil }

    /// The gap to wait before the next poll: the base interval doubled once per
    /// consecutive failure, capped at `maxPollInterval`. With no failures it is
    /// exactly `pollInterval`, so a healthy app keeps its normal 30s cadence;
    /// each failure only ever *lengthens* the gap, never shortens it below that.
    var nextPollInterval: TimeInterval {
        min(Self.pollInterval * pow(2, Double(consecutiveFailures)), Self.maxPollInterval)
    }

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
            consecutiveFailures = 0
        } catch {
            fetchFailed = true
            consecutiveFailures += 1
        }
        // Schedule the next poll from the outcome we just learned, so a failure
        // lengthens the gap before the *next* attempt rather than a later one.
        // Only while still polling — if the gate closed mid-fetch, stay quiet.
        if isPlaying || menuOpen {
            armTimer(after: nextPollInterval)
        } else {
            timer?.invalidate()
            timer = nil
        }
    }

    private func refreshGate() {
        let shouldPoll = isPlaying || menuOpen
        if shouldPoll, timer == nil {
            // Opening the dropdown starts polling, and polling starts with a
            // fetch — so without this, every click on the menu bar icon was a
            // request. Idly opening and closing it a dozen times sent a dozen,
            // against a documented rate of one per 30s. The gate is
            // `nextPollInterval`, not the base 30s, so during a backoff a
            // reopen can't outpace it either; only the eager first fetch is
            // held back, which costs at most one interval of staleness on data
            // we just asked for anyway.
            if let last = lastRequested, now().timeIntervalSince(last) < nextPollInterval {
                // Too soon. The timer below will catch up.
            } else {
                fetchNow()
            }
            // Arm a timer synchronously even when the eager fetch fired: it
            // guards the async gap so a burst of opens can't each start a poll,
            // and a completed fetch re-arms it with the accurate next gap.
            armTimer(after: nextPollInterval)
        } else if !shouldPoll {
            timer?.invalidate()
            timer = nil
        }
    }

    /// A one-shot timer, not a repeating one, because the gap between polls
    /// varies with the backoff. `fetch()` re-arms it on each completion.
    private func armTimer(after interval: TimeInterval) {
        timer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.timerFired() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func timerFired() {
        guard isPlaying || menuOpen else {
            timer = nil
            return
        }
        fetchNow()
    }
}
