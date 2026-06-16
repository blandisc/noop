import XCTest
import Foundation
@testable import StrandAnalytics

final class VitalityEngineTests: XCTestCase {

    /// Pull one factor's signed log-hazard out of `contributions` by key (nil if not present).
    private func lnHazard(_ inputs: VitalityEngine.Inputs, _ key: String) -> Double? {
        VitalityEngine.contributions(inputs).first { $0.key == key }?.lnHazard
    }

    // MARK: - Reference person → Body Age == chrono age, Vitality == 50 (the honesty anchor)

    func testReferencePersonReadsAtTheirOwnAge() {
        // Every factor exactly at its population reference (age 40): nocturnal RHR 58, VO₂max = expected,
        // 7.0 h sleep, SRI 0.60, RMSSD = age norm (33), 8,500 steps (<60 yr reference). Net Δ = 0.
        let inputs = VitalityEngine.Inputs(
            chronoAge: 40, restingHR: 58, vo2max: 40, expectedVO2max: 40, sleepHours: 7.0,
            sleepConsistency: 0.60, rmssd: 33, rmssdNorm: VitalityEngine.rmssdNorm(forAge: 40), steps: 8500)
        let r = VitalityEngine.compute(inputs)
        XCTAssertNotNil(r)
        XCTAssertEqual(r!.bodyAge, 40.0, accuracy: 1e-9)
        XCTAssertEqual(r!.vitality, 50.0, accuracy: 1e-9)
        XCTAssertEqual(r!.deltaYears, 0.0, accuracy: 1e-9)
        XCTAssertEqual(r!.bandYears, 5.0, accuracy: 1e-9)
        XCTAssertEqual(r!.factorsUsed, 6)
    }

    func testHealthierReadsYoungerUnhealthierReadsOlder() {
        let base = VitalityEngine.Inputs(chronoAge: 40, restingHR: 58, vo2max: 40, expectedVO2max: 40,
                                         sleepHours: 7.0, sleepConsistency: 0.60, rmssd: 33,
                                         rmssdNorm: 33, steps: 8500)
        var healthy = base
        healthy.restingHR = 48; healthy.vo2max = 47; healthy.sleepConsistency = 0.9; healthy.steps = 11000
        let rh = VitalityEngine.compute(healthy)!
        XCTAssertLessThan(rh.bodyAge, 40.0)
        XCTAssertGreaterThan(rh.vitality, 50.0)

        var unhealthy = base
        unhealthy.restingHR = 78; unhealthy.vo2max = 33; unhealthy.sleepHours = 5.0; unhealthy.steps = 3000
        let ru = VitalityEngine.compute(unhealthy)!
        XCTAssertGreaterThan(ru.bodyAge, 40.0)
        XCTAssertLessThan(ru.vitality, 50.0)
    }

    // MARK: - Correction #1: RHR reference re-anchored to the nocturnal domain (reuses FitnessAge's constant)

    func testRHRNeutralPointReusesFitnessAgeNocturnalAnchor() {
        // The RHR factor must be neutral exactly at FitnessAgeEngine.restingHRReference (the shared
        // nocturnal anchor, 58) — NOT at the old seated 65.
        let atAnchor = VitalityEngine.Inputs(chronoAge: 40, restingHR: FitnessAgeEngine.restingHRReference)
        XCTAssertEqual(lnHazard(atAnchor, "rhr")!, 0.0, accuracy: 1e-12)
        // At the old seated anchor (65) the factor is NO LONGER neutral — proof of the re-anchor.
        let atSeated = VitalityEngine.Inputs(chronoAge: 40, restingHR: 65)
        XCTAssertGreaterThan(lnHazard(atSeated, "rhr")!, 0.0)
        XCTAssertEqual(lnHazard(atSeated, "rhr")!, ((65 - 58) / 10) * 0.100, accuracy: 1e-9)
    }

    func testRHRSlopeAndLowerClamp() {
        // +10 bpm above the anchor → +0.100 log-hazard (≈ +10%/10 bpm, the conservative floor).
        let plus10 = VitalityEngine.Inputs(chronoAge: 40, restingHR: 68)
        XCTAssertEqual(lnHazard(plus10, "rhr")!, 0.100, accuracy: 1e-9)
        // Athletic nocturnal RHR is clamped at −1.5 decades (no unbounded credit): 40 bpm → −1.8 → −1.5.
        let athletic = VitalityEngine.Inputs(chronoAge: 40, restingHR: 40)
        XCTAssertEqual(lnHazard(athletic, "rhr")!, -1.5 * 0.100, accuracy: 1e-9)
    }

    // MARK: - Correction #2: sleep duration optimum 7.0 h, ASYMMETRIC arms (short 0.060 / long 0.120)

    func testSleepOptimumIsNeutralBand() {
        for h in [6.5, 7.0, 7.5] {
            let i = VitalityEngine.Inputs(chronoAge: 40, sleepHours: h)
            XCTAssertEqual(lnHazard(i, "sleep")!, 0.0, accuracy: 1e-12, "sleep \(h)h should be neutral")
        }
    }

    func testSleepAsymmetryLongPenalizedMoreThanShort() {
        // 5.5 h: dev 1.0 × short 0.060 = 0.060.  9.5 h: dev 2.0 × long 0.120 = 0.240.
        let short = lnHazard(VitalityEngine.Inputs(chronoAge: 40, sleepHours: 5.5), "sleep")!
        let long = lnHazard(VitalityEngine.Inputs(chronoAge: 40, sleepHours: 9.5), "sleep")!
        XCTAssertEqual(short, 0.060, accuracy: 1e-9)
        XCTAssertEqual(long, 0.240, accuracy: 1e-9)
        XCTAssertGreaterThan(long, short)   // asymmetry: long sleep is the heavier risk
    }

    func testSleepShortArmGentlerThanOldSymmetric() {
        // Regression for the symmetry bug: 5.5 h now costs 0.060, FAR below the old symmetric model
        // (optimum 7.5, |5.5−7.5|−0.5 = 1.5 × 0.110 = 0.165) that over-penalized short sleep.
        let short = lnHazard(VitalityEngine.Inputs(chronoAge: 40, sleepHours: 5.5), "sleep")!
        XCTAssertLessThan(short, 0.165)
    }

    // MARK: - Correction #3: overlap shrink derived from the number of active factors

    func testOverlapShrinkIsFactorCountDependent() {
        XCTAssertEqual(VitalityEngine.overlapShrink(forFactors: 1), 1.0, accuracy: 1e-12)      // no shrink
        XCTAssertEqual(VitalityEngine.overlapShrink(forFactors: 2), 1.0 / 1.35, accuracy: 1e-9)
        XCTAssertEqual(VitalityEngine.overlapShrink(forFactors: 3), 1.0 / 1.70, accuracy: 1e-9)
        XCTAssertEqual(VitalityEngine.overlapShrink(forFactors: 4), 1.0 / 2.05, accuracy: 1e-9)
        // Monotonically decreasing: more correlated signals → more shrink.
        XCTAssertGreaterThan(VitalityEngine.overlapShrink(forFactors: 3),
                             VitalityEngine.overlapShrink(forFactors: 6))
    }

    func testComputeAppliesTheFactorCountShrink() {
        // Hand-computed end-to-end with n=3: rhr 0.100 + sleep(5.5)=0.060 + steps(4500@40)=0.256 = 0.416;
        // shrink(3)=1/1.7=0.588235; ΔlnH=0.244706; Δage=0.244706/(ln2/8)=2.824 → Body Age 42.82.
        let i = VitalityEngine.Inputs(chronoAge: 40, restingHR: 68, sleepHours: 5.5, steps: 4500)
        let r = VitalityEngine.compute(i)!
        XCTAssertEqual(r.factorsUsed, 3)
        XCTAssertEqual(r.bodyAge, 42.824, accuracy: 0.02)
        XCTAssertEqual(r.deltaYears, -2.824, accuracy: 0.02)
    }

    // MARK: - Correction #4: HRV attenuated (β 0.110) + log form; daytime norm makes it conservative

    func testHRVNeutralAtNormAndLogForm() {
        let atNorm = VitalityEngine.Inputs(chronoAge: 40, rmssd: 33, rmssdNorm: 33)
        XCTAssertEqual(lnHazard(atNorm, "hrv")!, 0.0, accuracy: 1e-12)
        // Half the norm → ln(2) × 0.110 ages you; double the norm → ln(0.5) × 0.110 protects.
        let low = VitalityEngine.Inputs(chronoAge: 40, rmssd: 16.5, rmssdNorm: 33)
        XCTAssertEqual(lnHazard(low, "hrv")!, log(2.0) * 0.110, accuracy: 1e-9)
        let high = VitalityEngine.Inputs(chronoAge: 40, rmssd: 66, rmssdNorm: 33)
        XCTAssertEqual(lnHazard(high, "hrv")!, log(0.5) * 0.110, accuracy: 1e-9)
    }

    func testHRVClampAndZeroGuard() {
        // Extremely low HRV is clamped at +0.7 log-ratio (× 0.110 = 0.077).
        let veryLow = VitalityEngine.Inputs(chronoAge: 40, rmssd: 5, rmssdNorm: 33)
        XCTAssertEqual(lnHazard(veryLow, "hrv")!, 0.7 * 0.110, accuracy: 1e-9)
        // rmssd = 0 (or missing norm) → the factor is absent (log undefined; guarded).
        XCTAssertNil(lnHazard(VitalityEngine.Inputs(chronoAge: 40, rmssd: 0, rmssdNorm: 33), "hrv"))
        XCTAssertNil(lnHazard(VitalityEngine.Inputs(chronoAge: 40, rmssd: 33, rmssdNorm: 0), "hrv"))
    }

    // MARK: - Correction #5: sleep regularity reference 0.75 → 0.60 (population median)

    func testRegularityReferenceIsSixty() {
        let atRef = VitalityEngine.Inputs(chronoAge: 40, sleepConsistency: 0.60)
        XCTAssertEqual(lnHazard(atRef, "consistency")!, 0.0, accuracy: 1e-12)
        // Irregular (0.10) ages you; very regular (1.0) protects.
        XCTAssertEqual(lnHazard(VitalityEngine.Inputs(chronoAge: 40, sleepConsistency: 0.10), "consistency")!,
                       (0.60 - 0.10) * 0.450, accuracy: 1e-9)
        XCTAssertEqual(lnHazard(VitalityEngine.Inputs(chronoAge: 40, sleepConsistency: 1.0), "consistency")!,
                       (0.60 - 1.0) * 0.450, accuracy: 1e-9)
        // Under the OLD ref (0.75) an SRI of 0.75 was neutral; now it reads as protective (below ref).
        XCTAssertLessThan(lnHazard(VitalityEngine.Inputs(chronoAge: 40, sleepConsistency: 0.75), "consistency")!, 0.0)
    }

    // MARK: - Correction #6: steps reference is age-aware (≥60 → 7000, <60 → 8500)

    func testStepsThresholdDependsOnAge() {
        // 7,000 steps: a <60 yr user still has a deficit (ref 8500), a ≥60 yr user is neutral (ref 7000).
        let young = lnHazard(VitalityEngine.Inputs(chronoAge: 30, steps: 7000), "steps")!
        let old = lnHazard(VitalityEngine.Inputs(chronoAge: 65, steps: 7000), "steps")!
        XCTAssertEqual(young, ((8500 - 7000) / 1000) * 0.064, accuracy: 1e-9)   // 0.096
        XCTAssertEqual(old, 0.0, accuracy: 1e-12)
        XCTAssertGreaterThan(young, old)
    }

    func testStepsWeightAndCap() {
        // Per-1,000 weight 0.064, protection capped at 11,000 steps.
        let capped = lnHazard(VitalityEngine.Inputs(chronoAge: 30, steps: 15000), "steps")!
        let at11k = lnHazard(VitalityEngine.Inputs(chronoAge: 30, steps: 11000), "steps")!
        XCTAssertEqual(capped, at11k, accuracy: 1e-12)                          // cap holds
        XCTAssertEqual(at11k, ((8500 - 11000) / 1000) * 0.064, accuracy: 1e-9)  // protective, −0.16
    }

    // MARK: - Verbatim VO₂max (Kodama 2009 / Singh 2025): ~13%/MET vs the age/sex-expected value

    func testVO2maxVerbatim() {
        let lessFit = VitalityEngine.Inputs(chronoAge: 40, vo2max: 40, expectedVO2max: 47)
        XCTAssertEqual(lnHazard(lessFit, "vo2max")!, ((47 - 40) / 3.5) * 0.130, accuracy: 1e-9)  // +0.26
        let fitter = VitalityEngine.Inputs(chronoAge: 40, vo2max: 54, expectedVO2max: 47)
        XCTAssertEqual(lnHazard(fitter, "vo2max")!, ((47 - 54) / 3.5) * 0.130, accuracy: 1e-9)   // −0.26
        // Clamp at ±4 MET of deviation.
        let extreme = VitalityEngine.Inputs(chronoAge: 40, vo2max: 80, expectedVO2max: 40)
        XCTAssertEqual(lnHazard(extreme, "vo2max")!, -4 * 0.130, accuracy: 1e-9)
    }

    // MARK: - Honesty gate: < minFactors → nil

    func testGateBelowMinFactorsReturnsNil() {
        // Two factors only (rhr + sleep) → nil; chrono age missing → nil; three factors → a result.
        XCTAssertNil(VitalityEngine.compute(VitalityEngine.Inputs(chronoAge: 40, restingHR: 58, sleepHours: 7.0)))
        XCTAssertNil(VitalityEngine.compute(VitalityEngine.Inputs(chronoAge: 0, restingHR: 58, sleepHours: 7.0, steps: 9000)))
        XCTAssertNotNil(VitalityEngine.compute(VitalityEngine.Inputs(chronoAge: 40, restingHR: 58, sleepHours: 7.0, steps: 8500)))
    }

    // MARK: - contributions exposes the per-factor breakdown (drives the "what moves this" UI)

    func testContributionsBreakdownKeys() {
        let full = VitalityEngine.Inputs(chronoAge: 40, restingHR: 60, vo2max: 42, expectedVO2max: 45,
                                         sleepHours: 6.0, sleepConsistency: 0.5, rmssd: 30, rmssdNorm: 33,
                                         steps: 6000)
        XCTAssertEqual(Set(VitalityEngine.contributions(full).map { $0.key }),
                       ["rhr", "vo2max", "sleep", "consistency", "hrv", "steps"])
        // Partial inputs → only the present factors appear.
        let partial = VitalityEngine.Inputs(chronoAge: 40, restingHR: 60, sleepHours: 6.0, steps: 6000)
        XCTAssertEqual(Set(VitalityEngine.contributions(partial).map { $0.key }), ["rhr", "sleep", "steps"])
    }

    // MARK: - Body Age [20,90] and Vitality [0,100] clamps hold at the extremes

    func testBodyAgeClampsToFloorAndCeiling() {
        // Floor: a very young, very healthy profile cannot read below 20.
        let young = VitalityEngine.Inputs(chronoAge: 20, restingHR: 45, vo2max: 60, expectedVO2max: 40,
                                          sleepHours: 7.0, sleepConsistency: 1.0, rmssd: 70, rmssdNorm: 47,
                                          steps: 11000)
        XCTAssertEqual(VitalityEngine.compute(young)!.bodyAge, 20.0, accuracy: 1e-9)
        // Ceiling: a very old, very unhealthy profile cannot read above 90.
        let old = VitalityEngine.Inputs(chronoAge: 88, restingHR: 100, vo2max: 15, expectedVO2max: 35,
                                        sleepHours: 4.0, sleepConsistency: 0.0, rmssd: 8, rmssdNorm: 20,
                                        steps: 1000)
        XCTAssertEqual(VitalityEngine.compute(old)!.bodyAge, 90.0, accuracy: 1e-9)
    }

    func testVitalityStaysWithinBounds() {
        let healthy = VitalityEngine.Inputs(chronoAge: 45, restingHR: 44, vo2max: 65, expectedVO2max: 40,
                                            sleepHours: 7.0, sleepConsistency: 1.0, rmssd: 80, rmssdNorm: 31,
                                            steps: 11000)
        let unhealthy = VitalityEngine.Inputs(chronoAge: 45, restingHR: 110, vo2max: 12, expectedVO2max: 40,
                                              sleepHours: 3.0, sleepConsistency: 0.0, rmssd: 6, rmssdNorm: 31,
                                              steps: 500)
        for r in [VitalityEngine.compute(healthy)!, VitalityEngine.compute(unhealthy)!] {
            XCTAssertGreaterThanOrEqual(r.vitality, 0.0)
            XCTAssertLessThanOrEqual(r.vitality, 100.0)
            XCTAssertGreaterThanOrEqual(r.bodyAge, 20.0)
            XCTAssertLessThanOrEqual(r.bodyAge, 90.0)
        }
    }

    // MARK: - Helper tables/proxies

    func testRMSSDNormTableAnchorsAndInterpolation() {
        XCTAssertEqual(VitalityEngine.rmssdNorm(forAge: 20), 47, accuracy: 1e-9)
        XCTAssertEqual(VitalityEngine.rmssdNorm(forAge: 40), 33, accuracy: 1e-9)
        XCTAssertEqual(VitalityEngine.rmssdNorm(forAge: 80), 20, accuracy: 1e-9)
        XCTAssertEqual(VitalityEngine.rmssdNorm(forAge: 25), 43.5, accuracy: 1e-9)   // midway 47→40
        XCTAssertEqual(VitalityEngine.rmssdNorm(forAge: 15), 47, accuracy: 1e-9)     // below floor
        XCTAssertEqual(VitalityEngine.rmssdNorm(forAge: 95), 20, accuracy: 1e-9)     // above ceiling
    }

    func testSleepConsistencyProxy() {
        XCTAssertNil(VitalityEngine.sleepConsistency(nightlyHours: [7, 8]))            // < 3 nights
        XCTAssertEqual(VitalityEngine.sleepConsistency(nightlyHours: [7, 7, 7])!, 1.0, accuracy: 1e-9)
        let varied = VitalityEngine.sleepConsistency(nightlyHours: [5, 7, 9])!
        XCTAssertLessThan(varied, 1.0)
        XCTAssertGreaterThan(varied, 0.0)
    }
}
