import XCTest
@testable import StrandAnalytics

final class RestReadinessTests: XCTestCase {

    // Helper: a resting HR of 60 → target = 60 + 20 (default margin) = 80.
    private let resting: Double = 60

    func testBpmToReadyCountdown() {
        // HR 110, target 80 → 30 bpm to ready; still resting (well over the band).
        let r = RestReadinessRule.evaluate(currentHR: 110, worn: true, restingHR: resting, elapsedS: 30)
        XCTAssertEqual(r.targetReadyHR, 80)
        XCTAssertEqual(r.bpmToReady, 30)
        XCTAssertEqual(r.state, .resting)
        XCTAssertFalse(r.ready)
    }

    func testReadyWhenHRRecoveredAndFloorMet() {
        // HR 78 ≤ target 80, floor (20 s) elapsed → ready, clamped to 0, reason hrRecovered.
        let r = RestReadinessRule.evaluate(currentHR: 78, worn: true, restingHR: resting, elapsedS: 30)
        XCTAssertEqual(r.bpmToReady, 0)
        XCTAssertTrue(r.ready)
        XCTAssertEqual(r.reason, .hrRecovered)
        XCTAssertEqual(r.state, .ready)
    }

    func testFloorBlocksEarlyReady() {
        // HR already at target but only 10 s elapsed (< 20 s floor) → NOT ready yet.
        let r = RestReadinessRule.evaluate(currentHR: 78, worn: true, restingHR: resting, elapsedS: 10)
        XCTAssertEqual(r.bpmToReady, 0)
        XCTAssertFalse(r.ready)
        XCTAssertEqual(r.state, .almostReady)
        XCTAssertEqual(r.reason, .notReady)
    }

    func testCeilingReleasesRegardlessOfHR() {
        // HR still high (140) but ceiling (180 s) reached → released, reason ceiling,
        // and it keeps reporting the honest gap (140 − 80 = 60).
        let r = RestReadinessRule.evaluate(currentHR: 140, worn: true, restingHR: resting, elapsedS: 180)
        XCTAssertTrue(r.ready)
        XCTAssertEqual(r.reason, .ceiling)
        XCTAssertEqual(r.state, .ready)
        XCTAssertEqual(r.bpmToReady, 60)
    }

    func testHonestyBand() {
        // HR 84, target 80 → gap 4 ≤ band (5) → almostReady, not ready.
        let r = RestReadinessRule.evaluate(currentHR: 84, worn: true, restingHR: resting, elapsedS: 60)
        XCTAssertEqual(r.bpmToReady, 4)
        XCTAssertEqual(r.state, .almostReady)
        XCTAssertFalse(r.ready)
    }

    func testNoSignalFallsToTimer() {
        // No live HR → no number, no color; the fixed timer still releases at the ceiling.
        let resting2: Double = 60
        let early = RestReadinessRule.evaluate(currentHR: nil, worn: true, restingHR: resting2, elapsedS: 60)
        XCTAssertNil(early.bpmToReady)
        XCTAssertNil(early.targetReadyHR)
        XCTAssertEqual(early.state, .noSignal)
        XCTAssertEqual(early.reason, .noSignal)
        XCTAssertFalse(early.ready)

        let late = RestReadinessRule.evaluate(currentHR: nil, worn: true, restingHR: resting2, elapsedS: 180)
        XCTAssertTrue(late.ready)
        XCTAssertEqual(late.state, .noSignal)
    }

    func testNotWornForcesNoSignal() {
        // A stale HR while the strap is off the wrist must not drive readiness.
        let r = RestReadinessRule.evaluate(currentHR: 70, worn: false, restingHR: resting, elapsedS: 60)
        XCTAssertNil(r.bpmToReady)
        XCTAssertEqual(r.state, .noSignal)
        XCTAssertFalse(r.ready)
    }

    func testInclusiveBoundaries() {
        // Band is inclusive (gap <= bandBPM): gap exactly 5 → almostReady, not ready.
        let band = RestReadinessRule.evaluate(currentHR: 85, worn: true, restingHR: resting, elapsedS: 60)
        XCTAssertEqual(band.bpmToReady, 5)
        XCTAssertEqual(band.state, .almostReady)
        XCTAssertFalse(band.ready)

        // Floor is inclusive (elapsed >= minRestS): at exactly 20 s with HR recovered → ready.
        let floor = RestReadinessRule.evaluate(currentHR: 78, worn: true, restingHR: resting, elapsedS: 20)
        XCTAssertTrue(floor.ready)
        XCTAssertEqual(floor.reason, .hrRecovered)

        // Ceiling is inclusive (elapsed >= maxRestS): at exactly 180 s → released by clock.
        let ceil = RestReadinessRule.evaluate(currentHR: 120, worn: true, restingHR: resting, elapsedS: 180)
        XCTAssertTrue(ceil.ready)
        XCTAssertEqual(ceil.reason, .ceiling)
    }

    func testMissingBaselineForcesNoSignal() {
        // No trustworthy resting baseline AND no explicit target → the rule won't invent a target.
        let r = RestReadinessRule.evaluate(currentHR: 90, worn: true, restingHR: nil, elapsedS: 60)
        XCTAssertNil(r.bpmToReady)
        XCTAssertNil(r.targetReadyHR)
        XCTAssertEqual(r.state, .noSignal)
        XCTAssertFalse(r.ready)
    }

    // FER-506: an explicit target (peakDrop/fixedBpm) is honored even with no resting baseline —
    // those modes don't depend on the nightly RHR.
    func testExplicitTargetWithoutBaselineIsHonored() {
        let r = RestReadinessRule.evaluate(currentHR: 130, worn: true, restingHR: nil,
                                           elapsedS: 60, targetHR: 110)
        XCTAssertEqual(r.bpmToReady, 20)
        XCTAssertEqual(r.targetReadyHR, 110)
        XCTAssertEqual(r.state, .resting)
        XCTAssertFalse(r.ready)
    }

    func testRecoveredWithExplicitTargetNoBaseline() {
        let r = RestReadinessRule.evaluate(currentHR: 108, worn: true, restingHR: nil,
                                           elapsedS: 60, targetHR: 110)
        XCTAssertEqual(r.bpmToReady, 0)
        XCTAssertTrue(r.ready)            // at/under target and the floor (20s) elapsed
        XCTAssertEqual(r.reason, .hrRecovered)
    }

    // FER-758: the pulse is already well below target when the rest starts (e.g. HR 60 with resting 78 →
    // target 98). Before the 20s floor it must NOT be ready; at the floor it flips to ready/hrRecovered —
    // that transition is exactly what lets the session end the rest early and buzz the watch.
    func testAlreadyBelowTargetReadyOnlyAfterFloor() {
        let restingHigh: Double = 78   // target = 78 + 20 (default margin) = 98
        let before = RestReadinessRule.evaluate(currentHR: 60, worn: true, restingHR: restingHigh, elapsedS: 10)
        XCTAssertEqual(before.targetReadyHR, 98)
        XCTAssertEqual(before.bpmToReady, 0)
        XCTAssertFalse(before.ready)                 // floor not met yet
        XCTAssertEqual(before.state, .almostReady)

        let atFloor = RestReadinessRule.evaluate(currentHR: 60, worn: true, restingHR: restingHigh, elapsedS: 20)
        XCTAssertTrue(atFloor.ready)
        XCTAssertEqual(atFloor.reason, .hrRecovered)
        XCTAssertEqual(atFloor.state, .ready)
    }
}
