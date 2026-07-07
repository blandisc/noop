import Foundation
import HealthKit
import WatchConnectivity
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
    @Published var sessionActive = false
    /// The routine's display name, adopted from the rest snapshots the iPhone sends.
    @Published var routineName: String = ""
    /// Whether the paired iPhone is currently reachable. The face shows a quiet «no connection» line
    /// when false; heart rate and elapsed time keep running regardless.
    @Published var iPhoneReachable = true
    /// True when Health sharing is denied on the wrist → the face warns and drops to «--», but the
    /// session (timer + rests + haptics) keeps serving. Never blocks.
    @Published var healthAccessDenied = false
    /// True for the ~3s «Descanso terminado» transition after a rest naturally expires.
    @Published var restEndedBanner = false
    /// The end-of-session summary, set when the session ends with something saved.
    @Published var summary: WatchSessionSummary?

    private let healthStore = HKHealthStore()
    private let log = Logger(subsystem: "com.noopapp.noop.watch", category: "WatchWorkout")

    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    /// The shared session identity, injected by the iPhone's `.start`. Drives the idempotency key.
    private var sessionId: String?
    private var externalUUID: String?

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
    }

    /// Request HealthKit share/read up front (the watch has no in-app rationale screen).
    func requestAuthorization() {
        Task {
            do { try await healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead) }
            catch { log.error("Auth failed: \(error.localizedDescription, privacy: .public)") }
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
    func start(configuration: HKWorkoutConfiguration) async throws {
        beginConnecting()
        let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
        let builder = session.associatedWorkoutBuilder()
        session.delegate = self
        builder.delegate = self
        builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore,
                                                     workoutConfiguration: configuration)
        self.session = session
        self.builder = builder
        try await session.startMirroringToCompanionDevice()
        let start = Date()
        session.startActivity(with: start)
        try await builder.beginCollection(at: start)
        startDate = start
        sessionActive = true
        enterRunning()
        refreshHealthAccess()
        WatchHaptic.sessionStart.play()
        log.log("Watch workout started")
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

    /// End the session on the iPhone's order (`.end`). Saves the real workout when `save`, stamped with
    /// the shared `externalUUID`, then acks `watchDidSaveWorkout` so the iPhone omits its estimate.
    private func endSession(endedAt: Date, save: Bool) async {
        defer { cleanup() }
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
            session.end()
            presentSummary(stats, saveState: .failed)
        }
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
        startDate = nil
        restEndTask?.cancel()
        restEndTask = nil
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
        send(.completeSet(sessionId: sid))
    }

    /// Skip the current rest from the wrist. Sends `.skipRest` and clears the local rest immediately so the
    /// face returns to capture without waiting for the round-trip (honest even if the iPhone is away).
    func skipRestFromWrist() {
        guard let sid = sessionId, rest != nil else { return }
        send(.skipRest(sessionId: sid))
        restEndTask?.cancel()
        rest = nil
    }

    /// Nudge the current rest by `deltaS` (±30) from the wrist. Sends `.adjustRest`, then optimistically
    /// moves the local ceiling and re-arms `scheduleRestEnd` so the countdown and its buzz stay honest even
    /// while the iPhone is unreachable; the iPhone's next snapshot is authoritative. Caller hides «−30»
    /// once the rest has expired, and `extendRest` floors the ceiling at «now».
    func adjustRestFromWrist(by deltaS: Int) {
        guard let sid = sessionId, let snap = rest else { return }
        send(.adjustRest(sessionId: sid, deltaS: deltaS))
        let newEnd = max(Date(), snap.restEndsAt.addingTimeInterval(TimeInterval(deltaS)))
        rest?.restEndsAt = newEnd
        scheduleRestEnd(at: newEnd)
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
        case let .plan(snapshot):
            adoptIdentity(snapshot.sessionId)
            if !snapshot.routineName.isEmpty { routineName = snapshot.routineName }
            plan = snapshot
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
        case .watchDidSaveWorkout, .watchWillNotSave,
             .completeSet, .skipRest, .adjustRest:
            break   // watch → iPhone only (FER-808)
        }
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
                self?.transfer(data)
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
        Task { @MainActor in if bpm > 0 { self.heartRate = Int(bpm.rounded()) } }
    }
}

// MARK: - WCSessionDelegate (guaranteed control channel)
extension WatchWorkoutManager: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState,
                             error: Error?) {
        let reachable = session.isReachable
        Task { @MainActor in self.iPhoneReachable = reachable }
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
}

extension HKWorkoutSessionState {
    var isActive: Bool { self != .notStarted && self != .ended }
}
