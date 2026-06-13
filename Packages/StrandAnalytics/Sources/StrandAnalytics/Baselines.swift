import Foundation

// Baselines.swift — personal rolling baselines per nightly metric.
//
// Ported from server/ingest/app/analysis/baselines.py.
//
// Two paths are provided:
//   1. Winsorized EWMA (the production model): robust, recency-weighted center
//      with an EWMA-of-absolute-deviation spread tracker, cold-start gating, hard
//      outlier rejection, and Winsor clamping. This is `update`/`foldHistory`.
//   2. Trailing-window mean/SD (the task's "trailing 30-day mean/SD"): a simple,
//      auditable rolling mean and sample SD over the trailing N valid nights.
//      This is `rollingMeanSD`. Useful for explainability and cross-checking.
//
// Both produce a `BaselineState` so RecoveryScorer can consume either uniformly.

/// Per-metric configuration for the baseline model.
public struct MetricCfg: Equatable, Sendable {
    public let minVal: Double       // physiological lower bound (hard reject below)
    public let maxVal: Double       // physiological upper bound (hard reject above)
    public let floorSpread: Double  // σ_floor: minimum dispersion
    public let halfLifeB: Double    // baseline-center half-life (nights)
    public let halfLifeS: Double    // spread half-life (nights, slower than center)

    public init(minVal: Double, maxVal: Double, floorSpread: Double,
                halfLifeB: Double, halfLifeS: Double) {
        self.minVal = minVal
        self.maxVal = maxVal
        self.floorSpread = floorSpread
        self.halfLifeB = halfLifeB
        self.halfLifeS = halfLifeS
    }
}

/// Baseline status flags (cold-start → trusted → stale).
public enum BaselineStatus: String, Equatable, Sendable {
    case calibrating  // fewer than MIN_NIGHTS_SEED valid nights; no score yet
    case provisional  // between seed and trust thresholds; usable, higher uncertainty
    case trusted      // at least MIN_NIGHTS_TRUST valid nights
    case stale        // usable but no update for > STALE_DAYS nights
}

/// Immutable snapshot of a personal baseline for one metric after N nights.
public struct BaselineState: Equatable, Sendable {
    /// Robust EWMA center (the personal "mean").
    public let baseline: Double
    /// EWMA of absolute deviations, floored at cfg.floorSpread. Multiply by 1.253
    /// to approximate Gaussian σ.
    public let spread: Double
    /// Count of valid nights contributing to the state.
    public let nValid: Int
    /// Consecutive nights with no valid value (staleness tracking).
    public let nightsSinceUpdate: Int
    /// Cold-start / staleness status.
    public let status: BaselineStatus

    public init(baseline: Double, spread: Double, nValid: Int,
                nightsSinceUpdate: Int, status: BaselineStatus) {
        self.baseline = baseline
        self.spread = spread
        self.nValid = nValid
        self.nightsSinceUpdate = nightsSinceUpdate
        self.status = status
    }

    /// True iff fully trusted (not calibrating or stale).
    public var trusted: Bool { status == .trusted }
    /// True iff at least provisionally usable (nValid ≥ MIN_NIGHTS_SEED).
    public var usable: Bool { status == .provisional || status == .trusted }
}

/// Three forms of deviation from a personal baseline.
public struct Deviation: Equatable, Sendable {
    /// Robust z-score: (value − baseline) / (1.253 × spread).
    public let z: Double
    /// Signed physical-units delta: value − baseline.
    public let delta: Double
    /// Fractional deviation: value / baseline − 1.
    public let ratio: Double
    /// True iff |z| ≤ 1.0.
    public let inNormalRange: Bool

    public init(z: Double, delta: Double, ratio: Double, inNormalRange: Bool) {
        self.z = z; self.delta = delta; self.ratio = ratio
        self.inNormalRange = inNormalRange
    }
}

public enum Baselines {

    // MARK: - Constants (baselines.py)

    /// Winsorization clamp: fold only within ±WINSOR_K × spread.
    public static let winsorK: Double = 3.0
    /// Hard-reject gate: drop the night if > HARD_OUTLIER_K × spread away.
    public static let hardOutlierK: Double = 5.0
    /// Minimum valid nights before "provisionally" trusted.
    public static let minNightsSeed: Int = 4
    /// Minimum valid nights before fully trusted.
    public static let minNightsTrust: Int = 14
    /// Missing-night count after which a baseline is marked stale.
    public static let staleDays: Int = 14

    /// Default per-metric configurations (HRV, resting HR, respiration, skin temp).
    public static let metricCfg: [String: MetricCfg] = [
        "hrv": MetricCfg(minVal: 5.0, maxVal: 250.0, floorSpread: 5.0,
                         halfLifeB: 14.0, halfLifeS: 21.0),
        "resting_hr": MetricCfg(minVal: 30.0, maxVal: 120.0, floorSpread: 2.0,
                                halfLifeB: 14.0, halfLifeS: 21.0),
        "resp": MetricCfg(minVal: 4.0, maxVal: 40.0, floorSpread: 0.5,
                          halfLifeB: 14.0, halfLifeS: 21.0),
        "skin_temp": MetricCfg(minVal: 20.0, maxVal: 42.0, floorSpread: 0.3,
                               halfLifeB: 14.0, halfLifeS: 21.0),
        "efficiency": MetricCfg(minVal: 0.2, maxVal: 1.0, floorSpread: 0.03,
                                halfLifeB: 14.0, halfLifeS: 21.0),
    ]

    /// Convenience accessors for the standard configs.
    public static var hrvCfg: MetricCfg { metricCfg["hrv"]! }
    public static var restingHRCfg: MetricCfg { metricCfg["resting_hr"]! }
    public static var respCfg: MetricCfg { metricCfg["resp"]! }

    /// Convert a half-life in nights to an EWMA smoothing factor.
    static func lambda(halfLife: Double) -> Double {
        1.0 - pow(0.5, 1.0 / halfLife)
    }

    static func computeStatus(nValid: Int, nightsSinceUpdate: Int) -> BaselineStatus {
        if nightsSinceUpdate > staleDays && nValid >= minNightsSeed { return .stale }
        if nValid < minNightsSeed { return .calibrating }
        if nValid < minNightsTrust { return .provisional }
        return .trusted
    }

    /// Confidence weight at `nValid` valid nights (FER-13). The lowest weight a
    /// usable baseline ever earns: a freshly-seeded baseline (nValid == minNightsSeed)
    /// counts for this fraction of its z-score; from there it ramps linearly to 1.0.
    public static let confidenceFloor: Double = 0.5

    /// Shrinkage weight in [confidenceFloor, 1] for a baseline with `nValid` nights.
    ///
    /// Multiply a z-score by this to pull thin-evidence signals toward neutral so the
    /// recovery/readiness engine doesn't over-react to a value measured against a
    /// barely-seeded baseline. Ramps linearly from `confidenceFloor` at `minNightsSeed`
    /// (the first night a score appears) to 1.0 at `minNightsTrust`. A fully trusted
    /// baseline (nValid ≥ minNightsTrust) returns 1.0 — no shrinkage, so established
    /// users are unaffected.
    public static func confidence(nValid: Int) -> Double {
        if nValid >= minNightsTrust { return 1.0 }
        if nValid <= minNightsSeed { return confidenceFloor }
        let frac = Double(nValid - minNightsSeed) / Double(minNightsTrust - minNightsSeed)
        return confidenceFloor + (1.0 - confidenceFloor) * frac
    }

    // MARK: - Winsorized EWMA update (production model)

    /// Incorporate one new nightly value into the baseline state.
    ///
    /// - `state == nil`: seed the first night.
    /// - `value == nil` or out-of-range: skip-and-hold (carry forward).
    /// - hard outlier (> HARD_OUTLIER_K × spread): seen but not folded.
    /// - otherwise: Winsorized EWMA center + EWMA-abs-dev spread update.
    public static func update(_ state: BaselineState?, value: Double?, cfg: MetricCfg) -> BaselineState {
        let lb = lambda(halfLife: cfg.halfLifeB)
        let ls = lambda(halfLife: cfg.halfLifeS)

        // First night ever.
        guard let state = state else {
            if let v = value, cfg.minVal <= v && v <= cfg.maxVal {
                return BaselineState(baseline: v, spread: cfg.floorSpread, nValid: 1,
                                     nightsSinceUpdate: 0, status: .calibrating)
            }
            let seed = (cfg.minVal + cfg.maxVal) / 2.0
            return BaselineState(baseline: seed, spread: cfg.floorSpread, nValid: 0,
                                 nightsSinceUpdate: 1, status: .calibrating)
        }

        // Missing night: skip-and-hold.
        guard let value = value else {
            let m = state.nightsSinceUpdate + 1
            return BaselineState(baseline: state.baseline, spread: state.spread,
                                 nValid: state.nValid, nightsSinceUpdate: m,
                                 status: computeStatus(nValid: state.nValid, nightsSinceUpdate: m))
        }

        // Step 0: sanity gate — physiologically implausible → skip-and-hold.
        if !(cfg.minVal <= value && value <= cfg.maxVal) {
            let m = state.nightsSinceUpdate + 1
            return BaselineState(baseline: state.baseline, spread: state.spread,
                                 nValid: state.nValid, nightsSinceUpdate: m,
                                 status: computeStatus(nValid: state.nValid, nightsSinceUpdate: m))
        }

        // Hard outlier rejection (only once seeded): seen, but not folded.
        if state.nValid >= minNightsSeed {
            let dev = abs(value - state.baseline)
            if dev > hardOutlierK * state.spread {
                return BaselineState(baseline: state.baseline, spread: state.spread,
                                     nValid: state.nValid, nightsSinceUpdate: 0,
                                     status: computeStatus(nValid: state.nValid, nightsSinceUpdate: 0))
            }
        }

        // First real value after a None-placeholder seed: treat as clean first night.
        if state.nValid == 0 {
            return BaselineState(baseline: value, spread: cfg.floorSpread, nValid: 1,
                                 nightsSinceUpdate: 0, status: .calibrating)
        }

        // Step 1: Winsorized EWMA update.
        let lo = state.baseline - winsorK * state.spread
        let hi = state.baseline + winsorK * state.spread
        let clamped = max(lo, min(hi, value))
        let newBaseline = lb * clamped + (1.0 - lb) * state.baseline

        // Spread uses the UNCLAMPED value so true deviations are tracked.
        let absDev = abs(value - newBaseline)
        let newSpread = max(cfg.floorSpread, ls * absDev + (1.0 - ls) * state.spread)
        let newN = state.nValid + 1

        return BaselineState(baseline: newBaseline, spread: newSpread, nValid: newN,
                             nightsSinceUpdate: 0,
                             status: computeStatus(nValid: newN, nightsSinceUpdate: 0))
    }

    /// Replay an ordered sequence of nightly values (oldest first) to build state.
    /// `nil` entries are treated as missing nights (skip-and-hold).
    public static func foldHistory(_ values: [Double?], cfg: MetricCfg) -> BaselineState {
        var state: BaselineState? = nil
        for v in values { state = update(state, value: v, cfg: cfg) }
        if let s = state { return s }
        let seed = (cfg.minVal + cfg.maxVal) / 2.0
        return BaselineState(baseline: seed, spread: cfg.floorSpread, nValid: 0,
                             nightsSinceUpdate: 0, status: .calibrating)
    }

    // MARK: - Deviation

    /// Compute z / delta / ratio / in-normal-range for a value vs a baseline.
    /// z uses (value − baseline) / (1.253 × spread); 1.253 converts EWMA-abs-dev
    /// to an approximate Gaussian σ (E[|X−μ|] = σ·√(2/π) ≈ σ/1.253).
    public static func deviation(_ value: Double, state: BaselineState) -> Deviation {
        let sigma = max(1.253 * state.spread, 1e-9)
        let z = (value - state.baseline) / sigma
        let delta = value - state.baseline
        let ratio = state.baseline != 0 ? (value / state.baseline - 1.0) : 0.0
        return Deviation(z: z, delta: delta, ratio: ratio, inNormalRange: abs(z) <= 1.0)
    }

    // MARK: - Trailing-window mean/SD (simple, auditable)

    /// Rolling personal baseline from the trailing `window` valid nights, as a
    /// plain mean and sample SD (ddof=1). This is the task's "trailing 30-day
    /// mean/SD" path: no recency weighting, maximally explainable.
    ///
    /// Physiologically implausible values (outside cfg bounds) and nils are
    /// dropped. The spread returned is stored in the SAME internal units the
    /// Winsor EWMA uses (abs-dev space), i.e. SD / 1.253, so that
    /// `deviation()` recovers the intended Gaussian σ unchanged.
    ///
    /// - Parameters:
    ///   - values: ordered nightly values (oldest → newest); nils allowed.
    ///   - cfg: metric config (bounds + floor spread).
    ///   - window: number of trailing valid nights to use (default 30).
    public static func rollingMeanSD(_ values: [Double?], cfg: MetricCfg, window: Int = 30) -> BaselineState {
        let valid = values.compactMap { v -> Double? in
            guard let v = v, cfg.minVal <= v && v <= cfg.maxVal else { return nil }
            return v
        }
        guard !valid.isEmpty else {
            let seed = (cfg.minVal + cfg.maxVal) / 2.0
            return BaselineState(baseline: seed, spread: cfg.floorSpread, nValid: 0,
                                 nightsSinceUpdate: 0, status: .calibrating)
        }
        let trailing = valid.suffix(window)
        let n = trailing.count
        let mean = trailing.reduce(0, +) / Double(n)

        let sd: Double
        if n >= 2 {
            var ss = 0.0
            for v in trailing { let d = v - mean; ss += d * d }
            sd = (ss / Double(n - 1)).squareRoot()
        } else {
            // Single sample: no dispersion estimate; fall back to the σ floor.
            sd = cfg.floorSpread * 1.253
        }

        // Apply the σ floor in σ-space, then convert to internal abs-dev space.
        let sigmaFloored = max(cfg.floorSpread, sd)
        let spreadInternal = sigmaFloored / 1.253

        return BaselineState(baseline: mean, spread: spreadInternal, nValid: n,
                             nightsSinceUpdate: 0,
                             status: computeStatus(nValid: n, nightsSinceUpdate: 0))
    }
}
