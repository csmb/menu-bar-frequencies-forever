import AppKit
import XCTest
@testable import BFFCore

@MainActor
final class PanelBackgroundTests: XCTestCase {
    private func rgba(in appearance: NSAppearance.Name) -> (Int, Int, Int, Int) {
        var out = (0, 0, 0, 0)
        NSAppearance(named: appearance)!.performAsCurrentDrawingAppearance {
            let c = MenuView.backgroundColor.usingColorSpace(.sRGB)!
            out = (Int((c.redComponent * 255).rounded()),
                   Int((c.greenComponent * 255).rounded()),
                   Int((c.blueComponent * 255).rounded()),
                   Int((c.alphaComponent * 255).rounded()))
        }
        return out
    }

    func testLightIsOpaqueEFEFEF() {
        let (r, g, b, a) = rgba(in: .aqua)
        XCTAssertEqual([r, g, b, a], [0xef, 0xef, 0xef, 0xff])
    }

    func testDarkIs252525AtBFAlpha() {
        let (r, g, b, a) = rgba(in: .darkAqua)
        XCTAssertEqual([r, g, b, a], [0x25, 0x25, 0x25, 0xbf])
    }

    func testTheTwoAppearancesActuallyDiffer() {
        XCTAssertNotEqual(rgba(in: .aqua).0, rgba(in: .darkAqua).0)
    }
}
