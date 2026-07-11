import XCTest
@testable import StrandAnalytics

/// FER-868 — the day-dirtiness arithmetic behind the incremental analyzeRecent pass.
final class AnalysisSchedulerTests: XCTestCase {

    // A fixed "now": 2026-07-10 18:00:00 UTC.
    private let now = 1_783_101_600

    private func sig(_ dayCounts: [String: [Int: Int]], now: Int, offset: Int,
                     tz: Int) -> AnalysisScheduler.NightSignature {
        AnalysisScheduler.signature(
            dayCounts: dayCounts,
            epochDays: AnalysisScheduler.windowEpochDays(now: now, offset: offset, tzOffsetSeconds: tz))
    }

    // MARK: - isDirty

    func testEqualSignatureNotTodayIsClean() {
        let counts = ["hr": [20_000: 5_000, 20_001: 3_000], "rr": [20_000: 800]]
        let a = sig(counts, now: now, offset: 3, tz: 0)
        let b = sig(counts, now: now, offset: 3, tz: 0)
        XCTAssertFalse(AnalysisScheduler.isDirty(cached: a, current: b, isToday: false))
    }

    func testOneNewRowInAnyStreamOfTheWindowIsDirty() {
        let ed = AnalysisScheduler.epochDay(now - 3 * 86_400, tzOffsetSeconds: 0)
        let counts: [String: [Int: Int]] = ["hr": [ed: 5_000], "gravity": [ed: 9_000]]
        let cached = sig(counts, now: now, offset: 3, tz: 0)
        for stream in ["hr", "rr", "resp", "gravity", "steps", "skinTemp"] {
            var grown = counts
            grown[stream, default: [:]][ed, default: 0] += 1   // +1 row in this stream, this day
            let current = sig(grown, now: now, offset: 3, tz: 0)
            XCTAssertTrue(AnalysisScheduler.isDirty(cached: cached, current: current, isToday: false),
                          "+1 row in \(stream) must dirty the night")
        }
        // Control: the untouched counts stay clean.
        XCTAssertFalse(AnalysisScheduler.isDirty(cached: cached,
                                                 current: sig(counts, now: now, offset: 3, tz: 0),
                                                 isToday: false))
    }

    func testCountGoingDownIsDirty() {
        let ed = AnalysisScheduler.epochDay(now - 2 * 86_400, tzOffsetSeconds: 0)
        let cached = sig(["hr": [ed: 5_000]], now: now, offset: 2, tz: 0)
        let trimmed = sig(["hr": [ed: 4_000]], now: now, offset: 2, tz: 0)   // safe-trim deleted rows
        XCTAssertTrue(AnalysisScheduler.isDirty(cached: cached, current: trimmed, isToday: false))
        // Down to ZERO (day fully trimmed → key vanishes) is dirty too.
        let gone = sig(["hr": [:]], now: now, offset: 2, tz: 0)
        XCTAssertTrue(AnalysisScheduler.isDirty(cached: cached, current: gone, isToday: false))
    }

    func testNoCachedSignatureIsDirty() {
        let current = sig(["hr": [20_000: 1]], now: now, offset: 5, tz: 0)
        XCTAssertTrue(AnalysisScheduler.isDirty(cached: nil, current: current, isToday: false))
    }

    func testTodayIsAlwaysDirty() {
        let s = sig(["hr": [20_000: 5_000]], now: now, offset: 0, tz: 0)
        XCTAssertTrue(AnalysisScheduler.isDirty(cached: s, current: s, isToday: true))
    }

    func testCountMovingBetweenDaysInsideTheWindowIsDirty() {
        // Same window TOTAL, different per-day split — must still read as dirty (the signature is
        // keyed per (stream, day), not summed over the window).
        let days = AnalysisScheduler.windowEpochDays(now: now, offset: 4, tzOffsetSeconds: 0)
        let d0 = days.first!, d1 = days.last!
        let a = AnalysisScheduler.signature(dayCounts: ["hr": [d0: 100, d1: 200]], epochDays: days)
        let b = AnalysisScheduler.signature(dayCounts: ["hr": [d0: 200, d1: 100]], epochDays: days)
        XCTAssertTrue(AnalysisScheduler.isDirty(cached: a, current: b, isToday: false))
    }

    // MARK: - windowEpochDays covers exactly [dayStart − 30 h, dayStart + 12 h]

    private func assertWindow(now: Int, offset: Int, tz: Int,
                              file: StaticString = #filePath, line: UInt = #line) {
        let days = AnalysisScheduler.windowEpochDays(now: now, offset: offset, tzOffsetSeconds: tz)
        let dayStart = now - offset * 86_400
        let from = dayStart - 30 * 3_600
        let to = dayStart + 12 * 3_600
        // Contiguous ascending, first = day of `from`, last = day of `to` — i.e. every ts in the
        // read window maps into the set and the bounds are tight.
        XCTAssertEqual(days.first, AnalysisScheduler.epochDay(from, tzOffsetSeconds: tz), file: file, line: line)
        XCTAssertEqual(days.last, AnalysisScheduler.epochDay(to, tzOffsetSeconds: tz), file: file, line: line)
        XCTAssertEqual(days, Array(days.first!...days.last!), file: file, line: line)
        for ts in [from, from + 1, dayStart, to - 1, to] {
            XCTAssertTrue(days.contains(AnalysisScheduler.epochDay(ts, tzOffsetSeconds: tz)),
                          "ts \(ts) outside window days", file: file, line: line)
        }
        // Tight: one second outside either bound may (at most) add a NEW day, never lose one.
        XCTAssertFalse(days.contains(AnalysisScheduler.epochDay(from - 86_400, tzOffsetSeconds: tz)),
                       file: file, line: line)
        XCTAssertFalse(days.contains(AnalysisScheduler.epochDay(to + 86_400, tzOffsetSeconds: tz)),
                       file: file, line: line)
    }

    func testWindowEpochDaysNegativeTz() {
        assertWindow(now: now, offset: 0, tz: -6 * 3_600)   // CST (Mexico)
        assertWindow(now: now, offset: 7, tz: -6 * 3_600)
    }

    func testWindowEpochDaysPositiveTz() {
        assertWindow(now: now, offset: 0, tz: 9 * 3_600)    // JST
        assertWindow(now: now, offset: 20, tz: 9 * 3_600)
    }

    func testWindowEpochDaysMidnightCrossing() {
        // `now` just after local midnight with tz −6: dayStart sits minutes into the local day, so
        // the −30 h arm reaches TWO local days back.
        let justPastLocalMidnight = (1_783_101_600 / 86_400) * 86_400 + 6 * 3_600 + 300   // 00:05 local, tz −6
        let tz = -6 * 3_600
        assertWindow(now: justPastLocalMidnight, offset: 0, tz: tz)
        let days = AnalysisScheduler.windowEpochDays(now: justPastLocalMidnight, offset: 0, tzOffsetSeconds: tz)
        let today = AnalysisScheduler.epochDay(justPastLocalMidnight, tzOffsetSeconds: tz)
        XCTAssertEqual(days, [today - 2, today - 1, today],
                       "00:05 local: −30 h reaches two days back, +12 h stays inside today")
    }

    func testEpochDayFloorsNegativeValues() {
        // Pure floor semantics (toward −∞), so a tz shift across the epoch can't off-by-one.
        XCTAssertEqual(AnalysisScheduler.epochDay(0, tzOffsetSeconds: -1), -1)
        XCTAssertEqual(AnalysisScheduler.epochDay(0, tzOffsetSeconds: 0), 0)
        XCTAssertEqual(AnalysisScheduler.epochDay(86_399, tzOffsetSeconds: 0), 0)
        XCTAssertEqual(AnalysisScheduler.epochDay(86_400, tzOffsetSeconds: 0), 1)
    }
}
