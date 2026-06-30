import Foundation
import Combine
import WebKit
import UsageMeterKit

/// The app-side bridge for Source A: owns an isolated, persistent
/// `WKWebsiteDataStore` for the claude.ai login, tracks login state, exposes
/// host-scoped cookies + the discovered endpoint to the headless
/// `LiveAccountUsageClient`, and handles logout.
///
/// ⚠️ ToS grey-area surface. Privacy: the capture path only ever ingests
/// *usage-shaped* first-party responses (URLs whose path names usage/rate-limit/
/// quota) — never conversation or account endpoints — and the capture file holds
/// only those usage responses, wiped on logout.
@MainActor
final class AccountAuth: ObservableObject, AccountSessionProviding, AccountEndpointProviding, AccountCapturedUsageProviding {
    @Published private(set) var isAuthenticated: Bool
    @Published private(set) var endpointInfo: AccountEndpointInfo?
    /// Last usage decoded directly from a WebView capture (resilient fallback).
    @Published private(set) var lastCaptured: AccountUsage?
    @Published private(set) var captureCount = 0

    /// Isolated, stable, persistent store — keeps UsageMeter's claude.ai login data
    /// separate from any other WebKit usage, and lets logout wipe only this store.
    let dataStore: WKWebsiteDataStore

    private let endpointStore: AccountEndpointStore
    private let captureFileURL: URL
    private let discoveryFileURL: URL
    /// Host allowed in addition to claude.* for local self-tests (mock mode only).
    private let testHost: String?

    private static let storeIdentifier = UUID(uuidString: "F1A2B3C4-D5E6-4789-9012-3456789ABCDE")!
    /// Path tokens that mark a usage-related (not conversation/account) endpoint.
    private static let usagePathTokens = ["usage", "rate_limit", "ratelimit", "rate-limit", "utilization", "quota"]

    init(endpointStore: AccountEndpointStore = AccountEndpointStore()) {
        self.endpointStore = endpointStore
        self.dataStore = WKWebsiteDataStore(forIdentifier: Self.storeIdentifier)
        self.captureFileURL = UsageStore.defaultDirectory()
            .appendingPathComponent("account_capture.json", isDirectory: false)
        self.discoveryFileURL = UsageStore.defaultDirectory()
            .appendingPathComponent("account_discovery.json", isDirectory: false)
        self.testHost = ProcessInfo.processInfo.environment["USAGEMETER_MOCK_USAGE_URL"]
            .flatMap { URL(string: $0)?.host?.lowercased() }
        let info = endpointStore.load()
        self.endpointInfo = info
        self.isAuthenticated = info != nil // optimistic; first fetch (401) corrects it
        Task { await reconcileLoginState() }
    }

    // MARK: - AccountSessionProviding

    var isLoggedIn: Bool { get async { isAuthenticated } }

    /// Cookies scoped to `host` only (RFC-6265-ish domain suffix match).
    func cookieHeader(for host: String) async -> String? {
        let target = host.lowercased()
        let relevant = await allCookies().filter { Self.cookie($0, matchesHost: target) }
        guard !relevant.isEmpty else { return nil }
        return relevant.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }

    private static func cookie(_ cookie: HTTPCookie, matchesHost host: String) -> Bool {
        var domain = cookie.domain.lowercased()
        if domain.hasPrefix(".") { domain.removeFirst() }
        return host == domain || host.hasSuffix("." + domain)
    }

    // MARK: - AccountEndpointProviding

    func usageEndpoint() async -> AccountEndpointInfo? { endpointInfo }

    // MARK: - AccountCapturedUsageProviding

    func recentCapturedUsage(maxAge: TimeInterval) async -> AccountUsage? {
        guard let usage = lastCaptured, let at = usage.fetchedAt,
              Date().timeIntervalSince(at) <= maxAge else { return nil }
        return usage
    }

    // MARK: - Auth state

    /// Called from the headless client's auth callback. `false` on 401/403 marks
    /// the session dead and invalidates any captured fallback.
    func setAuthenticated(_ value: Bool) {
        if isAuthenticated != value { isAuthenticated = value }
        if !value, lastCaptured != nil { lastCaptured = nil }
    }

    private func reconcileLoginState() async {
        // No claude cookies at all → definitely logged out.
        if await cookieHeader(for: "claude.ai") == nil {
            setAuthenticated(false)
        }
    }

    // MARK: - Capture (endpoint discovery)

    /// Ingest a candidate response from the login WebView's capture hook.
    /// First-party API URLs are recorded **path-only** (no body) so the real usage
    /// endpoint can be identified; the response BODY is only ingested for
    /// usage-shaped 2xx responses. Decode + disk I/O run off the main actor (§8).
    func ingestCapture(url: String, status: Int, body: String) {
        captureCount += 1
        guard let parsed = URL(string: url), isAllowedHost(parsed) else { return }

        let discoveryFileURL = self.discoveryFileURL
        let captureFileURL = self.captureFileURL
        let path = parsed.path
        let isUsage = isUsageURL(url)
        let shouldCaptureBody = isUsage && (200..<300).contains(status) && !body.isEmpty

        Task.detached(priority: .utility) {
            // Endpoint discovery: paths only, never bodies, never query strings.
            Self.appendDiscovery(path: path, status: status, to: discoveryFileURL)

            guard shouldCaptureBody else { return }
            let decoded = AccountUsageDecoder.decode(Data(body.utf8))
            Self.appendCapture(url: url, status: status, body: body, to: captureFileURL)
            await MainActor.run {
                if let usage = decoded, usage.hasAnyMetric {
                    self.lastCaptured = usage
                }
                self.rememberEndpoint(url)
            }
        }
    }

    private func isUsageURL(_ raw: String) -> Bool {
        guard let url = URL(string: raw), isAllowedHost(url) else { return false }
        let path = url.path.lowercased()
        return Self.usagePathTokens.contains { path.contains($0) }
    }

    private func isAllowedHost(_ url: URL) -> Bool {
        if AccountHosts.isFirstParty(url: url) { return true }
        if let testHost, url.host?.lowercased() == testHost { return true }
        return false
    }

    private func rememberEndpoint(_ url: String) {
        let info = AccountEndpointInfo(url: url, method: "GET", capturedAt: Date())
        guard info.isValidFirstParty else { return }
        if endpointInfo?.url != url {
            endpointInfo = info
            endpointStore.save(info)
        }
        isAuthenticated = true
    }

    // MARK: - Logout

    func logout() async {
        await removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes())
        endpointStore.clear()
        try? FileManager.default.removeItem(at: captureFileURL)
        try? FileManager.default.removeItem(at: discoveryFileURL)
        endpointInfo = nil
        lastCaptured = nil
        captureCount = 0
        isAuthenticated = false
    }

    // MARK: - WebKit async wrappers

    private func allCookies() async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            dataStore.httpCookieStore.getAllCookies { continuation.resume(returning: $0) }
        }
    }

    private func removeData(ofTypes types: Set<String>) async {
        await withCheckedContinuation { continuation in
            dataStore.removeData(ofTypes: types, modifiedSince: .distantPast) {
                continuation.resume()
            }
        }
    }

    // MARK: - Capture persistence (usage-only; for finalizing the exact decoder)

    private struct Candidate: Codable {
        var url: String
        var status: Int
        var body: String
        var at: Date
    }

    /// Persists only usage-matched responses (gated by the caller) so the exact
    /// decoder can be finalized. Wiped on logout. Runs off the main actor.
    /// Records discovered API paths (no body, no query string) so the real usage
    /// endpoint can be identified. Deduplicated by path, last 40, wiped on logout.
    nonisolated private static func appendDiscovery(path: String, status: Int, to fileURL: URL) {
        struct Probe: Codable, Equatable { var path: String; var status: Int }
        var existing: [Probe] = []
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([Probe].self, from: data) {
            existing = decoded
        }
        let probe = Probe(path: path, status: status)
        guard !existing.contains(probe) else { return }
        existing.append(probe)
        if existing.count > 40 { existing = Array(existing.suffix(40)) }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        try? encoder.encode(existing).write(to: fileURL, options: [.atomic])
    }

    nonisolated private static func appendCapture(url: String, status: Int, body: String, to fileURL: URL) {
        var existing: [Candidate] = []
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([Candidate].self, from: data) {
            existing = decoded
        }
        existing.append(Candidate(url: url, status: status, body: String(body.prefix(20000)), at: Date()))
        if existing.count > 5 { existing = Array(existing.suffix(5)) }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        try? encoder.encode(existing).write(to: fileURL, options: [.atomic])
    }
}
