import XCTest
@testable import StrandTraining

/// Ola 2 · C1 (FER-361): the pushed seed becomes a FRESH PLAN template when the watch starts standalone —
/// a new identity, registered state cleared, the plan preserved. Guards against two days on the same plan
/// colliding on the session id, and against a stale «done» leaking into a fresh session.
final class StrengthSessionTemplateTests: XCTestCase {

    private func seed() -> StrengthSessionSnapshot {
        let s1 = StrengthSessionSnapshot.SetSnapshot(
            id: "s1", weightKg: 60, reps: 8, done: true, doneTs: 1000, kind: .work, rpe: 8,
            touched: true, restTakenS: 90, mode: .standard)
        let s2 = StrengthSessionSnapshot.SetSnapshot(
            id: "s2", weightKg: 40, reps: nil, done: false, kind: .work, mode: .amrap)  // AMRAP pending
        let run = StrengthSessionSnapshot.RunSnapshot(
            id: "r1", exerciseId: "sq", name: "Sentadilla", type: .weightReps,
            restSeconds: 120, restMode: .fixed, hrRestReference: .restingMargin, hrRestValue: 0,
            sets: [s1, s2], currentSet: 1, skipped: false)
        var snap = StrengthSessionSnapshot(
            id: "seed-id", routineId: "push", routineName: "Push A", startTs: 900,
            runs: [run], currentIndex: 1,
            restEndsAt: Date(timeIntervalSince1970: 1090), restStartedAt: Date(timeIntervalSince1970: 1000),
            currentRestTarget: 110, currentRestMode: .fixed,
            paused: true, pausedAccumulatedS: 45, pausedAt: Date(timeIntervalSince1970: 1002),
            updatedTs: 1005, restOwnerSetId: "s1")
        snap.programWeek = 3
        snap.deload = true
        return snap
    }

    func testAsTemplateMintsFreshIdentity() {
        let t = seed().asTemplate(newId: "fresh-uuid", nowTs: 5000)
        XCTAssertEqual(t.id, "fresh-uuid")          // NOT the seed's id → no PK collision across days
        XCTAssertEqual(t.startTs, 5000)
        XCTAssertEqual(t.updatedTs, 5000)
        XCTAssertEqual(t.currentIndex, 0)
    }

    func testAsTemplateClearsRegisteredAndInFlightState() {
        let t = seed().asTemplate(newId: "x", nowTs: 5000)
        XCTAssertFalse(t.paused)
        XCTAssertEqual(t.pausedAccumulatedS, 0)
        XCTAssertNil(t.restEndsAt)
        XCTAssertNil(t.restStartedAt)
        XCTAssertNil(t.currentRestTarget)
        XCTAssertNil(t.restOwnerSetId)
        XCTAssertEqual(t.runs[0].currentSet, 0)
        let s1 = t.runs[0].sets[0]
        XCTAssertFalse(s1.done)                     // a logged set from the seed is reset to pending
        XCTAssertNil(s1.doneTs)
        XCTAssertNil(s1.rpe)
        XCTAssertNil(s1.touched)
        XCTAssertNil(s1.restTakenS)
    }

    func testAsTemplatePreservesThePlan() {
        let t = seed().asTemplate(newId: "x", nowTs: 5000)
        XCTAssertEqual(t.routineName, "Push A")
        XCTAssertEqual(t.programWeek, 3)            // the served program week/deload survive
        XCTAssertEqual(t.deload, true)
        XCTAssertEqual(t.runs[0].sets[0].weightKg, 60)      // planned weight preserved
        XCTAssertEqual(t.runs[0].sets[0].id, "s1")          // set id preserved (unique within the session)
        XCTAssertEqual(t.runs[0].sets[0].mode, .standard)
        XCTAssertEqual(t.runs[0].sets[1].mode, .amrap)      // AMRAP mode preserved
        XCTAssertNil(t.runs[0].sets[1].reps)                // AMRAP stays pending (nil), not coerced to 0
    }
}
