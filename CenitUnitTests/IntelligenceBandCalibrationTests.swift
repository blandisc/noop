import XCTest
import WhoopProtocol
@testable import Cenit

/// FER-993 (D3) — regression pin for the `DeviceFamily` → `estimatesSteps: Bool` decoupling.
///
/// `IntelligenceEngine` used to take the hardware-family enum and switch on it in three places:
/// the skin-temp calibration offset, the motion-window span, and the steps-estimation branch. It now
/// takes a single Bool and knows nothing about the family type (which carries the GATT UUIDs and the
/// CLIENT_HELLO bytes, and must stay behind the BLE boundary — that's the point of the épico).
///
/// This test fixes the CALCULATION across that swap: same scenario (a 4.0 band, a 5/MG band), same
/// numbers the pre-D3 `switch family` produced. The values below are transcribed from the code as it
/// stood BEFORE this change, so a drift in either direction fails here:
///
///   pre-D3  skinTempOffsetC:  .whoop4 → 28.5   .whoop5 → 0
///   pre-D3  motionWindowDays: family.estimatesSteps ? 60 : 14
///
/// The companion pin lives in `WhoopProtocolTests.DeviceFamilyFramingTests`
/// (`testEstimatesStepsIsExactlyTheWhoop4Bit`): it guarantees the Bool is a LOSSLESS stand-in for the
/// enum, which is what makes deriving both calibrations from one bit behaviour-preserving.
final class IntelligenceBandCalibrationTests: XCTestCase {

    /// The pre-D3 body of `IntelligenceEngine.skinTempOffsetC`, kept here verbatim as the oracle.
    private func legacySkinTempOffsetC(_ family: DeviceFamily) -> Double {
        switch family {
        case .whoop4: return 28.5
        case .whoop5: return 0
        }
    }

    /// The pre-D3 expression at the top of `runAnalysis` (60 = steps calibration, 14 = circadian).
    private func legacyMotionWindowDays(_ family: DeviceFamily) -> Int {
        family.estimatesSteps ? 60 : 14
    }

    // MARK: - Same scenario, same result

    func testSkinTempOffsetMatchesPreD3ValuePerBand() {
        for family in DeviceFamily.allCases {
            XCTAssertEqual(IntelligenceEngine.skinTempOffsetC(estimatesSteps: family.estimatesSteps),
                           legacySkinTempOffsetC(family), accuracy: 0.0001,
                           "\(family): skin-temp calibration moved — nights would re-score")
        }
        // Absolute anchors, so the oracle above can't drift with the code it mirrors.
        XCTAssertEqual(IntelligenceEngine.skinTempOffsetC(estimatesSteps: true), 28.5, accuracy: 0.0001)
        XCTAssertEqual(IntelligenceEngine.skinTempOffsetC(estimatesSteps: false), 0, accuracy: 0.0001)
    }

    func testMotionWindowMatchesPreD3ValuePerBand() {
        for family in DeviceFamily.allCases {
            XCTAssertEqual(IntelligenceEngine.motionWindowDays(estimatesSteps: family.estimatesSteps),
                           legacyMotionWindowDays(family),
                           "\(family): motion window moved — the dirtiness signature would change")
        }
        XCTAssertEqual(IntelligenceEngine.motionWindowDays(estimatesSteps: true), 60)
        XCTAssertEqual(IntelligenceEngine.motionWindowDays(estimatesSteps: false), 14)
    }

    // MARK: - The façade hands the engine the same bit the family carried

    func testWhoopModelFacadeMatchesTheProtocolRule() {
        for model in WhoopModel.allCases {
            XCTAssertEqual(model.estimatesSteps, model.deviceFamily.estimatesSteps,
                           "\(model): the façade must DERIVE the bit, never re-state it")
        }
        XCTAssertTrue(WhoopModel.whoop4.estimatesSteps)
        XCTAssertFalse(WhoopModel.whoop5mg.estimatesSteps)
    }

    /// The engine's default argument stands in for the pre-D3 `family: DeviceFamily = .whoop4`, so
    /// call sites that don't pass a band (tests, previews) keep 4.0 calibration exactly as before.
    @MainActor
    func testDefaultArgumentStillMeansWhoop4() {
        let repo = Repository(deviceId: "test-device")
        let engine = IntelligenceEngine(repo: repo, profile: ProfileStore(), deviceId: "test-device")
        XCTAssertEqual(engine.estimatesSteps, DeviceFamily.whoop4.estimatesSteps)
        // …and an explicitly-configured 5/MG engine keeps the other side of the switch.
        let five = IntelligenceEngine(repo: repo, profile: ProfileStore(), deviceId: "test-device",
                                      estimatesSteps: DeviceFamily.whoop5.estimatesSteps)
        XCTAssertFalse(five.estimatesSteps)
    }
}
