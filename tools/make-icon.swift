// Renders the app icon. Usage: swift tools/make-icon.swift Resources/AppIcon.icns
import AppKit

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    let tile = NSRect(x: s * 0.1, y: s * 0.1, width: s * 0.8, height: s * 0.8)
    let path = NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.225, yRadius: tile.width * 0.225)
    NSGradient(starting: NSColor(red: 0.93, green: 0.56, blue: 0.40, alpha: 1),
               ending: NSColor(red: 0.76, green: 0.32, blue: 0.22, alpha: 1))!.draw(in: path, angle: -90)

    // A gauge: track, filled arc, needle.
    let center = NSPoint(x: s / 2, y: s * 0.42)
    let radius = tile.width * 0.3
    let line = tile.width * 0.085
    func arc(from start: CGFloat, to end: CGFloat, color: NSColor) {
        let p = NSBezierPath()
        p.appendArc(withCenter: center, radius: radius, startAngle: start, endAngle: end, clockwise: true)
        p.lineWidth = line
        p.lineCapStyle = .round
        color.setStroke()
        p.stroke()
    }
    arc(from: 200, to: -20, color: NSColor.white.withAlphaComponent(0.35))
    arc(from: 200, to: 70, color: .white)
    let angle = 70 * CGFloat.pi / 180
    let needle = NSBezierPath()
    needle.move(to: center)
    needle.line(to: NSPoint(x: center.x + cos(angle) * radius * 0.68, y: center.y + sin(angle) * radius * 0.68))
    needle.lineWidth = line * 0.6
    needle.lineCapStyle = .round
    NSColor.white.setStroke()
    needle.stroke()
    NSColor.white.setFill()
    NSBezierPath(ovalIn: NSRect(x: center.x - line * 0.7, y: center.y - line * 0.7, width: line * 1.4, height: line * 1.4)).fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let output = URL(fileURLWithPath: CommandLine.arguments[1])
let iconset = FileManager.default.temporaryDirectory.appending(path: "AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    try render(size).write(to: iconset.appending(path: "icon_\(size)x\(size).png"))
    try render(size * 2).write(to: iconset.appending(path: "icon_\(size)x\(size)@2x.png"))
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()
