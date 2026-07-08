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
    public let floorSpread: Double  // σ_floor: minimum dispersion (in the metric's CENTER space)
    public let halfLifeB: Double    // baseline-center half-life (nights)
    public let halfLifeS: Double    // spread half-life (nights, slower than center)
    /// Baseline in the natural-log domain. Nightly HRV (RMSSD) is ~log-normal
    /// (Plews et al. 2013, who monitor **lnRMSSD**); centering and z-scoring on the
    /// raw ms biases the center up and underweights low nights. When true, the center
    /// and spread are computed on ln(value): the stored `baseline` is the geometric
    /// mean (back in ms, so display is unchanged), `spread` is the dispersion in ln
    /// units, and `minVal`/`maxVal` stay the ms plausibility gate applied before the
    /// log transform. `floorSpread` is then a floor in ln units, not ms.
    public let logDomain: Bool

    public init(minVal: Double, maxVal: Double, floorSpread: Double,
                halfLifeB: Double, halfLifeS: Double, logDomain: Bool = false) {
        self.minVal = minVal
        self.maxVal = maxVal
        self.floorSpread = floorSpread
        self.halfLifeB = halfLifeB
        self.halfLifeS = halfLifeS
        self.logDomain = logDomain
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
    /// True when this baseline was built in the natural-log domain (HRV): `baseline`
    /// is the geometric mean (ms) and `spread` is the dispersion in ln units, so
    /// `deviation` z-scores on ln(value). Carried so consumers (deviation, the ±σ
    /// band) interpret `spread` in the right space without needing the `MetricCfg`.
    public let logDomain: Bool

    public init(baseline: Double, spread: Double, nValid: Int,
                nightsSinceUpdate: Int, status: BaselineStatus, logDomain: Bool = false) {
        self.baseline = baseline
        self.spread = spread
        self.nValid = nValid
        self.nightsSinceUpdate = nightsSinceUpdate
        self.status = status
        self.logDomain = logDomain
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

    // MARK: - Cold-start anti-anchoring (FER-673)

    /// Center half-life (nights) used while the baseline is still YOUNG (nValid <
    /// minNightsTrust). Much faster than the mature `cfg.halfLifeB` (~14) so a baseline
    /// seeded from artificially-high early nights converges to the true center in days,
    /// not weeks. Without this, a high seed anchors the center and crushes Charge for
    /// ~2-3 weeks. Reverts to `cfg.halfLifeB` once trusted, so mature users are unchanged.
    public static let earlyHalfLifeB: Double = 3.0

    /// Spread-floor multiplier at seed, ramping linearly back to 1.0 at trust. While the
    /// baseline is young the dispersion estimate is unreliable and a too-tight spread both
    /// (a) makes the z extreme (crushing Charge) and (b) narrows the Winsor clamp. Inflating
    /// the floor early keeps the normal-range band honestly wide until enough nights accrue.
    /// At/after trust the multiplier is exactly 1.0, so mature baselines are byte-identical.
    public static let earlySpreadInflation: Double = 1.5

    /// Whether the baseline is still young (has not yet earned full trust). While young the
    /// cold-start anti-anchoring applies: fast center half-life, suspended hard-outlier gate,
    /// inflated spread floor. At/after `minNightsTrust` everything reverts to mature behavior.
    static func isYoung(nValid: Int) -> Bool { nValid < minNightsTrust }

    /// Spread-floor inflation factor for a baseline with `nValid` nights: `earlySpreadInflation`
    /// at (or below) seed, ramping linearly to 1.0 at trust, and exactly 1.0 once trusted.
    /// Mirrors the `confidence` ramp so the two cold-start softenings move together.
    static func spreadInflation(nValid: Int) -> Double {
        if nValid >= minNightsTrust { return 1.0 }
        if nValid <= minNightsSeed { return earlySpreadInflation }
        let frac = Double(nValid - minNightsSeed) / Double(minNightsTrust - minNightsSeed)
        return earlySpreadInflation + (1.0 - earlySpreadInflation) * frac
    }

    /// Default per-metric configurations (HRV, resting HR, respiration, skin temp).
    public static let metricCfg: [String: MetricCfg] = [
        // HRV is baselined in ln(RMSSD): nightly RMSSD is ~log-normal (Plews 2013).
        // floorSpread is now a ln-unit dispersion floor (σ_floor ≈ 1.253 × 0.08 ≈ 0.10,
        // ~a 10% night-to-night band) instead of the old 5 ms.
        "hrv": MetricCfg(minVal: 5.0, maxVal: 250.0, floorSpread: 0.08,
                         halfLifeB: 14.0, halfLifeS: 21.0, logDomain: true),
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

    /// Map a metric value into the space the center/spread live in: ln(value) for a
    /// log-domain metric (HRV), identity otherwise. Inverse of `fromCenter`. Takes the
    /// flag directly so both the build path (`cfg.logDomain`) and the read path
    /// (`state.logDomain`, where no `MetricCfg` is in hand) share one definition.
    static func toCenter(_ v: Double, logDomain: Bool) -> Double {
        logDomain ? Foundation.log(v) : v
    }

    /// Map a center-space value back to the metric's display units (ms for HRV).
    static func fromCenter(_ c: Double, logDomain: Bool) -> Double {
        logDomain ? Foundation.exp(c) : c
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
        let ls = lambda(halfLife: cfg.halfLifeS)

        // First night ever.
        guard let state = state else {
            if let v = value, cfg.minVal <= v && v <= cfg.maxVal {
                return BaselineState(baseline: v, spread: cfg.floorSpread, nValid: 1,
                                     nightsSinceUpdate: 0, status: .calibrating,
                                     logDomain: cfg.logDomain)
            }
            let seed = (cfg.minVal + cfg.maxVal) / 2.0
            return BaselineState(baseline: seed, spread: cfg.floorSpread, nValid: 0,
                                 nightsSinceUpdate: 1, status: .calibrating,
                                 logDomain: cfg.logDomain)
        }

        // Missing night: skip-and-hold.
        guard let value = value else {
            let m = state.nightsSinceUpdate + 1
            return BaselineState(baseline: state.baseline, spread: state.spread,
                                 nValid: state.nValid, nightsSinceUpdate: m,
                                 status: computeStatus(nValid: state.nValid, nightsSinceUpdate: m),
                                 logDomain: state.logDomain)
        }

        // Step 0: sanity gate — physiologically implausible → skip-and-hold. The bounds
        // are ms either way; for a log-domain metric the transform happens only after this.
        if !(cfg.minVal <= value && value <= cfg.maxVal) {
            let m = state.nightsSinceUpdate + 1
            return BaselineState(baseline: state.baseline, spread: state.spread,
                                 nValid: state.nValid, nightsSinceUpdate: m,
                                 status: computeStatus(nValid: state.nValid, nightsSinceUpdate: m),
                                 logDomain: state.logDomain)
        }

        // All center/spread math runs in CENTER space: ln(value) for a log-domain
        // metric (HRV), the raw value otherwise.
        let center = toCenter(value, logDomain: cfg.logDomain)
        let baseCenter = toCenter(state.baseline, logDomain: cfg.logDomain)

        // Hard outlier rejection — MATURE baselines only (FER-673). While the baseline is
        // still young the gate is SUSPENDED: a high early seed would otherwise reject the
        // genuine lower nights that should pull the center down, anchoring it (and crushing
        // Charge) for ~2-3 weeks. Physiological bounds (minVal/maxVal, checked above) still
        // reject the truly impossible; the Winsor clamp below still bounds a spike's pull.
        if !isYoung(nValid: state.nValid) {
            let dev = abs(center - baseCenter)
            if dev > hardOutlierK * state.spread {
                return BaselineState(baseline: state.baseline, spread: state.spread,
                                     nValid: state.nValid, nightsSinceUpdate: 0,
                                     status: computeStatus(nValid: state.nValid, nightsSinceUpdate: 0),
                                     logDomain: state.logDomain)
            }
        }

        // First real value after a None-placeholder seed: treat as clean first night.
        if state.nValid == 0 {
            return BaselineState(baseline: value, spread: cfg.floorSpread, nValid: 1,
                                 nightsSinceUpdate: 0, status: .calibrating,
                                 logDomain: cfg.logDomain)
        }

        // Step 1: Winsorized EWMA update (in center space). While young, use the fast
        // early half-life so a mis-seeded center converges in days, not weeks (FER-673).
        let lb = lambda(halfLife: isYoung(nValid: state.nValid) ? earlyHalfLifeB : cfg.halfLifeB)
        let lo = baseCenter - winsorK * state.spread
        let hi = baseCenter + winsorK * state.spread
        let clamped = max(lo, min(hi, center))
        let newCenter = lb * clamped + (1.0 - lb) * baseCenter

        // Spread uses the UNCLAMPED value so true deviations are tracked. While young the
        // floor is inflated (ramping to 1.0 at trust) so the early band isn't spuriously
        // tight; at/after trust the multiplier is 1.0, so mature spreads are unchanged.
        let absDev = abs(center - newCenter)
        let floor = cfg.floorSpread * spreadInflation(nValid: state.nValid)
        let newSpread = max(floor, ls * absDev + (1.0 - ls) * state.spread)
        let newN = state.nValid + 1

        return BaselineState(baseline: fromCenter(newCenter, logDomain: cfg.logDomain), spread: newSpread, nValid: newN,
                             nightsSinceUpdate: 0,
                             status: computeStatus(nValid: newN, nightsSinceUpdate: 0),
                             logDomain: cfg.logDomain)
    }

    /// Replay an ordered sequence of nightly values (oldest first) to build state.
    /// `nil` entries are treated as missing nights (skip-and-hold).
    public static func foldHistory(_ values: [Double?], cfg: MetricCfg) -> BaselineState {
        var state: BaselineState? = nil
        for v in values { state = update(state, value: v, cfg: cfg) }
        if let s = state { return s }
        let seed = (cfg.minVal + cfg.maxVal) / 2.0
        return BaselineState(baseline: seed, spread: cfg.floorSpread, nValid: 0,
                             nightsSinceUpdate: 0, status: .calibrating,
                             logDomain: cfg.logDomain)
    }

    // MARK: - Deviation

    /// Compute z / delta / ratio / in-normal-range for a value vs a baseline.
    /// z uses (centerValue − centerBaseline) / (1.253 × spread); 1.253 converts
    /// EWMA-abs-dev to an approximate Gaussian σ (E[|X−μ|] = σ·√(2/π) ≈ σ/1.253).
    /// For a log-domain baseline (HRV) the z is taken on ln(value) vs ln(baseline),
    /// so a value at −1σ_ln scores z = −1 symmetrically; `delta` and `ratio` stay in
    /// the metric's display units (ms) for surfaces that show them.
    public static func deviation(_ value: Double, state: BaselineState) -> Deviation {
        let sigma = max(1.253 * state.spread, 1e-9)
        let center = toCenter(value, logDomain: state.logDomain)
        let baseCenter = toCenter(state.baseline, logDomain: state.logDomain)
        let z = (center - baseCenter) / sigma
        let delta = value - state.baseline
        let ratio = state.baseline != 0 ? (value / state.baseline - 1.0) : 0.0
        return Deviation(z: z, delta: delta, ratio: ratio, inNormalRange: abs(z) <= 1.0)
    }

    /// The ±k·σ "normal range" around the baseline, in the metric's display units.
    /// For a log-domain baseline (HRV) the band is multiplicative — exp(lnBaseline ± k·σ_ln)
    /// — so it stays positive and asymmetric in ms, matching the log-normal shape; for a
    /// linear baseline it is the plain baseline ± k·σ. Centralizes the band math so
    /// consumers don't hand-roll `baseline ± 1.253·spread` (which is wrong in log space).
    public static func normalRange(_ state: BaselineState, k: Double = 1.0) -> ClosedRange<Double> {
        let sigma = 1.253 * state.spread
        let c = toCenter(state.baseline, logDomain: state.logDomain)
        let lo = fromCenter(c - k * sigma, logDomain: state.logDomain)
        let hi = fromCenter(c + k * sigma, logDomain: state.logDomain)
        return Swift.min(lo, hi)...Swift.max(lo, hi)
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
                                 nightsSinceUpdate: 0, status: .calibrating,
                                 logDomain: cfg.logDomain)
        }
        let trailing = valid.suffix(window)
        let n = trailing.count
        // Center space: ln(value) for a log-domain metric (HRV), the raw value otherwise.
        // The center maps back to display units via exp() so HRV's baseline is the
        // geometric mean (Plews 2013), not the up-biased arithmetic mean.
        let centers = trailing.map { toCenter($0, logDomain: cfg.logDomain) }
        let mean = centers.reduce(0, +) / Double(n)

        let sd: Double
        if n >= 2 {
            var ss = 0.0
            for c in centers { let d = c - mean; ss += d * d }
            sd = (ss / Double(n - 1)).squareRoot()
        } else {
            // Single sample: no dispersion estimate; fall back to the σ floor.
            sd = cfg.floorSpread * 1.253
        }

        // Floor the spread in the SAME internal abs-dev space the EWMA `update` path uses, so the
        // scoring baseline and this displayed normal-range band agree near the floor: convert the σ to
        // abs-dev (÷1.253), then floor at `floorSpread` exactly like `update` does. Effective σ floor =
        // floorSpread·1.253 (≈0.10 for HRV) — matching `update` and the n<2 fallback above (which was
        // already `floorSpread·1.253`). (Was `max(floorSpread, sd)/1.253`, a σ floor of `floorSpread`
        // ≈0.08 — a 1.253× mismatch vs the scoring path.)
        let spreadInternal = max(cfg.floorSpread, sd / 1.253)

        return BaselineState(baseline: fromCenter(mean, logDomain: cfg.logDomain), spread: spreadInternal, nValid: n,
                             nightsSinceUpdate: 0,
                             status: computeStatus(nValid: n, nightsSinceUpdate: 0),
                             logDomain: cfg.logDomain)
    }
}
