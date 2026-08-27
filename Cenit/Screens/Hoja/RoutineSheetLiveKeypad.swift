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

    @ViewBuilder var keypadInset: some View {
        if session.summary == nil, !isZombie, let cell = effectiveCell {
            let (ei, si) = cellIndices(cell)
            let resting = session.phase == .resting
            SessionKeypad(
                theme: sheet.theme,
                stepLabel: isWeightCell(cell) ? (imperial ? "±5" : "±2,5") : "±1",
                canCopyPrevious: false,
                platesEnabled: isWeightCell(cell) && usesBarbell(ei),
                onDigit: { keypadInput(String($0), cell: cell) },
                onComma: { keypadComma(cell: cell) },
                onBackspace: { keypadBackspace(cell: cell) },
                onNext: { focusNextCell(after: cell) },
                onCopyPrevious: {},
                onStep: { keypadStep(cell, sign: 1) },
                onStepDown: { keypadStep(cell, sign: -1) },
                onPlates: { openPlates(ei: ei, si: si) },
                onConfirmSet: { resting ? skipRest() : confirmOrToggleSet(ei: ei, si: si) },
                confirmSetLabel: resting ? String(localized: "Skip") + " ›" : String(localized: "✓ Serie"),
                confirmSetAccessibilityLabel: resting ? Text("Skip rest") : Text("Mark set as done"),
                onHide: { withAnimation(.snappy(duration: 0.22)) { activeCell = nil } },
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
    func keypadStep(_ cell: LiveStrengthSheet.CellRef, sign: Int) {
        let (ei, si) = cellIndices(cell)
        guard session.runs.indices.contains(ei), session.runs[ei].sets.indices.contains(si) else { return }
        switch cell {
        case .weight: session.bumpWeight(byKg: Double(sign) * weightStepKg)
        case .reps: session.bumpReps(sign)
        }
        activeCell = cell
        buffer = currentCellString(cell)
        bufferTyped = false
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
        withAnimation(.snappy(duration: 0.22)) { activeCell = next }
        if let next { syncBufferFromModel(next) }
    }
    func openPlates(ei: Int, si: Int) {
        guard session.runs.indices.contains(ei), session.runs[ei].sets.indices.contains(si) else { return }
        platesTarget = LiveStrengthSheet.PlatesTarget(ei: ei, weightKg: session.runs[ei].sets[si].weightKg)
    }
}
#endif
