import AppKit
import Combine
import SwiftUI

/// Owns the menu bar item and the dropdown.
///
/// Deliberately AppKit rather than SwiftUI's `MenuBarExtra`: that scene keeps
/// its own private notion of whether the panel is showing and offers no way to
/// change it, so a panel dismissed any other way leaves the icon needing two
/// clicks. An `NSPopover` with `.transient` behaviour closes itself when the
/// user clicks away, and anchors itself under the button — which is also what
/// makes hand-centring the panel unnecessary.
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let model: AppModel
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private var cancellables: Set<AnyCancellable> = []
    private var outsideClickMonitor: Any?
    private var animation: Timer?
    private var frame = 0

    init(model: AppModel) {
        self.model = model
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        configureStatusItem()
        configurePopover()
        followPlaybackState()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.imagePosition = .imageOnly
        button.toolTip = "BFF.FM – Menu Bar Frequencies Forever"
        button.target = self
        button.action = #selector(togglePopover)
        // Fixed for the life of the app: a status item that resizes on
        // play/stop shoves its neighbours along and drags the open popover
        // sideways with it, because the popover is anchored to this button.
        statusItem.length = StatusIcon.playingSize.width + 8
        showIdleIcon()
    }

    // MARK: - The icon

    private func showIdleIcon() {
        animation?.invalidate()
        animation = nil
        frame = 0
        statusItem.button?.image = StatusIcon.idle
    }

    /// Swaps in a pre-rendered frame on a timer. `.common` mode keeps it
    /// running while a menu is open or the user is dragging something.
    private func startAnimating() {
        guard animation == nil else { return }
        let timer = Timer(timeInterval: StatusIcon.frameInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.advanceFrame() }
        }
        RunLoop.main.add(timer, forMode: .common)
        animation = timer
        advanceFrame()
    }

    private func advanceFrame() {
        let frames = StatusIcon.playingFrames
        guard !frames.isEmpty else { return }
        statusItem.button?.image = frames[frame % frames.count]
        frame += 1
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.delegate = self
        let host = NSHostingController(
            rootView: MenuView(player: model.player,
                               service: model.service,
                               shows: model.shows,
                               navigation: model.navigation)
        )
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
    }

    /// Still while stopped, rocking with its bars up while playing.
    private func followPlaybackState() {
        model.$playbackActive
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] active in
                guard let self else { return }
                active ? startAnimating() : showIdleIcon()
            }
            .store(in: &cancellables)
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            show()
        }
    }

    private func show() {
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

        // Without this the popover never becomes key, and every control in it
        // paints in its inactive state — Play comes up grey instead of blue.
        NSApp.activate(ignoringOtherApps: true)
        popover.contentViewController?.view.window?.makeKey()

        // `.transient` handles clicks within this app; a click landing in
        // another app's window needs the global monitor to catch it.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in self?.popover.performClose(nil) }
        }
    }

    private func stopWatchingForOutsideClicks() {
        guard let outsideClickMonitor else { return }
        NSEvent.removeMonitor(outsideClickMonitor)
        self.outsideClickMonitor = nil
    }

    // MARK: - NSPopoverDelegate

    nonisolated func popoverWillShow(_ notification: Notification) {
        // The popover reuses one hosting controller, so the view's onAppear
        // fires once for the life of the app. Per-open work belongs here.
        Task { @MainActor in model.dropdownWillOpen() }
    }

    nonisolated func popoverDidClose(_ notification: Notification) {
        Task { @MainActor in
            stopWatchingForOutsideClicks()
            model.dropdownDidClose()
        }
    }
}
