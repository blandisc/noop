import XCTest
@testable import StrandAnalytics

/// FER-145 — the orchestration aggregator that turns a window of raw nightly/daily signals into
/// `VitalityEngine.Inputs` (medians + the HRV coverage gate + the interim regularity proxy).
final class VitalityInputsBuilderTests: XCTestCase {

    // MARK: aggregation

    func test_median_oddAndEven() {
        XCTAssertEqual(VitalityInputsBuilder.median([3, 1, 2]), 2)
        XCTAssertEqual(VitalityInputsBuilder.median([4, 1, 3, 2]), 2.5)
        XCTAssertNil(VitalityInputsBuilder.median([]))
    }

    func test_mean_ignoresEmpty() {
        XCTAssertEqual(VitalityInputsBuilder.mean([2, 4, 6]), 4)
        XCTAssertNil(VitalityInputsBuilder.mean([]))
    }

    // MARK: HRV coverage gate

    func test_hrv_belowCoverage_isAbsent() {
        // 4 valid nights < minHRVNights (5) → RMSSD not scored (factor absent), norm absent too.
        let s = VitalityInputsBuilder.Signals(chronoAge: 35, nightlyRMSSD: [40, 41, 39, 42])
        let inputs = VitalityInputsBuilder.build(s)
        XCTAssertNil(inputs.rmssd)
        XCTAssertNil(inputs.rmssdNorm)
    }

    func test_hrv_atCoverage_isScored() {
        let s = VitalityInputsBuilder.Signals(chronoAge: 35, nightlyRMSSD: [40, 41, 39, 42, 38])
        let inputs = VitalityInputsBuilder.build(s)
        XCTAssertEqual(inputs.rmssd, 40)                              // median of the 5
        XCTAssertEqual(inputs.rmssdNorm, VitalityEngine.rmssdNorm(forAge: 35))
    }

    // MARK: honesty gate passes through

    func test_empty_yieldsNilResult() {
        let inputs = VitalityInputsBuilder.build(.init(chronoAge: 40))
        XCTAssertNil(VitalityEngine.compute(inputs))                  // 0 factors < minFactors
    }

    // MARK: an average-for-their-age person maps near their own age / ~50

    func test_averagePerson_mapsNearChronoAndFifty() {
        // Reference-ish signals: nocturnal RHR at the population anchor, 7 h sleep, steps at the
        // <60 reference, RMSSD at the age norm. Regular sleep gives the proxy a small protective
        // credit, which the overlap shrink tames — so a touch younger than chrono, by design.
        let norm = VitalityEngine.rmssdNorm(forAge: 35)
        let s = VitalityInputsBuilder.Signals(
            chronoAge: 35,
            nightlyRestingHR: Array(repeating: 58, count: 10),
            nightlyRMSSD: Array(repeating: norm, count: 10),
            nightlySleepHours: Array(repeating: 7.0, count: 10),
            dailySteps: Array(repeating: 8500, count: 10))
        let inputs = VitalityInputsBuilder.build(s)
        guard let r = VitalityEngine.compute(inputs) else { return XCTFail("expected a result") }

        XCTAssertEqual(r.factorsUsed, 5)                              // rhr, sleep, consistency, hrv, steps (no vo2max)
        XCTAssertEqual(r.bodyAge, 35, accuracy: 3.5)                 // ~chronological age
        XCTAssertEqual(r.vitality, 50, accuracy: 8)                  // ~typical
    }

    // MARK: vo2max stays nil (no waist in the profile)

    func test_vo2max_alwaysNil() {
        let s = VitalityInputsBuilder.Signals(chronoAge: 50, nightlyRestingHR: [60, 61, 59])
        let inputs = VitalityInputsBuilder.build(s)
        XCTAssertNil(inputs.vo2max)
        XCTAssertNil(inputs.expectedVO2max)
    }
}
