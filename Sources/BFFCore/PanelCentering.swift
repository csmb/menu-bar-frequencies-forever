import AppKit
import SwiftUI

/// Centres the dropdown under the menu bar icon.
///
/// `MenuBarExtra(.window)` hangs its panel from the status item's left edge,
/// so a 280pt panel under a 23pt icon sits almost entirely off to one side.
/// Dropping this into the panel's background slides it back so the icon sits
/// over the middle of the panel, which is what makes the two read as one
/// control. If the status item can't be located the panel is left exactly
/// where AppKit put it.
///
/// AppKit re-anchors the panel every time its content resizes — artwork
/// finishing its download grows the panel and moves it back — so this keeps
/// watching and re-centres rather than positioning once.
struct PanelCentering: NSViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        schedule(from: view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        schedule(from: nsView, coordinator: context.coordinator)
    }

    private func schedule(from view: NSView, coordinator: Coordinator) {
        // The window isn't attached during make/update, so measure next turn.
        DispatchQueue.main.async {
            guard let panel = view.window else { return }
            coordinator.watch(panel, onChange: Self.center)
            Self.center(panel)
        }
    }

    private static func center(_ panel: NSWindow) {
        guard let statusItem = statusItemWindow,
              let screen = panel.screen ?? NSScreen.main
        else { return }

        var frame = panel.frame
        let margin: CGFloat = 8
        let limit = screen.visibleFrame
        frame.origin.x = min(
            max(statusItem.frame.midX - frame.width / 2, limit.minX + margin),
            limit.maxX - frame.width - margin
        )

        // Bail out once it's in place, so re-centring can't loop against the
        // move notification it causes.
        guard abs(frame.origin.x - panel.frame.origin.x) > 0.5 else { return }

        // `setFrame(_:display:)` is silently ignored by this window class —
        // it re-anchors itself to the status item. `setFrameOrigin` is not.
        panel.setFrameOrigin(NSPoint(x: frame.origin.x, y: frame.origin.y))
    }

    /// The window backing our `MenuBarExtra`'s status item. AppKit owns it, so
    /// there's no public handle — it is found by class among our own windows.
    private static var statusItemWindow: NSWindow? {
        NSApp.windows.first { $0.className == "NSStatusBarWindow" }
    }

    /// Keeps the resize/move observers alive for as long as the panel is up.
    final class Coordinator {
        private var tokens: [NSObjectProtocol] = []
        private weak var watched: NSWindow?

        func watch(_ panel: NSWindow, onChange: @escaping (NSWindow) -> Void) {
            guard watched !== panel else { return }
            cancel()
            watched = panel
            let names: [Notification.Name] = [
                NSWindow.didResizeNotification,
                NSWindow.didMoveNotification,
            ]
            tokens = names.map { name in
                NotificationCenter.default.addObserver(
                    forName: name, object: panel, queue: .main
                ) { [weak panel] _ in
                    guard let panel else { return }
                    onChange(panel)
                }
            }
        }

        private func cancel() {
            tokens.forEach(NotificationCenter.default.removeObserver)
            tokens.removeAll()
        }

        deinit { cancel() }
    }
}
