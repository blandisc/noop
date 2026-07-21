import XCTest
@testable import StrandAnalytics
import StrandModels

// OutcomeTests.swift — binds the Bucle's outcome join key to its single source (FER-353).
//
// FER-311 left `GoalMetric.outcomeLabel` re-typing the es-MX strings that `InsightEngine`'s outcome
// catalog owns; a rename in the engine would silently make `outcomeSeries` return `[:]` and the goal
// simulator project an empty series, with nothing failing to compile. The catalog is now the typed
// `InsightEngine.Outcome`, and `GoalMetric.outcome` *returns* a case from it (compile-checked). This
// suite pins the engine half of that contract: every outcome's field accessor is wired to a real
// `DailyMetric` column, and every outcome resolves — both typed and by-label — to a non-empty series.

final class OutcomeTests: XCTestCase {

    /// A day with every outcome field populated, so each `Outcome.value` MUST read a non-nil number.
    private func fullDay(_ day: String) -> DailyMetric {
        DailyMetric(day: day, totalSleepMin: 462, efficiency: nil, deepMin: nil, remMin: nil,
                    lightMin: nil, disturbances: nil, restingHr: 54, avgHrv: 71, recovery: 68,
                    strain: nil, exerciseCount: nil)
    }

    private func days(_ n: Int) -> [DailyMetric] {
        (1...n).map { fullDay(String(format: "2026-06-%02d", $0)) }
    }

    /// Every outcome reads a non-nil value off a fully-populated day — i.e. no case is wired to a field
    /// that doesn't exist or is always nil.
    func testEveryOutcomeReadsAPopulatedDay() {
        let d = fullDay("2026-06-01")
        for o in InsightEngine.Outcome.allCases {
            XCTAssertNotNil(o.value(d), "Outcome.\(o) must read a value off a fully-populated DailyMetric")
        }
    }

    /// The typed join (the `GoalMetric.outcome` path) yields a value for every populated day, for every
    /// outcome.
    func testTypedSeriesIsNonEmptyForEveryOutcome() {
        let ds = days(3)
        for o in InsightEngine.Outcome.allCases {
            let series = InsightEngine.outcomeSeries(ds, o)
            XCTAssertEqual(series.count, ds.count, "typed series for \(o) should cover every populated day")
        }
    }

    /// The label round-trips: every `Outcome.label` resolves back to its case AND to a non-empty series
    /// through the persisted-string overload (the experiment / lever path). This is the exact join that
    /// used to break silently when the label was re-typed in two places.
    func testLabelRoundTripsToCaseAndSeries() {
        let ds = days(3)
        for o in InsightEngine.Outcome.allCases {
            XCTAssertEqual(InsightEngine.Outcome(label: o.label), o,
                           "label '\(o.label)' must resolve back to \(o)")
            let series = InsightEngine.outcomeSeries(ds, metric: o.label)
            XCTAssertFalse(series.isEmpty, "by-label series for '\(o.label)' must be non-empty")
        }
    }

    /// An unknown or mis-typed label is rejected (nil case, empty series) rather than silently matched —
    /// the join is exact, accents included.
    func testUnknownLabelResolvesToNothing() {
        XCTAssertNil(InsightEngine.Outcome(label: "Recuperacion"))   // missing accent → not a match
        XCTAssertNil(InsightEngine.Outcome(label: "Nope"))
        XCTAssertTrue(InsightEngine.outcomeSeries(days(2), metric: "Nope").isEmpty)
    }

    /// Each outcome carries a non-empty label and unit (no case left blank).
    func testEveryOutcomeHasLabelAndUnit() {
        for o in InsightEngine.Outcome.allCases {
            XCTAssertFalse(o.label.isEmpty, "Outcome.\(o) needs a label")
            XCTAssertFalse(o.unit.isEmpty, "Outcome.\(o) needs a unit")
        }
    }
}
