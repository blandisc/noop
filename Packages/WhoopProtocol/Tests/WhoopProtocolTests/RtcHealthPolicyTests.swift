import XCTest
@testable import WhoopProtocol

/// FER-93b Part 1: the pure RTC-health decision (no GET_CLOCK, no CoreBluetooth).
/// Oracle for "is the WHOOP 4.0 saving / has it lost its clock" from one offload's signals.
final class RtcHealthPolicyTests: XCTestCase {

    private func assess(_ s: RtcHealthPolicy.Signals) -> RtcHealthPolicy.Verdict {
        RtcHealthPolicy.assess(s)
    }

    // MARK: - Healthy: biometry flowing → clock is fine

    func testBiometryFlowing_isHealthy_notLost() {
        let v = assess(.init(biometricFrames: 50, consoleLogFrames: 1))
        XCTAssertTrue(v.savingHealthy)
        XCTAssertFalse(v.rtcLikelyLost)
        XCTAssertFalse(v.shouldReassertClock)
    }

    /// Saving wins over a stale RTC-invalid console log replayed in the same offload.
    func testBiometryFlowing_overridesStaleRtcInvalidLog() {
        let v = assess(.init(biometricFrames: 43,
                             consoleLogFrames: 15,
                             consoleLogReportsRtcInvalid: true,
                             recentPowerLoss: true))
        XCTAssertTrue(v.savingHealthy)
        XCTAssertFalse(v.rtcLikelyLost)
    }

    // MARK: - Lost: positive signals with no biometry

    /// The exact field signature: 0 type-47, only type-50 → narrating, not saving.
    func testNarratingNotSaving_isLost_andReasserts() {
        let v = assess(.init(biometricFrames: 0, consoleLogFrames: 30))
        XCTAssertFalse(v.savingHealthy)
        XCTAssertTrue(v.rtcLikelyLost)
        XCTAssertTrue(v.shouldReassertClock)
    }

    func testFirmwareRtcInvalidLog_isLost() {
        let v = assess(.init(biometricFrames: 0,
                             consoleLogFrames: 0,
                             consoleLogReportsRtcInvalid: true))
        XCTAssertTrue(v.rtcLikelyLost)
        XCTAssertTrue(v.shouldReassertClock)
    }

    func testImplausibleDataRange_noBiometry_isLost() {
        let v = assess(.init(biometricFrames: 0, dataRangeWindowPlausible: false))
        XCTAssertTrue(v.rtcLikelyLost)
    }

    func testRecentPowerLoss_noBiometry_reasserts() {
        // After a battery-pack removal the volatile RTC may have reset — re-assert proactively.
        let v = assess(.init(biometricFrames: 0, recentPowerLoss: true))
        XCTAssertTrue(v.rtcLikelyLost)
        XCTAssertTrue(v.shouldReassertClock)
    }

    // MARK: - NOT lost: "nothing new" must not look like a lost clock

    func testNothingNew_isNotLost() {
        // Caught up: no biometry, no logs, plausible range, no power loss → idle, not broken.
        let v = assess(.init(biometricFrames: 0,
                             consoleLogFrames: 0,
                             consoleLogReportsRtcInvalid: false,
                             dataRangeWindowPlausible: true,
                             recentPowerLoss: false))
        XCTAssertFalse(v.savingHealthy)
        XCTAssertFalse(v.rtcLikelyLost)
        XCTAssertFalse(v.shouldReassertClock)
    }

    /// A recovered band: power loss earlier in the session, but this offload delivered biometry.
    func testPowerLossThenRecovered_isHealthy() {
        let v = assess(.init(biometricFrames: 50, recentPowerLoss: true))
        XCTAssertTrue(v.savingHealthy)
        XCTAssertFalse(v.rtcLikelyLost)
    }

    // MARK: - Defaults

    func testDefaultsAreIdleNotLost() {
        // An empty signal set (unknown/just-connected) must be treated as idle, never as "lost".
        let v = assess(.init())
        XCTAssertFalse(v.rtcLikelyLost)
        XCTAssertFalse(v.savingHealthy)
    }
}
