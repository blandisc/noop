import SwiftUI
import StrandDesign
import Combine
import Observation
import BiometricStreams
import CenitStore
import StrandImport
import StrandAnalytics
import StrandTraining
#if canImport(UIKit)
import UIKit
#endif

/// Root app state: owns the on-device repository, profile, strength session, and Watch mirror.
/// Strap BLE ownership was amputated in Ola 2 (Apple-only).
@MainActor
// FER-984: `@Observable` (no `ObservableObject`) → SwiftUI rastrea lecturas por-propiedad.
// Sin `$` publishers: los pocos bindings (`$…strengthSheetPresented`) van por `@Bindable` en el consumidor.
@Observable final class AppModel {
    /// The live instance for App Intents (Shortcuts). Set in init(); `weak` so an intent fired while
    /// Cénit is closed sees nil and asks the user to open it. (#42)
    static weak var shared: AppModel?

    /// Shared device id for imported history / on-device store partition.
    let deviceId = "strap"
    /// Source id for imported Apple Health data (stored beside legacy strap rows for per-source pages + consensus).
    let appleDeviceId = "apple-health"
    /// Owns the rest Live Activity (FER-721): started/updated/ended from the guided session's rest state,
    /// and the bridge for its «+30 s»/«Saltar» lock-screen actions.
    let restActivity = RestActivityController()
    /// Read model over the on-device store (dashboard + detail screens).
    let repo: Repository
    /// User profile (age/sex/body/HR-max) for zones, calories, baselines.
    let profile = ProfileStore()
    /// Behaviour settings: double-tap action, wear automation, zone coaching, smart alarm, illness watch.
    let behavior = BehaviorStore()
    /// Inactivity reminder settings + its restart-safe de-dup state (FER-664).
    /// The Bucle's goal (metric + optional date) — a single user preference, UserDefaults-backed (FER-311).
    let goal = GoalStore()
    /// The user's barbell + owned plate denominations, for the session's «⛓ discos» calculator (FER-720).
    let plates = PlatesStore()
    /// Which data sources feed the dashboard + baseline (combined / WHOOP-only / Apple-Health-only) —
    /// a user preference; capture stays active in every mode (FER-484).
    let sources = SourceModeStore()

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
    /// FER-1003: the Apple Watch's own live heart rate during a mirrored strength session — replaces the
    /// band-sourced `bpm` now that there's no strap. nil with no watch mirroring / no reading yet.
    var watchBpm: Int?
    /// FER-226: HR samples admitted into the live strength session but not yet flushed to
    /// `CenitStore.appendStrengthHR` — drained every 30 samples by `ingestWatchPulse`, and once more (the
    /// remainder) at save. On a FAILED write the batch is left in place (not cleared) — the next flush
    /// (30 more samples, or the save-time drain) retries it; the (sessionId, ts) PK makes that retry a
    /// no-op for whatever DID already land.
    var pendingHrFlush: [HRSample] = []
    /// True while a flush `Task` is in flight — `ingestWatchPulse` only fires a new flush when this is
    /// false, so two overlapping flushes can never both read/trim `pendingHrFlush` (FER-226 round 2, D3:
    /// two `removeFirst(count)` calls racing against each other silently dropped un-flushed samples).
    var isFlushingHR = false
    /// The timestamp of the last watch pulse admitted into the current session — `StrengthHRIntake`'s
    /// repeated-timestamp guard, at the SAME second-truncated precision `accept` returns. Reset when the
    /// session changes.
    var lastAcceptedHrTs: Date?

    /// Session ids for which the watch already saved the real `HKWorkout`. The one-workout invariant
    /// gate (`WorkoutSaveGate`) reads this so the iPhone omits its own save. Ephemeral — the workout is
    /// already in HealthKit and idempotent by `externalUUID`, so it need not survive a relaunch.
    // AppModel-internal (split D1)
    var watchSavedSessionIds: Set<String> = []
    /// Session ids the watch declined to save (no permission / error) — the iPhone then saves. (FER-740)
    // AppModel-internal (split D1)
    var watchDeclinedSessionIds: Set<String> = []

    /// Timestamps of moments marked via a double-tap (persisted).
    var moments: [Date] = []

    /// The guided strength session in progress (FER-347), or nil. Lives here (global) so closing its sheet
    /// or switching tabs never loses it — the Train hub re-presents it. Saved as a `StrengthSession` + its
    /// `SetEntry` rows on Finish.
    var strengthSession: StrengthSessionModel? {
        didSet {
            bindRestActivity()
            // FER-96: a session ending is when the watch's resting face becomes relevant again — refresh
            // its verdict so it doesn't keep showing whatever was current when the session STARTED.
            if strengthSession == nil, oldValue != nil {
                Task { [weak self] in await self?.pushWatchIdleContext() }
            }
        }
    }
    /// Subscription to the active session's changes — drives the rest Live Activity's reconcile loop.
    // AppModel-internal (split D1)
    var restActivityCancellable: AnyCancellable?
    /// Debounces the in-progress-session snapshot writes (FER-798): a burst of keypad edits collapses to
    /// one store write; a phase change (rest start/end) forces an immediate flush.
    // AppModel-internal (split D1)
    var persistSessionTask: Task<Void, Never>?
    /// The session phase last seen by the persist observer — a change vs. this triggers an immediate flush.
    // AppModel-internal (split D1)
    var lastObservedStrengthPhase: StrengthSessionModel.Phase?
    /// Called at launch when there is NO recoverable in-progress strength session (FER-798). FER-806 installs
    /// this to end any orphaned Live Activity; nil here — this issue only leaves the hook.
    var onNoRecoverableStrengthSession: (() -> Void)?
    /// FER-810: the last plan signature mirrored to the watch, so the rotor is pushed only when its visible
    /// state changes (a set done / current advanced), not on every HR tick. Reset when the session rebinds.
    // AppModel-internal (split D1)
    var lastPlanSignature: String?
    /// Whether the guided-session sheet is currently shown. False while a session runs but the sheet is
    /// dismissed (the hub then offers «Resume»). Set true on start/resume, false on swipe-dismiss/finish.
    var strengthSheetPresented = false
    /// Illness/strain early-warning (recent RHR up + HRV down + skin-temp up vs baseline). nil = clear.
    var healthAlert: String?

    /// Import source currently writing to the local store, if any.
    // AppModel-internal (split D1)
    var activeImportSource: DataSourceImportKind?
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
    // AppModel-internal (split D1)
    var importTask: Task<Void, Never>?

    /// The illness heads-up recompute (FER-667), retained so a newer dashboard emission cancels the
    /// in-flight one — its journal read is async, so two overlapping runs could otherwise write
    /// `healthAlert` out of order.
    // AppModel-internal (split D1)
    var illnessTask: Task<Void, Never>?

    /// The periodic on-device analysis loop, retained so it can be cancelled. It used to be a
    /// fire-and-forget `Task` that lived for the whole process, re-reading ~21 days × 8 streams every
    /// 15 min and competing with BLE keep-alive / backfill / HR sinks on the main actor even while the
    /// app sat in the background. Now it's cancelled on background and resumed on foreground, and each
    /// tick skips the heavy pass while a backfill/import is writing (FER-177).
    // AppModel-internal (split D1)
    var analysisTask: Task<Void, Never>?

    /// True while any data-source import is writing to the local store.
    var hasActiveImport: Bool { activeImportSource != nil }

    private var hrCancellables = Set<AnyCancellable>()

    init() {
        self.repo = Repository(deviceId: "strap")
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

        // FER-114 · el aviso matutino se re-arma con cada lectura nueva del motor. El texto no
        // cambia nunca (es un recordatorio, no la entrega de la lectura: el texto de una
        // notificación se congela al programarla y Cénit solo calcula con la app abierta), pero
        // sí cambia si HAY algo que recordar: `MorningReadingScheduler` decide si se programa.
        //
        // OJO con las dos trampas de este `.sink`, que el scheduler ya absorbe (ver `reschedule`):
        //   · `$dashboard` es `@Published`, así que esto dispara DE INMEDIATO con el valor de
        //     `init` (`preparedness == nil`). Eso no es «no hay aviso que dar», es «todavía no sé»,
        //     y por eso una publicación sin lectura ya no cancela lo pendiente.
        //   · dos publicaciones seguidas lanzan dos tasks: el scheduler las pone EN COLA para que
        //     el `cancelAll()` de la vieja no aterrice después de los `add` de la nueva.
        repo.$dashboard.map(\.preparedness)
            .removeDuplicates()
            .sink { (prep: Preparedness.Read?) in
                Task { await MorningReadingScheduler.reschedule(prep: prep) }
            }
            .store(in: &hrCancellables)

        // FER-95 · E14 — «fuera de la app»: los dos widgets de pantalla de inicio + el recordatorio del
        // día que toca entrenar se re-arman en cada publicación del dashboard, igual que el aviso
        // matutino arriba. No hay `removeDuplicates` aquí a propósito: a diferencia del aviso (donde el
        // único insumo que le importa es `preparedness`), el snapshot también depende del split/rutinas
        // (que `$dashboard` no versiona) y de si hay sesión viva — una publicación repetida es un
        // re-cálculo barato (una lectura de store), no un efecto duplicado.
        repo.$dashboard
            .sink { [weak self] _ in
                guard let self else { return }
                Task { await self.publishTrainOutsideApp() }
            }
            .store(in: &hrCancellables)

        moments = (UserDefaults.standard.array(forKey: "moments") as? [Double] ?? [])
            .map { Date(timeIntervalSince1970: $0) }

        AppModel.shared = self   // publish for App Intents (Shortcuts) — see the static above (#42)

        #if DEBUG
        // Screenshot fixtures (UI test): seed a synthetic readiness state and skip the production
        // refresh/analyze loop entirely, so the seeded dashboard isn't immediately overwritten by a
        // real (empty) store load. Gated on the `-noop.fixture primed|strained` launch argument; an
        // absent/`empty` argument falls through to the normal launch path below. `activeState()` is
        // hard-gated to the simulator, so this never seeds a physical device (see ScreenshotFixtures).
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

        // Run the launch analysis sequence (first-paint → full refresh → migrations; band mode also
        // keeps a periodic recompute). Launch-time only — foreground returns use
        // `resumeForegroundAnalysis()` so the launch refresh isn't re-run each activation (FER-1024).
        startAnalysis()
    }

    /// The exercise whose thumbnail is currently staged in the App Group, and the resulting file name —
    /// so a rest snapshot copies the JPG only when the focused exercise changes, not on every reconcile.
    // AppModel-internal (split D1)
    var preparedRestThumb: (exerciseId: String, name: String?)?

    /// FER-810: «Ver recibo en iPhone» on the wrist summary → resolve the persisted session and publish its
    /// history-detail route; `RootTabView` switches to Entrenar and pushes `WorkoutSessionDetailScreen`. The
    /// route's `routineName` is a fallback (the detail's own `load()` resolves the real name from the store).
    var pendingReceiptRoute: WorkoutSessionRoute?

    /// FER-742: ask the bridge to recompute paired-watch availability (drives the Settings row's states).
    func refreshWatchPairing() { mirroringBridge?.refreshPairingState() }
    /// FER-742: «Reintentar» from the strength sheet's watch status line.
    func retryWatchMirroring() { mirroringBridge?.retryMirroring() }

    /// Everything `endStrengthSession` built for the durable save, kept so a failed save can retry
    /// without recomputing duration/energy or re-ordering the watch. (FER-969, X-01)
    // AppModel-internal (split D1)
    struct PendingStrengthSave {
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
    // AppModel-internal (split D1)
    var pendingStrengthSave: PendingStrengthSave?

    // MARK: - Day Strain display (settled only — live fold retired with the band, Ola 2)

    /// The user's effective HRmax: an explicit override, else Tanaka(age), else nil (unknown age).
    /// ONE definition shared by the Apple estimated «Carga del día» (pushed to `repo.strainHRmax`),
    /// so the number never jumps for the same person on the same day (FER-883, /cso finding 1).
    var effectiveHRmax: Double? {
        profile.hrMaxOverride > 0
            ? Double(profile.hrMaxOverride)
            : (profile.age > 0 ? StrainScorer.tanakaHRmax(age: Double(profile.age)) : nil)
    }

    /// The value the CURRENT day's strain shows on the Hoy/Cuerpo tiles: settled daily score only
    /// (live band-fold removed in Ola 2).
    var displayedDayStrain: Double? {
        repo.today?.strain ?? repo.estimatedStrain(repo.today?.day ?? Repository.localDayKey(Date()))
    }

    /// Cleared band-era HR smoother; kept as a no-op so strength start/end call sites still compile.
    func resetSmoothing() {}

    /// Realtime HR consumer ref-count (band stream removed in Ola 2). Kept so strength start/end call sites still compile.
    private var realtimeConsumers: Set<String> = []

    func acquireRealtimeHR(_ consumer: String) {
        realtimeConsumers.insert(consumer)
        resetSmoothing()
    }

    func releaseRealtimeHR(_ consumer: String) {
        _ = realtimeConsumers.remove(consumer)
    }

    /// Phone haptics for timer / rest / moment cues (replaces the retired strap motor, FER-1003).
    /// `loops` ≥ 3 use a heavier impact; ≥ 5 also fire a success notification for the long completion cue.
    func buzz(loops: UInt8 = 2) {
        #if canImport(UIKit)
        let count = max(1, min(Int(loops), 8))
        if count >= 5 {
            let note = UINotificationFeedbackGenerator()
            note.prepare()
            note.notificationOccurred(.success)
        }
        let style: UIImpactFeedbackGenerator.FeedbackStyle = count >= 3 ? .heavy : .medium
        let impact = UIImpactFeedbackGenerator(style: style)
        impact.prepare()
        for i in 0..<count {
            if i == 0 {
                impact.impactOccurred(intensity: 1.0)
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12 * Double(i)) {
                    impact.impactOccurred(intensity: 1.0)
                }
            }
        }
        #endif
    }

    /// Pattern was a strap motor id; on phone, loops alone drive the haptic.
    func buzz(pattern: UInt8, loops: UInt8 = 1) {
        _ = pattern
        buzz(loops: loops)
    }

    // MARK: - Moments

    /// Record a "moment" with a confirming phone haptic. `at` defaults to now; a moment
    /// queued by an App Intent passes the instant the user actually asked for it.
    func markMoment(at date: Date = Date()) {
        moments.append(date)
        moments.sort()
        if moments.count > 500 { moments.removeFirst(moments.count - 500) }
        UserDefaults.standard.set(moments.map(\.timeIntervalSince1970), forKey: "moments")
        buzz(loops: 1)
    }

    /// The journal QUESTIONS (verbatim catalog keys — never localised, see `JournalCatalogStore`)
    /// whose "yes" answer offers a plainer explanation than illness for an elevated night.
    // AppModel-internal (split D1)
    enum IllnessJournal {
        static let alcohol = "Did you drink any alcohol?"
        static let stress  = "Did you feel stressed?"
        static let sauna   = "Did you use a sauna?"
        static let sick    = "Did you feel sick or ill?"
    }

}

#if DEBUG
extension AppModel {
    /// Instancia compartida para los `#Preview` (FER-981): construir `AppModel()` cuesta ~230 ms
    /// de type-check por sitio; con una sola estática se paga UNA vez en vez de en cada preview.
    static let preview = AppModel()
}
#endif
