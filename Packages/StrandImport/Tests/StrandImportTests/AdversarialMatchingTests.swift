import XCTest
@testable import StrandImport
import StrandTraining

/// Adversarial harness for the import matcher (FER-537/542, adapted for FER-779). The curated synonym
/// table (FER-522, `exercise-aliases.json`) was retired with the ExerciseDB catalog adoption — native
/// ids let the LLM pick the exact exercise, so the alias-driven coverage floors no longer apply. What
/// survives is catalog-agnostic and still load-bearing: (A) every catalog name resolves by its own
/// name, (B) `preClean` strips LLM format noise without eroding legitimate names, and (C) trap
/// (not-an-exercise / ambiguous) names never auto-resolve or surface a high-confidence fuzzy match — a
/// wrong auto-match deceives the user, whereas an unmatched name only costs one tap in the mapping step.
final class AdversarialMatchingTests: XCTestCase {

    /// Ambiguous / not-an-exercise names. They must NOT auto-resolve (→ mapping) and must NOT surface a
    /// high-confidence fuzzy suggestion. Includes FER-544 cases where `preClean` strips a trailing volume
    /// annotation down to a bare, ambiguous word ("press 3x5" → "press") — which correctly stays unmatched.
    private static let traps = [
        "press", "máquina", "cardio 30 minutos", "estiramiento", "circuito de core",
        "movilidad de cadera", "descanso activo", "calentamiento", "enfriamiento",
        "press 3x5", "remo 12 reps", "curl 4 series",
    ]

    // MARK: - A: catalog-wide identity guard

    /// Every catalog exercise must be resolvable by its own canonical name, in English and (when present)
    /// Spanish. Not "resolves to its own id" — two exercises can share a normalized name (a legit
    /// collision), and the first wins; the property is "no canonical name is unmatchable". Guards the whole
    /// catalog against a `normalize` change or a name collision.
    func testCatalogIdentityGuard() {
        let reconciler = WorkoutExerciseReconciler(known: ExerciseCatalog.all)
        var enUnresolved: [String] = []
        var esUnresolved: [String] = []
        var esCount = 0

        for ex in ExerciseCatalog.all {
            if reconciler.resolve(WorkoutExercise(name: ex.name, sets: 1)) == nil {
                enUnresolved.append(ex.name)
            }
            if let es = ex.nameES, !es.isEmpty {
                esCount += 1
                if reconciler.resolve(WorkoutExercise(name: es, sets: 1)) == nil { esUnresolved.append(es) }
            }
        }

        print("catalog guard: EN \(ExerciseCatalog.all.count - enUnresolved.count)/\(ExerciseCatalog.all.count), "
            + "ES \(esCount - esUnresolved.count)/\(esCount)")
        XCTAssertTrue(enUnresolved.isEmpty, "English names that no longer resolve:\n" + enUnresolved.joined(separator: "\n"))
        XCTAssertTrue(esUnresolved.isEmpty, "Spanish names that no longer resolve:\n" + esUnresolved.joined(separator: "\n"))
    }

    // MARK: - B: preClean strips noise but never erodes a legitimate name

    func testPreCleanStripsFormatNoise() {
        let strip: [(String, String)] = [
            ("- press militar", "press militar"),
            ("• sentadilla con barra", "sentadilla con barra"),
            ("* peso muerto", "peso muerto"),
            ("1. peso muerto", "peso muerto"),
            ("2) sentadilla", "sentadilla"),
            ("press de banca 4x8", "press de banca"),
            ("sentadilla 3 x 10", "sentadilla"),
            ("press 3x5", "press"),
            ("curl 4 series", "curl"),
            ("remo 12 reps", "remo"),
        ]
        for (input, expected) in strip {
            XCTAssertEqual(WorkoutExerciseReconciler.preClean(input), expected, "preClean(\(input.debugDescription))")
        }
    }

    /// preClean must be the identity on names that only LOOK like they carry noise — internal hyphens,
    /// a leading number that's part of the name, a trailing token that isn't an NxM/units annotation.
    func testPreCleanPreservesLegitimateNames() {
        let untouched = ["Close-Grip Bench Press", "3/4 Sit-Up", "90/90 Hamstring", "Farmer's Walk",
                         "cardio 30 minutos", "21s", "Figure 8 Walk", "T-Bar Row"]
        for name in untouched {
            XCTAssertEqual(WorkoutExerciseReconciler.preClean(name), name, "preClean must not touch \(name.debugDescription)")
        }
    }

    // MARK: - C: trap discipline (no false auto-match, no high-confidence garbage)

    func testTrapsDoNotFalseMatch() {
        let reconciler = WorkoutExerciseReconciler(known: ExerciseCatalog.all)
        var falsePositives: [String] = []
        var trapHighConfidence: [String] = []
        for name in Self.traps {
            if let hit = reconciler.resolve(WorkoutExercise(name: name, sets: 1))?.id {
                falsePositives.append("TRAP \(name) → \(hit)")
            }
            if let top = reconciler.scoredSuggestions(for: name).first, top.score >= 0.6 {
                trapHighConfidence.append("\(name) → \(top.exercise.id) @\(String(format: "%.2f", top.score))")
            }
        }
        XCTAssertTrue(falsePositives.isEmpty,
            "A trap auto-resolved — it should have gone to the mapping step:\n" + falsePositives.joined(separator: "\n"))
        XCTAssertTrue(trapHighConfidence.isEmpty,
            "A trap surfaced a high-confidence (≥0.60) suggestion — the fuzzy net is leaking garbage:\n"
            + trapHighConfidence.joined(separator: "\n"))
    }
}
