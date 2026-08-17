import SwiftUI

/// The menu bar item and its dropdown are AppKit, owned by `AppDelegate` —
/// see `StatusItemController` for why. SwiftUI is still the entry point and
/// still draws the dropdown's contents.
public struct BFFMenuBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    public init() {}

    public var body: some Scene {
        // `App` needs a scene, but this app has no windows of its own.
        Settings { EmptyView() }
    }
}
