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
        button.image = StatusIcon.image(active: model.playbackActive)
        button.imagePosition = .imageOnly
        button.toolTip = "BFF.fm"
        button.target = self
        button.action = #selector(togglePopover)
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.delegate = self
        let host = NSHostingController(
            rootView: MenuView(player: model.player,
                               service: model.service,
                               shows: model.shows)
        )
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
    }

    /// The icon is full colour while playing and dimmed while stopped.
    private func followPlaybackState() {
        model.$playbackActive
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] active in
                self?.statusItem.button?.image = StatusIcon.image(active: active)
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
        Task { @MainActor in model.service.setMenuOpen(true) }
    }

    nonisolated func popoverDidClose(_ notification: Notification) {
        Task { @MainActor in
            stopWatchingForOutsideClicks()
            model.service.setMenuOpen(false)
        }
    }
}
