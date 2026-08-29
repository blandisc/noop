#if os(iOS)
import SwiftUI
import StrandDesign
import StrandTraining

// MARK: - HojaSesionViva — la consola contextual (FER-167 · F2, mock P3/P4)
//
// «Cero tecleo en el camino feliz»: la consola vive SIEMPRE anclada abajo mientras se captura (no
// espera un tap en una celda) — los dígitos pre-editan la SIGUIENTE serie (`effectiveCell` apunta
// sola a `session.currentIndex`/`currentSet` hasta que el usuario toca una celda distinta), y la
// tecla verde grande dice **✓ SERIE**. Durante el descanso (B2) la MISMA tecla se vuelve **SALTAR
// ›** y el renglón QUEDABAN se calla (mock: `.qrow` solo vive en P3). Motor idéntico a
// `LiveStrengthSheet` — solo cambia cuándo se muestra el teclado.
//
// Sin tecla ocultar (FER-167 ronda 2 · R19): la consola always-on no tiene de dónde reabrirse, así
// que `onHide` se queda en `nil` (default) — `SessionKeypad` ya la retira sola.

extension HojaSesionViva {

    /// La celda que la consola edita AHORA MISMO: la que el usuario tocó, o —sin ninguna elegida— la
    /// serie activa del ejercicio en foco (el «pre-editar la siguiente» del mapa).
    var effectiveCell: LiveStrengthSheet.CellRef? {
        if let activeCell { return activeCell }
        guard session.summary == nil, !isZombie,
              session.runs.indices.contains(session.currentIndex) else { return nil }
        let run = session.runs[session.currentIndex]
        guard run.type == .weightReps || run.type == .bodyweight else { return nil }
        return .weight(session.currentIndex, run.currentSet)
    }

    func cellIndices(_ ref: LiveStrengthSheet.CellRef) -> (Int, Int) {
        switch ref { case let .weight(e, s): return (e, s); case let .reps(e, s): return (e, s) }
    }
    func isWeightCell(_ ref: LiveStrengthSheet.CellRef) -> Bool {
        if case .weight = ref { return true }; return false
    }

    /// R3/R10: abre la consola sobre una celda concreta — el tap-zone de una fila activa/fantasma
    /// (peso o reps) llama esto, igual que tocar una celda en F1.
    func beginEditing(_ cell: LiveStrengthSheet.CellRef) {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) { activeCell = cell; keypadHidden = false }
        syncBufferFromModel(cell)
    }

    /// R10 (QA D6 = Grok 7): «copiar anterior» — paridad `LiveStrengthSheet` 1439/1446/4082. Solo
    /// vivo con peso×reps, que es donde `previousText` tiene algo que copiar.
    func previousText(_ run: StrengthSessionModel.ExerciseRun) -> String? {
        guard let w = run.lastWeightKg, let r = run.lastReps else { return nil }
        return "\(plateNumber(displayWeight(w))) × \(r)"
    }

    @ViewBuilder var keypadInset: some View {
        if !keypadHidden, session.summary == nil, !isZombie, let cell = effectiveCell {
            if session.phase == .resting {
                // O-r2b (ronda 3): un `TimelineView` propio para que la tecla vuelva a preguntar
                // «¿estamos en el tope?» cada segundo, igual que la banda — sin esto, la consola se
                // quedaba dicha «Saltar ›» aunque la banda ya hubiera pasado a «Continuar ›».
                TimelineView(.periodic(from: Date(), by: 1)) { ctx in
                    keypadBody(cell: cell, ceiling: isCeilingReleased(now: ctx.date))
                }
            } else {
                keypadBody(cell: cell, ceiling: false)
            }
        }
    }

    @ViewBuilder private func keypadBody(cell: LiveStrengthSheet.CellRef, ceiling: Bool) -> some View {
        let (ei, si) = cellIndices(cell)
        let run = session.runs.indices.contains(ei) ? session.runs[ei] : nil
        let resting = session.phase == .resting
        SessionKeypad(
            theme: sheet.theme,
            stepLabel: isWeightCell(cell) ? (imperial ? "±5" : "±2,5") : "±1",
            canCopyPrevious: run.map { previousText($0) != nil } ?? false,
            platesEnabled: isWeightCell(cell) && usesBarbell(ei),
            onDigit: { keypadInput(String($0), cell: cell) },
            onComma: { keypadComma(cell: cell) },
            onBackspace: { keypadBackspace(cell: cell) },
            onNext: { focusNextCell(after: cell) },
            onCopyPrevious: {
                guard let run, let text = previousText(run) else { return }
                session.prefillPrevious(exercise: ei, set: si)
                buffer = text; bufferTyped = true
            },
            onStep: { keypadStep(cell, sign: 1) },
            onStepDown: { keypadStep(cell, sign: -1) },
            onPlates: { openPlates(ei: ei, si: si) },
            // FER-223: SIN háptico propio aquí — `confirmOrToggleSet` llega a `registerActiveSet`
            // (el único funnel de «serie registrada») cuando de verdad palomea una serie; poner otro
            // aquí duplicaba el golpe. El des-palomear (toggle a no-hecho) tampoco lleva háptico,
            // igual que antes.
            onConfirmSet: { resting ? skipRest() : confirmOrToggleSet(ei: ei, si: si) },
            // O-r2b: en el tope, MISMA palabra que la banda — «Continuar ›», no «Saltar ›» (la
            // acción de fondo no cambia: `skipRest()` sigue siendo lo que suelta el descanso).
            confirmSetLabel: resting
                ? (ceiling ? String(localized: "Continue") + " ›" : String(localized: "Skip") + " ›")
                // FER-225 — reuses Foco's «Set done» key (→ «Serie hecha») instead of the ad hoc
                // «✓ Serie», so the register-a-set CTA reads the same canon copy everywhere.
                : "✓ " + String(localized: "Set done"),
            confirmSetAccessibilityLabel: resting
                ? (ceiling ? Text("Continue") : Text("Skip rest")) : Text("Mark set as done"),
            onHide: { withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) { keypadHidden = true } },
            onPause: alternarPausa,
            isPaused: session.paused,
            // QUEDABAN se calla durante el descanso (mock P4: `.pad` sin `.qrow`).
            selectedRIR: resting ? nil : LiveStrengthSheet.rirScoped(
                selectedRIR: selectedRIR, selectedRIRTarget: selectedRIRTarget,
                registering: LiveStrengthSheet.RIRTarget(ei: ei, si: si)),
            onSelectRIR: resting ? nil : { selectedRIR = $0; selectedRIRTarget = LiveStrengthSheet.RIRTarget(ei: ei, si: si) }
        )
        .transition(.move(edge: .bottom))
    }

    func currentCellString(_ ref: LiveStrengthSheet.CellRef) -> String {
        let (ei, si) = cellIndices(ref)
        guard session.runs.indices.contains(ei), session.runs[ei].sets.indices.contains(si) else { return "" }
        let set = session.runs[ei].sets[si]
        switch ref {
        case .weight: return set.weightKg > 0 ? plateNumber(displayWeight(set.weightKg)) : ""
        case .reps: return set.reps > 0 ? "\(set.reps)" : ""
        }
    }

    func syncBufferFromModel(_ cell: LiveStrengthSheet.CellRef) { buffer = currentCellString(cell); bufferTyped = false }

    func keypadInput(_ digit: String, cell: LiveStrengthSheet.CellRef) {
        activeCell = cell
        if !bufferTyped { buffer = ""; bufferTyped = true }
        buffer += digit
        commitBuffer(cell)
    }
    func keypadComma(cell: LiveStrengthSheet.CellRef) {
        guard isWeightCell(cell) else { return }
        activeCell = cell
        if !bufferTyped { buffer = "0"; bufferTyped = true }
        if !buffer.contains(",") && !buffer.contains(".") { buffer += "," }
        commitBuffer(cell)
    }
    func keypadBackspace(cell: LiveStrengthSheet.CellRef) {
        activeCell = cell
        if !bufferTyped { buffer = ""; bufferTyped = true }
        if !buffer.isEmpty { buffer.removeLast() }
        commitBuffer(cell)
    }
    /// R9 (Grok 9): el paso ± opera sobre el VALOR DE LA CELDA (léelo → suma paso → escribe por el
    /// mismo camino que `commitBuffer`) — antes llamaba `session.bumpWeight`/`bumpReps`, que mutan
    /// el set CORRIENTE del motor, distinto de la celda que la consola está editando tras «Siguiente».
    func keypadStep(_ cell: LiveStrengthSheet.CellRef, sign: Int) {
        let (ei, si) = cellIndices(cell)
        guard session.runs.indices.contains(ei), session.runs[ei].sets.indices.contains(si) else { return }
        let set = session.runs[ei].sets[si]
        let newValue: String
        switch cell {
        case .weight:
            newValue = plateNumber(displayWeight(set.weightKg) + (imperial ? Double(sign) * 5 : Double(sign) * weightStepKg))
        case .reps:
            newValue = "\(max(0, set.reps + sign))"
        }
        activeCell = cell
        buffer = newValue
        bufferTyped = true
        commitBuffer(cell)
    }
    private func commitBuffer(_ cell: LiveStrengthSheet.CellRef) {
        let (ei, si) = cellIndices(cell)
        guard session.runs.indices.contains(ei), session.runs[ei].sets.indices.contains(si) else { activeCell = nil; return }
        let norm = buffer.replacingOccurrences(of: ",", with: ".")
        switch cell {
        case .weight:
            let v = Double(norm) ?? 0
            session.setWeight(exercise: ei, set: si, kg: imperial ? UnitFormatter.poundsToKg(v) : v)
        case .reps:
            session.setReps(exercise: ei, set: si, reps: Int(norm) ?? 0)
        }
    }
    func focusNextCell(after cell: LiveStrengthSheet.CellRef) {
        let (ei, si) = cellIndices(cell)
        guard session.runs.indices.contains(ei) else { activeCell = nil; return }
        let type = session.runs[ei].type
        let usesReps = type == .weightReps || type == .bodyweight
        let usesWeight = type == .weightReps
        let next: LiveStrengthSheet.CellRef? = {
            if case .weight = cell, usesReps { return .reps(ei, si) }
            let nextSi = si + 1
            guard session.runs[ei].sets.indices.contains(nextSi) else { return nil }
            return usesWeight ? .weight(ei, nextSi) : .reps(ei, nextSi)
        }()
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) { activeCell = next }
        if let next { syncBufferFromModel(next) }
    }
    func openPlates(ei: Int, si: Int) {
        guard session.runs.indices.contains(ei), session.runs[ei].sets.indices.contains(si) else { return }
        platesTarget = LiveStrengthSheet.PlatesTarget(ei: ei, weightKg: session.runs[ei].sets[si].weightKg)
    }
}
#endif
