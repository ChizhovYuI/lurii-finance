import AppKit
import WebKit

enum WebSyncWebViewError: LocalizedError {
    case loadAlreadyInProgress
    case navigationFailed(String)
    case unexpectedScriptResult

    var errorDescription: String? {
        switch self {
        case .loadAlreadyInProgress:
            return "Page load is already in progress."
        case let .navigationFailed(message):
            return "Unable to load page: \(message)"
        case .unexpectedScriptResult:
            return "Unexpected script result."
        }
    }
}

@MainActor
final class WebSyncWebViewHost: NSObject, NSWindowDelegate, WKNavigationDelegate {
    enum Mode {
        case visible
        case hidden
    }

    let window: NSWindow
    let webView: WKWebView
    private let mode: Mode
    var onWindowWillClose: (() -> Void)?
    private(set) var isClosed = false
    private var loadContinuation: CheckedContinuation<Void, Error>?
    private var closeNotified = false

    init(title: String, mode: Mode) {
        self.mode = mode
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        webView = WKWebView(frame: .zero, configuration: configuration)

        switch mode {
        case .visible:
            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1200, height: 820),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
        case .hidden:
            window = NSWindow(
                contentRect: NSRect(x: -10_000, y: -10_000, width: 1200, height: 820),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.isOpaque = false
            window.alphaValue = 0.01
            window.backgroundColor = .clear
            window.ignoresMouseEvents = true
            window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        }

        super.init()
        window.title = title
        window.animationBehavior = .none
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.delegate = self
        window.contentView = webView
        webView.navigationDelegate = self

        switch mode {
        case .visible:
            window.center()
            window.makeKeyAndOrderFront(nil)
        case .hidden:
            window.orderFront(nil)
        }
    }

    var cookieStore: WKHTTPCookieStore {
        webView.configuration.websiteDataStore.httpCookieStore
    }

    func load(url: URL) async throws {
        guard loadContinuation == nil else {
            throw WebSyncWebViewError.loadAlreadyInProgress
        }

        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
        _ = webView.load(request)
        try await withCheckedThrowingContinuation { continuation in
            loadContinuation = continuation
        }
    }

    func loadForDisplay(url: URL) {
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
        _ = webView.load(request)
    }

    func evaluateScriptReturningString(_ script: String) async throws -> String {
        let result = try await webView.evaluateJavaScript(script)
        if let string = result as? String {
            return string
        }
        throw WebSyncWebViewError.unexpectedScriptResult
    }

    func close() {
        guard !isClosed else { return }
        prepareForClose()
        notifyCloseIfNeeded()
        // `window.close()` was causing intermittent crashes during WebView teardown.
        // Keep teardown idempotent and just hide/order out for sync hosts.
        window.orderOut(nil)
    }

    func windowWillClose(_ notification: Notification) {
        if !isClosed {
            prepareForClose()
        }
        notifyCloseIfNeeded()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        close()
        return false
    }

    private func prepareForClose() {
        isClosed = true
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        if window.contentView === webView {
            window.contentView = nil
        }
        window.delegate = nil
        if let loadContinuation {
            self.loadContinuation = nil
            loadContinuation.resume(throwing: WebSyncWebViewError.navigationFailed("Window closed"))
        }
    }

    private func notifyCloseIfNeeded() {
        guard !closeNotified else { return }
        closeNotified = true
        onWindowWillClose?()
    }

    deinit {
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        window.delegate = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let loadContinuation else { return }
        self.loadContinuation = nil
        loadContinuation.resume()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard let loadContinuation else { return }
        self.loadContinuation = nil
        loadContinuation.resume(throwing: WebSyncWebViewError.navigationFailed(error.localizedDescription))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard let loadContinuation else { return }
        self.loadContinuation = nil
        loadContinuation.resume(throwing: WebSyncWebViewError.navigationFailed(error.localizedDescription))
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        if let loadContinuation {
            self.loadContinuation = nil
            loadContinuation.resume(throwing: WebSyncWebViewError.navigationFailed("Web content process terminated"))
        }
    }
}
