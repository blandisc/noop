import XCTest
@testable import StrandAnalytics
import WhoopProtocol

/// Unit tests for the daily-steps derivation in AnalyticsEngine.analyzeDay: cumulative-counter
/// delta summation, u16 wraparound, sub-2-sample and cross-day filtering, and nil-when-no-movement.
/// No DB; pure-function test. step_motion_counter@57 is a CUMULATIVE u16 counter, so the daily total
/// is the sum of positive consecutive deltas (APPROXIMATE — @57 semantics unverified vs the app).
/// A per-record delta >= 512 is a sync-gap / reboot boundary, not real steps, and is dropped
/// (FER-658, upstream #132/#276/#316).
final class StepsDailyTests: XCTestCase {

    private let profile = UserProfile()

    // A timestamp safely inside UTC day 2026-01-02 (2026-01-02T12:00:00Z = 1767355200).
    private let dayUtc = "2026-01-02"
    private let noonUtc = 1_767_355_200

    private func step(_ tsOffsetSec: Int, _ counter: Int) -> StepSample {
        StepSample(ts: noonUtc + tsOffsetSec, counter: counter)
    }

    private func stepsFor(_ samples: [StepSample]) -> Int? {
        AnalyticsEngine.analyzeDay(day: dayUtc, steps: samples, profile: profile).daily.steps
    }

    func testSumsPositiveConsecutiveDeltas() {
        // counters 100 -> 150 -> 220 => deltas 50 + 70 = 120
        let s = [step(0, 100), step(60, 150), step(120, 220)]
        XCTAssertEqual(stepsFor(s), 120)
    }

    func testHandlesU16Wraparound() {
        // 65500 -> 30 wraps: delta = 30 - 65500 = -65470, +65536 => 66 real steps; then 30 -> 90 => 60.
        let s = [step(0, 65_500), step(60, 30), step(120, 90)]
        XCTAssertEqual(stepsFor(s), 66 + 60)
    }

    func testFewerThanTwoSamplesIsNil() {
        XCTAssertNil(stepsFor([]))
        XCTAssertNil(stepsFor([step(0, 500)]))
    }

    func testNoForwardMovementIsNil() {
        // Flat counter across the day => no positive delta => nil (not 0).
        let s = [step(0, 1_000), step(60, 1_000), step(120, 1_000)]
        XCTAssertNil(stepsFor(s))
    }

    func testDropsImplausibleResetDeltaAsReboot() {
        // 100 -> 400 (=300 real steps), then 400 -> 50 is a counter reset/reboot: the
        // wrap-corrected delta is 65186, implausibly large, so it is dropped rather than
        // injecting tens of thousands of phantom steps. Only the 300 counts.
        let s = [step(0, 100), step(60, 400), step(120, 50)]
        XCTAssertEqual(stepsFor(s), 300)
    }

    func testDropsSyncGapDeltaAboveThreshold() {
        // A gap between sync sessions jumps the counter by thousands without a wrap. The
        // 100 -> 5_000 delta (4_900) is a gap boundary, not steps — it must NOT count.
        // The surrounding normal deltas (150 and 200) must still count. (FER-658)
        let s = [step(0, 100), step(60, 250), step(7_200, 5_000), step(7_260, 5_200)]
        XCTAssertEqual(stepsFor(s), 150 + 200)
    }

    func testGateBoundaryAt512() {
        // 511 is the largest per-record delta that still counts; 512 is dropped (gap/reset).
        XCTAssertEqual(stepsFor([step(0, 0), step(60, 511)]), 511)
        XCTAssertNil(stepsFor([step(0, 0), step(60, 512)]))
    }

    func testIgnoresSamplesOutsideTheTargetDay() {
        // One sample 36h before the day (in the analytics window but a different UTC day)
        // must be excluded.
        let s = [step(-36 * 3_600, 5_000), step(0, 100), step(60, 300)]
        XCTAssertEqual(stepsFor(s), 200)  // only the in-day 100 -> 300 delta counts
    }

    func testDayStepsOverrideCountsFullCalendarDay() {
        // The night-window `steps` only sees the early part of the day; the full calendar-day
        // stream `daySteps` also carries the late-evening samples. When daySteps is supplied
        // the daily total must come from it, so late-day movement is NOT dropped (the past-day
        // undercount fix).
        let nightWindow = [step(0, 100), step(60, 300)]  // early only
        let fullDay = [
            step(0, 100), step(60, 300),     // morning: 200
            step(10 * 3_600, 700),           // evening samples only in the full-day stream
            step(11 * 3_600, 1_100),
        ]
        let total = AnalyticsEngine.analyzeDay(
            day: dayUtc, steps: nightWindow, daySteps: fullDay, profile: profile).daily.steps
        // deltas over the full day: 100->300=200, 300->700=400, 700->1100=400 => 1000.
        XCTAssertEqual(total, 1_000)
    }

    func testDayStepsNilFallsBackToWindowSteps() {
        // No calendar-day stream supplied (pure-function callers / old tests) -> total falls
        // back to the night-window `steps` exactly as before.
        let s = [step(0, 100), step(60, 150), step(120, 220)]  // 50 + 70 = 120
        XCTAssertEqual(AnalyticsEngine.analyzeDay(day: dayUtc, steps: s, profile: profile).daily.steps,
                       120)
    }

    // MARK: - stepTicksPerStep calibration (FER-665 — 5/MG native counter over-count)

    private func stepsFor(_ samples: [StepSample], ticksPerStep: Double) -> Int? {
        let p = UserProfile(stepTicksPerStep: ticksPerStep)
        return AnalyticsEngine.analyzeDay(day: dayUtc, steps: samples, profile: p).daily.steps
    }

    func testDefaultDivisorIsRawPassThrough() {
        // The default 1.0 must not change the count at all (no behaviour change until calibrated).
        let s = [step(0, 100), step(60, 250)]  // 150 raw
        XCTAssertEqual(stepsFor(s, ticksPerStep: 1.0), 150)
    }

    func testDivisorScalesDownAnOverCount() {
        // A 5/MG that over-counts ~2× is corrected by a divisor of 2.0: 1000 raw ticks -> 500 steps.
        let s = [step(0, 0), step(60, 400), step(120, 700), step(180, 1_000)]  // 400+300+300 = 1000 raw
        XCTAssertEqual(stepsFor(s, ticksPerStep: 2.0), 500)
    }

    func testDivisorRoundsToNearestStep() {
        // 150 raw / 4.0 = 37.5 -> rounds to 38.
        let s = [step(0, 0), step(60, 150)]
        XCTAssertEqual(stepsFor(s, ticksPerStep: 4.0), 38)
    }

    func testDivisorFlooredAtHalfSoItCannotInflate() {
        // A degenerate divisor below the 0.5 floor is clamped to 0.5 (raw ×2 at most), never a
        // huge multiplier: 100 raw / 0.1-clamped-to-0.5 = 200, not 1000.
        let s = [step(0, 0), step(60, 100)]
        XCTAssertEqual(stepsFor(s, ticksPerStep: 0.1), 200)
    }
}
