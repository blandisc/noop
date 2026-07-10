import XCTest
@testable import Cenit

// BaselineRecalibrationTests.swift — «Recalibrar recuperación» (FER-677).
//
// The one-level undo lives in ProfileStore (the engine-side epoch cut is pinned by
// StrandAnalytics' BaselinesTests/AppleRecoveryEstimatorTests). Here we pin that recalibrate
// stashes exactly one previous epoch and undo restores it — no stack, no data loss.

@MainActor
final class BaselineRecalibrationTests: XCTestCase {

    /// A fresh store with the recalibration keys cleared, so the test doesn't read a stale device value.
    private func freshProfile() -> ProfileStore {
        let d = UserDefaults.standard
        d.removeObject(forKey: "profile.baselineEpoch")
        d.removeObject(forKey: "profile.previousBaselineEpoch")
        return ProfileStore()
    }

    func testDefaultHasNoEpoch() {
        let p = freshProfile()
        XCTAssertEqual(p.baselineEpoch, "")
        XCTAssertNil(p.baselineEpochOrNil)
        XCTAssertFalse(p.canUndoRecalibration)
    }

    func testRecalibrateSetsEpochAndEnablesUndo() {
        let p = freshProfile()
        p.recalibrate(to: "2026-07-10")
        XCTAssertEqual(p.baselineEpoch, "2026-07-10")
        XCTAssertEqual(p.baselineEpochOrNil, "2026-07-10")
        XCTAssertTrue(p.canUndoRecalibration)
    }

    func testUndoRestoresPreviousEpochOneLevel() {
        let p = freshProfile()
        p.recalibrate(to: "2026-06-01")     // first recalibration (previous = "")
        p.recalibrate(to: "2026-07-10")     // second — previous stashes "2026-06-01"
        XCTAssertEqual(p.baselineEpoch, "2026-07-10")
        XCTAssertEqual(p.previousBaselineEpoch, "2026-06-01")

        p.undoRecalibration()               // restores the one stashed level
        XCTAssertEqual(p.baselineEpoch, "2026-06-01")
        XCTAssertEqual(p.previousBaselineEpoch, "")
    }

    func testUndoFromFirstRecalibrationReturnsToNoCut() {
        let p = freshProfile()
        p.recalibrate(to: "2026-07-10")     // previous = "" (there was no cut before)
        p.undoRecalibration()
        XCTAssertEqual(p.baselineEpoch, "")
        XCTAssertNil(p.baselineEpochOrNil)
        XCTAssertFalse(p.canUndoRecalibration)
    }
}
