import Foundation

public extension StrengthSessionSnapshot {
    /// Turn a pushed snapshot into a FRESH PLAN template for a brand-new session (ola 2 · C1, FER-361).
    ///
    /// The iPhone pushes today's plan to the watch as a `StrengthSessionSnapshot` seed (over
    /// `updateApplicationContext`, so the watch has it cached even when later offline). When the watch
    /// starts a session standalone, it must NOT reuse the seed's `id`/`startTs`: two days on the same plan
    /// would collide on the session PK. `asTemplate` mints a fresh identity and clears every bit of
    /// *registered* / in-flight state, while preserving the *plan* — the planned weights, reps, `mode`
    /// (incl. AMRAP's `nil` reps), rest config, `programWeek`/`deload`, and any held-raise/deload offer the
    /// iPhone served. Pure and testable (`StrengthSessionSnapshotTests.testAsTemplateIsFreshPlan`).
    func asTemplate(newId: String, nowTs: Int) -> StrengthSessionSnapshot {
        var copy = self
        copy.id = newId
        copy.startTs = nowTs
        copy.updatedTs = nowTs
        copy.currentIndex = 0
        // Clear any in-flight rest / stopwatch / pause the seed might have carried.
        copy.restEndsAt = nil
        copy.restStartedAt = nil
        copy.lastRestStartedAt = nil
        copy.currentRestTarget = nil
        copy.restOwnerSetId = nil
        copy.timerStart = nil
        copy.paused = false
        copy.pausedAccumulatedS = 0
        copy.pausedAt = nil
        copy.runs = runs.map { run in
            var r = run
            r.currentSet = 0
            r.skipped = false
            r.sets = run.sets.map { set in
                var s = set
                s.done = false          // nothing is logged yet in a fresh plan
                s.doneTs = nil
                s.rpe = nil
                s.touched = nil
                s.restTakenS = nil
                // weightKg / reps (incl. AMRAP nil) / mode / kind / rest are the PLAN — preserved.
                return s
            }
            return r
        }
        return copy
    }
}
