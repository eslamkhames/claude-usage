import Foundation

enum MenuBarMetric: String, CaseIterable, Identifiable {
    case session, weekly, highest
    var id: String { rawValue }
    var title: String {
        switch self {
        case .session: "5-hour session"
        case .weekly: "Weekly"
        case .highest: "Whichever is higher"
        }
    }
}

enum MenuBarStyle: String, CaseIterable, Identifiable {
    case text, bars, rings, icon
    var id: String { rawValue }
    var title: String {
        switch self {
        case .text: "Text"
        case .bars: "Bars (session + weekly)"
        case .rings: "Rings"
        case .icon: "Single icon (highest)"
        }
    }
}

enum HistoryRange: String, CaseIterable, Identifiable {
    case day, week
    var id: String { rawValue }
    var title: String { self == .day ? "24 hours" : "7 days" }
    var seconds: TimeInterval { self == .day ? 86_400 : 7 * 86_400 }
}

enum CodeRange: String, CaseIterable, Identifiable {
    case today, week
    var id: String { rawValue }
    var title: String { self == .today ? "Today" : "Last 7 days" }
    var startDate: Date {
        let today = Calendar.current.startOfDay(for: Date())
        return self == .today ? today : Calendar.current.date(byAdding: .day, value: -6, to: today) ?? today
    }
}

enum HotKeyChoice: String, CaseIterable, Identifiable {
    case ctrlOptC, ctrlOptU, cmdOptU, cmdShiftK
    var id: String { rawValue }
    var title: String {
        switch self {
        case .ctrlOptC: "⌃⌥C"
        case .ctrlOptU: "⌃⌥U"
        case .cmdOptU: "⌥⌘U"
        case .cmdShiftK: "⇧⌘K"
        }
    }
}

/// Every user setting lives in UserDefaults under these keys. Views bind to them with
/// `@AppStorage`; non-view code reads them through the accessors below.
enum Prefs {
    enum Key {
        static let refreshMinutes = "refreshMinutes"
        static let refreshOnWake = "refreshOnWake"
        static let metric = "metric"
        static let menuBarStyle = "menuBarStyle"
        static let showLabels = "showInitials"
        static let showCountdown = "showCountdown"
        static let highlightBest = "highlightBest"
        static let showPlanBadge = "showPlanBadge"
        static let showModelLimits = "showModelLimits"
        static let showModelResets = "showModelResets"
        static let showHistory = "showHistory"
        static let historyRange = "historyRange"
        static let showProjection = "showProjection"
        static let dimStale = "dimStale"
        static let autoZeroAfterReset = "autoZeroAfterReset"
        static let notifyEnabled = "notifyEnabled"
        static let warnThreshold = "warnThreshold"
        static let criticalThreshold = "criticalThreshold"
        static let notifyWeekly = "notifyWeekly"
        static let notifyReset = "notifyReset"
        static let notifySignedOut = "notifySignedOut"
        static let showClaudeCode = "showClaudeCode"
        static let claudeCodeRange = "claudeCodeRange"
        static let showClaudeCodeCost = "showClaudeCodeCost"
        static let showCodeProjects = "showCodeProjects"
        static let showCodeBreakdown = "showCodeBreakdown"
        static let showCodeNote = "showCodeNote"
        static let showLastUpdated = "showLastUpdated"
        static let hotKeyEnabled = "hotKeyEnabled"
        static let hotKey = "hotKey"
        static let autoCheckUpdates = "autoCheckUpdates"
    }

    static func register() {
        UserDefaults.standard.register(defaults: [
            Key.refreshMinutes: 5,
            Key.refreshOnWake: true,
            Key.metric: MenuBarMetric.session.rawValue,
            Key.menuBarStyle: MenuBarStyle.text.rawValue,
            Key.showLabels: true,
            Key.showCountdown: false,
            Key.highlightBest: true,
            Key.showPlanBadge: true,
            Key.showModelLimits: true,
            Key.showModelResets: true,
            Key.showHistory: true,
            Key.historyRange: HistoryRange.day.rawValue,
            Key.showProjection: true,
            Key.dimStale: true,
            Key.autoZeroAfterReset: true,
            Key.notifyEnabled: true,
            Key.warnThreshold: 75,
            Key.criticalThreshold: 90,
            Key.notifyWeekly: true,
            Key.notifyReset: true,
            Key.notifySignedOut: true,
            Key.showClaudeCode: true,
            Key.claudeCodeRange: CodeRange.today.rawValue,
            Key.showClaudeCodeCost: true,
            Key.showCodeProjects: true,
            Key.showCodeBreakdown: true,
            Key.showCodeNote: true,
            Key.showLastUpdated: true,
            Key.hotKeyEnabled: false,
            Key.hotKey: HotKeyChoice.ctrlOptC.rawValue,
            Key.autoCheckUpdates: true,
        ])
    }

    private static var d: UserDefaults { .standard }

    static var refreshMinutes: Int { max(1, d.integer(forKey: Key.refreshMinutes)) }
    static var refreshOnWake: Bool { d.bool(forKey: Key.refreshOnWake) }
    static var metric: MenuBarMetric { MenuBarMetric(rawValue: d.string(forKey: Key.metric) ?? "") ?? .session }
    static var autoZeroAfterReset: Bool { d.bool(forKey: Key.autoZeroAfterReset) }
    static var notifyEnabled: Bool { d.bool(forKey: Key.notifyEnabled) }
    static var warnThreshold: Int { d.integer(forKey: Key.warnThreshold) }
    static var criticalThreshold: Int { d.integer(forKey: Key.criticalThreshold) }
    static var notifyWeekly: Bool { d.bool(forKey: Key.notifyWeekly) }
    static var notifyReset: Bool { d.bool(forKey: Key.notifyReset) }
    static var notifySignedOut: Bool { d.bool(forKey: Key.notifySignedOut) }
    static var showClaudeCode: Bool { d.bool(forKey: Key.showClaudeCode) }
    static var claudeCodeRange: CodeRange { CodeRange(rawValue: d.string(forKey: Key.claudeCodeRange) ?? "") ?? .today }
    static var hotKeyEnabled: Bool { d.bool(forKey: Key.hotKeyEnabled) }
    static var hotKey: HotKeyChoice { HotKeyChoice(rawValue: d.string(forKey: Key.hotKey) ?? "") ?? .ctrlOptC }
    static var autoCheckUpdates: Bool { d.bool(forKey: Key.autoCheckUpdates) }
}
