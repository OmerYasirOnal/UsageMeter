import Foundation
import Testing
@testable import UsageMeterKit

@Suite("LoginFlowModel")
struct LoginFlowModelTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    /// A model that already skipped the native email step (mock mode / full-page fallback).
    private func atSigningIn() -> LoginFlowModel { LoginFlowModel(skipEmailStep: true) }

    // MARK: - Initial phase

    @Test func defaultStartsAtEmailStep() {
        #expect(LoginFlowModel().phase == .enterEmail)
    }

    @Test func skipEmailStepStartsSigningIn() {
        #expect(LoginFlowModel(skipEmailStep: true).phase == .signingIn)
    }

    // MARK: - Consent phase

    @Test func showConsentGateStartsAtConsent() {
        #expect(LoginFlowModel(showConsentGate: true).phase == .consent)
    }

    @Test func mockSkipsConsentGateEvenWhenRequested() {
        #expect(LoginFlowModel(skipEmailStep: true, showConsentGate: true).phase == .signingIn)
    }

    @Test func consentAcceptedMovesToEmailStep() {
        var m = LoginFlowModel(showConsentGate: true)
        m.consentAccepted()
        #expect(m.phase == .enterEmail)
    }

    @Test func consentAcceptedIgnoredOutsideConsentPhase() {
        var m = LoginFlowModel()
        m.consentAccepted()
        #expect(m.phase == .enterEmail)
    }

    @Test func backOnLoginPageIgnoredDuringConsent() {
        var m = LoginFlowModel(showConsentGate: true)
        m.backOnLoginPage()
        #expect(m.phase == .consent)
    }

    @Test func loggedInPageFinishedIgnoredDuringConsent() {
        var m = LoginFlowModel(showConsentGate: true)
        m.loggedInPageFinished(now: t0)
        #expect(m.phase == .consent)
    }

    // MARK: - Email step

    @Test func emailSubmittedStartsAutofill() {
        var m = LoginFlowModel()
        m.emailSubmitted(now: t0)
        #expect(m.phase == .autofilling(since: t0))
    }

    @Test func emailSubmittedIgnoredOutsideEmailStep() {
        var m = atSigningIn()
        m.emailSubmitted(now: t0)
        #expect(m.phase == .signingIn)
    }

    @Test func fullPageRequestSkipsToSigningIn() {
        var m = LoginFlowModel()
        m.fullPageRequested()
        #expect(m.phase == .signingIn)
        #expect(m.autofillFailed == false)
    }

    @Test func fullPageRequestIgnoredOutsideEmailStep() {
        var m = LoginFlowModel()
        m.emailSubmitted(now: t0)
        m.fullPageRequested()
        #expect(m.phase == .autofilling(since: t0))
    }

    // MARK: - Autofill phase

    @Test func codeScreenRevealsWebView() {
        var m = LoginFlowModel()
        m.emailSubmitted(now: t0)
        m.codeScreenDetected()
        #expect(m.phase == .signingIn)
        #expect(m.autofillFailed == false)
    }

    @Test func codeScreenIgnoredOutsideAutofill() {
        var m = atSigningIn()
        m.codeScreenDetected()
        #expect(m.phase == .signingIn)
    }

    @Test func lateCodeScreenClearsAutofillFailedBanner() {
        // Code screen arrives AFTER the 8s autofill timeout already fired: the
        // prefill actually worked (just slow), so the misleading banner clears.
        var m = LoginFlowModel()
        m.emailSubmitted(now: t0)
        m.tick(now: t0.addingTimeInterval(8)) // times out → .signingIn, autofillFailed = true
        #expect(m.autofillFailed == true)
        m.codeScreenDetected()
        #expect(m.phase == .signingIn)
        #expect(m.autofillFailed == false)
    }

    @Test func codeScreenInPlainSigningInIsNoOp() {
        // Full-page fallback signingIn (autofillFailed == false): a stray
        // code-screen message must not change anything.
        var m = atSigningIn()
        m.codeScreenDetected()
        #expect(m.phase == .signingIn)
        #expect(m.autofillFailed == false)
    }

    @Test func autofillTimesOutWithFailureFlag() {
        var m = LoginFlowModel()
        m.emailSubmitted(now: t0)
        m.tick(now: t0.addingTimeInterval(7.9))
        #expect(m.phase == .autofilling(since: t0))
        m.tick(now: t0.addingTimeInterval(8))
        #expect(m.phase == .signingIn)
        #expect(m.autofillFailed == true)
    }

    @Test func loggedInDuringAutofillShortcutsToFetching() {
        // Already-valid session: claude.ai skips the login form entirely.
        var m = LoginFlowModel()
        m.emailSubmitted(now: t0)
        m.loggedInPageFinished(now: t0.addingTimeInterval(2))
        #expect(m.phase == .fetching(since: t0.addingTimeInterval(2)))
    }

    @Test func loggedInClearsAutofillFailedFlag() {
        var m = LoginFlowModel()
        m.emailSubmitted(now: t0)
        m.tick(now: t0.addingTimeInterval(8)) // autofillFailed = true
        m.loggedInPageFinished(now: t0.addingTimeInterval(30))
        #expect(m.autofillFailed == false)
        #expect(m.phase == .fetching(since: t0.addingTimeInterval(30)))
    }

    @Test func backOnLoginPageIgnoredDuringEmailAndAutofill() {
        var atEmail = LoginFlowModel()
        atEmail.backOnLoginPage()
        #expect(atEmail.phase == .enterEmail)

        var autofilling = LoginFlowModel()
        autofilling.emailSubmitted(now: t0)
        autofilling.backOnLoginPage()
        #expect(autofilling.phase == .autofilling(since: t0))
    }

    // MARK: - Existing behavior (from .signingIn onwards) — unchanged

    @Test func loggedInPageStartsFetching() {
        var m = atSigningIn()
        m.loggedInPageFinished(now: t0)
        #expect(m.phase == .fetching(since: t0))
    }

    @Test func repeatedLoggedInPagesKeepOriginalTimer() {
        var m = atSigningIn()
        m.loggedInPageFinished(now: t0)
        m.loggedInPageFinished(now: t0.addingTimeInterval(5))
        #expect(m.phase == .fetching(since: t0)) // timeout clock must not reset
    }

    @Test func captureWinsFromAnyPhase() {
        var fromEmail = LoginFlowModel()
        fromEmail.usageCaptured()
        #expect(fromEmail.phase == .captured)

        var fromFetching = atSigningIn()
        fromFetching.loggedInPageFinished(now: t0)
        fromFetching.usageCaptured()
        #expect(fromFetching.phase == .captured)

        var fromTimeout = atSigningIn()
        fromTimeout.loggedInPageFinished(now: t0)
        fromTimeout.tick(now: t0.addingTimeInterval(15))
        fromTimeout.usageCaptured()
        #expect(fromTimeout.phase == .captured)
    }

    @Test func tickTimesOutFetchingOnlyAtBoundary() {
        var m = atSigningIn()
        m.loggedInPageFinished(now: t0)
        m.tick(now: t0.addingTimeInterval(14.9))
        #expect(m.phase == .fetching(since: t0))
        m.tick(now: t0.addingTimeInterval(15))
        #expect(m.phase == .fetchTimeout)
    }

    @Test func tickOutsideTimedPhasesDoesNothing() {
        var m = atSigningIn()
        m.tick(now: t0.addingTimeInterval(100))
        #expect(m.phase == .signingIn)
        m.usageCaptured()
        m.tick(now: t0.addingTimeInterval(1_000))
        #expect(m.phase == .captured)
    }

    @Test func backOnLoginPageRearms() {
        var m = atSigningIn()
        m.loggedInPageFinished(now: t0)
        m.backOnLoginPage()
        #expect(m.phase == .signingIn)
    }

    @Test func capturedIsTerminal() {
        var m = atSigningIn()
        m.usageCaptured()
        m.backOnLoginPage()
        m.loggedInPageFinished(now: t0)
        #expect(m.phase == .captured)
    }

    @Test func retryRestartsFetchTimer() {
        var m = atSigningIn()
        m.loggedInPageFinished(now: t0)
        m.tick(now: t0.addingTimeInterval(15))
        let t1 = t0.addingTimeInterval(20)
        m.retryRequested(now: t1)
        #expect(m.phase == .fetching(since: t1))
        m.tick(now: t1.addingTimeInterval(14))
        #expect(m.phase == .fetching(since: t1))
    }

    @Test func retryIgnoredOutsideTimeout() {
        var m = atSigningIn()
        m.retryRequested(now: t0)
        #expect(m.phase == .signingIn)
    }
}
