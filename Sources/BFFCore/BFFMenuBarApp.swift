import AppKit

/// The entry point, and it is AppKit's: the menu bar item and its dropdown
/// are AppKit, owned by `AppDelegate` — see `StatusItemController` for why —
/// and SwiftUI only draws the dropdown's contents.
///
/// This used to be a SwiftUI `App`, which must declare a scene, and the only
/// one there was to declare was an empty `Settings`. On macOS 27 that blank
/// window opened by itself whenever the app was launched from Finder or
/// `open` — so a first launch from the disk image greeted people with it —
/// and ⌘, opened it any time. With no SwiftUI scene, nothing can.
public enum BFFMenuBarApp {
    /// Called from `main.swift`, whose top-level code runs on the main thread
    /// without being main-actor code in Swift 5 mode — hence the assertion
    /// rather than an annotation the call site could not satisfy.
    public static func main() {
        MainActor.assumeIsolated {
            let app = NSApplication.shared
            let delegate = AppDelegate()
            app.delegate = delegate
            app.mainMenu = mainMenu()
            // `delegate` is weak on NSApplication; `run()` never returns, but
            // say what keeps the delegate alive rather than lean on that.
            withExtendedLifetime(delegate) { app.run() }
        }
    }

    /// Never shown — the app is `LSUIElement` — but it is where ⌘Q comes from
    /// while the dropdown has focus, as it did when SwiftUI built the menu.
    @MainActor
    private static func mainMenu() -> NSMenu {
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit",
                        action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        let menu = NSMenu()
        menu.addItem(appItem)
        return menu
    }
}
