import XCTest
@testable import StrandTraining

final class RoutineClassifierTests: XCTestCase {

    // MARK: - Muscle → region map (FER-745 spec)

    func testMuscleRegionMap() {
        XCTAssertEqual(RoutineClassifier.region(for: "chest"), .push)
        XCTAssertEqual(RoutineClassifier.region(for: "shoulders"), .push)
        XCTAssertEqual(RoutineClassifier.region(for: "triceps"), .push)
        XCTAssertEqual(RoutineClassifier.region(for: "lats"), .pull)
        XCTAssertEqual(RoutineClassifier.region(for: "middle back"), .pull)
        XCTAssertEqual(RoutineClassifier.region(for: "biceps"), .pull)
        XCTAssertEqual(RoutineClassifier.region(for: "traps"), .pull)
        XCTAssertEqual(RoutineClassifier.region(for: "forearms"), .pull)
        XCTAssertEqual(RoutineClassifier.region(for: "quadriceps"), .legs)
        XCTAssertEqual(RoutineClassifier.region(for: "hamstrings"), .legs)
        XCTAssertEqual(RoutineClassifier.region(for: "glutes"), .legs)
        XCTAssertEqual(RoutineClassifier.region(for: "calves"), .legs)
        XCTAssertEqual(RoutineClassifier.region(for: "abductors"), .legs)
        XCTAssertEqual(RoutineClassifier.region(for: "adductors"), .legs)
    }

    func testNeutralAndUnknownMusclesAreExcluded() {
        // Neutral muscles never tip a routine — they're outside the denominator.
        XCTAssertNil(RoutineClassifier.region(for: "abdominals"))
        XCTAssertNil(RoutineClassifier.region(for: "neck"))
        XCTAssertNil(RoutineClassifier.region(for: "lower back"))
        XCTAssertNil(RoutineClassifier.region(for: "banana"))
        XCTAssertNil(RoutineClassifier.region(for: ""))
    }

    func testMuscleMapIsCaseInsensitive() {
        XCTAssertEqual(RoutineClassifier.region(for: "Chest"), .push)
        XCTAssertEqual(RoutineClassifier.region(for: "LATS"), .pull)
    }

    // MARK: - Routine classification

    func testPushHeavyRoutine() {
        let region = RoutineClassifier.classify(primaryMusclesPerExercise: [
            ["chest"], ["shoulders"], ["triceps"], ["chest"]
        ])
        XCTAssertEqual(region, .push)
    }

    func testPullHeavyRoutine() {
        // FER-775 acceptance: «Día B — Cadena posterior y jalón» (lats/dorsales predominate) → Tirón.
        let region = RoutineClassifier.classify(primaryMusclesPerExercise: [
            ["lats"], ["lats"], ["middle back"], ["biceps"]
        ])
        XCTAssertEqual(region, .pull)
    }

    func testLegHeavyRoutine() {
        let region = RoutineClassifier.classify(primaryMusclesPerExercise: [
            ["quadriceps"], ["hamstrings"], ["glutes"], ["calves"]
        ])
        XCTAssertEqual(region, .legs)
    }

    func testEvenMixIsFullBody() {
        // 1 push / 1 pull / 1 leg — no region reaches 50 % → full body.
        let region = RoutineClassifier.classify(primaryMusclesPerExercise: [
            ["chest"], ["lats"], ["quadriceps"]
        ])
        XCTAssertEqual(region, .fullBody)
    }

    func testLegsAndShouldersMix() {
        // «Día C — Piernas unilateral y hombros»: 3 legs of 4 classifiable = 75 % ≥ 50 % → Pierna.
        let region = RoutineClassifier.classify(primaryMusclesPerExercise: [
            ["quadriceps"], ["hamstrings"], ["glutes"], ["shoulders"]
        ])
        XCTAssertEqual(region, .legs)
    }

    func testExactlyFiftyPercentLeadWins() {
        // 2 legs of 4 = exactly 50 % → legs (the threshold is inclusive).
        let region = RoutineClassifier.classify(primaryMusclesPerExercise: [
            ["quadriceps"], ["glutes"], ["chest"], ["lats"]
        ])
        XCTAssertEqual(region, .legs)
    }

    func testNeutralExercisesDontCountTowardDenominator() {
        // 2 push exercises + 2 abs-only exercises → push holds 2/2 of the *voting* exercises (abs abstain).
        let region = RoutineClassifier.classify(primaryMusclesPerExercise: [
            ["chest"], ["shoulders"], ["abdominals"], ["abdominals"]
        ])
        XCTAssertEqual(region, .push)
    }

    func testMultiMuscleExerciseVotesForItsDominantMuscle() {
        // A single exercise hitting mostly legs muscles votes legs, not push.
        let region = RoutineClassifier.classify(primaryMusclesPerExercise: [
            ["quadriceps", "glutes", "shoulders"]
        ])
        XCTAssertEqual(region, .legs)
    }

    func testNoClassifiableExercisesReturnsNil() {
        // Cardio / abs-only / empty → nil, so the caller falls back to the default hue (no crash, no hash).
        XCTAssertNil(RoutineClassifier.classify(primaryMusclesPerExercise: []))
        XCTAssertNil(RoutineClassifier.classify(primaryMusclesPerExercise: [["abdominals"], ["neck"]]))
        XCTAssertNil(RoutineClassifier.classify(primaryMusclesPerExercise: [[], []]))
    }

    func testClassificationIsDeterministic() {
        // The same input always yields the same region across repeated calls (no per-process seed).
        let input = [["chest"], ["lats"], ["quadriceps"], ["shoulders"]]
        let first = RoutineClassifier.classify(primaryMusclesPerExercise: input)
        for _ in 0..<50 {
            XCTAssertEqual(RoutineClassifier.classify(primaryMusclesPerExercise: input), first)
        }
    }
}
