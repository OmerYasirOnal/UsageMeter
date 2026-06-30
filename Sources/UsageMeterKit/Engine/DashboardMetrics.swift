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
