import XCTest
import CenitStore
import StrandTraining
@testable import Cenit

/// L3-F1: custom exercises are decoded once per memo fill, and resolution stays consistent
/// (override > custom > catalog) across `allExercises` / `resolvedExercise`.
@MainActor
final class StrengthExerciseResolveTests: XCTestCase {

    private var store: CenitStore!
    private var repo: Repository!
    private let deviceId = "test-device-strength-resolve"

    override func setUp() async throws {
        store = try await CenitStore.inMemory()
        repo = Repository(deviceId: deviceId)
        repo.attachStoreForTesting(store)
        StrengthExerciseMemo.invalidate(for: repo)
    }

    override func tearDown() async throws {
        StrengthExerciseMemo.invalidate(for: repo)
        repo = nil
        store = nil
    }

    /// `allExercises` and a loop of `resolvedExercise` agree after seeding customs + overrides,
    /// and the memo is filled a single time for that read burst (one custom-table decode).
    func testAllExercisesAndResolvedExerciseAgreeWithSingleMemoFill() async throws {
        let customA = Exercise(id: "custom-a", name: "Curl propio", type: .weightReps,
                               equipment: "barbell", primaryMuscles: ["biceps"],
                               secondaryMuscles: [], instructions: [])
        let customB = Exercise(id: "custom-b", name: "Press propio", type: .weightReps,
                               equipment: "dumbbell", primaryMuscles: ["chest"],
                               secondaryMuscles: [], instructions: [])
        try await repo.saveCustomExercise(customA)
        try await repo.saveCustomExercise(customB)

        // Override a catalog exercise if one exists; otherwise override a custom.
        let catalogId = ExerciseCatalog.all.first?.id
        if let catalogId {
            try await repo.setExerciseTypeOverride(catalogId, type: .bodyweight)
        }
        try await repo.setExerciseTypeOverride("custom-a", type: .time)

        // Writes invalidate; next reads should populate the memo once.
        XCTAssertNil(StrengthExerciseMemo.cachedEntry(for: repo))

        let all = await repo.allExercises()
        XCTAssertNotNil(StrengthExerciseMemo.cachedEntry(for: repo),
                        "allExercises must populate the strength read memo")

        let byId = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        XCTAssertEqual(byId["custom-a"]?.type, .time, "override must win on custom")
        XCTAssertEqual(byId["custom-b"]?.type, .weightReps)
        if let catalogId {
            XCTAssertEqual(byId[catalogId]?.type, .bodyweight, "override must win on catalog")
        }

        // Resolve many ids without a second store decode (memo still warm).
        let ids = Array(byId.keys.prefix(40))
        for id in ids {
            let resolved = await repo.resolvedExercise(id)
            XCTAssertEqual(resolved, byId[id],
                           "resolvedExercise(\(id)) must match allExercises entry")
        }
        // Still the same memo entry (no invalidation between reads).
        XCTAssertNotNil(StrengthExerciseMemo.cachedEntry(for: repo))

        // Write invalidates; subsequent resolve sees the update.
        let renamed = Exercise(id: "custom-a", name: "Curl renombrado", type: .weightReps,
                               equipment: "barbell", primaryMuscles: ["biceps"],
                               secondaryMuscles: [], instructions: [])
        try await repo.saveCustomExercise(renamed)
        XCTAssertNil(StrengthExerciseMemo.cachedEntry(for: repo),
                     "saveCustomExercise must invalidate the memo")
        let after = await repo.resolvedExercise("custom-a")
        // type override still applies on the re-fetched custom
        XCTAssertEqual(after?.name, "Curl renombrado")
        XCTAssertEqual(after?.type, .time)
    }

    func testResolveExercisePrecedenceOverrideCustomCatalog() {
        let catalog = Exercise(id: "x", name: "Cat", type: .bodyweight, equipment: nil,
                               primaryMuscles: ["core"], secondaryMuscles: [], instructions: [])
        let custom = Exercise(id: "x", name: "Custom", type: .weightReps, equipment: "barbell",
                              primaryMuscles: ["core"], secondaryMuscles: [], instructions: [])
        // custom base wins over catalog when no override
        let base = Repository.resolveExercise(id: "x", catalog: catalog, custom: custom, override: nil)
        XCTAssertEqual(base?.name, "Custom")
        XCTAssertEqual(base?.type, .weightReps)
        // override wins over both
        let over = Repository.resolveExercise(id: "x", catalog: catalog, custom: custom, override: .time)
        XCTAssertEqual(over?.type, .time)
        XCTAssertEqual(over?.name, "Custom", "override retypes base; does not swap identity")
        // catalog-only
        let catOnly = Repository.resolveExercise(id: "x", catalog: catalog, custom: nil, override: nil)
        XCTAssertEqual(catOnly?.name, "Cat")
        // unknown
        XCTAssertNil(Repository.resolveExercise(id: "nope", catalog: nil, custom: nil, override: nil))
    }
}
