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

    private static let maxResponseBytes = 1_000_000

    public init(
        session: any AccountSessionProviding,
        endpoint: any AccountEndpointProviding,
        captured: (any AccountCapturedUsageProviding)? = nil,
        urlSession: URLSession = .shared,
        extraHeaders: [String: String] = [:],
        capturedMaxAge: TimeInterval = 600,
        decode: @escaping @Sendable (Data) -> AccountUsage? = { AccountUsageDecoder.decode($0) },
        onAuthResult: (@Sendable (Bool) -> Void)? = nil
    ) {
        self.session = session
        self.endpoint = endpoint
        self.captured = captured
        self.urlSession = urlSession
        self.extraHeaders = extraHeaders
        self.capturedMaxAge = capturedMaxAge
        self.decode = decode
        self.onAuthResult = onAuthResult
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
        if http.statusCode == 401 || http.statusCode == 403 {
            onAuthResult?(false)
            return nil // session dead — do not show stale captured data
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
