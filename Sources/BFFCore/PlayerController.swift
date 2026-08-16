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

    static let streamURL = BFFAPI.stream

    @Published private(set) var state: State = .stopped

    private var player: AVPlayer?
    private var cancellables: Set<AnyCancellable> = []
    private var watchdog: Task<Void, Never>?
    private let loadingTimeout: Duration

    /// - Parameter loadingTimeout: how long the stream may sit in `.loading` —
    ///   connecting, or stalled mid-play — before we call it failed. Injectable
    ///   so tests need not wait out the real timeout.
    init(loadingTimeout: Duration = .seconds(20)) {
        self.loadingTimeout = loadingTimeout
    }

    func toggle() {
        state.isActive ? stop() : play()
    }

    func play() {
        teardown()
        let asset = AVURLAsset(url: Self.streamURL,
                               options: [AVURLAssetHTTPUserAgentKey: BFFAPI.userAgent])
        let item = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: item)
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
        case .stopped, .playing, .failed:
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
        transition(to: .failed(message))
    }

    private func teardown() {
        cancelWatchdog()
        cancellables.removeAll()
        player?.pause()
        player = nil
    }
}
