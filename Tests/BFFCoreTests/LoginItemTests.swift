import ServiceManagement
import XCTest
@testable import BFFCore

@MainActor
final class LoginItemTests: XCTestCase {
    /// The popover keeps one hosting controller for the app's life, so a value
    /// the view read when it was built was read once, ever. Turn Launch at
    /// Login off in System Settings and the toggle kept showing on for the
    /// rest of the session. Each open of the dropdown asks the system again.
    func testEachOpenShowsWhatTheSystemHasNow() {
        let system = FakeLoginItems(status: .enabled)
        let model = AppModel(service: NowPlayingService(provider: Self.unreachable),
                             shows: ShowDirectory(provider: Self.unreachable),
                             loginItem: LoginItem(service: system))
        model.dropdownWillOpen()
        XCTAssertTrue(model.loginItem.isEnabled)
        model.dropdownDidClose()

        system.status = .notRegistered              // switched off in System Settings
        model.dropdownWillOpen()
        XCTAssertFalse(model.loginItem.isEnabled)
    }

    /// A change the system refuses must not leave the toggle showing it.
    func testARefusedChangeShowsWhatTheSystemKept() {
        let system = FakeLoginItems(status: .notRegistered)
        system.refusal = CocoaError(.featureUnsupported)
        let item = LoginItem(service: system)
        item.setEnabled(true)
        XCTAssertFalse(item.isEnabled)
    }

    private static let unreachable: DataProvider = { _ in throw URLError(.notConnectedToInternet) }
}

/// Stands in for `SMAppService.mainApp`, so no test registers the test runner
/// as a login item.
final class FakeLoginItems: LoginItemService {
    var status: SMAppService.Status
    var refusal: Error?

    init(status: SMAppService.Status) { self.status = status }

    func register() throws {
        if let refusal { throw refusal }
        status = .enabled
    }

    func unregister() throws {
        if let refusal { throw refusal }
        status = .notRegistered
    }
}
