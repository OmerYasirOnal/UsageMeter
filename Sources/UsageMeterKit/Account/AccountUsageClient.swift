import Foundation

/// Source A — the account (claude.ai) usage numbers: the *primary* session % and
/// weekly %. This is the ONLY seam that touches the unofficial, undocumented
/// claude.ai endpoint.
///
/// ⚠️ ToS CAVEAT (see CLAUDE.md / README): automating authenticated access to
/// claude.ai is a Terms-of-Service grey area and the endpoint can change without
/// notice. Everything risky is isolated behind this protocol so that:
///   • breakage is contained to one swappable implementation, and
///   • the app stays fully useful in *local-only mode* (Sources B + C) when this
///     returns `nil` or throws.
///
/// Milestone 1 ships only `LocalOnlyAccountUsageClient` (always logged-out).
/// Milestone 2 adds the WKWebView-login-backed implementation.
public protocol AccountUsageClient: Sendable {
    /// Whether a session is currently available (cookies present + valid).
    var isAuthenticated: Bool { get async }

    /// Fetch the latest account usage, or `nil` when not logged in.
    /// Implementations should throw only on genuine errors (network/endpoint),
    /// never to signal "logged out".
    func currentUsage() async throws -> AccountUsage?
}

/// Milestone-1 default: no login, no network, no ToS exposure. The app runs in
/// local-only mode and the headline numbers come up empty (the UI shows a
/// "Log in for session/weekly %" affordance, wired up in M2).
public struct LocalOnlyAccountUsageClient: AccountUsageClient {
    public init() {}
    public var isAuthenticated: Bool { get async { false } }
    public func currentUsage() async throws -> AccountUsage? { nil }
}

/// Errors the M2 implementation may surface; defined now so call sites are stable.
public enum AccountUsageError: Error, Sendable, Equatable {
    case notAuthenticated
    case endpointChanged
    case decodingFailed
    case network(String)
}
