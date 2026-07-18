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

    // A timestamp safely inside UTC day 2026-01-02 (2026-01-02T12:00:00Z).
    private let dayUtc = "2026-01-02"
    private let noonUtc = 1_767_355_200

    private func hr(_ tsOffsetSec: Int, _ bpm: Int) -> HRSample {
        HRSample(ts: noonUtc + tsOffsetSec, bpm: bpm)
    }

    func testAnalyzeDayCaloriesIgnoreAdjacentDayHr() throws {
        // analyzeDay must filter HR to the target UTC day before summing calories — the
        // IntelligenceEngine read window spans ~42h, so adjacent-day HR must NOT inflate the
        // day's activeKcalEst (the critical "full-window double-count" regression).
        let inDay = (0..<600).map { hr($0, 120) }
        // Same in-day HR plus 600 samples ~36h earlier (a different UTC day, inside the window).
        let withAdjacent = inDay + (0..<600).map { hr(-36 * 3_600 - $0, 120) }
        let a = try XCTUnwrap(AnalyticsEngine.analyzeDay(
            day: dayUtc, hr: inDay, profile: UserProfile()).daily.activeKcalEst)
        let b = try XCTUnwrap(AnalyticsEngine.analyzeDay(
            day: dayUtc, hr: withAdjacent, profile: UserProfile()).daily.activeKcalEst)
        XCTAssertEqual(a, b, accuracy: 1e-6, "adjacent-day HR must not change the day's calories")
    }

    func testAnalyzeDayDayHrCoversFullCalendarDay() throws {
        // Simulate the past-day clip: the night-window HR only reaches midday; the full
        // calendar-day HR also has the afternoon. activeKcalEst must use dayHr when supplied,
        // so the full-day total exceeds the clipped night-window total (the undercount fix).
        let nightWindow = (0..<600).map { hr($0, 120) }
        let fullDay = nightWindow + (0..<600).map { hr(3 * 3_600 + $0, 120) }
        let clipped = try XCTUnwrap(AnalyticsEngine.analyzeDay(
            day: dayUtc, hr: nightWindow, profile: UserProfile()).daily.activeKcalEst)
        let full = try XCTUnwrap(AnalyticsEngine.analyzeDay(
            day: dayUtc, hr: nightWindow, dayHr: fullDay, profile: UserProfile()).daily.activeKcalEst)
        XCTAssertGreaterThan(full, clipped,
                             "full calendar-day calories must exceed the clipped night-window total")
    }

    func testAnalyzeDayDayHrNilFallsBackToWindowHr() throws {
        // With no calendar-day stream, the total falls back to the window `hr` — identical to
        // passing that same window explicitly as dayHr (the (dayHr ?? hr) fallback).
        let window = (0..<600).map { hr($0, 120) }
        let fallback = try XCTUnwrap(AnalyticsEngine.analyzeDay(
            day: dayUtc, hr: window, profile: UserProfile()).daily.activeKcalEst)
        let explicit = try XCTUnwrap(AnalyticsEngine.analyzeDay(
            day: dayUtc, hr: window, dayHr: window, profile: UserProfile()).daily.activeKcalEst)
        XCTAssertEqual(fallback, explicit, accuracy: 1e-9)
    }
}
