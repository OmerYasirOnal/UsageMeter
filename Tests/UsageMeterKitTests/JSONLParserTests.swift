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
}
