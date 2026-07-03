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

    /// The injected script saw claude.ai's verification-code screen. Reveals
    /// the WebView; if the screen only appeared after the autofill timeout
    /// already fired, also clears the now-wrong "couldn't prefill" banner —
    /// the prefill actually succeeded, it was just slow.
    public mutating func codeScreenDetected() {
        switch phase {
        case .autofilling:
            phase = .signingIn
        case .signingIn where autofillFailed:
            autofillFailed = false
        default:
            break
        }
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
