import AppKit
import AVFoundation
import Combine
import Foundation

/// Wraps AVPlayer on the BFF.fm live MP3 stream. Every play() builds a fresh
/// AVPlayerItem so playback rejoins the live edge instead of resuming a stale
/// buffer; stop() discards the player entirely.
///
/// `automaticallyWaitsToMinimizeStalling` is deliberately left at its default.
/// Turning it off is the obvious tune for live audio and it was measured:
/// median time-to-ready 0.938s against 0.973s, a 35ms difference inside a
/// sample spread of 0.84-1.26s — noise. The wait is the CDN's first byte, not
/// AVPlayer's buffering. It also costs something real: `timeControlStatus`
/// flips to playing at ~13ms while the buffer is still empty, so the dropdown
/// would show Stop through nearly a second of silence instead of Connecting.
/// See TimeToAudioMeasurement.
@MainActor
final class PlayerController: ObservableObject {
    enum State: Equatable {
        case stopped
        case loading
        case reconnecting
        case playing
        case failed(String)

        var isActive: Bool { self == .loading || self == .reconnecting || self == .playing }
    }

    static let streamURL = BFFAPI.stream

    @Published private(set) var state: State = .stopped

    static let volumeKey = "streamVolume"

    /// The stream's own level, 0...1, multiplied against the system volume —
    /// so the radio can sit under everything else on the Mac, which is the
    /// point of having it. Persisted, because a level you must set again on
    /// every launch is not really a preference.
    @Published var volume: Double = 1 {
        didSet {
            let clamped = Self.clamp(volume)
            if clamped != volume {
                volume = clamped        // re-enters once, then settles
                return
            }
            defaults.set(volume, forKey: Self.volumeKey)
            player?.volume = Float(volume)
        }
    }

    /// What the live player is actually set to. Visible for testing: `player`
    /// stays private so nothing outside can drive it.
    var playerVolume: Float? { player?.volume }

    /// Whether enough audio is buffered to play without stalling. Visible for
    /// measurement: `state` reaching `.playing` is not the same thing as sound
    /// coming out, and with `automaticallyWaitsToMinimizeStalling` off the two
    /// diverge — the status flips at once while the buffer is still empty.
    /// `currentTime()` is no use here; a continuous Icecast stream has no
    /// timeline and reports indefinite.
    var isReadyForSmoothPlayback: Bool {
        player?.currentItem?.isPlaybackLikelyToKeepUp ?? false
    }

    /// 2, 4, 8, 16, 32 seconds: five retries over about a minute of gaps,
    /// which covers a lid reopened while Wi-Fi rejoins, and stays a good
    /// guest — at most six connection attempts per incident.
    nonisolated static let defaultReconnectDelays: [Duration] =
        [.seconds(2), .seconds(4), .seconds(8), .seconds(16), .seconds(32)]

    private var player: AVPlayer?
    private var cancellables: Set<AnyCancellable> = []
    private var watchdog: Task<Void, Never>?
    /// True from play() until stop() or giving up — the difference between a
    /// drop worth chasing and a stream the user told to be quiet.
    private var wantsPlayback = false
    /// Reconnect recovers drops, not failed first connects: it arms only once
    /// this press of Play has actually produced playback, so Play against a
    /// down stream still fails honestly within one watchdog.
    private var hasPlayedSinceIntent = false
    private var reconnectAttempt = 0
    private var reconnectTask: Task<Void, Never>?
    /// Not in `cancellables` — teardown() clears those with every rebuild,
    /// and this subscription lasts the controller's life.
    private var wakeObserver: AnyCancellable?
    private let loadingTimeout: Duration
    private let reconnectDelays: [Duration]
    private let defaults: UserDefaults
    private let makePlayer: (AVPlayerItem) -> AVPlayer

    /// - Parameters:
    ///   - loadingTimeout: how long the stream may sit in `.loading` —
    ///     connecting, or stalled mid-play — before we call it failed.
    ///     Injectable so tests need not wait out the real timeout.
    ///   - reconnectDelays: the backoff gaps between automatic reconnect
    ///     attempts after a drop. Injectable so tests need not wait them out.
    ///   - defaults: where the volume is remembered. Injectable so tests do
    ///     not read or write the level this machine is actually using.
    ///   - workspaceNotifications: where `NSWorkspace.didWakeNotification`
    ///     arrives. Injectable so tests can post a wake without sleeping the
    ///     machine.
    ///   - makePlayer: builds the AVPlayer for a stream item. Injectable so a
    ///     test can exercise `play()` without opening the stream.
    init(loadingTimeout: Duration = .seconds(20),
         reconnectDelays: [Duration] = PlayerController.defaultReconnectDelays,
         defaults: UserDefaults = .standard,
         workspaceNotifications: NotificationCenter = NSWorkspace.shared.notificationCenter,
         makePlayer: @escaping (AVPlayerItem) -> AVPlayer = AVPlayer.init(playerItem:)) {
        self.loadingTimeout = loadingTimeout
        self.reconnectDelays = reconnectDelays
        self.defaults = defaults
        self.makePlayer = makePlayer
        // Not `defaults.double(forKey:)`: that answers 0 for a key nobody has
        // written, so a fresh install would start silent and read as broken.
        self.volume = defaults.object(forKey: Self.volumeKey)
            .map { Self.clamp(($0 as? Double) ?? 1) } ?? 1

        // The connection from before sleep is dead even when AVPlayer has not
        // noticed yet, so don't wait for the stall to surface: rebuild at the
        // live edge — which is where a listener wants to wake up anyway —
        // through play(), so the reconnect budget is fresh too.
        wakeObserver = workspaceNotifications
            .publisher(for: NSWorkspace.didWakeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.state.isActive else { return }
                self.play()
            }
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    func toggle() {
        state.isActive ? stop() : play()
    }

    func play() {
        wantsPlayback = true
        hasPlayedSinceIntent = false
        reconnectAttempt = 0
        cancelReconnect()
        open()
    }

    /// Builds a fresh player on the live edge. `play()` is the user's press
    /// and resets the reconnect budget; a reconnect attempt re-enters here
    /// without touching it.
    private func open() {
        teardown()
        let asset = AVURLAsset(url: Self.streamURL,
                               options: [AVURLAssetHTTPUserAgentKey: BFFAPI.userAgent])
        let item = AVPlayerItem(asset: asset)
        let player = makePlayer(item)
        // Every play() builds a new player, and a new player starts at full
        // volume — so without this the stream comes back loud the first time
        // you press Stop then Play.
        player.volume = Float(volume)
        self.player = player
        transition(to: .loading)

        player.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self, self.player === player else { return }
                switch status {
                case .playing:
                    self.transition(to: .playing)
                case .waitingToPlayAtSpecifiedRate:
                    self.transition(to: .loading)
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
            .sink { [weak self] notification in
                guard let self, self.player === player else { return }
                let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
                self.fail(error)
            }
            .store(in: &cancellables)

        // A live stream has no end, so reaching one means the server closed
        // the connection cleanly — a source restart, a relay recycling its
        // listeners. AVPlayer takes that as the item finishing: it plays out
        // its buffer and pauses, with no error and no stall, and `.paused` is
        // ignored above. Without this the app sat in `.playing` over silence
        // with nothing left to notice, and never reconnected.
        NotificationCenter.default
            .publisher(for: AVPlayerItem.didPlayToEndTimeNotification, object: item)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.player === player else { return }
                self.fail(message: "The BFF.fm stream ended")
            }
            .store(in: &cancellables)

        // A mid-stream stall — Wi-Fi dropped, stream server went away — leaves
        // the player waiting for data with no error and no status change we
        // could otherwise catch. Park in .loading so the watchdog bounds the
        // wait: a quick rebuffer recovers silently, a dead one ends in .failed.
        NotificationCenter.default
            .publisher(for: AVPlayerItem.playbackStalledNotification, object: item)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.player === player else { return }
                self.transition(to: .loading)
            }
            .store(in: &cancellables)

        player.play()
    }

    func stop() {
        wantsPlayback = false
        cancelReconnect()
        teardown()
        transition(to: .stopped)
    }

    /// The single funnel for state changes — that is what `private(set)` buys
    /// us — so the loading watchdog is armed and cancelled on exactly one path.
    func transition(to newState: State) {
        state = newState
        switch newState {
        case .loading:
            // Already armed means we re-entered .loading from a stall; keep the
            // original deadline instead of extending it on every notification.
            if watchdog == nil { startWatchdog() }
        case .playing:
            hasPlayedSinceIntent = true
            cancelWatchdog()
        case .stopped, .reconnecting, .failed:
            // .reconnecting needs no watchdog: the backoff gap is its own
            // bounded timer, and the attempt it launches re-enters .loading.
            cancelWatchdog()
        }
    }

    private func startWatchdog() {
        let timeout = loadingTimeout
        watchdog = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled, let self, self.state == .loading else { return }
            self.fail(message: "Couldn’t reach the BFF.fm stream")
        }
    }

    private func cancelWatchdog() {
        watchdog?.cancel()
        watchdog = nil
    }

    private func fail(_ error: Error?) {
        fail(message: error?.localizedDescription ?? "Stream failed")
    }

    private func fail(message: String) {
        teardown()
        guard wantsPlayback, hasPlayedSinceIntent,
              reconnectAttempt < reconnectDelays.count else {
            wantsPlayback = false
            transition(to: .failed(message))
            return
        }
        let gap = reconnectDelays[reconnectAttempt]
        reconnectAttempt += 1
        transition(to: .reconnecting)
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: gap)
            guard !Task.isCancelled, let self, self.state == .reconnecting else { return }
            self.open()
        }
    }

    private func cancelReconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
    }

    private func teardown() {
        cancelWatchdog()
        cancellables.removeAll()
        player?.pause()
        player = nil
    }
}
