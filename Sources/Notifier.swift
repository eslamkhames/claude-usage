import AppKit
import UserNotifications

/// Posts the threshold, reset and signed-out notifications. Each window notifies at most
/// once per level (warning, critical) until it resets or drops back down.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    private var levels: [String: Int]

    override init() {
        levels = UserDefaults.standard.dictionary(forKey: "notifiedLevels") as? [String: Int] ?? [:]
        super.init()
        center.delegate = self
    }

    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound]) { _, error in
            if let error { NSLog("ClaudeBar: notification permission failed: \(error)") }
        }
    }

    func usageUpdated(account: Account, usage: Usage) {
        guard Prefs.notifyEnabled, account.notify else { return }
        var windows: [(kind: WindowKind, title: String, window: UsageWindow?)] = [(.session, "5-hour session", usage.session)]
        if Prefs.notifyWeekly { windows.append((.weekly, "weekly limit", usage.weekly)) }

        for (kind, title, window) in windows {
            guard let window else { continue }
            // Keyed by window so a new session starts from zero again.
            let slot = Int((window.resetsAt?.timeIntervalSince1970 ?? 0) / 600)
            let key = "\(account.id)-\(kind.rawValue)-\(slot)"
            let level = window.percent >= Double(Prefs.criticalThreshold) ? 2
                : window.percent >= Double(Prefs.warnThreshold) ? 1 : 0
            let previous = levels[key] ?? 0
            levels[key] = level
            guard level > previous else { continue }

            var body = level == 2 ? "Almost at the limit." : "Getting close to the limit."
            if let reset = window.resetsAt {
                body += " Resets " + reset.formatted(.relative(presentation: .named)) + "."
            }
            post(id: key, title: "\(account.name): \(Int(window.percent.rounded()))% of \(title) used", body: body)
        }
        prune()
    }

    func limitReset(account: Account, kind: WindowKind, previousPercent: Double) {
        guard Prefs.notifyEnabled, Prefs.notifyReset, account.notify,
              previousPercent >= Double(Prefs.warnThreshold),
              kind == .session || Prefs.notifyWeekly else { return }
        let title = kind == .session ? "5-hour session" : "weekly limit"
        post(id: "\(account.id)-reset-\(kind.rawValue)", title: "\(account.name): \(title) reset", body: "Full usage is available again.")
    }

    func signedOut(_ account: Account) {
        guard Prefs.notifyEnabled, Prefs.notifySignedOut, account.notify else { return }
        post(id: "\(account.id)-signedout", title: "\(account.name) is signed out",
             body: "Sign in again from ClaudeBar to keep tracking its usage.")
    }

    func test() {
        requestAuthorization()
        post(id: "test", title: "ClaudeBar notifications work", body: "You'll be told when an account gets close to a limit.")
    }

    private func post(id: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    private func prune() {
        // Keys end in a 10-minute slot number; forget windows that ended over 8 days ago.
        let oldest = Int((Date().timeIntervalSince1970 - 8 * 86_400) / 600)
        levels = levels.filter { key, _ in
            guard let slot = Int(key.split(separator: "-").last ?? "") else { return false }
            return slot == 0 || slot >= oldest
        }
        UserDefaults.standard.set(levels, forKey: "notifiedLevels")
    }

    // MARK: UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        await MainActor.run { StatusItemPanel.toggle() }
    }
}
