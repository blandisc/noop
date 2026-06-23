import Foundation

// WeeklySplit.swift — pure derivation for the «La Semana» planner (FER-531).
//
// Given a weekly split (which routine is planned each weekday) and the strength sessions completed
// this week, derive the three things the planner landing reads: today's routine, the state of each day
// in the week strip, and the consistency streak. PURE and database-free: it takes PLAIN PRIMITIVES
// (weekday ints, a [weekday → routineId] map, counts) — never StrandTraining models or timestamps — so
// StrandAnalytics gains no dependency on StrandTraining and can never reintroduce the UTC-vs-local
// day-boundary bug (FER-224/226). The app layer owns the impure projection: it reads the split + the
// session history from the store and maps each session's `startTs` to a LOCAL weekday/week with
// `Calendar` before calling in here. The same primitives-in pattern MuscleFatigueMap already uses.
//
// Weekday numbering is the caller's `Calendar.component(.weekday)` convention (1 = Sunday … 7 =
// Saturday); this engine is agnostic to it — it only compares and looks up weekday keys.
//
// NOT physiology — the "streak" is bookkeeping, not a cited recovery model, so it needs no method
// citation; it stays fully deterministic and testable. No clinical claims.

public enum WeeklySplit {

    /// The state of one day in the week strip. The UI localizes the label (no es-MX copy here),
    /// like `TrainingRegulation.Adjustment`. These are the four strip tokens the design defines —
    /// a past assigned day that wasn't trained reads as `upcoming` (the «próximo» token), as in the mock;
    /// the strip deliberately doesn't distinguish "missed".
    public enum DayState: Equatable, Sendable {
        case done       // assigned + a session completed this week
        case today      // the local weekday of today (assigned, not yet completed)
        case upcoming   // assigned, not yet trained (the «próximo» token)
        case rest       // no routine assigned for this day
    }

    /// One day's resolved status, in the display order the caller asked for.
    public struct DayStatus: Equatable, Sendable {
        public let weekday: Int
        public let state: DayState
        public init(weekday: Int, state: DayState) {
            self.weekday = weekday; self.state = state
        }
    }

    /// Today's planned routine: `split[todayWeekday]`. `nil` when there is no split at all OR today is a
    /// rest day — the planner shows its «no plan yet» / rest state rather than falling back to an
    /// arbitrary routine (FER-531: no `routines.first` fallback).
    public static func todayRoutineId(split: [Int: String], todayWeekday: Int) -> String? {
        split[todayWeekday]
    }

    /// The state of each day in `orderedWeekdays` (the caller's display order, e.g. Monday-first local).
    /// `completedWeekdays` = the weekdays of THIS week that already have ≥1 completed session (the app
    /// derives them in local time).
    public static func weekStates(split: [Int: String],
                                  completedWeekdays: Set<Int>,
                                  todayWeekday: Int,
                                  orderedWeekdays: [Int]) -> [DayStatus] {
        orderedWeekdays.map { weekday in
            let state: DayState
            if split[weekday] == nil {
                state = .rest                          // not in the plan
            } else if completedWeekdays.contains(weekday) {
                state = .done                          // planned + trained
            } else if weekday == todayWeekday {
                state = .today
            } else {
                state = .upcoming                      // planned, not yet trained
            }
            return DayStatus(weekday: weekday, state: state)
        }
    }

    /// Consistency streak: the number of consecutive weeks (ending now) in which the completed-session
    /// count met the threshold — and the threshold is `currentAssignedCount`, the size of the split
    /// RIGHT NOW. We keep no history of past split sizes, so any per-week historical threshold would be
    /// invented; measuring every week against today's plan answers the honest question the user cares
    /// about — "have I sustained *my current* N-day-a-week plan?" — and is deterministic. With no split
    /// (`currentAssignedCount == 0`) there is nothing to sustain → the streak is 0.
    ///
    /// `weeklyCompletedCounts` is ordered oldest → newest. When `includesCurrentWeek` is true the last
    /// element is the in-progress current week: it EXTENDS the streak once it already meets the
    /// threshold, but it does NOT break the streak when it hasn't yet — a fresh week should not zero a
    /// real streak (the same "today not-yet-logged doesn't break it" spirit as StreakMath). Past weeks
    /// below the threshold always break it.
    public static func consistencyStreak(weeklyCompletedCounts: [Int],
                                         currentAssignedCount: Int,
                                         includesCurrentWeek: Bool) -> Int {
        guard currentAssignedCount > 0 else { return 0 }
        var counts = weeklyCompletedCounts
        var streak = 0
        if includesCurrentWeek, let current = counts.last {
            if current >= currentAssignedCount { streak += 1 }  // already met → it counts
            counts.removeLast()                                 // either way it can't break the streak
        }
        for count in counts.reversed() {
            if count >= currentAssignedCount { streak += 1 } else { break }
        }
        return streak
    }
}
