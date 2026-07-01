import Testing
import Foundation
@testable import UsageMeterKit

// MARK: - Parser edge cases ([5],[7],[18],[19],[20])

@Suite struct ParserEdgeCaseTests {
    let parser = JSONLParser()

    @Test func readsFlatCacheCreationAndIgnoresNestedObject() throws {
        // We read the flat `cache_creation_input_tokens`. A nested `cache_creation`
        // object (without the flat field) contributes 0 — documents intended behavior.
        let flat = #"{"type":"assistant","requestId":"f","timestamp":"2026-06-30T10:00:00.000Z","message":{"model":"claude-opus-4-8","usage":{"cache_creation_input_tokens":200,"output_tokens":5}}}"#
        let nested = #"{"type":"assistant","requestId":"n","timestamp":"2026-06-30T10:00:00.000Z","message":{"model":"claude-opus-4-8","usage":{"cache_creation":{"ephemeral_5m_input_tokens":999},"output_tokens":5}}}"#
        let r1 = try #require(parser.parse(data: Data(flat.utf8), projectID: "p").first)
        let r2 = try #require(parser.parse(data: Data(nested.utf8), projectID: "p").first)
        #expect(r1.usage.cacheCreationTokens == 200)
        #expect(r2.usage.cacheCreationTokens == 0)
    }

    @Test func intExtractionFloorsDoublesAndDefaultsNonNumeric() throws {
        let raw = #"{"type":"assistant","requestId":"x","timestamp":"2026-06-30T10:00:00.000Z","message":{"model":"claude-opus-4-8","usage":{"output_tokens":1.9,"input_tokens":"5"}}}"#
        let r = try #require(parser.parse(data: Data(raw.utf8), projectID: "p").first)
        #expect(r.usage.outputTokens == 1) // floored from 1.9
        #expect(r.usage.inputTokens == 0)  // string "5" is not numeric → 0
        #expect(r.usage.cacheReadTokens == 0) // missing → 0
    }

    @Test func parsesPlainISO8601WithoutFractionalSeconds() throws {
        let raw = #"{"type":"assistant","requestId":"p1","timestamp":"2026-06-30T10:00:00Z","message":{"model":"claude-opus-4-8","usage":{"output_tokens":1}}}"#
        let r = try #require(parser.parse(data: Data(raw.utf8), projectID: "p").first)
        #expect(r.timestamp == TestTime.date("2026-06-30T10:00:00.000Z"))
    }

    @Test func skipsRecordsWithMissingOrJunkTimestamp() {
        let missing = #"{"type":"assistant","requestId":"a","message":{"model":"claude-opus-4-8","usage":{"output_tokens":1}}}"#
        let junk = #"{"type":"assistant","requestId":"b","timestamp":"not-a-date","message":{"model":"claude-opus-4-8","usage":{"output_tokens":1}}}"#
        #expect(parser.parse(data: Data(missing.utf8), projectID: "p").isEmpty)
        #expect(parser.parse(data: Data(junk.utf8), projectID: "p").isEmpty)
    }

    @Test func skipsRecordsMissingTypeField() {
        // No `type` key at all → skipped (assistant-only allowlist).
        let noType = #"{"requestId":"a","timestamp":"2026-06-30T10:00:00.000Z","message":{"model":"claude-opus-4-8","usage":{"output_tokens":1}}}"#
        #expect(parser.parse(data: Data(noType.utf8), projectID: "p").isEmpty)
    }

    @Test func synthesizedIdIncludesProjectToAvoidCollision() throws {
        let raw = #"{"type":"assistant","timestamp":"2026-06-30T10:00:00.000Z","message":{"model":"claude-opus-4-8","usage":{"output_tokens":1}}}"#
        let a = try #require(parser.parse(data: Data(raw.utf8), projectID: "A", source: "f.jsonl").first)
        let b = try #require(parser.parse(data: Data(raw.utf8), projectID: "B", source: "f.jsonl").first)
        #expect(a.id != b.id)
        #expect(a.id.contains("A/"))
        #expect(b.id.contains("B/"))
    }
}

// MARK: - Aggregator session counts ([21])

@Suite struct AggregatorSessionCountTests {
    @Test func passesThroughSessionCounts() {
        let agg = DailyAggregator(calculator: CostCalculator(pricing: .defaults), calendar: utcCalendar())
        let records = [
            makeRecord(id: "1", at: "2026-06-30T10:00:00.000Z", project: "A", output: 10),
            makeRecord(id: "2", at: "2026-06-30T10:00:00.000Z", project: "B", output: 20)
        ]
        let stats = agg.aggregate(
            records: records,
            now: TestTime.date("2026-06-30T12:00:00.000Z"),
            sessionCountByProject: ["A": 2],
            totalSessions: 3
        )
        #expect(stats.sessionCount == 3)
        #expect(stats.byProject.first { $0.projectID == "A" }?.sessionCount == 2)
        #expect(stats.byProject.first { $0.projectID == "B" }?.sessionCount == 0)
    }
}

// MARK: - Block cost + boundary ([4],[27],[28])

@Suite struct BlockCostAndBoundaryTests {
    func builder() -> BlockBuilder { BlockBuilder(calculator: CostCalculator(pricing: .defaults)) }

    @Test func mixedModelBlockCostSumsPricedOnly() throws {
        let records = [
            makeRecord(id: "o", model: "claude-opus-4-8", at: "2026-06-30T10:00:00.000Z", output: 1_000_000),   // $25
            makeRecord(id: "s", model: "claude-sonnet-4-6", at: "2026-06-30T10:30:00.000Z", output: 1_000_000), // $15
            makeRecord(id: "x", model: "<synthetic>", at: "2026-06-30T11:00:00.000Z", output: 1_000_000)        // n/a
        ]
        let blocks = builder().buildBlocks(from: records, now: TestTime.date("2026-06-30T12:00:00.000Z"))
        #expect(blocks.count == 1)
        let cost = try #require(blocks[0].estimatedCost)
        #expect(abs(cost - 40.0) < 1e-9)
        #expect(blocks[0].totalTokens == 3_000_000)
    }

    @Test func unknownOnlyBlockHasNilCost() {
        let records = [makeRecord(id: "x", model: "<synthetic>", at: "2026-06-30T10:00:00.000Z", output: 100)]
        let blocks = builder().buildBlocks(from: records, now: TestTime.date("2026-06-30T11:00:00.000Z"))
        #expect(blocks.count == 1)
        #expect(blocks[0].estimatedCost == nil)
    }

    @Test func recordExactlyFiveHoursAfterStartOpensNewBlock() {
        let records = [
            makeRecord(id: "1", at: "2026-06-30T10:00:00.000Z", output: 10),
            makeRecord(id: "2", at: "2026-06-30T15:00:00.000Z", output: 10) // exactly start+5h
        ]
        let blocks = builder().buildBlocks(from: records, now: TestTime.date("2026-06-30T20:00:00.000Z"))
        #expect(blocks.count == 2)
        #expect(blocks[1].start == TestTime.date("2026-06-30T15:00:00.000Z"))
    }

    @Test func inactiveBlockHasNilBurnRateAndProjection() {
        let block = UsageBlock(
            start: TestTime.date("2026-06-30T10:00:00.000Z"),
            end: TestTime.date("2026-06-30T15:00:00.000Z"),
            usage: TokenUsage(outputTokens: 100),
            isActive: false
        )
        let now = TestTime.date("2026-06-30T12:00:00.000Z")
        #expect(block.burnRate(now: now) == nil)
        #expect(block.projectedTokens(now: now) == nil)
    }

    @Test func zeroElapsedActiveBlockHasNilBurnRate() {
        let start = TestTime.date("2026-06-30T10:00:00.000Z")
        let block = UsageBlock(start: start, end: start.addingTimeInterval(5 * 3600),
                               usage: TokenUsage(outputTokens: 100), isActive: true)
        #expect(block.burnRate(now: start) == nil) // elapsed == 0 → no divide-by-zero
    }
}

// MARK: - Status decoding extras ([23],[24],[25])

@Suite struct StatusDecodingExtraTests {
    @Test func operationalWithIncidentsStillHasActiveIssues() throws {
        let json = #"{"status":{"indicator":"none","description":"All Systems Operational"},"incidents":[{"id":"i","name":"Resolved-but-listed"}]}"#
        let status = try StatusDecoder.decodeSummary(Data(json.utf8))
        #expect(status.indicator == .none)
        #expect(status.hasActiveIssues) // second disjunct of hasActiveIssues
    }

    @Test func incidentOptionalFieldsDefaultCleanly() throws {
        let json = #"{"status":{"indicator":"minor","description":"x"},"incidents":[{"id":"i","name":"only id+name"}]}"#
        let status = try StatusDecoder.decodeSummary(Data(json.utf8))
        let inc = try #require(status.incidents.first)
        #expect(inc.status == "")
        #expect(inc.impact == nil)
        #expect(inc.shortlink == nil)
    }

    @Test func degradedFixtureMaintenanceFields() throws {
        let status = try StatusDecoder.decodeSummary(Fixture.data("status_degraded", "json"))
        let m = try #require(status.scheduledMaintenances.first)
        #expect(m.impact == "maintenance")
        #expect(m.shortlink == nil)
    }

    @Test func decodesMinorCriticalMaintenanceIndicators() throws {
        for (raw, expected): (String, StatusIndicator) in [
            ("minor", .minor), ("critical", .critical), ("maintenance", .maintenance)
        ] {
            let json = "{\"status\":{\"indicator\":\"\(raw)\",\"description\":\"x\"}}"
            let status = try StatusDecoder.decodeSummary(Data(json.utf8))
            #expect(status.indicator == expected)
        }
    }

    @Test func fetchedAtPropagates() throws {
        let when = TestTime.date("2026-06-30T12:00:00.000Z")
        let status = try StatusDecoder.decodeSummary(Fixture.data("status_operational", "json"), fetchedAt: when)
        #expect(status.fetchedAt == when)
    }
}

// MARK: - Scanner edge cases ([22],[26])

@Suite struct ScannerEdgeCaseTests {
    let fm = FileManager.default

    func tempRoot() throws -> URL {
        let root = fm.temporaryDirectory.appendingPathComponent("um-scan2-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        return root.resolvingSymlinksInPath()
    }

    func write(_ text: String, to url: URL) throws {
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    @Test func emptyRootsYieldEmpty() {
        #expect(ProjectScanner().scan(roots: []).isEmpty)
    }

    @Test func fileAsRootIsIgnored() throws {
        let root = try tempRoot()
        defer { try? fm.removeItem(at: root) }
        let asFile = root.appendingPathComponent("imafile")
        try write("x", to: asFile)
        #expect(ProjectScanner().scan(roots: [asFile]).isEmpty)
    }

    @Test func strayFileUnderRootIsIgnoredAndUppercaseExtensionFound() throws {
        let root = try tempRoot()
        defer { try? fm.removeItem(at: root) }
        try write("stray", to: root.appendingPathComponent("loose.txt")) // not a project dir
        try write("{}", to: root.appendingPathComponent("projA/SESSION.JSONL")) // uppercase ext
        let files = ProjectScanner().scan(roots: [root])
        #expect(files.count == 1)
        #expect(files.first?.url.lastPathComponent == "SESSION.JSONL")
    }

    @Test func mtimeOnlyChangeIsDetected() throws {
        let root = try tempRoot()
        defer { try? fm.removeItem(at: root) }
        let f = root.appendingPathComponent("projA/s.jsonl")
        try write("{}", to: f)
        let scanner = ProjectScanner()
        let first = scanner.scan(roots: [root])
        let snapshot = Dictionary(uniqueKeysWithValues: first.map {
            ($0.path, FileStamp(modifiedAt: $0.modifiedAt, size: $0.size))
        })
        // Bump mtime forward without changing the bytes/size.
        let newer = TestTime.date("2030-01-01T00:00:00.000Z")
        try fm.setAttributes([.modificationDate: newer], ofItemAtPath: f.path)
        let diff = scanner.diff(roots: [root], against: snapshot)
        #expect(diff.changed.contains { $0.url.lastPathComponent == "s.jsonl" })
        #expect(diff.unchanged.isEmpty)
    }
}

// MARK: - DataEngine orchestration (end-to-end incremental)

@Suite struct DataEngineIntegrationTests {
    let fm = FileManager.default

    @Test func refreshAllScansLogsAndMergesStatus() async throws {
        let root = fm.temporaryDirectory.appendingPathComponent("um-eng-\(UUID().uuidString)", isDirectory: true)
        let storeDir = fm.temporaryDirectory.appendingPathComponent("um-eng-store-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: root); try? fm.removeItem(at: storeDir) }

        let session = root.appendingPathComponent("projA/s1.jsonl")
        try fm.createDirectory(at: session.deletingLastPathComponent(), withIntermediateDirectories: true)
        let line = #"{"type":"assistant","requestId":"r1","timestamp":"2026-06-30T10:00:00.000Z","message":{"model":"claude-opus-4-8","usage":{"output_tokens":100}}}"#
        try Data((line + "\n").utf8).write(to: session)

        let engine = DataEngine(
            configuration: EngineConfiguration(projectRoots: [root], refreshInterval: 60),
            recordStore: UsageStore(directory: storeDir),
            statusStore: StatusStore(directory: storeDir),
            statusClient: StubStatusClient(ServiceStatus(indicator: .none, description: "All Systems Operational")),
            accountClient: LocalOnlyAccountUsageClient(),
            pricing: .defaults,
            calendar: utcCalendar()
        )

        let snap = await engine.refreshAll()
        #expect(snap.claudeCode.recordCount == 1)
        #expect(snap.claudeCode.total.outputTokens == 100)
        #expect(snap.status?.indicator == StatusIndicator.none)
        #expect(snap.account == nil) // local-only mode
        #expect(snap.lastUpdated != nil)

        // Add a second session file; incremental refresh should pick it up.
        let session2 = root.appendingPathComponent("projB/s2.jsonl")
        try fm.createDirectory(at: session2.deletingLastPathComponent(), withIntermediateDirectories: true)
        let line2 = #"{"type":"assistant","requestId":"r2","timestamp":"2026-06-30T11:00:00.000Z","message":{"model":"claude-sonnet-4-6","usage":{"output_tokens":50}}}"#
        try Data((line2 + "\n").utf8).write(to: session2)

        let stats2 = await engine.refreshClaudeCode()
        #expect(stats2.recordCount == 2)
        #expect(stats2.sessionCount == 2)
    }

    @Test func statusFailureFallsBackToLastGood() async throws {
        let storeDir = fm.temporaryDirectory.appendingPathComponent("um-eng-store2-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: storeDir) }
        // Seed a last-good status on disk.
        StatusStore(directory: storeDir).save(ServiceStatus(indicator: .none, description: "All Systems Operational"))

        let engine = DataEngine(
            configuration: EngineConfiguration(projectRoots: [], refreshInterval: 60),
            recordStore: UsageStore(directory: storeDir),
            statusStore: StatusStore(directory: storeDir),
            statusClient: StubStatusClient(error: StatusClientError.badStatus(503)),
            accountClient: LocalOnlyAccountUsageClient(),
            pricing: .defaults,
            calendar: utcCalendar()
        )
        let status = await engine.refreshStatus()
        #expect(status?.indicator == StatusIndicator.none) // fell back to seeded last-good
    }

    @Test func accountFetchIsFloorGuardedWithin60s() async throws {
        let storeDir = fm.temporaryDirectory.appendingPathComponent("um-eng-floor-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: storeDir) }
        let client = CountingAccountClient(usage: AccountUsage(session: UsageMetric(percent: 42)))
        let engine = DataEngine(
            configuration: EngineConfiguration(projectRoots: [], refreshInterval: 60),
            recordStore: UsageStore(directory: storeDir),
            statusStore: StatusStore(directory: storeDir),
            statusClient: StubStatusClient(ServiceStatus(indicator: .none, description: "ok")),
            accountClient: client,
            pricing: .defaults,
            calendar: utcCalendar()
        )
        let a = await engine.refreshAccount()
        let b = await engine.refreshAccount()   // within 60s → cached, no 2nd endpoint hit
        #expect(a?.session?.displayPercent == 42)
        #expect(b?.session?.displayPercent == 42)
        #expect(a?.fetchedAt != nil)             // stamped with the real fetch time
        #expect(client.calls == 1)               // politeness floor held

        await engine.clearAccountCache()
        _ = await engine.refreshAccount()        // cache cleared → fetches again
        #expect(client.calls == 2)
    }
}

/// Test double: returns a fixed usage and counts how many times the endpoint was hit.
final class CountingAccountClient: AccountUsageClient, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls = 0
    var calls: Int { lock.withLock { _calls } }
    private let usage: AccountUsage
    init(usage: AccountUsage) { self.usage = usage }
    var isAuthenticated: Bool { get async { true } }
    func currentUsage() async throws -> AccountUsage? {
        lock.withLock { _calls += 1 }
        return usage
    }
}

@Suite struct LocalClaudeCodeSourceRobustnessTests {
    let fm = FileManager.default

    private func makeRootAndStore() throws -> (root: URL, storeDir: URL) {
        let root = fm.temporaryDirectory
            .appendingPathComponent("um-src-\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()
        let storeDir = fm.temporaryDirectory
            .appendingPathComponent("um-src-store-\(UUID().uuidString)", isDirectory: true)
        let session = root.appendingPathComponent("projA/s1.jsonl")
        try fm.createDirectory(at: session.deletingLastPathComponent(), withIntermediateDirectories: true)
        let line = #"{"type":"assistant","requestId":"r1","timestamp":"2026-06-30T10:00:00.000Z","message":{"model":"claude-opus-4-8","usage":{"output_tokens":100}}}"#
        try Data((line + "\n").utf8).write(to: session)
        return (root, storeDir)
    }

    @Test func noOpRefreshDoesNotRewriteTheCacheFile() throws {
        let (root, storeDir) = try makeRootAndStore()
        defer { try? fm.removeItem(at: root); try? fm.removeItem(at: storeDir) }
        let store = UsageStore(directory: storeDir)
        let source = LocalClaudeCodeSource(store: store, pricing: .defaults)

        _ = source.refresh(roots: [root], now: Date(timeIntervalSince1970: 1_800_000_000))
        let firstWrite = try Data(contentsOf: store.fileURL)

        // Nothing on disk changed → the cache file must not be rewritten
        // (a rewrite would at minimum change the persisted lastUpdated).
        _ = source.refresh(roots: [root], now: Date(timeIntervalSince1970: 1_800_000_060))
        let secondWrite = try Data(contentsOf: store.fileURL)
        #expect(firstWrite == secondWrite)
    }

    @Test func emptyScanWithNonEmptyCacheDoesNotWipeStats() throws {
        let (root, storeDir) = try makeRootAndStore()
        defer { try? fm.removeItem(at: root); try? fm.removeItem(at: storeDir) }
        let store = UsageStore(directory: storeDir)
        let source = LocalClaudeCodeSource(store: store, pricing: .defaults)

        let seeded = source.refresh(roots: [root], now: Date(timeIntervalSince1970: 1_800_000_000))
        #expect(seeded.recordCount == 1)

        // Root temporarily unavailable (sandbox bookmark failure, unmounted
        // volume): the scan finds nothing. Stats and the persisted cache must
        // survive rather than being wiped to zero.
        let missing = fm.temporaryDirectory.appendingPathComponent("um-gone-\(UUID().uuidString)")
        let afterOutage = source.refresh(roots: [missing], now: Date(timeIntervalSince1970: 1_800_000_060))
        #expect(afterOutage.recordCount == 1)
        #expect(afterOutage.total.outputTokens == 100)

        let reloaded = UsageStore(directory: storeDir).load()
        #expect(!reloaded.files.isEmpty)
    }

    @Test func genuineRemovalStillDropsRecords() throws {
        // The wipe guard must not break normal removal semantics: when the scan
        // still sees the root but one file is gone, its records are dropped.
        let (root, storeDir) = try makeRootAndStore()
        defer { try? fm.removeItem(at: root); try? fm.removeItem(at: storeDir) }
        let extra = root.appendingPathComponent("projB/s2.jsonl")
        try fm.createDirectory(at: extra.deletingLastPathComponent(), withIntermediateDirectories: true)
        let line = #"{"type":"assistant","requestId":"r2","timestamp":"2026-06-30T11:00:00.000Z","message":{"model":"claude-opus-4-8","usage":{"output_tokens":50}}}"#
        try Data((line + "\n").utf8).write(to: extra)

        let store = UsageStore(directory: storeDir)
        let source = LocalClaudeCodeSource(store: store, pricing: .defaults)
        let seeded = source.refresh(roots: [root], now: Date(timeIntervalSince1970: 1_800_000_000))
        #expect(seeded.recordCount == 2)

        try fm.removeItem(at: extra)
        let afterRemove = source.refresh(roots: [root], now: Date(timeIntervalSince1970: 1_800_000_060))
        #expect(afterRemove.recordCount == 1)
    }
}
