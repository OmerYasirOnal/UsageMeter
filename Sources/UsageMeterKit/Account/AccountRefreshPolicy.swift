import Foundation

/// Adaptive, polite refresh cadence for the account source (§3.3): refresh more
/// often as utilization climbs toward a limit, back off when usage is low. Pure
/// function so it is trivially unit-testable.
public enum AccountRefreshPolicy {
    /// - Parameters:
    ///   - usage: latest account usage (nil → not logged in).
    ///   - base: the user's configured refresh interval (seconds).
    ///   - minimum: never refresh faster than this (politeness floor).
    ///   - maximum: never wait longer than this.
    public static func interval(
        for usage: AccountUsage?,
        base: TimeInterval,
        minimum: TimeInterval = 60,
        maximum: TimeInterval = 1800
    ) -> TimeInterval {
        guard let usage, usage.hasAnyMetric else {
            // Logged out / unknown → just use the base cadence.
            return clamp(base, minimum, maximum)
        }
        let scaled: TimeInterval
        switch usage.peakPercent {
        case 90...:      scaled = base * 0.25 // very close to a limit — watch it
        case 75..<90:    scaled = base * 0.5
        case 50..<75:    scaled = base
        default:         scaled = base * 2.0  // low usage — relax
        }
        return clamp(scaled, minimum, maximum)
    }

    private static func clamp(_ value: TimeInterval, _ lo: TimeInterval, _ hi: TimeInterval) -> TimeInterval {
        min(hi, max(lo, value))
    }
}
