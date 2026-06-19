import Foundation

// ExperimentVerdict.swift — the N-of-1 experiment verdict (FER-307).
//
// Pure, deterministic, DB-free. An experiment runs a candidate lever (a logged behavior × an outcome
// metric) for a fixed window; when the window closes this computes whether the candidate's observed
// association REPRODUCED prospectively in the user's own body. It re-implements no statistics — it
// delegates to `BehaviorInsights.effect` (Welch t-test + pooled Cohen's d + the per-side `minGroup`
// floor) and only classifies the result.
//
// The comparison is adherent-window-days vs the user's baseline: `outcomeByDay` carries the outcome
// over baseline history ∪ the window, and `adherentDays` is the set of window days the lever was
// actually logged (derived from the existing journal). "With" = adherent days, "without" = everyone
// else (mostly baseline) — this reuses the exact machinery that produced the candidate, and keeps a
// robust n on both sides (a short window's adherent-vs-non-adherent split would starve the "without"
// group below `minGroup`).
//
// Verdict is a reproducibility test, not "is this metric good": a positive verdict requires the
// effect to be significant AND in the SAME direction the candidate first showed (`expectedSign`). A
// short window has little statistical power, so `.notSustained` means "didn't reproduce this time",
// never "proven absent".

/// The outcome of an N-of-1 experiment.
public enum Verdict: String, Sendable, Equatable {
    /// Significant effect in the expected direction — the lever is promoted candidate→proven.
    case sustained
    /// Computable but not significant, or significant in the opposite direction.
    case notSustained
    /// Not enough adherent days (or no computable effect) to judge.
    case insufficient
}

/// An experiment verdict plus the underlying effect (nil when `insufficient` for lack of data).
public struct ExperimentResult: Sendable, Equatable {
    public let verdict: Verdict
    public let effect: BehaviorEffect?
    public init(verdict: Verdict, effect: BehaviorEffect?) {
        self.verdict = verdict
        self.effect = effect
    }
}

public enum ExperimentVerdict {

    /// Minimum adherent days (the "with" group) for a verdict to be judged rather than
    /// `insufficient`. Reuses `BehaviorInsights`' per-side significance floor.
    public static var minAdherentDays: Int { BehaviorInsights.minGroupForSignificance }

    /// Judge an experiment. `expectedSign` is the sign of the candidate's original effect (+1/−1).
    /// `adherentDays` are the "yyyy-MM-dd" days within the window the lever was logged; `outcomeByDay`
    /// is the target metric over baseline history ∪ window.
    ///
    /// - `.insufficient` when fewer than `minAdherentDays` adherent days, or no computable effect.
    /// - `.sustained` when the effect is significant AND its delta sign matches `expectedSign`.
    /// - `.notSustained` otherwise.
    public static func evaluate(behavior: String,
                                outcome: String,
                                expectedSign: Int,
                                adherentDays: Set<String>,
                                outcomeByDay: [String: Double]) -> ExperimentResult {
        guard adherentDays.count >= minAdherentDays else {
            return ExperimentResult(verdict: .insufficient, effect: nil)
        }
        guard let e = BehaviorInsights.effect(behaviorDays: adherentDays,
                                              outcomeByDay: outcomeByDay,
                                              behavior: behavior,
                                              outcome: outcome) else {
            return ExperimentResult(verdict: .insufficient, effect: nil)
        }
        // A `.sustained` verdict needs `significant`, which implies a nonzero delta, so comparing the
        // sign of the (positive/negative) delta against the candidate's expected sign is enough.
        let sameDirection = (e.delta > 0) == (expectedSign > 0)
        let verdict: Verdict = (e.significant && sameDirection) ? .sustained : .notSustained
        return ExperimentResult(verdict: verdict, effect: e)
    }
}
