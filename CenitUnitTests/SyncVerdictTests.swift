import XCTest
@testable import Cenit

/// Pins the sync-diagnostic verdict branching (`LiveState.SyncVerdict.decide`). The bug it guards
/// (FER-152): a lost-clock offload sends only CONSOLE_LOGS (type-50) and zero biometric records
/// (type-47), which the old logic mislabeled "data arrives but doesn't decode — report it". That
/// case must read as "the band isn't storing (clock)" and only the genuine type-47 → 0-rows case
/// keeps the "report it" verdict.
final class SyncVerdictTests: XCTestCase {

    private func receipt(frames: Int, biometric: Int, rows: Int) -> LiveState.SyncReceipt {
        var r = LiveState.SyncReceipt()
        r.framesReceived = frames
        r.biometricFrames = biometric
        r.rowsDecoded = rows
        return r
    }

    // MARK: - nothing new

    func testNoFramesIsNothingNew() {
        let r = receipt(frames: 0, biometric: 0, rows: 0)
        // No frames wins regardless of the history window.
        XCTAssertEqual(LiveState.SyncVerdict.decide(r, reportsStoredHistory: false), .nothingNew)
        XCTAssertEqual(LiveState.SyncVerdict.decide(r, reportsStoredHistory: true), .nothingNew)
    }

    // MARK: - lost clock (FER-152, criterion 1)

    func testConsoleLogsOnlyWithoutStoredHistoryIsNotStoringClock() {
        // type-50 console logs arrived (frames > 0) but zero type-47 biometric records, and
        // GET_DATA_RANGE reports no plausible window → the band isn't saving anything (lost clock).
        let r = receipt(frames: 12, biometric: 0, rows: 0)
        XCTAssertEqual(LiveState.SyncVerdict.decide(r, reportsStoredHistory: false), .notStoringClock)
    }

    func testConsoleLogsOnlyButBandReportsHistoryStaysReportable() {
        // Zero type-47, but the band DOES report a stored-history window — that's not the clean
        // lost-clock case, so stay conservative and keep the "report it" verdict, never claim
        // "not storing" when the band says it holds data.
        let r = receipt(frames: 12, biometric: 0, rows: 0)
        XCTAssertEqual(LiveState.SyncVerdict.decide(r, reportsStoredHistory: true), .arrivesButNoDecode)
    }

    // MARK: - decode failure (FER-152, criterion 2 — unchanged)

    func testBiometryArrivesButDecodesToZeroRowsIsReportable() {
        // The genuine silent-loss case: type-47 biometric frames arrived but decoded to nothing
        // (CRC / unmapped layout / out-of-range timestamp). Keeps its "report it" verdict whether or
        // not a history window was reported.
        let r = receipt(frames: 20, biometric: 20, rows: 0)
        XCTAssertEqual(LiveState.SyncVerdict.decide(r, reportsStoredHistory: false), .arrivesButNoDecode)
        XCTAssertEqual(LiveState.SyncVerdict.decide(r, reportsStoredHistory: true), .arrivesButNoDecode)
    }

    // MARK: - healthy

    func testBiometryArrivesAndDecodesIsReceivingAndStoring() {
        let r = receipt(frames: 20, biometric: 20, rows: 144)
        XCTAssertEqual(LiveState.SyncVerdict.decide(r, reportsStoredHistory: false), .receivingAndStoring)
        XCTAssertEqual(LiveState.SyncVerdict.decide(r, reportsStoredHistory: true), .receivingAndStoring)
    }
}
