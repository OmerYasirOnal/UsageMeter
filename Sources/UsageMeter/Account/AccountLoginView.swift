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
    /// Curtain phase machine — fed by the Coordinator, rendered by the screen.
    @Published var flow = LoginFlowModel()
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
            if webView === popupWebView, let title = webView.title, !title.isEmpty {
                MainActor.assumeIsolated { popupWindow?.title = title }
            }
            guard let url = webView.url, let host = url.host?.lowercased(),
                  host.contains("claude.ai") || host.contains("claude.com") else { return }
            // Only the main login WebView drives the usage hop — not the OAuth popup.
            guard webView !== popupWebView else { return }
            let path = url.path.lowercased()
            if path.contains("login") || path.contains("auth") || path.contains("oauth") || path.contains("magic") {
                requestedUsage = false   // back in the login flow → re-arm
                MainActor.assumeIsolated { controller.flow.backOnLoginPage() }
                return
            }
            // Logged in — drop the curtain BEFORE any usage content can render.
            MainActor.assumeIsolated { controller.flow.loggedInPageFinished(now: Date()) }
            if path.contains("usage") { return } // already captured-from here
            // Jump to Usage exactly once so the usage request fires (hidden behind
            // the curtain; works for email + Google).
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
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 700),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered, defer: false)
            window.title = "Sign in"
            window.isReleasedWhenClosed = false
            window.contentView = popup
            // Center over the login window (not the screen) so the flow reads
            // as one surface.
            if let parent = webView.window {
                let p = parent.frame
                window.setFrameOrigin(NSPoint(
                    x: p.midX - window.frame.width / 2,
                    y: p.midY - window.frame.height / 2))
            } else {
                window.center()
            }
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
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"

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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var closeTask: Task<Void, Never>?
    @State private var timeoutTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle").foregroundStyle(Theme.accent)
                Text("Sign in to claude.ai").font(.headline)
                Spacer()
                Button { controller.reload() } label: { Image(systemName: "arrow.clockwise") }
                    .help("Reload")
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
                if showsCurtain {
                    curtain
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 1.02)))
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: showsCurtain)

            if case .fetchTimeout = controller.flow.phase {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning)
                    Text("Couldn't fetch your usage yet.").font(.callout)
                    Button("Retry") {
                        controller.flow.retryRequested(now: Date())
                        controller.goToUsage()
                    }
                    .buttonStyle(.borderedProminent).tint(Theme.accent)
                    Spacer()
                }
                .padding(10)
                .background(.quaternary.opacity(0.5))
            }

            Divider()
            VStack(alignment: .leading, spacing: 4) {
                Label("If \u{201C}Continue with Google\u{201D} errors, try \u{201C}Continue with email\u{201D}.",
                      systemImage: "lightbulb")
                    .font(.caption2).foregroundStyle(Theme.accent)
                Text("UsageMeter never sees your password — only your claude.ai login session is stored locally, and Log out wipes it. It reads only usage percentages and reset times, never conversation content. This window closes by itself once your numbers are captured.")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(8)
        }
        .frame(minWidth: 560, minHeight: 640)
        .tint(Theme.accent)
        .managesActivationPolicy()
        .onChange(of: auth.lastCaptured) { _, captured in
            // React ONLY to a genuine usage capture (never while the user is still
            // typing credentials — no usage response fires until logged in).
            guard captured != nil else { return }
            controller.flow.usageCaptured()
        }
        .onChange(of: controller.flow.phase) { _, phase in
            timeoutTask?.cancel()
            switch phase {
            case .fetching(let since):
                timeoutTask = Task { @MainActor in
                    let deadline = since.addingTimeInterval(LoginFlowModel.fetchTimeout)
                    try? await Task.sleep(nanoseconds: UInt64(max(0, deadline.timeIntervalSinceNow) * 1_000_000_000))
                    guard !Task.isCancelled else { return }
                    controller.flow.tick(now: Date())
                }
            case .captured:
                closeTask?.cancel()
                closeTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 800_000_000)
                    guard !Task.isCancelled else { return }
                    dismissWindow(id: AppWindowID.accountLogin)
                }
            case .signingIn, .fetchTimeout, .enterEmail, .autofilling:
                break
            }
        }
        .onDisappear { closeTask?.cancel(); timeoutTask?.cancel() }
    }

    private var showsCurtain: Bool {
        switch controller.flow.phase {
        case .fetching, .captured: return true
        case .signingIn, .fetchTimeout, .enterEmail, .autofilling: return false
        }
    }

    /// Native cover shown from "logged in" until the window closes — the
    /// claude.ai usage page renders invisibly behind it.
    private var curtain: some View {
        VStack(spacing: 14) {
            if case .captured = controller.flow.phase {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44)).foregroundStyle(Theme.ok)
                Text("You're all set").font(.title3.weight(.semibold))
                Text("Usage captured — closing…").font(.callout).foregroundStyle(.secondary)
            } else {
                ProgressView().controlSize(.large)
                Text("Signed in").font(.title3.weight(.semibold))
                Text("Fetching your usage…").font(.callout).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .accessibilityElement(children: .combine)
    }
}
#endif
