#if os(iOS)
import SwiftUI
import StrandDesign
import StrandTraining

// MARK: - HojaTarjetaSuperserieCompuesta — la superserie compuesta con `HojaTarjetaSuperserie` (FER-166)
//
// Mock `hoja-pantallas.html` P1 `.ss2` / mapa C2: tarjeta única, nombre real («Zancadas ＋ Curl
// femoral»), SIN letras A1/A2 — decisión vigente, el recorte A5 del mapa que sigue con letras está
// stale. `HojaTarjetaSuperserie` (StrandDesign) trae el cristal cian + header + pie; esta vista
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

    private var rondas: Int { sheet.items[members[0]].re.sets.count }

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
            ForEach(members, id: \.self) { idx in
                filaMiembro(idx)
            }
        }
        .liquidEntrada()
        .paperMenu(
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
        let set = item.re.sets.first
        // R11 (QA D7): `relativeTo` en las tres — cero fuentes fixedSize en texto de lectura.
        return HStack(alignment: .firstTextBaseline, spacing: HojaMetrics.filaGap) {
            Text(StrengthDisplay.name(item.exercise))
                .font(InstrumentoType.grotesk(11.5, weight: .semibold, relativeTo: .caption2))
                .foregroundStyle(LiquidColor.tinta900)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(verbatim: sheet.showsWeight(type) ? (set?.weightKg.map { StrengthDisplay.weightNumber($0, system: sheet.system) } ?? "—") : "—")
                    .font(InstrumentoType.groteskNumber(15, weight: .bold, relativeTo: .callout)).foregroundStyle(LiquidColor.tinta900)
                if sheet.showsWeight(type) {
                    Text(verbatim: StrengthDisplay.weightUnit(sheet.system).lowercased())
                        .font(InstrumentoType.grotesk(10, weight: .semibold, relativeTo: .caption2)).foregroundStyle(LiquidColor.tinta500)
                        .padding(.leading, 2)
                }
            }
            .frame(width: HojaMetrics.colPesoEdicion, alignment: .leading)
            Text(sheet.showsReps(type) ? (set?.repsRangeLabel ?? "—") : "—")
                .font(InstrumentoType.groteskNumber(15, weight: .bold, relativeTo: .callout)).foregroundStyle(LiquidColor.tinta900)
                .frame(width: HojaMetrics.colRepsEdicion, alignment: .leading)
            Text(verbatim: "≡")
                .font(InstrumentoType.grotesk(HojaMetrics.agarreSize, weight: .regular, relativeTo: .caption))
                .foregroundStyle(LiquidColor.tinta500)
                .frame(width: HojaMetrics.colMarcaEdicion, alignment: .trailing)
        }
        .padding(.vertical, HojaMetrics.filaVPad)
        .frame(minHeight: HojaMetrics.hitMin)
        .contentShape(Rectangle())
        .overlay {
            let re = item.re
            let memberId = re.id
            // R7(a): señal de celda activa (mismo patrón que la tarjeta sola).
            let activeField: RoutineSheet.EditorCell.Field? =
                (sheet.activeCell?.idx == idx && sheet.activeCell?.si == 0) ? sheet.activeCell?.field : nil
            HStack(spacing: HojaMetrics.filaGap) {
                Color.clear.frame(maxWidth: .infinity)
                tapZone(sheet.showsWeight(type) ? { sheet.beginEditing(.init(idx: idx, si: 0, field: .weight)) } : nil,
                        active: activeField == .weight)
                    .frame(width: HojaMetrics.colPesoEdicion)
                tapZone(sheet.showsReps(type) ? { sheet.beginEditing(.init(idx: idx, si: 0, field: .repsFloor)) } : nil,
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
                    Rectangle().fill(LiquidColor.tinta900).frame(height: 2).padding(.bottom, 6)
                }
            }
    }

    // MARK: - «···» — reordenar en bloque, deshacer, ＋ ronda, y el menú completo de cada miembro

    private var menuItems: [PaperMenuItem] {
        var rows: [PaperMenuItem] = []
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
            rows.append(.init(StrengthDisplay.name(sheet.items[idx].exercise), systemImage: nil,
                              children: sheet.exerciseMenuItems(idx)))
        }
        return rows
    }
}
#endif
