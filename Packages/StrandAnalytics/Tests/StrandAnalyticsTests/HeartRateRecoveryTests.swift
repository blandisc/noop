import XCTest
@testable import StrandAnalytics
import BiometricStreams

/// FER-683 — post-session 60-second heart-rate recovery (HRR-60s).
///
/// Method: median HR at cessation minus median HR at +60 s (windowed to denoise), then an INTRA-USER
/// trend vs the person's own prior sessions (robust σ, shared with IllnessWatch). Never Cole's
/// population 12-bpm cut-off (NEJM 1999) — a wrist strap after an arbitrary workout isn't that protocol.
final class HeartRateRecoveryTests: XCTestCase {

    /// Constant HR before `end`, decaying after, so the drop is exact and known.
    private func stream(end: Int, endHR: Int, recHR: Int) -> [HRSample] {
        var s: [HRSample] = []
        // Effort tail: constant endHR for the 20 s up to end.
        for t in (end - 20)...end { s.append(HRSample(ts: t, bpm: endHR)) }
        // Recovery: constant recHR across the +60 s window (±10 s).
        for t in (end + 50)...(end + 70) { s.append(HRSample(ts: t, bpm: recHR)) }
        return s
    }

    /// A clean drop from 170 → 130 over 60 s is a 40-bpm HRR.
    func testBasicDrop() throws {
        let end = 1_000_000
        let r = HeartRateRecovery.hrr60s(sessionEnd: end, hr: stream(end: end, endHR: 170, recHR: 130))
        XCTAssertTrue(r.covered)
        XCTAssertEqual(try XCTUnwrap(r.hrrBpm), 40, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(r.hrAtEndBpm), 170, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(r.hrAt60sBpm), 130, accuracy: 1e-9)
    }

    /// No samples in the +60 s window ⇒ uncovered, nil drop (never fabricate a recovery from a gap).
    func testGapAtRecoveryIsUncovered() {
        let end = 2_000_000
        // Only the effort tail; nothing near +60 s.
        let tail = ((end - 20)...end).map { HRSample(ts: $0, bpm: 165) }
        let r = HeartRateRecovery.hrr60s(sessionEnd: end, hr: tail)
        XCTAssertFalse(r.covered)
        XCTAssertNil(r.hrrBpm)
    }

    /// A median ignores a single wild beat at the anchor second.
    func testMedianRejectsSingleSpike() throws {
        let end = 3_000_000
        var s = stream(end: end, endHR: 170, recHR: 130)
        s.append(HRSample(ts: end, bpm: 40))            // one dropout beat at cessation
        let r = HeartRateRecovery.hrr60s(sessionEnd: end, hr: s)
        XCTAssertEqual(try XCTUnwrap(r.hrAtEndBpm), 170, accuracy: 1e-9) // median unmoved by the outlier
    }

    /// A blunted drop (well below the personal mean) flags on the intra-user trend.
    func testTrendFlagsBluntedRecovery() {
        // Usual HRR ~40 bpm with small spread; today only 22.
        let prior = [40.0, 41, 39, 40, 42, 38, 40, 41]
        let t = HeartRateRecovery.trend(latest: 22, priorHRR: prior)
        XCTAssertTrue(t.bluntedVsNormal)
        XCTAssertLessThanOrEqual(t.z ?? 0, -HeartRateRecovery.bluntedZThreshold)
        XCTAssertEqual(t.baselineBpm ?? 0, 40.125, accuracy: 0.2)
    }

    /// A normal-range recovery does not flag, and a faster-than-usual one is not "blunted".
    func testTrendNormalAndStrong() {
        let prior = [40.0, 41, 39, 40, 42, 38, 40, 41]
        XCTAssertFalse(HeartRateRecovery.trend(latest: 40, priorHRR: prior).bluntedVsNormal)
        let strong = HeartRateRecovery.trend(latest: 58, priorHRR: prior)
        XCTAssertFalse(strong.bluntedVsNormal)
        XCTAssertGreaterThan(strong.z ?? 0, 0)
    }

    /// Too little history ⇒ no trend yet (learning), never a flag.
    func testTrendColdStart() {
        let t = HeartRateRecovery.trend(latest: 20, priorHRR: [40])
        XCTAssertNil(t.z)
        XCTAssertFalse(t.bluntedVsNormal)
    }

    /// Copy is intra-user and never invokes the clinical cut-off or mortality.
    func testCopyIsIntraUser() {
        let prior = [40.0, 41, 39, 40, 42, 38, 40, 41]
        let note = HeartRateRecovery.trend(latest: 22, priorHRR: prior).note.lowercased()
        for banned in ["12 bpm", "mortality", "abnormal", "disease", "cole"] {
            XCTAssertFalse(note.contains(banned), "copy must stay intra-user: found \(banned)")
        }
    }
}
