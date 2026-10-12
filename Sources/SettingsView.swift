import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: AccountStore
    @EnvironmentObject private var updater: Updater
    @EnvironmentObject private var monitor: ClaudeCodeMonitor

    @AppStorage(Prefs.Key.refreshMinutes) private var refreshMinutes = 5
    @AppStorage(Prefs.Key.refreshOnWake) private var refreshOnWake = true
    @AppStorage(Prefs.Key.menuBarStyle) private var style = MenuBarStyle.text
    @AppStorage(Prefs.Key.metric) private var metric = MenuBarMetric.session
    @AppStorage(Prefs.Key.showLabels) private var showLabels = true
    @AppStorage(Prefs.Key.showCountdown) private var showCountdown = false
    @AppStorage(Prefs.Key.highlightBest) private var highlightBest = true
    @AppStorage(Prefs.Key.showPlanBadge) private var showPlan = true
    @AppStorage(Prefs.Key.showModelLimits) private var showModels = true
    @AppStorage(Prefs.Key.showModelResets) private var showModelResets = true
    @AppStorage(Prefs.Key.showHistory) private var showHistory = true
    @AppStorage(Prefs.Key.historyRange) private var historyRange = HistoryRange.day
    @AppStorage(Prefs.Key.showProjection) private var showProjection = true
    @AppStorage(Prefs.Key.dimStale) private var dimStale = true
    @AppStorage(Prefs.Key.autoZeroAfterReset) private var autoZero = true
    @AppStorage(Prefs.Key.notifyEnabled) private var notifyEnabled = true
    @AppStorage(Prefs.Key.warnThreshold) private var warn = 75
    @AppStorage(Prefs.Key.criticalThreshold) private var critical = 90
    @AppStorage(Prefs.Key.notifyWeekly) private var notifyWeekly = true
    @AppStorage(Prefs.Key.notifyReset) private var notifyReset = true
    @AppStorage(Prefs.Key.notifySignedOut) private var notifySignedOut = true
    @AppStorage(Prefs.Key.showClaudeCode) private var showClaudeCode = true
    @AppStorage(Prefs.Key.claudeCodeRange) private var codeRange = CodeRange.today
    @AppStorage(Prefs.Key.showClaudeCodeCost) private var showCost = true
    @AppStorage(Prefs.Key.showCodeProjects) private var showCodeProjects = true
    @AppStorage(Prefs.Key.showCodeBreakdown) private var showCodeBreakdown = true
    @AppStorage(Prefs.Key.showCodeNote) private var showCodeNote = true
    @AppStorage(Prefs.Key.showLastUpdated) private var showLastUpdated = true
    @AppStorage(Prefs.Key.hotKeyEnabled) private var hotKeyEnabled = false
    @AppStorage(Prefs.Key.hotKey) private var hotKey = HotKeyChoice.ctrlOptC
    @AppStorage(Prefs.Key.autoCheckUpdates) private var autoCheckUpdates = true

    private let warnOptions = [50, 60, 70, 75, 80, 85, 90]
    private let criticalOptions = [60, 70, 75, 80, 85, 90, 95, 98]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SettingsSection("General") {
                    Picker("Refresh every", selection: $refreshMinutes) {
                        ForEach([1, 2, 5, 10, 15, 30], id: \.self) { Text("\($0) min").tag($0) }
                    }
                    Toggle("Refresh after waking and when back online", isOn: $refreshOnWake)
                    Toggle("Launch at login", isOn: $store.launchAtLogin)
                    Toggle("Show \u{201C}Updated … ago\u{201D} at the bottom", isOn: $showLastUpdated)
                }

                SettingsSection("Menu bar") {
                    Picker("Style", selection: $style) {
                        ForEach(MenuBarStyle.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Shows", selection: $metric) {
                        ForEach(MenuBarMetric.allCases) { Text($0.title).tag($0) }
                    }
                    .disabled(style == .bars)
                    Toggle("Show account labels", isOn: $showLabels).disabled(style == .icon)
                    Toggle("Show time until reset", isOn: $showCountdown)
                    Note("Set an account's label, or hide it from the menu bar, in its ⋯ menu.")
                }

                SettingsSection("Accounts") {
                    Toggle("Highlight the account with the most room", isOn: $highlightBest)
                    Toggle("Show plan badge", isOn: $showPlan)
                    Toggle("Show per-model weekly limits", isOn: $showModels)
                    Toggle("Show reset times for model limits", isOn: $showModelResets)
                        .disabled(!showModels)
                        .padding(.leading, 18)
                    Toggle("Show usage chart", isOn: $showHistory)
                    Picker("Chart covers", selection: $historyRange) {
                        ForEach(HistoryRange.allCases) { Text($0.title).tag($0) }
                    }
                    .disabled(!showHistory)
                    .padding(.leading, 18)
                    Toggle("Estimate when a limit will be reached", isOn: $showProjection)
                    Toggle("Fade numbers that are out of date", isOn: $dimStale)
                    Toggle("Show 0% as soon as a limit's reset time passes", isOn: $autoZero)
                }

                SettingsSection("Notifications") {
                    Toggle("Enable notifications", isOn: $notifyEnabled)
                    Group {
                        Picker("Warn at", selection: $warn) {
                            ForEach(warnOptions, id: \.self) { Text("\($0)%").tag($0) }
                        }
                        Picker("Critical at", selection: $critical) {
                            ForEach(criticalOptions, id: \.self) { Text("\($0)%").tag($0) }
                        }
                        Toggle("Include the weekly limit", isOn: $notifyWeekly)
                        Toggle("When a limit you were close to resets", isOn: $notifyReset)
                        Toggle("When an account gets signed out", isOn: $notifySignedOut)
                        Button("Send a test notification") { store.notifier.test() }
                    }
                    .disabled(!notifyEnabled)
                    Note("The thresholds also set when bars turn orange and red. Turn notifications off for one account in its ⋯ menu.")
                }

                SettingsSection("Claude Code") {
                    Toggle("Show Claude Code usage from this Mac", isOn: $showClaudeCode)
                    Group {
                        Picker("Period", selection: $codeRange) {
                            ForEach(CodeRange.allCases) { Text($0.title).tag($0) }
                        }
                        Toggle("Show top projects", isOn: $showCodeProjects)
                        Toggle("Show token breakdown (in, out, cache)", isOn: $showCodeBreakdown)
                        Toggle("Show estimated API cost", isOn: $showCost)
                        Toggle("Show the note about API prices", isOn: $showCodeNote)
                            .disabled(!showCost)
                            .padding(.leading, 18)
                    }
                    .disabled(!showClaudeCode)
                }

                SettingsSection("Keyboard shortcut") {
                    Toggle("Open ClaudeBar with a shortcut", isOn: $hotKeyEnabled)
                    Picker("Shortcut", selection: $hotKey) {
                        ForEach(HotKeyChoice.allCases) { Text($0.title).tag($0) }
                    }
                    .disabled(!hotKeyEnabled)
                }

                SettingsSection("Updates") {
                    Toggle("Check for updates once a day", isOn: $autoCheckUpdates)
                    HStack {
                        Button("Check now") { Task { await updater.check() } }.disabled(updater.busy)
                        if let status = updater.status { Note(status) }
                    }
                }

                SettingsSection("About") {
                    HStack {
                        Text("ClaudeBar \(updater.currentVersion)")
                        Spacer()
                        Button("About") {
                            NSApp.activate(ignoringOtherApps: true)
                            NSApp.orderFrontStandardAboutPanel(options: [
                                .credits: NSAttributedString(string: "Claude plan usage for several accounts, in the menu bar."),
                            ])
                        }
                        Button("GitHub") { NSWorkspace.shared.open(Updater.repoURL) }
                    }
                }
            }
            .padding(.trailing, 6)
        }
        .frame(maxHeight: 500)
        .controlSize(.small)
        .onChange(of: refreshMinutes) { store.restartTimer() }
        .onChange(of: hotKeyEnabled) { HotKeyManager.shared.apply() }
        .onChange(of: hotKey) { HotKeyManager.shared.apply() }
        .onChange(of: notifyEnabled) { if notifyEnabled { store.notifier.requestAuthorization() } }
        .onChange(of: warn) {
            if critical <= warn { critical = criticalOptions.first { $0 > warn } ?? 98 }
        }
        .onChange(of: critical) {
            if warn >= critical { warn = warnOptions.last { $0 < critical } ?? 50 }
        }
        .onChange(of: codeRange) { Task { await monitor.refresh() } }
        .onChange(of: showClaudeCode) { if showClaudeCode { Task { await monitor.refresh() } } }
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct Note: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
