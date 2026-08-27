#if os(iOS)
import SwiftUI
import StrandDesign
import StrandTraining

// MARK: - RoutineSheet — captura con el keypad de la sesión (FER-166)
//
// Ported de `RoutineEditorScreen`: el editor sigue tecleando con `SessionKeypad`, no con el teclado
// nativo. Extendido a TRES campos por serie (antes dos): peso, reps-piso, reps-techo
// (`RoutineSet.repsRangeTop`, E13/FER-94) — el GAP que este issue cierra («dale ESCRITURA a
// repsRangeTop»). `HojaFilaSerie` no expone celdas tocables por campo (es un componente de solo
// lectura, ver su doc); la composición (`HojaTarjetaEjercicio`) superpone una tira invisible con la
// MISMA geometría (`HojaMetrics`) para distinguir peso / reps-piso / reps-techo / arrastre sin
// tocar la interfaz del componente.

extension RoutineSheet {

    // MARK: - Bindings

    func repsText(idx: Int, si: Int) -> Binding<String> {
        Binding(get: { items[idx].re.sets[si].reps.map(String.init) ?? "" },
                set: { items[idx].re.sets[si].reps = Int($0.filter(\.isNumber)); dirty = true
                       mirrorAcrossRoundsIfSuperset(idx: idx, si: si) })
    }

    /// C2 (tarjeta única de superserie, sin A1/A2): el mock muestra UNA fila por miembro, no una
    /// por ronda — la prescripción se edita de una vez y se refleja a TODAS las rondas de ese
    /// miembro, para que «N rondas» nunca quede con datos huérfanos en filas que ya no se ven. Las
    /// series SOLO (fuera de superserie) no pasan por aquí — cada una sigue siendo independiente.
    func mirrorAcrossRoundsIfSuperset(idx: Int, si: Int) {
        guard RoutineSetEditing.inSuperset(items.map(\.re), idx) else { return }
        let src = items[idx].re.sets[si]
        for i in items[idx].re.sets.indices where i != si {
            items[idx].re.sets[i].weightKg = src.weightKg
            items[idx].re.sets[i].reps = src.reps
            items[idx].re.sets[i].repsRangeTop = src.repsRangeTop
        }
    }

    /// El TECHO del rango (E13/FER-94): vacío = sin rango, un solo piso fijo (comportamiento de
    /// siempre). Un valor menor o igual al piso se acepta tal cual — `RoutineSet.repsRangeLabel` ya
    /// lo trata como dato inválido y cae a solo el piso, así que no hay estado imposible que mostrar.
    func repsTopText(idx: Int, si: Int) -> Binding<String> {
        Binding(get: { items[idx].re.sets[si].repsRangeTop.map(String.init) ?? "" },
                set: { items[idx].re.sets[si].repsRangeTop = Int($0.filter(\.isNumber)); dirty = true
                       mirrorAcrossRoundsIfSuperset(idx: idx, si: si) })
    }

    func weightText(idx: Int, si: Int) -> Binding<String> {
        Binding(
            get: {
                guard let kg = items[idx].re.sets[si].weightKg, kg > 0 else { return "" }
                return StrengthDisplay.weightNumber(kg, system: system)
            },
            set: { raw in
                let norm = raw.replacingOccurrences(of: ",", with: ".")
                dirty = true
                if let v = Double(norm), v > 0 {
                    items[idx].re.sets[si].weightKg = system == .imperial ? UnitFormatter.poundsToKg(v) : v
                } else {
                    items[idx].re.sets[si].weightKg = nil
                }
                mirrorAcrossRoundsIfSuperset(idx: idx, si: si)
            })
    }

    func binding(for cell: EditorCell) -> Binding<String> {
        switch cell.field {
        case .weight:    return weightText(idx: cell.idx, si: cell.si)
        case .repsFloor: return repsText(idx: cell.idx, si: cell.si)
        case .repsTop:   return repsTopText(idx: cell.idx, si: cell.si)
        }
    }

    /// Toca una celda: la activa y siembra el buffer con su valor actual (sin teclear todavía).
    func beginEditing(_ cell: EditorCell) {
        guard !locked else { return }
        withAnimation(.snappy(duration: 0.22)) { activeCell = cell }
        buffer = binding(for: cell).wrappedValue
        bufferTyped = false
    }

    // MARK: - Keypad (montado al pie, atado a la celda activa)

    @ViewBuilder var keypadInset: some View {
        if let cell = activeCell {
            SessionKeypad(
                theme: theme,
                stepLabel: cell.field == .weight ? (system == .imperial ? "±5" : "±2,5") : "±1",
                canCopyPrevious: false,
                platesEnabled: false,
                onDigit: { keypadInput(String($0)) },
                onComma: { keypadComma() },
                onBackspace: { keypadBackspace() },
                onNext: { focusNextCell(after: cell) },
                onCopyPrevious: {},
                onStep: { keypadStep(cell) },
                stepDownEnabled: false,
                // «Copiar arriba»: el editor copia la MISMA columna de la serie anterior. Oculto en
                // la primera serie — no hay «arriba» de qué copiar.
                onCopyAbove: cell.si > 0 ? { copyAbove(cell) } : nil,
                confirmSetEnabled: false,
                onHide: { withAnimation(.snappy(duration: 0.22)) { activeCell = nil } }
            )
            .transition(.move(edge: .bottom))
        }
    }

    func keypadInput(_ digit: String) {
        if !bufferTyped { buffer = ""; bufferTyped = true }
        buffer += digit
        commitBuffer()
    }

    func keypadComma() {
        guard let cell = activeCell, cell.field == .weight else { return }   // reps son enteras
        if !bufferTyped { buffer = "0"; bufferTyped = true }
        if !buffer.contains(",") && !buffer.contains(".") { buffer += "," }
        commitBuffer()
    }

    func keypadBackspace() {
        if !bufferTyped { buffer = ""; bufferTyped = true }
        if !buffer.isEmpty { buffer.removeLast() }
        commitBuffer()
    }

    /// El ± suma un paso sobre el valor del MODELO (no sobre el buffer a medias), y resincroniza.
    func keypadStep(_ cell: EditorCell) {
        guard items.indices.contains(cell.idx), items[cell.idx].re.sets.indices.contains(cell.si) else { return }
        switch cell.field {
        case .weight:
            let stepKg = system == .imperial ? 5 * 0.45359237 : 2.5
            let current = items[cell.idx].re.sets[cell.si].weightKg ?? 0
            items[cell.idx].re.sets[cell.si].weightKg = current + stepKg
        case .repsFloor:
            items[cell.idx].re.sets[cell.si].reps = (items[cell.idx].re.sets[cell.si].reps ?? 0) + 1
        case .repsTop:
            let floor = items[cell.idx].re.sets[cell.si].reps ?? 0
            let current = items[cell.idx].re.sets[cell.si].repsRangeTop ?? floor
            items[cell.idx].re.sets[cell.si].repsRangeTop = current + 1
        }
        dirty = true
        buffer = binding(for: cell).wrappedValue
        bufferTyped = false
    }

    /// Empuja el buffer por el binding, que ya parsea y guarda (incluida la conversión imperial).
    func commitBuffer() {
        guard let cell = activeCell else { return }
        binding(for: cell).wrappedValue = buffer
    }

    /// «Copiar arriba»: copia el valor YA FORMATEADO del MISMO campo de la serie anterior, dentro
    /// del MISMO ejercicio. Un valor vacío arriba no copia nada.
    func copyAbove(_ cell: EditorCell) {
        guard cell.si > 0, items.indices.contains(cell.idx),
              items[cell.idx].re.sets.indices.contains(cell.si - 1) else { return }
        let above = EditorCell(idx: cell.idx, si: cell.si - 1, field: cell.field)
        let value = binding(for: above).wrappedValue
        guard !value.isEmpty else { return }
        withAnimation(.snappy(duration: 0.22)) { activeCell = cell }
        buffer = value
        bufferTyped = true
        commitBuffer()
    }

    /// Peso → reps-piso de la misma serie → peso de la siguiente. El techo (reps-rango) es un campo
    /// aparte que no entra en la cadena automática — se llega a él tocando la mitad derecha de la
    /// celda de reps (ver `HojaTarjetaEjercicio`), y de ahí «siguiente» también salta a la próxima
    /// serie: no encadena techo tras techo.
    func focusNextCell(after cell: EditorCell) {
        guard items.indices.contains(cell.idx) else { activeCell = nil; return }
        let type = items[cell.idx].exercise.type
        let next: EditorCell? = {
            if cell.field == .weight, showsReps(type) {
                return EditorCell(idx: cell.idx, si: cell.si, field: .repsFloor)
            }
            let nextSi = cell.si + 1
            guard items[cell.idx].re.sets.indices.contains(nextSi) else { return nil }
            return EditorCell(idx: cell.idx, si: nextSi, field: showsWeight(type) ? .weight : .repsFloor)
        }()
        withAnimation(.snappy(duration: 0.22)) { activeCell = next }
        if let next { buffer = binding(for: next).wrappedValue; bufferTyped = false }
    }
}
#endif
