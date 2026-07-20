import XCTest
@testable import StrandAnalytics

/// FER-676 — the three per-score confidence derivers + the H9 staging guard.
/// Input→output cases mirror the thresholds fixed in the requirement (via /cso).
final class ScoreConfidenceTests: XCTestCase {

    // MARK: - lowered ladder (pre-existing, guarded here)

    func testLoweredLadder() {
        XCTAssertEqual(ScoreConfidence.solid.lowered, .building)
        XCTAssertEqual(ScoreConfidence.building.lowered, .calibrating)
        XCTAssertEqual(ScoreConfidence.calibrating.lowered, .calibrating)
    }

    // MARK: - charge (Recovery)

    func testChargeThresholds() {
        XCTAssertEqual(ScoreConfidence.charge(hrvBaselineNights: 14), .solid)
        XCTAssertEqual(ScoreConfidence.charge(hrvBaselineNights: 20), .solid)
        XCTAssertEqual(ScoreConfidence.charge(hrvBaselineNights: 13), .building)
        XCTAssertEqual(ScoreConfidence.charge(hrvBaselineNights: 7), .building)
        XCTAssertEqual(ScoreConfidence.charge(hrvBaselineNights: 6), .calibrating)
        XCTAssertEqual(ScoreConfidence.charge(hrvBaselineNights: 0), .calibrating)
    }

    // MARK: - effort (Strain)

    /// A day of samples every `stepS` seconds from `startS` for `count` samples.
    private func hrSeconds(startS: Int, stepS: Int, count: Int) -> [Int] {
        (0..<count).map { startS + $0 * stepS }
    }

    func testEffortCalibratingWhenNotEnoughData() {
        XCTAssertEqual(ScoreConfidence.effort(hasEnoughData: false,
                                              hrSampleSecondsSorted: []), .calibrating)
    }

    func testEffortSolidFullDayCoverage() {
        // 08:00→20:00, one sample every 30 s, no gaps: full coverage, 12 h span.
        let start = 8 * 3600
        let ts = hrSeconds(startS: start, stepS: 30, count: 12 * 120 + 1)
        XCTAssertEqual(ScoreConfidence.effort(hasEnoughData: true, hrSampleSecondsSorted: ts), .solid)
    }

    func testEffortBuildingWhenSpanTooShort() {
        // A single 20-min gym block: high local coverage but span < 4 h → building.
        let start = 18 * 3600
        let ts = hrSeconds(startS: start, stepS: 30, count: 41) // 20 min
        XCTAssertEqual(ScoreConfidence.effort(hasEnoughData: true, hrSampleSecondsSorted: ts), .building)
    }

    func testEffortBuildingWhenSparseCoverage() {
        // Span is a full 12 h but only two clusters (morning + evening): coverage < 0.70.
        var ts = hrSeconds(startS: 8 * 3600, stepS: 30, count: 60)      // 30 min a.m.
        ts += hrSeconds(startS: 20 * 3600 - 1800, stepS: 30, count: 61) // 30 min p.m., ends 20:00
        XCTAssertEqual(ScoreConfidence.effort(hasEnoughData: true, hrSampleSecondsSorted: ts), .building)
    }

    func testHrCoverageFractionFullAndHalf() {
        // 4 windows of 1800 s, all occupied → 1.0.
        let full = hrSeconds(startS: 0, stepS: 300, count: 4 * 6 + 1) // through 2h
        XCTAssertEqual(ScoreConfidence.hrCoverageFraction(secondsSorted: full, windowSeconds: 1800),
                       1.0, accuracy: 1e-9)
        // Samples only in window 0 and window 3 of a 4-window span → 2/4.
        let sparse: [Int] = [0, 60, 120, 3 * 1800, 3 * 1800 + 60]
        XCTAssertEqual(ScoreConfidence.hrCoverageFraction(secondsSorted: sparse, windowSeconds: 1800),
                       0.5, accuracy: 1e-9)
    }

    // MARK: - rest (Sleep)

    func testRestSolid() {
        XCTAssertEqual(ScoreConfidence.rest(totalSleepMin: 420, deepMin: 75, remMin: 95), .solid)
    }

    func testRestBuildingWhenStagesUnresolved() {
        XCTAssertEqual(ScoreConfidence.rest(totalSleepMin: 390, deepMin: nil, remMin: nil), .building)
    }

    func testRestBuildingWhenBelowSolidDuration() {
        // ≥180 but <240, even with stages resolved → still building.
        XCTAssertEqual(ScoreConfidence.rest(totalSleepMin: 200, deepMin: 40, remMin: 50), .building)
    }

    func testRestCalibratingWhenNapOrMissing() {
        XCTAssertEqual(ScoreConfidence.rest(totalSleepMin: 95, deepMin: 10, remMin: 10), .calibrating)
        XCTAssertEqual(ScoreConfidence.rest(totalSleepMin: nil, deepMin: nil, remMin: nil), .calibrating)
    }

    // MARK: - H9 (suspicious staging)

    func testH9TrueWhenHighEfficiencyNoStages() {
        XCTAssertTrue(ScoreConfidence.suspiciousStaging(efficiency: 0.91, deepMin: 0, remMin: 0))
        // nil stages at high efficiency also trip.
        XCTAssertTrue(ScoreConfidence.suspiciousStaging(efficiency: 0.86, deepMin: nil, remMin: nil))
    }

    func testH9FalseWhenLowEfficiency() {
        // A genuinely fragmented night (low efficiency) is NOT a staging failure.
        XCTAssertFalse(ScoreConfidence.suspiciousStaging(efficiency: 0.72, deepMin: 0, remMin: 0))
    }

    func testH9FalseWhenStagesPresent() {
        XCTAssertFalse(ScoreConfidence.suspiciousStaging(efficiency: 0.90, deepMin: 60, remMin: 80))
    }

    /// The intended composition: a night the stager mis-scored (deep+REM = 0 at high
    /// efficiency) looks `solid` to `rest` on duration+resolved-stages alone; H9 catches
    /// the impossibility and lowers it one tier to `building`.
    func testH9LowersRestOneTier() {
        let base = ScoreConfidence.rest(totalSleepMin: 420, deepMin: 0, remMin: 0)
        XCTAssertEqual(base, .solid) // naive: stages "resolved" (non-nil) + long night
        let suspicious = ScoreConfidence.suspiciousStaging(efficiency: 0.92, deepMin: 0, remMin: 0)
        XCTAssertTrue(suspicious)
        XCTAssertEqual(suspicious ? base.lowered : base, .building)
    }
}
