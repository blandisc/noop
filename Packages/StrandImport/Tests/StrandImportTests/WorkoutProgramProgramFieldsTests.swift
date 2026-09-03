import XCTest
@testable import StrandImport
import StrandTraining

/// Ola 1 · E10 (FER-329): los campos de PROGRAMA del formato `noop.workout.v1` — `semanas`,
/// `semana_ligera`, `al_terminar` y el `dia` por rutina. Todos opcionales y retrocompatibles.
final class WorkoutProgramProgramFieldsTests: XCTestCase {

    private let importer = WorkoutProgramImporter()

    /// El payload v1 de siempre, sin un solo campo de programa.
    private let legacy = """
    { "schema":"noop.workout.v1", "idioma":"es", "programa":"Fuerza",
      "rutinas":[ { "nombre":"A", "ejercicios":[ { "nombre":"Sentadilla", "series":3, "reps":5 } ] } ] }
    """

    private func payload(program extra: String, routines: String? = nil) -> String {
        let r = routines ?? """
        [ { "nombre":"A", "ejercicios":[ { "nombre":"Sentadilla", "series":3, "reps":5 } ] } ]
        """
        return """
        { "schema":"noop.workout.v1", "idioma":"es", "programa":"Fuerza", \(extra)
          "rutinas": \(r) }
        """
    }

    // MARK: - Retrocompatibilidad

    func testLegacyPayloadParsesWithNoProgram() throws {
        let p = try importer.parse(text: legacy)
        XCTAssertNil(p.weeks, "sin «semanas» el archivo no trae programa")
        XCTAssertEqual(p.deloadRule, DeloadRule.none)
        XCTAssertEqual(p.endMode, .repeat)
        XCTAssertTrue(p.warnings.isEmpty)
        XCTAssertNil(p.routines[0].planDay)
        XCTAssertNil(p.routines[0].week)
    }

    // MARK: - semanas (4…8 en import, sin clamp)

    func testFiveAndEightWeeksParse() throws {
        XCTAssertEqual(try importer.parse(text: payload(program: "\"semanas\":5,")).weeks, 5)
        XCTAssertEqual(try importer.parse(text: payload(program: "\"semanas\":8,")).weeks, 8)
    }

    func testWeeksOutsideTheImportRangeAreRejectedNotClamped() {
        for bad in [3, 9] {
            XCTAssertThrowsError(try importer.parse(text: payload(program: "\"semanas\":\(bad),"))) {
                XCTAssertEqual($0 as? WorkoutProgramParseError, .unsupportedSemanas(found: bad))
            }
        }
    }

    func testTheImportRangeIsWiderThanTheAppRange() throws {
        // 7 y 8 son válidas al importar el bloque de un coach, aunque la app solo ofrezca 4·5·6.
        XCTAssertFalse(Program.appWeeks.contains(8))
        XCTAssertEqual(try importer.parse(text: payload(program: "\"semanas\":7,")).weeks, 7)
    }

    // MARK: - semana_ligera / al_terminar

    func testLightWeekAndEndModeMapFromTheWire() throws {
        let a = try importer.parse(text: payload(program: "\"semanas\":5,\"semana_ligera\":\"menos_series\","))
        XCTAssertEqual(a.deloadRule, .volumeOnly)
        let b = try importer.parse(
            text: payload(program: "\"semanas\":5,\"semana_ligera\":\"menos_series_y_peso\",\"al_terminar\":\"un_ciclo\","))
        XCTAssertEqual(b.deloadRule, .volumeAndLoad)
        XCTAssertEqual(b.endMode, .single)
        let c = try importer.parse(text: payload(program: "\"semana_ligera\":\"ninguna\",\"al_terminar\":\"repetir\","))
        XCTAssertEqual(c.deloadRule, DeloadRule.none)
        XCTAssertEqual(c.endMode, .repeat)
    }

    func testAnExplicitUnknownValueIsRejected() {
        XCTAssertThrowsError(try importer.parse(text: payload(program: "\"semana_ligera\":\"mitad\","))) {
            XCTAssertEqual($0 as? WorkoutProgramParseError, .unsupportedSemanaLigera(found: "mitad"))
        }
        XCTAssertThrowsError(try importer.parse(text: payload(program: "\"al_terminar\":\"otra_cosa\","))) {
            XCTAssertEqual($0 as? WorkoutProgramParseError, .unsupportedAlTerminar(found: "otra_cosa"))
        }
    }

    // MARK: - dia

    func testDeclaredDaysAreHonouredAndTheRestFillFreeDays() throws {
        let routines = """
        [ { "nombre":"A", "dia":3, "ejercicios":[ { "nombre":"X", "series":3 } ] },
          { "nombre":"B", "ejercicios":[ { "nombre":"Y", "series":3 } ] },
          { "nombre":"C", "dia":5, "ejercicios":[ { "nombre":"Z", "series":3 } ] } ]
        """
        let p = try importer.parse(text: payload(program: "\"semanas\":4,", routines: routines))
        XCTAssertEqual(p.routines.map(\.planDay), [3, nil, 5])
        // plan 3 = miércoles → Calendar 4; plan 5 = viernes → Calendar 6; B toma el primer día libre
        // (lunes = plan 1 → Calendar 2).
        XCTAssertEqual(p.assignedWeekdays(), [4, 2, 6])
    }

    func testAnOutOfRangeDayIsIgnoredNotHonoured() throws {
        let routines = """
        [ { "nombre":"A", "dia":9, "ejercicios":[ { "nombre":"X", "series":3 } ] } ]
        """
        let p = try importer.parse(text: payload(program: "", routines: routines))
        XCTAssertNil(p.routines[0].planDay)
        XCTAssertEqual(p.assignedWeekdays(), [2], "cae en el primer día libre: lunes")
    }

    func testWithNoDaysAtAllTheSplitLaysOutMondayFirst() throws {
        let routines = """
        [ { "nombre":"A", "ejercicios":[ { "nombre":"X", "series":3 } ] },
          { "nombre":"B", "ejercicios":[ { "nombre":"Y", "series":3 } ] },
          { "nombre":"C", "ejercicios":[ { "nombre":"Z", "series":3 } ] } ]
        """
        let p = try importer.parse(text: payload(program: "", routines: routines))
        XCTAssertEqual(p.assignedWeekdays(), [2, 3, 4], "L, M, X en convención Calendar")
    }

    func testPlanDayToCalendarWeekdayIsTheOneConversion() {
        // plan 1…7 = lunes…domingo → Calendar 2,3,4,5,6,7,1.
        XCTAssertEqual((1...7).map(WorkoutProgram.calendarWeekday(planDay:)), [2, 3, 4, 5, 6, 7, 1])
    }

    // MARK: - semanas distintas entre sí

    func testWeeksThatDifferWarnInsteadOfFailing() throws {
        let routines = """
        [ { "nombre":"S1-A", "semana":1, "ejercicios":[ { "nombre":"X", "series":3 } ] },
          { "nombre":"S1-B", "semana":1, "ejercicios":[ { "nombre":"Y", "series":3 } ] },
          { "nombre":"S2-A", "semana":2, "ejercicios":[ { "nombre":"Z", "series":4 } ] } ]
        """
        let p = try importer.parse(text: payload(program: "\"semanas\":4,", routines: routines))
        XCTAssertEqual(p.warnings, [.weeksDiffer])
        XCTAssertEqual(p.routines.map(\.name), ["S1-A", "S1-B"], "se importa la semana 1")
        XCTAssertEqual(p.weeks, 4, "el bloque sigue siendo de 4 semanas: se repite la semana 1")
    }

    func testAllRoutinesInTheSameWeekIsNotAWarning() throws {
        let routines = """
        [ { "nombre":"A", "semana":1, "ejercicios":[ { "nombre":"X", "series":3 } ] },
          { "nombre":"B", "semana":1, "ejercicios":[ { "nombre":"Y", "series":3 } ] } ]
        """
        let p = try importer.parse(text: payload(program: "\"semanas\":4,", routines: routines))
        XCTAssertTrue(p.warnings.isEmpty)
        XCTAssertEqual(p.routines.count, 2)
    }
}
