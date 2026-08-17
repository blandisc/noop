import XCTest
@testable import StrandAnalytics

/// FER-82 — «un solo oráculo»: Entrenar reads the SAME verdict Hoy shows, and one pure mapping turns
/// it into training advice. These tests pin the contract that makes the app stop contradicting itself:
/// the day the verdict is anything but clean, an earned raise waits.
final class SingleOracleTests: XCTestCase {

    // MARK: - The mapping

    func testVerdictMapsToAdvice() {
        XCTAssertEqual(TrainingRegulation.advice(for: .full), .planAsIs)
        XCTAssertEqual(TrainingRegulation.advice(for: .caution), .lighter)
        XCTAssertEqual(TrainingRegulation.advice(for: .easy), .recover)
        XCTAssertEqual(TrainingRegulation.advice(for: .lowSignal), .silent)
        XCTAssertEqual(TrainingRegulation.advice(for: nil), .silent)
    }

    /// The rule the whole epic hangs on: only a clean read lets the weight go up.
    func testOnlyCleanReadAllowsARaise() {
        XCTAssertTrue(TrainingRegulation.allowsRaise(verdict: .full))
        XCTAssertFalse(TrainingRegulation.allowsRaise(verdict: .caution))
        XCTAssertFalse(TrainingRegulation.allowsRaise(verdict: .easy))
        XCTAssertFalse(TrainingRegulation.allowsRaise(verdict: .lowSignal))
        XCTAssertFalse(TrainingRegulation.allowsRaise(verdict: nil))
    }

    /// There is no «push harder» advice: `Preparedness.full` already includes better-than-normal, so
    /// the honest mapping never tells anyone to exceed the plan.
    func testNoVerdictEverSuggestsPushingHarder() {
        for verdict: Preparedness.Verdict? in [.full, .caution, .easy, .lowSignal, nil] {
            XCTAssertNotEqual(TrainingRegulation.suggest(verdict: verdict)?.adjustment, .dialUp,
                              "verdict \(String(describing: verdict)) must never suggest dialUp")
        }
    }

    func testSilentVerdictsSayNothing() {
        XCTAssertNil(TrainingRegulation.suggest(verdict: .lowSignal))
        XCTAssertNil(TrainingRegulation.suggest(verdict: nil))
        XCTAssertNil(TrainingRegulation.lightAlternative(verdict: .lowSignal))
        XCTAssertNil(TrainingRegulation.lightAlternative(verdict: nil))
    }

    /// Only «Recupera» offers the gentler session. Within range there is nothing to suggest, and
    /// «Hoy ve leve» keeps the plan (it only blocks the raise).
    func testOnlyRecoverOffersTheGentlerOption() {
        XCTAssertNil(TrainingRegulation.lightAlternative(verdict: .full))
        XCTAssertNil(TrainingRegulation.lightAlternative(verdict: .caution))
        XCTAssertEqual(TrainingRegulation.lightAlternative(verdict: .easy), .softer)
    }

    // MARK: - The raise actually defers

    /// Two sessions that met the goal → the raise is earned. Whether it goes through depends on today.
    private func earnedInput(deferRaise: Bool,
                             recoveryReason: TrainingRegulation.Reason? = nil)
        -> ProgressionMath.ProgressionInput {
        let met = ProgressionMath.PastSession(workingKg: 80, workSetReps: [8, 8, 8])
        return ProgressionMath.ProgressionInput(
            history: [met, met], targetReps: 8, targetSets: 3,
            sessionsToAdvance: 2, incrementKg: 2.5,
            recoveryReason: recoveryReason, deferRaise: deferRaise)
    }

    func testEarnedRaiseGoesThroughOnACleanDay() {
        let state = ProgressionMath.classify(earnedInput(deferRaise: false))
        guard case .readyToAdvance(let kg) = state else {
            return XCTFail("expected readyToAdvance, got \(state)")
        }
        XCTAssertEqual(kg, 82.5, accuracy: 0.0001)
    }

    /// «Hoy ve leve» and «Recupera» both defer: the weight is kept for a better day, not lost.
    func testEarnedRaiseDefersWhenTheVerdictSaysSo() {
        for verdict: Preparedness.Verdict in [.caution, .easy] {
            let defer_ = !TrainingRegulation.allowsRaise(verdict: verdict)
            let state = ProgressionMath.classify(earnedInput(deferRaise: defer_))
            guard case .deferred(let kg) = state else {
                return XCTFail("verdict \(verdict) should defer, got \(state)")
            }
            XCTAssertEqual(kg, 82.5, accuracy: 0.0001, "the earned weight is preserved, not dropped")
        }
    }

    /// Retro-compatibility: the legacy score-driven path keeps its exact behaviour when the new flag
    /// is left at its default.
    func testLegacyRecoveryPathIsUnchanged() {
        let deferredByScore = ProgressionMath.classify(earnedInput(deferRaise: false,
                                                                   recoveryReason: .recoveryLow))
        guard case .deferred = deferredByScore else {
            return XCTFail("recoveryLow must still defer, got \(deferredByScore)")
        }
        let clean = ProgressionMath.classify(earnedInput(deferRaise: false,
                                                         recoveryReason: .withinNormal))
        guard case .readyToAdvance = clean else {
            return XCTFail("withinNormal must still advance, got \(clean)")
        }
    }

    /// The score-driven `suggest` keeps working untouched: the new verdict entry is additive.
    func testScoreDrivenSuggestStillWorks() {
        XCTAssertEqual(TrainingRegulation.suggest(recovery: 80)?.adjustment, .dialUp)
        XCTAssertEqual(TrainingRegulation.suggest(recovery: 50)?.adjustment, .hold)
        XCTAssertEqual(TrainingRegulation.suggest(recovery: 20)?.adjustment, .dialBack)
        XCTAssertNil(TrainingRegulation.suggest(recovery: nil))
    }

    // MARK: - The rule the UI must honour

    /// The verifiable rule of FER-82, stated as a test: there is no verdict for which the app both
    /// advises easing off AND lets the weight go up. If a future change breaks this, it fails here
    /// before it reaches a screen.
    func testNeverAdvisesEasingWhileAllowingARaise() {
        for verdict: Preparedness.Verdict? in [.full, .caution, .easy, .lowSignal, nil] {
            let advice = TrainingRegulation.advice(for: verdict)
            let raises = TrainingRegulation.allowsRaise(advice)
            if advice != .planAsIs {
                XCTAssertFalse(raises,
                               "\(advice) must never allow a raise (verdict \(String(describing: verdict)))")
            }
        }
    }
}
