import Testing
import Foundation
@testable import UsageMeterKit

@Suite struct DashboardMetricsTests {
    func makeStats() -> ClaudeCodeStats {
        var stats = ClaudeCodeStats()
        stats.byDay = [
            DailyUsage(day: "2026-06-30", usage: TokenUsage(outputTokens: 300), estimatedCost: 3.0),
            DailyUsage(day: "2026-06-28", usage: TokenUsage(outputTokens: 100), estimatedCost: 1.0),
            DailyUsage(day: "2026-06-29", usage: .zero, estimatedCost: nil),
            DailyUsage(day: "2026-06-10", usage: TokenUsage(outputTokens: 50), estimatedCost: 0.5),
        ]
        return stats
    }

    @Test func dailyPointsAreParsedAndSorted() {
        let points = DashboardMetrics.dailyPoints(from: makeStats(), calendar: utcCalendar())
        #expect(points.count == 4)
        #expect(points.first?.day == "2026-06-10") // sorted ascending
        #expect(points.last?.day == "2026-06-30")
        #expect(points.last?.tokens == 300)
    }

    @Test func filteredByRangeKeepsRecentDays() {
        let points = DashboardMetrics.dailyPoints(from: makeStats(), calendar: utcCalendar())
        let now = TestTime.date("2026-06-30T12:00:00Z")
        let last7 = DashboardMetrics.filtered(points, range: .days7, now: now, calendar: utcCalendar())
        #expect(last7.count == 3)                       // 06-10 dropped
        #expect(last7.contains { $0.day == "2026-06-10" } == false)
        let all = DashboardMetrics.filtered(points, range: .all, now: now, calendar: utcCalendar())
        #expect(all.count == 4)
    }

    @Test func insightsComputeAveragesPeakAndActiveDays() {
        let points = DashboardMetrics.dailyPoints(from: makeStats(), calendar: utcCalendar())
        let now = TestTime.date("2026-06-30T12:00:00Z")
        let last7 = DashboardMetrics.filtered(points, range: .days7, now: now, calendar: utcCalendar())
        let insights = DashboardMetrics.insights(last7)
        #expect(insights.totalTokens == 400)            // 100 + 0 + 300
        #expect(insights.activeDays == 2)               // the zero day excluded
        #expect(insights.averageDailyTokens == 200)     // 400 / 2 active days
        #expect(insights.peak?.day == "2026-06-30")
        #expect(insights.totalCost == 4.0)
    }

    @Test func insightsEmptyWhenNoUsage() {
        let insights = DashboardMetrics.insights([])
        #expect(insights.totalTokens == 0)
        #expect(insights.activeDays == 0)
        #expect(insights.peak == nil)
        #expect(insights.totalCost == nil)
    }
}
