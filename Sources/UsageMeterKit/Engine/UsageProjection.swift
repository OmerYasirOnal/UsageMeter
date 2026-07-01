import Foundation

/// Projects when an account metric (session / weekly %) will reach 100% at the
/// recent pace, from a SMOOTHED rate measured since the current reset-cycle began
/// (not a noisy two-sample slope). Pure and testable — mirrors the burn-rate math
/// in `NotificationPolicy`, but returns a rich result for the UI instead of a
/// one-shot alert.
///
/// "Realistic" guardrails: it won't extrapolate a projection from a few minutes of
/// data (needs `minObservation`) or from a barely-used window (needs `minPercent`),
/// so the estimate stays close to reality rather than swinging wildly.
public struct UsageProjection: Equatable, Sendable {
    public enum Status: Equatable, Sendable {
        /// Not enough observation yet (just started watching this cycle).
        case gathering
        /// Flat or decreasing — you're not on track to run out.
        case notRising
        /// At this pace you'd hit the limit, but the window RESETS first → you're fine.
        /// `timeToLimit` is seconds until you'd reach 100%.
        case resetsFirst(timeToLimit: TimeInterval)
        /// At this pace you'll hit the limit BEFORE it resets. `timeToLimit` is
        /// seconds until 100%; `marginBeforeReset` is how much sooner that is than
        /// the reset.
        case exhausts(timeToLimit: TimeInterval, marginBeforeReset: TimeInterval)
    }

    public let status: Status
    /// Percent consumed per hour at the smoothed rate (nil when gathering/not rising).
    public let ratePerHour: Double?
    /// The % you'd reach by the reset time at this pace (nil if unknown).
    public let projectedPercentAtReset: Double?

    public init(status: Status, ratePerHour: Double?, projectedPercentAtReset: Double?) {
        self.status = status
        self.ratePerHour = ratePerHour
        self.projectedPercentAtReset = projectedPercentAtReset
    }

    /// Seconds until 100% at this pace, if we have a rising rate.
    public var timeToLimit: TimeInterval? {
        switch status {
        case .resetsFirst(let t), .exhausts(let t, _): return t
        case .gathering, .notRising: return nil
        }
    }

    /// True when on track to hit the limit before the window resets.
    public var willExhaustBeforeReset: Bool {
        if case .exhausts = status { return true }
        return false
    }

    public static func compute(
        percent: Double,
        resetsAt: Date?,
        startPercent: Double?,
        startDate: Date?,
        now: Date,
        minObservation: TimeInterval = 15 * 60,
        minPercent: Double = 5
    ) -> UsageProjection {
        guard let startPercent, let startDate, let resetsAt else {
            return UsageProjection(status: .gathering, ratePerHour: nil, projectedPercentAtReset: nil)
        }
        let elapsed = now.timeIntervalSince(startDate)
        let consumed = percent - startPercent
        let secondsToReset = resetsAt.timeIntervalSince(now)

        guard elapsed >= minObservation, percent >= minPercent, secondsToReset > 0 else {
            return UsageProjection(status: .gathering, ratePerHour: nil, projectedPercentAtReset: nil)
        }
        guard consumed > 0, elapsed > 0, percent < 100 else {
            return UsageProjection(status: .notRising, ratePerHour: 0, projectedPercentAtReset: percent)
        }

        let ratePerSec = consumed / elapsed
        let ratePerHour = ratePerSec * 3600
        let timeToLimit = (100 - percent) / ratePerSec
        let projectedAtReset = min(999, percent + ratePerSec * secondsToReset)

        if timeToLimit < secondsToReset {
            return UsageProjection(
                status: .exhausts(timeToLimit: timeToLimit, marginBeforeReset: secondsToReset - timeToLimit),
                ratePerHour: ratePerHour, projectedPercentAtReset: projectedAtReset)
        }
        return UsageProjection(
            status: .resetsFirst(timeToLimit: timeToLimit),
            ratePerHour: ratePerHour, projectedPercentAtReset: projectedAtReset)
    }
}
