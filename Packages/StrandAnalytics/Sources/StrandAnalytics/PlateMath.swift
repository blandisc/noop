import Foundation

// PlateMath.swift — barbell plate loading + a warm-up ramp for a target work weight (FER-720, F5 · 3a).
//
// Two TRANSPARENT, database-free helpers for the strength session's "⛓ discos" accessory:
//
//   • `perSide` — given a target total weight, the bar, and the plates the user actually owns,
//     compute what goes on EACH SIDE of the bar. Deterministic greedy loading (heaviest plate that
//     still fits, limited by how many pairs the user has), mirroring how a lifter loads a bar by hand.
//     Barbells are symmetric, so we solve one side for half the (total − bar) load and mirror it.
//
//   • `warmup` — a conventional warm-up ramp UP TO a work weight: the empty bar, then a light and a
//     moderate percentage set. This is a widely used gym convention (bar → ~50–60% → ~80%), NOT a
//     published formula and NOT a prescription — it's a suggestion the user can edit. Each ramp weight
//     is SNAPPED to a weight the user's plates can actually make (via `perSide`), so we never suggest a
//     load they can't build. The percentages/reps are the mock's scheme (bar ×10, 55% ×6, 80% ×3).
//
// Pure & framework-free: operates on `Double` kilograms and a plain inventory list, so it runs in
// `swift test` with no app, DB, or strap. The screen owns persistence of the inventory and the mapping
// of a warm-up set into the live session.

public enum PlateMath {

    /// A plate denomination the user owns, and how many PAIRS of it they have (one pair = one plate per
    /// side). Count is in pairs because a bar is loaded symmetrically.
    public struct PlateStock: Sendable, Equatable {
        /// Mass of a single plate, kg (e.g. 20, 15, 1.25).
        public let kg: Double
        /// How many pairs the user owns (each pair loads one plate on each side).
        public let pairs: Int
        public init(kg: Double, pairs: Int) { self.kg = kg; self.pairs = pairs }
    }

    /// A sensible default inventory (kg), assuming plenty of pairs. Tops out at 20 kg — the common
    /// home/commercial set — so a 36.25 kg-per-side load reads as 20+15+1.25 (the mock's example), not
    /// 25+10+1.25. The user can add 25 kg (or drop denominations) via the editable, persisted inventory.
    public static let defaultInventory: [PlateStock] = [
        PlateStock(kg: 20, pairs: 8), PlateStock(kg: 15, pairs: 8), PlateStock(kg: 10, pairs: 8),
        PlateStock(kg: 5, pairs: 8), PlateStock(kg: 2.5, pairs: 8), PlateStock(kg: 1.25, pairs: 8),
    ]

    /// The standard men's Olympic barbell (kg) — a common default; the screen lets the user change it.
    public static let defaultBarKg: Double = 20

    /// The result of loading a bar toward a target: the plates ON ONE SIDE (heaviest first), the total
    /// weight actually achieved (bar + both sides), and any shortfall the user's plates couldn't cover.
    public struct Loading: Sendable, Equatable {
        /// Plates on a single side, heaviest first (mirror this on the other side). Empty = bar only.
        public let perSide: [Double]
        /// Total weight actually loaded (kg): `bar + 2 · sum(perSide)`.
        public let achievedKg: Double
        /// `target − achieved` (kg), ≥ 0. Non-zero when the inventory can't hit the target exactly
        /// (rounded DOWN — we never suggest more than the target).
        public let shortfallKg: Double
        public init(perSide: [Double], achievedKg: Double, shortfallKg: Double) {
            self.perSide = perSide; self.achievedKg = achievedKg; self.shortfallKg = shortfallKg
        }
    }

    /// Rounding floor for comparing kilogram sums (avoids binary-float noise like 36.249999).
    private static let epsilon = 0.0001

    /// Load a bar toward `targetKg` from `inventory`, returning the per-side plates (heaviest first).
    ///
    /// Greedy, largest-plate-first, bounded by the pairs owned — the natural way a lifter loads a bar.
    /// If `targetKg ≤ barKg` the bar alone already meets or exceeds it, so no plates are returned.
    /// The result rounds DOWN: if the exact target isn't buildable, `shortfallKg` reports the gap.
    public static func perSide(targetKg: Double, barKg: Double = defaultBarKg,
                               inventory: [PlateStock] = defaultInventory) -> Loading {
        guard targetKg > barKg + epsilon else {
            return Loading(perSide: [], achievedKg: barKg, shortfallKg: max(0, targetKg - barKg))
        }
        // Solve one side for half the plate load; the bar is symmetric.
        var remainingPerSide = (targetKg - barKg) / 2
        let stock = inventory.filter { $0.kg > 0 && $0.pairs > 0 }.sorted { $0.kg > $1.kg }
        var side: [Double] = []
        for plate in stock {
            var used = 0
            while used < plate.pairs && remainingPerSide + epsilon >= plate.kg {
                side.append(plate.kg)
                remainingPerSide -= plate.kg
                used += 1
            }
        }
        let achieved = barKg + 2 * side.reduce(0, +)
        return Loading(perSide: side, achievedKg: achieved, shortfallKg: max(0, targetKg - achieved))
    }

    /// One suggested warm-up set on the way to a work weight.
    public struct WarmupSet: Sendable, Equatable {
        /// Suggested load (kg), snapped to what the user's plates can build (bar-only for the first set).
        public let weightKg: Double
        /// Suggested reps for this ramp step.
        public let reps: Int
        /// Fraction of the work weight this step targets (0 = empty bar). For display/attribution only.
        public let fractionOfWork: Double
        public init(weightKg: Double, reps: Int, fractionOfWork: Double) {
            self.weightKg = weightKg; self.reps = reps; self.fractionOfWork = fractionOfWork
        }
    }

    /// The ramp steps as (fraction-of-work-weight, reps). `0` means the empty bar. Mirrors the mock's
    /// "barra sola ×10, 55% ×6, 80% ×3" — a common convention, editable by the user, not a formula.
    public static let warmupScheme: [(fraction: Double, reps: Int)] = [
        (0.0, 10), (0.55, 6), (0.80, 3),
    ]

    /// A warm-up ramp UP TO `workKg`: for each scheme step, the target percentage snapped DOWN to a
    /// buildable weight (bar-only for the 0% step). Steps that would snap to the bar or below the prior
    /// step are dropped, so the ramp is strictly increasing and never suggests an unbuildable load.
    /// Returns `[]` when `workKg ≤ barKg` (nothing to warm up to).
    public static func warmup(workKg: Double, barKg: Double = defaultBarKg,
                              inventory: [PlateStock] = defaultInventory) -> [WarmupSet] {
        guard workKg > barKg + epsilon else { return [] }
        var ramp: [WarmupSet] = []
        var lastKg = 0.0
        for step in warmupScheme {
            let weight: Double
            if step.fraction <= 0 {
                weight = barKg
            } else {
                weight = perSide(targetKg: workKg * step.fraction, barKg: barKg, inventory: inventory).achievedKg
            }
            // Strictly increasing and strictly below the work weight — no redundant or over-target steps.
            guard weight > lastKg + epsilon, weight < workKg - epsilon else { continue }
            ramp.append(WarmupSet(weightKg: weight, reps: step.reps, fractionOfWork: step.fraction))
            lastKg = weight
        }
        return ramp
    }
}
