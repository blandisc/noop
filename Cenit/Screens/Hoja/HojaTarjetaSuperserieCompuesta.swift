#if os(iOS)
import SwiftUI
import CenitDesign
import StrandTraining

// MARK: - HojaTarjetaSuperserieCompuesta — la superserie compuesta con `HojaTarjetaSuperserie` (FER-166)
//
// Mock `hoja-pantallas.html` P1 `.ss2` / mapa C2: tarjeta única, nombre real («Zancadas ＋ Curl
// femoral»), SIN letras A1/A2 — decisión vigente, el recorte A5 del mapa que sigue con letras está
// stale. `HojaTarjetaSuperserie` (CenitDesign) trae el cristal cian + header + pie; esta vista
// arma sus filas y su «···».
//
// Decisión (documentada en el reporte): el mock dibuja UNA fila por MIEMBRO, no una por ronda —
// distinto de una tarjeta de ejercicio solo, que abre una fila por serie. Editar la fila visible
// escribe la serie 0 del miembro Y LA REFLEJA a todas sus rondas (`mirrorAcrossRoundsIfSuperset`),
// para que ninguna ronda quede con datos huérfanos que la tarjeta ya no muestra. Cambiar el número
// de rondas es explícito: «＋ RONDA» / quitar la última (long-press), en vez de series
// individuales — la superserie no pyramidea por ronda en esta hoja.
struct HojaTarjetaSuperserieCompuesta: View {
    let sheet: RoutineSheet
    let members: [Int]

    private var nombre: String {
        members.map { StrengthDisplay.name(sheet.items[$0].exercise) }.joined(separator: " ＋ ")
    }

    /// N3 (ronda 3, moderado): rondas son series de TRABAJO — un calentamiento no cuenta (mentía
    /// «6 rounds» cuando en realidad eran 3 rondas + una rampa de 3 pasos).
    private var rondas: Int { sheet.items[members[0]].re.sets.filter { $0.kind == .work }.count }

    /// N1 (ronda 3, bloqueante): `ForEach(members, id: \.self)` identificaba por POSICIÓN — tras un
    /// swap, la vista de «posición 3» seguía viva (misma identidad) pero su clausura recomputaba
    /// `memberId` con el ejercicio que acababa de ATERRIZAR ahí, no el que el dedo seguía
    /// arrastrando. El `dragID` capturado por el gesto pasaba a ser otro EN CADA EVENTO → el par se
    /// intercambiaba sin parar (misma clase que R2/D2: autosalvado, corrompía la rutina). Fix:
    /// identidad por el id REAL del ejercicio — la vista «sigue» a su contenido cuando se mueve, en
    /// vez de que el contenido cambie bajo una vista fija (mismo patrón que las series de
    /// `HojaTarjetaEjercicio.tabla`, `ForEach(..., id: \.element.id)`).
    private struct MemberSlot: Identifiable { let idx: Int; let id: String }
    private var memberSlots: [MemberSlot] {
        members.map { MemberSlot(idx: $0, id: sheet.items[$0].id) }
    }

    /// R15 (QA D14): «N rondas · descanso al cerrar cada ronda · M:SS» — el orden y la copia EXACTA
    /// del mock (`hoja-pantallas.html` P1 `.ss2`, pie del footer).
    private var pie: String {
        let restLabel = RoutineSetEditing.restChipLabel(sheet.exerciseRest(members.last ?? members[0]))
        return String(localized: "\(rondas) rounds") + " · "
            + String(localized: "rest when each round closes") + " · " + restLabel
    }

    var body: some View {
        // R1 (paridad con la tarjeta sola, `HojaTarjetaEjercicio.chead` línea 70): sin sesión viva
        // corriendo, no hay «···» — nada que mutar bajo el candado.
        let onMenu: (() -> Void)? = sheet.locked ? nil : { sheet.menuExerciseIndex = members[0] }
        HojaTarjetaSuperserie(nombre: nombre, pie: pie, onMenu: onMenu) {
            ForEach(memberSlots) { slot in
                filaMiembro(slot.idx)
            }
        }
        .liquidEntrada()
        .liquidMenu(
            isPresented: Binding(get: { sheet.menuExerciseIndex == members[0] },
                                 set: { if !$0 { sheet.menuExerciseIndex = nil } }),
            items: menuItems
        )
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: Text("Reorder exercises")) {   // R12
            guard !sheet.locked else { return }
            sheet.activeCell = nil
            withAnimation(.snappy) { sheet.reordering = true }
        }
    }

    // MARK: - Filas de miembro (`.trow.ssrow`: nombre flex · peso 76 · reps · ≡)

    private func filaMiembro(_ idx: Int) -> some View {
        let item = sheet.items[idx]
        let type = item.exercise.type
        // N3: la fila muestra la PRIMERA serie de TRABAJO — nunca la rampa, que si existe vive
        // antes (posición 0..2) por cómo la inserta `addWarmupRamp`.
        let workSi = sheet.firstWorkIndex(idx)
        let set = workSi.map { item.re.sets[$0] }
        // R11 (QA D7): `relativeTo` en las tres — cero fuentes fixedSize en texto de lectura.
        // FER-310: nombre→tituloFila; peso/reps→valorS; unidad→captionFuerte; agarre→captionRegular.
        return HStack(alignment: .firstTextBaseline, spacing: HojaMetrics.filaGap) {
            Text(StrengthDisplay.name(item.exercise))
                .font(LiquidType.tituloFila)
                .foregroundStyle(LiquidColor.tinta900)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(verbatim: sheet.showsWeight(type) ? (set?.weightKg.map { StrengthDisplay.weightNumber($0, system: sheet.system) } ?? "—") : "—")
                    .font(LiquidType.valorS).foregroundStyle(LiquidColor.tinta900)
                if sheet.showsWeight(type) {
                    Text(verbatim: StrengthDisplay.weightUnit(sheet.system).lowercased())
                        .font(LiquidType.captionFuerte).foregroundStyle(LiquidColor.tinta500)
                        .padding(.leading, LiquidSpace.s050)
                }
            }
            .frame(width: HojaMetrics.colPesoEdicion, alignment: .leading)
            Text(sheet.showsReps(type) ? (set?.repsRangeLabel ?? "—") : "—")
                .font(LiquidType.valorS).foregroundStyle(LiquidColor.tinta900)
                .frame(width: HojaMetrics.colRepsEdicion, alignment: .leading)
            Text(verbatim: "≡")
                .font(LiquidType.captionRegular)
                .foregroundStyle(LiquidColor.tinta500)
                .frame(width: HojaMetrics.colMarcaEdicion, alignment: .trailing)
        }
        .padding(.vertical, HojaMetrics.filaVPad)
        .frame(minHeight: HojaMetrics.hitMin)
        .contentShape(Rectangle())
        .overlay {
            let re = item.re
            let memberId = re.id
            // N3: se edita/enfoca la primera serie de TRABAJO, no la posición 0 a secas.
            let editSi = workSi ?? 0
            // R7(a): señal de celda activa (mismo patrón que la tarjeta sola).
            let activeField: RoutineSheet.EditorCell.Field? =
                (sheet.activeCell?.idx == idx && sheet.activeCell?.si == editSi) ? sheet.activeCell?.field : nil
            HStack(spacing: HojaMetrics.filaGap) {
                Color.clear.frame(maxWidth: .infinity)
                tapZone(sheet.showsWeight(type) ? { sheet.beginEditing(.init(idx: idx, si: editSi, field: .weight)) } : nil,
                        active: activeField == .weight)
                    .frame(width: HojaMetrics.colPesoEdicion)
                tapZone(sheet.showsReps(type) ? { sheet.beginEditing(.init(idx: idx, si: editSi, field: .repsFloor)) } : nil,
                        active: activeField == .repsFloor)
                    .frame(width: HojaMetrics.colRepsEdicion)
                Color.clear.frame(width: HojaMetrics.colMarcaEdicion)
                    .contentShape(Rectangle())
                    .gesture(
                        // R2 (QA D2 = Grok G6): `dragID` = `RoutineExercise.id` FROZEN — nunca el
                        // `idx` de esta construcción de fila.
                        DragGesture(minimumDistance: 4)
                            .onChanged { sheet.dragMemberChanged(members: members, dragID: memberId, translation: $0.translation.height) }
                            .onEnded { _ in sheet.dragSetEnded() }
                    )
            }
        }
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.4).onEnded { _ in
            guard !sheet.locked, rondas > 1 else { return }
            sheet.removeLastRound(members: members)
        })
    }

    @ViewBuilder private func tapZone(_ action: (() -> Void)?, active: Bool) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture { action?() }
            .allowsHitTesting(action != nil)
            .overlay(alignment: .bottom) {
                if active {
                    Rectangle().fill(LiquidColor.tinta900).frame(height: EntrenarMetrics.currentEdge).padding(.bottom, LiquidSpace.s150)
                }
            }
    }

    // MARK: - «···» — reordenar en bloque, deshacer, ＋ ronda, y el menú completo de cada miembro

    private var menuItems: [LiquidMenuItem] {
        var rows: [LiquidMenuItem] = []
        rows.append(.init(String(localized: "Reorder exercises"), systemImage: "line.3.horizontal") {
            sheet.activeCell = nil
            withAnimation(.snappy) { sheet.reordering = true }
        })
        rows.append(.init(String(localized: "Add round"), systemImage: "plus.circle") { sheet.addRound(members: members) })
        if rondas > 1 {
            rows.append(.init(String(localized: "Remove last round"), systemImage: "minus.circle") { sheet.removeLastRound(members: members) })
        }
        rows.append(.init(String(localized: "Undo superset"), systemImage: "link", isDestructive: true) {
            sheet.breakSuperset(members[0])
        })
        for idx in members {
            // N3 (decisión): sin «Add warm-up» aquí — la tarjeta de superserie no tiene dónde
            // mostrar una rampa (una fila por miembro, atada a rondas sincronizadas). Ver la nota
            // en `RoutineSheetLogic.exerciseMenuItems`.
            rows.append(.init(StrengthDisplay.name(sheet.items[idx].exercise), systemImage: nil,
                              children: sheet.exerciseMenuItems(idx, includeWarmup: false)))
        }
        return rows
    }
}
#endif
