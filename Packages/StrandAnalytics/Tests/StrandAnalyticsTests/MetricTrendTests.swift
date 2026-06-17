import XCTest
@testable import StrandAnalytics

// FER-209 — the sufficiency + strength gate and the r→direction translation behind the
// "Qué la mueve" block. Synthetic `Correlation`s exercise each gate edge precisely; the
// final case runs real pairs through `pearson` → `trend` to prove the end-to-end path.
final class MetricTrendTests: XCTestCase {

    private func corr(r: Double, n: Int, p: Double) -> Correlation {
        Correlation(r: r, n: n, pApprox: p, slope: 0, intercept: 0)
    }

    func testNilCorrelationYieldsNoTrend() {
        XCTAssertNil(CorrelationEngine.trend(nil))
    }

    func testTooFewPairsHidden() {
        // Strong and significant, but only 41 paired days (< 42) → hidden.
        XCTAssertNil(CorrelationEngine.trend(corr(r: 0.8, n: 41, p: 0.0001)))
    }

    func testExactlyMinPairsAllowed() {
        XCTAssertEqual(CorrelationEngine.trend(corr(r: 0.5, n: 42, p: 0.001)), .rises)
    }

    func testWeakEffectHidden() {
        // Significant on large n, but |r| below the 0.20 floor → hidden (trivial effect).
        XCTAssertNil(CorrelationEngine.trend(corr(r: 0.15, n: 300, p: 0.009)))
    }

    func testNonSignificantHidden() {
        // |r| above the floor and enough pairs, but p ≥ 0.05 → hidden (could be chance).
        XCTAssertNil(CorrelationEngine.trend(corr(r: 0.25, n: 45, p: 0.09)))
    }

    func testPositiveClearsToRises() {
        XCTAssertEqual(CorrelationEngine.trend(corr(r: 0.42, n: 60, p: 0.001)), .rises)
    }

    func testNegativeClearsToFalls() {
        XCTAssertEqual(CorrelationEngine.trend(corr(r: -0.42, n: 60, p: 0.001)), .falls)
    }

    func testBoundaryAbsRInclusive() {
        // |r| exactly at the floor is allowed (≥).
        XCTAssertEqual(CorrelationEngine.trend(corr(r: 0.20, n: 60, p: 0.01)), .rises)
        XCTAssertEqual(CorrelationEngine.trend(corr(r: -0.20, n: 60, p: 0.01)), .falls)
    }

    func testBoundaryPExclusive() {
        // p exactly at maxP is rejected (strict <).
        XCTAssertNil(CorrelationEngine.trend(corr(r: 0.5, n: 60, p: 0.05)))
    }

    func testCustomStricterGate() {
        let strict = CorrelationEngine.TrendGate(minPairs: 56, minAbsR: 0.30, maxP: 0.01)
        XCTAssertNil(CorrelationEngine.trend(corr(r: 0.42, n: 50, p: 0.001), gate: strict))   // n < 56
        XCTAssertNil(CorrelationEngine.trend(corr(r: 0.25, n: 60, p: 0.001), gate: strict))   // |r| < 0.30
        XCTAssertEqual(CorrelationEngine.trend(corr(r: 0.42, n: 60, p: 0.001), gate: strict), .rises)
    }

    func testEndToEndFromPairsRises() {
        // 42 days where the second series climbs with the first plus jitter → a strong,
        // significant positive correlation that clears the default gate as .rises.
        var xy: [(Double, Double)] = []
        for i in 0..<42 {
            xy.append((Double(i), Double(i) * 0.8 + (i % 3 == 0 ? 4 : -3)))
        }
        XCTAssertEqual(CorrelationEngine.trend(CorrelationEngine.pearson(xy)), .rises)
    }
}
