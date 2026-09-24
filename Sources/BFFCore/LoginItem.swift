import ServiceManagement

/// The one piece of the system this app changes. `SMAppService` already has
/// this shape; tests stand in a fake so they never register the test runner.
protocol LoginItemService: AnyObject {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

extension SMAppService: LoginItemService {}

/// Launch at Login as the system has it, not as the view last left it. The
/// popover keeps one hosting controller for the app's life, so a value the
/// view read when it was built was read once, ever — turn the setting off in
/// System Settings and the toggle went on showing it on. `AppModel` calls
/// `refresh()` on every open of the dropdown instead.
@MainActor
final class LoginItem: ObservableObject {
    @Published private(set) var isEnabled: Bool
    private let service: LoginItemService

    init(service: LoginItemService = SMAppService.mainApp) {
        self.service = service
        isEnabled = service.status == .enabled
    }

    func refresh() {
        isEnabled = service.status == .enabled
    }

    /// Asks the system for the change, then shows what it actually has —
    /// which, when it refuses, is not what was asked for.
    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            // Refused; the refresh below shows what the system kept.
        }
        refresh()
    }
}
