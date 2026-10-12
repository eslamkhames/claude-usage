import AppKit

/// Checks the GitHub repo's latest release and installs it in place of the running app.
@MainActor
final class Updater: ObservableObject {
    struct Release: Equatable {
        var version: String
        var download: URL
        var page: URL
    }

    static let repo = "eslamkhames/claude-usage"
    static var repoURL: URL { URL(string: "https://github.com/\(repo)")! }

    @Published private(set) var available: Release?
    @Published private(set) var status: String?
    @Published private(set) var busy = false
    let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"

    func checkIfDue() async {
        guard Prefs.autoCheckUpdates else { return }
        let last = UserDefaults.standard.object(forKey: "lastUpdateCheck") as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) > 86_400 else { return }
        await check()
    }

    func check() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        UserDefaults.standard.set(Date(), forKey: "lastUpdateCheck")
        do {
            var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest")!)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else {
                status = "No published release found"
                return
            }
            let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            let assets = json["assets"] as? [[String: Any]] ?? []
            guard let zip = assets.first(where: { ($0["name"] as? String)?.hasSuffix(".zip") == true }),
                  let link = zip["browser_download_url"] as? String, let download = URL(string: link) else {
                status = "Release \(version) has no app download"
                return
            }
            let page = (json["html_url"] as? String).flatMap(URL.init(string:)) ?? Self.repoURL
            if Self.isNewer(version, than: currentVersion) {
                available = Release(version: version, download: download, page: page)
                status = "Version \(version) is available"
            } else {
                available = nil
                status = "Up to date (\(currentVersion))"
            }
        } catch {
            status = "Update check failed: \(error.localizedDescription)"
        }
    }

    static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }
        let y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }

    func install() async {
        guard let release = available, !busy else { return }
        busy = true
        defer { busy = false }
        status = "Downloading \(release.version)…"
        do {
            let dir = FileManager.default.temporaryDirectory.appending(path: "ClaudeBarUpdate-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let (downloaded, _) = try await URLSession.shared.download(from: release.download)
            let zip = dir.appending(path: "ClaudeBar.zip")
            try FileManager.default.moveItem(at: downloaded, to: zip)
            try Self.run("/usr/bin/ditto", ["-x", "-k", zip.path, dir.path])

            let newApp = dir.appending(path: "ClaudeBar.app")
            guard Bundle(url: newApp)?.bundleIdentifier == Bundle.main.bundleIdentifier else {
                status = "The download doesn't contain ClaudeBar.app"
                return
            }
            // Swap the bundles once this process has exited, then relaunch.
            let script = "while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done; "
                + "rm -rf \"$2\" && mv \"$1\" \"$2\" && open \"$2\""
            let swap = Process()
            swap.executableURL = URL(fileURLWithPath: "/bin/sh")
            swap.arguments = ["-c", script, "sh", newApp.path, Bundle.main.bundlePath]
            try swap.run()
            NSApp.terminate(nil)
        } catch {
            status = "Update failed: \(error.localizedDescription)"
        }
    }

    private static func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "ClaudeBar", code: Int(process.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "\(tool) failed"])
        }
    }
}
