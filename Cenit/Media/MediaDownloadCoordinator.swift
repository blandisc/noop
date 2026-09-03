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
    /// mute button. A miss (no baked `gifUrl` for that exercise) is expected and never retried.
    /// `.failed` covers two cases: NOTHING downloaded at all, or ≥1 exercise hit a network failure
    /// this run — `.completed` must never claim success while a retriable download is still pending,
    /// so a partial run with any network failure reports `.failed` too, even if others matched
    /// (P0-2, Sev-5: a flaky connection used to be indistinguishable from "no gifUrl" and got
    /// permanently blacklisted, then a later run lied "already fully downloaded").
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

    /// Whether the disk cache holds anything right now (ronda 2 #13) — Ajustes reads this, not
    /// `downloadState`, to decide whether «Borrar animaciones» is reachable: this session's progress
    /// state resets to `.idle` on every relaunch even though the cache on disk survives, so gating the
    /// destructive button on `downloadState != .idle` made it unreachable without first re-triggering
    /// a download (which fires network) just to be able to delete.
    var hasCachedMedia: Bool { cache?.hasAnyThumb ?? false }

    @Published private(set) var downloadState: DownloadState = .idle

    /// Guards against a second bulk pass running concurrently — the launch resume (FER-800) and the
    /// Ajustes toggle can both call `bulkDownloadThumbsIfNeeded()`; the first to start owns the run.
    private var isBulkDownloading = false

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
        guard isEnabled, let cache, !isBulkDownloading else { return }
        isBulkDownloading = true
        defer { isBulkDownloading = false }

        let missed = missedIds
        let toDownload = ExerciseCatalog.all.filter { !cache.hasThumb(for: $0.id) && !missed.contains($0.id) }
        guard !toDownload.isEmpty else { downloadState = .completed(matched: 0, total: 0); return }

        downloadState = .downloading(completed: 0, total: toDownload.count)
        var completed = 0
        var networkFailures = 0

        // Only `.noMedia` results are collected into `newMisses` and persisted — up to ~1500
        // individual UserDefaults read-modify-writes would otherwise pile up during one bulk run.
        // `.networkFailure` is counted but never recorded: a dropped connection is transient, not a
        // verdict on the exercise, and persisting it would permanently blacklist an exercise that DOES
        // have a `gifUrl` (P0-2, Sev-5 — a flaky run used to poison `missedIds`, and a later run then
        // found nothing left to try and reported "already fully downloaded").
        let newMisses = await withTaskGroup(of: ThumbResult.self) { group -> Set<String> in
            var inFlight = 0
            var newMisses: Set<String> = []
            func record(_ result: ThumbResult) {
                switch result {
                case .stored: break
                case .noMedia(let id): newMisses.insert(id)
                case .networkFailure: networkFailures += 1
                }
                completed += 1
                if completed % 10 == 0 || completed == toDownload.count {
                    downloadState = .downloading(completed: completed, total: toDownload.count)
                }
            }
            for exercise in toDownload {
                if inFlight >= 6 {
                    if let result = await group.next() { record(result) }
                    inFlight -= 1
                }
                group.addTask { [weak self] in
                    guard let self else { return .stored }
                    return await self.downloadThumb(exercise, cache: cache)
                }
                inFlight += 1
            }
            for await result in group { record(result) }
            return newMisses
        }
        if !newMisses.isEmpty { recordMisses(newMisses) }
        let matched = toDownload.count - newMisses.count - networkFailures
        // Any network failure keeps this run out of `.completed`, even if others matched — claiming
        // "complete" while a retriable exercise is still missing is exactly the lie this fixes.
        downloadState = (matched == 0 || networkFailures > 0)
            ? .failed
            : .completed(matched: matched, total: toDownload.count)
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
        // A network failure here (throw or non-200) returns nil WITHOUT recording a miss, unlike the
        // guard above — a bad connection isn't a verdict on the exercise (P0-2, Sev-5): the next tap
        // retries the same GET instead of being permanently blacklisted.
        guard let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        try? cache.storeThumb(data, for: exercise.id)
        return cache.hasThumb(for: exercise.id) ? cache.thumbPath(exercise.id) : nil
    }

    /// The exercise's already-cached media file, or nil — NEVER downloads. For list rows (FER-790):
    /// a scrolling catalog of ~1500 exercises must show the thumb only when it's already on disk,
    /// never fire a per-row GET. Keeps the zero-request guarantee: no cache / not cached ⇒ nil.
    func cachedMediaURL(for exercise: Exercise) -> URL? { cachedMediaURL(forId: exercise.id) }

    /// La misma búsqueda, con el id solo. La sesión guiada lleva `exerciseId` y no un `Exercise` resuelto,
    /// así que sin esta variante `SessionRunThumb` no podía usar el respaldo del GIF: un ejercicio sin
    /// imagen horneada —los que entran por importación— salía SIN miniatura en la sesión activa aunque el
    /// editor sí se la mostrara (bug Fer 2026-07-18).
    func cachedMediaURL(forId id: String) -> URL? {
        guard let cache, cache.hasThumb(for: id) else { return nil }
        return cache.thumbPath(id)
    }

    /// Deletes every cached GIF and forgets recorded misses, so a future bulk run retries
    /// everything. Independent of the toggle: callable regardless of `isEnabled`.
    func deleteAllCachedMedia() {
        try? cache?.deleteAll()
        userDefaults.removeObject(forKey: Self.missedIdsKey)
    }

    /// Why one thumb download didn't end in `.stored` — only `.noMedia` is a verdict on the exercise;
    /// `.networkFailure` is transient and must never be persisted the same way (P0-2, Sev-5).
    private enum ThumbResult {
        case stored
        case noMedia(String)
        case networkFailure(String)
    }

    /// Downloads one exercise's thumb from its baked `gifUrl`, distinguishing why it didn't store:
    /// `.noMedia` (no `gifUrl` at all — permanent, retrying tomorrow won't produce one) from
    /// `.networkFailure` (the GET threw or came back non-200 — transient, the exercise DOES have
    /// media, this attempt just couldn't fetch it).
    private func downloadThumb(_ exercise: Exercise, cache: MediaCache) async -> ThumbResult {
        guard let thumbURL = mediaURL(for: exercise) else { return .noMedia(exercise.id) }
        guard let (data, response) = try? await session.data(from: thumbURL),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return .networkFailure(exercise.id) }
        try? cache.storeThumb(data, for: exercise.id)
        return .stored
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
