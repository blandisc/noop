import SwiftUI
import Combine
import Observation
import UserNotifications
import WhoopProtocol
import BiometricStreams
import CenitStore
import StrandImport
import StrandAnalytics
import StrandTraining
import StrandDesign

/// Data source currently running an import from the Data Sources screen.
enum DataSourceImportKind {
    case appleHealth
}

/// Root app state: owns the live BLE connection state and the CoreBluetooth engine.
/// More subsystems (Repository, AnalyticsEngine, ImportCoordinator) get wired in here
/// in later milestones.
@MainActor
// FER-984: `@Observable` (no `ObservableObject`) → SwiftUI rastrea lecturas por-propiedad, así que un
// cambio a UNA propiedad (p.ej. `liveDayStrain` por `hrFlushSeq`) solo re-evalúa las vistas que LEEN esa
// propiedad, no las 16 pantallas que observan el modelo. Mismo patrón que `LiveState` (FER-874). Sin `$`
// publishers: los pocos bindings (`$…strengthSheetPresented`) van por `@Bindable` en el consumidor.
@Observable final class AppModel {
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
    /// Owns the rest Live Activity (FER-721): started/updated/ended from the guided session's rest state,
    /// and the bridge for its «+30 s»/«Saltar» lock-screen actions.
    let restActivity = RestActivityController()
    /// CoreBluetooth engine — scans, connects, bonds, streams.
    let ble: BLEManager
    /// Read model over the on-device store (dashboard + detail screens).
    let repo: Repository
    /// User profile (age/sex/body/HR-max) for zones, calories, baselines.
    let profile = ProfileStore()
    /// Behaviour settings: double-tap action, wear automation, zone coaching, smart alarm, illness watch.
    let behavior = BehaviorStore()
    /// Inactivity reminder settings + its restart-safe de-dup state (FER-664).
    let inactivity = InactivityPrefs()
    /// The Bucle's goal (metric + optional date) — a single user preference, UserDefaults-backed (FER-311).
    let goal = GoalStore()
    /// The user's barbell + owned plate denominations, for the session's «⛓ discos» calculator (FER-720).
    let plates = PlatesStore()
    /// Which data sources feed the dashboard + baseline (combined / WHOOP-only / Apple-Health-only) —
    /// a user preference; capture stays active in every mode (FER-484).
    let sources = SourceModeStore()
    /// On-device WHOOP-style recovery/strain/sleep computation from raw strap streams.
    let intelligence: IntelligenceEngine

    /// The iOS Apple Health bridge, wired in by `CenitApp` right after init (it depends on `repo`).
    /// `weak` so SwiftUI owns its lifetime; AppModel only reaches it for the one-time day-key
    /// re-bucket (FER-226), and tolerates nil (Apple re-group is then deferred to the normal sync).
    weak var healthBridge: HealthKitBridge?

    /// The Apple Watch workout-mirroring bridge (FER-740), wired in by `CenitApp` right after init.
    /// `weak` so SwiftUI owns its lifetime. When a strength session runs and a watch is available, it
    /// wakes the watch to record the real `HKWorkoutSession`; nil (no watch / disabled) is the normal
    /// path where the iPhone owns the estimated workout as before.
    weak var mirroringBridge: WorkoutMirroringBridge?

    /// FER-742: live watch state, mirrored off `WorkoutMirroringBridge` via `CenitApp`, so the views that
    /// already observe AppModel (the Settings row, and the strength sheet behind a fullScreenCover that
    /// strips EnvironmentObjects) can paint it. `.inactive` paints no line.
    var watchSessionStatus: WatchSessionStatus = .inactive
    var watchPaired = false
    var watchAppInstalled = false

    /// Session ids for which the watch already saved the real `HKWorkout`. The one-workout invariant
    /// gate (`WorkoutSaveGate`) reads this so the iPhone omits its own save. Ephemeral — the workout is
    /// already in HealthKit and idempotent by `externalUUID`, so it need not survive a relaunch.
    private var watchSavedSessionIds: Set<String> = []
    /// Session ids the watch declined to save (no permission / error) — the iPhone then saves. (FER-740)
    private var watchDeclinedSessionIds: Set<String> = []

    /// Timestamps of moments marked via a double-tap (persisted).
    var moments: [Date] = []

    /// An in-progress manually-tracked workout (requested by users who want to start a session
    /// themselves rather than rely on auto-detection). Holds the start time + the live HR collected
    /// since; on End the window is scored via `StrainScorer` and saved as a `WorkoutRow` (source
    /// "manual"), which then shows in the Workouts view. The day's strain already counts this HR (it's
    /// the same live stream the store persists), so this is a per-session annotation, not a double-count.
    var activeWorkout: ActiveWorkout?
    /// The guided strength session in progress (FER-347), or nil. Lives here (global) so closing its sheet
    /// or switching tabs never loses it — the Train hub re-presents it. Saved as a `StrengthSession` + its
    /// `SetEntry` rows on Finish. Independent of the live HR workout above.
    var strengthSession: StrengthSessionModel? { didSet { bindRestActivity() } }
    /// Subscription to the active session's changes — drives the rest Live Activity's reconcile loop.
    private var restActivityCancellable: AnyCancellable?
    /// Debounces the in-progress-session snapshot writes (FER-798): a burst of keypad edits collapses to
    /// one store write; a phase change (rest start/end) forces an immediate flush.
    private var persistSessionTask: Task<Void, Never>?
    /// The session phase last seen by the persist observer — a change vs. this triggers an immediate flush.
    private var lastObservedStrengthPhase: StrengthSessionModel.Phase?
    /// Called at launch when there is NO recoverable in-progress strength session (FER-798). FER-806 installs
    /// this to end any orphaned Live Activity; nil here — this issue only leaves the hook.
    var onNoRecoverableStrengthSession: (() -> Void)?
    /// FER-810: the last plan signature mirrored to the watch, so the rotor is pushed only when its visible
    /// state changes (a set done / current advanced), not on every HR tick. Reset when the session rebinds.
    private var lastPlanSignature: String?
    /// Whether the guided-session sheet is currently shown. False while a session runs but the sheet is
    /// dismissed (the hub then offers «Resume»). Set true on start/resume, false on swipe-dismiss/finish.
    var strengthSheetPresented = false
    /// The just-ended workout, for a brief inline confirmation in the Train hub (cleared on the next start).
    var lastWorkout: WorkoutRow?
    /// True when the just-ended session was discarded because no HR ever arrived (<2 samples), so the
    /// Train hub can show an honest "not saved" notice instead of silently dropping it (FER-197).
    /// Cleared on the next start and on acknowledge.
    var lastWorkoutDiscarded = false

    /// A manual workout in progress. `samples` accumulate from the smoothed live `bpm`; `liveStrain`
    /// is recomputed as the window grows so the active card can show strain building in real time.
    struct ActiveWorkout: Equatable {
        let start: Date
        var samples: [HRSample] = []
        var liveStrain: Double = 0
        var avgHr: Int = 0
        var peakHr: Int = 0
        // FER-870: running sums so each 1 Hz sample extends the average/strain in O(1)+O(300) instead
        // of re-summing and re-sorting the whole growing buffer. `strainState` folds the same Edwards
        // TRIMP `StrainScorer.strain` computes, so `strain` == the from-scratch value at every sample.
        var hrSum: Int = 0
        var strainState: StrainScorer.CumulativeStrainState?
    }
    /// Illness/strain early-warning (recent RHR up + HRV down + skin-temp up vs baseline). nil = clear.
    var healthAlert: String?
    private var lastDoubleTapAt: Date = .distantPast
    private var lastCoachZone: Int = -1
    // Stress-nudge state: rolling R-R buffer + a slow HRV baseline + a rate limiter.
    private var rrBuf: [Int] = []
    private var hrvBaseline: Double = 0
    private var lastStressBuzzAt: Date = .distantPast

    /// Import source currently writing to the local store, if any.
    private var activeImportSource: DataSourceImportKind?
    /// Last Apple Health import result surfaced in the Apple Health card.
    var appleHealthImportSummary: String?
    /// Typed failure flags per source — the summary's warning styling reads these instead of
    /// substring-matching the human-readable message (which misses errors like "Couldn't open
    /// the local store."). Surfaced on both the Data Sources cards and the onboarding import step.
    var appleHealthImportFailed = false
    /// Live element count during an Apple Health import, so the card shows real
    /// progress instead of a frozen-looking spinner on a multi-minute parse.
    var appleHealthImportProgress: Int?

    /// The in-flight import, retained so it can be cancelled. A fire-and-forget `Task` leaked:
    /// it kept parsing + writing after the user left the screen or started another import, and
    /// nothing could stop it. Now a new import (or `cancelImport()`) cancels the previous one, and
    /// the importers poll cancellation cooperatively so the work actually stops (FER-33).
    private var importTask: Task<Void, Never>?

    /// The illness heads-up recompute (FER-667), retained so a newer dashboard emission cancels the
    /// in-flight one — its journal read is async, so two overlapping runs could otherwise write
    /// `healthAlert` out of order.
    private var illnessTask: Task<Void, Never>?

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
        case .appleHealth: return appleHealthImportFailed
        }
    }

    /// Smoothed, display-ready live heart rate — median over a short window, spike-filtered.
    /// Every screen should show THIS, not the raw per-beat value (which swings with HRV).
    /// Stored on `live.pulse` (FER-755) so the ~1 Hz publish invalidates only the views that
    /// display it (via PulseReader), not every screen observing AppModel.
    var bpm: Int? {
        get { live.pulse.smoothedBpm }
        set { live.pulse.smoothedBpm = newValue }
    }
    /// The in-progress day's LIVE Day Strain (0–21): today's HR (local civil day → now) run through the
    /// SAME canonical parameters the intraday curve uses, so it equals the curve's LAST point by
    /// construction (FER-650). This is the DISPLAY value for the CURRENT day on the Hoy tile and the
    /// Detalle hero — one derivation, three surfaces. The settled `repo.today.strain` is left untouched
    /// (it still feeds recovery/readiness baselines). nil until first computed, or when there's too little
    /// activity today to score. Refreshed by `refreshLiveDayStrain()` on each dashboard/HR-flush tick.
    private(set) var liveDayStrain: Double?
    // FER-870: incremental cache for the in-progress day's strain curve. Each HR flush folds ONLY the
    // samples newer than `liveStrainState.lastTs` (TRIMP is additive) off the main actor, instead of
    // re-reading ~86k rows and re-sorting every gap from scratch. Reset when the civil day rolls over,
    // the data source switches, or a scoring parameter changes (`liveStrainDayStart`/`liveStrainSource`
    // + the state's own parameter check) — the only cases where the batch recompute would differ.
    private var liveStrainState: StrainScorer.CumulativeStrainState?
    private var liveStrainDayStart: Int?
    private var liveStrainSource: DataSourceMode?
    /// Generation counter for in-flight live-strain folds: only the most recently STARTED fold may
    /// commit its extended state, so a slow older fold can never double-count or clobber a newer one
    /// (same discipline as `Repository.refreshGen`). @MainActor-confined ⇒ no races.
    private var liveStrainGen = 0
    private var hrWindow: [(t: Date, v: Double)] = []
    private var hrCancellables = Set<AnyCancellable>()

    init() {
        let live: LiveState = LiveState()
        self.live = live
        self.ble = BLEManager(state: live, deviceId: "my-whoop")
        self.repo = Repository(deviceId: "my-whoop")
        self.repo.dataSourceMode = sources.mode      // FER-484: honor the persisted mode from launch
        self.repo.baselineEpoch = profile.baselineEpochOrNil   // FER-677: honor a persisted recalibration
        // FER-883: same HRmax as the live path. Inlined (not `effectiveHRmax`) — a computed property
        // can't be read here before all stored props are initialized.
        let hrMaxOverride: Int = profile.hrMaxOverride
        let age: Int = profile.age
        let strainHRmax: Double? = hrMaxOverride > 0
            ? Double(hrMaxOverride)
            : (age > 0 ? StrainScorer.tanakaHRmax(age: Double(age)) : nil)
        self.repo.strainHRmax = strainHRmax
        self.repo.strainSex = profile.sex
        let deviceFamily: DeviceFamily = WhoopModel.persisted.deviceFamily
        self.intelligence = IntelligenceEngine(repo: repo, profile: profile, deviceId: "my-whoop",
                                               family: deviceFamily)
        // Smooth HR centrally so it's solid everywhere it's shown.
        live.pulse.$heartRate.sink { [weak self] (_: Int?) in self?.ingestHR() }.store(in: &hrCancellables)
        live.pulse.$rr.sink { [weak self] (_: [Int]) in self?.ingestHR() }.store(in: &hrCancellables)

        // Physical-input + wear hooks (fired live by FrameRouter).
        live.onDoubleTap = { [weak self] in self?.handleDoubleTap() }
        live.onWristChange = { [weak self] (worn: Bool) in self?.handleWristChange(worn) }
        // HR-zone haptic coaching watches the smoothed bpm.
        live.pulse.$smoothedBpm.sink { [weak self] (hr: Int?) in self?.coachZone(hr) }.store(in: &hrCancellables)
        // FER-721: the lock-screen actions come back through the controller; apply them to the live session.
        restActivity.onAction = { [weak self] (action: RestActivityBridge.Action) in self?.applyRestAction(action) }
        // FER-806: the Activity now lives the WHOLE session, so we must NOT kill it unconditionally at
        // launch — that would blow away a legitimate card before crash-recovery restores its session.
        // Instead, only when FER-798's recovery finds NO recoverable session do we end any orphan (a card
        // left by a killed, unrecoverable session). A recoverable session is restored first, and its
        // `didSet` reconcile adopts the running Activity, so it stays alive.
        onNoRecoverableStrengthSession = { [weak self] in self?.restActivity.endOrphans() }
        RestThumbnailStore.clear()   // FER-789: sweep any rest thumbnail left by a killed session
        // Illness/strain early-warning recomputes when the daily history changes. `days` is no longer
        // its own @Published (folded into `dashboard` for single-publish refreshes, FER-30), so watch
        // the dashboard and project its days — still one emission per refresh.
        // FER-872: the launch cascade publishes the dashboard 4-5× in the first seconds (firstPaint,
        // full, morning analyzeRecent, HealthKit sync…). The illness window only reads counts + the
        // last two nights, so dedup by (count, last day) collapses those redundant re-evals into one —
        // a genuine data change (a new night or a longer history) still changes the signature and fires.
        // `reevaluateIllness()` calls `evaluateIllness` directly, so a settings toggle is never deduped.
        repo.$dashboard.map(\.days)
            .removeDuplicates { (a: [DailyMetric], b: [DailyMetric]) -> Bool in
                a.count == b.count && a.last?.day == b.last?.day
            }
            .sink { [weak self] (days: [DailyMetric]) in self?.evaluateIllness(days) }
            .store(in: &hrCancellables)
        // Re-arm the strap's firmware alarm whenever it (re)bonds. A smart-alarm time changed while the
        // strap was away never reached it — the send is gated on bond — so the strap kept the OLD time
        // and fired at it (#59). FER-874: LiveState is `@Observable` (no `$` publishers), so this is now a
        // callback fired from `bonded`'s didSet; the `!= oldValue` guard there is the old `removeDuplicates`.
        // Gated on enabled so a disabled alarm doesn't disarm on every reconnect.
        live.onBondedChange = { [weak self] bonded in
            guard let self, bonded, self.behavior.smartAlarmEnabled else { return }
            self.applySmartAlarm()
        }
        // A completed backfill has just written strap history. Refresh the dashboard cache, but leave
        // heavyweight analysis to its own guarded/background-friendly path. FER-874: callback from
        // `lastSyncedAt`'s didSet (non-nil + distinct), replacing the old `$lastSyncedAt` Combine sink.
        live.onSyncCompleted = { [weak self] _ in
            Task { [weak self] in await self?.refreshAfterCompletedBackfill() }
        }

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
                // FER-939: the Entrenar hub's planned state (routines + split + sessions) rides
                // every non-empty fixture, so the Train tab captures its full layout too.
                await ScreenshotFixtures.seedTrainingPlan(self)
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
            // Si hoy aún no tiene veredicto (mañana post-medianoche: la fila no existe o su recovery es
            // nil), no hagas esperar el primer análisis los 6 s del offload: los crudos YA almacenados
            // pueden producirlo ahora. El sleep de abajo queda solo como cortesía al primer offload BLE.
            if self.repo.today?.recovery == nil,
               Self.mayRecomputeAfterBackfill(backfilling: self.live.backfilling,
                                              hasActiveImport: self.hasActiveImport) {
                await self.intelligence.analyzeRecent()
            }
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
        // Two-pass launch: if the full history hasn't published (e.g. a pull-to-refresh made the
        // launch full pass stale mid-flight), `analyzeRecent(force:)` below would skip silently and
        // the cursor would burn WITHOUT the re-group having run. Defer to the next foreground/launch.
        guard repo.fullyLoaded else { return }
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

    /// Switch the data-source mode (combined / WHOOP-only / Apple-Health-only), persist it, and re-read
    /// the dashboard + baseline through the new filter. Non-destructive: every source stays stored and
    /// capture keeps running; only what's READ changes, so switching back to `.combined` restores the
    /// prior view with no re-import (FER-484). The UI selector (F2) will call this.
    func setDataSourceMode(_ m: DataSourceMode) {
        guard m != sources.mode else { return }
        sources.mode = m
        repo.dataSourceMode = m
        repo.strainHRmax = effectiveHRmax; repo.strainSex = profile.sex   // FER-883: refresh HRmax when entering Apple mode
        Task { @MainActor in
            await repo.refresh()
            await intelligence.analyzeRecent(force: true)
        }
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

    private func refreshAfterCompletedBackfill() async {
        live.append(log: "Backfill: refreshing dashboard cache from completed sync")
        // Full refresh, not a 120-day window: a windowed publish here used to clobber the dashboard
        // down to 120 days (truncating Tendencias 1A until the next full pass) and let the recompute
        // below fold baselines over it. With the off-main assembly the full pass no longer punishes
        // the main actor, so the shortcut lost its reason to exist.
        await repo.refresh()
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
        reconcileRestActivity()   // FER-721: push the fresh pulse to the rest Live Activity (HR-throttled)
    }

    // MARK: - Rest Live Activity (FER-721)

    /// Re-subscribe the rest Live Activity to whichever session is now active. Fires on every session
    /// start/end (via `strengthSession`'s `didSet`). Also drives the crash-recovery snapshot (FER-798):
    /// every durable edit persists the session (debounced), and a phase change (rest start/end) flushes now.
    private func bindRestActivity() {
        lastObservedStrengthPhase = strengthSession?.phase
        lastPlanSignature = nil   // FER-810: force a fresh plan push for the newly bound session
        restActivityCancellable = strengthSession?.objectWillChange
            .receive(on: DispatchQueue.main)   // read the session AFTER its change lands
            .sink { [weak self] in
                guard let self else { return }
                self.reconcileRestActivity()
                let phase = self.strengthSession?.phase
                let phaseChanged = phase != self.lastObservedStrengthPhase
                self.lastObservedStrengthPhase = phase
                self.scheduleInProgressPersist(immediate: phaseChanged)
            }
        reconcileRestActivity()
    }

    // MARK: - Crash-recovery persistence of the in-progress session (FER-798)

    /// Persist the live session's durable snapshot so it survives a crash/kill. Debounced by default (a
    /// burst of keypad edits → one write); `immediate` flushes now (session start, rest start/end — the
    /// moments most costly to lose). A no-op once the session has a receipt (it's already saved).
    func scheduleInProgressPersist(immediate: Bool = false) {
        guard let session = strengthSession, session.summary == nil else { return }
        persistSessionTask?.cancel()
        guard !immediate else {
            persistSessionTask = nil
            let snapshot = session.snapshot()   // immediate = a phase change (rare); capture the state now
            Task { [weak self] in await self?.writeInProgressSnapshot(snapshot) }
            return
        }
        // Debounced path: build the snapshot only when the delay fires, NOT on every coalesced keystroke —
        // a burst of edits would otherwise build (and throw away) a full deep copy each time.
        persistSessionTask = Self.debounced(after: 1_000_000_000) { [weak self] in
            await self?.persistCurrentSnapshot()
        }
    }

    /// Snapshot the live session on the main actor and persist it — the debounced write body, so the deep
    /// copy happens once at fire time rather than per edit. A no-op once the session has a receipt.
    @MainActor
    private func persistCurrentSnapshot() async {
        guard let session = strengthSession, session.summary == nil else { return }
        await writeInProgressSnapshot(session.snapshot())
    }

    private func writeInProgressSnapshot(_ snapshot: StrengthSessionSnapshot) async {
        guard let store = await repo.storeHandle() else { return }
        try? await store.saveInProgressSession(snapshot)
    }

    /// Drop the persisted in-progress snapshot (session saved, discarded, or receipt dismissed). Idempotent.
    func clearInProgressSession() {
        persistSessionTask?.cancel(); persistSessionTask = nil
        Task { [weak self] in
            guard let self, let store = await self.repo.storeHandle() else { return }
            try? await store.clearInProgressSession()
        }
    }

    /// Restore an in-progress strength session left by a crash/kill (FER-798): rebuild the live session so
    /// the Apple Watch's queued `.end` finds it and the receipt is saved. Runs once at launch. If the
    /// snapshot belongs to an already-saved session (a clear that failed after a save), discard it without
    /// restoring — no double receipt. No recoverable session → fire `onNoRecoverableStrengthSession`
    /// (FER-806's hook to close any orphaned Live Activity).
    func restoreInProgressStrengthSessionIfNeeded() async {
        #if DEBUG
        // Canvas/previews: la restauración post-crash corría en CARRERA con el seed de fixtures y
        // resucitaba una sesión vieja del store compartido — editor bloqueado sin razón visible
        // (canvas 2026-07-16). Los previews arrancan sesiones solo de forma explícita.
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" { return }
        #endif
        guard strengthSession == nil else { return }                 // never clobber a live session
        guard let store = await repo.storeHandle() else { return }   // no store yet → retry next launch
        guard let snap = (try? await store.inProgressSession()) ?? nil else {
            onNoRecoverableStrengthSession?()
            return
        }
        if (try? await store.session(id: snap.id)) != nil {
            try? await store.clearInProgressSession()
            onNoRecoverableStrengthSession?()
            return
        }
        strengthSession = StrengthSessionModel.restore(from: snap)   // didSet binds the Live Activity
        strengthSheetPresented = false                               // the hub offers «Resume»; no auto-present
        acquireRealtimeHR("strength")                                // re-arm the HR stream as at start
    }

    /// Hand the controller the current rest snapshot (or nil when not resting) — it starts/updates/ends
    /// the one Activity from that. Cheap and idempotent, so it's safe to call on any relevant change.
    /// FER-740: the same snapshot feeds the Apple Watch mirrored session (no-op without a watch).
    private func reconcileRestActivity() {
        // FER-758: an HR-guided rest ends the instant the pulse has recovered to target (past the 20s
        // floor), not only when the fallback clock runs out — and the watch buzzes «ready» to say so.
        // Only the honest HR-recovery path ends early here; the clock ceiling stays the watch's own timer.
        // FER-823: never end the rest while paused — the band keeps streaming, so an HR that recovers to
        // target during a pause must NOT skip the (frozen) rest. Same `!s.paused` gate as computeSessionSnapshot.
        if let s = strengthSession, s.summary == nil, !s.paused, s.phase == .resting,
           s.currentRestMode == .heartRate, let started = s.restStartedAt {
            let elapsed = max(0, Int(Date().timeIntervalSince(started)))
            let hr = (live.connected && live.worn) ? bpm : nil
            let v = RestReadinessRule.evaluate(currentHR: hr, worn: live.worn,
                                               restingHR: restingHrBaseline, elapsedS: elapsed,
                                               targetHR: s.currentRestTarget)
            if v.ready, v.reason == .hrRecovered {
                s.skipRest()
                clearRestThumb()
                restActivity.reconcile(nil)
                mirroringBridge?.pushRestEnded(sessionId: s.id, recovered: true)
                return
            }
        }
        let snapshot = computeSessionSnapshot()
        if snapshot == nil { clearRestThumb() }   // FER-789: no stale App Group image once the session ends
        restActivity.reconcile(snapshot)
        // FER-806: the Live Activity now spans the whole session, but the Apple Watch mirror keeps
        // FER-721's rest-only semantics — only push a rest window to the wrist while genuinely resting, so
        // the watch never shows a phantom countdown during the active set. Any other phase (active/pause,
        // or no session) = «rest ended», and FER-809's capture context takes over on the wrist.
        if let snapshot, snapshot.sessionPhaseRaw == SessionPhase.resting.rawValue {
            mirroringBridge?.pushRest(snapshot)
        } else if let sid = strengthSession?.id {
            mirroringBridge?.pushRestEnded(sessionId: sid)
            // FER-809: between rests, mirror the capture context so the wrist shows «qué toca», not a bare pulse.
            if let capture = computeCaptureSnapshot() { mirroringBridge?.pushCapture(capture) }
        }
        // FER-810: mirror the plan to the wrist's rotor, but only when its visible state changed.
        if let plan = computePlanSnapshot(), plan.signature != lastPlanSignature {
            lastPlanSignature = plan.signature
            mirroringBridge?.pushPlan(plan)
        }
    }

    /// Drop the staged rest thumbnail (App Group file + memo) — called whenever the rest/session ends so
    /// the next rest never shows the previous exercise's image (FER-789).
    private func clearRestThumb() {
        RestThumbnailStore.clear()
        preparedRestThumb = nil
    }

    /// The most recent nightly resting HR — the baseline for HR-guided rest targets (FER-348/FER-758).
    /// Same source the live sheet reads, so both compute the identical «recovered» target.
    private var restingHrBaseline: Double? { repo.days.compactMap(\.restingHr).last.map(Double.init) }

    /// The exercise whose thumbnail is currently staged in the App Group, and the resulting file name —
    /// so a rest snapshot copies the JPG only when the focused exercise changes, not on every reconcile.
    private var preparedRestThumb: (exerciseId: String, name: String?)?

    /// FER-806 — the whole-session phase the Live Activity paints, or nil when there's nothing to show
    /// (no session, or the receipt is up ⇒ the Activity ends). Pure + static so it's unit-testable without
    /// an AppModel or ActivityKit. `.paused` wins; then `.resting` between sets; else the active set.
    static func sessionPhase(for s: StrengthSessionModel?) -> SessionPhase? {
        guard let s, s.summary == nil else { return nil }
        if s.paused { return .paused }
        if s.phase == .resting { return .resting }
        return .active
    }

    /// The display-ready snapshot that drives the full-session Live Activity (FER-806), or nil when there's
    /// nothing to show (no session, the receipt is up, or the focused set is gone ⇒ the Activity ends).
    /// Generalizes FER-721's rest-only snapshot: it's produced across the WHOLE session (active set, rest,
    /// pause) and carries the session phase + global progress so the card keeps its fixed skeleton.
    private func computeSessionSnapshot() -> RestActivitySnapshot? {
        guard let phase = Self.sessionPhase(for: strengthSession),
              let s = strengthSession, let run = s.current, let set = s.currentSet else { return nil }
        let unit = UnitSystem(rawValue: UserDefaults.standard.string(forKey: UnitPrefs.systemKey) ?? "")
            ?? .metric
        // «al volver» / «peso × reps» detail: weight×reps exercises show the load; time/distance carry none.
        let usesWeightReps = run.type == .weightReps || run.type == .bodyweight
        let detail = usesWeightReps ? "\(StrengthDisplay.weight(set.weightKg, system: unit)) × \(set.reps)" : ""
        // No band (disconnected / off-wrist) → no pulse: the surfaces then show only the timer/hero.
        let bandBpm: Int? = (live.connected && live.worn) ? bpm : nil
        // FER-789 — rest phase drives the card's primary action + context line: the routine's last pending
        // set → «Terminar entreno» (flag); an exercise's last set → «Sigue: {next}»; otherwise the check.
        let restPhase: RestPhase = s.pendingCount <= 1 ? .lastSetOfRoutine
            : (s.pendingInCurrentRun <= 1 ? .lastSetOfExercise : .midExercise)
        let nextName = restPhase == .lastSetOfExercise ? s.nextPendingExerciseName : nil
        // Rest window: real dates while resting; a zero window «now» otherwise (the active/paused card
        // never renders the countdown — it keys off `sessionPhase`).
        let now = Date()
        let restStart = s.restStartedAt ?? now
        let restEnd = s.restEndsAt ?? now
        // FER-823 — the active-phase count-up anchors to the EFFECTIVE start in WALL-CLOCK terms
        // (`startTs + pausedSeconds`), so `now − anchor == active elapsed` while excluding paused time. Anchored
        // to the clock (not `now − elapsed`) so it stays STABLE tick-to-tick — a jittering anchor would flip
        // the controller's structural fingerprint every second and defeat its HR-update throttle. Active only.
        let effectiveStart = Date(timeIntervalSince1970: Double(s.startTs + s.pausedSeconds(at: now)))
        return RestActivitySnapshot(
            sessionId: s.id, routineName: s.routineName,
            setNumber: run.currentSet + 1, setTotal: run.sets.count,
            exerciseName: run.name, returnDetail: detail,
            restStartedAt: restStart, restEndsAt: restEnd,
            isHRMode: s.currentRestMode == .heartRate, hrTarget: s.currentRestTarget, bpm: bandBpm,
            phaseRaw: restPhase.rawValue, nextExerciseName: nextName,
            thumbnailName: restThumbName(for: run.exerciseId),
            paused: s.paused,
            sessionPhaseRaw: phase.rawValue,
            sessionStartedAt: phase == .active ? effectiveStart : nil,
            setsDone: s.doneCount, setsTotal: s.doneCount + s.pendingCount)
    }

    /// The display-ready capture snapshot (FER-809), or nil when not capturing (no session, resting, or the
    /// focused set is gone). Same field derivation as `computeRestSnapshot` so the wrist's «qué toca» reads
    /// identically to the rest card's «al volver» — set N/M, exercise and its «weight × reps».
    private func computeCaptureSnapshot() -> WorkoutCaptureSnapshot? {
        guard let s = strengthSession, s.summary == nil, s.phase == .capturing,
              let run = s.current, let set = s.currentSet else { return nil }
        let unit = UnitSystem(rawValue: UserDefaults.standard.string(forKey: UnitPrefs.systemKey) ?? "")
            ?? .metric
        let usesWeightReps = run.type == .weightReps || run.type == .bodyweight
        let detail = usesWeightReps ? "\(StrengthDisplay.weight(set.weightKg, system: unit)) × \(set.reps)" : ""
        let bandBpm: Int? = (live.connected && live.worn) ? bpm : nil
        return WorkoutCaptureSnapshot(
            sessionId: s.id, routineName: s.routineName,
            setNumber: run.currentSet + 1, setTotal: run.sets.count,
            exerciseName: run.name, returnDetail: detail, bpm: bandBpm,
            hrMax: profile.hrMax > 0 ? profile.hrMax : nil)   // FER-811: wrist effort-zone label; nil → omit
    }

    /// The lightweight plan snapshot for the watch rotor (FER-810), or nil with no session. Read-only: each
    /// exercise's name, sets done / total, and whether it's the current run — never the editable rest fields.
    private func computePlanSnapshot() -> WorkoutPlanSnapshot? {
        guard let s = strengthSession, s.summary == nil, !s.runs.isEmpty else { return nil }
        let currentId = s.current?.id
        let exercises = s.runs.map { run in
            WorkoutPlanSnapshot.Exercise(
                name: run.name,
                setsDone: run.sets.filter(\.done).count,
                setsTotal: run.sets.count,
                isCurrent: run.id == currentId)
        }
        return WorkoutPlanSnapshot(sessionId: s.id, routineName: s.routineName, exercises: exercises)
    }

    /// The App Group thumbnail file name for the focused exercise, copying the JPG only when the exercise
    /// changes (memoized). nil when media is off or the exercise has no cached image → the card omits it.
    private func restThumbName(for exerciseId: String) -> String? {
        if let cached = preparedRestThumb, cached.exerciseId == exerciseId { return cached.name }
        let enabled = UserDefaults.standard.bool(forKey: MediaDownloadCoordinator.enabledKey)
        let name = RestThumbnailProvider.prepare(exerciseId: exerciseId, mediaEnabled: enabled)
        preparedRestThumb = (exerciseId, name)
        return name
    }

    /// Apply a lock-screen action to the live session; the reconcile that follows reflects it back onto
    /// the Activity (a longer countdown, a shorter one, ending it, or advancing the session). FER-789
    /// adds ±30, complete-set and finish-workout. Completar ≠ Saltar: `completeSet` logs the upcoming set
    /// (`registerCurrentSet`) and rests again; `skip` only cuts the timer and leaves the set pending.
    private func applyRestAction(_ action: RestActivityBridge.Action) {
        // FER-806: actions arrive across the whole session now (the Activity lives the whole session), so
        // the guard is only «there's a live session without a receipt» — each action gates its own phase.
        guard let s = strengthSession, s.summary == nil else { return }
        switch action {
        case .resume:
            resumeStrengthSessionFromPause()   // FER-823 — leave «En pausa»; re-arms the reconcile loop
        case .completeSet:
            // «Completar» — works from the active card (log the set → rest) AND the rest card (log the
            // upcoming set → rest again). registerCurrentSet advances either way.
            s.registerCurrentSet(restingHR: restingHrBaseline, maxHR: Double(profile.hrMax))
        case .finishWorkout:
            // Last set of the routine: log it, then end the session (which ends the Live Activity).
            s.registerCurrentSet(restingHR: restingHrBaseline, maxHR: Double(profile.hrMax))
            endStrengthSession(save: true)
        case .addThirty:
            guard s.phase == .resting, !s.paused else { return }
            s.extendRest(byseconds: 30)
        case .removeThirty:
            guard s.phase == .resting, !s.paused else { return }
            s.extendRest(byseconds: -30)   // floored at «now» by extendRest — never negative
        case .skip:
            guard s.phase == .resting, !s.paused else { return }
            s.skipRest()
        }
    }

    /// Apply a wrist-initiated action (FER-808) to the live session. Routes to the SAME session mutators
    /// the lock-screen rest actions use (`registerCurrentSet` / `skipRest` / `extendRest`) — one path, no
    /// duplicated logic — and the `objectWillChange` reconcile that follows re-emits the fresh snapshot to
    /// both the wrist and the Live Activity. Each case is gated to the phase its wrist affordance lives in:
    /// `completeSet` fires from the capture face (guarded to `.capturing` so a late/queued message can't
    /// double-advance a set mid-rest); skip/adjust apply only while resting, mirroring `applyRestAction`.
    func applyWatchWorkoutAction(_ action: WatchWorkoutAction, sessionId: String) {
        guard let s = strengthSession, s.id == sessionId else { return }
        switch action {
        case .completeSet:
            guard s.phase == .capturing else { return }
            s.registerCurrentSet(restingHR: restingHrBaseline, maxHR: Double(profile.hrMax))
        case .skipRest:
            guard s.phase == .resting else { return }
            s.skipRest()
        case let .adjustRest(deltaS):
            guard s.phase == .resting else { return }
            s.extendRest(byseconds: deltaS)   // floored at «now» by extendRest — never negative
        }
    }

    /// FER-810: «Ver recibo en iPhone» on the wrist summary → resolve the persisted session and publish its
    /// history-detail route; `RootTabView` switches to Entrenar and pushes `WorkoutSessionDetailScreen`. The
    /// route's `routineName` is a fallback (the detail's own `load()` resolves the real name from the store).
    var pendingReceiptRoute: WorkoutSessionRoute?

    func openWorkoutReceipt(sessionId: String) async {
        guard let s = await repo.session(id: sessionId) else { return }
        var name = String(localized: "Strength workout")
        if let rid = s.routineId, let r = (await repo.routines()).first(where: { $0.id == rid }) { name = r.name }
        pendingReceiptRoute = WorkoutSessionRoute(id: s.id, startTs: s.startTs, endTs: s.endTs,
                                                  strain: s.strain, avgHr: s.avgHr, routineName: name)
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
        // r22 (owner): un ejercicio con calentamiento ACTIVADO nace con su rampa «C» puesta — la de
        // PlateMath sobre el peso de trabajo del día (solo barra, como la hoja de discos). Insertar
        // la rampa una vez lo activó; quitar su última «C» en sesión lo apaga (LiveStrengthSheet).
        if let s = strengthSession {
            for (ei, run) in s.runs.enumerated() where plates.warmupExerciseIds.contains(run.exerciseId) {
                guard !run.sets.contains(where: { $0.kind == .warmup }),
                      let workKg = run.sets.first(where: { $0.kind == .work })?.weightKg, workKg > 0,
                      let eq = ExerciseCatalog.byID(run.exerciseId)?.equipment?.lowercased(),
                      eq.contains("barbell") || eq.contains("curl bar") else { continue }
                let ramp = PlateMath.warmup(workKg: workKg, barKg: plates.barKg, inventory: plates.inventory)
                guard !ramp.isEmpty else { continue }
                s.insertWarmup(exercise: ei, sets: ramp.map { (weightKg: $0.weightKg, reps: $0.reps) })
            }
        }
        strengthSheetPresented = true
        // Arm the realtime HR stream for the duration of the session (FER-498) — without this, on a
        // WHOOP 4.0 the session sees no HR unless Live was opened first, and the receipt reads "no HR".
        acquireRealtimeHR("strength")
        // FER-740: wake the Apple Watch to record the real HKWorkoutSession, if available. Fire-and-forget
        // — the session above has already started; the watch just joins.
        if let s = strengthSession {
            mirroringBridge?.beginMirroredSessionIfEnabled(sessionId: s.id, routineName: routineName,
                                                           startedAt: Date())
        }
        scheduleInProgressPersist(immediate: true)   // FER-798: persist from the first moment (crash-safe)
        buzz(loops: 1)   // confirm the session started, same single buzz as the manual live workout (FER-498)
    }

    /// Start the bundled mobility template as a one-off guided session, NOT saved to the plan
    /// (`routineId: nil`). Shared by «Hoy descansas» (2B) and «Otra forma de entrenar» (3e), which are
    /// now pushed screens (FER-718). No-op if the template can't be resolved.
    func startMobilityOneOff() {
        guard let t = StarterTemplates.byID("mobility") else { return }
        let name = String(localized: "Mobility")
        let (_, exercises) = t.makeRoutine(name: name, now: Int(Date().timeIntervalSince1970))
        let slots = exercises.map {
            StrengthSessionModel.PlanSlot(re: $0, exercise: ExerciseCatalog.byID($0.exerciseId), lastSets: [])
        }
        startStrengthSession(routineId: nil, routineName: name, slots: slots)
    }

    /// Re-show the sheet for the in-progress session (the hub's «Resume»).
    func resumeStrengthSession() { if strengthSession != nil { strengthSheetPresented = true } }

    /// Pause the guided session (FER-823): freezes the clock and any rest, persists the paused state, and
    /// updates the Live Activity (the rest card ends while paused; the full-session card is FER-806).
    func pauseStrengthSession() {
        guard let s = strengthSession else { return }
        s.pause()
        reconcileRestActivity()
        scheduleInProgressPersist(immediate: true)
    }

    /// Resume the paused session (FER-823): shifts the rest/stopwatch anchors forward so they continue
    /// exactly where they were, then re-arms the Live Activity and persists. Named distinctly from
    /// `resumeStrengthSession()` (which only re-opens the sheet) so the two intents can't be confused.
    func resumeStrengthSessionFromPause() {
        guard let s = strengthSession else { return }
        s.resume()
        reconcileRestActivity()
        scheduleInProgressPersist(immediate: true)
    }

    /// Finish the guided session. With ≥1 logged set: persist it, mirror to Apple Health (opt-in), and
    /// compute the post-session receipt (FER-409) — keeping the session ALIVE so the sheet renders its
    /// `summaryPhase`. With nothing logged: discard and close. The receipt is ended by `closeStrengthSummary`
    /// («Listo» or a swipe of the summary).
    func endStrengthSession(save: Bool) { endStrengthSession(save: save, notifyWatch: true) }

    /// End the session from the Apple Watch (the user tapped end on the wrist). Same local persistence,
    /// but never echoes the end order back to the watch (it already ended). The watch's
    /// `watchDidSaveWorkout` ack has already marked this session, so the invariant gate omits the
    /// iPhone's HealthKit save. (FER-740)
    func endStrengthSessionFromWatch(sessionId: String, save: Bool) {
        guard let s = strengthSession, s.id == sessionId else { return }
        endStrengthSession(save: save, notifyWatch: false)
    }

    /// Marks that the watch saved the real `HKWorkout` for this session — the invariant gate then omits
    /// the iPhone's own save. Installed as a callback on the mirroring bridge. (FER-740)
    func noteWatchSavedWorkout(_ sessionId: String) { watchSavedSessionIds.insert(sessionId) }

    /// Marks that the watch declined to save (no permission / error / mirror lost) — the iPhone takes
    /// over and saves its estimated workout. Installed as a callback on the mirroring bridge. (FER-740)
    func noteWatchWillNotSave(_ sessionId: String) { watchDeclinedSessionIds.insert(sessionId) }

    /// FER-742: ask the bridge to recompute paired-watch availability (drives the Settings row's states).
    func refreshWatchPairing() { mirroringBridge?.refreshPairingState() }
    /// FER-742: «Reintentar» from the strength sheet's watch status line.
    func retryWatchMirroring() { mirroringBridge?.retryMirroring() }

    private func endStrengthSession(save: Bool, notifyWatch: Bool) {
        guard let session = strengthSession else { strengthSheetPresented = false; return }
        // FER-798: idempotent against a duplicate `.end` (the watch has been seen to ack twice) — once the
        // session has a receipt it's already saved, so a second end is a no-op (no re-save/re-mirror/re-Health).
        guard session.summary == nil else { return }
        // FER-823: the saved duration excludes time spent paused, so the receipt, the calorie estimate and
        // the Apple Health workout all reflect active time. `endTs` is the active end (wall clock minus pauses).
        let endTs = session.startTs + session.elapsedSeconds()
        // FER-740: was the watch actively mirroring this session? Capture before we tear it down — it
        // decides whether the iPhone waits for the watch's save decision below.
        let wasMirroring = mirroringBridge?.isMirroringActive ?? false
        guard save, session.doneCount > 0 else {        // nothing logged → discard + close
            if notifyWatch {
                mirroringBridge?.endMirroredSession(sessionId: session.id, endedAt: Date(), save: false)
            }
            strengthSession = nil
            strengthSheetPresented = false
            releaseRealtimeHR("strength")
            clearInProgressSession()   // FER-798: nothing to recover once discarded
            return
        }
        // Order the watch to end + save its real recording. Its `watchDidSaveWorkout` ack (awaited below)
        // decides whether the iPhone also saves — the one-HKWorkout invariant.
        if notifyWatch {
            mirroringBridge?.endMirroredSession(sessionId: session.id, endedAt: Date(), save: true)
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
        // FER-715: persist the session's energy + where it came from. Same entry point and threshold as
        // the Apple Health mirror, so the stored figure equals the mirrored one; the source label uses the
        // exact count `estimateStrengthEnergy` branches on, so origin can't drift from the math.
        record.energyKcal = Calories.estimateStrengthEnergy(
            hrSamples: hrSamples, durationSeconds: Double(endTs - record.startTs),
            profile: userProfile, hrMax: Double(hrMax))
        record.energySource = hrSamples.count >= Calories.strengthEnergyMinSamples
            ? .bandCalculated : .estimated
        // FER-969 (X-01): stash the fully built payload so a failed save can be retried verbatim —
        // duration/energy stay what the user saw, and the watch isn't ordered to end twice.
        pendingStrengthSave = PendingStrengthSave(
            record: record, sets: sets, progressionOptOuts: built.progressionOptOuts, notes: built.notes,
            endTs: endTs, wasMirroring: wasMirroring, notifyWatch: notifyWatch,
            userProfile: userProfile, hrSamples: hrSamples, hrMax: hrMax)
        Task { [weak self] in await self?.attemptStrengthSave() }
    }

    /// Everything `endStrengthSession` built for the durable save, kept so a failed save can retry
    /// without recomputing duration/energy or re-ordering the watch. (FER-969, X-01)
    private struct PendingStrengthSave {
        var record: StrengthSession
        var sets: [SetEntry]
        var progressionOptOuts: Set<String>
        var notes: [ExerciseNote]
        var endTs: Int
        var wasMirroring: Bool
        var notifyWatch: Bool
        var userProfile: UserProfile
        var hrSamples: [HRSample]
        var hrMax: Int
    }
    private var pendingStrengthSave: PendingStrengthSave?

    /// «Reintentar» from the sheet's save-failure banner (FER-969, X-01).
    func retryStrengthSave() {
        Task { [weak self] in await self?.attemptStrengthSave() }
    }

    /// FER-969 (X-01): the ordering contract of the final save — the anti-crash snapshot (FER-798) is
    /// dropped only AFTER the session row is durably in the store. On failure the snapshot stays put
    /// (it's the only remaining copy of the workout) and the caller surfaces a retry.
    nonisolated static func saveThenClearSnapshot(save: () async throws -> Void,
                                                  clearSnapshot: () async throws -> Void) async -> Bool {
        do { try await save() } catch { return false }
        // Best-effort: a failed clear only risks a stale restore offer, never data loss.
        try? await clearSnapshot()
        return true
    }

    private func attemptStrengthSave() async {
        guard let session = strengthSession, session.summary == nil else { return }
        guard let store = await repo.storeHandle() else {
            // `pendingStrengthSave` stays stashed — the banner's Retry re-enters here.
            session.saveError = true
            if pendingStrengthSave?.notifyWatch == false { strengthSheetPresented = true }
            return
        }
        // QA D4: TAKE the payload before the first await after this point — a second Retry tap
        // finds nil and no-ops instead of racing a duplicate post-save flow. Re-stashed on failure.
        guard let pending = pendingStrengthSave else { return }
        pendingStrengthSave = nil
        // Prior PRs (BEFORE save) so the receipt can tell which records are NEW this session.
        let prior = await priorStrengthPRs(store: store, ids: Set(pending.sets.map(\.exerciseId)))
        let saved = await Self.saveThenClearSnapshot(
            save: { try await store.saveSession(pending.record, sets: pending.sets,
                                                progressionOptOuts: pending.progressionOptOuts,
                                                notes: pending.notes) },
            clearSnapshot: { try await store.clearInProgressSession() })
        guard saved else {
            pendingStrengthSave = pending   // retry needs it back
            session.saveError = true
            // QA D5: a watch-initiated end has no open sheet — surface the failure banner too,
            // not just the receipt (FER-799's rationale applies double when something went wrong).
            if !pending.notifyWatch { strengthSheetPresented = true }
            return
        }
        session.saveError = false
        pendingStrengthSave = nil
        persistSessionTask?.cancel()            // FER-798: the session is saved — stop persisting
        // Surface the receipt on the live session — the sheet renders summaryPhase (session stays alive).
        session.summary = await buildStrengthSummary(session: session, record: pending.record,
                                                     sets: pending.sets, prior: prior, store: store)
        // FER-799: a watch-initiated end has no open sheet (the phone may be locked/backgrounded), so the
        // receipt would be stranded until the user re-opens the session. Present it — the flag re-evaluates
        // on the next foreground if the app is backgrounded. An iPhone-initiated finish already has it open.
        if !pending.notifyWatch { strengthSheetPresented = true }
        // FER-740 — one-HKWorkout invariant. If a watch was mirroring, wait briefly for its save
        // decision: it saved the real FC/kcal workout → the iPhone omits its estimate; it declined
        // or never answered → the iPhone saves as before. Without a watch, save immediately (no wait).
        let watchSaved = pending.wasMirroring ? await awaitWatchSaveDecision(sessionId: pending.record.id) : false
        // FER-742: the receipt's origin line says the watch saved the real FC/kcal to Health.
        if watchSaved { session.summary?.watchRecorded = true }
        guard WorkoutSaveGate.iPhoneShouldSaveWorkout(watchDidSaveWorkout: watchSaved) else { return }
        // Opt-in mirror to Apple Health (FER-390): a no-op unless the user enabled it. Runs AFTER
        // the local save (the source of truth) and never throws — Health is strictly best-effort.
        await healthBridge?.saveStrengthWorkoutIfEnabled(
            sessionId: pending.record.id,
            start: Date(timeIntervalSince1970: TimeInterval(pending.record.startTs)),
            end: Date(timeIntervalSince1970: TimeInterval(pending.endTs)),
            profile: pending.userProfile, hrSamples: pending.hrSamples, hrMax: pending.hrMax)
    }

    /// Await the watch's save decision for a session, up to a short timeout. Returns true only if the
    /// watch acked `watchDidSaveWorkout`. On decline or timeout returns false so the iPhone saves. The
    /// shared `externalUUID` idempotency is the hard backstop if a late ack races the iPhone's write.
    /// (FER-740; the exact timeout is tuned on hardware.)
    @MainActor
    private func awaitWatchSaveDecision(sessionId: String, timeout: TimeInterval = 6) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if watchSavedSessionIds.contains(sessionId) { return true }
            if watchDeclinedSessionIds.contains(sessionId) { return false }
            try? await Task.sleep(nanoseconds: 200_000_000)   // 0.2 s poll
        }
        return watchSavedSessionIds.contains(sessionId)
    }

    /// End the session once the user has seen the receipt (FER-409): «Listo» or a swipe of the summary.
    func closeStrengthSummary() {
        // FER-969 (X-01): while a failed save is pending retry the snapshot is the only copy —
        // never tear the session down from here in that state (the receipt can't be up yet anyway).
        if let s = strengthSession, s.summary == nil, s.saveError { return }
        strengthSession = nil
        strengthSheetPresented = false
        releaseRealtimeHR("strength")   // last consumer leaves → stream stops (unless Live still holds it)
        clearInProgressSession()        // FER-798: belt-and-suspenders — the snapshot was cleared at save
    }

    /// Prior best-per-metric PRs per exercise, BEFORE this session's save — the baseline new records beat.
    private func priorStrengthPRs(store: CenitStore, ids: Set<String>) async -> [String: [PRMetric: PersonalRecord]] {
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
                                      store: CenitStore) async -> StrengthSummary {
        let work: [SetEntry] = sets.filter { (s: SetEntry) in s.kind == .work && s.done }
        let volumeKg: Double = work.reduce(0.0) { (acc: Double, s: SetEntry) -> Double in
            let w: Double = s.weightKg ?? 0.0
            let r: Double = Double(s.reps ?? 0)
            return acc + (w * r)
        }
        let durationS: Int = max(0, (record.endTs ?? record.startTs) - record.startTs)

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
                prs.append(.init(exercise: name, metric: .maxWeight, valueKg: w, reps: nil,
                                 priorValueKg: was.valueKg))
            }
            if let r = exSets.compactMap(\.reps).max(), let was = p[.maxReps], r > (was.reps ?? 0) {
                prs.append(.init(exercise: name, metric: .maxReps, valueKg: nil, reps: r,
                                 priorReps: was.reps))
            }
            if let best = exSets.compactMap({ (s: SetEntry) -> (vol: Double, w: Double, r: Int)? in
                guard let w = s.weightKg, let r = s.reps else { return nil }
                let vol: Double = w * Double(r)
                return (vol: vol, w: w, r: r)
            }).max(by: { (a: (vol: Double, w: Double, r: Int), b: (vol: Double, w: Double, r: Int)) in a.vol < b.vol }),
               let was = p[.maxVolume] {
                let priorVol: Double = (was.valueKg ?? 0.0) * Double(was.reps ?? 0)
                if best.vol > priorVol {
                    prs.append(.init(exercise: name, metric: .maxVolume, valueKg: best.w, reps: best.r,
                                     priorValueKg: priorVol))
                }
            }
        }
        prs.sort { $0.exercise < $1.exercise }

        // «Contra tu última {rutina}» (FER-716): the newest EARLIER session of the same routine. The
        // current session is saved before this runs, so exclude it by id; a routine-less quick session
        // compares to nothing (the bars block is hidden).
        var comparison: StrengthSummary.Comparison?
        if let rid = record.routineId,
           let prev = ((try? await store.recentSessions(limit: 100)) ?? [])
               .first(where: { $0.routineId == rid && $0.id != record.id && $0.startTs < record.startTs }) {
            // Aggregate that one prior session directly (targeted read), instead of a full-table
            // GROUP BY over every set of every session (`sessionVolumes()`, which feeds the FER-504 list).
            let prevWork: [SetEntry] = ((try? await store.setEntries(sessionId: prev.id)) ?? [])
                .filter { (s: SetEntry) in s.kind == .work && s.done }
            let prevVol: Double = prevWork.reduce(0.0) { (acc: Double, s: SetEntry) -> Double in
                let w: Double = s.weightKg ?? 0.0
                let r: Double = Double(s.reps ?? 0)
                return acc + (w * r)
            }
            let prevDur: Int = max(0, (prev.endTs ?? prev.startTs) - prev.startTs)
            comparison = .init(
                prevVolumeKg: prevVol,
                prevSetCount: prevWork.count,
                prevDurationS: prevDur)
        }

        // «Por ejercicio» (FER-716): one row per exercise with logged sets, in plan order, carrying the
        // session's top datum for its type and the trend against «la última vez» (nil = no reference).
        func trend(_ current: Double?, _ last: Double?) -> Int? {
            guard let c = current, let l = last else { return nil }
            return c > l ? 1 : (c < l ? -1 : 0)
        }
        let exerciseLines: [StrengthSummary.ExerciseLine] = session.runs
            .filter { !$0.skipped && $0.sets.contains(where: \.done) }
            .map { run in
                let done = run.sets.filter(\.done)
                switch run.type {
                case .weightReps, .bodyweight:
                    let top = done.map(\.weightKg).max()
                    return .init(name: run.name, setCount: done.count, topWeightKg: top,
                                 topTimeS: nil, topDistanceM: nil, trend: trend(top, run.lastWeightKg))
                case .time:
                    let top = done.compactMap(\.timeS).max()
                    return .init(name: run.name, setCount: done.count, topWeightKg: nil,
                                 topTimeS: top, topDistanceM: nil,
                                 trend: trend(top.map(Double.init), run.lastTimeS.map(Double.init)))
                case .distance:
                    let top = done.compactMap(\.distanceM).max()
                    return .init(name: run.name, setCount: done.count, topWeightKg: nil,
                                 topTimeS: nil, topDistanceM: top, trend: trend(top, run.lastDistanceM))
                }
            }

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

        return StrengthSummary(routineName: session.routineName,
                               endTs: record.endTs ?? record.startTs, durationS: durationS,
                               volumeKg: volumeKg, setCount: work.count, strain: record.strain,
                               avgHr: record.avgHr,
                               costBand: SessionRecoveryCost.cost(sessionStrain: record.strain)?.band,
                               costTomorrowPct: costTomorrowPct,
                               energyKcal: record.energyKcal, energySource: record.energySource,
                               prs: prs, muscles: Array(muscles.prefix(6)),
                               isFirstTime: prior.allSatisfy { $0.value.isEmpty },
                               comparison: comparison, exercises: exerciseLines)
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
        // FER-823: drop HR captured while paused from the session's scoring set — the band keeps streaming
        // for the live readout (`bpm`), but paused beats must not inflate strain/energy.
        guard let s = strengthSession, s.summary == nil, !s.paused, let hr = bpm else { return }
        s.hrSamples.append(HRSample(ts: Int(Date().timeIntervalSince1970), bpm: hr))
    }

    /// Append the current smoothed `bpm` to the active workout and extend its running strain. Called
    /// from `ingestHR` on every fresh sample; a no-op when no workout is running. FER-870: the average
    /// and strain extend from running state (`hrSum` + `strainState`) instead of re-summing and
    /// re-sorting the whole growing buffer each sample — same values, O(1)+O(300) per sample.
    private func captureWorkoutSample() {
        guard var w = activeWorkout, let hr = bpm else { return }
        let sample = HRSample(ts: Int(Date().timeIntervalSince1970), bpm: hr)
        w.samples.append(sample)
        w.peakHr = max(w.peakHr, hr)
        w.hrSum += hr
        w.avgHr = Int((Double(w.hrSum) / Double(w.samples.count)).rounded())
        if w.strainState == nil {
            w.strainState = StrainScorer.CumulativeStrainState(maxHR: Double(profile.hrMax), sex: profile.sex)
        }
        w.strainState?.extend(with: [sample])
        w.liveStrain = w.strainState?.strain ?? 0
        activeWorkout = w
    }

    // MARK: - Live Day Strain (in-progress day) — FER-650

    /// The ONE canonical derivation of the in-progress day's accumulated strain, shared by the Hoy tile,
    /// the Detalle hero and the intraday curve (FER-650). Reads today's HR (local civil day → now) and runs
    /// `StrainScorer.cumulativeStrain` with the SAME parameters the daily engine uses, so the curve's last
    /// point is — by construction — the value the tile and hero show:
    ///   • **HRmax:** the UNROUNDED effective max the engine uses (`hrMaxOverride ?? Tanaka(age)`), NOT the
    ///     rounded `profile.hrMax` (rounding is display-only) — the divergence FER-650 traced.
    ///   • **Resting HR:** today's single resting HR (`repo.today.restingHr`), one source for all surfaces.
    ///   • **Window:** local midnight → now, so just past midnight it reads TODAY's (near-empty) samples,
    ///     never yesterday's (preserves FER-341).
    /// Publishes `liveDayStrain` (= the last cumulative point) as a side effect so the tile stays in lockstep
    /// with the curve. Returns [] under the same guard as the daily score: no settled score for today yet
    /// (the engine hasn't acknowledged the civil day), too few readings, or invalid HRR. PAST days are never
    /// read here — this only ever scores today's window, so settled history is untouched.
    /// The user's effective HRmax: an explicit override, else Tanaka(age), else nil (unknown age).
    /// ONE definition shared by the strap live-strain path (`liveDayStrainCurve`) and the Apple
    /// estimated «Carga del día» (pushed to `repo.strainHRmax`), so the number never jumps band↔Apple
    /// for the same person on the same day (FER-883, /cso finding 1).
    var effectiveHRmax: Double? {
        profile.hrMaxOverride > 0
            ? Double(profile.hrMaxOverride)
            : (profile.age > 0 ? StrainScorer.tanakaHRmax(age: Double(profile.age)) : nil)
    }

    @discardableResult
    func liveDayStrainCurve() async -> [StrainScorer.CumulativeStrainPoint] {
        guard repo.today?.strain != nil else { liveDayStrain = nil; return [] }
        let startOfToday = Int(Calendar.current.startOfDay(for: Date()).timeIntervalSince1970)
        let nowTs = Int(Date().timeIntervalSince1970)
        let restHR = repo.today?.restingHr.map(Double.init) ?? StrainScorer.defaultRestingHR
        let effMax: Double? = effectiveHRmax
        let source = repo.dataSourceMode

        // FER-870: reuse the cached incremental state unless the civil day rolled over, the data source
        // switched, or a scoring parameter changed — any of which would make the batch recompute differ,
        // so we discard and re-seed from midnight. Otherwise we only ever fold the NEW samples.
        let cached = liveStrainState
        let reusable = cached.map {
            liveStrainDayStart == startOfToday && liveStrainSource == source
                && $0.hasSameParameters(bucketSeconds: 900, maxHR: effMax, restingHR: restHR,
                                        method: .edwards, sex: profile.sex,
                                        denominator: StrainScorer.strainDenominator)
        } ?? false
        let base = reusable ? cached! : StrainScorer.CumulativeStrainState(
            maxHR: effMax, restingHR: restHR, sex: profile.sex)
        if !reusable {
            liveStrainDayStart = startOfToday
            liveStrainSource = source
            liveStrainState = base   // publish the empty re-seed immediately so a stale day never lingers
        }

        // Only the samples newer than what we've already folded. On a fresh seed that's midnight → now.
        let from = (base.lastTs ?? (startOfToday - 1)) + 1
        let newSamples = await repo.hrSamples(from: from, to: nowTs, limit: 100_000)

        liveStrainGen &+= 1
        let gen = liveStrainGen
        // Fold OFF the main actor: the accumulate + O(300) median never touches the UI thread.
        let (extended, curve): (StrainScorer.CumulativeStrainState, [StrainScorer.CumulativeStrainPoint]) =
            await Task.detached(priority: .utility) {
                let next = base.extended(with: newSamples)
                return (next, next.curve)
            }.value

        // Commit only if we're still the newest fold (a newer flush that started while we were folding
        // reads from the same base and supersedes us — no double-count, no clobber).
        guard gen == liveStrainGen else { return curve }
        liveStrainState = extended
        liveDayStrain = curve.last?.strain
        return curve
    }

    /// Refresh only the published `liveDayStrain` value (drops the curve) — the tile's cheap path, called on
    /// each dashboard refresh / live-HR flush so the Hoy tile rises in lockstep with the Detalle curve.
    func refreshLiveDayStrain() async { _ = await liveDayStrainCurve() }

    /// The value the CURRENT day's strain shows on the Hoy/Cuerpo tiles: the live derivation when it's
    /// computed, else the settled `repo.today.strain` (before the first live pass, or too little activity).
    /// One accessor so both tiles share the exact same fallback (FER-650).
    var displayedDayStrain: Double? {
        liveDayStrain ?? repo.today?.strain ?? repo.estimatedStrain(repo.today?.day ?? Repository.localDayKey(Date()))
    }

    /// The in-progress day's intraday strain curve as chart points, with the local-midnight anchor prepended
    /// (so the line reads "from 00:00" even if the strap wasn't worn until later). The ONE builder both the
    /// Hoy and Cuerpo detail sheets draw, over `liveDayStrainCurve()` — its last point is the tile/hero value
    /// by construction (FER-650). [] when there's no score / too little activity today.
    func strainCurveTrendPoints() async -> [TrendPoint] {
        let curve = await liveDayStrainCurve()
        guard !curve.isEmpty else { return [] }
        let midnight = TrendPoint(date: Calendar.current.startOfDay(for: Date()), value: 0)
        return [midnight] + curve.map { TrendPoint(date: $0.date, value: $0.strain) }
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
            live.append(log: "Stress nudge: take a paced breath")
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

    /// Mirror the inactivity-reminder wrist buzz as a local notification, so the "time to move" nudge
    /// still surfaces on the phone if the wrist buzz is missed (FER-664). Called from the BLE offload
    /// hook after `SedentaryDetector` decided to buzz; `minutes` = the seated bout the detector reported.
    /// Delivery is authorized-only (no second system prompt), mirroring `IllnessNotifier`. Gated on the
    /// feature toggle so turning the reminder off silences the notification too. iOS-only.
    static func postInactivity(minutes: Int) {
        #if os(iOS)
        guard InactivityPrefs.isEnabled() else { return }
        let body = minutes > 0
            ? String(localized: "You've been seated about \(minutes) min. Time to move.")
            : String(localized: "Time to move: you've been seated a while.")
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }
            let content = UNMutableNotificationContent()
            content.title = String(localized: "Move reminder")
            content.body = body
            content.sound = .default
            // A fixed identifier means a fresh nudge replaces the prior one rather than stacking.
            // Re-fetch `.current()` inside the @Sendable completion instead of capturing the outer
            // (non-Sendable) instance — same singleton, no cross-actor capture warning.
            UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: "inactivity-nudge", content: content, trigger: nil))
        }
        #endif
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

    /// Illness/strain early-warning (FER-667): compare the last ~2 days against a ~28-day baseline
    /// (ending 3 days ago) for resting HR, HRV, skin-temp deviation and respiration, then hand the
    /// per-signal z-scores to `IllnessSignalEngine` — a 0–100 composite behind a ≥2-signal
    /// corroboration gate with EXPLICIT confounder suppression. A hangover / sauna / hard-training
    /// night (read from the journal) damps the score ×0.45 and never fires the banner, so the classic
    /// early-illness signature (RHR↑ + HRV↓ + skin-temp↑) only raises when a plainer explanation was
    /// ruled out. On-device only; APPROXIMATE — a heads-up to rest, not a diagnosis.
    ///
    /// The journal read is async, so the recompute runs in a task; a newer dashboard emission cancels
    /// the in-flight one (`illnessTask`) so two runs never write `healthAlert` out of order.
    private func evaluateIllness(_ days: [DailyMetric]) {
        illnessTask?.cancel()
        guard behavior.illnessWatch, days.count >= 14 else { healthAlert = nil; return }
        illnessTask = Task { [weak self] in
            guard let self else { return }
            let context = await self.illnessContext(days)
            guard !Task.isCancelled else { return }
            self.applyIllnessEvaluation(days, context: context)
        }
    }

    /// The journal QUESTIONS (verbatim catalog keys — never localised, see `JournalCatalogStore`)
    /// whose "yes" answer offers a plainer explanation than illness for an elevated night.
    private enum IllnessJournal {
        static let alcohol = "Did you drink any alcohol?"
        static let stress  = "Did you feel stressed?"
        static let sauna   = "Did you use a sauna?"
        static let sick    = "Did you feel sick or ill?"
    }

    /// Same-day behaviour context for the recent illness window, read from the journal (imported ∪
    /// native). A confounder answered "yes" on either of the last two nights suppresses the heads-up.
    /// `hardOrLateWorkout` is derived from a strain z-anomaly (a hard/late session elevates RHR and
    /// lowers HRV overnight just like early illness); `travelPhaseJump` stays false until the
    /// CircadianEngine (FER-671) can flag a body-clock jump.
    private func illnessContext(_ days: [DailyMetric]) async -> IllnessSignalEngine.Context {
        let recentKeys = Set(days.suffix(2).map(\.day))
        let yesQuestions = Set(
            await repo.journalEntries(days: 5)
                .filter { recentKeys.contains($0.day) && $0.answeredYes }
                .map(\.question))
        let recentStrain = days.suffix(2).compactMap(\.strain)
        let hardWorkout = !recentStrain.isEmpty && IllnessWatch.isAnomaly(
            recentMean: recentStrain.reduce(0, +) / Double(recentStrain.count),
            base: Array(days.suffix(31).dropLast(3)).compactMap(\.strain),
            higherIsWorse: true)
        return IllnessSignalEngine.Context(
            alcohol: yesQuestions.contains(IllnessJournal.alcohol),
            stress: yesQuestions.contains(IllnessJournal.stress),
            sauna: yesQuestions.contains(IllnessJournal.sauna),
            hardOrLateWorkout: hardWorkout,
            travelPhaseJump: false,
            alreadyUnwell: yesQuestions.contains(IllnessJournal.sick),
            baselineTrusted: true)   // gated to ≥14 nights at the call site
    }

    /// Score the recent window with `IllnessSignalEngine` and set the banner. Only a `.raised` level
    /// (clear multi-signal anomaly, no confounder) surfaces the alarming banner + notification; mild /
    /// suppressed / already-unwell / quiet stay silent — that suppression is the false-positive win.
    private func applyIllnessEvaluation(_ days: [DailyMetric], context: IllnessSignalEngine.Context) {
        let previous: String? = healthAlert
        func mean(_ vals: [Double]) -> Double? {
            if vals.isEmpty { return nil }
            let sum: Double = vals.reduce(0.0) { (acc: Double, v: Double) in acc + v }
            return sum / Double(vals.count)
        }
        // FER-543 / FER-641 / FER-882 / FER-884: the HRV and resting-HR terms score against a
        // SINGLE-SOURCE history, chosen by the data-source mode. In Combined / strap-only they use the
        // STRAP-ONLY history exactly as before (regression zero): Apple-only nights carry SDNN, not the
        // band's RMSSD (not interchangeable, no published conversion; Shaffer & Ginsberg 2017), AND their
        // resting HR is read from awake sedentary samples excluding sleep — ~10–13 bpm above the band's
        // sleep-nadir RHR (Fenland Study; Gonzales et al. 2023, PLoS One 18(5):e0285272) — so mixing either
        // into the band baseline contaminates it (FER-519). In Apple-only mode `strapDays` is EMPTY, which
        // would collapse illness to <2 signals and never fire; instead we score Apple's OWN RHR/SDNN against
        // an APPLE-ISOLATED baseline (`SourceLens.maskForBaseline(keep:.apple)`). A within-source z-score is
        // valid regardless of Apple's absolute RHR offset or SDNN≠RMSSD — it measures the deviation from the
        // user's own Apple norm, exactly as `AppleRecoveryEstimator` already scores Apple SDNN (FER-153).
        // Skin temp is likewise source-routed (FER-882: each instrument has its own absolute-°C baseline).
        // Respiration IS the same physical metric across sources (both measured during sleep, breaths/min)
        // and keeps the full merged history. `appleHealthDays == []` ⇒ identity (a strap-only user → no change).
        let strapDays: [DailyMetric] = IntelligenceEngine.strapOnlyHistory(days, appleHealthDays: repo.appleHealthDays)
        // FER-884: the source that feeds RHR/HRV/skin-temp — Apple only when the mode excludes the band.
        let signalSource: SourceLens.Source = (repo.dataSourceMode == .appleHealthOnly) ? .apple : .band
        // RHR/HRV history: strapDays byte-for-byte in Combined/strap-only; Apple-isolated in Apple-only.
        let vitalsDays: [DailyMetric] = signalSource == .apple
            ? SourceLens.maskForBaseline(days, keep: .apple, appleDays: repo.appleHealthDays)
            : strapDays

        // Each signal's illness-ward z-score is computed exactly as before (robust σ via IllnessWatch,
        // recent = last ~2 nights, base = the ~28 nights ending 3 days ago), then handed to the engine
        // which owns the corroboration + confounder logic. The es-MX phrase is rendered here, in the app
        // layer, so the copy stays localised; the engine only decides which phrases to surface.
        var inputs: IllnessSignalEngine.Inputs = IllnessSignalEngine.Inputs()
        var labels: [String: String] = [:]
        func read(_ key: String, _ kp: (DailyMetric) -> Double?, higherIsWorse: Bool,
                  from src: [DailyMetric], label: (_ recent: Double, _ base: Double) -> String)
        -> IllnessSignalEngine.SignalReading? {
            let recent: [DailyMetric] = Array(src.suffix(2))
            let base: [DailyMetric] = Array(src.suffix(31).dropLast(3))
            let recentVals: [Double] = recent.compactMap(kp)
            let baseVals: [Double] = base.compactMap(kp)
            guard let r: Double = mean(recentVals),
                  let dev = IllnessWatch.deviation(recentMean: r, base: baseVals, higherIsWorse: higherIsWorse)
            else { return nil }
            labels[key] = label(r, dev.baseMean)
            let z: Double = dev.z
            return IllnessSignalEngine.SignalReading(zIllnessward: z)
        }
        inputs.restingHR = read("restingHR", { (d: DailyMetric) -> Double? in d.restingHr.map(Double.init) },
                                higherIsWorse: true, from: vitalsDays) { (recent: Double, base: Double) -> String in
            let delta: Int = Int((recent - base).rounded())
            return String(localized: "resting HR +\(delta) bpm")
        }
        // HRV's percentage phrase needs a positive baseline; skip the whole term if the base mean is 0.
        let hrvBaseWindow: [Double] = Array(vitalsDays.suffix(31).dropLast(3)).compactMap { (d: DailyMetric) -> Double? in d.avgHrv }
        if let hrvBase: Double = mean(hrvBaseWindow), hrvBase > 0 {
            inputs.hrv = read("hrv", { (d: DailyMetric) -> Double? in d.avgHrv }, higherIsWorse: false, from: vitalsDays) {
                (recent: Double, base: Double) -> String in
                let pct: Int = Int(((1.0 - recent / base) * 100.0).rounded())
                return String(localized: "HRV −\(pct)%")
            }
        }
        // FER-882: skin temp Δ is source-specific — route through the same baseline lens.
        let skinTempDays: [DailyMetric] = SourceLens.maskForBaseline(days, keep: signalSource, appleDays: repo.appleHealthDays)
        inputs.skinTemp = read("skinTemp", { (d: DailyMetric) -> Double? in d.skinTempDevC }, higherIsWorse: true, from: skinTempDays) {
            (r: Double, _: Double) -> String in
            String(localized: "skin temp +\(String(format: "%.1f", r))°C")
        }
        inputs.respiration = read("respiration", { (d: DailyMetric) -> Double? in d.respRateBpm }, higherIsWorse: true, from: days) {
            (_: Double, _: Double) -> String in
            String(localized: "respiration up")
        }

        let result = IllnessSignalEngine.evaluate(inputs, context: context, firedLabels: labels)
        healthAlert = result.level == .raised
            ? String(localized: "Your body looks strained: \(result.firedSignals.joined(separator: ", ")). Consider taking it easy.")
            : nil
        // Banner transition (clear → raised): surface it as a system notification so the
        // early-warning reaches the user when the window is closed. IllnessNotifier rate-limits to
        // once per local day; the not-a-diagnosis hedge lives in its subtitle.
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
        case .appleHealth:
            appleHealthImportSummary = nil
            appleHealthImportFailed = false
            appleHealthImportProgress = nil
        }
    }

    /// Stores the completed import summary (and typed failure flag) on the matching source card.
    private func finishImport(_ source: DataSourceImportKind, summary: String, failed: Bool = false) {
        switch source {
        case .appleHealth:
            appleHealthImportSummary = summary
            appleHealthImportFailed = failed
            appleHealthImportProgress = nil
        }
        activeImportSource = nil
    }
}

#if DEBUG
extension AppModel {
    /// Instancia compartida para los `#Preview` (FER-981): construir `AppModel()` cuesta ~230 ms
    /// de type-check por sitio; con una sola estática se paga UNA vez en vez de en cada preview.
    static let preview = AppModel()
}
#endif
