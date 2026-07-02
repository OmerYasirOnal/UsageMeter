import Foundation

/// Usage + estimated cost for one model family.
public struct ModelUsage: Codable, Sendable, Equatable, Identifiable {
    public var family: ModelFamily
    public var usage: TokenUsage
    /// Estimated USD cost, or `nil` when the family is unpriced (`n/a`).
    public var estimatedCost: Double?

    public var id: String { family.rawValue }

    public init(family: ModelFamily, usage: TokenUsage = .zero, estimatedCost: Double? = nil) {
        self.family = family
        self.usage = usage
        self.estimatedCost = estimatedCost
    }
}

/// Usage + estimated cost for one project, with a best-effort display name.
public struct ProjectUsage: Codable, Sendable, Equatable, Identifiable {
    /// Project slug (folder name).
    public var projectID: String
    /// Best-effort human-friendly name derived from the slug.
    public var displayName: String
    public var usage: TokenUsage
    public var estimatedCost: Double?
    /// Number of distinct session files contributing to this project.
    public var sessionCount: Int

    public var id: String { projectID }

    public init(
        projectID: String,
        displayName: String,
        usage: TokenUsage = .zero,
        estimatedCost: Double? = nil,
        sessionCount: Int = 0
    ) {
        self.projectID = projectID
        self.displayName = displayName
        self.usage = usage
        self.estimatedCost = estimatedCost
        self.sessionCount = sessionCount
    }
}

/// Usage for a single calendar day (used by the activity grid in M3 and "today").
public struct DailyUsage: Codable, Sendable, Equatable, Identifiable {
    /// `yyyy-MM-dd` in the aggregator's calendar.
    public var day: String
    public var usage: TokenUsage
    public var estimatedCost: Double?

    public var id: String { day }

    public init(day: String, usage: TokenUsage = .zero, estimatedCost: Double? = nil) {
        self.day = day
        self.usage = usage
        self.estimatedCost = estimatedCost
    }
}

/// The full Source-B summary the UI consumes.
/// One (day, model family) bucket — lets the UI recompute "By model" for any
/// date range without another engine pass.
public struct DayModelUsage: Codable, Sendable, Equatable {
    public var day: String          // "yyyy-MM-dd"
    public var family: ModelFamily
    public var usage: TokenUsage
    public var estimatedCost: Double?

    public init(day: String, family: ModelFamily, usage: TokenUsage, estimatedCost: Double?) {
        self.day = day
        self.family = family
        self.usage = usage
        self.estimatedCost = estimatedCost
    }
}

public struct ClaudeCodeStats: Codable, Sendable, Equatable {
    /// All-time totals across the scanned logs.
    public var total: TokenUsage
    public var totalEstimatedCost: Double?

    /// Today's totals (aggregator's calendar day).
    public var today: TokenUsage
    public var todayEstimatedCost: Double?

    public var byModel: [ModelUsage]
    public var byProject: [ProjectUsage]
    public var byDay: [DailyUsage]

    /// Distinct session files seen.
    public var sessionCount: Int
    /// Distinct de-duplicated usage records seen.
    public var recordCount: Int

    /// The active rolling 5-hour block (local Claude Code burn estimate), if any.
    public var activeBlock: UsageBlock?

    /// How tokens typically accumulate over this user's day (last 14 complete
    /// days) — powers the day-end forecast. Nil until enough history exists.
    public var intradayProfile: IntradayProfile?

    /// Per-day per-model buckets (range-scoped "By model"; sorted by day).
    public var dailyByModel: [DayModelUsage]

    public init(
        total: TokenUsage = .zero,
        totalEstimatedCost: Double? = nil,
        today: TokenUsage = .zero,
        todayEstimatedCost: Double? = nil,
        byModel: [ModelUsage] = [],
        byProject: [ProjectUsage] = [],
        byDay: [DailyUsage] = [],
        sessionCount: Int = 0,
        recordCount: Int = 0,
        activeBlock: UsageBlock? = nil,
        intradayProfile: IntradayProfile? = nil,
        dailyByModel: [DayModelUsage] = []
    ) {
        self.total = total
        self.totalEstimatedCost = totalEstimatedCost
        self.today = today
        self.todayEstimatedCost = todayEstimatedCost
        self.byModel = byModel
        self.byProject = byProject
        self.byDay = byDay
        self.sessionCount = sessionCount
        self.recordCount = recordCount
        self.activeBlock = activeBlock
        self.intradayProfile = intradayProfile
        self.dailyByModel = dailyByModel
    }

    public static let empty = ClaudeCodeStats()
}
