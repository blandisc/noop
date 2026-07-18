import XCTest
@testable import CenitStore

/// Pins the canonical day-key contract (FER-754): POSIX digits, UTC round-trip, and the deliberate
/// write-local / read-UTC split that the app's phantom-row bugs (FER-224/226, FER-630) hang on.
final class DayKeyTests: XCTestCase {

    func testUTCRoundTripIsExactInverse() {
        for key in ["2023-11-14", "2028-02-29", "2026-07-06", "2030-12-31"] {
            let date = DayKey.parseUTC(key)
            XCTAssertNotNil(date, key)
            XCTAssertEqual(DayKey.utc(date!), key, "utc(parseUTC(k)) must be identity")
        }
        XCTAssertNil(DayKey.parseUTC("not-a-day"))
    }

    func testParseUTCAnchorsAtUTCMidnight() {
        let d = DayKey.parseUTC("2026-07-06")!
        XCTAssertEqual(d.timeIntervalSince1970, 1_783_296_000, accuracy: 0.5)  // 2026-07-06T00:00:00Z
    }

    func testFormattersUsePosixDigits() {
        // en_US_POSIX pins ASCII digits and the Gregorian calendar regardless of device locale —
        // the copy this consolidates in IllnessNotifier had no locale at all.
        let d = Date(timeIntervalSince1970: 1_783_296_000)
        XCTAssertEqual(DayKey.utc(d), "2026-07-06")
        XCTAssertTrue(DayKey.local(d).range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil)
    }

    func testLocalAndUTCDisagreeWestOfGreenwichAtUTCMidnight() {
        // The reason the split exists: a UTC-midnight instant is still "yesterday" in CDMX.
        // Only meaningful when the test host runs west of UTC; assert the general contract instead:
        // local(d) is the key of d in the CURRENT zone, utc(d) in UTC — they may differ, and when
        // they do, local is exactly one day behind for a negative-offset zone.
        let utcMidnight = DayKey.parseUTC("2026-07-06")!
        let localKey = DayKey.local(utcMidnight)
        let secondsFromGMT = TimeZone.current.secondsFromGMT(for: utcMidnight)
        if secondsFromGMT < 0 {
            XCTAssertEqual(localKey, "2026-07-05", "west of UTC, a UTC-midnight instant is the prior civil day")
        } else if secondsFromGMT == 0 {
            XCTAssertEqual(localKey, "2026-07-06")
        }
    }

    func testUTCCalendarWholeDayArithmetic() {
        let a = DayKey.parseUTC("2026-02-27")!, b = DayKey.parseUTC("2026-03-02")!
        XCTAssertEqual(DayKey.utcCalendar.dateComponents([.day], from: a, to: b).day, 3)
    }
}
