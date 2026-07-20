import XCTest
@testable import StrandAnalytics

final class AutonomicTrendTests: XCTestCase {

    private func nights(_ vals: [(String, Double)]) -> [(day: String, rmssdMs: Double)] {
        vals.map { (day: $0.0, rmssdMs: $0.1) }
    }

    /// Generate consecutive day strings starting at a base, count nights of constant value.
    private func constantNights(count: Int, value: Double = 50.0,
                                prefix: String = "2026-01-", startDay: Int = 1) -> [(String, Double)] {
        (0..<count).map { i in
            let d = startDay + i
            let dayStr = String(format: "%@%02d", prefix, d)
            return (dayStr, value)
        }
    }

    /// Sequential days from a start YYYY-MM-DD style using simple day numbers in January 2026.
    private func janDays(from day: Int, count: Int, value: Double = 50.0) -> [(String, Double)] {
        (0..<count).map { i in
            (String(format: "2026-01-%02d", day + i), value)
        }
    }

    func test13NightsCalibrating() {
        // 13 dense nights Jan 1–13; asOf=13, recentCutoff=11 → recent days 11,12,13 = 3
        let ns = janDays(from: 1, count: 13, value: 50)
        let r = AutonomicTrend.evaluate(nights: nights(ns), asOf: "2026-01-13",
                                        recentCutoff: "2026-01-11")
        XCTAssertEqual(r.confidence, .calibrating)
        XCTAssertNil(r.direction)
        XCTAssertEqual(r.spark, [])
        XCTAssertNil(r.z7d)
        XCTAssertEqual(r.nightsToTrend, 1)
        XCTAssertEqual(r.nightsUsable, 13)
        XCTAssertEqual(r.recentDenseNights, 3)
    }

    func test14NightsBuilding() {
        let ns = janDays(from: 1, count: 14, value: 50)
        let r = AutonomicTrend.evaluate(nights: nights(ns), asOf: "2026-01-14",
                                        recentCutoff: "2026-01-12")
        XCTAssertEqual(r.confidence, .building)
        XCTAssertEqual(r.direction, .inBase)
        XCTAssertNil(r.z7d)
        XCTAssertEqual(r.spark, [])
        XCTAssertEqual(r.nightsToTrend, 0)
        XCTAssertEqual(r.nightsUsable, 14)
        XCTAssertGreaterThanOrEqual(r.recentDenseNights, 3)
    }

    func test21NightsSolid() {
        // Jan only has 31 days — use Nov 2025 for base stretch
        var ns: [(String, Double)] = []
        // 21 nights: 2025-12-12 .. 2026-01-01 style — just use sequential with format
        for i in 0..<21 {
            // days 2026-01-01 through 2026-01-21
            ns.append((String(format: "2026-01-%02d", i + 1), 50.0 + Double(i % 5)))
        }
        let r = AutonomicTrend.evaluate(nights: nights(ns), asOf: "2026-01-21",
                                        recentCutoff: "2026-01-15")
        XCTAssertEqual(r.confidence, .solid)
        XCTAssertNotNil(r.direction)
        XCTAssertNotNil(r.z7d)
        XCTAssertEqual(r.spark.count, 14)
        XCTAssertEqual(r.nightsUsable, 21)
    }

    func testRecentGateFewerThan3KeepsBuildingButNilDirection() {
        // 14 total dense nights, but only 2 inside recent window
        // nights Jan 1–14; recentCutoff = Jan 13 → only 13,14 = 2 recent
        let ns = janDays(from: 1, count: 14, value: 50)
        let r = AutonomicTrend.evaluate(nights: nights(ns), asOf: "2026-01-14",
                                        recentCutoff: "2026-01-13")
        // confidence from total-count ternary: 14 >= 14 and 14 < 21 → .building
        XCTAssertEqual(r.confidence, .building)
        XCTAssertNil(r.direction)
        XCTAssertNil(r.z7d)
        XCTAssertEqual(r.recentDenseNights, 2)
        XCTAssertEqual(r.nightsUsable, 14)
    }

    func testLastNightDense() {
        let ns = janDays(from: 1, count: 14, value: 50)
        let withAsOf = AutonomicTrend.evaluate(nights: nights(ns), asOf: "2026-01-14",
                                               recentCutoff: "2026-01-12")
        XCTAssertEqual(withAsOf.lastNightDense, true)

        let withoutAsOf = AutonomicTrend.evaluate(nights: nights(ns), asOf: "2026-01-20",
                                                  recentCutoff: "2026-01-12")
        // no dense night on asOf → nil
        XCTAssertNil(withoutAsOf.lastNightDense)
    }

    func testPastOnlyZGolden() {
        // 40 old nights of 50.0 ms before recentCutoff, + 3 recent [40, 50, 60]
        // recentCutoff = "2026-01-15", asOf = "2026-01-21"
        var ns: [(String, Double)] = []
        // 40 old days starting 2025-11-01
        // Use day arithmetic: Nov has 30, Dec has 31 → 40 days from Nov 1 = Dec 10
        let cal = Calendar(identifier: .gregorian)
        let comps = DateComponents(year: 2025, month: 11, day: 1)
        var date = cal.date(from: comps)!
        let df = DateFormatter()
        df.calendar = cal
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = "yyyy-MM-dd"
        for _ in 0..<40 {
            ns.append((df.string(from: date), 50.0))
            date = cal.date(byAdding: .day, value: 1, to: date)!
        }
        // last old day should be < "2026-01-15"
        XCTAssertLessThan(ns.last!.0, "2026-01-15")

        // 3 recent on distinct days inside [2026-01-15, 2026-01-21]
        ns.append(("2026-01-15", 40.0))
        ns.append(("2026-01-18", 50.0))
        ns.append(("2026-01-21", 60.0))

        let r = AutonomicTrend.evaluate(nights: nights(ns), asOf: "2026-01-21",
                                        recentCutoff: "2026-01-15")
        XCTAssertEqual(r.confidence, .solid)
        XCTAssertEqual(r.nightsUsable, 43)
        XCTAssertEqual(r.recentDenseNights, 3)
        XCTAssertNotNil(r.z7d)

        // Closed-form: (ln(0.96)/3.0) / (1.253 * 0.08) ≈ −0.13574752101707624
        let expectedZ = (Foundation.log(0.96) / 3.0) / (1.253 * 0.08)
        XCTAssertEqual(r.z7d!, expectedZ, accuracy: 1e-9)
        // Also pin the stated literal
        XCTAssertEqual(r.z7d!, -0.13574752101707624, accuracy: 1e-9)
        XCTAssertEqual(r.direction, .inBase)
    }

    func testDeterminism() {
        var ns: [(String, Double)] = []
        for i in 0..<21 {
            ns.append((String(format: "2026-01-%02d", i + 1), 50.0 + Double(i % 5)))
        }
        let a = AutonomicTrend.evaluate(nights: nights(ns), asOf: "2026-01-21",
                                        recentCutoff: "2026-01-15")
        let b = AutonomicTrend.evaluate(nights: nights(ns), asOf: "2026-01-21",
                                        recentCutoff: "2026-01-15")
        XCTAssertEqual(a, b)
    }
}
