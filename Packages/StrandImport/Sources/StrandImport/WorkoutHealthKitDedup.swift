import Foundation

/// De-duplicates the third-party strength workouts a user already owns in Apple Health (ola 2 · C4,
/// FER-362). Pure and Foundation-only — it operates on a minimal DTO and imports **nothing** from
/// `CenitStore`/`StrandTraining`, so it lives here (next to the CSV importer's dedup) and `swift test`
/// covers it without the app.
///
/// Two independent jobs, in order:
/// 1. **Echo** — an Apple-imported strength envelope that overlaps a rich `StrengthSession` (logged in
///    Cénit *or* imported from a CSV — both are just `RichInterval`s here) is the same workout read twice,
///    so it is dropped. The rich session always wins (it has the sets). The echo uses a **loose** sport
///    heuristic (contains strength/weight/lift/functional) so it also catches relabels like "Weight
///    Training". This mirrors what `UnifiedWorkoutHistory.isStrengthEcho` did inline; C4 moves it here.
/// 2. **Third-vs-third collapse** — two apps that recorded the *same* session write two overlapping
///    envelopes; among Apple **closed-strength** rows that overlap each other, keep the longest. The
///    closed set (`isClosedStrength`) is deliberately narrower than the echo heuristic: it also gates
///    entry into the app's «Fuerza» dialect, where a wrong inclusion would be visible.
///
/// The origin gate is `source` beginning with `apple-health` — a narrower, self-contained question than
/// re-deriving the app's `WorkoutSource.classify` taxonomy (so `manual`/`whoop`/`*-noop` are never
/// touched). The overlap predicate is **half-open interval overlap** `[startTs, endTs)`, never a
/// start-time window — an echo that begins 40 min into a 90-min session still overlaps and is dropped,
/// while two short workouts 25 min apart that don't overlap are both kept.
public enum WorkoutHealthKitDedup {

    /// The app maps `CenitStore.WorkoutRow` → this minimal shape (no CenitStore dependency here).
    public struct Workout: Equatable, Sendable {
        public let startTs: Int
        public let endTs: Int
        public let sport: String
        public let durationS: Double?
        public let source: String
        public init(startTs: Int, endTs: Int, sport: String, durationS: Double?, source: String) {
            self.startTs = startTs; self.endTs = endTs; self.sport = sport
            self.durationS = durationS; self.source = source
        }
    }

    /// A completed rich strength session (Cénit or CSV) reduced to the only thing dedup needs: its span.
    public struct RichInterval: Equatable, Sendable {
        public let startTs: Int
        public let endTs: Int
        public init(startTs: Int, endTs: Int) { self.startTs = startTs; self.endTs = endTs }
    }

    /// The CLOSED activity-type set — the only HK sports that count as strength for entry-to-«Fuerza»
    /// and for the third-vs-third collapse. Case-sensitive, matching `activityTypeName`'s output.
    public static func isClosedStrength(_ sport: String) -> Bool {
        sport == "TraditionalStrengthTraining" || sport == "FunctionalStrengthTraining"
    }

    /// The rows that survive both jobs, **in input order**.
    public static func survivingRows(_ rows: [Workout], richSessions: [RichInterval]) -> [Workout] {
        // Step 1 — echo: drop apple loose-strength rows overlapping a rich session. Keep offsets so the
        // final result preserves the caller's original order.
        let afterEcho = rows.enumerated().filter { !isEcho($0.element, rich: richSessions) }

        // Step 2 — collapse: among the surviving apple CLOSED-strength rows, keep the longest of each
        // overlapping cluster. Everything else (non-apple, cardio, non-closed apple) passes untouched.
        let collapsible = afterEcho.filter { isClosedStrengthApple($0.element) }
        let keptOffsets = keptAfterCollapse(collapsible)

        return afterEcho.compactMap { pair in
            if isClosedStrengthApple(pair.element) {
                return keptOffsets.contains(pair.offset) ? pair.element : nil
            }
            return pair.element
        }
    }

    // MARK: - internals

    static func isAppleSource(_ source: String) -> Bool {
        let s = source.lowercased()
        return s.hasPrefix("apple-health") || s.hasPrefix("apple_health")
    }

    private static func looksStrengthLoose(_ sport: String) -> Bool {
        let s = sport.lowercased()
        return s.contains("strength") || s.contains("weight") || s.contains("lift") || s.contains("functional")
    }

    private static func isClosedStrengthApple(_ w: Workout) -> Bool {
        isAppleSource(w.source) && isClosedStrength(w.sport)
    }

    private static func overlaps(_ w: Workout, _ r: RichInterval) -> Bool {
        w.startTs < r.endTs && r.startTs < w.endTs   // half-open interval overlap
    }

    private static func isEcho(_ w: Workout, rich: [RichInterval]) -> Bool {
        guard isAppleSource(w.source), looksStrengthLoose(w.sport) else { return false }
        return rich.contains { overlaps(w, $0) }
    }

    /// Longest-first greedy: keep a row unless it overlaps one already kept. Returns the set of kept
    /// offsets (into the enumerated `afterEcho`) so the caller can drop only the collapse-losers.
    private static func keptAfterCollapse(_ collapsible: [(offset: Int, element: Workout)]) -> Set<Int> {
        func dur(_ w: Workout) -> Double { w.durationS ?? Double(max(0, w.endTs - w.startTs)) }
        let ordered = collapsible.sorted {
            dur($0.element) != dur($1.element) ? dur($0.element) > dur($1.element) : $0.offset < $1.offset
        }
        var kept: [(offset: Int, element: Workout)] = []
        for row in ordered {
            let clashes = kept.contains { row.element.startTs < $0.element.endTs && $0.element.startTs < row.element.endTs }
            if !clashes { kept.append(row) }
        }
        return Set(kept.map(\.offset))
    }
}
