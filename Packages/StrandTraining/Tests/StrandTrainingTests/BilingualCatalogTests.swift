import XCTest
@testable import StrandTraining

// FER-501 / FER-779 — the es-MX overlay loads into the catalog (now ExerciseDB, LLM-translated at
// bake), the vocabulary tables are exhaustive, and the localized helpers fall back safely.
final class BilingualCatalogTests: XCTestCase {

    func testEveryCatalogEntryHasSpanishName() {
        // The bake ships a complete overlay: every catalog exercise has a non-empty Spanish name and
        // keeps its English one. (A custom exercise — not in the catalog — has nameES nil.)
        for e in ExerciseCatalog.all {
            let es = e.nameES
            XCTAssertNotNil(es, "\(e.id) has no Spanish name in the overlay")
            XCTAssertFalse((es ?? "").trimmingCharacters(in: .whitespaces).isEmpty, "\(e.id) has empty nameES")
            XCTAssertFalse(e.name.isEmpty, "\(e.id) lost its English name")
        }
    }

    func testKnownExerciseIsTranslated() {
        // Resolve by English name (ids are opaque ExerciseDB ids), then assert the localized name is a
        // non-empty Spanish string distinct from the English.
        let englishName = "Barbell Bench Press - Medium Grip"
        guard let bench = ExerciseCatalog.all.first(where: { $0.name == englishName }) else {
            return XCTFail("expected '\(englishName)' in the catalog")
        }
        XCTAssertEqual(bench.displayName(localized: false), englishName)
        let es = bench.displayName(localized: true)
        XCTAssertFalse(es.isEmpty)
        XCTAssertNotEqual(es, englishName, "Spanish mode should show the translated name")
    }

    func testDisplayNameFallsBackToEnglishWithoutOverlay() {
        // A custom-style exercise (built by hand, no nameES) always shows its given name.
        let custom = Exercise(id: "x", name: "Mi ejercicio", type: .weightReps, equipment: nil,
                              primaryMuscles: [], secondaryMuscles: [], instructions: [])
        XCTAssertNil(custom.nameES)
        XCTAssertEqual(custom.displayName(localized: true), "Mi ejercicio")
        XCTAssertEqual(custom.displayName(localized: false), "Mi ejercicio")
    }

    func testSpanishInstructionsLoadAndFallBack() {
        // A catalog exercise exposes Spanish instructions localized and keeps the English; step counts match.
        guard let e = ExerciseCatalog.all.first(where: { !$0.instructions.isEmpty }) else {
            return XCTFail("catalog has no instructions")
        }
        XCTAssertNotNil(e.instructionsES, "\(e.id) should have Spanish instructions (overlay is complete)")
        XCTAssertEqual(e.displayInstructions(localized: true).count, e.instructions.count,
                       "step count must match English")
        XCTAssertEqual(e.displayInstructions(localized: false), e.instructions, "English mode shows English")

        // A custom exercise (no overlay) shows whatever instructions it was built with, in both modes.
        let custom = Exercise(id: "z", name: "X", type: .weightReps, equipment: nil,
                              primaryMuscles: [], secondaryMuscles: [], instructions: ["paso uno"])
        XCTAssertEqual(custom.displayInstructions(localized: true), ["paso uno"])
        XCTAssertEqual(custom.displayInstructions(localized: false), ["paso uno"])
    }

    func testMuscleVocabularyCoversEveryCatalogMuscle() {
        let used = Set(ExerciseCatalog.all.flatMap { $0.primaryMuscles + $0.secondaryMuscles })
        for muscle in used {
            XCTAssertNotNil(MuscleVocabulary.es[muscle], "missing Spanish for muscle key '\(muscle)'")
        }
    }

    func testEquipmentVocabularyCoversEveryCatalogEquipment() {
        let used = Set(ExerciseCatalog.all.compactMap { $0.equipment })
        for eq in used {
            XCTAssertNotNil(EquipmentVocabulary.es[eq], "missing Spanish for equipment key '\(eq)'")
        }
    }

    func testBodyPartVocabularyCoversEveryCatalogBodyPart() {
        let used = Set(ExerciseCatalog.all.flatMap { $0.bodyParts })
        for bp in used {
            XCTAssertNotNil(BodyPartVocabulary.es[bp], "missing Spanish for body-part key '\(bp)'")
        }
    }
}
