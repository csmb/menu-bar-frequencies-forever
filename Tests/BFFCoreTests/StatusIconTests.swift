import AppKit
import XCTest
@testable import BFFCore

final class StatusIconTests: XCTestCase {
    /// Idle and playing must be the same size. A status item that changes
    /// width on play/stop shoves the menu bar around and drags the open
    /// popover sideways with it.
    func testIdleAndPlayingAreTheSameSize() {
        XCTAssertEqual(StatusIcon.idle.size, StatusIcon.playingSize)
        for frame in StatusIcon.playingFrames {
            XCTAssertEqual(frame.size, StatusIcon.playingSize)
        }
    }

    func testTheFrameIsWiderThanTheRockToFitTheBars() {
        XCTAssertGreaterThan(StatusIcon.playingSize.width, StatusIcon.pointSize.width)
    }

    /// The last bar used to run 1.5pt past the right edge and get sliced in
    /// half. Arithmetic alone missed it, so this reads the rendered pixels:
    /// the final column of the frame must be empty.
    func testNoBarIsClippedByTheRightEdge() throws {
        XCTAssertGreaterThanOrEqual(StatusIcon.playingSize.width, StatusIcon.barsRight,
                                    "the frame is narrower than the bars it has to hold")

        for (index, frame) in StatusIcon.playingFrames.enumerated() {
            let rep = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(frame.tiffRepresentation)))
            let lastColumn = rep.pixelsWide - 1
            var opaqueFound = false
            for y in 0..<rep.pixelsHigh {
                if let colour = rep.colorAt(x: lastColumn, y: y), colour.alphaComponent > 0.05 {
                    opaqueFound = true
                    break
                }
            }
            XCTAssertFalse(opaqueFound,
                           "frame \(index) paints its right-most column — a bar is being clipped")
        }
    }

    /// Stopped shows the bars, so idle can't just be the bare rock.
    func testIdleStillDrawsTheBars() throws {
        let whole = try pixels(of: StatusIcon.idle)
        let rockOnly = try rockRegion(of: StatusIcon.idle)
        XCTAssertNotEqual(whole, rockOnly)
    }

    /// Idle is upright and at rest, so it is not any of the moving frames.
    func testIdleIsStillerThanEveryPlayingFrame() throws {
        let idle = try pixels(of: StatusIcon.idle)
        for frame in StatusIcon.playingFrames {
            XCTAssertNotEqual(idle, try pixels(of: frame))
        }
    }

    func testNothingIsATemplateImage() {
        // Template images are flattened to a single colour, which would throw
        // away the whole reason for using BFF.fm's artwork.
        XCTAssertFalse(StatusIcon.idle.isTemplate)
        XCTAssertTrue(StatusIcon.playingFrames.allSatisfy { !$0.isTemplate })
    }

    func testThereIsAWholeCycleOfFrames() {
        XCTAssertEqual(StatusIcon.playingFrames.count, StatusIcon.frameCount)
        XCTAssertEqual(StatusIcon.frameInterval * Double(StatusIcon.frameCount),
                       StatusIcon.cycle, accuracy: 0.0001)
    }

    /// The frames have to actually differ — a loop of identical bitmaps would
    /// pass every size and count check above and animate nothing.
    func testFramesDifferFromOneAnother() throws {
        let frames = StatusIcon.playingFrames
        let quarter = try XCTUnwrap(frames[safe: frames.count / 4])
        let half = try XCTUnwrap(frames[safe: frames.count / 2])
        XCTAssertNotEqual(try pixels(of: frames[0]), try pixels(of: quarter))
        XCTAssertNotEqual(try pixels(of: quarter), try pixels(of: half))
    }

    /// The rock has to tilt on its own account. Comparing whole frames can't
    /// show that — the bars alone differ between every pair — so this looks
    /// only at the rock's half of the image.
    func testTheRockItselfTilts() throws {
        let frames = StatusIcon.playingFrames
        let upright = try rockRegion(of: frames[0])
        let tilted = try rockRegion(of: try XCTUnwrap(frames[safe: frames.count / 4]))
        XCTAssertNotEqual(upright, tilted, "the rock is not rotating, only the bars are")
    }

    /// Half a cycle along, the sway has passed back through upright.
    func testTheSwayIsSymmetric() throws {
        let frames = StatusIcon.playingFrames
        let start = try rockRegion(of: frames[0])
        let halfway = try rockRegion(of: try XCTUnwrap(frames[safe: frames.count / 2]))
        XCTAssertEqual(start, halfway, "the rock should be upright at both ends of a sway")
    }

    private func pixels(of image: NSImage) throws -> Data {
        try XCTUnwrap(image.tiffRepresentation)
    }

    /// The left `pointSize.width` of a frame, where the rock is drawn.
    private func rockRegion(of image: NSImage) throws -> Data {
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let rep = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        let scale = CGFloat(rep.pixelsWide) / image.size.width
        let width = Int(StatusIcon.pointSize.width * scale)
        let cropped = NSImage(size: NSSize(width: width, height: rep.pixelsHigh))
        cropped.lockFocus()
        rep.draw(in: NSRect(x: 0, y: 0, width: rep.pixelsWide, height: rep.pixelsHigh))
        cropped.unlockFocus()
        return try XCTUnwrap(cropped.tiffRepresentation)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
