import XCTest
@testable import StrandTraining

/// Ola 1 · E10 (FER-329 · D-Q4): los cuatro motores son DATOS sobre las plantillas ya empaquetadas.
final class ProgramTemplateTests: XCTestCase {

    func testTheFourEnginesExist() {
        XCTAssertEqual(Set(ProgramTemplate.all.map(\.id)),
                       ["linear-novice", "full-body-3", "ppl-6", "upper-lower-4"])
    }

    func testEveryEngineReferencesRealStarterTemplatesAndValidWeekdays() {
        for engine in ProgramTemplate.all {
            XCTAssertTrue(Program.appWeeks.contains(engine.weeks),
                          "\(engine.id): \(engine.weeks) semanas fuera de \(Program.appWeeks)")
            for (weekday, templateId) in engine.weekdays {
                XCTAssertTrue((1...7).contains(weekday), "\(engine.id): weekday \(weekday) inválido")
                XCTAssertNotNil(StarterTemplates.byID(templateId),
                                "\(engine.id) apunta a la plantilla inexistente \(templateId)")
            }
        }
    }

    func testEveryEngineSlotResolvesInTheCatalog() {
        for engine in ProgramTemplate.all {
            for templateId in Set(engine.weekdays.values) {
                let template = StarterTemplates.byID(templateId)!
                for slot in template.slots {
                    XCTAssertNotNil(ExerciseCatalog.byID(slot.exerciseId),
                                    "\(engine.id)/\(templateId): id desconocido \(slot.exerciseId)")
                }
            }
        }
    }

    func testPPLMaterializesThreeRoutinesForSixDaysWithoutDuplicatingSlots() {
        let engine = ProgramTemplate.byID("ppl-6")!
        let m = engine.materialize(now: 1_000, names: [:], programName: "PPL")
        XCTAssertEqual(m.routines.count, 3, "la misma rutina en dos días es UNA rutina")
        XCTAssertEqual(m.schedule.count, 6)
        XCTAssertEqual(Set(m.schedule.map(\.routineId)).count, 3)
        // Ningún ejercicio duplicado: cada rutina trae exactamente los slots de su plantilla, una vez.
        let expectedSlots = Set(engine.weekdays.values)
            .compactMap(StarterTemplates.byID)
            .reduce(0) { $0 + $1.slots.count }
        XCTAssertEqual(m.exercises.count, expectedSlots)
        XCTAssertEqual(Set(m.exercises.map(\.id)).count, m.exercises.count)
    }

    func testLinearNoviceRaisesTheBarbellInOneSessionAndKeepsRPEOff() {
        let engine = ProgramTemplate.byID("linear-novice")!
        XCTAssertEqual(engine.deloadRule, .none)
        XCTAssertFalse(engine.progressionUseRPE)
        let m = engine.materialize(now: 1_000, names: ["full-body": "Cuerpo completo"],
                                   programName: "Lineal")
        XCTAssertEqual(m.routines.count, 1)
        XCTAssertEqual(m.schedule.map(\.weekday), [2, 4, 6], "L/M/V")
        var sawBarbell = false
        var sawOther = false
        for re in m.exercises {
            XCTAssertFalse(re.progressionUseRPE)
            if ProgramTemplate.usesBarbell(exerciseId: re.exerciseId) {
                sawBarbell = true
                XCTAssertEqual(re.progressionSessions, 1, "\(re.exerciseId) es de barra: n = 1")
            } else {
                sawOther = true
                XCTAssertEqual(re.progressionSessions, 2, "\(re.exerciseId) no es de barra: n = 2")
            }
        }
        XCTAssertTrue(sawBarbell && sawOther, "la prueba necesita ambos casos para valer algo")
    }

    func testTheOtherEnginesKeepTheTwoSessionCycleEverywhere() {
        for id in ["full-body-3", "ppl-6", "upper-lower-4"] {
            let engine = ProgramTemplate.byID(id)!
            XCTAssertEqual(engine.barbellProgressionSessions, 2)
            XCTAssertEqual(engine.otherProgressionSessions, 2)
            let m = engine.materialize(now: 1_000, names: [:], programName: id)
            XCTAssertTrue(m.exercises.allSatisfy { $0.progressionSessions == 2 })
        }
    }

    func testMaterializeWritesTheProgramRowWithItsOwnRule() {
        let engine = ProgramTemplate.byID("upper-lower-4")!
        let m = engine.materialize(now: 4_242, names: [:], programName: "Torso / pierna",
                                   routineIds: ["upper": "R-UP", "lower": "R-LO"])
        XCTAssertEqual(m.program.id, Program.activeId)
        XCTAssertEqual(m.program.name, "Torso / pierna")
        XCTAssertEqual(m.program.weeks, engine.weeks)
        XCTAssertEqual(m.program.deloadRule, engine.deloadRule)
        XCTAssertEqual(m.program.endMode, engine.endMode)
        XCTAssertEqual(m.program.templateId, "upper-lower-4")
        XCTAssertEqual(m.program.startTs, 4_242)
        XCTAssertEqual(m.schedule.map(\.weekday), [2, 3, 5, 6], "torso L/J, pierna M/V")
        XCTAssertEqual(m.schedule.map(\.routineId), ["R-UP", "R-LO", "R-UP", "R-LO"])
        XCTAssertTrue(m.exercises.allSatisfy { ["R-UP", "R-LO"].contains($0.routineId) })
    }
}
