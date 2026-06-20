import XCTest
import Foundation
@testable import StrandAnalytics

final class TrajectorySimulatorTests: XCTestCase {

    // A linearly spaced `[Double?]` series, oldest → newest.
    private func series(from: Double, to: Double, count: Int) -> [Double?] {
        guard count > 1 else { return [from] }
        return (0..<count).map { i in from + (to - from) * Double(i) / Double(count - 1) }
    }

    private let b0_100: ClosedRange<Double> = 0...100

    // MARK: - Honest gate

    func testNilBelowMinDays() {
        let s = Array(repeating: 60.0 as Double?, count: TrajectorySimulator.minDays - 1)
        XCTAssertNil(TrajectorySimulator.project(series: s, horizonDays: 14, bounds: b0_100))
    }

    func testNilCountsOnlyValidDays() {
        // A full window of slots but most are nil / out-of-range → still below the gate.
        var s: [Double?] = Array(repeating: nil, count: TrajectorySimulator.window)
        for i in 0..<(TrajectorySimulator.minDays - 1) { s[i] = 55 }
        XCTAssertNil(TrajectorySimulator.project(series: s, horizonDays: 14, bounds: b0_100))
    }

    func testNilWhenHorizonNonPositive() {
        let s = series(from: 50, to: 70, count: TrajectorySimulator.window)
        XCTAssertNil(TrajectorySimulator.project(series: s, horizonDays: 0, bounds: b0_100))
    }

    func testProjectsWithFullBase() {
        let s = series(from: 50, to: 70, count: TrajectorySimulator.window)
        let p = TrajectorySimulator.project(series: s, horizonDays: 30, bounds: b0_100)
        XCTAssertNotNil(p)
        XCTAssertEqual(p?.baseline.count, 30)
        XCTAssertEqual(p?.basisDays, TrajectorySimulator.window)
    }

    // MARK: - Determinism

    func testDeterministic() {
        let s = series(from: 48, to: 66, count: TrajectorySimulator.window)
        let a = TrajectorySimulator.project(series: s, horizonDays: 21, leverDelta: 5, bounds: b0_100)
        let b = TrajectorySimulator.project(series: s, horizonDays: 21, leverDelta: 5, bounds: b0_100)
        XCTAssertEqual(a, b)
    }

    // MARK: - Bounds (clamp)

    func testEveryPointWithinBounds() {
        // Rising series near the top + a big positive lever → must clamp at 100, never exceed it.
        let s = series(from: 85, to: 99, count: TrajectorySimulator.window)
        guard let p = TrajectorySimulator.project(series: s, horizonDays: 30,
                                                  leverDelta: 12, bounds: b0_100) else {
            return XCTFail("expected a projection")
        }
        for pt in p.baseline + (p.withLever ?? []) {
            XCTAssert(pt.low >= 0 && pt.high <= 100 && pt.estimate >= 0 && pt.estimate <= 100,
                      "point \(pt) escaped bounds")
            XCTAssertLessThanOrEqual(pt.low, pt.estimate)
            XCTAssertGreaterThanOrEqual(pt.high, pt.estimate)
        }
    }

    // MARK: - Band grows with the horizon

    func testBandWidensWithHorizon() {
        // Low-dispersion series centered mid-range with wide bounds → the band never hits a bound,
        // so its growth is observable end to end.
        let s: [Double?] = (0..<TrajectorySimulator.window).map { i in i % 2 == 0 ? 59 : 61 }
        guard let p = TrajectorySimulator.project(series: s, horizonDays: 30, bounds: b0_100) else {
            return XCTFail("expected a projection")
        }
        var prevWidth = -1.0
        var prevLow = Double.greatestFiniteMagnitude
        var prevHigh = -Double.greatestFiniteMagnitude
        for pt in p.baseline {
            let width = pt.high - pt.low
            XCTAssertGreaterThanOrEqual(width + 1e-9, prevWidth, "band should not shrink")
            XCTAssertLessThanOrEqual(pt.low, prevLow + 1e-9, "low edge should fall or hold")
            XCTAssertGreaterThanOrEqual(pt.high, prevHigh - 1e-9, "high edge should rise or hold")
            prevWidth = width; prevLow = pt.low; prevHigh = pt.high
        }
        XCTAssertGreaterThan(p.baseline.last!.high - p.baseline.last!.low,
                             p.baseline.first!.high - p.baseline.first!.low,
                             "the band at the horizon should be wider than on day 1")
    }

    // MARK: - Direction & trend

    func testRisingSeriesTrendsUp() {
        let s = series(from: 50, to: 72, count: TrajectorySimulator.window)
        guard let p = TrajectorySimulator.project(series: s, horizonDays: 30, bounds: b0_100) else {
            return XCTFail("expected a projection")
        }
        XCTAssertEqual(p.direction, .rising)
        XCTAssertGreaterThan(p.baseline.last!.estimate, p.baseline.first!.estimate)
    }

    func testFallingSeriesTrendsDown() {
        let s = series(from: 72, to: 50, count: TrajectorySimulator.window)
        guard let p = TrajectorySimulator.project(series: s, horizonDays: 30, bounds: b0_100) else {
            return XCTFail("expected a projection")
        }
        XCTAssertEqual(p.direction, .falling)
        XCTAssertLessThan(p.baseline.last!.estimate, p.baseline.first!.estimate)
    }

    func testFlatSeriesIsSteadyNearLevel() {
        let s = Array(repeating: 60.0 as Double?, count: TrajectorySimulator.window)
        guard let p = TrajectorySimulator.project(series: s, horizonDays: 30, bounds: b0_100) else {
            return XCTFail("expected a projection")
        }
        XCTAssertEqual(p.direction, .steady)
        XCTAssertEqual(p.level, 60, accuracy: 0.001)
        for pt in p.baseline { XCTAssertEqual(pt.estimate, 60, accuracy: 0.001) }
    }

    func testDampedTrendPlateaus() {
        // A sloped series: consecutive baseline increments must shrink in magnitude (damped trend),
        // never stay constant (which a straight-line extrapolation would).
        let s = series(from: 50, to: 70, count: TrajectorySimulator.window)
        guard let p = TrajectorySimulator.project(series: s, horizonDays: 40, bounds: b0_100) else {
            return XCTFail("expected a projection")
        }
        var prev = p.level
        var increments: [Double] = []
        for pt in p.baseline { increments.append(pt.estimate - prev); prev = pt.estimate }
        for i in 1..<increments.count {
            XCTAssertLessThanOrEqual(abs(increments[i]), abs(increments[i - 1]) + 1e-9,
                                     "increment \(i) grew — trend is not damping")
        }
        XCTAssertLessThan(abs(increments.last!), abs(increments.first!),
                          "far-horizon increment should be smaller than the near one")
    }

    // MARK: - Lever path

    func testPositiveLeverLiftsPathAndGap() {
        let s = series(from: 52, to: 64, count: TrajectorySimulator.window)
        guard let p = TrajectorySimulator.project(series: s, horizonDays: 30,
                                                  leverDelta: 6, bounds: b0_100),
              let lever = p.withLever else {
            return XCTFail("expected a lever path")
        }
        XCTAssertEqual(lever.count, p.baseline.count)
        for (l, base) in zip(lever, p.baseline) {
            XCTAssertGreaterThanOrEqual(l.estimate, base.estimate - 1e-9,
                                        "with-lever should never sit below baseline for a positive delta")
        }
        XCTAssertGreaterThan(p.gap ?? 0, 0, "gap = cost of not changing should be positive")

        // The lever effect ramps in: the with−baseline gap is non-decreasing early and saturates at ~delta.
        var diffs: [Double] = zip(lever, p.baseline).map { $0.estimate - $1.estimate }
        for i in 1..<min(Int(TrajectorySimulator.leverRampDays), diffs.count) {
            XCTAssertGreaterThanOrEqual(diffs[i] + 1e-9, diffs[i - 1], "lever effect should ramp up")
        }
        XCTAssertEqual(diffs.last!, 6, accuracy: 0.001, "fully ramped, the gap equals the delta")
    }

    func testNegativeLeverLowersPath() {
        // Lower-is-better metric (e.g. resting HR): the beneficial lever delta is negative.
        let s = series(from: 60, to: 56, count: TrajectorySimulator.window)
        guard let p = TrajectorySimulator.project(series: s, horizonDays: 30,
                                                  leverDelta: -3, bounds: 40...80),
              let lever = p.withLever else {
            return XCTFail("expected a lever path")
        }
        for (l, base) in zip(lever, p.baseline) {
            XCTAssertLessThanOrEqual(l.estimate, base.estimate + 1e-9,
                                     "with-lever should sit below baseline for a negative delta")
        }
        XCTAssertLessThan(p.gap ?? 0, 0, "gap is negative when the lever lowers the metric")
    }

    func testNoLeverYieldsNilPath() {
        let s = series(from: 50, to: 70, count: TrajectorySimulator.window)
        guard let p = TrajectorySimulator.project(series: s, horizonDays: 30, bounds: b0_100) else {
            return XCTFail("expected a projection")
        }
        XCTAssertNil(p.withLever)
        XCTAssertNil(p.gap)
        XCTAssertFalse(p.baseline.isEmpty)
    }

    // MARK: - Reuse boundary (delegates to RecoveryForecast's OLS, doesn't re-implement)

    func testDirectionAgreesWithReusedSlope() {
        let s = series(from: 50, to: 70, count: TrajectorySimulator.window)
        let points: [(x: Double, y: Double)] = s.enumerated().compactMap { i, v in
            guard let v else { return nil }; return (Double(i), v)
        }
        let slope = RecoveryForecast.olsSlope(points)
        let p = TrajectorySimulator.project(series: s, horizonDays: 10, bounds: b0_100)
        XCTAssertGreaterThan(slope, 0)
        XCTAssertEqual(p?.direction, .rising, "direction must follow the sign of the reused OLS slope")
    }
}
