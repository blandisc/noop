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

    /// D0 (FER-170 · F5) + FER-187: la ÚNICA puerta a Foco — la tocan el «⤢» de la cabecera, el
    /// «⤢» de la tarjeta activa, el tap del cromo (thumb+nombre) de la tarjeta activa, y el
    /// «Enfoque» del «···» (puertas, un solo destino, mismo gesto). Reduce Motion: sin
    /// `withAnimation` la transacción no anima — el `matchedGeometryEffect` compartido entre la
    /// tarjeta y `HojaFoco` (`focoNS`) simplemente salta al estado final, corte seco.
    func enterFoco() {
        withAnimation(reduceMotion ? nil : .snappy) { focusMode = true }
    }

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
    /// no era ya la activa) y registra con su descanso real. `bypassAbsurdGuard` (B10, FER-169): la
    /// respuesta «SÍ, N» del aviso vuelve a llamar aquí mismo para no duplicar el camino de
    /// seleccionar+registrar — pasa `true` para no volver a preguntar sobre el mismo valor.
    func confirmOrToggleSet(ei: Int, si: Int, bypassAbsurdGuard: Bool = false) {
        guard session.runs.indices.contains(ei), session.runs[ei].sets.indices.contains(si) else { return }
        let set = session.runs[ei].sets[si]
        let isCurrent = si == session.runs[ei].currentSet && !set.done
        // B10 (FER-169): antes de registrar una serie nueva, ¿el peso capturado es 8× lo que ya
        // sabemos de este ejercicio? Una hecha que se está corrigiendo (B9) no vuelve a preguntar
        // aquí — ya pasó el guard cuando se palomeó la primera vez.
        if !set.done, !bypassAbsurdGuard {
            let run = session.runs[ei]
            let reference = absurdCaptureReference(run)
            if CaptureGuard.isAbsurd(weightKg: set.weightKg, referenceKg: reference) {
                absurdCapture = AbsurdCaptureTarget(runId: run.id, setId: set.id, weightKg: set.weightKg, referenceKg: reference)
                return
            }
        }
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

    // MARK: - B10 · el guard de captura absurda (FER-169)
    //
    // El umbral vive en `StrandTraining.CaptureGuard` — UNA constante que también usa `StrengthStore`
    // al cerrar el PR y al sembrar la próxima sesión (`lastWorkSets`/`workSetHistory`), así que un
    // «SÍ» aquí no puede envenenar ninguno de los dos sin que este archivo tenga que saberlo. Sin
    // columna nueva: el `SetEntry` se guarda tal cual con «SÍ»; el propio umbral, recomputado ahí, es
    // lo que lo excluye después.

    /// La referencia contra la que se juzga «¿es absurdo?»: el PR de peso máximo cargado al abrir la
    /// sesión (R16), o — sin PR — la semilla de la fila («la última vez»/prescripción, `lastWeightKg`).
    private func absurdCaptureReference(_ run: StrengthSessionModel.ExerciseRun) -> Double {
        personalRecords[run.exerciseId]?[.maxWeight]?.valueKg ?? run.lastWeightKg ?? 0
    }

    /// Resuelve la fila (`ei`/`si`) VIGENTE de un `AbsurdCaptureTarget` por identidad — nunca el
    /// índice que tenía cuando se armó el aviso, que B8 (saltar-al-final, mover) puede haber corrido
    /// mientras el aviso seguía en pantalla. `nil` si la fila ya no existe (ejercicio quitado de la
    /// sesión mientras tanto).
    private func resolveAbsurdCapture(_ target: AbsurdCaptureTarget) -> (ei: Int, si: Int)? {
        guard let ei = session.runs.firstIndex(where: { $0.id == target.runId }),
              let si = session.runs[ei].sets.firstIndex(where: { $0.id == target.setId }) else { return nil }
        return (ei, si)
    }

    /// «SÍ, 825»: el acta no miente — registra tal cual, con el guard destapado para esta fila. El
    /// PR y la siembra siguiente lo excluyen solos (mismo umbral, recalculado en `StrengthStore`).
    func confirmAbsurdCaptureAsIs() {
        guard let target = absurdCapture else { return }
        absurdCapture = nil
        guard let (ei, si) = resolveAbsurdCapture(target) else { return }
        confirmOrToggleSet(ei: ei, si: si, bypassAbsurdGuard: true)
    }

    /// «ERA 82.5»: el típo más común (el punto perdido, ×10) — corrige dividiendo entre 10 y vuelve a
    /// pasar por el guard (`confirmOrToggleSet` sin bypass): si el valor corregido TODAVÍA se ve
    /// absurdo, pregunta de nuevo en vez de registrar algo que sigue sin cuadrar.
    func correctAbsurdCapture() {
        guard let target = absurdCapture else { return }
        absurdCapture = nil
        guard let (ei, si) = resolveAbsurdCapture(target) else { return }
        session.setWeight(exercise: ei, set: si, kg: target.weightKg / 10)
        confirmOrToggleSet(ei: ei, si: si)
    }

    /// Descarta el aviso sin registrar nada — la fila queda pendiente, tal como estaba antes del tap.
    func dismissAbsurdCapture() { absurdCapture = nil }

    // MARK: - B16b · «¿La rutina se queda así?» (FER-169)

    /// Compara la marcha contra la rutina base (`routineREs`, cargada al abrir) — solo dos cosas
    /// cuentan como «cambio estructural» (mapa): series distintas a lo prescrito, y sustituciones
    /// (`run.exerciseId` ya no es el de la rutina). Agregar un ejercicio NO entra aquí: ese verbo
    /// (B8) ya persiste de inmediato, como hacía antes de F4 — nada que preguntar dos veces. Sin
    /// rutina detrás (sesión ad-hoc), nunca hay nada que preguntar.
    func detectRoutineChanges() -> RoutineChangesSummary? {
        guard session.routineId != nil else { return nil }
        var parts: [String] = []
        for run in session.runs {
            guard let re = routineREs[run.id] else { continue }
            if run.exerciseId != re.exerciseId {
                let oldName = ExerciseCatalog.byID(re.exerciseId).map(StrengthDisplay.name) ?? re.exerciseId
                parts.append(String(localized: "\(oldName) for \(run.name)"))
            } else if re.targetSets > 0 {
                let currentWork = run.sets.filter { $0.kind == .work }.count
                if currentWork > 0, currentWork != re.targetSets {
                    parts.append(String(localized: "\(run.name) \(re.targetSets) → \(currentWork) sets"))
                }
            }
        }
        guard !parts.isEmpty else { return nil }
        return RoutineChangesSummary(phrase: parts.joined(separator: " · "))
    }

    /// El CTA «Terminar y guardar» (B16) pasa por aquí: si la marcha cambió la estructura, pregunta
    /// UNA vez (B16b) antes de cerrar; si no, termina directo — el camino de siempre, intacto.
    func requestFinish() {
        if let summary = detectRoutineChanges() {
            routineChangesToConfirm = summary
        } else {
            sheet.model.endStrengthSession(save: true)
        }
    }

    /// «GUARDAR EN LA RUTINA»: escribe los cambios detectados a `RoutineExercise` (series, ejercicio)
    /// y DESPUÉS termina — la próxima vez que se abra esta rutina, sale así. El acta de HOY no
    /// depende de esto: refleja lo que de verdad se hizo sea cual sea la respuesta.
    func finishAndSaveRoutineChanges() {
        routineChangesToConfirm = nil
        Task { await persistRoutineChanges() }
        sheet.model.endStrengthSession(save: true)
    }

    /// «SOLO POR HOY»: termina sin tocar la rutina — la próxima sesión vuelve a sembrar desde lo de
    /// siempre.
    func finishWithoutSavingRoutineChanges() {
        routineChangesToConfirm = nil
        sheet.model.endStrengthSession(save: true)
    }

    private func persistRoutineChanges() async {
        guard let rid = session.routineId, let store = await sheet.repo.storeHandle(),
              var res = try? await store.routineExercises(routineId: rid),
              let routine = (try? await store.routines())?.first(where: { $0.id == rid }) else { return }
        for run in session.runs {
            guard let idx = res.firstIndex(where: { $0.id == run.id }) else { continue }
            let currentWork = run.sets.filter { $0.kind == .work }.count
            if currentWork > 0 { res[idx].targetSets = currentWork }
            if run.exerciseId != res[idx].exerciseId { res[idx].exerciseId = run.exerciseId }
        }
        try? await store.saveRoutine(routine, exercises: res)
    }

    // MARK: - B8 · «＋ Agregar ejercicio» (FER-169, porteado de `LiveStrengthSheet.addExercises`/
    // `persistInsertedExercises`)

    /// Inserta `picks` en la sesión justo tras el ejercicio `afterRunId` (o al final si es `nil` — la
    /// Rápida vacía, B13, agrega sin «después» que valga) y, con rutina detrás, los persiste ahí
    /// mismo — mismo trato PERMANENTE que ya usaba el «＋» de la Hoja fría. Por identidad (regla
    /// dura), no por índice: el picker es un `.sheet` async y B8 puede reordenar (saltar-al-final,
    /// mover) mientras está abierto, así que el índice se resuelve AQUÍ, tras el `await`, nunca antes.
    /// B16b decide, al terminar, si alguna OTRA marcha (series/sustituciones) también se guarda o se
    /// queda solo por hoy; agregar un ejercicio siempre fue permanente incluso antes de F4, así que
    /// no espera a esa pregunta.
    func addExercisesFromLibrary(_ picks: [Exercise], afterRunId: String?) async {
        guard !picks.isEmpty else { return }
        let lasts = await withTaskGroup(of: (String, Double?, Int?).self) { group in
            for ex in picks {
                group.addTask {
                    let last = await self.sheet.repo.exerciseHistory(exerciseId: ex.id).last
                    return (ex.id, last?.weightKg, last?.reps)
                }
            }
            var results: [String: (Double?, Int?)] = [:]
            for await (id, weight, reps) in group { results[id] = (weight, reps) }
            return results
        }
        await MainActor.run {
            if session.runs.isEmpty {
                for ex in picks {
                    let last = lasts[ex.id]
                    session.addExercise(ex, lastWeightKg: last?.0, lastReps: last?.1)
                }
            } else if let afterRunId, let after = session.runs.firstIndex(where: { $0.id == afterRunId }) {
                session.currentIndex = after   // `insertExerciseAfterCurrent` inserta a `currentIndex + 1`
                for ex in picks.reversed() {
                    let last = lasts[ex.id]
                    session.insertExerciseAfterCurrent(ex, lastWeightKg: last?.0, lastReps: last?.1)
                }
                if session.routineId != nil { persistInsertedExercises(picks, afterRunId: afterRunId) }
            } else {
                for ex in picks {
                    let last = lasts[ex.id]
                    session.addExercise(ex, lastWeightKg: last?.0, lastReps: last?.1)
                }
            }
        }
    }

    private func persistInsertedExercises(_ picks: [Exercise], afterRunId: String) {
        guard let rid = session.routineId else { return }
        Task {
            guard let store = await sheet.repo.storeHandle(),
                  var res = try? await store.routineExercises(routineId: rid),
                  let routine = (try? await store.routines())?.first(where: { $0.id == rid }) else { return }
            var insertAt = res.firstIndex(where: { $0.id == afterRunId }).map { $0 + 1 } ?? res.count
            for ex in picks {
                let re = RoutineExercise(routineId: rid, exerciseId: ex.id, position: insertAt,
                                         targetSets: 1, targetReps: 8,
                                         restMode: .fixed, restSeconds: StrengthSessionModel.adHocRestSeconds)
                res.insert(re, at: min(insertAt, res.count))
                insertAt += 1
            }
            for i in res.indices { res[i].position = i }
            do {
                try await store.saveRoutine(routine, exercises: res)
                await loadRoutineREs()
            } catch {
                await MainActor.run { routineWriteError = true }
            }
        }
    }

    // MARK: - B7 · la bajada propuesta (FER-169)

    /// «BAJAR A {toKg}»: mueve las celdas SIN palomear a la carga sugerida (mismo patrón que
    /// `takeHeldRaise` — solo lo pendiente, lo ya hecho conserva lo real) y apaga la píldora. Sin
    /// bandera nueva: la próxima clasificación (`ProgressionMath.classify`) lee esta sesión como
    /// entrenada a `toKg`, así que el estancamiento se rompe solo, sin nada que persistir aquí.
    func applyDeload(ei: Int, toKg: Double) {
        guard session.runs.indices.contains(ei) else { return }
        withAnimation(reduceMotion ? nil : .snappy) {
            for si in session.runs[ei].sets.indices where !session.runs[ei].sets[si].done {
                session.runs[ei].sets[si].weightKg = toKg
            }
            session.runs[ei].deloadState = nil
        }
    }

    /// «SEGUIR EN {fromKg}»: descarta la propuesta SOLO por esta sesión — no persiste un opt-out (sin
    /// columna nueva); si el estancamiento sigue, la próxima sesión vuelve a proponerlo.
    func dismissDeload(ei: Int) {
        guard session.runs.indices.contains(ei) else { return }
        withAnimation(reduceMotion ? nil : .snappy) { session.runs[ei].deloadState = nil }
    }

    // MARK: - B6b · «Volver a X» (FER-169, porteado 1:1 de `LiveStrengthSheet.revertRaise`)

    /// El per-session opt-out de una subida YA APLICADA: las celdas SIN palomear vuelven al peso
    /// viejo; las hechas conservan lo que de verdad se levantó. La sesión queda marcada opted-out
    /// (FER-835) — ni acierto ni fallo, la subida se vuelve a proponer la próxima vez.
    func revertRaise(ei: Int) {
        guard session.runs.indices.contains(ei), let raise = session.runs[ei].proposedRaise else { return }
        withAnimation(reduceMotion ? nil : .snappy) {
            for si in session.runs[ei].sets.indices where !session.runs[ei].sets[si].done {
                session.runs[ei].sets[si].weightKg = raise.fromKg
            }
            session.runs[ei].proposedRaise = nil
            session.runs[ei].raiseOptedOut = true
            raiseRevertOpenRunId = nil
        }
    }

    /// Todo «✓» de la Hoja viva pasa por aquí: registra (con el QUEDABAN elegido si aplica), limpia
    /// el RIR de la celda, revisa PR (R16) y da la háptica. `ei`/`si` son la celda que se ESTABA
    /// mirando ANTES de registrar (para el RIR/PR de ESA serie) — el modelo puede haber avanzado el
    /// foco a otra ya para cuando este método termina.
    ///
    /// FER-223 (corrección post-QA): este es el ÚNICO funnel de «serie registrada» — lo llaman tanto
    /// el «✓ Serie» del keypad como el «Set done» del Foco (`registerFromFoco`). Antes cada uno de
    /// esos dos call sites ADEMÁS disparaba su propio háptico, así que una serie palomeada sonaba dos
    /// veces; el evento vive solo aquí ahora. `sheet.model.buzz(loops: 1)` (AppModel.buzz, el cuarto
    /// sistema háptico del repo) queda reemplazado por el catálogo de Entrenar.
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
        EntrenarHaptic.serieCompletada.play()
    }

    // MARK: - D3 · HECHO (FER-170 · F5)

    /// El «✓ Serie hecha» de Foco pasa por AQUÍ — registra con `registerActiveSet` (RIR/RPE/PR/
    /// háptica, sin duplicar nada de eso) y decide si HECHO aparece YA o espera al descanso real que
    /// acaba de arrancar (paridad `LiveStrengthSheet.focusDoneTiming`, reusada tal cual — pura,
    /// tested en `LiveStrengthSheetRIRTests`). El «cierre» que dispara HECHO es distinto según el
    /// contexto: para un ejercicio suelto, que sus series de trabajo queden todas hechas; para un
    /// miembro de superserie, que la RONDA que esta serie completaba cierre (mapa D3: «en superserie
    /// solo al cerrar ronda») — un salto de round-robin a un compañero DENTRO de la misma ronda
    /// (`registerCurrentSet`, sin descanso) no cuenta como cierre; se detecta comparando cuántas
    /// rondas están cerradas antes/después de registrar (`StrengthSessionModel.closedSupersetRounds`).
    func registerFromFoco() {
        let ei = session.currentIndex
        guard session.runs.indices.contains(ei) else { return }
        let si = session.runs[ei].currentSet
        let inSuperset = session.isInSuperset(ei)
        let members = inSuperset ? session.supersetMembers(at: ei) : []
        let roundsClosedBefore = inSuperset ? session.closedSupersetRounds(members: members) : 0
        let runId = session.runs[ei].id

        registerActiveSet(ei: ei, si: si)

        let closedNow: Bool
        if inSuperset {
            closedNow = session.closedSupersetRounds(members: members) > roundsClosedBefore
        } else {
            closedNow = session.runs.indices.contains(ei)
                && !session.runs[ei].sets.contains(where: { $0.kind == .work && !$0.done })
        }
        guard closedNow else { return }
        switch LiveStrengthSheet.focusDoneTiming(exerciseFullyDone: true, restStarting: session.phase == .resting) {
        case .none: break
        case .pending: pendingFocusDoneRunId = runId
        case .immediate: focusDoneRunId = runId
        }
    }

    // MARK: - B9 · corregir una hecha (FER-169)

    /// Tap en el peso de una fila HECHA: la reabre (desmarca, sin cerrar ningún descanso en curso —
    /// `toggleDone` al DESmarcar es un no-op sobre el descanso) y el valor vuelve a la consola
    /// (`beginEditing`, la MISMA celda que edita cualquier fila activa). Nada queda inmutable hasta
    /// Terminar: re-✓ la vuelve a cerrar por el `confirmOrToggleSet` de siempre.
    func reopenDoneSetForCorrection(ei: Int, si: Int) {
        guard session.runs.indices.contains(ei), session.runs[ei].sets.indices.contains(si),
              session.runs[ei].sets[si].done else { return }
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) {
            session.toggleDone(exercise: ei, set: si)
        }
        beginEditing(.weight(ei, si))
    }

    /// SALTAR (B2/B3 consola, mock P4): el mismo `skipRest()` que el botón «SALTAR ›» de la banda.
    ///
    /// FER-223 (corrección post-QA): este mismo `skipRest()` lo llama TAMBIÉN `RestAutoSkipModifier`
    /// cuando el descanso se acaba SOLO — así que un háptico puesto aquí sonaría dos veces en ese
    /// camino (el automático + este). El golpe pesado de `descansoTerminado` vive únicamente en
    /// `RestAutoSkipModifier` (el sitio donde de verdad hace falta llamar la atención de alguien que
    /// no está mirando el teléfono). Aquí, en el toque MANUAL, decidí no poner ningún háptico: quien
    /// presiona «Saltar ›»/«Continuar ›» ya sabe lo que acaba de hacer — la confirmación visual de la
    /// banda es suficiente, y un golpe adicional al tacto que originó la acción es redundante, no
    /// informativo (mismo principio de `SetTable`: el check ya tiene su propio feedback al tocarlo).
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

    /// B11 (FER-169): si la serie recién registrada bate cualquiera de los 3 `PRMetric` (peso máximo,
    /// reps máximas, volumen máximo — SIN 1RM, eso sigue sin existir aquí) contra los PR cargados al
    /// abrir, arma el destello CON el copy del mapa («RÉCORD peso máx · antes 100.0»,
    /// `HojaFilaSerie`'s caller apaga solo tras un rato). Estricto: solo `.work` (sin calentamiento) y
    /// NUNCA lo que el guard de B10 acaba de rechazar — un 825 que «SÍ» guardó no puede además
    /// destellar como récord numérico, sería la misma mentira por otra puerta.
    private func checkForPR(ei: Int, set: StrengthSessionModel.WorkingSet) {
        guard set.kind == .work, session.runs.indices.contains(ei) else { return }
        let run = session.runs[ei]
        guard !CaptureGuard.isAbsurd(weightKg: set.weightKg, referenceKg: absurdCaptureReference(run)) else { return }
        let exId = run.exerciseId
        let prs = personalRecords[exId] ?? [:]
        let volume = set.weightKg * Double(set.reps)
        let priorWeight = prs[.maxWeight]?.valueKg
        let priorReps = prs[.maxReps]?.reps
        // El PR de volumen guarda el peso × reps de LA SERIE que lo puso, no el volumen ya multiplicado
        // (`PersonalRecord.valueKg`/`reps`, StrandTraining) — el volumen previo se recompone aquí, no
        // se compara peso contra volumen por descuido.
        let priorVolume = prs[.maxVolume].map { ($0.valueKg ?? 0) * Double($0.reps ?? 0) }
        let beatsWeight = priorWeight.map { set.weightKg > $0 } ?? (set.weightKg > 0)
        let beatsReps = priorReps.map { set.reps > $0 } ?? (set.reps > 0)
        let beatsVolume = priorVolume.map { volume > $0 } ?? (volume > 0)
        // Prioridad de copy cuando bate más de un tipo a la vez (mapa B11 muestra una sola línea):
        // peso máx primero (el más legible), luego volumen, luego reps.
        let flash: PRFlash?
        if beatsWeight {
            flash = PRFlash(setId: set.id, metric: .maxWeight,
                            priorText: priorWeight.map { "\(plateNumber(displayWeight($0))) \(weightUnit())" })
        } else if beatsVolume {
            flash = PRFlash(setId: set.id, metric: .maxVolume,
                            priorText: prs[.maxVolume].map { pr in
                                "\(plateNumber(displayWeight(pr.valueKg ?? 0))) × \(pr.reps ?? 0)"
                            })
        } else if beatsReps {
            flash = PRFlash(setId: set.id, metric: .maxReps, priorText: priorReps.map { "\($0)" })
        } else {
            flash = nil
        }
        guard let flash else { return }
        prFlash = flash
        Task {
            try? await Task.sleep(for: .seconds(1.1))
            if prFlash?.setId == set.id { prFlash = nil }
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

    /// R6 (ronda 2 del gate FER-168): la superserie descansa por RONDA, no por «SET N → M» — ese
    /// conteo (posición dentro de las series de un solo ejercicio) no significa nada cuando la
    /// banda cierra una ronda con varios miembros. `esRonda` cambia SOLO este rótulo; el headline
    /// de meta («down to N») que ya vive en `RestBand` no se toca — mismo contenido, misma meta.
    private func restBandKicker(esRonda: Bool) -> LocalizedStringKey {
        if esRonda { return "REST · ROUND" }
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

    /// R2 (ronda 2 del gate, bloqueante — criterio explícito del mapa D2: «toggle TIEMPO/FC»): D2 de
    /// Foco puede ofrecer los DOS combustibles al usuario, no solo el que el motor eligió — pero solo
    /// cuando el motor de verdad resolvió un objetivo de FC honesto (`currentRestMode == .heartRate`,
    /// `computeRestTarget`). Sin él, no hay «vista FC» que enseñar sin inventar un objetivo — el
    /// toggle simplemente no aparece (mismo principio «sin inventar» de toda la app).
    var puedeElegirCombustibleDescanso: Bool { session.currentRestMode == .heartRate }

    /// La banda de descanso ANCLADA (mock P4): dos combustibles — FC dice la meta («baja a N»,
    /// `RestBand` ya lo pinta desde FER-167), reloj fijo cuando no hay Watch. R13: con razón
    /// `.ceiling` y el pulso TODAVÍA arriba de la meta, la banda no dice «Listo» — dice el tope
    /// honesto y ofrece SEGUIR. R4: la misma función alcanza también a la superserie (Tarjeta.swift
    /// la monta igual). `esRonda` (R6, ronda 2 del gate FER-168): SOLO cambia el rótulo del kicker
    /// («REST · ROUND» en vez de «SET N → M») — el headline de meta es idéntico en los dos casos.
    /// `large` (FER-170 · F5): la variante GRANDE/centrada que pide D2 de Foco — «reusa el RestBand de
    /// F2», misma lógica de descanso, solo la piel cambia (paridad `RestBand.large`, ya construido en
    /// F2 para el modo foco vigente que este archivo retira). `forzarTiempo` (ronda 2 del gate FER-170,
    /// R2): el toggle TIEMPO/FC de D2 — `true` fuerza la vista de RELOJ aunque el motor haya resuelto
    /// FC (`puedeElegirCombustibleDescanso`); SIN caso nuevo en `RestBand` (F2, sin tocar su API
    /// pública) — el «reloj de respaldo» que YA existe para el caso sin señal (`restBandTimeBody`,
    /// alimentado por `session.restEndsAt`, que el motor fija SIEMPRE, en las dos rutas) es la MISMA
    /// vista que esta rama pide, solo que elegida a propósito en vez de por falta de señal.
    @ViewBuilder func restBand(esRonda: Bool = false, large: Bool = false, forzarTiempo: Bool = false) -> some View {
        VStack(alignment: large ? .center : .leading, spacing: CenitMetrics.space2) {
            if session.paused {
                // B5 (FER-169): «pausada» congela el descanso — la banda no sigue diciendo REST/tu
                // pulso bajando (ninguno de los dos avanza mientras `paused`); una línea honesta en
                // vez, con el mismo tiempo restante que ya estaba (`restBandCore` congela el número —
                // aquí solo se apaga el color/kicker para que no MIENTA que sigue corriendo).
                HStack(spacing: 8) {
                    Text("REST · PAUSED").instrumentoOverline().foregroundStyle(sheet.theme.inkTertiary)
                    Spacer(minLength: 6)
                    Text("waits with you").font(StrandFont.caption).foregroundStyle(sheet.theme.inkTertiary)
                }
                restBandCore(esRonda: esRonda, large: large, forzarTiempo: forzarTiempo)
                    .opacity(0.45)   // token-exempt: atenuación transitoria B5 «congelado», sin token de opacidad propio todavía (mismo patrón que el destello R16)
                    .allowsHitTesting(false)
            } else {
                restBandCore(esRonda: esRonda, large: large, forzarTiempo: forzarTiempo)
            }
            // R11(a): «Cambiar descanso» — el editor de umbral (capacidad intacta), paridad
            // `LiveStrengthSheet.restEditorPill`. `RestBand` no trae este control; se queda como
            // pastilla propia bajo la banda.
            if let ei = restOwnerExerciseIndex, !session.paused {
                Button { openRestEditor(ei: ei) } label: {
                    Label("Change rest", systemImage: "pencil").font(StrandFont.caption).foregroundStyle(sheet.theme.ink)
                        .padding(.horizontal, 13).padding(.vertical, 6)
                        .overlay(Capsule().strokeBorder(sheet.theme.hairlineStrong, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder private func restBandCore(esRonda: Bool, large: Bool, forzarTiempo: Bool = false) -> some View {
        let hrMode = session.currentRestMode == .heartRate && !forzarTiempo
        Group {
            if hrMode, let started = session.restStartedAt {
                TimelineView(.periodic(from: started, by: 1)) { ctx in
                    let tick = session.paused ? (session.pausedAt ?? ctx.date) : ctx.date
                    let elapsed = max(0, Int(tick.timeIntervalSince(started)))
                    let v = RestReadinessRule.evaluate(
                        currentHR: sheet.model.watchBpm, worn: sheet.model.watchBpm != nil, restingHR: restingBaseline,
                        elapsedS: elapsed, targetHR: session.currentRestTarget)
                    if v.state == .noSignal {
                        restBandTimeBody(end: session.restEndsAt, now: tick, noStrapFallback: true, esRonda: esRonda, large: large)
                    } else {
                        let ceiling = v.reason == .ceiling && (v.bpmToReady ?? 0) > 0
                        RestBand(kicker: restBandKicker(esRonda: esRonda),
                                 mode: .heartRate(remainingBpm: v.bpmToReady, targetBpm: v.targetReadyHR ?? 0,
                                                  currentBpm: sheet.model.watchBpm),
                                 trailing: SessionClock.format(elapsed),
                                 note: "at 5 bpm I say «almost» · at 3:00 I let you go even if it hasn't dropped",
                                 isAlmost: v.state == .almostReady, isReady: v.ready, isCeilingRelease: ceiling,
                                 startBpm: restStartBpm, large: large,
                                 onSkip: { skipRest() })
                            .accessibilityAddTraits(.updatesFrequently)
                    }
                }
            } else if let end = session.restEndsAt, let started = session.restStartedAt {
                TimelineView(.periodic(from: started, by: 1)) { ctx in
                    restBandTimeBody(end: end, now: session.paused ? (session.pausedAt ?? ctx.date) : ctx.date,
                                     noStrapFallback: false, esRonda: esRonda, large: large)
                }
            }
        }
    }

    private func restBandTimeBody(end: Date?, now: Date, noStrapFallback: Bool, esRonda: Bool, large: Bool) -> some View {
        let started = session.restStartedAt ?? now
        let cappedEnd = noStrapFallback ? min(end ?? now, started.addingTimeInterval(300)) : end
        let totalS = cappedEnd.map { max(0, Int($0.timeIntervalSince(started))) } ?? 0
        let elapsed = max(0, min(totalS, Int(now.timeIntervalSince(started))))
        return RestBand(kicker: restBandKicker(esRonda: esRonda),
                         mode: .clock(elapsed: SessionClock.format(elapsed), target: SessionClock.format(totalS)),
                         trailing: sheet.model.watchBpm == nil ? String(localized: "no watch on your wrist") : SessionClock.format(elapsed),
                         note: noStrapFallback ? "resting by clock: connect your Apple Watch for rest by heart rate" : nil,
                         large: large,
                         onSkip: { skipRest() })
            .accessibilityAddTraits(.updatesFrequently)
    }

    // MARK: - «···» del ejercicio (R8, porteado completo de `LiveStrengthSheet.exerciseMenuItems`)

    /// `incluirEstructura` (R1, ronda 2 del gate FER-168): `false` cuando este menú se monta como
    /// SUBMENÚ de un miembro dentro de la tarjeta de superserie viva (`HojaTarjetaSuperserieSesion`)
    /// — ahí «Move up/down» fragmentaría el bloque (swap ciego de un solo índice, sin conciencia de
    /// grupo) y «Superset with next/Undo» duplicaría/contradiría el «Undo superset» de BLOQUE que
    /// esa tarjeta ya ofrece arriba (`breakSupersetBlock`). Foco tampoco es por-miembro: abre sobre
    /// el foco REAL del motor (`focusMode`, sin `ei`), así que vive en el nivel de bloque, no aquí.
    /// `true` (default) preserva el menú de siempre para la tarjeta de un ejercicio suelto.
    func exerciseMenuItems(ei: Int, run: StrengthSessionModel.ExerciseRun, incluirEstructura: Bool = true) -> [PaperMenuItem] {
        var rows: [PaperMenuItem] = []
        if incluirEstructura {
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
            // B8 (FER-169) «el plan cede»: saltar ESTE ejercicio al final del plan, activo todavía —
            // distinto de «Remove from session» (destructivo) y de `skipExercise` (lo excluye del todo).
            if session.runs.count > 1 {
                rows.append(.init(String(localized: "Skip exercise · goes to the end"), systemImage: "arrow.turn.down.right") {
                    withAnimation(reduceMotion ? nil : .snappy) { session.sendExerciseToEnd(ei) }
                })
            }
        }
        rows.append(.init(String(localized: "Progression"), subtitle: progressionSubtitle(run),
                          systemImage: "chart.line.uptrend.xyaxis") {
            progressionEdit = LiveStrengthSheet.ProgressionEditTarget(id: ei)
        })
        // B8: «Sustituir» — el mismo «Change exercise» de siempre (`ChangeExerciseSheet` ya arma la
        // shortlist «misma zona primero»), solo con el nombre del mapa.
        rows.append(.init(String(localized: "Substitute · same muscle first"), systemImage: "arrow.triangle.2.circlepath") {
            changeExercise = LiveStrengthSheet.ChangeTarget(ei: ei, run: run)
        })
        // B8: «＋ Agregar ejercicio» — inserta justo después de ESTE, sin salir de la sesión.
        rows.append(.init(String(localized: "Add exercise"), systemImage: "plus") {
            addExerciseAfterRunId = run.id
        })
        if incluirEstructura, puedeEnfocar {
            rows.append(.init(String(localized: "Focus"), systemImage: "arrow.up.left.and.arrow.down.right") {
                enterFoco()
            })
        }
        if session.runs.count > 1 {
            rows.append(.init(String(localized: "Remove from session"), systemImage: "trash", isDestructive: true) {
                withAnimation(reduceMotion ? nil : .snappy) { session.removeExercise(at: ei) }
                EntrenarHaptic.borrado.play()   // FER-223: borrar no tenía háptico propio.
            })
        }
        return rows
    }

    /// R1 (ronda 2 del gate FER-168, bloqueante): deshace la superserie COMPLETA desde la tarjeta
    /// viva. A diferencia de `toggleSupersetWithNext` (solo desempareja DOS vecinos — con 3+
    /// miembros dejaba 2 sueltos + 1 «huérfano» con un `supersetGroup` viejo todavía puesto, QA
    /// D1/D2/D3), esto limpia `supersetGroup` en TODOS los miembros del bloque de una sola vez, sin
    /// importar cuántos sean. Persiste a la rutina igual que el toggle de a pares.
    func breakSupersetBlock(members: [Int]) {
        withAnimation(reduceMotion ? nil : .snappy) {
            for ei in members where session.runs.indices.contains(ei) {
                session.runs[ei].supersetGroup = nil
            }
        }
        persistSupersetGroups()
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
    /// FER-170 (F5): paridad `LiveStrengthSheet.distanceStepM` — el paso de Foco para ejercicios de
    /// distancia, portado tal cual (0.1 km métrico, 0.1 mi imperial).
    var distanceStepM: Double { imperial ? LiveStrengthSheet.metersPerMile * 0.1 : 100 }

    func displayWeight(_ kg: Double) -> Double { imperial ? UnitFormatter.kgToPounds(kg) : kg }
    func plateNumber(_ v: Double) -> String { StrengthDisplay.displayNumber(v, system: sheet.system) }
    func weightUnit() -> String { StrengthDisplay.weightUnit(sheet.system).lowercased() }
    /// FER-170 (F5): paridad `LiveStrengthSheet.distanceNumber` — metros guardados → la unidad del
    /// usuario (km/mi), dos decimales.
    func distanceNumber(_ meters: Double) -> String {
        let v = imperial ? meters / LiveStrengthSheet.metersPerMile : meters / 1000
        return String(format: "%.2f", v)
    }

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
///
/// FER-223: este es el sitio LEGÍTIMO del golpe pesado — el descanso se acabó SOLO, sin que nadie lo
/// tocara, así que hace falta llamar la atención de alguien que probablemente no está mirando el
/// teléfono (antes esto delegaba al Watch por completo; en el iPhone no sonaba nada). Reemplaza el
/// `vivo.sheet.model.buzz(loops: 1)` genérico (`AppModel.buzz`, el cuarto sistema háptico del repo)
/// por `EntrenarHaptic.descansoTerminado`, el evento correcto del catálogo de Entrenar.
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
                EntrenarHaptic.descansoTerminado.play()
                SessionComfort.playRestChime()
            }
            withAnimation(vivo.reduceMotion ? nil : StrandMotion.gentle) { vivo.session.skipRest() }
        }
    }
}
#endif
