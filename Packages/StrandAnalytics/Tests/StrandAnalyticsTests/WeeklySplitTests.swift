import XCTest
@testable import StrandAnalytics

/// Pure derivation for the «La Semana» planner (FER-531). Weekday numbering follows
/// `Calendar.component(.weekday)` (1 = Sunday … 7 = Saturday); Monday = 2. The Monday-first display
/// order used throughout is `[2, 3, 4, 5, 6, 7, 1]`.
final class WeeklySplitTests: XCTestCase {

    private let mondayFirst = [2, 3, 4, 5, 6, 7, 1]

    // MARK: - Today's routine

    /// No split at all → no routine for today (FER-531: no `routines.first` fallback).
    func testTodayRoutineNilWithoutSplit() {
        XCTAssertNil(WeeklySplit.todayRoutineId(split: [:], todayWeekday: 5))
    }

    /// An assigned day returns its routine; a rest day (no row) returns nil.
    func testTodayRoutineFromSplit() {
        let split = [2: "push", 5: "pull"]
        XCTAssertEqual(WeeklySplit.todayRoutineId(split: split, todayWeekday: 5), "pull")
        XCTAssertNil(WeeklySplit.todayRoutineId(split: split, todayWeekday: 4), "Wednesday is a rest day")
    }

    // MARK: - Week states

    /// done / today / upcoming / rest resolve correctly against the split and this week's completions.
    func testWeekStates() {
        let states = WeeklySplit.weekStates(
            split: [2: "push", 4: "legs", 6: "pull"],   // Mon, Wed, Fri
            completedWeekdays: [2],                       // did Monday
            todayWeekday: 4,                              // Wednesday
            orderedWeekdays: mondayFirst)
        XCTAssertEqual(states.map(\.state), [
            .done,      // Mon — assigned + trained
            .rest,      // Tue — unassigned
            .today,     // Wed — assigned, today, not yet trained
            .rest,      // Thu — unassigned
            .upcoming,  // Fri — assigned, future
            .rest,      // Sat
            .rest,      // Sun
        ])
        XCTAssertEqual(states.map(\.weekday), mondayFirst, "preserves the caller's display order")
    }

    /// A past assigned day with no completed session reads as `upcoming` (the «próximo» token) — the
    /// strip's four states don't distinguish a missed day, matching the design mock.
    func testPastUntrainedDayIsUpcoming() {
        let states = WeeklySplit.weekStates(
            split: [2: "push"],          // Monday only
            completedWeekdays: [],        // nothing done
            todayWeekday: 5,              // Thursday
            orderedWeekdays: mondayFirst)
        XCTAssertEqual(states.first { $0.weekday == 2 }?.state, .upcoming, "Monday is assigned + untrained")
    }

    // MARK: - Consistency streak

    /// The threshold is the size of the CURRENT split, applied to every week. Ana (a 2-day plan who does
    /// her 2) keeps her streak; Beto (a 4-day plan who only does 3) does not.
    func testStreakUsesCurrentSplitSize() {
        let ana = WeeklySplit.consistencyStreak(
            weeklyCompletedCounts: [2, 2, 2, 2], currentAssignedCount: 2, includesCurrentWeek: false)
        XCTAssertEqual(ana, 4, "2-day plan, did 2 every week → 4-week streak")

        let beto = WeeklySplit.consistencyStreak(
            weeklyCompletedCounts: [3, 3, 3, 3], currentAssignedCount: 4, includesCurrentWeek: false)
        XCTAssertEqual(beto, 0, "4-day plan, did only 3 → never met the plan → no streak")
    }

    /// No split (assigned count 0) → there is nothing to sustain → streak 0.
    func testStreakZeroWhenNoSplit() {
        XCTAssertEqual(
            WeeklySplit.consistencyStreak(weeklyCompletedCounts: [5, 5, 5], currentAssignedCount: 0,
                                          includesCurrentWeek: false),
            0)
    }

    /// A past week below the threshold breaks the streak; only the trailing run counts.
    func testStreakBreaksOnPastWeekBelowThreshold() {
        let streak = WeeklySplit.consistencyStreak(
            weeklyCompletedCounts: [3, 3, 1, 3, 3], currentAssignedCount: 3, includesCurrentWeek: false)
        XCTAssertEqual(streak, 2, "the most recent two weeks met it; the 1 before them breaks it")
    }

    /// The in-progress current week never breaks the streak (a fresh week shouldn't zero it), but it
    /// extends it once it already meets the threshold.
    func testCurrentWeekDoesNotBreakButExtends() {
        // Current week (last element) at 0 so far — must NOT zero the 3-week run behind it.
        XCTAssertEqual(
            WeeklySplit.consistencyStreak(weeklyCompletedCounts: [3, 3, 3, 0], currentAssignedCount: 3,
                                          includesCurrentWeek: true),
            3, "a fresh week in progress doesn't break the streak")
        // Current week already met → it counts on top.
        XCTAssertEqual(
            WeeklySplit.consistencyStreak(weeklyCompletedCounts: [3, 3, 3, 3], currentAssignedCount: 3,
                                          includesCurrentWeek: true),
            4, "current week already met extends the streak")
    }
}
