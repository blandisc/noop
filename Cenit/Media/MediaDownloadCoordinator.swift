import Foundation
import StrandTraining

// MARK: - The single gate for exercise-media downloads (FER-722)
//
// Every network call this feature ever makes flows through `bulkDownloadThumbsIfNeeded()` or
// `loopIfNeeded(for:)`, and both guard on `isEnabled` before touching `ExerciseDBClient` or
// `URLSession` at all. With the toggle off (the default), `client` is never constructed and no
// request is ever built — this is what makes "toggle off ⇒ zero requests" a structural property,
// checkable by a unit test, rather than a promise buried in call-site discipline.
//
// Catalog→EDB mapping: there is no static id map. Each lookup passes the catalog's own
// `exercise.name` (English, stable) to EDB's name search. Building a hand-authored map for 873
// entries without hitting the live API would mean inventing ids; a name-based lookup is simpler,
// self-healing if EDB's dataset changes, and degrades gracefully (miss → YouTube fallback stays).
@MainActor
final class MediaDownloadCoordinator: ObservableObject {
    static let enabledKey = "noop.exerciseMediaEnabled"
    /// Exercise ids EDB had no match for, so bulk downloads don't retry them every run. Small
    /// (≤873 strings), non-critical — UserDefaults is fine; re-derivable by re-running the bulk pass.
    private static let missedIdsKey = "noop.exerciseMediaMissedIds"

    private let userDefaults: UserDefaults
    private let session: URLSession
    /// Both built lazily, only once actually needed — never while the toggle is off, so a disabled
    /// coordinator (the default, at every app launch) never touches disk or `URLSession`.
    private lazy var cache: MediaCache? = try? MediaCache()
    private var client: ExerciseDBClient?

    /// Exposed for tests: true only once `bulkDownloadThumbsIfNeeded`/`loopIfNeeded` have actually
    /// needed the network client. Stays nil for the whole lifetime of a disabled coordinator.
    var hasBuiltClient: Bool { client != nil }

    var isEnabled: Bool { userDefaults.bool(forKey: Self.enabledKey) }

    init(userDefaults: UserDefaults = .standard, session: URLSession = .shared) {
        self.userDefaults = userDefaults
        self.session = session
    }

    /// Bulk-download every catalog exercise's thumb, skipping ones already cached or already known
    /// to miss. Bounded concurrency (6 in flight) so a fresh opt-in doesn't fire 873 requests at once.
    func bulkDownloadThumbsIfNeeded() async {
        guard isEnabled, let cache, let client = ensureClient() else { return }

        let missed = missedIds
        let toDownload = ExerciseCatalog.all.filter { !cache.hasThumb(for: $0.id) && !missed.contains($0.id) }
        guard !toDownload.isEmpty else { return }

        // Misses are collected here and persisted once at the end, not per-download — up to ~873
        // individual UserDefaults read-modify-writes would otherwise pile up during one bulk run.
        let newMisses = await withTaskGroup(of: String?.self) { group -> Set<String> in
            var inFlight = 0
            var newMisses: Set<String> = []
            for exercise in toDownload {
                if inFlight >= 6 {
                    if let missedId = await group.next(), let missedId { newMisses.insert(missedId) }
                    inFlight -= 1
                }
                group.addTask { [weak self] in
                    await self?.downloadThumb(exercise, client: client, cache: cache)
                }
                inFlight += 1
            }
            for await missedId in group {
                if let missedId { newMisses.insert(missedId) }
            }
            return newMisses
        }
        if !newMisses.isEmpty { recordMisses(newMisses) }
    }

    /// The cached thumb for `exercise`, if the bulk download already fetched it. Never triggers a
    /// download itself — that only happens in `bulkDownloadThumbsIfNeeded()`.
    func cachedThumbURL(for exercise: Exercise) -> URL? {
        guard let cache, cache.hasThumb(for: exercise.id) else { return nil }
        return cache.thumbPath(exercise.id)
    }

    /// Fetch the loop for one exercise, on demand (called from the detail screen). Returns the
    /// cached file if present; otherwise looks it up and caches it, or nil if unavailable.
    func loopIfNeeded(for exercise: Exercise) async -> URL? {
        guard isEnabled, let cache else { return nil }
        if let cached = cache.videoURL(for: exercise.id) { return cached }
        guard let client = ensureClient() else { return nil }

        guard let media = try? await client.lookup(name: exercise.name),
              let loopURL = media.mediaURL else {
            recordMisses([exercise.id])
            return nil
        }
        return try? await cache.storeVideo(from: loopURL, for: exercise.id, session: session)
    }

    /// Deletes every cached thumb/video and forgets recorded misses, so a future bulk run retries
    /// everything. Independent of the toggle: callable regardless of `isEnabled`.
    func deleteAllCachedMedia() {
        try? cache?.deleteAll()
        userDefaults.removeObject(forKey: Self.missedIdsKey)
    }

    /// Returns the network client, building (and caching) it the first time it's actually needed.
    private func ensureClient() -> ExerciseDBClient? {
        if let client { return client }
        client = ExerciseDBClient()
        return client
    }

    /// Downloads one exercise's thumb; returns its id if EDB had no media / the download failed, so
    /// the caller can batch that into a single miss-list write instead of one write per exercise.
    private func downloadThumb(_ exercise: Exercise, client: ExerciseDBClient, cache: MediaCache) async -> String? {
        guard let media = try? await client.lookup(name: exercise.name),
              let thumbURL = media.mediaURL else { return exercise.id }
        guard let (data, response) = try? await session.data(from: thumbURL),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return exercise.id }
        try? cache.storeThumb(data, for: exercise.id)
        return nil
    }

    private var missedIds: Set<String> {
        Set(userDefaults.stringArray(forKey: Self.missedIdsKey) ?? [])
    }

    private func recordMisses<S: Sequence>(_ exerciseIds: S) where S.Element == String {
        var current = missedIds
        current.formUnion(exerciseIds)
        userDefaults.set(Array(current), forKey: Self.missedIdsKey)
    }
}
