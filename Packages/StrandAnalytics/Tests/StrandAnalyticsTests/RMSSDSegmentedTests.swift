import XCTest
@testable import StrandAnalytics

final class RMSSDSegmentedTests: XCTestCase {

    private func nn(_ pairs: [(Int, Double)]) -> [TimedNN] {
        pairs.map { TimedNN(ts: Double($0.0), nnMs: $0.1) }
    }

    func testContiguousFourBeatsGolden() {
        // √(2100/3) = √700 ≈ 26.457513110645905
        let r = HRVAnalyzer.rmssdSegmented(nn([(0, 800), (1, 820), (2, 810), (3, 850)]))
        XCTAssertEqual(r.nPairs, 3)
        XCTAssertEqual(r.rmssd!, 26.457513110645905, accuracy: 1e-12)
    }

    func testGapExcludesDistantPair() {
        // gap 118s excludes the last pair → √(500/2) = √250 ≈ 15.811388300841896
        let r = HRVAnalyzer.rmssdSegmented(nn([(0, 800), (1, 820), (2, 810), (120, 850)]))
        XCTAssertEqual(r.nPairs, 2)
        XCTAssertEqual(r.rmssd!, 15.811388300841896, accuracy: 1e-12)
    }

    func testGapExactly3ExcludesPair() {
        // 3 < 3 is false → no valid pairs
        let r = HRVAnalyzer.rmssdSegmented(nn([(0, 800), (3, 820)]))
        XCTAssertNil(r.rmssd)
        XCTAssertEqual(r.nPairs, 0)
    }

    func testGap1Counts() {
        let r = HRVAnalyzer.rmssdSegmented(nn([(0, 800), (1, 820)]))
        XCTAssertEqual(r.nPairs, 1)
        XCTAssertEqual(r.rmssd!, 20.0, accuracy: 1e-12)
    }

    func testOutOfRangeInvalidatesTouchingPairsNoBridge() {
        // 2500 is out of range; pairs touching it are excluded, not bridged
        let r1 = HRVAnalyzer.rmssdSegmented(nn([(0, 800), (1, 2500), (2, 820)]))
        XCTAssertEqual(r1.nPairs, 0)
        XCTAssertNil(r1.rmssd)

        // only 800→820 is valid
        let r2 = HRVAnalyzer.rmssdSegmented(nn([(0, 250), (1, 800), (2, 820), (3, 2500)]))
        XCTAssertEqual(r2.nPairs, 1)
        XCTAssertEqual(r2.rmssd!, 20.0, accuracy: 1e-12)
    }

    func testFewerThanOneValidPairReturnsNil() {
        let empty = HRVAnalyzer.rmssdSegmented([])
        XCTAssertNil(empty.rmssd)
        XCTAssertEqual(empty.nPairs, 0)

        let single = HRVAnalyzer.rmssdSegmented(nn([(0, 800)]))
        XCTAssertNil(single.rmssd)
        XCTAssertEqual(single.nPairs, 0)
    }

    func testUnsortedInputDeterministic() {
        let sorted = HRVAnalyzer.rmssdSegmented(nn([(0, 800), (1, 820), (2, 810), (3, 850)]))
        let unsorted = HRVAnalyzer.rmssdSegmented(nn([(2, 810), (0, 800), (3, 850), (1, 820)]))
        XCTAssertEqual(sorted.nPairs, unsorted.nPairs)
        XCTAssertEqual(sorted.rmssd!, unsorted.rmssd!, accuracy: 1e-12)
    }
}
