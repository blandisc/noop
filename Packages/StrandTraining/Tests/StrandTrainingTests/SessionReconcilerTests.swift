import XCTest
@testable import StrandTraining

/// Ola 2 · C1 (FER-361): the pure fusion of a watch-logged strength session with the iPhone's structure.
/// The invariant that protects the data: mode/reps travel verbatim, a watch-created drop keeps its
/// adjacency, done wins over pending, and the merge is idempotent (the durable queue may deliver twice).
final class SessionReconcilerTests: XCTestCase {

    // MARK: fixtures

    private typealias Snap = StrengthSessionSnapshot
    private typealias SetS = StrengthSessionSnapshot.SetSnapshot
    private typealias RunS = StrengthSessionSnapshot.RunSnapshot

    private func set(_ id: String, _ w: Double, reps: Int?, done: Bool, doneTs: Int? = nil,
                     mode: SetMode? = nil) -> SetS {
        SetS(id: id, weightKg: w, reps: reps, done: done, doneTs: doneTs, mode: mode)
    }

    private func run(_ id: String, _ sets: [SetS], currentSet: Int = 0, skipped: Bool = false) -> RunS {
        RunS(id: id, exerciseId: "sq", name: "Sentadilla", type: .weightReps,
             restSeconds: 120, restMode: .fixed, hrRestReference: .restingMargin, hrRestValue: 0,
             sets: sets, currentSet: currentSet, skipped: skipped)
    }

    private func session(_ runs: [RunS], programWeek: Int? = nil, deload: Bool? = nil,
                         updatedTs: Int = 0) -> Snap {
        Snap(id: "sess", routineId: "r", routineName: "A", startTs: 0, runs: runs, currentIndex: 0,
             updatedTs: updatedTs, programWeek: programWeek, deload: deload)
    }

    // MARK: done wins

    func testWatchDoneBeatsPhonePending() {
        let base = session([run("run1", [set("s1", 60, reps: 8, done: false)])])
        let incoming = session([run("run1", [set("s1", 60, reps: 8, done: true, doneTs: 100)])])
        let m = StrengthSessionReconciler.merge(base: base, incoming: incoming)
        XCTAssertEqual(m.runs[0].sets[0].done, true)
        XCTAssertEqual(m.runs[0].sets[0].doneTs, 100)
    }

    func testPhoneDoneBeatsWatchPending() {
        let base = session([run("run1", [set("s1", 60, reps: 8, done: true, doneTs: 100)])])
        let incoming = session([run("run1", [set("s1", 60, reps: 8, done: false)])])
        let m = StrengthSessionReconciler.merge(base: base, incoming: incoming)
        XCTAssertEqual(m.runs[0].sets[0].done, true)
        XCTAssertEqual(m.runs[0].sets[0].doneTs, 100)
    }

    func testTwoDoneTakesHigherDoneTs() {
        let base = session([run("run1", [set("s1", 60, reps: 8, done: true, doneTs: 100)])])
        let incoming = session([run("run1", [set("s1", 62.5, reps: 6, done: true, doneTs: 200)])])
        let m = StrengthSessionReconciler.merge(base: base, incoming: incoming)
        XCTAssertEqual(m.runs[0].sets[0].weightKg, 62.5)   // the later-logged value won
        XCTAssertEqual(m.runs[0].sets[0].reps, 6)
    }

    // MARK: mode + reps verbatim

    func testAmrapRegisteredBeatsPendingNil() {
        // AMRAP is born pending with reps == nil; once registered on the watch it carries the real count.
        let base = session([run("run1", [set("s1", 40, reps: nil, done: false, mode: .amrap)])])
        let incoming = session([run("run1", [set("s1", 40, reps: 14, done: true, doneTs: 50, mode: .amrap)])])
        let m = StrengthSessionReconciler.merge(base: base, incoming: incoming)
        XCTAssertEqual(m.runs[0].sets[0].reps, 14)          // real count, never coerced to 0
        XCTAssertEqual(m.runs[0].sets[0].mode, .amrap)      // mode verbatim
    }

    func testPendingAmrapKeepsNilReps() {
        let base = session([run("run1", [set("s1", 40, reps: nil, done: false, mode: .amrap)])])
        let incoming = session([run("run1", [set("s1", 40, reps: nil, done: false, mode: .amrap)])])
        let m = StrengthSessionReconciler.merge(base: base, incoming: incoming)
        XCTAssertNil(m.runs[0].sets[0].reps)               // still pending → still nil, not 0
        XCTAssertEqual(m.runs[0].sets[0].mode, .amrap)
    }

    // MARK: drop created on the watch

    func testWatchCreatedDropInsertedAfterItsMother() {
        // Phone has [mother]. Watch registered the mother and created a drop right after it.
        let base = session([run("run1", [set("s1", 60, reps: 8, done: false)])])
        let incoming = session([run("run1", [
            set("s1", 60, reps: 8, done: true, doneTs: 100),
            set("s1-drop", 45, reps: 10, done: true, doneTs: 110, mode: .drop),
        ])])
        let m = StrengthSessionReconciler.merge(base: base, incoming: incoming)
        XCTAssertEqual(m.runs[0].sets.map(\.id), ["s1", "s1-drop"])   // adjacency preserved
        XCTAssertEqual(m.runs[0].sets[1].mode, .drop)                 // the escalón kept its mode
        XCTAssertEqual(m.runs[0].sets[1].weightKg, 45)
    }

    func testDropAmongManySetsKeepsPosition() {
        let base = session([run("run1", [
            set("a", 60, reps: 8, done: false),
            set("b", 60, reps: 8, done: false),
            set("c", 60, reps: 8, done: false),
        ])])
        let incoming = session([run("run1", [
            set("a", 60, reps: 8, done: true, doneTs: 10),
            set("b", 60, reps: 8, done: true, doneTs: 20),
            set("b-drop", 45, reps: 9, done: true, doneTs: 25, mode: .drop),
            set("c", 60, reps: 8, done: true, doneTs: 30),
        ])])
        let m = StrengthSessionReconciler.merge(base: base, incoming: incoming)
        XCTAssertEqual(m.runs[0].sets.map(\.id), ["a", "b", "b-drop", "c"])
    }

    // MARK: idempotency

    func testIdempotent() {
        let base = session([run("run1", [
            set("s1", 60, reps: 8, done: false),
            set("s2", 60, reps: 8, done: false),
        ])])
        let incoming = session([run("run1", [
            set("s1", 60, reps: 8, done: true, doneTs: 100),
            set("s1-drop", 45, reps: 10, done: true, doneTs: 110, mode: .drop),
            set("s2", 60, reps: 7, done: true, doneTs: 120),
        ])], updatedTs: 200)
        let once = StrengthSessionReconciler.merge(base: base, incoming: incoming)
        let twice = StrengthSessionReconciler.merge(base: once, incoming: incoming)
        XCTAssertEqual(once, twice, "merge must be idempotent for the durable queue")
    }

    // MARK: structure authority

    func testProgramWeekAndDeloadComeFromBase() {
        let base = session([run("run1", [set("s1", 60, reps: 8, done: false)])],
                           programWeek: 3, deload: true)
        let incoming = session([run("run1", [set("s1", 60, reps: 8, done: true, doneTs: 100)])],
                               programWeek: 99, deload: false)   // the watch must NOT override these
        let m = StrengthSessionReconciler.merge(base: base, incoming: incoming)
        XCTAssertEqual(m.programWeek, 3)
        XCTAssertEqual(m.deload, true)
    }

    func testUntouchedRunSurvives() {
        let base = session([
            run("run1", [set("s1", 60, reps: 8, done: false)]),
            run("run2", [set("s2", 40, reps: 12, done: false)]),
        ])
        let incoming = session([run("run1", [set("s1", 60, reps: 8, done: true, doneTs: 100)])])
        let m = StrengthSessionReconciler.merge(base: base, incoming: incoming)
        XCTAssertEqual(m.runs.count, 2)
        XCTAssertEqual(m.runs[1].id, "run2")   // the run the watch never sent is preserved
    }

    // MARK: RIR scale (moved to StrandTraining for the watch, FER-361)

    func testRIRScale() {
        XCTAssertEqual(RIRScale.rpe(fromRIR: 0), 10)
        XCTAssertEqual(RIRScale.rpe(fromRIR: 2), 8)
        XCTAssertEqual(RIRScale.rpe(fromRIR: 4), 6)
        XCTAssertEqual(RIRScale.rpe(fromRIR: 9), 6)   // saturates at 4 in reserve
        XCTAssertEqual(RIRScale.reserve(fromRPE: 10), 0)
        XCTAssertEqual(RIRScale.reserve(fromRPE: 6), 4)
        XCTAssertEqual(RIRScale.label(fromRPE: 10), .atFailure)
        XCTAssertEqual(RIRScale.label(fromRPE: 8), .inReserve(2))
        XCTAssertEqual(RIRScale.label(fromRPE: 6), .fourPlus)
    }
}
