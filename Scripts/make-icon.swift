#!/usr/bin/env swift
import AppKit

// Draws a simple, friendly Yank app icon (rounded clipboard glyph on a
// gradient) and writes PNGs at every size an .icns needs.
func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let ctx = NSGraphicsContext.current!.cgContext

    // Background gradient.
    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let radius = size * 0.225
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    path.addClip()
    let colors = [NSColor(calibratedRed: 0.36, green: 0.42, blue: 0.96, alpha: 1).cgColor,
                  NSColor(calibratedRed: 0.55, green: 0.30, blue: 0.92, alpha: 1).cgColor]
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: colors as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: .zero,
                           end: CGPoint(x: size, y: size), options: [])

    // Clipboard glyph drawn with an SF Symbol for crispness.
    let config = NSImage.SymbolConfiguration(pointSize: size * 0.5, weight: .semibold)
    if let symbol = NSImage(systemSymbolName: "doc.on.clipboard.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let s = size * 0.5
        let origin = NSPoint(x: (size - s) / 2, y: (size - s) / 2)
        let tinted = NSImage(size: NSSize(width: s, height: s))
        tinted.lockFocus()
        symbol.draw(in: NSRect(x: 0, y: 0, width: s, height: s))
        NSColor.white.set()
        NSRect(x: 0, y: 0, width: s, height: s).fill(using: .sourceAtop)
        tinted.unlockFocus()
        tinted.draw(in: NSRect(origin: origin, size: NSSize(width: s, height: s)))
    }

    image.unlockFocus()
    return image
}

func png(_ image: NSImage, _ pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                              isPlanar: false, colorSpaceName: .deviceRGB,
                              bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let iconset = "\(outDir)/Yank.iconset"
try? FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)

let sizes: [(Int, String)] = [
    (16, "icon_16x16"), (32, "icon_16x16@2x"),
    (32, "icon_32x32"), (64, "icon_32x32@2x"),
    (128, "icon_128x128"), (256, "icon_128x128@2x"),
    (256, "icon_256x256"), (512, "icon_256x256@2x"),
    (512, "icon_512x512"), (1024, "icon_512x512@2x"),
]
for (px, name) in sizes {
    let img = drawIcon(size: CGFloat(px))
    let data = png(img, px)
    try! data.write(to: URL(fileURLWithPath: "\(iconset)/\(name).png"))
}
print("wrote \(iconset)")
