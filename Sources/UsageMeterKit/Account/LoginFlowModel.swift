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
