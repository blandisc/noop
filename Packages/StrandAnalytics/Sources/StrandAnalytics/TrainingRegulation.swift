import Foundation

// TrainingRegulation.swift — pre-workout "dial up / hold / dial back" suggestion (FER-349).
//
// A TRANSPARENT, OPT-IN nudge shown BEFORE a strength session: should today's load go up, stay,
// or come down, judged against YOUR personal recovery baseline — not a population band. It is a
// SUGGESTION, never a gate ("tú decides"): the caller is free to ignore it, and the rule never
// blocks training.
//
// This is autoregulation — adjusting the day's training to the athlete's measured readiness:
//   • Kiviniemi, A.M. et al. "Endurance training guided individually by daily heart rate
//     variability measurements." Eur J Appl Physiol 101(6):743–751, 2007. The HRV-guided arm — raise /
//     hold / lower the day's load relative to each athlete's own band — out-performed a fixed
//     program. This rule is that pattern: measure today against your normal, then adjust.
//   • The ±½σ actionable threshold reuses the criterion already documented in ReadinessEngine
//     (Plews et al. 2013; Buchheit 2014): a drop of roughly half a standard deviation flags
//     autonomic fatigue. Kept identical here so "a deviation that matters" has one definition.
//
// Honest degradation: with no recovery signal at all the rule returns `nil` and the UI HIDES the
// band rather than inventing a direction — same nil contract as RecoveryScorer / RecoveryForecast.
//
// NOT a clinical instruction. Pure & database-free: operates on a score and/or a z, so it needs
// no dependency on persistence, CoreBluetooth, or UIKit.

public enum TrainingRegulation {

    /// The suggested direction for today's load.
    public enum Adjustment: String, Equatable, Sendable {
        case dialUp    // sube — recovery above your normal
        case hold      // mantén — within your normal band
        case dialBack  // baja — recovery below your normal
    }

    /// Why the suggestion landed where it did (no es-MX copy — the UI localizes from this).
    public enum Reason: String, Equatable, Sendable {
        case recoveryHigh   // score ≥ greenCut, or z ≥ +zHigh
        case recoveryLow    // score < redCut, or z ≤ -zLow
        case withinNormal   // neither high nor low
    }

    /// The opt-in suggestion. `isAdvisory` is always true: this rule never gates training.
    public struct Suggestion: Equatable, Sendable {
        public let adjustment: Adjustment
        public let reason: Reason
        /// "Sugerencia, tú decides" — the rule is always advisory, never a block.
        public var isAdvisory: Bool { true }
        public init(adjustment: Adjustment, reason: Reason) {
            self.adjustment = adjustment
            self.reason = reason
        }
    }

    // Score-band cuts (used when only a 0–100 recovery score is available): reuse the canonical
    // recovery bands so "green/red" means the same thing everywhere in the app.
    public static let greenCut = RecoveryScorer.bandYellowMax   // 67.0 — score ≥ this → dial up
    public static let redCut   = RecoveryScorer.bandRedMax      // 34.0 — score < this → dial back

    // Z-band cuts (preferred when the caller has today's z against the personal baseline): ±½σ,
    // the same actionable threshold ReadinessEngine uses (Plews 2013; Buchheit 2014). Calibration
    // knobs, tunable without touching the logic.
    public static let zHigh = 0.5
    public static let zLow  = 0.5

    // MARK: - The single oracle (FER-82)
    //
    // Entrenar used to read a 0–100 recovery score while Hoy painted its verdict from `Preparedness`
    // (per-axis consensus, no number). Two oracles, two sets of cut-offs: the app could say «Recupera»
    // in the thread and «Hoy subes 82.5 kg» three lines below. From here on Entrenar reads the SAME
    // verdict Hoy shows, and this is the ONE place that translates it into training advice.
    //
    // Note there is no «push harder» advice: `Preparedness` has no "better than your normal" verdict
    // (`.full` means *no axis out*, which already includes better-than-normal), so the honest mapping
    // never tells anyone to exceed the plan. Autoregulation here only ever holds or eases.

    /// What Entrenar advises today, derived from the verdict Hoy already showed.
    public enum Advice: String, Equatable, Sendable {
        /// «En rango» — the plan as written; an earned raise may go through.
        case planAsIs
        /// «Hoy ve leve» — keep today's load, do NOT raise.
        case lighter
        /// «Recupera» — ease off: offer the gentler option, do NOT raise.
        case recover
        /// No usable read (low signal, no reading yet, no Health permission) — say nothing at all.
        case silent
    }

    /// Translate Hoy's verdict into Entrenar's advice. `nil` (no read at all) is `.silent`.
    public static func advice(for verdict: Preparedness.Verdict?) -> Advice {
        switch verdict {
        case .full:      return .planAsIs
        case .caution:   return .lighter
        case .easy:      return .recover
        case .lowSignal: return .silent
        case nil:        return .silent
        }
    }

    /// Whether an earned progression raise may go through today. Only a clean read allows it: with
    /// `.lighter` or `.recover` the seed stays at last time's weight and the raise waits (the athlete
    /// can still raise by hand — advisory, never a gate).
    public static func allowsRaise(_ advice: Advice) -> Bool { advice == .planAsIs }

    /// Convenience: does today's verdict allow an earned raise?
    public static func allowsRaise(verdict: Preparedness.Verdict?) -> Bool {
        allowsRaise(advice(for: verdict))
    }

    /// The verdict-driven suggestion, for the surfaces that already speak `Suggestion`.
    /// `.silent` returns `nil` so the UI hides the row instead of inventing a direction.
    public static func suggest(verdict: Preparedness.Verdict?) -> Suggestion? {
        switch advice(for: verdict) {
        case .planAsIs: return Suggestion(adjustment: .hold, reason: .withinNormal)
        case .lighter:  return Suggestion(adjustment: .hold, reason: .recoveryLow)
        case .recover:  return Suggestion(adjustment: .dialBack, reason: .recoveryLow)
        case .silent:   return nil
        }
    }

    /// The lighter alternative straight from today's verdict. Only `.recover` offers one: within
    /// range there is nothing to suggest, and `.lighter` keeps the plan (it just blocks the raise).
    public static func lightAlternative(verdict: Preparedness.Verdict?) -> LightAlternative? {
        advice(for: verdict) == .recover ? .softer : nil
    }

    /// A concrete lighter alternative to today's planned load, derived from the direction.
    ///
    /// The planner's «Sugerencia» row (FER-532) maps a `Suggestion` to one actionable option:
    ///   • `.softer` — recovery is BELOW your normal (`dialBack`): offer a gentler session.
    ///   • `.optionalLight` — recovery is ABOVE your normal (`dialUp`): offer an OPTIONAL short add-on.
    /// Within your normal band (`hold`) or with no signal there is nothing to suggest, so the row hides.
    /// Still advisory: an alternative the athlete may take or ignore, never a block.
    public enum LightAlternative: String, Equatable, Sendable {
        case softer         // baja — a gentler option than the plan
        case optionalLight  // alta — an optional light add-on
    }

    /// Map a direction to a concrete lighter alternative, or `nil` when none applies (`hold` / no signal),
    /// so the UI shows the row ONLY when it carries a suggestion.
    public static func lightAlternative(for suggestion: Suggestion?) -> LightAlternative? {
        switch suggestion?.adjustment {
        case .dialBack: return .softer
        case .dialUp:   return .optionalLight
        case .hold, nil: return nil
        }
    }

    /// Convenience: the lighter alternative straight from today's recovery inputs (same contract as
    /// `suggest`). Returns `nil` within the normal band or with no recovery signal.
    public static func lightAlternative(recovery: Double?, recoveryZ: Double? = nil) -> LightAlternative? {
        lightAlternative(for: suggest(recovery: recovery, recoveryZ: recoveryZ))
    }

    /// Pre-workout suggestion, or `nil` when there is no recovery signal (the UI then hides the band).
    /// - Parameters:
    ///   - recovery: today's recovery score 0–100 (from `RecoveryScorer`), or `nil` in cold-start.
    ///   - recoveryZ: today's z against the personal recovery baseline (from `Baselines.deviation`),
    ///     optional. When present it WINS over the raw score — autoregulation is relative to the
    ///     individual, and z is the more faithful "today vs your normal" signal.
    /// Returns `nil` only when BOTH inputs are `nil`.
    public static func suggest(recovery: Double?, recoveryZ: Double? = nil) -> Suggestion? {
        if let z = recoveryZ {
            if z >= zHigh { return Suggestion(adjustment: .dialUp, reason: .recoveryHigh) }
            if z <= -zLow { return Suggestion(adjustment: .dialBack, reason: .recoveryLow) }
            return Suggestion(adjustment: .hold, reason: .withinNormal)
        }
        if let score = recovery {
            if score >= greenCut { return Suggestion(adjustment: .dialUp, reason: .recoveryHigh) }
            if score < redCut { return Suggestion(adjustment: .dialBack, reason: .recoveryLow) }
            return Suggestion(adjustment: .hold, reason: .withinNormal)
        }
        return nil
    }
}
