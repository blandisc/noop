import XCTest
@testable import StrandTraining

final class CatalogTests: XCTestCase {

    func testCatalogLoadsFromBundle() {
        // The bundled JSON decodes via Bundle.module and is the expected size.
        XCTAssertGreaterThan(ExerciseCatalog.all.count, 800,
                             "Seed catalog should hold ~873 exercises")
    }

    func testEveryEntryIsWellFormed() {
        for e in ExerciseCatalog.all {
            XCTAssertFalse(e.id.isEmpty, "exercise id must not be empty")
            XCTAssertFalse(e.name.isEmpty, "\(e.id) has empty name")
            XCTAssertFalse(e.primaryMuscles.isEmpty, "\(e.id) has no primary muscle")
            // type is a valid enum case by construction (decode would fail otherwise).
            XCTAssertTrue(ExerciseType.allCases.contains(e.type))
        }
    }

    func testIDsAreUnique() {
        let ids = ExerciseCatalog.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "catalog ids must be unique")
        // The index is built over those ids.
        XCTAssertEqual(ExerciseCatalog.index.count, ids.count)
    }

    func testByIDResolves() {
        guard let first = ExerciseCatalog.all.first else { return XCTFail("empty catalog") }
        XCTAssertEqual(ExerciseCatalog.byID(first.id), first)
        XCTAssertNil(ExerciseCatalog.byID("definitely-not-a-real-id"))
    }

    func testIsometricHoldsAreTimeBased() {
        // FER-539: isometric holds (held for time, no rep count) must be `.time`
        // so the guided session shows the timer Foco instead of asking for reps.
        let holds = ["Plank", "Side_Bridge", "Isometric_Chest_Squeezes",
                     "Isometric_Neck_Exercise_-_Front_And_Back",
                     "Isometric_Neck_Exercise_-_Sides", "Crucifix"]
        for id in holds {
            XCTAssertEqual(ExerciseCatalog.byID(id)?.type, .time,
                           "\(id) is an isometric hold and must be measured by time")
        }
    }

    func testRepMovementsStayReps() {
        // Counterexamples: "Isometric"/"Iron Cross" in the name but a dynamic rep
        // movement in the cues — must NOT be reclassified to `.time` (FER-539).
        XCTAssertEqual(ExerciseCatalog.byID("Iron_Cross")?.type, .weightReps)        // dumbbell rep movement
        XCTAssertEqual(ExerciseCatalog.byID("Cable_Iron_Cross")?.type, .weightReps)  // cable flye
        XCTAssertEqual(ExerciseCatalog.byID("Isometric_Wipers")?.type, .bodyweight)  // dynamic side-to-side
    }

    func testMuscleInvolvementWeights() {
        let e = Exercise(id: "x", name: "Bench", type: .weightReps, equipment: "barbell",
                         primaryMuscles: ["chest"], secondaryMuscles: ["triceps", "shoulders"],
                         cues: [])
        let inv = Dictionary(uniqueKeysWithValues: e.muscleInvolvement.map { ($0.muscle, $0.weight) })
        XCTAssertEqual(inv["chest"], 1.0)
        XCTAssertEqual(inv["triceps"], 0.5)
        XCTAssertEqual(inv["shoulders"], 0.5)
    }
}
