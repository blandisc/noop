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
/// F1.1 is cimientos: the UI is minimal (elapsed + pulse + rest countdown). Polished watch UI, haptics,
/// and a visual summary are FER-B.
@MainActor
final class WatchWorkoutManager: NSObject, ObservableObject {
    static let shared = WatchWorkoutManager()

    /// Live values the minimal UI observes.
    @Published var startDate: Date?
    @Published var heartRate: Int = 0
    @Published var rest: RestActivitySnapshot?
    @Published var sessionActive = false

    private let healthStore = HKHealthStore()
    private let log = Logger(subsystem: "com.noopapp.noop.watch", category: "WatchWorkout")

    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    /// The shared session identity, injected by the iPhone's `.start`. Drives the idempotency key.
    private var sessionId: String?
    private var externalUUID: String?

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

    /// Request HealthKit share/read up front (the watch has no in-app rationale screen in F1.1).
    func requestAuthorization() {
        Task {
            do { try await healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead) }
            catch { log.error("Auth failed: \(error.localizedDescription, privacy: .public)") }
        }
    }

    // MARK: - Session lifecycle

    /// Called from the `WKApplicationDelegate` when the iPhone wakes the app with a workout config.
    func start(configuration: HKWorkoutConfiguration) async throws {
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
        log.log("Watch workout started")
    }

    /// Re-adopt a session that outlived the app (killed / rebooted mid-session). Called at launch.
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
                self.log.log("Recovered active watch session")
            }
        }
    }

    /// End the session on the iPhone's order (`.end`). Saves the real workout when `save`, stamped with
    /// the shared `externalUUID`, then acks `watchDidSaveWorkout` so the iPhone omits its estimate.
    private func endSession(endedAt: Date, save: Bool) async {
        defer { cleanup() }
        guard let session, let builder else { sessionActive = false; return }
        let sid = sessionId ?? ""
        let ext = externalUUID ?? WorkoutMirrorKey.externalUUID(for: sid)
        guard save else { session.end(); return }   // discarded session → end without a workout
        // No workout-share permission on the wrist → let the iPhone save its estimate instead.
        guard healthStore.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized else {
            send(.watchWillNotSave(sessionId: sid, reason: .noPermission))
            session.end(); return
        }
        do {
            try await builder.endCollection(at: endedAt)
            try await builder.addMetadata([HKMetadataKeyExternalUUID: ext])
            let workout = try await builder.finishWorkout()
            session.end()
            if workout != nil { send(.watchDidSaveWorkout(sessionId: sid, externalUUID: ext)) }
            else { send(.watchWillNotSave(sessionId: sid, reason: .sessionError)) }
        } catch {
            log.error("Finish failed: \(error.localizedDescription, privacy: .public)")
            send(.watchWillNotSave(sessionId: sid, reason: .sessionError))
            session.end()
        }
    }

    private func cleanup() {
        session = nil
        builder = nil
        sessionActive = false
        rest = nil
        startDate = nil
    }

    // MARK: - Message handling

    private func handle(_ message: WorkoutMirrorMessage) {
        switch message {
        case let .start(sid, _, _):
            sessionId = sid
            externalUUID = WorkoutMirrorKey.externalUUID(for: sid)
        case let .rest(snapshot):
            adoptIdentity(snapshot.sessionId)
            rest = snapshot
            heartRate = snapshot.bpm ?? heartRate
        case .restEnded:
            rest = nil
        case let .end(sid, endedAt, save, ext):
            sessionId = sid
            externalUUID = ext
            Task { await endSession(endedAt: endedAt, save: save) }
        case .watchDidSaveWorkout, .watchWillNotSave:
            break   // watch → iPhone only
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
                             error: Error?) {}

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
