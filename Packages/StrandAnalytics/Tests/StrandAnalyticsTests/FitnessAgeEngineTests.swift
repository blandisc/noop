import XCTest
@testable import StrandAnalytics

final class FitnessAgeEngineTests: XCTestCase {

    // MARK: - VO₂max estimate (Nes 2011 waist-circumference variant, confirmed coefficients)
    // NOTE: `restingHR` is NOCTURNAL (WHOOP domain); the engine adds the 7-bpm dip internally to recover
    // the seated-equivalent RHR the Nes equation was calibrated on (correction #1). So nocturnal 58
    // reproduces the classic seated-65 published value.

    func testVO2maxMenKnownValue() {
        // nocturnal 58 (+7 = seated 65): 100.27 − 0.296·40 + 0.226·5 − 0.369·90 − 0.155·65 = 46.275
        let v = FitnessAgeEngine.estimateVO2max(age: 40, sex: "male", waistCm: 90, restingHR: 58, paIndex: 5)
        XCTAssertEqual(v, 46.275, accuracy: 1e-3)
    }

    func testVO2maxWomenKnownValue() {
        // nocturnal 58 (+7 = seated 65): 74.736 − 0.247·40 + 0.198·5 − 0.259·80 − 0.114·65 = 37.716
        let v = FitnessAgeEngine.estimateVO2max(age: 40, sex: "female", waistCm: 80, restingHR: 58, paIndex: 5)
        XCTAssertEqual(v, 37.716, accuracy: 1e-3)
    }

    func testBMIHelper() {
        XCTAssertEqual(FitnessAgeEngine.bmi(weightKg: 80, heightCm: 178), 25.249, accuracy: 1e-3)
    }

    // MARK: - Correction #1: nocturnal RHR anchor ties to the validated seated Nes anchor (65)

    func testNocturnalAnchorTiesToSeatedNesAnchor() {
        // The nocturnal reference is the seated Nes/CERG anchor (65) minus the 7-bpm nocturnal dip.
        XCTAssertEqual(FitnessAgeEngine.restingHRReference + FitnessAgeEngine.nocturnalToSeatedRHROffset,
                       65.0, accuracy: 1e-9)
        // Feeding the nocturnal reference RHR reproduces the published seated-65 VO₂max exactly.
        let v = FitnessAgeEngine.estimateVO2max(age: 40, sex: "male", waistCm: 90,
                                                restingHR: FitnessAgeEngine.restingHRReference, paIndex: 5)
        XCTAssertEqual(v, 46.275, accuracy: 1e-3)
    }

    // MARK: - Fitness Age (self-consistent Nes; waist cancels, so only age/sex/RHR/PA needed)

    func testFitnessAgeReferenceFitPersonEqualsChronoAge() {
        // Nocturnal RHR 58 + PAI 5 = the reference peer → Fitness Age == chronological age exactly.
        XCTAssertEqual(FitnessAgeEngine.fitnessAge(age: 40, sex: "male", restingHR: 58, paIndex: 5),
                       40.0, accuracy: 1e-9)
        XCTAssertEqual(FitnessAgeEngine.fitnessAge(age: 55, sex: "female", restingHR: 58, paIndex: 5),
                       55.0, accuracy: 1e-9)
    }

    func testFitnessAgeFitterIsYounger() {
        // Man 40, nocturnal RHR 48, PAI 10: 40 + (0.155·(48−58) − 0.226·(10−5))/0.296 = 30.95
        XCTAssertEqual(FitnessAgeEngine.fitnessAge(age: 40, sex: "male", restingHR: 48, paIndex: 10),
                       30.95, accuracy: 0.05)
    }

    func testFitnessAgeUnfitterIsOlder() {
        // Man 40, nocturnal RHR 72, PAI 2: 40 + (0.155·(72−58) − 0.226·(2−5))/0.296 = 49.62
        XCTAssertEqual(FitnessAgeEngine.fitnessAge(age: 40, sex: "male", restingHR: 72, paIndex: 2),
                       49.62, accuracy: 0.05)
    }

    func testFitnessAgeClampsToRange() {
        // Extremely unfit, older → clamps to 80.
        XCTAssertEqual(FitnessAgeEngine.fitnessAge(age: 75, sex: "male", restingHR: 120, paIndex: 0),
                       80, accuracy: 1e-9)
        // Extremely fit, young → clamps to 20.
        XCTAssertEqual(FitnessAgeEngine.fitnessAge(age: 25, sex: "male", restingHR: 35, paIndex: 15),
                       20, accuracy: 1e-9)
    }

    // MARK: - PA-index reconstruction (HUNT1 PA-Q buckets)

    func testPAIndexSedentary() {
        XCTAssertEqual(FitnessAgeEngine.physicalActivityIndex(
            activeDaysPerWeek: 0, avgActiveMinutesPerDay: 0, highIntensityFraction: 0), 0, accuracy: 1e-9)
    }

    func testPAIndexHighlyActive() {
        XCTAssertEqual(FitnessAgeEngine.physicalActivityIndex(
            activeDaysPerWeek: 7, avgActiveMinutesPerDay: 75, highIntensityFraction: 0.8), 15.0, accuracy: 1e-9)
    }

    func testPAIndexModerate() {
        // 3 days (2.5) × moderate (2) × ~40 min (0.75) = 3.75
        XCTAssertEqual(FitnessAgeEngine.physicalActivityIndex(
            activeDaysPerWeek: 3, avgActiveMinutesPerDay: 40, highIntensityFraction: 0.3), 3.75, accuracy: 1e-9)
    }

    // MARK: - Correction #2: PA-index from strain recalibrated to THIS repo's 0–21 scale

    func testPAIndexFromStrainSedentary() {
        XCTAssertEqual(FitnessAgeEngine.physicalActivityIndexFromStrain(
            activeDaysPerWeek: 0, meanActiveStrain: 0), 0, accuracy: 1e-9)
    }

    func testPAIndexFromStrainReferencePeer() {
        // The reference peer: ≈4 active days (freq 2.5) × strain 14 (id 14/7 = 2.0) = PA-index 5.0.
        XCTAssertEqual(FitnessAgeEngine.physicalActivityIndexFromStrain(
            activeDaysPerWeek: 4, meanActiveStrain: 14), 5.0, accuracy: 1e-9)
    }

    func testPAIndexFromStrainRealWorkoutIsNotSedentary() {
        // REGRESSION for the 0–100→0–21 bug: a real workout (strain ~14) must read as solidly active,
        // not sedentary. Under the old /30 divisor this collapsed to ≈0.47 → everyone looked sedentary.
        let id = FitnessAgeEngine.physicalActivityIndexFromStrain(activeDaysPerWeek: 1, meanActiveStrain: 14)
        XCTAssertEqual(id, 0.5 * 2.0, accuracy: 1e-9)   // freq(1 day)=0.5 × id(14/7=2.0) = 1.0
    }

    func testPAIndexFromStrainScaleEndpointsAndCap() {
        // 7 days (freq 5.0) × strain 21 (id 3.0) = 15.0 (top of scale).
        XCTAssertEqual(FitnessAgeEngine.physicalActivityIndexFromStrain(
            activeDaysPerWeek: 7, meanActiveStrain: 21), 15.0, accuracy: 1e-9)
        // 3 days (freq 2.5) × strain 10.5 (id 1.5) = 3.75.
        XCTAssertEqual(FitnessAgeEngine.physicalActivityIndexFromStrain(
            activeDaysPerWeek: 3, meanActiveStrain: 10.5), 3.75, accuracy: 1e-9)
        // intensity×duration caps at 3.0 even above strain 21.
        XCTAssertEqual(FitnessAgeEngine.physicalActivityIndexFromStrain(
            activeDaysPerWeek: 7, meanActiveStrain: 40), 15.0, accuracy: 1e-9)
    }

    // MARK: - compute (full result + gates)

    func testComputeReferencePersonExactAge() {
        let r = FitnessAgeEngine.compute(age: 40, sex: "male", restingHR: 58, paIndex: 5)
        XCTAssertNotNil(r)
        XCTAssertEqual(r!.fitnessAge, 40.0, accuracy: 1e-9)
        XCTAssertEqual(r!.deltaYears, 0.0, accuracy: 1e-9)
        XCTAssertNil(r!.vo2max)               // no waist → no VO₂max display
        XCTAssertEqual(r!.bandYears, 5.0, accuracy: 1e-9)
        XCTAssertFalse(r!.lowerConfidence)
    }

    func testComputeWithWaistFillsVO2max() {
        let r = FitnessAgeEngine.compute(age: 40, sex: "male", restingHR: 58, paIndex: 5, waistCm: 90)
        XCTAssertEqual(r!.vo2max!, 46.275, accuracy: 1e-3)
    }

    // MARK: - Correction #3: the ±5 band is the AGE-DELTA band, NOT a VO₂max band

    func testBandAppliesToAgeDeltaNotVO2max() {
        // With a waist, the absolute VO₂max is present — but `bandYears` stays the age-delta band (5),
        // and the result exposes NO ± band attached to vo2max (the struct carries none by construction).
        let r = FitnessAgeEngine.compute(age: 40, sex: "male", restingHR: 58, paIndex: 5, waistCm: 90)!
        XCTAssertEqual(r.bandYears, FitnessAgeEngine.displayBandYears, accuracy: 1e-9)
        XCTAssertNotNil(r.vo2max)
        // bandYears describes the age delta: chronoAge ± bandYears, independent of the VO₂max estimate.
        XCTAssertEqual(r.bandYears, 5.0, accuracy: 1e-9)
    }

    func testComputeNonBinaryFlagsLowerConfidence() {
        let r = FitnessAgeEngine.compute(age: 40, sex: "nonbinary", restingHR: 53, paIndex: 6)
        XCTAssertTrue(r!.lowerConfidence)
    }

    func testComputeNilWhenNoRHR() {
        XCTAssertNil(FitnessAgeEngine.compute(age: 40, sex: "male", restingHR: 0, paIndex: 7.5))
    }

    // MARK: - Readiness checklist

    func testReadinessAllPresentIsReady() {
        let r = FitnessAgeEngine.assessReadiness(hasAge: true, hasSex: true, rhrDays: 7, activityDays: 7,
                                                 hasHeightWeight: true, hasWaist: true)
        XCTAssertEqual(r.confidence, .ready)
        XCTAssertTrue(r.canCompute)
        XCTAssertTrue(r.items.allSatisfy { $0.status == .satisfied })
        XCTAssertEqual(r.items.count, 6)
    }

    func testReadinessMissingRHRIsNotReady() {
        let r = FitnessAgeEngine.assessReadiness(hasAge: true, hasSex: true, rhrDays: 0, activityDays: 7,
                                                 hasHeightWeight: true, hasWaist: true)
        XCTAssertEqual(r.confidence, .notReady)
        XCTAssertFalse(r.canCompute)
        XCTAssertEqual(r.items.first { $0.key == "rhr" }!.status, .missing)
    }

    func testReadinessPartialCoverageIsEstimate() {
        // age+sex set, 5 nights RHR (≥ min 4 but < good 6), sparse activity → computes, but "estimate".
        let r = FitnessAgeEngine.assessReadiness(hasAge: true, hasSex: true, rhrDays: 5, activityDays: 3,
                                                 hasHeightWeight: false, hasWaist: false)
        XCTAssertEqual(r.confidence, .estimate)
        XCTAssertTrue(r.canCompute)
        XCTAssertEqual(r.items.first { $0.key == "rhr" }!.status, .partial)
        XCTAssertEqual(r.items.first { $0.key == "activity" }!.status, .partial)
        // Missing body metrics never blocks the headline — they sit under the VO₂max role.
        let body = r.items.first { $0.key == "bodyMetrics" }!
        XCTAssertEqual(body.status, .missing)
        XCTAssertEqual(body.role, .unlocksVO2max)
        XCTAssertFalse(body.required)
    }

    func testReadinessGoodRHRSparseActivityIsEstimate() {
        // Correction #2 rationale: full RHR coverage but sparse activity → NOT `.ready`. The unvalidated
        // strain→PA-index bridge can't carry a confident verdict on thin activity data.
        let r = FitnessAgeEngine.assessReadiness(hasAge: true, hasSex: true, rhrDays: 7, activityDays: 3,
                                                 hasHeightWeight: true, hasWaist: true)
        XCTAssertEqual(r.confidence, .estimate)
        XCTAssertTrue(r.canCompute)
    }

    func testReadinessMissingAgeIsNotReady() {
        let r = FitnessAgeEngine.assessReadiness(hasAge: false, hasSex: true, rhrDays: 7, activityDays: 7,
                                                 hasHeightWeight: true, hasWaist: true)
        XCTAssertEqual(r.confidence, .notReady)
    }

    func testReadinessGoodCoverageNoBodyMetricsStillReady() {
        // Headline only needs age/sex/coverage; missing height/weight (VO₂max-only) doesn't drop it.
        let r = FitnessAgeEngine.assessReadiness(hasAge: true, hasSex: true, rhrDays: 7, activityDays: 6,
                                                 hasHeightWeight: false, hasWaist: false)
        XCTAssertEqual(r.confidence, .ready)
    }
}
