import SwiftUI
import TindeqCore
import WebKit

/// Owns the WKWebView showing instagram.com/reels and enforces the reels-only
/// policy. The DOM-specific work (next reel, pausing, nav hiding) is done by
/// `Injected/ReelsBridge.js`. This class just calls into it.
@MainActor
final class ReelsWebController: NSObject {
    let webView: WKWebView

    /// Called whenever the main-frame route changes (including SPA pushState routes).
    var onRouteChange: (@MainActor (InstagramRoutes.Route) -> Void)?
    /// Called when ReelsBridge.js has (re)loaded in a new document.
    var onBridgeReady: (@MainActor () -> Void)?

    private(set) var route: InstagramRoutes.Route = .external
    private var observingURL = false
    private var lastReelsURL: URL?
    private var forcedRedirects: [Date] = []

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        // Look like mobile Safari. WKWebView's default UA lacks the Safari token,
        // and Instagram serves a degraded page or "open the app" walls without it.
        let major = UIDevice.current.systemVersion.split(separator: ".").first ?? "18"
        config.applicationNameForUserAgent = "Version/\(major).0 Mobile/15E148 Safari/604.1"

        let contentController = WKUserContentController()
        contentController.addUserScript(WKUserScript(
            source: InstagramRoutes.bridgeConfigScript() + Self.bridgeSource,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))
        config.userContentController = contentController

        webView = WKWebView(frame: .zero, configuration: config)
        super.init()

        contentController.add(WeakScriptHandler(self), name: "tindeq")
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = false
        webView.backgroundColor = .black
        webView.isOpaque = false
        #if DEBUG
        // Lets you attach Safari Web Inspector (Develop menu) to tune ReelsBridge.js.
        webView.isInspectable = true
        #endif

        // WKWebView.url changes on full loads *and* SPA pushState routes, which
        // never reach decidePolicyFor. String KVO avoids key paths to the
        // main-actor-isolated property.
        webView.addObserver(self, forKeyPath: Self.urlKeyPath, options: [.new], context: nil)
        observingURL = true
    }

    private static let urlKeyPath = "URL"

    nonisolated override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        guard keyPath == "URL" else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
            return
        }
        // WKWebView posts KVO on the main thread.
        MainActor.assumeIsolated {
            handleURLChange(webView.url)
        }
    }

    func loadReels() {
        webView.load(URLRequest(url: InstagramRoutes.reelsURL))
    }

    func tearDown() {
        if observingURL {
            webView.removeObserver(self, forKeyPath: Self.urlKeyPath)
            observingURL = false
        }
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "tindeq")
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
    }

    // MARK: - Bridge calls

    /// Scrolls to the next reel and returns ReelsBridge's diagnostic string.
    @discardableResult
    func nextReel() async -> String {
        await callBridge("return window.__tindeq ? await window.__tindeq.nextReel() : 'no-bridge';")
    }

    func setLocked(_ locked: Bool) {
        webView.evaluateJavaScript("window.__tindeq && window.__tindeq.setLocked(\(locked))", completionHandler: nil)
    }

    func setHandsFree(_ enabled: Bool) {
        webView.evaluateJavaScript("window.__tindeq && window.__tindeq.setHandsFree(\(enabled))", completionHandler: nil)
    }

    func diagnose() async -> String {
        await callBridge("return window.__tindeq ? window.__tindeq.diagnose() : 'no-bridge';")
    }

    private func callBridge(_ body: String) async -> String {
        do {
            let result = try await webView.callAsyncJavaScript(body, contentWorld: .page)
            return (result as? String) ?? String(describing: result ?? "nil")
        } catch {
            return "error:\(error.localizedDescription)"
        }
    }

    // MARK: - Reels-only policy

    private func handleURLChange(_ url: URL?) {
        guard let url else { return }
        let newRoute = InstagramRoutes.classify(url)
        switch newRoute {
        case .reels:
            lastReelsURL = url
        case .blocked:
            // An in-page (pushState) navigation away from reels slipped past the
            // link blocker in ReelsBridge.js. Bounce back.
            redirectToReels()
            return
        case .auth, .external:
            break
        }
        if newRoute != route {
            route = newRoute
            onRouteChange?(newRoute)
        }
    }

    private func redirectToReels() {
        let now = Date()
        forcedRedirects = forcedRedirects.filter { now.timeIntervalSince($0) < 10 } + [now]
        // Guard against fighting Instagram in a redirect loop (e.g. if it forces
        // a page we don't allow). Stop enforcing and let it settle.
        guard forcedRedirects.count <= 4 else { return }
        if webView.canGoBack, InstagramRoutes.classify(webView.backForwardList.backItem?.url) == .reels {
            webView.goBack()
        } else {
            webView.load(URLRequest(url: lastReelsURL ?? InstagramRoutes.reelsURL))
        }
    }

    private static let bridgeSource: String = {
        guard let url = Bundle.main.url(forResource: "ReelsBridge", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8) else {
            assertionFailure("ReelsBridge.js missing from app bundle")
            return ""
        }
        return source
    }()
}

// MARK: - WKNavigationDelegate

extension ReelsWebController: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        let url = navigationAction.request.url
        let scheme = url?.scheme?.lowercased() ?? ""

        // Never hand off to the Instagram app, App Store, or other schemes.
        guard ["https", "http", "about", "blob", "data"].contains(scheme) else {
            return .cancel
        }
        // Iframes (ads, captchas, Facebook login widgets) are left alone.
        if let frame = navigationAction.targetFrame, !frame.isMainFrame {
            return .allow
        }
        if scheme == "about" || scheme == "blob" || scheme == "data" {
            return .allow
        }

        switch InstagramRoutes.classify(url) {
        case .reels, .auth:
            return .allow
        case .blocked:
            // Typically "/" after login, or a profile link. Land on reels instead,
            // unless we're already showing reels (then just stay put).
            if route != .reels {
                Task { webView.load(URLRequest(url: InstagramRoutes.reelsURL)) }
            }
            return .cancel
        case .external:
            return .cancel
        }
    }
}

// MARK: - WKUIDelegate

extension ReelsWebController: WKUIDelegate {
    /// target=_blank / window.open: load allowed pages in place, drop the rest.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        let route = InstagramRoutes.classify(navigationAction.request.url)
        if route == .reels || route == .auth {
            webView.load(navigationAction.request)
        }
        return nil
    }
}

// MARK: - Script messages

extension ReelsWebController: WKScriptMessageHandler {
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let body = message.body as? [String: Any] else { return }
        #if DEBUG
        print("[ReelsBridge]", body)
        #endif
        if body["type"] as? String == "ready" {
            onBridgeReady?()
        }
    }
}

/// WKUserContentController retains its handlers strongly; this breaks the cycle.
private final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var target: (any WKScriptMessageHandler)?

    init(_ target: any WKScriptMessageHandler) {
        self.target = target
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        target?.userContentController(userContentController, didReceive: message)
    }
}

/// SwiftUI host for the controller's web view.
struct ReelsWebView: UIViewRepresentable {
    let controller: ReelsWebController

    func makeUIView(context: Context) -> WKWebView {
        controller.webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
