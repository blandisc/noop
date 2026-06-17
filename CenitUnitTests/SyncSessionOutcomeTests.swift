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

    // MARK: - timer invariant

    /// The absolute cap must outlast the idle watchdog (so a healthy offload making real progress isn't
    /// cut short) yet fire well before the next periodic re-trigger (so a wedge clears within one
    /// interval and the next tick starts a clean session). FER-174.
    func testAbsoluteCapSitsBetweenIdleWatchdogAndPeriodicRetrigger() {
        XCTAssertGreaterThan(BLEManager.backfillAbsoluteTimeoutSeconds, BLEManager.backfillIdleTimeoutSeconds)
        XCTAssertLessThan(BLEManager.backfillAbsoluteTimeoutSeconds, BLEManager.backfillIntervalSeconds)
    }
}
