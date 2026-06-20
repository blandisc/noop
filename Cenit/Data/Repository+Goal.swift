import Foundation
import StrandAnalytics
import WhoopStore

// Repository+Goal.swift — building a goal simulation from on-device data (FER-311).
//
// Pure composition over `TrajectorySimulator`: no math here. The focus series comes from
// `InsightEngine.outcomeSeries`, keyed by the typed `metric.outcome` (`InsightEngine.Outcome`, the single
// label→field source of truth), and the lever's magnitude is the `effectDelta` the N-of-1 experiment
// measured when it PROVED the lever — not a fresh recompute, so the projection uses exactly the effect
// the user validated.

extension Repository {

    /// Build the goal simulation for `metric` toward an optional `targetDate`.
    /// - `projection == nil` → fewer than ~two weeks of base (gate; the screen hides the chart).
    /// - `leverName == nil` → no proven lever for this metric (the "sin palancas" state).
    func goalSimulation(metric: GoalMetric, targetDate: Date?) async -> GoalSimulation {
        let sorted = days.sorted { $0.day < $1.day }
        let seriesMap = InsightEngine.outcomeSeries(sorted, metric.outcome)
        let series: [Double?] = sorted.map { seriesMap[$0.day] }
        let usable = Array(series.suffix(TrajectorySimulator.window)).compactMap { $0 }.count
        let horizon = Self.goalHorizon(targetDate: targetDate)

        // Strongest proven lever for this metric — magnitude from the experiment that validated it.
        let exps = await allExperiments()
        let proven = exps.filter {
            $0.status == .completed && $0.result == Verdict.sustained.rawValue
                && $0.outcome == metric.outcomeLabel && $0.effectDelta != nil
        }
        let best = proven.max { abs($0.effectDelta!) < abs($1.effectDelta!) }
        // Orient the delta toward "better": positive for higher-is-better metrics, negative for resting HR.
        let leverDelta: Double? = best.map {
            metric.higherIsBetter ? abs($0.effectDelta!) : -abs($0.effectDelta!)
        }

        let projection = TrajectorySimulator.project(series: series, horizonDays: horizon,
                                                     leverDelta: leverDelta, bounds: metric.bounds)

        return GoalSimulation(projection: projection,
                              leverName: leverDelta != nil ? best?.behavior : nil,
                              usableDays: usable)
    }

    /// Days from today to the goal date, clamped to a sane projection window; 14 by default (no date).
    static func goalHorizon(targetDate: Date?, today: Date = Date()) -> Int {
        guard let t = targetDate else { return 14 }
        let days = Calendar.current.dateComponents([.day], from: today, to: t).day ?? 14
        return min(90, max(7, days))
    }
}
