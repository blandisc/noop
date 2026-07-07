import XCTest
@testable import StrandTraining

final class CatalogTests: XCTestCase {

    func testCatalogLoadsFromBundle() {
        // The bundled ExerciseDB catalog decodes via Bundle.module (FER-779: ~1500 exercises).
        XCTAssertGreaterThan(ExerciseCatalog.all.count, 1400,
                             "Seed catalog should hold ~1500 exercises")
    }

    func testEveryEntryIsWellFormed() {
        for e in ExerciseCatalog.all {
            XCTAssertFalse(e.id.isEmpty, "exercise id must not be empty")
            XCTAssertFalse(e.name.isEmpty, "\(e.id) has empty name")
            // Every strength move targets a muscle; cardio (bodyParts == ["cardio"]) legitimately has
            // none, since ExerciseDB's only target for it is "cardiovascular system" (no atlas region).
            if e.bodyParts != ["cardio"] {
                XCTAssertFalse(e.primaryMuscles.isEmpty, "\(e.id) has no primary muscle")
            }
            // type is a valid enum case by construction (decode would fail otherwise).
            XCTAssertTrue(ExerciseType.allCases.contains(e.type))
        }
    }

    func testIDsAreUnique() {
        let ids = ExerciseCatalog.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "catalog ids must be unique")
        XCTAssertEqual(ExerciseCatalog.index.count, ids.count)
    }

    func testByIDResolves() {
        guard let first = ExerciseCatalog.all.first else { return XCTFail("empty catalog") }
        XCTAssertEqual(ExerciseCatalog.byID(first.id), first)
        XCTAssertNil(ExerciseCatalog.byID("definitely-not-a-real-id"))
    }

    func testInstructionsAreStrippedOfStepPrefix() {
        // FER-779: the bake strips ExerciseDB's "Step:N " prefix — no instruction should start with it.
        for e in ExerciseCatalog.all {
            for step in e.instructions {
                XCTAssertFalse(step.lowercased().hasPrefix("step:"),
                               "\(e.id) instruction still carries the Step: prefix: \(step)")
            }
        }
    }

    func testTypeDistributionIsNotDegenerate() {
        // The bake derives ExerciseType heuristically (equipment/bodyParts/name). Guard against a
        // degenerate mapping (e.g. everything classified weightReps) — every type should appear.
        let byType = Dictionary(grouping: ExerciseCatalog.all, by: \.type).mapValues(\.count)
        for t in ExerciseType.allCases {
            XCTAssertGreaterThan(byType[t] ?? 0, 0, "no exercise derived as \(t)")
        }
        // Timed holds exist (planks, stretches) and rep movements dominate.
        XCTAssertGreaterThan(byType[.weightReps] ?? 0, 300)
    }

    func testMuscleInvolvementWeights() {
        let e = Exercise(id: "x", name: "Bench", type: .weightReps, equipment: "barbell",
                         primaryMuscles: ["chest"], secondaryMuscles: ["triceps", "shoulders"],
                         instructions: [])
        let inv = Dictionary(uniqueKeysWithValues: e.muscleInvolvement.map { ($0.muscle, $0.weight) })
        XCTAssertEqual(inv["chest"], 1.0)
        XCTAssertEqual(inv["triceps"], 0.5)
        XCTAssertEqual(inv["shoulders"], 0.5)
    }
}
