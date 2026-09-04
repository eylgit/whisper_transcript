import AppKit

// Renders the app icon from an SF Symbol, so the repo carries no binary assets.
let outDir = CommandLine.arguments[1]
let iconset = outDir + "/Transcribe.iconset"
try? FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)

func render(pixels px: Int) -> Data? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }

    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let size = NSSize(width: px, height: px)
    let rect = NSRect(origin: .zero, size: size)
    let radius = CGFloat(px) * 0.2237      // macOS squircle-ish corner
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    NSGradient(colors: [
        NSColor(calibratedRed: 0.29, green: 0.47, blue: 0.88, alpha: 1),
        NSColor(calibratedRed: 0.12, green: 0.22, blue: 0.58, alpha: 1),
    ])?.draw(in: path, angle: -90)

    let config = NSImage.SymbolConfiguration(pointSize: CGFloat(px) * 0.5, weight: .medium)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    if let symbol = NSImage(systemSymbolName: "waveform", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let s = symbol.size
        symbol.draw(in: NSRect(x: (size.width - s.width) / 2, y: (size.height - s.height) / 2,
                               width: s.width, height: s.height))
    }
    NSGraphicsContext.current?.flushGraphics()
    return rep.representation(using: .png, properties: [:])
}

// iconutil requires exactly these names.
for (base, scale) in [(16,1),(16,2),(32,1),(32,2),(128,1),(128,2),(256,1),(256,2),(512,1),(512,2)] {
    guard let data = render(pixels: base * scale) else {
        FileHandle.standardError.write(Data("failed to render \(base)@\(scale)x\n".utf8)); continue
    }
    let suffix = scale == 1 ? "" : "@2x"
    let name = "icon_\(base)x\(base)\(suffix).png"
    try? data.write(to: URL(fileURLWithPath: "\(iconset)/\(name)"))
}
