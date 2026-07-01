import Testing
import Foundation
@testable import UsageMeterKit

private let fixedNow = TestTime.date("2026-06-30T12:00:00Z")

// MARK: - Heuristic decoder

@Suite struct AccountUsageDecoderTests {
    let sample = #"""
    {
      "five_hour":      { "utilization": 42, "resets_at": "2026-06-30T15:00:00Z" },
      "seven_day":      { "utilization": 10, "resets_at": "2026-07-05T00:00:00Z" },
      "seven_day_opus": { "utilization": 88, "resets_at": "2026-07-05T00:00:00Z" }
    }
    """#

    @Test func classifiesSessionWeeklyAndOpus() throws {
        let usage = try #require(AccountUsageDecoder.decode(Data(sample.utf8), now: fixedNow))
        #expect(usage.session?.displayPercent == 42)
        #expect(usage.weekly?.displayPercent == 10)
        #expect(usage.weeklyOpus?.displayPercent == 88)
        #expect(usage.session?.resetsAt == TestTime.date("2026-06-30T15:00:00Z"))
    }

    @Test func acceptsAlreadyPercentValues() throws {
        let json = #"{"session":{"percent":73,"reset_at":"2026-06-30T15:00:00Z"}}"#
        let usage = try #require(AccountUsageDecoder.decode(Data(json.utf8), now: fixedNow))
        #expect(usage.session?.displayPercent == 73)
    }

    @Test func parsesEpochResetTimes() throws {
        let epoch = Int(TestTime.date("2026-06-30T15:00:00Z").timeIntervalSince1970)
        let json = "{\"five_hour\":{\"utilization\":0.5,\"resets_at\":\(epoch)}}"
        let usage = try #require(AccountUsageDecoder.decode(Data(json.utf8), now: fixedNow))
        #expect(usage.session?.resetsAt == TestTime.date("2026-06-30T15:00:00Z"))
    }

    @Test func handlesRelativeResetDurations() throws {
        // Non-exact key so the heuristic path (which handles relative durations) runs.
        let json = #"{"session_block":{"utilization":0.5,"resets_in":3600}}"#
        let usage = try #require(AccountUsageDecoder.decode(Data(json.utf8), now: fixedNow))
        #expect(usage.session?.resetsAt == fixedNow.addingTimeInterval(3600))
    }

    @Test func rejectsRawCountsAsPercent() {
        // "used" is not a percent key, and 543000 is out of the plausible range.
        let json = #"{"session":{"used":543000}}"#
        #expect(AccountUsageDecoder.decode(Data(json.utf8), now: fixedNow) == nil)
    }

    @Test func prefersSpecificPercentKeyDeterministically() throws {
        // Both keys present → priority order picks "utilization" over "pct".
        // (Non-exact key so the heuristic — which has the fraction scaling — runs.)
        let json = #"{"session_meter":{"pct":90,"utilization":0.2}}"#
        let usage = try #require(AccountUsageDecoder.decode(Data(json.utf8), now: fixedNow))
        #expect(usage.session?.displayPercent == 20)
    }

    @Test func ignoresInsaneAbsoluteResetDates() throws {
        let json = #"{"five_hour":{"utilization":0.5,"resets_at":"1999-01-01T00:00:00Z"}}"#
        let usage = try #require(AccountUsageDecoder.decode(Data(json.utf8), now: fixedNow))
        #expect(usage.session?.resetsAt == nil) // out of sanity window → dropped
    }

    @Test func returnsNilWhenNoMetricsFound() {
        #expect(AccountUsageDecoder.decode(Data(#"{"hello":"world"}"#.utf8), now: fixedNow) == nil)
        #expect(AccountUsageDecoder.decode(Data("not json".utf8), now: fixedNow) == nil)
    }

    /// The exact shape captured from the real claude.ai /usage endpoint.
    @Test func decodesRealClaudeShapeExactly() throws {
        let json = #"""
        {
          "five_hour": {"utilization": 29, "resets_at": "2026-06-30T16:29:00Z", "limit_dollars": null},
          "seven_day": {"utilization": 6, "resets_at": "2026-07-06T07:59:00Z"},
          "seven_day_opus": null,
          "seven_day_sonnet": {"utilization": 12, "resets_at": null},
          "spend": {"used": {"amount_minor": 0, "currency": "USD", "exponent": 2}, "can_purchase_credits": true},
          "limits": [{"kind": "session", "group": "session", "percent": 29, "severity": "ok", "resets_at": "2026-06-30T16:29:00Z", "is_active": true}]
        }
        """#
        let u = try #require(AccountUsageDecoder.decode(Data(json.utf8), now: fixedNow))
        #expect(u.session?.displayPercent == 29)
        #expect(u.weekly?.displayPercent == 6)
        #expect(u.weeklyOpus == nil)                 // seven_day_opus was null
        #expect(u.session?.resetsAt == TestTime.date("2026-06-30T16:29:00Z"))
        #expect(u.spend?.currency == "USD")
        #expect(u.spend?.usedAmount == 0.0)
        #expect(u.spend?.canPurchaseCredits == true)
    }

    /// The real bug: `utilization` is a 0...100 PERCENT (e.g. 39), not a 0...1
    /// fraction — so it must NOT be rescaled. Windows are primary; the `limits`
    /// array fills any category the windows don't carry (e.g. Opus).
    @Test func treatsUtilizationAsPercentAndUsesLimitsFallback() throws {
        let json = #"""
        {
          "five_hour": {"utilization": 39, "resets_at": "2026-06-30T16:29:00Z"},
          "seven_day": {"utilization": 8, "resets_at": "2026-07-06T07:59:00Z"},
          "seven_day_opus": null,
          "limits": [
            {"kind":"weekly_scoped","group":"opus","percent":12,"is_active":false,"resets_at":"2026-07-06T07:59:00Z"}
          ]
        }
        """#
        let u = try #require(AccountUsageDecoder.decode(Data(json.utf8), now: fixedNow))
        #expect(u.session?.displayPercent == 39)      // utilization used as-is, not *100
        #expect(u.weekly?.displayPercent == 8)
        #expect(u.weeklyOpus?.displayPercent == 12)   // from limits (window was null)
    }

    @Test func decodesRealSpendMinorUnits() throws {
        let json = #"{"five_hour":{"utilization":0.1,"resets_at":"2026-06-30T16:00:00Z"},"spend":{"used":{"amount_minor":350,"currency":"USD","exponent":2}}}"#
        let u = try #require(AccountUsageDecoder.decode(Data(json.utf8), now: fixedNow))
        #expect(u.spend?.usedAmount == 3.5)
    }
}

// MARK: - Adaptive refresh policy

@Suite struct AccountRefreshPolicyTests {
    func usage(_ percent: Double) -> AccountUsage {
        AccountUsage(session: UsageMetric(percent: percent), fetchedAt: Date())
    }

    @Test func loggedOutUsesBase() {
        #expect(AccountRefreshPolicy.interval(for: nil, base: 180) == 180)
        #expect(AccountRefreshPolicy.interval(for: AccountUsage(), base: 180) == 180)
    }

    @Test func tightensNearLimitAndClampsToMinimum() {
        #expect(AccountRefreshPolicy.interval(for: usage(95), base: 180) == 60)
    }

    @Test func scalesByUtilizationBand() {
        #expect(AccountRefreshPolicy.interval(for: usage(80), base: 180) == 90)
        #expect(AccountRefreshPolicy.interval(for: usage(60), base: 180) == 180)
        #expect(AccountRefreshPolicy.interval(for: usage(10), base: 180) == 360)
    }

    @Test func clampsToMaximum() {
        #expect(AccountRefreshPolicy.interval(for: usage(10), base: 2000) == 1800)
    }
}

// MARK: - Models, hosts, endpoint store

@Suite struct AccountModelTests {
    @Test func peakAndHasAnyMetric() {
        #expect(AccountUsage().hasAnyMetric == false)
        let u = AccountUsage(session: UsageMetric(percent: 12),
                             weekly: UsageMetric(percent: 80),
                             weeklyOpus: UsageMetric(percent: 55))
        #expect(u.hasAnyMetric)
        #expect(u.peakPercent == 80)
    }

    @Test func displayPercentClampsAndRounds() {
        #expect(UsageMetric(percent: 42.6).displayPercent == 43)
        #expect(UsageMetric(percent: -5).displayPercent == 0)
    }

    @Test func firstPartyHostAllowlist() {
        #expect(AccountHosts.isFirstParty("claude.ai"))
        #expect(AccountHosts.isFirstParty("api.claude.ai"))
        #expect(AccountHosts.isFirstParty("claude.com"))
        #expect(AccountHosts.isFirstParty("evil.com") == false)
        #expect(AccountHosts.isFirstParty("notclaude.ai") == false)
        #expect(AccountHosts.isFirstParty(nil) == false)
    }

    @Test func endpointInfoValidity() {
        #expect(AccountEndpointInfo(url: "https://claude.ai/api/usage").isValidFirstParty)
        #expect(AccountEndpointInfo(url: "/api/usage").isValidFirstParty == false)       // relative
        #expect(AccountEndpointInfo(url: "https://evil.com/usage").isValidFirstParty == false)
    }

    @Test func endpointStoreRoundTrips() {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("um-ep-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: dir) }
        let store = AccountEndpointStore(directory: dir)
        #expect(store.load() == nil)
        let info = AccountEndpointInfo(url: "https://claude.ai/api/usage", method: "GET",
                                       capturedAt: TestTime.date("2026-06-30T10:00:00Z"))
        #expect(store.save(info))
        #expect(store.load() == info)
        store.clear()
        #expect(store.load() == nil)
    }
}

// MARK: - LiveAccountUsageClient (mocked transport)

private struct StubSession: AccountSessionProviding {
    let header: String?
    let logged: Bool
    var isLoggedIn: Bool { get async { logged } }
    func cookieHeader(for host: String) async -> String? { header }
}

private struct StubEndpoint: AccountEndpointProviding {
    let info: AccountEndpointInfo?
    func usageEndpoint() async -> AccountEndpointInfo? { info }
}

private struct StubCaptured: AccountCapturedUsageProviding {
    let usage: AccountUsage?
    func recentCapturedUsage(maxAge: TimeInterval) async -> AccountUsage? { usage }
}

final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var responder: (@Sendable (URLRequest) -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let responder = MockURLProtocol.responder else {
            client?.urlProtocolDidFinishLoading(self); return
        }
        let (response, data) = responder(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Suite(.serialized) struct LiveAccountUsageClientTests {
    let info = AccountEndpointInfo(url: "https://claude.ai/api/usage")

    func mockedSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    @Test func returnsNilWhenLoggedOut() async throws {
        let client = LiveAccountUsageClient(
            session: StubSession(header: nil, logged: false),
            endpoint: StubEndpoint(info: info),
            urlSession: mockedSession())
        #expect(try await client.currentUsage() == nil)
    }

    @Test func returnsNilWhenEndpointUnknown() async throws {
        let client = LiveAccountUsageClient(
            session: StubSession(header: "a=1", logged: true),
            endpoint: StubEndpoint(info: nil),
            urlSession: mockedSession())
        #expect(try await client.currentUsage() == nil)
    }

    @Test func rejectsNonFirstPartyEndpoint() async throws {
        let client = LiveAccountUsageClient(
            session: StubSession(header: "a=1", logged: true),
            endpoint: StubEndpoint(info: AccountEndpointInfo(url: "https://evil.com/usage")),
            urlSession: mockedSession())
        #expect(try await client.currentUsage() == nil) // never sends cookies off-domain
    }

    @Test func decodesSuccessfulResponse() async throws {
        let url = info.resolvedURL!
        MockURLProtocol.responder = { _ in
            let body = #"{"five_hour":{"utilization":50,"resets_at":"2026-06-30T15:00:00Z"}}"#
            let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json"])!
            return (resp, Data(body.utf8))
        }
        defer { MockURLProtocol.responder = nil }
        let client = LiveAccountUsageClient(
            session: StubSession(header: "a=1", logged: true),
            endpoint: StubEndpoint(info: info),
            urlSession: mockedSession(),
            decode: { AccountUsageDecoder.decode($0, now: fixedNow) })
        let usage = try await client.currentUsage()
        #expect(usage?.session?.displayPercent == 50)
    }

    @Test func unauthorizedReturnsNilAndSignalsAuthFalse() async throws {
        let url = info.resolvedURL!
        MockURLProtocol.responder = { _ in
            (HTTPURLResponse(url: url, statusCode: 401, httpVersion: nil, headerFields: nil)!, Data())
        }
        defer { MockURLProtocol.responder = nil }
        let box = AuthBox()
        let client = LiveAccountUsageClient(
            session: StubSession(header: "a=1", logged: true),
            endpoint: StubEndpoint(info: info),
            captured: StubCaptured(usage: AccountUsage(session: UsageMetric(percent: 5), fetchedAt: Date())),
            urlSession: mockedSession(),
            onAuthResult: { box.set($0) })
        #expect(try await client.currentUsage() == nil) // 401 → nil, NOT the stale capture
        #expect(box.value == false)
    }

    @Test func forbidden403FallsBackToRecentCaptureAndKeepsSession() async throws {
        // A 403 is often a transient bot-challenge / rate-limit, not a dead session:
        // serve the recent capture and DON'T flap auth to logged-out.
        let url = info.resolvedURL!
        MockURLProtocol.responder = { _ in
            (HTTPURLResponse(url: url, statusCode: 403, httpVersion: nil, headerFields: nil)!, Data())
        }
        defer { MockURLProtocol.responder = nil }
        let box = AuthBox()
        let client = LiveAccountUsageClient(
            session: StubSession(header: "a=1", logged: true),
            endpoint: StubEndpoint(info: info),
            captured: StubCaptured(usage: AccountUsage(session: UsageMetric(percent: 7), fetchedAt: Date())),
            urlSession: mockedSession(),
            onAuthResult: { box.set($0) })
        let usage = try await client.currentUsage()
        #expect(usage?.session?.displayPercent == 7) // recent capture, not nil
        #expect(box.value == nil)                     // auth NOT signalled false
    }

    @Test func serverErrorFallsBackToRecentCapture() async throws {
        let url = info.resolvedURL!
        MockURLProtocol.responder = { _ in
            (HTTPURLResponse(url: url, statusCode: 500, httpVersion: nil, headerFields: nil)!, Data())
        }
        defer { MockURLProtocol.responder = nil }
        let captured = AccountUsage(session: UsageMetric(percent: 33), fetchedAt: Date())
        let client = LiveAccountUsageClient(
            session: StubSession(header: "a=1", logged: true),
            endpoint: StubEndpoint(info: info),
            captured: StubCaptured(usage: captured),
            urlSession: mockedSession())
        let usage = try await client.currentUsage()
        #expect(usage?.session?.displayPercent == 33) // resilient fallback on 5xx
    }
}

/// Thread-safe capture of the auth callback value.
final class AuthBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Bool?
    func set(_ v: Bool) { lock.lock(); stored = v; lock.unlock() }
    var value: Bool? { lock.lock(); defer { lock.unlock() }; return stored }
}
