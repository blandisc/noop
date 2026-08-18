import XCTest
import Foundation
@testable import StrandAnalytics

final class TrainingRegulationTests: XCTestCase {

    // MARK: - Honest gate (no signal → nil, UI hides the band)

    func testNilWhenBothInputsNil() {
        XCTAssertNil(TrainingRegulation.suggest(recovery: nil, recoveryZ: nil))
    }

    // MARK: - By z (preferred path)

    func testZHighDialsUp() {
        let s = TrainingRegulation.suggest(recovery: nil, recoveryZ: 0.6)
        XCTAssertEqual(s?.adjustment, .dialUp)
        XCTAssertEqual(s?.reason, .recoveryHigh)
    }

    func testZLowDialsBack() {
        let s = TrainingRegulation.suggest(recovery: nil, recoveryZ: -0.6)
        XCTAssertEqual(s?.adjustment, .dialBack)
        XCTAssertEqual(s?.reason, .recoveryLow)
    }

    func testZNeutralHolds() {
        let s = TrainingRegulation.suggest(recovery: nil, recoveryZ: 0.0)
        XCTAssertEqual(s?.adjustment, .hold)
        XCTAssertEqual(s?.reason, .withinNormal)
    }

    func testZBoundaries() {
        // z == +zHigh → dial up (inclusive); z == -zLow → dial back (inclusive).
        XCTAssertEqual(TrainingRegulation.suggest(recovery: nil, recoveryZ: TrainingRegulation.zHigh)?.adjustment, .dialUp)
        XCTAssertEqual(TrainingRegulation.suggest(recovery: nil, recoveryZ: -TrainingRegulation.zLow)?.adjustment, .dialBack)
        // Just inside the band → hold.
        XCTAssertEqual(TrainingRegulation.suggest(recovery: nil, recoveryZ: 0.49)?.adjustment, .hold)
        XCTAssertEqual(TrainingRegulation.suggest(recovery: nil, recoveryZ: -0.49)?.adjustment, .hold)
    }

    // MARK: - By score (fallback when no z)

    func testScoreHighDialsUp() {
        XCTAssertEqual(TrainingRegulation.suggest(recovery: 80)?.adjustment, .dialUp)
    }

    func testScoreLowDialsBack() {
        XCTAssertEqual(TrainingRegulation.suggest(recovery: 20)?.adjustment, .dialBack)
    }

    func testScoreMidHolds() {
        XCTAssertEqual(TrainingRegulation.suggest(recovery: 50)?.adjustment, .hold)
    }

    func testScoreBoundaries() {
        // score == greenCut (67) → dial up (inclusive).
        XCTAssertEqual(TrainingRegulation.suggest(recovery: TrainingRegulation.greenCut)?.adjustment, .dialUp)
        // score == redCut (34) → hold (redCut is the exclusive lower bound of the hold band).
        XCTAssertEqual(TrainingRegulation.suggest(recovery: TrainingRegulation.redCut)?.adjustment, .hold)
        // just below redCut → dial back.
        XCTAssertEqual(TrainingRegulation.suggest(recovery: TrainingRegulation.redCut - 0.1)?.adjustment, .dialBack)
    }

    // MARK: - Precedence & invariants

    func testZWinsOverScore() {
        // High score but a low z → the z drives the suggestion.
        let s = TrainingRegulation.suggest(recovery: 90, recoveryZ: -1.0)
        XCTAssertEqual(s?.adjustment, .dialBack)
    }

    func testAlwaysAdvisory() {
        XCTAssertTrue(TrainingRegulation.suggest(recovery: 80)!.isAdvisory)
        XCTAssertTrue(TrainingRegulation.suggest(recovery: nil, recoveryZ: -2.0)!.isAdvisory)
    }

    // MARK: - Light alternative (FER-532) — the planner's «Sugerencia» row

    // MARK: - The systemic gate (FER-91 · E10 «Tu cuerpo») — regression

    /// The bug the code comment at `gatesTraining` documents, pinned so it can't come back: the
    /// muscle map used to read `!allowsRaise` as its gate, which is TRUE for `.lighter` too, and
    /// ended up shouting «hoy toca descanso» on a morning whose own bullet said «hoy ve leve» ten
    /// points below — a second oracle, in a different tone. Only `.recover` may close the screen.
    func testOnlyRecoverGatesTraining() {
        XCTAssertTrue(TrainingRegulation.gatesTraining(.recover))
        for advice in allAdvice where advice != .recover {
            XCTAssertFalse(TrainingRegulation.gatesTraining(advice),
                           "\(advice) must NOT gate «Tu cuerpo» — only .recover does")
        }
    }

    /// `.lighter` holds the WEIGHT (`allowsRaise` is false), never the training itself: the two
    /// predicates answer different questions, and the fix this test protects is exactly that a gate
    /// must not be derived from `!allowsRaise`.
    func testLighterHoldsTheRaiseButNeverGatesTraining() {
        XCTAssertFalse(TrainingRegulation.allowsRaise(.lighter))
        XCTAssertFalse(TrainingRegulation.gatesTraining(.lighter))
    }

    private let allAdvice: [TrainingRegulation.Advice] = [.planAsIs, .lighter, .recover, .silent, .pending]


}
