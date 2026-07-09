# Source A explicit consent gate — design

**Date:** 2026-07-09 · **Status:** approved by Yasir · **Scope:** `#if !APPSTORE` builds only (the App Store variant excludes Source A entirely, so this doesn't touch it).

## Goal

Resolve the top open item in `docs/STATUS.md` / `docs/TOS_REVIEW.md`: the 2026-07-03
ToS review found that Anthropic's Consumer Terms §3 (automated/non-human access,
except via an API key) appears to directly cover what Source A does (headless
replay of claude.ai's usage endpoint with the user's own cookies). Yasir's decision
(of the 4 documented options): **Option 1 — keep Source A, add an explicit
informed-consent gate before login.** This doesn't remove the underlying tension,
but makes the user's acceptance of it explicit rather than implicit in README prose
they may never read.

## Decisions

1. **New phase in the existing login window, not a separate popover-level gate.**
   `LoginFlowModel` already has a phase reducer with a native first-step screen
   (`enterEmail`, added for the email-first login flow) — a `.consent` phase slots
   in before it using the exact same pattern (native SwiftUI card, no WebView yet).
2. **Shown once, ever, per device.** Persisted via `@AppStorage`, same mechanism as
   the already-remembered login email. `Log out` does **not** clear it — consent is
   about the automated-access mechanism, not the login session.
3. **Direct framing.** The screen states the ToS tension in plain language (matches
   CLAUDE.md's "handle honestly — do not fake" rule for Source A), not a softened
   "unofficial endpoint" euphemism. Exact copy below.
4. **Single "I Understand, Continue" button, no checkbox.** Declining has no new
   UI — the window's existing "Done" button (always visible) closes it without
   proceeding, identical to backing out of today's email step.
5. **Mock/demo mode is unaffected** — `USAGEMETER_MOCK_USAGE_URL` continues to skip
   straight to `.signingIn` as it does today; the consent gate only applies to a
   real login attempt.

## `LoginFlowModel` changes (`Sources/UsageMeterKit/Account/LoginFlowModel.swift`)

- `Phase` gains a new case: `case consent`.
- `init(skipEmailStep: Bool = false, showConsentGate: Bool = false)`. **Correction
  from an earlier draft of this spec:** the flag is named and defaulted so that
  bare `LoginFlowModel()` — used throughout the ~15 existing call sites in
  `LoginFlowModelTests.swift` — keeps starting at `.enterEmail` unchanged; only the
  one real production call site (`LoginWebController.init()`, below) explicitly
  passes `showConsentGate: true` when consent hasn't been granted yet. A
  `consentGranted: Bool = false` parameter (defaulting to *show* the gate) would
  have silently broken every existing test that constructs a bare
  `LoginFlowModel()` expecting `.enterEmail`.
  - `skipEmailStep` (mock) → `.signingIn`, unchanged.
  - else `showConsentGate` → `.consent` (new — only when the caller explicitly asks for it).
  - else → `.enterEmail`, unchanged default (matches every existing test's assumption).
- New mutating method:
  ```swift
  /// The user accepted the automated-access disclosure on the consent screen.
  public mutating func consentAccepted() {
      guard phase == .consent else { return }
      phase = .enterEmail
  }
  ```
- `backOnLoginPage()`: add `.consent` to the existing no-op group (alongside
  `.captured, .enterEmail, .autofilling`) — the switch is exhaustive, so this is
  required for the file to compile, and a login-page navigation event during the
  consent screen (before any WebView exists) is meaningless and must stay a no-op.
- `loggedInPageFinished(now:)`: add `.consent` to the existing no-op/return group
  (alongside `.enterEmail, .fetching, .captured`) — same exhaustiveness requirement,
  same reasoning (no WebView exists yet during consent).
- `tick`, `codeScreenDetected`, `emailSubmitted`, `fullPageRequested`,
  `retryRequested`, `usageCaptured` — no changes needed; each either already has a
  `default`/`guard` that safely no-ops on `.consent`, or (in `usageCaptured`'s case)
  is unconditional and has no realistic path to fire during `.consent` (no WebView
  is attached to trigger a capture message).

## `AccountLoginView.swift` changes

- `LoginWebController.init()`: currently reads only the mock env var. Also read
  the persisted consent flag and pass both into the model:
  ```swift
  let mock = ProcessInfo.processInfo.environment["USAGEMETER_MOCK_USAGE_URL"] != nil
  let consentGranted = UserDefaults.standard.bool(forKey: "accountLoginConsentGranted")
  flow = LoginFlowModel(skipEmailStep: mock, showConsentGate: !consentGranted)
  ```
- `AccountLoginScreen`:
  - New `@AppStorage("accountLoginConsentGranted") private var consentGranted = false`
    (mirrors the existing `@AppStorage("accountLoginEmail")`).
  - New `private var isConsentStep: Bool { controller.flow.phase == .consent }`.
  - New `private func acceptConsent() { consentGranted = true; controller.flow.consentAccepted() }`.
  - Header title: extend the existing ternary to a 3-way switch —
    `.consent` → "Before You Continue", `.enterEmail` → "Sign in with Email",
    else → "Sign in to claude.ai".
  - The reload button and the "If Continue with Google errors…" footer hint are
    currently gated on `!isEmailStep`; extend both to `!isEmailStep && !isConsentStep`
    (neither is meaningful before a WebView exists).
  - The body `ZStack` gains a third branch: `if isConsentStep { consentStep } else if isEmailStep { emailStep } else { <existing WebView + curtain> }`.
  - The existing bottom privacy paragraph ("UsageMeter never sees your
    password…") stays visible on every phase, unchanged — it's still accurate and
    reinforcing it doesn't hurt.

### New `consentStep` view

Mirrors `emailStep`'s layout: centered `VStack`, a card on `.quaternary.opacity(0.35)`
background, `maxWidth: 460`, matching padding/spacing conventions already in the file.

Copy (exact, Turkish product but this is the shipping English string — matches the
file's existing English-only UI copy convention):

> **UsageMeter's account features (session %, weekly %, real spend) read your
> usage numbers by automatically signing in to claude.ai — the same way you're
> already logged in, just replayed by the app instead of a browser tab.**
>
> Anthropic's Consumer Terms of Service prohibit accessing their Services
> "through automated or non-human means" except via an official API key. This
> app does exactly that — for read-only usage numbers only, never your messages
> or account actions — which means using this feature falls outside Anthropic's
> stated Terms.
>
> This is entirely optional. Claude Code token tracking works fully without ever
> logging in.

Button: "I Understand, Continue" — `.buttonStyle(.borderedProminent).tint(Theme.accent)`,
`.keyboardShortcut(.defaultAction)` (matches `emailStep`'s submit button), calls
`acceptConsent()`.

## `docs/TOS_REVIEW.md` update

Fill in the previously-blank "Decision" section at the bottom of the file:

```
## Decision

- Date decided: 2026-07-09
- Choice: Option 1 — keep Source A, add an explicit informed-consent gate before login.
- Rationale: lowest-effort mitigation that makes the ToS tension explicit to the
  user rather than only documented in README/PRIVACY prose; app is already live
  and being promoted, so an immediate mitigation matters more than a perfect one.
  Option 3 (OAuth pivot, ROADMAP #12) remains the tracked durable fix — this
  consent gate is not a substitute for it, just the interim mitigation.
```

## Testing

`Tests/UsageMeterKitTests/LoginFlowModelTests.swift` — new cases (TDD), all existing
cases untouched (see the correction above — default behavior is unchanged):
- Default `init()` (no args) still starts at `.enterEmail` — regression guard for
  the correction above, so a future edit can't silently flip the default back.
- `init(showConsentGate: true)` starts at `.consent`.
- `init(skipEmailStep: true, showConsentGate: true)` still starts at `.signingIn`
  (mock overrides consent gating, matching today's mock behavior).
- `consentAccepted()` from `.consent` transitions to `.enterEmail`.
- `consentAccepted()` from any other phase (e.g. `.enterEmail`) is a no-op.
- `backOnLoginPage()` from `.consent` stays `.consent` (no-op).
- `loggedInPageFinished(now:)` from `.consent` stays `.consent` (no-op).

`AccountLoginScreen`/`consentStep` (SwiftUI view) — not unit tested, matching this
project's existing convention (no view-layer tests anywhere in the codebase).
Verified manually via `make run`: delete the `accountLoginConsentGranted` default
(or use a fresh `defaults delete` profile), open login, confirm the consent screen
appears before the email step, confirm accepting it never reappears on a second
login attempt, confirm "Done" closes the window without granting consent.

## Unchanged

Everything else about the login flow (email autofill, code-screen detection,
curtain/fetch timeout, popup OAuth handling, logout wiping cookies+email),
Source B/C, the App Store build (excludes Source A entirely, untouched by this).
