# Source A explicit consent gate — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a one-time, explicit consent screen before claude.ai login that
states — in plain language — that this optional feature automates access to
claude.ai outside Anthropic's stated Terms of Service, resolving the top open
item in `docs/STATUS.md`.

**Architecture:** A new `.consent` phase is added to the existing
`LoginFlowModel` phase reducer (Kit, pure/tested), shown as a new native SwiftUI
card in `AccountLoginScreen` before the existing `enterEmail` step — the exact
same pattern the email-first-login flow already established. Acceptance is
persisted via `@AppStorage`, so it's shown once per device, ever.

**Tech Stack:** Swift 6, SwiftUI, Swift Testing (`@Suite`/`@Test`/`#expect`).

## Global Constraints

- Scope is `#if !APPSTORE` only — the App Store build excludes Source A entirely and is untouched.
- `init(skipEmailStep: Bool = false, showConsentGate: Bool = false)` — **not** `consentGranted: Bool = false`. Getting this backwards breaks ~15 existing tests that construct a bare `LoginFlowModel()` expecting `.enterEmail`. Bare `LoginFlowModel()` must keep starting at `.enterEmail` unchanged.
- Consent, once granted, is never re-shown and is **not** cleared by Log out.
- No checkbox — a single "I Understand, Continue" button. Declining uses the existing "Done" toolbar button; no new decline UI.
- Copy is exact — use the text given in each task verbatim, do not paraphrase.

---

### Task 1: `LoginFlowModel` — add the `.consent` phase (TDD)

**Files:**
- Modify: `Sources/UsageMeterKit/Account/LoginFlowModel.swift`
- Test: `Tests/UsageMeterKitTests/LoginFlowModelTests.swift`

**Interfaces:**
- Produces: `LoginFlowModel.Phase.consent` (new enum case); `LoginFlowModel.init(skipEmailStep: Bool = false, showConsentGate: Bool = false)` (new second parameter, both default `false`); `LoginFlowModel.consentAccepted()` (new mutating method, no-ops unless `phase == .consent`, otherwise transitions to `.enterEmail`).
- Consumes: nothing new — this task only touches the Kit's pure phase reducer.

- [ ] **Step 1: Write the failing tests**

Open `Tests/UsageMeterKitTests/LoginFlowModelTests.swift`. Find the `// MARK: - Initial phase` section (currently containing `defaultStartsAtEmailStep` and `skipEmailStepStartsSigningIn` — **do not modify either of those**, they stay exactly as-is since default behavior is unchanged). Immediately after that section (right before `// MARK: - Email step`), insert:

```swift
    // MARK: - Consent phase

    @Test func showConsentGateStartsAtConsent() {
        #expect(LoginFlowModel(showConsentGate: true).phase == .consent)
    }

    @Test func mockSkipsConsentGateEvenWhenRequested() {
        #expect(LoginFlowModel(skipEmailStep: true, showConsentGate: true).phase == .signingIn)
    }

    @Test func consentAcceptedMovesToEmailStep() {
        var m = LoginFlowModel(showConsentGate: true)
        m.consentAccepted()
        #expect(m.phase == .enterEmail)
    }

    @Test func consentAcceptedIgnoredOutsideConsentPhase() {
        var m = LoginFlowModel()
        m.consentAccepted()
        #expect(m.phase == .enterEmail)
    }

    @Test func backOnLoginPageIgnoredDuringConsent() {
        var m = LoginFlowModel(showConsentGate: true)
        m.backOnLoginPage()
        #expect(m.phase == .consent)
    }

    @Test func loggedInPageFinishedIgnoredDuringConsent() {
        var m = LoginFlowModel(showConsentGate: true)
        m.loggedInPageFinished(now: t0)
        #expect(m.phase == .consent)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter LoginFlowModelTests`
Expected: FAIL to compile — `Phase` has no member `consent`, `LoginFlowModel` has no `showConsentGate` parameter or `consentAccepted()` method.

- [ ] **Step 3: Add the `.consent` case and update the doc comment**

In `Sources/UsageMeterKit/Account/LoginFlowModel.swift`, replace:

```swift
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
```

with:

```swift
/// Pure phase reducer for the claude.ai login window:
/// `consent` (optional, first-ever login only) discloses that this feature
/// automates access to claude.ai outside Anthropic's stated Terms, before
/// anything else happens; `enterEmail` shows the native email step (no
/// WebView yet); `autofilling` hides the WebView behind a "sending code"
/// cover while an injected script fills + submits claude.ai's email form;
/// `signingIn` shows the WebView (normally at the code-entry screen);
/// `fetching` hides it behind a native overlay while the hidden hop to the
/// Usage page fires the capture; `captured` is terminal (window closes);
/// `fetchTimeout` lifts the curtain so the user is never trapped behind a
/// spinner.
public struct LoginFlowModel: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case consent
        case enterEmail
        case autofilling(since: Date)
        case signingIn
        case fetching(since: Date)
        case captured
        case fetchTimeout
    }
```

- [ ] **Step 4: Replace the initializer and add `consentAccepted()`**

Replace:

```swift
    /// `skipEmailStep` starts directly at `.signingIn` (mock mode and the
    /// "use the full sign-in page" fallback keep today's behavior).
    public init(skipEmailStep: Bool = false) {
        phase = skipEmailStep ? .signingIn : .enterEmail
    }

    /// The user submitted their email on the native step screen.
    public mutating func emailSubmitted(now: Date) {
```

with:

```swift
    /// `skipEmailStep` starts directly at `.signingIn` (mock mode and the
    /// "use the full sign-in page" fallback keep today's behavior).
    /// `showConsentGate` starts at `.consent` instead of `.enterEmail` —
    /// defaults to `false` so every existing bare `LoginFlowModel()` call
    /// (throughout this file's own tests) keeps starting at `.enterEmail`
    /// unchanged; only a real login attempt with consent not yet granted
    /// passes `true` (see `LoginWebController.init()`).
    public init(skipEmailStep: Bool = false, showConsentGate: Bool = false) {
        if skipEmailStep {
            phase = .signingIn
        } else if showConsentGate {
            phase = .consent
        } else {
            phase = .enterEmail
        }
    }

    /// The user accepted the automated-access disclosure on the consent screen.
    public mutating func consentAccepted() {
        guard phase == .consent else { return }
        phase = .enterEmail
    }

    /// The user submitted their email on the native step screen.
    public mutating func emailSubmitted(now: Date) {
```

- [ ] **Step 5: Make `loggedInPageFinished` and `backOnLoginPage` exhaustive**

Replace:

```swift
    public mutating func loggedInPageFinished(now: Date) {
        switch phase {
        case .signingIn, .fetchTimeout, .autofilling:
            autofillFailed = false
            phase = .fetching(since: now)
        case .enterEmail, .fetching, .captured:
            return
        }
    }
```

with:

```swift
    public mutating func loggedInPageFinished(now: Date) {
        switch phase {
        case .signingIn, .fetchTimeout, .autofilling:
            autofillFailed = false
            phase = .fetching(since: now)
        case .consent, .enterEmail, .fetching, .captured:
            return
        }
    }
```

Replace:

```swift
    public mutating func backOnLoginPage() {
        switch phase {
        case .captured, .enterEmail, .autofilling: return
        case .signingIn, .fetching, .fetchTimeout: phase = .signingIn
        }
    }
```

with:

```swift
    public mutating func backOnLoginPage() {
        switch phase {
        case .captured, .consent, .enterEmail, .autofilling: return
        case .signingIn, .fetching, .fetchTimeout: phase = .signingIn
        }
    }
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `swift test --filter LoginFlowModelTests`
Expected: PASS — all existing tests plus the 6 new ones from Step 1.

- [ ] **Step 7: Run the full suite**

Run: `swift test`
Expected: all tests pass (regression check — nothing outside this file references `Phase`'s cases exhaustively except this file itself, so no other breakage is expected, but confirm).

- [ ] **Step 8: Commit**

```bash
git add Sources/UsageMeterKit/Account/LoginFlowModel.swift Tests/UsageMeterKitTests/LoginFlowModelTests.swift
git commit -m "feat(kit): add consent phase to the login flow reducer"
```

---

### Task 2: Consent screen UI in `AccountLoginScreen`

**Files:**
- Modify: `Sources/UsageMeter/Account/AccountLoginView.swift`

**Interfaces:**
- Consumes: `LoginFlowModel.Phase.consent`, `LoginFlowModel(skipEmailStep:showConsentGate:)`, `LoginFlowModel.consentAccepted()` (all from Task 1).
- Produces: no new public API — this is the terminal UI layer for this feature.

- [ ] **Step 1: Wire the persisted flag into `LoginWebController.init()`**

Replace:

```swift
    init() {
        // Mock mode loads a local fixture page — the email step makes no sense there.
        let mock = ProcessInfo.processInfo.environment["USAGEMETER_MOCK_USAGE_URL"] != nil
        flow = LoginFlowModel(skipEmailStep: mock)
    }
```

with:

```swift
    init() {
        // Mock mode loads a local fixture page — the email step makes no sense there.
        let mock = ProcessInfo.processInfo.environment["USAGEMETER_MOCK_USAGE_URL"] != nil
        let consentGranted = UserDefaults.standard.bool(forKey: "accountLoginConsentGranted")
        flow = LoginFlowModel(skipEmailStep: mock, showConsentGate: !consentGranted)
    }
```

- [ ] **Step 2: Add the persisted `@AppStorage` flag to `AccountLoginScreen`**

Replace:

```swift
    @AppStorage("accountLoginEmail") private var email = ""
    @State private var closeTask: Task<Void, Never>?
```

with:

```swift
    @AppStorage("accountLoginEmail") private var email = ""
    @AppStorage("accountLoginConsentGranted") private var consentGranted = false
    @State private var closeTask: Task<Void, Never>?
```

- [ ] **Step 3: Add `isConsentStep`, `headerTitle`, and `acceptConsent()`**

Replace:

```swift
    private var isEmailStep: Bool { controller.flow.phase == .enterEmail }
```

with:

```swift
    private var isEmailStep: Bool { controller.flow.phase == .enterEmail }
    private var isConsentStep: Bool { controller.flow.phase == .consent }

    private var headerTitle: String {
        if isConsentStep { return "Before You Continue" }
        if isEmailStep { return "Sign in with Email" }
        return "Sign in to claude.ai"
    }

    private func acceptConsent() {
        consentGranted = true
        controller.flow.consentAccepted()
    }
```

- [ ] **Step 4: Use `headerTitle` and gate the reload button on the consent step too**

Replace:

```swift
                Image(systemName: "person.crop.circle").foregroundStyle(Theme.accent)
                Text(isEmailStep ? "Sign in with Email" : "Sign in to claude.ai").font(.headline)
                Spacer()
                if !isEmailStep {
                    Button { controller.reload() } label: { Image(systemName: "arrow.clockwise") }
                        .help("Reload")
                }
```

with:

```swift
                Image(systemName: "person.crop.circle").foregroundStyle(Theme.accent)
                Text(headerTitle).font(.headline)
                Spacer()
                if !isEmailStep && !isConsentStep {
                    Button { controller.reload() } label: { Image(systemName: "arrow.clockwise") }
                        .help("Reload")
                }
```

- [ ] **Step 5: Add the consent branch to the body `ZStack`**

Replace:

```swift
            ZStack {
                if isEmailStep {
                    emailStep
                } else {
                    AccountLoginView(auth: auth, controller: controller)
```

with:

```swift
            ZStack {
                if isConsentStep {
                    consentStep
                } else if isEmailStep {
                    emailStep
                } else {
                    AccountLoginView(auth: auth, controller: controller)
```

- [ ] **Step 6: Hide the Google/SSO footer hint during consent too**

Replace:

```swift
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                if !isEmailStep {
                    Label("If \u{201C}Continue with Google\u{201D} errors, try \u{201C}Continue with email\u{201D}.",
                          systemImage: "lightbulb")
                        .font(.caption2).foregroundStyle(Theme.accent)
                }
```

with:

```swift
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                if !isEmailStep && !isConsentStep {
                    Label("If \u{201C}Continue with Google\u{201D} errors, try \u{201C}Continue with email\u{201D}.",
                          systemImage: "lightbulb")
                        .font(.caption2).foregroundStyle(Theme.accent)
                }
```

- [ ] **Step 7: Add the `consentStep` view**

Find `// MARK: - Email step (native, no WebView yet)`. Immediately **before** that
line, insert:

```swift
    // MARK: - Consent step (native, no WebView yet)

    private var consentStep: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 12)
            VStack(alignment: .leading, spacing: 14) {
                Text("UsageMeter's account features (session %, weekly %, real spend) read your usage numbers by automatically signing in to claude.ai — the same way you're already logged in, just replayed by the app instead of a browser tab.")
                Text("Anthropic's Consumer Terms of Service prohibit accessing their Services \u{201C}through automated or non-human means\u{201D} except via an official API key. This app does exactly that — for read-only usage numbers only, never your messages or account actions — which means using this feature falls outside Anthropic's stated Terms.")
                Text("This is entirely optional. Claude Code token tracking works fully without ever logging in.")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(20)
            .background(RoundedRectangle(cornerRadius: 12).fill(.quaternary.opacity(0.35)))
            .frame(maxWidth: 460)

            Spacer(minLength: 12)

            Button {
                acceptConsent()
            } label: {
                Label("I Understand, Continue", systemImage: "checkmark.circle.fill")
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .padding(.bottom, 16)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }

```

- [ ] **Step 8: Build**

Run: `swift build`
Expected: builds cleanly.

- [ ] **Step 9: Run the full test suite**

Run: `swift test`
Expected: all tests still pass (this task adds no new tests — SwiftUI views aren't unit tested anywhere in this project).

- [ ] **Step 10: Manual verification**

This view has no automated test, so verify it by hand:

```bash
defaults delete com.omeryasir.usagemeter accountLoginConsentGranted 2>/dev/null
make run
```

Then in the running app: click the menu-bar gauge → "Log in to claude.ai" (if
already logged in, first "Log out" from the popover, then retry). Confirm:
- The window opens on a "Before You Continue" screen with the 3 paragraphs above and a single "I Understand, Continue" button — no email field yet, no reload button, no Google/SSO hint line.
- Clicking "I Understand, Continue" moves to the existing "Sign in with Email" step.
- Click "Done" to close the window, then reopen login: confirm it now skips straight to "Sign in with Email" (consent isn't shown twice).
- `defaults read com.omeryasir.usagemeter accountLoginConsentGranted` prints `1`.

- [ ] **Step 11: Commit**

```bash
git add Sources/UsageMeter/Account/AccountLoginView.swift
git commit -m "feat: add explicit consent screen before claude.ai login"
```

---

### Task 3: Close out the TOS_REVIEW.md decision record

**Files:**
- Modify: `docs/TOS_REVIEW.md`

**Interfaces:** None — documentation only.

- [ ] **Step 1: Fill in the decision**

At the end of `docs/TOS_REVIEW.md`, replace:

```markdown
## Decision (to be filled in by Yasir)

- Date decided: _____
- Choice: _____
- Rationale / any counsel consulted: _____
```

with:

```markdown
## Decision

- Date decided: 2026-07-09
- Choice: Option 1 — keep Source A, add an explicit informed-consent gate before login.
- Rationale: lowest-effort mitigation that makes the ToS tension explicit to the
  user rather than only documented in README/PRIVACY prose; the app is already
  live and being promoted, so an immediate mitigation matters more than a
  perfect one. Option 3 (OAuth pivot, ROADMAP #12) remains the tracked durable
  fix — this consent gate is not a substitute for it, just the interim
  mitigation. Implemented in
  `docs/superpowers/plans/2026-07-09-source-a-consent-gate.md`.
```

- [ ] **Step 2: Commit**

```bash
git add docs/TOS_REVIEW.md
git commit -m "docs: record the Source A ToS decision (Option 1, consent gate)"
```
