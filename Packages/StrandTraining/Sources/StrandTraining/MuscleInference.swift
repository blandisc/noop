import Foundation

// Guess a primary muscle from an exercise's *name* (FER-995).
//
// Why this exists: the import flow's «create new» used to save an exercise with `primaryMuscles: []`,
// which makes it invisible to the muscle map, the weekly volume and `RoutineClassifier` — silently, so a
// routine could be misclassified by one imported exercise and nothing said so. The fix is not to guess
// behind the user's back: this only *proposes* a muscle, pre-filled in the create form, which the user
// confirms or corrects. A wrong proposal is one tap away from being fixed; an empty muscle was forever.
//
// Deliberately a dumb keyword table, not a model: it is auditable, deterministic and covered by tests.
// It returns `nil` when nothing matches rather than picking a plausible-looking default — an honest
// «pick one» beats a confident wrong answer.

public enum MuscleInference {

    /// A phrase that implies a primary muscle. Keys are matched against the normalized name as whole
    /// words; the **longest matching phrase wins**, so «leg press» (quadriceps) beats «press» (chest)
    /// and «front raise» (shoulders) beats «raise» (calves).
    ///
    /// Values are the catalog's lowercased English muscle keys (`MuscleVocabulary.es`), so a proposal is
    /// always a value the rest of the app already understands.
    static let phrases: [String: String] = [
        // Chest
        "bench press": "chest", "chest press": "chest", "chest fly": "chest", "chest flye": "chest",
        "pec deck": "chest", "pushup": "chest", "push up": "chest", "push ups": "chest",
        "dips": "chest", "dip": "chest", "pullover": "chest", "chest": "chest", "pec": "chest",

        // Shoulders
        "shoulder press": "shoulders", "overhead press": "shoulders", "military press": "shoulders",
        "arnold press": "shoulders", "lateral raise": "shoulders", "side raise": "shoulders",
        "front raise": "shoulders", "upright row": "shoulders", "face pull": "shoulders",
        "rear delt": "shoulders", "delt": "shoulders", "shoulder": "shoulders", "shoulders": "shoulders",

        // Triceps
        "triceps": "triceps", "tricep": "triceps", "skullcrusher": "triceps", "skull crusher": "triceps",
        "pushdown": "triceps", "push down": "triceps", "kickback": "triceps", "close grip bench": "triceps",

        // Biceps
        "biceps": "biceps", "bicep": "biceps", "curl": "biceps", "chin up": "biceps", "chinup": "biceps",
        "preacher": "biceps", "hammer curl": "biceps",

        // Back
        "lat pulldown": "lats", "pulldown": "lats", "pull down": "lats", "pull up": "lats",
        "pullup": "lats", "pull ups": "lats", "lats": "lats", "lat": "lats",
        "row": "middle back", "rowing": "middle back", "seated row": "middle back",
        "bent over row": "middle back", "t bar row": "middle back", "middle back": "middle back",
        "shrug": "traps", "traps": "traps", "trap": "traps",
        "deadlift": "lower back", "good morning": "lower back", "back extension": "lower back",
        "hyperextension": "lower back", "lower back": "lower back",

        // Legs
        "squat": "quadriceps", "leg press": "quadriceps", "leg extension": "quadriceps",
        "lunge": "quadriceps", "step up": "quadriceps", "split squat": "quadriceps",
        "quadriceps": "quadriceps", "quad": "quadriceps",
        "leg curl": "hamstrings", "romanian deadlift": "hamstrings", "rdl": "hamstrings",
        "stiff leg deadlift": "hamstrings", "hamstring": "hamstrings", "hamstrings": "hamstrings",
        "hip thrust": "glutes", "glute bridge": "glutes", "glute": "glutes", "glutes": "glutes",
        "calf raise": "calves", "calf": "calves", "calves": "calves",
        "hip abduction": "abductors", "abductor": "abductors", "abduction": "abductors",
        "hip adduction": "adductors", "adductor": "adductors", "adduction": "adductors",

        // Core / other
        "crunch": "abdominals", "sit up": "abdominals", "situp": "abdominals", "plank": "abdominals",
        "leg raise": "abdominals", "russian twist": "abdominals", "ab wheel": "abdominals",
        "hanging knee raise": "abdominals", "abdominal": "abdominals", "abs": "abdominals",
        "neck curl": "neck", "neck": "neck",
        "wrist curl": "forearms", "forearm": "forearms", "grip": "forearms",
    ]

    /// The primary muscle implied by `name`, or `nil` when nothing in the vocabulary matches.
    ///
    /// Matching is whole-word on a normalized form (lowercased, punctuation → spaces), so «Dumbbell
    /// Incline Bench Press» matches «bench press» while «pressa» matches nothing. Among several matches
    /// the longest phrase wins, and an exact length tie resolves alphabetically so the result never
    /// depends on dictionary iteration order.
    public static func primaryMuscle(forName name: String) -> String? {
        let haystack = " " + normalize(name) + " "
        var best: (phrase: String, muscle: String)?
        for (phrase, muscle) in phrases where haystack.contains(" " + phrase + " ") {
            guard let current = best else { best = (phrase, muscle); continue }
            if phrase.count > current.phrase.count
                || (phrase.count == current.phrase.count && phrase < current.phrase) {
                best = (phrase, muscle)
            }
        }
        return best?.muscle
    }

    /// Lowercase and reduce anything that isn't a letter or digit to a single space, so hyphens, slashes
    /// and parentheses in a plan's names («close-grip bench press (barbell)») don't hide a match.
    static func normalize(_ name: String) -> String {
        let scalars = name.lowercased().unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : " "
        }
        return String(scalars).split(separator: " ").joined(separator: " ")
    }
}
