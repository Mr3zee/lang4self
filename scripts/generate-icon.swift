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

// A single German letter keeps the mark direct and legible at every icon size.
let tile = NSBezierPath(
    roundedRect: NSRect(x: 62, y: 62, width: 900, height: 900),
    xRadius: 205,
    yRadius: 205
)
let ink = NSColor(srgbRed: 0.09, green: 0.16, blue: 0.14, alpha: 1)
let paper = NSColor(srgbRed: 0.95, green: 0.93, blue: 0.87, alpha: 1)
ink.setFill()
tile.fill()

let text = "Ä" as NSString
let font = NSFont.systemFont(ofSize: 570, weight: .black)
let attributes: [NSAttributedString.Key: Any] = [
    .font: font,
    .foregroundColor: paper
]
let textSize = text.size(withAttributes: attributes)
text.draw(
    at: NSPoint(
        x: (CGFloat(size) - textSize.width) / 2,
        y: (CGFloat(size) - textSize.height) / 2 - 18
    ),
    withAttributes: attributes
)

NSGraphicsContext.restoreGraphicsState()
guard let data = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Could not encode icon")
}
let outputURL = URL(fileURLWithPath: output)
try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
try data.write(to: outputURL)
print(outputURL.path)
