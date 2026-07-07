import XCTest
import StrandTraining
@testable import Cenit

/// FER-789 — pins the enriched rest Live Activity: the ActivityKit contract stays back-compatible across
/// an app update, and the model's phase helpers + the Completar≠Saltar distinction behave. Pure model /
/// codec — verifies headless, no widget, strap or HealthKit needed.
@MainActor
final class RestActivityFER789Tests: XCTestCase {

    // MARK: Contract back-compat

    #if canImport(ActivityKit)
    /// A ContentState encoded WITHOUT the FER-789 fields (the pre-update contract) still decodes — the new
    /// keys are Optional, so a running Activity started under the old app never crashes the widget.
    func testContentStateDecodesLegacyPayload() throws {
        let legacy = """
        {"routineName":"Push","setNumber":2,"setTotal":4,"exerciseName":"Bench",
         "returnDetail":"60 kg × 8","restStartedAt":0,"restEndsAt":90,"isHRMode":false}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(RestActivityAttributes.ContentState.self, from: legacy)
        XCTAssertNil(decoded.thumbnailName)
        XCTAssertNil(decoded.phase)
        XCTAssertNil(decoded.nextExerciseName)
        XCTAssertEqual(decoded.setNumber, 2)
    }

    /// The new fields round-trip through JSON — the widget reads exactly what the app pushed.
    func testContentStateRoundTripsNewFields() throws {
        let state = RestActivityAttributes.ContentState(
            routineName: "Push", setNumber: 3, setTotal: 4, exerciseName: "Bench",
            returnDetail: "60 kg × 8", restStartedAt: Date(timeIntervalSince1970: 0),
            restEndsAt: Date(timeIntervalSince1970: 90), isHRMode: false, hrTarget: nil, bpm: 120,
            thumbnailName: "bench.jpg", phase: .lastSetOfExercise, nextExerciseName: "Row")
        let data = try JSONEncoder().encode(state)
        let back = try JSONDecoder().decode(RestActivityAttributes.ContentState.self, from: data)
        XCTAssertEqual(back, state)
        XCTAssertEqual(back.phase, .lastSetOfExercise)
    }
    #endif

    /// The snapshot carries the new fields (raw phase + next exercise + thumbnail name) through JSON.
    func testSnapshotRoundTripsNewFields() throws {
        let snap = RestActivitySnapshot(
            sessionId: "s", routineName: "Push", setNumber: 2, setTotal: 4,
            exerciseName: "Bench", returnDetail: "60 kg × 8",
            restStartedAt: Date(timeIntervalSince1970: 0), restEndsAt: Date(timeIntervalSince1970: 90),
            isHRMode: false, hrTarget: nil, bpm: nil,
            phaseRaw: "lastSetOfRoutine", nextExerciseName: nil, thumbnailName: "bench.jpg")
        let data = try JSONEncoder().encode(snap)
        XCTAssertEqual(try JSONDecoder().decode(RestActivitySnapshot.self, from: data), snap)
    }

    // MARK: Phase helpers + Completar ≠ Saltar

    private func re(_ id: String, _ exId: String, sets: Int) -> RoutineExercise {
        RoutineExercise(id: id, routineId: "rt", exerciseId: exId, position: 0,
                        targetSets: sets, targetReps: 8, targetWeightKg: 50, restMode: .fixed, restSeconds: 60)
    }
    private func ex(_ id: String, _ name: String) -> Exercise {
        Exercise(id: id, name: name, type: .weightReps, equipment: nil,
                 primaryMuscles: [], secondaryMuscles: [], instructions: [])
    }
    private func model(_ slots: [(id: String, ex: String, sets: Int)]) -> StrengthSessionModel {
        let ps = slots.map {
            StrengthSessionModel.PlanSlot(re: re($0.id, $0.ex, sets: $0.sets), exercise: ex($0.ex, $0.ex), lastSets: [])
        }
        return StrengthSessionModel.make(routineId: "rt", routineName: "Push", slots: ps, startTs: 100)
    }

    /// The card's phase is derived from these: pendingInCurrentRun (exercise's last set) and pendingCount
    /// (routine's last set); nextPendingExerciseName drives the «Sigue: …» handoff line.
    func testPhaseHelpersAcrossExercises() {
        let s = model([(id: "a", ex: "bench", sets: 2), (id: "b", ex: "row", sets: 1)])   // 3 pending
        XCTAssertEqual(s.pendingInCurrentRun, 2)
        XCTAssertEqual(s.pendingCount, 3)
        XCTAssertEqual(s.nextPendingExerciseName, "row")
        s.registerCurrentSet()                             // bench set 1 done → focus bench's last set
        XCTAssertEqual(s.pendingInCurrentRun, 1)
        XCTAssertEqual(s.pendingCount, 2)
        s.registerCurrentSet()                             // bench done → focus row (routine's last set)
        XCTAssertEqual(s.pendingCount, 1)
        XCTAssertEqual(s.pendingInCurrentRun, 1)
    }

    /// Completar (registerCurrentSet) logs the upcoming set and rests again; Saltar (skipRest) only cuts
    /// the timer and leaves the set pending — the two must produce different data states (FER-789).
    func testCompleteVsSkipDistinction() {
        let s = model([(id: "a", ex: "bench", sets: 2)])
        s.registerCurrentSet()                             // set 1 done → resting, focus set 2
        XCTAssertEqual(s.doneCount, 1)
        XCTAssertEqual(s.phase, .resting)

        s.skipRest()                                       // Saltar: no set logged
        XCTAssertEqual(s.doneCount, 1)
        XCTAssertEqual(s.pendingCount, 1)
        XCTAssertEqual(s.phase, .capturing)

        s.registerCurrentSet()                             // Completar: logs the set
        XCTAssertEqual(s.doneCount, 2)
        XCTAssertEqual(s.pendingCount, 0)
    }
}
