import Foundation

/// Fuses a strength session logged (partly) on the Apple Watch with the iPhone's structure (ola 2 · C1,
/// FER-361). Pure and database-free so it lives here and both sides run the exact same rule.
///
/// The wrist is the fresh **logger** of values; the iPhone is the **structure authority** (the plan it
/// served, `programWeek`/`deload`). So:
///
/// - **`base`** = the iPhone's snapshot: run structure, `programWeek`/`deload`, routine identity.
/// - **`incoming`** = the watch's snapshot: the values actually registered standalone.
///
/// Rules (all covered by `SessionReconcilerTests`):
/// - Runs are matched by `id`; within a run, `SetSnapshot`s are unioned by `id`.
/// - **Done wins over pending**; two done sets → the one with the higher `doneTs` (tie → the watch, the
///   fresher logger). `mode` (incl. `.drop`) and `reps` (incl. AMRAP's `nil`) travel **verbatim** — never
///   coerced to `.standard` or to `0`.
/// - A **drop created on the watch** (an id only `incoming` has, `mode == .drop`) is inserted preserving
///   its adjacency — the walk follows `incoming`'s order, so the escalón lands right after its mother.
///   Losing it would be a data defect (a drop counts only toward volume; read as `.standard` it would
///   gate progression/records/1RM wrongly).
/// - **Idempotent**: `merge(merge(a, b), b) == merge(a, b)` — the durable queue can deliver a snapshot
///   twice without duplicating anything.
/// - `programWeek`/`deload` (and the rest of the top-level plan) come from `base`; the watch only shows them.
///
/// Note: this transports `mode` faithfully but never interprets it — `SetMode.counts(for:)` stays the one
/// oracle the iPhone's save/progression/records read, unchanged.
public enum StrengthSessionReconciler {

    public static func merge(base: StrengthSessionSnapshot,
                             incoming: StrengthSessionSnapshot) -> StrengthSessionSnapshot {
        var result = base   // base is the structure authority: programWeek/deload/routine/rest state.

        let incomingRuns = Dictionary(incoming.runs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        result.runs = base.runs.map { baseRun in
            guard let inRun = incomingRuns[baseRun.id] else { return baseRun }  // the watch never touched this run.
            return mergeRun(base: baseRun, incoming: inRun)
        }
        // Runs only the watch has (shouldn't happen — the watch is seeded from base — but never drop one).
        let baseRunIds = Set(base.runs.map(\.id))
        for inRun in incoming.runs where !baseRunIds.contains(inRun.id) {
            result.runs.append(inRun)
        }
        result.updatedTs = max(base.updatedTs, incoming.updatedTs)
        return result
    }

    private static func mergeRun(base: StrengthSessionSnapshot.RunSnapshot,
                                 incoming: StrengthSessionSnapshot.RunSnapshot)
        -> StrengthSessionSnapshot.RunSnapshot {
        var run = base   // base run keeps its structure (name/type/rest/held/deload, seeded by the iPhone).
        let baseSets = Dictionary(base.sets.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        var merged: [StrengthSessionSnapshot.SetSnapshot] = []
        var seen = Set<String>()
        // Walk INCOMING order: it carries the watch-created drop's adjacency to its mother.
        for inSet in incoming.sets {
            if let baseSet = baseSets[inSet.id] {
                merged.append(pick(base: baseSet, incoming: inSet))
            } else {
                merged.append(inSet)   // new on the watch (e.g. a drop) — inserted at its incoming position.
            }
            seen.insert(inSet.id)
        }
        // Preserve any set only `base` had (the watch's snapshot lagged) — conservative, never lose one.
        for baseSet in base.sets where !seen.contains(baseSet.id) {
            merged.append(baseSet)
        }

        run.sets = merged
        run.currentSet = merged.isEmpty ? 0 : min(max(incoming.currentSet, 0), merged.count - 1)
        run.skipped = base.skipped || incoming.skipped
        return run
    }

    /// Done wins over pending; two done → higher `doneTs` (tie → incoming, the fresher logger); two
    /// pending → incoming. The winner is returned whole, so `mode` and `reps` carry verbatim.
    private static func pick(base: StrengthSessionSnapshot.SetSnapshot,
                             incoming: StrengthSessionSnapshot.SetSnapshot)
        -> StrengthSessionSnapshot.SetSnapshot {
        switch (base.done, incoming.done) {
        case (false, true):  return incoming
        case (true, false):  return base
        case (true, true):
            return (incoming.doneTs ?? Int.min) >= (base.doneTs ?? Int.min) ? incoming : base
        case (false, false):
            return incoming
        }
    }
}
