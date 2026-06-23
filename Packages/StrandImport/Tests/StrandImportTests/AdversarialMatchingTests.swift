import XCTest
@testable import StrandImport
import StrandTraining

/// FER-537 — adversarial harness for the import matcher. A fixture of "dirty" exercise names a real
/// LLM (or a user pasting its output) would produce — abbreviations, es-MX regionalisms, mixed es/en,
/// reordered/extra-equipment phrasings, finger typos — each labeled with the catalog id it SHOULD
/// resolve to, plus trap rows that must NOT auto-resolve (ambiguous / not-an-exercise → go to mapping).
///
/// It locks in a coverage floor so future catalog/alias edits can't silently regress the matcher, and a
/// hard "zero false positives" guard: a wrong auto-match deceives the user, whereas an unmatched name
/// only costs one tap in the mapping step (FER-496). The matching algorithm is unchanged — coverage is
/// reached purely by the curated synonym table (exercise-aliases.json, FER-522) + the bilingual catalog
/// (FER-501); the fuzzy `suggestions` net (FER-523) catches the rest as "did you mean…?" (never auto).
final class AdversarialMatchingTests: XCTestCase {

    /// (dirty name as written, expected catalog id) — nil expected means a TRAP: it must NOT auto-resolve.
    private static let fixture: [(name: String, expected: String?)] = [
        // abbreviations
        ("OHP", "Barbell_Shoulder_Press"),                  // overhead press == shoulder press
        ("BB bench press", "Barbell_Bench_Press_-_Medium_Grip"),
        ("DB bench press", "Dumbbell_Bench_Press"),
        ("RDL", "Romanian_Deadlift"),
        ("CGBP", "Close-Grip_Barbell_Bench_Press"),
        ("BB row", "Bent_Over_Barbell_Row"),
        ("DB shoulder press", "Dumbbell_Shoulder_Press"),
        ("lat pulldown", "Wide-Grip_Lat_Pulldown"),
        ("skullcrusher", "Lying_Triceps_Press"),            // == lying triceps extension
        ("incline DB press", "Incline_Dumbbell_Press"),

        // es-MX regionalisms
        ("desplante con barra", "Barbell_Lunge"),           // desplante == lunge (MX)
        ("desplantes con mancuernas", "Dumbbell_Lunges"),
        ("lagartijas", "Pushups"),
        ("sentadilla búlgara", "Split_Squats"),
        ("peso muerto piernas rígidas", "Romanian_Deadlift"),
        ("peso muerto rumano", "Romanian_Deadlift"),
        ("jalón al pecho", "Wide-Grip_Lat_Pulldown"),
        ("prensa de pierna", "Leg_Press"),
        ("elevación lateral", "Side_Lateral_Raise"),
        ("cruce de poleas", "Cable_Crossover"),
        ("curl martillo", "Hammer_Curls"),
        ("press militar", "Standing_Military_Press"),
        ("empuje de cadera", "Barbell_Hip_Thrust"),
        ("jalón a la cara", "Face_Pull"),
        ("fondos de tríceps", "Dips_-_Triceps_Version"),
        ("plancha", "Plank"),
        ("dominadas", "Pullups"),

        // mixed es/en, reordered, extra equipment/grip words
        ("press de banca", "Barbell_Bench_Press_-_Medium_Grip"),
        ("press banca plano", "Barbell_Bench_Press_-_Medium_Grip"),
        ("squat con barra", "Barbell_Squat"),
        ("sentadilla", "Barbell_Squat"),
        ("peso muerto", "Barbell_Deadlift"),
        ("curl de bíceps con mancuerna", "Dumbbell_Bicep_Curl"),
        ("remo con barra inclinado", "Bent_Over_Barbell_Row"),
        ("sentadilla frontal", "Front_Barbell_Squat"),
        ("sentadilla goblet", "Goblet_Squat"),
        ("press arnold", "Arnold_Dumbbell_Press"),
        ("remo sentado en polea", "Seated_Cable_Rows"),
        ("curl predicador", "Preacher_Curl"),
        ("curl femoral acostado", "Lying_Leg_Curls"),
        ("extensiones de pierna", "Leg_Extensions"),
        ("elevación de pantorrilla de pie", "Standing_Calf_Raises"),
        ("aperturas con mancuernas", "Dumbbell_Flyes"),
        ("extensión de tríceps en polea", "Triceps_Pushdown"),
        ("press de hombros con barra", "Barbell_Shoulder_Press"),
        ("dominada supina", "Chin-Up"),
        ("curl con barra", "Barbell_Curl"),
        ("push press", "Push_Press"),
        ("curl de biceps", "Barbell_Curl"),                 // bare "biceps curl" → barbell default

        // finger typos (the user-pasted text can carry them; LLMs rarely do). "press de banc" is the
        // deliberate hard case — a single dropped letter the matcher can't reach; kept so the floor has
        // honest margin rather than being cherry-picked to 100%.
        ("press de banc", "Barbell_Bench_Press_-_Medium_Grip"),
        ("sentadila con barra", "Barbell_Squat"),
        ("peso muerto rumano con barra", "Romanian_Deadlift"),
        ("elevacion lateral con mancuernas", "Side_Lateral_Raise"),

        // TRAPS — genuinely ambiguous / not an exercise → must stay unmatched (go to mapping)
        ("press", nil),
        ("máquina", nil),
        ("cardio 30 minutos", nil),
        ("estiramiento", nil),
        ("circuito de core", nil),
        ("movilidad de cadera", nil),
        ("descanso activo", nil),
    ]

    /// Coverage floors. Auto-resolve is the win (no manual step); the top-3 suggestions are the safety
    /// net; false positives must be zero. Floors sit below today's measured rates so honest churn (a new
    /// catalog entry shifting a fuzzy rank) doesn't fail the build, but a real regression does.
    func testAdversarialCoverage() {
        let reconciler = WorkoutExerciseReconciler(known: ExerciseCatalog.all)
        let labeled = Self.fixture.filter { $0.expected != nil }
        let traps = Self.fixture.filter { $0.expected == nil }

        var autoCorrect = 0, reachable = 0
        var falsePositives: [String] = []

        for (name, expected) in labeled {
            guard let expected else { continue }
            let resolved = reconciler.resolve(WorkoutExercise(name: name, sets: 1))?.id
            if resolved == expected {
                autoCorrect += 1
                reachable += 1
            } else {
                if let resolved { falsePositives.append("\(name) → \(resolved) (expected \(expected))") }
                let inTop3 = reconciler.suggestions(for: name, limit: 3).contains { $0.id == expected }
                if inTop3 { reachable += 1 }
            }
        }

        // A trap that auto-resolves is also a false positive — it should have gone to the mapping step.
        for (name, _) in traps {
            if let hit = reconciler.resolve(WorkoutExercise(name: name, sets: 1))?.id {
                falsePositives.append("TRAP \(name) → \(hit)")
            }
        }

        let n = Double(labeled.count)
        let autoRate = Double(autoCorrect) / n
        let reachRate = Double(reachable) / n
        print("FER-537 adversarial: auto=\(autoCorrect)/\(labeled.count) (\(Int(autoRate * 100))%), "
            + "reachable=\(reachable)/\(labeled.count) (\(Int(reachRate * 100))%), "
            + "falsePositives=\(falsePositives.count)")

        XCTAssertTrue(falsePositives.isEmpty,
            "A wrong auto-match deceives the user (worse than sending to mapping):\n" + falsePositives.joined(separator: "\n"))
        XCTAssertGreaterThanOrEqual(autoRate, 0.80,
            "Auto-resolve coverage regressed below floor — add curated aliases for the new misses.")
        XCTAssertGreaterThanOrEqual(reachRate, 0.95,
            "Reachable (auto + top-3 suggestion) coverage regressed below floor.")
    }
}
