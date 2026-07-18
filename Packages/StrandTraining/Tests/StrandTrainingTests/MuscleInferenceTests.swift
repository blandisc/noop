import XCTest
@testable import StrandTraining

/// FER-995: the import flow proposes a primary muscle from the name so «create new» can't quietly
/// produce an exercise that's invisible to the muscle map, the weekly volume and `RoutineClassifier`.
final class MuscleInferenceTests: XCTestCase {

    func testInfersTheMuscleFromCommonNames() {
        let cases: [(String, String)] = [
            ("dumbbell incline bench press", "chest"),   // the name from the FER-995 report
            ("Barbell Bench Press", "chest"),
            ("Seated Cable Row", "middle back"),
            ("Lat Pulldown", "lats"),
            ("Back Squat", "quadriceps"),
            ("Romanian Deadlift", "hamstrings"),
            ("Standing Calf Raise", "calves"),
            ("Barbell Hip Thrust", "glutes"),
            ("Dumbbell Lateral Raise", "shoulders"),
            ("Triceps Pushdown", "triceps"),
            ("Hammer Curl", "biceps"),
            ("Barbell Shrug", "traps"),
            ("Hanging Leg Raise", "abdominals"),
        ]
        for (name, expected) in cases {
            XCTAssertEqual(MuscleInference.primaryMuscle(forName: name), expected, "for '\(name)'")
        }
    }

    /// The whole point of longest-phrase-wins: a specific phrase must beat a generic one it contains.
    func testTheMostSpecificPhraseWins() {
        XCTAssertEqual(MuscleInference.primaryMuscle(forName: "Leg Press"), "quadriceps")       // not chest
        XCTAssertEqual(MuscleInference.primaryMuscle(forName: "Lying Leg Curl"), "hamstrings")  // not biceps
        XCTAssertEqual(MuscleInference.primaryMuscle(forName: "Front Raise"), "shoulders")      // not calves
        XCTAssertEqual(MuscleInference.primaryMuscle(forName: "Neck Curl"), "neck")             // not biceps
        XCTAssertEqual(MuscleInference.primaryMuscle(forName: "Romanian Deadlift"), "hamstrings")  // not lower back
    }

    /// Punctuation in a plan's names must not hide a match.
    func testNormalizationHandlesPunctuationAndCase() {
        XCTAssertEqual(MuscleInference.primaryMuscle(forName: "Incline Bench Press (Barbell)"), "chest")
        XCTAssertEqual(MuscleInference.primaryMuscle(forName: "PUSH-UPS"), "chest")
        // «close grip bench» is a triceps-emphasis lift, and being the longer phrase it correctly
        // outranks the «bench press» it contains.
        XCTAssertEqual(MuscleInference.primaryMuscle(forName: "Close-Grip Bench Press"), "triceps")
        XCTAssertEqual(MuscleInference.normalize("Close-Grip  Bench/Press"), "close grip bench press")
    }

    /// Matching is whole-word, so a substring inside another word is not a match.
    func testDoesNotMatchSubstringsInsideWords() {
        XCTAssertNil(MuscleInference.primaryMuscle(forName: "pressa"))
        XCTAssertNil(MuscleInference.primaryMuscle(forName: "curler"))
    }

    /// An honest `nil` beats a confident wrong guess — the form then asks the user to pick.
    func testReturnsNilWhenNothingMatches() {
        XCTAssertNil(MuscleInference.primaryMuscle(forName: "Svend"))
        XCTAssertNil(MuscleInference.primaryMuscle(forName: ""))
        XCTAssertNil(MuscleInference.primaryMuscle(forName: "   "))
    }

    /// Every proposal must be a key the rest of the app already understands, or the muscle map and the
    /// weekly volume would silently drop it — the exact failure FER-995 is about.
    func testEveryProposedMuscleIsAKnownCatalogKey() {
        let known = Set(ExerciseCatalog.all.flatMap { $0.primaryMuscles })
        for (phrase, muscle) in MuscleInference.phrases {
            XCTAssertTrue(known.contains(muscle), "'\(phrase)' proposes unknown muscle key '\(muscle)'")
            XCTAssertNotNil(MuscleVocabulary.es[muscle], "'\(muscle)' has no Spanish label")
        }
    }

    /// The result must not depend on dictionary iteration order.
    func testIsDeterministic() {
        let name = "Barbell Bench Press"
        let results = Set((0..<50).map { _ in MuscleInference.primaryMuscle(forName: name) ?? "nil" })
        XCTAssertEqual(results, ["chest"])
    }

    /// The full chain of the FER-995 report: an exercise created from an import name the way the create
    /// sheet builds it (name + the muscle it proposed) produces the involvement events the weekly volume
    /// and the muscle map are computed from — where the old muscle-less exercise produced none at all.
    func testACreatedExerciseFeedsTheVolumeMath() {
        let name = "dumbbell incline bench press"   // the name from the report
        let muscle = MuscleInference.primaryMuscle(forName: name)
        XCTAssertEqual(muscle, "chest")

        let created = Exercise(id: "user-1", name: name, type: .weightReps, equipment: "dumbbell",
                               primaryMuscles: [muscle!], secondaryMuscles: [], instructions: [])
        let involvement = created.muscleInvolvement
        XCTAssertEqual(involvement.count, 1)
        XCTAssertEqual(involvement.first?.muscle, "chest")
        XCTAssertGreaterThan(involvement.first?.weight ?? 0, 0)

        // The regression this test exists for: the shape «create new» used to save.
        let mute = Exercise(id: "user-0", name: name, type: .weightReps, equipment: nil,
                            primaryMuscles: [], secondaryMuscles: [], instructions: [])
        XCTAssertTrue(mute.muscleInvolvement.isEmpty, "a muscle-less exercise contributes no volume")
    }

    /// The end of the chain FER-995 cares about: an inferred muscle makes the routine classify the same
    /// as if the exercise had been matched to the catalog, instead of abstaining.
    func testAnInferredMuscleLetsTheRoutineClassify() {
        let inferred = ["dumbbell incline bench press", "cable chest fly", "triceps pushdown"]
            .compactMap { MuscleInference.primaryMuscle(forName: $0) }
            .map { [$0] }
        XCTAssertEqual(inferred.count, 3)
        XCTAssertEqual(RoutineClassifier.classify(primaryMusclesPerExercise: inferred), .push)
        // Without the inference these are all `[]` — no exercise votes and the routine can't classify.
        XCTAssertNil(RoutineClassifier.classify(primaryMusclesPerExercise: [[], [], []]))
    }
}
