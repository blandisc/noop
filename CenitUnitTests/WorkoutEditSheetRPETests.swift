import XCTest
import StrandTraining
@testable import Cenit

/// FER-172 — `WorkoutEditSheet.save()` reconstructs each `SetEntry` from its `EditSet` working copy via
/// `EditSet.toSetEntry(...)`. The editor only ever exposes weight/reps controls; every other field the
/// original `SetEntry` carried (`rpe`, `restTakenS`) must ride through untouched. Before FER-172,
/// `EditSet` never captured `rpe` from the loaded set (its `init(_:)` dropped it, and the reconstruction
/// had no `rpe:` argument at all — the `SetEntry` init default of `nil` won silently) — editing ANY saved
/// session's weight erased the RPE the live session had captured. This truena against that old shape:
/// `EditSet(original).toSetEntry(...)` must hand back the same `rpe` the original `SetEntry` had.
final class WorkoutEditSheetRPETests: XCTestCase {

    /// A saved work set exactly as `StrengthStore.setEntry(_:)` would read it back: `rpe` and
    /// `restTakenS` both captured by the live session.
    private func savedWorkSet(rpe: Double?, restTakenS: Int?) -> SetEntry {
        SetEntry(id: "set-a", sessionId: "s1", exerciseId: "bench", position: 0, kind: .work,
                 weightKg: 60, reps: 8, done: true, ts: 1000, rpe: rpe, restTakenS: restTakenS)
    }

    /// Loading a saved set into the editor, then reconstructing it on save with NO edit at all, must
    /// hand back the exact same `rpe`. Truena si `EditSet.init(_:)` no captura `rpe`, o si
    /// `toSetEntry` no lo reenvía al `SetEntry` reconstruido.
    func testUnchangedSetPreservesRPEOnSave() {
        let original = savedWorkSet(rpe: 8.5, restTakenS: 95)
        let working = EditSet(original)

        let saved = working.toSetEntry(sessionId: original.sessionId, exerciseId: original.exerciseId,
                                        position: 0, usesWeightReps: true)

        XCTAssertEqual(saved.rpe, 8.5, "editing (even a no-op save) must not erase the captured RPE")
        XCTAssertEqual(saved.restTakenS, 95, "and the real rest measured after the set — same class of bug")
    }

    /// The realistic case: the user edits ONLY the weight (the editor's own control). `rpe` never had a
    /// control shown for it, so it must survive that edit unchanged — the exact scenario from
    /// `WorkoutHistoryScreen` → «Editar» → `WorkoutEditSheet.save()`.
    func testEditingWeightStillPreservesRPE() {
        let original = savedWorkSet(rpe: 7, restTakenS: 60)
        var working = EditSet(original)
        working.weightKg = 65   // the only thing the editor's numberField mutates

        let saved = working.toSetEntry(sessionId: original.sessionId, exerciseId: original.exerciseId,
                                        position: 0, usesWeightReps: true)

        XCTAssertEqual(saved.weightKg, 65, "the actual edit must still apply")
        XCTAssertEqual(saved.rpe, 7, "RPE must survive an edit to a DIFFERENT field")
    }

    /// No RPE captured (nil, never 0 — the app never fabricates one) must still read back nil after a
    /// reconstruction, not silently become present.
    func testNoRPEStaysNilOnSave() {
        let original = savedWorkSet(rpe: nil, restTakenS: nil)
        let working = EditSet(original)

        let saved = working.toSetEntry(sessionId: original.sessionId, exerciseId: original.exerciseId,
                                        position: 0, usesWeightReps: true)

        XCTAssertNil(saved.rpe)
    }
}
