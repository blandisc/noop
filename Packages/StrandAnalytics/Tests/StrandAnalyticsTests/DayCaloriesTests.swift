import XCTest
@testable import StrandAnalytics
import BiometricStreams

/// Tests Calories.estimateDayCalories — the APPROXIMATE whole-day HR-only energy estimate
/// (Keytel active + Harris–Benedict BMR) that backs DailyMetric.activeKcalEst for BLE-only
/// users. Pure-function tests; no DB. Not cloud/clinical parity. Mirrors the Android
/// DayCaloriesTest vectors value-for-value.
final class DayCaloriesTests: XCTestCase {

    private func hrDay(bpm: Int, n: Int) -> [HRSample] {
        (0..<n).map { HRSample(ts: $0, bpm: bpm) }
    }

    func testDayCaloriesEmptyIsZero() {
        XCTAssertEqual(
            Calories.estimateDayCalories([], profile: UserProfile(), hrmax: 190.0, restingHR: 55.0),
            0.0, accuracy: 1e-12)
    }

    func testDayCaloriesMatchesBoutAtGenuineExerciseHR() {
        // At genuine exercise-level HR that clears BOTH gates (bout 30%, day 50%), a dense 1 Hz
        // stream scores the same on both paths: the day path counts flat 1 s/sample (like the bout
        // at 1 Hz) and its resting-floor is inert above the gate. day-gate = 55 + 0.50*130 = 120;
        // 130 ≥ 120 → active on the day path too. FER-661 kept the paths equal here on purpose.
        let profile = UserProfile(weightKg: 80, heightCm: 180, age: 35, sex: "male")
        let hr = hrDay(bpm: 130, n: 600)
        let day = Calories.estimateDayCalories(hr, profile: profile, hrmax: 185.0, restingHR: 55.0)
        let bout = Calories.estimateBoutCalories(hr, profile: profile, hrmax: 185.0, restingHR: 55.0).0
        XCTAssertEqual(day, bout, accuracy: 1e-9)
    }

    func testDayCaloriesRestingDayIsLowerThanActiveDay() {
        // A whole day at resting HR burns far less than the same length all-active day,
        // and the resting-day total is positive (BMR floor).
        let profile = UserProfile(weightKg: 70, heightCm: 170, age: 30, sex: "nonbinary")
        // day activeThreshold = 55 + 0.50*(185-55) = 120 bpm; 60 < 120 (resting), 150 >= 120 (active).
        let restingDay = Calories.estimateDayCalories(hrDay(bpm: 60, n: 3600), profile: profile,
                                                      hrmax: 185.0, restingHR: 55.0)
        let activeDay = Calories.estimateDayCalories(hrDay(bpm: 150, n: 3600), profile: profile,
                                                     hrmax: 185.0, restingHR: 55.0)
        XCTAssertGreaterThan(restingDay, 0.0, "resting day must burn > 0 (BMR floor)")
        XCTAssertGreaterThan(activeDay, restingDay, "active day must exceed resting day")
    }

    func testDayGateHigherThanBoutGateForLowDaytimeHR() {
        // FER-661: low-intensity daytime HR between the two gates (30% bout, 50% day) counts as
        // ACTIVE on a bout but RESTING on the day path — the fix for the ~1000+ kcal day overcount.
        // resting 55, hrmax 185: bout gate = 55 + 0.30*130 = 94; day gate = 55 + 0.50*130 = 120.
        // 110 bpm is above the bout gate, below the day gate.
        let profile = UserProfile(weightKg: 80, heightCm: 180, age: 35, sex: "male")
        let hr = hrDay(bpm: 110, n: 3600)  // an hour of easy "walking" daytime HR
        let day = Calories.estimateDayCalories(hr, profile: profile, hrmax: 185.0, restingHR: 55.0)
        let bout = Calories.estimateBoutCalories(hr, profile: profile, hrmax: 185.0, restingHR: 55.0).0
        // The day path stays at the BMR resting rate for this HR; the bout applies Keytel → higher.
        XCTAssertLessThan(day, bout, "110 bpm must be resting on the day path but active on the bout")
        // And it equals a pure resting hour (no Keytel credit at all).
        let restingHour = Calories.estimateDayCalories(hrDay(bpm: 55, n: 3600), profile: profile,
                                                       hrmax: 185.0, restingHR: 55.0)
        XCTAssertEqual(day, restingHour, accuracy: 1e-9)
    }

    func testDayCaloriesCapsDegenerateInputAtOneDay() {
        // 90 000 samples (>24 h at 1 Hz) must not exceed the energy of a true
        // full day (86 400 s) — the raw API caps the seconds counted at one day.
        let profile = UserProfile(weightKg: 80, heightCm: 180, age: 35, sex: "male")
        let degenerate = Calories.estimateDayCalories(hrDay(bpm: 150, n: 90_000), profile: profile,
                                                      hrmax: 185.0, restingHR: 55.0)
        let fullDay = Calories.estimateDayCalories(hrDay(bpm: 150, n: 86_400), profile: profile,
                                                   hrmax: 185.0, restingHR: 55.0)
        XCTAssertEqual(degenerate, fullDay, accuracy: 1e-6,
                       "samples beyond one day must be ignored")
    }
}
