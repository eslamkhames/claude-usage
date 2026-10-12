import Foundation
import WebKit

let safariUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"

@MainActor
private var dataStores: [UUID: WKWebsiteDataStore] = [:]

extension Account {
    /// Each account gets its own isolated cookie jar, so several claude.ai logins can coexist.
    /// One instance per account is kept for the app's lifetime so every web view shares it.
    @MainActor
    var dataStore: WKWebsiteDataStore {
        if let store = dataStores[id] { return store }
        let store = WKWebsiteDataStore(forIdentifier: id)
        dataStores[id] = store
        return store
    }

    /// Forgets the in-memory store so `WKWebsiteDataStore.remove(forIdentifier:)` can delete it.
    @MainActor
    func releaseDataStore() {
        dataStores[id] = nil
    }
}

/// Talks to claude.ai's internal API through an invisible WKWebView that uses the
/// account's cookie jar. Going through a real WebKit page (instead of URLSession)
/// means Cloudflare checks and cookie refreshes are handled like in Safari.
@MainActor
final class ClaudeWebSession: NSObject, WKNavigationDelegate {
    private let webView: WKWebView
    private var loadContinuation: CheckedContinuation<Void, Error>?

    private init(store: WKWebsiteDataStore) {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = store
        webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = safariUserAgent
        super.init()
        webView.navigationDelegate = self
    }

    static func open(for account: Account) async throws -> ClaudeWebSession {
        let session = ClaudeWebSession(store: account.dataStore)
        try await session.loadOrigin()
        // Only check cookies once a web view has loaded the store: before that WebKit
        // can report an empty cookie jar even though the account is signed in.
        let cookies = await account.dataStore.httpCookieStore.allCookies()
        guard cookies.contains(where: { $0.name == "sessionKey" && $0.domain.hasSuffix("claude.ai") }) else {
            throw UsageError.notSignedIn
        }
        return session
    }

    /// Loads a lightweight claude.ai URL so later `fetch` calls run same-origin.
    private func loadOrigin() async throws {
        let timeout = Task { [weak self] in
            try await Task.sleep(for: .seconds(30))
            self?.finishLoad(UsageError.timedOut)
        }
        defer { timeout.cancel() }
        try await withCheckedThrowingContinuation { continuation in
            loadContinuation = continuation
            webView.load(URLRequest(url: URL(string: "https://claude.ai/api/organizations")!))
        }

        // A Cloudflare interstitial reloads the page by itself once it's solved.
        for _ in 0..<30 {
            let title = (try? await webView.evaluateJavaScript("document.title")) as? String ?? ""
            if !title.localizedCaseInsensitiveContains("just a moment") { return }
            try await Task.sleep(for: .milliseconds(500))
        }
        throw UsageError.blocked
    }

    private func finishLoad(_ error: Error?) {
        guard let continuation = loadContinuation else { return }
        loadContinuation = nil
        if let error { continuation.resume(throwing: error) } else { continuation.resume() }
    }

    func getJSON(_ path: String) async throws -> Any {
        let result = try await webView.callAsyncJavaScript(
            """
            const r = await fetch(path, { credentials: 'include', headers: { 'Accept': 'application/json' } });
            return [r.status, await r.text()];
            """,
            arguments: ["path": path],
            contentWorld: .defaultClient
        )
        guard let pair = result as? [Any], pair.count == 2,
              let status = (pair[0] as? NSNumber)?.intValue,
              let text = pair[1] as? String else { throw UsageError.badResponse }

        switch status {
        case 200:
            guard let data = text.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) else { throw UsageError.badResponse }
            return json
        case 401, 403:
            // Cloudflare answers with an HTML challenge page; claude.ai itself with a JSON error.
            if text.localizedCaseInsensitiveContains("<html") { throw UsageError.blocked }
            throw UsageError.notSignedIn
        case 429:
            throw UsageError.rateLimited
        default:
            throw UsageError.http(status)
        }
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finishLoad(nil)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finishLoad(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finishLoad(error)
    }
}
