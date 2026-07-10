import Foundation

/// Illness / strain early-warning thresholds, expressed in the user's OWN dispersion.
///
/// Each watched signal (resting HR, HRV, skin-temp deviation, respiration) fires an
/// anomaly when its recent mean sits **≥ 2σ** away — in the direction of concern —
/// from the trailing baseline, where σ is the baseline's own robust dispersion.
/// This replaces fixed absolute offsets (+5 bpm, ×0.80, …): for a very stable user a
/// +5 bpm jump is several σ (a real signal), while for a volatile user the same +5 bpm
/// is sub-σ noise. Anchoring to σ makes the trigger comparable across people.
///
/// σ is the robust mean-absolute-deviation estimator scaled by 1.253, the same
/// convention used by `RecoveryScorer`/`Baselines` (E[|X−μ|] = σ·√(2/π) ≈ σ/1.253 for
/// a Gaussian). APPROXIMATE — a wellness nudge from personal baselines, not a clinical
/// screen.
public enum IllnessWatch {
    /// z-score that fires an anomaly. 2σ ≈ the 2.3% one-sided tail of a Gaussian.
    public static let zThreshold = 2.0

    /// Robust σ of a baseline sample: 1.253 × mean(|x − mean|). Returns 0 when the
    /// sample is too small to estimate dispersion (caller treats 0 as "not estimable").
    public static func robustSigma(_ sample: [Double]) -> Double {
        guard sample.count >= 2 else { return 0 }
        let mean = sample.reduce(0, +) / Double(sample.count)
        let mad = sample.map { abs($0 - mean) }.reduce(0, +) / Double(sample.count)
        return 1.253 * mad
    }

    /// Robust σ anchored on the MEDIAN: 1.253 × mean(|x − median|). Same mean-of-absolute-deviations
    /// estimator and 1.253 scale as `robustSigma`, only re-centered — so a z-score whose numerator is
    /// centered on the median measures its spread against the same anchor (consistent robustness),
    /// instead of anchoring the spread on the mean (which the median-centered numerator ignores). On a
    /// symmetric sample (mean = median) it equals `robustSigma`. Deliberately NOT the classic MAD
    /// (median-of-absolute-deviations), which degenerates to 0 on low-variation samples like `[0×9, 10]`.
    /// Returns 0 when the sample is too small to estimate dispersion.
    static func robustSigmaAboutMedian(_ sample: [Double]) -> Double {
        guard sample.count >= 2 else { return 0 }
        let m = HRVAnalyzer.median(sample)
        let mad = sample.map { abs($0 - m) }.reduce(0, +) / Double(sample.count)
        return 1.253 * mad
    }

    /// A recent value's deviation from its baseline: the concern-oriented z-score plus the
    /// baseline mean it was measured against (so callers don't re-walk the sample to label it).
    public struct Deviation {
        public let z: Double
        public let baseMean: Double
    }

    /// Deviation of `recentMean` from the baseline sample, oriented so a higher `z` means
    /// "more concerning". For `higherIsWorse` signals (RHR, skin temp, respiration)
    /// z = (recent − baseMean)/σ; for "lower is worse" signals (HRV) the sign is flipped.
    /// Returns nil when σ is not estimable (flat or too-small baseline).
    public static func deviation(recentMean: Double, base: [Double], higherIsWorse: Bool) -> Deviation? {
        let sigma = robustSigma(base)
        guard sigma > 1e-9, !base.isEmpty else { return nil }
        let baseMean = base.reduce(0, +) / Double(base.count)
        let z = (recentMean - baseMean) / sigma
        return Deviation(z: higherIsWorse ? z : -z, baseMean: baseMean)
    }

    /// Concern-oriented z-score; nil when σ is not estimable. See `deviation`.
    public static func concernZ(recentMean: Double, base: [Double], higherIsWorse: Bool) -> Double? {
        deviation(recentMean: recentMean, base: base, higherIsWorse: higherIsWorse)?.z
    }

    /// True when `recentMean` is at least `zThreshold` σ in the concerning direction.
    public static func isAnomaly(recentMean: Double, base: [Double], higherIsWorse: Bool) -> Bool {
        guard let z = concernZ(recentMean: recentMean, base: base, higherIsWorse: higherIsWorse) else { return false }
        return z >= zThreshold
    }
}
