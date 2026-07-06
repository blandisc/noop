#if os(iOS)
import Foundation
import HealthKit
import WatchConnectivity
import os

/// iPhone side of the strength-session **workout mirroring** (FER-740, F1.1 of the Apple Watch epic
/// FER-391). Its job: when a guided strength session starts and the paired Apple Watch is available,
/// wake the watch app so it runs the real `HKWorkoutSession`, then exchange the mirroring contract
/// (`WorkoutMirrorMessage`) with it. The iPhone never blocks on the watch — `AppModel` starts and ends
/// the session locally regardless; this bridge is a best-effort companion.
///
/// Two channels, per `/arquitecto`:
///   • **HealthKit mirror** (`mirroredSession.sendToRemoteWorkoutSession`) — best-effort, for the
///     frequent `rest` snapshots the watch renders as a local countdown.
///   • **WatchConnectivity** (`WCSession`) — guaranteed + acked, for the control messages that must
///     arrive: `start`, `end`, and the watch's `watchDidSaveWorkout` / `watchWillNotSave` replies.
///
/// The one-HKWorkout invariant lives in `AppModel`: this bridge only surfaces the watch's save state
/// via callbacks; `WorkoutSaveGate` decides. HealthKit is never a source of truth here.
@MainActor
final class WorkoutMirroringBridge: NSObject, ObservableObject {
    /// Read once at session start: whether to attempt mirroring to the watch at all. Defaults ON so the
    /// loop works end-to-end for hardware testing; the user-facing Settings toggle is FER-C.
    static let mirrorToWatchKey = "noop.mirrorStrengthToWatch"

    private let healthStore = HKHealthStore()
    private let log = Logger(subsystem: "com.noopapp.noop", category: "WatchMirror")

    /// The mirrored session HealthKit hands us once the watch starts mirroring. Retained so we can push
    /// rest snapshots to the wrist and receive its data.
    private var mirroredSession: HKWorkoutSession?
    /// The session currently being mirrored, so late acks/messages can be matched.
    private var activeSessionId: String?

    // Callbacks `AppModel` installs to close the loop. All fire on the main actor.
    /// The watch saved the real HKWorkout for this session → the iPhone must OMIT its own save.
    var onWatchDidSaveWorkout: ((_ sessionId: String) -> Void)?
    /// The watch ended the session from the wrist → the iPhone should end its local session too.
    var onWatchEndedSession: ((_ sessionId: String, _ save: Bool) -> Void)?
    /// The watch declined to save (no permission / error / mirror lost) → the iPhone takes over.
    var onWatchWillNotSave: ((_ sessionId: String) -> Void)?

    /// Whether a watch session is currently mirroring to the iPhone. Read at end-of-session to decide
    /// whether to wait for the watch's save decision.
    var isMirroringActive: Bool { mirroredSession != nil }

    override init() {
        super.init()
        configure()
    }

    /// Activate WatchConnectivity and install the mirroring start handler. Safe to call once at init.
    private func configure() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        // HealthKit calls this when the watch begins mirroring its session to us.
        healthStore.workoutSessionMirroringStartHandler = { [weak self] mirrored in
            Task { @MainActor in
                guard let self else { return }
                self.mirroredSession = mirrored
                mirrored.delegate = self
                self.log.log("Mirrored watch session started")
                // Inject the shared sessionId so the watch derives the same idempotency key.
                if let sid = self.activeSessionId {
                    self.sendOverHealthKit(.start(sessionId: sid, routineName: "", startedAt: Date()))
                }
            }
        }
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    /// Whether a paired watch with our app installed is available to mirror to.
    private var watchAvailable: Bool {
        guard WCSession.isSupported() else { return false }
        let s = WCSession.default
        return s.activationState == .activated && s.isPaired && s.isWatchAppInstalled
    }

    // MARK: - Session lifecycle (called by AppModel)

    /// Attempt to start a mirrored session on the watch. Fire-and-forget: never blocks or throws to the
    /// caller — the iPhone's own session has already started. A no-op when mirroring is disabled or no
    /// watch is available (the iPhone then saves the estimated workout as it does today).
    func beginMirroredSessionIfEnabled(sessionId: String, routineName: String, startedAt: Date) {
        guard UserDefaults.standard.object(forKey: Self.mirrorToWatchKey) as? Bool ?? true else { return }
        guard watchAvailable else { log.log("No watch available — iPhone owns the workout"); return }
        activeSessionId = sessionId
        let config = HKWorkoutConfiguration()
        config.activityType = .traditionalStrengthTraining
        Task {
            do {
                try await healthStore.startWatchApp(toHandle: config)
                log.log("Requested watch app start for session \(sessionId, privacy: .public)")
            } catch {
                // Watch unreachable / declined → the iPhone stays the sole saver. No user-facing error
                // in F1.1 (degraded states are FER-B/FER-C).
                self.activeSessionId = nil
                log.error("startWatchApp failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Push the current rest window to the watch (best-effort HealthKit channel).
    func pushRest(_ snapshot: RestActivitySnapshot) {
        guard mirroredSession != nil else { return }
        sendOverHealthKit(.rest(snapshot))
    }

    /// Tell the watch a rest window ended without ending the session.
    func pushRestEnded(sessionId: String) {
        guard mirroredSession != nil else { return }
        sendOverHealthKit(.restEnded(sessionId: sessionId))
    }

    /// Order the watch to end its session (and save the HKWorkout when `save`). Sent over the guaranteed
    /// channel; the watch replies with `watchDidSaveWorkout` (→ iPhone omits its save) or nothing.
    func endMirroredSession(sessionId: String, endedAt: Date, save: Bool) {
        let externalUUID = WorkoutMirrorKey.externalUUID(for: sessionId)
        sendOverWatchConnectivity(.end(sessionId: sessionId, endedAt: endedAt,
                                       save: save, externalUUID: externalUUID))
        mirroredSession = nil
        activeSessionId = nil
    }

    // MARK: - Send

    private func sendOverHealthKit(_ message: WorkoutMirrorMessage) {
        guard let session = mirroredSession, let data = message.encoded() else { return }
        Task {
            do { try await session.sendToRemoteWorkoutSession(data: data) }
            catch { log.error("HK send failed: \(error.localizedDescription, privacy: .public)") }
        }
    }

    private func sendOverWatchConnectivity(_ message: WorkoutMirrorMessage) {
        guard WCSession.isSupported(), let data = message.encoded() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        if session.isReachable {
            session.sendMessageData(data, replyHandler: nil) { [weak self] error in
                // Not reachable right now → queue it so it arrives on reconnect (scenario: end out of range).
                self?.transferData(data)
                self?.log.error("WC send failed, queued: \(error.localizedDescription, privacy: .public)")
            }
        } else {
            transferData(data)
        }
    }

    /// Background-queue the payload so it's delivered when the watch reconnects.
    private func transferData(_ data: Data) {
        guard WCSession.isSupported() else { return }
        WCSession.default.transferUserInfo([WorkoutMirrorKey.payloadKey: data])
    }

    // MARK: - Receive

    private func handle(_ message: WorkoutMirrorMessage) {
        switch message {
        case let .watchDidSaveWorkout(sessionId, _):
            log.log("Watch saved workout for \(sessionId, privacy: .public) — iPhone will omit its save")
            onWatchDidSaveWorkout?(sessionId)
        case let .end(sessionId, _, save, _):
            // The watch ended from the wrist: end the iPhone session too (persist record + receipt).
            onWatchEndedSession?(sessionId, save)
        case let .watchWillNotSave(sessionId, reason):
            log.log("Watch won't save \(sessionId, privacy: .public): \(reason.rawValue, privacy: .public)")
            onWatchWillNotSave?(sessionId)
        case .start, .rest, .restEnded:
            break   // iPhone → watch only
        }
    }
}

// MARK: - HKWorkoutSessionDelegate (mirrored session on iPhone)
// Delegate callbacks arrive on a background queue → hop to the main actor.
extension WorkoutMirroringBridge: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession,
                                    didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState, date: Date) {}

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {}

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession,
                                    didReceiveDataFromRemoteWorkoutSession data: [Data]) {
        Task { @MainActor in
            for datum in data {
                if let message = WorkoutMirrorMessage.decode(datum) { self.handle(message) }
            }
        }
    }
}

// MARK: - WCSessionDelegate (guaranteed control channel)
extension WorkoutMirroringBridge: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState,
                             error: Error?) {}
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { WCSession.default.activate() }

    nonisolated func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
        Task { @MainActor in
            if let message = WorkoutMirrorMessage.decode(messageData) { self.handle(message) }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let data = userInfo[WorkoutMirrorKey.payloadKey] as? Data else { return }
        Task { @MainActor in
            if let message = WorkoutMirrorMessage.decode(data) { self.handle(message) }
        }
    }
}
#endif
