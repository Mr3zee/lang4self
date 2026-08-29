#!/usr/bin/swift

import AppKit
import Foundation

let output = CommandLine.arguments.dropFirst().first
    ?? "Apps/macOS/Lang4Self/Resources/AppIcon-1024.png"
let size = 1024
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: size,
    pixelsHigh: size,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else { fatalError("Could not create icon canvas") }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSColor.clear.setFill()
NSRect(x: 0, y: 0, width: size, height: size).fill()

let tile = NSBezierPath(roundedRect: NSRect(x: 62, y: 62, width: 900, height: 900), xRadius: 205, yRadius: 205)
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
shadow.shadowBlurRadius = 42
shadow.shadowOffset = NSSize(width: 0, height: -18)
shadow.set()
let gradient = NSGradient(
    starting: NSColor(calibratedRed: 0.10, green: 0.16, blue: 0.31, alpha: 1),
    ending: NSColor(calibratedRed: 0.24, green: 0.42, blue: 0.86, alpha: 1)
)!
gradient.draw(in: tile, angle: 58)
NSShadow().set()

// A warm speech bubble makes the dictation feature legible at small sizes.
let bubble = NSBezierPath(roundedRect: NSRect(x: 220, y: 425, width: 584, height: 390), xRadius: 112, yRadius: 112)
NSColor(calibratedRed: 1.00, green: 0.91, blue: 0.58, alpha: 1).setFill()
bubble.fill()
let tail = NSBezierPath()
tail.move(to: NSPoint(x: 474, y: 448))
tail.line(to: NSPoint(x: 532, y: 350))
tail.line(to: NSPoint(x: 598, y: 448))
tail.close()
tail.fill()

let text = "Ä" as NSString
let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .center
let attributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 250, weight: .heavy),
    .foregroundColor: NSColor(calibratedRed: 0.10, green: 0.16, blue: 0.31, alpha: 1),
    .paragraphStyle: paragraph
]
text.draw(in: NSRect(x: 220, y: 487, width: 584, height: 280), withAttributes: attributes)

// Open book: two clean page shapes and a bright center spine.
let paper = NSColor(calibratedRed: 0.97, green: 0.98, blue: 1.00, alpha: 1)
let leftPage = NSBezierPath()
leftPage.move(to: NSPoint(x: 142, y: 354))
leftPage.curve(to: NSPoint(x: 486, y: 274), controlPoint1: NSPoint(x: 270, y: 355), controlPoint2: NSPoint(x: 408, y: 328))
leftPage.line(to: NSPoint(x: 486, y: 130))
leftPage.curve(to: NSPoint(x: 142, y: 212), controlPoint1: NSPoint(x: 385, y: 179), controlPoint2: NSPoint(x: 265, y: 210))
leftPage.close()
paper.setFill()
leftPage.fill()

let rightPage = NSBezierPath()
rightPage.move(to: NSPoint(x: 538, y: 274))
rightPage.curve(to: NSPoint(x: 882, y: 354), controlPoint1: NSPoint(x: 616, y: 328), controlPoint2: NSPoint(x: 754, y: 355))
rightPage.line(to: NSPoint(x: 882, y: 212))
rightPage.curve(to: NSPoint(x: 538, y: 130), controlPoint1: NSPoint(x: 759, y: 210), controlPoint2: NSPoint(x: 639, y: 179))
rightPage.close()
rightPage.fill()

NSColor(calibratedRed: 0.99, green: 0.73, blue: 0.20, alpha: 1).setStroke()
let spine = NSBezierPath()
spine.lineWidth = 16
spine.lineCapStyle = .round
spine.move(to: NSPoint(x: 512, y: 137))
spine.line(to: NSPoint(x: 512, y: 285))
spine.stroke()

// Three gender-color page marks: masculine, feminine, neuter.
for (x, color) in [
    (330.0, NSColor.systemBlue),
    (512.0, NSColor.systemPink),
    (694.0, NSColor.systemGreen)
] {
    color.setFill()
    NSBezierPath(ovalIn: NSRect(x: x - 16, y: 205, width: 32, height: 32)).fill()
}

NSGraphicsContext.restoreGraphicsState()
guard let data = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Could not encode icon")
}
let outputURL = URL(fileURLWithPath: output)
try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
try data.write(to: outputURL)
print(outputURL.path)
