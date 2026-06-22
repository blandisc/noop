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

    func testSpanishCuesLoadAndFallBack() {
        // F2 ships a PARTIAL cues overlay (common exercises); an entry with Spanish cues exposes them
        // localized and keeps the English; one without falls back to English. Step counts match.
        let squat = ExerciseCatalog.byID("Barbell_Squat")
        XCTAssertNotNil(squat?.cuesES, "Barbell_Squat should have Spanish cues in the F2 batch")
        XCTAssertEqual(squat?.displayCues(localized: true).count, squat?.cues.count, "step count must match English")
        XCTAssertEqual(squat?.displayCues(localized: false), squat?.cues, "English mode shows English cues")
        XCTAssertNotEqual(squat?.displayCues(localized: true), squat?.cues, "Spanish mode shows Spanish cues")

        // An exercise outside the batch falls back to English cues (safe degradation).
        let untranslated = ExerciseCatalog.all.first { $0.cuesES == nil && !$0.cues.isEmpty }
        XCTAssertNotNil(untranslated, "the cues overlay is partial — some exercises have no Spanish cues yet")
        XCTAssertEqual(untranslated?.displayCues(localized: true), untranslated?.cues, "no Spanish cues → English")

        // A custom exercise (no overlay) shows whatever cues it was built with, in both modes.
        let custom = Exercise(id: "z", name: "X", type: .weightReps, equipment: nil,
                              primaryMuscles: [], secondaryMuscles: [], cues: ["paso uno"])
        XCTAssertEqual(custom.displayCues(localized: true), ["paso uno"])
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
