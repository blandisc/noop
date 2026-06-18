import Foundation

// WhatMovesStrain.swift — directional drivers of DAY STRAIN. (FER-239)
//
// The sibling of the "Qué la mueve" block for the recovery vitals (HRV / resting HR, wired in the app
// layer's `WhatMovesItEngine`), but with STRAIN as the TARGET — "qué mueve tu esfuerzo". Same discipline
// as FER-209: degrade the Pearson r to a gated DIRECTION only (never a coefficient, never a causal claim),
// reusing `CorrelationEngine` + `TrendGate`. Pure, deterministic, DB-free → covered by `swift test`.
//
// Predictors (deliberately non-circular — strain is the heart-rate-zone load TRIMP, so anything that
// directly BUILDS that total — workout count, steps, active kcal — would correlate by construction and
// teach nothing; those are excluded, the same way the HRV engine excludes recovery as circular):
//   • SAME-DAY RECOVERY — recovery is scored each morning from overnight HRV/RHR/sleep, so it predates the
//     day's accumulated load; higher morning readiness tends to coincide with a higher-strain day. This is
//     the HRV-guided-training relationship: athletes take on and tolerate more load on high-readiness days
//     (Plews 2013; Vesterinen 2016). Non-circular: strain is not computed from recovery.
//   • PRIOR-DAY STRAIN (lag +1) — yesterday's load vs today's: does a hard day tend to be followed by
//     another hard day, or by a lighter one? Lag-1 autocorrelation of the load series — the training-
//     pattern signal.
//
// The block surfaces only the relationships that clear the FER-209 sufficiency + strength gate (≥ ~6 weeks
// of paired days, |r| ≥ 0.20, p < 0.05). When none clear it, `drivers` returns `[]` → the caller HIDES the
// block; it never invents a direction.

/// Which day-level driver a `StrainDriverFinding` describes (drives the localized, direction-aware copy).
public enum StrainDriver: Sendable {
    /// The same day's recovery score (morning readiness, which predates the day's load).
    case sameDayRecovery
    /// The prior day's Day Strain (lag +1).
    case priorDayStrain
}

/// One gated, directional relationship to render in the "Qué mueve tu esfuerzo" block: which driver, and
/// which way strain leans as that driver rises. Never carries a coefficient or an implied cause.
public struct StrainDriverFinding: Equatable, Sendable {
    public let driver: StrainDriver
    public let trend: MetricTrend
    public init(driver: StrainDriver, trend: MetricTrend) {
        self.driver = driver
        self.trend = trend
    }
}

public enum WhatMovesStrainEngine {

    /// The directional drivers of day strain, computed from the user's OWN daily history. Each series is
    /// `(day "yyyy-MM-dd", value)` in any order; only days present in both a pair are used. Returns only
    /// the relationships that clear `gate`, in a stable order (recovery, then prior-day strain); `[]` when
    /// none do → the caller hides the block.
    public static func drivers(strain: [(day: String, value: Double)],
                               recovery: [(day: String, value: Double)],
                               gate: CorrelationEngine.TrendGate = .default) -> [StrainDriverFinding] {
        var out: [StrainDriverFinding] = []

        // Same-day recovery vs strain. Pearson is symmetric, so corr(strain, recovery) has the sign we
        // want: `.rises` ⇔ strain runs HIGHER on days you start more recovered.
        if let dir = CorrelationEngine.trend(
            CorrelationEngine.pearson(CorrelationEngine.alignByDay(strain, recovery)), gate: gate) {
            out.append(.init(driver: .sameDayRecovery, trend: dir))
        }

        // Prior-day strain (day D) vs strain the NEXT day (day D+1): lag-1 autocorrelation. `.rises` ⇔ a
        // hard day tends to be followed by another hard day.
        if let dir = CorrelationEngine.trend(
            CorrelationEngine.lagged(x: strain, y: strain, lagDays: 1), gate: gate) {
            out.append(.init(driver: .priorDayStrain, trend: dir))
        }

        return out
    }
}
