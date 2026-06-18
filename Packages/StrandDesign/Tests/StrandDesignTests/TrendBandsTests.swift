import XCTest
@testable import StrandDesign

/// FER-244 — `TrendBands` is the pure band math behind the trend chart's moving "active band" bracket
/// and the "N of the last N days in this range" count. Membership is a half-open interval `[lower, upper)`
/// with `nil` = open; the active band follows the LAST value, and the count is how many values share it.
final class TrendBandsTests: XCTestCase {

    // Sleep bands in hours: Short [-,6) · Adequate [6,7) · Optimal [7,9) · Extended [9,-)
    private let sleep: [TrendBand] = [
        TrendBand(label: "Short", lower: nil, upper: 6),
        TrendBand(label: "Adequate", lower: 6, upper: 7),
        TrendBand(label: "Optimal", lower: 7, upper: 9),
        TrendBand(label: "Extended", lower: 9, upper: nil),
    ]

    func testContainsHalfOpen() {
        XCTAssertTrue(sleep[1].contains(6.0))    // lower is inclusive
        XCTAssertFalse(sleep[1].contains(7.0))   // upper is exclusive
        XCTAssertTrue(sleep[2].contains(7.0))    // 7 belongs to Optimal
        XCTAssertTrue(sleep[0].contains(0.4))    // open-below catches the low outlier
        XCTAssertTrue(sleep[3].contains(11.0))   // open-above catches long sleeps
    }

    func testIndexContaining() {
        XCTAssertEqual(TrendBands.index(containing: 5.9, in: sleep), 0)
        XCTAssertEqual(TrendBands.index(containing: 6.5, in: sleep), 1)
        XCTAssertEqual(TrendBands.index(containing: 8.0, in: sleep), 2)
        XCTAssertEqual(TrendBands.index(containing: 9.0, in: sleep), 3)
    }

    func testActiveBandFollowsLastValueAndCounts() {
        // Last value 7.4 → Optimal (index 2). Of the series, 7.4/8.0/7.0 land in Optimal → count 3.
        let values = [6.2, 5.4, 6.9, 8.0, 7.0, 7.4]
        let result = TrendBands.activeBand(values: values, bands: sleep)
        XCTAssertEqual(result?.index, 2)
        XCTAssertEqual(result?.count, 3)
    }

    func testActiveBandMovesWithLastValue() {
        // Same series but a short last night → active band is Short (index 0), count 1 (only the 5.4… wait)
        let values = [7.4, 8.0, 5.4]
        let result = TrendBands.activeBand(values: values, bands: sleep)
        XCTAssertEqual(result?.index, 0)   // last value 5.4 → Short
        XCTAssertEqual(result?.count, 1)   // only 5.4 is Short
    }

    func testEmptyValuesYieldNil() {
        XCTAssertNil(TrendBands.activeBand(values: [], bands: sleep))
    }

    func testStressBandsThreeWay() {
        // Stress score: Low [-,1) · Medium [1,2) · High [2,-)
        let stress: [TrendBand] = [
            TrendBand(label: "Low", lower: nil, upper: 1),
            TrendBand(label: "Medium", lower: 1, upper: 2),
            TrendBand(label: "High", lower: 2, upper: nil),
        ]
        XCTAssertEqual(TrendBands.index(containing: 0.5, in: stress), 0)
        XCTAssertEqual(TrendBands.index(containing: 1.0, in: stress), 1)
        XCTAssertEqual(TrendBands.index(containing: 2.0, in: stress), 2)
        let r = TrendBands.activeBand(values: [0.5, 1.4, 2.2, 1.8], bands: stress)
        XCTAssertEqual(r?.index, 1)   // last 1.8 → Medium
        XCTAssertEqual(r?.count, 2)   // 1.4 and 1.8
    }
}
