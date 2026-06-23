import Foundation

/// Per-metric *levels* — the pure analytic foundation of the new metric detail (FER-570 / F6a).
///
/// Given a metric and a window of values, this returns the metric's ordered levels (a stable,
/// language-free key + its numeric bounds), how many of those values fall in each level, and the
/// level the latest ("today") value sits in. Two flavours:
///
/// * **Fixed levels** — the population thresholds finalized for each metric (`FixedMetric`,
///   the numbers below). Used by Recovery, Sleep, Strain, Resting HR, Blood Oxygen, Steps,
///   Stress and Respiration.
/// * **Relative-to-baseline levels** — *below / in your base / above*, derived from the user's
///   OWN baseline ± a dispersion, with no population threshold at all. This is the only honest
///   way to band HRV (RMSSD has no universal good/bad cut — only your own trend), and it also
///   gives Recovery a personal view on top of its fixed 0–100 scale.
///
/// Pure and database-free: no `import` of UIKit / SwiftUI / CoreBluetooth, no device clock, no I/O.
/// It defines ONLY keys, thresholds and counts — **never** colours or UI copy; F6b/F6c
/// (`StrandDesign` / `Cenit`) own the presentation. These thresholds are the NEW canonical set the
/// redesigned metric detail adopts (the F6 README numbers); they are not the same as the shipped
/// `MetricInfo.Band` (Cenit) / `TrendBands` (StrandDesign), which several screens still render and
/// which this phase deliberately leaves untouched. F6b/F6c migrate those consumers onto this engine,
/// at which point it becomes the single source of truth; until then the two sets coexist by design.
///
/// Interval convention: half-open `[lower, upper)` (consistent with `MetricInfo.Band`), so a value
/// exactly on a boundary falls into the UPPER level and the per-level counts sum to the number of
/// values fed in — no double-counting, no gaps.
///
/// APPROXIMATE — informational, not a diagnosis.
public enum MetricLevels {

    // MARK: - Model

    /// One named level within a metric: a stable, language-free `key` plus its half-open bounds.
    /// `lower == nil` means open below (the bottom level); `upper == nil` means open above (the
    /// top level). Levels for a metric are contiguous and cover the whole line, so every finite
    /// value lands in exactly one.
    public struct Level: Equatable, Sendable {
        /// Stable identifier the UI maps to copy/colour (e.g. `"depleted"`). Never user-facing text.
        public let key: String
        /// Inclusive lower bound; `nil` = open below.
        public let lower: Double?
        /// Exclusive upper bound; `nil` = open above.
        public let upper: Double?
        public init(key: String, lower: Double?, upper: Double?) {
            self.key = key
            self.lower = lower
            self.upper = upper
        }
    }

    /// The result of classifying a window of values against a metric's levels.
    public struct Classification: Equatable, Sendable {
        /// The metric's levels, ordered low→high.
        public let levels: [Level]
        /// How many fed-in values fell in each level — parallel to `levels`. `counts.reduce(0,+) == total`.
        public let counts: [Int]
        /// The level the `today` value sits in, or `nil` when no `today` value was given.
        public let activeIndex: Int?
        /// Number of values counted — the size of the window fed in. Derived from `counts`, which
        /// the total partition guarantees sums to the window size.
        public var total: Int { counts.reduce(0, +) }
        public init(levels: [Level], counts: [Int], activeIndex: Int?) {
            self.levels = levels
            self.counts = counts
            self.activeIndex = activeIndex
        }
    }

    // MARK: - Fixed-threshold metrics

    /// Metrics whose levels are fixed population thresholds (HRV is intentionally absent — it has
    /// no honest universal cut and must use the relative path).
    public enum FixedMetric: String, CaseIterable, Sendable {
        case recovery      // 0–100 recovery score
        case sleep         // total sleep, MINUTES
        case strain        // 0–21 day strain
        case restingHR     // resting heart rate, bpm
        case bloodOxygen   // SpO2, %
        case steps         // daily steps
        case stress        // 0–3 stress score
        case respiration   // breaths/min
    }

    /// The ordered levels (low→high) for a fixed metric — the EXACT thresholds finalized for F6.
    ///
    /// The lowest level is always open below and the highest open above, so the partition is total;
    /// a value on any internal boundary falls into the upper level (half-open `[lower, upper)`).
    public static func levels(for metric: FixedMetric) -> [Level] {
        switch metric {
        case .recovery:
            // Agotado <25 · Bajo 25–50 · Moderado 50–70 · A punto 70–88 · Pleno ≥88.
            return [
                Level(key: "depleted",  lower: nil, upper: 25),
                Level(key: "low",       lower: 25,  upper: 50),
                Level(key: "moderate",  lower: 50,  upper: 70),
                Level(key: "primed",    lower: 70,  upper: 88),
                Level(key: "peak",      lower: 88,  upper: nil),
            ]
        case .sleep:
            // Corto <360 · Suficiente 360–420 · Óptimo 420–510 · Extenso >510 (minutes).
            return [
                Level(key: "short",     lower: nil, upper: 360),
                Level(key: "adequate",  lower: 360, upper: 420),
                Level(key: "optimal",   lower: 420, upper: 510),
                Level(key: "extended",  lower: 510, upper: nil),
            ]
        case .strain:
            // Reposo <6 · Ligero 6–10 · Moderado 10–14 · Intenso 14–18 · Extremo ≥18.
            return [
                Level(key: "rest",      lower: nil, upper: 6),
                Level(key: "light",     lower: 6,   upper: 10),
                Level(key: "moderate",  lower: 10,  upper: 14),
                Level(key: "hard",      lower: 14,  upper: 18),
                Level(key: "extreme",   lower: 18,  upper: nil),
            ]
        case .restingHR:
            // Atleta <50 · Excelente 50–60 · Normal 60–80 · Elevada >80.
            return [
                Level(key: "athlete",   lower: nil, upper: 50),
                Level(key: "excellent", lower: 50,  upper: 60),
                Level(key: "normal",    lower: 60,  upper: 80),
                Level(key: "elevated",  lower: 80,  upper: nil),
            ]
        case .bloodOxygen:
            // Bajo <95 · Normal 95–100.
            return [
                Level(key: "low",    lower: nil, upper: 95),
                Level(key: "normal", lower: 95,  upper: nil),
            ]
        case .steps:
            // Sedentario <5000 · Activo 5000–10000 · Muy activo >10000.
            return [
                Level(key: "sedentary",  lower: nil,   upper: 5000),
                Level(key: "active",     lower: 5000,  upper: 10000),
                Level(key: "veryActive", lower: 10000, upper: nil),
            ]
        case .stress:
            // Bajo 0–1 · Medio 1–2 · Alto 2–3 (the 0 and 3 are the scale's ends, so the partition
            // is open at both ends to stay total).
            return [
                Level(key: "low",    lower: nil, upper: 1),
                Level(key: "medium", lower: 1,   upper: 2),
                Level(key: "high",   lower: 2,   upper: nil),
            ]
        case .respiration:
            // Normal 12–20 · Elevada >20. The README names two levels; 12 is the descriptive typical
            // floor, not a third level, so "normal" stays open below to keep the partition total.
            return [
                Level(key: "normal",   lower: nil, upper: 20),
                Level(key: "elevated", lower: 20,  upper: nil),
            ]
        }
    }

    /// Index of the level a single `value` belongs to, for a fixed metric.
    public static func index(of value: Double, for metric: FixedMetric) -> Int {
        index(of: value, in: levels(for: metric))
    }

    /// Classify a window of fixed-metric `values` (oldest→newest is irrelevant) into the metric's
    /// levels, counting each level and marking the level the `today` value sits in.
    ///
    /// - Parameters:
    ///   - values: the window's valid values (the caller drops nils first); empty → all-zero counts.
    ///   - today: the latest/active value, or `nil` for no active level.
    public static func classification(for metric: FixedMetric,
                                      values: [Double],
                                      today: Double?) -> Classification {
        classify(values: values, today: today, levels: levels(for: metric))
    }

    // MARK: - Relative-to-baseline levels (HRV, Recovery)

    /// The personal levels *below your base / in your base / above your base*, derived from the
    /// user's own `baseline` ± `k`·`sd` — no population threshold. This is how HRV is banded
    /// (RMSSD has no universal cut, only your own trend) and gives Recovery an optional personal view.
    ///
    /// Method: ±1 SD around the personal baseline brackets the central ~68% of the user's own
    /// nights (Gaussian), so "in your base" is a genuinely typical night and the tails flag a real
    /// low/high vs your norm. `k` defaults to 1 SD; the caller supplies `baseline` and `sd` (e.g. the
    /// Winsorized EWMA + spread `Baselines` already builds). Deliberately looser than
    /// `VitalBands` (which uses k=2 for a 95% in/out band) because here we want three meaningful
    /// levels, not a binary normal-range flag.
    ///
    /// Reference: HRV interpreted relative to an individual rolling baseline rather than a fixed
    /// threshold (Plews et al., 2013); RMSSD per Task Force (1996).
    ///
    /// The band is linear (`baseline ± k·sd`). The caller is responsible for supplying `baseline`
    /// and `sd` in the value's own domain — for a log-normal metric like HRV the honest band is
    /// multiplicative, so the consumer (F6b) should derive the cuts in log space (e.g. from
    /// `Baselines`' log-domain baseline) and pass linearised endpoints, rather than feeding a raw
    /// linear SD here.
    ///
    /// - Parameters:
    ///   - baseline: the user's own central value.
    ///   - sd: the dispersion of the user's own values, in the value's domain (clamped to ≥ 0).
    ///   - k: how many SDs mark the edge of "in your base" (default 1).
    public static func relativeLevels(baseline: Double, sd: Double, k: Double = 1.0) -> [Level] {
        let spread = max(sd, 0) * k
        let lowCut = baseline - spread
        let highCut = baseline + spread
        return [
            Level(key: "below",  lower: nil,    upper: lowCut),
            Level(key: "inBase", lower: lowCut, upper: highCut),
            Level(key: "above",  lower: highCut, upper: nil),
        ]
    }

    /// Classify a window of values against the relative-to-baseline levels (HRV / Recovery).
    /// Same counting contract as `classification(for:values:today:)`.
    public static func relativeClassification(values: [Double],
                                              today: Double?,
                                              baseline: Double,
                                              sd: Double,
                                              k: Double = 1.0) -> Classification {
        classify(values: values, today: today, levels: relativeLevels(baseline: baseline, sd: sd, k: k))
    }

    /// Classify a window of values against a caller-supplied `levels` array, rather than a metric's own
    /// fixed or symmetric-relative levels. F6b (HRV) uses this with personal cut points derived in LOG space
    /// from `Baselines.normalRange` (a multiplicative band in ms) — which the linear `relativeClassification`
    /// can't express. Same counting contract: half-open `[lower, upper)`, per-level counts summing to the
    /// window size, and the level `today` sits in. (FER-571)
    public static func classification(values: [Double], today: Double?, levels: [Level]) -> Classification {
        classify(values: values, today: today, levels: levels)
    }

    // MARK: - Core (shared by fixed & relative)

    /// Index of the level `value` falls into, for any contiguous, total, low→high `levels` array.
    /// Half-open `[lower, upper)`: a value on a boundary lands in the level whose `lower` it equals
    /// (the upper level). Returns the last index as a safe fallback if `levels` is somehow not total.
    static func index(of value: Double, in levels: [Level]) -> Int {
        for (i, level) in levels.enumerated() {
            let aboveLower = level.lower.map { value >= $0 } ?? true
            let belowUpper = level.upper.map { value < $0 } ?? true
            if aboveLower && belowUpper { return i }
        }
        return max(0, levels.count - 1)
    }

    private static func classify(values: [Double], today: Double?, levels: [Level]) -> Classification {
        var counts = [Int](repeating: 0, count: levels.count)
        for v in values {
            counts[index(of: v, in: levels)] += 1
        }
        let activeIndex = today.map { index(of: $0, in: levels) }
        return Classification(levels: levels, counts: counts, activeIndex: activeIndex)
    }
}
