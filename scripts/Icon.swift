import AppKit

let destination = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: destination, withIntermediateDirectories: true)
func rounded(_ rect: NSRect, _ radius: CGFloat, _ color: NSColor) {
    color.setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
}
for size in [16, 32, 128, 256, 512] {
    for density in [1, 2] {
        let pixels = size * density
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let transform = NSAffineTransform()
        transform.scale(by: CGFloat(pixels) / 1024)
        transform.concat()
        let body = NSBezierPath(roundedRect: NSRect(x: 40, y: 40, width: 944, height: 944), xRadius: 210, yRadius: 210)
        NSGradient(starting: NSColor(calibratedRed: 0.19, green: 0.23, blue: 0.55, alpha: 1), ending: NSColor(calibratedRed: 0.05, green: 0.08, blue: 0.22, alpha: 1))!.draw(in: body, angle: -90)
        rounded(NSRect(x: 176, y: 300, width: 680, height: 460), 42, NSColor(calibratedWhite: 0.06, alpha: 1))
        let screen = NSBezierPath(roundedRect: NSRect(x: 197, y: 323, width: 638, height: 414), xRadius: 24, yRadius: 24)
        NSGradient(starting: NSColor(calibratedRed: 0.40, green: 0.38, blue: 0.96, alpha: 1), ending: NSColor(calibratedRed: 0.22, green: 0.83, blue: 0.79, alpha: 1))!.draw(in: screen, angle: -25)
        rounded(NSRect(x: 464, y: 218, width: 94, height: 82), 12, NSColor(calibratedWhite: 0.70, alpha: 1))
        rounded(NSRect(x: 377, y: 205, width: 270, height: 24), 12, NSColor(calibratedWhite: 0.87, alpha: 1))
        rounded(NSRect(x: 222, y: 380, width: 66, height: 285), 22, NSColor.white.withAlphaComponent(0.65))
        for (index, color) in [NSColor.systemBlue, .white, .systemOrange, .systemPurple, .systemMint].enumerated() {
            rounded(NSRect(x: 234, y: 396 + CGFloat(index) * 51, width: 42, height: 42), 11, color)
        }
        NSGraphicsContext.restoreGraphicsState()
        let suffix = density == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: destination).appending(path: "icon_\(size)x\(size)\(suffix).png"))
    }
}
