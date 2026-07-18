import XCTest
import BiometricStreams
@testable import StrandAnalytics

final class StepsEstimateEngineTests: XCTestCase {

    // MARK: motion intensity

    func testMotionIntensitySumsDeltas() {
        // Three samples: deltas of magnitude 0.3 then 0.4 → total 0.7.
        let grav = [
            GravitySample(ts: 0, x: 0, y: 0, z: 1),
            GravitySample(ts: 1, x: 0.3, y: 0, z: 1),   // Δ = 0.3
            GravitySample(ts: 2, x: 0.3, y: 0.4, z: 1), // Δ = 0.4
        ]
        XCTAssertEqual(StepsEstimateEngine.dayMotionIntensity(grav), 0.7, accuracy: 1e-9)
    }

    func testMotionIntensityEmptyAndSingle() {
        XCTAssertEqual(StepsEstimateEngine.dayMotionIntensity([]), 0)
        XCTAssertEqual(StepsEstimateEngine.dayMotionIntensity([GravitySample(ts: 0, x: 0, y: 0, z: 1)]), 0)
    }

    // MARK: calibration

    func testCalibrateFitsMedianRatio() {
        // steps/motion ratios: 100, 100, 110, 90, 100 → median 100.
        let pts = [(10.0, 1000.0), (20.0, 2000.0), (10.0, 1100.0), (10.0, 900.0), (10.0, 1000.0)]
            .map { StepsEstimateEngine.CalibrationPoint(motion: $0.0, steps: $0.1) }
        let cal = StepsEstimateEngine.calibrate(pts)
        XCTAssertNotNil(cal)
        XCTAssertEqual(cal!.coefficient, 100, accuracy: 1e-9)
        XCTAssertFalse(cal!.manual)
        XCTAssertEqual(cal!.sampleDays, 5)
        XCTAssertGreaterThan(cal!.confidence, 0)
    }

    func testCalibrateNilBelowMinDays() {
        let pts = [(10.0, 1000.0), (10.0, 1000.0)]   // only 2 < minCalibrationDays(3)
            .map { StepsEstimateEngine.CalibrationPoint(motion: $0.0, steps: $0.1) }
        XCTAssertNil(StepsEstimateEngine.calibrate(pts))
    }

    func testCalibrateSkipsNearStillAndZeroStepDays() {
        // Two near-still days (motion < minMotionForFit) + two zero-step days should NOT count toward the fit;
        // only the 3 real days remain, all ratio 100.
        let pts = [
            (0.2, 5000.0),   // below minMotionForFit → skipped
            (10.0, 0.0),     // zero steps → skipped
            (10.0, 1000.0), (20.0, 2000.0), (15.0, 1500.0),
        ].map { StepsEstimateEngine.CalibrationPoint(motion: $0.0, steps: $0.1) }
        let cal = StepsEstimateEngine.calibrate(pts)
        XCTAssertNotNil(cal)
        XCTAssertEqual(cal!.coefficient, 100, accuracy: 1e-9)
        XCTAssertEqual(cal!.sampleDays, 3)
    }

    func testCalibrateMotionWeightedHighActivityDayDrivesFit() {
        // Three near-still low-activity days all read ratio 50 (motion 1, steps 50); one busy day reads
        // ratio 100 (motion 100, steps 10000). The PLAIN median of [50,50,50,100] would be 50 — the low days
        // win by COUNT. The motion-weighted median lets the busy day's 100 units of motion outvote the 3 units
        // from the still days (half-mass 51.5 lands inside the busy day), so k = 100.
        let pts = [
            (1.0, 50.0), (1.0, 50.0), (1.0, 50.0),   // ratio 50, weight 1 each
            (100.0, 10000.0),                        // ratio 100, weight 100
        ].map { StepsEstimateEngine.CalibrationPoint(motion: $0.0, steps: $0.1) }
        let cal = StepsEstimateEngine.calibrate(pts)
        XCTAssertNotNil(cal)
        XCTAssertEqual(cal!.coefficient, 100, accuracy: 1e-9)   // weighted → busy day wins (plain median = 50)
        XCTAssertEqual(cal!.sampleDays, 4)
    }

    func testWeightedMedianReducesToPlainMedianAtEqualWeights() {
        // Equal weights must reproduce the old even-count midpoint average exactly (byte-identical fits).
        XCTAssertEqual(StepsEstimateEngine.weightedMedian([90, 100, 110, 130], weights: [5, 5, 5, 5]),
                       105, accuracy: 1e-9)                       // plain median = (100+110)/2
        XCTAssertEqual(StepsEstimateEngine.weightedMedian([3, 1, 2], weights: [7, 7, 7]),
                       2, accuracy: 1e-9)                         // odd count, order-independent
    }

    func testWeightedMedianFallsBackOnDegenerateWeights() {
        XCTAssertEqual(StepsEstimateEngine.weightedMedian([1, 2, 3], weights: []), 2, accuracy: 1e-9)
        XCTAssertEqual(StepsEstimateEngine.weightedMedian([1, 2, 3], weights: [0, 0, 0]), 2, accuracy: 1e-9)
        XCTAssertEqual(StepsEstimateEngine.weightedMedian([], weights: []), 0, accuracy: 1e-9)
    }

    func testManualOverrideWinsWithFullConfidence() {
        let cal = StepsEstimateEngine.calibrate([], manualOverride: 123)
        XCTAssertNotNil(cal)
        XCTAssertEqual(cal!.coefficient, 123)
        XCTAssertTrue(cal!.manual)
        XCTAssertEqual(cal!.confidence, 1.0)
    }

    func testTightFitMoreConfidentThanScattered() {
        let tight = (0..<14).map { _ in StepsEstimateEngine.CalibrationPoint(motion: 10, steps: 1000) }
        let scattered = (0..<14).map { i in
            StepsEstimateEngine.CalibrationPoint(motion: 10, steps: Double(500 + (i % 2) * 1500))
        }
        let ct = StepsEstimateEngine.calibrate(tight)!
        let cs = StepsEstimateEngine.calibrate(scattered)!
        XCTAssertGreaterThan(ct.confidence, cs.confidence)
        XCTAssertEqual(ct.confidence, 1.0, accuracy: 1e-9)   // 14 days, zero spread
    }

    // MARK: estimate

    func testEstimateAppliesCoefficient() {
        let cal = StepsEstimateEngine.Calibration(coefficient: 100, sampleDays: 5, confidence: 0.8, manual: false)
        XCTAssertEqual(StepsEstimateEngine.estimate(motion: 87, calibration: cal), 8700)
    }

    func testEstimateNilBelowMinMotion() {
        let cal = StepsEstimateEngine.Calibration(coefficient: 100, sampleDays: 5, confidence: 0.8, manual: false)
        XCTAssertNil(StepsEstimateEngine.estimate(motion: 0.5, calibration: cal))
    }

    func testEstimateClampsAbsurd() {
        let cal = StepsEstimateEngine.Calibration(coefficient: 1_000_000, sampleDays: 5, confidence: 0.1, manual: false)
        XCTAssertEqual(StepsEstimateEngine.estimate(motion: 100, calibration: cal), StepsEstimateEngine.maxDailySteps)
    }

    // MARK: calibration status (explain a blank tile instead of going silent)

    func testStatusNeedsMoreDaysCountsUsableDays() {
        // Two usable overlapping days (< minCalibrationDays 3) → needsMoreDays with have=2. A near-still
        // day and a zero-step day don't count toward `have`.
        let pts = [
            (0.2, 5000.0),     // below minMotionForFit → not usable
            (10.0, 0.0),       // zero steps → not usable
            (10.0, 1000.0), (20.0, 2000.0),
        ].map { StepsEstimateEngine.CalibrationPoint(motion: $0.0, steps: $0.1) }
        let status = StepsEstimateEngine.status(pts)
        XCTAssertEqual(status, .needsMoreDays(have: 2, need: 3))
        XCTAssertFalse(status.canEstimate)
    }

    func testStatusCalibratedOnceEnoughDays() {
        let pts = (0..<3).map { _ in StepsEstimateEngine.CalibrationPoint(motion: 10, steps: 1000) }
        let status = StepsEstimateEngine.status(pts)
        guard case let .calibrated(coefficient, sampleDays, confidence) = status else {
            return XCTFail("3 usable days must report .calibrated, got \(status)")
        }
        XCTAssertEqual(coefficient, 100, accuracy: 1e-9)
        XCTAssertEqual(sampleDays, 3)
        XCTAssertGreaterThan(confidence, 0)
        XCTAssertTrue(status.canEstimate)
    }

    func testStatusManualOverrideWinsEvenWithNoDays() {
        // A hand-set coefficient reports .manual regardless of how few overlapping days exist (the whole
        // point of the manual path — a user with no phone history can still get an estimate).
        let status = StepsEstimateEngine.status([], manualOverride: 42)
        XCTAssertEqual(status, .manual(coefficient: 42, sampleDays: 0))
        XCTAssertTrue(status.canEstimate)
    }
}
