import XCTest
@testable import StrandAnalytics

/// Pins `MetricFormat` (FER-29 · contrato 5): one grammar per metric for value, unit and band edge,
/// so the hero, axis, scrub and levels table can never restate a number differently. Cases are the
/// exact examples in the requirement plus the boundary rendering the levels table reads.
final class MetricFormatTests: XCTestCase {

    // MARK: - The requirement's worked examples

    func testSleepMinutesRenderAsClock() {
        let f = MetricFormat.forMetric(.sleep)
        XCTAssertEqual(f.numeral(432), "7:12")   // the example
        XCTAssertEqual(f.numeral(360), "6:00")
        XCTAssertEqual(f.numeral(420), "7:00")
        XCTAssertEqual(f.numeral(510), "8:30")
        XCTAssertEqual(f.numeral(5), "0:05")     // pads minutes
        XCTAssertEqual(f.full(432), "7:12")      // no unit hung
    }

    func testStrainHeroIsOneDecimalEdgesAreWhole() {
        let f = MetricFormat.forMetric(.strain)
        XCTAssertEqual(f.numeral(10), "10.0")    // the example
        XCTAssertEqual(f.numeral(10.04), "10.0")
        XCTAssertEqual(f.boundary(18), "18")     // edge is whole
        XCTAssertEqual(f.scaleSuffix, "/ 21")
        XCTAssertNil(f.unit)
    }

    func testSpo2IsIntegerPercentTight() {
        let f = MetricFormat.forMetric(.bloodOxygen)
        XCTAssertEqual(f.numeral(97), "97")      // the example
        XCTAssertEqual(f.full(97), "97%")        // «97%», tight
        XCTAssertEqual(f.unit, "%")
        XCTAssertTrue(f.unitTight)
    }

    func testRespirationIsOneDecimal() {
        let f = MetricFormat.forMetric(.respiration)
        XCTAssertEqual(f.numeral(14.2), "14.2")  // the example
        XCTAssertEqual(f.full(14.2), "14.2 rpm")
        XCTAssertEqual(f.boundary(20), "20")     // whole edge
    }

    func testRestingHRIsIntegerWithSpacedBpm() {
        let f = MetricFormat.forMetric(.restingHR)
        XCTAssertEqual(f.numeral(58.4), "58")    // whole, rounded
        XCTAssertEqual(f.full(58), "58 bpm")     // spaced unit
        XCTAssertFalse(f.unitTight)
    }

    // MARK: - Rounding & signed / grouped styles

    func testIntegerRoundsHalfUp() {
        let f = MetricFormat.forMetric(.bloodOxygen)
        XCTAssertEqual(f.numeral(96.5), "97")
        XCTAssertEqual(f.numeral(96.4), "96")
    }

    func testStepsGroupThousandsDeterministically() {
        let f = MetricFormat.forMetric(.steps)
        XCTAssertEqual(f.numeral(8240), "8,240")
        XCTAssertEqual(f.numeral(999), "999")
        XCTAssertEqual(f.numeral(1000000), "1,000,000")
    }

    func testSkinTempAlwaysSignedWithRealMinus() {
        let f = MetricFormat.forMetric(.skinTemp)
        XCTAssertEqual(f.numeral(0.4), "+0.4")
        XCTAssertEqual(f.numeral(-0.4), "−0.4")   // real «−», not ASCII «-»
        XCTAssertEqual(f.numeral(0), "+0.0")
        XCTAssertEqual(f.full(0.4), "+0.4 °C")
    }

    // MARK: - range(): the levels-table text derives from the same grammar

    func testRangeRendersHalfOpenBands() {
        let spo2 = MetricFormat.forMetric(.bloodOxygen)
        XCTAssertEqual(spo2.range(lower: nil, upper: 95), "< 95%")
        XCTAssertEqual(spo2.range(lower: 95, upper: nil), "≥ 95%")

        let rhr = MetricFormat.forMetric(.restingHR)
        XCTAssertEqual(rhr.range(lower: nil, upper: 50), "< 50 bpm")
        XCTAssertEqual(rhr.range(lower: 60, upper: 80), "60 – 80 bpm")   // unit once, on the right
        XCTAssertEqual(rhr.range(lower: 80, upper: nil), "≥ 80 bpm")

        let strain = MetricFormat.forMetric(.strain)
        XCTAssertEqual(strain.range(lower: nil, upper: 6), "< 6")
        XCTAssertEqual(strain.range(lower: 6, upper: 10), "6 – 10")
        XCTAssertEqual(strain.range(lower: 18, upper: nil), "≥ 18")     // honest open top

        let sleep = MetricFormat.forMetric(.sleep)
        XCTAssertEqual(sleep.range(lower: 420, upper: 510), "7:00 – 8:30")
        XCTAssertEqual(sleep.range(lower: nil, upper: 360), "< 6:00")
    }

    func testRangeOpenBothSidesIsEmpty() {
        let f = MetricFormat.forMetric(.strain)
        XCTAssertEqual(f.range(lower: nil, upper: nil), "")
    }
}
