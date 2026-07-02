# Login-Flow Curtain Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** After signing in to claude.ai, the user never sees the claude.ai usage page — a native "fetching your usage…" curtain covers the WebView until capture succeeds and the window closes fast; the Google OAuth popup is hardened and the window chrome is slimmed.

**Architecture:** A pure `LoginFlowModel` phase reducer lives in UsageMeterKit (testable, precedent `AccountRefreshPolicy`); `LoginWebController` publishes it; the existing Coordinator `didFinish` logic feeds it events; `AccountLoginScreen` renders the curtain from the phase. The empirical capture/discovery pipeline is untouched — the hop to `/settings/usage` still happens, just hidden.

**Tech Stack:** Swift 6, SwiftUI, WebKit, swift-testing (`@Test`/`#expect`) as used in `Tests/UsageMeterKitTests`.

## Global Constraints

- Everything app-side is inside `#if !APPSTORE` (already the case for both files touched).
- All new colors/UI follow Kiln: chrome = `Theme.accent`, success = `Theme.ok`; respect `accessibilityReduceMotion`.
- Privacy hard rule unchanged: no new endpoints, no content reads.
- Verify BOTH variants: `swift build` and `swift build -Xswiftc -DAPPSTORE`.
- `make test` must stay green (144 existing tests + new ones).

---

### Task 1: `LoginFlowModel` reducer (Kit, TDD)

**Files:**
- Create: `Sources/UsageMeterKit/Account/LoginFlowModel.swift`
- Test: `Tests/UsageMeterKitTests/LoginFlowModelTests.swift`

**Interfaces:**
- Consumes: nothing (Foundation only).
- Produces (Task 2 relies on these exact names):
  ```swift
  public struct LoginFlowModel: Equatable, Sendable {
      public enum Phase: Equatable, Sendable {
          case signingIn
          case fetching(since: Date)
          case captured
          case fetchTimeout
      }
      public static let fetchTimeout: TimeInterval = 15
      public private(set) var phase: Phase
      public init()
      public mutating func loggedInPageFinished(now: Date)
      public mutating func backOnLoginPage()
      public mutating func usageCaptured()
      public mutating func tick(now: Date)
      public mutating func retryRequested(now: Date)
  }
  ```

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing
@testable import UsageMeterKit

@Suite("LoginFlowModel")
struct LoginFlowModelTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    @Test func startsSigningIn() {
        #expect(LoginFlowModel().phase == .signingIn)
    }

    @Test func loggedInPageStartsFetching() {
        var m = LoginFlowModel()
        m.loggedInPageFinished(now: t0)
        #expect(m.phase == .fetching(since: t0))
    }

    @Test func repeatedLoggedInPagesKeepOriginalTimer() {
        var m = LoginFlowModel()
        m.loggedInPageFinished(now: t0)
        m.loggedInPageFinished(now: t0.addingTimeInterval(5))
        #expect(m.phase == .fetching(since: t0)) // timeout clock must not reset
    }

    @Test func captureWinsFromAnyPhase() {
        var fromSigningIn = LoginFlowModel()
        fromSigningIn.usageCaptured()
        #expect(fromSigningIn.phase == .captured)

        var fromFetching = LoginFlowModel()
        fromFetching.loggedInPageFinished(now: t0)
        fromFetching.usageCaptured()
        #expect(fromFetching.phase == .captured)

        var fromTimeout = LoginFlowModel()
        fromTimeout.loggedInPageFinished(now: t0)
        fromTimeout.tick(now: t0.addingTimeInterval(15))
        fromTimeout.usageCaptured()
        #expect(fromTimeout.phase == .captured)
    }

    @Test func tickTimesOutOnlyAtBoundary() {
        var m = LoginFlowModel()
        m.loggedInPageFinished(now: t0)
        m.tick(now: t0.addingTimeInterval(14.9))
        #expect(m.phase == .fetching(since: t0))
        m.tick(now: t0.addingTimeInterval(15))
        #expect(m.phase == .fetchTimeout)
    }

    @Test func tickOutsideFetchingDoesNothing() {
        var m = LoginFlowModel()
        m.tick(now: t0.addingTimeInterval(100))
        #expect(m.phase == .signingIn)
        m.usageCaptured()
        m.tick(now: t0.addingTimeInterval(1_000))
        #expect(m.phase == .captured)
    }

    @Test func backOnLoginPageRearms() {
        var m = LoginFlowModel()
        m.loggedInPageFinished(now: t0)
        m.backOnLoginPage()
        #expect(m.phase == .signingIn)
    }

    @Test func capturedIsTerminal() {
        var m = LoginFlowModel()
        m.usageCaptured()
        m.backOnLoginPage()
        m.loggedInPageFinished(now: t0)
        #expect(m.phase == .captured)
    }

    @Test func retryRestartsFetchTimer() {
        var m = LoginFlowModel()
        m.loggedInPageFinished(now: t0)
        m.tick(now: t0.addingTimeInterval(15))
        let t1 = t0.addingTimeInterval(20)
        m.retryRequested(now: t1)
        #expect(m.phase == .fetching(since: t1))
        m.tick(now: t1.addingTimeInterval(14))
        #expect(m.phase == .fetching(since: t1))
    }

    @Test func retryIgnoredOutsideTimeout() {
        var m = LoginFlowModel()
        m.retryRequested(now: t0)
        #expect(m.phase == .signingIn)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter LoginFlowModelTests 2>&1 | tail -5`
Expected: compile error "cannot find 'LoginFlowModel' in scope".

- [ ] **Step 3: Write the implementation**

```swift
import Foundation

/// Pure phase reducer for the claude.ai login window ("curtain" flow):
/// `signingIn` shows the WebView; `fetching` hides it behind a native overlay
/// while the hidden hop to the Usage page fires the capture; `captured` is
/// terminal (window closes); `fetchTimeout` lifts the curtain so the user is
/// never trapped behind a spinner.
public struct LoginFlowModel: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case signingIn
        case fetching(since: Date)
        case captured
        case fetchTimeout
    }

    /// How long the curtain waits for a usage capture before lifting.
    public static let fetchTimeout: TimeInterval = 15

    public private(set) var phase: Phase = .signingIn

    public init() {}

    /// The WebView finished loading a logged-in claude.ai page (the Coordinator
    /// is about to hop to the Usage page). Keeps the original timeout clock if
    /// several pages finish while already fetching.
    public mutating func loggedInPageFinished(now: Date) {
        guard phase == .signingIn || phase == .fetchTimeout else { return }
        phase = .fetching(since: now)
    }

    /// The WebView navigated back to a login/auth page (logout, expired session).
    public mutating func backOnLoginPage() {
        guard phase != .captured else { return }
        phase = .signingIn
    }

    /// A usage response was captured — terminal.
    public mutating func usageCaptured() {
        phase = .captured
    }

    /// Periodic clock while fetching; past the deadline the curtain lifts.
    public mutating func tick(now: Date) {
        guard case .fetching(let since) = phase,
              now.timeIntervalSince(since) >= Self.fetchTimeout else { return }
        phase = .fetchTimeout
    }

    /// The user asked to retry after a timeout — restart the fetch clock.
    public mutating func retryRequested(now: Date) {
        guard phase == .fetchTimeout else { return }
        phase = .fetching(since: now)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter LoginFlowModelTests 2>&1 | tail -3`
Expected: all LoginFlowModel tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/UsageMeterKit/Account/LoginFlowModel.swift Tests/UsageMeterKitTests/LoginFlowModelTests.swift
git commit -m "feat(kit): LoginFlowModel phase reducer for the login curtain"
```

---

### Task 2: Curtain overlay + Coordinator wiring

**Files:**
- Modify: `Sources/UsageMeter/Account/AccountLoginView.swift` (Coordinator `didFinish`, `LoginWebController`, `AccountLoginScreen`)

**Interfaces:**
- Consumes: `LoginFlowModel` from Task 1 (exact API above); existing `auth.lastCaptured`, `controller.goToUsage()`, `Theme.accent`/`Theme.ok`.
- Produces: `LoginWebController.flow: LoginFlowModel` (`@Published`), used only within this file.

- [ ] **Step 1: Publish the flow from the controller**

In `LoginWebController` add:

```swift
    /// Curtain phase machine — fed by the Coordinator, rendered by the screen.
    @Published var flow = LoginFlowModel()
```

- [ ] **Step 2: Feed events from the Coordinator's `didFinish`**

Replace the body of `webView(_:didFinish:)` (keep the guards) so the existing
decisions also drive the flow:

```swift
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            MainActor.assumeIsolated { controller.hasLoadedOnce = true }
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
```

- [ ] **Step 3: Render the curtain in `AccountLoginScreen`**

Replace `AccountLoginScreen`'s `body` internals:

1. In the header `HStack`, replace the `auth.isAuthenticated` label and the
   "Usage Page" button (delete both) so the toolbar is just:

```swift
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
```

2. Replace the middle `ZStack` with the curtain-aware version and add the
   timeout banner:

```swift
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
```

3. Add the supporting members to `AccountLoginScreen`:

```swift
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var timeoutTask: Task<Void, Never>?

    private var showsCurtain: Bool {
        switch controller.flow.phase {
        case .fetching, .captured: return true
        case .signingIn, .fetchTimeout: return false
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
```

4. Rewire the reactions (replace the existing `.onChange(of: auth.lastCaptured)`
   block; keep `.onDisappear` but cancel both tasks):

```swift
        .onChange(of: auth.lastCaptured) { _, captured in
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
            case .signingIn, .fetchTimeout:
                break
            }
        }
        .onDisappear { closeTask?.cancel(); timeoutTask?.cancel() }
```

Note: if the user was already logged in when the window opens (e.g. reopened by
hand), the first `didFinish` lands on a non-login page → curtain drops → capture
fires → window closes; that is the desired "instant" path.

- [ ] **Step 4: Build both variants**

Run: `swift build 2>&1 | tail -2 && swift build -Xswiftc -DAPPSTORE 2>&1 | tail -2`
Expected: `Build complete!` twice (login file is `#if !APPSTORE`, so the second
just proves nothing else broke).

- [ ] **Step 5: Commit**

```bash
git add Sources/UsageMeter/Account/AccountLoginView.swift
git commit -m "feat: native curtain hides the claude.ai usage page after login"
```

---

### Task 3: Google popup hardening + window chrome

**Files:**
- Modify: `Sources/UsageMeter/Account/AccountLoginView.swift` (UA constant, popup creation, footer, frame)
- Modify: `Sources/UsageMeter/App/UsageMeterApp.swift:38` (login window `defaultSize`)

**Interfaces:**
- Consumes: existing `safariUserAgent` constant, popup handling in `Coordinator`.
- Produces: nothing new for other tasks.

- [ ] **Step 1: Bump the Safari UA**

In `AccountLoginView` replace the constant:

```swift
    static let safariUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"
```

(Verified live 2026-07-02: with a Safari UA + shared-config popup, Google's OAuth
reaches the real sign-in page; a current version token is the best defence at the
credential step where Google's checks are strictest.)

- [ ] **Step 2: Polish the OAuth popup window**

In `webView(_:createWebViewWith:for:windowFeatures:)` replace the window setup:

```swift
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
```

And in `webView(_:didFinish:)`, before the popup guard, keep the popup's title
honest (insert right after the first-party host guard):

```swift
            if webView === popupWebView, let title = webView.title, !title.isEmpty {
                popupWindow?.title = title
            }
```

Note: this line must come before `guard webView !== popupWebView else { return }`
— actually place it immediately after `MainActor.assumeIsolated { controller.hasLoadedOnce = true }`
and drop the host guard for it (popup titles come from accounts.google.com too):

```swift
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            MainActor.assumeIsolated { controller.hasLoadedOnce = true }
            if webView === popupWebView, let title = webView.title, !title.isEmpty {
                MainActor.assumeIsolated { popupWindow?.title = title }
            }
            // …existing guards continue unchanged…
```

(`popupWindow`/`popupWebView` are Coordinator properties; `didFinish` runs on the
main thread, matching the existing `MainActor.assumeIsolated` pattern.)

- [ ] **Step 3: Slim the window + footer**

1. `AccountLoginScreen`: change `.frame(minWidth: 860, minHeight: 680)` →
   `.frame(minWidth: 560, minHeight: 640)`.
2. Footer: keep both lines but tighten the copy (usage page is now never shown):

```swift
            VStack(alignment: .leading, spacing: 4) {
                Label("If \u{201C}Continue with Google\u{201D} errors, try \u{201C}Continue with email\u{201D}.",
                      systemImage: "lightbulb")
                    .font(.caption2).foregroundStyle(Theme.accent)
                Text("UsageMeter never sees your password — only your claude.ai login session is stored locally, and Log out wipes it. It reads only usage percentages and reset times, never conversation content. This window closes by itself once your numbers are captured.")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(8)
```

3. `Sources/UsageMeter/App/UsageMeterApp.swift:38`: `.defaultSize(width: 860, height: 680)` →
   `.defaultSize(width: 640, height: 760)`.

- [ ] **Step 4: Full verification**

Run: `make test 2>&1 | tail -3 && swift build -Xswiftc -DAPPSTORE 2>&1 | tail -1`
Expected: all tests pass (144 + 10 new), both variants build.

- [ ] **Step 5: Commit**

```bash
git add Sources/UsageMeter/Account/AccountLoginView.swift Sources/UsageMeter/App/UsageMeterApp.swift
git commit -m "feat: harden Google OAuth popup, slim the login window"
```

---

### Task 4: Real-app verification

**Files:** none (manual/scripted verification).

- [ ] **Step 1:** `make app && make install`, relaunch, open the login window from
  the popover; verify: slim window, no "Usage Page" button, page loads.
- [ ] **Step 2:** Screenshot the window (`screencapture -l <windowid>`); confirm
  the chrome reads Kiln (teal Done button) and the footer copy.
- [ ] **Step 3:** If the user signs in during verification: confirm the usage page
  never becomes visible (curtain covers it), the success state shows, and the
  window closes in <1 s after capture. Otherwise leave live-login verification to
  the user's next login and say so in the report.
- [ ] **Step 4:** Update `docs/STATUS.md` (one bullet) and commit.
