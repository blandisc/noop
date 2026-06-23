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

    func testLightAlternativeLowIsSofter() {
        // Recovery below normal → a gentler option.
        XCTAssertEqual(TrainingRegulation.lightAlternative(recovery: 20), .softer)
        XCTAssertEqual(TrainingRegulation.lightAlternative(recovery: nil, recoveryZ: -0.6), .softer)
    }

    func testLightAlternativeHighIsOptionalLight() {
        // Recovery above normal → an optional light add-on.
        XCTAssertEqual(TrainingRegulation.lightAlternative(recovery: 80), .optionalLight)
        XCTAssertEqual(TrainingRegulation.lightAlternative(recovery: nil, recoveryZ: 0.6), .optionalLight)
    }

    func testLightAlternativeMidIsNil() {
        // Within the normal band there is nothing to suggest → the row hides.
        XCTAssertNil(TrainingRegulation.lightAlternative(recovery: 50))
        XCTAssertNil(TrainingRegulation.lightAlternative(recovery: nil, recoveryZ: 0.0))
    }

    func testLightAlternativeNoSignalIsNil() {
        // No recovery signal → no row.
        XCTAssertNil(TrainingRegulation.lightAlternative(recovery: nil, recoveryZ: nil))
        XCTAssertNil(TrainingRegulation.lightAlternative(for: nil))
    }

    func testLightAlternativeZWinsOverScore() {
        // High score but a low z → the z drives it → softer.
        XCTAssertEqual(TrainingRegulation.lightAlternative(recovery: 90, recoveryZ: -1.0), .softer)
    }
}
