import XCTest
import Foundation
@testable import StrandAnalytics

final class CorrelationEngineTests: XCTestCase {

    func testPerfectPositiveCorrelation() {
        // y = 2x + 1 → r = 1, slope 2, intercept 1.
        let xy: [(Double, Double)] = [(1, 3), (2, 5), (3, 7), (4, 9), (5, 11)]
        let c = CorrelationEngine.pearson(xy)!
        XCTAssertEqual(c.r, 1.0, accuracy: 1e-9)
        XCTAssertEqual(c.slope, 2.0, accuracy: 1e-9)
        XCTAssertEqual(c.intercept, 1.0, accuracy: 1e-9)
        XCTAssertEqual(c.n, 5)
        XCTAssertEqual(c.pApprox, 0.0, accuracy: 1e-9)   // |r|=1 → p 0
    }

    func testPerfectNegativeCorrelation() {
        // y = -3x + 20 → r = -1, slope -3.
        let xy: [(Double, Double)] = [(1, 17), (2, 14), (3, 11), (4, 8), (5, 5)]
        let c = CorrelationEngine.pearson(xy)!
        XCTAssertEqual(c.r, -1.0, accuracy: 1e-9)
        XCTAssertEqual(c.slope, -3.0, accuracy: 1e-9)
        XCTAssertEqual(c.intercept, 20.0, accuracy: 1e-9)
    }

    func testIndependentSeriesNearZero() {
        // Symmetric (y mirrors across the x midpoint) → exactly r = 0.
        let xy: [(Double, Double)] = [(1, 10), (2, 8), (3, 6), (4, 6), (5, 8), (6, 10)]
        let c = CorrelationEngine.pearson(xy)!
        XCTAssertEqual(c.r, 0.0, accuracy: 1e-9)
        XCTAssertEqual(c.slope, 0.0, accuracy: 1e-9)
        // r=0 → t=0 → p≈1 (A&S erf leaves a ~1e-9 residual at z=0).
        XCTAssertEqual(c.pApprox, 1.0, accuracy: 1e-6)
    }

    func testPearsonGoldenValues() {
        // x=[1..5], y=[2,4,5,4,5] → r=0.7745966692, slope 0.6, intercept 2.2.
        // p uses the EXACT Student-t tail (df=3): t = r·sqrt(3/(1−r²)) ≈ 2.12132 →
        // two-sided p ≈ 0.12402706 (matches SciPy stats.pearsonr to 1e-8). The old
        // normal approximation gave 0.03389 — a 3.66× understatement at n=5.
        let xy: [(Double, Double)] = [(1, 2), (2, 4), (3, 5), (4, 4), (5, 5)]
        let c = CorrelationEngine.pearson(xy)!
        XCTAssertEqual(c.r, 0.7745966692414834, accuracy: 1e-9)
        XCTAssertEqual(c.slope, 0.6, accuracy: 1e-9)
        XCTAssertEqual(c.intercept, 2.2, accuracy: 1e-9)
        XCTAssertEqual(c.pApprox, 0.12402706265755416, accuracy: 1e-8)
    }

    func testStudentTTailMatchesKnownValues() {
        // Cross-checked against SciPy's stats.t.sf(|t|, df)*2 (Student 1908).
        XCTAssertEqual(CorrelationEngine.studentTTwoSided(t: 2.0, df: 10),
                       0.07338803477, accuracy: 1e-8)   // SciPy 0.073388…
        XCTAssertEqual(CorrelationEngine.studentTTwoSided(t: 2.121320343559643, df: 3),
                       0.12402706266, accuracy: 1e-8)   // the n=5 golden case
        // t = 0 → no evidence; df ≤ 0 → no evidence.
        XCTAssertEqual(CorrelationEngine.studentTTwoSided(t: 0, df: 3), 1.0, accuracy: 1e-12)
        XCTAssertEqual(CorrelationEngine.studentTTwoSided(t: 5, df: 0), 1.0, accuracy: 1e-12)
    }

    func testStudentTTailIsHeavierThanNormal() {
        // The whole point of the fix: at small df the t tail (p) is strictly larger
        // than the old normal approximation 2·(1−Φ(|t|)) — i.e. more conservative.
        func normalTwoSided(_ t: Double) -> Double {
            // Φ via the same A&S erf the engine used before the fix.
            func erf(_ x: Double) -> Double {
                let s = x < 0 ? -1.0 : 1.0, ax = abs(x)
                let u = 1.0 / (1.0 + 0.3275911 * ax)
                let y = 1.0 - (((((1.061405429 * u - 1.453152027) * u) + 1.421413741) * u
                                - 0.284496736) * u + 0.254829592) * u * Foundation.exp(-ax * ax)
                return s * y
            }
            return 2.0 * (1.0 - 0.5 * (1.0 + erf(t / 2.0.squareRoot())))
        }
        for df in [3.0, 5.0, 10.0] {
            let t = 2.2
            XCTAssertGreaterThan(CorrelationEngine.studentTTwoSided(t: t, df: df),
                                 normalTwoSided(t),
                                 "t tail must exceed the normal tail at df=\(df)")
        }
    }

    func testPearsonTooFewReturnsNil() {
        XCTAssertNil(CorrelationEngine.pearson([(1, 1), (2, 2)]))   // n=2 < 3
    }

    func testPearsonZeroVarianceReturnsNil() {
        // x constant → undefined correlation.
        XCTAssertNil(CorrelationEngine.pearson([(5, 1), (5, 2), (5, 3)]))
        // y constant → undefined correlation.
        XCTAssertNil(CorrelationEngine.pearson([(1, 7), (2, 7), (3, 7)]))
    }

    func testAlignByDayInnerJoinSorted() {
        let a: [(day: String, value: Double)] = [
            ("2026-01-03", 30), ("2026-01-01", 10), ("2026-01-02", 20),
        ]
        let b: [(day: String, value: Double)] = [
            ("2026-01-02", 200), ("2026-01-01", 100), ("2026-01-09", 900),  // 01-09 only in b
        ]
        let pairs = CorrelationEngine.alignByDay(a, b)
        // Common days 01-01, 01-02 in sorted order.
        XCTAssertEqual(pairs.count, 2)
        XCTAssertEqual(pairs[0].0, 10); XCTAssertEqual(pairs[0].1, 100)
        XCTAssertEqual(pairs[1].0, 20); XCTAssertEqual(pairs[1].1, 200)
    }

    func testLaggedPicksTheRightOffset() {
        // Build y as x shifted FORWARD by one day: y[D+1] = x[D].
        // So lag = +1 (x[D] vs y[D+1]) should be a perfect positive correlation;
        // lag = 0 should be much weaker / undefined here.
        let x: [(day: String, value: Double)] = [
            ("2026-01-01", 1), ("2026-01-02", 2), ("2026-01-03", 3),
            ("2026-01-04", 4), ("2026-01-05", 5),
        ]
        let y: [(day: String, value: Double)] = [
            ("2026-01-02", 1), ("2026-01-03", 2), ("2026-01-04", 3),
            ("2026-01-05", 4), ("2026-01-06", 5),
        ]
        let lag1 = CorrelationEngine.lagged(x: x, y: y, lagDays: 1)!
        XCTAssertEqual(lag1.r, 1.0, accuracy: 1e-9)
        XCTAssertEqual(lag1.n, 5)   // all five x days map onto a y day

        // lag 0: only days present in both are 01-02..01-05 (4 pairs). x there is
        // 2,3,4,5 and y there is 1,2,3,4 → still perfectly linear, r=1 but a
        // DIFFERENT intercept; the discriminator is which lag includes the most
        // data and the strongest relationship. Use lag 2 to show it falls off.
        let lag2 = CorrelationEngine.lagged(x: x, y: y, lagDays: 2)
        // x[D] vs y[D+2]: pairs (01-01→01-03:1,2),(01-02→01-04:2,3),(01-03→01-05:3,4),
        // (01-04→01-06:4,5) → 4 pairs, still linear r=1. To truly distinguish, build
        // a non-monotone y below; here we just assert lag2 has fewer pairs than lag1.
        XCTAssertEqual(lag2!.n, 4)
        XCTAssertLessThan(lag2!.n, lag1.n)
    }

    func testLaggedDiscriminatesOnNonMonotoneSeries() {
        // x is a sawtooth; y equals x shifted forward by exactly 2 days.
        // Then lag=+2 must give r=1 while lag=+1 gives a weaker correlation.
        let xv: [Double] = [1, 5, 2, 6, 3, 7, 4]
        var x: [(day: String, value: Double)] = []
        var y: [(day: String, value: Double)] = []
        let base = 1
        for (i, v) in xv.enumerated() {
            let dDay = String(format: "2026-02-%02d", base + i)
            x.append((dDay, v))
            // y on day+2 carries the same value.
            let yDay = String(format: "2026-02-%02d", base + i + 2)
            y.append((yDay, v))
        }
        let lag2 = CorrelationEngine.lagged(x: x, y: y, lagDays: 2)!
        XCTAssertEqual(lag2.r, 1.0, accuracy: 1e-9)   // exact match at the true lag

        let lag1 = CorrelationEngine.lagged(x: x, y: y, lagDays: 1)!
        XCTAssertLessThan(abs(lag1.r), 0.999)         // weaker at the wrong lag
        XCTAssertGreaterThan(lag2.r, lag1.r)          // best at the true offset
    }

    func testLaggedZeroLagEqualsAlign() {
        let x: [(day: String, value: Double)] = [
            ("2026-03-01", 1), ("2026-03-02", 2), ("2026-03-03", 3), ("2026-03-04", 4),
        ]
        let y: [(day: String, value: Double)] = [
            ("2026-03-01", 2), ("2026-03-02", 1), ("2026-03-03", 4), ("2026-03-04", 3),
        ]
        let lag0 = CorrelationEngine.lagged(x: x, y: y, lagDays: 0)!
        let direct = CorrelationEngine.pearson(CorrelationEngine.alignByDay(x, y))!
        XCTAssertEqual(lag0.r, direct.r, accuracy: 1e-12)
        XCTAssertEqual(lag0.slope, direct.slope, accuracy: 1e-12)
    }

    func testShiftDayCrossesMonthAndYear() {
        XCTAssertEqual(CorrelationEngine.shiftDay("2026-01-31", by: 1), "2026-02-01")
        XCTAssertEqual(CorrelationEngine.shiftDay("2026-03-01", by: -1), "2026-02-28")
        XCTAssertEqual(CorrelationEngine.shiftDay("2025-12-31", by: 1), "2026-01-01")
        XCTAssertEqual(CorrelationEngine.shiftDay("2024-02-28", by: 1), "2024-02-29") // leap year
    }
}
