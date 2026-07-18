import XCTest
import BiometricStreams
@testable import StrandAnalytics

/// FER-972 (P-02 · M-02): the O(n) window-bucketing rewrites must be beat-for-beat equivalent to
/// the old per-window re-filtering. Each test recomputes the OLD algorithm inline (naive filter
/// per window, verbatim) and pins the shipped implementation against it on a synthetic,
/// irregular night — odd span (clipped last window), beats outside the span, gaps, and (for the
/// HRV port) wake spans so the skip path is exercised.
final class WindowBucketingEquivalenceTests: XCTestCase {

    /// Deterministic LCG so the fixture is irregular but reproducible.
    private struct Rand {
        var s: UInt64
        mutating func next(_ m: Int) -> Int {
            s = s &* 6364136223846793005 &+ 1442695040888963407
            return Int((s >> 33) % UInt64(m))
        }
    }

    func testAssembleMatchesNaivePerWindowFiltering() {
        var r = Rand(s: 7)
        let from = 1_700_000_123
        let to = from + 7 * 3600 + 421   // odd span → the last window is clipped at `to`
        var rr: [RRInterval] = []
        var ts = from - 50               // beats before/after the span must be ignored
        while ts < to + 50 {
            rr.append(RRInterval(ts: ts, rrMs: 700 + r.next(300)))
            ts += 1 + r.next(4)          // irregular spacing, with dropout-sized gaps
        }
        var gravity: [GravitySample] = []
        ts = from - 50
        while ts < to + 50 {
            gravity.append(GravitySample(ts: ts, x: Double(r.next(100)) / 500, y: 0, z: 1))
            ts += 1 + r.next(3)
        }

        let got = NightRhythmAssembler.assemble(rr: rr, gravity: gravity, from: from, to: to)

        // The OLD algorithm, verbatim (filter the whole night per window).
        var expected: [RhythmScreener.WindowResult] = []
        var w0 = from
        while w0 < to {
            let w1 = min(w0 + NightRhythmAssembler.windowSeconds, to)
            let rrWindow = rr.filter { $0.ts >= w0 && $0.ts < w1 }
            if !rrWindow.isEmpty {
                let gravWindow = gravity.filter { $0.ts >= w0 && $0.ts < w1 }
                let input = RhythmScreener.WindowInput(rr: rrWindow,
                                                       motionStill: NightRhythmAssembler.isStill(gravWindow))
                expected.append(RhythmScreener.screenWindow(input))
            }
            w0 = w1
        }

        XCTAssertEqual(got.windows, expected)
        XCTAssertEqual(got.summary, RhythmScreener.summarizeNight(expected))
    }

    func testSessionAvgHRVMatchesNaivePerWindowFiltering() {
        var r = Rand(s: 21)
        let start = 1_700_100_000
        let end = start + 6 * 3600 + 137
        var rr: [RRInterval] = []
        var ts = start - 30
        while ts < end + 30 {
            rr.append(RRInterval(ts: ts, rrMs: 600 + r.next(500)))
            ts += 1 + r.next(3)
        }
        // A hypnogram with wake spans at both ends so the skip path is exercised too.
        let stages = [StageSegment(start: start, end: start + 1_800, stage: "wake"),
                      StageSegment(start: start + 1_800, end: end - 3_600, stage: "core"),
                      StageSegment(start: end - 3_600, end: end - 1_800, stage: "wake"),
                      StageSegment(start: end - 1_800, end: end, stage: "rem")]

        // The OLD algorithm, verbatim.
        func naive(_ stages: [StageSegment]) -> Double? {
            let seg = rr.filter { $0.ts >= start && $0.ts <= end }
            guard !seg.isEmpty else { return nil }
            let windowS = 5 * 60
            var vals: [Double] = []
            var t = start
            while t < end {
                if !stages.isEmpty, SleepStager.stageAt(t + windowS / 2, stages) == "wake" {
                    t += windowS
                    continue
                }
                let bucket = seg.filter { $0.ts >= t && $0.ts < t + windowS }.map { Double($0.rrMs) }
                let filtered = HRVAnalyzer.cleanRR(bucket)
                if filtered.count >= 2, let v = HRVAnalyzer.rmssdRaw(filtered) { vals.append(v) }
                t += windowS
            }
            guard !vals.isEmpty else { return nil }
            return HRVAnalyzer.median(vals)
        }

        XCTAssertEqual(SleepStager.sessionAvgHRV(start: start, end: end, rr: rr, stages: stages),
                       naive(stages))
        XCTAssertEqual(SleepStager.sessionAvgHRV(start: start, end: end, rr: rr), naive([]))
        // ts == end edge: a beat exactly at `end` belongs to the last clipped window iff the span
        // isn't an exact multiple of 5 min — pinned by an exact-multiple variant.
        let exactEnd = start + 6 * 3600
        func naiveExact() -> Double? {
            let seg = rr.filter { $0.ts >= start && $0.ts <= exactEnd }
            guard !seg.isEmpty else { return nil }
            let windowS = 5 * 60
            var vals: [Double] = []
            var t = start
            while t < exactEnd {
                let bucket = seg.filter { $0.ts >= t && $0.ts < t + windowS }.map { Double($0.rrMs) }
                let filtered = HRVAnalyzer.cleanRR(bucket)
                if filtered.count >= 2, let v = HRVAnalyzer.rmssdRaw(filtered) { vals.append(v) }
                t += windowS
            }
            guard !vals.isEmpty else { return nil }
            return HRVAnalyzer.median(vals)
        }
        XCTAssertEqual(SleepStager.sessionAvgHRV(start: start, end: exactEnd, rr: rr), naiveExact())
    }
}
