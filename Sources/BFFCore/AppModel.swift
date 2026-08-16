import AppKit
import Combine

/// Owns the player and metadata service and bridges them: playback state
/// drives both the menu bar icon (via `playbackActive`, republished so the
/// MenuBarExtra label refreshes) and the service's poll gate.
@MainActor
final class AppModel: ObservableObject {
    let player = PlayerController()
    let service = NowPlayingService()

    @Published private(set) var playbackActive = false

    private var cancellables: Set<AnyCancellable> = []

    init() {
        // Menu bar only — no Dock icon, even when run outside a bundle.
        NSApplication.shared.setActivationPolicy(.accessory)

        player.$state
            .map(\.isActive)
            .removeDuplicates()
            .sink { [weak self] active in
                self?.playbackActive = active
                self?.service.setPlaying(active)
            }
            .store(in: &cancellables)
    }
}
