#if os(iOS)
import SwiftUI
import CenitDesign
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
                set: { raw in
                    guard !locked else { return }
                    guard !holdForMirrorConfirm(idx: idx, si: si, field: .repsFloor, raw: raw) else { return }
                    items[idx].re.sets[si].reps = Int(raw.filter(\.isNumber))
                    // R4: subir el piso puede invalidar un techo ya puesto — re-normaliza los dos
                    // juntos, no solo la celda que se acaba de teclear.
                    items[idx].re.sets[si].repsRangeTop = RoutineSet.normalizedRepsRangeTop(
                        reps: items[idx].re.sets[si].reps, top: items[idx].re.sets[si].repsRangeTop,
                        mode: items[idx].re.sets[si].mode)
                    dirty = true
                    mirrorAcrossRoundsIfSuperset(idx: idx, si: si)
                })
    }

    /// C2 (tarjeta única de superserie, sin A1/A2): el mock muestra UNA fila por miembro, no una
    /// por ronda — la prescripción se edita de una vez y se refleja a TODAS las rondas de TRABAJO
    /// de ese miembro, para que «N rondas» nunca quede con datos huérfanos en filas que ya no se
    /// ven. N3 (ronda 3): un calentamiento (si el miembro llegó con rampa desde antes de agruparse)
    /// NO es una ronda — el espejo lo salta, nunca lo pisa ni lo clona. Las series SOLO (fuera de
    /// superserie) no pasan por aquí — cada una sigue siendo independiente.
    func mirrorAcrossRoundsIfSuperset(idx: Int, si: Int) {
        guard RoutineSetEditing.inSuperset(items.map(\.re), idx) else { return }
        RoutineSetEditing.mirrorWorkSets(&items[idx].re.sets, from: si)
    }

    /// R8 (QA D10, adjudicado): si esta serie pertenece a una superserie cuyas rondas YA son
    /// desiguales entre sí (dato legado, de antes de que el espejo existiera), la escritura que
    /// dispararía el espejo se queda en `pendingMirror` en vez de aplicarse — `true` = espera un
    /// confirm, nada se tocó todavía. Rondas ya parejas no preguntan nada (no hay qué perder).
    func holdForMirrorConfirm(idx: Int, si: Int, field: EditorCell.Field, raw: String) -> Bool {
        guard RoutineSetEditing.inSuperset(items.map(\.re), idx), !roundsAreEven(idx) else { return false }
        pendingMirror = PendingMirror(idx: idx, si: si, field: field, value: raw)
        return true
    }

    /// N3: compara solo series de TRABAJO — un calentamiento (40-80 % rampeado, distinto por
    /// diseño) no debe disparar el confirm de «rondas desiguales» en cada edición.
    ///
    /// Ola 1 · FER-327: era una COPIA carácter por carácter de `RoutineSetEditing.workSetsAreEqual`, y
    /// al agregar `mode` a la igualdad (v5 N15) hubo que tocarla dos veces — la señal de que eran dos
    /// oráculos de la misma regla. Ahora delega: «rondas parejas» ES «series iguales».
    func roundsAreEven(_ idx: Int) -> Bool {
        RoutineSetEditing.workSetsAreEqual(items[idx].re.sets)
    }

    /// Libera un `pendingMirror`: escribe el valor que había quedado en espera y espeja normal.
    func confirmPendingMirror() {
        guard let p = pendingMirror, !locked,
              items.indices.contains(p.idx), items[p.idx].re.sets.indices.contains(p.si) else {
            pendingMirror = nil
            return
        }
        switch p.field {
        case .weight:
            let norm = p.value.replacingOccurrences(of: ",", with: ".")
            if let v = Double(norm), v > 0 {
                items[p.idx].re.sets[p.si].weightKg = system == .imperial ? UnitFormatter.poundsToKg(v) : v
            } else {
                items[p.idx].re.sets[p.si].weightKg = nil
            }
        case .repsFloor:
            items[p.idx].re.sets[p.si].reps = Int(p.value.filter(\.isNumber))
            items[p.idx].re.sets[p.si].repsRangeTop = RoutineSet.normalizedRepsRangeTop(
                reps: items[p.idx].re.sets[p.si].reps, top: items[p.idx].re.sets[p.si].repsRangeTop,
                mode: items[p.idx].re.sets[p.si].mode)
        case .repsTop:
            items[p.idx].re.sets[p.si].repsRangeTop = RoutineSet.normalizedRepsRangeTop(
                reps: items[p.idx].re.sets[p.si].reps, top: Int(p.value.filter(\.isNumber)),
                mode: items[p.idx].re.sets[p.si].mode)
        }
        dirty = true
        mirrorAcrossRoundsIfSuperset(idx: p.idx, si: p.si)
        pendingMirror = nil
    }

    /// El TECHO del rango (E13/FER-94): vacío = sin rango, un solo piso fijo (comportamiento de
    /// siempre). R4 (FER-166 ronda 2): un techo que no supera al piso NUNCA se persiste — se
    /// normaliza a `nil` al commitear (`RoutineSet.normalizedRepsRangeTop`), nunca un "10-8"
    /// invertido, ni un instante antes de espejarse a otras rondas de una superserie.
    func repsTopText(idx: Int, si: Int) -> Binding<String> {
        Binding(get: { items[idx].re.sets[si].repsRangeTop.map(String.init) ?? "" },
                set: { raw in
                    guard !locked else { return }
                    guard !holdForMirrorConfirm(idx: idx, si: si, field: .repsTop, raw: raw) else { return }
                    let candidate = Int(raw.filter(\.isNumber))
                    items[idx].re.sets[si].repsRangeTop = RoutineSet.normalizedRepsRangeTop(
                        reps: items[idx].re.sets[si].reps, top: candidate,
                        mode: items[idx].re.sets[si].mode)
                    dirty = true
                    mirrorAcrossRoundsIfSuperset(idx: idx, si: si)
                })
    }

    func weightText(idx: Int, si: Int) -> Binding<String> {
        Binding(
            get: {
                guard let kg = items[idx].re.sets[si].weightKg, kg > 0 else { return "" }
                return StrengthDisplay.weightNumber(kg, system: system)
            },
            set: { raw in
                guard !locked else { return }
                guard !holdForMirrorConfirm(idx: idx, si: si, field: .weight, raw: raw) else { return }
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
        guard !locked else { return }
        if !bufferTyped { buffer = ""; bufferTyped = true }
        buffer += digit
        commitBuffer()
    }

    func keypadComma() {
        guard !locked else { return }
        guard let cell = activeCell, cell.field == .weight else { return }   // reps son enteras
        if !bufferTyped { buffer = "0"; bufferTyped = true }
        if !buffer.contains(",") && !buffer.contains(".") { buffer += "," }
        commitBuffer()
    }

    func keypadBackspace() {
        guard !locked else { return }
        if !bufferTyped { buffer = ""; bufferTyped = true }
        if !buffer.isEmpty { buffer.removeLast() }
        commitBuffer()
    }

    /// El ± suma un paso sobre el valor del MODELO (no sobre el buffer a medias), y resincroniza.
    /// Pasa por el MISMO binding que el teclear directo (no escribe aparte): así hereda el candado
    /// (R1), la invariante piso ≤ techo (R4) y el confirm de rondas desiguales (R8) sin duplicar
    /// esas tres reglas una segunda vez aquí.
    func keypadStep(_ cell: EditorCell) {
        guard !locked, items.indices.contains(cell.idx), items[cell.idx].re.sets.indices.contains(cell.si) else { return }
        let set = items[cell.idx].re.sets[cell.si]
        let newValue: String
        switch cell.field {
        case .weight:
            let stepKg = system == .imperial ? 5 * 0.45359237 : 2.5
            newValue = StrengthDisplay.weightNumber((set.weightKg ?? 0) + stepKg, system: system)
        case .repsFloor:
            newValue = "\((set.reps ?? 0) + 1)"
        case .repsTop:
            let floor = set.reps ?? 0
            newValue = "\((set.repsRangeTop ?? floor) + 1)"
        }
        binding(for: cell).wrappedValue = newValue
        buffer = binding(for: cell).wrappedValue
        bufferTyped = false
    }

    /// Empuja el buffer por el binding, que ya parsea y guarda (incluida la conversión imperial).
    /// R7: si la celda dueña ya no existe (se borró el ejercicio/serie mientras el keypad seguía
    /// montado), no escribe sobre un índice fantasma — se limpia en su lugar.
    func commitBuffer() {
        guard !locked, let cell = activeCell else { return }
        guard items.indices.contains(cell.idx), items[cell.idx].re.sets.indices.contains(cell.si) else {
            activeCell = nil
            return
        }
        binding(for: cell).wrappedValue = buffer
    }

    /// «Copiar arriba»: copia el valor YA FORMATEADO del MISMO campo de la serie anterior, dentro
    /// del MISMO ejercicio. Un valor vacío arriba no copia nada.
    func copyAbove(_ cell: EditorCell) {
        guard !locked, cell.si > 0, items.indices.contains(cell.idx),
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
