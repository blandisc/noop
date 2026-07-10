import XCTest
@testable import StrandAnalytics

final class NocturnalDCTests: XCTestCase {

    // MARK: - Core DC formula (Bauer T=1 Haar)

    /// Hand-computed reference. Series [800,810,805,820,815,830]:
    /// the only valid anchor (increase ≤5%, with two beats before and one after) is index 3 (820>805).
    ///   DC = (X̄0 + X̄1 − X̄−1 − X̄−2)/4 = (820 + 815 − 805 − 810)/4 = 20/4 = 5.0 ms, over 1 anchor.
    func testDecelerationCapacityHandComputed() {
        let rr: [Double] = [800, 810, 805, 820, 815, 830]
        guard let (dc, anchors) = NocturnalDC.decelerationCapacity(rr) else {
            return XCTFail("expected a DC value")
        }
        XCTAssertEqual(anchors, 1)
        XCTAssertEqual(dc, 5.0, accuracy: 1e-9)
    }

    /// A flat series has no strict increases ⇒ no anchors ⇒ nil.
    func testFlatSeriesHasNoAnchors() {
        XCTAssertNil(NocturnalDC.decelerationCapacity([Double](repeating: 800, count: 50)))
    }

    /// The 5% artifact guard rejects an implausibly large jump as an anchor.
    func testAnchorArtifactGuardRejectsBigJumps() {
        // 800 → 900 is +12.5% (> 5%): index 2 must NOT be an anchor. No other valid anchor ⇒ nil.
        XCTAssertNil(NocturnalDC.decelerationCapacity([810, 800, 900, 890]))
    }

    /// An oscillating (respiratory-like) R-R series has genuine deceleration structure ⇒ positive DC.
    func testOscillatingSeriesGivesPositiveDC() {
        let rr = (0..<600).map { 850.0 + 30.0 * sin(2.0 * Double.pi * Double($0) / 10.0) }
        guard let (dc, anchors) = NocturnalDC.decelerationCapacity(rr) else {
            return XCTFail("expected a DC value")
        }
        XCTAssertGreaterThan(anchors, 100)
        XCTAssertGreaterThan(dc, 0)
    }

    // MARK: - Gating in compute()

    func testTooFewBeatsIsUnreadable() {
        let rr = (0..<100).map { 850.0 + 20.0 * sin(2.0 * Double.pi * Double($0) / 10.0) }
        let res = NocturnalDC.compute(rawRR: rr)
        XCTAssertEqual(res.confidence, .unreadable)
        XCTAssertEqual(res.dcMs, 0)
        XCTAssertNil(res.trend)
    }

    func testHighArtifactFractionIsUnreadable() {
        // Half the beats are out of the physiological range [300,2000] ⇒ artifactFraction ~0.5 > ceiling.
        var rr: [Double] = []
        for i in 0..<800 { rr.append(i % 2 == 0 ? 850.0 : 5000.0) }
        let res = NocturnalDC.compute(rawRR: rr)
        XCTAssertEqual(res.confidence, .unreadable)
        XCTAssertGreaterThan(res.artifactFraction, NocturnalDC.maxArtifactFraction)
    }

    func testCleanNightIsReadableWithPositiveDC() {
        let rr = (0..<3000).map { 900.0 + 40.0 * sin(2.0 * Double.pi * Double($0) / 12.0) }
        let res = NocturnalDC.compute(rawRR: rr)
        XCTAssertNotEqual(res.confidence, .unreadable)
        XCTAssertGreaterThan(res.dcMs, 0)
        XCTAssertGreaterThanOrEqual(res.anchors, NocturnalDC.minAnchors)
    }

    // MARK: - Trend vs personal baseline

    func testTrendAboveBelowAround() {
        let rr = (0..<3000).map { 900.0 + 40.0 * sin(2.0 * Double.pi * Double($0) / 12.0) }
        let dc = NocturnalDC.compute(rawRR: rr).dcMs
        XCTAssertGreaterThan(dc, 0)

        // Baseline well below tonight ⇒ above; well above ⇒ below; equal ⇒ around.
        XCTAssertEqual(NocturnalDC.compute(rawRR: rr, baselineDcMs: dc * 0.5).trend, .above)
        XCTAssertEqual(NocturnalDC.compute(rawRR: rr, baselineDcMs: dc * 2.0).trend, .below)
        XCTAssertEqual(NocturnalDC.compute(rawRR: rr, baselineDcMs: dc).trend, .around)
    }

    // MARK: - Honest copy (no clinical cut-offs, no mortality)

    func testNoteNeverMentionsMortalityOrRisk() {
        let rr = (0..<3000).map { 900.0 + 40.0 * sin(2.0 * Double.pi * Double($0) / 12.0) }
        for base in [nil, 3.0, 30.0] as [Double?] {
            let note = NocturnalDC.compute(rawRR: rr, baselineDcMs: base).note.lowercased()
            for banned in ["mortal", "muerte", "riesgo", "hipertens", "diagnóst", "enferm"] {
                XCTAssertFalse(note.contains(banned), "note leaked a clinical/risk term: \(note)")
            }
        }
    }

    func testNoteWithoutBaselineFramesAsTrend() {
        let rr = (0..<3000).map { 900.0 + 40.0 * sin(2.0 * Double.pi * Double($0) / 12.0) }
        let note = NocturnalDC.compute(rawRR: rr).note
        XCTAssertTrue(note.contains("tendencia"), "no-baseline note should frame DC as a personal trend: \(note)")
    }

    func testUnreadableNoteIsHonest() {
        let res = NocturnalDC.compute(rawRR: [Double](repeating: 800, count: 50))
        XCTAssertEqual(res.confidence, .unreadable)
        XCTAssertTrue(res.note.contains("suficiente señal"))
    }
}
