import XCTest
@testable import WhoopProtocol

/// Pins `DrainContinuationPolicy` — the pure decision behind FER-287/FER-480 ("auto-continue the offload
/// until the backlog drains, so the user doesn't tap Sync dozens of times"). FER-480 re-anchored the
/// "is there more backlog?" signal from a frame-count heuristic to GROUND TRUTH: the strap's reported
/// newest banked record (`GET_DATA_RANGE`) vs our persisted frontier (max HR ts), with an anti-spin trim
/// guard and a #451 stale-range fallback (real rows persisted). `caughtUp` and a non-clean close are hard
/// stops; `maxChain` guarantees termination.
final class DrainContinuationPolicyTests: XCTestCase {

    // A strap clearly ahead of our frontier (≫ behindGapSeconds). Far-apart sane unix epochs.
    private let aheadNewest = 2_000_000_000
    private let frontier    = 1_000_000_000

    /// Ground truth says backlog remains (strap newest ≫ frontier) + trim advanced + clean → continue.
    func testBacklogAheadContinues() {
        var p = DrainContinuationPolicy(behindGapSeconds: 300, maxChain: 120)
        XCTAssertTrue(p.shouldContinue(completedCleanly: true, caughtUp: false,
                                       strapNewestTs: aheadNewest, ourFrontierTs: frontier,
                                       rowsPersistedThisSession: 270, lastTrimAdvanced: true))
        XCTAssertEqual(p.chainLength, 1)
    }

    /// Strap not ahead (within behindGap) and no rows persisted → caught up → stop.
    func testNotBehindAndNoRowsStops() {
        var p = DrainContinuationPolicy(behindGapSeconds: 300, maxChain: 120)
        XCTAssertFalse(p.shouldContinue(completedCleanly: true, caughtUp: false,
                                        strapNewestTs: frontier + 100, ourFrontierTs: frontier,
                                        rowsPersistedThisSession: 0, lastTrimAdvanced: true))
        XCTAssertEqual(p.chainLength, 0)
    }

    /// `caughtUp` (CaughtUpDetector) is a hard stop even if the range reads "behind" — this is also what
    /// bounds the HR-only-frontier-lag case on a WHOOP 4.0 synced night (sparse derived HR, #507).
    func testCaughtUpHardStop() {
        var p = DrainContinuationPolicy()
        XCTAssertFalse(p.shouldContinue(completedCleanly: true, caughtUp: true,
                                        strapNewestTs: aheadNewest, ourFrontierTs: frontier,
                                        rowsPersistedThisSession: 5000, lastTrimAdvanced: true))
    }

    /// A frozen trim cursor → anti-spin → stop, even when behind with rows (strap refusing to trim).
    func testFrozenTrimStops() {
        var p = DrainContinuationPolicy()
        XCTAssertFalse(p.shouldContinue(completedCleanly: true, caughtUp: false,
                                        strapNewestTs: aheadNewest, ourFrontierTs: frontier,
                                        rowsPersistedThisSession: 270, lastTrimAdvanced: false))
    }

    /// #451 fallback — range unknown (nil newest) but real rows persisted + trim advanced → still
    /// draining → continue.
    func testStaleRangeNilNewestButRealRowsContinues() {
        var p = DrainContinuationPolicy()
        XCTAssertTrue(p.shouldContinue(completedCleanly: true, caughtUp: false,
                                       strapNewestTs: nil, ourFrontierTs: frontier,
                                       rowsPersistedThisSession: 270, lastTrimAdvanced: true))
    }

    /// #451 fallback — a multi-epoch strap latches a "newest" BEHIND our frontier, but it's still handing
    /// over real rows (and the trim advanced) → keep going, don't make the user tap the strap.
    func testStaleRangeOlderNewestButRealRowsContinues() {
        var p = DrainContinuationPolicy()
        XCTAssertTrue(p.shouldContinue(completedCleanly: true, caughtUp: false,
                                       strapNewestTs: frontier - 100_000_000, ourFrontierTs: frontier,
                                       rowsPersistedThisSession: 270, lastTrimAdvanced: true))
    }

    /// Empty / console-only session (0 rows) with a stale / not-ahead range → genuinely caught up → stop.
    func testStaleRangeAndNoRowsStops() {
        var p = DrainContinuationPolicy()
        XCTAssertFalse(p.shouldContinue(completedCleanly: true, caughtUp: false,
                                        strapNewestTs: nil, ourFrontierTs: frontier,
                                        rowsPersistedThisSession: 0, lastTrimAdvanced: true))
    }

    /// A non-clean close (idle timeout / session cap) never chains, even with a big backlog ahead.
    func testInterruptedNeverContinues() {
        var p = DrainContinuationPolicy()
        XCTAssertFalse(p.shouldContinue(completedCleanly: false, caughtUp: false,
                                        strapNewestTs: aheadNewest, ourFrontierTs: frontier,
                                        rowsPersistedThisSession: 270, lastTrimAdvanced: true))
    }

    /// The "behind" threshold is exclusive: exactly `behindGapSeconds` ahead (no rows) → not behind → stop;
    /// one second more → behind → continue.
    func testBehindBoundaryExclusive() {
        var p = DrainContinuationPolicy(behindGapSeconds: 300, maxChain: 120)
        XCTAssertFalse(p.shouldContinue(completedCleanly: true, caughtUp: false,
                                        strapNewestTs: frontier + 300, ourFrontierTs: frontier,
                                        rowsPersistedThisSession: 0, lastTrimAdvanced: true))
        XCTAssertTrue(p.shouldContinue(completedCleanly: true, caughtUp: false,
                                       strapNewestTs: frontier + 301, ourFrontierTs: frontier,
                                       rowsPersistedThisSession: 0, lastTrimAdvanced: true))
    }

    /// Unknown frontier (nil) can't compute "behind", so it falls back to rows: real rows → continue,
    /// zero rows → stop.
    func testNilFrontierFallsBackToRows() {
        var p = DrainContinuationPolicy()
        XCTAssertTrue(p.shouldContinue(completedCleanly: true, caughtUp: false,
                                       strapNewestTs: aheadNewest, ourFrontierTs: nil,
                                       rowsPersistedThisSession: 270, lastTrimAdvanced: true))
        var q = DrainContinuationPolicy()
        XCTAssertFalse(q.shouldContinue(completedCleanly: true, caughtUp: false,
                                        strapNewestTs: aheadNewest, ourFrontierTs: nil,
                                        rowsPersistedThisSession: 0, lastTrimAdvanced: true))
    }

    /// Termination: even with backlog forever ahead, the chain stops at `maxChain`; `reset()` re-arms.
    func testMaxChainCapsThenResetReArms() {
        var p = DrainContinuationPolicy(behindGapSeconds: 300, maxChain: 3)
        for _ in 0..<3 {
            XCTAssertTrue(p.shouldContinue(completedCleanly: true, caughtUp: false,
                                           strapNewestTs: aheadNewest, ourFrontierTs: frontier,
                                           rowsPersistedThisSession: 270, lastTrimAdvanced: true))
        }
        XCTAssertFalse(p.shouldContinue(completedCleanly: true, caughtUp: false,
                                        strapNewestTs: aheadNewest, ourFrontierTs: frontier,
                                        rowsPersistedThisSession: 270, lastTrimAdvanced: true))
        XCTAssertEqual(p.chainLength, 3)
        p.reset()
        XCTAssertEqual(p.chainLength, 0)
        XCTAssertTrue(p.shouldContinue(completedCleanly: true, caughtUp: false,
                                       strapNewestTs: aheadNewest, ourFrontierTs: frontier,
                                       rowsPersistedThisSession: 270, lastTrimAdvanced: true))
    }

    /// A full disconnected night drains in one chain on ground truth: while the strap stays ahead the
    /// chain continues; once the frontier catches up (not behind) with the live drip it stops — well under
    /// the safety cap. Models the frontier advancing each session as the oldest-first offload progresses.
    func testFullNightDrainConvergesAndStops() {
        var p = DrainContinuationPolicy(behindGapSeconds: 300, maxChain: 120)
        let strapNewest = 1_000_000_000 + 8 * 3600       // strap holds ~8 h of backlog ahead of our start
        var front = 1_000_000_000                         // our frontier at the start of the drain
        var sessions = 0
        // Each session advances the frontier ~7 min (≈270 samples at 1 Hz over a sparse night) toward newest.
        while (strapNewest - front) > 300 {
            sessions += 1
            XCTAssertTrue(p.shouldContinue(completedCleanly: true, caughtUp: false,
                                           strapNewestTs: strapNewest, ourFrontierTs: front,
                                           rowsPersistedThisSession: 270, lastTrimAdvanced: true),
                          "should keep draining at session \(sessions)")
            front += 7 * 60
        }
        // Caught up to the live edge → stop. Not behind, and a caught-up session persists 0 NEW rows
        // (the live drip is already stored → idempotent insert), so neither the range nor the #451 rows
        // fallback fires. The night drained without hitting the safety cap.
        XCTAssertFalse(p.shouldContinue(completedCleanly: true, caughtUp: false,
                                        strapNewestTs: strapNewest, ourFrontierTs: front,
                                        rowsPersistedThisSession: 0, lastTrimAdvanced: true))
        XCTAssertLessThan(p.chainLength, 120, "a full night must drain without hitting the safety cap")
        XCTAssertEqual(p.chainLength, sessions)
    }
}
