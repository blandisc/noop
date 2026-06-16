import XCTest
import SwiftUI
@testable import StrandDesign

/// FER-134 — the 24-hour Diurnal Dial. Pins the pure geometry the view composes:
/// the hour→angle mapping (noon up, midnight down, clockwise), the now-dot point,
/// the midnight-wrapping span (sleep band / day arc), and the opening-sweep offset.
final class DiurnalDialTests: XCTestCase {

    private func normalized(_ deg: Double) -> Double {
        let m = deg.truncatingRemainder(dividingBy: 360)
        return m < 0 ? m + 360 : m
    }

    // MARK: hour → angle (noon up, midnight down, time clockwise)

    func testNoonIsUp()       { XCTAssertEqual(DialGeometry.degrees(forHour: 12), -90,  accuracy: 1e-9) }
    func testEveningIsEast()  { XCTAssertEqual(DialGeometry.degrees(forHour: 18),   0,  accuracy: 1e-9) }
    func testMorningIsWest()  { XCTAssertEqual(DialGeometry.degrees(forHour: 6),  -180,  accuracy: 1e-9) }
    func testMidnightIsDown() {
        XCTAssertEqual(normalized(DialGeometry.degrees(forHour: 0)),  90, accuracy: 1e-6)
        XCTAssertEqual(normalized(DialGeometry.degrees(forHour: 24)), 90, accuracy: 1e-6)
    }

    // MARK: now-dot placement on the face

    func testNoonPointIsAboveCentre() {
        let c = CGPoint(x: 100, y: 100)
        let p = DialGeometry.point(forHour: 12, center: c, radius: 80)
        XCTAssertEqual(p.x, 100, accuracy: 0.001)
        XCTAssertEqual(p.y, 20,  accuracy: 0.001)   // smaller y == higher on screen
        XCTAssertLessThan(p.y, c.y)
    }
    func testMidnightPointIsBelowCentre() {
        let c = CGPoint(x: 100, y: 100)
        let p = DialGeometry.point(forHour: 0, center: c, radius: 80)
        XCTAssertEqual(p.x, 100, accuracy: 0.001)
        XCTAssertEqual(p.y, 180, accuracy: 0.001)
        XCTAssertGreaterThan(p.y, c.y)
    }
    func testMorningPointIsLeft() {
        let p = DialGeometry.point(forHour: 6, center: CGPoint(x: 100, y: 100), radius: 80)
        XCTAssertEqual(p.x, 20, accuracy: 0.001)
        XCTAssertEqual(p.y, 100, accuracy: 0.001)
    }
    func testEveningPointIsRight() {
        let p = DialGeometry.point(forHour: 18, center: CGPoint(x: 100, y: 100), radius: 80)
        XCTAssertEqual(p.x, 180, accuracy: 0.001)
        XCTAssertEqual(p.y, 100, accuracy: 0.001)
    }

    // MARK: "now dot correct per the device clock" — the two pure pieces the view
    // composes: local hour from the injected Date/Calendar, then the dial angle.

    func testNowDotMatchesClock() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let d = cal.date(from: DateComponents(year: 2026, month: 6, day: 16, hour: 15, minute: 30))!
        let hour = InstrumentoThemeEngine.localHour(of: d, calendar: cal)
        XCTAssertEqual(hour, 15.5, accuracy: 1e-6)
        XCTAssertEqual(DialGeometry.degrees(forHour: hour), 15.5 * 15 - 270, accuracy: 1e-9)
    }

    // MARK: span wraps midnight (sleep band + day arc)

    func testSleepSpanWrapsMidnight() { XCTAssertEqual(DialGeometry.spanHours(from: 23.5, to: 7.25), 7.75, accuracy: 1e-9) }
    func testDaySpanNoWrap()          { XCTAssertEqual(DialGeometry.spanHours(from: 6.2,  to: 19.8), 13.6, accuracy: 1e-9) }
    func testSpanZeroWhenEqual()      { XCTAssertEqual(DialGeometry.spanHours(from: 10,   to: 10),    0,   accuracy: 1e-9) }

    // MARK: opening sweep parks the dot at midnight before settling to "now"

    func testSweepStartParksDotAtMidnight() {
        let hour = 12.0
        let start = DialGeometry.sweepStartDegrees(forHour: hour)
        XCTAssertEqual(start, -180, accuracy: 1e-9)
        XCTAssertEqual(normalized(DialGeometry.degrees(forHour: hour) + start),
                       normalized(DialGeometry.degrees(forHour: 0)), accuracy: 1e-6)
    }

    // MARK: injected windows are value types

    func testSleepWindowEquatable() {
        XCTAssertEqual(SleepWindow(bedtime: 23, wake: 7), SleepWindow(bedtime: 23, wake: 7))
        XCTAssertNotEqual(SleepWindow(bedtime: 23, wake: 7), SleepWindow(bedtime: 22, wake: 7))
    }
}
