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

    // MARK: - Moving average

    private func point(_ day: String, _ tokens: Int) -> DailyPoint {
        let formatter = DateFormatter()
        formatter.calendar = utcCalendar()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = utcCalendar().timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return DailyPoint(day: day, date: formatter.date(from: day)!, tokens: tokens, cost: nil)
    }

    @Test func movingAverageUsesTrailingWindowIncludingGaps() {
        // Days 1–10 with 100 tokens each but day 5 missing (gap = 0 in the window).
        var points = (1...10).filter { $0 != 5 }
            .map { point(String(format: "2026-06-%02d", $0), 100) }
        points = points.sorted { $0.date < $1.date }
        let ma = DashboardMetrics.movingAverage(points, window: 7, calendar: utcCalendar())
        #expect(ma.count == points.count)
        // At 06-10 the trailing 7 calendar days are 06-04…06-10 with one gap:
        // 6×100/7 ≈ 85.7.
        let last = ma.last!
        #expect(last.day == "2026-06-10")
        #expect(abs(last.value - 600.0 / 7.0) < 0.001)
        // At 06-01 the window is just that day → 100/7 (calendar window, not
        // "points so far") keeps early values honest rather than inflated.
        #expect(abs(ma.first!.value - 100.0 / 7.0) < 0.001)
    }

    @Test func movingAverageEmptyForNoPoints() {
        #expect(DashboardMetrics.movingAverage([], window: 7, calendar: utcCalendar()).isEmpty)
    }

    // MARK: - Weekday averages

    @Test func weekdayAveragesDivideByCalendarOccurrences() {
        // 4 weeks of Mondays (2026-06-01, 08, 15, 22 are Mondays) at 200 each;
        // everything else zero. Average over 4 weeks → Monday 200, others 0.
        let mondays = ["2026-06-01", "2026-06-08", "2026-06-15", "2026-06-22"]
        let points = mondays.map { point($0, 200) }
        let now = TestTime.date("2026-06-28T12:00:00Z") // Sunday
        let averages = DashboardMetrics.weekdayAverages(
            points, weeks: 4, now: now, calendar: utcCalendar())
        #expect(averages.count == 7)
        let monday = averages.first { $0.weekday == 2 }!  // Calendar weekday 2 = Monday
        #expect(monday.averageTokens == 200)
        #expect(averages.filter { $0.weekday != 2 }.allSatisfy { $0.averageTokens == 0 })
    }
}
