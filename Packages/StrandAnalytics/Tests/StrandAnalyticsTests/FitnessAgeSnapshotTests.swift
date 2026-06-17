import XCTest
@testable import StrandAnalytics

/// Orchestration tests for `FitnessAgeEngine.snapshot(...)` (FER-141): the glue that turns a trailing
/// 7-day window of measured signals + profile into the full UI snapshot. The pure coefficients are
/// covered by `FitnessAgeEngineTests`; here we test the AGGREGATION (median RHR, active-day counting,
/// strain→PA bridge) and that readiness + compute compose correctly.
final class FitnessAgeSnapshotTests: XCTestCase {

    /// Seven days of the same value — the common fixture.
    private func seven<T>(_ v: T) -> [T?] { Array(repeating: Optional(v), count: 7) }

    // MARK: - The engine invariant, through orchestration: average peer ⇒ chronological age

    func testAveragePeerMapsToChronoAgeAndReady() {
        // RHR = the nocturnal reference (58) every night; 7 active days at strain 7 → PA-index 5
        // (= paiReference, since freq(7d)=5.0 × intensity·duration(7/7=1) = 5). By construction
        // fitnessAge == chronoAge, and full coverage (7 nights + 7 active days) clears the .ready bar.
        let s = FitnessAgeEngine.snapshot(
            rhrLast7: seven(58), strainLast7: seven(7.0),
            age: 36, sex: "male", hasHeightWeight: true)
        XCTAssertEqual(s.readiness.confidence, .ready)
        XCTAssertNotNil(s.result)
        XCTAssertEqual(s.result!.fitnessAge, 36, accuracy: 0.01)
        XCTAssertEqual(s.result!.deltaYears, 0, accuracy: 0.01)
        XCTAssertEqual(s.restingHR, 58)
        XCTAssertEqual(s.activeDays, 7)
        XCTAssertEqual(s.rhrNights, 7)
    }

    // MARK: - notReady: too few RHR nights → no number, but aggregates still populate the levers

    func testTooFewNightsIsNotReady() {
        // Only 2 nights of RHR (< minCoverageDays 4) → cannot compute; result nil.
        var rhr: [Int?] = Array(repeating: nil, count: 7)
        rhr[0] = 50; rhr[1] = 54
        let s = FitnessAgeEngine.snapshot(
            rhrLast7: rhr, strainLast7: seven(10.0),
            age: 36, sex: "male", hasHeightWeight: true)
        XCTAssertEqual(s.readiness.confidence, .notReady)
        XCTAssertNil(s.result)
        XCTAssertEqual(s.rhrNights, 2)
        XCTAssertEqual(s.restingHR, 52)   // median of [50, 54] still reported for the lever copy
    }

    // MARK: - estimate: a full RHR week but sparse activity stays a soft claim

    func testSparseActivityCapsAtEstimate() {
        // 7 nights RHR=58, but only 4 active days (strain 14 → PA 5). Computes, but activity coverage
        // is below the good bar, so the unvalidated activity→PA bridge keeps it .estimate, never .ready.
        var strain: [Double?] = Array(repeating: nil, count: 7)
        for i in 0..<4 { strain[i] = 14 }
        let s = FitnessAgeEngine.snapshot(
            rhrLast7: seven(58), strainLast7: strain,
            age: 36, sex: "male", hasHeightWeight: true)
        XCTAssertEqual(s.readiness.confidence, .estimate)
        XCTAssertNotNil(s.result)
        XCTAssertTrue(s.result!.lowerConfidence)
        XCTAssertEqual(s.activeDays, 4)
        XCTAssertEqual(s.result!.fitnessAge, 36, accuracy: 0.01)   // PA 5 + RHR 58 = chrono age
    }

    // MARK: - Direction: a high resting HR reads OLDER, a low one reads YOUNGER

    func testHighRestingHRReadsOlder() {
        // RHR 72 (14 above the 58 reference), activity at reference → older. Sensitivity ≈ 0.524 yr/bpm
        // (men rhrC/ageC) ⇒ +7.3 yr.
        let s = FitnessAgeEngine.snapshot(
            rhrLast7: seven(72), strainLast7: seven(7.0),
            age: 36, sex: "male", hasHeightWeight: true)
        XCTAssertNotNil(s.result)
        XCTAssertGreaterThan(s.result!.fitnessAge, 36)
        XCTAssertLessThan(s.result!.deltaYears, 0)              // older than your age
        XCTAssertEqual(s.result!.fitnessAge, 43.33, accuracy: 0.1)
    }

    func testLowRestingHRReadsYounger() {
        let s = FitnessAgeEngine.snapshot(
            rhrLast7: seven(48), strainLast7: seven(7.0),
            age: 36, sex: "male", hasHeightWeight: true)
        XCTAssertNotNil(s.result)
        XCTAssertLessThan(s.result!.fitnessAge, 36)
        XCTAssertGreaterThan(s.result!.deltaYears, 0)           // younger than your age
    }

    // MARK: - Aggregation details

    func testActiveDaysCountsOnlyPositiveStrain() {
        // strain > 0 counts; an explicit 0 and a nil do not.
        let strain: [Double?] = [14, 0, nil, 14, 14, 14, nil]
        let s = FitnessAgeEngine.snapshot(
            rhrLast7: seven(58), strainLast7: strain,
            age: 36, sex: "male", hasHeightWeight: true)
        XCTAssertEqual(s.activeDays, 4)
    }

    func testRestingHRIsMedianNotMean() {
        // Median is robust to one noisy night: median[50,51,51,52,52,53,90] = 52 (mean would be 57).
        let rhr: [Int?] = [50, 52, 90, 51, 53, 52, 51]
        let s = FitnessAgeEngine.snapshot(
            rhrLast7: rhr, strainLast7: seven(7.0),
            age: 36, sex: "male", hasHeightWeight: true)
        XCTAssertEqual(s.restingHR, 52)
    }

    func testBodyMetricsDoNotChangeTheHeadline() {
        // The waist/body term cancels out of the age, so height/weight presence never moves fitnessAge.
        let withBody = FitnessAgeEngine.snapshot(
            rhrLast7: seven(54), strainLast7: seven(12.0),
            age: 40, sex: "female", hasHeightWeight: true)
        let without = FitnessAgeEngine.snapshot(
            rhrLast7: seven(54), strainLast7: seven(12.0),
            age: 40, sex: "female", hasHeightWeight: false)
        XCTAssertEqual(withBody.result!.fitnessAge, without.result!.fitnessAge, accuracy: 1e-9)
    }

    func testNonBinaryFlagsLowerConfidence() {
        let s = FitnessAgeEngine.snapshot(
            rhrLast7: seven(58), strainLast7: seven(7.0),
            age: 36, sex: "nonbinary", hasHeightWeight: true)
        XCTAssertNotNil(s.result)
        XCTAssertTrue(s.result!.lowerConfidence)   // sex-specific model → softer claim for non-binary
    }

    func testDirectionDeadband() {
        // The ±0.5-yr "even" deadband (FitnessAgeResult.direction): within ⇒ even, beyond ⇒ younger/older.
        func dir(rhr: Int) -> FitnessAgeResult.Direction {
            FitnessAgeEngine.snapshot(rhrLast7: seven(rhr), strainLast7: seven(7.0),
                                      age: 36, sex: "male", hasHeightWeight: true).result!.direction
        }
        XCTAssertEqual(dir(rhr: 58), .even)      // RHR = reference ⇒ delta 0 ⇒ even
        XCTAssertEqual(dir(rhr: 48), .younger)   // low RHR ⇒ younger
        XCTAssertEqual(dir(rhr: 72), .older)     // high RHR ⇒ older
    }

    func testNoDataAtAllIsNotReady() {
        let s = FitnessAgeEngine.snapshot(
            rhrLast7: Array(repeating: nil, count: 7),
            strainLast7: Array(repeating: nil, count: 7),
            age: 36, sex: "male", hasHeightWeight: false)
        XCTAssertEqual(s.readiness.confidence, .notReady)
        XCTAssertNil(s.result)
        XCTAssertNil(s.restingHR)
        XCTAssertEqual(s.activeDays, 0)
    }
}
