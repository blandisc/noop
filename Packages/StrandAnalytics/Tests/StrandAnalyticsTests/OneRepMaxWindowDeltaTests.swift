import XCTest
@testable import StrandAnalytics

/// FER-149 — the «≈ +N %» trend chip: fortnight-vs-fortnight change over a fixed 90-day window
/// anchored at HOY (never the last logged day). Table signed off by the CSO + CDO; endpoints below
/// are adapted to the exact quincena boundaries the pure function enforces, but every expected
/// number is the one the table specifies. A few cases pad in a harmless mid-window filler day (in
/// neither fortnight) purely to clear the documented ≥4-estimable-days-in-window minimum — it never
/// changes the two fortnight maxima (A/B) the table's numbers were computed from.
final class OneRepMaxWindowDeltaTests: XCTestCase {

    private static var utcCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    private let today = OneRepMaxWindowDeltaTests.dayFormatter.date(from: "2026-08-25")!
    private let todayKey = "2026-08-25"

    /// "dN" — N days before `today`, as the "yyyy-MM-dd" key the CSO's table shorthand means.
    private func d(_ daysAgo: Int) -> String {
        let date = Self.utcCalendar.date(byAdding: .day, value: -daysAgo, to: today)!
        return Self.dayFormatter.string(from: date)
    }

    private typealias Row = (day: String, weightKg: Double, reps: Int)

    func testHappyPathFortnightVsFortnight() {
        // d80 (1st quincena) → A = 76.0; d2 (last quincena) → B = 83.6; +10%. d50 is a harmless
        // middle-of-window filler for the ≥4-day minimum only.
        let sets: [Row] = [(d(80), 60, 8), (d(50), 1, 1), (d(40), 63, 8), (d(2), 66, 8)]
        XCTAssertEqual(OneRepMax.windowDeltaPercent(sets, todayKey: todayKey), 10)
    }

    func testRoundingToNearestInteger() {
        // A = 100×5 → 116.6667; B = best of (105×5, 100×8) → 126.6667; +8.571% rounds to +9%.
        let sets: [Row] = [
            (d(80), 100, 5), (d(50), 1, 1), (d(30), 1, 1),
            (d(1), 105, 5), (d(1), 100, 8),
        ]
        XCTAssertEqual(OneRepMax.windowDeltaPercent(sets, todayKey: todayKey), 9)
    }

    func testNegativeDelta() {
        // A = 120×5 → 140.0; B = 100×5 → 116.667; −16.667% rounds to −17%.
        let sets: [Row] = [(d(80), 120, 5), (d(50), 1, 1), (d(30), 1, 1), (d(3), 100, 5)]
        XCTAssertEqual(OneRepMax.windowDeltaPercent(sets, todayKey: todayKey), -17)
    }

    func testNoiseFloorExactBoundaryShowsChip() {
        // Exactly +2.0% — the guard is `>=` the floor, so the floor's own boundary must still
        // clear it and show the chip (same rep count both ends, so the Epley factor cancels and
        // the raw-weight ratio IS the estimated-kg ratio: 100→102 is exactly +2.0%).
        let sets: [Row] = [(d(80), 100, 5), (d(50), 1, 1), (d(30), 1, 1), (d(2), 102, 5)]
        XCTAssertEqual(OneRepMax.windowDeltaPercent(sets, todayKey: todayKey), 2)
    }

    func testNoiseFloorSuppressesTinyChange() {
        // +1.5% never clears the 2.0-point floor → silence, not "+2 %" or "0 %".
        let sets: [Row] = [(d(80), 100, 5), (d(50), 1, 1), (d(30), 1, 1), (d(2), 101.5, 5)]
        XCTAssertNil(OneRepMax.windowDeltaPercent(sets, todayKey: todayKey))
    }

    func testOnlyOneFortnightPopulatedStaysSilent() {
        // Nothing in the first quincena at all → silence, regardless of how much data the last
        // quincena has.
        let sets: [Row] = [(d(5), 100, 5)]
        XCTAssertNil(OneRepMax.windowDeltaPercent(sets, todayKey: todayKey))
    }

    func testEmptyWindowStaysSilent() {
        // Both points are older than 89 days — outside the window entirely.
        let sets: [Row] = [(d(100), 100, 5), (d(95), 100, 5)]
        XCTAssertNil(OneRepMax.windowDeltaPercent(sets, todayKey: todayKey))
    }

    func testWindowStartBoundaryDayCounts() {
        // d89 is exactly the window's oldest inclusive day — it counts.
        let sets: [Row] = [(d(89), 100, 5), (d(40), 1, 1), (d(20), 1, 1), (d(0), 105, 5)]
        XCTAssertEqual(OneRepMax.windowDeltaPercent(sets, todayKey: todayKey), 5)
    }

    func testMidWindowSpikeNeverLeaksIntoTheFortnights() {
        // The 140×1 spike sits in neither fortnight (documented: it lives in RECORDS, not here).
        // Both fortnights independently resolve to the SAME estimate → 0% → silence.
        let sets: [Row] = [(d(80), 100, 5), (d(60), 1, 1), (d(40), 140, 1), (d(2), 100, 5)]
        XCTAssertNil(OneRepMax.windowDeltaPercent(sets, todayKey: todayKey))
    }

    func testUnitInvariantKgVsLbRoundTrip() {
        // The function is kg-internal and unit-blind by construction; round-tripping every weight
        // through the kg↔lb conversion (as the caller does before this function ever sees the data)
        // must not move the result.
        let kgPerLb = 0.45359237
        let raw: [Row] = [(d(80), 60, 8), (d(50), 1, 1), (d(40), 63, 8), (d(2), 66, 8)]
        let roundTripped: [Row] = raw.map { row in
            let lb = row.weightKg / kgPerLb
            return (day: row.day, weightKg: lb * kgPerLb, reps: row.reps)
        }
        XCTAssertEqual(OneRepMax.windowDeltaPercent(raw, todayKey: todayKey), 10)
        XCTAssertEqual(OneRepMax.windowDeltaPercent(roundTripped, todayKey: todayKey),
                       OneRepMax.windowDeltaPercent(raw, todayKey: todayKey))
    }

    func testNonEstimableSetsDontCountTowardTheMinimum() {
        // 0 kg is not estimable (dropped by `dailySparkline` itself) — only 1 real estimable day
        // remains, short of the ≥4 minimum.
        let sets: [Row] = [(d(80), 0, 5), (d(10), 100, 5)]
        XCTAssertNil(OneRepMax.windowDeltaPercent(sets, todayKey: todayKey))
    }
}
