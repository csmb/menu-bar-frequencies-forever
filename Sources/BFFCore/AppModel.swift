import AppKit
import Combine

/// Which of the dropdown's two screens is showing.
///
/// This lives outside the view because the popover keeps one hosting
/// controller for the life of the app: SwiftUI's `onAppear` fires once, ever,
/// so a `@State` page would stay on whatever screen it was left on and the
/// dropdown would reopen into the settings instead of the music.
@MainActor
final class MenuNavigation: ObservableObject {
    enum Page {
        case nowPlaying, more
    }

    @Published var page: Page = .nowPlaying

    func reset() {
        page = .nowPlaying
    }
}

/// Owns the player and metadata service and bridges them: playback state
/// drives both the menu bar icon (via `playbackActive`) and the service's
/// poll gate.
@MainActor
final class AppModel: ObservableObject {
    let player = PlayerController()
    let service = NowPlayingService()
    let shows = ShowDirectory()
    let navigation = MenuNavigation()

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

    /// Everything that has to happen each time the dropdown opens. Driven by
    /// the popover rather than by the view, because the view only appears once.
    func dropdownWillOpen() {
        navigation.reset()
        service.setMenuOpen(true)
        shows.loadIfNeeded()
        resolvePresenter()
    }

    func dropdownDidClose() {
        service.setMenuOpen(false)
    }

    /// The DJ's page is listed on their show's page, so this needs the
    /// schedule to have arrived first.
    func resolvePresenter() {
        guard let now = service.nowPlaying,
              let presenter = now.presenter,
              let program = now.program
        else { return }
        shows.loadPresenterIfNeeded(presenter, forShow: program)
    }
}
