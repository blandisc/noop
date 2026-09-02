import SwiftUI
import CenitDesign
import Combine
import Observation
import BiometricStreams
import CenitStore
import StrandImport
import StrandAnalytics
import StrandTraining

extension AppModel {

    /// Run the on-device analysis sequence, retained so `stopAnalysis()` can cancel it. Idempotent —
    /// a call while it is already running is a no-op, so the launch path doesn't double-start it.
    ///
    /// Runs the **launch refresh sequence** (first-paint → restore session → full refresh →
    /// one-shot migrations). Under the Apple-only pin (FER-1003/1022) there is no periodic band
    /// recompute — the sequence is purely the launch refresh. Cancelled in `stopAnalysis()` when
    /// the app backgrounds (FER-177).
    ///
    /// NOTE: this is a LAUNCH-time entry point. It is NOT re-invoked on every foreground return — that
    /// would re-run the whole launch refresh each activation, concurrently with `HealthKitBridge.sync`,
    /// assembling the dashboard twice. Foreground uses `resumeForegroundAnalysis()` instead (FER-1024).
    func startAnalysis() {
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
            // persists off `repo.days` (the day-key migration below) runs AFTER the full
            // pass — `migrateDayKeysToLocalIfNeeded` recomputes with `force: true`, so running it over
            // the short window would both skew scores and burn its one-shot flag.
            await self.repo.refreshFirstPaint()                // ① paint «Hoy» now (~90 days)
            await self.restoreInProgressStrengthSessionIfNeeded()  // FER-798: recover a session left by a crash
            await self.repo.refresh()                          // ② full history, off-main assembly
            await self.migrateDayKeysToLocalIfNeeded()         // FER-226: one-time UTC→local re-bucket (flag-gated)
            await self.compactDatabaseAfterSpo2PurgeIfNeeded() // FER-511: one-time VACUUM after the spo2 purge (flag-gated)
            await self.compactDatabaseAfterRebuildIfNeeded()   // FER-513: one-time VACUUM after the v21 rebuild (flag-gated)
        }
    }

    /// Cancel the analysis sequence (app backgrounded / teardown). Any in-flight `analyzeRecent`
    /// finishes its current pass, then it exits; the next `startAnalysis()` begins fresh.
    func stopAnalysis() {
        analysisTask?.cancel()
        analysisTask = nil
    }

    /// Foreground policy for the scene-phase `.active` handler. Replaces the old unconditional
    /// `startAnalysisLoop()` re-run, which re-executed the ENTIRE launch refresh (first-paint + full
    /// refresh) on every return to foreground — concurrently with `HealthKitBridge.sync`'s own
    /// refresh, so the dashboard was assembled twice per activation (wasted work/battery; correct only
    /// by luck of the `refreshGen` guard). Now at most ONE refresh per foreground, never two
    /// concurrent (FER-1024):
    ///  • Apple-only: the launch sequence already ran once at launch. Re-assemble ONLY if the day
    ///    rolled over since the last published dashboard, so «Hoy» re-buckets to the new local day
    ///    even when Apple has no new data (FER-224/226/630). Awaited by the caller BEFORE
    ///    `HealthKitBridge.sync`, so the forced refresh and the sync's guarded refresh never overlap.
    ///    A same-day foreground forces nothing — `HealthKitBridge.sync`'s FER-872/881 guard covers any
    ///    genuinely new Apple data.
    @MainActor
    func resumeForegroundAnalysis() async {
        // Un pase COMPLETO que nunca terminó también obliga a refrescar. El primer pintado ya fija
        // `lastRefreshDayKey = hoy`, así que si el usuario manda la app a segundo plano antes de que
        // el pase completo acabe y vuelve el MISMO día, la compuerta de medianoche no dispara y el
        // dashboard se queda a medias. Con el veredicto publicándose SOLO en el pase completo, eso
        // dejaría al héroe pegado en «Leyendo tu noche…» toda la jornada.
        if Self.shouldForceRefreshOnForeground(lastPublishedDay: repo.lastRefreshDayKey,
                                               currentDay: Repository.localDayKey(Date()),
                                               fullyLoaded: repo.fullyLoaded) {
            await repo.refresh()
        }
    }

    /// Whether returning to the foreground must force a full dashboard rebuild. Two triggers:
    /// (a) the day rolled over since the dashboard was last assembled (FER-1024 — the midnight case);
    /// (b) **the full pass never finished** (`fullyLoaded == false`). (b) exists because first paint
    /// already stamps `lastRefreshDayKey = today`, so a user who backgrounds the app mid-load and
    /// returns the SAME day would otherwise never complete it — and since the «Preparación» verdict
    /// is published only by the full pass, the hero would sit on «Leyendo tu noche…» all day.
    /// Pure (no instance state) so a unit test can pin the matrix without a live AppModel.
    /// `nil` (nothing published yet) never forces: the launch sequence owns that path.
    nonisolated static func shouldForceRefreshOnForeground(lastPublishedDay: String?,
                                                           currentDay: String,
                                                           fullyLoaded: Bool = true) -> Bool {
        guard let lastPublishedDay else { return false }
        return !fullyLoaded || lastPublishedDay != currentDay
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
