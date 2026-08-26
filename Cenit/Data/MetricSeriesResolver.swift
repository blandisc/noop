import Foundation
import StrandModels

// MetricSeriesResolver.swift — the ONE «catalog key → daily on-device series» map (FER-104 / TND-29).
//
// Compare and Explore each carried their own copy of this resolver, and the two DISAGREED on two
// metrics — so the same metric read a different number depending on which screen you opened:
//
//   • sleep_efficiency — Compare normalized to a percent (× 100 when stored as a 0–1 fraction);
//     Explore returned the raw 0–1 value, which then rendered as «1 %» against the catalog's «%»
//     unit. Compare's normalization is correct.
//   • active_kcal / energy_kcal — Explore resolved them to the dashboard's `activeKcalEst`; Compare
//     returned nil on purpose so they load from `repo.series()`. The catalog sources active_kcal from
//     Apple Health and energy_kcal from the strap import, whereas `activeKcalEst` is a DIFFERENT figure
//     (an HR-only whole-day estimate) — resolving it silently swaps the metric's meaning. Compare's
//     note (FER-275) is the authority: calories are NOT dashboard-resolved.
//
// This is the single source both screens now call, so a key resolves to one number everywhere.

/// The single map from a `MetricCatalog` key to its daily series read from the merged on-device
/// dashboard (`repo.displayDays`). `nil` means the key is not dashboard-resolvable — the caller falls
/// back to `repo.series()` (the imports table): import-/Apple-only body metrics (weight, body fat,
/// BMI, HR-zone splits, avg/max HR) and — by policy — calories.
enum MetricSeriesResolver {

    /// The per-day picker for a dashboard-resolvable key, or `nil` for keys the dashboard doesn't
    /// compute (or must not stand in for — calories). Mirrors the key→field map the Cuerpo detail
    /// screens use (FER-149 / FER-281).
    static func dashboardPicker(for key: String) -> ((DailyMetric) -> Double?)? {
        switch key {
        case "recovery":         return { $0.recovery }
        case "strain":           return { $0.strain }
        case "hrv":              return { $0.avgHrv }
        case "rhr":              return { $0.restingHr.map(Double.init) }
        case "resp_rate":        return { $0.respRateBpm }
        case "spo2":             return { $0.spo2Pct }
        case "skin_temp":        return { $0.skinTempDevC }
        case "steps":            return { $0.steps.map(Double.init) }
        case "sleep_total_min":  return { $0.totalSleepMin }
        case "sleep_deep_min":   return { $0.deepMin }
        case "sleep_rem_min":    return { $0.remMin }
        case "sleep_light_min":  return { $0.lightMin }
        // Canonical: efficiency may be stored as a 0–1 fraction OR already as a percent; normalize to
        // a percent so the catalog's «%» unit reads «92 %», never «1 %». (Compare's rule wins over
        // Explore's raw 0–1, which was a display bug against the unit.)
        case "sleep_efficiency": return { $0.efficiency.map { $0 <= 1.0 ? $0 * 100 : $0 } }
        // Canonical: calories are NOT dashboard-resolved (return nil → caller uses `repo.series()`).
        // `activeKcalEst` is an HR-only whole-day estimate — a DIFFERENT figure than the cataloged
        // Apple-Health / strap-import calorie value, so resolving it would swap the metric's meaning.
        // (Authority: CompareView's FER-275 note.)
        case "active_kcal", "energy_kcal": return nil
        default:                 return nil
        }
    }

    /// The full ascending daily series for a key from the merged dashboard rows, or `nil` if the key
    /// isn't dashboard-resolvable (caller falls back to `repo.series()`).
    static func dashboardSeries(_ key: String, from days: [DailyMetric]) -> [(day: String, value: Double)]? {
        guard let pick = dashboardPicker(for: key) else { return nil }
        return days.compactMap { row in pick(row).map { (row.day, $0) } }.sorted { $0.day < $1.day }
    }
}
