import Foundation

/// Curated synonym table for matching imported exercise names (FER-522).
///
/// LLM-generated plans name exercises with common variants that are neither the exact catalog name
/// nor a picked id ("press plano", "jalón dorsal", "sentadilla profunda"…). This bundled table maps
/// those variants (es/en) to a catalog `id`, so the import reconciler (StrandImport) can match them
/// before falling to the manual mapping step. Pure data, bundled, offline — and re-curatable as data.
///
/// The `alias` strings are written naturally (accents, case); the reconciler normalizes them with the
/// same `normalize` it uses for names, so matching is consistent. Each `id` must exist in
/// `ExerciseCatalog` (a test enforces it).
public enum ExerciseAliases {
    /// Every (alias, catalog-id) pair, decoded once from the bundled `exercise-aliases.json`.
    public static let all: [(alias: String, id: String)] = load()

    private struct Entry: Decodable { let alias: String; let id: String }

    private static func load() -> [(alias: String, id: String)] {
        guard let url = Bundle.module.url(forResource: "exercise-aliases", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([Entry].self, from: data)
        else { return [] }
        return list.map { ($0.alias, $0.id) }
    }
}
