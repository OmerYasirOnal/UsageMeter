import Foundation

/// One day of Claude Code usage as a chart-ready point.
public struct DailyPoint: Sendable, Equatable, Identifiable {
    public let day: String          // "yyyy-MM-dd"
    public let date: Date           // start of that day
    public let tokens: Int
    public let cost: Double?

    public var id: String { day }

    public init(day: String, date: Date, tokens: Int, cost: Double?) {
        self.day = day
        self.date = date
        self.tokens = tokens
        self.cost = cost
    }
}

/// Computed dashboard insights over a set of daily points.
public struct UsageInsights: Sendable, Equatable {
    public var totalTokens: Int
    public var totalCost: Double?
    public var activeDays: Int
    public var averageDailyTokens: Int      // averaged over active days
    public var peak: DailyPoint?

    public init(totalTokens: Int = 0, totalCost: Double? = nil, activeDays: Int = 0,
                averageDailyTokens: Int = 0, peak: DailyPoint? = nil) {
        self.totalTokens = totalTokens
        self.totalCost = totalCost
        self.activeDays = activeDays
        self.averageDailyTokens = averageDailyTokens
        self.peak = peak
    }
}

/// One point of a moving-average trend line.
public struct MAPoint: Sendable, Equatable, Identifiable {
    public let day: String
    public let date: Date
    public let value: Double
    public var id: String { day }

    public init(day: String, date: Date, value: Double) {
        self.day = day
        self.date = date
        self.value = value
    }
}

/// Average daily tokens for one `Calendar` weekday (1 = Sunday … 7 = Saturday).
public struct WeekdayAverage: Sendable, Equatable, Identifiable {
    public let weekday: Int
    public let averageTokens: Int
    public var id: Int { weekday }

    public init(weekday: Int, averageTokens: Int) {
        self.weekday = weekday
        self.averageTokens = averageTokens
    }
}

/// Time window for the dashboard charts.
public enum DashboardRange: Sendable, Equatable, CaseIterable {
    case days7, days30, days90, all

    public var label: String {
        switch self {
        case .days7: return "7D"
        case .days30: return "30D"
        case .days90: return "90D"
        case .all: return "All"
        }
    }

    public var dayCount: Int? {
        switch self {
        case .days7: return 7
        case .days30: return 30
        case .days90: return 90
        case .all: return nil
        }
    }
}

/// Pure transforms from `ClaudeCodeStats` to chart/insight data — testable, no UI.
public enum DashboardMetrics {
    /// Convert the aggregator's per-day buckets into dated points (sorted ascending).
    public static func dailyPoints(from stats: ClaudeCodeStats, calendar: Calendar = .current) -> [DailyPoint] {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"

        return stats.byDay
            .compactMap { daily -> DailyPoint? in
                guard let date = formatter.date(from: daily.day) else { return nil }
                return DailyPoint(day: daily.day, date: date,
                                  tokens: daily.usage.totalTokens, cost: daily.estimatedCost)
            }
            .sorted { $0.date < $1.date }
    }

    /// Keep only points within `range` relative to `now`.
    public static func filtered(_ points: [DailyPoint], range: DashboardRange,
                                now: Date = Date(), calendar: Calendar = .current) -> [DailyPoint] {
        guard let dayCount = range.dayCount else { return points }
        let startOfToday = calendar.startOfDay(for: now)
        guard let cutoff = calendar.date(byAdding: .day, value: -(dayCount - 1), to: startOfToday) else {
            return points
        }
        return points.filter { $0.date >= cutoff }
    }

    /// Trailing moving average over CALENDAR days (gaps count as zero), one
    /// value per input point. Dividing by the window — not by "points seen" —
    /// keeps sparse early history from reading as a plateau.
    public static func movingAverage(
        _ points: [DailyPoint], window: Int = 7, calendar: Calendar = .current
    ) -> [MAPoint] {
        guard !points.isEmpty, window > 0 else { return [] }
        let tokensByDay = Dictionary(uniqueKeysWithValues: points.map { ($0.date, $0.tokens) })
        return points.map { point in
            var sum = 0
            for offset in 0..<window {
                if let day = calendar.date(byAdding: .day, value: -offset, to: point.date) {
                    sum += tokensByDay[day] ?? 0
                }
            }
            return MAPoint(day: point.day, date: point.date, value: Double(sum) / Double(window))
        }
    }

    /// Average tokens per weekday over the last `weeks` calendar weeks, dividing
    /// by the weekday's OCCURRENCES (missing days count as zero days). Returned
    /// for all 7 `Calendar` weekdays (1 = Sunday … 7 = Saturday).
    public static func weekdayAverages(
        _ points: [DailyPoint], weeks: Int = 12, now: Date = Date(), calendar: Calendar = .current
    ) -> [WeekdayAverage] {
        let startOfToday = calendar.startOfDay(for: now)
        guard weeks > 0,
              let cutoff = calendar.date(byAdding: .day, value: -(weeks * 7 - 1), to: startOfToday)
        else { return [] }
        var totals = [Int: Int]()
        for point in points where point.date >= cutoff && point.date <= startOfToday {
            totals[calendar.component(.weekday, from: point.date), default: 0] += point.tokens
        }
        return (1...7).map { weekday in
            WeekdayAverage(weekday: weekday, averageTokens: (totals[weekday] ?? 0) / weeks)
        }
    }

    public static func insights(_ points: [DailyPoint]) -> UsageInsights {
        let active = points.filter { $0.tokens > 0 }
        let totalTokens = points.reduce(0) { $0 + $1.tokens }
        let costs = points.compactMap { $0.cost }
        let totalCost = costs.isEmpty ? nil : costs.reduce(0, +)
        let avg = active.isEmpty ? 0 : totalTokens / active.count
        let peak = points.max { $0.tokens < $1.tokens }
        return UsageInsights(
            totalTokens: totalTokens,
            totalCost: totalCost,
            activeDays: active.count,
            averageDailyTokens: avg,
            peak: (peak?.tokens ?? 0) > 0 ? peak : nil
        )
    }
}
