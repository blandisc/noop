import XCTest
@testable import WhoopProtocol

/// Pins `CaughtUpDetector` — the pure decision behind FER-201 ("the 4.0 sync never closes because the
/// firmware never sends HISTORY_COMPLETE"). The detector lets the offload complete as a SUCCESS once a
/// sustained run of small `HISTORY_END` chunks proves the backlog is drained, instead of wedging to the
/// 300 s cap ("Sync ran long and was paused"). Backlog chunks ≈ 50 records; caught-up ≈ live drip.
final class CaughtUpDetectorTests: XCTestCase {

    /// A real backlog (full chunks forever) must NEVER be mistaken for caught-up.
    func testBacklogNeverCompletes() {
        var d = CaughtUpDetector(smallChunkMax: 8, run: 3)
        for _ in 0..<200 { XCTAssertFalse(d.observe(biometricFrames: 50)) }
        XCTAssertFalse(d.isCaughtUp)
    }

    /// A sustained run of small ENDs (the live drip after the backlog drains) completes on the Nth.
    func testSustainedSmallRunCompletesOnTheNth() {
        var d = CaughtUpDetector(smallChunkMax: 8, run: 3)
        XCTAssertFalse(d.observe(biometricFrames: 50)) // backlog
        XCTAssertFalse(d.observe(biometricFrames: 4))  // small 1
        XCTAssertFalse(d.observe(biometricFrames: 3))  // small 2
        XCTAssertTrue(d.observe(biometricFrames: 0))   // small 3 → caught up
    }

    /// A one-off small chunk in the middle of a backlog must not complete — the next full chunk resets.
    func testSingleSmallChunkMidBacklogDoesNotComplete() {
        var d = CaughtUpDetector(smallChunkMax: 8, run: 3)
        XCTAssertFalse(d.observe(biometricFrames: 3))   // small 1
        XCTAssertFalse(d.observe(biometricFrames: 50))  // reset
        XCTAssertFalse(d.observe(biometricFrames: 3))   // small 1
        XCTAssertFalse(d.observe(biometricFrames: 50))  // reset
        XCTAssertFalse(d.isCaughtUp)
    }

    /// Alternating full/empty ENDs (an empty END is acked mid-backlog to advance trim) never reaches a
    /// run of N consecutive small — the full chunks keep resetting it.
    func testAlternatingFullAndEmptyNeverCompletes() {
        var d = CaughtUpDetector(smallChunkMax: 8, run: 3)
        for _ in 0..<50 {
            XCTAssertFalse(d.observe(biometricFrames: 50))
            XCTAssertFalse(d.observe(biometricFrames: 0))
        }
    }

    /// A band with nothing to offload (empty ENDs from the start) is caught-up after the run.
    func testEmptyBandCaughtUpAfterRun() {
        var d = CaughtUpDetector(smallChunkMax: 8, run: 3)
        XCTAssertFalse(d.observe(biometricFrames: 0))
        XCTAssertFalse(d.observe(biometricFrames: 0))
        XCTAssertTrue(d.observe(biometricFrames: 0))
    }

    /// `smallChunkMax` is inclusive; one above it is a backlog chunk that resets the run.
    func testBoundaryAtSmallChunkMax() {
        var atMax = CaughtUpDetector(smallChunkMax: 8, run: 2)
        XCTAssertFalse(atMax.observe(biometricFrames: 8)) // == max → small 1
        XCTAssertTrue(atMax.observe(biometricFrames: 8))  // small 2 → done

        var aboveMax = CaughtUpDetector(smallChunkMax: 8, run: 2)
        XCTAssertFalse(aboveMax.observe(biometricFrames: 9)) // > max → not small
        XCTAssertFalse(aboveMax.observe(biometricFrames: 9))
        XCTAssertFalse(aboveMax.isCaughtUp)
    }

    /// Once caught-up it stays caught-up regardless of later input (idempotent).
    func testStaysDoneAfterCaughtUp() {
        var d = CaughtUpDetector(smallChunkMax: 8, run: 2)
        _ = d.observe(biometricFrames: 0)
        XCTAssertTrue(d.observe(biometricFrames: 0))
        XCTAssertTrue(d.observe(biometricFrames: 999)) // a late big chunk can't un-complete it
        XCTAssertTrue(d.isCaughtUp)
    }

    /// `reset()` clears state for a fresh offload session.
    func testResetClearsState() {
        var d = CaughtUpDetector(smallChunkMax: 8, run: 2)
        _ = d.observe(biometricFrames: 0)
        _ = d.observe(biometricFrames: 0)
        XCTAssertTrue(d.isCaughtUp)
        d.reset()
        XCTAssertFalse(d.isCaughtUp)
        XCTAssertFalse(d.observe(biometricFrames: 0)) // counter cleared → needs the full run again
    }

    /// FER-93: a narrating-not-saving END (RTC-lost band: zero biometry + CONSOLE_LOGS) must NEVER count
    /// toward caught-up — a sync over an un-clocked band must not complete "green" while it isn't saving.
    func testNarratingNotSavingNeverCompletes() {
        var d = CaughtUpDetector(smallChunkMax: 8, run: 3)
        for _ in 0..<200 { XCTAssertFalse(d.observe(biometricFrames: 0, narratingNotSaving: true)) }
        XCTAssertFalse(d.isCaughtUp)
    }

    /// A narrating END mid-run resets the small-chunk count, so the run restarts from scratch.
    func testNarratingResetsTheRun() {
        var d = CaughtUpDetector(smallChunkMax: 8, run: 3)
        XCTAssertFalse(d.observe(biometricFrames: 3))                           // small 1
        XCTAssertFalse(d.observe(biometricFrames: 3))                           // small 2
        XCTAssertFalse(d.observe(biometricFrames: 0, narratingNotSaving: true)) // narrating → reset
        XCTAssertFalse(d.observe(biometricFrames: 3))                           // small 1 again
        XCTAssertFalse(d.observe(biometricFrames: 3))                           // small 2
        XCTAssertTrue(d.observe(biometricFrames: 3))                            // small 3 → caught up
    }

    /// A genuine small-but-SAVING tail (biometry > 0, not narrating) still completes — narrating is the
    /// only new exclusion; a small saving chunk is the real live drip.
    func testSmallSavingTailStillCompletes() {
        var d = CaughtUpDetector(smallChunkMax: 8, run: 3)
        XCTAssertFalse(d.observe(biometricFrames: 4, narratingNotSaving: false))
        XCTAssertFalse(d.observe(biometricFrames: 2, narratingNotSaving: false))
        XCTAssertTrue(d.observe(biometricFrames: 1, narratingNotSaving: false))
    }
}
