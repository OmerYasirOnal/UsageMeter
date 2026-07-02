import Foundation

/// Turns a flat list of parsed `UsageRecord`s into the `ClaudeCodeStats` the UI
/// consumes. Performs the global de-duplication (Section 4.3 rule 3) and the
/// (model, day, project) accumulation (rule 4).
///
/// `@unchecked Sendable`: holds a configured `DateFormatter`, which Apple
/// documents as thread-safe for formatting on macOS 10.9+. It is only ever read.
public struct DailyAggregator: @unchecked Sendable {
    private let calculator: CostCalculator
    private let calendar: Calendar
    private let dayFormatter: DateFormatter

    /// - Parameters:
    ///   - calculator: cost engine.
    ///   - calendar: calendar used for "today" and per-day grouping. Defaults to
    ///     the current calendar (local time), which matches what a user means by
    ///     "today". Tests pin this for determinism.
    public init(calculator: CostCalculator, calendar: Calendar = .current) {
        self.calculator = calculator
        self.calendar = calendar
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        self.dayFormatter = formatter
    }

    /// Aggregate de-duplicated records into stats.
    /// - Parameters:
    ///   - records: parsed records across all files (may contain cross-file dupes).
    ///   - now: reference "now" for the today bucket and the active block.
    ///   - sessionCountByProject: optional file counts per project for the table.
    ///   - totalSessions: optional total session-file count.
    public func aggregate(
        records: [UsageRecord],
        now: Date,
        sessionCountByProject: [String: Int] = [:],
        totalSessions: Int = 0
    ) -> ClaudeCodeStats {
        // Global dedup, preferring the first occurrence of each id.
        var seen = Set<String>()
        var unique: [UsageRecord] = []
        unique.reserveCapacity(records.count)
        for record in records where seen.insert(record.id).inserted {
            unique.append(record)
        }

        let todayString = dayFormatter.string(from: now)

        var total = TokenUsage.zero
        var today = TokenUsage.zero
        var totalByFamily: [ModelFamily: TokenUsage] = [:]
        var todayByFamily: [ModelFamily: TokenUsage] = [:]
        var byModel: [ModelFamily: TokenUsage] = [:]
        var byProject: [String: TokenUsage] = [:]
        var byProjectFamily: [String: [ModelFamily: TokenUsage]] = [:]
        var byDay: [String: TokenUsage] = [:]
        var byDayFamily: [String: [ModelFamily: TokenUsage]] = [:]

        for record in unique {
            let family = record.family
            total += record.usage
            totalByFamily[family, default: .zero] += record.usage

            byModel[family, default: .zero] += record.usage
            byProject[record.projectID, default: .zero] += record.usage
            byProjectFamily[record.projectID, default: [:]][family, default: .zero] += record.usage

            let day = dayFormatter.string(from: record.timestamp)
            byDay[day, default: .zero] += record.usage
            byDayFamily[day, default: [:]][family, default: .zero] += record.usage

            if day == todayString {
                today += record.usage
                todayByFamily[family, default: .zero] += record.usage
            }
        }

        let modelUsages: [ModelUsage] = byModel
            .map { ModelUsage(family: $0.key, usage: $0.value,
                              estimatedCost: calculator.cost(usage: $0.value, family: $0.key)) }
            .sorted { $0.usage.totalTokens > $1.usage.totalTokens }

        let projectUsages: [ProjectUsage] = byProject
            .map { (projectID, usage) in
                ProjectUsage(
                    projectID: projectID,
                    displayName: ProjectName.display(forSlug: projectID),
                    usage: usage,
                    estimatedCost: calculator.totalCost(byProjectFamily[projectID] ?? [:]),
                    sessionCount: sessionCountByProject[projectID] ?? 0
                )
            }
            .sorted { $0.usage.totalTokens > $1.usage.totalTokens }

        let dailyUsages: [DailyUsage] = byDay
            .map { (day, usage) in
                DailyUsage(day: day, usage: usage,
                           estimatedCost: calculator.totalCost(byDayFamily[day] ?? [:]))
            }
            .sorted { $0.day < $1.day }

        let dailyByModel: [DayModelUsage] = byDayFamily
            .flatMap { day, families in
                families.map { family, usage in
                    DayModelUsage(day: day, family: family, usage: usage,
                                  estimatedCost: calculator.cost(usage: usage, family: family))
                }
            }
            .sorted { ($0.day, $0.family.rawValue) < ($1.day, $1.family.rawValue) }

        let blockBuilder = BlockBuilder(calculator: calculator)
        let activeBlock = blockBuilder.activeBlock(from: unique, now: now)

        return ClaudeCodeStats(
            total: total,
            totalEstimatedCost: calculator.totalCost(totalByFamily),
            today: today,
            todayEstimatedCost: calculator.totalCost(todayByFamily),
            byModel: modelUsages,
            byProject: projectUsages,
            byDay: dailyUsages,
            sessionCount: totalSessions,
            recordCount: unique.count,
            activeBlock: activeBlock,
            intradayProfile: IntradayProfile.compute(records: unique, now: now, calendar: calendar),
            dailyByModel: dailyByModel
        )
    }
}
