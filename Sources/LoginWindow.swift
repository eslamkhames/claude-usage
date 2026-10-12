import AppKit
import SwiftUI
import WebKit

/// A browser window that signs one account in to claude.ai, storing the cookies in
/// that account's own data store. It closes itself once a session cookie appears.
@MainActor
final class LoginWindowController: NSWindowController, NSWindowDelegate {
    private let account: Account
    private let webView: WKWebView
    private let onFinish: (Bool) -> Void
    private var pollTask: Task<Void, Never>?
    private var finished = false

    init(account: Account, onFinish: @escaping (Bool) -> Void) {
        self.account = account
        self.onFinish = onFinish
        let config = WKWebViewConfiguration()
        config.websiteDataStore = account.dataStore
        webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = safariUserAgent

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 760),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Sign in to Claude — \(account.name)"
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)

        window.delegate = self
        window.contentView = NSHostingView(rootView: LoginView(webView: webView) { [weak self] key in
            self?.useSessionKey(key)
        })
        webView.load(URLRequest(url: URL(string: "https://claude.ai/login")!))
        startPolling()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func startPolling() {
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                let cookies = await self.account.dataStore.httpCookieStore.allCookies()
                let hasSession = cookies.contains { $0.name == "sessionKey" && $0.domain.hasSuffix("claude.ai") }
                let path = self.webView.url?.path ?? ""
                if hasSession && !path.hasPrefix("/login") && !path.hasPrefix("/magic-link") {
                    self.finish(success: true)
                    return
                }
            }
        }
    }

    /// Fallback for logins that don't work in an embedded browser: paste the
    /// `sessionKey` cookie copied from your normal browser's dev tools.
    private func useSessionKey(_ key: String) {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, let cookie = HTTPCookie(properties: [
            .domain: ".claude.ai",
            .path: "/",
            .name: "sessionKey",
            .value: key,
            .secure: "TRUE",
            .expires: Date().addingTimeInterval(60 * 60 * 24 * 30),
        ]) else { return }
        Task {
            await account.dataStore.httpCookieStore.setCookie(cookie)
            finish(success: true)
        }
    }

    private func finish(success: Bool) {
        guard !finished else { return }
        finished = true
        pollTask?.cancel()
        window?.close()
        onFinish(success)
    }

    func windowWillClose(_ notification: Notification) {
        if !finished {
            finished = true
            pollTask?.cancel()
            onFinish(false)
        }
    }
}

private struct LoginView: View {
    let webView: WKWebView
    let onSessionKey: (String) -> Void
    @State private var showKeyField = false
    @State private var key = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if showKeyField {
                    SecureField("Paste sessionKey (sk-ant-sid…)", text: $key)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { onSessionKey(key) }
                    Button("Use key") { onSessionKey(key) }
                        .disabled(key.isEmpty)
                } else {
                    Text("Sign in below. Tip: use “Continue with email” if Google sign-in is blocked.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Paste session key instead") { showKeyField = true }
                        .controlSize(.small)
                }
            }
            .padding(10)
            Divider()
            WebView(webView: webView)
        }
    }
}

private struct WebView: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
