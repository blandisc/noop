import XCTest
@testable import CenitDesign

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

    // MARK: - A band with no bounds contains NOTHING (FER-1045 · C2)

    /// The safety net behind the sleep sub-metric fix: an unbounded band used to swallow every value
    /// (`nil == nil && nil == nil` → true), so any caller that forgot its cutoffs got a free
    /// "N of the last N nights in this range". A band that declares no interval classifies nothing.
    func testBandWithoutBoundsContainsNothing() {
        let unbounded = TrendBand(label: "No bounds", lower: nil, upper: nil)
        XCTAssertFalse(unbounded.contains(0))
        XCTAssertFalse(unbounded.contains(-12.5))
        XCTAssertFalse(unbounded.contains(85))
        XCTAssertFalse(unbounded.contains(.greatestFiniteMagnitude))

        XCTAssertNil(TrendBands.index(containing: 85, in: [unbounded]))
        XCTAssertNil(TrendBands.activeBand(values: [70, 85, 92], bands: [unbounded]))
        XCTAssertNil(TrendBands.summarize(values: [70, 85, 92], bands: [unbounded], todayIndex: nil))
    }

    /// A half-bounded band is untouched by the guard — only the fully open one is empty.
    func testHalfBoundedBandStillContains() {
        XCTAssertTrue(TrendBand(label: "Open below", lower: nil, upper: 70).contains(12))
        XCTAssertTrue(TrendBand(label: "Open above", lower: 85, upper: nil).contains(1_000))
    }

    // MARK: - Sleep sub-metric ladders (FER-1045 · C1)
    //
    // Mirrors of `MetricInfo.sleepPerformance` / `.sleepEfficiency` / `.sleepRestorative`
    // (`Cenit/Screens/MetricInfoCatalog.swift`), which live in the app module and so can't be imported
    // here. Units are PERCENT — the same the trend chart plots. Keep the numbers in sync with the
    // catalog: they are the cutoffs the sheet's band readout and per-band night counts are built on.

    /// Performance: Low [-,70) · Adequate [70,85) · Optimal [85,-)
    private let sleepPerformance: [TrendBand] = [
        TrendBand(label: "Low", lower: nil, upper: 70),
        TrendBand(label: "Adequate", lower: 70, upper: 85),
        TrendBand(label: "Optimal", lower: 85, upper: nil),
    ]

    /// Efficiency: Low [-,75) · Adequate [75,85) · Optimal [85,-)
    private let sleepEfficiency: [TrendBand] = [
        TrendBand(label: "Low", lower: nil, upper: 75),
        TrendBand(label: "Adequate", lower: 75, upper: 85),
        TrendBand(label: "Optimal", lower: 85, upper: nil),
    ]

    /// Restorative: Low [-,30) · Typical [30,50) · High [50,-)
    private let sleepRestorative: [TrendBand] = [
        TrendBand(label: "Low", lower: nil, upper: 30),
        TrendBand(label: "Typical", lower: 30, upper: 50),
        TrendBand(label: "High", lower: 50, upper: nil),
    ]

    /// The defect this fixes, stated as a test: with the old boundless bands EVERY value landed in the
    /// FIRST band, so the table read "14 nights / 0 / 0" and the readout "14 of the last 14". With real
    /// cutoffs the 14 nights split three ways, the counts differ, and they still sum to the window.
    func testSleepPerformanceSplitsFourteenNightsAcrossThreeBands() {
        let values = [62.0, 71, 86, 66, 74, 88, 68, 78, 90, 80, 92, 83, 95, 100]
        let s = TrendBands.summarize(values: values, bands: sleepPerformance, todayIndex: 2)!
        XCTAssertEqual(s.counts, [3, 5, 6])          // Low 62/66/68 · Adequate 71/74/78/80/83 · Optimal 86/88/90/92/95/100
        XCTAssertEqual(s.counts.reduce(0, +), 14)    // every night classified, none double-counted
        XCTAssertEqual(Set(s.counts).count, 3)       // three DIFFERENT counts — not the old 14/0/0
        XCTAssertEqual(s.n, 14)

        // The readout ("N of the last 14 nights in this range") now says 6, not 14.
        let active = TrendBands.activeBand(values: values, bands: sleepPerformance)
        XCTAssertEqual(active?.index, 2)             // last night 100 → Optimal
        XCTAssertEqual(active?.count, 6)
        XCTAssertLessThan(active!.count, values.count)
    }

    func testSleepEfficiencyCutoffs() {
        XCTAssertEqual(TrendBands.index(containing: 74.9, in: sleepEfficiency), 0)
        XCTAssertEqual(TrendBands.index(containing: 75.0, in: sleepEfficiency), 1)
        XCTAssertEqual(TrendBands.index(containing: 84.9, in: sleepEfficiency), 1)
        XCTAssertEqual(TrendBands.index(containing: 85.0, in: sleepEfficiency), 2)
    }

    /// The one-integer edge the catalog change documents: the interval is half-open, so **exactly 50**
    /// is High, not Typical. The catalog's `isActive` for `sleepRestorative` was moved to match
    /// (`>= 30 && < 50` / `>= 50`); before, a 50.0 night lit the "Typical" row while being counted in
    /// "High". The visible copy ("30 – 50%" / "> 50%") is deliberately unchanged.
    func testSleepRestorativeFiftyIsHighNotTypical() {
        XCTAssertTrue(sleepRestorative[1].contains(49.9))
        XCTAssertFalse(sleepRestorative[1].contains(50.0))
        XCTAssertTrue(sleepRestorative[2].contains(50.0))
        XCTAssertEqual(TrendBands.index(containing: 50.0, in: sleepRestorative), 2)

        // Counts written by hand: Low 28 → 1 · Typical 30 / 44 / 49.9 → 3 · High 50 / 55 / 62 → 3.
        let values = [28.0, 30.0, 44.0, 49.9, 50.0, 55.0, 62.0]
        let s = TrendBands.summarize(values: values, bands: sleepRestorative, todayIndex: 2)!
        XCTAssertEqual(s.counts, [1, 3, 3])
        XCTAssertEqual(s.n, 7)
        XCTAssertEqual(s.dominant, 1)                // ties break toward the lower band index
        XCTAssertEqual(s.todayVsDominant, .higher)
    }

    /// Each ladder is contiguous and open at both ends, so every possible reading lands in EXACTLY one
    /// band — no gap that silently drops a night from the counts, no overlap that counts it twice.
    func testSleepLaddersPartitionTheWholeRange() {
        for bands in [sleepPerformance, sleepEfficiency, sleepRestorative] {
            for v in stride(from: -20.0, through: 140.0, by: 0.5) {
                let hits = bands.filter { $0.contains(v) }.count
                XCTAssertEqual(hits, 1, "value \(v) landed in \(hits) bands")
            }
        }
    }
}
