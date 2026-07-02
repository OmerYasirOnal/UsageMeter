import Foundation

/// A stats-only, shareable summary of one member's Claude Code usage — the
/// Stage-0 "team" exchange format (`.umteam`). Serverless by design: a member
/// exports this file and hands it to their admin; nothing is transmitted by
/// the app itself.
///
/// **Privacy rule:** carries NO project entries (slugs encode absolute paths
/// and the macOS username) and — like everything upstream — nothing
/// message-adjacent. The `encodedJSONNeverContainsProjects` test locks this.
public struct TeamSummary: Codable, Equatable, Sendable {
    public struct Model: Codable, Equatable, Sendable {
        public let family: String
        public let tokens: Int
        public let cost: Double?

        public init(family: String, tokens: Int, cost: Double?) {
            self.family = family
            self.tokens = tokens
            self.cost = cost
        }
    }

    public struct Day: Codable, Equatable, Sendable {
        public let day: String       // "yyyy-MM-dd"
        public let tokens: Int
        public let cost: Double?

        public init(day: String, tokens: Int, cost: Double?) {
            self.day = day
            self.tokens = tokens
            self.cost = cost
        }
    }

    public static let currentSchemaVersion = 1
    public static let fileExtension = "umteam"

    public var schemaVersion: Int = TeamSummary.currentSchemaVersion
    public let member: String
    public let generatedAt: Date
    /// Size of the `byDay` window in days.
    public let days: Int
    public let totalTokens: Int
    public let totalCost: Double?
    public let sessionCount: Int
    public let byModel: [Model]
    public let byDay: [Day]

    public init(member: String, generatedAt: Date, days: Int, totalTokens: Int,
                totalCost: Double?, sessionCount: Int, byModel: [Model], byDay: [Day]) {
        self.member = member
        self.generatedAt = generatedAt
        self.days = days
        self.totalTokens = totalTokens
        self.totalCost = totalCost
        self.sessionCount = sessionCount
        self.byModel = byModel
        self.byDay = byDay
    }

    /// Build from the aggregator's stats, slicing `byDay` to the last `days`.
    public static func make(from stats: ClaudeCodeStats, member: String, now: Date,
                            calendar: Calendar = .current, days: Int = 90) -> TeamSummary {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        let cutoff = calendar.date(byAdding: .day, value: -(days - 1),
                                   to: calendar.startOfDay(for: now))
        let recent = stats.byDay
            .filter { daily in
                guard let cutoff, let date = formatter.date(from: daily.day) else { return false }
                return date >= cutoff
            }
            .sorted { $0.day < $1.day }
            .map { Day(day: $0.day, tokens: $0.usage.totalTokens, cost: $0.estimatedCost) }

        return TeamSummary(
            member: member,
            generatedAt: now,
            days: days,
            totalTokens: stats.total.totalTokens,
            totalCost: stats.totalEstimatedCost,
            sessionCount: stats.sessionCount,
            byModel: stats.byModel.map {
                Model(family: $0.family.rawValue, tokens: $0.usage.totalTokens, cost: $0.estimatedCost)
            },
            byDay: recent)
    }

    public func encode() -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? encoder.encode(self)) ?? Data()
    }

    /// Nil on garbage or an unknown schema version — never a half-decoded row.
    public static func decode(_ data: Data) -> TeamSummary? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let summary = try? decoder.decode(TeamSummary.self, from: data),
              summary.schemaVersion == currentSchemaVersion else { return nil }
        return summary
    }
}

/// One row of the admin's team table, computed from an imported summary.
public struct TeamMemberRow: Equatable, Sendable, Identifiable {
    public let member: String
    public let windowTokens: Int
    public let windowCost: Double?
    /// Last-7-complete-days vs the 7 before (same semantics as the dashboard card).
    public let weekOverWeek: Double?
    public let lastActiveDay: String?
    public let generatedAt: Date

    public var id: String { member + generatedAt.description }

    public static func make(from summary: TeamSummary, now: Date,
                            calendar: Calendar = .current) -> TeamMemberRow {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        let points: [DailyPoint] = summary.byDay.compactMap { day in
            guard let date = formatter.date(from: day.day) else { return nil }
            return DailyPoint(day: day.day, date: date, tokens: day.tokens, cost: day.cost)
        }
        let costs = summary.byDay.compactMap(\.cost)
        return TeamMemberRow(
            member: summary.member,
            windowTokens: summary.byDay.reduce(0) { $0 + $1.tokens },
            windowCost: costs.isEmpty ? nil : costs.reduce(0, +),
            weekOverWeek: DashboardMetrics.weekOverWeekChange(points, now: now, calendar: calendar),
            lastActiveDay: summary.byDay.last(where: { $0.tokens > 0 })?.day,
            generatedAt: summary.generatedAt)
    }
}
