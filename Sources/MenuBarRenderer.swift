import AppKit

struct MenuBarEntry {
    var label: String
    /// The value picked by the "Menu bar shows" setting.
    var percent: Double?
    var session: Double?
    var weekly: Double?
    var resetsAt: Date?
    var signedOut: Bool
    var stale: Bool
}

enum MenuBarRenderer {
    static func color(for percent: Double) -> NSColor {
        percent >= Double(Prefs.criticalThreshold) ? .systemRed
            : percent >= Double(Prefs.warnThreshold) ? .systemOrange : .systemGreen
    }

    static func countdown(to date: Date?, now: Date) -> String? {
        guard let seconds = date?.timeIntervalSince(now), seconds > 0 else { return nil }
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        if seconds < 86_400 { return "\(Int(seconds / 3600))h" + String(format: "%02d", Int(seconds) % 3600 / 60) }
        return "\(Int(seconds / 86_400))d"
    }

    static func text(_ entries: [MenuBarEntry], showLabels: Bool, showCountdown: Bool, markStale: Bool, now: Date) -> String {
        guard !entries.isEmpty else { return "✳ Claude" }
        let parts = entries.map { entry -> String in
            var value: String
            if entry.signedOut {
                value = "!"
            } else if let percent = entry.percent {
                value = (markStale && entry.stale ? "~" : "") + "\(Int(percent.rounded()))%"
                if showCountdown, let left = countdown(to: entry.resetsAt, now: now) { value += " " + left }
            } else {
                value = "–"
            }
            return showLabels ? "\(entry.label) \(value)" : value
        }
        return "✳ " + parts.joined(separator: "  ")
    }

    private enum Piece {
        case text(String, NSFont)
        case bars(session: Double?, weekly: Double?)
        case ring(Double?)

        var width: CGFloat {
            switch self {
            case .text(let string, let font): ceil((string as NSString).size(withAttributes: [.font: font]).width)
            case .bars: 20
            case .ring: 15
            }
        }
    }

    static func image(_ entries: [MenuBarEntry], style: MenuBarStyle, showLabels: Bool,
                      showCountdown: Bool, markStale: Bool, now: Date) -> NSImage {
        let labelFont = NSFont.systemFont(ofSize: 11, weight: .semibold)
        let smallFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium)

        var groups: [(pieces: [Piece], faded: Bool)] = []
        if style == .icon {
            let worst = entries.filter { !$0.signedOut && $0.percent != nil }.max { $0.percent! < $1.percent! }
            var pieces: [Piece] = [.ring(worst?.percent)]
            if entries.contains(where: \.signedOut) { pieces.append(.text("!", labelFont)) }
            if showCountdown, let left = countdown(to: worst?.resetsAt, now: now) { pieces.append(.text(left, smallFont)) }
            groups.append((pieces, markStale && (worst?.stale ?? false)))
        } else {
            for entry in entries {
                var pieces: [Piece] = []
                if showLabels { pieces.append(.text(entry.label, labelFont)) }
                if entry.signedOut {
                    pieces.append(.text("!", labelFont))
                } else {
                    pieces.append(style == .bars ? .bars(session: entry.session, weekly: entry.weekly) : .ring(entry.percent))
                    if showCountdown, let left = countdown(to: entry.resetsAt, now: now) { pieces.append(.text(left, smallFont)) }
                }
                groups.append((pieces, markStale && entry.stale))
            }
        }

        let pieceGap: CGFloat = 3, groupGap: CGFloat = 8, height: CGFloat = 18
        let widths = groups.map { group in
            group.pieces.map(\.width).reduce(0, +) + pieceGap * CGFloat(max(0, group.pieces.count - 1))
        }
        let total = widths.reduce(0, +) + groupGap * CGFloat(max(0, groups.count - 1))

        // Drawn lazily so labelColor follows the menu bar's light or dark appearance.
        let image = NSImage(size: NSSize(width: max(total, 1), height: height), flipped: false) { _ in
            var x: CGFloat = 0
            for group in groups {
                NSGraphicsContext.current?.saveGraphicsState()
                if group.faded { NSGraphicsContext.current?.cgContext.setAlpha(0.45) }
                for piece in group.pieces {
                    draw(piece, at: x, height: height)
                    x += piece.width + pieceGap
                }
                NSGraphicsContext.current?.restoreGraphicsState()
                x += groupGap - pieceGap
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func draw(_ piece: Piece, at x: CGFloat, height: CGFloat) {
        let track = NSColor.labelColor.withAlphaComponent(0.25)
        switch piece {
        case .text(let string, let font):
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor]
            let size = (string as NSString).size(withAttributes: attributes)
            (string as NSString).draw(at: NSPoint(x: x, y: (height - size.height) / 2), withAttributes: attributes)

        case .bars(let session, let weekly):
            for (value, y) in [(session, CGFloat(10)), (weekly, CGFloat(4))] {
                let rect = NSRect(x: x, y: y, width: 20, height: 4)
                track.setFill()
                NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2).fill()
                if let value, value > 0 {
                    color(for: value).setFill()
                    var filled = rect
                    filled.size.width = max(4, rect.width * min(value, 100) / 100)
                    NSBezierPath(roundedRect: filled, xRadius: 2, yRadius: 2).fill()
                }
            }

        case .ring(let value):
            let center = NSPoint(x: x + 7.5, y: height / 2)
            let radius: CGFloat = 6
            let circle = NSBezierPath()
            circle.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
            circle.lineWidth = 2.5
            track.setStroke()
            circle.stroke()
            if let value, value > 0 {
                let arc = NSBezierPath()
                arc.appendArc(withCenter: center, radius: radius, startAngle: 90,
                              endAngle: 90 - 360 * min(value, 100) / 100, clockwise: true)
                arc.lineWidth = 2.5
                arc.lineCapStyle = .round
                color(for: value).setStroke()
                arc.stroke()
            }
        }
    }
}
