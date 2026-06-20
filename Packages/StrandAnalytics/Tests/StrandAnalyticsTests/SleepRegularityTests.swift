import XCTest
import Foundation
@testable import StrandAnalytics

final class SleepRegularityTests: XCTestCase {

    // A fixed UTC calendar so weekday + local-noon math is deterministic across machines.
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    /// Build a NightTiming from a base day (yyyy-MM-dd, UTC) with an onset clock hour (can be ≥24 for
    /// after-midnight) and a sleep length in hours.
    private func night(_ day: String, onsetHour: Double, hours: Double) -> SleepRegularity.NightTiming {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")!
        f.dateFormat = "yyyy-MM-dd"
        let base = f.date(from: day)!
        let onset = Int(base.timeIntervalSince1970) + Int(onsetHour * 3600)
        let wake = onset + Int(hours * 3600)
        return SleepRegularity.NightTiming(onset: onset, wake: wake)
    }

    // MARK: - Gate: fewer than 7 nights → nil (calibration, not a fake number)

    func testFewerThanMinNightsReturnsNil() {
        let nights = (0..<6).map { i in
            night(String(format: "2026-03-%02d", i + 1), onsetHour: 23, hours: 8)
        }
        XCTAssertNil(SleepRegularity.compute(nights, calendar: cal))
    }

    func testExactlyMinNightsIsPreliminary() {
        let nights = (0..<7).map { i in
            night(String(format: "2026-03-%02d", i + 1), onsetHour: 23, hours: 8)
        }
        let r = SleepRegularity.compute(nights, calendar: cal)
        XCTAssertNotNil(r)
        XCTAssertEqual(r?.nights, 7)
        XCTAssertTrue(r?.preliminary == true, "7 nights is below the 14-night stable threshold")
    }

    func testFourteenNightsIsStable() {
        let nights = (0..<14).map { i in
            night(String(format: "2026-03-%02d", i + 1), onsetHour: 23, hours: 8)
        }
        let r = SleepRegularity.compute(nights, calendar: cal)
        XCTAssertEqual(r?.nights, 14)
        XCTAssertFalse(r?.preliminary == true, "14 nights drops the preliminary flag")
    }

    // MARK: - Midnight crossing: 23:30 and 00:30 must average ~midnight, not ~11:30

    func testMidnightCrossingAveragesCleanly() {
        // Alternate onsets at 23:30 and 00:30 (next day) every night for 10 nights. The mid-sleep
        // points must cluster tightly (~1 h apart), NOT split by ~24 h. A naive clock-hour average
        // would explode the SD here.
        var nights: [SleepRegularity.NightTiming] = []
        for i in 0..<10 {
            let onsetHour = (i % 2 == 0) ? 23.5 : 24.5   // 24.5 = 00:30 the next calendar day
            nights.append(night(String(format: "2026-03-%02d", i + 1), onsetHour: onsetHour, hours: 8))
        }
        let r = SleepRegularity.compute(nights, calendar: cal)!
        // Two onset clusters 60 min apart, 8 h each → mids 60 min apart → SD well under 45 min.
        XCTAssertLessThan(r.midSleepSDMinutes, 45,
                          "midnight-crossing onsets must NOT inflate the SD; got \(r.midSleepSDMinutes)")
        XCTAssertGreaterThan(r.score, 60, "a ±30 min schedule should still read fairly steady")
    }

    // MARK: - Regular vs irregular: SD ordering + score ordering

    func testRegularBeatsIrregular() {
        let steady = (0..<14).map { i in
            night(String(format: "2026-03-%02d", i + 1), onsetHour: 23, hours: 8)
        }
        // Irregular: onset swings between 21:00 and 02:00.
        let chaotic = (0..<14).map { i -> SleepRegularity.NightTiming in
            let onset = (i % 2 == 0) ? 21.0 : 26.0   // 26.0 = 02:00 next day
            return night(String(format: "2026-03-%02d", i + 1), onsetHour: onset, hours: 8)
        }
        let rSteady = SleepRegularity.compute(steady, calendar: cal)!
        let rChaotic = SleepRegularity.compute(chaotic, calendar: cal)!

        XCTAssertEqual(rSteady.midSleepSDMinutes, 0, accuracy: 1e-6, "identical nights → SD 0")
        XCTAssertGreaterThan(rChaotic.midSleepSDMinutes, rSteady.midSleepSDMinutes)
        XCTAssertGreaterThan(rSteady.score, rChaotic.score)
        XCTAssertEqual(rSteady.score, 100)
    }

    // MARK: - Weekend shift (social jetlag)

    func testWeekendShiftDetectsLaterWeekends() {
        // Two full weeks. Weekday onset 23:00, Fri/Sat onset 01:00 (2 h later) → ~120 min shift.
        // 2026-03-02 is a Monday (UTC). Friday = 03-06, Saturday = 03-07, then 03-13 / 03-14.
        var nights: [SleepRegularity.NightTiming] = []
        for dayNum in 2...15 {
            let day = String(format: "2026-03-%02d", dayNum)
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(identifier: "UTC")!
            f.dateFormat = "yyyy-MM-dd"
            let wd = cal.component(.weekday, from: f.date(from: day)!)
            let isWeekend = (wd == 6 || wd == 7)   // Fri or Sat onset
            nights.append(night(day, onsetHour: isWeekend ? 25.0 : 23.0, hours: 8))
        }
        let r = SleepRegularity.compute(nights, calendar: cal)!
        XCTAssertNotNil(r.weekendShiftMinutes)
        XCTAssertEqual(r.weekendShiftMinutes ?? 0, 120, accuracy: 5,
                       "Fri/Sat onsets 2 h later than weekdays → ~120 min social jetlag")
    }

    func testWeekendShiftNilWhenOneSideTooThin() {
        // 7 consecutive weekday nights (no Fri/Sat) → weekend side empty → shift nil.
        // 2026-03-02 Mon … 2026-03-05 Thu is 4 weekdays; pad to 7 with the next Mon–Wed.
        let days = ["2026-03-02", "2026-03-03", "2026-03-04", "2026-03-05",
                    "2026-03-09", "2026-03-10", "2026-03-11"]   // all Mon–Thu
        let nights = days.map { night($0, onsetHour: 23, hours: 8) }
        let r = SleepRegularity.compute(nights, calendar: cal)!
        XCTAssertNil(r.weekendShiftMinutes, "no weekend nights → shift undefined")
    }

    // MARK: - Naps must not degrade schedule regularity (FER-298)
    //
    // A nap is a short daytime sleep whose mid-point sits ~11 h from the nocturnal mid-sleep — near
    // anti-phase on the 24 h clock circle (Wittmann et al. 2006; Mardia & Jupp 2000). Counted as a "night"
    // it would explode the circular SD. The "main night" gate (≥ 3 h, SleepMainNight) drops it, so a
    // perfectly steady sleeper stays steady. Fixed vector: 13 identical nights + one 2 h afternoon nap
    // → the same score as the 13 nights alone (regression of the reported SD 126.9 / score 0).

    func testNapDoesNotDegradeRegularity() {
        let steady = (0..<13).map { i in
            night(String(format: "2026-03-%02d", i + 1), onsetHour: 23, hours: 8)
        }
        let nap = night("2026-03-07", onsetHour: 15, hours: 2)   // 15:00–17:00, ~11 h off the night mid

        let withoutNap = SleepRegularity.compute(steady, calendar: cal)!
        let withNap = SleepRegularity.compute(steady + [nap], calendar: cal)!

        XCTAssertEqual(withNap.midSleepSDMinutes, withoutNap.midSleepSDMinutes, accuracy: 1e-6,
                       "a 2 h nap must not change the mid-sleep SD")
        XCTAssertEqual(withNap.score, withoutNap.score, "a 2 h nap must not change the score")
        XCTAssertEqual(withNap.score, 100, "13 identical nights stay perfectly regular despite the nap")
        XCTAssertEqual(withNap.nights, 13, "the nap is excluded from the window")
    }

    // MARK: - Rolling window: only the most recent 14 nights count

    func testUsesOnlyMostRecentWindow() {
        // 30 nights: the oldest 16 are chaotic, the newest 14 are perfectly steady. The result must
        // reflect ONLY the steady tail (rolling window), so SD ≈ 0.
        var nights: [SleepRegularity.NightTiming] = []
        for i in 0..<16 {   // old + chaotic
            let onset = (i % 2 == 0) ? 20.0 : 27.0
            nights.append(night(String(format: "2026-02-%02d", i + 1), onsetHour: onset, hours: 7))
        }
        for i in 0..<14 {   // recent + steady
            nights.append(night(String(format: "2026-03-%02d", i + 1), onsetHour: 23, hours: 8))
        }
        let r = SleepRegularity.compute(nights, calendar: cal)!
        XCTAssertEqual(r.nights, 14)
        XCTAssertEqual(r.midSleepSDMinutes, 0, accuracy: 1e-6,
                       "only the steady most-recent 14 nights should drive the SD")
    }

    func testCircularSDPerfectScheduleIsPositiveZero() {
        // Identical points (r == 1) must yield +0.0, never -0.0 (which the UI
        // can render as "-0 min").
        let sd = SleepRegularity.circularSDMinutes([480, 480, 480, 480])
        XCTAssertEqual(sd, 0)
        XCTAssertFalse(sd.sign == .minus, "circularSDMinutes must not return -0.0")
    }
}
