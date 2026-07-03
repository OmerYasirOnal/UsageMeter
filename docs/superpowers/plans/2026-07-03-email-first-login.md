# Email-First Login Flow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the raw claude.ai WebView login with an email-first flow: a native email step screen, automatic prefill+submit of claude.ai's magic-code form, and the WebView revealed only at the code-entry step — degrading gracefully to today's flow if anything breaks.

**Architecture:** `LoginFlowModel` (pure reducer in UsageMeterKit) gains two pre-phases (`enterEmail`, `autofilling`). `AccountLoginScreen` renders a native email form during `enterEmail` and only creates the WebView afterwards. The `AccountLoginView` Coordinator injects a fill+submit script into claude.ai/login and listens on a new `loginFlow` script-message channel for code-screen detection. Everything downstream (curtain, usage capture, auto-close) is untouched.

**Tech Stack:** Swift 6, SwiftUI, WebKit (`WKWebView`, `WKScriptMessageHandler`), swift-testing (`@Test`/`#expect`).

**Spec:** `docs/superpowers/specs/2026-07-03-email-first-login-design.md`

## Global Constraints

- All Source-A login UI lives inside `#if !APPSTORE` (already the case for both files touched).
- Privacy: the email travels ONLY into the claude.ai page (first-party); the `usageProbe` capture handler and its allowlist are not modified.
- Mock mode (`USAGEMETER_MOCK_USAGE_URL` env var) must skip the email step entirely and behave exactly as today.
- `LoginFlowModel` stays a pure, `Sendable`, `Equatable` value type — no Foundation clocks inside; time comes in via parameters.
- `make test` (swift test) must pass after every task; UI code must compile via `swift build`.
- UserDefaults key for the remembered email: `"accountLoginEmail"` (exact string, used in two files).

---

### Task 1: LoginFlowModel — new phases `enterEmail` and `autofilling`

**Files:**
- Modify: `Sources/UsageMeterKit/Account/LoginFlowModel.swift`
- Test: `Tests/UsageMeterKitTests/LoginFlowModelTests.swift`

**Interfaces:**
- Consumes: nothing new.
- Produces (used by Tasks 2–3):
  - `LoginFlowModel.init(skipEmailStep: Bool = false)` — default start phase is `.enterEmail`; `true` starts at `.signingIn` (mock mode).
  - New phases: `Phase.enterEmail`, `Phase.autofilling(since: Date)`.
  - New mutations: `emailSubmitted(now: Date)`, `fullPageRequested()`, `codeScreenDetected()`.
  - New constant: `LoginFlowModel.autofillTimeout: TimeInterval == 8`.
  - New flag: `var autofillFailed: Bool` (read-only outside) — set by `tick` on autofill timeout, cleared by `loggedInPageFinished`.
  - Changed guards: `loggedInPageFinished` also fires from `.autofilling`; `backOnLoginPage` is a no-op in `.enterEmail` and `.autofilling`; `tick` also times out `.autofilling`.

- [ ] **Step 1: Update existing tests for the new initial phase and add new transition tests**

Replace the entire contents of `Tests/UsageMeterKitTests/LoginFlowModelTests.swift` with:

```swift
import Foundation
import Testing
@testable import UsageMeterKit

@Suite("LoginFlowModel")
struct LoginFlowModelTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    /// A model that already skipped the native email step (mock mode / full-page fallback).
    private func atSigningIn() -> LoginFlowModel { LoginFlowModel(skipEmailStep: true) }

    // MARK: - Initial phase

    @Test func defaultStartsAtEmailStep() {
        #expect(LoginFlowModel().phase == .enterEmail)
    }

    @Test func skipEmailStepStartsSigningIn() {
        #expect(LoginFlowModel(skipEmailStep: true).phase == .signingIn)
    }

    // MARK: - Email step

    @Test func emailSubmittedStartsAutofill() {
        var m = LoginFlowModel()
        m.emailSubmitted(now: t0)
        #expect(m.phase == .autofilling(since: t0))
    }

    @Test func emailSubmittedIgnoredOutsideEmailStep() {
        var m = atSigningIn()
        m.emailSubmitted(now: t0)
        #expect(m.phase == .signingIn)
    }

    @Test func fullPageRequestSkipsToSigningIn() {
        var m = LoginFlowModel()
        m.fullPageRequested()
        #expect(m.phase == .signingIn)
        #expect(m.autofillFailed == false)
    }

    @Test func fullPageRequestIgnoredOutsideEmailStep() {
        var m = LoginFlowModel()
        m.emailSubmitted(now: t0)
        m.fullPageRequested()
        #expect(m.phase == .autofilling(since: t0))
    }

    // MARK: - Autofill phase

    @Test func codeScreenRevealsWebView() {
        var m = LoginFlowModel()
        m.emailSubmitted(now: t0)
        m.codeScreenDetected()
        #expect(m.phase == .signingIn)
        #expect(m.autofillFailed == false)
    }

    @Test func codeScreenIgnoredOutsideAutofill() {
        var m = atSigningIn()
        m.codeScreenDetected()
        #expect(m.phase == .signingIn)
    }

    @Test func autofillTimesOutWithFailureFlag() {
        var m = LoginFlowModel()
        m.emailSubmitted(now: t0)
        m.tick(now: t0.addingTimeInterval(7.9))
        #expect(m.phase == .autofilling(since: t0))
        m.tick(now: t0.addingTimeInterval(8))
        #expect(m.phase == .signingIn)
        #expect(m.autofillFailed == true)
    }

    @Test func loggedInDuringAutofillShortcutsToFetching() {
        // Already-valid session: claude.ai skips the login form entirely.
        var m = LoginFlowModel()
        m.emailSubmitted(now: t0)
        m.loggedInPageFinished(now: t0.addingTimeInterval(2))
        #expect(m.phase == .fetching(since: t0.addingTimeInterval(2)))
    }

    @Test func loggedInClearsAutofillFailedFlag() {
        var m = LoginFlowModel()
        m.emailSubmitted(now: t0)
        m.tick(now: t0.addingTimeInterval(8)) // autofillFailed = true
        m.loggedInPageFinished(now: t0.addingTimeInterval(30))
        #expect(m.autofillFailed == false)
        #expect(m.phase == .fetching(since: t0.addingTimeInterval(30)))
    }

    @Test func backOnLoginPageIgnoredDuringEmailAndAutofill() {
        var atEmail = LoginFlowModel()
        atEmail.backOnLoginPage()
        #expect(atEmail.phase == .enterEmail)

        var autofilling = LoginFlowModel()
        autofilling.emailSubmitted(now: t0)
        autofilling.backOnLoginPage()
        #expect(autofilling.phase == .autofilling(since: t0))
    }

    // MARK: - Existing behavior (from .signingIn onwards) — unchanged

    @Test func loggedInPageStartsFetching() {
        var m = atSigningIn()
        m.loggedInPageFinished(now: t0)
        #expect(m.phase == .fetching(since: t0))
    }

    @Test func repeatedLoggedInPagesKeepOriginalTimer() {
        var m = atSigningIn()
        m.loggedInPageFinished(now: t0)
        m.loggedInPageFinished(now: t0.addingTimeInterval(5))
        #expect(m.phase == .fetching(since: t0)) // timeout clock must not reset
    }

    @Test func captureWinsFromAnyPhase() {
        var fromEmail = LoginFlowModel()
        fromEmail.usageCaptured()
        #expect(fromEmail.phase == .captured)

        var fromFetching = atSigningIn()
        fromFetching.loggedInPageFinished(now: t0)
        fromFetching.usageCaptured()
        #expect(fromFetching.phase == .captured)

        var fromTimeout = atSigningIn()
        fromTimeout.loggedInPageFinished(now: t0)
        fromTimeout.tick(now: t0.addingTimeInterval(15))
        fromTimeout.usageCaptured()
        #expect(fromTimeout.phase == .captured)
    }

    @Test func tickTimesOutFetchingOnlyAtBoundary() {
        var m = atSigningIn()
        m.loggedInPageFinished(now: t0)
        m.tick(now: t0.addingTimeInterval(14.9))
        #expect(m.phase == .fetching(since: t0))
        m.tick(now: t0.addingTimeInterval(15))
        #expect(m.phase == .fetchTimeout)
    }

    @Test func tickOutsideTimedPhasesDoesNothing() {
        var m = atSigningIn()
        m.tick(now: t0.addingTimeInterval(100))
        #expect(m.phase == .signingIn)
        m.usageCaptured()
        m.tick(now: t0.addingTimeInterval(1_000))
        #expect(m.phase == .captured)
    }

    @Test func backOnLoginPageRearms() {
        var m = atSigningIn()
        m.loggedInPageFinished(now: t0)
        m.backOnLoginPage()
        #expect(m.phase == .signingIn)
    }

    @Test func capturedIsTerminal() {
        var m = atSigningIn()
        m.usageCaptured()
        m.backOnLoginPage()
        m.loggedInPageFinished(now: t0)
        #expect(m.phase == .captured)
    }

    @Test func retryRestartsFetchTimer() {
        var m = atSigningIn()
        m.loggedInPageFinished(now: t0)
        m.tick(now: t0.addingTimeInterval(15))
        let t1 = t0.addingTimeInterval(20)
        m.retryRequested(now: t1)
        #expect(m.phase == .fetching(since: t1))
        m.tick(now: t1.addingTimeInterval(14))
        #expect(m.phase == .fetching(since: t1))
    }

    @Test func retryIgnoredOutsideTimeout() {
        var m = atSigningIn()
        m.retryRequested(now: t0)
        #expect(m.phase == .signingIn)
    }
}
```

- [ ] **Step 2: Run tests to verify the new ones fail**

Run: `swift test --filter LoginFlowModelTests`
Expected: compile FAILURE — `enterEmail`, `autofilling`, `emailSubmitted`, `skipEmailStep:` etc. don't exist yet. (A compile error in the test target is this cycle's "failing test".)

- [ ] **Step 3: Implement the new phase machine**

Replace the entire contents of `Sources/UsageMeterKit/Account/LoginFlowModel.swift` with:

```swift
import Foundation

/// Pure phase reducer for the claude.ai login window:
/// `enterEmail` shows the native email step (no WebView yet); `autofilling`
/// hides the WebView behind a "sending code" cover while an injected script
/// fills + submits claude.ai's email form; `signingIn` shows the WebView
/// (normally at the code-entry screen); `fetching` hides it behind a native
/// overlay while the hidden hop to the Usage page fires the capture;
/// `captured` is terminal (window closes); `fetchTimeout` lifts the curtain
/// so the user is never trapped behind a spinner.
public struct LoginFlowModel: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case enterEmail
        case autofilling(since: Date)
        case signingIn
        case fetching(since: Date)
        case captured
        case fetchTimeout
    }

    /// How long the curtain waits for a usage capture before lifting.
    public static let fetchTimeout: TimeInterval = 15
    /// How long the autofill cover waits for claude.ai's code screen before
    /// revealing the page untouched (graceful degradation to the manual flow).
    public static let autofillTimeout: TimeInterval = 8

    public private(set) var phase: Phase
    /// One-shot presentation flag: the autofill attempt timed out and the page
    /// was revealed as-is — show a "type your email on the page" hint.
    public private(set) var autofillFailed = false

    /// `skipEmailStep` starts directly at `.signingIn` (mock mode and the
    /// "use the full sign-in page" fallback keep today's behavior).
    public init(skipEmailStep: Bool = false) {
        phase = skipEmailStep ? .signingIn : .enterEmail
    }

    /// The user submitted their email on the native step screen.
    public mutating func emailSubmitted(now: Date) {
        guard phase == .enterEmail else { return }
        phase = .autofilling(since: now)
    }

    /// The user chose the full claude.ai sign-in page (Google/SSO fallback).
    public mutating func fullPageRequested() {
        guard phase == .enterEmail else { return }
        phase = .signingIn
    }

    /// The injected script saw claude.ai's verification-code screen.
    public mutating func codeScreenDetected() {
        guard case .autofilling = phase else { return }
        phase = .signingIn
    }

    /// The WebView finished loading a logged-in claude.ai page. Also fires
    /// from `.autofilling` — an already-valid session skips the login form.
    /// Keeps the original timeout clock if several pages finish while fetching.
    public mutating func loggedInPageFinished(now: Date) {
        switch phase {
        case .signingIn, .fetchTimeout, .autofilling:
            autofillFailed = false
            phase = .fetching(since: now)
        case .enterEmail, .fetching, .captured:
            return
        }
    }

    /// The WebView navigated back to a login/auth page (logout, expired
    /// session). Ignored before the WebView is user-visible — during the
    /// email step and autofill the login page loading is EXPECTED.
    public mutating func backOnLoginPage() {
        switch phase {
        case .captured, .enterEmail, .autofilling: return
        case .signingIn, .fetching, .fetchTimeout: phase = .signingIn
        }
    }

    /// A usage response was captured — terminal.
    public mutating func usageCaptured() {
        phase = .captured
    }

    /// Periodic clock: past the deadline, fetching lifts the curtain and
    /// autofilling reveals the untouched page with the failure hint.
    public mutating func tick(now: Date) {
        switch phase {
        case .fetching(let since) where now.timeIntervalSince(since) >= Self.fetchTimeout:
            phase = .fetchTimeout
        case .autofilling(let since) where now.timeIntervalSince(since) >= Self.autofillTimeout:
            autofillFailed = true
            phase = .signingIn
        default:
            break
        }
    }

    /// The user asked to retry after a timeout — restart the fetch clock.
    public mutating func retryRequested(now: Date) {
        guard phase == .fetchTimeout else { return }
        phase = .fetching(since: now)
    }
}
```

- [ ] **Step 4: Run the full test suite**

Run: `swift test`
Expected: all tests PASS (144 existing + the new LoginFlowModel ones; count goes up).

- [ ] **Step 5: Commit**

```bash
git add Sources/UsageMeterKit/Account/LoginFlowModel.swift Tests/UsageMeterKitTests/LoginFlowModelTests.swift
git commit -m "feat(kit): enterEmail + autofilling phases in LoginFlowModel"
```

---

### Task 2: Native email step screen + phase wiring in `AccountLoginScreen`

**Files:**
- Modify: `Sources/UsageMeter/Account/AccountLoginView.swift` (the `LoginWebController` class at the top and the `AccountLoginScreen` struct at the bottom; the `AccountLoginView`/Coordinator middle section is Task 3)

**Interfaces:**
- Consumes (Task 1): `LoginFlowModel(skipEmailStep:)`, `.enterEmail`, `.autofilling(since:)`, `emailSubmitted(now:)`, `fullPageRequested()`, `autofillFailed`, `LoginFlowModel.autofillTimeout`.
- Produces (Task 3 relies on): `LoginWebController.pendingEmail: String?` (set before the WebView exists), `AccountLoginView.loginPageURL`.

- [ ] **Step 1: Extend `LoginWebController` (mock-mode start phase + pending email)**

In `Sources/UsageMeter/Account/AccountLoginView.swift`, replace the `LoginWebController` class with:

```swift
/// Imperative handle to drive the login WebView from the surrounding SwiftUI view.
@MainActor
final class LoginWebController: ObservableObject {
    fileprivate weak var webView: WKWebView?
    /// First page finished loading — used to hide the loading overlay.
    @Published var hasLoadedOnce = false
    /// Curtain phase machine — fed by the Coordinator, rendered by the screen.
    @Published var flow: LoginFlowModel
    /// Email captured on the native step screen, autofilled into claude.ai's
    /// login form by the Coordinator. First-party only — never sent elsewhere.
    var pendingEmail: String?

    init() {
        // Mock mode loads a local fixture page — the email step makes no sense there.
        let mock = ProcessInfo.processInfo.environment["USAGEMETER_MOCK_USAGE_URL"] != nil
        flow = LoginFlowModel(skipEmailStep: mock)
    }

    func reload() { webView?.reload() }
    func goToUsage() { webView?.load(URLRequest(url: AccountLoginView.usagePageURL)) }
}
```

- [ ] **Step 2: Add the login page URL constant**

In the `// MARK: - Constants` section of `AccountLoginView`, below the `usagePageURL` line, add:

```swift
    static let loginPageURL = URL(string: "https://claude.ai/login")!
```

And change the start-URL selection in `makeNSView` from:

```swift
        let start = ProcessInfo.processInfo.environment["USAGEMETER_MOCK_USAGE_URL"]
            .flatMap { URL(string: $0) } ?? Self.usagePageURL
```

to:

```swift
        let start: URL
        if let mock = ProcessInfo.processInfo.environment["USAGEMETER_MOCK_USAGE_URL"]
            .flatMap({ URL(string: $0) }) {
            start = mock
        } else if controller.pendingEmail != nil {
            start = Self.loginPageURL      // email flow: land on the form we autofill
        } else {
            start = Self.usagePageURL      // full-page fallback: today's behavior
        }
```

- [ ] **Step 3: Rebuild `AccountLoginScreen` around the email step**

Replace the entire `AccountLoginScreen` struct with:

```swift
/// Window content hosting the email step and the login WebView with a toolbar.
struct AccountLoginScreen: View {
    @ObservedObject var auth: AccountAuth
    @StateObject private var controller = LoginWebController()
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("accountLoginEmail") private var email = ""
    @State private var closeTask: Task<Void, Never>?
    @State private var timeoutTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle").foregroundStyle(Theme.accent)
                Text(isEmailStep ? "Sign in with Email" : "Sign in to claude.ai").font(.headline)
                Spacer()
                if !isEmailStep {
                    Button { controller.reload() } label: { Image(systemName: "arrow.clockwise") }
                        .help("Reload")
                }
                Button("Done") { dismissWindow(id: AppWindowID.accountLogin) }
                    .buttonStyle(.bordered)
            }
            .padding(10)

            Divider()

            ZStack {
                if isEmailStep {
                    emailStep
                } else {
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
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: showsCurtain)

            if controller.flow.autofillFailed, case .signingIn = controller.flow.phase {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning)
                    Text("Couldn't prefill your email — enter it on the page.").font(.callout)
                    Spacer()
                }
                .padding(10)
                .background(.quaternary.opacity(0.5))
            }

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
                if !isEmailStep {
                    Label("If \u{201C}Continue with Google\u{201D} errors, try \u{201C}Continue with email\u{201D}.",
                          systemImage: "lightbulb")
                        .font(.caption2).foregroundStyle(Theme.accent)
                }
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
            case .autofilling(let since):
                scheduleTick(at: since.addingTimeInterval(LoginFlowModel.autofillTimeout))
            case .fetching(let since):
                scheduleTick(at: since.addingTimeInterval(LoginFlowModel.fetchTimeout))
            case .captured:
                closeTask?.cancel()
                closeTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 800_000_000)
                    guard !Task.isCancelled else { return }
                    dismissWindow(id: AppWindowID.accountLogin)
                }
            case .enterEmail, .signingIn, .fetchTimeout:
                break
            }
        }
        .onDisappear { closeTask?.cancel(); timeoutTask?.cancel() }
    }

    private var isEmailStep: Bool { controller.flow.phase == .enterEmail }

    private func scheduleTick(at deadline: Date) {
        timeoutTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(max(0, deadline.timeIntervalSinceNow) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            controller.flow.tick(now: Date())
        }
    }

    // MARK: - Email step (native, no WebView yet)

    private var emailLooksValid: Bool {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        return trimmed.contains("@") && trimmed.contains(".") && trimmed.count >= 6
    }

    private func submitEmail() {
        guard emailLooksValid else { return }
        controller.pendingEmail = email.trimmingCharacters(in: .whitespaces)
        controller.flow.emailSubmitted(now: Date())
    }

    private var emailStep: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 12)
            Text("Enter your email and follow these steps to verify.")
                .font(.callout).foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 0) {
                stepRow(number: "1", title: "Enter your Claude email",
                        detail: "Use the email you log in to claude.ai with.")
                Divider().padding(.vertical, 12)
                stepRow(number: "2", title: "Check your inbox",
                        detail: "Claude sends you a sign-in code.")
                Divider().padding(.vertical, 12)
                stepRow(number: "3", title: "Enter the code",
                        detail: "Type it on the claude.ai screen that appears here.")
            }
            .padding(20)
            .background(RoundedRectangle(cornerRadius: 12).fill(.quaternary.opacity(0.35)))
            .frame(maxWidth: 460)

            Spacer(minLength: 12)

            HStack(spacing: 10) {
                TextField("Enter your claude.ai email…", text: $email)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.username)
                    .onSubmit(submitEmail)
                Button {
                    submitEmail()
                } label: {
                    Label("Sign in to Claude", systemImage: "envelope.fill")
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .disabled(!emailLooksValid)
            }
            .frame(maxWidth: 460)

            Button("Google or SSO account? Use the full claude.ai sign-in page.") {
                controller.flow.fullPageRequested()
            }
            .buttonStyle(.link)
            .font(.caption)
            .padding(.bottom, 16)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }

    private func stepRow(number: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.callout.weight(.bold)).monospacedDigit()
                .frame(width: 26, height: 26)
                .background(Circle().fill(Theme.accent.opacity(0.85)))
                .foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var showsCurtain: Bool {
        switch controller.flow.phase {
        case .autofilling, .fetching, .captured: return true
        case .enterEmail, .signingIn, .fetchTimeout: return false
        }
    }

    /// Native cover: shown while the injected script submits the email form
    /// ("sending code"), and again from "logged in" until the window closes —
    /// the claude.ai page renders invisibly behind it.
    private var curtain: some View {
        VStack(spacing: 14) {
            switch controller.flow.phase {
            case .captured:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44)).foregroundStyle(Theme.ok)
                Text("You're all set").font(.title3.weight(.semibold))
                Text("Usage captured — closing…").font(.callout).foregroundStyle(.secondary)
            case .autofilling:
                ProgressView().controlSize(.large)
                Text("Sending you a sign-in code…").font(.title3.weight(.semibold))
                Text("Submitting your email to claude.ai.").font(.callout).foregroundStyle(.secondary)
            default:
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
```

Note: the "Done" button loses `.keyboardShortcut(.defaultAction)` (return key now belongs to "Sign in to Claude" on the email step) and becomes `.bordered` so the prominent accent button is unique per screen.

- [ ] **Step 4: Build**

Run: `swift build`
Expected: compiles with no errors (warnings unchanged).

- [ ] **Step 5: Run the full test suite**

Run: `swift test`
Expected: all tests PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/UsageMeter/Account/AccountLoginView.swift
git commit -m "feat: native email step screen before the claude.ai WebView"
```

---

### Task 3: Autofill injection + code-screen detection in the Coordinator

**Files:**
- Modify: `Sources/UsageMeter/Account/AccountLoginView.swift` (the `AccountLoginView` struct and its `Coordinator`)

**Interfaces:**
- Consumes: `controller.pendingEmail` (Task 2), `controller.flow.codeScreenDetected()` (Task 1).
- Produces: new script-message channel `AccountLoginView.loginFlowMessageName == "loginFlow"`; `AccountLoginView.autofillScript(email:)`.

- [ ] **Step 1: Register the `loginFlow` message channel**

In `makeNSView`, after the existing `userContent.add(context.coordinator, name: Self.messageName)` line, add:

```swift
        userContent.add(context.coordinator, name: Self.loginFlowMessageName)
```

In `dismantleNSView`, after the existing `removeScriptMessageHandler(forName: messageName)` line, add:

```swift
        nsView.configuration.userContentController.removeScriptMessageHandler(forName: loginFlowMessageName)
```

In the `// MARK: - Constants` section, below `static let messageName = "usageProbe"`, add:

```swift
    static let loginFlowMessageName = "loginFlow"
```

- [ ] **Step 2: Handle the code-screen message in the Coordinator**

Replace the `userContentController(_:didReceive:)` method with:

```swift
        func userContentController(_ controller: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            if message.name == AccountLoginView.loginFlowMessageName {
                guard let dict = message.body as? [String: Any],
                      dict["event"] as? String == "codeScreen" else { return }
                let flowController = self.controller
                Task { @MainActor in flowController.flow.codeScreenDetected() }
                return
            }
            guard message.name == AccountLoginView.messageName,
                  let dict = message.body as? [String: Any],
                  let url = dict["url"] as? String, !url.isEmpty else { return }
            let status = (dict["status"] as? Int) ?? 0
            let body = (dict["body"] as? String) ?? ""
            let auth = self.auth
            Task { @MainActor in auth.ingestCapture(url: url, status: status, body: body) }
        }
```

- [ ] **Step 3: Inject the autofill script when the login page finishes during autofill**

In the Coordinator, add a state property next to `requestedUsage`:

```swift
        private var autofillInjected = false
```

In `webView(_:didFinish:)`, replace the login-path branch:

```swift
            if path.contains("login") || path.contains("auth") || path.contains("oauth") || path.contains("magic") {
                requestedUsage = false   // back in the login flow → re-arm
                MainActor.assumeIsolated { controller.flow.backOnLoginPage() }
                return
            }
```

with:

```swift
            if path.contains("login") || path.contains("auth") || path.contains("oauth") || path.contains("magic") {
                requestedUsage = false   // back in the login flow → re-arm
                MainActor.assumeIsolated {
                    controller.flow.backOnLoginPage() // no-op during autofill (expected page)
                    if case .autofilling = controller.flow.phase,
                       let email = controller.pendingEmail, !autofillInjected {
                        autofillInjected = true
                        webView.evaluateJavaScript(AccountLoginView.autofillScript(email: email))
                    }
                }
                return
            }
```

- [ ] **Step 4: Add the autofill script builder**

Below the existing `captureScript` constant, add:

```swift
    /// Fills claude.ai's email login form (React controlled input → native
    /// value setter + `input` event), submits it once, and reports when the
    /// verification-code screen appears. The email string is JSON-encoded so
    /// arbitrary user input cannot escape the script.
    static func autofillScript(email: String) -> String {
        let encoded = (try? JSONEncoder().encode([email]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? #"[""]"#
        return """
        (function () {
          var email = \(encoded)[0];
          var submitted = false;
          var reportedCode = false;
          function fill() {
            if (submitted) return;
            var input = document.querySelector('input#email, input[data-testid="email"], input[type="email"]');
            if (!input) return;
            try {
              var setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
              setter.call(input, email);
              input.dispatchEvent(new Event('input', { bubbles: true }));
              var form = input.closest('form');
              if (form && form.requestSubmit) { form.requestSubmit(); }
              else {
                var btn = (form || document).querySelector('button[type=submit]');
                if (!btn) return;
                btn.click();
              }
              submitted = true;
            } catch (e) {}
          }
          function isCodeInput(el) {
            var s = ((el.getAttribute('placeholder') || '') + ' ' +
                     (el.getAttribute('data-testid') || '') + ' ' +
                     (el.getAttribute('autocomplete') || '') + ' ' +
                     (el.id || '')).toLowerCase();
            return s.indexOf('code') > -1 || s.indexOf('one-time') > -1;
          }
          function codeScreenVisible() {
            var inputs = document.querySelectorAll('input');
            for (var i = 0; i < inputs.length; i++) { if (isCodeInput(inputs[i])) return true; }
            return false;
          }
          function check() {
            fill();
            if (!reportedCode && codeScreenVisible()) {
              reportedCode = true;
              try {
                window.webkit.messageHandlers.loginFlow.postMessage({ kind: 'loginFlow', event: 'codeScreen' });
              } catch (e) {}
            }
            if (submitted && reportedCode) { stop(); }
          }
          var timer = setInterval(check, 400);
          var observer = new MutationObserver(check);
          function stop() { clearInterval(timer); observer.disconnect(); }
          observer.observe(document.documentElement, { childList: true, subtree: true });
          setTimeout(stop, 20000);
          check();
        })();
        """
    }
```

- [ ] **Step 5: Build and run the full test suite**

Run: `swift build && swift test`
Expected: compiles, all tests PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/UsageMeter/Account/AccountLoginView.swift
git commit -m "feat: autofill claude.ai's email form and reveal the WebView at the code screen"
```

---

### Task 4: Logout clears the remembered email + end-to-end verification

**Files:**
- Modify: `Sources/UsageMeter/Account/AccountAuth.swift:204-214` (the `logout()` method)

**Interfaces:**
- Consumes: the `"accountLoginEmail"` UserDefaults key written by Task 2's `@AppStorage`.
- Produces: nothing new.

- [ ] **Step 1: Clear the email in `logout()`**

In `AccountAuth.logout()`, after `endpointStore.clear()`, add:

```swift
        UserDefaults.standard.removeObject(forKey: "accountLoginEmail") // "Log out wipes it"
```

- [ ] **Step 2: Build and run the full test suite**

Run: `swift build && swift test`
Expected: compiles, all tests PASS.

- [ ] **Step 3: Manual end-to-end verification (real claude.ai)**

Run: `make run`, then in the menu bar open **Sign in** and verify:

1. The window opens on the native "Sign in with Email" step (3 steps + email field, no WebView).
2. Return key / "Sign in to Claude" is disabled until the field looks like an email.
3. Submitting shows the "Sending you a sign-in code…" cover, then reveals claude.ai's **code-entry screen** (email already submitted).
4. The code from the inbox completes login → existing curtain → "You're all set" → window auto-closes; menu bar shows account %.
5. Re-open Sign in after **Log out**: email field is EMPTY (wiped) and the flow starts at the email step again.
6. "Use the full claude.ai sign-in page" shows the raw login page immediately (Google button visible).
7. Mock mode still bypasses the email step: `USAGEMETER_MOCK_USAGE_URL=... swift run` opens straight into the WebView.

Expected: all 7 pass. If claude.ai's DOM changed and step 3 hangs, the cover must lift by itself after 8 s with the "Couldn't prefill your email" hint (graceful degradation — also a pass for that step, but note it).

- [ ] **Step 4: Commit**

```bash
git add Sources/UsageMeter/Account/AccountAuth.swift
git commit -m "feat: logout also wipes the remembered login email"
```
