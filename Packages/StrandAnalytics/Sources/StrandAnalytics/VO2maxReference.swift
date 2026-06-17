import Foundation

// VO2maxReference.swift — population-reference VO₂max by age & sex (FER-215).
//
// A REFERENCE value to contextualize a MEASURED VO₂max (e.g. the one Apple Health computes from your
// Apple Watch): "the average for your age is around N". It does NOT drive Fitness Age — that's the Nes
// model's own self-consistent comparison (FitnessAgeEngine). This is just the population median so a
// raw number ("48 ml/kg/min") reads as something the user can place ("above / below average").
//
// Method: a linear approximation of the FRIEND Registry sex-specific p50 (median) VO₂max by decade
// (Kaminsky et al., "Reference Standards for Cardiorespiratory Fitness…", Mayo Clin Proc 2015 — a
// healthy US adult reference cohort). Regressed over the per-decade medians; a coarse normative
// REFERENCE for context, never a clinical norm or diagnosis.

public enum VO2maxReference {

    /// Median (p50) VO₂max (ml/kg/min) for a healthy adult of this age & sex — a coarse population
    /// reference for context. `age` is clamped to [20, 80] (the cohort range); the result floors at 15.
    /// Non-binary uses the men's curve, matching `FitnessAgeEngine`'s coefficient choice.
    public static func expected(age: Int, sex: String) -> Double {
        let a = Double(min(80, max(20, age)))
        let v: Double
        switch sex.lowercased() {
        case "female": v = 45.8 - 0.32 * a   // FRIEND p50, women (≈39 at 20 → ≈20 at 80)
        default:       v = 58.3 - 0.42 * a   // FRIEND p50, men   (≈50 at 20 → ≈25 at 80)
        }
        return max(15, v)
    }
}
