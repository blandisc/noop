#if os(iOS)
import SwiftUI
import StrandDesign
import StrandTraining
import StrandAnalytics

// MARK: - HojaSesionViva — el motor del bucle B1-B4 (FER-167 · F2, ronda 2)
//
// Toda mutación reusa la API vigente de `StrengthSessionModel` (NO se reescribe: v40 ya trae la
// captura del descanso real) — este archivo solo decide QUÉ llamar y CUÁNDO, igual que
// `LiveStrengthSheet.registerActiveSet`/`confirmOrToggleSet`, de donde está portado 1:1 (el modelo
// es el mismo, así que el contrato es idéntico; lo único que cambia es la piel que lo dispara).
//
// REGLA DURA (ronda 2): cero identidad por índice. El ancla del descanso (`accordionIndex`) se
// DERIVA de `session.restOwnerSetId` (v40, viaja en el snapshot) — no hay `@State restAnchorEi: Int`
// que un reorden (Subir/Bajar) pueda desincronizar.

extension HojaSesionViva {

    // MARK: - Avance («Serie N de M» — unidad única: cabecera, píldora y riel)

    var totalSets: Int { session.doneCount + session.pendingCount }

    /// N de la unidad «Serie N de M»: la posición de la PRÓXIMA serie a capturar (1-based); una vez
    /// completa, N == total (mapa B16: «18 de 18 · completa»).
    var serieActual: Int { session.isComplete ? totalSets : session.doneCount + 1 }

    var serieSubtitle: String {
        session.isComplete
            ? String(localized: "\(totalSets) of \(totalSets) · complete")
            : String(localized: "Set \(serieActual) of \(totalSets)")
    }

    var fraccionAvance: CGFloat {
        guard totalSets > 0 else { return 0 }
        return CGFloat(session.doneCount) / CGFloat(totalSets)
    }

    /// El tinte de familia de la cabecera/riel — el grupo muscular más representado entre los
    /// ejercicios activos (mismo criterio que `RoutineSheetLogic.refreshTint`, pero leyendo el
    /// catálogo por `exerciseId` en vez de `EditorItem.exercise` — la Hoja viva no carga esa lista).
    var familyTint: Color {
        var tally: [MuscleGroup: Int] = [:]
        for (_, run) in session.activeExercises {
            guard let ex = ExerciseCatalog.byID(run.exerciseId) else { continue }
            for m in ex.primaryMuscles { if let g = MuscleGroup.of(m) { tally[g, default: 0] += 1 } }
        }
        var best: MuscleGroup?
        var bestCount = 0
        for g in MuscleGroup.allCases where (tally[g] ?? 0) > bestCount {
            best = g; bestCount = tally[g] ?? 0
        }
        return best?.tint(sheet.theme) ?? sheet.theme.inkTertiary
    }

    // MARK: - Pausa (misma decisión que la cabecera y el teclado se turnan — una sola, dos superficies)

    var alternarPausa: (() -> Void)? {
        guard session.summary == nil else { return nil }
        return {
            if session.paused { sheet.model.resumeStrengthSessionFromPause() }
            else { sheet.model.pauseStrengthSession() }
        }
    }

    /// R2(a): la puerta a Foco — paridad `SessionStatsBar.onFocus` (`LiveStrengthSheet.puedeEnfocar`).
    var puedeEnfocar: Bool { session.summary == nil && !session.isComplete && !isZombie }

    // MARK: - B15b — sesión zombie (quedó abierta un día calendario distinto)

    /// Umbral decidido aquí (el mapa no fija horas, solo «AYER»): cambio de DÍA CALENDARIO local
    /// entre el arranque de la sesión y ahora — no una ventana de N horas.
    var isZombie: Bool {
        !Calendar.current.isDateInToday(Date(timeIntervalSince1970: Double(session.startTs)))
    }

    /// ARCHIVAR (B15b): el flujo de terminar VIGENTE (`AppModel.endStrengthSession`) — genera el
    /// acta con lo hecho hasta ahora, igual que «Terminar y guardar».
    func archivarZombie() {
        sheet.model.endStrengthSession(save: true)
    }

    // MARK: - El núcleo de ✓ (porteado de `LiveStrengthSheet.registerActiveSet`/`confirmOrToggleSet`)

    /// Desmarcar una serie hecha es corrección sin descanso; palomear la pendiente la selecciona (si
    /// no era ya la activa) y registra con su descanso real.
    func confirmOrToggleSet(ei: Int, si: Int) {
        guard session.runs.indices.contains(ei), session.runs[ei].sets.indices.contains(si) else { return }
        let set = session.runs[ei].sets[si]
        let isCurrent = si == session.runs[ei].currentSet && !set.done
        withAnimation(reduceMotion ? nil : .snappy) {
            if set.done {
                session.toggleDone(exercise: ei, set: si)
            } else {
                activeCell = nil
                if !isCurrent { session.select(exerciseIndex: ei, setIndex: si) }
                registerActiveSet(ei: ei, si: si)
            }
        }
    }

    /// Todo «✓» de la Hoja viva pasa por aquí: registra (con el QUEDABAN elegido si aplica), limpia
    /// el RIR de la celda, revisa PR (R16) y da la háptica. `ei`/`si` son la celda que se ESTABA
    /// mirando ANTES de registrar (para el RIR/PR de ESA serie) — el modelo puede haber avanzado el
    /// foco a otra ya para cuando este método termina.
    func registerActiveSet(ei: Int, si: Int) {
        session.registerCurrentSet(restingHR: restingBaseline, maxHR: profileMaxHR)
        let rirForThisSet = LiveStrengthSheet.rirScoped(
            selectedRIR: selectedRIR, selectedRIRTarget: selectedRIRTarget,
            registering: LiveStrengthSheet.RIRTarget(ei: ei, si: si))
        if session.runs.indices.contains(ei), session.runs[ei].sets.indices.contains(si) {
            let registered = session.runs[ei].sets[si]
            if let rpe = LiveStrengthSheet.rpeToWrite(selectedRIR: rirForThisSet, existingRPE: registered.rpe) {
                session.setRPE(exercise: session.runs[ei].id, set: registered.id, rpe: rpe)
            }
            checkForPR(ei: ei, set: registered)   // R16
        }
        selectedRIR = nil
        selectedRIRTarget = nil
        sheet.model.buzz(loops: 1)   // háptica al palomear (contrato F1/F2: hápticas en palomear/fin de descanso/arranque)
    }

    /// SALTAR (B2/B3 consola, mock P4): el mismo `skipRest()` que el botón «SALTAR ›» de la banda.
    func skipRest() {
        withAnimation(reduceMotion ? nil : StrandMotion.gentle) { session.skipRest() }
    }

    // MARK: - R16 · destello de récord (detección VIGENTE — `PRMetric`, sin redefinir tipos, F4/B11 intacto)

    /// Carga los PR de cada ejercicio de la sesión una sola vez al abrir — la referencia contra la
    /// que `checkForPR` compara cada serie que se palomea.
    func loadPersonalRecords() async {
        guard let store = await sheet.repo.storeHandle() else { return }
        var built: [String: [PRMetric: PersonalRecord]] = [:]
        for exId in Set(session.runs.map(\.exerciseId)) {
            guard let prs = try? await store.personalRecords(exerciseId: exId) else { continue }
            built[exId] = Dictionary(uniqueKeysWithValues: prs.map { ($0.metric, $0) })
        }
        personalRecords = built
    }

    /// Si la serie recién registrada bate cualquiera de los 3 `PRMetric` (peso máximo, reps máximas,
    /// volumen máximo — SIN 1RM, eso sigue sin existir aquí, F4/B11) contra los PR cargados al abrir,
    /// arma el destello breve (`prFlashSetId`), que `HojaFilaSerie`'s caller apaga solo tras un rato.
    private func checkForPR(ei: Int, set: StrengthSessionModel.WorkingSet) {
        guard set.kind == .work, session.runs.indices.contains(ei) else { return }
        let exId = session.runs[ei].exerciseId
        let prs = personalRecords[exId] ?? [:]
        let volume = set.weightKg * Double(set.reps)
        let beatsWeight = (prs[.maxWeight]?.valueKg).map { set.weightKg > $0 } ?? (set.weightKg > 0)
        let beatsReps = (prs[.maxReps]?.reps).map { set.reps > $0 } ?? (set.reps > 0)
        let beatsVolume = (prs[.maxVolume]?.valueKg).map { volume > $0 } ?? (volume > 0)
        guard beatsWeight || beatsReps || beatsVolume else { return }
        prFlashSetId = set.id
        Task {
            try? await Task.sleep(for: .seconds(1.1))
            if prFlashSetId == set.id { prFlashSetId = nil }
        }
    }

    // MARK: - Descanso: dónde ancla la banda + qué combustible dibuja (porteado de `restBandHRBody`/`restBandTimeBody`)

    /// R7: el ejercicio dueño del descanso — derivado de `session.restOwnerSetId` (el SET que lo
    /// abrió, v40), nunca un `@State` `Int` que un reorden («Subir») podría dejar apuntando al
    /// ejercicio que ocupó ese slot. `nil` cuando no hay descanso en vuelo o su set dueño ya no existe.
    var restOwnerExerciseIndex: Int? {
        guard let ownerId = session.restOwnerSetId else { return nil }
        return session.runs.firstIndex { $0.sets.contains { $0.id == ownerId } }
    }

    /// O-r2a (ronda 3): quién se muestra a tinta plena. Mientras se descansa, el ancla automática es
    /// el dueño del descanso — SALVO que el usuario haya tocado explícitamente una tarjeta plegada
    /// para verla (`peekRunId`, por `id` — regla dura, nunca un índice que sobreviva un reorden): el
    /// select explícito GANA la tarjeta abierta. El descanso en sí NO se toca (`session.phase` sigue
    /// `.resting`, el auto-skip sigue vivo — ver `RestAutoSkipModifier`, ahora colgado a nivel de
    /// `HojaSesionViva.body` para que sobreviva aunque la tarjeta dueña se pliegue); solo la banda
    /// deja de verse, porque su tarjeta (la dueña) ya no es la que está abierta. Documentado aquí y
    /// en `HojaPlegadaSesion` (dónde se arma `peekRunId`) y en `restSlotIndex` (por qué NO usa esto).
    var accordionIndex: Int {
        guard session.phase == .resting else { return session.currentIndex }
        if let peekId = peekRunId, let idx = session.runs.firstIndex(where: { $0.id == peekId }) { return idx }
        return restOwnerExerciseIndex ?? session.currentIndex
    }

    /// El índice donde la banda debe insertarse: justo tras la última fila hecha de ESE ejercicio —
    /// `nil` cuando el ejercicio ya no tiene fila pendiente que anclar (la tarjeta la muestra en su
    /// pie). Ancla contra el DUEÑO real (`restOwnerExerciseIndex`), NUNCA contra `accordionIndex`
    /// (O-r2a): mientras el usuario espía otra tarjeta (`peekRunId`), `accordionIndex` apunta ahí,
    /// pero la banda sigue siendo del dueño — si su tarjeta quedó plegada, la banda simplemente no
    /// se pinta en ningún lado (no se reasigna a la tarjeta espiada, que no es la que descansa).
    func restSlotIndex(ei: Int) -> Int? {
        guard session.phase == .resting, ei == restOwnerExerciseIndex, session.summary == nil,
              session.runs.indices.contains(ei) else { return nil }
        let run = session.runs[ei]
        guard let lastDone = run.sets.lastIndex(where: { $0.done }) else {
            return run.sets.isEmpty ? nil : 0
        }
        let si = run.sets.index(after: lastDone)
        return run.sets.indices.contains(si) ? si : nil
    }

    private var restingBaseline: Double? {
        let restingHrs: [Int] = sheet.repo.days.compactMap(\.restingHr)
        return restingHrs.last.map(Double.init)
    }
    private var profileMaxHR: Double { Double(sheet.model.profile.hrMax) }

    private var accordionRestRun: StrengthSessionModel.ExerciseRun? {
        session.runs.indices.contains(accordionIndex) ? session.runs[accordionIndex] : nil
    }

    private var restBandKicker: LocalizedStringKey {
        guard let run = accordionRestRun, let lastDone = run.sets.lastIndex(where: { $0.done }) else { return "REST" }
        let from = run.sets.prefix(lastDone + 1).reduce(0) { $0 + ($1.kind == .work ? 1 : 0) }
        guard from > 0 else { return "REST" }
        let nextIdx = run.sets.index(after: lastDone)
        let to = run.sets.indices.contains(nextIdx)
            ? run.sets.prefix(nextIdx + 1).reduce(0) { $0 + ($1.kind == .work ? 1 : 0) }
            : from + 1
        return "REST · SET \(String(from)) → \(String(to))"
    }

    /// O-r2a (ronda 3): el auto-skip (R1) ya NO cuelga de `restBand()` — esa vista solo se monta
    /// bajo la tarjeta del DUEÑO, que puede plegarse mientras el usuario espía otra (`peekRunId`), y
    /// SwiftUI cancela el `.task` de una vista que sale del árbol. Colgado en cambio de
    /// `HojaSesionViva.body` (siempre presente), el auto-skip sigue vivo pase lo que pase con el
    /// acordeón — «el auto-skip no cambia» es la garantía, no una promesa vacía.
    func restAutoSkipModifier() -> some ViewModifier { RestAutoSkipModifier(vivo: self) }

    /// O-r2b (ronda 3): la consola dice lo MISMO que la banda en el tope — «Continuar ›», no
    /// «Saltar ›» (misma razón `.ceiling` que `restBandCore` ya evalúa, aquí expuesta como función
    /// pura para que `keypadInset` la re-consulte cada segundo con su propio `TimelineView`).
    func isCeilingReleased(now: Date) -> Bool {
        guard session.phase == .resting, session.currentRestMode == .heartRate,
              let started = session.restStartedAt else { return false }
        let tick = session.paused ? (session.pausedAt ?? now) : now
        let elapsed = max(0, Int(tick.timeIntervalSince(started)))
        let v = RestReadinessRule.evaluate(currentHR: sheet.model.watchBpm, worn: sheet.model.watchBpm != nil,
                                           restingHR: restingBaseline, elapsedS: elapsed, targetHR: session.currentRestTarget)
        return v.reason == .ceiling && (v.bpmToReady ?? 0) > 0
    }

    /// La banda de descanso ANCLADA (mock P4): dos combustibles — FC dice la meta («baja a N»,
    /// `RestBand` ya lo pinta desde FER-167), reloj fijo cuando no hay Watch. R13: con razón
    /// `.ceiling` y el pulso TODAVÍA arriba de la meta, la banda no dice «Listo» — dice el tope
    /// honesto y ofrece SEGUIR. R4: la misma función alcanza también a la superserie (Tarjeta.swift
    /// la monta igual).
    @ViewBuilder func restBand() -> some View {
        VStack(alignment: .leading, spacing: CenitMetrics.space2) {
            restBandCore()
            // R11(a): «Cambiar descanso» — el editor de umbral (capacidad intacta), paridad
            // `LiveStrengthSheet.restEditorPill`. `RestBand` no trae este control; se queda como
            // pastilla propia bajo la banda.
            if let ei = restOwnerExerciseIndex {
                Button { openRestEditor(ei: ei) } label: {
                    Label("Change rest", systemImage: "pencil").font(StrandFont.caption).foregroundStyle(sheet.theme.ink)
                        .padding(.horizontal, 13).padding(.vertical, 6)
                        .overlay(Capsule().strokeBorder(sheet.theme.hairlineStrong, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder private func restBandCore() -> some View {
        let hrMode = session.currentRestMode == .heartRate
        Group {
            if hrMode, let started = session.restStartedAt {
                TimelineView(.periodic(from: started, by: 1)) { ctx in
                    let tick = session.paused ? (session.pausedAt ?? ctx.date) : ctx.date
                    let elapsed = max(0, Int(tick.timeIntervalSince(started)))
                    let v = RestReadinessRule.evaluate(
                        currentHR: sheet.model.watchBpm, worn: sheet.model.watchBpm != nil, restingHR: restingBaseline,
                        elapsedS: elapsed, targetHR: session.currentRestTarget)
                    if v.state == .noSignal {
                        restBandTimeBody(end: session.restEndsAt, now: tick, noStrapFallback: true)
                    } else {
                        let ceiling = v.reason == .ceiling && (v.bpmToReady ?? 0) > 0
                        RestBand(kicker: restBandKicker,
                                 mode: .heartRate(remainingBpm: v.bpmToReady, targetBpm: v.targetReadyHR ?? 0,
                                                  currentBpm: sheet.model.watchBpm),
                                 trailing: SessionClock.format(elapsed),
                                 note: "at 5 bpm I say «almost» · at 3:00 I let you go even if it hasn't dropped",
                                 isAlmost: v.state == .almostReady, isReady: v.ready, isCeilingRelease: ceiling,
                                 startBpm: restStartBpm,
                                 onSkip: { skipRest() })
                            .accessibilityAddTraits(.updatesFrequently)
                    }
                }
            } else if let end = session.restEndsAt, let started = session.restStartedAt {
                TimelineView(.periodic(from: started, by: 1)) { ctx in
                    restBandTimeBody(end: end, now: session.paused ? (session.pausedAt ?? ctx.date) : ctx.date, noStrapFallback: false)
                }
            }
        }
    }

    private func restBandTimeBody(end: Date?, now: Date, noStrapFallback: Bool) -> some View {
        let started = session.restStartedAt ?? now
        let cappedEnd = noStrapFallback ? min(end ?? now, started.addingTimeInterval(300)) : end
        let totalS = cappedEnd.map { max(0, Int($0.timeIntervalSince(started))) } ?? 0
        let elapsed = max(0, min(totalS, Int(now.timeIntervalSince(started))))
        return RestBand(kicker: restBandKicker,
                         mode: .clock(elapsed: SessionClock.format(elapsed), target: SessionClock.format(totalS)),
                         trailing: sheet.model.watchBpm == nil ? String(localized: "no watch on your wrist") : SessionClock.format(elapsed),
                         note: noStrapFallback ? "resting by clock: connect your Apple Watch for rest by heart rate" : nil,
                         onSkip: { skipRest() })
            .accessibilityAddTraits(.updatesFrequently)
    }

    // MARK: - «···» del ejercicio (R8, porteado completo de `LiveStrengthSheet.exerciseMenuItems`)

    func exerciseMenuItems(ei: Int, run: StrengthSessionModel.ExerciseRun) -> [PaperMenuItem] {
        var rows: [PaperMenuItem] = []
        if ei > 0 {
            rows.append(.init(String(localized: "Move up"), systemImage: "arrow.up") {
                withAnimation(reduceMotion ? nil : .snappy) { session.moveExerciseEarlier(ei) }
            })
        }
        if ei < session.runs.count - 1 {
            rows.append(.init(String(localized: "Move down"), systemImage: "arrow.down") {
                withAnimation(reduceMotion ? nil : .snappy) { moveExerciseLater(ei) }
            })
        }
        if ei < session.runs.count - 1 {
            let paired = run.supersetGroup != nil && run.supersetGroup == session.runs[ei + 1].supersetGroup
            rows.append(.init(String(localized: paired ? "Undo superset" : "Superset with next"),
                              systemImage: "link") {
                if !paired, session.runs[ei + 1].supersetGroup != nil {
                    confirmSupersetSteal = ei
                } else {
                    withAnimation(reduceMotion ? nil : .snappy) { session.toggleSupersetWithNext(ei) }
                    persistSupersetGroups()
                }
            })
        }
        rows.append(.init(String(localized: "Progression"), subtitle: progressionSubtitle(run),
                          systemImage: "chart.line.uptrend.xyaxis") {
            progressionEdit = LiveStrengthSheet.ProgressionEditTarget(id: ei)
        })
        rows.append(.init(String(localized: "Change exercise"), systemImage: "arrow.triangle.2.circlepath") {
            changeExercise = LiveStrengthSheet.ChangeTarget(ei: ei, run: run)
        })
        if puedeEnfocar {
            rows.append(.init(String(localized: "Focus"), systemImage: "arrow.up.left.and.arrow.down.right") {
                focusMode = true
            })
        }
        if session.runs.count > 1 {
            rows.append(.init(String(localized: "Remove from session"), systemImage: "trash", isDestructive: true) {
                withAnimation(reduceMotion ? nil : .snappy) { session.removeExercise(at: ei) }
            })
        }
        return rows
    }

    /// «Bajar» — el modelo solo trae `moveExerciseEarlier`; una posición más tarde es el mismo swap
    /// al revés, manteniendo el foco guiado si le tocaba a él (misma garantía que `moveExerciseEarlier`).
    private func moveExerciseLater(_ ei: Int) {
        guard session.runs.indices.contains(ei + 1) else { return }
        session.moveExerciseEarlier(ei + 1)
    }

    /// «activada · +2,5 kg cada 2 ✓» / «desactivada» — paridad `LiveStrengthSheet.progressionSubtitle`.
    private func progressionSubtitle(_ run: StrengthSessionModel.ExerciseRun) -> String {
        guard let re = routineREs[run.id], re.progressionEnabled else { return String(localized: "off") }
        let derived = PlateMath.minimumIncrement(for: .from(equipment: ExerciseCatalog.byID(run.exerciseId)?.equipment),
                                                 inventory: sheet.model.plates.inventory)
        return String(localized: "on") + " · " + ProgressionChip.summary(re, system: sheet.system, derived: derived)
    }

    /// R8: el «robo» de superserie pide confirmar antes de deshacer la pareja del vecino — paridad
    /// `LiveStrengthSheet.bodySupersetStealMessage`.
    var supersetStealMessage: String {
        let neighborName: String = confirmSupersetSteal.flatMap { ei -> String? in
            let next = ei + 1
            guard session.runs.indices.contains(next) else { return nil }
            return session.runs[next].name
        } ?? ""
        return String(format: String(localized: "%@ is already paired in another superset. Pairing it here undoes that one."),
                      neighborName)
    }

    func confirmSupersetStealAndPair() {
        guard let ei = confirmSupersetSteal else { return }
        withAnimation(reduceMotion ? nil : .snappy) { session.toggleSupersetWithNext(ei) }
        persistSupersetGroups()
        confirmSupersetSteal = nil
    }

    /// Persiste la pareja/deshecho de superserie a la RUTINA (paridad `LiveStrengthSheet.persistSupersetGroups`,
    /// r30): la sesión ya cambió `supersetGroup` en el modelo en memoria; esto lo hace sobrevivir a la
    /// próxima vez que la rutina se abra a editar. Sin rutina detrás (sesión ad-hoc), no-op.
    func persistSupersetGroups() {
        guard let rid = session.routineId else { return }
        let groups = Dictionary(uniqueKeysWithValues: session.runs.map { ($0.id, $0.supersetGroup) })
        Task {
            guard let store = await sheet.repo.storeHandle(),
                  var res = try? await store.routineExercises(routineId: rid),
                  let routine = (try? await store.routines())?.first(where: { $0.id == rid }) else { return }
            for i in res.indices where groups.keys.contains(res[i].id) {
                res[i].supersetGroup = groups[res[i].id] ?? nil
            }
            try? await store.saveRoutine(routine, exercises: res)
            for re in res { routineREs[re.id] = re }
        }
    }

    // MARK: - Formato (mismos formateadores que `LiveStrengthSheet`, sin duplicar la unidad)

    var imperial: Bool { sheet.system == .imperial }
    var weightStepKg: Double { imperial ? 5 * LiveStrengthSheet.kgPerPound : 2.5 }

    func displayWeight(_ kg: Double) -> Double { imperial ? UnitFormatter.kgToPounds(kg) : kg }
    func plateNumber(_ v: Double) -> String { StrengthDisplay.displayNumber(v, system: sheet.system) }
    func weightUnit() -> String { StrengthDisplay.weightUnit(sheet.system).lowercased() }

    /// «ANT 80 × 8 · Q2» — el playhead bajo la fila activa (R12: `lastRPE` ya viaja en el modelo).
    func antPlayhead(_ run: StrengthSessionModel.ExerciseRun) -> String? {
        guard let w = run.lastWeightKg, let r = run.lastReps else { return nil }
        let weightPart = run.type == .weightReps ? "\(plateNumber(displayWeight(w))) × " : ""
        let qPart = run.lastRPE.map { " · " + LiveStrengthSheet.qLabel(fromRPE: $0) } ?? ""
        return "ANT \(weightPart)\(r)\(qPart)"
    }

    /// «3 × 10 · 145 kg» — receta de una línea para la fila plegada (mismo orden que
    /// `RoutineSheetLogic.recetaSummary`, leyendo el plan de la SESIÓN en vez de `RoutineSet`).
    func recetaSummary(_ run: StrengthSessionModel.ExerciseRun) -> String {
        let work = run.sets.filter { $0.kind == .work }
        guard run.type == .weightReps || run.type == .bodyweight, let r = work.first?.reps else {
            return String(localized: "\(work.count) sets")
        }
        var head = "\(work.count) × \(r)"
        if run.type == .weightReps, let w = work.first?.weightKg, w > 0 {
            head += " · \(plateNumber(displayWeight(w))) \(weightUnit())"
        }
        return head
    }

    /// R11(a): abre el editor de descanso — misma hoja capa 3 (`RestEditorScreen`) que F1, para la
    /// serie que le sigue a la que acaba de cerrar (`session.runs[ei].currentSet`).
    func openRestEditor(ei: Int) {
        guard session.runs.indices.contains(ei) else { return }
        restEdit = LiveStrengthSheet.RestEdit(id: ei, setIndex: session.runs[ei].currentSet)
    }

    /// R11(b): «✎ Nota» en la tarjeta activa (adjudicado en r1) — abre la MISMA `NoteSheet` que F1.
    func openNote(ei: Int) {
        guard session.runs.indices.contains(ei) else { return }
        let run = session.runs[ei]
        let firstSet = run.sets.first
        noteTarget = LiveStrengthSheet.NoteTarget(
            id: run.id, exerciseId: run.exerciseId, exerciseName: run.name,
            setId: firstSet?.id ?? "", setNumber: 1)
        noteHistory = nil
        Task {
            guard let store = await sheet.repo.storeHandle() else { return }
            let history = (try? await store.exerciseNotes(exerciseId: run.exerciseId, excludingSession: session.id)) ?? []
            noteHistory = history
        }
    }

    /// D-r2.2 (ronda 3): abre la hoja de RPE — alcanzable desde el bucle (el viejo SÍ lo hacía,
    /// `tapEntrenarCell` case `.rpe`), no solo desde Foco. El `onPick` de la hoja (`RoutineSheetLive.swift`)
    /// llama `session.setRPE(...)` SIN condición — PISA cualquier RPE existente, a propósito: abrir
    /// la hoja a mano es una decisión explícita del usuario, distinta del auto-relleno de QUEDABAN
    /// (`rpeToWrite`, arriba) que sí protege un RPE ya puesto para no pisarlo con una inferencia.
    func openRPE(ei: Int, si: Int) {
        guard session.runs.indices.contains(ei), session.runs[ei].sets.indices.contains(si) else { return }
        let run = session.runs[ei]
        let set = run.sets[si]
        rpeTarget = LiveStrengthSheet.RPETarget(id: set.id, runId: run.id, setNumber: si + 1,
                                                weightKg: displayWeight(set.weightKg), reps: set.reps, currentRPE: set.rpe)
    }

    func usesBarbell(_ ei: Int) -> Bool {
        guard session.runs.indices.contains(ei),
              let eq = ExerciseCatalog.byID(session.runs[ei].exerciseId)?.equipment?.lowercased() else { return false }
        return eq.contains("barbell") || eq.contains("curl bar")
    }
}

/// R1: el `.task(id:)` de auto-cierre del descanso fijo, envuelto en un `ViewModifier` propio para
/// poder colgarlo de `HojaSesionViva.body` (ronda 3 · O-r2a: a nivel de la vista raíz, no de una
/// tarjeta que puede plegarse — ver `restAutoSkipModifier()` arriba) sin ensanchar su firma. No
/// `private`: `RoutineSheetLive.swift` lo monta directo.
struct RestAutoSkipModifier: ViewModifier {
    let vivo: HojaSesionViva
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content.task(id: vivo.session.restEndsAt) {
            guard vivo.session.currentRestMode == .fixed, let end = vivo.session.restEndsAt else { return }
            let delay = end.timeIntervalSinceNow
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard !Task.isCancelled, vivo.session.phase == .resting, !vivo.session.paused else { return }
            let fresco = abs(end.timeIntervalSinceNow) < 2 && scenePhase == .active
            if fresco {
                vivo.sheet.model.buzz(loops: 1)
                SessionComfort.playRestChime()
            }
            withAnimation(vivo.reduceMotion ? nil : StrandMotion.gentle) { vivo.session.skipRest() }
        }
    }
}
#endif
