import AppKit

/// Holds the pieces that have to outlive any view: the model, and the status
/// item that puts the Cool Rock in the menu bar.
@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private lazy var model = AppModel()
    private var statusItem: StatusItemController?

    public nonisolated func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            statusItem = StatusItemController(model: model)
        }
    }
}
