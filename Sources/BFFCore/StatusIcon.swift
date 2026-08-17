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

    /// Playing is wider — the bars sit to the right of the rock.
    static let playingSize = NSSize(width: 31, height: 20)

    /// How far the rock tilts at the extremes of its sway.
    private static let tilt: CGFloat = 8
    /// One full sway, and one full pass of the bars.
    static let cycle: TimeInterval = 1.2
    static let frameCount = 18
    static var frameInterval: TimeInterval { cycle / Double(frameCount) }

    /// Shown while stopped: full colour, perfectly still.
    static let idle: NSImage = renderIdle()

    /// One sway of the rock with the bars running alongside, as a loop.
    static let playingFrames: [NSImage] = (0..<frameCount).map(renderPlayingFrame)

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

    private static func renderIdle() -> NSImage {
        guard let svg = loadSVG() else { return fallback() }
        let image = NSImage(size: pointSize, flipped: false) { rect in
            svg.draw(in: rect)
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func renderPlayingFrame(_ index: Int) -> NSImage {
        guard let svg = loadSVG() else { return fallback() }
        let phase = Double(index) / Double(frameCount)

        let image = NSImage(size: playingSize, flipped: false) { _ in
            drawRock(svg, tiltedBy: CGFloat(sin(phase * 2 * .pi)) * tilt)
            drawBars(atPhase: phase)
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

    /// Three bars, each a third of a cycle out of step with its neighbour, so
    /// they read as levels moving rather than as one block flashing.
    private static func drawBars(atPhase phase: Double) {
        let width: CGFloat = 2.5
        let gap: CGFloat = 1.5
        let maxHeight = pointSize.height * 0.62
        let floor = pointSize.height * 0.14
        let left = pointSize.width + 2

        NSColor(srgbRed: 0x00 / 255, green: 0x9e / 255, blue: 1, alpha: 1).setFill()
        for bar in 0..<3 {
            let offset = phase + Double(bar) / 3
            // sin swings -1...1; fold it to 0.28...1 so a bar never vanishes.
            let level = 0.28 + 0.72 * (sin(offset * 2 * .pi) + 1) / 2
            let height = maxHeight * CGFloat(level)
            let x = left + CGFloat(bar) * (width + gap)
            NSBezierPath(
                roundedRect: NSRect(x: x, y: floor, width: width, height: height),
                xRadius: width / 2, yRadius: width / 2
            ).fill()
        }
    }

    private static func fallback() -> NSImage {
        NSImage(systemSymbolName: "radio", accessibilityDescription: "BFF.fm")
            ?? NSImage(size: pointSize)
    }
}
