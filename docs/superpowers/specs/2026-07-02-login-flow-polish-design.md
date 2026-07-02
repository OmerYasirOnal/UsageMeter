# Login flow polish ("curtain") — design

**Date:** 2026-07-02 · **Approach chosen:** native curtain overlay + hardened Google popup
(user asked to professionalize the login flow: smooth Google sign-in, and never show
claude.ai's usage page inside the app after login).

## Problem

Today the login window loads `claude.ai/settings/usage`, the user signs in, the
Coordinator hops the **visible** WebView to the Usage page, capture fires, and the
window closes 2.5 s later — the user watches claude.ai's usage dashboard render
before the window vanishes. Google sign-in has also been reported to error.

Empirical findings (live WKWebView harness, this machine, 2026-07-02):
- The Google button renders and its OAuth popup reaches Google's real sign-in page
  with the current Safari-UA + shared-configuration popup handling — no
  `disallowed_useragent` block at that stage. If Google blocks, it happens at the
  credential/2FA step (not testable without credentials), where Google's checks are
  strictest and a modern UA matters.
- The "button stuck at Loading…" symptom is transient page-load slowness, not a bug
  in our injection (verified with and without the capture script, old/new UA,
  clean and real cookie stores).

## Design

### 1. Login phase machine (`LoginFlowModel`, UsageMeterKit `Account/`)

Pure, Foundation-only reducer so it is unit-testable (precedent: `AccountRefreshPolicy`).

Phases: `signingIn → fetching → captured`, plus `fetchTimeout` (escape hatch).

Events (inputs):
- `loggedInPageFinished` (Coordinator decided to hop to Usage) → `fetching`, stamps start time.
- `backOnLoginPage` → back to `signingIn` (re-armed, curtain lifts).
- `usageCaptured` → `captured` from ANY phase (page may fire usage on its own).
- `tick(now)` in `fetching` past 15 s → `fetchTimeout`.
- `retryRequested` from `fetchTimeout` → `fetching` (re-hop, timer restarts).

### 2. Curtain overlay (`AccountLoginScreen`)

- `signingIn`: WebView visible as today (plus initial loading state).
- `fetching`: full-window native overlay (app icon mark, "Signed in ✓ — fetching your
  usage…", spinner) covers the WebView **before** the hop to `/settings/usage`, so the
  claude.ai usage page is never visible. The hidden WebView still performs the hop —
  the empirical capture/discovery pipeline is unchanged.
- `captured`: overlay flips to a success checkmark; window auto-closes after **0.8 s**
  (was 2.5 s). Respect `accessibilityReduceMotion` for the transition.
- `fetchTimeout`: curtain lifts (WebView visible again) + a banner: "Couldn't fetch your
  usage yet" with a **Retry** button (re-hops to the Usage page under the curtain).

Coordinator → UI wiring: `LoginWebController` gains `@Published var phase` driven by the
Coordinator's existing `didFinish` logic (the same place that sets `requestedUsage`) and
by `auth.lastCaptured`.

### 3. Google hardening + chrome polish

- UA version bump: `Version/18.3` → `Version/26.0` (macOS token stays `10_15_7`, the
  frozen standard), main WebView + popup.
- OAuth popup: title "Continue with Google", 480×700, centered **relative to the login
  window**; shares the configuration/data store as today.
- Remove the dev-era "Usage Page" toolbar button; keep Reload + Done.
- Window slimmed to a login-sized default (~640×760, min 560×640) — it no longer needs
  to fit a usage dashboard.
- Footer: keep the one-line privacy sentence; keep the "if Google errors, use email"
  tip (it is the honest fallback while Google's credential-step behavior remains
  outside our control).

## Error handling

- Capture never fires → 15 s timeout → curtain lifts + Retry (user is never trapped
  behind a spinner).
- User logs out mid-flow / lands back on a login page → phase returns to `signingIn`.
- Window closed manually in any phase → close task cancelled (existing behavior kept).

## Testing

- `LoginFlowModelTests` (Kit): every transition above incl. timeout boundary,
  capture-while-signingIn, retry re-arms the timer.
- Manual: real login on this machine (the user must re-login anyway after the
  bundle-ID move) — verify the usage page is never visible and the window closes fast.
- Both build variants (`swift build`, `-DAPPSTORE`) — the whole file is `#if !APPSTORE`.

## Out of scope

Headless-first fetch via a hardcoded `/api/organizations` call (rejected: second
unofficial endpoint, weakens the empirical-discovery resilience); system-browser
login (cannot capture cookies); popup-failure auto-detection (Google's error pages
are not reliably detectable).
