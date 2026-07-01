#if !APPSTORE
import SwiftUI
import WebKit
import UsageMeterKit

/// Imperative handle to drive the login WebView from the surrounding SwiftUI view.
@MainActor
final class LoginWebController: ObservableObject {
    fileprivate weak var webView: WKWebView?
    /// First page finished loading — used to hide the loading overlay.
    @Published var hasLoadedOnce = false
    func reload() { webView?.reload() }
    func goToUsage() { webView?.load(URLRequest(url: AccountLoginView.usagePageURL)) }
}

/// A `WKWebView` showing claude.ai's real login page. The user authenticates
/// normally (we never see the password); session cookies persist in an isolated
/// `WKWebsiteDataStore`. An injected hook reports ONLY usage-shaped first-party
/// responses so the endpoint is discovered empirically (brief §3.2).
struct AccountLoginView: NSViewRepresentable {
    let auth: AccountAuth
    let controller: LoginWebController

    func makeCoordinator() -> Coordinator { Coordinator(auth: auth, controller: controller) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = auth.dataStore
        config.preferences.javaScriptCanOpenWindowsAutomatically = true

        let userContent = WKUserContentController()
        userContent.add(context.coordinator, name: Self.messageName)
        userContent.addUserScript(WKUserScript(
            source: Self.captureScript, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        config.userContentController = userContent

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        // Google etc. refuse OAuth in "embedded" WebViews via UA sniffing.
        webView.customUserAgent = Self.safariUserAgent
        controller.webView = webView

        let start = ProcessInfo.processInfo.environment["USAGEMETER_MOCK_USAGE_URL"]
            .flatMap { URL(string: $0) } ?? Self.usagePageURL
        webView.load(URLRequest(url: start))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        nsView.configuration.userContentController.removeScriptMessageHandler(forName: messageName)
        nsView.configuration.userContentController.removeAllUserScripts()
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
        private let auth: AccountAuth
        private let controller: LoginWebController
        private var requestedUsage = false
        private var popupWindow: NSWindow?
        private var popupWebView: WKWebView?

        init(auth: AccountAuth, controller: LoginWebController) {
            self.auth = auth
            self.controller = controller
        }

        func userContentController(_ controller: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard message.name == AccountLoginView.messageName,
                  let dict = message.body as? [String: Any],
                  let url = dict["url"] as? String, !url.isEmpty else { return }
            let status = (dict["status"] as? Int) ?? 0
            let body = (dict["body"] as? String) ?? ""
            let auth = self.auth
            Task { @MainActor in auth.ingestCapture(url: url, status: status, body: body) }
        }

        /// After login, claude.ai lands on the app home; hop to the Usage page once
        /// so the usage request fires and gets captured (fixes the "blank after
        /// login" dead end).
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            MainActor.assumeIsolated { controller.hasLoadedOnce = true }
            guard let url = webView.url, let host = url.host?.lowercased(),
                  host.contains("claude.ai") || host.contains("claude.com") else { return }
            // Only the main login WebView drives the usage hop — not the OAuth popup.
            guard webView !== popupWebView else { return }
            let path = url.path.lowercased()
            if path.contains("login") || path.contains("auth") || path.contains("oauth") || path.contains("magic") {
                requestedUsage = false   // back in the login flow → re-arm
                return
            }
            if path.contains("usage") { return } // already captured-from here
            // Logged in and landed on an app page → jump to Usage exactly once so the
            // usage request fires (works for email + Google; fixes the blank dead-end).
            if !requestedUsage {
                requestedUsage = true
                webView.load(URLRequest(url: AccountLoginView.usagePageURL))
            }
        }

        /// Real OAuth popup (e.g. "Continue with Google"): host a secondary WebView
        /// in its own window, sharing the same `configuration` (and thus the same
        /// cookie/data store), so the opener / window.close() / postMessage handshake
        /// the provider relies on works. Loading it in the main frame breaks Google.
        func webView(_ webView: WKWebView,
                     createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            let popup = WKWebView(frame: .zero, configuration: configuration)
            popup.customUserAgent = AccountLoginView.safariUserAgent
            popup.navigationDelegate = self
            popup.uiDelegate = self

            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 660),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered, defer: false)
            window.title = "Sign in"
            window.isReleasedWhenClosed = false
            window.contentView = popup
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)

            popupWindow = window
            popupWebView = popup
            return popup
        }

        /// The provider's popup called window.close() — tear down its window.
        func webViewDidClose(_ webView: WKWebView) {
            guard webView === popupWebView else { return }
            popupWindow?.close()
            popupWindow = nil
            popupWebView = nil
        }
    }

    // MARK: - Constants

    static let messageName = "usageProbe"
    static let usagePageURL = URL(string: "https://claude.ai/settings/usage")!
    static let safariUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.3 Safari/605.1.15"

    /// Wraps `fetch`/`XHR`. Reports the URL for first-party API calls (discovery),
    /// but sends the response BODY only for usage-shaped URLs.
    static let captureScript = #"""
    (function () {
      function abs(u) { try { return new URL(u, location.href).href; } catch (e) { return String(u || ''); } }
      function isApi(u) {
        u = String(u || '').toLowerCase();
        return u.indexOf('/api/') > -1 || u.indexOf('usage') > -1 ||
               u.indexOf('rate') > -1 || u.indexOf('limit') > -1 || u.indexOf('quota') > -1;
      }
      function isUsage(u) {
        u = String(u || '').toLowerCase();
        return u.indexOf('usage') > -1 || u.indexOf('rate_limit') > -1 ||
               u.indexOf('ratelimit') > -1 || u.indexOf('rate-limit') > -1 ||
               u.indexOf('utilization') > -1 || u.indexOf('quota') > -1;
      }
      function send(url, status, body) {
        try {
          window.webkit.messageHandlers.usageProbe.postMessage({
            url: String(url), status: status | 0,
            body: (typeof body === 'string' ? body.slice(0, 20000) : '')
          });
        } catch (e) {}
      }
      function report(url, status, getBody) {
        var path;
        try { path = new URL(url, location.href).pathname; } catch (e) { path = String(url); }
        if (!isApi(path)) return;                       // gate on PATH, not query string
        if (isUsage(path)) { try { getBody(function (t) { send(url, status, t); }); } catch (e) {} }
        else { send(url, status, ''); }
      }
      try {
        var origFetch = window.fetch;
        if (origFetch) {
          window.fetch = function () {
            var args = arguments;
            var url = abs((args[0] && args[0].url) ? args[0].url : args[0]);
            var p = origFetch.apply(this, args);
            try {
              p.then(function (resp) {
                report(url, resp.status, function (cb) {
                  resp.clone().text().then(cb).catch(function () {});
                });
              }).catch(function () {});
            } catch (e) {}
            return p;
          };
        }
      } catch (e) {}
      try {
        var origOpen = XMLHttpRequest.prototype.open;
        XMLHttpRequest.prototype.open = function (m, u) { this.__umURL = u; return origOpen.apply(this, arguments); };
        var origSend = XMLHttpRequest.prototype.send;
        XMLHttpRequest.prototype.send = function () {
          var xhr = this;
          try {
            xhr.addEventListener('load', function () {
              try {
                var u = abs(xhr.__umURL);
                report(u, xhr.status, function (cb) {
                  var rt = xhr.responseType;
                  if (rt === '' || rt === 'text') { cb(xhr.responseText); }
                  else if (rt === 'json') { try { cb(JSON.stringify(xhr.response)); } catch (e) {} }
                });
              } catch (e) {}
            });
          } catch (e) {}
          return origSend.apply(this, arguments);
        };
      } catch (e) {}
    })();
    """#
}

/// Window content hosting the login WebView with a toolbar.
struct AccountLoginScreen: View {
    @ObservedObject var auth: AccountAuth
    @StateObject private var controller = LoginWebController()
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var closeTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle").foregroundStyle(Theme.accent)
                Text("Sign in to claude.ai").font(.headline)
                if auth.isAuthenticated {
                    Label("Captured — closing…", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(Theme.ok).font(.callout)
                }
                Spacer()
                Button { controller.goToUsage() } label: { Label("Usage Page", systemImage: "chart.bar") }
                Button { controller.reload() } label: { Image(systemName: "arrow.clockwise") }
                Button("Done") { dismissWindow(id: AppWindowID.accountLogin) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
            }
            .padding(10)

            Divider()

            ZStack {
                AccountLoginView(auth: auth, controller: controller)
                if !controller.hasLoadedOnce {
                    VStack(spacing: 12) {
                        ProgressView().controlSize(.large)
                        Text("Loading claude.ai…").font(.callout).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.background)
                }
            }

            Divider()
            VStack(alignment: .leading, spacing: 4) {
                Label("If \u{201C}Continue with Google\u{201D} errors, try \u{201C}Continue with email\u{201D}.",
                      systemImage: "lightbulb")
                    .font(.caption2).foregroundStyle(Theme.accent)
                Text("UsageMeter never sees your password — only your claude.ai login session is stored locally, and Log out wipes it. It reads only your usage percentages and reset times — never conversation content. After signing in, the Usage page opens automatically and this window closes once your numbers are captured.")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(8)
        }
        .frame(minWidth: 860, minHeight: 680)
        .tint(Theme.accent)
        .managesActivationPolicy()
        .onChange(of: auth.lastCaptured) { _, captured in
            // Close ONLY after a genuine usage capture (never while the user is still
            // typing credentials — no usage response fires until logged in). 2.5s,
            // cancellable so it can't close the wrong window or fire twice.
            guard captured != nil else { return }
            closeTask?.cancel()
            closeTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                guard !Task.isCancelled else { return }
                dismissWindow(id: AppWindowID.accountLogin)
            }
        }
        .onDisappear { closeTask?.cancel() }
    }
}
#endif
