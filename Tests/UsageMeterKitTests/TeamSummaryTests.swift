import Foundation
import Testing
@testable import UsageMeterKit

@Suite("TeamSummary")
struct TeamSummaryTests {
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    private var now: Date {
        DateComponents(calendar: calendar, timeZone: calendar.timeZone,
                       year: 2026, month: 7, day: 2, hour: 12).date!
    }

    private func stats() -> ClaudeCodeStats {
        var stats = ClaudeCodeStats()
        stats.total = TokenUsage(inputTokens: 1_000)
        stats.totalEstimatedCost = 123.45
        stats.sessionCount = 9
        stats.byModel = [ModelUsage(family: .opus, usage: TokenUsage(inputTokens: 900), estimatedCost: 100)]
        stats.byDay = [
            DailyUsage(day: "2026-07-01", usage: TokenUsage(inputTokens: 500), estimatedCost: 60),
            DailyUsage(day: "2026-03-01", usage: TokenUsage(inputTokens: 500), estimatedCost: 63.45), // outside 90d
        ]
        stats.byProject = [ProjectUsage(projectID: "-Users-yasir-secret-path",
                                        displayName: "secret", usage: TokenUsage(inputTokens: 1))]
        return stats
    }

    @Test func roundTripsThroughJSON() throws {
        let summary = TeamSummary.make(from: stats(), member: "Yasir", now: now, calendar: calendar)
        let decoded = try #require(TeamSummary.decode(summary.encode()))
        #expect(decoded == summary)
        #expect(decoded.member == "Yasir")
        #expect(decoded.totalTokens == 1_000)
        #expect(decoded.sessionCount == 9)
        #expect(decoded.byModel.first?.family == "opus")
    }

    @Test func byDayIsSlicedToWindow() {
        let summary = TeamSummary.make(from: stats(), member: "Y", now: now, calendar: calendar)
        #expect(summary.byDay.count == 1)                 // the March day dropped
        #expect(summary.byDay.first?.day == "2026-07-01")
        #expect(summary.days == 90)
    }

    @Test func encodedJSONNeverContainsProjects() throws {
        // Privacy lock: project slugs encode absolute paths + the macOS username.
        let data = TeamSummary.make(from: stats(), member: "Y", now: now, calendar: calendar).encode()
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(!text.lowercased().contains("project"))
        #expect(!text.contains("secret"))
    }

    @Test func rejectsWrongSchemaVersionAndGarbage() {
        #expect(TeamSummary.decode(Data("junk".utf8)) == nil)
        let wrongVersion = #"{"schemaVersion":99,"member":"x","generatedAt":"2026-07-02T12:00:00Z","days":90,"totalTokens":1,"sessionCount":1,"byModel":[],"byDay":[]}"#
        #expect(TeamSummary.decode(Data(wrongVersion.utf8)) == nil)
    }

    @Test func memberRowComputesDeltaAndLastActive() {
        // Previous 7 complete days (06-18…06-24): 100/day. Last 7 (06-25…07-01): 200/day.
        var byDay: [TeamSummary.Day] = []
        for d in 18...24 { byDay.append(.init(day: String(format: "2026-06-%02d", d), tokens: 100, cost: nil)) }
        for d in 25...30 { byDay.append(.init(day: String(format: "2026-06-%02d", d), tokens: 200, cost: nil)) }
        byDay.append(.init(day: "2026-07-01", tokens: 200, cost: nil))
        let summary = TeamSummary(
            member: "Ali", generatedAt: now, days: 90,
            totalTokens: 2_100, totalCost: nil, sessionCount: 3, byModel: [], byDay: byDay)
        let row = TeamMemberRow.make(from: summary, now: now, calendar: calendar)
        #expect(row.member == "Ali")
        #expect(row.windowTokens == 2_100)
        #expect(row.weekOverWeek != nil)
        #expect(abs(row.weekOverWeek! - 1.0) < 0.0001)     // doubled
        #expect(row.lastActiveDay == "2026-07-01")
    }
}
