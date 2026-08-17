// Draws the disk image backdrop: the arrow between where the app sits and
// where Applications sits, plus a one-line instruction.
//
// Drawn in code rather than committed as a PNG so the arrow cannot drift out
// of line with the icon positions — both read the same constants, and
// make-dmg.sh passes those same numbers to Finder. A hand-made image would go
// stale the first time the window is resized.
//
// Emits background.png and background@2x.png; make-dmg.sh folds them into one
// multi-resolution TIFF, which is how a DMG backdrop stays sharp on Retina.
//
// Usage: swift Scripts/dmg-background.swift <output-directory>

import AppKit
import Foundation

// Must match make-dmg.sh. Finder measures from the top-left of the window's
// content area; AppKit draws from the bottom-left, hence `flip` below.
//
// The width matches the content area exactly. The height deliberately does
// not: Finder draws a backdrop at its natural size anchored top-left, so an
// image taller than the content is cropped harmlessly while a shorter one
// leaves a white band along the bottom. The content area is only ever 340pt
// tall (a 400pt window frame less 34pt of title bar and 26pt of status bar),
// and the status bar refuses to stay hidden — so 420 covers every case,
// including a Mac where it does hide and the content grows to 366.
//
// Everything meaningful therefore lives in the top 340pt.
let imageWidth: CGFloat = 560
let imageHeight: CGFloat = 420
let guaranteedVisibleHeight: CGFloat = 340
let appCenter = CGPoint(x: 150, y: 160)
let applicationsCenter = CGPoint(x: 410, y: 160)
let iconSize: CGFloat = 100
let captionBaseline: CGFloat = 300

func flip(_ y: CGFloat) -> CGFloat { imageHeight - y }

func drawBackdrop() {
    NSColor(calibratedWhite: 0.96, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: imageWidth, height: imageHeight).fill()

    // A soft vertical gradient stops the flat fill reading as a rendering
    // failure on a large display.
    let gradient = NSGradient(colors: [
        NSColor(calibratedWhite: 0.99, alpha: 1),
        NSColor(calibratedWhite: 0.93, alpha: 1),
    ])
    // Run the gradient over the visible band only, so the cropped tail below
    // it stays the same tone as the band's end rather than banding visibly.
    gradient?.draw(in: NSRect(x: 0, y: flip(guaranteedVisibleHeight),
                              width: imageWidth, height: guaranteedVisibleHeight), angle: -90)
    NSColor(calibratedWhite: 0.93, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: imageWidth, height: flip(guaranteedVisibleHeight)).fill()
}

func drawArrow() {
    // Span the gap between the two icons, leaving breathing room at each end
    // so the arrow never appears to touch either one.
    let gap: CGFloat = 22
    let startX = appCenter.x + iconSize / 2 + gap
    let endX = applicationsCenter.x - iconSize / 2 - gap
    let y = flip(appCenter.y)

    let headLength: CGFloat = 26
    let headHalfHeight: CGFloat = 17
    let shaftThickness: CGFloat = 11

    NSColor(calibratedRed: 0.62, green: 0.65, blue: 0.70, alpha: 1).setFill()

    let shaft = NSBezierPath(roundedRect: NSRect(x: startX,
                                                 y: y - shaftThickness / 2,
                                                 width: endX - headLength - startX,
                                                 height: shaftThickness),
                             xRadius: shaftThickness / 2,
                             yRadius: shaftThickness / 2)
    shaft.fill()

    let head = NSBezierPath()
    head.move(to: CGPoint(x: endX, y: y))
    head.line(to: CGPoint(x: endX - headLength, y: y + headHalfHeight))
    head.line(to: CGPoint(x: endX - headLength, y: y - headHalfHeight))
    head.close()
    head.fill()
}

func drawCaption() {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center

    let caption = NSAttributedString(
        string: "Drag the app onto Applications to install",
        attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .regular),
            .foregroundColor: NSColor(calibratedWhite: 0.45, alpha: 1),
            .paragraphStyle: paragraph,
        ])

    // Below the icons and their labels. The app's name is long and wraps to
    // two lines under its icon, so this sits well clear of it and still inside
    // the band that is visible whether or not Finder shows a status bar.
    caption.draw(in: NSRect(x: 0, y: flip(captionBaseline) - 9, width: imageWidth, height: 22))
}

func render(scale: CGFloat) -> Data {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(imageWidth * scale),
        pixelsHigh: Int(imageHeight * scale),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0)
    else { fatalError("could not allocate a bitmap") }

    rep.size = NSSize(width: imageWidth, height: imageHeight)

    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
        fatalError("could not bind a drawing context")
    }
    NSGraphicsContext.current = context

    drawBackdrop()
    drawArrow()
    drawCaption()

    context.flushGraphics()
    guard let png = rep.representation(using: .png, properties: [:]) else {
        fatalError("could not encode PNG")
    }
    return png
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(
        Data("usage: dmg-background.swift <output-directory>\n".utf8))
    exit(1)
}
let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1])

for (scale, name) in [(CGFloat(1), "background.png"), (CGFloat(2), "background@2x.png")] {
    let url = outputDirectory.appendingPathComponent(name)
    do {
        try render(scale: scale).write(to: url)
    } catch {
        FileHandle.standardError.write(Data("error: \(error)\n".utf8))
        exit(1)
    }
    print("wrote \(url.path)")
}
