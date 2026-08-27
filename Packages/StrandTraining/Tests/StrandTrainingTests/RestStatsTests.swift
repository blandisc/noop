import XCTest
@testable import StrandTraining

/// FER-167: pins `RestStats`, the pure engine behind the hub's «DESCANSO REAL» tile — a plain
/// arithmetic mean with a documented interruption cap, no black box.
final class RestStatsTests: XCTestCase {

    // MARK: - averageRestS

    func testRestStatsAverageExcludesInterruptions() {
        XCTAssertNil(RestStats.averageRestS([]), "no data → nil, never 0")
        XCTAssertEqual(RestStats.averageRestS([90, 90, 90]), 90, "plain mean")
        XCTAssertEqual(RestStats.averageRestS([90, 150]), 120, "rounds to nearest")
        // A 20-minute gap (1200 s) is an interruption (phone locked, chatting), not rest — excluded.
        XCTAssertEqual(RestStats.averageRestS([90, 110, 1200]), 100,
                       "an interruption above the cap is excluded from the mean")
        // Exactly the cap (900 s) is still counted — the cap is inclusive.
        XCTAssertEqual(RestStats.averageRestS([RestStats.interruptionCapS]), RestStats.interruptionCapS,
                       "the cap itself still counts as rest, not interruption")
        // Every value is an interruption → nothing left to average.
        XCTAssertNil(RestStats.averageRestS([1000, 2000]), "all-interruption input → nil, not 0")
    }

    func testRestStatsAverageRespectsCustomCap() {
        XCTAssertEqual(RestStats.averageRestS([100, 500], interruptionCapS: 200), 100,
                       "a caller-supplied cap excludes 500 the same way the default cap excludes 1200")
    }

    // MARK: - plannedAverageRestS

    private func re(_ id: String, restSeconds: Int, sets: [RoutineSet]) -> RoutineExercise {
        RoutineExercise(id: id, routineId: "rt", exerciseId: id, position: 0, targetSets: sets.count,
                        restMode: .fixed, restSeconds: restSeconds, sets: sets)
    }

    /// A set's own `rest` override wins; a set with no override falls back to the exercise default —
    /// the same `effectiveRest(for:)` rule the live session uses, so plan and reality speak the same
    /// language.
    func testRestStatsPlannedUsesEffectiveRestFallback() {
        let override = RestConfig(mode: .fixed, seconds: 200)
        let ex = re("a", restSeconds: 90, sets: [
            RoutineSet(position: 0, kind: .work, reps: 8, weightKg: 60, rest: override),   // 200s override
            RoutineSet(position: 1, kind: .work, reps: 8, weightKg: 60),                   // falls back to 90s
        ])
        // (200 + 90) / 2 = 145
        XCTAssertEqual(RestStats.plannedAverageRestS([ex]), 145)
    }

    /// Warm-ups don't carry a rest prescription worth averaging — only work sets count.
    func testRestStatsPlannedExcludesWarmups() {
        let ex = re("a", restSeconds: 90, sets: [
            RoutineSet(position: 0, kind: .warmup, reps: 10, weightKg: 30),
            RoutineSet(position: 1, kind: .work, reps: 8, weightKg: 60),
        ])
        XCTAssertEqual(RestStats.plannedAverageRestS([ex]), 90, "only the work set's rest counts")
    }

    /// A «sin descanso» exercise (fixed, 0 s) contributes nothing to the plan average, same as a work
    /// set never contributes a rest-free row.
    func testRestStatsPlannedExcludesZeroRestSets() {
        let ex = re("a", restSeconds: 0, sets: [RoutineSet(position: 0, kind: .work, reps: 8, weightKg: 60)])
        XCTAssertNil(RestStats.plannedAverageRestS([ex]), "no set with rest > 0 → nil")
    }

    func testRestStatsPlannedEmptyRoutineIsNil() {
        XCTAssertNil(RestStats.plannedAverageRestS([]))
    }

    /// In HR-driven rest, `seconds` is the ceiling the countdown falls back to, not a target — the
    /// plan average compares against that ceiling exactly as documented, no special-casing.
    func testRestStatsPlannedTreatsHRSecondsAsCeiling() {
        let ex = RoutineExercise(id: "a", routineId: "rt", exerciseId: "a", position: 0, targetSets: 1,
                                 restMode: .heartRate, restSeconds: 180,
                                 sets: [RoutineSet(position: 0, kind: .work, reps: 8, weightKg: 60)])
        XCTAssertEqual(RestStats.plannedAverageRestS([ex]), 180)
    }
}
