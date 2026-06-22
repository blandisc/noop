import XCTest
@testable import Cenit

/// Pins `BLEManager.syncSessionOutcome` and the offload-session timer invariants — the pure policy
/// behind FER-174 ("BLE/store se puede colgar sin salida"). The bug it guards: an offload could stay
/// alive forever when the strap kept streaming frames (re-arming the 60 s idle watchdog) but never
/// emitted HISTORY_COMPLETE (the WHOOP 4.0 wedge in FER-152) → "Sincronizando…" pinned. The fix adds
/// an absolute wall-clock cap whose teardown ("session-cap") must surface a NON-silent, honest error
/// and must NOT be stamped as a successful sync — so the durable strap_trim cursor resumes next session.
final class SyncSessionOutcomeTests: XCTestCase {

    // MARK: - reason → outcome policy

    func testHistoryCompleteIsACompletedSync() {
        XCTAssertEqual(BLEManager.syncSessionOutcome(reason: "HISTORY_COMPLETE"), .completed)
    }

    func testIdleTimeoutIsANonSilentInterruption() {
        guard case .interrupted(let message) = BLEManager.syncSessionOutcome(reason: "timeout") else {
            return XCTFail("the idle watchdog timeout must surface a non-silent error, not be silent")
        }
        XCTAssertFalse(message.isEmpty)
    }

    /// The core FER-174 assertion: the absolute cap ends the wedge with an honest, non-silent message.
    func testAbsoluteSessionCapIsANonSilentInterruption() {
        guard case .interrupted(let message) = BLEManager.syncSessionOutcome(reason: "session-cap") else {
            return XCTFail("the absolute session cap must surface a non-silent error, not be silent")
        }
        XCTAssertFalse(message.isEmpty)
    }

    /// A capped session is NOT a successful sync — it must never stamp lastSyncedAt / unlock the verdict,
    /// otherwise a wedge that never delivered HISTORY_COMPLETE would falsely read as "synced".
    func testAbsoluteCapIsNotTreatedAsACompletedSync() {
        XCTAssertNotEqual(BLEManager.syncSessionOutcome(reason: "session-cap"), .completed)
    }

    /// Idle timeout and the absolute cap are distinct teardown reasons but share the same outcome shape
    /// (a non-silent interruption) with their own copy.
    func testTimeoutAndCapAreDistinctMessages() {
        let idle = BLEManager.syncSessionOutcome(reason: "timeout")
        let cap = BLEManager.syncSessionOutcome(reason: "session-cap")
        XCTAssertNotEqual(idle, cap)
    }

    /// Any other teardown (e.g. a mid-sync disconnect routed through here) leaves the sync UI untouched.
    func testUnknownReasonIsSilent() {
        XCTAssertEqual(BLEManager.syncSessionOutcome(reason: "disconnect"), .silent)
        XCTAssertEqual(BLEManager.syncSessionOutcome(reason: ""), .silent)
    }

    /// Caught-up completion (FER-201): when the offload drains the backlog on a firmware that never
    /// sends HISTORY_COMPLETE, the `CaughtUpDetector` ends the session — and that MUST stamp a
    /// successful sync (green receipt + lastSyncedAt), exactly like HISTORY_COMPLETE.
    func testCaughtUpIsACompletedSync() {
        XCTAssertEqual(BLEManager.syncSessionOutcome(reason: "caught-up"), .completed)
    }

    /// "caught-up" is a SUCCESS; the absolute cap is NOT — the FER-201 fix must never collapse the two,
    /// otherwise a wedge would read as synced (or a real completion would show the orange paused error).
    func testCaughtUpAndSessionCapAreOppositeOutcomes() {
        XCTAssertEqual(BLEManager.syncSessionOutcome(reason: "caught-up"), .completed)
        XCTAssertNotEqual(BLEManager.syncSessionOutcome(reason: "caught-up"),
                          BLEManager.syncSessionOutcome(reason: "session-cap"))
    }

    // MARK: - RTC-lost gate (FER-93)

    /// FER-93: a "clean" close (HISTORY_COMPLETE / caught-up) over an RTC-lost band — narrating-not-saving,
    /// zero real biometry — must NOT be stamped as a successful sync, even though the reason is a completion.
    /// Otherwise the UI shows a green "synced" over a night the strap never recorded.
    func testRtcLostOverridesCleanCompletionToInterrupted() {
        for reason in ["HISTORY_COMPLETE", "caught-up"] {
            guard case .interrupted(let message) = BLEManager.syncSessionOutcome(reason: reason, rtcLikelyLost: true) else {
                return XCTFail("an RTC-lost band must not complete \(reason) as a successful sync")
            }
            XCTAssertFalse(message.isEmpty)
        }
    }

    /// The gate is opt-in: without the flag (default `rtcLikelyLost: false`) the policy is byte-for-byte what
    /// it was, so a healthy band's existing reasons can't regress.
    func testRtcHealthyKeepsExistingOutcomes() {
        XCTAssertEqual(BLEManager.syncSessionOutcome(reason: "HISTORY_COMPLETE", rtcLikelyLost: false), .completed)
        XCTAssertEqual(BLEManager.syncSessionOutcome(reason: "caught-up", rtcLikelyLost: false), .completed)
        XCTAssertNotEqual(BLEManager.syncSessionOutcome(reason: "session-cap", rtcLikelyLost: false), .completed)
    }

    // MARK: - timer invariant

    /// The absolute cap must outlast the idle watchdog (so a healthy offload making real progress isn't
    /// cut short) yet fire well before the next periodic re-trigger (so a wedge clears within one
    /// interval and the next tick starts a clean session). FER-174.
    func testAbsoluteCapSitsBetweenIdleWatchdogAndPeriodicRetrigger() {
        XCTAssertGreaterThan(BLEManager.backfillAbsoluteTimeoutSeconds, BLEManager.backfillIdleTimeoutSeconds)
        XCTAssertLessThan(BLEManager.backfillAbsoluteTimeoutSeconds, BLEManager.backfillIntervalSeconds)
    }
}
