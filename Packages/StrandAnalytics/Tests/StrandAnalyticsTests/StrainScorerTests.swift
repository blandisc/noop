import XCTest
@testable import StrandAnalytics
import BiometricStreams

final class StrainScorerTests: XCTestCase {

    /// Build n consecutive 1 Hz HR samples at a constant bpm.
    private func hr(_ bpm: Int, _ n: Int, start: Int = 0) -> [HRSample] {
        (0..<n).map { HRSample(ts: start + $0, bpm: bpm) }
    }

    func testTanakaAndDefaultMax() {
        XCTAssertEqual(StrainScorer.tanakaHRmax(age: 30), 187.0, accuracy: 1e-9)
        XCTAssertEqual(StrainScorer.defaultMaxHR(age: 30), 190)
    }

    func testTrimpToStrainCeilingMapsTo21() {
        // Edwards 24 h ceiling TRIMP = 7200 → strain exactly 21.0 with D = 7201.
        XCTAssertEqual(StrainScorer.trimpToStrain(7200), 21.0, accuracy: 1e-9)
    }

    func testTrimpToStrainKnownValues() {
        XCTAssertEqual(StrainScorer.trimpToStrain(0), 0.0, accuracy: 1e-9)
        XCTAssertEqual(StrainScorer.trimpToStrain(-5), 0.0, accuracy: 1e-9)
        XCTAssertEqual(StrainScorer.trimpToStrain(100), 10.91, accuracy: 1e-9)
    }

    func testStrainGoldenEdwardsZone5() {
        // 600 z5 samples at 1 Hz, resting 60, max 190. TRIMP = 600*5*(1/60)=50.
        // strain = 21*ln(51)/ln(7201) = 9.3.
        let s = StrainScorer.strain(hr(185, 600), maxHR: 190, restingHR: 60)
        XCTAssertEqual(s!, 9.3, accuracy: 1e-2)
    }

    func testSampleDurationUsesMedianNotFirstPair() {
        // First pair is a 60 s gap (strap reconnect); the rest are 1 Hz.
        // The robust estimate is the MEDIAN plausible spacing (1 s), not the
        // first pair (60 s). 1 s = 1/60 min.
        var samples = [HRSample(ts: 0, bpm: 100)]
        samples += (0..<10).map { HRSample(ts: 60 + $0, bpm: 100) }
        XCTAssertEqual(StrainScorer.sampleDurationMinutes(samples), 1.0 / 60.0, accuracy: 1e-9)
    }

    func testStrainUnaffectedByInitialGap() {
        // TRIMP load via the Edwards 5-zone summation (Edwards 1993). A single
        // early gap (strap reconnect; a distant first sample at ~1 Hz) must NOT
        // rescale the whole day's strain — per-sample duration now derives from
        // the median plausible spacing, not the first timestamp pair.
        let clean = hr(185, 600)                            // 600 z5 samples @ 1 Hz
        let baseline = StrainScorer.strain(clean, maxHR: 190, restingHR: 60)!
        XCTAssertEqual(baseline, 9.3, accuracy: 1e-2)       // golden reference

        // Same 600 samples, but the first sits 60 s before the rest.
        var gapped = [HRSample(ts: 0, bpm: 185)]
        gapped += (0..<599).map { HRSample(ts: 60 + $0, bpm: 185) }
        let withGap = StrainScorer.strain(gapped, maxHR: 190, restingHR: 60)!

        // Before the fix this jumped to 18.93 (≈2×). Now within ±1% of baseline.
        XCTAssertEqual(withGap, baseline, accuracy: baseline * 0.01)
        XCTAssertLessThan(withGap, 10.0)                    // nowhere near the old 18.93
    }

    func testStrainReturnsNilTooFewReadings() {
        XCTAssertNil(StrainScorer.strain(hr(150, 599), maxHR: 190, restingHR: 60))
    }

    func testStrainReturnsNilInvalidHRR() {
        XCTAssertNil(StrainScorer.strain(hr(150, 600), maxHR: 60, restingHR: 60))
        XCTAssertNil(StrainScorer.strain(hr(150, 600), maxHR: 50, restingHR: 60))
    }

    func testStrainMonotonicInZoneTime() {
        // More time at high intensity → higher strain. Compare 600 vs 1200 z5 samples.
        let short = StrainScorer.strain(hr(185, 600), maxHR: 190, restingHR: 60)!
        let long = StrainScorer.strain(hr(185, 1200), maxHR: 190, restingHR: 60)!
        XCTAssertGreaterThan(long, short)
    }

    func testStrainMonotonicInIntensity() {
        // Same duration, higher zone → higher strain.
        let z3 = StrainScorer.strain(hr(155, 600), maxHR: 190, restingHR: 60)!  // ~73% HRR → w3
        let z5 = StrainScorer.strain(hr(185, 600), maxHR: 190, restingHR: 60)!  // ~96% HRR → w5
        XCTAssertGreaterThan(z5, z3)
    }

    func testStrainBanisterAlsoBounded() {
        let s = StrainScorer.strain(hr(185, 600), maxHR: 190, restingHR: 60, method: .banister)!
        XCTAssertGreaterThan(s, 0)
        XCTAssertLessThanOrEqual(s, 21.0)
    }

    func testEstimateHRmaxObservedVsTanaka() {
        // Thin history but known age → tanaka.
        let (v1, src1) = StrainScorer.estimateHRmax([150, 160, 170], age: 30)
        XCTAssertEqual(v1, 187.0, accuracy: 1e-9)
        XCTAssertEqual(src1, "tanaka")

        // No age, no history → unknown.
        let (v2, src2) = StrainScorer.estimateHRmax([150], age: nil)
        XCTAssertEqual(v2, 0.0)
        XCTAssertEqual(src2, "unknown")

        // Dense history with a sustained high tail above tanaka → observed.
        // The 99.5th percentile must exceed 187, so the top ~0.5% must be high:
        // 700 samples, top 10 (>0.5%) at 195 → p99.5 lands in the high tail.
        var hist = Array(repeating: 120.0, count: 690)
        hist.append(contentsOf: Array(repeating: 195.0, count: 10))
        let (v3, src3) = StrainScorer.estimateHRmax(hist, age: 30)
        XCTAssertEqual(src3, "observed")
        XCTAssertGreaterThan(v3, 187.0)
    }

    func testPercentileLinearInterp() {
        XCTAssertEqual(StrainScorer.percentile([10, 20, 30, 40], 50), 25.0, accuracy: 1e-9)
        XCTAssertEqual(StrainScorer.percentile([10, 20, 30, 40], 0), 10.0, accuracy: 1e-9)
        XCTAssertEqual(StrainScorer.percentile([10, 20, 30, 40], 100), 40.0, accuracy: 1e-9)
    }

    func testFitStrainDenominator() throws {
        // Pairs generated from a known D should recover that D.
        let knownD = 5000.0
        func strainFor(_ t: Double) -> Double { 21 * log(t + 1) / log(knownD) }
        let pairs = [(100.0, strainFor(100)), (1000.0, strainFor(1000)), (50.0, strainFor(50))]
        let fitted = try StrainScorer.fitStrainDenominator(pairs)
        XCTAssertEqual(fitted, knownD, accuracy: 1.0)
    }

    func testFitStrainDenominatorThrowsTooFew() {
        XCTAssertThrowsError(try StrainScorer.fitStrainDenominator([(100, 10)]))
    }

    // MARK: - Degenerate HRR guards (FER-36)

    /// A non-positive HR reserve (restingHR ≥ HRmax) must not divide by zero;
    /// %HRR and the Edwards zone weight both collapse to 0.
    func testPctHRRZeroOrNegativeReserveReturnsZero() {
        XCTAssertEqual(StrainScorer.pctHRR(150, restingHR: 60, hrReserve: 0), 0)
        XCTAssertEqual(StrainScorer.pctHRR(150, restingHR: 60, hrReserve: -10), 0)
        XCTAssertEqual(StrainScorer.zoneWeight(150, restingHR: 60, hrReserve: 0), 0)
        XCTAssertEqual(StrainScorer.zoneWeight(150, restingHR: 60, hrReserve: -10), 0)
    }

    // MARK: - Cumulative (intraday) strain (FER-110)

    /// Two-phase 1 Hz series: `nA` samples at `bpmA`, then `nB` at `bpmB`, contiguous in time.
    private func twoPhase(_ bpmA: Int, _ nA: Int, _ bpmB: Int, _ nB: Int) -> [HRSample] {
        hr(bpmA, nA, start: 0) + hr(bpmB, nB, start: nA)
    }

    func testCumulativeStrainEndsAtDailyStrain() {
        // The LAST cumulative point must equal strain() over the SAME window + params, so a chart of
        // the curve lands exactly on the day's score.
        let series = twoPhase(120, 3600, 185, 3600)
        let daily = StrainScorer.strain(series, maxHR: 190, restingHR: 60)!
        let curve = StrainScorer.cumulativeStrain(series, bucketSeconds: 900, maxHR: 190, restingHR: 60)
        XCTAssertFalse(curve.isEmpty)
        XCTAssertEqual(curve.last!.strain, daily, accuracy: 1e-9)
    }

    func testCumulativeStrainEndsAtDailyStrainUnroundedMaxHR() {
        // FER-650: the in-progress day feeds the curve the UNROUNDED effective HRmax (Tanaka is fractional,
        // e.g. 208 − 0.7×33 = 184.9), not the rounded `profile.hrMax`. The invariant must still hold exactly
        // with a fractional maxHR, so the tile/hero (= the last point) can never disagree with the curve.
        let series = twoPhase(120, 3600, 185, 3600)
        let maxHR = StrainScorer.tanakaHRmax(age: 33)     // 184.9 — deliberately non-integer
        let daily = StrainScorer.strain(series, maxHR: maxHR, restingHR: 58)!
        let curve = StrainScorer.cumulativeStrain(series, bucketSeconds: 900, maxHR: maxHR, restingHR: 58)
        XCTAssertFalse(curve.isEmpty)
        XCTAssertEqual(curve.last!.strain, daily, accuracy: 1e-9)
    }

    func testCumulativeStrainBanisterEndsAtDailyStrain() {
        let series = twoPhase(120, 3600, 185, 3600)
        let daily = StrainScorer.strain(series, maxHR: 190, restingHR: 60, method: .banister)!
        let curve = StrainScorer.cumulativeStrain(series, bucketSeconds: 900, maxHR: 190, restingHR: 60, method: .banister)
        XCTAssertEqual(curve.last!.strain, daily, accuracy: 1e-9)
    }

    func testCumulativeStrainMonotonicNonDecreasing() {
        // Accumulated load only ever grows; every point ≥ the previous and within [0, 21].
        let series = twoPhase(120, 3600, 185, 3600)
        let curve = StrainScorer.cumulativeStrain(series, bucketSeconds: 600, maxHR: 190, restingHR: 60)
        XCTAssertGreaterThan(curve.count, 1)
        for i in 1..<curve.count {
            XCTAssertGreaterThanOrEqual(curve[i].strain, curve[i - 1].strain)
            XCTAssertLessThanOrEqual(curve[i].strain, 21.0)
        }
        // Dates are strictly increasing too.
        for i in 1..<curve.count {
            XCTAssertGreaterThan(curve[i].date, curve[i - 1].date)
        }
    }

    func testCumulativeStrainEmptyTooFewReadings() {
        XCTAssertTrue(StrainScorer.cumulativeStrain(hr(150, 599), maxHR: 190, restingHR: 60).isEmpty)
    }

    func testCumulativeStrainEmptyInvalidHRR() {
        XCTAssertTrue(StrainScorer.cumulativeStrain(hr(150, 600), maxHR: 60, restingHR: 60).isEmpty)
    }

    func testCumulativeStrainCoarserBucketsFewerPointsSameEndpoint() {
        let series = twoPhase(120, 3600, 185, 3600)
        let fine = StrainScorer.cumulativeStrain(series, bucketSeconds: 300, maxHR: 190, restingHR: 60)
        let coarse = StrainScorer.cumulativeStrain(series, bucketSeconds: 1800, maxHR: 190, restingHR: 60)
        XCTAssertGreaterThan(fine.count, coarse.count)
        // Bucket size changes the sampling density, never the final accumulated score.
        XCTAssertEqual(fine.last!.strain, coarse.last!.strain, accuracy: 1e-9)
    }

    // MARK: - Sparse-stream gate (FER-659, upstream #482)

    /// `n` samples at a constant bpm spaced `stepSec` apart — the 5/MG's low-cadence live HR.
    private func sparseHr(_ bpm: Int, _ n: Int, stepSec: Int) -> [HRSample] {
        (0..<n).map { HRSample(ts: $0 * stepSec, bpm: bpm) }
    }

    func testStrainSparseStreamAccepted() {
        // 21 zone-5 samples every 30 s (5/MG cadence) span 600 s — scored, not nil, and TRIMP
        // integrates honestly: 21 samples × weight 5 × 0.5 min = 52.5 → 21·ln(53.5)/ln(7201) ≈ 9.41.
        let s = StrainScorer.strain(sparseHr(185, 21, stepSec: 30), maxHR: 190, restingHR: 60)
        XCTAssertNotNil(s)
        XCTAssertEqual(s!, 9.41, accuracy: 1e-2)
    }

    func testStrainSparseTooFewSamplesStillNil() {
        // 19 samples < minSparseReadings — nil even though the span (1080 s) clears minSpanSeconds.
        XCTAssertNil(StrainScorer.strain(sparseHr(150, 19, stepSec: 60), maxHR: 190, restingHR: 60))
    }

    func testStrainSparseShortSpanStillNil() {
        // 20 samples but only 380 s of wall-clock — not yet sustained, still nil.
        XCTAssertNil(StrainScorer.strain(sparseHr(150, 20, stepSec: 20), maxHR: 190, restingHR: 60))
    }

    func testStrainSparseSpanBoundary() {
        // Exactly minSparseReadings samples: 19 steps of 30 s span 570 s (< 600, nil);
        // stretching only the last gap so the span lands exactly on 600 s flips it to scored.
        var justShort = sparseHr(150, 20, stepSec: 30)                 // span 570 → nil
        XCTAssertNil(StrainScorer.strain(justShort, maxHR: 190, restingHR: 60))
        justShort[19] = HRSample(ts: 600, bpm: 150)                    // span 600 → scored
        XCTAssertNotNil(StrainScorer.strain(justShort, maxHR: 190, restingHR: 60))
    }

    func testStrainDenseGateUnchangedBySparsePath() {
        // The dense golden vector must score identically with the sparse gate in place.
        let s = StrainScorer.strain(hr(185, 600), maxHR: 190, restingHR: 60)
        XCTAssertEqual(s!, 9.3, accuracy: 1e-2)
    }

    func testCumulativeStrainSparseEndsAtDailyStrain() {
        // FER-650 invariant on the sparse path too: the curve exists exactly when the score does,
        // and its last point equals strain() over the same window + params.
        let series = sparseHr(140, 40, stepSec: 30)
        let daily = StrainScorer.strain(series, maxHR: 190, restingHR: 60)
        let curve = StrainScorer.cumulativeStrain(series, bucketSeconds: 300, maxHR: 190, restingHR: 60)
        XCTAssertNotNil(daily)
        XCTAssertFalse(curve.isEmpty)
        XCTAssertEqual(curve.last!.strain, daily!, accuracy: 1e-9)
    }

    func testCumulativeStrainSparseRejectedStaysEmpty() {
        // Below the sparse floor the curve stays empty, matching strain() == nil.
        let series = sparseHr(140, 19, stepSec: 60)
        XCTAssertNil(StrainScorer.strain(series, maxHR: 190, restingHR: 60))
        XCTAssertTrue(StrainScorer.cumulativeStrain(series, bucketSeconds: 300, maxHR: 190, restingHR: 60).isEmpty)
    }
}
