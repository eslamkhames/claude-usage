import AppKit
import WebKit

/// A claude.ai window signed in as one account, using that account's cookie jar.
@MainActor
final class BrowserWindowController: NSWindowController, NSWindowDelegate, WKUIDelegate {
    private let webView: WKWebView
    private let onClose: () -> Void

    init(account: Account, onClose: @escaping () -> Void) {
        self.onClose = onClose
        let config = WKWebViewConfiguration()
        config.websiteDataStore = account.dataStore
        webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = safariUserAgent
        webView.allowsBackForwardNavigationGestures = true

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 800),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Claude — \(account.name)"
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("ClaudeBrowser")
        super.init(window: window)

        window.delegate = self
        window.contentView = webView
        webView.uiDelegate = self
        webView.load(URLRequest(url: URL(string: "https://claude.ai/new")!))
    }

    required init?(coder: NSCoder) { fatalError() }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }

    // Links that open a new tab: stay here for claude.ai, use the default browser otherwise.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url {
            if url.host?.hasSuffix("claude.ai") == true {
                webView.load(navigationAction.request)
            } else {
                NSWorkspace.shared.open(url)
            }
        }
        return nil
    }

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.begin { response in
            completionHandler(response == .OK ? panel.urls : nil)
        }
    }
}
