import XCTest
@testable import StrandAnalytics
import BiometricStreams

final class HRVAnalyzerTests: XCTestCase {

    func testRMSSDRawHandComputed() {
        // NN = [800, 810, 800, 810] → diffs 10, -10, 10 → sqrt(300/3) = 10.
        let nn = [800.0, 810, 800, 810]
        XCTAssertEqual(HRVAnalyzer.rmssdRaw(nn)!, 10.0, accuracy: 1e-9)
    }

    func testSDNNRawSampleStdDev() {
        // Sample SD (ddof=1) of [800, 810, 800, 810] = 5.7735026919...
        let nn = [800.0, 810, 800, 810]
        XCTAssertEqual(HRVAnalyzer.sdnnRaw(nn)!, 5.773502691896258, accuracy: 1e-9)
    }

    func testRMSSDRawTooFewReturnsNil() {
        XCTAssertNil(HRVAnalyzer.rmssdRaw([800]))
        XCTAssertNil(HRVAnalyzer.sdnnRaw([]))
    }

    // MARK: - Degenerate stat guards (FER-36)

    /// Sample SD (ddof=1) of a single value has no n−1 denominator → nil, never
    /// a divide-by-zero. Symmetric to the rmssd case above.
    func testSDNNRawSingleValueReturnsNil() {
        XCTAssertNil(HRVAnalyzer.sdnnRaw([800]))
        XCTAssertNil(HRVAnalyzer.rmssdRaw([]))
    }

    /// pNN50 divides by (clean.count − 1). The minBeats(20) gate keeps that ≥ 19,
    /// so on a valid series pNN50 is a finite percentage in [0, 100].
    func testPnn50FiniteOnValidSeries() {
        let nn = Array(repeating: 800.0, count: 22)
        let result = HRVAnalyzer.analyze(rawRR: nn)
        XCTAssertNotNil(result.pnn50)
        XCTAssertTrue(result.pnn50!.isFinite)
        XCTAssertEqual(result.pnn50!, 0.0, accuracy: 1e-9)  // constant series → no >50ms jumps
    }

    func testRangeFilterDropsOutOfRange() {
        let rr = [250.0, 300, 800, 2000, 2100, 1500]
        // 250 (<300) and 2100 (>2000) dropped; 300 and 2000 kept (inclusive).
        XCTAssertEqual(HRVAnalyzer.rangeFilter(rr), [300, 800, 2000, 1500])
    }

    func testAnalyzeRequiresMinBeats() {
        // 19 clean intervals → below minBeats(20) → empty result.
        let rr = Array(repeating: 800.0, count: 19)
        let result = HRVAnalyzer.analyze(rawRR: rr)
        XCTAssertNil(result.rmssd)
        XCTAssertNil(result.sdnn)
        XCTAssertEqual(result.nInput, 19)
        XCTAssertEqual(result.nClean, 0)
    }

    func testAnalyzeGoldenSeries() {
        // 22 intervals oscillating near 800 ms; matches Python golden values.
        let nn: [Double] = [800, 810, 805, 815, 800, 820, 810, 800, 815, 805, 810,
                            800, 820, 815, 805, 810, 800, 815, 810, 805, 800, 820]
        let result = HRVAnalyzer.analyze(rawRR: nn)
        XCTAssertEqual(result.nClean, 22)  // none ectopic (all near local median)
        XCTAssertEqual(result.rmssd!, 11.649647450214351, accuracy: 1e-9)
        XCTAssertEqual(result.sdnn!, 7.101612523427368, accuracy: 1e-9)
        XCTAssertEqual(result.meanNN!, nn.reduce(0,+)/22, accuracy: 1e-9)
    }

    func testEctopicRejectionDropsSpike() {
        // A steady 800 ms series with one impossible 1400 ms beat in the middle.
        // The spike deviates ~75% from local median → rejected. Remaining beats
        // are all 800 → RMSSD 0.
        var nn = Array(repeating: 800.0, count: 30)
        nn[15] = 1400
        let clean = HRVAnalyzer.cleanRR(nn)
        XCTAssertEqual(clean.count, 29)               // exactly one beat dropped
        XCTAssertFalse(clean.contains(1400))
        XCTAssertEqual(HRVAnalyzer.rmssdRaw(clean)!, 0.0, accuracy: 1e-9)
    }

    func testEctopicKeepsModerateVariation() {
        // ±15% variation is within the 20% Malik threshold → all kept.
        let nn = [800.0, 900, 800, 900, 800, 900, 800, 900]  // 900/800 = +12.5%
        let clean = HRVAnalyzer.rejectEctopic(nn)
        XCTAssertEqual(clean.count, nn.count)
    }

    func testAnalyzeWindowFiltersByTimestamp() {
        // RR rows across two windows; only [1000,1010] should be analyzed.
        var rr: [RRInterval] = []
        for t in 1000...1030 { rr.append(RRInterval(ts: t, rrMs: 800)) }   // 31 in window A
        for t in 5000...5030 { rr.append(RRInterval(ts: t, rrMs: 600)) }   // window B
        let result = HRVAnalyzer.analyze(rr, windowStart: 1000, windowEnd: 1030)
        XCTAssertEqual(result.nInput, 31)
        XCTAssertEqual(result.nClean, 31)
        XCTAssertEqual(result.rmssd!, 0.0, accuracy: 1e-9)  // all 800 → no successive diffs
    }
}
