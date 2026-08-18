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

/// The live status of the watch's mirrored recording, for the iPhone's in-session status line (FER-742).
/// `.inactive`/`.waiting` paint nothing; the other three each map to one tertiary line in `LiveStrengthSheet`.
enum WatchSessionStatus: Equatable { case inactive, waiting, recording, notResponding, unavailable }

@MainActor
final class WorkoutMirroringBridge: NSObject, ObservableObject {
    /// Read at session start: whether to mirror to the watch at all. Opt-in (default off) — flipped on by
    /// the Settings «Grabar en el Apple Watch» toggle (FER-742); until then the iPhone owns the estimate.
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
    /// FER-808: the user logged a set / skipped or adjusted a rest from the wrist → apply it to the live
    /// session exactly as the lock-screen actions do (`AppModel` routes to the shared session mutators).
    var onWatchAction: ((_ sessionId: String, _ action: WatchWorkoutAction) -> Void)?
    /// FER-810: «Ver recibo en iPhone» from the wrist summary → open the saved workout's history detail.
    var onOpenReceipt: ((_ sessionId: String) -> Void)?
    /// FER-96: «Empezar» tapped on the wrist's idle face, OUTSIDE any session → resolve + start today's
    /// session exactly as the iPhone's «Empezar» button does. The one-oracle invariant: the watch never
    /// resolves routine/slots itself, so this callback carries no payload beyond the ask.
    var onStartFromWrist: (() -> Void)?

    // FER-742: state the iPhone UI paints, pushed to `AppModel` (which the Settings row + the strength
    // sheet already observe) via these closures — same fire-on-main-actor pattern as the ones above.
    /// Paired-watch availability changed → the Settings «Grabar en el Apple Watch» row shows/hides + enables.
    var onPairingChanged: ((_ paired: Bool, _ appInstalled: Bool) -> Void)?
    /// The live mirror status changed during a session → the sheet's tertiary watch line.
    var onSessionStatusChanged: ((WatchSessionStatus) -> Void)?
    /// FER-1003: the watch's own live heart rate during the mirrored session (replaces the band-sourced bpm).
    var onWatchPulseChanged: ((Int?) -> Void)?

    /// How many times we've asked the watch to mirror THIS session — the retry cap is one (2 total).
    private var mirrorAttempts = 0
    /// The pending start parameters, kept so «Reintentar» can re-issue the same start (FER-742).
    private var pendingStart: (sessionId: String, routineName: String, startedAt: Date)?
    /// The timeout that flips a silent watch to «no respondió» when no mirror begins in time (FER-742).
    private var waitTimeout: Task<Void, Never>?
    /// The live mirror status; publishing goes through the closure so `AppModel` re-renders (FER-742).
    private var sessionStatus: WatchSessionStatus = .inactive {
        didSet { if sessionStatus != oldValue { onSessionStatusChanged?(sessionStatus) } }
    }

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
                // FER-742: the watch confirmed it's recording → the sheet shows «Reloj grabando».
                self.waitTimeout?.cancel(); self.waitTimeout = nil
                self.sessionStatus = .recording
                // Inject the shared sessionId so the watch derives the same idempotency key.
                if let sid = self.activeSessionId {
                    self.sendOverHealthKit(Self.injectedStartMessage(
                        sessionId: sid, pendingRoutineName: self.pendingStart?.routineName, startedAt: Date()))
                }
            }
        }
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    /// The `.start` message injected once the watch confirms mirroring — a pure static function so the
    /// FER-96 fix is unit-testable without a real HealthKit mirroring callback.
    ///
    /// This used to hardcode `routineName: ""` on purpose, even though `pendingStart.routineName`
    /// already held the real name — the watch only learned it later, off the first
    /// `.rest`/`.capture`/`.plan` (`WatchWorkoutManager.swift`'s `if !snapshot.routineName.isEmpty`
    /// pattern in each case), a real blank window on the idle/live face, not cosmetic.
    nonisolated static func injectedStartMessage(sessionId: String, pendingRoutineName: String?,
                                                 startedAt: Date) -> WorkoutMirrorMessage {
        .start(sessionId: sessionId, routineName: pendingRoutineName ?? "", startedAt: startedAt)
    }

    /// Recompute + publish whether a watch is paired and whether our app is installed on it (FER-742) —
    /// drives the Settings row's three states (hidden / disabled+nudge / on). Safe to call anytime.
    func refreshPairingState() {
        guard WCSession.isSupported() else { onPairingChanged?(false, false); return }
        let s = WCSession.default
        onPairingChanged?(s.isPaired, s.isWatchAppInstalled)
    }

    /// Whether a paired watch with our app installed is available to mirror to.
    private var watchAvailable: Bool {
        guard WCSession.isSupported() else { return false }
        let s = WCSession.default
        return s.activationState == .activated && s.isPaired && s.isWatchAppInstalled
    }

    // MARK: - Session lifecycle (called by AppModel)

    /// Attempt to start a mirrored session on the watch. Fire-and-forget: never blocks or throws to the
    /// caller — the iPhone's own session has already started. A no-op (status `.inactive`, no line) when
    /// mirroring is opt-out or no watch is available: the iPhone then saves the estimated workout as today.
    func beginMirroredSessionIfEnabled(sessionId: String, routineName: String, startedAt: Date) {
        guard UserDefaults.standard.object(forKey: Self.mirrorToWatchKey) as? Bool ?? false else {
            sessionStatus = .inactive; return
        }
        guard watchAvailable else { sessionStatus = .inactive; log.log("No watch available — iPhone owns the workout"); return }
        mirrorAttempts = 0
        pendingStart = (sessionId, routineName, startedAt)
        attemptMirror()
    }

    /// Issue (or re-issue) the watch-start request and arm the no-response timeout (FER-742). A throw or a
    /// silent watch flips the status to `.notResponding` (offers «Reintentar») or `.unavailable` once the
    /// one retry is spent. The session itself never waits on any of this.
    private func attemptMirror() {
        guard let start = pendingStart else { return }
        mirrorAttempts += 1
        sessionStatus = .waiting
        activeSessionId = start.sessionId
        let config = HKWorkoutConfiguration()
        config.activityType = .traditionalStrengthTraining
        Task {
            do {
                try await healthStore.startWatchApp(toHandle: config)
                log.log("Requested watch app start for session \(start.sessionId, privacy: .public)")
            } catch {
                self.activeSessionId = nil
                log.error("startWatchApp failed: \(error.localizedDescription, privacy: .public)")
                self.failedToMirror()
            }
        }
        armWaitTimeout()
    }

    /// Flip a silent/failed watch to «no respondió», or «sin reloj esta sesión» once the retry is spent.
    private func failedToMirror() {
        waitTimeout?.cancel(); waitTimeout = nil
        sessionStatus = mirrorAttempts >= 2 ? .unavailable : .notResponding
    }

    /// If no mirror has begun within the window, treat the watch as non-responding (FER-742).
    private func armWaitTimeout() {
        waitTimeout?.cancel()
        waitTimeout = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)   // 8 s to begin mirroring
            guard let self, !Task.isCancelled else { return }
            if self.sessionStatus == .waiting { self.failedToMirror() }
        }
    }

    /// «Reintentar» from the sheet's watch line — one more attempt at the same pending session (FER-742).
    func retryMirroring() {
        guard sessionStatus == .notResponding, pendingStart != nil else { return }
        attemptMirror()
    }

    /// Push the current rest window to the watch (best-effort HealthKit channel).
    func pushRest(_ snapshot: RestActivitySnapshot) {
        guard mirroredSession != nil else { return }
        sendOverHealthKit(.rest(snapshot))
    }

    /// Push the current capture context to the watch (FER-809) — which set is up and its load, so the wrist
    /// shows «qué toca» between rests. Best-effort HealthKit channel, same as `pushRest`.
    func pushCapture(_ snapshot: WorkoutCaptureSnapshot) {
        guard mirroredSession != nil else { return }
        sendOverHealthKit(.capture(snapshot))
    }

    /// Push the routine plan to the watch for its rotor page (FER-810). Best-effort HealthKit channel; the
    /// caller only sends it when the plan's visible state changes.
    func pushPlan(_ snapshot: WorkoutPlanSnapshot) {
        guard mirroredSession != nil else { return }
        sendOverHealthKit(.plan(snapshot))
    }

    /// Tell the watch a rest window ended without ending the session. `recovered == true` (FER-758) means
    /// the pulse recovered to target → the watch buzzes «ready»; the default `false` is a silent cancel.
    func pushRestEnded(sessionId: String, recovered: Bool = false) {
        guard mirroredSession != nil else { return }
        sendOverHealthKit(.restEnded(sessionId: sessionId, recovered: recovered))
    }

    /// Order the watch to end its session (and save the HKWorkout when `save`). Sent over the guaranteed
    /// channel; the watch replies with `watchDidSaveWorkout` (→ iPhone omits its save) or nothing.
    func endMirroredSession(sessionId: String, endedAt: Date, save: Bool) {
        let externalUUID = WorkoutMirrorKey.externalUUID(for: sessionId)
        sendOverWatchConnectivity(.end(sessionId: sessionId, endedAt: endedAt,
                                       save: save, externalUUID: externalUUID))
        mirroredSession = nil
        activeSessionId = nil
        // FER-742: the session is over → clear the status line and any pending retry/timeout.
        pendingStart = nil
        mirrorAttempts = 0
        waitTimeout?.cancel(); waitTimeout = nil
        sessionStatus = .inactive
    }

    /// Push the resting-face context (FER-96) — today's routine name + the already-resolved daily
    /// verdict word/tone/advice — OUTSIDE any active session, over `updateApplicationContext`: the one
    /// channel WatchConnectivity delivers as «last known state», reachable or not, session or not. A
    /// no-op without WatchConnectivity; best-effort like every other push in this bridge (`AppModel`
    /// never awaits or blocks on it).
    func pushIdleContext(word: String?, toneRaw: String?, advice: String?, routineName: String?) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        guard let data = WorkoutMirrorMessage
            .idleContext(word: word, toneRaw: toneRaw, advice: advice, routineName: routineName)
            .encoded() else { return }
        do { try session.updateApplicationContext([WorkoutMirrorKey.payloadKey: data]) }
        catch { log.error("updateApplicationContext failed: \(error.localizedDescription, privacy: .public)") }
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
        case let .completeSet(sessionId):
            onWatchAction?(sessionId, .completeSet)
        case let .skipRest(sessionId):
            onWatchAction?(sessionId, .skipRest)
        case let .adjustRest(sessionId, deltaS):
            onWatchAction?(sessionId, .adjustRest(deltaS: deltaS))
        case let .openReceipt(sessionId):
            onOpenReceipt?(sessionId)
        case let .watchPulse(bpm):
            onWatchPulseChanged?(bpm)
        case .startFromWrist:
            // FER-96: «Empezar» from the wrist's idle face. The one-oracle invariant — no routine/slots
            // to read here, `AppModel` resolves + starts through the SAME path the iPhone button uses.
            onStartFromWrist?()
        case .start, .rest, .restEnded, .capture, .plan, .idleContext:
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
                             error: Error?) {
        Task { @MainActor in self.refreshPairingState() }   // FER-742: pairing is valid once activated
    }
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { WCSession.default.activate() }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.refreshPairingState() }   // FER-742: watch (un)paired or app (un)installed
    }

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
