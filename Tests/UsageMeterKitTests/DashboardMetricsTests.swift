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

    // MARK: - Per-day per-model (range-scoped "By model")

    @Test func aggregatorEmitsDailyByModel() {
        let calendar = utcCalendar()
        let aggregator = DailyAggregator(
            calculator: CostCalculator(pricing: Pricing.loadBundled()), calendar: calendar)
        let t1 = TestTime.date("2026-06-29T10:00:00Z")
        let t2 = TestTime.date("2026-06-30T10:00:00Z")
        let records = [
            UsageRecord(id: "a", model: "claude-opus-4-8", timestamp: t1,
                        usage: TokenUsage(outputTokens: 100), projectID: "p"),
            UsageRecord(id: "b", model: "claude-sonnet-5", timestamp: t2,
                        usage: TokenUsage(outputTokens: 50), projectID: "p"),
            UsageRecord(id: "c", model: "claude-opus-4-8", timestamp: t2,
                        usage: TokenUsage(outputTokens: 25), projectID: "p"),
        ]
        let stats = aggregator.aggregate(records: records, now: t2)
        let daily = stats.dailyByModel
        #expect(daily.count == 3) // (29,opus) (30,sonnet) (30,opus)
        let opus30 = daily.first { $0.day == "2026-06-30" && $0.family == .opus }
        #expect(opus30?.usage.totalTokens == 25)
        #expect(opus30?.estimatedCost != nil)
        // Range filter+sum helper: only 06-30 within a 1-day range.
        let ranged = DashboardMetrics.modelUsage(
            daily, range: .days7, now: TestTime.date("2026-07-06T12:00:00Z"), calendar: calendar)
        #expect(ranged.count == 2)                    // 06-29 opus dropped
        #expect(ranged.first?.family == .sonnet)      // 50 > 25, sorted by tokens
        #expect(ranged.first?.usage.totalTokens == 50)
    }

    // MARK: - Anomaly detection

    @Test func flagsDaysAboveMeanPlusTwoSigma() {
        // 9 quiet days at 100 + 1 spike at 1000. Active mean/σ make the spike
        // an outlier; the quiet days are not.
        var points = (1...9).map { point(String(format: "2026-06-%02d", $0), 100) }
        points.append(point("2026-06-10", 1000))
        let spikes = DashboardMetrics.anomalousDays(points)
        #expect(spikes.count == 1)
        #expect(spikes.first?.day == "2026-06-10")
    }

    @Test func noAnomaliesWhenUsageIsEven() {
        let points = (1...10).map { point(String(format: "2026-06-%02d", $0), 100) }
        #expect(DashboardMetrics.anomalousDays(points).isEmpty)
    }

    @Test func anomalyNeedsEnoughActiveDays() {
        // Too few active days → no statistics, no false spikes.
        let points = [point("2026-06-01", 100), point("2026-06-02", 5000)]
        #expect(DashboardMetrics.anomalousDays(points).isEmpty)
    }

    @Test func anomalyIgnoresZeroDays() {
        // Zero days must not drag the mean down and manufacture outliers.
        var points = (1...8).map { point(String(format: "2026-06-%02d", $0), 100) }
        points += [point("2026-06-09", 0), point("2026-06-10", 0)]
        points.append(point("2026-06-11", 260)) // 100 mean, small σ → 260 is >2σ
        let spikes = DashboardMetrics.anomalousDays(points)
        #expect(spikes.map(\.day) == ["2026-06-11"])
    }

    // MARK: - Week over week

    @Test func weekOverWeekComparesCompleteWindows() {
        // Previous 7 complete days (06-14…06-20): 700. Last 7 (06-21…06-27): 1400.
        // Today (06-28) is excluded — it's incomplete.
        var points = (14...20).map { point(String(format: "2026-06-%02d", $0), 100) }
        points += (21...27).map { point(String(format: "2026-06-%02d", $0), 200) }
        points.append(point("2026-06-28", 999_999)) // must be ignored
        let now = TestTime.date("2026-06-28T12:00:00Z")
        let change = DashboardMetrics.weekOverWeekChange(points, now: now, calendar: utcCalendar())
        #expect(change != nil)
        #expect(abs(change! - 1.0) < 0.0001) // +100%
    }

    @Test func weekOverWeekNilWithoutBaseline() {
        // Nothing in the previous window → no meaningful ratio.
        let points = (21...27).map { point(String(format: "2026-06-%02d", $0), 200) }
        let now = TestTime.date("2026-06-28T12:00:00Z")
        #expect(DashboardMetrics.weekOverWeekChange(points, now: now, calendar: utcCalendar()) == nil)
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

    // MARK: - Project × model breakdown

    @Test func projectModelBreakdownComputesPercentagesAndSortOrder() {
        let entries = [
            ProjectModelUsage(projectID: "A", displayName: "Proj A", family: .opus,
                              usage: TokenUsage(outputTokens: 300)),
            ProjectModelUsage(projectID: "A", displayName: "Proj A", family: .sonnet,
                              usage: TokenUsage(outputTokens: 100)),
            ProjectModelUsage(projectID: "B", displayName: "Proj B", family: .haiku,
                              usage: TokenUsage(outputTokens: 50))
        ]
        let breakdown = DashboardMetrics.projectModelBreakdown(entries)
        #expect(breakdown.count == 2)
        #expect(breakdown.first?.projectID == "A")   // A's total (400) > B's (50)
        #expect(breakdown.first?.totalTokens == 400)
        let segments = breakdown.first?.segments ?? []
        #expect(segments.count == 2)
        #expect(segments.first?.family == .opus)      // sorted desc by tokens
        #expect(segments.first?.percent.rounded() == 75)   // 300/400
        #expect(segments.last?.percent.rounded() == 25)    // 100/400
    }

    @Test func projectModelBreakdownTruncatesToTopProjects() {
        let entries = (0..<10).map { i in
            ProjectModelUsage(projectID: "P\(i)", displayName: "P\(i)", family: .opus,
                              usage: TokenUsage(outputTokens: 100 - i))
        }
        let breakdown = DashboardMetrics.projectModelBreakdown(entries, topProjects: 3)
        #expect(breakdown.count == 3)
        #expect(breakdown.map { $0.projectID } == ["P0", "P1", "P2"])
    }

    @Test func projectModelBreakdownEmptyForNoData() {
        #expect(DashboardMetrics.projectModelBreakdown([]).isEmpty)
    }
}
