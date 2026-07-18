import XCTest
import CenitStore
@testable import StrandAnalytics

/// FER-154 — `SleepWindowClock.recent` turns the most recent sleep session into local
/// clock hours for the DiurnalDial's sleep band. Pure (clock injected), so every claim
/// — correct hours, honest midnight crossing, time-zone dependence, freshness gate,
/// most-recent selection, empty → nil — is asserted without an app or a strap.
final class SleepWindowClockTests: XCTestCase {

    private func utc() -> Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c
    }
    private func ts(_ cal: Calendar, _ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Int {
        Int(cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!.timeIntervalSince1970)
    }
    private func session(_ start: Int, _ end: Int) -> CachedSleepSession {
        CachedSleepSession(startTs: start, endTs: end, efficiency: nil, restingHr: nil, avgHrv: nil, stagesJSON: nil)
    }

    func testClockHoursAndHonestMidnightCrossing() {
        let cal = utc()
        let bed = ts(cal, 2026, 6, 16, 23, 15)   // 23:15
        let wake = ts(cal, 2026, 6, 17, 6, 45)    // 06:45 next morning
        let now = Date(timeIntervalSince1970: TimeInterval(ts(cal, 2026, 6, 17, 9, 0)))
        let w = SleepWindowClock.recent([session(bed, wake)], now: now, calendar: cal)
        XCTAssertNotNil(w)
        XCTAssertEqual(w!.bedtime, 23.25, accuracy: 0.0001)
        XCTAssertEqual(w!.wake, 6.75, accuracy: 0.0001)
        XCTAssertGreaterThan(w!.bedtime, w!.wake, "midnight crossing: bedtime > wake, NOT wrapped")
    }

    func testNilWhenNoSessions() {
        XCTAssertNil(SleepWindowClock.recent([], now: Date(), calendar: utc()))
    }

    func testNilWhenStale() {
        let cal = utc()
        let bed = ts(cal, 2026, 6, 10, 23, 0)
        let wake = ts(cal, 2026, 6, 11, 7, 0)
        let now = Date(timeIntervalSince1970: TimeInterval(ts(cal, 2026, 6, 16, 9, 0)))   // ~5 days later
        XCTAssertNil(SleepWindowClock.recent([session(bed, wake)], now: now, calendar: cal, freshnessHours: 36))
    }

    func testFreshWithinWindow() {
        let cal = utc()
        let bed = ts(cal, 2026, 6, 16, 23, 0)
        let wake = ts(cal, 2026, 6, 17, 7, 0)
        let now = Date(timeIntervalSince1970: TimeInterval(ts(cal, 2026, 6, 18, 14, 0)))   // ~31h after wake
        XCTAssertNotNil(SleepWindowClock.recent([session(bed, wake)], now: now, calendar: cal, freshnessHours: 36))
    }

    func testPicksMostRecentSession() {
        let cal = utc()
        let old = session(ts(cal, 2026, 6, 14, 23, 0), ts(cal, 2026, 6, 15, 7, 0))
        let new = session(ts(cal, 2026, 6, 16, 22, 30), ts(cal, 2026, 6, 17, 6, 30))
        let now = Date(timeIntervalSince1970: TimeInterval(ts(cal, 2026, 6, 17, 8, 0)))
        let w = SleepWindowClock.recent([new, old], now: now, calendar: cal)   // most-recent NOT last → exercises order-independence
        XCTAssertEqual(w!.bedtime, 22.5, accuracy: 0.0001)
        XCTAssertEqual(w!.wake, 6.5, accuracy: 0.0001)
    }

    func testTimeZoneDependence() {
        let utcCal = utc()
        var ny = Calendar(identifier: .gregorian); ny.timeZone = TimeZone(identifier: "America/New_York")!
        let bed = ts(utcCal, 2026, 6, 16, 23, 15)     // 23:15 UTC
        let wake = ts(utcCal, 2026, 6, 17, 6, 45)
        let now = Date(timeIntervalSince1970: TimeInterval(ts(utcCal, 2026, 6, 17, 9, 0)))
        let wUTC = SleepWindowClock.recent([session(bed, wake)], now: now, calendar: utcCal)!
        let wNY = SleepWindowClock.recent([session(bed, wake)], now: now, calendar: ny)!
        XCTAssertEqual(wUTC.bedtime, 23.25, accuracy: 0.0001)
        XCTAssertEqual(wNY.bedtime, 19.25, accuracy: 0.0001, "NY is UTC−4 in June, so 23:15 UTC = 19:15 local")
    }
}
