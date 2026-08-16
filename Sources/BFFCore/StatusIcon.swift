import AppKit
import CoreImage

/// The Cool Rock menu bar icon: full color while playing, desaturated and
/// dimmed while stopped. Rendered from the bundled SVG so it stays sharp on
/// Retina displays; never a template image (we want BFF.fm's colors).
enum StatusIcon {
    nonisolated static let pointSize = NSSize(width: 20, height: 20)

    nonisolated static let active: NSImage = renderBase()
    nonisolated static let inactive: NSImage = renderDimmed()

    static func image(active isActive: Bool) -> NSImage {
        isActive ? active : inactive
    }

    private static func loadSVG() -> NSImage? {
        guard let url = Bundle.module.url(forResource: "coolrock", withExtension: "svg") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }

    private static func renderBase() -> NSImage {
        guard let svg = loadSVG() else { return fallback() }
        let image = NSImage(size: pointSize, flipped: false) { rect in
            svg.draw(in: rect)
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func renderDimmed() -> NSImage {
        guard let svg = loadSVG() else { return fallback() }
        // Rasterize at 2x, drop saturation to zero, then draw at reduced alpha.
        let pixels = 40
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: rep) else {
            return renderBase()
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        svg.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()

        guard let cgImage = rep.cgImage else { return renderBase() }
        let gray = CIImage(cgImage: cgImage)
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0.0])
        guard let grayCG = CIContext().createCGImage(gray, from: gray.extent) else {
            return renderBase()
        }
        let grayImage = NSImage(cgImage: grayCG, size: pointSize)

        let dimmed = NSImage(size: pointSize, flipped: false) { rect in
            grayImage.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 0.45)
            return true
        }
        dimmed.isTemplate = false
        return dimmed
    }

    private static func fallback() -> NSImage {
        NSImage(systemSymbolName: "radio", accessibilityDescription: "BFF.fm")
            ?? NSImage(size: pointSize)
    }
}
