import XCTest
@testable import BFFCore

final class StatusIconTests: XCTestCase {
    func testIconsRenderAtMenuBarSize() {
        XCTAssertEqual(StatusIcon.active.size, StatusIcon.pointSize)
        XCTAssertEqual(StatusIcon.inactive.size, StatusIcon.pointSize)
    }

    func testActiveAndInactiveAreDistinctNonTemplateImages() {
        XCTAssertFalse(StatusIcon.active === StatusIcon.inactive)
        XCTAssertFalse(StatusIcon.active.isTemplate)
        XCTAssertFalse(StatusIcon.inactive.isTemplate)
    }

    func testImageSelectionFollowsPlaybackState() {
        XCTAssertTrue(StatusIcon.image(active: true) === StatusIcon.active)
        XCTAssertTrue(StatusIcon.image(active: false) === StatusIcon.inactive)
    }
}
