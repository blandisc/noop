import XCTest
import StrandTraining
import StrandAnalytics
@testable import Cenit

/// FER-82 — the app-layer half of «un solo oráculo», where the pure mapping meets the screen.
///
/// The acceptance criterion is a UI rule: «no existe combinación en la que la pantalla muestre "Hoy
/// subes" junto a un veredicto caution o easy». The hero's «Hoy subes» is fed by exactly one thing —
/// `ProgressionPlanner.evaluate`'s applied raise — and the session's table by exactly one other — the
/// seed `StrengthSessionModel.make` builds from it. This suite drives both with a history that HAS
/// earned the raise, across every advice, so the rule is checked where the screen reads it, not only
/// where the mapping is written.
@MainActor
final class SingleOracleSeedTests: XCTestCase {

    private let allAdvice: [TrainingRegulation.Advice] = [.planAsIs, .lighter, .recover, .silent, .pending]

    /// A slot that has earned its raise: 3×8 at 80 kg, twice, with progression on.
    private func earnedSlot() -> RoutineExercise {
        RoutineExercise(id: "a", routineId: "rt", exerciseId: "bench", position: 0,
                        targetSets: 3, targetReps: 8, targetWeightKg: 80,
                        restMode: .fixed, restSeconds: 90,
                        progressionEnabled: true, progressionSessions: 2, progressionIncrementKg: 2.5)
    }

    private func earnedHistory() -> [(startTs: Int, weightKg: Double, reps: Int, optedOut: Bool)] {
        [1, 2].flatMap { session in
            (0..<3).map { _ in (startTs: session * 1000, weightKg: 80.0, reps: 8, optedOut: false) }
        }
    }

    private func evaluate(_ advice: TrainingRegulation.Advice)
        -> (state: ProgressionState, raise: ProgressionPlanner.Raise?)? {
        ProgressionPlanner.evaluate(re: earnedSlot(), history: earnedHistory(),
                                    inventory: [], equipment: nil, advice: advice)
    }

    // MARK: The rule, at the surface that renders it

    /// «Hoy subes» is drawn ONLY from an applied raise (`waiting == false`). No advice that eases off
    /// may ever produce one — this is the criterion, checked at the planner the hero reads.
    func testNoEasingAdviceEverProducesAnAppliedRaise() {
        for advice in allAdvice {
            guard let result = evaluate(advice) else { return XCTFail("\(advice): no evaluation") }
            let applied = result.raise.map { !$0.waiting } ?? false
            XCTAssertEqual(applied, TrainingRegulation.allowsRaise(advice),
                           "\(advice): applied raise must match the advice's permission")
        }
    }

    /// A held raise is held, not lost: the kilo is still there, flagged as waiting, so the session can
    /// offer it in one tap and the hero can name it.
    func testHeldRaiseKeepsItsWeightAndIsFlagged() {
        for advice in allAdvice where !TrainingRegulation.allowsRaise(advice) {
            guard let result = evaluate(advice), let raise = result.raise else {
                return XCTFail("\(advice): the earned raise must survive as an offer")
            }
            XCTAssertTrue(raise.waiting, "\(advice)")
            XCTAssertEqual(raise.toKg, 82.5, accuracy: 0.0001, "\(advice)")
            XCTAssertEqual(raise.fromKg, 80, accuracy: 0.0001, "\(advice)")
            XCTAssertFalse(raise.phrase.isEmpty, "\(advice): a held raise still explains itself")
            guard case .deferred = result.state else {
                return XCTFail("\(advice): expected .deferred, got \(result.state)")
            }
        }
    }

    func testCleanDayAppliesTheRaise() {
        guard let result = evaluate(.planAsIs), let raise = result.raise else {
            return XCTFail("expected a raise")
        }
        XCTAssertFalse(raise.waiting)
        XCTAssertEqual(raise.toKg, 82.5, accuracy: 0.0001)
        guard case .readyToAdvance = result.state else {
            return XCTFail("expected .readyToAdvance, got \(result.state)")
        }
    }

    /// No usable read is not a reason to hold back what the log earned: the plan runs as written.
    func testUnreadableDayStillAppliesTheRaise() {
        guard let result = evaluate(.silent), let raise = result.raise else {
            return XCTFail("expected a raise")
        }
        XCTAssertFalse(raise.waiting, "a silent day must not quietly withhold the raise")
    }

    // MARK: The seeding rule the owner decided

    /// «Con ámbar o rojo la sesión se siembra con el peso de la última vez, y la subida queda a un
    /// toque»: every work cell opens at 80, not 82.5, while the offer travels with the run.
    func testHeldRaiseSeedsAtLastTimesWeight() {
        guard let raise = evaluate(.lighter)?.raise else { return XCTFail("expected a held raise") }
        let slot = StrengthSessionModel.PlanSlot(
            re: earnedSlot(),
            exercise: Exercise(id: "bench", name: "Bench", type: .weightReps, equipment: nil,
                               primaryMuscles: [], secondaryMuscles: [], instructions: []),
            lastSets: [SetEntry(id: "s1", sessionId: "s", exerciseId: "bench", position: 0,
                                kind: .work, weightKg: 80, reps: 8, done: true, ts: 1000)],
            raise: raise)
        let session = StrengthSessionModel.make(routineId: "rt", routineName: "Push",
                                                slots: [slot], startTs: 100)
        let run = session.runs.first
        XCTAssertEqual(run?.sets.count, 3)
        for set in run?.sets ?? [] {
            XCTAssertEqual(set.weightKg, 80, accuracy: 0.0001, "a held raise must not seed the table")
        }
        XCTAssertEqual(run?.proposedRaise?.toKg, 82.5, "the offer travels into the session")
        XCTAssertEqual(run?.proposedRaise?.waiting, true)
    }

    /// An applied raise keeps seeding every work set, unchanged (FER-E, owner's decision: all sets).
    func testAppliedRaiseStillSeedsEveryWorkSet() {
        guard let raise = evaluate(.planAsIs)?.raise else { return XCTFail("expected a raise") }
        let slot = StrengthSessionModel.PlanSlot(
            re: earnedSlot(),
            exercise: Exercise(id: "bench", name: "Bench", type: .weightReps, equipment: nil,
                               primaryMuscles: [], secondaryMuscles: [], instructions: []),
            lastSets: [SetEntry(id: "s1", sessionId: "s", exerciseId: "bench", position: 0,
                                kind: .work, weightKg: 80, reps: 8, done: true, ts: 1000)],
            raise: raise)
        let session = StrengthSessionModel.make(routineId: "rt", routineName: "Push",
                                                slots: [slot], startTs: 100)
        for set in session.runs.first?.sets ?? [] {
            XCTAssertEqual(set.weightKg, 82.5, accuracy: 0.0001, "every work set arrives at the new load")
        }
    }

    // MARK: Taking the held raise

    /// The offer applies to every UNDONE work set at once — the all-sets rule the owner kept — and
    /// leaves what was already lifted alone.
    func testTakingTheHeldRaiseMovesEveryPendingWorkSet() {
        guard let raise = evaluate(.lighter)?.raise else { return XCTFail("expected a held raise") }
        let session = sessionWith(raise)
        session.runs[0].sets[0].done = true            // one set already lifted at the old weight
        XCTAssertTrue(session.canTakeHeldRaise(at: 0))
        XCTAssertTrue(session.takeHeldRaise(at: 0))
        XCTAssertEqual(session.runs[0].sets[0].weightKg, 80, accuracy: 0.0001, "a done set is history")
        XCTAssertEqual(session.runs[0].sets[1].weightKg, 82.5, accuracy: 0.0001)
        XCTAssertEqual(session.runs[0].sets[2].weightKg, 82.5, accuracy: 0.0001)
        XCTAssertEqual(session.runs[0].proposedRaise?.waiting, false, "the line stops waiting")
    }

    /// An exercise with nothing left to lift offers nothing: taking it would move no weight while the
    /// screen turned green claiming today's load rose.
    func testAFinishedExerciseCannotTakeTheRaise() {
        guard let raise = evaluate(.lighter)?.raise else { return XCTFail("expected a held raise") }
        let session = sessionWith(raise)
        for i in session.runs[0].sets.indices { session.runs[0].sets[i].done = true }
        XCTAssertFalse(session.canTakeHeldRaise(at: 0))
        XCTAssertFalse(session.takeHeldRaise(at: 0), "nothing to take")
        XCTAssertEqual(session.runs[0].proposedRaise?.waiting, true, "and the line keeps saying so")
        for set in session.runs[0].sets {
            XCTAssertEqual(set.weightKg, 80, accuracy: 0.0001, "no weight moved")
        }
    }

    /// Taking twice is not a way to raise twice.
    func testTakingTwiceIsANoOp() {
        guard let raise = evaluate(.lighter)?.raise else { return XCTFail("expected a held raise") }
        let session = sessionWith(raise)
        XCTAssertTrue(session.takeHeldRaise(at: 0))
        XCTAssertFalse(session.takeHeldRaise(at: 0))
        for set in session.runs[0].sets {
            XCTAssertEqual(set.weightKg, 82.5, accuracy: 0.0001)
        }
    }

    /// The held table opens at the weight the raise climbs FROM (the cycle's working load), not at the
    /// last row logged — which may be a lighter back-off set the hero never mentioned.
    func testHeldTableOpensAtTheCycleWeightNotTheLastBackOffSet() {
        guard let raise = evaluate(.lighter)?.raise else { return XCTFail("expected a held raise") }
        let slot = StrengthSessionModel.PlanSlot(
            re: earnedSlot(),
            exercise: Exercise(id: "bench", name: "Bench", type: .weightReps, equipment: nil,
                               primaryMuscles: [], secondaryMuscles: [], instructions: []),
            // Last session ended with a 60 kg back-off set; the cycle's working weight is still 80.
            lastSets: [SetEntry(id: "s1", sessionId: "s", exerciseId: "bench", position: 3,
                                kind: .work, weightKg: 60, reps: 10, done: true, ts: 2000)],
            raise: raise)
        let session = StrengthSessionModel.make(routineId: "rt", routineName: "Push",
                                                slots: [slot], startTs: 100)
        for set in session.runs.first?.sets ?? [] {
            XCTAssertEqual(set.weightKg, 80, accuracy: 0.0001,
                           "opens at the weight the promised raise climbs from")
        }
    }

    // MARK: The offer survives a crash

    private func sessionWith(_ raise: ProgressionPlanner.Raise?) -> StrengthSessionModel {
        let slot = StrengthSessionModel.PlanSlot(
            re: earnedSlot(),
            exercise: Exercise(id: "bench", name: "Bench", type: .weightReps, equipment: nil,
                               primaryMuscles: [], secondaryMuscles: [], instructions: []),
            lastSets: [SetEntry(id: "s1", sessionId: "s", exerciseId: "bench", position: 0,
                                kind: .work, weightKg: 80, reps: 8, done: true, ts: 1000)],
            raise: raise)
        return StrengthSessionModel.make(routineId: "rt", routineName: "Push",
                                         slots: [slot], startTs: 100)
    }

    /// A held raise is the ONLY place the one-tap offer lives, so it has to survive a crash: after a
    /// restore the table is still at last time's weight and the raise is still one tap away.
    func testHeldOfferSurvivesTheCrashSnapshot() {
        guard let raise = evaluate(.lighter)?.raise else { return XCTFail("expected a held raise") }
        let restored = StrengthSessionModel.restore(from: sessionWith(raise).snapshot(now: 200))
        let run = restored.runs.first
        XCTAssertEqual(run?.proposedRaise?.toKg, 82.5)
        XCTAssertEqual(run?.proposedRaise?.fromKg, 80)
        XCTAssertEqual(run?.proposedRaise?.waiting, true)
        XCTAssertEqual(run?.proposedRaise?.phrase, raise.phrase, "the why survives with the offer")
        for set in run?.sets ?? [] {
            XCTAssertEqual(set.weightKg, 80, accuracy: 0.0001, "the table stays where it opened")
        }
    }

    /// An applied raise is already in the weights, so it does not travel (pre-FER-82 behaviour kept):
    /// what must survive is the load the athlete is lifting, and it does.
    func testAppliedRaiseKeepsItsWeightsThroughARestore() {
        guard let raise = evaluate(.planAsIs)?.raise else { return XCTFail("expected a raise") }
        let restored = StrengthSessionModel.restore(from: sessionWith(raise).snapshot(now: 200))
        let run = restored.runs.first
        XCTAssertNil(run?.proposedRaise, "an applied raise is not re-offered")
        for set in run?.sets ?? [] {
            XCTAssertEqual(set.weightKg, 82.5, accuracy: 0.0001, "the raised load survives")
        }
    }

    /// A snapshot written before FER-82 (no `heldRaise` key) still decodes, with no offer.
    func testPreFER82SnapshotDecodesWithoutAnOffer() throws {
        let snap = sessionWith(nil).snapshot(now: 200)
        let json = try JSONEncoder().encode(snap)
        var object = try XCTUnwrap(try JSONSerialization.jsonObject(with: json) as? [String: Any])
        var runs = try XCTUnwrap(object["runs"] as? [[String: Any]])
        runs = runs.map { var r = $0; r.removeValue(forKey: "heldRaise"); return r }
        object["runs"] = runs
        let stripped = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(StrengthSessionSnapshot.self, from: stripped)
        XCTAssertNil(StrengthSessionModel.restore(from: decoded).runs.first?.proposedRaise)
    }

    /// The per-exercise opt-out («ignora mi recuperación aquí») still wins over the day's verdict.
    func testPerExerciseOptOutIgnoresTheVerdict() {
        var re = earnedSlot()
        re.progressionIgnoreRecovery = true
        let result = ProgressionPlanner.evaluate(re: re, history: earnedHistory(),
                                                 inventory: [], equipment: nil, advice: .recover)
        XCTAssertEqual(result?.raise?.waiting, false, "the opt-out keeps the raise on the log alone")
    }
}
