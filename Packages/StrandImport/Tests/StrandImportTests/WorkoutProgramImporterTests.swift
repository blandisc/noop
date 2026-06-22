import XCTest
@testable import StrandImport
import StrandTraining

final class WorkoutProgramImporterTests: XCTestCase {

    private let importer = WorkoutProgramImporter()

    // MARK: - Fixtures

    /// Multi-routine Spanish program: a 2-day split with reps/weight/rest/warm-up/superset + a
    /// bodyweight exercise and an omitted-tipo exercise (→ defaults to weightReps).
    private let validES = """
    { "schema":"noop.workout.v1", "idioma":"es", "unidad":"kg", "programa":"Fuerza 2 días",
      "rutinas":[
        { "nombre":"Empuje", "etiqueta":"Lunes",
          "ejercicios":[
            { "nombre":"Press de banca con barra", "tipo":"weightReps", "series":4, "reps":8,
              "peso":60, "descanso_seg":120, "calentamiento_pcts":[0.4,0.6,0.8], "superset":null },
            { "nombre":"Press militar", "series":3, "reps":10, "peso":35 }
          ] },
        { "nombre":"Jalón", "etiqueta":"Miércoles",
          "ejercicios":[
            { "nombre":"Dominadas", "tipo":"bodyweight", "series":4, "reps":8, "superset":1 },
            { "nombre":"Remo pendlay", "tipo":"weightReps", "series":4, "reps":8, "peso":70, "superset":1 }
          ] }
      ] }
    """

    // MARK: - Happy paths

    func testParsesMultiRoutineProgram() throws {
        let p = try importer.parse(text: validES)
        XCTAssertEqual(p.schema, "noop.workout.v1")
        XCTAssertEqual(p.language, .es)
        XCTAssertEqual(p.name, "Fuerza 2 días")
        XCTAssertEqual(p.routines.count, 2)

        let push = p.routines[0]
        XCTAssertEqual(push.name, "Empuje")
        XCTAssertEqual(push.tag, "Lunes")
        XCTAssertEqual(push.exercises.count, 2)

        let bench = push.exercises[0]
        XCTAssertEqual(bench.name, "Press de banca con barra")
        XCTAssertEqual(bench.type, .weightReps)
        XCTAssertEqual(bench.sets, 4)
        XCTAssertEqual(bench.reps, 8)
        XCTAssertEqual(bench.weightKg, 60)
        XCTAssertEqual(bench.restSeconds, 120)
        XCTAssertEqual(bench.warmupPercents, [0.4, 0.6, 0.8])
        XCTAssertNil(bench.supersetGroup)

        // tipo omitted → defaults to weightReps; reps/weight present, no warm-up/rest declared.
        let ohp = push.exercises[1]
        XCTAssertEqual(ohp.type, .weightReps)
        XCTAssertNil(ohp.restSeconds)
        XCTAssertEqual(ohp.warmupPercents, [])
    }

    func testSupersetGrouping() throws {
        let p = try importer.parse(text: validES)
        let pull = p.routines[1].exercises
        XCTAssertEqual(pull[0].supersetGroup, 1)
        XCTAssertEqual(pull[1].supersetGroup, 1)
        XCTAssertEqual(pull[0].type, .bodyweight)
    }

    func testPoundsNormalizeToKilograms() throws {
        let lbProgram = """
        { "schema":"noop.workout.v1", "idioma":"en", "unidad":"lb", "programa":"Imperial",
          "rutinas":[ { "nombre":"A", "ejercicios":[
            { "nombre":"Deadlift", "series":3, "reps":5, "peso":225 } ] } ] }
        """
        let p = try importer.parse(text: lbProgram)
        let kg = try XCTUnwrap(p.routines[0].exercises[0].weightKg)
        XCTAssertEqual(kg, 225 * 0.45359237, accuracy: 0.001)   // ≈ 102.06 kg
    }

    func testUnidadDefaultsToKilogramsWhenAbsent() throws {
        let noUnit = """
        { "schema":"noop.workout.v1", "idioma":"es", "programa":"X",
          "rutinas":[ { "nombre":"A", "ejercicios":[
            { "nombre":"Sentadilla", "series":5, "reps":5, "peso":100 } ] } ] }
        """
        let p = try importer.parse(text: noUnit)
        XCTAssertEqual(p.routines[0].exercises[0].weightKg, 100)
    }

    func testMissingSetsClampsToOne() throws {
        let noSets = """
        { "schema":"noop.workout.v1", "idioma":"es", "programa":"X",
          "rutinas":[ { "nombre":"A", "ejercicios":[ { "nombre":"Plancha", "tipo":"time" } ] } ] }
        """
        let p = try importer.parse(text: noSets)
        XCTAssertEqual(p.routines[0].exercises[0].sets, 1)
        XCTAssertEqual(p.routines[0].exercises[0].type, .time)
        XCTAssertNil(p.routines[0].exercises[0].weightKg)   // never invented
    }

    // MARK: - Rejections

    func testRejectsBrokenJSON() {
        XCTAssertThrowsError(try importer.parse(text: "{ not json ")) {
            XCTAssertEqual($0 as? WorkoutProgramParseError, .notJSON)
        }
    }

    func testRejectsUnknownSchema() {
        let s = """
        { "schema":"noop.diet.v1", "idioma":"es", "rutinas":[
          { "nombre":"A", "ejercicios":[ { "nombre":"X", "series":1 } ] } ] }
        """
        XCTAssertThrowsError(try importer.parse(text: s)) {
            XCTAssertEqual($0 as? WorkoutProgramParseError, .unsupportedSchema(found: "noop.diet.v1"))
        }
    }

    func testRejectsUnknownIdioma() {
        let s = """
        { "schema":"noop.workout.v1", "idioma":"de", "rutinas":[
          { "nombre":"A", "ejercicios":[ { "nombre":"X", "series":1 } ] } ] }
        """
        XCTAssertThrowsError(try importer.parse(text: s)) {
            XCTAssertEqual($0 as? WorkoutProgramParseError, .unsupportedIdioma(found: "de"))
        }
    }

    func testRejectsUnknownUnidad() {
        let s = """
        { "schema":"noop.workout.v1", "idioma":"es", "unidad":"stones", "rutinas":[
          { "nombre":"A", "ejercicios":[ { "nombre":"X", "series":1 } ] } ] }
        """
        XCTAssertThrowsError(try importer.parse(text: s)) {
            XCTAssertEqual($0 as? WorkoutProgramParseError, .unsupportedUnidad(found: "stones"))
        }
    }

    func testRejectsUnknownTipo() {
        let s = """
        { "schema":"noop.workout.v1", "idioma":"es", "rutinas":[
          { "nombre":"A", "ejercicios":[ { "nombre":"X", "tipo":"isometric", "series":1 } ] } ] }
        """
        XCTAssertThrowsError(try importer.parse(text: s)) {
            XCTAssertEqual($0 as? WorkoutProgramParseError, .unsupportedTipo(found: "isometric"))
        }
    }

    func testRejectsNoRoutines() {
        let s = #"{ "schema":"noop.workout.v1", "idioma":"es", "rutinas":[] }"#
        XCTAssertThrowsError(try importer.parse(text: s)) {
            XCTAssertEqual($0 as? WorkoutProgramParseError, .noRoutines)
        }
    }

    func testRejectsRoutineWithoutExercises() {
        let s = """
        { "schema":"noop.workout.v1", "idioma":"es", "rutinas":[
          { "nombre":"Empuje", "ejercicios":[] } ] }
        """
        XCTAssertThrowsError(try importer.parse(text: s)) {
            XCTAssertEqual($0 as? WorkoutProgramParseError, .routineWithoutExercises(name: "Empuje"))
        }
    }

    func testRejectsExerciseWithoutName() {
        let s = """
        { "schema":"noop.workout.v1", "idioma":"es", "rutinas":[
          { "nombre":"Empuje", "ejercicios":[ { "series":4, "reps":8 } ] } ] }
        """
        XCTAssertThrowsError(try importer.parse(text: s)) {
            XCTAssertEqual($0 as? WorkoutProgramParseError, .exerciseWithoutName(routine: "Empuje"))
        }
    }

    // MARK: - Reconciliation

    private func ex(_ id: String, _ name: String) -> Exercise {
        Exercise(id: id, name: name, type: .weightReps, equipment: nil,
                 primaryMuscles: [], secondaryMuscles: [], cues: [])
    }

    func testReconcilerMatchesExactlyAndByNormalization() {
        let known = [ex("benchpress", "Barbell Bench Press"), ex("squat", "Sentadilla")]
        let r = WorkoutExerciseReconciler(known: known)
        XCTAssertEqual(r.match("Barbell Bench Press")?.id, "benchpress")        // exact
        XCTAssertEqual(r.match("  barbell   bench press ")?.id, "benchpress")   // case + whitespace
        XCTAssertEqual(r.match("sentadilla")?.id, "squat")                      // case
        XCTAssertEqual(r.match("SENTÁDILLA")?.id, "squat")                      // accents folded
        XCTAssertNil(r.match("Press de banca con barra"))                       // different wording → no match
    }

    func testReconcilerListsUnmatchedNamesDedupedInOrder() throws {
        let program = try importer.parse(text: validES)   // 4 distinct names, none in this tiny catalog
        let known = [ex("ohp", "Press militar")]           // only one matches
        let r = WorkoutExerciseReconciler(known: known)
        let unmatched = r.unmatchedNames(in: program)
        XCTAssertEqual(unmatched, ["Press de banca con barra", "Dominadas", "Remo pendlay"])
    }
}
