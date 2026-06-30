import Foundation

/// A rolling 5-hour Claude Code usage window.
///
/// IMPORTANT: this is a *local estimate for Claude Code only*. Claude Code bills
/// in rolling 5-hour windows with boundaries aligned to the hour in UTC. The
/// authoritative account session/weekly percentages come from Source A, never this.
public struct UsageBlock: Codable, Sendable, Equatable, Identifiable {
    /// Block start (floored to the hour, UTC).
    public var start: Date
    /// Block end (`start` + 5h).
    public var end: Date
    public var usage: TokenUsage
    public var estimatedCost: Double?
    /// Whether `Date.now` falls inside `[start, end)`.
    public var isActive: Bool

    public var id: Date { start }

    public init(
        start: Date,
        end: Date,
        usage: TokenUsage = .zero,
        estimatedCost: Double? = nil,
        isActive: Bool = false
    ) {
        self.start = start
        self.end = end
        self.usage = usage
        self.estimatedCost = estimatedCost
        self.isActive = isActive
    }

    /// Total tokens burned in the block.
    public var totalTokens: Int { usage.totalTokens }

    /// Burn rate in tokens/minute, measured from block start to `now`.
    /// Returns `nil` for non-active blocks or when no time has elapsed.
    public func burnRate(now: Date) -> Double? {
        guard isActive else { return nil }
        let elapsedMinutes = now.timeIntervalSince(start) / 60.0
        guard elapsedMinutes > 0 else { return nil }
        return Double(totalTokens) / elapsedMinutes
    }

    /// Projected total tokens by block end if the current burn rate holds.
    public func projectedTokens(now: Date) -> Int? {
        guard let rate = burnRate(now: now) else { return nil }
        let totalMinutes = end.timeIntervalSince(start) / 60.0
        return Int((rate * totalMinutes).rounded())
    }
}
