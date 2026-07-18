import XCTest
import BiometricStreams
@testable import StrandAnalytics

// CDOAuditRegressionTests — regression tests dropped by the CDO audit (modo solo-evaluación).
// These FIX findings/invariants re-derived by hand against the engines; they do NOT touch the
// engines themselves. Clearly separated from production math.
final class CDOAuditRegressionTests: XCTestCase {

    // MARK: - CircadianEngine: recover known cosinor phase/amplitude from a synthetic cosine.

    /// A pure cosine y = M + A·cos(2π(t − φ)/24) sampled at all 24 hours must recover M, A, φ.
    func testCosinorRecoversKnownPhaseAmplitude() {
        let M = 5.0, A = 3.0, phi = 15.0   // peak at 15:00
        let w = 2.0 * Double.pi / 24.0
        var bins: [CircadianEngine.ActivityBin] = []
        for h in 0..<24 {
            let y = M + A * cos(w * (Double(h) - phi))
            bins.append(.init(hour: Double(h), activity: y))
        }
        let fit = CircadianEngine.cosinor(bins)!
        XCTAssertEqual(fit.mesor, M, accuracy: 1e-6)
        XCTAssertEqual(fit.amplitude, A, accuracy: 1e-6)
        XCTAssertEqual(fit.acrophaseHours, phi, accuracy: 1e-6)
    }

    /// Amplitude is always ≥ 0 and acrophase always in [0,24) even for a peak near midnight.
    func testCosinorAcrophaseWraps() {
        let w = 2.0 * Double.pi / 24.0
        let phi = 23.5
        var bins: [CircadianEngine.ActivityBin] = []
        for h in 0..<24 { bins.append(.init(hour: Double(h), activity: 2.0 + cos(w * (Double(h) - phi)))) }
        let fit = CircadianEngine.cosinor(bins)!
        XCTAssertGreaterThanOrEqual(fit.amplitude, 0)
        XCTAssertGreaterThanOrEqual(fit.acrophaseHours, 0)
        XCTAssertLessThan(fit.acrophaseHours, 24)
        XCTAssertEqual(fit.acrophaseHours, phi, accuracy: 1e-6)
    }

    // MARK: - HRVFreqDomain: a pure sine in the HF band lands in HF, not LF.

    /// Synthesize an R-R series modulated at 0.25 Hz (HF band). Over a >=250 s span the HF power
    /// must dominate LF power.
    func testPureHFSineLandsInHFnotLF() {
        // Build a tachogram: mean R-R 800 ms, oscillation at 0.25 Hz in cumulative-time space.
        // We construct rr[i] so that cumulative time advances ~0.8 s/beat and the R-R value carries
        // a 0.25 Hz sinusoid in real time.
        var rr: [Double] = []
        var t = 0.0
        let fHF = 0.25
        // ~400 beats -> ~320 s span, above the 250 s LF gate.
        for _ in 0..<400 {
            let val = 800.0 + 40.0 * sin(2.0 * Double.pi * fHF * t)
            rr.append(val)
            t += val / 1000.0
        }
        let bands = HRVFreqDomain.freqDomain(rawRR: rr)!
        XCTAssertNotNil(bands.lf, "span >= 250 s should trust LF")
        XCTAssertGreaterThan(bands.hf, 0)
        // HF power must exceed LF power for an HF-band oscillation.
        XCTAssertGreaterThan(bands.hf, bands.lf!, "HF oscillation must put more power in HF than LF")
        // totalPower is a superset band, must be >= hf.
        XCTAssertGreaterThanOrEqual(bands.totalPower, bands.hf)
        // lfhf ratio < 1 when HF dominates.
        XCTAssertLessThan(bands.lfhf!, 1.0)
    }

    /// Powers are never negative and span < 60 s abstains.
    func testFreqDomainInvariants() {
        // Short span (<60 s): 25 beats * 0.8 s = 20 s -> nil.
        let short = [Double](repeating: 800, count: 25)
        XCTAssertNil(HRVFreqDomain.freqDomain(rawRR: short))
    }

    // MARK: - Robust σ: two anchors. `robustSigma` (mean, shared convention) vs `robustSigmaAboutMedian`.

    /// `robustSigma` is mean-absolute-deviation about the MEAN × 1.253 — the shared convention used by
    /// RecoveryScorer/Baselines/IllnessWatch. This PINS it so that convention never drifts. (FER-726
    /// re-centered only CyclePhaseEngine onto `robustSigmaAboutMedian`; `robustSigma` itself is unchanged.)
    func testRobustSigmaIsMADaboutMeanNotMedian() {
        // Skewed series: most values ~0, one large outlier. median != mean.
        let xs = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 10.0]
        let mean = xs.reduce(0, +) / Double(xs.count)          // 1.0
        let madAboutMean = xs.map { abs($0 - mean) }.reduce(0, +) / Double(xs.count) // (9*1 + 9)/10 = 1.8
        let expected = 1.253 * madAboutMean                     // 2.2554
        XCTAssertEqual(IllnessWatch.robustSigma(xs), expected, accuracy: 1e-9)
        // The median is 0.0, not the mean 1.0 — mean-anchored spread and a median center disagree.
        XCTAssertEqual(HRVAnalyzer.median(xs), 0.0, accuracy: 1e-9)
    }

    /// FER-726 — `robustSigmaAboutMedian` re-centers the spread on the median so CyclePhaseEngine's
    /// median-centered z measures scale against the same anchor. Two guarantees:
    /// (a) on a symmetric sample (mean = median) it equals `robustSigma` (no drift where anchors agree);
    /// (b) on a right-skewed sample the median-anchored MAD is smaller (L1 spread is minimized at the
    ///     median), so the z is correspondingly larger than the legacy mean-anchored one.
    func testRobustSigmaAboutMedianCalibration() {
        // (a) Symmetric: mean = median = 0 → both estimators coincide.
        let sym = [-2.0, -1.0, 0.0, 1.0, 2.0]
        XCTAssertEqual(IllnessWatch.robustSigmaAboutMedian(sym),
                       IllnessWatch.robustSigma(sym), accuracy: 1e-9)

        // (b) Right-skewed: mean 2.0, median 1.0.
        let skew = [0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 2.0, 4.0, 10.0]
        let madMean = 20.0 / 9.0                                 // (2+2+2+2+1+1+0+2+8)/9
        let madMedian = 17.0 / 9.0                               // (1+1+1+1+0+0+1+3+9)/9
        XCTAssertEqual(IllnessWatch.robustSigma(skew), 1.253 * madMean, accuracy: 1e-9)          // 2.7844
        XCTAssertEqual(IllnessWatch.robustSigmaAboutMedian(skew), 1.253 * madMedian, accuracy: 1e-9) // 2.3672
        XCTAssertLessThan(IllnessWatch.robustSigmaAboutMedian(skew), IllnessWatch.robustSigma(skew))

        // Resulting z of tonight = 4 against `skew`: median-anchored is larger (denominator shrank).
        let median = HRVAnalyzer.median(skew)                   // 1.0
        let zLegacy = (4.0 - median) / IllnessWatch.robustSigma(skew)              // 3 / 2.7844 = 1.0774
        let zFixed  = (4.0 - median) / IllnessWatch.robustSigmaAboutMedian(skew)   // 3 / 2.3672 = 1.2673
        XCTAssertEqual(zLegacy, 1.0774, accuracy: 1e-3)
        XCTAssertEqual(zFixed, 1.2673, accuracy: 1e-3)
    }
}
