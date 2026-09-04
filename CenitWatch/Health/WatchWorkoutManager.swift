import Foundation
import HealthKit
import WatchConnectivity
import StrandTraining   // C1 (FER-361): the standalone logger mutates the real domain types (Decision A)
import os

/// watchOS side of the strength-session **workout mirroring** (FER-740). The wrist runs the *real*
/// `HKWorkoutSession` (started when the iPhone wakes the app via `startWatchApp`), mirrors it to the
/// iPhone, records HR/energy from the watch's own sensors, and on end saves exactly one
/// `HKWorkout(.traditionalStrengthTraining)` — stamped with the shared `externalUUID` so it can never
/// duplicate the iPhone's write. There is no database on the watch; state crosses the pairing over the
/// HealthKit mirror channel and `WatchConnectivity`.
///
/// FER-740 laid the session/mirror/save plumbing (unchanged below). FER-741 adds the **presentation
/// layer** the watch face observes — `phase`, the rest-end haptic scheduler, the end-of-session
/// `summary`, iPhone reachability and Health-access state, and a wrist-initiated end — without touching
/// the save invariant.
@MainActor
final class WatchWorkoutManager: NSObject, ObservableObject {
    static let shared = WatchWorkoutManager()

    /// The coarse screen the watch face renders (FER-741). Rest vs. no-rest and the degraded overlays
    /// (no reading / no permission / no iPhone) are derived from the finer published state below.
    enum Phase: Equatable {
        /// No session — the waiting face, or the «couldn't connect» variant after a failed wake.
        case idle(couldNotConnect: Bool)
        /// Woken by the iPhone; the session hasn't started yet. Falls to `.idle(couldNotConnect: true)`
        /// after 15s with no session.
        case connecting
        /// A session is running (the live face — pulse, rest countdown, degraded overlays).
        case running
        /// The session ended — the minimal summary card.
        case summary
        /// FER-96: `HKWorkoutSession(healthStore:configuration:)` (or the mirror/collection start that
        /// follows it) threw. Distinct from `idle(couldNotConnect: true)` on purpose — that one is the
        /// generic 15s watchdog for a wake that never produced ANY session (could be a dropped message,
        /// could be anything); this one fires immediately and says the actual reason: a Health problem,
        /// not a connectivity one. Both used to be a silent `log.error` with no observable state.
        case healthKitFailure
    }

    // MARK: Live values the UI observes
    @Published var phase: Phase = .idle(couldNotConnect: false)
    @Published var startDate: Date?
    @Published var heartRate: Int = 0
    @Published var rest: RestActivitySnapshot?
    /// FER-809: the capture context between rests — which set is up (N/M), exercise and «weight × reps» —
    /// so the live face shows «qué toca», not a bare pulse. nil until the first `.capture` arrives.
    @Published var capture: WorkoutCaptureSnapshot?
    /// FER-810: the routine plan for the read-only rotor page (done / current / pending + N/M per exercise).
    @Published var plan: WorkoutPlanSnapshot?
    /// FER-811: the profile's max heart rate (mirrored from the iPhone), for the effort-zone label next to
    /// the pulse. nil until known / when unreliable → the zone is omitted, never guessed.
    @Published var hrMax: Int?
    @Published var sessionActive = false
    /// The routine's display name, adopted from the rest snapshots the iPhone sends.
    @Published var routineName: String = ""
    /// Whether the paired iPhone is currently reachable. The face shows a quiet «no connection» line
    /// when false; heart rate and elapsed time keep running regardless.
    @Published var iPhoneReachable = true
    /// True when Health sharing is denied on the wrist → the face warns and drops to «--», but the
    /// session (timer + rests + haptics) keeps serving. Never blocks.
    @Published var healthAccessDenied = false
    /// FER-96: `requestAuthorization()` itself threw at launch (not a plain denial — an actual system
    /// error, e.g. Health data unavailable on this device). Surfaced on the idle face; used to be a
    /// silent `log.error` that left the person with no reading and no explanation.
    @Published var authorizationRequestFailed = false
    /// FER-96: today's routine + the already-resolved daily verdict, for the idle face — pushed by the
    /// iPhone over `updateApplicationContext`, adopted outside any active session.
    @Published var idleContext = WatchIdleContext()
    /// True for the ~3s «Descanso terminado» transition after a rest naturally expires.
    @Published var restEndedBanner = false
    /// The end-of-session summary, set when the session ends with something saved.
    @Published var summary: WatchSessionSummary?

    /// C1 (FER-361): the current session's full structural model — every run/set, however we got it.
    /// Adopted verbatim from `.sessionModel` while a mirrored (iPhone-driven) session is live, or
    /// authored + mutated locally while `isStandalone`. Distinct from `rest`/`capture`/`plan`, which keep
    /// driving the existing narrow mirrored faces unchanged; B2's standalone logger reads/mutates THIS.
    /// nil whenever there's no session (idle, or between end and the next start).
    @Published private(set) var sessionSnapshot: StrengthSessionSnapshot?
    /// True only while the WATCH itself is the logger (a local start via `startTodayFromWrist()` while
    /// the iPhone was unreachable) — false for an iPhone-driven mirrored session, even though
    /// `sessionSnapshot` may be populated in both cases. Gates `logStandaloneSet`/`addStandaloneDrop`/
    /// `endStandaloneSession`, and tells B2 which face/copy applies.
    @Published private(set) var isStandalone = false
    /// Whether a cached seed (today's plan, pushed by the iPhone as `.sessionModel`) exists to start a
    /// standalone session from if the iPhone is unreachable. B2 uses this to gate/label the idle face's
    /// «Empezar» before the person even taps it.
    @Published private(set) var hasSeed = false
    /// C1 (FER-361): `startTodayFromWrist()` was tapped with the iPhone unreachable AND no cached seed —
    /// the one case where the tap truly does nothing. B2 shows «Empieza en tu iPhone» from this rather
    /// than `Phase` (nothing failed to connect; there was simply nothing to start from). Cleared on the
    /// next start attempt that isn't this same dead end.
    @Published private(set) var startNeedsPhone = false

    private let healthStore = HKHealthStore()
    private let log = Logger(subsystem: "com.noopapp.noop.watch", category: "WatchWorkout")

    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    /// The shared session identity, injected by the iPhone's `.start`. Drives the idempotency key.
    private var sessionId: String?
    private var externalUUID: String?
    /// C1 (FER-361): the last seed the iPhone pushed (`.sessionModel`), mirrored in memory from
    /// `WatchSessionStore` so `startTodayFromWrist()` can decide synchronously whether a local start is
    /// possible. The store itself, not this cache, is the durable source of truth across relaunches.
    private var cachedSeed: StrengthSessionSnapshot?

    /// Fires the rest-end haptic locally at `restEndsAt` (survives an iPhone disconnect). Cancelled if
    /// the iPhone leaves the rest early (user returned to the set) → no haptic.
    private var restEndTask: Task<Void, Never>?
    /// Falls back to «couldn't connect» if a wake never produces a session within 15s.
    private var connectWatchdog: Task<Void, Never>?

    private let typesToShare: Set<HKSampleType> = [HKQuantityType.workoutType(),
                                                   HKQuantityType(.activeEnergyBurned)]
    private let typesToRead: Set<HKObjectType> = [HKQuantityType(.heartRate),
                                                  HKQuantityType(.activeEnergyBurned),
                                                  HKQuantityType.workoutType()]

    override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
        Task { await self.loadCachedSeed() }   // C1 (FER-361): a seed from a prior launch survives here
    }

    /// C1 (FER-361): prime `cachedSeed`/`hasSeed` from `WatchSessionStore` at launch, so a seed cached
    /// before the app last quit is available to `startTodayFromWrist()` immediately — not only after the
    /// iPhone re-pushes `.sessionModel` this session.
    private func loadCachedSeed() async {
        guard let seed = await WatchSessionStore.shared.loadSeed() else { return }
        cachedSeed = seed
        hasSeed = true
    }

    /// Request HealthKit share/read up front (the watch has no in-app rationale screen).
    func requestAuthorization() {
        Task {
            do {
                try await healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead)
                authorizationRequestFailed = false
            } catch {
                // FER-96: this used to be a silent `log.error` — the person saw no reading, no saved
                // workout, and nothing telling them why. Surfaced on the idle face instead.
                log.error("Auth failed: \(error.localizedDescription, privacy: .public)")
                authorizationRequestFailed = true
            }
            self.refreshHealthAccess()
        }
    }

    /// Whether Health *sharing* is denied — the one authorization the wrist can read (read permission is
    /// deliberately opaque). Drives the no-permission face; without share access there is no saved
    /// workout, and heart rate falls back to «--».
    private func refreshHealthAccess() {
        healthAccessDenied = healthStore.authorizationStatus(for: HKObjectType.workoutType()) == .sharingDenied
    }

    // MARK: - Session lifecycle

    /// Called from the `WKApplicationDelegate` when the iPhone wakes the app with a workout config. Marks
    /// the brief «Conectando» window and arms the 15s watchdog before starting the real session.
    ///
    /// FER-96: every throwing step below used to propagate to a `catch { log.error(...) }` in the
    /// caller that touched no `@Published` state — a failed `HKWorkoutSession` init left the face stuck
    /// on «Conectando» for the full 15s watchdog, indistinguishable from a simply-dropped wake. Now any
    /// failure here flips `phase` immediately, with its own text.
    func start(configuration: HKWorkoutConfiguration) async throws {
        beginConnecting()
        try await startHealthKitSession(configuration: configuration, mirrorToCompanion: true)
    }

    /// The actual `HKWorkoutSession`/builder setup, shared by the iPhone-driven path above and the
    /// standalone path below (C1 · FER-361) — factored out so the two can never drift on the delicate
    /// HealthKit choreography (delegate wiring, data source, `externalUUID`-bearing finish downstream).
    /// `mirrorToCompanion` is the only real difference: a standalone start already knows the phone is
    /// unreachable (that's why it's standalone), so it skips `startMirroringToCompanionDevice()` rather
    /// than waiting on a call that can only fail or stall.
    private func startHealthKitSession(configuration: HKWorkoutConfiguration,
                                       mirrorToCompanion: Bool) async throws {
        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            session.delegate = self
            builder.delegate = self
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore,
                                                         workoutConfiguration: configuration)
            self.session = session
            self.builder = builder
            if mirrorToCompanion { try await session.startMirroringToCompanionDevice() }
            let start = Date()
            session.startActivity(with: start)
            try await builder.beginCollection(at: start)
            startDate = start
            sessionActive = true
            enterRunning()
            refreshHealthAccess()
            WatchHaptic.sessionStart.play()
            log.log("Watch workout started (mirrored: \(mirrorToCompanion))")
        } catch {
            log.error("Failed to start workout: \(error.localizedDescription, privacy: .public)")
            failToStart()
            throw error
        }
    }

    /// The same configuration the iPhone requests when it wakes the watch
    /// (`WorkoutMirroringBridge.attemptMirror`) — traditional strength training, default location — so a
    /// standalone `HKWorkout` reads identically to a mirrored one. A fresh instance per call, matching
    /// how the iPhone side builds it (HealthKit owns the object once handed off).
    private static func strengthWorkoutConfiguration() -> HKWorkoutConfiguration {
        let config = HKWorkoutConfiguration()
        config.activityType = .traditionalStrengthTraining
        return config
    }

    /// Local-start branch of `startTodayFromWrist()` (C1 · FER-361): the iPhone is unreachable but a
    /// cached seed exists — turn it into a fresh plan (`asTemplate`, so the id/startTs never collide with
    /// the seed itself or an earlier local start on the same plan), publish it as `sessionSnapshot` +
    /// `isStandalone` for the UI (B2), persist it via `WatchSessionStore` (debounced like every other
    /// in-progress edit — a crash within that ~1s window loses the identity, same risk as losing the last
    /// edit mid-session), and start the real `HKWorkoutSession` with no companion-mirroring attempt.
    private func startStandalone(from seed: StrengthSessionSnapshot) async {
        guard sessionId == nil, !sessionActive else { return }
        let template = seed.asTemplate(newId: UUID().uuidString, nowTs: Int(Date().timeIntervalSince1970))
        sessionId = template.id
        externalUUID = WorkoutMirrorKey.externalUUID(for: template.id)
        if !template.routineName.isEmpty { routineName = template.routineName }
        isStandalone = true
        sessionSnapshot = template
        await WatchSessionStore.shared.saveInProgress(template)
        do {
            try await startHealthKitSession(configuration: Self.strengthWorkoutConfiguration(),
                                            mirrorToCompanion: false)
        } catch {
            // `startHealthKitSession` already flipped `phase` to `.healthKitFailure` and logged — undo
            // the published/persisted state so a retry starts clean instead of finding a dead identity.
            isStandalone = false
            sessionSnapshot = nil
            sessionId = nil
            externalUUID = nil
            await WatchSessionStore.shared.clearInProgress()
        }
    }

    /// FER-96: HealthKit refused to start the mirrored session — an immediate, distinguishable failure,
    /// never the generic 15s «couldn't connect» watchdog (`beginConnecting`'s fallback, for a wake that
    /// produced no session at all — could be anything). This one fires now and says why.
    private func failToStart() {
        connectWatchdog?.cancel(); connectWatchdog = nil
        session = nil
        builder = nil
        phase = .healthKitFailure
    }

    /// Enter the brief «Conectando» state and arm the watchdog. If no session materializes in 15s (the
    /// wake was declined / dropped), fall to the idle face with the «couldn't connect» line.
    private func beginConnecting() {
        phase = .connecting
        connectWatchdog?.cancel()
        connectWatchdog = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            guard let self, !Task.isCancelled else { return }
            if case .connecting = self.phase { self.phase = .idle(couldNotConnect: true) }
        }
    }

    private func enterRunning() {
        connectWatchdog?.cancel()
        connectWatchdog = nil
        phase = .running
    }

    /// Re-adopt a session that outlived the app (killed / rebooted mid-session). Called at launch. The
    /// user lands back on the running face (state 3/4), not a special screen.
    func recoverIfNeeded() {
        Task { await self.restoreStandaloneIfNeeded() }
        healthStore.recoverActiveWorkoutSession { [weak self] recovered, error in
            guard let self else { return }
            if let error { self.log.error("Recover failed: \(error.localizedDescription, privacy: .public)"); return }
            guard let recovered else { return }
            Task { @MainActor in
                let builder = recovered.associatedWorkoutBuilder()
                recovered.delegate = self
                builder.delegate = self
                self.session = recovered
                self.builder = builder
                self.sessionActive = recovered.state.isActive
                self.startDate = recovered.startDate
                self.refreshHealthAccess()
                if recovered.state.isActive { self.phase = .running }
                self.log.log("Recovered active watch session")
            }
        }
    }

    /// C1 (FER-361): re-adopt a standalone session's LOGGED DATA after the watch relaunches mid-session —
    /// sibling of the block above, which re-adopts the raw `HKWorkoutSession`/builder. Independent of
    /// whether that recovery succeeds: even with a lost HK session, `endStandaloneSession()` can still
    /// emit one more `.syncSnapshot` from whatever was logged before the relaunch.
    private func restoreStandaloneIfNeeded() async {
        guard let snapshot = await WatchSessionStore.shared.loadInProgress() else { return }
        guard sessionId == nil else { return }   // a mirrored session already claimed identity first
        isStandalone = true
        sessionSnapshot = snapshot
        sessionId = snapshot.id
        externalUUID = WorkoutMirrorKey.externalUUID(for: snapshot.id)
        if !snapshot.routineName.isEmpty { routineName = snapshot.routineName }
        log.log("Restored standalone session from disk")
    }

    /// End the session from the wrist (FER-741). Reuses the existing `.end` contract: the iPhone's bridge
    /// reads a watch-sent `.end` as «ended from the wrist» (`onWatchEndedSession`) and closes its own
    /// session — no new message type needed. We also end locally so the summary appears immediately.
    func endFromWrist() {
        guard let sid = sessionId else { return }
        let ext = externalUUID ?? WorkoutMirrorKey.externalUUID(for: sid)
        let now = Date()
        send(.end(sessionId: sid, endedAt: now, save: true, externalUUID: ext))
        Task { await endSession(endedAt: now, save: true) }
    }

    /// Dismiss the summary card (via «Listo», or auto after ~30s when saved) → back to the idle face.
    func dismissSummary() {
        summary = nil
        phase = .idle(couldNotConnect: false)
    }

    /// End the session on the iPhone's order (`.end`) OR from `endStandaloneSession()`. Saves the real
    /// workout when `save`, stamped with the shared `externalUUID`, then acks `watchDidSaveWorkout` so
    /// the iPhone omits its estimate.
    ///
    /// C1 (FER-361): when the session being closed is standalone, this ALSO reconciles it back to the
    /// iPhone via `.syncSnapshot` — the `defer` below fires it exactly once on every exit path (even the
    /// early bail-outs, with whatever `avgHr`/`kcal` were actually measured, `nil` if we never got that
    /// far), using state captured before `cleanup()` clears it.
    private func endSession(endedAt: Date, save: Bool) async {
        let standaloneToSync = isStandalone ? sessionSnapshot : nil
        var finalStats: (hr: Int?, kcal: Int?)?
        defer {
            if let standaloneToSync { syncStandaloneSnapshot(standaloneToSync, avgHr: finalStats?.hr,
                                                             energyKcal: finalStats?.kcal) }
            cleanup()
        }
        restEndTask?.cancel()
        guard let session, let builder else { sessionActive = false; return }
        let sid = sessionId ?? ""
        let ext = externalUUID ?? WorkoutMirrorKey.externalUUID(for: sid)
        guard save else { session.end(); return }   // discarded session → end without a workout or summary
        // No workout-share permission on the wrist → let the iPhone save its estimate instead.
        guard healthStore.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized else {
            send(.watchWillNotSave(sessionId: sid, reason: .noPermission))
            session.end(); return
        }
        do {
            try await builder.endCollection(at: endedAt)
            let stats = summaryStatistics(from: builder, endedAt: endedAt)
            finalStats = (stats.hr, stats.kcal)
            try await builder.addMetadata([HKMetadataKeyExternalUUID: ext])
            let workout = try await builder.finishWorkout()
            session.end()
            if workout != nil {
                send(.watchDidSaveWorkout(sessionId: sid, externalUUID: ext))
                presentSummary(stats, saveState: .saved)
            } else {
                send(.watchWillNotSave(sessionId: sid, reason: .sessionError))
                presentSummary(stats, saveState: .failed)
            }
        } catch {
            log.error("Finish failed: \(error.localizedDescription, privacy: .public)")
            send(.watchWillNotSave(sessionId: sid, reason: .sessionError))
            let stats = summaryStatistics(from: builder, endedAt: endedAt)
            finalStats = (stats.hr, stats.kcal)
            session.end()
            presentSummary(stats, saveState: .failed)
        }
    }

    /// C1 (FER-361): the authoritative reconciliation backup for a standalone session — sent over the
    /// DURABLE queue (`transferUserInfo`) directly, never the best-effort live channel `send(_:)` prefers,
    /// because this is exactly the message that must survive the iPhone being unreachable right now (the
    /// reason the session ran standalone at all) and land whenever it reconnects. `energyKcal` travels as
    /// `Double` (the wire's shape); `summaryStatistics` already rounds to `Int` for the wrist's own card.
    private func syncStandaloneSnapshot(_ snapshot: StrengthSessionSnapshot, avgHr: Int?, energyKcal: Int?) {
        guard let data = WorkoutMirrorMessage.syncSnapshot(snapshot: snapshot, avgHr: avgHr,
                                                           energyKcal: energyKcal.map(Double.init)).encoded()
        else { return }
        transfer(data)
    }

    /// Read average heart rate + active energy off the builder for the summary card. Best-effort: any
    /// missing statistic is `nil` and the card omits it.
    private func summaryStatistics(from builder: HKLiveWorkoutBuilder,
                                   endedAt: Date) -> (duration: TimeInterval, hr: Int?, kcal: Int?) {
        let bpmUnit = HKUnit.count().unitDivided(by: .minute())
        let hr = builder.statistics(for: HKQuantityType(.heartRate))?.averageQuantity()?.doubleValue(for: bpmUnit)
        let kcal = builder.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie())
        let duration = startDate.map { endedAt.timeIntervalSince($0) } ?? 0
        return (duration, hr.map { Int($0.rounded()) }, kcal.map { Int($0.rounded()) })
    }

    private func presentSummary(_ stats: (duration: TimeInterval, hr: Int?, kcal: Int?),
                                saveState: WatchSessionSummary.SaveState) {
        summary = WatchSessionSummary(duration: stats.duration, averageHeartRate: stats.hr,
                                      activeEnergyKcal: stats.kcal, saveState: saveState)
        phase = .summary
        WatchHaptic.sessionEnded.play()
        // A saved card may clear itself after ~30s; a failed one waits for «Listo».
        guard saveState == .saved else { return }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            guard let self, !Task.isCancelled else { return }
            if case .summary = self.phase { self.dismissSummary() }
        }
    }

    private func cleanup() {
        session = nil
        builder = nil
        sessionActive = false
        rest = nil
        capture = nil
        plan = nil
        hrMax = nil
        startDate = nil
        restEndTask?.cancel()
        restEndTask = nil
        sessionSnapshot = nil
        if isStandalone {
            isStandalone = false
            Task { await WatchSessionStore.shared.clearInProgress() }
        }
    }

    // MARK: - Rest window (FER-741)

    /// Arm the local rest-end haptic for `endsAt`. The countdown and its haptic run on the wrist, so they
    /// survive an iPhone disconnect. Re-arming (a rest extended by the iPhone) cancels the prior timer.
    private func scheduleRestEnd(at endsAt: Date) {
        restEndTask?.cancel()
        restEndTask = Task { [weak self] in
            let delay = endsAt.timeIntervalSinceNow
            if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            guard !Task.isCancelled else { return }
            await self?.fireRestEnded()
        }
    }

    /// The rest window expired on its own → the primary haptic + the ~3s «Descanso terminado» transition,
    /// then back to the live face. Guarded so a late/cancelled timer can't fire twice.
    private func fireRestEnded() async {
        guard rest != nil else { return }
        rest = nil
        restEndedBanner = true
        WatchHaptic.restEnded.play()
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        restEndedBanner = false
    }

    // MARK: - Wrist actions (FER-808)

    /// Log the current set from the wrist. Sends `.completeSet`; the iPhone runs `registerCurrentSet` and
    /// re-emits the snapshot (which flips this face to the rest countdown). The confirmation haptic + the
    /// 400 ms check are the view's job. Stays available with no permission / no iPhone (the message queues
    /// over `transferUserInfo` and applies on reconnect) — the CTA is never a dead button.
    func completeSetFromWrist() {
        guard let sid = sessionId else { return }
        send(.completeSet(sessionId: sid, ts: Date()))
    }

    /// Skip the current rest from the wrist. Sends `.skipRest` and clears the local rest immediately so the
    /// face returns to capture without waiting for the round-trip (honest even if the iPhone is away).
    func skipRestFromWrist() {
        guard let sid = sessionId, rest != nil else { return }
        send(.skipRest(sessionId: sid, ts: Date()))
        restEndTask?.cancel()
        rest = nil
    }

    /// Nudge the current rest by `deltaS` (±30) from the wrist. Sends `.adjustRest`, then optimistically
    /// moves the local ceiling and re-arms `scheduleRestEnd` so the countdown and its buzz stay honest even
    /// while the iPhone is unreachable; the iPhone's next snapshot is authoritative. Caller hides «−30»
    /// once the rest has expired, and `extendRest` floors the ceiling at «now».
    func adjustRestFromWrist(by deltaS: Int) {
        guard let sid = sessionId, let snap = rest else { return }
        send(.adjustRest(sessionId: sid, deltaS: deltaS, ts: Date()))
        let newEnd = max(Date(), snap.restEndsAt.addingTimeInterval(TimeInterval(deltaS)))
        rest?.restEndsAt = newEnd
        scheduleRestEnd(at: newEnd)
    }

    /// FER-810: «Ver recibo en iPhone» from the summary → ask the iPhone to open the saved workout's
    /// history detail. `sessionId` survives session cleanup (only reset on the next `.start`), so it still
    /// identifies the just-finished session while the summary is up.
    func openReceiptFromWrist() {
        guard let sid = sessionId else { return }
        send(.openReceipt(sessionId: sid))
    }

    /// FER-96: «Empezar» from the wrist's idle face, OUTSIDE any session. The one-oracle invariant — no
    /// routine/slots travel with this: the watch only asks, the iPhone resolves «today» and starts,
    /// through the exact same path its own «Empezar» button uses. Same guaranteed-channel `send` as
    /// every other wrist action.
    ///
    /// C1 (FER-361) extends the table for when the iPhone can't be asked at all:
    ///
    /// | iPhone reachable? | cached seed? | outcome |
    /// |---|---|---|
    /// | yes | — | ask it, as before (`.startFromWrist`) — it mints, never the watch |
    /// | no  | yes | mint LOCALLY from the seed (`asTemplate`) and start standalone |
    /// | no  | no  | nothing to start from → `startNeedsPhone` (B2: «Empieza en tu iPhone») |
    func startTodayFromWrist() {
        guard sessionId == nil, !sessionActive else { return }   // already running → nothing to ask
        guard iPhoneReachable else {
            guard let seed = cachedSeed else {
                startNeedsPhone = true
                return
            }
            startNeedsPhone = false
            Task { await startStandalone(from: seed) }
            return
        }
        startNeedsPhone = false
        send(.startFromWrist(sessionId: nil))
    }

    // MARK: - Standalone logging (C1 · FER-361) — the watch itself is the logger

    /// Log a set while running standalone — the wrist IS the logger here (unlike
    /// `completeSetFromWrist()`, which only asks the iPhone to advance ITS live set). Addressed
    /// EXPLICITLY by `runId`/`setId` (the same two keys the outgoing `.logSet` uses) rather than an
    /// implicit "current" cursor — B2's UI already knows which row it's rendering/tapping, and this way
    /// the manager never has to invent which set becomes focused next (supersets, "bajar y seguir"
    /// skipping rest, warm-ups…) — that policy stays entirely in the UI/product layer, not here.
    ///
    /// Mutates the matching `SetSnapshot` in place (weight/reps/mode/done/doneTs/rpe), persists via
    /// `WatchSessionStore`, and tells the iPhone via the id-addressed `.logSet` so
    /// `StrengthSessionReconciler` can fold it in on reconnect.
    ///
    /// Covers standard AND AMRAP alike (both are weight×reps; AMRAP's `reps` simply arrives here for the
    /// first time instead of already being set) — same zero/blank-reps guard
    /// `StrengthSessionModel.canRegisterCurrentSet` uses on the iPhone, so a volume-less tap is refused
    /// rather than logging a silent 0. A drop step is its own `SetSnapshot` (`addStandaloneDrop`); once
    /// on screen, it logs through this exact same path, addressed by its own `setId`.
    ///
    /// `mode`, when passed, overrides the set's planned mode (e.g. a set planned `.standard` performed as
    /// AMRAP); `nil` (the default) leaves whatever the plan already had. `rir` (reps in reserve, optional)
    /// converts to RPE via `RIRScale.rpe(fromRIR:)` — the same scale the iPhone's live sheet uses.
    @discardableResult
    func logStandaloneSet(runId: String, setId: String, weightKg: Double, reps: Int?,
                          mode: SetMode? = nil, rir: Int? = nil, now: Date = Date()) -> Bool {
        guard isStandalone, var snap = sessionSnapshot,
              let ei = snap.runs.firstIndex(where: { $0.id == runId }) else { return false }
        var run = snap.runs[ei]
        guard let si = run.sets.firstIndex(where: { $0.id == setId }) else { return false }
        let usesReps = run.type == .weightReps || run.type == .bodyweight
        if usesReps, (reps ?? 0) <= 0 { return false }   // never log a blank/zero-rep set
        var set = run.sets[si]
        set.weightKg = weightKg
        set.reps = reps
        if let mode { set.mode = mode }
        set.done = true
        set.doneTs = Int(now.timeIntervalSince1970)
        if let rir { set.rpe = RIRScale.rpe(fromRIR: rir) }
        run.sets[si] = set
        snap.runs[ei] = run
        snap.updatedTs = Int(now.timeIntervalSince1970)
        sessionSnapshot = snap
        Task { await WatchSessionStore.shared.saveInProgress(snap) }
        send(.logSet(sessionId: snap.id, runId: run.id, set: set))
        WatchHaptic.actionTapped.play()
        return true
    }

    /// Hang a drop-set step off `setId` (the mother set, or an existing step already hanging off it) in
    /// `runId` while running standalone — mirrors `StrengthSessionModel.addDrop`'s invariants
    /// (mother-lookup, `SetVariants.maxDropSteps` cap, adjacency) with NO `PlateMath` rounding (the watch
    /// can't import `StrandAnalytics`): the target weight is the raw `SetVariants.dropTargetKg(fromKg:)`.
    /// Returns `false` (and changes nothing) when there's no headroom — already at the step cap, the set
    /// isn't a work set, or the raw target isn't actually lower (e.g. a bodyweight set at 0 kg) — so a
    /// caller never inserts a step that lies.
    @discardableResult
    func addStandaloneDrop(runId: String, afterSetId setId: String) -> Bool {
        guard isStandalone, var snap = sessionSnapshot,
              let ei = snap.runs.firstIndex(where: { $0.id == runId }) else { return false }
        var run = snap.runs[ei]
        guard let si = run.sets.firstIndex(where: { $0.id == setId }), run.sets[si].kind == .work
        else { return false }
        var motherIndex = si
        while motherIndex > 0 && run.sets[motherIndex].mode == .drop { motherIndex -= 1 }
        guard run.sets[motherIndex].mode != .drop else { return false }   // orphan: nothing to hang from
        var tail = motherIndex
        var steps = 0
        while tail + 1 < run.sets.count && run.sets[tail + 1].mode == .drop {
            tail += 1; steps += 1
        }
        guard steps < SetVariants.maxDropSteps else { return false }
        let from = run.sets[tail]
        let target = SetVariants.dropTargetKg(fromKg: from.weightKg)
        guard target < from.weightKg else { return false }
        let drop = StrengthSessionSnapshot.SetSnapshot(id: UUID().uuidString, weightKg: target,
                                                       reps: run.sets[motherIndex].reps, kind: .work,
                                                       mode: .drop)
        run.sets.insert(drop, at: tail + 1)
        if run.currentSet > tail { run.currentSet += 1 }   // keep the index-based cursor consistent post-insert
        snap.runs[ei] = run
        snap.updatedTs = Int(Date().timeIntervalSince1970)
        sessionSnapshot = snap
        Task { await WatchSessionStore.shared.saveInProgress(snap) }
        send(.logSet(sessionId: snap.id, runId: run.id, set: drop))
        WatchHaptic.actionTapped.play()
        return true
    }

    /// «Terminar» from the wrist while running standalone. Closes the real `HKWorkout` through the exact
    /// same invariant `endFromWrist()` uses (shared `externalUUID`, FER-740's one-workout rule), then
    /// `endSession` reconciles back to the iPhone via `.syncSnapshot` — no `.end(...)` round-trip first:
    /// the iPhone never had a live mirror for a session it minted nothing for, so there's nothing on its
    /// side to close, and `.syncSnapshot` alone carries the whole story (plan + logged sets + measured
    /// avgHr/kcal).
    func endStandaloneSession() {
        guard isStandalone else { return }
        Task { await endSession(endedAt: Date(), save: true) }
    }

    // MARK: - Message handling

    private func handle(_ message: WorkoutMirrorMessage) {
        switch message {
        case let .start(sid, routine, _):
            sessionId = sid
            externalUUID = WorkoutMirrorKey.externalUUID(for: sid)
            if !routine.isEmpty { routineName = routine }
        case let .rest(snapshot):
            adoptIdentity(snapshot.sessionId)
            if !snapshot.routineName.isEmpty { routineName = snapshot.routineName }
            rest = snapshot
            heartRate = snapshot.bpm ?? heartRate
            scheduleRestEnd(at: snapshot.restEndsAt)
        case let .capture(snapshot):
            // FER-809: we're working a set, not resting → adopt the «qué toca» context and drop any rest.
            adoptIdentity(snapshot.sessionId)
            if !snapshot.routineName.isEmpty { routineName = snapshot.routineName }
            capture = snapshot
            rest = nil
            restEndTask?.cancel()
            heartRate = snapshot.bpm ?? heartRate
            if let hm = snapshot.hrMax { hrMax = hm }   // FER-811: adopt the mirrored max HR for the zone label
        case let .plan(snapshot):
            adoptIdentity(snapshot.sessionId)
            if !snapshot.routineName.isEmpty { routineName = snapshot.routineName }
            plan = snapshot
        case let .sessionModel(snapshot):
            // C1 (FER-361): always cache as the seed — today's plan, kept fresh for a future local start.
            cachedSeed = snapshot
            hasSeed = true
            Task { await WatchSessionStore.shared.saveSeed(snapshot) }
            // If a mirrored (iPhone-driven) session is already live, this fuller model becomes its
            // structural reference too. Never overwrites a STANDALONE session's own snapshot — that one
            // is the watch's own logged truth, not the plan the iPhone happens to be pushing right now.
            if sessionActive, !isStandalone { sessionSnapshot = snapshot }
        case let .restEnded(_, recovered):
            // Cancel the local clock timer either way, then decide the signal:
            //  • recovered (FER-758): the pulse dropped to target → fire the «ready» buzz + banner now.
            //  • not recovered: the user returned to the set → clear silently, no buzz.
            restEndTask?.cancel()
            if recovered { Task { await fireRestEnded() } } else { rest = nil }
        case let .end(sid, endedAt, save, ext):
            sessionId = sid
            externalUUID = ext
            Task { await endSession(endedAt: endedAt, save: save) }
        case let .idleContext(word, toneRaw, advice, routineName):
            // FER-96: the resting-face verdict, resolved by the iPhone — adopted as-is, never recomputed.
            idleContext = WatchIdleContext(word: word, advice: advice, routineName: routineName,
                                           toneRaw: toneRaw)
        case .watchDidSaveWorkout, .watchWillNotSave, .completeSet, .logSet, .syncSnapshot,
             .skipRest, .adjustRest, .openReceipt, .watchPulse, .startFromWrist:
            break   // watch → iPhone only (FER-808/810/1003/96/361)
        }
    }

    /// Adopt a `WorkoutMirrorMessage` delivered over `updateApplicationContext` (FER-96) — the resting
    /// face's context, which must reach the watch even with no active session and no live reachability.
    /// Called both from the delegate callback (a NEW context arrived) and once at activation (the
    /// context the iPhone already pushed before this app process existed).
    private func adoptApplicationContext(_ context: [String: Any]) {
        // C1 (FER-361): the standalone SEED (today's plan) rides in its own key alongside the idle-face
        // context — cache it first so a start tap right after activation already has today's plan.
        if let seedData = context[WorkoutMirrorKey.seedKey] as? Data,
           let seedMsg = WorkoutMirrorMessage.decode(seedData) {
            handle(seedMsg)
        }
        guard let data = context[WorkoutMirrorKey.payloadKey] as? Data,
              let message = WorkoutMirrorMessage.decode(data) else { return }
        handle(message)
    }

    private func adoptIdentity(_ sid: String) {
        guard sessionId == nil else { return }
        sessionId = sid
        externalUUID = WorkoutMirrorKey.externalUUID(for: sid)
    }

    // MARK: - Send (watch → iPhone)

    /// Send a control message to the iPhone. Prefers the guaranteed `WCSession` channel with a
    /// background `transferUserInfo` fallback so the save-ack survives being briefly out of range.
    private func send(_ message: WorkoutMirrorMessage) {
        guard let data = message.encoded() else { return }
        // Also push over the HealthKit mirror channel while the session is live (belt and suspenders).
        if let session { Task { try? await session.sendToRemoteWorkoutSession(data: data) } }
        guard WCSession.isSupported() else { return }
        let wc = WCSession.default
        guard wc.activationState == .activated else { return }
        if wc.isReachable {
            wc.sendMessageData(data, replyHandler: nil) { [weak self] _ in
                // errorHandler runs on WatchConnectivity's private queue, not the main actor — hop before
                // touching `self` (Sev-4, mina de Swift 6; mismo patrón que los delegates nonisolated abajo).
                Task { @MainActor in
                    self?.transfer(data)
                }
            }
        } else {
            transfer(data)
        }
    }

    private func transfer(_ data: Data) {
        guard WCSession.isSupported() else { return }
        WCSession.default.transferUserInfo([WorkoutMirrorKey.payloadKey: data])
    }
}

// MARK: - HKWorkoutSessionDelegate
extension WatchWorkoutManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession,
                                    didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState, date: Date) {
        Task { @MainActor in self.sessionActive = toState.isActive }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {}

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession,
                                    didReceiveDataFromRemoteWorkoutSession data: [Data]) {
        Task { @MainActor in
            for datum in data { if let m = WorkoutMirrorMessage.decode(datum) { self.handle(m) } }
        }
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate — read the watch's own HR
extension WatchWorkoutManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder,
                                    didCollectDataOf collectedTypes: Set<HKSampleType>) {
        guard collectedTypes.contains(HKQuantityType(.heartRate)) else { return }
        let statistics = workoutBuilder.statistics(for: HKQuantityType(.heartRate))
        let unit = HKUnit.count().unitDivided(by: .minute())
        let bpm = statistics?.mostRecentQuantity()?.doubleValue(for: unit) ?? 0
        Task { @MainActor in
            guard bpm > 0 else { return }
            let value = Int(bpm.rounded())
            self.heartRate = value
            // FER-1003: mirror live HR to the iPhone — strength sheet's only live-HR source without a band.
            self.send(.watchPulse(bpm: value))
        }
    }
}

// MARK: - WCSessionDelegate (guaranteed control channel)
extension WatchWorkoutManager: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState,
                             error: Error?) {
        let reachable = session.isReachable
        // FER-96: `updateApplicationContext` delivers as «last known state» — read what's already there
        // at activation (pushed before this app process existed), not only future changes.
        let context = session.receivedApplicationContext
        Task { @MainActor in
            self.iPhoneReachable = reachable
            self.adoptApplicationContext(context)
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in self.iPhoneReachable = reachable }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
        Task { @MainActor in if let m = WorkoutMirrorMessage.decode(messageData) { self.handle(m) } }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let data = userInfo[WorkoutMirrorKey.payloadKey] as? Data else { return }
        Task { @MainActor in if let m = WorkoutMirrorMessage.decode(data) { self.handle(m) } }
    }

    /// FER-96: the resting-face context — the ONE channel WatchConnectivity delivers even with no
    /// active session and no live reachability.
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in self.adoptApplicationContext(applicationContext) }
    }
}

extension HKWorkoutSessionState {
    var isActive: Bool { self != .notStarted && self != .ended }
}
