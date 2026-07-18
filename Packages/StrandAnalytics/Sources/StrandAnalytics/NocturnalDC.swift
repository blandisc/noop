import Foundation
import BiometricStreams

// NocturnalDC.swift — nocturnal Deceleration Capacity (DC) via Phase-Rectified Signal Averaging
// (PRSA) over the night's R-R series (FER-680). Pure, deterministic, DB-free.
//
// WHAT — DC quantifies how much the heart is able to "ease off" (decelerate) at rest: it isolates the
// deceleration-related component of heart-rate variability, which RMSSD/SDNN blend together with the
// acceleration side. A larger DC reflects more room to slow down — colloquially, more braking reserve.
//
// METHOD (Bauer A, Kantelhardt JW, Barthel P, et al., "Deceleration capacity of heart rate as a
// predictor of mortality after myocardial infarction: cohort study", Lancet 2006;367(9523):1674–1681):
//   1. ANCHORS — every beat that is LONGER than the one before it (R-R increases ⇒ heart decelerating).
//      An artifact guard rejects anchors whose increase exceeds `anchorMaxIncreaseFraction` (Bauer's
//      percentage filter), so a single spurious long interval can't seed a false anchor.
//   2. PRSA — align a short window around every anchor at the anchor point (relative index 0) and average
//      the interval value across all anchors at each relative index → the phase-rectified average X̄(k).
//      Averaging over MANY anchors is what makes DC comparatively robust to isolated PPG artifacts: an
//      artifact that survives cleaning is diluted across thousands of events instead of dominating.
//   3. QUANTIFIER (Bauer's Haar-wavelet DC at scale T = 1):
//         DC = [ X̄(0) + X̄(1) − X̄(−1) − X̄(−2) ] / 4     (milliseconds)
//      X̄(0) is the anchor, X̄(1) the beat after, X̄(−1)/X̄(−2) the two before. Positive DC ⇒ the R-R
//      series lengthens around decelerations (braking reserve present).
//
// WHY IT'S VIABLE FROM WRIST PPG — PRSA is an averaging estimator, so it tolerates the residual beat
// noise of wrist PPG far better than a per-window nonlinear exponent (e.g. DFA-α1) would. We still run it
// over the SLEEP window (where wrist PPG is most reliable) and still clean the R-R first with the same
// range + Malik ectopic filter used everywhere (`HRVAnalyzer.cleanRR`), gating on the surviving artifact
// fraction and anchor count. Because the averaging dilutes noise, DC is NOT hidden behind an experimental
// flag (unlike DFA-α1); instead the signal quality is surfaced through `confidence`.
//
// HONEST FRAMING (load-bearing, es-MX copy is a PATTERN, never a verdict):
//   APPROXIMATION, not a medical device, no clinical claim. Bauer's cohort defined mortality-risk
//   cut-offs (the widely-cited three-tier split, ~DC ≤ 4.5 ms = high risk — illustrative, from secondary
//   sources, not the primary abstract) for post-infarction ECG at 1000 Hz. We DELIBERATELY do NOT
//   import those cut-offs: wrist PPG at rest is not diagnostic ECG, and a single night's absolute DC is
//   noisy. We present DC ONLY as the user's OWN trend ("more / about the same / less braking reserve than
//   your normal"), NEVER as a mortality score, a risk category, or a clinical threshold.
public enum NocturnalDC {

    // MARK: - Tuning constants (pinned by test)

    /// Bauer's artifact guard: a beat is a valid deceleration anchor only if it is longer than the
    /// preceding beat by AT MOST this fraction. 0.05 == 5%, the value Bauer used to exclude artifacts
    /// while keeping physiological decelerations. A larger jump is treated as noise, not a true anchor.
    public static let anchorMaxIncreaseFraction: Double = 0.05

    /// Minimum CLEAN beats before DC is reported. DC needs a long, quiet recording to accumulate enough
    /// anchors; 500 beats (~8 min at ~1 beat/s) is a floor well below a real night (~20k+), sized so the
    /// gate is meaningful yet testable on synthetic series.
    public static let minCleanBeats: Int = 500

    /// Minimum deceleration anchors that must survive before DC is trustworthy. PRSA stabilises with anchor
    /// count; below this the average is too thin to read.
    public static let minAnchors: Int = 100

    /// Maximum tolerated artifact fraction (beats removed by range/ectopic cleaning ÷ input). PRSA tolerates
    /// more residual noise than DFA-α1 (whose ceiling is 5%) because it averages over events — but a night
    /// that lost more than this to cleaning was mostly off-wrist and is refused.
    public static let maxArtifactFraction: Double = 0.15

    /// A SOLID read needs both a low artifact fraction and a full night's worth of anchors.
    public static let solidArtifactCeiling: Double = 0.05
    public static let solidMinAnchors: Int = 800

    /// Relative band around the user's own DC baseline used to classify tonight as above / around / below
    /// their normal. 0.10 == ±10%. A single night's DC is noisy, so we don't split hairs finer than this.
    public static let trendBandFraction: Double = 0.10

    // MARK: - Output

    public enum Confidence: String, Equatable, Sendable, Codable {
        case unreadable   // too few clean beats / too few anchors / too gappy to read
        case estimate     // enough to report, thin coverage or some artifacts
        case solid        // clean, full night
    }

    /// Tonight relative to the user's OWN baseline — the only comparison we make. Never a risk class.
    public enum Trend: String, Equatable, Sendable, Codable {
        case below        // less braking reserve than your normal
        case around       // in your usual range
        case above        // more braking reserve than your normal
    }

    public struct Result: Equatable, Sendable {
        /// Deceleration Capacity in milliseconds (Bauer T=1 Haar DC). 0 when unreadable.
        public let dcMs: Double
        /// Number of deceleration anchors PRSA averaged over.
        public let anchors: Int
        /// Fraction of input beats removed by cleaning (range + ectopic), in [0, 1].
        public let artifactFraction: Double
        /// Clean beats that survived cleaning.
        public let nClean: Int
        public let confidence: Confidence
        /// Tonight vs the user's own DC baseline, or nil when no baseline was supplied.
        public let trend: Trend?
        /// Honest es-MX one-liner (a personal-trend pattern, never a diagnosis).
        public let note: String

        public init(dcMs: Double, anchors: Int, artifactFraction: Double, nClean: Int,
                    confidence: Confidence, trend: Trend?, note: String) {
            self.dcMs = dcMs; self.anchors = anchors
            self.artifactFraction = artifactFraction; self.nClean = nClean
            self.confidence = confidence; self.trend = trend; self.note = note
        }
    }

    // MARK: - API

    /// Compute nocturnal DC from a window of raw R-R intervals (ms), already restricted to the asleep
    /// span by the caller. Cleaning reuses `HRVAnalyzer.cleanRR` (range + Malik ectopic), so the artifact
    /// fraction is measured the same way as elsewhere.
    ///
    /// - Parameters:
    ///   - rawRR: the night's R-R intervals (ms), in order.
    ///   - baselineDcMs: the user's own recent DC baseline (ms) for the trend read. `nil`/≤0 ⇒ no trend.
    /// - Returns: a populated `Result` (never nil) — an unreadable night still returns a Result whose
    ///   `confidence == .unreadable` so the surface can show an honest "not enough signal" state.
    public static func compute(rawRR: [Double], baselineDcMs: Double? = nil) -> Result {
        let nInput = rawRR.count
        let clean = HRVAnalyzer.cleanRR(rawRR)
        let nClean = clean.count
        let artifactFraction = nInput > 0 ? Double(nInput - nClean) / Double(nInput) : 1.0

        func unreadable() -> Result {
            Result(dcMs: 0, anchors: 0, artifactFraction: artifactFraction, nClean: nClean,
                   confidence: .unreadable, trend: nil,
                   note: "No hay suficiente señal esta noche para leer cómo baja de marcha tu corazón.")
        }

        guard nClean >= minCleanBeats, artifactFraction <= maxArtifactFraction else { return unreadable() }
        guard let (dc, anchors) = decelerationCapacity(clean), anchors >= minAnchors else {
            return unreadable()
        }

        let confidence: Confidence =
            (artifactFraction <= solidArtifactCeiling && anchors >= solidMinAnchors) ? .solid : .estimate

        let trend = classify(dcMs: dc, baselineDcMs: baselineDcMs)
        let note = phrase(dcMs: dc, trend: trend)

        return Result(dcMs: dc, anchors: anchors, artifactFraction: artifactFraction, nClean: nClean,
                      confidence: confidence, trend: trend, note: note)
    }

    // MARK: - PRSA / DC core

    /// Bauer's Haar-wavelet DC (scale T = 1) over an already-clean R-R series (ms). Anchors are beats that
    /// are longer than the preceding beat by at most `anchorMaxIncreaseFraction`, with room for the two
    /// preceding and one following beat. Returns nil if no valid anchor exists. Exposed for testing on
    /// synthetic series — the gates (min beats / anchors / artifacts) live in `compute`.
    ///
    /// SIMPLIFICATION vs Bauer (documented, not hidden): Bauer's percentage filter is canonically applied
    /// across the whole PRSA segment (any interval in the averaging window deviating > T from the
    /// reference disqualifies it); here we guard only the anchor step `rr[i]/rr[i-1]`. This is a
    /// conservative deviation — it never over-claims DC — and the series is already pre-cleaned by
    /// `HRVAnalyzer.cleanRR` (range + Malik ectopic) upstream, so gross artifacts are gone before anchors
    /// are picked. Aligning to Bauer's full-segment filter is a possible future refinement.
    public static func decelerationCapacity(_ rr: [Double]) -> (dcMs: Double, anchors: Int)? {
        guard rr.count >= 4 else { return nil }
        var sum0 = 0.0, sum1 = 0.0, sumM1 = 0.0, sumM2 = 0.0
        var anchors = 0
        // i is the anchor index; need i-2 ≥ 0 and i+1 ≤ count-1.
        for i in 2..<(rr.count - 1) {
            let prev = rr[i - 1]
            guard prev > 0 else { continue }
            let ratio = rr[i] / prev
            guard ratio > 1.0, ratio <= 1.0 + anchorMaxIncreaseFraction else { continue }
            sum0 += rr[i]
            sum1 += rr[i + 1]
            sumM1 += rr[i - 1]
            sumM2 += rr[i - 2]
            anchors += 1
        }
        guard anchors > 0 else { return nil }
        let n = Double(anchors)
        let dc = ((sum0 / n) + (sum1 / n) - (sumM1 / n) - (sumM2 / n)) / 4.0
        return (dc, anchors)
    }

    // MARK: - Trend + copy

    /// Classify tonight against the user's own baseline. nil baseline ⇒ nil trend (no comparison).
    static func classify(dcMs: Double, baselineDcMs: Double?) -> Trend? {
        guard let base = baselineDcMs, base > 0 else { return nil }
        if dcMs > base * (1.0 + trendBandFraction) { return .above }
        if dcMs < base * (1.0 - trendBandFraction) { return .below }
        return .around
    }

    /// Honest es-MX one-liner. A personal-trend pattern, never a diagnosis or a clinical cut-off.
    static func phrase(dcMs: Double, trend: Trend?) -> String {
        let ms = String(format: "%.1f", dcMs)
        switch trend {
        case .above:
            return "Tu corazón mostró más reserva para bajar de marcha que tu normal esta noche (\(ms) ms)."
        case .around:
            return "Tu capacidad de bajar de marcha en reposo estuvo en tu rango habitual esta noche (\(ms) ms)."
        case .below:
            return "Tu corazón mostró menos reserva para bajar de marcha que tu normal esta noche (\(ms) ms)."
        case .none:
            return "Tu capacidad de bajar de marcha en reposo esta noche fue de \(ms) ms. Cobra sentido como tendencia personal: síguela en el tiempo."
        }
    }
}
