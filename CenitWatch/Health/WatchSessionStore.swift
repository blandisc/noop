import Foundation
import StrandTraining

/// Durable, file-backed buffer for the watch's own strength-session state (C1 · FER-361, B1) — NOT GRDB:
/// the wrist has no database (FER-740's whole premise is a database-free watch), so this persists two
/// `StrengthSessionSnapshot`s as plain JSON under `applicationSupportDirectory`, the same primitive
/// `MediaCache`/`StorePaths` already use on the iPhone side (atomic writes, no metadata beyond presence).
///
/// Two independent slots:
/// - **seed**: today's plan, pushed by the iPhone as `.sessionModel` over `updateApplicationContext` so
///   it's cached even while the watch is offline. `WatchWorkoutManager.startTodayFromWrist()` turns it
///   into a fresh plan (`StrengthSessionSnapshot.asTemplate`) to start a session standalone.
/// - **inProgress**: the standalone session actually being logged on the wrist right now — `nil` when
///   there is none. Written on every durable edit (debounced) and cleared once the session ends, so a
///   relaunch mid-session (the watch died / was force-quit) finds it again (`recoverIfNeeded`).
///
/// An `actor` because both slots are written from the wrist's message-handling and its own logging call
/// sites, which don't share a queue; the per-slot debounce `Task` is itself actor-isolated, so a burst of
/// edits (dialing a weight, a fast set-after-set superset) collapses into the ONE most recent write —
/// same idea as the iPhone's own in-progress debounce (`AppModel+SessionMirror.scheduleInProgressPersist`).
actor WatchSessionStore {
    static let shared = WatchSessionStore()

    private let seedURL: URL
    private let inProgressURL: URL

    private var seedWriteTask: Task<Void, Never>?
    private var inProgressWriteTask: Task<Void, Never>?

    /// Coalesce a burst of edits into one write — generous enough to skip a disk write per crown tick
    /// or per set in a fast round, short enough that a crash right after the last edit loses very little.
    private static let debounceNanoseconds: UInt64 = 1_000_000_000

    init() {
        let dir = Self.directory()
        seedURL = dir.appendingPathComponent("seed.json")
        inProgressURL = dir.appendingPathComponent("inProgress.json")
    }

    private static func directory() -> URL {
        let fm = FileManager.default
        let base = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                appropriateFor: nil, create: true)) ?? fm.temporaryDirectory
        let dir = base.appendingPathComponent("WatchSession", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Seed (today's plan, pushed by the iPhone)

    /// Cache today's plan. Debounced like `saveInProgress` — the iPhone may re-push `.sessionModel` on
    /// every reachability change, and most of those re-pushes don't need their own disk write.
    func saveSeed(_ snapshot: StrengthSessionSnapshot) {
        seedWriteTask?.cancel()
        let url = seedURL
        seedWriteTask = Task {
            try? await Task.sleep(nanoseconds: Self.debounceNanoseconds)
            guard !Task.isCancelled else { return }
            Self.write(snapshot, to: url)
        }
    }

    /// The last cached seed, or nil if the watch has never received one (fresh install, or never synced).
    func loadSeed() -> StrengthSessionSnapshot? { Self.read(from: seedURL) }

    // MARK: - In-progress (a standalone session being logged on the wrist)

    /// Persist the session actually running on the wrist right now. Debounced — logging a set, adding a
    /// drop, or a crown-driven weight adjustment all fire this, and shouldn't each force a disk write.
    func saveInProgress(_ snapshot: StrengthSessionSnapshot) {
        inProgressWriteTask?.cancel()
        let url = inProgressURL
        inProgressWriteTask = Task {
            try? await Task.sleep(nanoseconds: Self.debounceNanoseconds)
            guard !Task.isCancelled else { return }
            Self.write(snapshot, to: url)
        }
    }

    /// The in-progress standalone session, or nil if none is running.
    func loadInProgress() -> StrengthSessionSnapshot? { Self.read(from: inProgressURL) }

    /// Drop the in-progress snapshot (the session saved or ended). Cancels any write still in flight
    /// first, so a debounced write from just before the end can't resurrect the file right after this
    /// deletes it.
    func clearInProgress() {
        inProgressWriteTask?.cancel()
        inProgressWriteTask = nil
        try? FileManager.default.removeItem(at: inProgressURL)
    }

    // MARK: - File IO (best-effort, atomic — mirrors `MediaCache`'s write primitive)

    private static func write(_ snapshot: StrengthSessionSnapshot, to url: URL) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private static func read(from url: URL) -> StrengthSessionSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(StrengthSessionSnapshot.self, from: data)
    }
}
