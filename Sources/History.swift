import Foundation

struct UsageSample: Codable, Hashable {
    var t: Date
    var s: Double?
    var w: Double?
}

enum Projection: Equatable {
    case hitsLimit(Date)
    case staysUnder
}

/// Keeps a reading per refresh for the last 8 days, for the usage chart and the
/// time-to-limit estimate. Stored in Application Support so it survives restarts.
@MainActor
final class HistoryStore {
    private(set) var samples: [UUID: [UsageSample]] = [:]
    private let url: URL

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "ClaudeBar", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appending(path: "history.json")
        if let data = try? Data(contentsOf: url),
           let saved = try? JSONDecoder().decode([UUID: [UsageSample]].self, from: data) {
            samples = saved
        }
    }

    func record(_ id: UUID, _ usage: Usage, at date: Date = Date()) {
        var list = samples[id] ?? []
        // Manual refreshes right after a timed one would only add noise.
        if let last = list.last, date.timeIntervalSince(last.t) < 50 { list.removeLast() }
        list.append(UsageSample(t: date, s: usage.session?.percent, w: usage.weekly?.percent))
        let cutoff = date.addingTimeInterval(-8 * 86_400)
        list.removeAll { $0.t < cutoff }
        samples[id] = list
        save()
    }

    func remove(_ id: UUID) {
        samples[id] = nil
        save()
    }

    func samples(for id: UUID, since: Date) -> [UsageSample] {
        (samples[id] ?? []).filter { $0.t >= since }
    }

    /// Fits a line through recent readings of the current window and says whether the
    /// limit will be reached before the window resets.
    func projection(for id: UUID, kind: WindowKind, window: UsageWindow, now: Date) -> Projection? {
        guard window.percent < 100 else { return nil }
        let length: TimeInterval = kind == .session ? 5 * 3600 : 7 * 86_400
        let lookback: TimeInterval = kind == .session ? 90 * 60 : 24 * 3600
        let minSpan: TimeInterval = kind == .session ? 10 * 60 : 2 * 3600

        var start = now.addingTimeInterval(-lookback)
        if let reset = window.resetsAt { start = max(start, reset.addingTimeInterval(-length)) }
        let points: [(x: Double, y: Double)] = (samples[id] ?? []).compactMap { sample in
            guard sample.t >= start, let y = kind == .session ? sample.s : sample.w else { return nil }
            return (sample.t.timeIntervalSince(now), y)
        }
        guard points.count >= 2, let first = points.first, let last = points.last,
              last.x - first.x >= minSpan else { return nil }

        let n = Double(points.count)
        let meanX = points.map(\.x).reduce(0, +) / n
        let meanY = points.map(\.y).reduce(0, +) / n
        let num = points.reduce(0) { $0 + ($1.x - meanX) * ($1.y - meanY) }
        let den = points.reduce(0) { $0 + ($1.x - meanX) * ($1.x - meanX) }
        guard den > 0 else { return nil }
        let slope = num / den // percent per second
        guard slope > 0 else { return .staysUnder }

        let eta = now.addingTimeInterval((100 - window.percent) / slope)
        if let reset = window.resetsAt, eta >= reset { return .staysUnder }
        return .hitsLimit(eta)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(samples) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
