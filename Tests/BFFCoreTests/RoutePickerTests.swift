import AVKit
import XCTest
@testable import BFFCore

/// Pins the one thing that makes AirPlay work from an AppKit app on macOS:
/// the picker's `player` stays nil, always.
///
/// Attaching the AVPlayer is the obvious wiring and it is broken at the
/// platform level — the picker's checkboxes toggle and the audio never
/// leaves the Mac (Apple Developer Forums threads 708248 and 744128;
/// unacknowledged). Left nil, the picker routes the app's CoreMedia audio
/// as a whole, and this app has exactly one AVPlayer. Do not "fix" this
/// back; it shipped attached once and HomePod selection did nothing.
@MainActor
final class RoutePickerTests: XCTestCase {
    func testPickerIsNeverAttachedToAPlayer() {
        XCTAssertNil(RoutePickerView.makePicker().player)
    }

    func testPickerButtonIsBorderless() {
        XCTAssertFalse(RoutePickerView.makePicker().isRoutePickerButtonBordered)
    }
}
