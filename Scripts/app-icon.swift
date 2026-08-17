// Centres the Cool Rock inside the app icon canvas.
//
// qlmanage rasterizes coolrock.svg faithfully, but the artwork does not fill
// its own viewBox evenly — there is noticeably more empty space below and to
// the right of the rock than above and left. Fed straight to iconutil that
// offset becomes the app icon's offset, and macOS 26 then composites the whole
// thing onto its rounded tile, where the rock sits visibly high.
//
// So: find what is actually drawn by scanning alpha, scale that to a fixed
// share of the canvas, and centre it. Measuring beats trusting the viewBox,
// because the SVG's bounds and its ink are not the same rectangle.
//
// Usage: swift Scripts/app-icon.swift <rasterized.png> <output.png>

import AppKit
import Foundation

// How much of the canvas the artwork spans on its longer axis. macOS leaves
// app icons some breathing room inside their tile; filling the square edge to
// edge looks oversized next to everything else in /Applications.
let coverage: CGFloat = 0.86

func loadBitmap(_ path: String) -> NSBitmapImageRep {
    guard let data = FileManager.default.contents(atPath: path),
          let rep = NSBitmapImageRep(data: data)
    else { fatalError("could not read \(path)") }
    return rep
}

/// The rectangle actually covered by artwork.
///
/// Measured against the backdrop colour rather than alpha: qlmanage composites
/// the SVG onto opaque white, so every pixel is alpha 255 and an alpha scan
/// reports the whole canvas as content. That silently produces a no-op crop,
/// which is exactly the bug this file exists to fix.
func contentBounds(_ rep: NSBitmapImageRep, backdrop: (UInt8, UInt8, UInt8)) -> NSRect {
    let width = rep.pixelsWide, height = rep.pixelsHigh
    var minX = width, minY = height, maxX = -1, maxY = -1

    guard let data = rep.bitmapData else { fatalError("no bitmap data") }
    let bytesPerRow = rep.bytesPerRow
    let samples = rep.samplesPerPixel
    // Generous enough to ignore JPEG-ish noise and antialiasing haze, tight
    // enough to catch the rock's pale headphone cushions against white.
    let tolerance = 12

    func differs(_ p: UnsafeMutablePointer<UInt8>) -> Bool {
        if samples >= 4 && p[samples - 1] < 8 { return false }   // fully transparent
        return abs(Int(p[0]) - Int(backdrop.0)) > tolerance
            || abs(Int(p[1]) - Int(backdrop.1)) > tolerance
            || abs(Int(p[2]) - Int(backdrop.2)) > tolerance
    }

    for y in 0..<height {
        let row = data + y * bytesPerRow
        for x in 0..<width where differs(row + x * samples) {
            if x < minX { minX = x }
            if x > maxX { maxX = x }
            if y < minY { minY = y }
            if y > maxY { maxY = y }
        }
    }

    guard maxX >= minX, maxY >= minY else { fatalError("image has no artwork on its backdrop") }
    return NSRect(x: CGFloat(minX), y: CGFloat(minY),
                  width: CGFloat(maxX - minX + 1), height: CGFloat(maxY - minY + 1))
}

guard CommandLine.arguments.count == 3 else {
    FileHandle.standardError.write(
        Data("usage: app-icon.swift <rasterized.png> <output.png>\n".utf8))
    exit(1)
}

let source = loadBitmap(CommandLine.arguments[1])
let side = CGFloat(max(source.pixelsWide, source.pixelsHigh))

// Whatever fills the corner is the backdrop — white here, but read it rather
// than assume it, so a change to the artwork does not quietly break the crop.
let corner = source.bitmapData!
let backdrop = (corner[0], corner[1], corner[2])
let ink = contentBounds(source, backdrop: backdrop)

// Report it: this is the number that explains why the icon looked off, and it
// should stay roughly stable. A sudden change means the artwork changed.
let insetTop = ink.minY
let insetBottom = CGFloat(source.pixelsHigh) - ink.maxY
print(String(format: "ink %.0fx%.0f at (%.0f, %.0f) in %.0f square",
             ink.width, ink.height, ink.minX, ink.minY, side))
print(String(format: "  source margins — top %.0f, bottom %.0f, left %.0f, right %.0f",
             insetTop, insetBottom, ink.minX, CGFloat(source.pixelsWide) - ink.maxX))

let scale = (side * coverage) / max(ink.width, ink.height)
let drawnWidth = ink.width * scale
let drawnHeight = ink.height * scale
let destination = NSRect(x: (side - drawnWidth) / 2,
                         y: (side - drawnHeight) / 2,
                         width: drawnWidth,
                         height: drawnHeight)

guard let canvas = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(side), pixelsHigh: Int(side),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
else { fatalError("could not allocate the canvas") }
canvas.size = NSSize(width: side, height: side)

NSGraphicsContext.saveGraphicsState()
guard let context = NSGraphicsContext(bitmapImageRep: canvas) else {
    fatalError("could not bind a drawing context")
}
NSGraphicsContext.current = context
context.imageInterpolation = .high

// Repaint the backdrop first: the crop is being moved, and without this the
// area it vacated would come out transparent instead of matching.
NSColor(calibratedRed: CGFloat(backdrop.0) / 255,
        green: CGFloat(backdrop.1) / 255,
        blue: CGFloat(backdrop.2) / 255,
        alpha: 1).setFill()
NSRect(x: 0, y: 0, width: side, height: side).fill()

// AppKit's origin is bottom-left and inkBounds counted rows from the top, so
// the crop rectangle has to be flipped before it means the same thing here.
let crop = NSRect(x: ink.minX,
                  y: CGFloat(source.pixelsHigh) - ink.maxY - 1,
                  width: ink.width,
                  height: ink.height)
source.draw(in: destination, from: crop, operation: .sourceOver,
            fraction: 1, respectFlipped: false, hints: [.interpolation: NSNumber(value: NSImageInterpolation.high.rawValue)])

context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

guard let png = canvas.representation(using: .png, properties: [:]) else {
    fatalError("could not encode PNG")
}
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
print(String(format: "  centred %.0fx%.0f — margins now %.0f top and bottom, %.0f left and right",
             drawnWidth, drawnHeight, destination.minY, destination.minX))
