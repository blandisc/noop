import XCTest
@testable import StrandTraining

/// FER-798: the in-progress-session snapshot must survive a JSON round-trip bit-for-bit, since it's the
/// only thing that rebuilds a live session after a crash. If a field is dropped in encode/decode, the
/// recovered session would silently lose it (a logged set, the in-flight rest, the focus).
final class StrengthSessionSnapshotTests: XCTestCase {

    private func sample() -> StrengthSessionSnapshot {
        let set1 = StrengthSessionSnapshot.SetSnapshot(
            id: "s1", weightKg: 60, reps: 8, done: true, doneTs: 1000,
            rest: RestConfig(mode: .fixed, seconds: 90, hrReference: .restingMargin, hrValue: 0),
            kind: .work, rpe: 7, note: "Falló al final", restTakenS: 95)
        let set2 = StrengthSessionSnapshot.SetSnapshot(
            id: "s2", weightKg: 60, reps: 8, done: false, kind: .warmup)
        let run = StrengthSessionSnapshot.RunSnapshot(
            id: "r1", exerciseId: "bench", name: "Press de banca", type: .weightReps,
            restSeconds: 90, restMode: .heartRate, hrRestReference: .restingMargin, hrRestValue: 12,
            lastWeightKg: 57.5, lastReps: 8, lastTimeS: nil, lastDistanceM: nil,
            sets: [set1, set2], currentSet: 1, skipped: false, raiseOptedOut: true,
            supersetGroup: 1, note: "Buena técnica hoy")
        return StrengthSessionSnapshot(
            id: "sess-1", routineId: "push-a", routineName: "Push A", startTs: 900,
            runs: [run], currentIndex: 0,
            restEndsAt: Date(timeIntervalSince1970: 1090),
            restStartedAt: Date(timeIntervalSince1970: 1000),
            currentRestTarget: 110, currentRestMode: .heartRate,
            timerStart: nil,
            paused: true, pausedAccumulatedS: 45, pausedAt: Date(timeIntervalSince1970: 1002),
            updatedTs: 1005, restOwnerSetId: "s2")
    }

    func testRoundTripPreservesEverything() throws {
        let original = sample()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(StrengthSessionSnapshot.self, from: data)
        XCTAssertEqual(decoded, original, "snapshot changed across a JSON round-trip")
    }

    func testPreservesLoggedSetsAndRestState() throws {
        let decoded = try JSONDecoder().decode(
            StrengthSessionSnapshot.self, from: try JSONEncoder().encode(sample()))
        XCTAssertEqual(decoded.runs.first?.sets.first?.done, true)
        XCTAssertEqual(decoded.runs.first?.sets.first?.doneTs, 1000)
        XCTAssertEqual(decoded.runs.first?.sets.last?.kind, .warmup)
        XCTAssertEqual(decoded.currentRestTarget, 110)
        XCTAssertEqual(decoded.currentRestMode, .heartRate)
        XCTAssertEqual(decoded.restEndsAt, Date(timeIntervalSince1970: 1090))
        XCTAssertEqual(decoded.paused, true)                                   // FER-823
        XCTAssertEqual(decoded.pausedAccumulatedS, 45)
        XCTAssertEqual(decoded.pausedAt, Date(timeIntervalSince1970: 1002))
        XCTAssertEqual(decoded.runs.first?.raiseOptedOut, true)                 // FER-835
    }

    /// FER-835: a snapshot persisted BEFORE the field existed (no `raiseOptedOut` key) still decodes —
    /// the mark is optional, absent = no opt-out.
    func testPreFer835SnapshotDecodesWithoutRaiseOptedOut() throws {
        var snap = sample()
        snap.runs[0].raiseOptedOut = nil
        let data = try JSONEncoder().encode(snap)   // optional nil → key absent, like an old snapshot
        XCTAssertFalse(String(data: data, encoding: .utf8)!.contains("raiseOptedOut"))
        let decoded = try JSONDecoder().decode(StrengthSessionSnapshot.self, from: data)
        XCTAssertNil(decoded.runs.first?.raiseOptedOut)
    }

    /// FER-931: the superset grouping rides the snapshot so a crash mid-superset restores the same
    /// A1/A2 pairing rather than falling back to standalone.
    func testPreservesSupersetGroup() throws {
        let decoded = try JSONDecoder().decode(
            StrengthSessionSnapshot.self, from: try JSONEncoder().encode(sample()))
        XCTAssertEqual(decoded.runs.first?.supersetGroup, 1)
    }

    /// FER-931: a snapshot persisted BEFORE the field existed (no `supersetGroup` key) still decodes —
    /// absent means standalone (nil), never a false grouping.
    func testPreFer931SnapshotDecodesWithoutSupersetGroup() throws {
        var snap = sample()
        snap.runs[0].supersetGroup = nil
        let data = try JSONEncoder().encode(snap)   // optional nil → key absent, like a pre-931 snapshot
        XCTAssertFalse(String(data: data, encoding: .utf8)!.contains("supersetGroup"))
        let decoded = try JSONDecoder().decode(StrengthSessionSnapshot.self, from: data)
        XCTAssertNil(decoded.runs.first?.supersetGroup)
    }

    /// FER-930: RPE rides the snapshot so a crash mid-set doesn't lose an already-entered value.
    func testPreservesRPE() throws {
        let decoded = try JSONDecoder().decode(
            StrengthSessionSnapshot.self, from: try JSONEncoder().encode(sample()))
        XCTAssertEqual(decoded.runs.first?.sets.first?.rpe, 7)
    }

    /// FER-930: a snapshot persisted BEFORE the field existed (no `rpe` key) still decodes — absent
    /// means "not captured" (nil), never a fabricated 0.
    func testPreFer930SnapshotDecodesWithoutRPE() throws {
        var snap = sample()
        snap.runs[0].sets[0].rpe = nil
        let data = try JSONEncoder().encode(snap)   // optional nil → key absent, like a pre-930 snapshot
        XCTAssertFalse(String(data: data, encoding: .utf8)!.contains("\"rpe\""))
        let decoded = try JSONDecoder().decode(StrengthSessionSnapshot.self, from: data)
        XCTAssertNil(decoded.runs.first?.sets.first?.rpe)
    }

    /// FER-932: the exercise-scoped note and the set-scoped note both ride the snapshot so a crash
    /// mid-entry doesn't lose an already-typed note.
    func testPreservesNotes() throws {
        let decoded = try JSONDecoder().decode(
            StrengthSessionSnapshot.self, from: try JSONEncoder().encode(sample()))
        XCTAssertEqual(decoded.runs.first?.note, "Buena técnica hoy")
        XCTAssertEqual(decoded.runs.first?.sets.first?.note, "Falló al final")
    }

    /// FER-932: a snapshot persisted BEFORE the field existed (no `note` key on run or set) still
    /// decodes — absent means "no note" (nil), never an empty string standing in for it.
    func testPreFer932SnapshotDecodesWithoutNote() throws {
        var snap = sample()
        snap.runs[0].note = nil
        snap.runs[0].sets[0].note = nil
        let data = try JSONEncoder().encode(snap)   // optional nil → key absent, like a pre-932 snapshot
        XCTAssertFalse(String(data: data, encoding: .utf8)!.contains("\"note\""))
        let decoded = try JSONDecoder().decode(StrengthSessionSnapshot.self, from: data)
        XCTAssertNil(decoded.runs.first?.note)
        XCTAssertNil(decoded.runs.first?.sets.first?.note)
    }

    /// FER-166: `seededNote` (the routine's fixed note as it was seeded into the run) rides the
    /// snapshot separately from the live, possibly-edited `note` — so a crash mid-session doesn't blur
    /// "untouched seed" with "user edited it this session".
    func testRunSnapshotSeededNoteRoundTripAndLegacyDecodesNil() throws {
        var snap = sample()
        snap.runs[0].note = "Buena técnica hoy"          // unchanged from the seed
        snap.runs[0].seededNote = "Buena técnica hoy"    // what the routine seeded
        let decoded = try JSONDecoder().decode(
            StrengthSessionSnapshot.self, from: try JSONEncoder().encode(snap))
        XCTAssertEqual(decoded.runs.first?.seededNote, "Buena técnica hoy")
        XCTAssertEqual(decoded.runs.first?.note, decoded.runs.first?.seededNote,
                      "an untouched seed decodes identical to the live note")
    }

    /// FER-166: a snapshot persisted BEFORE the field existed (no `seededNote` key) still decodes —
    /// absent means nil, so after a restore from such a legacy snapshot an intact seed is copied to the
    /// acta at most once (same as the pre-FER-166 behavior), never a startup crash.
    func testPreFer166SnapshotDecodesWithoutSeededNote() throws {
        var snap = sample()
        snap.runs[0].seededNote = nil
        let data = try JSONEncoder().encode(snap)   // optional nil → key absent, like a pre-166 snapshot
        XCTAssertFalse(String(data: data, encoding: .utf8)!.contains("seededNote"))
        let decoded = try JSONDecoder().decode(StrengthSessionSnapshot.self, from: data)
        XCTAssertNil(decoded.runs.first?.seededNote)
    }

    /// FER-167: a set's measured real rest, and the id of the set that owns the rest currently in
    /// flight, both ride the snapshot — a crash mid-rest must not lose either.
    func testSnapshotCarriesRestTakenSAndOwnerAndLegacyDecodes() throws {
        let decoded = try JSONDecoder().decode(
            StrengthSessionSnapshot.self, from: try JSONEncoder().encode(sample()))
        XCTAssertEqual(decoded.runs.first?.sets.first?.restTakenS, 95)
        XCTAssertEqual(decoded.restOwnerSetId, "s2")
    }

    /// FER-167: a snapshot persisted BEFORE the fields existed (no `restTakenS`/`restOwnerSetId` keys)
    /// still decodes — absent means nil, so a restore from such a legacy snapshot loses at most the one
    /// rest measurement in flight, never a startup crash.
    func testPreFer167SnapshotDecodesWithoutRestTakenSOrOwner() throws {
        var snap = sample()
        snap.runs[0].sets[0].restTakenS = nil
        snap.restOwnerSetId = nil
        let data = try JSONEncoder().encode(snap)   // optional nil → key absent, like a pre-167 snapshot
        XCTAssertFalse(String(data: data, encoding: .utf8)!.contains("restTakenS"))
        XCTAssertFalse(String(data: data, encoding: .utf8)!.contains("restOwnerSetId"))
        let decoded = try JSONDecoder().decode(StrengthSessionSnapshot.self, from: data)
        XCTAssertNil(decoded.runs.first?.sets.first?.restTakenS)
        XCTAssertNil(decoded.restOwnerSetId)
    }

    /// FER-189 (B7): the un-actioned deload proposal (`StrengthSessionModel.ExerciseRun.deloadState`)
    /// rides the snapshot — `StrandTraining` can't import `StrandAnalytics` (the dependency only runs
    /// the other way), so `DeloadStateSnapshot` is a Codable mirror of `ProgressionState`, same reason
    /// `HeldRaise` mirrors `ProgressionPlanner.Raise` instead of storing it directly.
    func testPreservesDeloadState() throws {
        var snap = sample()
        snap.runs[0].deloadState = .deloading(fromKg: 100, toKg: 92.5)
        let decoded = try JSONDecoder().decode(
            StrengthSessionSnapshot.self, from: try JSONEncoder().encode(snap))
        XCTAssertEqual(decoded.runs.first?.deloadState, .deloading(fromKg: 100, toKg: 92.5))
    }

    /// FER-189: a snapshot persisted BEFORE the field existed (no `deloadState` key) still decodes —
    /// absent means nil, so a restore from such a legacy snapshot loses at most today's un-actioned
    /// deload offer (it gets recomputed next session), never a startup crash.
    func testPreFer189SnapshotDecodesWithoutDeloadState() throws {
        let snap = sample()   // deloadState already nil in the base fixture
        let data = try JSONEncoder().encode(snap)   // optional nil → key absent, like a pre-189 snapshot
        XCTAssertFalse(String(data: data, encoding: .utf8)!.contains("deloadState"))
        let decoded = try JSONDecoder().decode(StrengthSessionSnapshot.self, from: data)
        XCTAssertNil(decoded.runs.first?.deloadState)
    }

    /// Ola 1 (v42): `mode` on a set and `programWeek`/`deload` on the root round-trip, and a snapshot
    /// written before ola 1 (keys absent) still decodes with nil — a crash mid-session on an updated
    /// app must never lose the in-flight session over a new key.
    func testPreOla1SnapshotDecodesWithoutModeAndProgramKeys() throws {
        let json = """
        {"id":"s1","routineId":null,"routineName":"Empuje","startTs":1000,
         "runs":[{"id":"r1","exerciseId":"press","name":"Press","type":"weightReps","restSeconds":90,
                  "restMode":"fixed","hrRestReference":"restingMargin","hrRestValue":0,
                  "sets":[{"id":"a","weightKg":80,"reps":8,"done":false,"kind":"work"}],
                  "currentSet":0,"skipped":false}],
         "currentIndex":0,"currentRestMode":"fixed","paused":false,"pausedAccumulatedS":0,"updatedTs":1001}
        """
        let snap = try JSONDecoder().decode(StrengthSessionSnapshot.self, from: Data(json.utf8))
        XCTAssertNil(snap.runs[0].sets[0].mode)
        XCTAssertNil(snap.programWeek)
        XCTAssertNil(snap.deload)
    }

    /// FER-327 · E6: un AMRAP nace con las repeticiones PENDIENTES (`reps == nil`). La ida y vuelta
    /// tiene que conservar el nil — si el snapshot lo convirtiera en 0, un crash a mitad de sesión
    /// devolvería una serie que dice «0 repeticiones» (registrable en falso) en vez de una pendiente.
    func testAmrapWithPendingRepsRoundTripsAsNil() throws {
        let pending = StrengthSessionSnapshot.SetSnapshot(id: "a", weightKg: 80, reps: nil, mode: .amrap)
        let run = StrengthSessionSnapshot.RunSnapshot(id: "r1", exerciseId: "press", name: "Press",
                                                      type: .weightReps, restSeconds: 90, restMode: .fixed,
                                                      hrRestReference: .restingMargin, hrRestValue: 0,
                                                      sets: [pending], currentSet: 0, skipped: false)
        let snap = StrengthSessionSnapshot(id: "s1", routineId: nil, routineName: "Empuje", startTs: 1000,
                                           runs: [run], currentIndex: 0, updatedTs: 1001)
        let data = try JSONEncoder().encode(snap)
        XCTAssertFalse(String(data: data, encoding: .utf8)!.contains("\"reps\""),
                       "reps pendiente = clave ausente, nunca un 0 inventado")
        let back = try JSONDecoder().decode(StrengthSessionSnapshot.self, from: data)
        XCTAssertNil(back.runs[0].sets[0].reps)
        XCTAssertEqual(back.runs[0].sets[0].mode, .amrap)
        XCTAssertEqual(back, snap)
    }

    /// FER-327 · E6: `reps` pasó a opcional, pero TODO JSON escrito antes de ola 1 la trae siempre —
    /// un snapshot viejo sigue decodificando con su número intacto.
    func testLegacySnapshotWithRepsPresentStillDecodes() throws {
        let json = """
        {"id":"s1","routineName":"Empuje","startTs":1000,
         "runs":[{"id":"r1","exerciseId":"press","name":"Press","type":"weightReps","restSeconds":90,
                  "restMode":"fixed","hrRestReference":"restingMargin","hrRestValue":0,
                  "sets":[{"id":"a","weightKg":80,"reps":8,"done":true,"kind":"work"}],
                  "currentSet":0,"skipped":false}],
         "currentIndex":0,"currentRestMode":"fixed","paused":false,"pausedAccumulatedS":0,"updatedTs":1001}
        """
        let snap = try JSONDecoder().decode(StrengthSessionSnapshot.self, from: Data(json.utf8))
        XCTAssertEqual(snap.runs[0].sets[0].reps, 8)
        XCTAssertNil(snap.runs[0].sets[0].mode)
    }

    func testPreservesModeAndProgramWeek() throws {
        let set = StrengthSessionSnapshot.SetSnapshot(id: "a", weightKg: 80, reps: 0, mode: .amrap)
        let run = StrengthSessionSnapshot.RunSnapshot(id: "r1", exerciseId: "press", name: "Press",
                                                       type: .weightReps, restSeconds: 90, restMode: .fixed,
                                                       hrRestReference: .restingMargin, hrRestValue: 0,
                                                       sets: [set], currentSet: 0, skipped: false)
        let snap = StrengthSessionSnapshot(id: "s1", routineId: nil, routineName: "Empuje", startTs: 1000,
                                           runs: [run], currentIndex: 0, updatedTs: 1001,
                                           programWeek: 5, deload: true)
        let data = try JSONEncoder().encode(snap)
        let back = try JSONDecoder().decode(StrengthSessionSnapshot.self, from: data)
        XCTAssertEqual(back.runs[0].sets[0].mode, .amrap)
        XCTAssertEqual(back.programWeek, 5)
        XCTAssertEqual(back.deload, true)
    }
}
