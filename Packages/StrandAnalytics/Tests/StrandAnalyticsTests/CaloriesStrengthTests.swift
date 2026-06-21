import XCTest
@testable import StrandAnalytics

/// `Calories.estimateStrengthCalories` — the MET-based active-energy estimate a guided strength
/// session writes to Apple Health (FER-390). The session records no per-second HR, so this is the
/// deterministic `kcal = MET × bodyMass × hours` model (Compendium of Physical Activities,
/// Ainsworth 2011). Covers the published cases, the empty/degenerate inputs, the missing-weight
/// fallback, and the duration clamp that keeps a bad end timestamp bounded.
final class CaloriesStrengthTests: XCTestCase {

    private func profile(weightKg: Double) -> UserProfile {
        UserProfile(weightKg: weightKg, heightCm: 175, age: 30, sex: "male")
    }

    func testModerate80kg45min() {
        // 3.5 MET × 80 kg × 0.75 h = 210 kcal
        let kcal = Calories.estimateStrengthCalories(durationSeconds: 45 * 60, profile: profile(weightKg: 80))
        XCTAssertEqual(kcal, 210.0, accuracy: 0.001)
    }

    func testModerate70kg60min() {
        // 3.5 MET × 70 kg × 1.0 h = 245 kcal
        let kcal = Calories.estimateStrengthCalories(durationSeconds: 60 * 60, profile: profile(weightKg: 70))
        XCTAssertEqual(kcal, 245.0, accuracy: 0.001)
    }

    func testZeroDurationIsZero() {
        XCTAssertEqual(Calories.estimateStrengthCalories(durationSeconds: 0, profile: profile(weightKg: 80)),
                       0.0, accuracy: 0.001)
    }

    func testNegativeDurationClampsToZero() {
        XCTAssertEqual(Calories.estimateStrengthCalories(durationSeconds: -500, profile: profile(weightKg: 80)),
                       0.0, accuracy: 0.001)
    }

    func testMissingWeightFallsBackTo70kg() {
        // weightKg 0 → 70 kg default: 3.5 × 70 × 0.5 h = 122.5 kcal
        let kcal = Calories.estimateStrengthCalories(durationSeconds: 30 * 60, profile: profile(weightKg: 0))
        XCTAssertEqual(kcal, 122.5, accuracy: 0.001)
    }

    func testDurationClampedToSixHours() {
        // 10 h of input clamps to 6 h: 3.5 × 70 × 6 = 1470 kcal
        let kcal = Calories.estimateStrengthCalories(durationSeconds: 10 * 3600, profile: profile(weightKg: 70))
        XCTAssertEqual(kcal, 1470.0, accuracy: 0.001)
    }
}
