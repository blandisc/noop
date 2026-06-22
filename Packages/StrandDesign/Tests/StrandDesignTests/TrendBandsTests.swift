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

    // MARK: - summarize (FER-459)

    // Resting HR bands in bpm: Athlete [-,50) · Excellent [50,60) · Normal [60,80) · Elevated [80,-)
    private let rhr: [TrendBand] = [
        TrendBand(label: "Athlete", lower: nil, upper: 50),
        TrendBand(label: "Excellent", lower: 50, upper: 60),
        TrendBand(label: "Normal", lower: 60, upper: 80),
        TrendBand(label: "Elevated", lower: 80, upper: nil),
    ]

    /// The owner's example: 9 days Normal, 5 days Excellent, today 59 (Excellent). Dominant Normal, a
    /// clear majority → `.mostly`; today sits in a lower-value band → `.lower` ("hoy bajaste a Excelente").
    func testSummarizeMostlyWithLowerToday() {
        let values = [62.0, 65, 70, 72, 61, 64, 68, 75, 66,   // 9 Normal
                      59, 58, 55, 57, 59]                       // 5 Excellent
        let s = TrendBands.summarize(values: values, bands: rhr, todayIndex: 1)!
        XCTAssertEqual(s.n, 14)
        XCTAssertEqual(s.counts, [0, 5, 9, 0])
        XCTAssertEqual(s.dominant, 2)         // Normal
        XCTAssertEqual(s.tier, .mostly)
        XCTAssertEqual(s.todayVsDominant, .lower)
    }

    func testSummarizeAlmostAlways() {
        // 13 of 14 in band 0, one stray in band 1 → ≥ 0.8 share.
        let spo2: [TrendBand] = [
            TrendBand(label: "Normal", lower: 95, upper: nil),
            TrendBand(label: "Borderline", lower: 90, upper: 95),
            TrendBand(label: "Low", lower: nil, upper: 90),
        ]
        // bands here are high-to-low, so "Normal" is index 0.
        let values = Array(repeating: 97.0, count: 13) + [93.0]
        let s = TrendBands.summarize(values: values, bands: spo2, todayIndex: 0)!
        XCTAssertEqual(s.tier, .almostAlways)
        XCTAssertEqual(s.dominant, 0)
        XCTAssertEqual(s.todayVsDominant, .same)
    }

    func testSummarizeAlways() {
        let values = Array(repeating: 66.0, count: 10)   // all Normal
        let s = TrendBands.summarize(values: values, bands: rhr, todayIndex: 2)!
        XCTAssertEqual(s.tier, .always)
        XCTAssertEqual(s.todayVsDominant, .same)
    }

    func testSummarizeAlternatingAdjacentWithNoToday() {
        // Steps-like spread: 2 / 5 / 5 / 2 → top two (Light, Active) adjacent, together 10/14 ≥ 0.7.
        let steps: [TrendBand] = [
            TrendBand(label: "Sedentary", lower: nil, upper: 5000),
            TrendBand(label: "Light", lower: 5000, upper: 8000),
            TrendBand(label: "Active", lower: 8000, upper: 10000),
            TrendBand(label: "Very active", lower: 10000, upper: nil),
        ]
        let values = [3000.0, 4000,                       // 2 Sedentary
                      6000, 6500, 7000, 7500, 5500,       // 5 Light
                      8500, 9000, 9500, 8200, 9900,       // 5 Active
                      11000, 12000]                       // 2 Very active
        let s = TrendBands.summarize(values: values, bands: steps, todayIndex: nil)!
        XCTAssertEqual(s.counts, [2, 5, 5, 2])
        XCTAssertEqual(s.tier, .alternating)
        XCTAssertEqual(s.dominant, 1)        // ties break to the lower index
        XCTAssertEqual(s.second, 2)
        XCTAssertNil(s.todayVsDominant)      // partial day → no "today"
    }

    func testSummarizeScatteredWhenNoPairDominates() {
        // Spread 4 / 4 / 3 / 3: the top two are adjacent but together only 8/14 (< 0.7), and nothing
        // reaches a 0.5 majority → no clear shape.
        let values = [45.0, 46, 47, 48,         // 4 Athlete (0)
                      52, 54, 56, 58,           // 4 Excellent (1)
                      66, 70, 72,               // 3 Normal (2)
                      85, 90, 95]               // 3 Elevated (3)
        let s = TrendBands.summarize(values: values, bands: rhr, todayIndex: 2)!
        XCTAssertEqual(s.counts, [4, 4, 3, 3])
        XCTAssertEqual(s.tier, .scattered)
    }

    func testSummarizeHigherToday() {
        // Mostly Medium, today High → today in a higher-value band.
        let stress: [TrendBand] = [
            TrendBand(label: "Low", lower: nil, upper: 1),
            TrendBand(label: "Medium", lower: 1, upper: 2),
            TrendBand(label: "High", lower: 2, upper: nil),
        ]
        let values = [0.4, 0.6, 0.8, 0.9, 0.5, 0.7,   // 6 Low
                      1.2, 1.4, 1.6, 1.1, 1.7, 1.3, 1.9,  // 7 Medium
                      2.4]                                  // 1 High
        let s = TrendBands.summarize(values: values, bands: stress, todayIndex: 2)!
        XCTAssertEqual(s.dominant, 1)
        XCTAssertEqual(s.tier, .mostly)
        XCTAssertEqual(s.todayVsDominant, .higher)
    }

    func testSummarizeEmptyOrNoBandsYieldsNil() {
        XCTAssertNil(TrendBands.summarize(values: [], bands: rhr, todayIndex: nil))
        XCTAssertNil(TrendBands.summarize(values: [66.0], bands: [], todayIndex: nil))
    }
}
