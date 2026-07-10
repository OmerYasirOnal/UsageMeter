import Testing
import Foundation
@testable import UsageMeterKit

@Suite struct DailyAggregatorTests {
    func makeAggregator() -> DailyAggregator {
        DailyAggregator(calculator: CostCalculator(pricing: .defaults), calendar: utcCalendar())
    }

    @Test func deduplicatesByIdKeepingFirst() {
        let records = [
            makeRecord(id: "req_1", at: "2026-06-30T10:00:00.000Z", input: 100, output: 50),
            makeRecord(id: "req_1", at: "2026-06-30T10:00:01.000Z", input: 999, output: 999),
            makeRecord(id: "req_2", model: "claude-sonnet-4-6", at: "2026-06-30T11:00:00.000Z", output: 20)
        ]
        let stats = makeAggregator().aggregate(records: records, now: TestTime.date("2026-06-30T15:00:00.000Z"))
        #expect(stats.recordCount == 2)
        // The duplicate's 999s must not leak into totals.
        #expect(stats.total == TokenUsage(inputTokens: 100, cacheCreationTokens: 0,
                                          cacheReadTokens: 0, outputTokens: 70))
    }

    @Test func aggregatesRealFixtureCorrectly() {
        let parser = JSONLParser()
        let records = parser.parse(data: Fixture.data("session_basic", "jsonl"), projectID: "proj")
        let stats = makeAggregator().aggregate(records: records, now: TestTime.date("2026-06-30T15:00:00.000Z"))

        #expect(stats.recordCount == 4) // dedup removed the duplicate req_1
        // 1350 (opus) + 30 (sonnet) + 2000 (haiku) + 5 (synthetic) = 3385
        #expect(stats.total.totalTokens == 3385)
        // Opus reflects only the first req_1, not the 999-token duplicate.
        let opus = stats.byModel.first { $0.family == .opus }
        #expect(opus?.usage.totalTokens == 1350)
    }

    @Test func todayBucketUsesAggregatorCalendar() {
        let records = [
            makeRecord(id: "today", at: "2026-06-30T23:30:00.000Z", output: 100),
            makeRecord(id: "yesterday", at: "2026-06-29T23:30:00.000Z", output: 5)
        ]
        let stats = makeAggregator().aggregate(records: records, now: TestTime.date("2026-06-30T12:00:00.000Z"))
        #expect(stats.today.totalTokens == 100)
        #expect(stats.byDay.count == 2)
    }

    @Test func groupsByModelProjectAndDay() {
        let records = [
            makeRecord(id: "1", model: "opus", at: "2026-06-30T10:00:00.000Z", project: "A", output: 10),
            makeRecord(id: "2", model: "sonnet", at: "2026-06-30T10:00:00.000Z", project: "B", output: 20),
            makeRecord(id: "3", model: "opus", at: "2026-06-29T10:00:00.000Z", project: "A", output: 30)
        ]
        let stats = makeAggregator().aggregate(records: records, now: TestTime.date("2026-06-30T12:00:00.000Z"))
        #expect(stats.byModel.count == 2)
        #expect(stats.byProject.count == 2)
        #expect(stats.byDay.count == 2)
        let projA = stats.byProject.first { $0.projectID == "A" }
        #expect(projA?.usage.totalTokens == 40)
    }

    @Test func groupsByProjectAndModel() {
        let records = [
            makeRecord(id: "1", model: "opus", at: "2026-06-30T10:00:00.000Z", project: "A", output: 10),
            makeRecord(id: "2", model: "sonnet", at: "2026-06-30T10:00:00.000Z", project: "A", output: 20),
            makeRecord(id: "3", model: "opus", at: "2026-06-29T10:00:00.000Z", project: "B", output: 30)
        ]
        let stats = makeAggregator().aggregate(records: records, now: TestTime.date("2026-06-30T12:00:00.000Z"))
        #expect(stats.byProjectModel.count == 3)
        let aOpus = stats.byProjectModel.first { $0.projectID == "A" && $0.family == .opus }
        #expect(aOpus?.usage.totalTokens == 10)
        let aSonnet = stats.byProjectModel.first { $0.projectID == "A" && $0.family == .sonnet }
        #expect(aSonnet?.usage.totalTokens == 20)
        let bOpus = stats.byProjectModel.first { $0.projectID == "B" && $0.family == .opus }
        #expect(bOpus?.usage.totalTokens == 30)
    }

    @Test func emptyRecordsProduceEmptyStats() {
        let stats = makeAggregator().aggregate(records: [], now: Date())
        #expect(stats.recordCount == 0)
        #expect(stats.total == .zero)
        #expect(stats.activeBlock == nil)
    }
}
