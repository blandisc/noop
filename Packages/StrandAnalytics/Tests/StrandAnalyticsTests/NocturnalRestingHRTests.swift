import XCTest
@testable import StrandAnalytics

final class NocturnalRestingHRTests: XCTestCase {

    // MARK: - Helpers

    private func sample(ts: Int = 0, bpm: Double, deep: Bool) -> NocturnalRestingHR.Sample {
        NocturnalRestingHR.Sample(ts: ts, bpm: bpm, deep: deep)
    }

    /// `count` deep samples with ascending bpm starting at `base` (base, base+1, …).
    private func deepCluster(count: Int, base: Double = 50, ts0: Int = 0) -> [NocturnalRestingHR.Sample] {
        (0..<count).map { i in
            sample(ts: ts0 + i, bpm: base + Double(i), deep: true)
        }
    }

    // MARK: - A1: Prefer deep-only when deep ≥ minSamples

    func testA1_deepOnlyIgnoresHighAwakeOutlier() {
        // 20 deep samples with a known distribution; one very-high awake sample that must
        // not move the result when the deep path is taken.
        let deep = deepCluster(count: 20, base: 50) // 50…69
        let awakeOutlier = sample(ts: 10_000, bpm: 110, deep: false)
        let mixed = deep + [awakeOutlier]

        let result = NocturnalRestingHR.estimate(mixed)
        let deepOnly = NocturnalRestingHR.estimate(deep)

        XCTAssertNotNil(result)
        XCTAssertNotNil(deepOnly)
        // High awake outlier must not move the deep-only quantile at all.
        XCTAssertEqual(result!, deepOnly!, accuracy: 1e-12)

        // Hand check: n=20 deep, q=0.125 → index = 0.125*19 = 2.375
        // sorted[2]=52, sorted[3]=53 → 52 + 0.375*(53-52) = 52.375
        XCTAssertEqual(result!, 52.375, accuracy: 1e-9)
    }

    // MARK: - A2: Fallback to whole window when deep < minSamples

    func testA2_fallbackToWholeWindowWhenDeepSparse() {
        // 10 deep + 15 non-deep = 25 filtered (≥ 20), but deep alone is below minSamples →
        // must fall back to the WHOLE filtered window (not return nil, not use deep alone).
        var samples: [NocturnalRestingHR.Sample] = []
        for i in 0..<10 {
            samples.append(sample(ts: i, bpm: 48 + Double(i), deep: true)) // 48…57
        }
        for i in 0..<15 {
            samples.append(sample(ts: 100 + i, bpm: 70 + Double(i), deep: false)) // 70…84
        }

        let result = NocturnalRestingHR.estimate(samples)
        XCTAssertNotNil(result, "≥20 filtered total should emit even with sparse deep")

        // Deep-only has only 10 samples → would be nil if called alone.
        let deepOnly = samples.filter(\.deep)
        XCTAssertLessThan(deepOnly.count, NocturnalRestingHR.minSamples)
        XCTAssertNil(NocturnalRestingHR.estimate(deepOnly))

        // Whole-window hand computation (proves fallback, not deep-only without the gate):
        // sorted n=25: 48…57, 70…84. index = 0.125*(25-1) = 3.0 → sorted[3] = 51.
        // (Deep-only type-7 on 10 values would be index=0.125*9=1.125 → 48.125 — different.)
        XCTAssertEqual(result!, 51.0, accuracy: 1e-9)
    }

    // MARK: - A3: Insufficient filtered samples → nil

    func testA3_insufficientSamplesReturnsNil() {
        let samples = deepCluster(count: 19, base: 55)
        XCTAssertEqual(samples.count, 19)
        XCTAssertNil(NocturnalRestingHR.estimate(samples))
    }

    // MARK: - A4: Robustness vs raw minimum

    func testA4_quantileNotEqualToRawMinimum() {
        // Cluster ~55 bpm (plenty of points) plus one isolated low in-range outlier (32).
        // 32 survives the [30,120] filter but must not become the estimate (unlike raw min).
        var samples: [NocturnalRestingHR.Sample] = []
        samples.append(sample(ts: 0, bpm: 32, deep: true)) // physiological outlier, in range
        for i in 0..<25 {
            // Tight cluster around 55 (54, 55, 56 cycling).
            let bpm = 54.0 + Double(i % 3)
            samples.append(sample(ts: 1 + i, bpm: bpm, deep: true))
        }

        let values = samples.map(\.bpm)
        let rawMin = values.min()!
        XCTAssertEqual(rawMin, 32, accuracy: 1e-12)

        let result = NocturnalRestingHR.estimate(samples)
        XCTAssertNotNil(result)
        // Quantile stays near the ~55 cluster, clearly not the raw minimum.
        XCTAssertNotEqual(result!, rawMin, accuracy: 1e-9)
        XCTAssertGreaterThan(result!, 50)
        XCTAssertLessThan(result!, 58)
    }

    // MARK: - A5: Artifact filter before minSamples count

    func testA5_outOfRangeExcludedBeforeMinSamplesAndResult() {
        // Without exclusion: 15 valid + 10 out-of-range = 25 raw samples (≥ 20).
        // After correct exclusion: 15 valid → below minSamples → nil.
        var thin: [NocturnalRestingHR.Sample] = []
        for i in 0..<15 {
            thin.append(sample(ts: i, bpm: 55 + Double(i % 5), deep: true))
        }
        for i in 0..<5 {
            thin.append(sample(ts: 100 + i, bpm: 20, deep: true))  // below 30
            thin.append(sample(ts: 200 + i, bpm: 150, deep: true)) // above 120
        }
        XCTAssertEqual(thin.count, 25, "raw count would clear minSamples if unfiltered")
        XCTAssertNil(
            NocturnalRestingHR.estimate(thin),
            "out-of-range must be dropped before minSamples is evaluated"
        )

        // Separately: enough valid samples so we emit; out-of-range must not move the number.
        let valid = deepCluster(count: 20, base: 50) // known p12.5 = 52.375
        let polluted = valid + [
            sample(ts: 9_000, bpm: 20, deep: true),
            sample(ts: 9_001, bpm: 150, deep: true),
            sample(ts: 9_002, bpm: 10, deep: false),
            sample(ts: 9_003, bpm: 200, deep: false),
        ]
        let clean = NocturnalRestingHR.estimate(valid)
        let withJunk = NocturnalRestingHR.estimate(polluted)
        XCTAssertNotNil(clean)
        XCTAssertNotNil(withJunk)
        XCTAssertEqual(withJunk!, clean!, accuracy: 1e-12)
        XCTAssertEqual(withJunk!, 52.375, accuracy: 1e-9)
    }

    // MARK: - A6: R type-7 quantile pin (hand-computed)

    func testA6_type7QuantileHandComputedPin() {
        // Hand-picked vector of n=20 ascending bpm values: 50, 51, …, 69.
        // R type-7 / numpy linear at q=0.125:
        //   index = q * (n - 1) = 0.125 * 19 = 2.375
        //   floor = 2, ceil = 3
        //   sorted[2] = 52, sorted[3] = 53
        //   result = 52 + 0.375 * (53 - 52) = 52.375
        let samples = deepCluster(count: 20, base: 50)
        let expected = 52.375

        let result = NocturnalRestingHR.estimate(samples)
        XCTAssertNotNil(result)
        XCTAssertEqual(result!, expected, accuracy: 1e-9)

        // Second pin with fractional interpolation that is not a half-step:
        // n=21 values 40…60, index = 0.125 * 20 = 2.5
        // sorted[2]=42, sorted[3]=43 → 42 + 0.5*(43-42) = 42.5
        let samples21 = deepCluster(count: 21, base: 40)
        let result21 = NocturnalRestingHR.estimate(samples21)
        XCTAssertNotNil(result21)
        XCTAssertEqual(result21!, 42.5, accuracy: 1e-9)
    }
}
