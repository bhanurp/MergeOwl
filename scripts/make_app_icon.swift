import AppKit
import Foundation

// Deterministic packaging of the approved transparent artwork; no artistic edits.
guard CommandLine.arguments.count == 3,
      let source = NSImage(contentsOfFile: CommandLine.arguments[1]) else {
    fatalError("Usage: swift scripts/make_app_icon.swift <approved.png> <output.iconset>")
}
let directory = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSGraphicsContext.current?.imageInterpolation = .high
        let factor = min(CGFloat(pixels) / source.size.width, CGFloat(pixels) / source.size.height)
        let width = source.size.width * factor, height = source.size.height * factor
        let rect = NSRect(x: (CGFloat(pixels) - width) / 2, y: (CGFloat(pixels) - height) / 2, width: width, height: height)
        NSGraphicsContext.current?.cgContext.clear(CGRect(x: 0, y: 0, width: pixels, height: pixels))
        source.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
