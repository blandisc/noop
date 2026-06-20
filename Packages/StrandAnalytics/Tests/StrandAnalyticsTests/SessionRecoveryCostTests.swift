import XCTest
import Foundation
@testable import StrandAnalytics

final class SessionRecoveryCostTests: XCTestCase {

    // MARK: - Honest gate (no strap → nil, UI does not invent a cost)

    func testNilWhenNoSignal() {
        XCTAssertNil(SessionRecoveryCost.cost(sessionStrain: nil, meanHRRPct: nil))
    }

    // MARK: - By session strain

    func testStrainLight() {
        let r = SessionRecoveryCost.cost(sessionStrain: 5)
        XCTAssertEqual(r?.band, .light)
        XCTAssertEqual(r?.basis, .sessionStrain)
    }

    func testStrainModerate() {
        XCTAssertEqual(SessionRecoveryCost.cost(sessionStrain: 11)?.band, .moderate)
    }

    func testStrainHigh() {
        XCTAssertEqual(SessionRecoveryCost.cost(sessionStrain: 17)?.band, .high)
    }

    func testStrainBoundaries() {
        // 8 → moderate (lightMax is exclusive upper bound of light).
        XCTAssertEqual(SessionRecoveryCost.cost(sessionStrain: SessionRecoveryCost.strainLightMax)?.band, .moderate)
        // 14 → high.
        XCTAssertEqual(SessionRecoveryCost.cost(sessionStrain: SessionRecoveryCost.strainModerateMax)?.band, .high)
        // just below 8 → light.
        XCTAssertEqual(SessionRecoveryCost.cost(sessionStrain: SessionRecoveryCost.strainLightMax - 0.1)?.band, .light)
    }

    // MARK: - Fallback by mean %HRR (strain nil)

    func testHRRLight() {
        let r = SessionRecoveryCost.cost(sessionStrain: nil, meanHRRPct: 40)
        XCTAssertEqual(r?.band, .light)
        XCTAssertEqual(r?.basis, .meanHRR)
    }

    func testHRRModerate() {
        XCTAssertEqual(SessionRecoveryCost.cost(sessionStrain: nil, meanHRRPct: 60)?.band, .moderate)
    }

    func testHRRHigh() {
        XCTAssertEqual(SessionRecoveryCost.cost(sessionStrain: nil, meanHRRPct: 80)?.band, .high)
    }

    func testHRRBoundaries() {
        XCTAssertEqual(SessionRecoveryCost.cost(sessionStrain: nil, meanHRRPct: SessionRecoveryCost.hrrLightMax)?.band, .moderate)
        XCTAssertEqual(SessionRecoveryCost.cost(sessionStrain: nil, meanHRRPct: SessionRecoveryCost.hrrModerateMax)?.band, .high)
    }

    // MARK: - Precedence & ExerciseSession convenience

    func testStrainWinsOverHRR() {
        // High %HRR but a light strain → strain drives the band, basis is sessionStrain.
        let r = SessionRecoveryCost.cost(sessionStrain: 5, meanHRRPct: 95)
        XCTAssertEqual(r?.band, .light)
        XCTAssertEqual(r?.basis, .sessionStrain)
    }

    func testCostForExerciseSession() {
        let session = ExerciseSession(
            start: 0, end: 1800, avgHR: 130, peakHR: 160, strain: 11,
            durationS: 1800, zoneTimePct: [:], avgHRRPct: 65,
            hrmax: 190, hrmaxSource: "tanaka", caloriesKcal: nil, caloriesKJ: nil)
        let r = SessionRecoveryCost.cost(for: session)
        XCTAssertEqual(r?.band, .moderate)
        XCTAssertEqual(r?.basis, .sessionStrain)
    }

    func testCostForSessionWithoutStrapIsNil() {
        let session = ExerciseSession(
            start: 0, end: 1800, avgHR: 0, peakHR: 0, strain: nil,
            durationS: 1800, zoneTimePct: [:], avgHRRPct: nil,
            hrmax: nil, hrmaxSource: "unknown", caloriesKcal: nil, caloriesKJ: nil)
        XCTAssertNil(SessionRecoveryCost.cost(for: session))
    }
}
