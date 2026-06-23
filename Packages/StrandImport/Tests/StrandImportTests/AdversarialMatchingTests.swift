import XCTest
@testable import StrandImport
import StrandTraining

/// FER-537 + FER-542 — adversarial harness for the import matcher. A fixture of "dirty" exercise names a
/// real LLM (or a user pasting its output) would produce — abbreviations, es-MX regionalisms, English-only
/// names, mixed es/en, reordered/extra-equipment phrasings, finger typos — each labeled with the catalog id
/// it SHOULD resolve to, plus trap rows that must NOT auto-resolve (ambiguous / not-an-exercise → mapping).
///
/// It locks in coverage floors so future catalog/alias edits can't silently regress the matcher, and a hard
/// "zero false positives" guard: a wrong auto-match deceives the user, whereas an unmatched name only costs
/// one tap in the mapping step (FER-496). The matching algorithm is unchanged — coverage comes purely from
/// the curated synonym table (exercise-aliases.json, FER-522) + the bilingual catalog (FER-501); the fuzzy
/// `suggestions` net (FER-523) catches the rest as "did you mean…?" (never auto).
///
/// FER-542 adds three guards: (A) a catalog-wide identity property over all ~873 exercises; (B) more dirty
/// categories (English-only, underserved muscles, transposition typos, format noise); (C) stricter metrics
/// (rank-1 of the suggestions, and a trap-discipline check that traps surface no high-confidence match).
final class AdversarialMatchingTests: XCTestCase {

    /// (dirty name as written, expected catalog id). All of these SHOULD resolve or at least be reachable
    /// via the top-3 suggestions; they count toward the coverage floors.
    private static let fixture: [(name: String, expected: String)] = [
        // --- abbreviations ---
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

        // --- es-MX regionalisms ---
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

        // --- mixed es/en, reordered, extra equipment/grip words ---
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

        // --- FER-542 B1: English-only names (an English LLM) ---
        ("bulgarian split squat", "Split_Squats"),
        ("standing calf raise", "Standing_Calf_Raises"),
        ("face pull", "Face_Pull"),
        ("hip thrust", "Barbell_Hip_Thrust"),
        ("barbell shrug", "Barbell_Shrug"),
        ("russian twist", "Russian_Twist"),
        ("hanging leg raise", "Hanging_Leg_Raise"),
        ("seated cable row", "Seated_Cable_Rows"),
        ("romanian deadlift", "Romanian_Deadlift"),

        // --- FER-542 B2: underserved muscles (calf / forearm / abs / glute / traps) ---
        ("encogimiento de hombros", "Barbell_Shrug"),
        ("curl de muñeca", "Cable_Wrist_Curl"),
        ("abdominal en polea", "Cable_Crunch"),
        ("elevación de piernas colgado", "Hanging_Leg_Raise"),
        ("puente de glúteos", "Butt_Lift_Bridge"),          // exact ES catalog name of Butt_Lift_Bridge
        ("giro ruso", "Russian_Twist"),
        ("elevación de pantorrilla sentado", "Seated_Calf_Raise"),

        // --- FER-542 B3: transposition / doubled-letter typos (the hard tail; many reach only top-3) ---
        ("press de banc", "Barbell_Bench_Press_-_Medium_Grip"),
        ("sentadila con barra", "Barbell_Squat"),
        ("sentadlla con barra", "Barbell_Squat"),
        ("press de banca con barrra", "Barbell_Bench_Press_-_Medium_Grip"),
        ("domindas", "Pullups"),
        ("peso muerto rumano con barra", "Romanian_Deadlift"),
        ("elevacion lateral con mancuernas", "Side_Lateral_Raise"),

        // --- FER-544 B4: LLM format noise — a leading bullet/number or a trailing "NxM"/"N reps" that
        // `preClean` now strips before matching, so these pasted-as-is names resolve on their own. ---
        ("- press militar", "Standing_Military_Press"),
        ("• sentadilla con barra", "Barbell_Squat"),
        ("press de banca 4x8", "Barbell_Bench_Press_-_Medium_Grip"),
        ("sentadilla 3x10", "Barbell_Squat"),
        ("1. peso muerto", "Barbell_Deadlift"),
    ]

    /// Ambiguous / not-an-exercise names. They must NOT auto-resolve (→ mapping) and must NOT surface a
    /// high-confidence fuzzy suggestion (the trap-discipline guard).
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
    /// catalog against a `normalize` change, a name collision, or an alias shadowing a real name.
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

        print("FER-542 catalog guard: EN \(ExerciseCatalog.all.count - enUnresolved.count)/\(ExerciseCatalog.all.count), "
            + "ES \(esCount - esUnresolved.count)/\(esCount)")
        XCTAssertTrue(enUnresolved.isEmpty, "English names that no longer resolve:\n" + enUnresolved.joined(separator: "\n"))
        XCTAssertTrue(esUnresolved.isEmpty, "Spanish names that no longer resolve:\n" + esUnresolved.joined(separator: "\n"))
    }

    // MARK: - FER-544: preClean strips noise but never erodes a legitimate name

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

    // MARK: - B + C: coverage + stricter metrics

    func testAdversarialCoverage() {
        let reconciler = WorkoutExerciseReconciler(known: ExerciseCatalog.all)

        var autoCorrect = 0, reachable = 0, rank1 = 0, nonAuto = 0
        var falsePositives: [String] = []

        for (name, expected) in Self.fixture {
            let resolved = reconciler.resolve(WorkoutExercise(name: name, sets: 1))?.id
            if resolved == expected {
                autoCorrect += 1
                reachable += 1
            } else {
                if let resolved { falsePositives.append("\(name) → \(resolved) (expected \(expected))") }
                nonAuto += 1
                let sug = reconciler.suggestions(for: name, limit: 3).map(\.id)
                if sug.contains(expected) { reachable += 1 }
                if sug.first == expected { rank1 += 1 }   // C: expected is the FIRST suggestion
            }
        }

        // A trap that auto-resolves is also a false positive — it should have gone to the mapping step.
        // And (C, trap discipline) no trap may surface a high-confidence fuzzy suggestion.
        var trapHighConfidence: [String] = []
        for name in Self.traps {
            if let hit = reconciler.resolve(WorkoutExercise(name: name, sets: 1))?.id {
                falsePositives.append("TRAP \(name) → \(hit)")
            }
            if let top = reconciler.scoredSuggestions(for: name).first, top.score >= 0.6 {
                trapHighConfidence.append("\(name) → \(top.exercise.id) @\(String(format: "%.2f", top.score))")
            }
        }

        let n = Double(Self.fixture.count)
        let autoRate = Double(autoCorrect) / n
        let reachRate = Double(reachable) / n
        // C metric: the right exercise lands with the LEAST user effort — auto-resolved, or the very first
        // "did you mean…?" suggestion. Measured over the whole fixture (stable), not just the noisy typo
        // tail, so an unrelated catalog addition shifting one fuzzy rank can't make it flaky.
        let firstChoiceRate = Double(autoCorrect + rank1) / n
        let rank1OfNonAuto = nonAuto > 0 ? Double(rank1) / Double(nonAuto) : 1   // informational
        print("FER-542 adversarial: auto=\(autoCorrect)/\(Self.fixture.count) (\(Int(autoRate * 100))%), "
            + "reachable=\(reachable)/\(Self.fixture.count) (\(Int(reachRate * 100))%), "
            + "firstChoice=\(autoCorrect + rank1)/\(Self.fixture.count) (\(Int(firstChoiceRate * 100))%), "
            + "rank1OfNonAuto=\(rank1)/\(nonAuto) (\(Int(rank1OfNonAuto * 100))%), "
            + "falsePositives=\(falsePositives.count), trapHighConfidence=\(trapHighConfidence.count)")

        XCTAssertTrue(falsePositives.isEmpty,
            "A wrong auto-match deceives the user (worse than sending to mapping):\n" + falsePositives.joined(separator: "\n"))
        XCTAssertTrue(trapHighConfidence.isEmpty,
            "A trap surfaced a high-confidence (≥0.60) suggestion — loosening coverage is leaking garbage:\n"
            + trapHighConfidence.joined(separator: "\n"))
        XCTAssertGreaterThanOrEqual(autoRate, 0.80,
            "Auto-resolve coverage regressed below floor — add curated aliases for the new misses.")
        XCTAssertGreaterThanOrEqual(reachRate, 0.90,
            "Reachable (auto + top-3 suggestion) coverage regressed below floor.")
        XCTAssertGreaterThanOrEqual(firstChoiceRate, 0.85,
            "Least-effort coverage regressed — fewer names auto-resolve or lead the 'did you mean…?' list.")
    }

}
