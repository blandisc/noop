#if os(iOS)
import SwiftUI
import StrandDesign
import StrandTraining
import StrandAnalytics

// MARK: - HojaSesionViva — el motor del bucle B1-B4 (FER-167 · F2)
//
// Toda mutación reusa la API vigente de `StrengthSessionModel` (NO se reescribe: v40 ya trae la
// captura del descanso real) — este archivo solo decide QUÉ llamar y CUÁNDO, igual que
// `LiveStrengthSheet.registerActiveSet`/`confirmOrToggleSet`, de donde está portado 1:1 (el modelo
// es el mismo, así que el contrato es idéntico; lo único que cambia es la piel que lo dispara).

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
        withAnimation(.snappy) {
            if set.done {
                session.toggleDone(exercise: ei, set: si)
            } else {
                activeCell = nil
                if !isCurrent { session.select(exerciseIndex: ei, setIndex: si) }
                registerActiveSet()
            }
        }
    }

    /// Todo «✓» de la Hoja viva pasa por aquí: ancla el ejercicio dueño del descanso ANTES de que el
    /// modelo avance, registra (con el QUEDABAN elegido si aplica) y limpia el RIR de la celda.
    func registerActiveSet() {
        restAnchorEi = session.currentIndex
        let ei = session.currentIndex
        let si = session.runs.indices.contains(ei) ? session.runs[ei].currentSet : -1
        session.registerCurrentSet(restingHR: restingBaseline, maxHR: profileMaxHR)
        let rirForThisSet = LiveStrengthSheet.rirScoped(
            selectedRIR: selectedRIR, selectedRIRTarget: selectedRIRTarget,
            registering: LiveStrengthSheet.RIRTarget(ei: ei, si: si))
        if session.runs.indices.contains(ei), session.runs[ei].sets.indices.contains(si),
           let rpe = LiveStrengthSheet.rpeToWrite(selectedRIR: rirForThisSet, existingRPE: session.runs[ei].sets[si].rpe) {
            session.setRPE(exercise: session.runs[ei].id, set: session.runs[ei].sets[si].id, rpe: rpe)
        }
        selectedRIR = nil
        selectedRIRTarget = nil
        sheet.model.buzz(loops: 1)   // háptica al palomear (contrato F1/F2: hápticas en palomear/fin de descanso/arranque)
    }

    /// SALTAR (B2/B3 consola, mock P4): el mismo `skipRest()` que el botón «SALTAR ›» de la banda.
    func skipRest() {
        withAnimation(StrandMotion.gentle) { session.skipRest() }
    }

    // MARK: - Descanso: dónde ancla la banda + qué combustible dibuja (porteado de `restBandHRBody`/`restBandTimeBody`)

    var accordionIndex: Int {
        (session.phase == .resting ? restAnchorEi : nil) ?? session.currentIndex
    }

    /// El índice donde la banda debe insertarse: justo tras la última fila hecha de ESE ejercicio —
    /// `nil` cuando el ejercicio ya no tiene fila pendiente que anclar (la tarjeta la muestra en su pie).
    func restSlotIndex(ei: Int) -> Int? {
        guard session.phase == .resting, ei == accordionIndex, session.summary == nil,
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

    /// La banda de descanso ANCLADA (mock P4): dos combustibles — FC dice la meta («baja a N»,
    /// `RestBand` ya lo pinta desde FER-167), reloj fijo cuando no hay Watch. Misma regla de
    /// honestidad que `LiveStrengthSheet`: sin señal, cae al reloj (tope 5 min) en vez de inventar.
    @ViewBuilder func restBand() -> some View {
        let hrMode = session.currentRestMode == .heartRate
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
                    RestBand(kicker: restBandKicker,
                             mode: .heartRate(remainingBpm: v.bpmToReady, targetBpm: v.targetReadyHR ?? 0,
                                              currentBpm: sheet.model.watchBpm),
                             trailing: SessionClock.format(elapsed),
                             note: "at 5 bpm I say «almost» · at 3:00 I let you go even if it hasn't dropped",
                             isAlmost: v.state == .almostReady, isReady: v.ready, startBpm: restStartBpm,
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

    // MARK: - «···» del ejercicio (porteado de `LiveStrengthSheet.exerciseMenuItems` — mismas puertas)

    func exerciseMenuItems(ei: Int, run: StrengthSessionModel.ExerciseRun) -> [PaperMenuItem] {
        var rows: [PaperMenuItem] = []
        if ei > 0 {
            rows.append(.init(String(localized: "Move up"), systemImage: "arrow.up") {
                withAnimation(.snappy) { session.moveExerciseEarlier(ei) }
            })
        }
        rows.append(.init(String(localized: "Progression"), systemImage: "chart.line.uptrend.xyaxis") {
            progressionEdit = LiveStrengthSheet.ProgressionEditTarget(id: ei)
        })
        rows.append(.init(String(localized: "Change exercise"), systemImage: "arrow.triangle.2.circlepath") {
            changeExercise = LiveStrengthSheet.ChangeTarget(ei: ei, run: run)
        })
        if session.runs.count > 1 {
            rows.append(.init(String(localized: "Remove from session"), systemImage: "trash", isDestructive: true) {
                withAnimation(.snappy) { session.removeExercise(at: ei) }
            })
        }
        return rows
    }

    // MARK: - Formato (mismos formateadores que `LiveStrengthSheet`, sin duplicar la unidad)

    var imperial: Bool { sheet.system == .imperial }
    var weightStepKg: Double { imperial ? 5 * LiveStrengthSheet.kgPerPound : 2.5 }

    func displayWeight(_ kg: Double) -> Double { imperial ? UnitFormatter.kgToPounds(kg) : kg }
    func plateNumber(_ v: Double) -> String { StrengthDisplay.displayNumber(v, system: sheet.system) }
    func weightUnit() -> String { StrengthDisplay.weightUnit(sheet.system).lowercased() }

    /// «80 × 8» — el playhead ANT bajo la fila activa. Sin Q: `ExerciseRun` solo guarda
    /// `lastWeightKg`/`lastReps` de la sesión anterior, no su RPE (GAP declarado en el reporte —
    /// añadir `lastRPE` es un cambio de `StrengthSessionModel`, fuera de alcance de F2).
    func antPlayhead(_ run: StrengthSessionModel.ExerciseRun) -> String? {
        guard let w = run.lastWeightKg, let r = run.lastReps else { return nil }
        let weightPart = run.type == .weightReps ? "\(plateNumber(displayWeight(w))) × " : ""
        return "ANT \(weightPart)\(r)"
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

    func usesBarbell(_ ei: Int) -> Bool {
        guard session.runs.indices.contains(ei),
              let eq = ExerciseCatalog.byID(session.runs[ei].exerciseId)?.equipment?.lowercased() else { return false }
        return eq.contains("barbell") || eq.contains("curl bar")
    }
}
#endif
