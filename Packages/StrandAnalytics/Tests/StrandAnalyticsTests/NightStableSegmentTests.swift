import XCTest
@testable import StrandAnalytics

/// FER-1048 · fase 1b — the signal-detected stable night segment. Numeric CAs from
/// `docs/_plan-veredicto-v4.md` → PARTE A → FASE 1b. Pure/deterministic; no Date(), no I/O.
final class NightStableSegmentTests: XCTestCase {

    private typealias S = NightStableSegment.Sample

    /// Deterministic, IRREGULAR "agitated" rest around 70 bpm (±`amp`). Irregular on purpose: a
    /// periodic block wave would create flat low sub-stretches that are themselves stable segments,
    /// and a fast alternation would smooth to a flat median line — both defeat the fixture. This
    /// integer hash spreads values across [70−amp, 70+amp] with no long flat run and no clean period,
    /// so after smoothing it still crosses the median with real local steps → never quiet for 20 min.
    private func restBpm(_ i: Int, amp: Double = 8) -> Double {
        let h = (i &* 1103515245 &+ 12345) >> 8
        let unit = Double(((h % 1000) + 1000) % 1000) / 999.0   // deterministic 0…1
        return 70 + (unit * 2 - 1) * amp
    }

    /// 8-h night at 60-s sampling with a clearly stable low stretch in `stableRange` (index range),
    /// at ~`stableBpm` ± tiny wobble, and agitated rest elsewhere.
    private func night(stableRange: Range<Int>, stableBpm: Double = 50,
                       total: Int = 480, restAmp: Double = 8) -> [S] {
        (0..<total).map { i in
            let bpm: Double
            if stableRange.contains(i) {
                bpm = stableBpm + Double(i % 3 - 1)   // 49, 50, 51 cycling — locally flat
            } else {
                bpm = restBpm(i, amp: restAmp)
            }
            return S(ts: i * 60, bpm: bpm)
        }
    }

    // MARK: - CA1: a clear 2h+ stable stretch is found, inside the stable region

    func testCA1_findsStableStretchInsideTheQuietRegion() {
        // Stable stretch indices [180, 360): 3 h at ~50 bpm; ts 10_800 … 21_540.
        let s = night(stableRange: 180..<360)
        guard let r = NightStableSegment.find(s) else {
            return XCTFail("expected a stable segment, got nil")
        }
        let segStartTs = 180 * 60, segEndTs = 359 * 60
        // Centered smoothing bleeds the detected edges by at most one window into the rest; a full
        // window (300 s) on a 3-h segment is <3% — comfortably "contained in the stable stretch".
        let tol = NightStableSegment.smoothWindowSec
        XCTAssertGreaterThanOrEqual(r.start, segStartTs - tol)
        XCTAssertLessThanOrEqual(r.end, segEndTs + tol)
        // It covers essentially the whole 3-h stretch, well past the 20-min floor.
        XCTAssertGreaterThanOrEqual(r.end - r.start, 2 * 3600)
        // It found the LOW region, not the ~70 rest: the raw HR inside the range is ~50.
        let inside = s.filter { $0.ts >= r.start && $0.ts <= r.end }.map(\.bpm).sorted()
        XCTAssertLessThan(inside[inside.count / 2], 55, "median inside the segment should be ~50")
    }

    // MARK: - CA2: uniformly agitated night → nil (no 20-min stable stretch)

    func testCA2_uniformlyAgitatedReturnsNil() {
        // Whole night agitated at 70±15, nothing stable for 20 min.
        let s = (0..<480).map { i in S(ts: i * 60, bpm: restBpm(i, amp: 15)) }
        XCTAssertNil(NightStableSegment.find(s))
    }

    // MARK: - CA3 / CA4: independent of any hypnogram, pure & deterministic

    func testCA3_independentOfStageLabelsAndDeterministic() {
        // `find` takes ONLY (ts, bpm) — there is, by construction, no `stagesJSON`/stage parameter,
        // so the result cannot depend on Apple's hypnogram. Two contradictory hypnograms would be
        // the same call. Deterministic: same input → same output.
        let s = night(stableRange: 180..<360)
        XCTAssertEqual(NightStableSegment.find(s)?.start, NightStableSegment.find(s)?.start)
        XCTAssertEqual(NightStableSegment.find(s)?.end, NightStableSegment.find(s)?.end)
    }

    // MARK: - CA (robustness): a data hole is not bridged into a fake segment

    func testDataHoleBreaksTheRun() {
        // Two 15-min low stretches with a 30-min GAP (no samples) between them: neither alone
        // clears 20 min, and the gap must not be bridged into one 60-min "stable" segment.
        var s: [S] = []
        for i in 0..<15 { s.append(S(ts: i * 60, bpm: 50)) }            // 0…840  (14 min span)
        for i in 0..<15 { s.append(S(ts: 2400 + i * 60, bpm: 50)) }     // 2400…3240 after a 26-min hole
        XCTAssertNil(NightStableSegment.find(s), "a gap larger than maxGapSec must break the run")
    }

    // MARK: - CA5: NocturnalRestingHR paridad when find == nil

    func testCA5_nocturnalRestingHRParityWhenNoSegment() {
        // The A2 fixture from NocturnalRestingHRTests: 10 deep (48…57) + 15 non-deep (70…84), all
        // within a <2-min ts span so `find` returns nil → estimate must equal the exact pre-FER-1048
        // whole-window quantile (51.0), byte-for-byte.
        var samples: [NocturnalRestingHR.Sample] = []
        for i in 0..<10 { samples.append(.init(ts: i, bpm: 48 + Double(i), deep: true)) }
        for i in 0..<15 { samples.append(.init(ts: 100 + i, bpm: 70 + Double(i), deep: false)) }
        // find is nil on this short span (no 20-min stretch is possible).
        let seg = samples.map { NightStableSegment.Sample(ts: $0.ts, bpm: $0.bpm) }
        XCTAssertNil(NightStableSegment.find(seg))
        let est = NocturnalRestingHR.estimate(samples)
        XCTAssertNotNil(est)
        XCTAssertEqual(est!, 51.0, accuracy: 1e-9)
    }

    // MARK: - The new branch actually fires: estimate prefers the stable segment

    func testEstimatePrefersStableSegmentWhenPresent() {
        // 8-h night: a dense 40-min stable stretch at ~48 bpm (>= minSamples) + agitated rest ~80.
        // The stable-segment estimate (~48) must differ from the whole-window quantile (higher).
        let stable = 180..<220   // 40 samples at 60 s = 40 min ≥ minSamples (20)
        let s = (0..<480).map { i -> NocturnalRestingHR.Sample in
            if stable.contains(i) {
                return .init(ts: i * 60, bpm: 48 + Double(i % 3 - 1), deep: false)
            }
            return .init(ts: i * 60, bpm: 80 + Double(i % 20 < 10 ? 6 : -6), deep: false)
        }
        let seg = s.map { NightStableSegment.Sample(ts: $0.ts, bpm: $0.bpm) }
        XCTAssertNotNil(NightStableSegment.find(seg), "a clear 40-min stretch should be found")
        let est = NocturnalRestingHR.estimate(s)!
        // Estimate rides the stable stretch (~48), not the ~80 rest, and clearly below the
        // whole-window low quantile.
        XCTAssertLessThan(est, 55)
        let wholeQuantile = wholeWindowQuantile(s.map(\.bpm))
        XCTAssertLessThan(est, wholeQuantile, "segment estimate must be below the whole-window low quantile")
    }

    /// Mirror of NocturnalRestingHR's R type-7 p12.5 over the whole (artifact-filtered) window, for
    /// the difference assertion above.
    private func wholeWindowQuantile(_ raw: [Double]) -> Double {
        let v = raw.filter { $0 >= 30 && $0 <= 120 }.sorted()
        let q = 0.125, n = v.count
        let index = q * Double(n - 1)
        let lo = Int(index.rounded(.down)), hi = Int(index.rounded(.up))
        if lo == hi { return v[lo] }
        return v[lo] + (index - Double(lo)) * (v[hi] - v[lo])
    }
}
