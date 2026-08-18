import XCTest
@testable import StrandTraining

final class StarterTemplatesTests: XCTestCase {

    func testEverySlotReferencesARealCatalogExercise() {
        // The whole point of bundled templates: every id must resolve in the seed catalog, or the
        // copied routine would carry a dangling exercise the app can't render.
        for t in StarterTemplates.all {
            for slot in t.slots {
                XCTAssertNotNil(ExerciseCatalog.byID(slot.exerciseId),
                                "\(t.id) references unknown exercise id \(slot.exerciseId)")
            }
        }
    }

    func testAllFourProgramsAreOffered() {
        // FER-386 acceptance: PPL, full body, upper/lower, at home all present.
        for group in StarterTemplate.Group.allCases {
            XCTAssertFalse(StarterTemplates.inGroup(group).isEmpty,
                           "no template in group \(group.rawValue)")
        }
    }

    func testTemplateIDsAreUnique() {
        let ids = StarterTemplates.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "template ids must be unique")
    }

    func testTemplatesAreNonEmptyAndWellFormed() {
        for t in StarterTemplates.all {
            XCTAssertFalse(t.slots.isEmpty, "\(t.id) has no exercises")
            XCTAssertEqual(t.exerciseCount, t.slots.count)
            for slot in t.slots {
                XCTAssertGreaterThan(slot.sets, 0, "\(t.id) has a slot with no sets")
                XCTAssertGreaterThan(slot.restSeconds, 0, "\(t.id) has a slot with no rest")
            }
        }
    }

    func testMakeRoutineCopiesNameSchemeAndOrder() {
        let t = StarterTemplates.byID("ppl-push")!
        let (routine, exercises) = t.makeRoutine(name: "Empuje", now: 1_000)

        XCTAssertEqual(routine.name, "Empuje")
        XCTAssertEqual(routine.createdTs, 1_000)
        XCTAssertEqual(routine.updatedTs, 1_000)

        // One RoutineExercise per slot, in order, all pointing at the new routine.
        XCTAssertEqual(exercises.count, t.slots.count)
        for (index, (re, slot)) in zip(exercises, t.slots).enumerated() {
            XCTAssertEqual(re.routineId, routine.id)
            XCTAssertEqual(re.position, index)
            XCTAssertEqual(re.exerciseId, slot.exerciseId)
            XCTAssertEqual(re.targetSets, slot.sets)
            XCTAssertEqual(re.targetReps, slot.reps)
            XCTAssertEqual(re.restSeconds, slot.restSeconds)
            XCTAssertNil(re.targetWeightKg, "a starter template prescribes no weight — the user sets it")
        }
    }

    func testLaPlantillaDeMovilidadExisteParaSusTresPuertas() {
        // La plantilla la piden tres puertas VIVAS: el pliegue «Otra forma», la fila del día de
        // descanso y «Otra forma de entrenar». (La cuarta —la sugerencia «suave» de FER-554— se
        // retiró en FER-85; las otras tres siguen, así que la plantilla no se va con ella.)
        let t = StarterTemplates.byID("mobility")
        XCTAssertNotNil(t, "la plantilla de movilidad la necesitan el pliegue y el día de descanso")
        XCTAssertEqual(t?.group, .mobility)
        XCTAssertEqual(t?.slots.map(\.exerciseId), [
            "Chest_And_Front_Of_Shoulder_Stretch", "Worlds_Greatest_Stretch", "Cat_Stretch", "Bodyweight_Walking_Lunge", "Mountain_Climbers", "Hamstring_Stretch",
        ])
        XCTAssertEqual(StarterTemplates.inGroup(.mobility).map(\.id), ["mobility"])
    }

    func testMakeRoutineMakesAnIndependentCopyEachTime() {
        // Two copies of the same template must be distinct routines (different ids) — a copy, not a
        // live link — so editing one never touches the other or the template.
        let t = StarterTemplates.byID("full-body")!
        let (a, aExercises) = t.makeRoutine(name: "A", now: 1)
        let (b, bExercises) = t.makeRoutine(name: "B", now: 2)

        XCTAssertNotEqual(a.id, b.id)
        XCTAssertEqual(aExercises.map(\.routineId), Array(repeating: a.id, count: t.slots.count))
        XCTAssertEqual(bExercises.map(\.routineId), Array(repeating: b.id, count: t.slots.count))
        XCTAssertTrue(Set(aExercises.map(\.id)).isDisjoint(with: bExercises.map(\.id)),
                      "each copy must mint fresh RoutineExercise ids")
    }
}
