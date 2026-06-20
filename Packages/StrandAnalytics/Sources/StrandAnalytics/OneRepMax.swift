import Foundation

// OneRepMax.swift — estimated one-rep-max from a work set's weight × reps (FER-346).
//
// A TRANSPARENT, cited estimate of the most you could lift once, inferred from a heavier-for-more-reps
// set you actually did. It powers the exercise detail's "1RM estimado" trend. It is NOT a prescription:
// never tell the user to load a barbell to this number — it's a progress signal, not a safety target.
//
// Two textbook formulas, both reps-to-fatigue regressions; default is Epley (the most widely used):
//   • Epley (1985):   1RM = w · (1 + reps/30)
//       Epley, B. "Poundage Chart." Boyd Epley Workout. Lincoln, NE: Body Enterprises, 1985.
//   • Brzycki (1993): 1RM = w · 36 / (37 − reps)
//       Brzycki, M. "Strength testing—predicting a one-rep max from reps-to-fatigue."
//       JOPERD 64(1):88–90, 1993.
//
// Both degrade above ~10–12 reps (and Brzycki's denominator blows up near reps = 37), so the input
// reps are CLAMPED to `maxReps = 12`: a 15-rep set is estimated as if it were 12 — a deliberate,
// consistent under-count, honest about the formulas' range rather than fabricating a high number.
// A true single (reps == 1) is its own 1RM and is returned as the bare weight.
//
// Pure & database-free: operates on `(weightKg, reps)` primitives, so it needs no dependency on
// StrandTraining's `SetEntry`. The caller (the detail screen) reads work sets from WhoopStore, maps
// them to tuples, and buckets by day for the sparkline.

public enum OneRepMax {

    /// Which reps-to-fatigue regression to use. Epley is the default (most common); Brzycki reads a
    /// touch more conservative at moderate reps.
    public enum Formula: Sendable { case epley, brzycki }

    /// Reps above this clamp the input (both formulas degrade past ~10–12, and Brzycki's `37 − reps`
    /// denominator misbehaves near 37). A 15-rep set is estimated as a 12-rep one — an honest
    /// under-count, not a fabricated high estimate.
    public static let maxReps = 12

    /// Estimated 1RM (kg) for one work set. `nil` when `weightKg ≤ 0` or `reps < 1` (not estimable).
    /// `reps == 1` returns `weightKg` exactly (a real single is its own 1RM); higher reps clamp to
    /// `maxReps` before the formula is applied.
    public static func estimate(weightKg: Double, reps: Int, formula: Formula = .epley) -> Double? {
        guard weightKg > 0, reps >= 1 else { return nil }
        guard reps > 1 else { return weightKg }
        let r = Double(min(reps, maxReps))
        switch formula {
        case .epley:   return weightKg * (1 + r / 30)
        case .brzycki: return weightKg * 36 / (37 - r)
        }
    }

    /// The best (highest) estimated 1RM across a group of work sets — what a session or day contributes
    /// to the trend. `nil` if none of the sets are estimable.
    public static func bestEstimate<S: Sequence>(_ sets: S, formula: Formula = .epley) -> Double?
        where S.Element == (weightKg: Double, reps: Int) {
        sets.compactMap { estimate(weightKg: $0.weightKg, reps: $0.reps, formula: formula) }.max()
    }

    /// One point of the detail's sparkline: the best estimated 1RM observed on a given day.
    public struct DailyBest: Sendable, Equatable {
        /// Day bucket key (the caller's convention, e.g. "2026-06-20"); points sort ascending by it.
        public let day: String
        public let estimatedKg: Double
        public init(day: String, estimatedKg: Double) { self.day = day; self.estimatedKg = estimatedKg }
    }

    /// Collapse dated work sets to the best estimated 1RM per day, ascending by day — mirrors the
    /// best-per-exercise logic of the stored PRs (progress is the heaviest implied single you showed,
    /// not an average). Days with no estimable set are dropped.
    public static func dailySparkline<S: Sequence>(_ sets: S, formula: Formula = .epley) -> [DailyBest]
        where S.Element == (day: String, weightKg: Double, reps: Int) {
        var bestByDay: [String: Double] = [:]
        for s in sets {
            guard let e = estimate(weightKg: s.weightKg, reps: s.reps, formula: formula) else { continue }
            if let cur = bestByDay[s.day] { bestByDay[s.day] = Swift.max(cur, e) }
            else { bestByDay[s.day] = e }
        }
        return bestByDay.map { DailyBest(day: $0.key, estimatedKg: $0.value) }
            .sorted { $0.day < $1.day }
    }
}
