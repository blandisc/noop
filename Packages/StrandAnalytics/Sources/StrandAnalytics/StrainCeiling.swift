import Foundation
import WhoopStore

// StrainCeiling.swift — a PERSONAL, recovery-scaled ceiling for today's day-strain, in
// the same 0–21 log units the strain curve plots. NOT a fixed zone constant, NOT WHOOP's
// proprietary "Strain Target" (independent implementation of published methods); NOT medical
// advice — it is context, a guardrail you can read past.
//
// Idea: the acute:chronic workload ratio (ACWR) has a debated "sweet spot" band of ~0.8–1.3
// (Gabbett 2016). We turn that into a same-day ceiling: pick the ACUTE load that would keep
// today's ratio inside the band, scaled by how recovered you are this morning — recovered →
// aim for the top of the band (you can push above your chronic load), run-down → hold near the
// bottom. Then express that ceiling back on the 0–21 strain scale so the curve can draw it.
//
// Pipeline (all reusing the SAME dose the ACWR read already uses, so ceiling and load never
// tell two different stories):
//   1. chronic = mean of the last `chronicWindow` days of LINEARIZED strain load
//      (ReadinessEngine.strainToLoad — inverts StrainScorer's log map so a spike reads as a spike).
//   2. ratio(recovery) = minRatio + (maxRatio − minRatio) · clamp(recovery/100, 0, 1)  ∈ [0.8, 1.3].
//   3. ceiling load = chronic · ratio.
//   4. ceiling strain = StrainScorer.trimpToStrain(ceiling load), clamped to [0, 21].
// nil until there is enough chronic history (`minChronic` strain-days) AND a recovery score —
// so a caller omits the line rather than inventing one.
//
// Honesty about what is and isn't published: the 0.8–1.3 BAND is Gabbett 2016 (Br J Sports Med
// 50:273 — the ACWR "sweet spot", the same heuristic ReadinessEngine cites). The linear map from
// recovery onto that band (the `0.5` slope, the linearity) is NOT from Gabbett or anyone — it is a
// NOOP product calibration: recovered → aim for the top of the band (you may push above chronic),
// run-down → hold near the bottom. Physiologically sensible, but an unvalidated knob, not a
// published result. What this ceiling inherits from the ACWR literature is only that the band is a
// DEBATED heuristic, not a validated threshold — NOT the coupled-ratio artifact (Lolli 2019: acute
// sitting inside chronic inflates the correlation), which bites a MEASURED acute/chronic ratio; the
// ceiling never divides — it multiplies chronic by a recovery-derived factor. Either way this is
// context, never an instruction: the surface frames it as a reference you can read past.
public enum StrainCeiling {

    /// Chronic-load window (days). Matches `ReadinessEngine.chronicWindow` so the ceiling's chronic
    /// baseline is the exact dose the ACWR read uses.
    static let chronicWindow = 28
    /// Minimum strain-days before a chronic baseline is trustworthy. Mirrors `ReadinessEngine.minChronic`.
    static let minChronic = 14
    /// The ACWR "sweet spot" band (Gabbett 2016): the target acute:chronic ratio rides between these.
    static let minRatio = 0.8
    static let maxRatio = 1.3

    public struct Recommendation: Sendable, Equatable {
        /// The advisable day-strain ceiling on the 0–21 scale — what the curve draws.
        public let strain: Double
        /// The acute:chronic ratio the recovery scaled to (0.8–1.3), for copy / tests.
        public let ratio: Double
        /// The chronic linearized load the ceiling was built from, for tests.
        public let chronicLoad: Double
        public init(strain: Double, ratio: Double, chronicLoad: Double) {
            self.strain = strain; self.ratio = ratio; self.chronicLoad = chronicLoad
        }
    }

    /// Today's recommended day-strain ceiling, or nil when there isn't enough history or no recovery
    /// score. `recovery` is today's 0–100 recovery (band-measured or Apple-estimated — the caller's
    /// surfaced value). `today` optionally caps the rows to that civil day and earlier (as-of replay).
    public static func recommend(days: [DailyMetric], recovery: Double?, today: String? = nil) -> Recommendation? {
        guard let recovery else { return nil }
        let sorted = days.sorted { $0.day < $1.day }
        let upTo = today.map { t in sorted.filter { $0.day <= t } } ?? sorted
        let loads = upTo.compactMap { $0.strain }.map(ReadinessEngine.strainToLoad)
        guard loads.count >= minChronic else { return nil }
        guard let chronic = ReadinessEngine.mean(Array(loads.suffix(chronicWindow))), chronic > 0 else { return nil }
        let r = max(0, min(1, recovery / 100))
        let ratio = minRatio + (maxRatio - minRatio) * r
        let ceilingLoad = chronic * ratio
        let strain = min(StrainScorer.maxStrain, StrainScorer.trimpToStrain(ceilingLoad))
        return Recommendation(strain: strain, ratio: ratio, chronicLoad: chronic)
    }
}
