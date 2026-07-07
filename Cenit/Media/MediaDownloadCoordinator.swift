import Foundation
import StrandTraining

// MARK: - The single gate for exercise-media downloads (FER-722, FER-786, FER-790)
//
// Every network call this feature ever makes flows through `bulkDownloadThumbsIfNeeded()` or
// `mediaIfNeeded(for:)`, and both guard on `isEnabled` before touching `URLSession` at all. With the
// toggle off (the default), nothing is ever fetched — this is what makes "toggle off ⇒ zero requests"
// a structural property, checkable by a unit test, rather than a promise buried in call-site discipline.
//
// Catalog→media mapping (FER-786): since the catalog IS ExerciseDB (FER-779), each exercise carries its
// own `gifUrl` baked by id — no runtime name search, no API key. The download is a plain GET of that
// URL off the ExerciseDB CDN. An exercise with no `gifUrl` is a miss → the YouTube hand-off fallback
// stays. The GIF is a single asset that serves as both the still thumbnail and the animated loop
// (FER-790) — one download, one cached file, rendered still in rows and animated in the detail hero.
@MainActor
final class MediaDownloadCoordinator: ObservableObject {
    static let enabledKey = "noop.exerciseMediaEnabled"
    /// Exercise ids with no baked media, so bulk downloads don't retry them every run. Small
    /// (≤ catalog size), non-critical — UserDefaults is fine; re-derivable by re-running the bulk pass.
    private static let missedIdsKey = "noop.exerciseMediaMissedIds"

    /// The bulk thumb download's observable progress (FER-778) — Ajustes reads this instead of a
    /// mute button. A miss (no baked `gifUrl` for that exercise, or its download failed) is expected;
    /// `.failed` is reserved for the case where NOTHING downloaded at all (almost certainly no connection).
    enum DownloadState: Equatable {
        case idle
        case downloading(completed: Int, total: Int)
        case completed(matched: Int, total: Int)
        case failed
    }

    private let userDefaults: UserDefaults
    private let session: URLSession
    /// Built lazily, only once actually needed — never while the toggle is off, so a disabled
    /// coordinator (the default, at every app launch) never touches disk.
    private lazy var cache: MediaCache? = try? MediaCache()

    var isEnabled: Bool { userDefaults.bool(forKey: Self.enabledKey) }

    @Published private(set) var downloadState: DownloadState = .idle

    init(userDefaults: UserDefaults = .standard, session: URLSession = .shared) {
        self.userDefaults = userDefaults
        self.session = session
    }

    /// Turning the toggle off doesn't delete anything, but the progress row should go quiet again —
    /// same layout as before the toggle existed.
    func resetDownloadState() { downloadState = .idle }

    /// The exercise's baked media URL (the ExerciseDB `gifUrl`), or nil if it has none.
    private func mediaURL(for exercise: Exercise) -> URL? {
        exercise.gifUrl.flatMap(URL.init(string:))
    }

    /// Bulk-download every catalog exercise's thumb, skipping ones already cached or already known
    /// to miss. Bounded concurrency (6 in flight) so a fresh opt-in doesn't fire every request at once.
    func bulkDownloadThumbsIfNeeded() async {
        guard isEnabled, let cache else { return }

        let missed = missedIds
        let toDownload = ExerciseCatalog.all.filter { !cache.hasThumb(for: $0.id) && !missed.contains($0.id) }
        guard !toDownload.isEmpty else { downloadState = .completed(matched: 0, total: 0); return }

        downloadState = .downloading(completed: 0, total: toDownload.count)
        var completed = 0

        // Misses are collected here and persisted once at the end, not per-download — up to ~1500
        // individual UserDefaults read-modify-writes would otherwise pile up during one bulk run.
        let newMisses = await withTaskGroup(of: String?.self) { group -> Set<String> in
            var inFlight = 0
            var newMisses: Set<String> = []
            for exercise in toDownload {
                if inFlight >= 6 {
                    if let missedId = await group.next() {
                        if let missedId { newMisses.insert(missedId) }
                        completed += 1
                        downloadState = .downloading(completed: completed, total: toDownload.count)
                    }
                    inFlight -= 1
                }
                group.addTask { [weak self] in
                    await self?.downloadThumb(exercise, cache: cache)
                }
                inFlight += 1
            }
            for await missedId in group {
                if let missedId { newMisses.insert(missedId) }
                completed += 1
                downloadState = .downloading(completed: completed, total: toDownload.count)
            }
            return newMisses
        }
        if !newMisses.isEmpty { recordMisses(newMisses) }
        let matched = toDownload.count - newMisses.count
        downloadState = matched == 0 ? .failed : .completed(matched: matched, total: toDownload.count)
    }

    /// The exercise's media file (the animated GIF) for the detail hero, on demand. Returns the
    /// cached file if already downloaded; otherwise, only if enabled, downloads its baked `gifUrl`
    /// and caches it. Nil if the toggle is off and nothing is cached, or the exercise has no media —
    /// so the hero falls back to the placeholder. The zero-request guarantee holds: a disabled
    /// coordinator with no cache never reaches the GET.
    func mediaIfNeeded(for exercise: Exercise) async -> URL? {
        guard let cache else { return nil }
        if cache.hasThumb(for: exercise.id) { return cache.thumbPath(exercise.id) }
        guard isEnabled, let url = mediaURL(for: exercise) else {
            if isEnabled { recordMisses([exercise.id]) }
            return nil
        }
        guard let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        try? cache.storeThumb(data, for: exercise.id)
        return cache.hasThumb(for: exercise.id) ? cache.thumbPath(exercise.id) : nil
    }

    /// Deletes every cached GIF and forgets recorded misses, so a future bulk run retries
    /// everything. Independent of the toggle: callable regardless of `isEnabled`.
    func deleteAllCachedMedia() {
        try? cache?.deleteAll()
        userDefaults.removeObject(forKey: Self.missedIdsKey)
    }

    /// Downloads one exercise's thumb from its baked `gifUrl`; returns its id if it has no media / the
    /// download failed, so the caller can batch that into a single miss-list write.
    private func downloadThumb(_ exercise: Exercise, cache: MediaCache) async -> String? {
        guard let thumbURL = mediaURL(for: exercise) else { return exercise.id }
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
