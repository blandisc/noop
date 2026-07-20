import XCTest
@testable import StrandAnalytics

final class NocturnalHRVTests: XCTestCase {

    /// N contiguous intervals (ts = 0,1,2,…), all in range, gap 1s.
    private func contiguous(_ n: Int, nnMs: Double = 800) -> [TimedNN] {
        (0..<n).map { TimedNN(ts: Double($0), nnMs: nnMs) }
    }

    /// Build intervals with controlled nClean and nPairs.
    /// `pairGroups` groups of 2 contiguous intervals give that many pairs;
    /// remaining singles add clean beats with 0 pairs. Groups separated by gap ≥ 3s.
    private func sparse(clean: Int, pairs: Int, nnMs: Double = 800) -> [TimedNN] {
        // pairs groups of 2 + (clean - 2*pairs) singletons
        precondition(clean >= pairs * 2)
        var result: [TimedNN] = []
        var ts = 0
        for _ in 0..<pairs {
            result.append(TimedNN(ts: Double(ts), nnMs: nnMs))
            result.append(TimedNN(ts: Double(ts + 1), nnMs: nnMs + 20)) // nonzero Δ so rmssd > 0
            ts += 10 // gap ≥ 3 between groups
        }
        let singles = clean - pairs * 2
        for _ in 0..<singles {
            result.append(TimedNN(ts: Double(ts), nnMs: nnMs))
            ts += 10
        }
        return result
    }

    func test59CleanNotDense() {
        let intervals = contiguous(59, nnMs: 800)
        // vary slightly so rmssd > 0 if it were dense
        let varied = intervals.enumerated().map { i, t in
            TimedNN(ts: t.ts, nnMs: 800 + Double(i % 3) * 10)
        }
        let r = NocturnalHRV.night(intervals: varied, windowStart: nil, windowEnd: nil)
        XCTAssertEqual(r.nClean, 59)
        XCTAssertFalse(r.dense)
        XCTAssertNil(r.rmssdMs)
    }

    func test60Clean29PairsNotDense() {
        // 29 groups of 2 + 2 singletons = 60 clean, 29 pairs
        let intervals = sparse(clean: 60, pairs: 29)
        let r = NocturnalHRV.night(intervals: intervals, windowStart: nil, windowEnd: nil)
        XCTAssertEqual(r.nClean, 60)
        XCTAssertEqual(r.nPairs, 29)
        XCTAssertFalse(r.dense)
        XCTAssertNil(r.rmssdMs)
    }

    func test60Clean30PairsDense() {
        let intervals = sparse(clean: 60, pairs: 30)
        let r = NocturnalHRV.night(intervals: intervals, windowStart: nil, windowEnd: nil)
        XCTAssertEqual(r.nClean, 60)
        XCTAssertEqual(r.nPairs, 30)
        XCTAssertTrue(r.dense)
        XCTAssertNotNil(r.rmssdMs)
        XCTAssertGreaterThan(r.rmssdMs!, 0)
    }

    func testIdenticalNNGivesZeroRMSSDNotDense() {
        // ≥60 clean, ≥30 pairs, but all nnMs identical → rmssd == 0 → not dense
        let intervals = contiguous(61, nnMs: 800) // 60 pairs of identical diffs = 0
        let r = NocturnalHRV.night(intervals: intervals, windowStart: nil, windowEnd: nil)
        XCTAssertEqual(r.nClean, 61)
        XCTAssertGreaterThanOrEqual(r.nPairs, 30)
        XCTAssertNil(r.rmssdMs)
        XCTAssertFalse(r.dense)
    }

    func testWindowExcludesOutsideIntervals() {
        // 70 contiguous in-range, but window only keeps 50 of them
        var intervals = contiguous(70, nnMs: 800)
        intervals = intervals.enumerated().map { i, t in
            TimedNN(ts: t.ts, nnMs: 800 + Double(i % 2) * 20)
        }
        let r = NocturnalHRV.night(intervals: intervals, windowStart: 10, windowEnd: 59)
        // ts 10...59 inclusive = 50 intervals
        XCTAssertEqual(r.nClean, 50)
        XCTAssertFalse(r.dense)
        XCTAssertNil(r.rmssdMs)
    }

    func testNCleanCountsOnlyInRange() {
        var intervals: [TimedNN] = []
        // 50 in-range + 20 out-of-range interleaved
        for i in 0..<70 {
            let ms = i < 50 ? 800.0 : 2500.0
            intervals.append(TimedNN(ts: Double(i), nnMs: ms))
        }
        // make first 50 vary for nonzero rmssd potential
        intervals = intervals.enumerated().map { i, t in
            if t.nnMs <= 2000 {
                return TimedNN(ts: t.ts, nnMs: 800 + Double(i % 3) * 10)
            }
            return t
        }
        let r = NocturnalHRV.night(intervals: intervals, windowStart: nil, windowEnd: nil)
        XCTAssertEqual(r.nClean, 50)
        // out-of-range don't bump nClean
        XCTAssertLessThan(r.nClean, 70)
    }
}
