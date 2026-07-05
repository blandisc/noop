import Foundation

// HRVSpectralBaseline.swift — "your normal" per-band label for the frequency-domain HRV powers.
//
// The only new logic FER-702 adds: given a band's recent nightly powers (ms²), say whether tonight's
// value is higher / within / lower than the user's OWN normal. It delegates entirely to the shared
// baseline engine (`Baselines.foldHistory` + `deviation`) — no new estimator — and mirrors the
// `VitalBands` convention (fold the history excluding the displayed night, require a trusted baseline,
// threshold at ±`VitalBands.sigmaK`).
//
// WHY LOG-DOMAIN. Frequency-domain HRV powers (LF / HF / total) are strongly right-skewed and
// approximately log-normal — the same reason the time-domain HRV baseline is taken in ln(RMSSD)
// (Plews et al. 2013). Folding in log-domain gives a geometric center and a dispersion in ln-units,
// the appropriate scale for a skewed power; a raw-ms² fold would let a single high night dominate.
//
// NOT autonomic balance. These are descriptive band POWERS compared to your own recent nights, never
// a "sympatho-vagal balance" claim (LF/HF as autonomic balance is contested — Billman 2013). The
// label speaks only in "higher / within / lower than your normal".

public enum HRVSpectralBaseline {

    /// Where tonight's band power falls relative to the user's own recent nights.
    public enum Label: String, Equatable, Sendable {
        case higher   // |z| beyond +sigmaK — higher than your normal
        case normal   // within ±sigmaK of your normal
        case lower    // beyond −sigmaK — lower than your normal
    }

    /// Trailing nights of history the caller slices for the per-band baseline. Matches the vitals
    /// convention of a rolling personal window; the trust gate (≥14 valid nights) lives in `Baselines`.
    public static let historyNights = 30

    /// Per-band baseline config, in log-domain (powers are log-normal). `minVal`/`maxVal` are a
    /// generous ms² plausibility guard so an artifact night can't poison the fold; `floorSpread` is a
    /// dispersion floor in ln-units (~a 15% night-to-night band). These bounds are a science decision
    /// audited by `/cso` against the real ms² range of nightly LF/HF powers.
    public static let bandCfg = MetricCfg(minVal: 1.0, maxVal: 50_000.0, floorSpread: 0.15,
                                          halfLifeB: 14.0, halfLifeS: 21.0, logDomain: true)

    /// Label a band's `value` (ms²) against the user's own recent nightly powers.
    ///
    /// - Parameters:
    ///   - value: tonight's band power (ms²).
    ///   - history: prior nightly powers oldest→newest, EXCLUDING tonight. A nil entry is a missing
    ///     night (use a calendar-padded series so staleness sees wear gaps).
    /// - Returns: the label, or nil when there is no trusted baseline yet (cold-start / calibrating)
    ///   so the UI shows the value without a comparison rather than a fabricated one.
    public static func label(value: Double, history: [Double?]) -> Label? {
        let state = Baselines.foldHistory(history, cfg: bandCfg)
        guard state.trusted else { return nil }   // >= 14 valid nights and not stale
        let z = Baselines.deviation(value, state: state).z
        if z > VitalBands.sigmaK { return .higher }
        if z < -VitalBands.sigmaK { return .lower }
        return .normal
    }
}
