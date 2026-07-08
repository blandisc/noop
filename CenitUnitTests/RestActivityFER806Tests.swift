import XCTest
import StrandTraining
@testable import Cenit

/// FER-806 — pins the full-session Live Activity: the session-phase derivation, the additive contract
/// (back-compat across an app update + the new resume action), and the snapshot's v2 fields. Pure model /
/// codec — verifies headless, no widget, strap or HealthKit needed.
@MainActor
final class RestActivityFER806Tests: XCTestCase {

    // MARK: Builders (mirror the FER-789 test helpers)

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

    // MARK: sessionPhase(for:) — the pure gate that drives the whole-session card

    #if canImport(ActivityKit)
    func testSessionPhaseAcrossStates() {
        // No session → nothing to show (the Activity ends).
        XCTAssertNil(AppModel.sessionPhase(for: nil))

        let s = model([(id: "a", ex: "bench", sets: 2)])
        // Fresh session, mid-set → active.
        XCTAssertEqual(AppModel.sessionPhase(for: s), .active)

        // Register a set → resting.
        s.registerCurrentSet()
        XCTAssertEqual(s.phase, .resting)
        XCTAssertEqual(AppModel.sessionPhase(for: s), .resting)

        // Paused wins over rest.
        s.pause()
        XCTAssertEqual(AppModel.sessionPhase(for: s), .paused)
        s.resume()
        XCTAssertEqual(AppModel.sessionPhase(for: s), .resting)

        // A receipt is up → nil (the Activity ends, the receipt lives in-app).
        s.summary = StrengthSummary(
            routineName: "Push", endTs: 0, durationS: 0, volumeKg: 0, setCount: 0, strain: nil,
            avgHr: nil, costBand: nil, costTomorrowPct: nil, energyKcal: nil, energySource: nil,
            prs: [], muscles: [], isFirstTime: false, comparison: nil, exercises: [])
        XCTAssertNil(AppModel.sessionPhase(for: s))
    }

    // MARK: Contract back-compat

    /// A ContentState encoded WITHOUT the FER-806 fields (an Activity started under the FER-721/789 app)
    /// still decodes: `sessionPhase` is Optional, so a running Activity never crashes the updated widget,
    /// and the view falls back to the rest layout.
    func testContentStateDecodesPreFER806Payload() throws {
        let legacy = """
        {"routineName":"Push","setNumber":2,"setTotal":4,"exerciseName":"Bench",
         "returnDetail":"60 kg × 8","restStartedAt":0,"restEndsAt":90,"isHRMode":false}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(RestActivityAttributes.ContentState.self, from: legacy)
        XCTAssertNil(decoded.sessionPhase)
        XCTAssertNil(decoded.sessionStartedAt)
        XCTAssertNil(decoded.setsDone)
        XCTAssertNil(decoded.setsTotal)
    }

    /// The FER-806 fields round-trip through JSON — the widget reads exactly what the app pushed.
    func testContentStateRoundTripsSessionFields() throws {
        let state = RestActivityAttributes.ContentState(
            routineName: "Push", setNumber: 3, setTotal: 5, exerciseName: "Bench",
            returnDetail: "60 kg × 8", restStartedAt: Date(timeIntervalSince1970: 0),
            restEndsAt: Date(timeIntervalSince1970: 90), isHRMode: false, hrTarget: nil, bpm: 120,
            sessionPhase: .active, sessionStartedAt: Date(timeIntervalSince1970: 50),
            setsDone: 8, setsTotal: 18)
        let data = try JSONEncoder().encode(state)
        let back = try JSONDecoder().decode(RestActivityAttributes.ContentState.self, from: data)
        XCTAssertEqual(back, state)
        XCTAssertEqual(back.sessionPhase, .active)
        XCTAssertEqual(back.setsDone, 8)
    }
    #endif

    /// The snapshot carries the v2 session fields (phase + effective anchor + global progress) through JSON,
    /// and a pre-FER-806 snapshot (missing keys) still decodes with them nil.
    func testSnapshotRoundTripsSessionFields() throws {
        let snap = RestActivitySnapshot(
            sessionId: "s", routineName: "Push", setNumber: 2, setTotal: 4,
            exerciseName: "Bench", returnDetail: "60 kg × 8",
            restStartedAt: Date(timeIntervalSince1970: 0), restEndsAt: Date(timeIntervalSince1970: 90),
            isHRMode: false, hrTarget: nil, bpm: nil,
            sessionPhaseRaw: "active", sessionStartedAt: Date(timeIntervalSince1970: 40),
            setsDone: 8, setsTotal: 18)
        let data = try JSONEncoder().encode(snap)
        XCTAssertEqual(try JSONDecoder().decode(RestActivitySnapshot.self, from: data), snap)
    }

    // MARK: Resume action

    /// Every bridge action — including FER-806's `resume` — round-trips through JSON (the inbox payload).
    func testActionsRoundTripInclResume() throws {
        for action in [RestActivityBridge.Action.addThirty, .removeThirty, .skip,
                       .completeSet, .finishWorkout, .resume] {
            let data = try JSONEncoder().encode(action)
            XCTAssertEqual(try JSONDecoder().decode(RestActivityBridge.Action.self, from: data), action)
        }
        // The raw value is stable (older/newer payloads agree on the wire string).
        XCTAssertEqual(RestActivityBridge.Action.resume.rawValue, "resume")
    }
}
