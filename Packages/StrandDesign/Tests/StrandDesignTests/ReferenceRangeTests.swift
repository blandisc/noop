import XCTest
@testable import StrandDesign

/// FER-155 — `ReferenceRange` is the pure p25–p75 calculation behind the Sparkline's
/// reference band. The percentile method is asserted against hand-computed values, and
/// the degenerate cases (empty / single / constant / non-finite / unsorted) are pinned
/// so the band logic never crashes or inverts.
final class ReferenceRangeTests: XCTestCase {

    func testPercentileLinearInterpolation() {
        // [10,20,30,40]: p25 → position 0.25·3 = 0.75 → 10 + 0.75·(20−10) = 17.5
        XCTAssertEqual(ReferenceRange.percentile([10, 20, 30, 40], 25), 17.5, accuracy: 1e-9)
        // p75 → position 0.75·3 = 2.25 → 30 + 0.25·(40−30) = 32.5
        XCTAssertEqual(ReferenceRange.percentile([10, 20, 30, 40], 75), 32.5, accuracy: 1e-9)
    }

    func testInterquartileNormalSeries() {
        // [1...9]: p25 → 0.25·8 = 2 → sorted[2] = 3; p75 → 0.75·8 = 6 → sorted[6] = 7
        let r = ReferenceRange.interquartile([1, 2, 3, 4, 5, 6, 7, 8, 9])!
        XCTAssertEqual(r.lowerBound, 3, accuracy: 1e-9)
        XCTAssertEqual(r.upperBound, 7, accuracy: 1e-9)
    }

    func testEmptyReturnsNil() {
        XCTAssertNil(ReferenceRange.interquartile([]))
    }

    func testSingleValue() {
        let r = ReferenceRange.interquartile([42])!
        XCTAssertEqual(r.lowerBound, 42, accuracy: 1e-9)
        XCTAssertEqual(r.upperBound, 42, accuracy: 1e-9)
    }

    func testConstantSeriesIsZeroWidthNotInverted() {
        let r = ReferenceRange.interquartile([7, 7, 7, 7])!
        XCTAssertEqual(r.lowerBound, 7, accuracy: 1e-9)
        XCTAssertEqual(r.upperBound, 7, accuracy: 1e-9)
        XCTAssertLessThanOrEqual(r.lowerBound, r.upperBound)
    }

    func testDropsNonFiniteValues() {
        let r = ReferenceRange.interquartile([1, 2, .nan, 3, .infinity, 4, -.infinity])
        XCTAssertNotNil(r)
        XCTAssertTrue(r!.lowerBound.isFinite && r!.upperBound.isFinite)
    }

    func testUnsortedInputIsHandled() {
        // interquartile sorts internally → same result regardless of input order
        let a = ReferenceRange.interquartile([9, 1, 5, 3, 7])!
        let b = ReferenceRange.interquartile([1, 3, 5, 7, 9])!
        XCTAssertEqual(a.lowerBound, b.lowerBound, accuracy: 1e-9)
        XCTAssertEqual(a.upperBound, b.upperBound, accuracy: 1e-9)
    }

    func testAllNonFiniteReturnsNil() {
        XCTAssertNil(ReferenceRange.interquartile([.nan, .infinity, -.infinity]))
    }
}
