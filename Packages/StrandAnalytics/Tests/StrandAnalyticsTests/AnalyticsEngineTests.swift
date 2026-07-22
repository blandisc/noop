import XCTest
@testable import StrandAnalytics

final class AnalyticsEngineTests: XCTestCase {

    func testVersion() {
        XCTAssertEqual(StrandAnalytics.version, "0.1.0")
    }

    func testDayStringUTC() {
        // 2021-01-01 00:00:00 UTC == 1609459200.
        XCTAssertEqual(AnalyticsEngine.dayString(1_609_459_200), "2021-01-01")
    }

    // MARK: - Local civil-day attribution (FER-226)

    func testDayStringLocalNegativeOffsetCrossesMidnight() {
        // 2026-06-18 01:30:00 UTC is still 2026-06-17 19:30 in México (UTC−6) — the exact incident.
        let ts = utcTimestamp("2026-06-18 01:30:00")
        XCTAssertEqual(AnalyticsEngine.dayString(ts), "2026-06-18")                          // default = UTC
        XCTAssertEqual(AnalyticsEngine.dayString(ts, tzOffsetSeconds: -6 * 3600), "2026-06-17")
        // A positive offset (e.g. UTC+10) rolls an early-UTC instant forward into the next civil day.
        XCTAssertEqual(AnalyticsEngine.dayString(utcTimestamp("2026-06-17 16:00:00"),
                                                 tzOffsetSeconds: 10 * 3600), "2026-06-18")
    }

    func testLocalMidnightNegativeOffset() {
        // Local midnight of 2026-06-17 in México (UTC−6) is 2026-06-17 06:00:00 UTC.
        let ts = utcTimestamp("2026-06-18 01:30:00")   // evening of the 17th, local MX
        let mid = AnalyticsEngine.localMidnight(ts, tzOffsetSeconds: -6 * 3600)
        XCTAssertEqual(mid, utcTimestamp("2026-06-17 06:00:00"))
        // It floors to local midnight: the instant maps to the 17th, one second earlier to the 16th.
        XCTAssertEqual(AnalyticsEngine.dayString(mid, tzOffsetSeconds: -6 * 3600), "2026-06-17")
        XCTAssertEqual(AnalyticsEngine.dayString(mid - 1, tzOffsetSeconds: -6 * 3600), "2026-06-16")
        // Default offset 0 floors to UTC midnight — unchanged behaviour for pure callers.
        XCTAssertEqual(AnalyticsEngine.localMidnight(ts), utcTimestamp("2026-06-18 00:00:00"))
    }

    func testFutureLocalDaysToPruneSelectsOnlyFutureUnwrittenRows() {
        let today = "2026-06-17"
        let written: Set<String> = ["2026-06-15", "2026-06-16", "2026-06-17"]   // re-grouped local days
        // (a) The future-in-local phantom row (the 18th) IS selected for prune…
        let stored = ["2026-06-15", "2026-06-16", "2026-06-17", "2026-06-18"]
        XCTAssertEqual(AnalyticsEngine.futureLocalDaysToPrune(stored: stored, today: today, written: written),
                       ["2026-06-18"])
        // (b) …a today/past row is never selected — even a PAST day NOT in `written` (raw pruned, not
        // recomputable) is kept: no data loss. Only the future row is pruned.
        let withUnrecomputedPast = ["2026-04-01", "2026-06-17", "2026-06-18"]
        XCTAssertEqual(AnalyticsEngine.futureLocalDaysToPrune(stored: withUnrecomputedPast, today: today,
                                                              written: written), ["2026-06-18"])
        // (c) A future row that WAS written this run is not pruned (defensive belt-and-suspenders).
        XCTAssertEqual(AnalyticsEngine.futureLocalDaysToPrune(stored: ["2026-06-18"], today: today,
                                                              written: ["2026-06-18"]), [])
    }

    /// Unix-seconds for a `yyyy-MM-dd HH:mm:ss` wall-clock string interpreted in UTC.
    private func utcTimestamp(_ s: String) -> Int {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return Int(f.date(from: s)!.timeIntervalSince1970)
    }
}
