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

    /// Start (or resume) the periodic on-device analysis loop. Idempotent — a call while the loop is
    /// already running is a no-op, so the launch path and the scene-phase `.active` hook don't
    /// double-start it. The loop refreshes the dashboard once; if today still has no verdict it runs
    /// `analyzeRecent()` right away (the stored raw streams may already produce it — no reason to make
    /// the morning verdict wait for the offload grace); then waits for the first offload and every
    /// 15 min runs `analyzeRecent()` UNLESS a backfill or import is writing (it would compete with BLE
    /// on the main actor and could score fresh raw rows against a stale baseline). Cancelled in
    /// `stopAnalysisLoop()` when the app backgrounds (FER-177).
    func startAnalysisLoop() {
        guard analysisTask == nil else { return }
        #if DEBUG
        // Screenshot fixtures seed a synthetic dashboard; the production loop would overwrite it.
        if ScreenshotFixtures.activeState() != nil { return }
        #endif
        analysisTask = Task { [weak self] in
            guard let self else { return }
            // Two-pass launch: the ~90-day first-paint pass publishes the dashboard in
            // milliseconds so «Hoy» renders, then the full pass rebuilds it over the whole history
            // (its merge work runs off the main actor) and flips `repo.fullyLoaded`. Everything that
            // persists off `repo.days` (the engine, the day-key migration below) runs AFTER the full
            // pass — `migrateDayKeysToLocalIfNeeded` recomputes with `force: true`, so running it over
            // the short window would both skew scores and burn its one-shot flag.
            await self.repo.refreshFirstPaint()                // ① paint «Hoy» now (~90 days)
            await self.restoreInProgressStrengthSessionIfNeeded()  // FER-798: recover a session left by a crash
            await self.repo.refresh()                          // ② full history, off-main assembly
            await self.migrateDayKeysToLocalIfNeeded()         // FER-226: one-time UTC→local re-bucket (flag-gated)
            await self.compactDatabaseAfterSpo2PurgeIfNeeded() // FER-511: one-time VACUUM after the spo2 purge (flag-gated)
            await self.compactDatabaseAfterRebuildIfNeeded()   // FER-513: one-time VACUUM after the v21 rebuild (flag-gated)
            // FER-1022: under the Apple-only pin, `IntelligenceEngine.analyzeRecent` is a constant no-op
            // (its `usesWhoop` guard never opens). The launch sequence above is the real work and has run;
            // fresh Apple data refreshes the dashboard through `HealthKitBridge.sync`, not this loop. So
            // stop here rather than wake every 15 min to do nothing. (If the band pin is ever lifted this
            // guard falls through and the periodic recompute resumes unchanged.)
            guard self.sources.mode.usesWhoop else { return }
            // Si hoy aún no tiene veredicto (mañana post-medianoche: la fila no existe o su recovery es
            // nil), no hagas esperar el primer análisis los 6 s del offload: los crudos YA almacenados
            // pueden producirlo ahora. El sleep de abajo queda solo como cortesía al primer offload BLE.
            if self.repo.today?.recovery == nil,
               Self.mayRecomputeAfterBackfill(backfilling: false,
                                              hasActiveImport: self.hasActiveImport) {
                await self.intelligence.analyzeRecent()
            }
            try? await Task.sleep(nanoseconds: 6_000_000_000)  // give the first offload a moment
            while !Task.isCancelled {
                if Self.mayRecomputeAfterBackfill(backfilling: false,
                                                  hasActiveImport: self.hasActiveImport) {
                    await self.intelligence.analyzeRecent()
                }
                try? await Task.sleep(nanoseconds: 900_000_000_000)  // 15 min, matches the offload cadence
            }
        }
    }

    /// Cancel the periodic analysis loop (app backgrounded / teardown). Any in-flight `analyzeRecent`
    /// finishes its current pass, then the loop exits; the next `startAnalysisLoop()` begins fresh.
    func stopAnalysisLoop() {
        analysisTask?.cancel()
        analysisTask = nil
    }

    // MARK: - Baseline recalibration («Recalibrar recuperación», FER-677)

    /// Re-anchor every nightly baseline from today: persist the epoch, push it to the repo, and
    /// recompute so recovery/readiness re-score against the user's "new normal" (they drop to
    /// «calibrando» until enough post-epoch nights accrue — expected, and the confirmation warns of it).
    func recalibrateBaseline() {
        let today = AnalyticsEngine.dayString(Int(Date().timeIntervalSince1970),
                                              tzOffsetSeconds: TimeZone.current.secondsFromGMT())
        profile.recalibrate(to: today)
        applyBaselineEpochAndRecompute()
    }

    /// Undo the last recalibration (one level): restore the previous epoch and recompute.
    func undoRecalibrateBaseline() {
        profile.undoRecalibration()
        applyBaselineEpochAndRecompute()
    }

    private func applyBaselineEpochAndRecompute() {
        repo.baselineEpoch = profile.baselineEpochOrNil
        Task { @MainActor in
            await repo.refresh()
            await intelligence.analyzeRecent(force: true)
        }
    }

    /// Whether a completed-backfill recompute may run now. Mirrors the 15-min loop's guard (FER-177):
    /// the heavy on-device pass must not run while a backfill or import is actively writing, or it would
    /// contend with BLE/import on the main actor. Pure (no instance state) for testing.
    nonisolated static func mayRecomputeAfterBackfill(backfilling: Bool, hasActiveImport: Bool) -> Bool {
        !backfilling && !hasActiveImport
    }

    /// Cancel-and-reschedule debounce primitive: a Task that runs `action` after `delayNanos` unless it
    /// is cancelled first (by the next call replacing it). A burst of calls that each cancel the prior
    /// Task therefore collapses to a SINGLE `action` run — the last one scheduled. Nonisolated and
    /// instance-free so the coalescing is unit-testable without the live AppModel (FER-406).
    nonisolated static func debounced(after delayNanos: UInt64,
                                      action: @escaping @Sendable () async -> Void) -> Task<Void, Never> {
        Task {
            try? await Task.sleep(nanoseconds: delayNanos)
            guard !Task.isCancelled else { return }
            await action()
        }
    }
}
