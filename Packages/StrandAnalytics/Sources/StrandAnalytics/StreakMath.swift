import Foundation

// MARK: - StreakMath — consecutive-adherence streaks (FER-462)
//
// The «racha» behind a running N-of-1 experiment: how many days in a row you've kept the habit, and
// your best run so far. Pure and deterministic — it takes an ordered list of the days that count
// («eligible») and the subset you adhered to, and reports the trailing run (current) and the longest
// run (best). The caller decides what's eligible; in particular, a still-pending «today» is left OUT
// of the list, so an unmarked today reads as «not broken yet», not as a miss.
//
// Adherence semantics match the rest of Coach (a day is adherent iff it's in `adherent`); a day that
// isn't adherent — a logged «No» or, for past days, an unlogged one — resets the run.

public enum StreakMath {

    /// The current (trailing) and best (longest) consecutive-adherence runs over `eligibleDays`.
    ///
    /// - Parameters:
    ///   - eligibleDays: the day-keys that count, in ascending chronological order. Drop a pending
    ///     «today» before calling so it doesn't read as a break.
    ///   - adherent: the subset of day-keys the habit was kept on.
    /// - Returns: `current` = the run ending at the last eligible day (0 if that day wasn't adherent);
    ///   `best` = the longest run anywhere in the list. `best >= current` always.
    public static func streaks(eligibleDays: [String], adherent: Set<String>) -> (current: Int, best: Int) {
        var best = 0
        var run = 0
        for day in eligibleDays {
            if adherent.contains(day) {
                run += 1
                if run > best { best = run }
            } else {
                run = 0
            }
        }
        return (run, best)
    }
}
