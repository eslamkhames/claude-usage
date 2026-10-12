import AppKit
import Network
import ServiceManagement
import WebKit

@MainActor
final class AccountStore: ObservableObject {
    @Published private(set) var accounts: [Account] = []
    @Published private(set) var usage: [UUID: Usage] = [:]
    @Published private(set) var problems: [UUID: UsageError] = [:]
    @Published private(set) var loading: Set<UUID> = []
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var lastSuccess: [UUID: Date] = [:]
    /// Ticks every 30 seconds so countdowns, stale markers and passed resets stay current.
    @Published private(set) var now = Date()

    @Published var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled {
        didSet {
            do {
                if launchAtLogin { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("ClaudeBar: launch at login failed: \(error)")
            }
        }
    }

    let history = HistoryStore()
    let notifier = Notifier()
    let claudeCode = ClaudeCodeMonitor()
    let updater = Updater()

    private let defaults = UserDefaults.standard
    private var timer: Task<Void, Never>?
    private var ticker: Task<Void, Never>?
    private var loginWindows: [UUID: LoginWindowController] = [:]
    private var browserWindows: [UUID: BrowserWindowController] = [:]
    private var handledResets: Set<String> = []
    private var planChecked: Set<UUID> = []
    private var refreshingAll = false
    private let pathMonitor = NWPathMonitor()
    private var online = true
    private var wakeObserver: NSObjectProtocol?

    init() {
        Prefs.register()
        if let data = defaults.data(forKey: "accounts"),
           let saved = try? JSONDecoder().decode([Account].self, from: data) {
            accounts = saved
        }
        startTimer()
        startTicker()
        watchNetworkAndWake()
        HotKeyManager.shared.apply()
        if Prefs.notifyEnabled { notifier.requestAuthorization() }
    }

    // MARK: Derived values

    /// A window as it stands now: empty once its reset time has passed, if that setting is on.
    func current(_ window: UsageWindow?) -> UsageWindow? {
        window?.current(at: now, autoReset: Prefs.autoZeroAfterReset)
    }

    /// True when the numbers shown are not from a recent successful refresh.
    func isStale(_ id: UUID) -> Bool {
        guard usage[id] != nil else { return false }
        if problems[id] != nil { return true }
        guard let last = lastSuccess[id] else { return true }
        return now.timeIntervalSince(last) > Double(max(3 * Prefs.refreshMinutes, 15) * 60)
    }

    /// The signed-in account with the most room left across its session and weekly limits.
    func bestAccountId() -> UUID? {
        let candidates = accounts.compactMap { account -> (id: UUID, load: Double)? in
            guard problems[account.id] != .notSignedIn, let usage = usage[account.id] else { return nil }
            let load = [current(usage.session), current(usage.weekly)].compactMap { $0?.percent }.max() ?? 0
            return (account.id, load)
        }
        guard candidates.count > 1 else { return nil }
        return candidates.min { $0.load < $1.load }?.id
    }

    func menuBarEntries(metric: MenuBarMetric) -> [MenuBarEntry] {
        accounts.filter(\.showInMenuBar).map { account in
            let session = current(usage[account.id]?.session)
            let weekly = current(usage[account.id]?.weekly)
            let chosen: UsageWindow? = switch metric {
            case .session: session
            case .weekly: weekly
            case .highest: [session, weekly].compactMap { $0 }.max { $0.percent < $1.percent }
            }
            return MenuBarEntry(
                label: account.menuBarLabel,
                percent: chosen?.percent,
                session: session?.percent,
                weekly: weekly?.percent,
                resetsAt: chosen?.resetsAt,
                signedOut: problems[account.id] == .notSignedIn,
                stale: isStale(account.id)
            )
        }
    }

    // MARK: Refreshing

    func restartTimer() {
        startTimer()
    }

    private func startTimer() {
        timer?.cancel()
        timer = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshAll()
                await self?.updater.checkIfDue()
                try? await Task.sleep(for: .seconds(Prefs.refreshMinutes * 60))
            }
        }
    }

    private func startTicker() {
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                self?.tick()
            }
        }
    }

    private func tick() {
        now = Date()
        // When a window's reset time passes, say so and fetch the fresh numbers.
        for account in accounts {
            guard let usage = usage[account.id] else { continue }
            var needsRefresh = false
            for (kind, window) in [(WindowKind.session, usage.session), (.weekly, usage.weekly)] {
                guard let window, let reset = window.resetsAt, reset <= now else { continue }
                guard handledResets.insert("\(account.id)-\(kind.rawValue)-\(reset.timeIntervalSince1970)").inserted else { continue }
                notifier.limitReset(account: account, kind: kind, previousPercent: window.percent)
                needsRefresh = true
            }
            if needsRefresh { Task { await refresh(account.id) } }
        }
    }

    private func watchNetworkAndWake() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let isOnline = path.status == .satisfied
            Task { @MainActor in self?.networkChanged(isOnline) }
        }
        pathMonitor.start(queue: .global(qos: .utility))
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.didWake() }
        }
    }

    private func networkChanged(_ isOnline: Bool) {
        let cameBack = isOnline && !online
        online = isOnline
        if cameBack && Prefs.refreshOnWake { Task { await refreshAll() } }
    }

    private func didWake() {
        guard Prefs.refreshOnWake else { return }
        Task {
            // Give Wi-Fi a moment to reconnect.
            try? await Task.sleep(for: .seconds(5))
            await refreshAll()
        }
    }

    func refreshAll() async {
        guard !refreshingAll else { return }
        refreshingAll = true
        defer { refreshingAll = false }
        if online {
            // One account at a time, so claude.ai doesn't see a burst of parallel requests.
            for account in accounts {
                await refresh(account.id)
            }
            lastRefresh = Date()
        }
        if Prefs.showClaudeCode { await claudeCode.refresh() }
    }

    func refresh(_ id: UUID) async {
        guard var account = accounts.first(where: { $0.id == id }), !loading.contains(id) else { return }
        loading.insert(id)
        defer { loading.remove(id) }

        do {
            let session = try await ClaudeWebSession.open(for: account)
            if account.orgId == nil || (account.plan == nil && !planChecked.contains(id)) {
                planChecked.insert(id)
                let org = try await pickOrganization(session, preferring: account.orgId)
                account.orgId = org.id
                account.plan = org.plan
                edit(account) { $0.orgId = org.id; $0.plan = org.plan }
            }
            let json = try await session.getJSON("/api/organizations/\(account.orgId!)/usage")
            guard let dict = json as? [String: Any] else { throw UsageError.badResponse }
            guard accounts.contains(where: { $0.id == id }) else { return } // removed meanwhile
            let fresh = Usage(json: dict)
            usage[id] = fresh
            problems[id] = nil
            lastSuccess[id] = Date()
            now = Date()
            history.record(id, fresh)
            notifier.usageUpdated(account: account, usage: fresh)
        } catch let error as UsageError {
            guard accounts.contains(where: { $0.id == id }) else { return }
            if error == .notSignedIn && problems[id] != .notSignedIn { notifier.signedOut(account) }
            problems[id] = error
            // The saved organization may have gone away; pick again next time.
            if case .http(404) = error { edit(account) { $0.orgId = nil } }
        } catch {
            NSLog("ClaudeBar: refresh failed: \(error)")
            problems[id] = .badResponse
        }
    }

    private func pickOrganization(_ session: ClaudeWebSession, preferring orgId: String?) async throws -> (id: String, plan: String?) {
        guard let orgs = try await session.getJSON("/api/organizations") as? [[String: Any]] else {
            throw UsageError.badResponse
        }
        func has(_ org: [String: Any], _ capability: String) -> Bool {
            (org["capabilities"] as? [String])?.contains(capability) ?? false
        }
        // Keep the saved org if it still exists; otherwise prefer the one carrying the
        // Pro/Max subscription over API-only orgs.
        let chosen = orgs.first { orgId != nil && $0["uuid"] as? String == orgId }
            ?? orgs.first { has($0, "claude_max") || has($0, "claude_pro") }
            ?? orgs.first { has($0, "chat") }
            ?? orgs.first
        guard let chosen, let id = chosen["uuid"] as? String else { throw UsageError.noOrganization }

        let tier = (chosen["rate_limit_tier"] as? String ?? "").lowercased()
        let plan: String? = if tier.contains("max_20x") { "Max 20x" }
            else if tier.contains("max_5x") { "Max 5x" }
            else if has(chosen, "claude_max") { "Max" }
            else if has(chosen, "claude_pro") { "Pro" }
            else if has(chosen, "raven") { "Team" }
            else if has(chosen, "chat") { "Free" }
            else { nil }
        return (id, plan)
    }

    // MARK: Managing accounts

    func addAccount(named name: String) {
        let account = Account(id: UUID(), name: name)
        accounts.append(account)
        save()
        signIn(account, isNew: true)
    }

    func signIn(_ account: Account, isNew: Bool = false) {
        if let existing = loginWindows[account.id] {
            existing.showWindow(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let controller = LoginWindowController(account: account) { [weak self] success in
            guard let self else { return }
            self.loginWindows[account.id] = nil
            if success {
                Task { await self.refresh(account.id) }
            } else if isNew {
                self.remove(account)
            }
        }
        loginWindows[account.id] = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func openBrowser(_ account: Account) {
        let controller = browserWindows[account.id] ?? BrowserWindowController(account: account) { [weak self] in
            self?.browserWindows[account.id] = nil
        }
        browserWindows[account.id] = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func edit(_ account: Account, _ change: (inout Account) -> Void) {
        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else { return }
        change(&accounts[index])
        save()
    }

    func move(_ account: Account, by offset: Int) {
        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else { return }
        let target = index + offset
        guard accounts.indices.contains(target) else { return }
        accounts.swapAt(index, target)
        save()
    }

    func remove(_ account: Account) {
        accounts.removeAll { $0.id == account.id }
        usage[account.id] = nil
        problems[account.id] = nil
        lastSuccess[account.id] = nil
        save()
        history.remove(account.id)
        // Close its windows first so nothing keeps the cookie store alive or signs it back in.
        loginWindows.removeValue(forKey: account.id)?.close()
        browserWindows.removeValue(forKey: account.id)?.close()
        account.releaseDataStore()
        Task { try? await WKWebsiteDataStore.remove(forIdentifier: account.id) }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(accounts) {
            defaults.set(data, forKey: "accounts")
        }
    }
}
