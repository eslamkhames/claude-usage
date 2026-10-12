import Foundation

struct ClaudeCodeProject: Identifiable, Hashable {
    var name: String
    var tokens: Int
    var cost: Double
    var id: String { name }
}

struct ClaudeCodeSummary {
    var inputTokens = 0
    var outputTokens = 0
    var cacheWriteTokens = 0
    var cacheReadTokens = 0
    var cost = 0.0
    var messages = 0
    var projects: [ClaudeCodeProject] = []
    var unpricedModels: Set<String> = []
    var totalTokens: Int { inputTokens + outputTokens + cacheWriteTokens + cacheReadTokens }
}

@MainActor
final class ClaudeCodeMonitor: ObservableObject {
    @Published private(set) var summary: ClaudeCodeSummary?
    @Published private(set) var scanning = false
    private let scanner = ClaudeCodeScanner()

    func refresh() async {
        guard !scanning else { return }
        scanning = true
        defer { scanning = false }
        let since = Prefs.claudeCodeRange.startDate
        let scanner = scanner
        summary = await Task.detached(priority: .utility) { scanner.summary(since: since) }.value
    }
}

/// API list prices per million tokens. Cache writes cost 1.25x input (5-minute) or
/// 2x input (1-hour); fast mode doubles everything.
enum ClaudePricing {
    struct Price { var input: Double; var output: Double; var cacheRead: Double }

    // Checked in order, so more specific model names come first.
    private static let table: [(match: String, price: Price)] = [
        ("fable-5-1", Price(input: 10, output: 50, cacheRead: 0.25)),
        ("mythos-5-1", Price(input: 10, output: 50, cacheRead: 0.25)),
        ("fable", Price(input: 10, output: 50, cacheRead: 1)),
        ("mythos", Price(input: 10, output: 50, cacheRead: 1)),
        ("opus-5-5", Price(input: 4, output: 20, cacheRead: 0.2)),
        ("opus-5", Price(input: 5, output: 25, cacheRead: 0.5)),
        ("opus-4-8", Price(input: 5, output: 25, cacheRead: 0.5)),
        ("opus-4-7", Price(input: 5, output: 25, cacheRead: 0.5)),
        ("opus-4-6", Price(input: 5, output: 25, cacheRead: 0.5)),
        ("opus-4-5", Price(input: 5, output: 25, cacheRead: 0.5)),
        ("opus-4", Price(input: 15, output: 75, cacheRead: 1.5)),
        ("sonnet-5", Price(input: 2, output: 10, cacheRead: 0.2)),
        ("sonnet-4", Price(input: 3, output: 15, cacheRead: 0.3)),
        ("sonnet-3", Price(input: 3, output: 15, cacheRead: 0.3)),
        ("haiku-5-5", Price(input: 0.1, output: 0.5, cacheRead: 0.01)),
        ("haiku-4-5", Price(input: 1, output: 5, cacheRead: 0.1)),
        ("haiku-3-5", Price(input: 0.8, output: 4, cacheRead: 0.08)),
        ("haiku-3", Price(input: 0.25, output: 1.25, cacheRead: 0.03)),
    ]

    static func price(for model: String) -> Price? {
        let model = model.lowercased()
        return table.first { model.contains($0.match) }?.price
    }
}

/// Reads Claude Code's session logs in ~/.claude/projects. Parsed files are cached by
/// modification date, so a refresh only re-reads logs that changed. Only one scan runs
/// at a time (ClaudeCodeMonitor guards that), so the cache needs no lock.
final class ClaudeCodeScanner: @unchecked Sendable {
    private struct Entry {
        var key: String
        var date: Date
        var model: String
        var project: String
        var input: Int
        var output: Int
        var cacheWrite5m: Int
        var cacheWrite1h: Int
        var cacheRead: Int
        var fast: Bool

        var tokens: Int { input + output + cacheWrite5m + cacheWrite1h + cacheRead }

        var cost: Double? {
            guard let p = ClaudePricing.price(for: model) else { return nil }
            let dollars = Double(input) * p.input + Double(output) * p.output
                + Double(cacheWrite5m) * p.input * 1.25 + Double(cacheWrite1h) * p.input * 2
                + Double(cacheRead) * p.cacheRead
            return dollars / 1_000_000 * (fast ? 2 : 1)
        }
    }

    private var cache: [String: (modified: Date, size: Int, entries: [Entry])] = [:]

    func summary(since: Date) -> ClaudeCodeSummary {
        var summary = ClaudeCodeSummary()
        let root = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude/projects")
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys) else { return summary }

        var seen = Set<String>()
        var livePaths = Set<String>()
        var projects: [String: (tokens: Int, cost: Double)] = [:]

        for case let url as URL in files where url.pathExtension == "jsonl" {
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true,
                  let modified = values.contentModificationDate, modified >= since else { continue }
            let size = values.fileSize ?? 0
            livePaths.insert(url.path)

            let entries: [Entry]
            if let cached = cache[url.path], cached.modified == modified, cached.size == size {
                entries = cached.entries
            } else {
                entries = Self.parse(url)
                cache[url.path] = (modified, size, entries)
            }

            // Claude Code repeats a message's usage on every content block, and resumed
            // sessions copy earlier messages into a new file, so count each response once.
            for entry in entries where entry.date >= since && seen.insert(entry.key).inserted {
                summary.messages += 1
                summary.inputTokens += entry.input
                summary.outputTokens += entry.output
                summary.cacheWriteTokens += entry.cacheWrite5m + entry.cacheWrite1h
                summary.cacheReadTokens += entry.cacheRead
                let cost = entry.cost
                if cost == nil { summary.unpricedModels.insert(entry.model) }
                summary.cost += cost ?? 0
                projects[entry.project, default: (0, 0)].tokens += entry.tokens
                projects[entry.project, default: (0, 0)].cost += cost ?? 0
            }
        }
        cache = cache.filter { livePaths.contains($0.key) }
        summary.projects = projects
            .map { ClaudeCodeProject(name: $0.key, tokens: $0.value.tokens, cost: $0.value.cost) }
            .sorted { ($0.cost, $0.tokens) > ($1.cost, $1.tokens) }
        return summary
    }

    private static func parse(_ url: URL) -> [Entry] {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return [] }
        let fallbackProject = url.deletingLastPathComponent().lastPathComponent
        let marker = Data("\"usage\"".utf8)
        var entries: [Entry] = []

        for line in data.split(separator: UInt8(ascii: "\n")) where line.range(of: marker) != nil {
            guard let obj = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
                  obj["type"] as? String == "assistant",
                  let message = obj["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any],
                  let model = message["model"] as? String, model != "<synthetic>",
                  let date = Usage.date(obj["timestamp"]) else { continue }

            let cacheWrite = int(usage["cache_creation_input_tokens"])
            var write1h = 0
            if let split = usage["cache_creation"] as? [String: Any] {
                write1h = min(cacheWrite, int(split["ephemeral_1h_input_tokens"]))
            }
            let project = (obj["cwd"] as? String).map { URL(fileURLWithPath: $0).lastPathComponent } ?? fallbackProject
            let messageId = message["id"] as? String ?? UUID().uuidString

            entries.append(Entry(
                key: messageId + ":" + (obj["requestId"] as? String ?? ""),
                date: date,
                model: model,
                project: project,
                input: int(usage["input_tokens"]),
                output: int(usage["output_tokens"]),
                cacheWrite5m: cacheWrite - write1h,
                cacheWrite1h: write1h,
                cacheRead: int(usage["cache_read_input_tokens"]),
                fast: usage["speed"] as? String == "fast"
            ))
        }
        return entries
    }

    private static func int(_ value: Any?) -> Int {
        (value as? NSNumber)?.intValue ?? 0
    }
}
