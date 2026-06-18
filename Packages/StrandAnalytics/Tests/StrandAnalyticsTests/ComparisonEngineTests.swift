import XCTest
@testable import StrandAnalytics

final class ComparisonEngineTests: XCTestCase {

    func testStatHandComputed() {
        // [10,12,14,16,18]: mean 14, median 14, min 10, max 18,
        // sample SD = 3.16227766…, OLS slope vs index 0..4 = 2.0.
        let s = ComparisonEngine.stat([10, 12, 14, 16, 18])
        XCTAssertEqual(s.mean, 14.0, accuracy: 1e-9)
        XCTAssertEqual(s.median, 14.0, accuracy: 1e-9)
        XCTAssertEqual(s.min, 10.0, accuracy: 1e-9)
        XCTAssertEqual(s.max, 18.0, accuracy: 1e-9)
        XCTAssertEqual(s.stdev, 3.1622776601683795, accuracy: 1e-9)
        XCTAssertEqual(s.n, 5)
        XCTAssertEqual(s.slopePerDay, 2.0, accuracy: 1e-9)
    }

    func testStatEmpty() {
        XCTAssertEqual(ComparisonEngine.stat([]), .empty)
    }

    func testStatSingleValue() {
        let s = ComparisonEngine.stat([42])
        XCTAssertEqual(s.mean, 42.0, accuracy: 1e-9)
        XCTAssertEqual(s.median, 42.0, accuracy: 1e-9)
        XCTAssertEqual(s.stdev, 0.0, accuracy: 1e-9)   // ddof=1 undefined → 0
        XCTAssertEqual(s.slopePerDay, 0.0, accuracy: 1e-9)
        XCTAssertEqual(s.n, 1)
    }

    func testMedianEvenCount() {
        // [1,2,3,4] → (2+3)/2 = 2.5
        XCTAssertEqual(ComparisonEngine.stat([1, 2, 3, 4]).median, 2.5, accuracy: 1e-9)
    }

    func testSlopeOnDescendingSeries() {
        // Strictly decreasing by 5 → slope -5.
        let s = ComparisonEngine.stat([20, 15, 10, 5])
        XCTAssertEqual(s.slopePerDay, -5.0, accuracy: 1e-9)
    }

    func testCompareUp() {
        let c = ComparisonEngine.compare(current: [12, 14, 16], previous: [10, 10, 10])
        XCTAssertEqual(c.delta, 4.0, accuracy: 1e-9)         // mean 14 vs 10
        XCTAssertEqual(c.pctChange!, 40.0, accuracy: 1e-9)
        XCTAssertEqual(c.direction, 1)
    }

    func testCompareDown() {
        let c = ComparisonEngine.compare(current: [8, 8, 8], previous: [10, 10, 10])
        XCTAssertEqual(c.delta, -2.0, accuracy: 1e-9)
        XCTAssertEqual(c.pctChange!, -20.0, accuracy: 1e-9)
        XCTAssertEqual(c.direction, -1)
    }

    func testCompareFlat() {
        let c = ComparisonEngine.compare(current: [10, 10], previous: [10, 10])
        XCTAssertEqual(c.delta, 0.0, accuracy: 1e-9)
        XCTAssertEqual(c.pctChange!, 0.0, accuracy: 1e-9)
        XCTAssertEqual(c.direction, 0)
    }

    func testComparePreviousEmptyGivesNilPct() {
        let c = ComparisonEngine.compare(current: [10, 12], previous: [])
        XCTAssertNil(c.pctChange)
        XCTAssertEqual(c.direction, 0)   // no previous data → no direction
        XCTAssertEqual(c.previous.n, 0)
    }

    func testComparePreviousZeroMeanGivesNilPct() {
        let c = ComparisonEngine.compare(current: [5, 5], previous: [0, 0])
        XCTAssertNil(c.pctChange)       // ratio undefined when previous mean is 0
        XCTAssertEqual(c.delta, 5.0, accuracy: 1e-9)
        XCTAssertEqual(c.direction, 1)
    }

    func testMonthOverMonthSplitsOnCalendarMonth() {
        // March has values 60,62,64 (mean 62); February has 50,52 (mean 51).
        // referenceDay in March → current = March, previous = February.
        let byDay: [(day: String, value: Double)] = [
            ("2026-02-10", 50), ("2026-02-20", 52),
            ("2026-03-01", 60), ("2026-03-15", 62), ("2026-03-31", 64),
            ("2026-01-05", 99),   // out of both months → ignored
        ]
        let c = ComparisonEngine.monthOverMonth(byDay: byDay, referenceDay: "2026-03-20")
        XCTAssertEqual(c.current.n, 3)
        XCTAssertEqual(c.previous.n, 2)
        XCTAssertEqual(c.current.mean, 62.0, accuracy: 1e-9)
        XCTAssertEqual(c.previous.mean, 51.0, accuracy: 1e-9)
        XCTAssertEqual(c.delta, 11.0, accuracy: 1e-9)
        XCTAssertEqual(c.direction, 1)
        // Current month values ordered by day: 60,62,64 → slope +2/day-index.
        XCTAssertEqual(c.current.slopePerDay, 2.0, accuracy: 1e-9)
    }

    func testMonthOverMonthCrossesYearBoundary() {
        // referenceDay Jan 2026 → previous month is Dec 2025.
        let byDay: [(day: String, value: Double)] = [
            ("2025-12-01", 10), ("2025-12-31", 20),
            ("2026-01-10", 30), ("2026-01-20", 40),
        ]
        let c = ComparisonEngine.monthOverMonth(byDay: byDay, referenceDay: "2026-01-15")
        XCTAssertEqual(c.current.mean, 35.0, accuracy: 1e-9)   // Jan: 30,40
        XCTAssertEqual(c.previous.mean, 15.0, accuracy: 1e-9)  // Dec: 10,20
    }

    func testMonthOverMonthUnsortedInputStillChronologicalSlope() {
        // Same March data supplied out of order; slope must still be chronological.
        let byDay: [(day: String, value: Double)] = [
            ("2026-03-31", 64), ("2026-03-01", 60), ("2026-03-15", 62),
            ("2026-02-20", 52), ("2026-02-10", 50),
        ]
        let c = ComparisonEngine.monthOverMonth(byDay: byDay, referenceDay: "2026-03-20")
        XCTAssertEqual(c.current.slopePerDay, 2.0, accuracy: 1e-9)
    }

    func testMonthOverMonthBadReferenceDayGivesEmpty() {
        let byDay: [(day: String, value: Double)] = [("2026-03-01", 60)]
        let c = ComparisonEngine.monthOverMonth(byDay: byDay, referenceDay: "not-a-date")
        XCTAssertEqual(c.current.n, 0)
        XCTAssertEqual(c.previous.n, 0)
    }

    // MARK: - Period over period

    func testPeriodOverPeriodWeekWindowSplitsTrailingTwoWeeks() {
        // referenceDay = 2026-03-14. Current week = the 7 days 03-08…03-14; previous = 03-01…03-07.
        let byDay: [(day: String, value: Double)] = [
            ("2026-03-01", 10), ("2026-03-02", 10), ("2026-03-03", 10), ("2026-03-04", 10),
            ("2026-03-05", 10), ("2026-03-06", 10), ("2026-03-07", 10),                       // previous: 7×10
            ("2026-03-08", 20), ("2026-03-09", 20), ("2026-03-10", 20), ("2026-03-11", 20),
            ("2026-03-12", 20), ("2026-03-13", 20), ("2026-03-14", 20),                       // current: 7×20
            ("2026-02-25", 99),   // older than both windows → ignored
        ]
        let c = ComparisonEngine.periodOverPeriod(byDay: byDay, windowDays: 7, referenceDay: "2026-03-14")
        XCTAssertEqual(c.current.n, 7)
        XCTAssertEqual(c.previous.n, 7)
        XCTAssertEqual(c.current.mean, 20.0, accuracy: 1e-9)
        XCTAssertEqual(c.previous.mean, 10.0, accuracy: 1e-9)
        XCTAssertEqual(c.pctChange ?? .nan, 100.0, accuracy: 1e-9)
        XCTAssertEqual(c.direction, 1)
    }

    func testPeriodOverPeriodCrossesMonthBoundaryByCalendarDistance() {
        // A 30-day window ending 2026-03-10 reaches back to 2026-02-09 (current), prior 30 to 2026-01-10.
        let byDay: [(day: String, value: Double)] = [
            ("2026-02-09", 4), ("2026-03-10", 8),   // both in the current 30-day window
            ("2026-01-20", 2),                       // in the previous 30-day window
            ("2026-01-01", 99),                      // older → ignored
        ]
        let c = ComparisonEngine.periodOverPeriod(byDay: byDay, windowDays: 30, referenceDay: "2026-03-10")
        XCTAssertEqual(c.current.n, 2)             // 02-09 and 03-10
        XCTAssertEqual(c.previous.n, 1)            // 01-20
        XCTAssertEqual(c.current.mean, 6.0, accuracy: 1e-9)
        XCTAssertEqual(c.previous.mean, 2.0, accuracy: 1e-9)
    }

    func testPeriodOverPeriodEmptyPreviousGivesNilPct() {
        let byDay: [(day: String, value: Double)] = [("2026-03-13", 5), ("2026-03-14", 5)]
        let c = ComparisonEngine.periodOverPeriod(byDay: byDay, windowDays: 7, referenceDay: "2026-03-14")
        XCTAssertEqual(c.current.n, 2)
        XCTAssertEqual(c.previous.n, 0)
        XCTAssertNil(c.pctChange)
        XCTAssertEqual(c.direction, 0)
    }

    func testEpochDayConsecutiveDaysDifferByOne() {
        XCTAssertEqual(ComparisonEngine.epochDay(of: "2026-03-01")! - ComparisonEngine.epochDay(of: "2026-02-28")!, 1)
        // 2024 is a leap year → Feb has 29 days.
        XCTAssertEqual(ComparisonEngine.epochDay(of: "2024-03-01")! - ComparisonEngine.epochDay(of: "2024-02-29")!, 1)
        XCTAssertEqual(ComparisonEngine.epochDay(of: "1970-01-01"), 0)
        XCTAssertNil(ComparisonEngine.epochDay(of: "not-a-date"))
    }
}
