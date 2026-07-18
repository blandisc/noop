import XCTest
import CenitStore
import StrandAnalytics
@testable import Cenit

// GoalMetricBindingTests.swift — the Bucle goal's outcome join can't break silently (FER-353).
//
// End-to-end half of the FER-353 contract (the engine half is StrandAnalytics' OutcomeTests): for every
// `GoalMetric`, the label it exposes resolves to a non-empty outcome series given a day that carries
// only that metric's field. `GoalMetric.outcome` is compile-checked against `InsightEngine.Outcome`, so
// this guards the data half — that each goal maps to the field the engine actually reads, and that the
// typed and by-label paths agree.

final class GoalMetricBindingTests: XCTestCase {

    /// A day carrying ONLY `metric`'s field, so a non-empty series proves that field is the one the
    /// engine reads for this goal (a mis-wired case would read a nil column and yield `[:]`).
    private func day(_ key: String, for metric: GoalMetric) -> DailyMetric {
        DailyMetric(day: key,
                    totalSleepMin: metric == .sleep ? 462 : nil,
                    efficiency: nil, deepMin: nil, remMin: nil, lightMin: nil, disturbances: nil,
                    restingHr: metric == .restingHr ? 54 : nil,
                    avgHrv: metric == .hrv ? 71 : nil,
                    recovery: metric == .recovery ? 68 : nil,
                    strain: nil, exerciseCount: nil)
    }

    func testEveryGoalMetricResolvesToANonEmptySeries() {
        for metric in GoalMetric.allCases {
            let days = (1...3).map { day(String(format: "2026-06-%02d", $0), for: metric) }

            // The label path (proven-lever / experiment join key).
            let byLabel = InsightEngine.outcomeSeries(days, metric: metric.outcomeLabel)
            XCTAssertFalse(byLabel.isEmpty,
                           "GoalMetric.\(metric) (label '\(metric.outcomeLabel)') must resolve to a non-empty series")

            // The typed path the simulator actually uses, and that it agrees with the label path.
            let typed = InsightEngine.outcomeSeries(days, metric.outcome)
            XCTAssertEqual(typed.count, byLabel.count, "typed and by-label series must agree for \(metric)")
            XCTAssertEqual(metric.outcome.label, metric.outcomeLabel, "outcomeLabel must be derived from outcome")
        }
    }
}
