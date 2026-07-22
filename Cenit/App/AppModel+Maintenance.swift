import SwiftUI
import StrandDesign
import Combine
import Observation
import BiometricStreams
import CenitStore
import StrandImport
import StrandAnalytics
import StrandTraining

extension AppModel {

    // MARK: - One-time day-key re-bucket (FER-226)

    /// Cursor flag (in the existing `cursors` table — no schema change) that gates the one-time
    /// UTC→local day-key re-bucket so it runs at most once per install.
    private static let dayKeyMigrationCursor = "dayKeyV2Done"

    /// Re-group the on-device computed scores (and, when Apple Health is connected, the Apple rows)
    /// onto the device's LOCAL civil day, then prune the spurious future-in-local rows the old UTC
    /// dating left behind (FER-226). Flag-gated so it runs once; idempotent and safe to re-enter on
    /// every foreground. Conservative by construction: the re-group rewrites from the still-stored raw
    /// streams / Apple Health, and the prune only ever removes FUTURE-dated rows — a past day that
    /// can't be recomputed (raw already pruned) keeps its row, so there is no data loss.
    func migrateDayKeysToLocalIfNeeded() async {
        // Two-pass launch: if the full history hasn't published (e.g. a pull-to-refresh made the
        // launch full pass stale mid-flight), `analyzeRecent(force:)` below would skip silently and
        // the cursor would burn WITHOUT the re-group having run. Defer to the next foreground/launch.
        guard repo.fullyLoaded else { return }
        guard let store = await repo.storeHandle() else { return }   // no store yet → retry next launch
        if ((try? await store.cursor(Self.dayKeyMigrationCursor)) ?? nil) == 1 { return }   // already done

        let window = 60   // bounded recompute window; older days keep their date (accepted seam)

        // Apple Health: only when already connected (auth restored from the persisted "connected"
        // flag on launch). New Apple rows are written local from now on, so a user who connects HK
        // LATER has no UTC rows to migrate — the normal sync already lands them on the local day.
        // (The on-device band `-noop` re-group/prune is gone; only the Apple path is migrated now.)
        if let health = healthBridge, health.auth == .authorized {
            let writtenApple = await health.sync(days: window)
            await Self.pruneFutureLocalDays(store: store, deviceId: appleDeviceId, written: writtenApple)
        }

        // Mark done so the heavy re-group doesn't re-run on every launch. The re-group is idempotent,
        // so marking even when Apple was skipped is harmless (a later HK connect lands local anyway).
        try? await store.setCursor(Self.dayKeyMigrationCursor, 1)
    }

    // MARK: - One-time DB compaction after the spo2 purge (FER-511)

    /// Cursor flag (in the existing `cursors` table — no schema change) gating the one-time VACUUM
    /// that returns the space freed by the v20 spo2 purge to the OS, so it runs at most once per
    /// install. VACUUM rewrites the whole file, so it must NOT run on every launch.
    private static let spo2CompactCursor = "spo2VacuumV1Done"

    /// The v20 migration DELETEs the write-only spo2 rows, but the pages stay allocated (WAL, and the
    /// existing file was created with auto_vacuum=NONE) so the `.sqlite` doesn't shrink on its own.
    /// Run a single VACUUM to reclaim them (and convert the file to INCREMENTAL auto-vacuum going
    /// forward). Flag-gated + off the launch critical path (called from the analysis task). Best-effort:
    /// a failure just leaves the space reclaimable on a later run.
    func compactDatabaseAfterSpo2PurgeIfNeeded() async {
        guard let store = await repo.storeHandle() else { return }   // no store yet → retry next launch
        if ((try? await store.cursor(Self.spo2CompactCursor)) ?? nil) == 1 { return }   // already done
        do {
            try await store.vacuum()
            try await store.setCursor(Self.spo2CompactCursor, 1)
        } catch {
            // Leave the cursor unset so the next launch retries; the freed pages remain reclaimable.
        }
    }

    // MARK: - One-time DB compaction after the v21 WITHOUT-ROWID rebuild (FER-513)

    /// Cursor flag gating the one-time VACUUM that returns the space freed by the v21 rebuild (the five
    /// 1 Hz tables shrank ~60% but the old pages stay allocated until a VACUUM). Distinct from the spo2
    /// one so each runs exactly once. VACUUM rewrites the whole file → must NOT run every launch.
    private static let rebuildCompactCursor = "rebuildVacuumV1Done"

    /// After the v21 migration rebuilds the sample tables WITHOUT ROWID + integer deviceId, the file is
    /// much smaller logically but the freed pages aren't returned to the OS until a VACUUM. Run one,
    /// flag-gated + off the launch critical path. Best-effort: on failure (e.g. disk full) the cursor is
    /// left unset so the next launch retries, and SQLite's atomic VACUUM never corrupts on a partial run.
    func compactDatabaseAfterRebuildIfNeeded() async {
        guard let store = await repo.storeHandle() else { return }   // no store yet → retry next launch
        if ((try? await store.cursor(Self.rebuildCompactCursor)) ?? nil) == 1 { return }   // already done
        do {
            try await store.vacuum()
            try await store.setCursor(Self.rebuildCompactCursor, 1)
        } catch {
            // Leave the cursor unset so the next launch retries; the freed pages remain reclaimable.
        }
    }

    /// Prune rows for `deviceId` dated AFTER today's local civil day — the spurious "future-in-local"
    /// rows the old UTC dating materialized for the evening's data in a UTC− zone, now superseded by
    /// the local-day rows the re-group just wrote. Only future-dated rows are touched, so a past day
    /// that couldn't be recomputed keeps its row (no data loss). `written` are this run's freshly
    /// written local days, excluded defensively. Static: no instance state, just the store.
    private static func pruneFutureLocalDays(store: CenitStore, deviceId: String,
                                             written: Set<String>) async {
        let todayLocal = Repository.localDayKey(Date())
        // A UTC offset shifts a row by at most one day, so [today … +2d local] covers every future orphan.
        let now = Int(Date().timeIntervalSince1970)
        let tz = TimeZone.current.secondsFromGMT()
        let toDay = AnalyticsEngine.dayString(now + 2 * 86_400, tzOffsetSeconds: tz)
        let rows = (try? await store.dailyMetrics(deviceId: deviceId, from: todayLocal, to: toDay)) ?? []
        let future = AnalyticsEngine.futureLocalDaysToPrune(stored: rows.map(\.day),
                                                            today: todayLocal, written: written)
        if !future.isEmpty {
            _ = try? await store.deleteDailyMetrics(deviceId: deviceId, days: future)
        }
    }
}
