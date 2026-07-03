# Email-first login flow (Source A) — design

**Date:** 2026-07-03 · **Status:** approved by Yasir · **Scope:** `#if !APPSTORE` builds only (Source A login is excluded from the App Store target).

## Goal

Match the competitor's ("Usage for Claude") email-first sign-in UX: the user types
their claude.ai email in a **native** step screen, the app drives claude.ai's
magic-code login for them (email prefilled + submitted), and the WebView is only
revealed at the code-entry step. Everything after login (curtain → usage capture →
auto-close) is already built and stays unchanged.

Verified live against claude.ai/login (2026-07-03):
- Email field: `input#email` with `data-testid="email"`, `type="email"` — a React
  controlled input, so autofill must use the native value setter and dispatch an
  `input` event before submitting.
- Submit: the surrounding `form`'s `button[type=submit]` ("Continue with email"),
  or `form.requestSubmit()`.

## Decisions

1. **Email-primary, full page as fallback.** The native email screen is the
   default path. A small link — "Use the full claude.ai sign-in page" — skips
   autofill and shows the WebView immediately (covers Google/SSO users and any
   future DOM breakage). Google login is NOT removed, just demoted; the existing
   hint ("if Google errors, try email") moves to the fallback view.
2. **No native code entry.** The user types the verification code on claude.ai's
   own page inside the WebView. Proxying the code through claude.ai's auth API
   directly (fully native flow) is rejected: deeper ToS exposure and fragile
   against bot protection.
3. **Graceful degradation is mandatory.** If the email form can't be found and
   submitted within 8 s, the curtain lifts and the untouched claude.ai page is
   shown with a hint ("Couldn't prefill your email — enter it on the page.").
   A claude.ai DOM change degrades to today's flow, never to a dead end.
4. **Remember the email** in `UserDefaults` (`@AppStorage`) to prefill the native
   field next time. It is the user's own address, not a credential; it is cleared
   on logout along with everything else, consistent with "Log out wipes it".

## Flow / phase machine (`LoginFlowModel`, UsageMeterKit — pure, testable)

New phases prepended to the existing machine:

```
enterEmail ──emailSubmitted(now)──▶ autofilling(since)
enterEmail ──fullPageRequested──▶ signingIn
autofilling ──codeScreenDetected──▶ signingIn          (WebView revealed at code entry)
autofilling ──tick past 8 s──▶ signingIn + autofillFailed flag   (reveal + hint)
signingIn / fetching / captured / fetchTimeout — unchanged from today
```

Rules:
- `backOnLoginPage()` must NOT fire while in `enterEmail`/`autofilling` (the login
  page finishing its load is expected there, not a regression signal).
- `loggedInPageFinished` may arrive during `autofilling` (already-valid session:
  claude.ai skips straight past login) → go directly to `fetching`.
- `autofillFailed` is a one-shot presentation flag on the model, cleared when the
  phase leaves `signingIn`.
- Initial phase is `enterEmail` (was `signingIn`).

## Native email screen (`AccountLoginScreen`, Kiln style)

- Title "Sign in with Email", subtitle, 3 numbered steps: enter your claude.ai
  email ("Google login works via the full page" footnote) / check your inbox /
  enter the code on the next screen.
- Privacy note reuses the existing copy (never sees password, usage-only, local).
- Bottom bar: email `TextField` (prefilled from `@AppStorage("accountLoginEmail")`,
  basic contains-"@" validation) + prominent "Sign in to Claude" button
  (`.defaultAction`), plus the full-page fallback link.
- The WebView is NOT created until the user leaves `enterEmail` (avoids loading
  claude.ai before it's needed).

## Autofill + code-screen detection (WebView side)

- While `autofilling`, a native cover ("Sending you a sign-in code…") hides the
  WebView, mirroring the existing curtain style.
- On `didFinish` of the login page during `autofilling`, the Coordinator runs an
  injected script with the target email:
  - Poll (interval ≤ 500 ms, ≤ 8 s) for `input#email, input[data-testid="email"],
    input[type="email"]`; set the value via
    `Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'value').set`,
    dispatch `input`, then `form.requestSubmit()` (fallback: click
    `button[type=submit]`). Submit exactly once.
  - Separately observe the DOM (MutationObserver + poll) for the code screen —
    an input whose `placeholder`/`data-testid`/`autocomplete` mentions
    code/one-time-code — and post `{kind:"loginFlow", event:"codeScreen"}` on a
    new `WKScriptMessage` handler (`loginFlow`), distinct from the existing
    `usageProbe` capture handler, which is untouched.
- The email travels only into the claude.ai page (first-party); it is never sent
  anywhere else. No change to the capture/privacy surface.
- The native timeout clock lives in Swift (`tick`), not in JS, so a hung page
  still degrades correctly.

## Unchanged

`AccountAuth` (cookies, capture, endpoint discovery, logout — plus one line to
clear the remembered email), post-login curtain, usage hop, auto-close, popup
handling for OAuth, adaptive refresh, all of Source B/C.

## Testing

- `LoginFlowModelTests`: every new transition (email submit, code-screen detect,
  autofill timeout, full-page skip, logged-in-during-autofill shortcut,
  backOnLoginPage guards, autofillFailed lifecycle).
- Autofill JS + UI: manual verification via `make run` against real claude.ai
  (mock URL env var path must still work: `USAGEMETER_MOCK_USAGE_URL` start URL
  skips the email phase entirely — mock mode goes straight to `signingIn`).
