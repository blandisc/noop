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

    // MARK: - Guided strength session (FER-347)

    /// Begin a guided strength session from a routine's resolved plan (built by «Rutina de hoy»), and show
    /// its sheet. A no-op while one is already running, so re-tapping «Empezar» resumes rather than restarts.
    /// `programWeek`/`deload` (ola 1 · E10, FER-329) los pasa quien YA resolvió la semana —
    /// `RoutineSheetLogic.start()`, la única puerta que sirve el plan del día. Con default `nil`, todo
    /// arranque que no viene de un programa (movilidad, sesión rápida, repetir una del historial,
    /// arranque desde el reloj) guarda la columna en NULL, que es exactamente lo que significa: no
    /// había programa.
    func startStrengthSession(routineId: String?, routineName: String,
                              slots: [StrengthSessionModel.PlanSlot],
                              programWeek: Int? = nil, deload: Bool? = nil) {
        guard strengthSession == nil else { strengthSheetPresented = true; return }
        pendingHrFlush.removeAll()
        lastAcceptedHrTs = nil
        strengthSession = StrengthSessionModel.make(routineId: routineId, routineName: routineName,
                                                    slots: slots, startTs: Int(Date().timeIntervalSince1970))
        strengthSession?.programWeek = programWeek
        strengthSession?.deload = deload
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
        // FER-93: la pantalla encendida cuelga de la SESIÓN, no de una vista. Colgarla del
        // `onAppear`/`onDisappear` de la hoja la apagaba en dos momentos donde el usuario sí la
        // quiere: el modo foco y el recibo se presentan como `fullScreenCover` DESDE la hoja, y una
        // presentación así desmonta a quien presenta.
        SessionComfort.applyKeepAwake(active: true)
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
        // FER-223: evento del catálogo de Entrenar, no el `buzz` genérico de AppModel.
        EntrenarHaptic.sesionIniciada.play()
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

    /// The single sink for a raw watch pulse (FER-226 — revives the capturer killed by FER-1003's band
    /// amputation). Always publishes `watchBpm` for the live-reading views; ALSO admits the sample into
    /// the live session's HR buffer (via `StrengthHRIntake`'s pure rule) so `avgHr`/`strain`/`energySource`
    /// aren't stuck nil forever. Flushes to the store every 30 accepted samples — fire-and-forget, so this
    /// function itself never awaits (the mirroring bridge's callback is synchronous).
    func ingestWatchPulse(bpm: Int) {
        watchBpm = bpm
        guard let session = strengthSession, session.summary == nil else { return }
        guard let accepted = StrengthHRIntake.accept(bpm: bpm, ts: Date(), lastTs: lastAcceptedHrTs,
                                                     paused: session.paused) else { return }
        lastAcceptedHrTs = accepted.ts   // second-truncated — same precision `accept` compares next time
        let sample = HRSample(ts: Int(accepted.ts.timeIntervalSince1970), bpm: accepted.bpm)
        session.hrSamples.append(sample)
        pendingHrFlush.append(sample)
        // FER-226 round 2 (D3): only fire a new flush while none is already in flight — two overlapping
        // flushes each doing `removeFirst(batch.count)` against a buffer the OTHER one already trimmed
        // silently drops samples neither of them ever wrote.
        guard !isFlushingHR, pendingHrFlush.count >= 30 else { return }
        flushPendingHR(sessionId: session.id)
    }

    /// Drains `pendingHrFlush` to the store. On failure the batch is left in place — the (sessionId, ts)
    /// primary key makes a retry idempotent for whatever already landed. Guarded by `isFlushingHR` so a
    /// second flush can never start while this one is still trimming the buffer it read (D3).
    private func flushPendingHR(sessionId: String) {
        let batch = pendingHrFlush
        guard !batch.isEmpty else { return }
        isFlushingHR = true
        Task { [weak self] in
            guard let self else { return }
            defer { self.isFlushingHR = false }
            guard let store = await self.repo.storeHandle() else { return }
            do {
                try await store.appendStrengthHR(sessionId: sessionId, samples: batch)
                self.pendingHrFlush.removeFirst(min(batch.count, self.pendingHrFlush.count))
            } catch {
                // Left in place — the next flush (30 more samples, or the save-time drain) retries it.
            }
        }
    }

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
            SessionComfort.applyKeepAwake(active: false)
            RestEndNotifier.cancel()   // el aviso no puede sobrevivir a la sesión que lo pidió
            releaseRealtimeHR("strength")
            clearInProgressSession()   // FER-798: nothing to recover once discarded
            pendingHrFlush.removeAll()
            lastAcceptedHrTs = nil
            Task { [weak self] in try? await self?.repo.storeHandle()?.deleteStrengthHR(sessionId: session.id) }
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
        }
        // Ola 1 · E3 (FER-330) — the receipt asks «¿qué tan duro estuvo?» ALWAYS (D-Q13). If the
        // work sets already carry RPE, seed the SUGGESTED answer as `.prefill` so closing the receipt
        // without a tap still estimates the load (A1). The receipt draws it dotted — Sweet 2004: the
        // per-set mean sits above the session rating — and never presents it as a confirmed answer.
        // Tapping in the receipt upgrades to `.answered` (or clears to nil); see
        // `updateStrengthSessionEffort`. The LOAD is resolved in `attemptStrengthSave`.
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
        guard var pending = pendingStrengthSave else { return }
        pendingStrengthSave = nil
        // Ola 1 · E3: seed the suggested session effort BEFORE resolving load, so a receipt closed
        // without a tap still stores `.prefill` (A1). No rated work sets → leave nil (A2).
        if pending.record.sessionRpe == nil,
           let prefill = SessionRPE.prefill(sets: pending.sets) {
            pending.record.sessionRpe = prefill
            pending.record.sessionRpeSource = .prefill
        }
        // Ola 1 · E2 — where this session's LOAD comes from, decided ONCE, right before it is stored.
        let elapsedS = (pending.record.endTs ?? pending.record.startTs) - pending.record.startTs
        let resolved = Self.resolveStrengthLoad(hrSamples: pending.hrSamples, elapsedSeconds: elapsedS,
                                                sessionRpe: pending.record.sessionRpe,
                                                trimpPerAU: StrengthLoadCalibration.current,
                                                hrMax: Double(pending.hrMax), sex: pending.userProfile.sex)
        pending.record.strain = resolved.strain
        pending.record.strainSource = resolved.source
        pending.record.trimpPerAU = resolved.trimpPerAU
        // Prior PRs (BEFORE save) so the receipt can tell which records are NEW this session.
        let prior = await priorStrengthPRs(store: store, ids: Set(pending.sets.map(\.exerciseId)))
        // FER-226: flush whatever the 30-sample threshold hasn't drained yet — the last partial batch
        // must not be lost just because the session is ending. Best-effort: a failure here just means
        // the tail of the HR series is missing, not that the save itself should be blocked.
        if !pendingHrFlush.isEmpty {
            try? await store.appendStrengthHR(sessionId: session.id, samples: pendingHrFlush)
            pendingHrFlush.removeAll()
        }
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
        // FER-93: la sesión terminó y guardó. El descanso ya no existe, así que su aviso tampoco:
        // este es el camino normal de «Terminar», que no pasa por `clearRest`.
        RestEndNotifier.cancel()
        // Surface the receipt on the live session — the sheet renders summaryPhase (session stays alive).
        session.summary = await buildStrengthSummary(session: session, record: pending.record,
                                                     sets: pending.sets, prior: prior, store: store)
        // Ola 1 · E2: this session may have completed a calibration pair. Off the receipt's path —
        // the user is looking at the summary, not waiting for a re-fit.
        Task { [weak self] in await self?.recalibrateStrengthLoadIfNeeded(store: store) }
        // FER-223: la sesión cerró y guardó — no tenía ningún háptico. Mismo patrón de éxito
        // ascendente que `prNuevo` (ambos son un cierre, nunca coinciden en el mismo segundo).
        EntrenarHaptic.sesionTerminada.play()
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
        // FER-93: aquí se cierra de verdad la sesión (el recibo ya se leyó), así que aquí se
        // restaura el auto-bloqueo y se retira cualquier aviso pendiente. Ninguno de los dos puede
        // sobrevivir a la sesión que los pidió.
        SessionComfort.applyKeepAwake(active: false)
        RestEndNotifier.cancel()
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
        // Ola 1 · E2: the recovery COST is cardiovascular, so it reads the pulse whenever the pulse
        // covered the session — even when the day's LOAD was estimated from effort. Without a usable
        // pulse it falls back to whatever the session stored, exactly as before.
        let cardiovascularStrain = Self.measuredStrain(hrSamples: session.hrSamples,
                                                       elapsedSeconds: durationS,
                                                       hrMax: Double(profile.hrMax), sex: profile.sex)
            // Ola 1 · E3 (gate /qa D1): una carga ESTIMADA por esfuerzo nunca se disfraza de costo
            // cardiovascular — sin pulso, el bloque de costo no se pinta (D-Q13).
            ?? (record.strainSource == .rpe ? nil : record.strain)

        // Resolve exercises (bundled catalog + user-created) for names + muscles.
        let custom = (try? await store.customExercises()) ?? []
        let customByID = Dictionary(custom.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        func exercise(_ id: String) -> Exercise? { ExerciseCatalog.byID(id) ?? customByID[id] }

        // NEW records: this session's per-exercise bests that strictly beat the prior PR.
        var prs: [StrengthSummary.PR] = []
        // Ola 1 · FER-327: los RÉCORDS del recibo leen la MISMA tabla que la base (`SetMode.counts`) —
        // el drop queda fuera. `work` de arriba NO se toca: ese sí alimenta el volumen, donde un drop
        // cuenta (movió kilos de verdad). Es el único punto de esta pantalla donde el modo importa.
        let recordEligible = work.filter { (s: SetEntry) in s.counts(for: .records) }
        for (id, exSets) in Dictionary(grouping: recordEligible, by: \.exerciseId) {
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

        // Músculos trabajados (FER-124): principales Y de apoyo, en orden de serie, sin repetir.
        // El principal gana: si un músculo es protagonista en un ejercicio y de apoyo en otro, se
        // marca principal (negrita en el acta). El catálogo ya distinguía los dos — el acta no.
        let muscles = StrengthSummary.worked(
            primaryPerSet: work.map { exercise($0.exerciseId)?.primaryMuscles ?? [] },
            secondaryPerSet: work.map { exercise($0.exerciseId)?.secondaryMuscles ?? [] },
            titleCase: StrengthDisplay.titleCase)

        // Tomorrow's projection given today's session cost (FER-442): recovery base = repo.days
        // (already oldest→newest from Repository; nils kept so the engine respects missing-day
        // spacing). "Si descansas bien" → no sleep-debt drag; the only downward pull is the acute
        // session strain. nil (→ the line is hidden) when there's no strain or fewer than ~2 weeks
        // of base — we never invent a number.
        let recoverySeries = repo.days.map(\.recovery)
        // Same source as `costBand` on the same card: the pulse when it covered the session, else the
        // session's load — never one line from the pulse and the next from the estimate (gate /qa D4).
        let costTomorrowPct: Int? = cardiovascularStrain.flatMap { strain in
            RecoveryForecast.compute(recovery: recoverySeries, sessionStrain: strain)
                .map { Int($0.estimate.rounded()) }
        }

        return StrengthSummary(routineName: session.routineName,
                               endTs: record.endTs ?? record.startTs, durationS: durationS,
                               volumeKg: volumeKg, setCount: work.count, strain: record.strain,
                               strainSource: record.strainSource,
                               sessionRpe: record.sessionRpe,
                               sessionRpeSource: record.sessionRpeSource,
                               avgHr: record.avgHr,
                               costBand: SessionRecoveryCost.cost(sessionStrain: cardiovascularStrain)?.band,
                               costTomorrowPct: costTomorrowPct,
                               energyKcal: record.energyKcal, energySource: record.energySource,
                               prs: prs, muscles: Array(muscles.prefix(8)),
                               isFirstTime: prior.allSatisfy { $0.value.isEmpty },
                               comparison: comparison, exercises: exerciseLines)
    }

    /// Ola 1 · E3: the receipt just changed the live session's rating. Re-resolves load and patches
    /// the summary numeral in place.
    func updateStrengthSessionEffort(rpe: Double?, source: SessionRpeSource?) async {
        guard let session = strengthSession, let summary = session.summary else { return }
        await updateStoredSessionEffort(sessionId: session.id, durationS: summary.durationS,
                                        rpe: rpe, source: source, hrSamples: session.hrSamples)
    }

    /// Ola 1 · E3: write a session-effort answer for ANY finished strength session (receipt or
    /// detail «Calificar esfuerzo…»). Passing `rpe == nil` clears the rating and falls back to a
    /// measured pulse when one covered the session. When `hrSamples` is nil, loads them from the store.
    func updateStoredSessionEffort(sessionId: String, durationS: Int,
                                   rpe: Double?, source: SessionRpeSource?,
                                   hrSamples: [HRSample]? = nil) async {
        let samples: [HRSample]
        if let hrSamples {
            samples = hrSamples
        } else if let store = await repo.storeHandle() {
            samples = (try? await store.strengthHRSamples(sessionId: sessionId)) ?? []
        } else {
            samples = []
        }
        let resolved = Self.resolveStrengthLoad(hrSamples: samples, elapsedSeconds: durationS,
                                                sessionRpe: rpe,
                                                trimpPerAU: StrengthLoadCalibration.current,
                                                hrMax: Double(profile.hrMax), sex: profile.sex)
        do {
            try await repo.updateSessionEffort(sessionId: sessionId,
                                               sessionRpe: rpe,
                                               sessionRpeSource: rpe == nil ? nil : source,
                                               strain: resolved.strain,
                                               strainSource: resolved.source,
                                               trimpPerAU: resolved.trimpPerAU)
        } catch {
            return
        }
        if let session = strengthSession, session.id == sessionId, var summary = session.summary {
            summary.sessionRpe = rpe
            summary.sessionRpeSource = rpe == nil ? nil : source
            summary.strain = resolved.strain
            summary.strainSource = resolved.source
            session.summary = summary
        }
        if let store = await repo.storeHandle() {
            Task { [weak self] in await self?.recalibrateStrengthLoadIfNeeded(store: store) }
        }
        Task { await repo.refresh() }
    }

    // MARK: - Ola 1 · E2 · where a strength session's load comes from

    /// The pulse-measured load, or nil when the pulse didn't cover enough of the session
    /// (`HRCoverage`, gate estadístico H1). Pure so the matrix is testable without a store.
    nonisolated static func measuredStrain(hrSamples: [HRSample], elapsedSeconds: Int,
                                           hrMax: Double, sex: String) -> Double? {
        guard HRCoverage.isMeasured(hrSamples, elapsedSeconds: elapsedSeconds) else { return nil }
        return StrainScorer.strain(hrSamples, maxHR: hrMax, sex: sex)
    }

    /// THE rule for a strength session's load — one source, never a sum:
    /// 1. a rating → minutes × effort (`SessionRPELoad`), `strainSource == .rpe`. The rating wins
    ///    because heart rate does not discriminate intensity in resistance-type work (Falk Neto 2020,
    ///    functional fitness, n = 8) while perceived effort does in lifting (Day 2004, Sweet 2004,
    ///    Haddad 2017);
    /// 2. no rating but a pulse that actually covered the session → Edwards TRIMP, `.hr` — the same
    ///    number this path has always stored;
    /// 3. neither → `nil`. «Entrenaste, carga sin estimar» is a hold, never a zero.
    /// The pulse keeps feeding `avgHr` and the recovery cost in every case: only the LOAD is single-sourced.
    nonisolated static func resolveStrengthLoad(hrSamples: [HRSample], elapsedSeconds: Int,
                                                sessionRpe: Double?, trimpPerAU: Double,
                                                hrMax: Double, sex: String)
        -> (strain: Double?, source: StrainSource?, trimpPerAU: Double?) {
        if let rpe = sessionRpe,
           let s = SessionRPELoad.strain(durationS: elapsedSeconds, rpe: rpe, trimpPerAU: trimpPerAU) {
            return (s, .rpe, trimpPerAU)
        }
        if let s = measuredStrain(hrSamples: hrSamples, elapsedSeconds: elapsedSeconds,
                                  hrMax: hrMax, sex: sex) {
            return (s, .hr, nil)
        }
        return (nil, nil, nil)
    }

    /// Re-fit the personal TRIMP-per-AU scale from the sessions that carry BOTH a rating and a pulse
    /// good enough to measure, and — only when the fit is accepted (`SessionRPELoad.shouldAcceptRefit`:
    /// the evidence doubled AND the scale really moved) — rewrite every estimated session onto it in
    /// one write, so the receipt, the history and Tendencias never disagree about the same session.
    func recalibrateStrengthLoadIfNeeded(store: CenitStore) async {
        guard let candidates = try? await store.strengthCalibrationPairs() else { return }
        let hrMax = Double(profile.hrMax), sex = profile.sex
        let pairs: [(au: Double, trimp: Double)] = candidates.compactMap { c in
            let elapsed = c.endTs - c.startTs
            guard let au = SessionRPELoad.arbitraryUnits(durationS: elapsed, rpe: c.sessionRpe),
                  let measured = Self.measuredStrain(hrSamples: c.hrSamples, elapsedSeconds: elapsed,
                                                     hrMax: hrMax, sex: sex)
            else { return nil }
            return (au, StrainScorer.strainToTrimp(measured))
        }
        guard let candidate = SessionRPELoad.fitTrimpPerAU(pairs: pairs),
              SessionRPELoad.shouldAcceptRefit(pairCount: pairs.count,
                                               lastFitPairCount: StrengthLoadCalibration.lastFitPairCount,
                                               currentTrimpPerAU: StrengthLoadCalibration.current,
                                               candidateTrimpPerAU: candidate)
        else { return }
        // The scale is accepted only AFTER the rewrite succeeded: a new k with old sessions is the
        // very inconsistency the single write exists to prevent (gate /qa D3).
        do {
            _ = try await store.recomputeEstimatedStrain(trimpPerAU: candidate) { durationS, rpe in
                SessionRPELoad.strain(durationS: durationS, rpe: rpe, trimpPerAU: candidate)
            }
        } catch { return }
        StrengthLoadCalibration.accept(candidate, pairCount: pairs.count)
    }
}

/// The personal TRIMP-per-AU scale for estimated strength load (ola 1 · E2). Two numbers, on device:
/// the scale in use and how many pairs fitted it — the second one is what makes the refit wait for the
/// evidence to DOUBLE instead of drifting band by band on noise (gate estadístico H4). No schema: this
/// is a preference of the estimate, not data about the body.
enum StrengthLoadCalibration {
    static let scaleKey = "strength.trimpPerAU"
    static let pairsKey = "strength.trimpPerAU.pairs"

    /// The scale in use — the calibration default until a fit has been accepted.
    static var current: Double {
        UserDefaults.standard.object(forKey: scaleKey) as? Double ?? SessionRPELoad.defaultTrimpPerAU
    }
    /// How many pairs produced the scale in use; nil = never fitted.
    static var lastFitPairCount: Int? { UserDefaults.standard.object(forKey: pairsKey) as? Int }

    static func accept(_ trimpPerAU: Double, pairCount: Int) {
        UserDefaults.standard.set(trimpPerAU, forKey: scaleKey)
        UserDefaults.standard.set(pairCount, forKey: pairsKey)
    }
}
