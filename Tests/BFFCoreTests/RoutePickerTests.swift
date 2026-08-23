import AVFoundation
import AVKit
import XCTest
@testable import BFFCore

/// The AirPlay picker routes whatever `player` it is pointed at — and this
/// app builds a brand new AVPlayer on every play() and every reconnect, so
/// the pointing has to be re-done each time. These pin that lifecycle.
@MainActor
final class RoutePickerTests: XCTestCase {
    final class Built { var last: AVPlayer? }

    private func makeController(built: Built) -> PlayerController {
        PlayerController(defaults: UserDefaults(suiteName: "route-picker-tests")!,
                         workspaceNotifications: NotificationCenter(),
                         makePlayer: { _ in
                             let player = AVPlayer()
                             built.last = player
                             return player
                         })
    }

    func testPlayHandsTheNewPlayerToTheAttachedPicker() {
        let built = Built()
        let controller = makeController(built: built)
        let picker = AVRoutePickerView()
        controller.attachRoutePicker(picker)
        controller.play()
        XCTAssertNotNil(built.last)
        XCTAssertTrue(picker.player === built.last)
        controller.stop()
    }

    func testStopClearsThePickersPlayer() {
        let built = Built()
        let controller = makeController(built: built)
        let picker = AVRoutePickerView()
        controller.attachRoutePicker(picker)
        controller.play()
        controller.stop()
        XCTAssertNil(picker.player)
    }

    /// The view attaches whenever SwiftUI makes it, which can be after the
    /// user already pressed Play.
    func testAttachAfterPlayAdoptsTheCurrentPlayer() {
        let built = Built()
        let controller = makeController(built: built)
        controller.play()
        let picker = AVRoutePickerView()
        controller.attachRoutePicker(picker)
        XCTAssertTrue(picker.player === built.last)
        controller.stop()
    }
}
