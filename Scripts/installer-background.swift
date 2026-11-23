import AppKit

// Finder draws the draggable app, the Applications alias and both filenames.
// This artwork uses the same 640 × 300 point coordinate space as installer.json.
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let width = 640, height = 300
let centered = NSMutableParagraphStyle()
centered.alignment = .center
let ink = NSColor(srgbRed: 0.10, green: 0.14, blue: 0.21, alpha: 1)
let secondary = NSColor(srgbRed: 0.34, green: 0.39, blue: 0.45, alpha: 1)

func label(_ text: String, top: CGFloat, size: CGFloat, weight: NSFont.Weight, color: NSColor) {
    let font = NSFont.systemFont(ofSize: size, weight: weight)
    let box = NSRect(x: 0, y: CGFloat(height) - top - size * 1.5, width: CGFloat(width), height: size * 1.5)
    (text as NSString).draw(in: box, withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: centered])
}

for scale in [1, 2] {
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width * scale, pixelsHigh: height * scale,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0), let context = NSGraphicsContext(bitmapImageRep: bitmap)
    else { throw CocoaError(.fileWriteUnknown) }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
    NSColor(srgbRed: 0.973, green: 0.977, blue: 0.985, alpha: 1).setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: height)).fill()
    label("安装 Packpier", top: 18, size: 26, weight: .semibold, color: ink)
    label("将 Packpier 拖到 Applications", top: 54, size: 15, weight: .regular, color: ink)
    label("Drag Packpier to Applications.", top: 78, size: 13, weight: .regular, color: secondary)
    let arrow = NSBezierPath()
    let y: CGFloat = CGFloat(height) - 173
    arrow.move(to: NSPoint(x: 267, y: y))
    arrow.line(to: NSPoint(x: 373, y: y))
    arrow.move(to: NSPoint(x: 365, y: y + 8))
    arrow.line(to: NSPoint(x: 373, y: y))
    arrow.line(to: NSPoint(x: 365, y: y - 8))
    arrow.lineWidth = 2
    arrow.lineJoinStyle = .round
    arrow.lineCapStyle = .round
    NSColor(srgbRed: 0.15, green: 0.37, blue: 0.82, alpha: 1).setStroke()
    arrow.stroke()
    NSGraphicsContext.restoreGraphicsState()
    bitmap.size = NSSize(width: width, height: height)
    guard let tiff = bitmap.tiffRepresentation else { throw CocoaError(.fileWriteUnknown) }
    try tiff.write(to: output.appendingPathComponent("paper-\(scale)x.tiff"))
}
