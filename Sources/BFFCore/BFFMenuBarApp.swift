import SwiftUI

public struct BFFMenuBarApp: App {
    @StateObject private var model = AppModel()

    public init() {}

    public var body: some Scene {
        MenuBarExtra {
            MenuView(player: model.player, service: model.service, shows: model.shows)
        } label: {
            Image(nsImage: StatusIcon.image(active: model.playbackActive))
        }
        .menuBarExtraStyle(.window)
    }
}
