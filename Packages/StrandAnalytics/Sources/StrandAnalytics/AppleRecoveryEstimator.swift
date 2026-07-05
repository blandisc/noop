import Foundation

// AppleRecoveryEstimator.swift — an ESTIMATED recovery for a night that did not come
// from the band, computed from Apple Health's HRV + sleep against the user's OWN Apple
// norm (FER-153, "Capa 2" of the data-source epic FER-483).
//
// THE METHOD, AND WHY IT IS HONEST
// --------------------------------
// Apple Health exposes HRV as **SDNN** (the standard deviation of NN intervals), not
// the **RMSSD** the band-derived recovery uses. This estimator scores tonight's SDNN
// against a baseline built from the user's OWN previous Apple SDNN nights — SDNN-vs-SDNN
// — reusing the EXACT same z-score + logistic model `RecoveryScorer` applies to the
// band's RMSSD. It deliberately does **NOT** convert SDNN→RMSSD: each source is compared
// only against itself ("your HRV today vs your normal HRV", both SDNN). Because the
// z-score is relative (and scale-invariant in the log domain), there is no conversion
// factor — the same RELATIVE deviation produces the same score regardless of the
// absolute ms scale. That is what makes "norma propia" free of a hidden cross-metric bias.
//
// IMPORTANT CONSTRUCT CAVEAT (cited; do not let the copy overclaim) — verified by /cso:
//   • SDNN reflects **total** variability (both sympathetic and parasympathetic);
//     RMSSD reflects the **vagally-mediated** component (Shaffer & Ginsberg 2017,
//     Front Public Health 5:258 — "Both SNS and PNS activity contribute to SDNN";
//     "RMSSD … is the primary time-domain measure used to estimate the vagally
//     mediated changes"). Both are valid time-domain HRV measures (Task Force 1996,
//     Circulation 93(5):1043–1065).
//   • Apple's SDNN is ultra-short (~60 s windows) and aggregated across the whole day,
//     not sleep-windowed. So this estimate is an "autonomic state vs your own Apple
//     norm" proxy — NOT the band's nocturnal-vagal recovery, and a "70" here is NOT
//     interchangeable with a "70" from the band. It is therefore labelled **estimado**
//     with a lower confidence grade wherever it is shown. No clinical/diagnostic claim.
//
// Pure + database-free, like the rest of StrandAnalytics: the app maps each
// `apple-health` daily row into a `Night` and reads the result back; this type never
// touches the store, the strap RMSSD baseline, or the network.

public enum AppleRecoveryEstimator {

    /// One Apple-Health night's inputs (mapped by the app from an `apple-health` daily row).
    public struct Night: Equatable, Sendable {
        public let day: String          // YYYY-MM-DD (the local civil day the night ends on)
        public let hrvSDNN: Double?     // Apple HRV = SDNN (ms). Required for an estimate.
        public let restingHr: Double?   // bpm; optional (the RHR term drops if absent)
        public let resp: Double?        // breaths/min; optional (the resp term drops if absent)
        public let sleepPerf: Double?   // sleep efficiency 0..1; Apple writes nil today → term drops
        public let sleepMinutes: Double?// measured sleep that night; drives the coverage grade
        public init(day: String, hrvSDNN: Double?, restingHr: Double?, resp: Double?,
                    sleepPerf: Double?, sleepMinutes: Double?) {
            self.day = day; self.hrvSDNN = hrvSDNN; self.restingHr = restingHr
            self.resp = resp; self.sleepPerf = sleepPerf; self.sleepMinutes = sleepMinutes
        }
    }

    /// The estimate for one night: a 0–100 score plus its honesty grade.
    public struct DayEstimate: Equatable, Sendable {
        public let day: String
        public let score: Double                 // estimated recovery, 0–100
        public let confidence: ScoreConfidence   // baja=.calibrating · media=.building · alta=.solid
        public init(day: String, score: Double, confidence: ScoreConfidence) {
            self.day = day; self.score = score; self.confidence = confidence
        }
    }

    // MARK: - Confidence knobs (product-calibration, not validated constants)

    /// Apple HRV nights needed for the top grade. Tied to the EWMA baseline's own
    /// "trusted" gate so the grade tracks when the baseline is genuinely settled.
    static let solidNights = Baselines.minNightsTrust          // 14
    /// Apple HRV nights for the middle grade (mirrors the strap's Apple-prior cap of 7).
    static let buildingNights = 7
    // Below `Baselines.minNightsSeed` (4) the baseline isn't usable → no estimate at all.

    /// Minimum measured sleep (minutes) to score a night at all. A loose proxy: Apple's
    /// SDNN is all-day, so below this a night is too thin to stand as a recovery number
    /// (it is OMITTED, UI shows "—"). This is also what suppresses the in-progress current
    /// night just after midnight (only ~2 h logged), which otherwise scored an inflated
    /// "estimado 100" off HRV alone (FER-697). Product-calibration knob, not a validated
    /// threshold.
    static let coverageSleepMinThreshold: Double = 180   // ~3 h

    // MARK: - Estimate

    /// Estimate recovery for each Apple night that has a usable baseline behind it.
    ///
    /// Builds ONE SDNN baseline (plus optional RHR / resp baselines) from these Apple
    /// nights — SEPARATE from the strap's RMSSD baseline, never mixed — and scores each
    /// night against it with `RecoveryScorer`. Nights are scored against the full-window
    /// baseline (same approach as the strap's pass-2 recompute). Returns an estimate ONLY
    /// for nights whose Apple HRV baseline is `usable` (≥ `minNightsSeed` valid SDNN
    /// nights); below that the night is omitted (honest cold-start → the UI shows "—").
    /// A night is ALSO omitted when its measured sleep is below `coverageSleepMinThreshold`
    /// (too thin to score — same "—" as cold-start; see FER-697).
    ///
    /// `nights` must be ordered oldest → newest (the baseline replay is chronological).
    public static func estimate(nights: [Night]) -> [DayEstimate] {
        // SEPARATE Apple baselines — SDNN here is never folded into the band's RMSSD
        // histogram. `hrvCfg` is log-domain (SDNN, like RMSSD, is ~log-normal); its
        // 5–250 ms bounds bracket overnight SDNN.
        let hrvBase = Baselines.foldHistory(nights.map { $0.hrvSDNN }, cfg: Baselines.hrvCfg)
        let rhrBase = Baselines.foldHistory(nights.map { $0.restingHr }, cfg: Baselines.restingHRCfg)
        let respBase = Baselines.foldHistory(nights.map { $0.resp }, cfg: Baselines.respCfg)

        // Cold-start: if the SDNN baseline isn't usable yet, no night can be scored.
        guard hrvBase.usable else { return [] }

        var out: [DayEstimate] = []
        for n in nights {
            guard let sdnn = n.hrvSDNN else { continue }   // HRV is the required driver
            // Coverage gate (FER-697): below the minimum measured sleep the night is too
            // thin to stand as a number — omit it (UI shows "—") rather than emit a score
            // with a merely-lowered confidence grade. This is what suppresses the
            // in-progress current night just after midnight (~2 h logged): with sleep/RHR
            // still absent, HRV alone drove the composite up to an inflated ~100.
            guard (n.sleepMinutes ?? 0) >= coverageSleepMinThreshold else { continue }
            let score = RecoveryScorer.recovery(
                hrv: sdnn,
                rhr: n.restingHr ?? 0,                      // unused when rhrBaseline is nil
                resp: n.resp,
                hrvBaseline: hrvBase,
                rhrBaseline: (n.restingHr != nil && rhrBase.usable) ? rhrBase : nil,
                respBaseline: (n.resp != nil && respBase.usable) ? respBase : nil,
                sleepPerf: n.sleepPerf)
            guard let score else { continue }               // nil = cold-start guard inside the scorer
            out.append(DayEstimate(day: n.day, score: score,
                                   confidence: confidence(hrvBaselineNights: hrvBase.nValid)))
        }
        return out
    }

    /// Confidence grade from how many Apple SDNN nights back the baseline. Coverage is a
    /// hard gate in `estimate` (nights below `coverageSleepMinThreshold` are omitted, not
    /// downgraded), so every scored night has already cleared it — the grade tracks only
    /// how settled the baseline is.
    static func confidence(hrvBaselineNights nValid: Int) -> ScoreConfidence {
        nValid >= solidNights ? .solid
      : nValid >= buildingNights ? .building
      : .calibrating
    }
}
