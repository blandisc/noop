import XCTest
@testable import StrandImport
import WhoopStore

final class DietPlanImporterTests: XCTestCase {

    private let importer = DietPlanImporter()

    // MARK: - Fixtures

    /// Full Spanish plan: equivalentes, hora_sugerida, notas, objetivos, reglas.
    private let validES = """
    { "schema":"noop.diet.v1", "idioma":"es", "nombre":"Plan Dra. Pérez", "ciclo":"diario",
      "comidas":[
        { "id":"desayuno", "nombre":"Desayuno", "hora_sugerida":"08:00",
          "opciones":[ {"alimentos":["2 huevos","40 g avena","1 taza fruta"]} ],
          "notas":"Sin azúcar" },
        { "id":"comida", "nombre":"Comida",
          "opciones":[ {"alimentos":["150 g pollo","1 taza arroz","ensalada"]},
                       {"alimentos":["150 g pescado","verduras"]} ] }
      ],
      "objetivos_diarios":{ "calorias_kcal":1800, "proteina_g":130 },
      "reglas":["No comer después de las 21:00"] }
    """

    /// English plan — names stay in English; language is en.
    private let validEN = """
    { "schema":"noop.diet.v1", "idioma":"en", "nombre":"Dr. Smith plan", "ciclo":"diario",
      "comidas":[
        { "id":"breakfast", "nombre":"Breakfast",
          "opciones":[ {"alimentos":["2 eggs","oatmeal","1 cup fruit"]} ] }
      ] }
    """

    // MARK: - Valid

    func testParsesValidSpanishPlan() throws {
        let plan = try importer.parse(text: validES)
        XCTAssertEqual(plan.schema, "noop.diet.v1")
        XCTAssertEqual(plan.language, .es)
        XCTAssertEqual(plan.name, "Plan Dra. Pérez")
        XCTAssertEqual(plan.cycle, .diario)
        XCTAssertEqual(plan.meals.count, 2)

        let desayuno = plan.meals[0]
        XCTAssertEqual(desayuno.id, "desayuno")
        XCTAssertEqual(desayuno.suggestedTime, "08:00")
        XCTAssertEqual(desayuno.notes, "Sin azúcar")
        XCTAssertEqual(desayuno.options.count, 1)
        XCTAssertEqual(desayuno.options[0].foods, ["2 huevos", "40 g avena", "1 taza fruta"])

        // Equivalentes preserved as multiple options.
        XCTAssertEqual(plan.meals[1].options.count, 2)
        XCTAssertEqual(plan.meals[1].options[1].foods, ["150 g pescado", "verduras"])

        XCTAssertEqual(plan.dailyTargets, ["calorias_kcal": 1800, "proteina_g": 130])
        XCTAssertEqual(plan.rules, ["No comer después de las 21:00"])
    }

    func testParsesValidEnglishPlan() throws {
        let plan = try importer.parse(text: validEN)
        XCTAssertEqual(plan.language, .en)
        XCTAssertEqual(plan.meals[0].options[0].foods, ["2 eggs", "oatmeal", "1 cup fruit"])
        XCTAssertNil(plan.dailyTargets)   // absent → nil, never invented
        XCTAssertNil(plan.rules)
    }

    /// Food names are kept verbatim — never translated or normalized.
    func testDoesNotTranslateNames() throws {
        let es = try importer.parse(text: validES)
        let en = try importer.parse(text: validEN)
        XCTAssertEqual(es.meals[0].name, "Desayuno")
        XCTAssertEqual(en.meals[0].name, "Breakfast")
        XCTAssertTrue(es.meals[0].options[0].foods.contains("2 huevos"))
        XCTAssertTrue(en.meals[0].options[0].foods.contains("2 eggs"))
    }

    /// Unknown fields (top-level, per-meal, per-option) are ignored for forward-compatibility.
    func testIgnoresUnknownFields() throws {
        let json = """
        { "schema":"noop.diet.v1", "idioma":"es", "nombre":"X", "ciclo":"diario",
          "version_app":"9.9", "extra_top":{"a":1},
          "comidas":[ { "id":"d", "nombre":"D", "color":"rojo",
            "opciones":[ {"alimentos":["a"], "kcal":99} ] } ] }
        """
        let plan = try importer.parse(text: json)
        XCTAssertEqual(plan.meals.count, 1)
        XCTAssertEqual(plan.meals[0].options[0].foods, ["a"])
    }

    /// An empty objetivos_diarios object normalizes to nil (no targets).
    func testEmptyDailyTargetsNormalizesToNil() throws {
        let json = """
        { "schema":"noop.diet.v1", "idioma":"es", "nombre":"X", "ciclo":"diario",
          "objetivos_diarios":{},
          "comidas":[ { "id":"d", "opciones":[ {"alimentos":["a"]} ] } ] }
        """
        XCTAssertNil(try importer.parse(text: json).dailyTargets)
    }

    /// ciclo absent defaults to diario.
    func testMissingCicloDefaultsToDiario() throws {
        let json = """
        { "schema":"noop.diet.v1", "idioma":"es", "nombre":"X",
          "comidas":[ { "id":"d", "opciones":[ {"alimentos":["a"]} ] } ] }
        """
        XCTAssertEqual(try importer.parse(text: json).cycle, .diario)
    }

    // MARK: - Invalid

    func testRejectsNonJSON() {
        assertThrows("no soy json {", .notJSON)
        assertThrows("[1,2,3]", .notJSON)   // top-level not an object
    }

    func testRejectsUnsupportedSchema() {
        assertThrows(#"{ "schema":"noop.diet.v2", "idioma":"es", "comidas":[{"opciones":[{"alimentos":["a"]}]}] }"#,
                     .unsupportedSchema(found: "noop.diet.v2"))
    }

    func testRejectsUnsupportedIdioma() {
        assertThrows(#"{ "schema":"noop.diet.v1", "idioma":"fr", "comidas":[{"opciones":[{"alimentos":["a"]}]}] }"#,
                     .unsupportedIdioma(found: "fr"))
    }

    func testRejectsUnsupportedCiclo() {
        assertThrows(#"{ "schema":"noop.diet.v1", "idioma":"es", "ciclo":"semanal", "comidas":[{"opciones":[{"alimentos":["a"]}]}] }"#,
                     .unsupportedCiclo(found: "semanal"))
    }

    func testRejectsNoMeals() {
        assertThrows(#"{ "schema":"noop.diet.v1", "idioma":"es", "comidas":[] }"#, .noMeals)
        assertThrows(#"{ "schema":"noop.diet.v1", "idioma":"es" }"#, .noMeals)
    }

    func testRejectsMealWithoutOptions() {
        assertThrows(#"{ "schema":"noop.diet.v1", "idioma":"es", "comidas":[{"id":"d","nombre":"D"}] }"#,
                     .mealWithoutOptions(id: "d"))
    }

    func testRejectsEmptyOption() {
        assertThrows(#"{ "schema":"noop.diet.v1", "idioma":"es", "comidas":[{"id":"d","opciones":[{"alimentos":[]}]}] }"#,
                     .emptyOption(id: "d"))
    }

    func testRejectsInvalidDailyTargets() {
        // Non-number value.
        assertThrows(#"{ "schema":"noop.diet.v1", "idioma":"es", "objetivos_diarios":{"kcal":"mucho"}, "comidas":[{"id":"d","opciones":[{"alimentos":["a"]}]}] }"#,
                     .invalidDailyTargets)
        // Negative value.
        assertThrows(#"{ "schema":"noop.diet.v1", "idioma":"es", "objetivos_diarios":{"kcal":-5}, "comidas":[{"id":"d","opciones":[{"alimentos":["a"]}]}] }"#,
                     .invalidDailyTargets)
    }

    // MARK: - Round-trip (parse → makeDietPlanRow → store → re-parse == original)

    func testFullPipelineRoundTrip() async throws {
        let plan = try importer.parse(text: validES)
        let row = try importer.makeDietPlanRow(plan, id: "p1", createdAt: 1000)
        XCTAssertEqual(row.id, "p1")
        XCTAssertEqual(row.name, "Plan Dra. Pérez")
        XCTAssertEqual(row.language, "es")
        XCTAssertEqual(row.cycle, "diario")

        let store = try await WhoopStore.inMemory()
        try await store.upsertDietPlan(row, deviceId: "dev")
        let stored = try await store.activeDietPlan(deviceId: "dev")
        let reparsed = try importer.parse(text: try XCTUnwrap(stored).payloadJSON)

        XCTAssertEqual(reparsed, plan)   // survives encode → persist → decode unchanged
    }

    func testCanonicalJSONReparsesEqual() throws {
        let plan = try importer.parse(text: validEN)
        let payload = try DietPlanImporter.canonicalJSON(plan)
        XCTAssertEqual(try importer.parse(text: payload), plan)
    }

    // MARK: - Helper

    private func assertThrows(_ json: String, _ expected: DietPlanParseError,
                              file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try importer.parse(text: json), file: file, line: line) { error in
            XCTAssertEqual(error as? DietPlanParseError, expected, file: file, line: line)
        }
    }
}
