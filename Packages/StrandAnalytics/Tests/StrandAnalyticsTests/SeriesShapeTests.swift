import XCTest
@testable import StrandAnalytics

final class SeriesShapeTests: XCTestCase {

    // MARK: - movingAverage

    func testMovingAverageSameLengthAsInput() {
        let v = [1.0, 2, 3, 4, 5, 6, 7, 8]
        XCTAssertEqual(SeriesShape.movingAverage(v, window: 7).count, v.count)
    }

    func testMovingAverageTrailingHandComputed() {
        // window 3 over [1,2,3,4,5]:
        //  i0: mean[1]               = 1
        //  i1: mean[1,2]             = 1.5
        //  i2: mean[1,2,3]           = 2
        //  i3: mean[2,3,4]           = 3
        //  i4: mean[3,4,5]           = 4
        let out = SeriesShape.movingAverage([1, 2, 3, 4, 5], window: 3)
        let expected = [1.0, 1.5, 2.0, 3.0, 4.0]
        XCTAssertEqual(out.count, expected.count)
        for (a, b) in zip(out, expected) { XCTAssertEqual(a, b, accuracy: 1e-9) }
    }

    func testMovingAverageHeadUsesShortestPrefix() {
        // The first point with no full window behind it is just itself; the second is
        // the mean of the first two — i.e. the head is the shortest available prefix.
        let out = SeriesShape.movingAverage([10, 20, 30], window: 7)
        XCTAssertEqual(out[0], 10.0, accuracy: 1e-9)
        XCTAssertEqual(out[1], 15.0, accuracy: 1e-9)
        XCTAssertEqual(out[2], 20.0, accuracy: 1e-9)   // (10+20+30)/3
    }

    func testMovingAverageConstantSeriesIsFlat() {
        let out = SeriesShape.movingAverage([5, 5, 5, 5, 5], window: 7)
        for v in out { XCTAssertEqual(v, 5.0, accuracy: 1e-9) }
    }

    func testMovingAverageEmptyAndDegenerateWindow() {
        XCTAssertEqual(SeriesShape.movingAverage([], window: 7), [])
        // window <= 1 returns the input unchanged (no smoothing).
        XCTAssertEqual(SeriesShape.movingAverage([1, 2, 3], window: 1), [1, 2, 3])
    }

    // MARK: - latestMovingAverage

    func testLatestMovingAverageIsMeanOfTail() {
        // last 7 of a 10-long series: values 4...10, mean = 7.
        let v = (1...10).map(Double.init)
        XCTAssertEqual(SeriesShape.latestMovingAverage(v, window: 7)!, 7.0, accuracy: 1e-9)
    }

    func testLatestMovingAverageShortSeriesUsesAllAvailable() {
        // Fewer points than the window → mean of everything present.
        XCTAssertEqual(SeriesShape.latestMovingAverage([3, 5], window: 7)!, 4.0, accuracy: 1e-9)
    }

    func testLatestMovingAverageEmptyIsNil() {
        XCTAssertNil(SeriesShape.latestMovingAverage([], window: 7))
    }

    func testLatestMovingAverageEqualsLastOfFullSeries() {
        // The latest MA must equal the last element of the full trailing-MA series.
        let v = [40.0, 44, 39, 51, 47, 42, 55, 49, 46]
        let full = SeriesShape.movingAverage(v, window: 7)
        XCTAssertEqual(SeriesShape.latestMovingAverage(v, window: 7)!, full.last!, accuracy: 1e-9)
    }

    // MARK: - coefficientOfVariation

    func testCoefficientOfVariationHandComputed() {
        // [10,12,14,16,18] over a window covering all 5: mean 14,
        // sample SD = 3.1622776601683795 → CV = SD/14 = 0.225876975…
        let cv = SeriesShape.coefficientOfVariation([10, 12, 14, 16, 18], window: 7)!
        XCTAssertEqual(cv, 3.1622776601683795 / 14.0, accuracy: 1e-12)
    }

    func testCoefficientOfVariationUsesTailWindowRobustToNoisyHead() {
        // A wild head followed by a perfectly steady tail of 7: with window 7 the CV
        // is computed over the steady tail only, so it's ~0 regardless of the head.
        let noisyHead = [200.0, 5, 180, 9]
        let steadyTail = Array(repeating: 50.0, count: 7)
        let cv = SeriesShape.coefficientOfVariation(noisyHead + steadyTail, window: 7)!
        XCTAssertEqual(cv, 0.0, accuracy: 1e-12)
    }

    func testCoefficientOfVariationConstantTailIsZero() {
        let cv = SeriesShape.coefficientOfVariation([7, 7, 7, 7], window: 7)!
        XCTAssertEqual(cv, 0.0, accuracy: 1e-12)
    }

    func testCoefficientOfVariationNilWhenFewerThanTwo() {
        XCTAssertNil(SeriesShape.coefficientOfVariation([], window: 7))
        XCTAssertNil(SeriesShape.coefficientOfVariation([42], window: 7))
    }

    func testCoefficientOfVariationNilWhenMeanNearZero() {
        // Symmetric around zero → mean ≈ 0 → ratio undefined → nil.
        XCTAssertNil(SeriesShape.coefficientOfVariation([-5, 5, -5, 5], window: 7))
    }

    func testCoefficientOfVariationIsFractionNotPercent() {
        // A 7-day tail oscillating ±10% of a ~46 mean lands well under 1.0 (a fraction),
        // not in the tens (a percent) — guards the documented return contract.
        let cv = SeriesShape.coefficientOfVariation([44, 48, 45, 47, 46, 44, 48], window: 7)!
        XCTAssertGreaterThan(cv, 0)
        XCTAssertLessThan(cv, 1.0)
    }
}
