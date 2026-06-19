import XCTest
@testable import StrandAnalytics

final class MultipleComparisonsTests: XCTestCase {

    func testEmptyAndSingle() {
        XCTAssertEqual(MultipleComparisons.benjaminiHochberg([]), [])
        // A single test gets no penalty (m = 1): q == p (clamped).
        XCTAssertEqual(MultipleComparisons.benjaminiHochberg([0.03])[0], 0.03, accuracy: 1e-12)
        XCTAssertEqual(MultipleComparisons.benjaminiHochberg([1.7])[0], 1.0, accuracy: 1e-12)
    }

    /// A uniform p ladder p = k·α/m collapses to a flat q = α (the BH boundary case).
    func testUniformLadderCollapsesToAlpha() {
        let q = MultipleComparisons.benjaminiHochberg([0.01, 0.02, 0.03, 0.04, 0.05])
        for v in q { XCTAssertEqual(v, 0.05, accuracy: 1e-9) }
    }

    /// One tiny p among large ones survives; the rest stay near 1.
    func testOneStrongHit() {
        let q = MultipleComparisons.benjaminiHochberg([0.001, 0.5, 0.5, 0.5, 0.5])
        XCTAssertEqual(q[0], 0.005, accuracy: 1e-9)   // 0.001 · 5 / 1
        // The four 0.5 nulls collapse to q = 0.5 (rank-5 raw = 0.5·5/5, carried up by the running min).
        for v in q.dropFirst() { XCTAssertEqual(v, 0.5, accuracy: 1e-9) }
    }

    /// q is order-preserving in the raw p ordering and always ≥ the raw p.
    func testMonotonicAndInflating() {
        let p = [0.04, 0.001, 0.20, 0.012, 0.30, 0.008]
        let q = MultipleComparisons.benjaminiHochberg(p)
        // Each q ≥ its raw p (correction only ever inflates).
        for (pv, qv) in zip(p, q) { XCTAssertGreaterThanOrEqual(qv + 1e-12, pv) }
        // Order preserved: sorting by p and by q gives the same index order.
        let byP = (0..<p.count).sorted { p[$0] < p[$1] }
        let byQ = (0..<q.count).sorted { q[$0] < q[$1] }
        XCTAssertEqual(byP, byQ)
        for v in q { XCTAssertLessThanOrEqual(v, 1.0) }
    }
}
