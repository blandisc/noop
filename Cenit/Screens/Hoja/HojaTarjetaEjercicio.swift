#if os(iOS)
import SwiftUI
import StrandDesign
import StrandTraining
import StrandAnalytics

// MARK: - HojaTarjetaEjercicio — la tarjeta ABIERTA de un ejercicio SOLO (FER-166)
//
// Mock `hoja-pantallas.html` P1 `.mod` (Sentadilla): chead (miniatura + nombre + chip de descanso +
// «···») · sube (progresión activa) · notaF (nota fija ✎) · tabla (`HojaFilaSerie` por serie) ·
// ＋ SERIE. Vidrio neutro vía `EntrenarModulo` — La Hoja abandona el riel/dot de «recibo» de
// `RoutineEditorScreen`: son tarjetas de vidrio independientes, sin hilo.

struct HojaTarjetaEjercicio: View {
    let sheet: RoutineSheet
    let idx: Int

    private var item: EditorItem { sheet.items[idx] }
    private var type: ExerciseType { item.exercise.type }

    var body: some View {
        EntrenarModulo(tono: .neutro) {
            VStack(alignment: .leading, spacing: 0) {
                chead
                if item.re.progressionEnabled {
                    ProgressionChip(re: item.re, system: sheet.system, theme: sheet.theme,
                                    derivedIncrementKg: PlateMath.minimumIncrement(
                                        for: .from(equipment: item.exercise.equipment), inventory: sheet.plates.inventory),
                                    disabled: sheet.locked,
                                    action: { sheet.progressionTarget = ProgressionTarget(ei: idx) })
                        .padding(.top, LiquidSpace.s150)
                }
                notaF
                tabla
                if !sheet.locked { agregarSerie.padding(.top, LiquidSpace.s200) }
            }
        }
        .liquidEntrada()
        .accessibilityElement(children: .contain)
        // R12 (QA D13 = Grok G9): rotor de VoiceOver al modo reorder que ya existe (el editor viejo
        // lo tenía; se había perdido en la composición nueva).
        .accessibilityAction(named: Text("Reorder exercises")) {
            guard !sheet.locked else { return }
            sheet.activeCell = nil
            withAnimation(.snappy) { sheet.reordering = true }
        }
    }

    // MARK: - Cabecera

    private var chead: some View {
        HStack(spacing: LiquidSpace.s250) {
            Button { sheet.detailExercise = item.exercise } label: {
                ExerciseThumbView(exercise: item.exercise, side: 40)
                    .overlay(RoundedRectangle(cornerRadius: ExerciseThumbnail.tileCornerRadius(side: 40), style: .continuous)
                        .strokeBorder(sheet.theme.movementFamilyTint(primaryMuscles: item.exercise.primaryMuscles), lineWidth: 2))
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("Opens the exercise"))
            Button { sheet.detailExercise = item.exercise } label: {
                VStack(alignment: .leading, spacing: LiquidSpace.s025) {
                    if type != .weightReps {
                        Text(StrengthDisplay.subtitle(item.exercise)).liquidKicker().foregroundStyle(LiquidColor.tinta500)
                    }
                    Text(StrengthDisplay.name(item.exercise)).font(LiquidType.titulo).foregroundStyle(LiquidColor.tinta900)
                        .fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("Opens the exercise"))
            RestChip(cfg: sheet.exerciseRest(idx)) {
                sheet.activeCell = nil; sheet.restTarget = RestEditTarget(ei: idx, si: 0)
            }
            .disabled(sheet.locked)
            if !sheet.locked { menuButton }
        }
        .padding(.bottom, LiquidSpace.s150)
    }

    private var menuButton: some View {
        Button { sheet.menuExerciseIndex = idx } label: {
            StrandIcon.more.image.font(LiquidType.infoGlifo.weight(.semibold))
                .foregroundStyle(LiquidColor.tinta500).frame(width: 30, height: LiquidControl.hitTarget).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("More options"))   // R12 (QA D13 = Grok G9)
        .liquidMenu(
            isPresented: Binding(get: { sheet.menuExerciseIndex == idx },
                                 set: { if !$0 { sheet.menuExerciseIndex = nil } }),
            items: sheet.exerciseMenuItems(idx)
        )
    }

    // MARK: - Nota fija (✎)

    private var notaF: some View {
        Button { sheet.openNote(idx) } label: {
            HStack(alignment: .top, spacing: LiquidSpace.s100) {
                Text(verbatim: "✎").font(LiquidType.caption)
                let note = item.re.note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                Text(note.isEmpty ? String(localized: "Add note") : note)
                    .font(LiquidType.caption)
                    .foregroundStyle(LiquidColor.tinta500)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(sheet.locked)
        .padding(.bottom, LiquidSpace.s150)
    }

    // MARK: - Tabla

    private var tabla: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(item.re.sets.enumerated()), id: \.element.id) { si, set in
                filaSerie(si: si, set: set)
            }
        }
    }

    private func filaSerie(si: Int, set: RoutineSet) -> some View {
        let setId = set.id
        let warmup = set.kind == .warmup
        let anterior: String? = warmup ? rampaLabel : sheet.lastSetHistoryLabel(idx: idx, si: si, type: type)
        let datos = HojaFilaSerie.Datos(
            numero: RoutineSetEditing.setLabel(item.re, si),
            esCalentamiento: warmup,
            peso: sheet.showsWeight(type) ? (set.weightKg.map { StrengthDisplay.weightNumber($0, system: sheet.system) } ?? "—") : "—",
            unidad: sheet.showsWeight(type) ? StrengthDisplay.weightUnit(sheet.system).lowercased() : "",
            conSubida: false,
            reps: sheet.showsReps(type) ? (set.repsRangeLabel ?? "—") : "—",
            anterior: anterior,
            arrastrable: true,
            esPrimera: si == 0
        )
        // R7(a): la celda activa de ESTA fila (si la hay) — la tira de toques dibuja su señal.
        let activeField: RoutineSheet.EditorCell.Field? =
            (sheet.activeCell?.idx == idx && sheet.activeCell?.si == si) ? sheet.activeCell?.field : nil
        return HojaFilaSerie(datos: datos, contexto: .edicion, marca: .pendiente)
            .overlay {
                HojaFilaSerieTapZones(
                    onPeso: sheet.showsWeight(type) ? { sheet.beginEditing(.init(idx: idx, si: si, field: .weight)) } : nil,
                    onRepsFloor: sheet.showsReps(type) ? { sheet.beginEditing(.init(idx: idx, si: si, field: .repsFloor)) } : nil,
                    onRepsTop: sheet.showsReps(type) ? { sheet.beginEditing(.init(idx: idx, si: si, field: .repsTop)) } : nil,
                    activeField: activeField,
                    // R2 (QA D2 = Grok G6): `setId` FROZEN, nunca el `si` de esta construcción de
                    // fila — un swap a medio gesto ya lo dejaría mirando a la serie equivocada.
                    onDragChanged: { t in sheet.dragSetChanged(idx: idx, setId: setId, translation: t) },
                    onDragEnded: { sheet.dragSetEnded() }
                )
            }
            .overlay(alignment: .trailing) {
                if sheet.armedDeleteSetId == setId {
                    DeleteSetPill {
                        withAnimation(.snappy) { sheet.armedDeleteSetId = nil; sheet.deleteSet(idx: idx, setId: setId) }
                    }
                }
            }
            .simultaneousGesture(LongPressGesture(minimumDuration: 0.4).onEnded { _ in
                guard !sheet.locked, item.re.sets.count > 1 else { return }
                withAnimation(LiquidMotion.suave) { sheet.armedDeleteSetId = setId }
            })
            .simultaneousGesture(TapGesture().onEnded {
                if sheet.armedDeleteSetId != nil {
                    withAnimation(LiquidMotion.suave) { sheet.armedDeleteSetId = nil }
                }
            })
            .accessibilityActions {
                if !sheet.locked, item.re.sets.count > 1 {
                    Button("Delete set") { sheet.deleteSet(idx: idx, setId: setId) }
                }
            }
    }

    /// «rampa 40·60·80 %» — la ANTERIOR de una fila de calentamiento no es historia, es la regla
    /// (siempre la misma rampa, `RoutineSetEditing.warmupFactors`).
    private var rampaLabel: String {
        let pct = RoutineSetEditing.warmupFactors.map { "\(Int(($0 * 100).rounded()))" }.joined(separator: "·")
        return String(localized: "ramp \(pct) %")
    }

    // MARK: - ＋ SERIE
    //
    // Cápsula compacta «＋ SET» — `HojaCapsulaAccion` del catálogo (FER-301); sin chevron
    // (acción dentro de la hoja, no puerta a otra pantalla).
    private var agregarSerie: some View {
        HojaCapsulaAccion("＋ \(String(localized: "SET"))") { sheet.addSet(idx) }
            .accessibilityLabel(Text("Add set"))
    }
}

/// Tira invisible con la MISMA geometría que `HojaFilaSerie.edicion` (`HojaMetrics`), superpuesta
/// para distinguir toques por campo sin ensanchar la interfaz del componente sellado: peso · reps
/// piso (mitad izquierda de la celda de reps) · reps techo (mitad derecha, GAP «dale ESCRITURA a
/// repsRangeTop») · arrastre ≡ (reordenar series).
private struct HojaFilaSerieTapZones: View {
    let onPeso: (() -> Void)?
    let onRepsFloor: (() -> Void)?
    let onRepsTop: (() -> Void)?
    /// R7(a): qué campo de ESTA fila está activo (o nil) — dibuja la señal de foco, restaurada del
    /// `setCellChrome(focused:)` del editor viejo (subrayado tinta cuando enfocado).
    let activeField: RoutineSheet.EditorCell.Field?
    let onDragChanged: (CGFloat) -> Void
    let onDragEnded: () -> Void

    var body: some View {
        HStack(spacing: HojaMetrics.filaGap) {
            Color.clear.frame(width: HojaMetrics.colNumero)
            zone(onPeso, active: activeField == .weight).frame(width: HojaMetrics.colPesoEdicion)
            HStack(spacing: 0) {
                zone(onRepsFloor, active: activeField == .repsFloor)
                zone(onRepsTop, active: activeField == .repsTop)
            }
            .frame(width: HojaMetrics.colRepsEdicion)
            Color.clear.frame(maxWidth: .infinity)
            Color.clear.frame(width: HojaMetrics.colMarcaEdicion)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 4)
                        .onChanged { onDragChanged($0.translation.height) }
                        .onEnded { _ in onDragEnded() }
                )
        }
        .padding(.horizontal, HojaMetrics.filaHPad)
    }

    @ViewBuilder private func zone(_ action: (() -> Void)?, active: Bool) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture { action?() }
            .allowsHitTesting(action != nil)
            .overlay(alignment: .bottom) {
                if active {
                    Rectangle().fill(LiquidColor.tinta900).frame(height: EntrenarMetrics.currentEdge)
                        .padding(.bottom, LiquidSpace.s150)
                }
            }
    }
}
#endif
