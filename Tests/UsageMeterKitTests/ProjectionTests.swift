import Testing
import Foundation
@testable import UsageMeterKit

@Suite struct UsageProjectionTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func gatheringWhenNotEnoughObservation() {
        let p = UsageProjection.compute(
            percent: 40, resetsAt: now.addingTimeInterval(3600),
            startPercent: 20, startDate: now.addingTimeInterval(-600), // 10 min < 15 min gate
            now: now)
        #expect(p.status == .gathering)
        #expect(p.timeToLimit == nil)
    }

    @Test func exhaustsBeforeReset() {
        // 20% → 80% over 60 min = 60%/hr; 20% left ⇒ ~20 min to limit; resets in 60 min.
        let p = UsageProjection.compute(
            percent: 80, resetsAt: now.addingTimeInterval(3600),
            startPercent: 20, startDate: now.addingTimeInterval(-3600),
            now: now)
        #expect(p.willExhaustBeforeReset)
        #expect(abs((p.ratePerHour ?? 0) - 60) < 0.01)
        if case .exhausts(let ttl, let margin) = p.status {
            #expect(abs(ttl - 1200) < 1)      // ~20 min
            #expect(abs(margin - 2400) < 1)   // 40 min of head-room before reset
        } else { Issue.record("expected .exhausts, got \(p.status)") }
    }

    @Test func resetsFirstWhenPaceIsSlow() {
        // 20% → 30% over 60 min = 10%/hr; 70% left ⇒ ~7h to limit; resets in 60 min.
        let p = UsageProjection.compute(
            percent: 30, resetsAt: now.addingTimeInterval(3600),
            startPercent: 20, startDate: now.addingTimeInterval(-3600),
            now: now)
        #expect(!p.willExhaustBeforeReset)
        if case .resetsFirst(let ttl) = p.status {
            #expect(ttl > 3600)   // limit is beyond the reset
        } else { Issue.record("expected .resetsFirst, got \(p.status)") }
    }

    @Test func notRisingWhenFlat() {
        let p = UsageProjection.compute(
            percent: 30, resetsAt: now.addingTimeInterval(3600),
            startPercent: 30, startDate: now.addingTimeInterval(-3600),
            now: now)
        #expect(p.status == .notRising)
        #expect(p.timeToLimit == nil)
    }

    @Test func gatheringWithoutResetInfo() {
        let p = UsageProjection.compute(
            percent: 80, resetsAt: nil,
            startPercent: 20, startDate: now.addingTimeInterval(-3600),
            now: now)
        #expect(p.status == .gathering)   // no reset → can't project a meaningful margin
    }
}
