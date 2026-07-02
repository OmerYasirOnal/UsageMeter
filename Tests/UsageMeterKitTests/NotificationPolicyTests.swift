import Testing
import Foundation
@testable import UsageMeterKit

@Suite struct NotificationPolicyTests {
    let reset = TestTime.date("2026-07-01T00:00:00Z")
    let now = TestTime.date("2026-06-30T12:00:00Z")

    @Test func firesHighestNewlyCrossedThresholdOnce() {
        let r = NotificationPolicy.evaluate(metricName: "Session", percent: 76, resetsAt: reset, now: now, prior: nil)
        let thresholds = r.alerts.compactMap { if case .threshold(let t) = $0.kind { return t } else { return nil } }
        #expect(thresholds == [75])                        // 75 fired, not 50+75 burst
        #expect(Set(r.state.firedThresholds) == [50, 75])  // both marked fired
    }

    @Test func doesNotRefireAlreadyFiredThresholds() {
        let first = NotificationPolicy.evaluate(metricName: "Session", percent: 76, resetsAt: reset, now: now, prior: nil)
        let second = NotificationPolicy.evaluate(metricName: "Session", percent: 80, resetsAt: reset,
                                                 now: now.addingTimeInterval(60), prior: first.state)
        #expect(second.alerts.contains { if case .threshold = $0.kind { return true } else { return false } } == false)
    }

    @Test func firesNinetyWhenCrossed() {
        let first = NotificationPolicy.evaluate(metricName: "Weekly", percent: 76, resetsAt: reset, now: now, prior: nil)
        let second = NotificationPolicy.evaluate(metricName: "Weekly", percent: 92, resetsAt: reset,
                                                 now: now.addingTimeInterval(60), prior: first.state)
        let thresholds = second.alerts.compactMap { if case .threshold(let t) = $0.kind { return t } else { return nil } }
        #expect(thresholds == [90])
    }

    @Test func newCycleResetsFiredThresholds() {
        let first = NotificationPolicy.evaluate(metricName: "Session", percent: 76, resetsAt: reset, now: now, prior: nil)
        let newReset = TestTime.date("2026-07-02T00:00:00Z")
        let second = NotificationPolicy.evaluate(metricName: "Session", percent: 76, resetsAt: newReset,
                                                 now: now.addingTimeInterval(3600), prior: first.state)
        let thresholds = second.alerts.compactMap { if case .threshold(let t) = $0.kind { return t } else { return nil } }
        #expect(thresholds == [75]) // re-fires in the new cycle
    }

    @Test func burnRateFiresWhenProjectedOverLimit() {
        // 10% now, then 60% an hour later, with reset 1h out → projected 110% → alert.
        let first = NotificationPolicy.evaluate(metricName: "Session", percent: 10,
                                                resetsAt: now.addingTimeInterval(7200), now: now, prior: nil)
        #expect(first.alerts.contains { $0.kind == .burnRate } == false) // need 2 readings
        let later = now.addingTimeInterval(3600)
        let second = NotificationPolicy.evaluate(metricName: "Session", percent: 60,
                                                 resetsAt: later.addingTimeInterval(3600), now: later, prior: first.state)
        #expect(second.alerts.contains { $0.kind == .burnRate })
    }

    @Test func burnRateRequiresEnoughObservation() {
        // The original bug: a tiny weekly tick over one 3-min refresh extrapolated
        // across 7 days fired a false positive. The observation gate must prevent it.
        let weekReset = now.addingTimeInterval(7 * 86400)
        let first = NotificationPolicy.evaluate(metricName: "Weekly", percent: 30, resetsAt: weekReset, now: now, prior: nil)
        let soon = now.addingTimeInterval(180) // only 3 minutes later
        let second = NotificationPolicy.evaluate(metricName: "Weekly", percent: 31, resetsAt: weekReset, now: soon, prior: first.state)
        #expect(second.alerts.contains { $0.kind == .burnRate } == false)
    }

    @Test func cycleKeyToleratesSubHourResetJitter() {
        // Reset time wobbling by a couple minutes (same hour) must NOT reset the
        // fired-threshold set and re-fire notifications every poll.
        let r1 = TestTime.date("2026-07-01T03:00:00Z")
        let r2 = r1.addingTimeInterval(120)
        let first = NotificationPolicy.evaluate(metricName: "Session", percent: 76, resetsAt: r1, now: now, prior: nil)
        let second = NotificationPolicy.evaluate(metricName: "Session", percent: 77, resetsAt: r2,
                                                 now: now.addingTimeInterval(60), prior: first.state)
        #expect(second.alerts.contains { if case .threshold = $0.kind { return true } else { return false } } == false)
    }

    @Test func burnRateDoesNotFireWhenPaceIsSafe() {
        // ~0.1%/hour with ~3h to reset → projects to ~10.3%, well under the limit.
        let reset3h = now.addingTimeInterval(3 * 3600)
        let first = NotificationPolicy.evaluate(metricName: "Weekly", percent: 10,
                                                resetsAt: reset3h, now: now, prior: nil)
        let later = now.addingTimeInterval(3600)
        let second = NotificationPolicy.evaluate(metricName: "Weekly", percent: 10.1,
                                                 resetsAt: reset3h, now: later, prior: first.state)
        #expect(second.alerts.contains { $0.kind == .burnRate } == false)
    }
}

@Suite struct DailyBudgetPolicyTests {
    @Test func firesOncePerDayWhenBudgetCrossed() {
        let first = DailyBudgetPolicy.evaluate(todayCost: 12.5, budgetUSD: 10, dayKey: "2026-7-2", prior: nil)
        #expect(first.alerts.count == 1)
        #expect(first.alerts.first?.kind == .budget)

        // Same day, still over budget → no repeat.
        let second = DailyBudgetPolicy.evaluate(todayCost: 15.0, budgetUSD: 10, dayKey: "2026-7-2", prior: first.state)
        #expect(second.alerts.isEmpty)
    }

    @Test func reArmsOnANewDay() {
        let fired = DailyBudgetPolicy.evaluate(todayCost: 12.5, budgetUSD: 10, dayKey: "2026-7-2", prior: nil)
        let nextDay = DailyBudgetPolicy.evaluate(todayCost: 11.0, budgetUSD: 10, dayKey: "2026-7-3", prior: fired.state)
        #expect(nextDay.alerts.count == 1)
    }

    @Test func silentWhenOffBelowOrUnknown() {
        #expect(DailyBudgetPolicy.evaluate(todayCost: 99, budgetUSD: 0, dayKey: "d", prior: nil).alerts.isEmpty)   // off
        #expect(DailyBudgetPolicy.evaluate(todayCost: 99, budgetUSD: nil, dayKey: "d", prior: nil).alerts.isEmpty) // off
        #expect(DailyBudgetPolicy.evaluate(todayCost: 5, budgetUSD: 10, dayKey: "d", prior: nil).alerts.isEmpty)   // below
        #expect(DailyBudgetPolicy.evaluate(todayCost: nil, budgetUSD: 10, dayKey: "d", prior: nil).alerts.isEmpty) // unknown cost
    }

    @Test func exactBudgetCountsAsCrossed() {
        let r = DailyBudgetPolicy.evaluate(todayCost: 10, budgetUSD: 10, dayKey: "d", prior: nil)
        #expect(r.alerts.count == 1)
    }
}
