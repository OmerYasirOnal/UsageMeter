import Foundation
import Testing
@testable import UsageMeterKit

@Suite("LoginFlowModel")
struct LoginFlowModelTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    @Test func startsSigningIn() {
        #expect(LoginFlowModel().phase == .signingIn)
    }

    @Test func loggedInPageStartsFetching() {
        var m = LoginFlowModel()
        m.loggedInPageFinished(now: t0)
        #expect(m.phase == .fetching(since: t0))
    }

    @Test func repeatedLoggedInPagesKeepOriginalTimer() {
        var m = LoginFlowModel()
        m.loggedInPageFinished(now: t0)
        m.loggedInPageFinished(now: t0.addingTimeInterval(5))
        #expect(m.phase == .fetching(since: t0)) // timeout clock must not reset
    }

    @Test func captureWinsFromAnyPhase() {
        var fromSigningIn = LoginFlowModel()
        fromSigningIn.usageCaptured()
        #expect(fromSigningIn.phase == .captured)

        var fromFetching = LoginFlowModel()
        fromFetching.loggedInPageFinished(now: t0)
        fromFetching.usageCaptured()
        #expect(fromFetching.phase == .captured)

        var fromTimeout = LoginFlowModel()
        fromTimeout.loggedInPageFinished(now: t0)
        fromTimeout.tick(now: t0.addingTimeInterval(15))
        fromTimeout.usageCaptured()
        #expect(fromTimeout.phase == .captured)
    }

    @Test func tickTimesOutOnlyAtBoundary() {
        var m = LoginFlowModel()
        m.loggedInPageFinished(now: t0)
        m.tick(now: t0.addingTimeInterval(14.9))
        #expect(m.phase == .fetching(since: t0))
        m.tick(now: t0.addingTimeInterval(15))
        #expect(m.phase == .fetchTimeout)
    }

    @Test func tickOutsideFetchingDoesNothing() {
        var m = LoginFlowModel()
        m.tick(now: t0.addingTimeInterval(100))
        #expect(m.phase == .signingIn)
        m.usageCaptured()
        m.tick(now: t0.addingTimeInterval(1_000))
        #expect(m.phase == .captured)
    }

    @Test func backOnLoginPageRearms() {
        var m = LoginFlowModel()
        m.loggedInPageFinished(now: t0)
        m.backOnLoginPage()
        #expect(m.phase == .signingIn)
    }

    @Test func capturedIsTerminal() {
        var m = LoginFlowModel()
        m.usageCaptured()
        m.backOnLoginPage()
        m.loggedInPageFinished(now: t0)
        #expect(m.phase == .captured)
    }

    @Test func retryRestartsFetchTimer() {
        var m = LoginFlowModel()
        m.loggedInPageFinished(now: t0)
        m.tick(now: t0.addingTimeInterval(15))
        let t1 = t0.addingTimeInterval(20)
        m.retryRequested(now: t1)
        #expect(m.phase == .fetching(since: t1))
        m.tick(now: t1.addingTimeInterval(14))
        #expect(m.phase == .fetching(since: t1))
    }

    @Test func retryIgnoredOutsideTimeout() {
        var m = LoginFlowModel()
        m.retryRequested(now: t0)
        #expect(m.phase == .signingIn)
    }
}
