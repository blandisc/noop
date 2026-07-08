import Foundation
import WhoopProtocol

// RecoveryScorer.swift — resting HR during sleep + a transparent 0–100 recovery score.
//
// Ported from server/ingest/app/analysis/recovery.py.
//
// recovery() is a z-score + logistic composite. It is APPROXIMATE — not
// WHOOP-identical (WHOOP's model is proprietary). It is a transparent,
// HRV-dominant, baseline-normalized proxy.
//
// Weighting (documented, grounded, explainable):
//   higher HRV vs baseline       → higher recovery  (W_HRV   = 0.60, dominant)
//   lower resting HR vs baseline → higher recovery  (W_RHR   = 0.20)
//   lower resp vs baseline       → higher recovery  (W_RESP  = 0.05)
//   higher sleep performance     → higher recovery  (W_SLEEP = 0.15)
//   lower skin temp vs baseline  → higher recovery  (W_TEMP  = 0.10, optional)
//
// Each metric is standardized to a robust z-score against the personal baseline
// (mean + EWMA-abs-dev spread). Missing terms are dropped and the weights
// renormalized; the composite is then pulled toward neutral in proportion to the
// driver weight actually present (missing-driver shrinkage, FER-698), so a single
// driver can't saturate the score as if the whole picture agreed. The composite z is
// squashed through a logistic anchored so that Z = 0 → ~58% (WHOOP's self-reported
// member-average recovery — a calibration anchor from WHOOP's own user base, not a
// peer-reviewed population norm).
//
// Cold-start: if the HRV baseline (dominant driver) is not yet usable
// (< MIN_NIGHTS_SEED valid nights), recovery() returns nil. Callers may use
// RECOVERY_POPULATION_MEAN (58.0) as a fallback but should flag it.

public enum RecoveryScorer {

    // MARK: - Constants (recovery.py)

    public static let wHRV: Double = 0.60
    public static let wRHR: Double = 0.20
    public static let wResp: Double = 0.05
    public static let wSleep: Double = 0.15
    /// Skin-temperature term: an elevated nightly skin temp vs personal baseline
    /// (illness, overreaching, alcohol) lowers recovery. Optional — the term drops
    /// and the weights renormalize when no temp value or baseline is available, so
    /// callers that don't supply temperature score exactly as before.
    public static let wTemp: Double = 0.10

    /// Reference weight for the missing-driver shrinkage (FER-698): the three PRIMARY
    /// drivers (HRV + RHR + sleep = 0.95). A composite standing on at least this much
    /// weight counts as full coverage (shrink factor capped at 1.0, unchanged); below it,
    /// the composite z is pulled toward neutral in proportion to the weight present, so a
    /// single strong driver can't saturate the score as if the whole picture agreed.
    /// Resp/temp are optional refinements, excluded from the reference so their absence
    /// never shrinks a band read.
    public static let referenceCoverageWeight: Double = wHRV + wRHR + wSleep   // 0.95

    /// Logistic spread: ±2 z-units ≈ full Red–Green band (15%–95%).
    public static let logisticK: Double = 1.6
    /// Logistic offset so Z=0 → 58%.
    public static let logisticZ0: Double = -0.20
    /// WHOOP self-reported member-average recovery (~58%) — a calibration anchor,
    /// not a peer-reviewed population norm. Cold-start fallback.
    public static let populationMean: Double = 58.0

    /// Recovery band thresholds (WHOOP color scheme).
    public static let bandRedMax: Double = 34.0
    public static let bandYellowMax: Double = 67.0

    /// Sleep-performance center ("good night" at ~85% efficiency).
    public static let sleepPerfCenter: Double = 0.85
    /// Sleep-performance scale (±2 z spans the normal range).
    public static let sleepPerfScale: Double = 0.12

    /// Rolling-mean HR window (seconds) for the resting-HR estimate.
    public static let restingHRWindowS: Int = 5 * 60

    /// A 5-minute bin must hold at least this many HR samples before it can win the
    /// nightly resting-HR floor (FER-674). A bin with a handful of stray samples during
    /// a sensor dropout is not a sustained reading — without this gate the minimum can
    /// latch onto a sparse, unreliable bin and fabricate a sub-physiological RHR.
    public static let restingHRMinBinSamples: Int = 5
    /// A bin's mean must be at least this many bpm to win the floor (FER-674). Nightly
    /// resting HR below ~25 bpm is non-physiological (bradycardia floors well above it);
    /// a bin averaging under this is a dropout/artifact, not a true resting floor, and
    /// must not contaminate the HRV→RHR→Charge chain.
    public static let restingHRMinBpm: Double = 25.0

    // MARK: - Resting HR

    /// Lowest sustained HR during the in-bed window (bpm, rounded), or nil.
    ///
    /// "Sustained" = the minimum over the 5-minute non-overlapping bin means of the HR
    /// samples whose ts ∈ [start, end], counting only bins with at least
    /// `restingHRMinBinSamples` samples AND a mean ≥ `restingHRMinBpm` (FER-674). This
    /// rejects single-beat dips and sparse dropout bins that would otherwise fabricate a
    /// sub-physiological floor. Returns nil when no bin qualifies (no samples in window,
    /// or only sparse/artefactual bins) — an honest "no reliable resting HR" rather than
    /// an impossible number.
    public static func restingHR(_ hr: [HRSample], start: Int, end: Int) -> Int? {
        let seg = hr.filter { $0.ts >= start && $0.ts <= end }
        guard !seg.isEmpty else { return nil }

        var means: [Double] = []
        var t = start
        while t < end {
            let win = seg.filter { $0.ts >= t && $0.ts < t + restingHRWindowS }
            if win.count >= restingHRMinBinSamples {
                let mean = Double(win.reduce(0) { $0 + $1.bpm }) / Double(win.count)
                if mean >= restingHRMinBpm { means.append(mean) }
            }
            t += restingHRWindowS
        }
        // No qualifying bin → no reliable floor (a dropout must not fabricate an RHR).
        guard let floor = means.min() else { return nil }
        return Int(floor.rounded())
    }

    // MARK: - Recovery band

    /// WHOOP-style color band for a recovery score [0, 100].
    public static func band(_ score: Double) -> String {
        if score < bandRedMax { return "red" }
        if score < bandYellowMax { return "yellow" }
        return "green"
    }

    // MARK: - Cold-start calibration progress

    /// Nights carrying a usable nightly HRV — the signal that seeds the recovery baseline. While
    /// recovery is still nil and this count is in [1, seed), it is the honest
    /// "Calibrating — N of <seed> nights" progress the dashboard shows in place of a bare empty
    /// state; nil once recovery exists or no night has data yet. Matches the baseline's validity
    /// predicate, not just non-nil: `Baselines.update` only advances the recovery seed (nValid)
    /// for nights whose value is within the metric config bounds, so an implausible out-of-range
    /// night must NOT be counted here either — else the displayed N could over-state nValid.
    /// Never claims "calibrating" at/above the seed gate (a nil recovery there is some other gap).
    /// Mirrors Android TodayScreen.recoveryCalibrationNights (RecoveryCalibrationTest is the oracle).
    public static func calibrationNights(nightlyHrv: [Double?],
                                         hasRecovery: Bool,
                                         seed: Int = Baselines.minNightsSeed,
                                         cfg: MetricCfg = Baselines.hrvCfg) -> Int? {
        guard !hasRecovery else { return nil }
        let n = nightlyHrv.compactMap { $0 }.filter { $0 >= cfg.minVal && $0 <= cfg.maxVal }.count
        return (1..<seed).contains(n) ? n : nil
    }

    // MARK: - Recovery score

    /// A baseline driver: mean + spread (internal abs-dev units, as in BaselineState).
    public struct DriverBaseline: Equatable, Sendable {
        public let mean: Double
        public let spread: Double
        /// Valid nights behind this baseline; drives confidence shrinkage (FER-13).
        /// Defaults to `minNightsTrust` so callers that build a baseline directly
        /// (e.g. fixed population priors) are treated as fully trusted (no shrinkage).
        public let nValid: Int
        /// True when this driver's baseline lives in the natural-log domain (HRV):
        /// `mean` is the geometric mean (ms), `spread` the dispersion in ln units, so
        /// the z is taken on ln(value) vs ln(mean).
        public let logDomain: Bool
        public init(mean: Double, spread: Double, nValid: Int = Baselines.minNightsTrust,
                    logDomain: Bool = false) {
            self.mean = mean; self.spread = spread; self.nValid = nValid; self.logDomain = logDomain
        }
        public init(_ state: BaselineState) {
            self.mean = state.baseline; self.spread = state.spread
            self.nValid = state.nValid; self.logDomain = state.logDomain
        }
    }

    /// Robust z-score using EWMA spread: (value − mean) / (1.253 × spread). For a
    /// log-domain baseline (HRV) the z is taken on ln(value) vs ln(mean), so a value
    /// at −1σ_ln scores z = −1 symmetrically (Plews 2013).
    static func zScore(_ value: Double, mean: Double, spread: Double, logDomain: Bool = false) -> Double {
        let sigma = max(1.253 * spread, 1e-9)
        if logDomain { return (Foundation.log(value) - Foundation.log(mean)) / sigma }
        return (value - mean) / sigma
    }

    /// Z-score + logistic recovery score in [0, 100]. APPROXIMATE.
    ///
    /// Returns nil when the HRV baseline (dominant driver) is not yet usable, or
    /// no valid driver is available at all.
    ///
    /// - Parameters:
    ///   - hrv: tonight's HRV (RMSSD, ms).
    ///   - rhr: tonight's resting HR (bpm).
    ///   - resp: tonight's respiration (raw or calibrated — z is scale-invariant);
    ///           nil drops the term.
    ///   - hrvBaseline: HRV baseline (required for a score).
    ///   - rhrBaseline: resting-HR baseline; nil drops the RHR term.
    ///   - respBaseline: respiration baseline; nil drops the resp term.
    ///   - sleepPerf: sleep-performance proxy (efficiency 0..1); nil drops the term.
    ///   - hrvBaselineUsable: whether the HRV baseline has enough nights
    ///     (BaselineState.usable). When false, returns nil (cold-start).
    public static func recovery(hrv: Double,
                                rhr: Double,
                                resp: Double?,
                                hrvBaseline: DriverBaseline?,
                                rhrBaseline: DriverBaseline?,
                                respBaseline: DriverBaseline?,
                                sleepPerf: Double?,
                                sleepPerfBaseline: DriverBaseline? = nil,
                                skinTemp: Double? = nil,
                                skinTempBaseline: DriverBaseline? = nil,
                                hrvBaselineUsable: Bool = true) -> Double? {
        // Cold-start gate: HRV is the dominant driver; if its baseline isn't
        // usable, refuse to score (more honest than a fabricated value).
        if !hrvBaselineUsable { return nil }

        var terms: [(z: Double, w: Double)] = []

        // Each personal-baseline z is shrunk toward neutral by Baselines.confidence(nValid)
        // so a thin baseline (few valid nights) can't swing the score (FER-13). A trusted
        // baseline returns confidence 1.0, leaving established users' scores unchanged.

        // HRV term: higher is better. z on ln(HRV) when the baseline is log-domain.
        if let b = hrvBaseline {
            let z = zScore(hrv, mean: b.mean, spread: b.spread, logDomain: b.logDomain) * Baselines.confidence(nValid: b.nValid)
            terms.append((z, wHRV))
        }
        // RHR term: lower is better → (μ − x) / σ.
        // INVARIANT: callers pass a real bpm here ONLY when they also pass an rhrBaseline;
        // when the baseline is nil the RHR term is skipped entirely, so `rhr` is never read
        // (some callers pass a sentinel then — e.g. AppleRecoveryEstimator's `?? .nan`). This
        // precondition forces that invariant: if a future refactor ever reads `rhr` under a
        // present baseline while feeding a non-physiological value, it fails loudly here
        // instead of seeding a silently inflated score.
        if let b = rhrBaseline {
            precondition(rhr.isFinite && rhr > 0, "rhr must be a real bpm when rhrBaseline is present")
            let z = zScore(b.mean, mean: rhr, spread: b.spread) * Baselines.confidence(nValid: b.nValid)
            terms.append((z, wRHR))
        }
        // Resp term: lower is better, optional.
        if let r = resp, let b = respBaseline {
            let z = zScore(b.mean, mean: r, spread: b.spread) * Baselines.confidence(nValid: b.nValid)
            terms.append((z, wResp))
        }
        // Skin-temp term: lower is better (elevated temp = illness / overreaching), optional.
        if let t = skinTemp, let b = skinTempBaseline {
            let z = zScore(b.mean, mean: t, spread: b.spread) * Baselines.confidence(nValid: b.nValid)
            terms.append((z, wTemp))
        }
        // Sleep-performance term. With a personal efficiency baseline, z is measured
        // against the user's OWN normal — consistent with every other driver — so a
        // naturally low (or high) sleeper isn't perpetually penalized (or flattered),
        // and the same confidence shrinkage applies. Without one (cold-start) it falls
        // back to the fixed population center/scale (not a personal baseline, so unshrunk).
        if let sp = sleepPerf {
            let z: Double
            if let b = sleepPerfBaseline {
                z = zScore(sp, mean: b.mean, spread: b.spread) * Baselines.confidence(nValid: b.nValid)
            } else {
                z = (sp - sleepPerfCenter) / sleepPerfScale
            }
            terms.append((z, wSleep))
        }

        guard !terms.isEmpty else { return nil }
        let presentWeight = terms.reduce(0) { $0 + $1.w }
        guard presentWeight > 0 else { return nil }

        // Weighted mean-z of the drivers actually present (renormalized to their own
        // weight, as before).
        let meanZ = terms.reduce(0) { $0 + $1.z * $1.w } / presentWeight
        // Missing-driver shrinkage (FER-698): renormalizing to the present weight lets a
        // single strong driver (e.g. HRV alone in an Apple-Health estimate, where RHR/sleep
        // are absent) speak for the whole composite and saturate the logistic to ~100 as if
        // every driver agreed. Instead, pull the composite toward neutral (Z=0) in
        // proportion to the weight actually present. Reference = the three PRIMARY drivers
        // (HRV+RHR+sleep = 0.95 of the 1.10 max); resp/temp are optional refinements, so a
        // read backed by the primary three counts as full coverage (factor capped at 1.0)
        // and is byte-identical to before — no regression for band users. Same spirit as the
        // thin-baseline shrinkage already applied per term via Baselines.confidence.
        let coverage = min(1.0, presentWeight / referenceCoverageWeight)
        let z = meanZ * coverage
        // A non-finite z (NaN/±inf from a degenerate term) would propagate through
        // the logistic; bail rather than emit a bogus score.
        guard z.isFinite else { return nil }
        let score = 100.0 / (1.0 + exp(-logisticK * (z - logisticZ0)))
        return max(0.0, min(100.0, score))
    }

    /// Convenience overload taking BaselineState directly. Enforces the cold-start
    /// gate using `hrvBaseline.usable`.
    public static func recovery(hrv: Double,
                                rhr: Double,
                                resp: Double?,
                                hrvBaseline: BaselineState,
                                rhrBaseline: BaselineState?,
                                respBaseline: BaselineState?,
                                sleepPerf: Double?,
                                sleepPerfBaseline: BaselineState? = nil,
                                skinTemp: Double? = nil,
                                skinTempBaseline: BaselineState? = nil) -> Double? {
        recovery(hrv: hrv,
                 rhr: rhr,
                 resp: resp,
                 hrvBaseline: DriverBaseline(hrvBaseline),
                 rhrBaseline: rhrBaseline.map(DriverBaseline.init),
                 respBaseline: respBaseline.map(DriverBaseline.init),
                 sleepPerf: sleepPerf,
                 sleepPerfBaseline: sleepPerfBaseline.map(DriverBaseline.init),
                 skinTemp: skinTemp,
                 skinTempBaseline: skinTempBaseline.map(DriverBaseline.init),
                 hrvBaselineUsable: hrvBaseline.usable)
    }
}
