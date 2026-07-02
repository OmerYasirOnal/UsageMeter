import Foundation

/// The Milestone-2 account client (Source A). Replays the usage request headlessly
/// using the captured session cookies + the empirically-discovered endpoint, then
/// decodes the response. This is the ONE place that touches the unofficial
/// claude.ai endpoint.
///
/// Failure handling:
///   • logged out / no endpoint / non-first-party endpoint → `nil` (local-only).
///   • 401/403 → session invalid: report auth=false and return `nil` (don't show
///     stale captured data).
///   • offline / 5xx / 429 / decode-fail while logged in → return a *recent*
///     captured value if available (resilience), else `nil`.
///   • success → report auth=true and return the decoded usage.
public struct LiveAccountUsageClient: AccountUsageClient {
    private let session: any AccountSessionProviding
    private let endpoint: any AccountEndpointProviding
    private let captured: (any AccountCapturedUsageProviding)?
    private let urlSession: URLSession
    private let extraHeaders: [String: String]
    private let capturedMaxAge: TimeInterval
    private let decode: @Sendable (Data) -> AccountUsage?
    /// Reports authentication outcome: true on a 2xx, false on 401/403.
    private let onAuthResult: (@Sendable (Bool) -> Void)?
    /// Hands back cookies the server set on a replay response so the app can
    /// persist them into the WebKit store — claude.ai rotates/extends session
    /// cookies, and dropping those updates kills the login at its ORIGINAL
    /// expiry (the "logged out after a while" failure mode).
    private let onSetCookies: (@Sendable ([HTTPCookie]) -> Void)?

    private static let maxResponseBytes = 1_000_000

    public init(
        session: any AccountSessionProviding,
        endpoint: any AccountEndpointProviding,
        captured: (any AccountCapturedUsageProviding)? = nil,
        urlSession: URLSession = .shared,
        extraHeaders: [String: String] = [:],
        capturedMaxAge: TimeInterval = 600,
        decode: @escaping @Sendable (Data) -> AccountUsage? = { AccountUsageDecoder.decode($0) },
        onAuthResult: (@Sendable (Bool) -> Void)? = nil,
        onSetCookies: (@Sendable ([HTTPCookie]) -> Void)? = nil
    ) {
        self.session = session
        self.endpoint = endpoint
        self.captured = captured
        self.urlSession = urlSession
        self.extraHeaders = extraHeaders
        self.capturedMaxAge = capturedMaxAge
        self.decode = decode
        self.onAuthResult = onAuthResult
        self.onSetCookies = onSetCookies
    }

    public var isAuthenticated: Bool {
        get async { await session.isLoggedIn }
    }

    public func currentUsage() async throws -> AccountUsage? {
        guard let info = await endpoint.usageEndpoint(),
              info.isValidFirstParty,
              let url = info.resolvedURL,
              let host = url.host,
              let cookieHeader = await session.cookieHeader(for: host), !cookieHeader.isEmpty else {
            return nil // not logged in / no (valid) endpoint
        }

        var request = URLRequest(url: url)
        request.httpMethod = info.method
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("UsageMeter/1.0", forHTTPHeaderField: "User-Agent")
        for (key, value) in extraHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            return await capturedFallback() // offline / transient → resilience
        }

        guard let http = response as? HTTPURLResponse else {
            return await capturedFallback()
        }
        // Persist rotated cookies ONLY from healthy responses. Error/challenge
        // responses (401/403/5xx) can carry session-CLEARING Set-Cookie headers —
        // writing those back would log the user out by our own hand. Same reason
        // already-expired cookies (deletions) are skipped.
        if let onSetCookies, (200...299).contains(http.statusCode),
           let fields = http.allHeaderFields as? [String: String] {
            let cookies = HTTPCookie.cookies(withResponseHeaderFields: fields, for: url)
                .filter { cookie in
                    guard let expires = cookie.expiresDate else { return true } // session cookie
                    return expires > Date()
                }
            if !cookies.isEmpty { onSetCookies(cookies) }
        }
        if http.statusCode == 401 {
            onAuthResult?(false)
            return nil // unauthorized — session dead; don't show stale captured data
        }
        if http.statusCode == 403 {
            // 403 is frequently a transient bot-challenge / rate-limit rather than a
            // dead session — don't flap to logged-out or wipe the capture; serve a
            // recent capture (or nil) like other transient errors. A truly dead
            // session surfaces as 401 or an expired capture → local-only.
            return await capturedFallback()
        }
        guard (200...299).contains(http.statusCode) else {
            return await capturedFallback() // 5xx / 429 → keep last good if recent
        }
        guard data.count <= Self.maxResponseBytes, let usage = decode(data) else {
            // Logged in but couldn't decode (endpoint shape changed). Prefer a recent
            // capture; otherwise nil. (Endpoint-changed surfacing is future work.)
            return await capturedFallback()
        }
        onAuthResult?(true)
        return usage
    }

    private func capturedFallback() async -> AccountUsage? {
        guard let captured else { return nil }
        return await captured.recentCapturedUsage(maxAge: capturedMaxAge)
    }
}
