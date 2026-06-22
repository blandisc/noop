import XCTest
@testable import StrandTraining

// FER-501 — the Spanish overlay loads into the catalog, the vocabulary tables are exhaustive, and
// the localized-name helper falls back safely. The overlay is partial (curated common exercises) for
// now; F2/the data fill completes it — so these assert correctness, not full coverage.
final class BilingualCatalogTests: XCTestCase {

    func testEveryCatalogEntryHasSpanishName() {
        // F1 ships a complete overlay: every one of the ~873 catalog exercises has a non-empty Spanish
        // name, and keeps its English one. (A custom exercise — not in the catalog — has nameES nil; see
        // testDisplayNameFallsBackToEnglishWithoutOverlay.)
        for e in ExerciseCatalog.all {
            let es = e.nameES
            XCTAssertNotNil(es, "\(e.id) has no Spanish name in the overlay")
            XCTAssertFalse((es ?? "").trimmingCharacters(in: .whitespaces).isEmpty, "\(e.id) has empty nameES")
            XCTAssertFalse(e.name.isEmpty, "\(e.id) lost its English name")
        }
    }

    func testKnownExerciseIsTranslated() {
        let squat = ExerciseCatalog.byID("Barbell_Squat")
        XCTAssertEqual(squat?.nameES, "Sentadilla con barra")
        XCTAssertEqual(squat?.displayName(localized: true), "Sentadilla con barra")
        XCTAssertEqual(squat?.displayName(localized: false), "Barbell Squat")
    }

    func testDisplayNameFallsBackToEnglishWithoutOverlay() {
        // A custom-style exercise (built by hand, no nameES) always shows its given name.
        let custom = Exercise(id: "x", name: "Mi ejercicio", type: .weightReps, equipment: nil,
                              primaryMuscles: [], secondaryMuscles: [], cues: [])
        XCTAssertNil(custom.nameES)
        XCTAssertEqual(custom.displayName(localized: true), "Mi ejercicio")
        XCTAssertEqual(custom.displayName(localized: false), "Mi ejercicio")
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
}
