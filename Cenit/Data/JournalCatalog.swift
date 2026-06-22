import Foundation

/// The user's custom journal questions plus the starter behaviour catalog. Question strings are
/// opaque exact-match labels to BehaviorInsights, so imported question strings (merged in at load
/// time, ahead of these) always take precedence — adopting the export's exact wording is what
/// joins a logged day and an imported day into one behaviour. UserDefaults-backed (single user).
@MainActor
final class JournalCatalogStore: ObservableObject {

    /// Mirrors Android STARTER_JOURNAL_QUESTIONS value-for-value (JournalLog.kt). These are DATA,
    /// not UI literals — stored verbatim in the journal table and rendered verbatim, so they must
    /// never be localised (a translated key would start a new, disconnected behaviour).
    nonisolated static let starterQuestions: [String] = [
        "Did you drink any alcohol?",
        "Did you have caffeine late in the day?",
        "Did you view a screen in bed?",
        "Did you eat close to bedtime?",
        "Did you feel stressed?",
        "Did you use a sauna?",
        "Did you share your bed?",
        "Did you feel sick or ill?",
        "Did you take magnesium?",
        "Did you read before bed?",
    ]

    /// The Coach's diet-adherence behavior identity (FER-385). Like the starter questions this is a
    /// STABLE English data string — the engine join key and the value stored in an experiment row — never
    /// localised. It is NOT a journal question (you don't answer it in the journal; it's derived from the
    /// `diet-adherence` series), so it lives apart from `starterQuestions`. Its es-MX display label is in
    /// `esLabels` below, exactly like the journal behaviors.
    nonisolated static let dietBehaviorKey = "Did you follow your diet?"

    @Published var customQuestions: [String] { didSet { d.set(customQuestions, forKey: K.custom) } }

    private let d = UserDefaults.standard
    private enum K { static let custom = "journal.customQuestions" }

    init() { customQuestions = d.stringArray(forKey: K.custom) ?? [] }

    /// imported > starter > custom; case-insensitive dedupe, first casing wins. Imported questions
    /// lead so the export's exact strings (which the effects engine keys on) survive verbatim and
    /// pull the matching starter/custom out of the list.
    nonisolated static func mergeCatalog(imported: [String], custom: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for q in imported + starterQuestions + custom {
            let t = q.trimmingCharacters(in: .whitespaces)
            if !t.isEmpty, seen.insert(t.lowercased()).inserted { out.append(t) }
        }
        return out
    }

    /// A short es-MX display label for a known starter behaviour. The journal QUESTION itself is data
    /// (the engine's join key, never localised — see `starterQuestions`), so the Spanish copy lives
    /// here as a display-only mapping (FER-312). Unknown questions (custom / imported) fall back to
    /// the verbatim string.
    nonisolated static func esLabel(for question: String) -> String {
        if question == dietBehaviorKey { return String(localized: "I followed my diet", bundle: .main) }
        // The short display label lives in the String Catalog (en + es), so it follows the app language —
        // single source shared with the InsightEngine. The journal QUESTION is the catalog key; unknown
        // (custom/imported) questions fall back to the raw question. FER-477.
        return Bundle.main.localizedString(forKey: question, value: question, table: nil)
    }
}
