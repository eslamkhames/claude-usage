import Foundation

struct Account: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    /// claude.ai organization whose usage we read; picked automatically after sign-in.
    var orgId: String?
    /// Plan name shown as a badge (Pro, Max 5x, ...), read from the organization.
    var plan: String?
    /// Short menu bar label; defaults to the first letter of the name.
    var label: String?
    var showInMenuBar = true
    var notify = true

    init(id: UUID, name: String) {
        self.id = id
        self.name = name
    }

    // Accounts saved by older versions lack the newer fields.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        orgId = try c.decodeIfPresent(String.self, forKey: .orgId)
        plan = try c.decodeIfPresent(String.self, forKey: .plan)
        label = try c.decodeIfPresent(String.self, forKey: .label)
        showInMenuBar = try c.decodeIfPresent(Bool.self, forKey: .showInMenuBar) ?? true
        notify = try c.decodeIfPresent(Bool.self, forKey: .notify) ?? true
    }

    var menuBarLabel: String {
        let custom = label?.trimmingCharacters(in: .whitespaces) ?? ""
        return custom.isEmpty ? name.prefix(1).uppercased() : custom
    }
}

enum WindowKind: String {
    case session, weekly
}

struct UsageWindow: Hashable {
    var percent: Double
    var resetsAt: Date?

    func hasReset(at now: Date) -> Bool {
        resetsAt.map { $0 <= now } ?? false
    }

    /// Once the reset time has passed the window is empty, even before the next refresh confirms it.
    func current(at now: Date, autoReset: Bool) -> UsageWindow {
        autoReset && hasReset(at: now) ? UsageWindow(percent: 0, resetsAt: nil) : self
    }
}

struct Usage {
    /// The rolling 5-hour session limit.
    var session: UsageWindow?
    /// The 7-day limit across all models.
    var weekly: UsageWindow?
    /// Per-model weekly limits (Opus, Sonnet, ...), when the plan has them.
    var models: [ModelUsage] = []
}

struct ModelUsage: Hashable, Identifiable {
    var name: String
    var window: UsageWindow
    var id: String { name }
}

enum UsageError: LocalizedError, Equatable {
    case notSignedIn
    case blocked
    case timedOut
    case noOrganization
    case rateLimited
    case http(Int)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .notSignedIn: "Signed out"
        case .blocked: "Blocked by Cloudflare check"
        case .timedOut: "Timed out"
        case .noOrganization: "No organization found"
        case .rateLimited: "Rate limited by claude.ai, will retry"
        case .http(let code): "claude.ai returned HTTP \(code)"
        case .badResponse: "Unexpected response from claude.ai"
        }
    }
}

extension Usage {
    /// Parses claude.ai's `/api/organizations/{id}/usage` response.
    init(json: [String: Any]) {
        func window(_ key: String) -> UsageWindow? {
            guard let obj = json[key] as? [String: Any],
                  let percent = Self.number(obj["utilization"]) else { return nil }
            return UsageWindow(percent: percent, resetsAt: Self.date(obj["resets_at"]))
        }

        session = window("five_hour")
        weekly = window("seven_day")

        var models: [String: UsageWindow] = [:]
        if let opus = window("seven_day_opus") { models["Opus"] = opus }
        if let sonnet = window("seven_day_sonnet") { models["Sonnet"] = sonnet }
        // Newer responses report per-model limits here and null out the legacy fields.
        for limit in json["limits"] as? [[String: Any]] ?? [] {
            guard limit["kind"] as? String == "weekly_scoped",
                  let model = (limit["scope"] as? [String: Any])?["model"] as? [String: Any],
                  let name = model["display_name"] as? String,
                  let percent = Self.number(limit["percent"]) else { continue }
            models[name] = UsageWindow(percent: percent, resetsAt: Self.date(limit["resets_at"]))
        }
        self.models = models.sorted { $0.key < $1.key }.map { ModelUsage(name: $0.key, window: $0.value) }
    }

    private static func number(_ value: Any?) -> Double? {
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String { return Double(s) }
        return nil
    }

    private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain = ISO8601DateFormatter()

    static func date(_ value: Any?) -> Date? {
        guard let s = value as? String else { return nil }
        return fractional.date(from: s) ?? plain.date(from: s)
    }
}
