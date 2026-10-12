import Charts
import SwiftUI

@main
struct ClaudeBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = AccountStore()

    var body: some Scene {
        MenuBarExtra {
            PanelView()
                .environmentObject(store)
                .environmentObject(store.claudeCode)
                .environmentObject(store.updater)
        } label: {
            MenuBarLabel().environmentObject(store)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // The app has no visible menu bar, but the main menu's key equivalents still make
        // ⌘C/⌘V/⌘A/⌘W work in the sign-in and claude.ai windows.
        let main = NSMenu()
        let appItem = NSMenuItem()
        appItem.submenu = NSMenu()
        appItem.submenu?.addItem(withTitle: "Quit ClaudeBar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        windowItem.submenu = NSMenu(title: "Window")
        windowItem.submenu?.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu?.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        main.addItem(windowItem)

        NSApp.mainMenu = main
    }
}

// MARK: - Menu bar

struct MenuBarLabel: View {
    @EnvironmentObject private var store: AccountStore
    @AppStorage(Prefs.Key.menuBarStyle) private var style = MenuBarStyle.text
    @AppStorage(Prefs.Key.metric) private var metric = MenuBarMetric.session
    @AppStorage(Prefs.Key.showLabels) private var showLabels = true
    @AppStorage(Prefs.Key.showCountdown) private var showCountdown = false
    @AppStorage(Prefs.Key.dimStale) private var markStale = true
    // Read so the label redraws when these change.
    @AppStorage(Prefs.Key.autoZeroAfterReset) private var autoZero = true
    @AppStorage(Prefs.Key.warnThreshold) private var warn = 75
    @AppStorage(Prefs.Key.criticalThreshold) private var critical = 90

    var body: some View {
        let entries = store.menuBarEntries(metric: metric)
        if style == .text || entries.isEmpty {
            Text(MenuBarRenderer.text(entries, showLabels: showLabels, showCountdown: showCountdown,
                                      markStale: markStale, now: store.now))
        } else {
            Image(nsImage: MenuBarRenderer.image(entries, style: style, showLabels: showLabels,
                                                 showCountdown: showCountdown, markStale: markStale, now: store.now))
        }
    }
}

// MARK: - Panel

struct PanelView: View {
    @EnvironmentObject private var store: AccountStore
    @EnvironmentObject private var updater: Updater
    @AppStorage(Prefs.Key.showClaudeCode) private var showClaudeCode = true
    @AppStorage(Prefs.Key.highlightBest) private var highlightBest = true
    @AppStorage(Prefs.Key.showLastUpdated) private var showLastUpdated = true
    @State private var showingSettings = false
    @State private var newName = ""
    @State private var adding = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(showingSettings ? "Settings" : "Claude Usage").font(.headline)
                Spacer()
                if !showingSettings {
                    Button {
                        Task { await store.refreshAll() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(!store.loading.isEmpty)
                    .help("Refresh now")
                }
                Button {
                    showingSettings.toggle()
                } label: {
                    Image(systemName: showingSettings ? "xmark" : "gearshape")
                }
                .help(showingSettings ? "Close settings" : "Settings")
            }
            .buttonStyle(.borderless)

            if showingSettings {
                SettingsView()
            } else {
                if let release = updater.available { updateBanner(release) }
                accountList
                addRow
                if showClaudeCode {
                    Divider()
                    ClaudeCodeSection()
                }
            }

            Divider()
            HStack {
                if showLastUpdated, let last = store.lastRefresh {
                    Text("Updated \(last, style: .relative) ago")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
        }
        .padding(14)
        .frame(width: 360)
    }

    private func updateBanner(_ release: Updater.Release) -> some View {
        HStack {
            Image(systemName: "arrow.down.circle.fill").foregroundStyle(.blue)
            Text("ClaudeBar \(release.version) is available").font(.callout)
            Spacer()
            Button(updater.busy ? "Installing…" : "Install") { Task { await updater.install() } }
                .disabled(updater.busy)
                .controlSize(.small)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(.blue.opacity(0.12)))
    }

    @ViewBuilder private var accountList: some View {
        if store.accounts.isEmpty {
            Text("Add each Claude account you use. Each one signs in separately and its usage shows in the menu bar.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            let best = highlightBest ? store.bestAccountId() : nil
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(Array(store.accounts.enumerated()), id: \.element.id) { index, account in
                        AccountCard(account: account, isBest: account.id == best,
                                    isFirst: index == 0, isLast: index == store.accounts.count - 1)
                    }
                }
            }
            .frame(maxHeight: 460)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var addRow: some View {
        if adding {
            HStack {
                TextField("Account name (e.g. Work)", text: $newName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)
                Button("Sign in", action: add).disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Cancel") { adding = false; newName = "" }
            }
            .controlSize(.small)
        } else {
            Button {
                adding = true
            } label: {
                Label("Add account", systemImage: "plus")
            }
            .buttonStyle(.borderless)
        }
    }

    private func add() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        store.addAccount(named: name)
        newName = ""
        adding = false
    }
}

// MARK: - Account card

struct AccountCard: View {
    @EnvironmentObject private var store: AccountStore
    let account: Account
    var isBest = false
    var isFirst = false
    var isLast = false

    @AppStorage(Prefs.Key.showPlanBadge) private var showPlan = true
    @AppStorage(Prefs.Key.showModelLimits) private var showModels = true
    @AppStorage(Prefs.Key.showModelResets) private var showModelResets = true
    @AppStorage(Prefs.Key.showHistory) private var showHistory = true
    @AppStorage(Prefs.Key.historyRange) private var historyRange = HistoryRange.day
    @AppStorage(Prefs.Key.showProjection) private var showProjection = true
    @AppStorage(Prefs.Key.dimStale) private var dimStale = true
    @AppStorage(Prefs.Key.autoZeroAfterReset) private var autoZero = true

    private enum Field { case name, label }
    @State private var editing: Field?
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            if let problem = store.problems[account.id] {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(problem.localizedDescription).font(.caption)
                    Spacer()
                    if problem == .notSignedIn {
                        Button("Sign in") { store.signIn(account) }.controlSize(.small)
                    }
                }
            }

            if let usage = store.usage[account.id] {
                let stale = store.isStale(account.id)
                if stale, let last = store.lastSuccess[account.id] {
                    Text("Numbers from \(last.formatted(.relative(presentation: .named)))")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                VStack(alignment: .leading, spacing: 8) {
                    usageRows(usage)
                    chart
                }
                .opacity(dimStale && stale ? 0.5 : 1)
            } else if store.problems[account.id] == nil {
                Text("Loading…").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.green.opacity(isBest ? 0.7 : 0), lineWidth: 1.5))
    }

    @ViewBuilder private var header: some View {
        HStack(spacing: 6) {
            if let field = editing {
                TextField(field == .name ? "Name" : "Label, up to 3 letters (empty = first letter)", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(commit)
                Button("Save", action: commit).controlSize(.small)
                Button("Cancel") { editing = nil }.controlSize(.small)
            } else {
                Text(account.name).font(.system(.body, weight: .semibold)).lineLimit(1)
                if showPlan, let plan = account.plan { Badge(text: plan, color: .secondary) }
                if isBest { Badge(text: "Best now", color: .green, systemImage: "star.fill") }
                if !account.showInMenuBar {
                    Image(systemName: "eye.slash").font(.caption).foregroundStyle(.secondary).help("Hidden from the menu bar")
                }
                if !account.notify {
                    Image(systemName: "bell.slash").font(.caption).foregroundStyle(.secondary).help("Notifications off")
                }
                if store.loading.contains(account.id) {
                    ProgressView().controlSize(.mini)
                }
                Spacer()
                menu
            }
        }
    }

    private var menu: some View {
        Menu {
            Button("Refresh") { Task { await store.refresh(account.id) } }
            Button("Open claude.ai as \(account.name)") { store.openBrowser(account) }
            Button("Sign in again") { store.signIn(account) }
            Divider()
            Button("Rename…") { draft = account.name; editing = .name }
            Button("Menu bar label…") { draft = account.label ?? ""; editing = .label }
            Toggle("Show in menu bar", isOn: Binding(
                get: { account.showInMenuBar },
                set: { value in store.edit(account) { $0.showInMenuBar = value } }
            ))
            Toggle("Notifications", isOn: Binding(
                get: { account.notify },
                set: { value in store.edit(account) { $0.notify = value } }
            ))
            Divider()
            Button("Move up") { store.move(account, by: -1) }.disabled(isFirst)
            Button("Move down") { store.move(account, by: 1) }.disabled(isLast)
            Divider()
            Button("Remove", role: .destructive) { store.remove(account) }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    @ViewBuilder private func usageRows(_ usage: Usage) -> some View {
        let now = store.now
        if let session = usage.session {
            let shown = session.current(at: now, autoReset: autoZero)
            UsageRow(title: "5-hour session", window: shown,
                     projection: projection(.session, raw: session, shown: shown))
        }
        if let weekly = usage.weekly {
            let shown = weekly.current(at: now, autoReset: autoZero)
            UsageRow(title: "Weekly", window: shown,
                     projection: projection(.weekly, raw: weekly, shown: shown))
        }
        if showModels {
            ForEach(usage.models) { model in
                UsageRow(title: "Weekly · \(model.name)", window: model.window.current(at: now, autoReset: autoZero),
                         compact: true, showReset: showModelResets)
            }
        }
    }

    private func projection(_ kind: WindowKind, raw: UsageWindow, shown: UsageWindow) -> Projection? {
        // After a reset the old readings say nothing about the new window.
        guard showProjection, !raw.hasReset(at: store.now) else { return nil }
        return store.history.projection(for: account.id, kind: kind, window: shown, now: store.now)
    }

    @ViewBuilder private var chart: some View {
        if showHistory {
            let since = store.now.addingTimeInterval(-historyRange.seconds)
            let samples = store.history.samples(for: account.id, since: since)
            if samples.count >= 2 {
                UsageChart(samples: samples, since: since, now: store.now)
            }
        }
    }

    private func commit() {
        let text = draft.trimmingCharacters(in: .whitespaces)
        switch editing {
        case .name: if !text.isEmpty { store.edit(account) { $0.name = text } }
        case .label: store.edit(account) { $0.label = text.isEmpty ? nil : String(text.prefix(3)) }
        case nil: break
        }
        editing = nil
    }
}

struct Badge: View {
    let text: String
    let color: Color
    var systemImage: String?

    var body: some View {
        HStack(spacing: 2) {
            if let systemImage { Image(systemName: systemImage) }
            Text(text)
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(color)
        .padding(.horizontal, 5)
        .padding(.vertical, 1)
        .background(Capsule().fill(color.opacity(0.15)))
    }
}

func usageColor(_ percent: Double) -> Color {
    Color(nsColor: MenuBarRenderer.color(for: percent))
}

struct UsageRow: View {
    let title: String
    let window: UsageWindow
    var compact = false
    var showReset = true
    var projection: Projection?
    // Read so colors update when the thresholds change.
    @AppStorage(Prefs.Key.warnThreshold) private var warn = 75
    @AppStorage(Prefs.Key.criticalThreshold) private var critical = 90

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title).font(compact ? .caption : .callout)
                Spacer()
                Text("\(Int(window.percent.rounded()))%")
                    .font((compact ? Font.caption : .callout).monospacedDigit().weight(.medium))
                    .foregroundStyle(usageColor(window.percent))
            }
            ProgressView(value: min(window.percent, 100), total: 100)
                .tint(usageColor(window.percent))
                .controlSize(compact ? .mini : .small)
            let reset = showReset ? window.resetsAt : nil
            if reset != nil || projection != nil {
                HStack {
                    if let reset { Text(resetText(reset)) }
                    Spacer()
                    if let projection { projectionText(projection) }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private func projectionText(_ projection: Projection) -> some View {
        switch projection {
        case .hitsLimit(let date):
            Label("Limit ~\(timeText(date))", systemImage: "exclamationmark.circle")
                .foregroundStyle(.orange)
                .help("At the current pace this limit is reached before it resets")
        case .staysUnder:
            Text("On pace to stay under")
        }
    }

    private func timeText(_ date: Date) -> String {
        Calendar.current.isDateInToday(date)
            ? date.formatted(date: .omitted, time: .shortened)
            : date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }

    private func resetText(_ date: Date) -> String {
        let seconds = date.timeIntervalSinceNow
        guard seconds > 0 else { return "Resetting now" }
        if seconds < 24 * 3600 {
            let hours = Int(seconds) / 3600
            let minutes = Int(seconds) % 3600 / 60
            return hours > 0 ? "Resets in \(hours)h \(minutes)m" : "Resets in \(minutes)m"
        }
        return "Resets " + date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }
}

struct UsageChart: View {
    let samples: [UsageSample]
    let since: Date
    let now: Date

    var body: some View {
        Chart {
            ForEach(samples, id: \.t) { sample in
                if let value = sample.s {
                    LineMark(x: .value("Time", sample.t), y: .value("Used", value), series: .value("Limit", "Session"))
                        .foregroundStyle(by: .value("Limit", "Session"))
                }
                if let value = sample.w {
                    LineMark(x: .value("Time", sample.t), y: .value("Used", value), series: .value("Limit", "Weekly"))
                        .foregroundStyle(by: .value("Limit", "Weekly"))
                }
            }
        }
        .chartForegroundStyleScale(["Session": Color.accentColor, "Weekly": Color.purple])
        .chartYScale(domain: 0...100)
        .chartXScale(domain: since...now)
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 50, 100]) { value in
                AxisGridLine()
                AxisValueLabel { Text("\(value.as(Int.self) ?? 0)%") }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine()
                AxisValueLabel(format: now.timeIntervalSince(since) > 86_400
                               ? .dateTime.weekday(.abbreviated) : .dateTime.hour())
            }
        }
        .chartLegend(position: .bottom, spacing: 2)
        .font(.caption2)
        .frame(height: 80)
    }
}

// MARK: - Claude Code

struct ClaudeCodeSection: View {
    @EnvironmentObject private var monitor: ClaudeCodeMonitor
    @AppStorage(Prefs.Key.claudeCodeRange) private var range = CodeRange.today
    @AppStorage(Prefs.Key.showClaudeCodeCost) private var showCost = true
    @AppStorage(Prefs.Key.showCodeProjects) private var showProjects = true
    @AppStorage(Prefs.Key.showCodeBreakdown) private var showBreakdown = true
    @AppStorage(Prefs.Key.showCodeNote) private var showNote = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Claude Code · \(range.title)").font(.subheadline.weight(.semibold))
                if monitor.scanning { ProgressView().controlSize(.mini) }
                Spacer()
                if let summary = monitor.summary, summary.messages > 0 {
                    Text(formatTokens(summary.totalTokens) + " tokens")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    if showCost { Text(formatCost(summary.cost)).font(.callout.monospacedDigit().weight(.medium)) }
                }
            }

            if let summary = monitor.summary {
                if summary.messages == 0 {
                    Text(range == .today ? "No Claude Code activity today." : "No Claude Code activity in the last 7 days.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(showProjects ? Array(summary.projects.prefix(5)) : []) { project in
                        HStack {
                            Text(project.name).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Text(formatTokens(project.tokens)).monospacedDigit().foregroundStyle(.secondary)
                            if showCost {
                                Text(formatCost(project.cost)).monospacedDigit().frame(minWidth: 52, alignment: .trailing)
                            }
                        }
                        .font(.caption)
                    }
                    if showBreakdown {
                        Text("In \(formatTokens(summary.inputTokens)) · Out \(formatTokens(summary.outputTokens)) · "
                             + "Cache write \(formatTokens(summary.cacheWriteTokens)) · read \(formatTokens(summary.cacheReadTokens))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if showCost && showNote {
                        Text("Cost is what this would cost at API prices, not what your plan charges."
                             + (summary.unpricedModels.isEmpty ? "" : " Not priced: \(summary.unpricedModels.sorted().joined(separator: ", "))."))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                Text("Reading ~/.claude…").font(.caption).foregroundStyle(.secondary)
            }
        }
        .task { if monitor.summary == nil { await monitor.refresh() } }
    }
}

func formatTokens(_ count: Int) -> String {
    switch count {
    case 1_000_000_000...: String(format: "%.1fB", Double(count) / 1_000_000_000)
    case 1_000_000...: String(format: "%.1fM", Double(count) / 1_000_000)
    case 1_000...: String(format: "%.1fK", Double(count) / 1_000)
    default: "\(count)"
    }
}

func formatCost(_ dollars: Double) -> String {
    dollars >= 100 ? String(format: "$%.0f", dollars) : String(format: "$%.2f", dollars)
}
