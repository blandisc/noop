import Foundation

/// FER-923: the two bundled maps that drive the v33 exercise-catalog remap (see `makeMigrator`).
/// Baked by `Tools/bake-exercisedb/build_remap.py` from the old ExerciseDB catalog against the new
/// free-exercise-db one, and shipped zlib-compressed (raw DEFLATE, same wrapper as StrandTraining's
/// `exercises.json.zlib`) so the migration is fully offline.
extension CenitStore {
    /// One legacy (old-ExerciseDB) exercise with NO exact-name match in the new catalog — carried so a
    /// saved set that references it can be materialized as a `customExercise` instead of orphaning.
    struct LegacyExerciseData: Decodable {
        let name: String
        let type: String
        let equipment: String?
        let primaryMuscles: [String]
        let secondaryMuscles: [String]
    }

    /// Load `exercise-id-remap` (old id → new slug) and `legacy-exercise-data` (old id → its record)
    /// from the bundle. Missing/corrupt resources decode to empty, which makes the v33 migration a
    /// safe no-op rather than a crash.
    static func loadExerciseRemapResources() -> (remap: [String: String], legacy: [String: LegacyExerciseData]) {
        func decode<T: Decodable>(_ name: String, as _: T.Type) -> T? {
            guard let url = Bundle.module.url(forResource: name, withExtension: "zlib"),
                  let compressed = try? Data(contentsOf: url),
                  let data = try? (compressed as NSData).decompressed(using: .zlib) as Data
            else { return nil }
            return try? JSONDecoder().decode(T.self, from: data)
        }
        let remap = decode("exercise-id-remap.json", as: [String: String].self) ?? [:]
        let legacy = decode("legacy-exercise-data.json", as: [String: LegacyExerciseData].self) ?? [:]
        return (remap, legacy)
    }

    /// Compact JSON-array encoding for the `customExercise` muscle columns (stored as JSON text).
    static func jsonArrayText(_ items: [String]) -> String {
        guard let data = try? JSONEncoder().encode(items),
              let text = String(data: data, encoding: .utf8) else { return "[]" }
        return text
    }
}
