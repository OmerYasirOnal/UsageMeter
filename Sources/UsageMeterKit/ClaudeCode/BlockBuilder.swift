import Foundation

/// Groups usage records into rolling 5-hour blocks (a *local* Claude Code burn
/// estimate, never the authoritative account number).
///
/// Algorithm (a simplified version of the widely-used ccusage approach):
///   - Block start is floored to the hour, in UTC.
///   - A new block begins when either the running block has spanned ≥ 5h since its
///     start, or there has been a ≥ 5h gap since the last activity.
public struct BlockBuilder: Sendable {
    public static let blockDuration: TimeInterval = 5 * 60 * 60

    private let calculator: CostCalculator
    private let utcCalendar: Calendar

    public init(calculator: CostCalculator) {
        self.calculator = calculator
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        self.utcCalendar = cal
    }

    /// Build all blocks from (already de-duplicated) records, oldest first.
    public func buildBlocks(from records: [UsageRecord], now: Date) -> [UsageBlock] {
        guard !records.isEmpty else { return [] }
        let sorted = records.sorted { $0.timestamp < $1.timestamp }

        var blocks: [UsageBlock] = []
        var perFamily: [ModelFamily: TokenUsage] = [:]
        var blockStart: Date = floorToHourUTC(sorted[0].timestamp)
        var blockEnd: Date = blockStart.addingTimeInterval(Self.blockDuration)
        var lastActivity: Date = sorted[0].timestamp
        var blockUsage = TokenUsage.zero

        func closeBlock() {
            guard blockUsage != .zero || !perFamily.isEmpty else { return }
            let cost = calculator.totalCost(perFamily)
            let isActive = (blockStart <= now) && (now < blockEnd)
            blocks.append(
                UsageBlock(start: blockStart, end: blockEnd, usage: blockUsage,
                           estimatedCost: cost, isActive: isActive)
            )
            perFamily = [:]
            blockUsage = .zero
        }

        for record in sorted {
            let spannedTooLong = record.timestamp >= blockStart.addingTimeInterval(Self.blockDuration)
            let gapTooLong = record.timestamp.timeIntervalSince(lastActivity) >= Self.blockDuration
            if spannedTooLong || gapTooLong {
                closeBlock()
                blockStart = floorToHourUTC(record.timestamp)
                blockEnd = blockStart.addingTimeInterval(Self.blockDuration)
            }
            blockUsage += record.usage
            perFamily[record.family, default: .zero] += record.usage
            lastActivity = record.timestamp
        }
        closeBlock()
        return blocks
    }

    /// The block containing `now`, if usage is recent enough to have one.
    public func activeBlock(from records: [UsageRecord], now: Date) -> UsageBlock? {
        buildBlocks(from: records, now: now).first { $0.isActive }
    }

    func floorToHourUTC(_ date: Date) -> Date {
        let comps = utcCalendar.dateComponents([.year, .month, .day, .hour], from: date)
        return utcCalendar.date(from: comps) ?? date
    }
}
