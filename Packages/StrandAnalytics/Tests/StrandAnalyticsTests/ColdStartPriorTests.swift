import XCTest
@testable import StrandAnalytics

/// FER-60: pins the cold-start contract the Apple Health baseline prior relies on. Folding a handful
/// of seed nights (the capped seed prior injected from Apple Health history) must take
/// the HRV baseline from CALIBRATING — where recovery honestly refuses to score — to PROVISIONAL,
/// where recovery scores but the FER-13 confidence shrinkage still damps it (so the Apple↔strap HRV
/// scale gap can't swing the number). A capped prior must NOT vault straight to TRUSTED.
final class ColdStartPriorTests: XCTestCase {

    func testBelowSeedGateRefusesToScore() {
        // 3 nights < minNightsSeed (4): baseline is calibrating, so recovery is nil (honest cold-start).
        let seq: [Double?] = [55, 58, 56]
        let cold = Baselines.foldHistory(seq, cfg: Baselines.hrvCfg)
        XCTAssertFalse(cold.usable)
        XCTAssertNil(RecoveryScorer.recovery(
            hrv: 57, rhr: 55, resp: nil,
            hrvBaseline: cold, rhrBaseline: nil, respBaseline: nil,
            sleepPerf: RecoveryScorer.sleepPerfCenter))
    }

    func testSeedNightPriorCrossesGateAsProvisionalAndScores() {
        // 7 seeded nights — what a capped Apple Health prior (applePriorMaxNights) injects: the
        // baseline becomes PROVISIONAL — usable, yet below minNightsTrust (14) so it stays shrunk.
        let seq: [Double?] = [60, 58, 61, 59, 57, 62, 56]
        let seeded = Baselines.foldHistory(seq, cfg: Baselines.hrvCfg)
        XCTAssertTrue(seeded.usable, "7 seed nights must clear the seed gate")
        XCTAssertEqual(seeded.status, .provisional, "a capped prior stays provisional, not trusted")
        XCTAssertLessThan(seeded.nValid, Baselines.minNightsTrust)
        XCTAssertNotNil(RecoveryScorer.recovery(
            hrv: 56, rhr: 55, resp: nil,
            hrvBaseline: seeded, rhrBaseline: nil, respBaseline: nil,
            sleepPerf: RecoveryScorer.sleepPerfCenter),
            "recovery lights up once the baseline is seeded")
    }
}
