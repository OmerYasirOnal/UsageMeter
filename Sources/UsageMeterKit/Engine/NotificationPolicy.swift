import Foundation

/// What kind of usage alert to raise.
public enum UsageAlertKind: Equatable, Sendable {
    case threshold(Int)   // crossed 50 / 75 / 90 %
    case burnRate         // projected to hit the limit before reset
    case budget           // today's local API value crossed the user's daily budget
}

/// A single alert the app should surface as a notification.
public struct UsageAlert: Equatable, Sendable, Identifiable {
    public let metric: String       // "Session" / "Weekly" / "Weekly Opus"
    public let kind: UsageAlertKind
    public let title: String
    public let body: String

    public var id: String {
        switch kind {
        case .threshold(let t): return "\(metric)-t\(t)"
        case .burnRate: return "\(metric)-burn"
        case .budget: return "\(metric)-budget"
        }
    }
}

/// Per-metric, per-reset-cycle state so a given alert fires at most once per cycle.
public struct MetricAlertState: Codable, Equatable, Sendable {
    public var cycleKey: String
    public var firedThresholds: [Int]
    public var firedBurnRate: Bool
    /// First reading seen in this cycle — used for a smoothed (not 2-sample-noisy) rate.
    public var cycleStartPercent: Double?
    public var cycleStartDate: Date?

    public init(cycleKey: String, firedThresholds: [Int] = [], firedBurnRate: Bool = false,
                cycleStartPercent: Double? = nil, cycleStartDate: Date? = nil) {
        self.cycleKey = cycleKey
        self.firedThresholds = firedThresholds
        self.firedBurnRate = firedBurnRate
        self.cycleStartPercent = cycleStartPercent
        self.cycleStartDate = cycleStartDate
    }
}

/// Pure decision logic for limit notifications (testable; no UNUserNotificationCenter).
public enum NotificationPolicy {
    public static let thresholds = [50, 75, 90]
    /// Require at least this much observation before projecting a burn-rate, so we
    /// don't extrapolate a multi-day window from a few minutes of data.
    public static let minBurnObservation: TimeInterval = 30 * 60
    /// Don't bother projecting until usage is at least this high.
    public static let minBurnPercent = 25.0

    /// Evaluate one metric against its prior state.
    /// - Returns: alerts to fire now + the updated state to persist.
    public static func evaluate(
        metricName: String,
        percent: Double,
        resetsAt: Date?,
        now: Date,
        prior: MetricAlertState?
    ) -> (alerts: [UsageAlert], state: MetricAlertState) {
        let cycleKey = Self.cycleKey(for: resetsAt)
        var state = prior ?? MetricAlertState(cycleKey: cycleKey)
        if state.cycleKey != cycleKey {
            state = MetricAlertState(cycleKey: cycleKey)   // new cycle → clear fired + samples
        }
        if state.cycleStartPercent == nil {
            state.cycleStartPercent = percent
            state.cycleStartDate = now
        }

        var alerts: [UsageAlert] = []

        // Fire the highest newly-crossed threshold once; mark all crossed as fired.
        let alreadyFired = Set(state.firedThresholds)
        let crossedNow = thresholds.filter { percent >= Double($0) }
        if let highest = crossedNow.filter({ !alreadyFired.contains($0) }).max() {
            alerts.append(UsageAlert(
                metric: metricName, kind: .threshold(highest),
                title: "\(metricName): \(highest)%+ used",
                body: "You've used over \(highest)% of your \(metricName.lowercased()) limit."))
        }
        state.firedThresholds = Array(alreadyFired.union(crossedNow)).sorted()

        // Burn-rate: project from a SMOOTHED rate measured since the cycle start,
        // not the last two samples, and only after enough observation.
        if !state.firedBurnRate, let resetsAt,
           let startPercent = state.cycleStartPercent, let startDate = state.cycleStartDate {
            let elapsed = now.timeIntervalSince(startDate)
            let consumed = percent - startPercent
            let secondsToReset = resetsAt.timeIntervalSince(now)
            if elapsed >= minBurnObservation, consumed > 0, secondsToReset > 0, percent >= minBurnPercent {
                let projected = percent + (consumed / elapsed) * secondsToReset
                if projected >= 100 {
                    state.firedBurnRate = true
                    alerts.append(UsageAlert(
                        metric: metricName, kind: .burnRate,
                        title: "\(metricName): on track to hit the limit",
                        body: "At your recent pace you'll reach your \(metricName.lowercased()) limit before it resets."))
                }
            }
        }

        return (alerts, state)
    }

    /// Quantize the reset instant to the hour so sub-second/recomputed jitter (and
    /// the heuristic decoder's relative-duration resets) don't reset state every poll.
    public static func cycleKey(for resetsAt: Date?) -> String {
        guard let resetsAt else { return "none" }
        return String(Int(resetsAt.timeIntervalSince1970 / 3600))
    }
}

/// Pure decision logic for the local (Source B) daily-budget alert. Needs no
/// account, so notifications stay useful in the local-only App Store build and
/// for logged-out users. Reuses `MetricAlertState` (cycleKey = local day key;
/// `firedBurnRate` doubles as the "fired today" flag) so the notifier's
/// persisted state format is unchanged.
public enum DailyBudgetPolicy {
    public static let metricName = "Daily budget"

    public static func evaluate(
        todayCost: Double?,
        budgetUSD: Double?,
        dayKey: String,
        prior: MetricAlertState?
    ) -> (alerts: [UsageAlert], state: MetricAlertState) {
        var state = prior ?? MetricAlertState(cycleKey: dayKey)
        if state.cycleKey != dayKey {
            state = MetricAlertState(cycleKey: dayKey)   // new day → re-arm
        }
        guard let budgetUSD, budgetUSD > 0,
              let todayCost, todayCost >= budgetUSD,
              !state.firedBurnRate else {
            return ([], state)
        }
        state.firedBurnRate = true
        let alert = UsageAlert(
            metric: metricName, kind: .budget,
            title: "Daily budget reached",
            body: String(format: "Today's Claude Code API value (≈ $%.2f) crossed your $%.2f daily budget.", todayCost, budgetUSD))
        return ([alert], state)
    }
}
