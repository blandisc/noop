import XCTest
import Foundation
@testable import StrandAnalytics

final class RecoveryForecastTests: XCTestCase {

    // MARK: - Honest gate (no base → nil)

    func testNilBelowMinDays() {
        // Only minDays-1 valid days → not enough base to forecast.
        let series = Array(repeating: 60.0 as Double?, count: RecoveryForecast.minDays - 1)
        XCTAssertNil(RecoveryForecast.compute(recovery: series))
    }

    func testNilWhenEmpty() {
        XCTAssertNil(RecoveryForecast.compute(recovery: []))
    }

    func testNilCountsOnlyValidDays() {
        // minDays nils + a handful of real days that still fall short of the gate → nil.
        var series: [Double?] = Array(repeating: nil, count: RecoveryForecast.window)
        for i in 0..<(RecoveryForecast.minDays - 1) { series[i] = 55 }
        XCTAssertNil(RecoveryForecast.compute(recovery: series))
    }

    // MARK: - With base → estimate + range

    func testFlatSeriesEstimatesNearLevelWithRange() {
        let series = Array(repeating: 60.0 as Double?, count: RecoveryForecast.window)
        guard let r = RecoveryForecast.compute(recovery: series) else {
            return XCTFail("expected a forecast with a full window of base")
        }
        XCTAssertEqual(r.estimate, 60.0, accuracy: 1.0, "flat series should project ~the level")
        XCTAssertEqual(r.direction, .steady)
        XCTAssertEqual(r.basisDays, RecoveryForecast.window)
        // A range, not a point: ordered, bracketing the estimate, and floored to non-trivial width.
        XCTAssertLessThanOrEqual(r.low, r.estimate)
        XCTAssertGreaterThanOrEqual(r.high, r.estimate)
        XCTAssertGreaterThanOrEqual(r.high - r.low, 2 * RecoveryForecast.bandFloorHalf - 0.001)
    }

    func testRangeStaysWithinBounds() {
        // High near the ceiling: the range must clamp into 0…100, never overshoot.
        let series = Array(repeating: 98.0 as Double?, count: RecoveryForecast.window)
        guard let r = RecoveryForecast.compute(recovery: series) else { return XCTFail() }
        XCTAssertGreaterThanOrEqual(r.low, 0)
        XCTAssertLessThanOrEqual(r.high, 100)
        XCTAssertLessThanOrEqual(r.estimate, 100)
    }

    // MARK: - Trend direction

    func testRisingTrend() {
        // 40 → 68 over the window: clearly ascending.
        let series: [Double?] = (0..<RecoveryForecast.window).map { 40.0 + Double($0) }
        guard let r = RecoveryForecast.compute(recovery: series) else { return XCTFail() }
        XCTAssertEqual(r.direction, .rising)
        // Projection should sit at or above the recent level (positive step).
        let recentMean = series.compactMap { $0 }.suffix(RecoveryForecast.levelDays)
            .reduce(0, +) / Double(RecoveryForecast.levelDays)
        XCTAssertGreaterThan(r.estimate, recentMean - 0.001)
    }

    func testFallingTrend() {
        // 80 → 52 over the window: clearly descending.
        let series: [Double?] = (0..<RecoveryForecast.window).map { 80.0 - Double($0) }
        guard let r = RecoveryForecast.compute(recovery: series) else { return XCTFail() }
        XCTAssertEqual(r.direction, .falling)
        let recentMean = series.compactMap { $0 }.suffix(RecoveryForecast.levelDays)
            .reduce(0, +) / Double(RecoveryForecast.levelDays)
        XCTAssertLessThan(r.estimate, recentMean + 0.001)
    }

    // MARK: - Sleep-debt drag

    func testSleepDebtLowersEstimate() {
        let series = Array(repeating: 65.0 as Double?, count: RecoveryForecast.window)
        guard let base = RecoveryForecast.compute(recovery: series),
              let withDebt = RecoveryForecast.compute(recovery: series, sleepDebtMin: 480) else {
            return XCTFail()
        }
        XCTAssertLessThan(withDebt.estimate, base.estimate, "a standing sleep debt should drag the projection down")
    }

    func testSmallDebtBelowFloorHasNoEffect() {
        let series = Array(repeating: 65.0 as Double?, count: RecoveryForecast.window)
        guard let base = RecoveryForecast.compute(recovery: series),
              let tiny = RecoveryForecast.compute(recovery: series, sleepDebtMin: 10) else {
            return XCTFail()
        }
        XCTAssertEqual(tiny.estimate, base.estimate, accuracy: 0.001, "debt under the floor applies no drag")
    }

    func testDebtDragIsCapped() {
        // Absurd debt must not push the drag past maxDebtDrag.
        XCTAssertEqual(RecoveryForecast.debtDrag(100_000), RecoveryForecast.maxDebtDrag, accuracy: 0.001)
        XCTAssertEqual(RecoveryForecast.debtDrag(nil), 0)
    }

    // MARK: - Robustness

    func testOutOfRangeAndMissingValuesIgnored() {
        // A full window of valid 60s, plus injected garbage that must be filtered out.
        var series: [Double?] = Array(repeating: 60.0, count: RecoveryForecast.window)
        series.insert(999, at: 3)     // impossible high
        series.insert(-5, at: 8)      // impossible low
        series.insert(nil, at: 12)    // missing
        guard let r = RecoveryForecast.compute(recovery: series) else { return XCTFail() }
        XCTAssertEqual(r.estimate, 60.0, accuracy: 1.0)
        // Garbage didn't inflate the basis beyond the real valid days in-window.
        XCTAssertLessThanOrEqual(r.basisDays, RecoveryForecast.window)
    }

    // MARK: - Math helpers

    func testOlsSlopeSign() {
        XCTAssertGreaterThan(RecoveryForecast.olsSlope([(0, 1), (1, 2), (2, 3)]), 0)
        XCTAssertLessThan(RecoveryForecast.olsSlope([(0, 3), (1, 2), (2, 1)]), 0)
        XCTAssertEqual(RecoveryForecast.olsSlope([(0, 5), (1, 5), (2, 5)]), 0, accuracy: 1e-9)
    }
}
