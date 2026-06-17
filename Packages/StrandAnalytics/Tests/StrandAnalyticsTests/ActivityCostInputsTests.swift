import XCTest
@testable import StrandAnalytics

/// ActivityCostInputs — building the engine's day-keyed inputs from raw sessions.
///
/// Covers the risky parts the app layer would otherwise hide: day-keying in the
/// caller's timezone (the bug that would silently misalign D→D+1), same-day
/// de-duplication, and an end-to-end run through `ActivityCostEngine.evaluate` to
/// prove the keys line up with the recovery day-keys.
final class ActivityCostInputsTests: XCTestCase {

    private func utcCalendar() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    /// Unix seconds for a wall-clock UTC instant (deterministic; no `Date()`).
    private func utcTs(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Int {
        Int(utcCalendar().date(from: DateComponents(year: y, month: m, day: d, hour: h))!
            .timeIntervalSince1970)
    }

    // MARK: - Day-keying honors the given timezone  [the alignment bug guard]

    func testDayKeyRespectsTimeZone() {
        // 2026-01-15 02:00 UTC is still 2026-01-14 (20:00) in Mexico City (UTC-6, no DST since 2022).
        let s = [ActivityCostInputs.Session(startTs: utcTs(2026, 1, 15, 2), sport: "Run")]
        let inUTC = ActivityCostInputs.activityDaysBySport(s, timeZone: TimeZone(identifier: "UTC")!)
        XCTAssertEqual(inUTC["Run"], ["2026-01-15"])
        let inMX = ActivityCostInputs.activityDaysBySport(
            s, timeZone: TimeZone(identifier: "America/Mexico_City")!)
        XCTAssertEqual(inMX["Run"], ["2026-01-14"])
    }

    // MARK: - Same-day duplicates collapse; sports stay separate

    func testSameDayCollapsesAndSeparatesSports() {
        let sessions = [
            ActivityCostInputs.Session(startTs: utcTs(2026, 5, 10, 7),  sport: "Running"), // morning run
            ActivityCostInputs.Session(startTs: utcTs(2026, 5, 10, 18), sport: "Running"), // same day, pm
            ActivityCostInputs.Session(startTs: utcTs(2026, 5, 11, 7),  sport: "Running"),
            ActivityCostInputs.Session(startTs: utcTs(2026, 5, 10, 12), sport: "Yoga"),
        ]
        let out = ActivityCostInputs.activityDaysBySport(sessions, timeZone: TimeZone(identifier: "UTC")!)
        XCTAssertEqual(out["Running"], ["2026-05-10", "2026-05-11"]) // two same-day runs → one day
        XCTAssertEqual(out["Yoga"], ["2026-05-10"])
    }

    func testEmptySessionsReturnEmpty() {
        XCTAssertTrue(ActivityCostInputs.activityDaysBySport([], timeZone: TimeZone(identifier: "UTC")!).isEmpty)
    }

    // MARK: - End-to-end: keys built here line up with recovery keys in evaluate()

    func testPipelineAlignsSessionsToNextMorning() {
        let cal = utcCalendar()
        // Rest block far before the sessions, untouched (not tagged, outside any D+1…D+7 window).
        var rec: [String: Double] = [:]
        for i in 0..<5 { rec[String(format: "2026-01-%02d", i + 1)] = 70 }

        // 6 Running sessions, every other day in March; each next morning's Charge = 50.
        var sessions: [ActivityCostInputs.Session] = []
        for d in stride(from: 2, through: 12, by: 2) {
            sessions.append(.init(startTs: utcTs(2026, 3, d), sport: "Running"))
            let nm = cal.date(from: DateComponents(year: 2026, month: 3, day: d + 1))!
            let c = cal.dateComponents([.year, .month, .day], from: nm)
            rec[String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)] = 50
        }

        let inputs = ActivityCostInputs.activityDaysBySport(sessions, timeZone: TimeZone(identifier: "UTC")!)
        XCTAssertEqual(inputs["Running"]?.count, 6)

        let out = ActivityCostEngine.evaluate(activityDaysBySport: inputs, recoveryByDay: rec)
        XCTAssertEqual(out.count, 1)
        let r = out[0]
        XCTAssertEqual(r.sport, "Running")
        XCTAssertEqual(r.baselineCenter, 70, accuracy: 1e-9)  // rest block, post-effect window excluded
        XCTAssertEqual(r.nextMorningCenter, 50, accuracy: 1e-9) // D+1 keys aligned correctly
        XCTAssertEqual(r.delta, 20, accuracy: 1e-9)
        XCTAssertEqual(r.n, 6)
    }
}
