import XCTest
@testable import StrandAnalytics

/// Method: an anomaly fires when the recent mean is ≥2σ from the trailing baseline in
/// the concerning direction, where σ is the robust mean-absolute-deviation estimator
/// scaled by 1.253 (E[|X−μ|] = σ·√(2/π) ≈ σ/1.253 for a Gaussian — same convention as
/// `RecoveryScorer`/`Baselines`). The point of FER-300: the SAME absolute Δ must trip a
/// stable user and not a volatile one, because the threshold scales with each person's σ.
final class IllnessWatchTests: XCTestCase {

    /// robustSigma = 1.253 × mean|x−mean|. For [−1, +1] around 0, mean abs-dev = 1 → σ = 1.253.
    func testRobustSigmaMatchesMADScaling() {
        XCTAssertEqual(IllnessWatch.robustSigma([-1, 1]), 1.253, accuracy: 1e-9)
        XCTAssertEqual(IllnessWatch.robustSigma([10, 10, 10]), 0, accuracy: 1e-12)  // flat → no dispersion
        XCTAssertEqual(IllnessWatch.robustSigma([42]), 0)                            // too small to estimate
    }

    /// Fixed vector: two users, IDENTICAL baseline mean (50 bpm) and the SAME recent +5 bpm
    /// jump — but the stable user's baseline barely moves (σ≈0.6) while the volatile user's
    /// swings (σ≈4.4). Old fixed +5 bpm offset would fire for BOTH; z≥2σ fires only the stable one.
    func testStableUserFiresVolatileUserDoesNotForSameDelta() throws {
        let stableBase: [Double]   = [49, 50, 51, 50, 49, 51, 50, 50]   // σ ≈ 0.63
        let volatileBase: [Double] = [44, 56, 47, 53, 45, 55, 50, 50]   // σ ≈ 4.39
        let recentMean = 55.0  // +5 over the shared baseline mean of 50

        let stableZ = try XCTUnwrap(IllnessWatch.concernZ(recentMean: recentMean, base: stableBase, higherIsWorse: true))
        let volatileZ = try XCTUnwrap(IllnessWatch.concernZ(recentMean: recentMean, base: volatileBase, higherIsWorse: true))

        XCTAssertGreaterThanOrEqual(stableZ, IllnessWatch.zThreshold, "stable user: +5 bpm is several σ")
        XCTAssertLessThan(volatileZ, IllnessWatch.zThreshold, "volatile user: +5 bpm is sub-2σ noise")

        XCTAssertTrue(IllnessWatch.isAnomaly(recentMean: recentMean, base: stableBase, higherIsWorse: true))
        XCTAssertFalse(IllnessWatch.isAnomaly(recentMean: recentMean, base: volatileBase, higherIsWorse: true))
    }

    /// "Lower is worse" signal (HRV): a DROP below baseline is the concerning direction.
    func testLowerIsWorseFlipsSign() {
        let base: [Double] = [59, 60, 61, 60, 59, 61, 60, 60]  // mean 60, σ ≈ 0.75
        // A drop to 57 (−3, ≈4σ) is concerning for HRV…
        XCTAssertTrue(IllnessWatch.isAnomaly(recentMean: 57, base: base, higherIsWorse: false))
        // …while a RISE to 63 is not (higher HRV is good).
        XCTAssertFalse(IllnessWatch.isAnomaly(recentMean: 63, base: base, higherIsWorse: false))
    }

    /// A flat or too-small baseline yields no σ → no anomaly (avoids divide-by-zero false alarms).
    func testFlatBaselineNeverFires() {
        XCTAssertNil(IllnessWatch.concernZ(recentMean: 99, base: [50, 50, 50], higherIsWorse: true))
        XCTAssertFalse(IllnessWatch.isAnomaly(recentMean: 99, base: [50, 50, 50], higherIsWorse: true))
    }
}
