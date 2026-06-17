import Foundation
import StrandAnalytics
import WhoopStore

// WhatMovesIt.swift — FER-209. App-layer orchestration for the "Qué la mueve" block.
//
// Picks the relevant metric pairs for a vital, computes each over the user's OWN daily
// history with `CorrelationEngine`, and degrades the result to a gated DIRECTION (never
// a coefficient, never causation — see `MetricTrend`). The math + the sufficiency gate
// live in StrandAnalytics (pure, `swift test`); this layer only chooses which pairs to
// ask about and reads them off `repo.displayDays`.
//
// Pairs (for HRV and resting HR — the two recovery vitals; FER-185 left the other detail
// metrics without this block):
//   • same-night sleep DURATION — both vitals track how much you slept (Plews 2013).
//   • the PRIOR day's strain (lag +1) — yesterday's load shows up in tonight's vital
//     (Stanley 2013, parasympathetic reactivation); resting HR moves the opposite way.
// HRV↔recovery is deliberately excluded: recovery is computed FROM HRV (circular).

/// One gated, directional relationship to render in the "Qué la mueve" block.
struct WhatMovesItFinding: Equatable, Identifiable {
    /// Which paired relationship this describes (drives the localized, metric-agnostic sentence).
    enum Relationship: String { case sleepDuration, priorStrain }
    let relationship: Relationship
    let trend: MetricTrend
    var id: String { relationship.rawValue }
}

enum WhatMovesItEngine {

    /// The directional findings for `key`, computed from the daily history. Returns `[]`
    /// when the metric carries no pairs or none clear the gate → the block stays hidden.
    static func findings(forMetricKey key: String,
                         days: [DailyMetric],
                         gate: CorrelationEngine.TrendGate = .default) -> [WhatMovesItFinding] {
        // Only the two recovery vitals carry this block (FER-209 scope).
        let primary: (DailyMetric) -> Double?
        switch key {
        case "hrv": primary = { $0.avgHrv }
        case "rhr": primary = { $0.restingHr.map(Double.init) }
        default:    return []
        }

        let metric = series(days, primary)
        let sleep  = series(days) { $0.totalSleepMin }
        let strain = series(days) { $0.strain }

        var out: [WhatMovesItFinding] = []
        // Same-night sleep duration vs the vital (Pearson is symmetric, so order is irrelevant).
        if let dir = CorrelationEngine.trend(
            CorrelationEngine.pearson(CorrelationEngine.alignByDay(metric, sleep)), gate: gate) {
            out.append(.init(relationship: .sleepDuration, trend: dir))
        }
        // Prior-day strain (day D) vs the vital the NEXT day (day D+1): does yesterday's load
        // show up tonight? `trend` reads the sign of corr(strain, vital), so .rises ⇔ the vital
        // goes UP after a hard day.
        if let dir = CorrelationEngine.trend(
            CorrelationEngine.lagged(x: strain, y: metric, lagDays: 1), gate: gate) {
            out.append(.init(relationship: .priorStrain, trend: dir))
        }
        return out
    }

    /// Pull one metric's daily series off the history as `(day, value)`, oldest → newest.
    private static func series(_ days: [DailyMetric],
                              _ pick: (DailyMetric) -> Double?) -> [(day: String, value: Double)] {
        days.compactMap { d in pick(d).map { (d.day, $0) } }.sorted { $0.day < $1.day }
    }
}
