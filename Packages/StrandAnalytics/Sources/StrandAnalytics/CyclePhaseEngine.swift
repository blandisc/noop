import Foundation

// CyclePhaseEngine.swift — on-device, retrospective estimate of the CURRENT menstrual-cycle phase
// (follicular-lean vs luteal-lean) from the nightly skin-temperature deviation NOOP already persists.
// Pure, deterministic, DB-free. No decode, no persistence, no migration — it consumes `skinTempDevC`
// (+ resting HR, HRV) from the existing daily metrics and recomputes on the fly.
//
// INDEPENDENT implementation of the well-established basal-temperature phase signature: core/skin
// temperature runs HIGHER in the post-ovulatory LUTEAL phase (progesterone is thermogenic) and lower
// in the FOLLICULAR phase. NOOP re-derives the PATTERN against the user's OWN recent window, in robust
// dispersion units — never a population cutoff, never a calendar prediction.
//
// Verified physiology (each is an APPROXIMATE, documented driver — see docs/ANALYTICS.md):
//   • Skin temp ↑ in luteal — the DOMINANT, most robust driver, read from the Apple Watch's overnight
//     WRIST temperature. Site-matched evidence (wrist): Shilaih et al. 2018, Bioscience Reports 38(6):
//     BSR20171279 (doi:10.1042/BSR20171279): early-luteal wrist temp +0.33 °C vs the fertile window,
//     biphasic pattern in ~82% of cycles, n=136 — so the wrist does NOT attenuate the signal below the
//     finger. Direct Apple-Watch validation: Human Reproduction 2025, 40(3):469: algorithms on Apple Watch
//     overnight wrist temperature estimate ovulation retrospectively at MAE 1.22–1.59 days (~80–89% within
//     ±2 days), signal threshold ≥0.2 °C — evidence that Apple's wrist signal is present and usable for a
//     temperature-based cycle read. (That paper targets the ovulation DAY; NOOP claims less — only the
//     follicular/luteal LEAN — and never surfaces an ovulation or fertility estimate.)
//     Corroborating finger-site value: Maijala et al. 2019, BMC Women's Health 19 (doi:10.1186/s12905-019-
//     0844-9): nightly FINGER skin temp +0.30 °C (SD 0.12), p<0.001 (Oura ring). NOOP re-derives the
//     PATTERN against the user's own window in robust units, so magnitude is never assumed from any one site.
//   • Resting HR ↑ in luteal — consistent, small CORROBORATION. Shilaih et al. 2017, Sci Rep 7
//     (doi:10.1038/s41598-017-01433-9): sleeping pulse +1.8 bpm (mid-luteal vs fertile), +3.8 vs menses.
//   • HRV ↓ in luteal — the WEAKEST, MIXED driver, used ONLY as conditional confidence reinforcement,
//     never as a term in the index (decision H1). The vagal-drop is real on AVERAGE (Schmalenberger
//     et al. 2019 systematic review, PMID 31726666; 2020 J Clin Med 9(3):617, doi:10.3390/jcm9030617)
//     BUT for RMSSD specifically — the HRV NOOP measures on-device — the effect is inconsistent/null
//     (Yazar & Yazıcı 2016, Med Princ Pract 25(4), doi:10.1159/000444322: rMSSD 38±12 → 41±27 ms, n.s.).
//     So HRV can only REINFORCE a lean that temp+RHR already agree on; it never votes on the phase.
//
// The weights and the ≥42-night gate below are PRODUCT-CALIBRATION knobs, NOT values derived from any
// publication — no paper prescribes this exact blend (decision H2). They encode the evidence HIERARCHY
// (temp ≫ RHR), nothing more, and are pinned by test in one place for audit.
//
// WELLNESS / SELF-KNOWLEDGE ONLY — APPROXIMATE, RETROSPECTIVE, NOT A DIAGNOSIS. The temperature shift
// CONFIRMS a phase 1–3 days AFTER it changes, so this looks BACKWARD, never "in real time" (H3). The
// engine returns data only (phase + confidence); all user-facing copy — and the hard rule that it never
// implies fertility, ovulation, contraception, a period date, or any clinical claim — lives in the app
// layer's localized strings, not here.
public enum CyclePhaseEngine {

    // MARK: - Tuning constants (product-calibration, NOT validated — pinned by test; see H2 above)

    /// Minimum USABLE nights (those carrying a `skinTempDevC` reading) before any phase is estimated.
    /// ~1.5 mean cycles (28-day mean, 24–38-day range) — enough to cover a full cycle with margin for
    /// nights without a wrist-temp reading (the Apple Watch needs a Series 8+/Ultra worn to sleep, and many
    /// people charge it overnight). Below this the engine is honestly still `.learning`.
    public static let minUsableNights: Int = 42

    /// Usable-night count at/above which a strong lean can read as `.solid` (~2 cycles → a steadier
    /// window). Between `minUsableNights` and this, the ceiling is `.moderate`.
    public static let solidNights: Int = 56

    /// Weight of the skin-temp z (dominant driver) and resting-HR z (corroboration) in the luteal index.
    /// Renormalised from the original 0.6/0.2 after HRV was removed from the sum (H1). Product-calibration.
    public static let weightTemp: Double = 0.75
    public static let weightRHR: Double = 0.25

    /// Minimum samples for an AUXILIARY signal (RHR, HRV) to be usable for its own robust z.
    public static let minAuxSamples: Int = 10

    /// A robust σ at/below this (in the signal's own units) is treated as "not estimable / flat".
    /// For skin-temp deviation (°C), a σ under ~0.05 °C means essentially no nightly variation — no
    /// rhythm to read → `.noClearPattern`. Nightly physiologic spread is ~0.2–0.5 °C, the luteal shift
    /// ~0.30 °C, so this floor only trips on a genuinely blunted/flat signal.
    public static let tempNoiseFloorC: Double = 0.05
    public static let auxNoiseFloor: Double = 1e-9

    /// |luteal index z| thresholds. Below `zLean` tonight sits at the user's typical level → we decline
    /// to lean (`.noClearPattern`). At/above `zModerate` the lean is at least `.moderate`; at/above
    /// `zSolid` (with enough nights) it can reach `.solid`. Product-calibration.
    public static let zLean: Double = 0.25
    public static let zModerate: Double = 0.60
    public static let zSolid: Double = 1.00

    /// Minimum |HRV luteal-ward z| for HRV to count as agreeing corroboration (else it stays silent).
    public static let hrvAgreementMinZ: Double = 0.30

    // MARK: - Inputs

    /// One night of input — exactly the fields the engine reads from an existing daily-metrics row.
    /// `skinTempDevC` is the ANCHOR (nightly skin-temperature deviation °C vs the personal baseline,
    /// already computed by `AnalyticsEngine`); a night without it is not "usable" and does not count
    /// toward the gate. RHR and HRV are optional corroboration and tolerate `nil`.
    public struct NightSample: Equatable, Sendable {
        public let day: String            // "yyyy-MM-dd"
        public let skinTempDevC: Double?
        public let restingHr: Double?
        public let avgHrv: Double?
        public init(day: String, skinTempDevC: Double?, restingHr: Double?, avgHrv: Double?) {
            self.day = day; self.skinTempDevC = skinTempDevC
            self.restingHr = restingHr; self.avgHrv = avgHrv
        }
    }

    // MARK: - Output

    public enum Phase: String, Equatable, Sendable, Codable { case follicularLean, lutealLean }
    public enum PhaseConfidence: String, Equatable, Sendable, Codable { case low, moderate, solid }

    /// The single output. The two non-estimated cases are the HONEST default, never a placeholder — the
    /// app renders them as carefully as the estimated one.
    public enum State: Equatable, Sendable {
        /// Fewer than `needed` usable nights — the expected early state.
        case learning(nightsSoFar: Int, needed: Int)
        /// Enough nights, but the engine cannot lean to a phase: the rhythm is too flat/blunted, or the
        /// most recent night sits at the user's typical level. Common and not a fault.
        case noClearPattern
        /// A readable lean. `lutealIndexZ` is INTERNAL (drives confidence / tests), never shown as a
        /// number; the app shows only the phase word, always hedged.
        case estimated(phase: Phase, confidence: PhaseConfidence, lutealIndexZ: Double)
    }

    // MARK: - Consent gate (FER-183)

    /// The phase the RECOVERY VERDICT is allowed to see — the estimate ONLY when the user opted IN to the
    /// cycle-phase experiment (default OFF). The verdict's luteal discount is gated on this, so someone who
    /// never opted in never has their recovery number silently adjusted (reverts FER-181/H8). Pure, so the
    /// consent behaviour is pinned by a fast-loop test instead of an app-layer one; the app reads the opt-in
    /// flag and passes it here. `.learning`/`.noClearPattern` collapse to `nil` (nothing to apply yet).
    public static func gatedPhase(optIn: Bool, nights: [NightSample], asOf day: String) -> Phase? {
        guard optIn else { return nil }
        switch estimate(nights, asOf: day) {
        case .estimated(let phase, _, _): return phase
        case .learning, .noClearPattern:  return nil
        }
    }

    // MARK: - Evaluate

    /// Estimate the current-phase state for `day`, given the trailing per-night samples (any order).
    public static func estimate(_ nights: [NightSample], asOf day: String) -> State {
        // Gate 0 — the anchor. A night is "usable" only if it carries a skin-temp reading.
        let usableTemp = nights.compactMap { $0.skinTempDevC }
        if usableTemp.count < minUsableNights {
            return .learning(nightsSoFar: usableTemp.count, needed: minUsableNights)
        }

        // Tonight must itself carry the anchor to place it against the window.
        guard let tonight = nights.first(where: { $0.day == day }),
              let tTemp = tonight.skinTempDevC else {
            return .noClearPattern
        }

        // Gate 1 — a readable rhythm. A flat/blunted temp series (e.g. suppressed thermal shift) has no
        // phase to read.
        let sigmaTemp = IllnessWatch.robustSigmaAboutMedian(usableTemp)
        guard sigmaTemp > tempNoiseFloorC else { return .noClearPattern }
        let zTemp = (tTemp - HRVAnalyzer.median(usableTemp)) / sigmaTemp

        // Luteal index — temp (dominant) plus RHR (corroboration) when RHR is estimable tonight; temp
        // alone otherwise. Higher = warmer-than-usual = luteal-ward.
        var indexZ = zTemp
        if let tRHR = tonight.restingHr, let zRHR = robustZ(tRHR, nights.compactMap { $0.restingHr }) {
            indexZ = weightTemp * zTemp + weightRHR * zRHR
        }

        // Tonight sits at the user's typical level → decline to lean (honest, not a coin flip).
        guard abs(indexZ) >= zLean else { return .noClearPattern }
        let phase: Phase = indexZ > 0 ? .lutealLean : .follicularLean

        // Base confidence from the lean's magnitude and how many nights back it.
        var confidence: PhaseConfidence
        if abs(indexZ) >= zSolid && usableTemp.count >= solidNights { confidence = .solid }
        else if abs(indexZ) >= zModerate { confidence = .moderate }
        else { confidence = .low }

        // H1 — HRV reinforcement. HRV can only RAISE confidence one notch, and only when its luteal-ward
        // direction (a DROP is luteal-ward → negate the z) agrees with the lean temp+RHR already found.
        if let tHRV = tonight.avgHrv, let zHRV = robustZ(tHRV, nights.compactMap { $0.avgHrv }) {
            let hrvLutealWard = -zHRV
            let agrees = (hrvLutealWard > 0) == (indexZ > 0) && abs(hrvLutealWard) >= hrvAgreementMinZ
            if agrees { confidence = bumped(confidence) }
        }

        return .estimated(phase: phase, confidence: confidence, lutealIndexZ: indexZ)
    }

    // MARK: - Helpers

    /// Robust z of `value` against `series`: (value − median) / robustσ, both centered on the median so
    /// numerator and scale share one anchor (see `IllnessWatch.robustSigmaAboutMedian`). Nil when the
    /// series is too small or too flat to estimate dispersion.
    static func robustZ(_ value: Double, _ series: [Double]) -> Double? {
        guard series.count >= minAuxSamples else { return nil }
        let sigma = IllnessWatch.robustSigmaAboutMedian(series)
        guard sigma > auxNoiseFloor else { return nil }
        return (value - HRVAnalyzer.median(series)) / sigma
    }

    /// Raise confidence one notch (low → moderate → solid); solid is the ceiling.
    static func bumped(_ c: PhaseConfidence) -> PhaseConfidence {
        switch c {
        case .low: return .moderate
        case .moderate: return .solid
        case .solid: return .solid
        }
    }
}
