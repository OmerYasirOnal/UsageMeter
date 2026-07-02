import Testing
import Foundation
@testable import UsageMeterKit

@Suite struct JSONLParserTests {
    let parser = JSONLParser()

    @Test func parsesOnlyAssistantUsageRecords() {
        let data = Fixture.data("session_basic", "jsonl")
        let records = parser.parse(data: data, projectID: "proj", source: "session_basic.jsonl")

        // req_1, req_2, req_1(dup), u_3, req_syn — user/malformed/sidechain/blank excluded.
        #expect(records.count == 5)
    }

    @Test func skipsSidechainRecords() {
        let data = Fixture.data("session_basic", "jsonl")
        let records = parser.parse(data: data, projectID: "proj")
        #expect(records.contains { $0.id == "req_side" } == false)
    }

    @Test func neverReadsNonUsageRecords() {
        let data = Fixture.data("session_basic", "jsonl")
        let records = parser.parse(data: data, projectID: "proj")
        // The user line has no usage and must be dropped entirely.
        #expect(records.allSatisfy { $0.id != "u_user" })
    }

    @Test func usesRequestIdThenUuid() {
        let data = Fixture.data("session_basic", "jsonl")
        let records = parser.parse(data: data, projectID: "proj")
        // requestId-bearing record keyed by requestId...
        #expect(records.contains { $0.id == "req_1" })
        // ...uuid-only record falls back to uuid.
        #expect(records.contains { $0.id == "u_3" })
    }

    @Test func extractsTokenCountsExactly() throws {
        let data = Fixture.data("session_basic", "jsonl")
        let records = parser.parse(data: data, projectID: "proj")
        let first = try #require(records.first { $0.id == "req_1" })
        #expect(first.usage == TokenUsage(inputTokens: 100, cacheCreationTokens: 200,
                                          cacheReadTokens: 1000, outputTokens: 50))
        #expect(first.family == .opus)
    }

    @Test func toleratesMalformedAndPartialLines() {
        // A trailing partial line (active session) and outright garbage must not crash.
        let raw = """
        {"type":"assistant","requestId":"a","timestamp":"2026-06-30T10:00:00.000Z","message":{"model":"claude-opus-4-8","usage":{"output_tokens":5}}}
        garbage line {{{
        {"type":"assistant","requestId":"b","timestamp":"2026-06-30T10:01:00.000Z","message":{"model":"claude-sonnet-4-6","usage":{"output_tokens":7}
        """
        let records = parser.parse(data: Data(raw.utf8), projectID: "proj")
        #expect(records.count == 1)
        #expect(records.first?.id == "a")
    }

    @Test func emptyDataYieldsNothing() {
        #expect(parser.parse(data: Data(), projectID: "proj").isEmpty)
    }

    @Test func parsesFromFileURL() {
        let url = Fixture.url("session_basic", "jsonl")
        let records = parser.parse(fileAt: url, projectID: "proj")
        #expect(records.count == 5)
    }

    @Test func syntheticModelMapsToUnknown() throws {
        let data = Fixture.data("session_basic", "jsonl")
        let records = parser.parse(data: data, projectID: "proj")
        let syn = try #require(records.first { $0.id == "req_syn" })
        #expect(syn.family == .unknown)
    }

    @Test func readsCacheCreationTTLSplit() {
        let line = #"{"type":"assistant","requestId":"r1","timestamp":"2026-07-01T10:00:00.000Z","message":{"model":"claude-fable-5","usage":{"input_tokens":10,"cache_creation_input_tokens":1000,"cache_creation":{"ephemeral_5m_input_tokens":100,"ephemeral_1h_input_tokens":900},"cache_read_input_tokens":5,"output_tokens":7}}}"#
        let records = parser.parse(data: Data(line.utf8), projectID: "p")
        #expect(records.count == 1)
        #expect(records.first?.usage.cacheCreationTokens == 1000)
        #expect(records.first?.usage.cacheCreation1hTokens == 900)
    }

    @Test func splitWithoutLegacyAggregateStillCountsCacheWrites() {
        // If Claude Code ever drops the legacy aggregate, the split must carry.
        let line = #"{"type":"assistant","requestId":"r2","timestamp":"2026-07-01T10:00:00.000Z","message":{"model":"claude-fable-5","usage":{"cache_creation":{"ephemeral_5m_input_tokens":100,"ephemeral_1h_input_tokens":900},"output_tokens":1}}}"#
        let records = parser.parse(data: Data(line.utf8), projectID: "p")
        #expect(records.first?.usage.cacheCreationTokens == 1000)
        #expect(records.first?.usage.cacheCreation1hTokens == 900)
    }

    @Test func legacyOnlyCacheWriteHasZeroOneHourPortion() {
        let line = #"{"type":"assistant","requestId":"r3","timestamp":"2026-07-01T10:00:00.000Z","message":{"model":"claude-opus-4-8","usage":{"cache_creation_input_tokens":500,"output_tokens":1}}}"#
        let records = parser.parse(data: Data(line.utf8), projectID: "p")
        #expect(records.first?.usage.cacheCreationTokens == 500)
        #expect(records.first?.usage.cacheCreation1hTokens == 0)
    }

    // MARK: - Incremental (append-offset) parsing

    private func line(_ id: Int) -> String {
        #"{"type":"assistant","requestId":"inc-\#(id)","timestamp":"2026-07-01T10:00:0\#(id % 10).000Z","message":{"model":"claude-opus-4-8","usage":{"output_tokens":1}}}"#
    }

    @Test func incrementalParseConsumesOnlyCompleteLines() throws {
        let fm = FileManager.default
        let url = fm.temporaryDirectory.appendingPathComponent("inc-\(UUID().uuidString).jsonl")
        defer { try? fm.removeItem(at: url) }
        let complete = line(1) + "\n" + line(2) + "\n"
        let partial = #"{"type":"assistant","requestId":"inc-3","time"#   // torn mid-write
        try Data((complete + partial).utf8).write(to: url)

        let result = parser.parseIncremental(fileAt: url, projectID: "p")
        #expect(result.records.count == 2)                        // partial line skipped
        #expect(result.parsedBytes == Data(complete.utf8).count)  // …and NOT consumed
        #expect(result.parsedLines == 2)
    }

    @Test func incrementalResumeMatchesOneShotParse() throws {
        let fm = FileManager.default
        let url = fm.temporaryDirectory.appendingPathComponent("inc-\(UUID().uuidString).jsonl")
        defer { try? fm.removeItem(at: url) }
        // Include a record WITHOUT requestId/uuid so synthetic-id continuity is exercised.
        let noID = #"{"type":"assistant","timestamp":"2026-07-01T10:00:05.000Z","message":{"model":"claude-opus-4-8","usage":{"output_tokens":9}}}"#
        try Data((line(1) + "\n" + line(2) + "\n").utf8).write(to: url)

        let first = parser.parseIncremental(fileAt: url, projectID: "p")
        try Data((line(1) + "\n" + line(2) + "\n" + noID + "\n" + line(4) + "\n").utf8).write(to: url)
        let second = parser.parseIncremental(fileAt: url, projectID: "p",
                                             fromByteOffset: first.parsedBytes,
                                             lineIndexBase: first.parsedLines)

        let oneShot = parser.parseIncremental(fileAt: url, projectID: "p")
        #expect((first.records + second.records).map(\.id) == oneShot.records.map(\.id))
        #expect(second.parsedBytes == oneShot.parsedBytes)
        #expect(second.parsedLines == oneShot.parsedLines)
    }

    @Test func incrementalParseOfMissingFileIsEmptyAndKeepsOffsets() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("gone-\(UUID().uuidString).jsonl")
        let result = parser.parseIncremental(fileAt: url, projectID: "p", fromByteOffset: 42, lineIndexBase: 7)
        #expect(result.records.isEmpty)
        #expect(result.parsedBytes == 42)
        #expect(result.parsedLines == 7)
    }
}
