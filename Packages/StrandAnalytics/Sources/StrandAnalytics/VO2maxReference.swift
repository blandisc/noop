import Foundation

// VO2maxReference.swift — population-reference VO₂max by age & sex (FER-215).
//
// A REFERENCE value to contextualize a MEASURED VO₂max (e.g. the one Apple Health computes from your
// Apple Watch): "the average for your age is around N". It does NOT drive Fitness Age — that's the Nes
// model's own self-consistent comparison (FitnessAgeEngine). This is just the population median so a
// raw number ("48 ml/kg/min") reads as something the user can place ("above / below average").
//
// Method: a least-squares linear fit of the FRIEND Registry sex-specific p50 (median) treadmill VO₂max
// over the decade midpoints (Kaminsky LA, Arena R, Myers J, "Reference Standards for Cardiorespiratory
// Fitness…", Mayo Clin Proc 2015;90(11):1515–1523 — a healthy US adult reference cohort). FRIEND p50 by
// decade (20s→70s): men 48.0 / 42.4 / 37.8 / 32.6 / 28.2 / 24.4; women 37.6 / 30.2 / 26.7 / 23.4 / 20.0 /
// 18.3 ml/kg/min. A coarse normative REFERENCE for context, never a clinical norm or diagnosis.

public enum VO2maxReference {

    /// Median (p50) VO₂max (ml/kg/min) for a healthy adult of this age & sex — a coarse population
    /// reference for context. `age` is clamped to [20, 80] (the cohort range); the result floors at 15.
    /// Non-binary uses the men's curve, matching `FitnessAgeEngine`'s coefficient choice.
    public static func expected(age: Int, sex: String) -> Double {
        let a = Double(min(80, max(20, age)))
        let v: Double
        switch sex.lowercased() {
        case "female": v = 44.66 - 0.373 * a   // FRIEND p50, women (least-squares over the decade medians)
        default:       v = 59.25 - 0.474 * a   // FRIEND p50, men   (least-squares over the decade medians)
        }
        return max(15, v)
    }

    // MARK: - Fitness category (FER-257)

    /// A coarse fitness band relative to one's age & sex peers — the legible reading on a measured VO₂max.
    public enum Category: String, Sendable {
        case low, average, good, excellent
    }

    /// Approximate population spread (SD, ml/kg/min) of VO₂max within a sex, roughly constant across the
    /// FRIEND decades (men spread a little wider than women). Used to turn the p50 median into percentile
    /// bands via a normal approximation. A coarse reference, never a clinical cutoff.
    private static func spread(sex: String) -> Double {
        sex.lowercased() == "female" ? 7.0 : 9.0
    }

    /// The three cut points (ascending, ml/kg/min) splitting the four categories for this age & sex:
    /// `low | average | good | excellent`. Derived from the median (`expected`) ± a normal-approximation
    /// of the FRIEND spread at the ~p30 / ~p70 / ~p90 marks (z = −0.524 / +0.524 / +1.282). (Kaminsky 2015)
    public static func categoryThresholds(age: Int, sex: String) -> (low: Double, good: Double, excellent: Double) {
        let mid = expected(age: age, sex: sex)
        let sd = spread(sex: sex)
        return (low: mid - 0.524 * sd, good: mid + 0.524 * sd, excellent: mid + 1.282 * sd)
    }

    /// Classify a MEASURED VO₂max against its age- & sex-peers into a coarse fitness band. A reference for
    /// context (where you sit among healthy peers), never a diagnosis. (Kaminsky 2015, normal approximation)
    public static func category(value: Double, age: Int, sex: String) -> Category {
        let t = categoryThresholds(age: age, sex: sex)
        if value < t.low { return .low }
        if value < t.good { return .average }
        if value < t.excellent { return .good }
        return .excellent
    }

    /// The age whose median VO₂max equals this measured value — a "cardiorespiratory-equivalent age"
    /// (e.g. a measured 47 might match the p50 of a 30-year-old). Inverts `expected` on the same sex
    /// curve and clamps to the cohort range [20, 80]. Independent of the Nes Fitness Age. (FER-257)
    public static func equivalentAge(value: Double, sex: String) -> Int {
        let a: Double
        switch sex.lowercased() {
        case "female": a = (44.66 - value) / 0.373
        default:       a = (59.25 - value) / 0.474
        }
        return Int(min(80, max(20, a)).rounded())
    }
}
