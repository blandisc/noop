import XCTest
@testable import StrandTraining

// CaptureGuardTests.swift — FER-169 · B10: the fat-finger threshold, pure and isolated from the DB/UI
// call sites that all defer to it (`StrengthStore.bestPRs`/`lastWorkSets`/`workSetHistory`,
// `StrengthSessionModel`'s capture guard).

final class CaptureGuardTests: XCTestCase {
    func testFiresAtExactlyEightTimesTheReference() {
        XCTAssertTrue(CaptureGuard.isAbsurd(weightKg: 800, referenceKg: 100))     // 8.0×, boundary — fires
        XCTAssertFalse(CaptureGuard.isAbsurd(weightKg: 799.9, referenceKg: 100))  // just under — doesn't
    }

    func testTheCanonicalTypo825For82point5() {
        XCTAssertTrue(CaptureGuard.isAbsurd(weightKg: 825, referenceKg: 100))
    }

    func testALegitimateBigJumpNeverTrips() {
        // A held raise, a fresh PR, a big jump between warm-up and work — none of these are 8×.
        XCTAssertFalse(CaptureGuard.isAbsurd(weightKg: 120, referenceKg: 100))
        XCTAssertFalse(CaptureGuard.isAbsurd(weightKg: 200, referenceKg: 100))
    }

    func testNoReferenceNeverFires() {
        // First-ever weighted set of an exercise: nothing to compare against, never guessed.
        XCTAssertFalse(CaptureGuard.isAbsurd(weightKg: 825, referenceKg: 0))
        XCTAssertFalse(CaptureGuard.isAbsurd(weightKg: 825, referenceKg: -1))
    }
}
