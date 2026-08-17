import AppKit

/// The Cool Rock menu bar icon.
///
/// Stopped, it's the plain mascot in full colour. Playing, it rocks gently
/// side to side with three equalizer bars beside it — the rock carries the
/// station's character, the bars say unambiguously that audio is running.
///
/// The playing frames are rendered once and cached, so the animation costs a
/// timer swapping a prepared bitmap rather than redrawing an SVG 15 times a
/// second. Never a template image: BFF.fm's colours are the point.
enum StatusIcon {
    static let pointSize = NSSize(width: 20, height: 20)

    // MARK: - Bar geometry
    //
    // The frame's width is derived from these rather than written down
    // separately: hard-coding it once left the last bar running 1.5pt past the
    // right edge, where it was silently clipped in half.

    private static let barCount = 3
    private static let barWidth: CGFloat = 2.5
    private static let barGap: CGFloat = 1.5
    private static let barsLeft = pointSize.width + 2
    private static let trailingMargin: CGFloat = 1

    static let barsRight = barsLeft
        + CGFloat(barCount) * barWidth
        + CGFloat(barCount - 1) * barGap

    /// Wide enough for the rock plus every bar, whole.
    static let playingSize = NSSize(width: barsRight + trailingMargin, height: 20)

    /// How far the rock tilts at the extremes of its sway.
    private static let tilt: CGFloat = 8
    /// One full sway, and one full pass of the bars.
    static let cycle: TimeInterval = 1.2
    static let frameCount = 18
    static var frameInterval: TimeInterval { cycle / Double(frameCount) }

    /// Where the bars sit when nothing is playing — present, but at rest.
    private static let restLevel = 0.28

    /// Shown while stopped: upright, full colour, bars down and still. Same
    /// size as a playing frame so the status item never changes width and the
    /// popover never gets re-anchored out from under the pointer.
    static let idle: NSImage = renderFrame(tilt: 0, levels: [restLevel, restLevel, restLevel])

    /// One sway of the rock with the bars running alongside, as a loop.
    static let playingFrames: [NSImage] = (0..<frameCount).map { index in
        let phase = Double(index) / Double(frameCount)
        return renderFrame(
            tilt: CGFloat(sin(phase * 2 * .pi)) * tilt,
            levels: (0..<3).map { level(atPhase: phase + Double($0) / 3) }
        )
    }

    /// sin swings -1...1; fold it so a bar never drops below its resting height.
    private static func level(atPhase phase: Double) -> Double {
        restLevel + (1 - restLevel) * (sin(phase * 2 * .pi) + 1) / 2
    }

    /// Prefers the copy inside the running app bundle so a shipped .app is
    /// self-contained. `Bundle.module`'s SwiftPM accessor falls back to an
    /// absolute `.build/` path and `fatalError`s when that is gone, so it is
    /// only touched when `Bundle.main` misses — i.e. `swift run` and tests.
    private static func loadSVG() -> NSImage? {
        if let url = Bundle.main.url(forResource: "coolrock", withExtension: "svg") {
            return NSImage(contentsOf: url)
        }
        return Bundle.module.url(forResource: "coolrock", withExtension: "svg")
            .flatMap(NSImage.init(contentsOf:))
    }

    private static func renderFrame(tilt degrees: CGFloat, levels: [Double]) -> NSImage {
        guard let svg = loadSVG() else { return fallback() }
        let image = NSImage(size: playingSize, flipped: false) { _ in
            drawRock(svg, tiltedBy: degrees)
            drawBars(levels)
            return true
        }
        image.isTemplate = false
        return image
    }

    /// Pivots near the base, the way something heavy actually rocks.
    private static func drawRock(_ svg: NSImage, tiltedBy degrees: CGFloat) {
        let pivot = NSPoint(x: pointSize.width / 2, y: pointSize.height * 0.16)
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: pivot.x, yBy: pivot.y)
        transform.rotate(byDegrees: degrees)
        transform.translateX(by: -pivot.x, yBy: -pivot.y)
        transform.concat()
        svg.draw(in: NSRect(origin: .zero, size: pointSize))
        NSGraphicsContext.restoreGraphicsState()
    }

    /// Three bars at the given levels. While playing each is a third of a
    /// cycle out of step with its neighbour, so they read as levels moving
    /// rather than as one block flashing.
    private static func drawBars(_ levels: [Double]) {
        let maxHeight = pointSize.height * 0.62
        let floor = pointSize.height * 0.14

        NSColor(srgbRed: 0x00 / 255, green: 0x9e / 255, blue: 1, alpha: 1).setFill()
        for (bar, level) in levels.enumerated() {
            let x = barsLeft + CGFloat(bar) * (barWidth + barGap)
            NSBezierPath(
                roundedRect: NSRect(x: x, y: floor, width: barWidth,
                                    height: maxHeight * CGFloat(level)),
                xRadius: barWidth / 2, yRadius: barWidth / 2
            ).fill()
        }
    }

    private static func fallback() -> NSImage {
        NSImage(systemSymbolName: "radio", accessibilityDescription: "BFF.FM – Menu Bar Frequencies Forever")
            ?? NSImage(size: pointSize)
    }
}
