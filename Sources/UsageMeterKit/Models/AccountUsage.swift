import Foundation

/// One usage dimension from the account (Source A): a percentage plus its reset time.
public struct UsageMetric: Codable, Sendable, Equatable {
    /// 0...100 (or beyond, defensively) percentage of the limit used.
    public var percent: Double
    /// When this window resets, if known.
    public var resetsAt: Date?

    public init(percent: Double, resetsAt: Date? = nil) {
        self.percent = percent
        self.resetsAt = resetsAt
    }

    /// Clamped-to-0 integer percent for compact display.
    public var displayPercent: Int { Int(max(0, percent).rounded()) }
}

/// Real money the account has spent on pay-as-you-go / overage credit, straight
/// from claude.ai's own usage response (`spend.used`). Unlike the Claude Code
/// "API value" estimate, this is the user's *actual* spend.
public struct SpendInfo: Codable, Sendable, Equatable {
    public var usedMinor: Int       // amount in minor units (e.g. cents)
    public var currency: String     // ISO code, e.g. "USD"
    public var exponent: Int        // minor-unit exponent, e.g. 2 → /100
    public var canPurchaseCredits: Bool

    public init(usedMinor: Int, currency: String, exponent: Int, canPurchaseCredits: Bool = false) {
        self.usedMinor = usedMinor
        self.currency = currency
        self.exponent = exponent
        self.canPurchaseCredits = canPurchaseCredits
    }

    /// The spent amount in major units (e.g. dollars). Negative ("used" can't be
    /// negative) is clamped to 0; the exponent is bounded so a bad value can't
    /// zero out or explode the amount.
    public var usedAmount: Double {
        let boundedExponent = min(max(0, exponent), 6)
        return Double(max(0, usedMinor)) / pow(10.0, Double(boundedExponent))
    }
}

/// The headline account numbers (Source A — claude.ai). The *primary* numbers,
/// mirroring `claude.ai/settings/usage`: the current 5-hour session, the rolling
/// 7-day window, and (when the plan exposes it) the separate weekly Opus limit.
///
/// Populated in Milestone 2 via `LiveAccountUsageClient`. When not logged in / the
/// endpoint is unknown / a fetch fails, this is `nil` and the app runs in
/// local-only mode (Sources B + C).
public struct AccountUsage: Codable, Sendable, Equatable {
    public var session: UsageMetric?
    public var weekly: UsageMetric?
    /// Separate weekly Opus limit, when the account/plan reports one.
    public var weeklyOpus: UsageMetric?
    /// Separate weekly Fable limit, when the account/plan reports one (a
    /// model-scoped entry in the `limits[]` array, not a top-level window).
    public var weeklyFable: UsageMetric?
    /// Real pay-as-you-go spend from claude.ai (the user's actual money).
    public var spend: SpendInfo?
    /// When these numbers were fetched.
    public var fetchedAt: Date?

    public init(
        session: UsageMetric? = nil,
        weekly: UsageMetric? = nil,
        weeklyOpus: UsageMetric? = nil,
        weeklyFable: UsageMetric? = nil,
        spend: SpendInfo? = nil,
        fetchedAt: Date? = nil
    ) {
        self.session = session
        self.weekly = weekly
        self.weeklyOpus = weeklyOpus
        self.weeklyFable = weeklyFable
        self.spend = spend
        self.fetchedAt = fetchedAt
    }

    /// Whether any dimension was actually populated.
    public var hasAnyMetric: Bool {
        session != nil || weekly != nil || weeklyOpus != nil || weeklyFable != nil
    }

    /// The highest utilization across dimensions — drives "near limit" logic.
    public var peakPercent: Double {
        [session?.percent, weekly?.percent, weeklyOpus?.percent, weeklyFable?.percent]
            .compactMap { $0 }
            .max() ?? 0
    }
}
