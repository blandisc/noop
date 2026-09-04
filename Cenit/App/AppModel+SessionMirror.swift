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

    // MARK: - Rest Live Activity (FER-721)

    /// Re-subscribe the rest Live Activity to whichever session is now active. Fires on every session
    /// start/end (via `strengthSession`'s `didSet`). Also drives the crash-recovery snapshot (FER-798):
    /// every durable edit persists the session (debounced), and a phase change (rest start/end) flushes now.
    // AppModel-internal (split D1)
    func bindRestActivity() {
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
            // FER-93: sin sesión que recuperar tampoco puede quedar vivo su aviso de descanso. Una
            // app que murió a media serie dejaba programada una notificación que iOS entregaría
            // igual, de una sesión que ya no existe.
            RestEndNotifier.cancel()
            onNoRecoverableStrengthSession?()
            return
        }
        if (try? await store.session(id: snap.id)) != nil {
            try? await store.clearInProgressSession()
            onNoRecoverableStrengthSession?()
            return
        }
        // FER-86: el comentario que vivía aquí decía que el descanso «NO se restaura corriendo».
        // Es falso: `restore(from:)` hace `phase = snap.restEndsAt != nil ? .resting : .capturing`,
        // así que un descanso a media cuenta SÍ vuelve corriendo, con su `restEndsAt` intacto. Se
        // cancelaba el aviso y nadie lo volvía a programar, así que el descanso terminaba en
        // silencio justo en el caso que el aviso existe para cubrir: el teléfono guardado.
        //
        // Se cancela primero (el aviso viejo pudo quedar rancio mientras la app estaba muerta) y se
        // re-arma desde el estado ya restaurado, que es quien sabe si sigue vivo, si está en pausa,
        // y si el interruptor está encendido.
        RestEndNotifier.cancel()
        let restaurada = StrengthSessionModel.restore(from: snap)
        // FER-226: `hrSamples` is memory-only (`StrengthSessionSnapshot` omits it) — rehydrate from
        // whatever already flushed to `strengthHrSample` so a crash mid-session doesn't lose the avgHr.
        restaurada.hrSamples = (try? await store.strengthHRSamples(sessionId: restaurada.id)) ?? []
        pendingHrFlush.removeAll()
        lastAcceptedHrTs = nil
        strengthSession = restaurada                                 // didSet binds the Live Activity
        restaurada.reprogramarAviso()
        strengthSheetPresented = false                               // the hub offers «Resume»; no auto-present
        acquireRealtimeHR("strength")                                // re-arm the HR stream as at start
    }

    /// Hand the controller the current rest snapshot (or nil when not resting) — it starts/updates/ends
    /// the one Activity from that. Cheap and idempotent, so it's safe to call on any relevant change.
    /// FER-740: the same snapshot feeds the Apple Watch mirrored session (no-op without a watch).
    // AppModel-internal (split D1)
    func reconcileRestActivity() {
        // FER-758: an HR-guided rest ends the instant the pulse has recovered to target (past the 20s
        // floor), not only when the fallback clock runs out — and the watch buzzes «ready» to say so.
        // Only the honest HR-recovery path ends early here; the clock ceiling stays the watch's own timer.
        // FER-823: never end the rest while paused — the band keeps streaming, so an HR that recovers to
        // target during a pause must NOT skip the (frozen) rest. Same `!s.paused` gate as computeSessionSnapshot.
        if let s = strengthSession, s.summary == nil, !s.paused, s.phase == .resting,
           s.currentRestMode == .heartRate, let started = s.restStartedAt {
            let elapsed = max(0, Int(Date().timeIntervalSince(started)))
            // FER-1003 / L2-B1: live HR is the Watch mirror (`watchBpm`); feeds auto-skip when recovered.
            let hr = watchBpm
            let v = RestReadinessRule.evaluate(currentHR: hr, worn: watchBpm != nil,
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

    /// FER-806 — the whole-session phase the Live Activity paints, or nil when there's nothing to show
    /// (no session, or the receipt is up ⇒ the Activity ends). Pure + static so it's unit-testable without
    /// an AppModel or ActivityKit. `.paused` wins; then `.resting` between sets; else the active set.
    static func sessionPhase(for s: StrengthSessionModel?) -> SessionPhase? {
        guard let s, s.summary == nil else { return nil }
        if s.paused { return .paused }
        if s.phase == .resting { return .resting }
        return .active
    }

    /// «80 kg × 8» / «80 kg × máx» (AMRAP pendiente) / «↳ 64 kg × 9» (escalón de «bajar y seguir») —
    /// ola 1 (FER-327 · E7 · ux-B §③): la MISMA gramática de la sesión y el recibo, preformateada para
    /// la Live Activity y el reloj (ninguno de los dos resuelve `SetMode` por su cuenta). Vacío para
    /// tipos sin peso×reps (tiempo/distancia) — sin dato que fingir.
    private func returnDetail(for set: StrengthSessionModel.WorkingSet, usesWeightReps: Bool, unit: UnitSystem) -> String {
        guard usesWeightReps else { return "" }
        let weightStr = StrengthDisplay.weight(set.weightKg, system: unit)
        // FER-327: `reps == nil` = AMRAP pendiente — «× máx» (el techo abierto), nunca «× 0».
        let reps = set.reps.map(String.init)
            ?? (set.mode == .amrap ? String(localized: "max") : nil)
        let base = reps.map { "\(weightStr) × \($0)" } ?? weightStr
        return set.mode == .drop ? "↳ \(base)" : base
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
        let detail = returnDetail(for: set, usesWeightReps: usesWeightReps, unit: unit)
        // no band → no live HR to push outward; wrist uses its own HKWorkoutSession HR
        let bandBpm: Int? = nil
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
        let detail = returnDetail(for: set, usesWeightReps: usesWeightReps, unit: unit)
        // no band → no live HR to push outward
        let bandBpm: Int? = nil
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
    // AppModel-internal (split D1)
    func applyRestAction(_ action: RestActivityBridge.PendingAction) {
        // FER-806: actions arrive across the whole session now (the Activity lives the whole session), so
        // the guard is only «there's a live session without a receipt» — each action gates its own phase.
        guard let s = strengthSession, s.summary == nil else { return }
        // P0-3: an action sealed for a DIFFERENT session (enqueued while session A was live, drained
        // after session B already started) must never reach B — a stray ±30/Saltar/Completar/Terminar
        // could otherwise mutate, or even CLOSE, a session the user never touched. `sessionId == nil` is
        // an old payload written before this field existed — accepted for compat; the `lastRestStartedAt`
        // guard right below still covers those exactly as it did before this fix.
        guard action.sessionId == nil || action.sessionId == s.id else { return }
        // Nancy · ronda 6: el inbox del App Group es durable y puede drenar TARDE (app suspendida,
        // Darwin con retraso). Un toque anterior al inicio del ÚLTIMO descanso que haya arrancado
        // pertenece a un contexto ya cerrado — aplicarlo extendería/cortaría el descanso equivocado
        // o registraría una serie que la usuaria no estaba viendo. Se descarta, no se reinterpreta.
        // El ancla es `lastRestStartedAt` (sobrevive a `clearRest`): si NINGÚN descanso arrancó
        // después del toque, la serie enfocada sigue siendo la que la tarjeta prometía.
        if let anchor = s.lastRestStartedAt, action.ts < anchor { return }
        switch action.action {
        case .resume:
            resumeStrengthSessionFromPause()   // FER-823 — leave «En pausa»; re-arms the reconcile loop
        case .completeSet:
            // «Completar» — works from the active card (log the set → rest) AND the rest card (log the
            // upcoming set → rest again). registerCurrentSet advances either way.
            // FER-257 D4: pulso vivo real (mismo criterio que RoutineSheetLiveLogic) — no asumir true.
            s.registerCurrentSet(restingHR: restingHrBaseline, maxHR: Double(profile.hrMax),
                                 hasLivePulse: watchBpm != nil)
        case .finishWorkout:
            // Last set of the routine: log it, then end the session (which ends the Live Activity).
            // Nancy · ronda 3: la tarjeta promete «registrar y terminar», pero desde la pantalla
            // bloqueada no hay dónde escribir un número que falte. Si la serie enfocada no es
            // registrable (peso×reps sin repeticiones — hoy inalcanzable desde la UI, pero puede
            // llegar en un snapshot restaurado o una rutina vieja con `targetReps` 0), el acta se
            // cierra con lo que de verdad se hizo: la serie se queda PENDIENTE en vez de guardarse
            // como trabajo de volumen cero. Terminar nunca se bloquea; el acta nunca miente.
            if s.canRegisterCurrentSet {
                s.registerCurrentSet(restingHR: restingHrBaseline, maxHR: Double(profile.hrMax),
                                     hasLivePulse: watchBpm != nil)
            }
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
    func applyWatchWorkoutAction(_ action: WatchWorkoutAction, sessionId: String, requestedAt: Date? = nil) {
        guard let s = strengthSession, s.id == sessionId else { return }
        // Nancy · ronda 7: `transferUserInfo` es una cola DURABLE — un toque de muñeca hecho fuera de
        // alcance Bluetooth puede entregarse minutos después, cuando el descanso/serie que la usuaria
        // veía ya no existe. Mismo candado que el inbox de la Live Activity (ronda 6): si ALGÚN
        // descanso arrancó después del toque, el toque es de un contexto cerrado y se descarta.
        // `requestedAt` nil = reloj viejo sin `ts` → sin candado, como antes (degradación honesta).
        if let requestedAt, let anchor = s.lastRestStartedAt, requestedAt < anchor { return }
        switch action {
        case .completeSet:
            guard s.phase == .capturing else { return }
            // FER-257 D4: pulso vivo real — el default `true` colgaría un descanso por FC sin Watch.
            s.registerCurrentSet(restingHR: restingHrBaseline, maxHR: Double(profile.hrMax),
                                 hasLivePulse: watchBpm != nil)
        case .skipRest:
            guard s.phase == .resting else { return }
            s.skipRest()
        case let .adjustRest(deltaS):
            guard s.phase == .resting else { return }
            s.extendRest(byseconds: deltaS)   // floored at «now» by extendRest — never negative
        }
    }

    /// C1 (FER-361): the watch LOGGED a set standalone — fold it into a LIVE/adopted session by `id` via
    /// the reconciler (the ONE fold path), never gated by rest staleness (a set is a fact, not an intent).
    /// Best-effort fast-path: if the iPhone has no live session with this id (the common standalone case),
    /// it's a no-op — the authoritative `.syncSnapshot` reconciles the whole session on reconnect.
    func applyWatchLoggedSet(sessionId: String, runId: String, set: StrengthSessionSnapshot.SetSnapshot) {
        guard let session = strengthSession, session.id == sessionId, session.summary == nil else { return }
        var incoming = session.snapshot()
        guard let ri = incoming.runs.firstIndex(where: { $0.id == runId }) else { return }
        if let si = incoming.runs[ri].sets.firstIndex(where: { $0.id == set.id }) {
            incoming.runs[ri].sets[si] = set
        } else {
            incoming.runs[ri].sets.append(set)   // a new set (e.g. a watch-created drop)
        }
        let merged = StrengthSessionReconciler.merge(base: session.snapshot(), incoming: incoming)
        strengthSession = StrengthSessionModel.restore(from: merged)
        scheduleInProgressPersist()
    }

    /// C1 (FER-361): the authoritative reconciliation of a standalone watch session (+ its MEASURED
    /// avgHr/energy). If the iPhone never knew the session, ADOPT it (the watch is the source); if a live
    /// session shares the id, MERGE by id via the reconciler. Then persist through the normal end path —
    /// which stamps `bornOnWatch`/energy and, via the gate, OMITS the iPhone's own HKWorkout (the watch
    /// already saved it → one-HKWorkout, FER-740). Idempotent against a late duplicate from the durable queue.
    func applyWatchSnapshot(_ snapshot: StrengthSessionSnapshot, avgHr: Int?, energyKcal: Double?) {
        // A late duplicate after this session was already adopted + receipted: don't re-adopt / re-show it.
        if strengthSession == nil, adoptedWatchSessionIds.contains(snapshot.id) { return }
        // The watch wrote the real HKWorkout under the shared externalUUID → the iPhone must omit its save.
        noteWatchSavedWorkout(snapshot.id)

        let merged: StrengthSessionSnapshot
        if let live = strengthSession, live.id == snapshot.id {
            merged = StrengthSessionReconciler.merge(base: live.snapshot(), incoming: snapshot)
        } else {
            merged = snapshot   // adopt: the iPhone never mirrored this standalone session
            adoptedWatchSessionIds.insert(snapshot.id)
        }
        let model = StrengthSessionModel.restore(from: merged)
        model.bornOnWatch = true
        if let avgHr, let energyKcal { model.watchSyncedEnergy = (avgHr: avgHr, kcal: energyKcal) }
        strengthSession = model
        // Persist via the shared end path (guarded by `summary == nil`; the gate omits the HKWorkout).
        endStrengthSessionFromWatch(sessionId: snapshot.id, save: true)
    }

    func openWorkoutReceipt(sessionId: String) async {
        guard let s = await repo.session(id: sessionId) else { return }
        var name = String(localized: "Strength workout")
        if let rid = s.routineId, let r = (await repo.routines()).first(where: { $0.id == rid }) { name = r.name }
        pendingReceiptRoute = WorkoutSessionRoute(id: s.id, startTs: s.startTs, endTs: s.endTs,
                                                  strain: s.strain, avgHr: s.avgHr, routineName: name)
    }
}
