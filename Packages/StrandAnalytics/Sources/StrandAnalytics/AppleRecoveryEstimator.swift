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

    /// Where one present primary driver sits relative to the user's OWN Apple norm, for the estimated
    /// coverage-attribution surface. DELIBERATELY carries no point magnitude / additive share: an estimate
    /// (SDNN vs your own SDNN) must not imply the band path's precise per-signal decomposition
    /// (`RecoveryImpact`), which is why that path returns nil for an Apple-only day. Only the honest facts
    /// an Apple-vs-own-Apple-norm comparison supports: WHERE the raw signal sits, and whether that HELPS or
    /// HURTS recovery. Same orientation the band decomposition uses (HRV↑ helps · resting HR↓ helps · sleep↑
    /// helps). `inRange` = within ~1σ of the user's usual (the band path's «in your base» deadband).
    public struct SignalDirection: Equatable, Sendable, Identifiable {
        public enum Position: String, Equatable, Sendable { case above, below, inRange }
        public let key: String          // "hrv" | "rhr" | "sleep"
        /// Where the RAW signal sits vs its own Apple baseline (+ = above your usual value).
        public let position: Position
        /// Whether that position helps recovery (oriented): HRV above helps; resting HR below helps; sleep
        /// above helps. Carries the valence the row color reads, independent of `position`.
        public let helps: Bool
        /// True only when `position` is measured against the user's OWN Apple baseline (HRV, resting HR).
        /// Sleep has no personal Apple sleep baseline (Apple writes no efficiency today), so its position is
        /// taken against a FIXED population center — that's «vs typical», not «vs your usual». The UI reads
        /// this to show sleep as PRESENCE-ONLY (no above/below word), so the «vs your normal» copy is never
        /// overstated for a signal that wasn't compared to the user's own norm. (CSO finding, gate 9542ba19)
        public let hasPersonalNorm: Bool
        public var id: String { key }
        public init(key: String, position: Position, helps: Bool, hasPersonalNorm: Bool = true) {
            self.key = key; self.position = position; self.helps = helps
            self.hasPersonalNorm = hasPersonalNorm
        }
    }

    /// The estimate for one night: a 0–100 score plus its honesty grade.
    public struct DayEstimate: Equatable, Sendable {
        public let day: String
        public let score: Double                 // estimated recovery, 0–100
        public let confidence: ScoreConfidence   // baja=.calibrating · media=.building · alta=.solid
        /// How many of the THREE primary recovery drivers (HRV, resting HR, sleep) actually
        /// backed this night's score — the same coverage the FER-698 missing-driver shrinkage
        /// keys on (`RecoveryScorer.referenceCoverageWeight`). HRV is required for any estimate,
        /// so this is 1…3. Surfaced so the UI can say WHY an estimate is conservative
        /// («Estimado — 1 de 3 señales», FER-700) rather than only shrinking the number. The
        /// grade in `confidence` measures a DIFFERENT thing (how settled the HRV baseline is),
        /// so the two are reported side by side, not merged.
        public let presentPrimaryDrivers: Int
        /// The present primary drivers' directions vs the user's own Apple norm (HRV always first), for the
        /// estimated coverage-attribution block. `count == presentPrimaryDrivers`; absent drivers are simply
        /// not listed (the UI shows them attenuated with a reason). Empty on the fixture/init default.
        public let signalDirections: [SignalDirection]
        /// The total primary drivers coverage is measured against (always 3: HRV, RHR, sleep).
        public static let totalPrimaryDrivers = 3
        public init(day: String, score: Double, confidence: ScoreConfidence,
                    presentPrimaryDrivers: Int, signalDirections: [SignalDirection] = []) {
            self.day = day; self.score = score; self.confidence = confidence
            self.presentPrimaryDrivers = presentPrimaryDrivers
            self.signalDirections = signalDirections
        }
    }

    // MARK: - Confidence knobs (product-calibration, not validated constants)

    /// Apple HRV nights needed for the top grade. Tied to the EWMA baseline's own
    /// "trusted" gate so the grade tracks when the baseline is genuinely settled.
    static let solidNights = Baselines.minNightsTrust          // 14
    /// Apple HRV nights for the middle grade (mirrors the strap's Apple-prior cap of 7).
    static let buildingNights = 7
    // Below `Baselines.minNightsSeed` (4) the baseline isn't usable → no estimate at all.

    /// Minimum measured sleep (minutes) to score a night at all. This is a SLEEP-COVERAGE
    /// floor, not an HRV-stability one: SDNN stabilizes in minutes (Task Force 1996), so 3 h
    /// is not about the HRV window settling — it is a proxy that a genuine night is present
    /// (essentially over), not a sliver of the current in-progress one. Below it the night
    /// is OMITTED (UI shows "—"). This is what suppresses the just-after-midnight night
    /// (~2 h logged), which otherwise scored an inflated "estimado 100" off HRV alone
    /// (FER-697). Product-calibration knob, not a validated threshold.
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
            // The three PRIMARY drivers actually backing tonight's score (FER-700), for the honest
            // «N de 3 señales» surface. `hasRHR` is the SAME predicate fed to the scorer's
            // `rhrBaseline:` argument below (computed once, reused) so the RHR count and the RHR
            // term can't diverge. HRV is required (the `guard let sdnn` above), so it always counts.
            // `hasSleep` mirrors the scorer's own sleep-term condition (`sleepPerf != nil`,
            // RecoveryScorer.swift): if that condition ever gains a threshold, keep this in step (a
            // test pins 1/2/3). These are the drivers of the FER-698 `referenceCoverageWeight`.
            let hasRHR = n.restingHr != nil && rhrBase.usable
            let hasSleep = n.sleepPerf != nil
            let primaryDrivers = 1 + (hasRHR ? 1 : 0) + (hasSleep ? 1 : 0)
            // Per-signal DIRECTION vs the user's own Apple norm (never the band's), for the estimated
            // coverage-attribution surface. Position uses the RAW deviation z against the SAME Apple
            // baseline the score reads (SDNN-vs-own-SDNN, RHR-vs-own-RHR), with the band path's ~1σ
            // «in your base» deadband; `helps` orients it (HRV↑ · resting HR↓ · sleep↑). Sleep, which has
            // no separate Apple baseline (Apple writes nil today), falls to the scorer's fixed population
            // center — the same cold-start fallback the sleep term uses. No point magnitude is exposed.
            func position(_ z: Double) -> SignalDirection.Position {
                z >= 1 ? .above : z <= -1 ? .below : .inRange
            }
            var directions: [SignalDirection] = []
            let zHrv = Baselines.deviation(sdnn, state: hrvBase).z
            directions.append(SignalDirection(key: "hrv", position: position(zHrv), helps: zHrv > 0))
            if hasRHR, let rhr = n.restingHr {
                let zRhr = Baselines.deviation(rhr, state: rhrBase).z
                directions.append(SignalDirection(key: "rhr", position: position(zRhr), helps: zRhr < 0))
            }
            if hasSleep, let eff = n.sleepPerf {
                // Sleep has no personal Apple baseline — its position is vs a FIXED population center, so it is
                // flagged `hasPersonalNorm: false` and the UI shows it as presence-only (no «vs your usual»
                // word). `helps: zSleep > 0` also assumes efficiency is monotonic (higher = better), a coarse
                // approximation without the band: very high efficiency can mean a short time-in-bed, not more
                // recovery. Both are why sleep does not claim a personal-norm direction. (CSO gate 9542ba19)
                let zSleep = (eff - RecoveryScorer.sleepPerfCenter) / RecoveryScorer.sleepPerfScale
                directions.append(SignalDirection(key: "sleep", position: position(zSleep),
                                                  helps: zSleep > 0, hasPersonalNorm: false))
            }
            let score = RecoveryScorer.recovery(
                hrv: sdnn,
                // INVARIANT: `rhr` is read by the scorer ONLY under a present rhrBaseline,
                // and we pass rhrBaseline nil whenever restingHr is absent (see below). So
                // this value is never consumed here — `.nan` (not a fake 0 bpm) makes any
                // accidental future read fail the scorer's own z.isFinite guard → nil, rather
                // than inflate a score. RecoveryScorer.recovery also `precondition`s this.
                rhr: n.restingHr ?? .nan,
                resp: n.resp,
                hrvBaseline: hrvBase,
                rhrBaseline: hasRHR ? rhrBase : nil,
                respBaseline: (n.resp != nil && respBase.usable) ? respBase : nil,
                sleepPerf: n.sleepPerf)
            guard let score else { continue }               // nil = cold-start guard inside the scorer
            out.append(DayEstimate(day: n.day, score: score,
                                   confidence: confidence(hrvBaselineNights: hrvBase.nValid),
                                   presentPrimaryDrivers: primaryDrivers,
                                   signalDirections: directions))
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
