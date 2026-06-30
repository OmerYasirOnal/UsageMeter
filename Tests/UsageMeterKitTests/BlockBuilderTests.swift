import Testing
import Foundation
@testable import UsageMeterKit

@Suite struct BlockBuilderTests {
    func builder() -> BlockBuilder {
        BlockBuilder(calculator: CostCalculator(pricing: .defaults))
    }

    @Test func floorsBlockStartToTheHourInUTC() {
        let b = builder()
        let floored = b.floorToHourUTC(TestTime.date("2026-06-30T10:37:21.500Z"))
        #expect(floored == TestTime.date("2026-06-30T10:00:00.000Z"))
    }

    @Test func groupsRecordsWithinFiveHoursIntoOneBlock() {
        let records = [
            makeRecord(id: "1", at: "2026-06-30T10:05:00.000Z", output: 10),
            makeRecord(id: "2", at: "2026-06-30T11:00:00.000Z", output: 20),
            makeRecord(id: "3", at: "2026-06-30T14:30:00.000Z", output: 30)
        ]
        let blocks = builder().buildBlocks(from: records, now: TestTime.date("2026-06-30T20:00:00.000Z"))
        #expect(blocks.count == 1)
        #expect(blocks[0].start == TestTime.date("2026-06-30T10:00:00.000Z"))
        #expect(blocks[0].end == TestTime.date("2026-06-30T15:00:00.000Z"))
        #expect(blocks[0].totalTokens == 60)
    }

    @Test func startsNewBlockWhenSpanExceedsFiveHours() {
        let records = [
            makeRecord(id: "1", at: "2026-06-30T10:05:00.000Z", output: 10),
            // 16:00 is >= 10:00 + 5h, so a new block opens at floor(16:00).
            makeRecord(id: "2", at: "2026-06-30T16:00:00.000Z", output: 20)
        ]
        let blocks = builder().buildBlocks(from: records, now: TestTime.date("2026-06-30T20:00:00.000Z"))
        #expect(blocks.count == 2)
        #expect(blocks[1].start == TestTime.date("2026-06-30T16:00:00.000Z"))
    }

    @Test func startsNewBlockAfterFiveHourGap() {
        let records = [
            makeRecord(id: "1", at: "2026-06-30T10:00:00.000Z", output: 10),
            makeRecord(id: "2", at: "2026-06-30T11:00:00.000Z", output: 10),
            // gap from 11:00 to 16:30 is 5.5h >= 5h → new block.
            makeRecord(id: "3", at: "2026-06-30T16:30:00.000Z", output: 10)
        ]
        let blocks = builder().buildBlocks(from: records, now: TestTime.date("2026-06-30T20:00:00.000Z"))
        #expect(blocks.count == 2)
    }

    @Test func marksActiveBlockAndComputesBurnRate() {
        let now = TestTime.date("2026-06-30T12:00:00.000Z")
        let records = [
            makeRecord(id: "1", at: "2026-06-30T11:00:00.000Z", output: 600),
            makeRecord(id: "2", at: "2026-06-30T11:30:00.000Z", output: 600)
        ]
        let active = builder().activeBlock(from: records, now: now)
        #expect(active != nil)
        #expect(active?.isActive == true)
        // block start floor(11:00) = 11:00, now = 12:00 → 60 min elapsed, 1200 tokens → 20 tok/min
        #expect(abs((active?.burnRate(now: now) ?? 0) - 20.0) < 1e-6)
        // projection over the full 5h (300 min) at 20/min = 6000
        #expect(active?.projectedTokens(now: now) == 6000)
    }

    @Test func noActiveBlockWhenUsageIsStale() {
        let now = TestTime.date("2026-06-30T23:00:00.000Z")
        let records = [makeRecord(id: "1", at: "2026-06-30T10:00:00.000Z", output: 10)]
        #expect(builder().activeBlock(from: records, now: now) == nil)
    }
}
