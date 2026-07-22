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

    // MARK: - Tag-experiment contrast (FER-1034, Preparación Capa 2)

    /// The result of a tag-experiment: the two-sided contrast of the outcome on days a context tag was
    /// "yes" vs "no", plus the arm sizes and how many days confounder-restriction removed.
    public struct ContrastResult: Sendable, Equatable {
        public let verdict: Verdict
        /// The Mann-Whitney read (nil when `insufficient` for lack of data).
        public let mwu: MannWhitneyResult?
        public let nWith: Int
        public let nWithout: Int
        /// Days dropped from BOTH arms by confounder restriction (sick/travel), surfaced honestly.
        public let nExcluded: Int
        public init(verdict: Verdict, mwu: MannWhitneyResult?, nWith: Int, nWithout: Int, nExcluded: Int) {
            self.verdict = verdict; self.mwu = mwu
            self.nWith = nWith; self.nWithout = nWithout; self.nExcluded = nExcluded
        }
    }

    /// Minimum days PER ARM (after confounder restriction) to judge rather than `insufficient`. Reuses
    /// the repo-wide significance floor (5): the smallest balanced design where the exact Mann-Whitney
    /// can cross α = 0.05 with some overlap (5v5 min p = 2/252 ≈ 0.008). Below it the test degenerates
    /// to all-or-nothing and a "result" is more likely artifact than effect.
    public static var minPerArm: Int { BehaviorInsights.minGroupForSignificance }

    /// Judge a tag experiment: the outcome on explicit yes-days vs explicit no-days, WITHIN the window,
    /// with confounder days removed from both arms. Two-sided (no prior direction), distribution-free.
    ///
    /// - `withDays` / `withoutDays`: the window days the user answered the tag "yes" / "no" (absence of
    ///   an answer = unknown = neither arm — the FER-385 eligible-universe discipline).
    /// - `outcomeByDay`: the target outcome per "yyyy-MM-dd".
    /// - `confounderYesDays`: window days with a "yes" on ANY OTHER confounder tag (sick/travel); the
    ///   caller excludes the experiment's own tag before passing this in.
    ///
    /// Verdicts map to the shipped es-MX copy: `.sustained` = «probable efecto (en ti)», `.notSustained`
    /// = «no se ve (todavía)», `.insufficient` = «datos insuficientes».
    public static func evaluateContrast(withDays: Set<String>,
                                        withoutDays: Set<String>,
                                        outcomeByDay: [String: Double],
                                        confounderYesDays: Set<String> = []) -> ContrastResult {
        let r = restrictConfounders(with: withDays, without: withoutDays,
                                    confounderYesDays: confounderYesDays)
        let xs = r.with.compactMap { outcomeByDay[$0] }
        let ys = r.without.compactMap { outcomeByDay[$0] }
        guard xs.count >= minPerArm, ys.count >= minPerArm else {
            return ContrastResult(verdict: .insufficient, mwu: nil,
                                  nWith: xs.count, nWithout: ys.count, nExcluded: r.excluded)
        }
        guard let mwu = MannWhitney.test(xs, ys) else {
            return ContrastResult(verdict: .insufficient, mwu: nil,
                                  nWith: xs.count, nWithout: ys.count, nExcluded: r.excluded)
        }
        // Two-sided: `.sustained` iff significant in EITHER direction (the templates carry no prior
        // hypothesis). A short window has little power, so `.notSustained` means "didn't show THIS
        // time", never "proven absent".
        let verdict: Verdict = mwu.p < 0.05 ? .sustained : .notSustained
        return ContrastResult(verdict: verdict, mwu: mwu,
                              nWith: xs.count, nWithout: ys.count, nExcluded: r.excluded)
    }

    /// Remove confounder days from BOTH arms (restriction by design — classic confound control). The
    /// experiment's own tag is never a confounder here (the caller strips it). Returns the trimmed arms
    /// and how many day-memberships were removed (for the honest "se excluyeron N días" line).
    public static func restrictConfounders(with: Set<String>, without: Set<String>,
                                           confounderYesDays: Set<String>)
        -> (with: Set<String>, without: Set<String>, excluded: Int) {
        let w = with.subtracting(confounderYesDays)
        let wo = without.subtracting(confounderYesDays)
        let excluded = (with.count - w.count) + (without.count - wo.count)
        return (w, wo, excluded)
    }
}
