import XCTest
@testable import StrandAnalytics
import BiometricStreams

final class AppleLoadEstimatorTests: XCTestCase {

    /// Dense 1 Hz series long enough to clear `StrainScorer.hasEnoughData` (minReadings = 600).
    private func denseWorkoutHR(bpm: Int = 140, n: Int = 700, start: Int = 1_700_000_000) -> [HRSample] {
        (0..<n).map { HRSample(ts: start + $0, bpm: bpm) }
    }

    func testQuietDayIsRest() {
        let a = AppleLoadEstimator.DayActivity(
            workoutHR: [], steps: 2000, activeKcal: 100, hasWorkout: false)
        let load = AppleLoadEstimator.classify(a, maxHR: 190, restingHR: 60)
        XCTAssertEqual(load, .rest)
    }

    func testActiveUnregisteredDayIsMissing() {
        let a = AppleLoadEstimator.DayActivity(
            workoutHR: [], steps: 12_000, activeKcal: 500, hasWorkout: false)
        let load = AppleLoadEstimator.classify(a, maxHR: 190, restingHR: 60)
        XCTAssertEqual(load, .missing)
    }

    func testWorkoutHRLoadEqualsStrainScorer() {
        let hr = denseWorkoutHR()
        let maxHR: Double = 190
        let restingHR: Double = 60
        let sex = "male"
        let expected = StrainScorer.strain(hr, maxHR: maxHR, restingHR: restingHR, sex: sex)
        XCTAssertNotNil(expected, "synthetic series must clear hasEnoughData")

        let a = AppleLoadEstimator.DayActivity(
            workoutHR: hr, steps: 2000, activeKcal: 100, hasWorkout: true)
        let load = AppleLoadEstimator.classify(a, maxHR: maxHR, restingHR: restingHR, sex: sex)
        guard case .load(let score) = load else {
            return XCTFail("expected .load, got \(load)")
        }
        XCTAssertEqual(score, expected!, accuracy: 1e-12,
                       "load must equal StrainScorer.strain with the same arguments")
    }

    /// Known workout with no/too-little HR must stay `.missing` even when steps/kcal look low —
    /// never fabricate a rest day for a strength session that didn't log HR.
    func testKnownWorkoutWithoutHRIsMissingNotRest() {
        let a = AppleLoadEstimator.DayActivity(
            workoutHR: [], steps: 500, activeKcal: 50, hasWorkout: true)
        let load = AppleLoadEstimator.classify(a, maxHR: 190, restingHR: 60)
        XCTAssertEqual(load, .missing)
        XCTAssertNotEqual(load, .rest)
    }

    /// Rest thresholds are strict `<`, not `<=` — a day exactly at the steps or kcal ceiling is not rest.
    func testRestThresholdIsStrictLessThan() {
        let cfg = AppleLoadEstimator.RestThresholds.standard
        // Exactly at stepsRestMax, kcal well below → not rest (steps not < max).
        let atSteps = AppleLoadEstimator.DayActivity(
            workoutHR: [], steps: cfg.stepsRestMax, activeKcal: 100, hasWorkout: false)
        XCTAssertEqual(AppleLoadEstimator.classify(atSteps, maxHR: 190, restingHR: 60, cfg: cfg),
                       .missing)

        // Exactly at kcalRestMax, steps well below → not rest (kcal not < max).
        let atKcal = AppleLoadEstimator.DayActivity(
            workoutHR: [], steps: 1000, activeKcal: cfg.kcalRestMax, hasWorkout: false)
        XCTAssertEqual(AppleLoadEstimator.classify(atKcal, maxHR: 190, restingHR: 60, cfg: cfg),
                       .missing)

        // Just under both → rest.
        let under = AppleLoadEstimator.DayActivity(
            workoutHR: [], steps: cfg.stepsRestMax - 1, activeKcal: cfg.kcalRestMax - 1,
            hasWorkout: false)
        XCTAssertEqual(AppleLoadEstimator.classify(under, maxHR: 190, restingHR: 60, cfg: cfg),
                       .rest)
    }

    // MARK: - isCompletedDay (persist strain only for finished days)

    func testIsCompletedDayPastIsTrue() {
        XCTAssertTrue(AppleLoadEstimator.isCompletedDay("2026-07-20", today: "2026-07-21"))
    }

    func testIsCompletedDayTodayIsFalse() {
        XCTAssertFalse(AppleLoadEstimator.isCompletedDay("2026-07-21", today: "2026-07-21"))
    }

    /// Future day keys should not occur in practice; the pure compare must still be correct.
    func testIsCompletedDayFutureIsFalse() {
        XCTAssertFalse(AppleLoadEstimator.isCompletedDay("2026-07-22", today: "2026-07-21"))
    }

    /// yyyy-MM-dd string order matches chronological order across month/year boundaries.
    func testIsCompletedDayAcrossMonthBoundary() {
        XCTAssertTrue(AppleLoadEstimator.isCompletedDay("2026-06-30", today: "2026-07-01"))
        XCTAssertTrue(AppleLoadEstimator.isCompletedDay("2025-12-31", today: "2026-01-01"))
    }

    // MARK: - both activity signals nil → missing (not rest)

    /// When Apple Health has neither steps nor active kcal and there is no workout, we cannot
    /// tell quiet rest from a data gap — classify as `.missing`, never fabricate `.rest` via ?? 0.
    func testBothActivitySignalsNilWithoutWorkoutIsMissing() {
        let a = AppleLoadEstimator.DayActivity(
            workoutHR: [], steps: nil, activeKcal: nil, hasWorkout: false)
        XCTAssertEqual(AppleLoadEstimator.classify(a, maxHR: 190, restingHR: 60), .missing)
    }

    /// One signal present, the other nil: still uses `?? 0` for the absent one (prior behaviour).
    func testOneActivitySignalPresentStillUsesZeroForAbsent() {
        let cfg = AppleLoadEstimator.RestThresholds.standard
        // steps low, kcal nil → treated as kcal=0 → rest
        let stepsOnlyRest = AppleLoadEstimator.DayActivity(
            workoutHR: [], steps: 1000, activeKcal: nil, hasWorkout: false)
        XCTAssertEqual(AppleLoadEstimator.classify(stepsOnlyRest, maxHR: 190, restingHR: 60, cfg: cfg),
                       .rest)
        // steps nil, kcal low → treated as steps=0 → rest
        let kcalOnlyRest = AppleLoadEstimator.DayActivity(
            workoutHR: [], steps: nil, activeKcal: 50, hasWorkout: false)
        XCTAssertEqual(AppleLoadEstimator.classify(kcalOnlyRest, maxHR: 190, restingHR: 60, cfg: cfg),
                       .rest)
        // steps high, kcal nil → treated as kcal=0 but steps not < max → missing
        let stepsOnlyActive = AppleLoadEstimator.DayActivity(
            workoutHR: [], steps: 12_000, activeKcal: nil, hasWorkout: false)
        XCTAssertEqual(AppleLoadEstimator.classify(stepsOnlyActive, maxHR: 190, restingHR: 60, cfg: cfg),
                       .missing)
    }
}
