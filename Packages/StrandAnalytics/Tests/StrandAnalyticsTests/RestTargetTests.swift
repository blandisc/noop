import XCTest
@testable import StrandAnalytics

// RestTarget (FER-495): the per-exercise HR rest target, resolved from the chosen reference. Pure
// math; nil = "can't compute honestly" (the caller falls back to FER-348 / the fixed timer).
final class RestTargetTests: XCTestCase {

    func testPeakDrop() {
        // 30% drop from a 170 peak → 119 bpm; resting floor (60) doesn't bind.
        let t = RestTarget.resolve(reference: .peakDrop, value: 0.30, peakHR: 170, restingHR: 60, maxHR: nil)
        XCTAssertEqual(t, 119)
    }

    func testPeakDropFlooredAtResting() {
        // A big drop (50% of 80 = 40) would land below resting (60) → floored to resting.
        let t = RestTarget.resolve(reference: .peakDrop, value: 0.50, peakHR: 80, restingHR: 60, maxHR: nil)
        XCTAssertEqual(t, 60)
    }

    func testPeakDropClampsFraction() {
        // value > 0.9 clamps to 0.9 → 170·0.1 = 17, floored to resting 60.
        let t = RestTarget.resolve(reference: .peakDrop, value: 1.5, peakHR: 170, restingHR: 60, maxHR: nil)
        XCTAssertEqual(t, 60)
    }

    func testPeakDropNeedsPeak() {
        XCTAssertNil(RestTarget.resolve(reference: .peakDrop, value: 0.30, peakHR: nil, restingHR: 60, maxHR: 190))
    }

    func testKarvonenReserve() {
        // Karvonen 1957: 50 + 0.40·(190 − 50) = 106.
        let t = RestTarget.resolve(reference: .karvonenReserve, value: 0.40, peakHR: nil, restingHR: 50, maxHR: 190)
        XCTAssertEqual(t, 106)
    }

    func testKarvonenNeedsBothProfileValues() {
        XCTAssertNil(RestTarget.resolve(reference: .karvonenReserve, value: 0.6, peakHR: nil, restingHR: nil, maxHR: 190))
        XCTAssertNil(RestTarget.resolve(reference: .karvonenReserve, value: 0.6, peakHR: nil, restingHR: 50, maxHR: nil))
    }

    func testKarvonenRejectsInvalidReserve() {
        // maxHR ≤ restingHR → no valid reserve.
        XCTAssertNil(RestTarget.resolve(reference: .karvonenReserve, value: 0.6, peakHR: nil, restingHR: 190, maxHR: 180))
    }

    func testFixedBpm() {
        XCTAssertEqual(RestTarget.resolve(reference: .fixedBpm, value: 110, peakHR: nil, restingHR: nil, maxHR: nil), 110)
        XCTAssertNil(RestTarget.resolve(reference: .fixedBpm, value: 0, peakHR: nil, restingHR: nil, maxHR: nil))
    }

    func testRestingMarginDelegatesToEvaluate() {
        // value 0 is FER-348's default path — resolve returns nil so evaluate() owns the resting+20 target.
        XCTAssertNil(RestTarget.resolve(reference: .restingMargin, value: 0, peakHR: 170, restingHR: 60, maxHR: 190))
    }

    // FER-759: a custom margin (bpm) pulls the target down toward resting — target = round(resting) + margin.
    func testRestingMarginCustomValue() {
        // resting 78, margin +15 → 93 bpm (below the +20 default of 98), letting the user lower the target.
        XCTAssertEqual(RestTarget.resolve(reference: .restingMargin, value: 15, peakHR: nil, restingHR: 78, maxHR: nil), 93)
        XCTAssertEqual(RestTarget.resolve(reference: .restingMargin, value: 10, peakHR: nil, restingHR: 60, maxHR: nil), 70)
        // No resting baseline → can't compute honestly → nil (falls back to the fixed timer).
        XCTAssertNil(RestTarget.resolve(reference: .restingMargin, value: 15, peakHR: nil, restingHR: nil, maxHR: nil))
    }

    // The target override threads through evaluate(): an explicit target is used instead of resting+margin.
    func testEvaluateUsesExplicitTarget() {
        let r = RestReadinessRule.evaluate(currentHR: 122, worn: true, restingHR: 60, elapsedS: 30, targetHR: 120)
        XCTAssertEqual(r.targetReadyHR, 120)            // not 60+20=80
        XCTAssertEqual(r.bpmToReady, 2)
        XCTAssertEqual(r.state, .almostReady)
    }

    // Regression: targetHR == nil reproduces FER-348 exactly (resting+margin).
    func testEvaluateNilTargetIsFER348() {
        let a = RestReadinessRule.evaluate(currentHR: 110, worn: true, restingHR: 60, elapsedS: 30)
        let b = RestReadinessRule.evaluate(currentHR: 110, worn: true, restingHR: 60, elapsedS: 30, targetHR: nil)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.targetReadyHR, 80)
    }
}
