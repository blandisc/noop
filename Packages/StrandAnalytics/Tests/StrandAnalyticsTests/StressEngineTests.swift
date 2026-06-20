import XCTest
@testable import StrandAnalytics
import WhoopProtocol

final class StressEngineTests: XCTestCase {

    // MARK: - Helpers

    /// One bucket's worth of RR beats: an alternating mean/(mean+delta) pattern so the successive
    /// differences are all ±delta → RMSSD == delta (exact). `meanNN` sets the HR (60000/mean) for the
    /// activity gate. All beats land in a single epoch bucket of `StressEngine.defaultWindowSeconds`.
    private func bucket(index: Int, count: Int = 40, meanNN: Int, delta: Int) -> [RRInterval] {
        let base = index * StressEngine.defaultWindowSeconds
        return (0..<count).map { i in
            RRInterval(ts: base + i, rrMs: meanNN + (i % 2 == 0 ? 0 : delta))
        }
    }

    /// A calm, non-active waking reference: calm RMSSD 60 ms, activated 15 ms.
    private let ref = StressEngine.WakingReference(rmssdCalm: 60, rmssdActivated: 15, nWindows: 40)

    // MARK: - Mapping (RMSSD → 0–3, clamped)

    func testStressMappingAnchorsAndClamp() {
        // At the calm anchor → 0; at the activated anchor → 3.
        XCTAssertEqual(StressEngine.stress(forRMSSD: 60, reference: ref), 0, accuracy: 1e-9)
        XCTAssertEqual(StressEngine.stress(forRMSSD: 15, reference: ref), 3, accuracy: 1e-9)
        // Beyond the anchors → clamped, never outside [0, 3].
        XCTAssertEqual(StressEngine.stress(forRMSSD: 200, reference: ref), 0, accuracy: 1e-9) // calmer than calm
        XCTAssertEqual(StressEngine.stress(forRMSSD: 1, reference: ref), 3, accuracy: 1e-9)   // more activated
        // Monotonic decreasing: lower RMSSD ⇒ higher stress.
        XCTAssertGreaterThan(StressEngine.stress(forRMSSD: 20, reference: ref),
                             StressEngine.stress(forRMSSD: 50, reference: ref))
    }

    func testStressMappingDegenerateSpreadIsMidpoint() {
        let flat = StressEngine.WakingReference(rmssdCalm: 40, rmssdActivated: 40, nWindows: 40)
        XCTAssertEqual(StressEngine.stress(forRMSSD: 40, reference: flat), 1.5, accuracy: 1e-9)
    }

    // MARK: - Intraday curve

    func testIntradayEmptyWithoutRR() {
        XCTAssertTrue(StressEngine.intradayStress([], reference: ref).isEmpty)
    }

    func testSuppressedRMSSDReadsHigherThanCalm() {
        // Two waking buckets: one calm (high RMSSD), one activated (low RMSSD, still not exercising).
        let calm = bucket(index: 10, meanNN: 850, delta: 55)   // RMSSD 55 → near calm
        let activated = bucket(index: 11, meanNN: 820, delta: 18) // RMSSD 18 → near activated
        let pts = StressEngine.intradayStress(calm + activated, reference: ref)
        XCTAssertEqual(pts.count, 2)
        let s0 = pts[0].stress, s1 = pts[1].stress
        XCTAssertNotNil(s0); XCTAssertNotNil(s1)
        XCTAssertLessThan(s0!, s1!)                 // suppressed HRV ⇒ more stress
        for p in pts { XCTAssertTrue((0...3).contains(p.stress!)) } // bounded
    }

    func testActivityWindowIsNoReading() {
        // meanNN 400 ms ⇒ 150 bpm. With resting 60 / max 190, threshold = 60 + .35·130 = 105.5 → active.
        let active = bucket(index: 20, meanNN: 400, delta: 20)
        let pts = StressEngine.intradayStress(active, reference: ref, restingHR: 60, maxHR: 190)
        XCTAssertEqual(pts.count, 1)
        XCTAssertNil(pts[0].stress, "an active (effort) window must read nil, not a stress value")
    }

    func testNoisyWindowIsNoReading() {
        // 20 valid calm beats + 20 out-of-range beats (5000 ms, dropped by the range filter) → clean
        // coverage 0.5 < 0.7 → no reading, even though 20 clean beats clears HRVAnalyzer.minBeats.
        let base = 30 * StressEngine.defaultWindowSeconds
        var rr: [RRInterval] = []
        for i in 0..<20 { rr.append(RRInterval(ts: base + i, rrMs: 800 + (i % 2 == 0 ? 0 : 40))) }
        for i in 20..<40 { rr.append(RRInterval(ts: base + i, rrMs: 5000)) }
        let pts = StressEngine.intradayStress(rr, reference: ref)
        XCTAssertEqual(pts.count, 1)
        XCTAssertNil(pts[0].stress, "a window dominated by artifacts must read nil")
    }

    func testExcludedSpanIsNoReading() {
        let b = bucket(index: 40, meanNN: 850, delta: 55) // would otherwise be a valid calm reading
        let span = (40 * StressEngine.defaultWindowSeconds)...(41 * StressEngine.defaultWindowSeconds)
        let pts = StressEngine.intradayStress(b, reference: ref, excluded: [span])
        XCTAssertEqual(pts.count, 1)
        XCTAssertNil(pts[0].stress, "a window inside an excluded span (sleep/movement) must read nil")
    }

    /// The anti-min-max guard: a genuinely flat, calm day must NOT be stretched into a peak.
    func testCalmFlatDayHasNoFalsePeak() {
        // 12 buckets all at RMSSD ≈ 55 (near the calm anchor 60). With absolute anchors + clamp, every
        // point sits low; nothing approaches the activated end.
        var day: [RRInterval] = []
        for idx in 0..<12 { day += bucket(index: idx, meanNN: 850, delta: 55) }
        let pts = StressEngine.intradayStress(day, reference: ref)
        let readings = pts.compactMap(\.stress)
        XCTAssertEqual(readings.count, 12)
        let peak = readings.max() ?? 0
        XCTAssertLessThan(peak, 1.0, "a flat calm day must not fabricate a stress peak (min-max bug)")
    }

    func testCurveIsTimeOrdered() {
        let day = bucket(index: 5, meanNN: 850, delta: 55)
            + bucket(index: 2, meanNN: 820, delta: 30)
            + bucket(index: 9, meanNN: 840, delta: 45)
        let pts = StressEngine.intradayStress(day, reference: ref)
        XCTAssertEqual(pts.map(\.date), pts.map(\.date).sorted())
    }

    // MARK: - Waking reference

    func testReferenceNilOnColdStart() {
        // One valid bucket is far below minReferenceWindows → no reference (caller shows "learning").
        let day = bucket(index: 0, meanNN: 850, delta: 50)
        XCTAssertNil(StressEngine.wakingReference(daysRR: [day]))
    }

    func testReferenceBuildsRobustAnchors() {
        // 40 waking buckets across 2 days, RMSSD cycling 20…60 → calm anchor (p80) > activated (p20).
        let deltas = [20, 30, 40, 50, 60]
        func day(_ offset: Int) -> [RRInterval] {
            (0..<20).reduce(into: [RRInterval]()) { acc, j in
                acc += bucket(index: offset + j, meanNN: 850, delta: deltas[j % deltas.count])
            }
        }
        let r = StressEngine.wakingReference(daysRR: [day(0), day(100)])
        XCTAssertNotNil(r)
        XCTAssertGreaterThan(r!.rmssdCalm, r!.rmssdActivated)
        XCTAssertGreaterThanOrEqual(r!.spread, StressEngine.defaultMinSpreadMs)
        XCTAssertEqual(r!.nWindows, 40)
    }

    func testReferenceNilOnDegenerateSpread() {
        // 40 buckets, all identical RMSSD → calm == activated → spread 0 < minSpread → no reference.
        let day = (0..<40).reduce(into: [RRInterval]()) { acc, j in
            acc += bucket(index: j, meanNN: 850, delta: 35)
        }
        XCTAssertNil(StressEngine.wakingReference(daysRR: [day]))
    }

    func testReferenceExcludesActivityFromAnchors() {
        // Mix of calm waking buckets + clearly-active buckets; the active ones must not inflate anchors.
        var day: [RRInterval] = []
        for j in 0..<35 { day += bucket(index: j, meanNN: 850, delta: [25, 45, 60][j % 3]) }
        for j in 35..<45 { day += bucket(index: j, meanNN: 380, delta: 20) } // ~158 bpm → excluded
        let r = StressEngine.wakingReference(daysRR: [day])
        XCTAssertNotNil(r)
        XCTAssertEqual(r!.nWindows, 35, "active buckets must be excluded from the waking reference")
    }

    // MARK: - Consistency with HRVAnalyzer (one source of truth for RMSSD)

    func testBucketRMSSDMatchesHRVAnalyzer() {
        let b = bucket(index: 7, meanNN: 850, delta: 42)
        let values = b.map { Double($0.rrMs) }
        let expected = HRVAnalyzer.analyze(rawRR: values).rmssd
        XCTAssertNotNil(expected)
        let got = StressEngine.bucketRMSSD(values, restingHR: 60, maxHR: 190,
                                           activeFraction: 0.35, minCleanFraction: 0.7)
        XCTAssertNotNil(got)
        XCTAssertEqual(got!, expected!, accuracy: 1e-9)
        XCTAssertEqual(got!, 42, accuracy: 1e-9) // alternating ±42 ⇒ RMSSD 42
    }
}
