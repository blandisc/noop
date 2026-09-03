import XCTest
@testable import StrandImport
import StrandTraining

/// FER-794 — the auto-match tier that restored the import matcher after the ExerciseDB adoption
/// (FER-779). Covers the three sub-tiers (content-key equality, derived alias, confident fuzzy),
/// the owner's reference plan (the 16 names that all fell to manual mapping), the alias table's
/// integrity, and the trap discipline extended to `autoMatch`.
final class WorkoutAutoMatchTests: XCTestCase {

    private static let reconciler = WorkoutExerciseReconciler(
        known: ExerciseCatalog.all, aliases: ExerciseAliasTable.bundled)

    /// The owner's reference plan (FER-794): the 16 names of the real import that resolved 0/16
    /// before this change. Each maps to the tokens the matched exercise's name (EN or ES) must
    /// contain — correctness, not just "matched something".
    private static let ownerPlan: [(name: String, expects: [String])] = [
        ("Press banca con barra",            ["press", "banca", "barra"]),
        ("Press militar de pie",             ["press militar", "de pie"]),
        ("Prensa de pierna 45°",             ["prensa", "pierna"]),   // free-exercise-db: «Prensa de piernas» (sin 45)
        ("Remo con barra (bent-over)",       ["remo inclinado", "barra"]),
        ("Sentadilla con barra",             ["sentadilla", "barra"]),
        ("Peso muerto rumano",               ["peso muerto rumano"]),
        ("Curl de bíceps con barra",         ["curl", "barra"]),
        ("Extensión de tríceps en polea",    ["polea"]),
        ("Jalón al pecho",                   ["jalón"]),
        ("Remo sentado en polea",            ["remo", "polea"]),
        ("Elevaciones laterales",            ["elevación lateral"]),
        ("Press inclinado con mancuernas",   ["press", "inclinado", "mancuernas"]),
        ("Fondos en paralelas",              ["fondos"]),
        ("Curl femoral acostado",            ["curl", "acostado"]),
        ("Extensión de pierna",              ["extensión de pierna"]),
        ("Elevación de pantorrilla de pie",  ["pantorrilla", "pie"]),   // catálogo: «Elevación de pantorrilla de pie»
    ]

    /// Acceptance criterion FER-794: the reference plan resolves ≥ 13/16 automatically, each to the
    /// correct exercise (its name must carry the expected tokens).
    func testOwnerPlanAutoMatches() {
        var matched = 0
        var wrong: [String] = []
        var unresolved: [String] = []
        for (name, expects) in Self.ownerPlan {
            guard let hit = Self.reconciler.autoMatch(name) else { unresolved.append(name); continue }
            let haystack = WorkoutExerciseReconciler.normalize((hit.nameES ?? "") + " " + hit.name)
            let ok = expects.allSatisfy { haystack.contains(WorkoutExerciseReconciler.normalize($0)) }
            if ok { matched += 1 }
            else { wrong.append("\(name) → \(hit.nameES ?? hit.name) (id \(hit.id))") }
        }
        XCTAssertTrue(wrong.isEmpty, "Auto-matched to the WRONG exercise:\n" + wrong.joined(separator: "\n"))
        XCTAssertGreaterThanOrEqual(matched, 13,
            "Only \(matched)/16 of the reference plan auto-matched. Unresolved:\n"
            + unresolved.joined(separator: "\n"))
    }

    /// FER-797 — the second wave of realistic names (plurals, colloquial es/en) that the first pass
    /// missed. Singularization + content-keyed aliases + the extended table must resolve them all.
    func testColloquialAndPluralNames() {
        let probes = [
            "Sentadillas con barra", "Curls de bíceps", "Press de banca plano",
            "Dominadas lastradas", "Elevaciones frontales", "Remo con mancuerna a una mano",
            "Press militar con mancuernas", "Extensión de tríceps con mancuerna",
            "Aperturas inclinadas", "Remo en máquina", "Curl de bíceps en polea",
            "Elevación de talones sentado", "Abdominales en polea", "Zancadas caminando",
            "Face pull", "Pájaros", "Walking lunges", "Seated leg curl", "Pec fly",
            "Hip thrust en máquina",
        ]
        let unresolved = probes.filter { Self.reconciler.autoMatch($0) == nil }
        XCTAssertTrue(unresolved.isEmpty,
            "Colloquial/plural names that no longer auto-match:\n" + unresolved.joined(separator: "\n"))
    }

    /// The content-key tier: stopword/word-order differences collapse; the alias tier is not involved.
    func testContentKeyEquality() {
        let plain = WorkoutExerciseReconciler(known: ExerciseCatalog.all)   // no aliases
        // free-exercise-db's basic barbell bench press → «Press de banca con barra agarre medio».
        let expected = "Press de banca con barra agarre medio"
        let hit = plain.autoMatch("Press banca con barra agarre medio")   // stopword «de» dropped
        XCTAssertEqual(hit?.nameES, expected)
        // Word order too — same content tokens.
        XCTAssertEqual(plain.autoMatch("Press agarre medio con barra de banca")?.nameES, expected)
    }

    /// Every alias in the derived table must point at an id that exists in the bundled catalog —
    /// the same guard `build_aliases.py` applies at generation, re-checked against the shipped bundle.
    func testAliasTableIntegrity() {
        XCTAssertFalse(ExerciseAliasTable.bundled.isEmpty, "alias table missing from the bundle")
        let ids = Set(ExerciseCatalog.all.map(\.id))
        let orphans = ExerciseAliasTable.bundled.filter { !ids.contains($0.value) }
        XCTAssertTrue(orphans.isEmpty, "aliases pointing at unknown ids: \(orphans)")
    }

    /// Trap discipline extended to autoMatch (FER-542 spirit): ambiguous / not-an-exercise names must
    /// never auto-resolve — a wrong auto-match deceives; an unmatched name costs one tap.
    /// FER-328: bare Strong/Hevy words («Row», «Press», «Curl», «Fly») never auto-casan.
    func testTrapsDoNotAutoMatch() {
        let traps = ["press", "máquina", "cardio 30 minutos", "estiramiento", "circuito de core",
                     "movilidad de cadera", "descanso activo", "calentamiento", "enfriamiento",
                     "press 3x5", "remo 12 reps", "curl 4 series",
                     "mi ejercicio inventado 3x8",
                     "Row", "Press", "Curl", "Fly", "row", "fly"]
        for trap in traps {
            if let hit = Self.reconciler.autoMatch(trap) {
                XCTFail("trap \(trap.debugDescription) auto-matched → \(hit.name) (id \(hit.id))")
            }
        }
    }

    /// FER-328 · E8: the ~100 most common Strong/Hevy export names resolve automatically ≥ 90 %.
    func testStrongHevyTop100Resolve() {
        let names = Self.strongHevyTop100
        XCTAssertGreaterThanOrEqual(names.count, 100, "fixture list must stay ≥ 100 names")
        var hit = 0
        var missed: [String] = []
        for name in names {
            if Self.reconciler.autoMatch(name) != nil || Self.reconciler.match(name) != nil {
                hit += 1
            } else {
                missed.append(name)
            }
        }
        let rate = Double(hit) / Double(names.count)
        XCTAssertGreaterThanOrEqual(rate, 0.90,
            "Only \(hit)/\(names.count) (\(Int(rate * 100))%) auto-resolved. Missed:\n"
            + missed.prefix(20).joined(separator: "\n"))
    }

    /// Common Strong / Hevy library titles (EN) plus the es-MX aliases athletes type by hand.
    private static let strongHevyTop100: [String] = [
        // Strong / Hevy English titles
        "Bench Press (Barbell)", "Incline Bench Press (Barbell)", "Incline Bench Press (Dumbbell)",
        "Bench Press (Dumbbell)", "Close Grip Bench Press", "Chest Press (Machine)",
        "Chest Fly", "Incline Chest Fly", "Cable Crossover", "Chest Dip",
        "Overhead Press (Barbell)", "Shoulder Press (Dumbbell)", "Arnold Press (Dumbbell)",
        "Lateral Raise (Dumbbell)", "Front Raise (Dumbbell)", "Rear Delt Fly", "Face Pull",
        "Upright Row (Barbell)", "Shrug (Barbell)", "Shrug (Dumbbell)",
        "Pull Up", "Chin Up", "Lat Pulldown (Cable)", "Seated Cable Row",
        "Bent Over Row (Barbell)", "Bent Over Row (Dumbbell)", "T Bar Row",
        "Machine Row", "Pull Up (Weighted)",
        "Squat (Barbell)", "Front Squat (Barbell)", "Goblet Squat", "Hack Squat",
        "Leg Press", "Lunge (Dumbbell)", "Walking Lunge", "Bulgarian Split Squat",
        "Romanian Deadlift (Barbell)", "Deadlift (Barbell)", "Sumo Deadlift",
        "Good Morning", "Hip Thrust (Barbell)", "Leg Curl (Lying)", "Leg Curl (Seated)",
        "Leg Extension", "Calf Raise (Standing)", "Calf Raise (Seated)",
        "Bicep Curl (Barbell)", "Bicep Curl (Dumbbell)", "Hammer Curl (Dumbbell)",
        "Preacher Curl", "EZ Bar Curl", "Cable Curl", "Wrist Curl",
        "Triceps Pushdown", "Skullcrusher", "Overhead Triceps Extension",
        "Triceps Kickback", "Triceps Dip", "Bench Dip",
        "Crunch", "Cable Crunch", "Russian Twist", "Hanging Leg Raise", "Plank",
        // es-MX / colloquial (alias table)
        "press de banca", "press banca", "press inclinado", "press militar",
        "elevaciones laterales", "face pull", "dominadas", "jalon al pecho",
        "remo sentado", "remo con barra", "remo con mancuerna", "sentadilla",
        "sentadilla con barra", "prensa de pierna", "zancadas", "peso muerto rumano",
        "peso muerto", "hip thrust", "curl femoral", "extension de pierna",
        "elevacion de pantorrilla de pie", "curl de biceps con barra",
        "curl de biceps", "curl martillo", "extension de triceps en polea",
        "press frances", "fondos", "abdominales", "abdominales en polea",
        "bench press", "squat", "deadlift", "overhead press", "lat pulldown",
        "barbell row", "dumbbell curl", "leg press", "romanian deadlift", "rdl",
        "incline dumbbell press", "seated cable row", "lateral raise",
        "triceps pushdown", "hip thrust con barra", "walking lunges",
        "pec fly", "machine fly", "shoulder press", "chin up", "pull ups",
    ]

    /// `resolve` (the silent tier: id / exact name / learned) must NOT gain auto-matching — anything
    /// the user didn't confirm goes through the visible mapping step.
    func testResolveStaysConservative() {
        XCTAssertNil(Self.reconciler.resolve(WorkoutExercise(name: "Press banca con barra", sets: 3)),
                     "resolve() must not silently auto-match — that's autoMatch's (visible) job")
    }
}
