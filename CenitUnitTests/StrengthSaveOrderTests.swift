import XCTest
@testable import Cenit

/// Pins the FER-969 (X-01) ordering contract of the final strength save: the anti-crash snapshot
/// (FER-798) — the only remaining copy of the workout — is dropped only AFTER the session row is
/// durably saved. A failed save must leave the snapshot untouched and report failure so the sheet
/// can offer retry instead of pretending success.
final class StrengthSaveOrderTests: XCTestCase {

    private struct Boom: Error {}

    func testSnapshotClearedOnlyAfterSuccessfulSave() async {
        var log: [String] = []
        let saved = await AppModel.saveThenClearSnapshot(
            save: { log.append("save") },
            clearSnapshot: { log.append("clear") })
        XCTAssertTrue(saved)
        XCTAssertEqual(log, ["save", "clear"], "the snapshot may only be cleared after the save landed")
    }

    func testFailedSaveKeepsSnapshotAndReportsFailure() async {
        var log: [String] = []
        let saved = await AppModel.saveThenClearSnapshot(
            save: { log.append("save"); throw Boom() },
            clearSnapshot: { log.append("clear") })
        XCTAssertFalse(saved)
        XCTAssertEqual(log, ["save"], "a failed save must never clear the snapshot")
    }

    func testClearFailureStillReportsSavedButNeverBlocksTheReceipt() async {
        let saved = await AppModel.saveThenClearSnapshot(
            save: {},
            clearSnapshot: { throw Boom() })
        XCTAssertTrue(saved, "a failed best-effort clear must not mask a successful save")
    }
}
