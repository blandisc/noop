import SwiftUI
import Combine
import WhoopProtocol
import WhoopStore
import StrandImport
import StrandAnalytics
import StrandTraining

/// Data source currently running an import from the Data Sources screen.
enum DataSourceImportKind {
    case whoop
    case appleHealth
}

/// Root app state: owns the live BLE connection state and the CoreBluetooth engine.
/// More subsystems (Repository, AnalyticsEngine, ImportCoordinator) get wired in here
/// in later milestones.
@MainActor
final class AppModel: ObservableObject {
    /// The live instance, so an AppIntent (Shortcuts) can reach the bonded strap rather than spinning
    /// up a dead second AppModel (which would start a duplicate BLE engine and never buzz). Set in
    /// init(); `weak` so an intent fired while NOOP is closed sees nil and asks the user to open it. (#42)
    static weak var shared: AppModel?

    /// Shared device id for both live capture (BLEManager) and imported history.
    let deviceId = "my-whoop"
    /// Source id for imported Apple Health data (stored beside Whoop for per-source pages + consensus).
    let appleDeviceId = "apple-health"
    /// Observable snapshot driven by the BLE engine (connection, HR, battery, log).
    let live: LiveState
    /// CoreBluetooth engine — scans, connects, bonds, streams.
    let ble: BLEManager
    /// Read model over the on-device store (dashboard + detail screens).
    let repo: Repository
    /// User profile (age/sex/body/HR-max) for zones, calories, baselines.
    let profile = ProfileStore()
    /// Behaviour settings: double-tap action, wear automation, zone coaching, smart alarm, illness watch.
    let behavior = BehaviorStore()
    /// The Bucle's goal (metric + optional date) — a single user preference, UserDefaults-backed (FER-311).
    let goal = GoalStore()
    /// Which data sources feed the dashboard + baseline (combined / WHOOP-only / Apple-Health-only) —
    /// a user preference; capture stays active in every mode (FER-484).
    let sources = SourceModeStore()
    /// On-device WHOOP-style recovery/strain/sleep computation from raw strap streams.
    let intelligence: IntelligenceEngine

    /// Opt-in AI coach (bring-your-own-key) — the one networked feature, off until the user enables it.
    let coach: AICoachEngine

    /// The iOS Apple Health bridge, wired in by `CenitApp` right after init (it depends on `repo`).
    /// `weak` so SwiftUI owns its lifetime; AppModel only reaches it for the one-time day-key
    /// re-bucket (FER-226), and tolerates nil (Apple re-group is then deferred to the normal sync).
    weak var healthBridge: HealthKitBridge?

    /// Timestamps of moments marked via a double-tap (persisted).
    @Published var moments: [Date] = []

    /// An in-progress manually-tracked workout (requested by users who want to start a session
    /// themselves rather than rely on auto-detection). Holds the start time + the live HR collected
    /// since; on End the window is scored via `StrainScorer` and saved as a `WorkoutRow` (source
    /// "manual"), which then shows in the Workouts view. The day's strain already counts this HR (it's
    /// the same live stream the store persists), so this is a per-session annotation, not a double-count.
    @Published var activeWorkout: ActiveWorkout?
    /// The guided strength session in progress (FER-347), or nil. Lives here (global) so closing its sheet
    /// or switching tabs never loses it — the Train hub re-presents it. Saved as a `StrengthSession` + its
    /// `SetEntry` rows on Finish. Independent of the live HR workout above.
    @Published var strengthSession: StrengthSessionModel?
    /// Whether the guided-session sheet is currently shown. False while a session runs but the sheet is
    /// dismissed (the hub then offers «Resume»). Set true on start/resume, false on swipe-dismiss/finish.
    @Published var strengthSheetPresented = false
    /// The just-ended workout, for a brief inline confirmation in the Train hub (cleared on the next start).
    @Published var lastWorkout: WorkoutRow?
    /// True when the just-ended session was discarded because no HR ever arrived (<2 samples), so the
    /// Train hub can show an honest "not saved" notice instead of silently dropping it (FER-197).
    /// Cleared on the next start and on acknowledge.
    @Published var lastWorkoutDiscarded = false

    /// A manual workout in progress. `samples` accumulate from the smoothed live `bpm`; `liveStrain`
    /// is recomputed as the window grows so the active card can show strain building in real time.
    struct ActiveWorkout: Equatable {
        let start: Date
        var samples: [HRSample] = []
        var liveStrain: Double = 0
        var avgHr: Int = 0
        var peakHr: Int = 0
    }
    /// Illness/strain early-warning (recent RHR up + HRV down + skin-temp up vs baseline). nil = clear.
    @Published var healthAlert: String?
    private var lastDoubleTapAt: Date = .distantPast
    private var lastCoachZone: Int = -1
    // Stress-nudge state: rolling R-R buffer + a slow HRV baseline + a rate limiter.
    private var rrBuf: [Int] = []
    private var hrvBaseline: Double = 0
    private var lastStressBuzzAt: Date = .distantPast

    /// Import source currently writing to the local store, if any.
    @Published private var activeImportSource: DataSourceImportKind?
    /// Last WHOOP export import result surfaced in the WHOOP card.
    @Published var whoopImportSummary: String?
    /// Last Apple Health import result surfaced in the Apple Health card.
    @Published var appleHealthImportSummary: String?
    /// Typed failure flags per source — the summary's warning styling reads these instead of
    /// substring-matching the human-readable message (which misses errors like "Couldn't open
    /// the local store."). Surfaced on both the Data Sources cards and the onboarding import step.
    @Published var whoopImportFailed = false
    @Published var appleHealthImportFailed = false
    /// Live element count during an Apple Health import, so the card shows real
    /// progress instead of a frozen-looking spinner on a multi-minute parse.
    @Published var appleHealthImportProgress: Int?

    /// The in-flight import, retained so it can be cancelled. A fire-and-forget `Task` leaked:
    /// it kept parsing + writing after the user left the screen or started another import, and
    /// nothing could stop it. Now a new import (or `cancelImport()`) cancels the previous one, and
    /// the importers poll cancellation cooperatively so the work actually stops (FER-33).
    private var importTask: Task<Void, Never>?

    /// The periodic on-device analysis loop, retained so it can be cancelled. It used to be a
    /// fire-and-forget `Task` that lived for the whole process, re-reading ~21 days × 8 streams every
    /// 15 min and competing with BLE keep-alive / backfill / HR sinks on the main actor even while the
    /// app sat in the background. Now it's cancelled on background and resumed on foreground, and each
    /// tick skips the heavy pass while a backfill/import is writing (FER-177).
    private var analysisTask: Task<Void, Never>?

    /// Debounced on-device recompute fired by a *completed* backfill (FER-406). The morning catch-up
    /// lands last night's data in a burst (~6 drain completions in <60 s); each completion
    /// cancel-and-reschedules this Task so the heavy `analyzeRecent()` pass runs ONCE, after the burst
    /// settles — never per-completion. It fires on completion (not during offload) and re-checks the
    /// FER-177 guard before running, so it never contends with a live BLE write on the main actor.
    /// Cancelled alongside `analysisTask` on background/teardown.
    private var backfillRecomputeTask: Task<Void, Never>?

    /// Debounce window after a completed backfill before the recompute runs. ~3 s lets the drain
    /// chain's `backfilling` false→true→false flapping settle so the guard sees a quiet strap.
    private static let backfillRecomputeDebounceNanos: UInt64 = 3_000_000_000

    /// True while any data-source import is writing to the local store.
    var hasActiveImport: Bool { activeImportSource != nil }

    /// Cancel the in-flight import, if any. The importer stops at its next cooperative check and the
    /// matching card returns to its idle state.
    func cancelImport() { importTask?.cancel() }

    /// Returns true only for the source currently importing.
    func isImporting(_ source: DataSourceImportKind) -> Bool {
        activeImportSource == source
    }

    /// Whether the last import for a source ended in failure (for warning styling).
    func importFailed(_ source: DataSourceImportKind) -> Bool {
        switch source {
        case .whoop: return whoopImportFailed
        case .appleHealth: return appleHealthImportFailed
        }
    }

    /// Smoothed, display-ready live heart rate — median over a short window, spike-filtered.
    /// Every screen should show THIS, not the raw per-beat value (which swings with HRV).
    @Published var bpm: Int?
    private var hrWindow: [(t: Date, v: Double)] = []
    private var hrCancellables = Set<AnyCancellable>()

    init() {
        let live = LiveState()
        self.live = live
        self.ble = BLEManager(state: live, deviceId: "my-whoop")
        self.repo = Repository(deviceId: "my-whoop")
        self.repo.dataSourceMode = sources.mode      // FER-484: honor the persisted mode from launch
        self.coach = AICoachEngine(repo: repo)
        self.intelligence = IntelligenceEngine(repo: repo, profile: profile, deviceId: "my-whoop",
                                               family: WhoopModel.persisted.deviceFamily)
        // Smooth HR centrally so it's solid everywhere it's shown.
        live.$heartRate.sink { [weak self] _ in self?.ingestHR() }.store(in: &hrCancellables)
        live.$rr.sink { [weak self] _ in self?.ingestHR() }.store(in: &hrCancellables)

        // Physical-input + wear hooks (fired live by FrameRouter).
        live.onDoubleTap = { [weak self] in self?.handleDoubleTap() }
        live.onWristChange = { [weak self] worn in self?.handleWristChange(worn) }
        // HR-zone haptic coaching watches the smoothed bpm.
        $bpm.sink { [weak self] hr in self?.coachZone(hr) }.store(in: &hrCancellables)
        // Illness/strain early-warning recomputes when the daily history changes. `days` is no longer
        // its own @Published (folded into `dashboard` for single-publish refreshes, FER-30), so watch
        // the dashboard and project its days — still one emission per refresh.
        repo.$dashboard.map(\.days).sink { [weak self] days in self?.evaluateIllness(days) }.store(in: &hrCancellables)
        // Re-arm the strap's firmware alarm whenever it (re)bonds. A smart-alarm time changed while the
        // strap was away never reached it — the send is gated on bond — so the strap kept the OLD time
        // and fired at it (#59). removeDuplicates() fires once per bond; gated on enabled so a disabled
        // alarm doesn't disarm on every reconnect.
        live.$bonded.removeDuplicates().sink { [weak self] bonded in
            guard let self, bonded, self.behavior.smartAlarmEnabled else { return }
            self.applySmartAlarm()
        }.store(in: &hrCancellables)
        // A completed backfill has just written strap history. Refresh the dashboard cache,
        // but leave heavyweight analysis to its own guarded/background-friendly path.
        live.$lastSyncedAt
            .dropFirst()
            .compactMap { $0 }
            .removeDuplicates()
            .sink { [weak self] _ in
                Task { [weak self] in await self?.refreshAfterCompletedBackfill() }
            }
            .store(in: &hrCancellables)

        moments = (UserDefaults.standard.array(forKey: "moments") as? [Double] ?? [])
            .map { Date(timeIntervalSince1970: $0) }

        AppModel.shared = self   // publish for App Intents (Shortcuts) — see the static above (#42)

        #if DEBUG
        // Screenshot fixtures (UI test): seed a synthetic readiness state and skip the production
        // refresh/analyze loop entirely, so the seeded dashboard isn't immediately overwritten by a
        // real (empty) store load. Gated on the `-noop.fixture primed|strained` launch argument; an
        // absent/`empty` argument falls through to the normal launch path below.
        if let fixtureState = ScreenshotFixtures.activeState() {
            Task { [weak self] in
                guard let self else { return }
                await ScreenshotFixtures.seed(self, state: fixtureState)
            }
            return
        }
        #endif

        // Turn the strap's offloaded raw data into dashboard scores on launch and every 15
        // minutes, so recovery / strain / sleep populate from the strap itself with no import.
        // IntelligenceEngine computes, persists under "my-whoop-noop", and refreshes the dashboard.
        startAnalysisLoop()
    }

    /// Start (or resume) the periodic on-device analysis loop. Idempotent — a call while the loop is
    /// already running is a no-op, so the launch path and the scene-phase `.active` hook don't
    /// double-start it. The loop refreshes the dashboard once, waits for the first offload, then every
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
            await self.repo.refresh()                          // surface any imported data at once
            await self.migrateDayKeysToLocalIfNeeded()         // FER-226: one-time UTC→local re-bucket (flag-gated)
            try? await Task.sleep(nanoseconds: 6_000_000_000)  // give the first offload a moment
            while !Task.isCancelled {
                if Self.mayRecomputeAfterBackfill(backfilling: self.live.backfilling,
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
        backfillRecomputeTask?.cancel()
        backfillRecomputeTask = nil
    }

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
        guard let store = await repo.storeHandle() else { return }   // no store yet → retry next launch
        if ((try? await store.cursor(Self.dayKeyMigrationCursor)) ?? nil) == 1 { return }   // already done

        let window = 60   // bounded recompute window; older days keep their date (accepted seam)

        // 1. On-device computed scores: re-group from the still-stored raw streams onto the local day
        //    (force bypasses FER-177's idempotent skip), then drop the future-in-local orphan(s).
        let writtenComputed = await intelligence.analyzeRecent(maxDays: window, force: true)
        await Self.pruneFutureLocalDays(store: store, deviceId: deviceId + "-noop", written: writtenComputed)

        // 2. Apple Health: only when already connected (auth restored from the persisted "connected"
        //    flag on launch). New Apple rows are written local from now on, so a user who connects HK
        //    LATER has no UTC rows to migrate — the normal sync already lands them on the local day.
        if let health = healthBridge, health.auth == .authorized {
            let writtenApple = await health.sync(days: window)
            await Self.pruneFutureLocalDays(store: store, deviceId: appleDeviceId, written: writtenApple)
        }

        // Mark done so the heavy re-group doesn't re-run on every launch. The re-group is idempotent,
        // so marking even when Apple was skipped is harmless (a later HK connect lands local anyway).
        try? await store.setCursor(Self.dayKeyMigrationCursor, 1)
    }

    /// Prune rows for `deviceId` dated AFTER today's local civil day — the spurious "future-in-local"
    /// rows the old UTC dating materialized for the evening's data in a UTC− zone, now superseded by
    /// the local-day rows the re-group just wrote. Only future-dated rows are touched, so a past day
    /// that couldn't be recomputed keeps its row (no data loss). `written` are this run's freshly
    /// written local days, excluded defensively. Static: no instance state, just the store.
    private static func pruneFutureLocalDays(store: WhoopStore, deviceId: String,
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

    /// Switch the data-source mode (combined / WHOOP-only / Apple-Health-only), persist it, and re-read
    /// the dashboard + baseline through the new filter. Non-destructive: every source stays stored and
    /// capture keeps running; only what's READ changes, so switching back to `.combined` restores the
    /// prior view with no re-import (FER-484). The UI selector (F2) will call this.
    func setDataSourceMode(_ m: DataSourceMode) {
        guard m != sources.mode else { return }
        sources.mode = m
        repo.dataSourceMode = m
        Task { @MainActor in
            await repo.refresh()
            await intelligence.analyzeRecent(force: true)
        }
    }

    private func refreshAfterCompletedBackfill() async {
        live.append(log: "Backfill: refreshing dashboard cache from completed sync")
        await repo.refresh(days: 120)
        // The completed sync just landed last night's raw data — but reloading the cache only re-reads
        // it; the on-device scores still need recomputing. The 15-min loop is the only other recompute
        // path and it skips while a backfill is writing (FER-177), so during the morning catch-up the
        // verdict/sleep/strain could lag minutes behind the data. Schedule a debounced recompute here so
        // it runs reliably once the sync settles, coalescing the burst of completions into one pass.
        scheduleRecomputeAfterBackfill()
    }

    /// Cancel-and-reschedule the debounced recompute after a completed backfill (FER-406). Each
    /// completion in the morning burst replaces the prior pending Task, so `analyzeRecent()` runs ONCE
    /// after the burst settles rather than per-completion. The run re-checks the FER-177 guard so it
    /// never competes with a live BLE/import write on the main actor; `analyzeRecent()` itself refreshes
    /// the dashboard at the end of a non-empty pass, so the verdict appears with no manual refresh.
    private func scheduleRecomputeAfterBackfill(retriesLeft: Int = 3) {
        backfillRecomputeTask?.cancel()
        backfillRecomputeTask = Self.debounced(after: Self.backfillRecomputeDebounceNanos) { [weak self] in
            await self?.runRecomputeAfterBackfill(retriesLeft: retriesLeft)
        }
    }

    /// Run the on-device recompute, but only while the strap/import is quiet (the FER-177 guard) — the
    /// heavy pass must not contend with a live offload writing rows on the main actor. `analyzeRecent`
    /// has its own re-entrancy guard and idempotent-skip, so an overlap with the 15-min tick is safe.
    /// If a backfill re-started INSIDE the debounce window (the drain chain re-arms `backfilling` within
    /// the same morning catch-up), the guard is closed at fire time. Rather than strand the recompute
    /// until the next completion or the 15-min tick — the very "stays empty for minutes" symptom this
    /// fixes — reschedule a bounded few times; a fresh completion resets the budget, and once it's spent
    /// the periodic loop remains the backstop.
    private func runRecomputeAfterBackfill(retriesLeft: Int) async {
        guard Self.mayRecomputeAfterBackfill(backfilling: live.backfilling,
                                             hasActiveImport: hasActiveImport) else {
            if retriesLeft > 0 { scheduleRecomputeAfterBackfill(retriesLeft: retriesLeft - 1) }
            return
        }
        await intelligence.analyzeRecent()
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

    /// Fold a fresh reading into the smoothing window and republish a stable bpm.
    /// Prefers the strap's reported HR; falls back to 60000/R-R. Clamps to a plausible
    /// 30–220 range (rejects 0 / garbage spikes) and publishes the window MEDIAN.
    private func ingestHR() {
        var inst: Double?
        if let hr = live.heartRate, hr >= 30, hr <= 220 {
            inst = Double(hr)
        } else if let rr = live.rr.last, rr > 0 {
            let v = 60_000.0 / Double(rr)
            if v >= 30, v <= 220 { inst = v }
        }
        guard let inst else { return }
        let now = Date()
        hrWindow.append((now, inst))
        hrWindow.removeAll { now.timeIntervalSince($0.t) > 10 }   // ~10s window
        if hrWindow.count > 40 { hrWindow.removeFirst(hrWindow.count - 40) }
        let vals = hrWindow.map(\.v).sorted()
        bpm = vals.isEmpty ? nil : Int(vals[vals.count / 2].rounded())
        captureWorkoutSample()
        captureStrengthSample()
        evaluateStress()
    }

    // MARK: - Manual workout tracking

    /// Begin a manually-tracked workout. The active card on Live then shows elapsed time, live HR and
    /// strain building; End scores + saves it. Confirms with a single buzz.
    func startWorkout() {
        guard activeWorkout == nil else { return }
        lastWorkout = nil
        lastWorkoutDiscarded = false
        activeWorkout = ActiveWorkout(start: Date())
        buzz(loops: 1)
    }

    /// Finish the active workout: score the captured HR window and save it as a `WorkoutRow`. A session
    /// with too few samples (never streamed HR) is discarded quietly. Double-buzz confirms the save.
    func endWorkout() {
        guard let w = activeWorkout else { return }
        activeWorkout = nil
        let samples = w.samples
        guard samples.count >= 2 else { lastWorkout = nil; lastWorkoutDiscarded = true; return }
        let end = Date()
        let avg = Int((Double(samples.map(\.bpm).reduce(0, +)) / Double(samples.count)).rounded())
        let peak = samples.map(\.bpm).max() ?? 0
        let strain = StrainScorer.strain(samples, maxHR: Double(profile.hrMax), sex: profile.sex)
        let row = WorkoutRow(
            startTs: Int(w.start.timeIntervalSince1970), endTs: Int(end.timeIntervalSince1970),
            sport: "Workout", source: "manual", durationS: end.timeIntervalSince(w.start),
            energyKcal: nil, avgHr: avg, maxHr: peak, strain: strain,
            distanceM: nil, zonesJSON: nil, notes: nil)
        lastWorkout = row
        lastWorkoutDiscarded = false
        buzz(loops: 2)
        Task { [weak self] in
            guard let self else { return }
            if let store = await self.repo.storeHandle() {
                _ = try? await store.upsertWorkouts([row], deviceId: self.deviceId)
                await self.repo.refresh()
            }
        }
    }

    // MARK: - Guided strength session (FER-347)

    /// Begin a guided strength session from a routine's resolved plan (built by «Rutina de hoy»), and show
    /// its sheet. A no-op while one is already running, so re-tapping «Empezar» resumes rather than restarts.
    func startStrengthSession(routineId: String?, routineName: String,
                              slots: [StrengthSessionModel.PlanSlot]) {
        guard strengthSession == nil else { strengthSheetPresented = true; return }
        strengthSession = StrengthSessionModel.make(routineId: routineId, routineName: routineName,
                                                    slots: slots, startTs: Int(Date().timeIntervalSince1970))
        strengthSheetPresented = true
        // Arm the realtime HR stream for the duration of the session (FER-498) — without this, on a
        // WHOOP 4.0 the session sees no HR unless Live was opened first, and the receipt reads "no HR".
        acquireRealtimeHR("strength")
        buzz(loops: 1)   // confirm the session started, same single buzz as the manual live workout (FER-498)
    }

    /// Re-show the sheet for the in-progress session (the hub's «Resume»).
    func resumeStrengthSession() { if strengthSession != nil { strengthSheetPresented = true } }

    /// Finish the guided session. With ≥1 logged set: persist it, mirror to Apple Health (opt-in), and
    /// compute the post-session receipt (FER-409) — keeping the session ALIVE so the sheet renders its
    /// `summaryPhase`. With nothing logged: discard and close. The receipt is ended by `closeStrengthSummary`
    /// («Listo» or a swipe of the summary).
    func endStrengthSession(save: Bool) {
        guard let session = strengthSession else { strengthSheetPresented = false; return }
        let endTs = Int(Date().timeIntervalSince1970)
        guard save, session.doneCount > 0 else {        // nothing logged → discard + close
            strengthSession = nil
            strengthSheetPresented = false
            releaseRealtimeHR("strength")
            return
        }
        let built = session.buildForSave(deviceId: deviceId, endTs: endTs)
        let sets = built.1
        var record = built.0
        // FER-399: if the strap streamed HR during the session, derive avgHr + strain (same model as the
        // live workout) and persist them — this lights up the summary's Effort hero + recovery-cost block.
        let hrSamples = session.hrSamples
        if hrSamples.count >= 2 {
            let hrSum: Double = hrSamples.reduce(0.0) { $0 + Double($1.bpm) }
            let hrMean: Double = hrSum / Double(hrSamples.count)
            record.avgHr = Int(hrMean.rounded())
            record.strain = StrainScorer.strain(hrSamples, maxHR: Double(profile.hrMax), sex: profile.sex)
        }
        let hrMax = profile.hrMax
        // Snapshot the profile on the main actor for the calorie estimate before hopping off it.
        let userProfile = UserProfile(weightKg: profile.weightKg, heightCm: profile.heightCm,
                                      age: Double(profile.age), sex: profile.sex)
        Task { [weak self] in
            guard let self, let store = await self.repo.storeHandle() else { return }
            // Prior PRs (BEFORE save) so the receipt can tell which records are NEW this session.
            let prior = await self.priorStrengthPRs(store: store, ids: Set(sets.map(\.exerciseId)))
            try? await store.saveSession(record, sets: sets)
            // Surface the receipt on the live session — the sheet renders summaryPhase (session stays alive).
            session.summary = await self.buildStrengthSummary(session: session, record: record,
                                                              sets: sets, prior: prior, store: store)
            // Opt-in mirror to Apple Health (FER-390): a no-op unless the user enabled it. Runs AFTER
            // the local save (the source of truth) and never throws — Health is strictly best-effort.
            await self.healthBridge?.saveStrengthWorkoutIfEnabled(
                sessionId: record.id,
                start: Date(timeIntervalSince1970: TimeInterval(record.startTs)),
                end: Date(timeIntervalSince1970: TimeInterval(endTs)),
                profile: userProfile, hrSamples: hrSamples, hrMax: hrMax)
        }
    }

    /// End the session once the user has seen the receipt (FER-409): «Listo» or a swipe of the summary.
    func closeStrengthSummary() {
        strengthSession = nil
        strengthSheetPresented = false
        releaseRealtimeHR("strength")   // last consumer leaves → stream stops (unless Live still holds it)
    }

    /// Prior best-per-metric PRs per exercise, BEFORE this session's save — the baseline new records beat.
    private func priorStrengthPRs(store: WhoopStore, ids: Set<String>) async -> [String: [PRMetric: PersonalRecord]] {
        var out: [String: [PRMetric: PersonalRecord]] = [:]
        for id in ids {
            let prs = (try? await store.personalRecords(exerciseId: id)) ?? []
            out[id] = Dictionary(prs.map { ($0.metric, $0) }, uniquingKeysWith: { a, _ in a })
        }
        return out
    }

    /// Build the post-session receipt (FER-409): volume/duration, the records that STRICTLY beat a prior PR
    /// (a first-ever entry is not a record), worked muscles, and the recovery-cost band — `nil` until the
    /// session carries strain (FER-399), so the view omits the cost block rather than inventing a zero.
    private func buildStrengthSummary(session: StrengthSessionModel, record: StrengthSession,
                                      sets: [SetEntry], prior: [String: [PRMetric: PersonalRecord]],
                                      store: WhoopStore) async -> StrengthSummary {
        let work = sets.filter { $0.kind == .work && $0.done }
        let volumeKg = work.reduce(0.0) { $0 + (($1.weightKg ?? 0) * Double($1.reps ?? 0)) }
        let durationS = max(0, (record.endTs ?? record.startTs) - record.startTs)

        // Resolve exercises (bundled catalog + user-created) for names + muscles.
        let custom = (try? await store.customExercises()) ?? []
        let customByID = Dictionary(custom.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        func exercise(_ id: String) -> Exercise? { ExerciseCatalog.byID(id) ?? customByID[id] }

        // NEW records: this session's per-exercise bests that strictly beat the prior PR.
        var prs: [StrengthSummary.PR] = []
        for (id, exSets) in Dictionary(grouping: work, by: \.exerciseId) {
            let name = exercise(id)?.name ?? String(localized: "Exercise")
            let p = prior[id] ?? [:]
            if let w = exSets.compactMap(\.weightKg).max(), let was = p[.maxWeight], w > (was.valueKg ?? 0) {
                prs.append(.init(exercise: name, metric: .maxWeight, valueKg: w, reps: nil))
            }
            if let r = exSets.compactMap(\.reps).max(), let was = p[.maxReps], r > (was.reps ?? 0) {
                prs.append(.init(exercise: name, metric: .maxReps, valueKg: nil, reps: r))
            }
            if let best = exSets.compactMap({ s -> (vol: Double, w: Double, r: Int)? in
                guard let w = s.weightKg, let r = s.reps else { return nil }
                return (w * Double(r), w, r)
            }).max(by: { $0.vol < $1.vol }),
               let was = p[.maxVolume], best.vol > (was.valueKg ?? 0) * Double(was.reps ?? 0) {
                prs.append(.init(exercise: name, metric: .maxVolume, valueKg: best.w, reps: best.r))
            }
        }
        prs.sort { $0.exercise < $1.exercise }

        // Worked muscles, in set order, deduped, title-cased, capped.
        var seen = Set<String>(); var muscles: [String] = []
        for s in work {
            for m in exercise(s.exerciseId)?.primaryMuscles ?? [] where !seen.contains(m) {
                seen.insert(m); muscles.append(StrengthDisplay.titleCase(m))
            }
        }

        // Tomorrow's projection given today's session cost (FER-442): recovery base = repo.days
        // (already oldest→newest from Repository; nils kept so the engine respects missing-day
        // spacing). "Si descansas bien" → no sleep-debt drag; the only downward pull is the acute
        // session strain. nil (→ the line is hidden) when there's no strain or fewer than ~2 weeks
        // of base — we never invent a number.
        let recoverySeries = repo.days.map(\.recovery)
        let costTomorrowPct: Int? = record.strain.flatMap { strain in
            RecoveryForecast.compute(recovery: recoverySeries, sessionStrain: strain)
                .map { Int($0.estimate.rounded()) }
        }

        return StrengthSummary(routineName: session.routineName, durationS: durationS,
                               volumeKg: volumeKg, setCount: work.count, strain: record.strain,
                               costBand: SessionRecoveryCost.cost(sessionStrain: record.strain)?.band,
                               costTomorrowPct: costTomorrowPct,
                               prs: prs, muscles: Array(muscles.prefix(6)), isFirstTime: prior.allSatisfy { $0.value.isEmpty })
    }

    /// Dismiss the just-ended confirmation / discard notice shown in the Train hub once the user has
    /// seen it (FER-197) — the hub auto-acknowledges after a few seconds so the row returns to idle.
    func acknowledgeLastWorkout() {
        lastWorkout = nil
        lastWorkoutDiscarded = false
    }

    /// Append the current smoothed `bpm` to the active strength session's HR buffer (FER-399), so finishing
    /// can derive avgHr/strain + a Keytel calorie estimate. In-memory only; a no-op when no strength session
    /// is running, the receipt is already shown, or there's no fresh HR. Same main-actor cadence as
    /// `captureWorkoutSample` — never touches the BLE drain.
    private func captureStrengthSample() {
        guard let s = strengthSession, s.summary == nil, let hr = bpm else { return }
        s.hrSamples.append(HRSample(ts: Int(Date().timeIntervalSince1970), bpm: hr))
    }

    /// Append the current smoothed `bpm` to the active workout and recompute its running strain. Called
    /// from `ingestHR` on every fresh sample; a no-op when no workout is running. Recomputing strain
    /// over the growing window each sample is cheap at the ~1 Hz live-HR cadence.
    private func captureWorkoutSample() {
        guard var w = activeWorkout, let hr = bpm else { return }
        w.samples.append(HRSample(ts: Int(Date().timeIntervalSince1970), bpm: hr))
        w.peakHr = max(w.peakHr, hr)
        w.avgHr = Int((Double(w.samples.map(\.bpm).reduce(0, +)) / Double(w.samples.count)).rounded())
        w.liveStrain = StrainScorer.strain(w.samples, maxHR: Double(profile.hrMax), sex: profile.sex) ?? 0
        activeWorkout = w
    }

    /// Drop the smoothing window and blank the hero number so a resume / re-attach shows "—"
    /// until a genuinely fresh sample arrives, instead of republishing the stale pre-gap median.
    /// Called when the first realtime consumer arms the stream (see `acquireRealtimeHR`), NOT on the
    /// 30s keep-alive re-arm — so steady-state smoothing is untouched. Fixes #46 (HR jumped to a stale ~100 on
    /// reopen, then "slowly came back down" as fresh low samples refilled the window).
    func resetSmoothing() {
        hrWindow.removeAll()
        bpm = nil
    }

    /// Experimental resting stress nudge: track RMSSD vs a slow baseline; when HRV drops well below
    /// baseline while HR is calm (not exercising), buzz once — rate-limited to once / 15 min. Off by
    /// default; conservative so it rarely false-fires.
    private func evaluateStress() {
        guard behavior.stressNudge, live.bonded, live.worn else { return }
        let fresh = live.rr.filter { $0 > 300 && $0 < 2000 }   // plausible R-R (30–200 bpm)
        guard !fresh.isEmpty else { return }
        rrBuf.append(contentsOf: fresh)
        if rrBuf.count > 60 { rrBuf.removeFirst(rrBuf.count - 60) }
        guard rrBuf.count >= 20 else { return }
        let rmssd = AppModel.rmssd(rrBuf)
        guard rmssd > 0 else { return }
        hrvBaseline = hrvBaseline == 0 ? rmssd : hrvBaseline * 0.98 + rmssd * 0.02   // slow EMA
        guard let hr = bpm, hr >= 55, hr <= 100 else { return }   // resting band — not a workout
        let now = Date()
        if rmssd < hrvBaseline * 0.6, now.timeIntervalSince(lastStressBuzzAt) > 900 {
            lastStressBuzzAt = now
            buzz(loops: 1)
            live.append(log: "Stress nudge — take a paced breath")
        }
    }

    static func rmssd(_ rr: [Int]) -> Double {
        guard rr.count >= 2 else { return 0 }
        var sum = 0.0, n = 0
        for i in 1..<rr.count { let d = Double(rr[i] - rr[i - 1]); sum += d * d; n += 1 }
        return n > 0 ? (sum / Double(n)).squareRoot() : 0
    }

    /// Start scanning for the strap. When no model is given, use the one the user
    /// picked (persisted under "selectedWhoopModel"), so every scan entry point —
    /// Live, onboarding, the menu bar, Settings — honours the same choice.
    func scan(model: WhoopModel? = nil) {
        let chosen = model
            ?? UserDefaults.standard.string(forKey: "selectedWhoopModel").flatMap(WhoopModel.init(rawValue:))
            ?? .whoop4
        ble.connect(model: chosen)
    }
    func disconnect() { ble.disconnect() }

    /// Drop the current strap and clear bond state so a newly-picked strap model connects fresh
    /// (lets a user with both a WHOOP 4 and a 5/MG switch between them).
    func prepareStrapSwitch() { ble.prepareForModelSwitch() }

    /// Live-HR consumers that want the heavy R10/R11 realtime stream (the Live tab, a guided strength
    /// session). The stream is armed while ANY consumer wants it and stopped only when the LAST one
    /// leaves — so leaving Live mid-session doesn't kill the session's HR, and ending a session doesn't
    /// kill Live's (FER-498). The keep-alive re-arm goes through `ble.startRealtime()` directly (NOT
    /// here), so steady-state — and the marginal-radio fallback (#80) it honors — is untouched.
    private var realtimeConsumers: Set<String> = []

    /// A consumer (`"live"`, `"strength"`) wants live HR. ALWAYS (re)arms the realtime stream and blanks
    /// the stale smoothing window (#46) — not just on the first consumer (FER-498). This matters because
    /// the consumer set can desync from the actual stream: SwiftUI's `onDisappear` for Live isn't reliable
    /// (tabs/sheets), so `"live"` can linger; meanwhile the stream may already be OFF (a disconnect, an
    /// offload that stopped the R10/R11 flood, or a marginal-radio fallback). If we armed only `wasIdle`,
    /// a strength session opened in that state would never re-arm — leaving a FROZEN `bpm` and zero capture
    /// (the receipt then reads "no heart rate"). Re-arming every time is safe and idempotent — it's exactly
    /// what Live already did on each `onAppear`/connection change. The ref-count governs only the STOP.
    func acquireRealtimeHR(_ consumer: String) {
        realtimeConsumers.insert(consumer)
        resetSmoothing()
        ble.startRealtime()
    }

    /// A consumer is done with live HR. Stops the realtime stream once the LAST consumer leaves (the
    /// lightweight 0x2A37 HR keeps recording regardless). Idempotent per consumer.
    func releaseRealtimeHR(_ consumer: String) {
        guard realtimeConsumers.remove(consumer) != nil, realtimeConsumers.isEmpty else { return }
        ble.stopRealtime()
    }
    /// Ask the strap for a fresh battery reading.
    func getBattery() { ble.refreshBattery() }

    /// Fire a haptic buzz on the strap. patternId=2 is the graduated buzz confirmed on-device;
    /// `loops` sets the length. Used by the in-app test button and (later) notification alerts.
    /// Requires a bonded connection — no-op otherwise (the command characteristic is gated on bond).
    func buzz(loops: UInt8 = 2) {
        ble.send(.runHapticsPattern, payload: [2, loops, 0, 0, 0])
    }

    /// Fire a specific preset haptic pattern (patternId 0–6 on Harvard; loops sets length).
    /// Used by the notification-pattern picker and coaching features.
    func buzz(pattern: UInt8, loops: UInt8 = 1) {
        ble.send(.runHapticsPattern, payload: [pattern, loops, 0, 0, 0])
    }

    /// Arm (or clear) the strap's firmware alarm from the smart-alarm settings. The firmware alarm
    /// fires even if the Mac is asleep / NOOP is closed. No-op until bonded (send is gated on bond).
    func applySmartAlarm() {
        guard behavior.smartAlarmEnabled else { ble.disableStrapAlarm(); return }
        let cal = Calendar.current
        let now = Date()
        var next = cal.date(bySettingHour: behavior.smartAlarmMinutes / 60,
                            minute: behavior.smartAlarmMinutes % 60, second: 0, of: now) ?? now
        if next <= now { next = cal.date(byAdding: .day, value: 1, to: next) ?? next }
        ble.armStrapAlarm(at: next)
    }

    // MARK: - Physical inputs / wear automation

    private func handleDoubleTap() {
        let now = Date()
        guard now.timeIntervalSince(lastDoubleTapAt) > 1.2 else { return }   // debounce repeats
        lastDoubleTapAt = now
        live.append(log: "Double-tap → \(behavior.doubleTapAction.label)")
        runStrapAction(behavior.doubleTapAction, shortcut: behavior.doubleTapShortcut)
    }

    /// Run a configured strap action. In-app actions (buzz/moment) stay on-device; shortcuts go
    /// through StrapActions.
    func runStrapAction(_ kind: StrapActionKind, shortcut: String) {
        switch kind {
        case .none: break
        case .buzzBack: buzz(loops: 1)
        case .markMoment: markMoment()
        case .runShortcut: StrapActions.runShortcut(shortcut)
        }
    }

    /// Record a "moment" (double-tap marker) with a confirming buzz.
    func markMoment() {
        moments.append(Date())
        if moments.count > 500 { moments.removeFirst(moments.count - 500) }
        UserDefaults.standard.set(moments.map(\.timeIntervalSince1970), forKey: "moments")
        buzz(loops: 1)
        live.append(log: "Moment marked")
    }

    private func handleWristChange(_ worn: Bool) {
        if worn {
            if !behavior.wristOnShortcut.isEmpty { StrapActions.runShortcut(behavior.wristOnShortcut) }
        } else {
            if !behavior.wristOffShortcut.isEmpty { StrapActions.runShortcut(behavior.wristOffShortcut) }
        }
    }

    /// HR-zone haptic coaching: buzz when crossing into the top zone (ease off) or back to recovery.
    private func coachZone(_ hr: Int?) {
        guard behavior.zoneCoaching, live.bonded, live.worn, let hr, hr >= 30 else { return }
        let maxHR = Double(profile.hrMax)
        guard maxHR > 0 else { return }
        let pct = Double(hr) / maxHR
        let zone = pct >= 0.9 ? 5 : pct >= 0.8 ? 4 : pct >= 0.7 ? 3 : pct >= 0.6 ? 2 : 1
        defer { lastCoachZone = zone }
        guard lastCoachZone != -1, zone != lastCoachZone else { return }
        if zone == 5, lastCoachZone < 5 { buzz(loops: 3) }          // entered max — ease off
        else if zone <= 1, lastCoachZone > 1 { buzz(loops: 1) }     // recovered
    }

    /// Illness/strain early-warning: compare the last ~2 days against a ~28-day baseline (ending 3
    /// days ago) for resting HR, HRV, skin-temp deviation and respiration. Two or more anomalies →
    /// a banner. The classic early-illness signature (RHR↑ + HRV↓ + skin-temp↑). On-device only.
    private func evaluateIllness(_ days: [DailyMetric]) {
        let previous = healthAlert
        guard behavior.illnessWatch, days.count >= 14 else { healthAlert = nil; return }
        // `recent` is a small sample — by design 2 nights, but a single night if one is missing.
        let recent = Array(days.suffix(2))
        let base = Array(days.suffix(31).dropLast(3))    // ~28 days ending 3 days ago
        func mean(_ vals: [Double]) -> Double? { vals.isEmpty ? nil : vals.reduce(0, +) / Double(vals.count) }
        func rm(_ kp: (DailyMetric) -> Double?) -> Double? { mean(recent.compactMap(kp)) }

        // Each anomaly fires by z-score ≥2σ against the baseline's OWN dispersion (robust σ via
        // IllnessWatch), not a fixed offset — so the same absolute Δ trips a stable user but not a
        // volatile one. The flag string still reports the human-readable Δ.
        var flags: [String] = []
        func anomaly(_ kp: (DailyMetric) -> Double?, higherIsWorse: Bool) -> (r: Double, b: Double)? {
            guard let r = rm(kp),
                  let dev = IllnessWatch.deviation(recentMean: r, base: base.compactMap(kp), higherIsWorse: higherIsWorse),
                  dev.z >= IllnessWatch.zThreshold else { return nil }
            return (r, dev.baseMean)
        }
        if let a = anomaly({ $0.restingHr.map(Double.init) }, higherIsWorse: true) {
            flags.append(String(localized: "resting HR +\(Int((a.r - a.b).rounded())) bpm"))
        }
        if let a = anomaly({ $0.avgHrv }, higherIsWorse: false), a.b > 0 {
            flags.append(String(localized: "HRV −\(Int(((1 - a.r / a.b) * 100).rounded()))%"))
        }
        if let a = anomaly({ $0.skinTempDevC }, higherIsWorse: true) {
            flags.append(String(localized: "skin temp +\(String(format: "%.1f", a.r))°C"))
        }
        if anomaly({ $0.respRateBpm }, higherIsWorse: true) != nil {
            flags.append(String(localized: "respiration up"))
        }
        healthAlert = flags.count >= 2
            ? String(localized: "Your body looks strained — \(flags.joined(separator: ", ")). Consider taking it easy.")
            : nil
        // Banner transition (clear → raised): surface it as a system notification so the
        // early-warning reaches the user when the window is closed (menu bar keeps us alive).
        // IllnessNotifier rate-limits to once per local day.
        if let alert = healthAlert, previous == nil {
            IllnessNotifier.post(alert)
        }
    }

    /// Re-run the illness watch over the cached history. Called when the Automations toggle
    /// flips — the repo.$days sink only fires on data changes, so a flip would otherwise wait
    /// for the next refresh.
    func reevaluateIllness() {
        evaluateIllness(repo.days)
    }

    /// Import a Whoop CSV export (.zip or folder) → on-device store, then refresh the dashboard.
    func importWhoop(url: URL) {
        beginImport(.whoop)
        importTask?.cancel()
        // Not nil'd on completion: a finished `Task<Void, Never>` is harmless to retain, and nil'ing
        // it in a `defer` would race a newer import that already replaced the handle. `cancelImport()`
        // cancelling an already-finished task is a no-op. `hasActiveImport` keys off `activeImportSource`.
        importTask = Task { [weak self] in
            guard let self else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                guard let store = await repo.storeHandle() else {
                    finishImport(.whoop, summary: "Couldn't open the local store.", failed: true)
                    return
                }
                let summary = try await WhoopImporter.importExport(url: url, into: store, deviceId: deviceId)
                await repo.refresh()
                let span: String
                if let a = summary.earliest, let b = summary.latest {
                    let f = DateFormatter(); f.dateFormat = "MMM yyyy"
                    span = " · \(f.string(from: a))–\(f.string(from: b))"
                } else { span = "" }
                finishImport(.whoop, summary: "Imported \(summary.recordCount) records\(span)")
            } catch is CancellationError {
                finishImport(.whoop, summary: "Import cancelled.")
            } catch {
                finishImport(.whoop, summary: "Import failed: \(error)", failed: true)
            }
        }
    }

    /// Import an Apple Health export (export.zip) — streams + aggregates per-day into the store
    /// under the `apple-health` source, then refreshes. Large exports take ~1–2 minutes.
    func importAppleHealth(url: URL) {
        beginImport(.appleHealth)
        importTask?.cancel()
        importTask = Task { [weak self] in
            guard let self else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                guard let store = await repo.storeHandle() else {
                    finishImport(.appleHealth, summary: "Couldn't open the local store.", failed: true)
                    return
                }
                // The parser fires `progress` off the main thread; hop back to
                // update the @Published count the card observes.
                let progress: AppleHealthImporter.ProgressHandler = { count in
                    Task { @MainActor [weak self] in self?.appleHealthImportProgress = count }
                }
                let summary = try await AppleHealthImport.importExport(
                    url: url, into: store, deviceId: appleDeviceId, progress: progress,
                    isCancelled: { Task.isCancelled })
                await repo.refresh()
                finishImport(.appleHealth, summary: "Imported \(summary.recordCount) records")
            } catch is CancellationError {
                finishImport(.appleHealth, summary: "Import cancelled.")
            } catch {
                finishImport(.appleHealth, summary: "Import failed: \(error)", failed: true)
            }
        }
    }

    /// Marks a source as importing and clears only that source's old status text + failure flag.
    private func beginImport(_ source: DataSourceImportKind) {
        activeImportSource = source
        switch source {
        case .whoop:
            whoopImportSummary = nil
            whoopImportFailed = false
        case .appleHealth:
            appleHealthImportSummary = nil
            appleHealthImportFailed = false
            appleHealthImportProgress = nil
        }
    }

    /// Stores the completed import summary (and typed failure flag) on the matching source card.
    private func finishImport(_ source: DataSourceImportKind, summary: String, failed: Bool = false) {
        switch source {
        case .whoop:
            whoopImportSummary = summary
            whoopImportFailed = failed
        case .appleHealth:
            appleHealthImportSummary = summary
            appleHealthImportFailed = failed
            appleHealthImportProgress = nil
        }
        activeImportSource = nil
    }
}
