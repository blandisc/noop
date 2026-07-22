import XCTest
@testable import StrandAnalytics

/// Locks the exact/approx Mann-Whitney U engine (FER-1034). Reference values are hand-derived exact
/// distributions + scipy-known cases (validated in the design harness before porting).
final class MannWhitneyTests: XCTestCase {

    private let tol = 1e-9

    // MARK: Exact null distribution

    func testExactCounts_sumToBinomial() {
        // Total arrangements over the U distribution = C(m+n, m).
        XCTAssertEqual(MannWhitney.exactUCounts(m: 3, n: 3).reduce(0, +), 20, accuracy: tol)
        XCTAssertEqual(MannWhitney.exactUCounts(m: 5, n: 5).reduce(0, +), 252, accuracy: tol)
        XCTAssertEqual(MannWhitney.exactUCounts(m: 4, n: 4).reduce(0, +), 70, accuracy: tol)
    }

    func testExactCounts_3v3_handDerived() {
        // Hand-derived 3v3 distribution of U: 1,1,2,3,3,3,3,2,1,1.
        XCTAssertEqual(MannWhitney.exactUCounts(m: 3, n: 3), [1, 1, 2, 3, 3, 3, 3, 2, 1, 1])
    }

    // MARK: Exact two-sided p — reference cases

    func testP_scipyReference_123vs456() {
        // scipy mannwhitneyu([1,2,3],[4,5,6], alternative='two-sided', method='exact') = 0.1
        let r = MannWhitney.test([1, 2, 3], [4, 5, 6])!
        XCTAssertEqual(r.method, .exact)
        XCTAssertEqual(r.p, 0.1, accuracy: 1e-9)
    }

    func testP_perfectSeparation_minima() {
        XCTAssertEqual(MannWhitney.test([1, 2, 3, 4, 5], [6, 7, 8, 9, 10])!.p, 2.0 / 252.0, accuracy: 1e-9)
        XCTAssertEqual(MannWhitney.test([1, 2, 3, 4], [5, 6, 7, 8])!.p, 2.0 / 70.0, accuracy: 1e-9)
    }

    func testP_slightOverlap_5v5() {
        // U = 2 → 2 * P(U<=2) = 2 * 4/252 = 8/252.
        let r = MannWhitney.test([1, 2, 3, 4, 7], [5, 6, 8, 9, 10])!
        XCTAssertEqual(r.p, 8.0 / 252.0, accuracy: 1e-9)
        XCTAssertLessThan(r.p, 0.05)   // still significant → drives a `.sustained`
    }

    func testP_symmetry() {
        let a: [Double] = [12, 15, 9, 22, 18], b: [Double] = [8, 11, 7, 14]
        XCTAssertEqual(MannWhitney.test(a, b)!.p, MannWhitney.test(b, a)!.p, accuracy: 1e-12)
    }

    // MARK: Ties / approximation

    func testTies_useApproximation_notExact() {
        // A shared value between the groups forces the tie-corrected normal approximation.
        let r = MannWhitney.test([1, 2, 3, 4, 5], [5, 6, 7, 8, 9])!
        XCTAssertEqual(r.method, .approx)
        XCTAssertGreaterThan(r.p, 0)
        XCTAssertLessThanOrEqual(r.p, 1)
    }

    func testDegenerate_allIdentical_pIsOne() {
        // No variance at all → cannot distinguish → p = 1 (never a false positive).
        let r = MannWhitney.test([5, 5, 5, 5, 5], [5, 5, 5, 5, 5])!
        XCTAssertEqual(r.p, 1.0, accuracy: tol)
    }

    // MARK: Effect

    func testHodgesLehmann_knownShift() {
        XCTAssertEqual(MannWhitney.test([1, 2, 3], [4, 5, 6])!.hlShift, -3, accuracy: tol)
        XCTAssertEqual(MannWhitney.test([15, 16, 17, 18], [10, 11, 12, 13])!.hlShift, 5, accuracy: tol)
    }

    func testRankBiserial_signAndBounds() {
        // Group 1 entirely above group 2 → r = +1; entirely below → r = −1.
        XCTAssertEqual(MannWhitney.test([6, 7, 8], [1, 2, 3])!.rankBiserial, 1, accuracy: tol)
        XCTAssertEqual(MannWhitney.test([1, 2, 3], [6, 7, 8])!.rankBiserial, -1, accuracy: tol)
    }

    // MARK: Guards

    func testEmptyGroup_returnsNil() {
        XCTAssertNil(MannWhitney.test([], [1, 2, 3]))
        XCTAssertNil(MannWhitney.test([1, 2, 3], []))
    }
}
