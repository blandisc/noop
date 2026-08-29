import XCTest
import StrandTraining
import StrandAnalytics
import BiometricStreams
@testable import Cenit

/// FER-226 round 2 (D2): the previously-uncovered glue in `AppModel+Strength.swift` — the
/// `ingestWatchPulse` sink that had been dead since F7's band amputation. These tests drive it through
/// `AppModel` directly and assert that `avgHr`/`strain`/`energySource` stop being the permanent `nil`
/// they were before FER-226 (this repo's own `strength-session-no-hr-fer498.md` diagnosed the exact
/// symptom on the now-retired band path).
///
/// `endStrengthSession(save:)` computes `record.avgHr`/`record.strain`/`record.energySource`
/// SYNCHRONOUSLY and stashes them on `pendingStrengthSave.record` before dispatching the async
/// `attemptStrengthSave()` Task that actually talks to `CenitStore` — so these assertions never need a
/// live store/simulator; they read the pre-save payload directly.
///
/// NOTE (honesty about verification): this file could not be RUN in the implementing session —
/// `xcodebuild`/the simulator are off-limits there, and `CenitUnitTests` needs a signed simulator run
/// (App Group entitlement) per this repo's own build docs. It was verified with `swiftc -parse` only
/// (syntax, not semantics) and by careful manual reading against `AppModel+Strength.swift`. CI's
/// `ios-app` workflow (or a local `Tools/verify.sh app-tests`) is what actually executes it.
@MainActor
final class AppModelStrengthHRTests: XCTestCase {

    /// A single work set with no plan target — the minimum session that can log ≥1 done set (needed
    /// so `endStrengthSession(save:)` takes the SAVE branch, not the discard-on-zero-done branch).
    private func oneExerciseSlot() -> StrengthSessionModel.PlanSlot {
        let re = RoutineExercise(id: "re1", routineId: "rt", exerciseId: "bench", position: 0,
                                 targetSets: 1, restMode: .fixed, restSeconds: 90)
        let exercise = Exercise(id: "bench", name: "Bench", type: .weightReps, equipment: nil,
                                primaryMuscles: [], secondaryMuscles: [], instructions: [])
        return StrengthSessionModel.PlanSlot(re: re, exercise: exercise, lastSets: [])
    }

    /// Before FER-226: `ingestWatchPulse` didn't exist and nothing ever wrote `hrSamples`, so
    /// `record.avgHr`/`.strain` were permanently nil and `record.energySource` was permanently
    /// `.estimated`. After: two watch pulses a second apart (`StrengthHRIntake`'s repeated-timestamp
    /// guard forces the second call past the first whole second) land in `session.hrSamples`, and the
    /// finish-session payload reflects them — `avgHr` non-nil, `energySource` promoted past the
    /// `strengthEnergyMinSamples` floor (2), and `strain` correctly STILL nil (2 samples over ~1s is
    /// nowhere near `StrainScorer`'s minimum readings/span gate — a short session, not a fake number).
    func testIngestWatchPulseFeedsAvgHrAndEnergySourceOnFinish() {
        let model = AppModel()
        model.startStrengthSession(routineId: nil, routineName: "Test", slots: [oneExerciseSlot()])
        guard let session = model.strengthSession else {
            XCTFail("startStrengthSession must create a live session"); return
        }
        XCTAssertNil(session.hrSamples.first, "no HR captured yet")

        model.ingestWatchPulse(bpm: 120)
        // `StrengthHRIntake.accept` truncates to whole seconds and rejects a repeated timestamp — a
        // real ~1s gap is required for the second pulse to land as a DISTINCT sample (D4's fix means a
        // sub-second retry here would silently collide, same as the real DB PK).
        Thread.sleep(forTimeInterval: 1.1)
        model.ingestWatchPulse(bpm: 130)

        XCTAssertEqual(session.hrSamples.count, 2, "both distinct-second pulses must be admitted")
        XCTAssertEqual(model.watchBpm, 130, "ingestWatchPulse still publishes watchBpm for live-reading views")

        session.registerCurrentSet()   // ≥1 done set → endStrengthSession takes the SAVE branch
        XCTAssertGreaterThan(session.doneCount, 0)

        model.endStrengthSession(save: true)

        guard let record = model.pendingStrengthSave?.record else {
            XCTFail("endStrengthSession(save: true) with doneCount > 0 must stash a pendingStrengthSave"); return
        }
        XCTAssertNotNil(record.avgHr, "avgHr must no longer be permanently nil (FER-226)")
        XCTAssertEqual(record.avgHr, 125, "mean of 120 and 130")
        XCTAssertEqual(record.energySource, .bandCalculated,
                       "2 samples meets Calories.strengthEnergyMinSamples — no longer stuck at .estimated")
        XCTAssertNil(record.strain, "2 samples over ~1s is far short of StrainScorer's gate — honestly nil, not invented")
    }

    /// The complementary "no watch at all" state: zero pulses → the finish payload stays exactly as
    /// honest as before FER-226 — nil avgHr/strain, `.estimated` energy, and `pendingHrFlush` never
    /// grows (so nothing gets written to `strengthHrSample` for a session the watch never touched).
    func testNoWatchPulseKeepsSessionHonestlyEmpty() {
        let model = AppModel()
        model.startStrengthSession(routineId: nil, routineName: "Test", slots: [oneExerciseSlot()])
        guard let session = model.strengthSession else {
            XCTFail("startStrengthSession must create a live session"); return
        }
        session.registerCurrentSet()

        model.endStrengthSession(save: true)

        guard let record = model.pendingStrengthSave?.record else {
            XCTFail("endStrengthSession(save: true) with doneCount > 0 must stash a pendingStrengthSave"); return
        }
        XCTAssertNil(record.avgHr)
        XCTAssertNil(record.strain)
        XCTAssertEqual(record.energySource, .estimated)
        XCTAssertTrue(model.pendingHrFlush.isEmpty, "nothing to flush when the watch never sent a pulse")
    }

    /// D3 regression guard: two flush-triggering bursts fired back to back must not race each other's
    /// `removeFirst(count)` and silently drop samples. This test can't force a REAL race (that needs
    /// the async Task scheduler to interleave, which isn't controllable from a synchronous XCTest), but
    /// it locks the observable contract `isFlushingHR` exists to protect: a second burst that arrives
    /// while `isFlushingHR` is already true does not fire a second overlapping flush Task.
    func testOverlappingFlushGuardPreventsASecondConcurrentFlush() {
        let model = AppModel()
        model.startStrengthSession(routineId: nil, routineName: "Test", slots: [oneExerciseSlot()])
        XCTAssertFalse(model.isFlushingHR, "no flush in flight before any pulse arrives")
        model.pendingHrFlush = Array(repeating: HRSample(ts: 0, bpm: 120), count: 29)
        model.isFlushingHR = true   // simulate a flush already in flight
        model.ingestWatchPulse(bpm: 140)   // crosses the 30-sample threshold
        // The guard in `ingestWatchPulse` must have skipped firing a second flush — `isFlushingHR`
        // stays true (still "owned" by the simulated in-flight flush, not toggled by a new one that
        // never started) and the buffer still holds all 30 samples (nothing was trimmed by a flush that
        // didn't run).
        XCTAssertTrue(model.isFlushingHR)
        XCTAssertEqual(model.pendingHrFlush.count, 30)
    }
}
