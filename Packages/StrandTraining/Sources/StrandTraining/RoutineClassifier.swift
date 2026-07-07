import Foundation

// A content-derived identity for a routine: which coarse training region its exercises predominantly
// hit, computed from their `primaryMuscles`. `Routine` carries no category/color field (only a free
// `name`), so the color of identity is derived, never guessed from the name — a routine's family stays
// stable across app launches (unlike `String.hashValue`, whose seed is randomized per process). Pure and
// database-free so it lives here and is covered by `swift test`; the app maps the region to a token color.
//
// This is the single classifier shared by every routine-tinted surface (the guided session header FER-745,
// the Entrenar planner's dots/legend/Constancia grid FER-775) — one criterion, never duplicated.

/// The coarse training region a routine belongs to. `push`/`pull`/`legs` are the three classifiable
/// regions; `fullBody` is the routine-level outcome when the mix is too even for any one region to lead.
public enum RoutineRegion: String, Sendable, CaseIterable {
    case push, pull, legs, fullBody
}

public enum RoutineClassifier {

    /// The three classifiable regions in a fixed order — used as the deterministic tie-break so a tie always
    /// resolves to the same region (a `Dictionary.max` by value is unstable across accesses).
    private static let orderedRegions: [RoutineRegion] = [.push, .pull, .legs]

    /// Map a catalog primary-muscle key (lowercased English) to its region. Neutral muscles — abdominals,
    /// neck, lower back — and anything unknown return `nil` and are excluded from the denominator (they
    /// don't tip a routine one way or the other). `fullBody` is never returned here: it's a routine-level
    /// outcome, not a muscle's region.
    public static func region(for muscle: String) -> RoutineRegion? {
        switch muscle.lowercased() {
        case "chest", "shoulders", "triceps":
            return .push
        case "lats", "middle back", "biceps", "traps", "forearms":
            return .pull
        case "quadriceps", "hamstrings", "glutes", "calves", "abductors", "adductors":
            return .legs
        default:
            return nil   // abdominals, neck, lower back, and any unmapped/empty muscle
        }
    }

    /// Classify a routine into a region from its exercises' primary muscles (one `[String]` of primary
    /// muscles per exercise). Each exercise votes once for its own dominant region (neutral muscles
    /// excluded, ties broken by `orderedRegions`); an exercise with no classifiable primary muscle abstains.
    /// The region with the most votes wins if it holds **≥ 50 %** of the voting exercises; otherwise the
    /// routine is too mixed → `.fullBody`. Returns `nil` when no exercise is classifiable (e.g. cardio or
    /// abs-only), so callers can fall back to a default hue.
    public static func classify(primaryMusclesPerExercise: [[String]]) -> RoutineRegion? {
        var votes: [RoutineRegion: Int] = [:]
        var voting = 0
        for muscles in primaryMusclesPerExercise {
            guard let region = dominantRegion(of: muscles) else { continue }   // abstains
            votes[region, default: 0] += 1
            voting += 1
        }
        guard voting > 0 else { return nil }
        guard let (winner, count) = leadingRegion(votes) else { return nil }
        return Double(count) / Double(voting) >= 0.5 ? winner : .fullBody
    }

    /// One exercise's region: the region most represented across its primary muscles (neutral excluded),
    /// tie-broken deterministically. `nil` when it hits no classifiable muscle.
    private static func dominantRegion(of muscles: [String]) -> RoutineRegion? {
        var tally: [RoutineRegion: Int] = [:]
        for m in muscles { if let r = region(for: m) { tally[r, default: 0] += 1 } }
        return leadingRegion(tally)?.0
    }

    /// The strictly-ahead leader of a region tally, scanned in fixed order so ties resolve deterministically.
    private static func leadingRegion(_ tally: [RoutineRegion: Int]) -> (RoutineRegion, Int)? {
        var best: RoutineRegion?
        var bestCount = 0
        for r in orderedRegions where (tally[r] ?? 0) > bestCount {
            best = r; bestCount = tally[r] ?? 0
        }
        return best.map { ($0, bestCount) }
    }
}
