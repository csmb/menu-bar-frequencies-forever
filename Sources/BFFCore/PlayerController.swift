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

    static let streamURL = URL(string: "https://stream.bff.fm/1/mp3.mp3?app_id=bffdotfm-menu-bar")!

    @Published private(set) var state: State = .stopped

    private var player: AVPlayer?
    private var cancellables: Set<AnyCancellable> = []

    func toggle() {
        state.isActive ? stop() : play()
    }

    func play() {
        teardown()
        let asset = AVURLAsset(url: Self.streamURL,
                               options: [AVURLAssetHTTPUserAgentKey: NowPlayingService.userAgent])
        let item = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: item)
        self.player = player
        state = .loading

        player.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self, self.player === player else { return }
                switch status {
                case .playing:
                    self.state = .playing
                case .waitingToPlayAtSpecifiedRate:
                    self.state = .loading
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
            .sink { [weak self] _ in
                guard let self, self.player === player else { return }
                self.fail(item.error)
            }
            .store(in: &cancellables)

        player.play()
    }

    func stop() {
        teardown()
        state = .stopped
    }

    private func fail(_ error: Error?) {
        teardown()
        state = .failed(error?.localizedDescription ?? "Stream failed")
    }

    private func teardown() {
        cancellables.removeAll()
        player?.pause()
        player = nil
    }
}
