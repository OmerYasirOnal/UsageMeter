import Foundation

/// Supplies the authenticated session for headless account requests. Implemented
/// in the app layer over `WKWebsiteDataStore` cookies; abstracted here so the
/// client stays in Kit and is unit-testable with a stub.
public protocol AccountSessionProviding: Sendable {
    var isLoggedIn: Bool { get async }
    /// A `Cookie:` header value scoped to `host` (only cookies whose domain matches
    /// that host), or nil. Scoping prevents sending unrelated cookies cross-domain.
    func cookieHeader(for host: String) async -> String?
}

/// Supplies the usage endpoint that was discovered empirically by the in-app
/// capture (never hard-coded by guess — see the brief §3.2).
public protocol AccountEndpointProviding: Sendable {
    func usageEndpoint() async -> AccountEndpointInfo?
}

/// Supplies a usage value captured directly by the login WebView, used as a
/// short-lived fallback when the headless replay can't reproduce the request.
/// Keeps Source A fully behind the client (no UI-layer side channel).
public protocol AccountCapturedUsageProviding: Sendable {
    /// The last captured usage, but only if newer than `maxAge` seconds.
    func recentCapturedUsage(maxAge: TimeInterval) async -> AccountUsage?
}

/// First-party hosts we will ever attach claude.ai session cookies to.
public enum AccountHosts {
    public static let allowed = ["claude.ai", "claude.com", "anthropic.com"]

    public static func isFirstParty(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return allowed.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    public static func isFirstParty(url: URL) -> Bool {
        isFirstParty(url.host)
    }
}
