#if os(iOS)
import SwiftUI
import StrandDesign
import StrandTraining

// MARK: - Tarjetas de «La Hoja viva» (FER-167 · F2)
//
// `HojaTarjetaEjercicioSesion`: el ejercicio ACTIVO — mock `hoja-pantallas.html` P3/P4, vidrio
// índigo (`EntrenarModulo(tono: .indigo)`), filas `HojaFilaSerie` en contexto `.sesion` (el caso que
// F1 ya construyó y nunca ejercitó fuera de su #Preview), la banda de descanso ANCLADA bajo la fila
// que la causó. `HojaTarjetaSuperserieSesion`: la superserie en sesión — una fila por MIEMBRO
// mostrando su ronda actual (round-robin del motor vigente), SIN divisores de ronda ni banda interna
// (F3 los trae); palomeo intercalado funciona porque cada fila llama al MISMO `confirmOrToggleSet`.
// `HojaPlegadaSesion`: el resto de la rutina, receta de una línea, sin acordeón tocable (la Hoja
// viva no pliega/abre — el foco lo decide el motor, no un tap).

struct HojaTarjetaEjercicioSesion: View {
    let vivo: HojaSesionViva
    let ei: Int

    private var run: StrengthSessionModel.ExerciseRun { vivo.session.runs[ei] }

    var body: some View {
        EntrenarModulo(tono: .indigo) {
            VStack(alignment: .leading, spacing: 0) {
                chead
                if vivo.session.canTakeHeldRaise(at: ei) { raisePill.padding(.top, 4) }
                tabla.padding(.top, 6)
                footer.padding(.top, 8)
            }
        }
        .liquidEntrada()
        .accessibilityElement(children: .contain)
    }

    private var chead: some View {
        HStack(spacing: 10) {
            Button { vivo.detailExercise = ExerciseCatalog.byID(run.exerciseId) } label: {
                SessionRunThumb(exerciseId: run.exerciseId, side: 40)
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("Opens the exercise"))
            Text(run.name).font(StrandFont.headline).foregroundStyle(vivo.sheet.theme.ink)
                .frame(maxWidth: .infinity, alignment: .leading).lineLimit(1)
            Button { vivo.menuExerciseIndex = ei } label: {
                Image(systemName: "ellipsis").font(StrandFont.glyph(.inline, weight: .semibold))
                    .foregroundStyle(vivo.sheet.theme.inkTertiary).frame(width: 30, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("More options for \(run.name)"))
            .paperMenu(
                isPresented: Binding(get: { vivo.menuExerciseIndex == ei }, set: { if !$0 { vivo.menuExerciseIndex = nil } }),
                items: vivo.exerciseMenuItems(ei: ei, run: run)
            )
        }
    }

    /// «Subida esperando ▲» — la propuesta de la barra RETENIDA (mapa: intervención vigente, alcanzable
    /// aquí). El «por qué» expandible es F4 (deload/intervención); esta hoja solo ofrece tomarla.
    private var raisePill: some View {
        Button {
            withAnimation(.snappy) { _ = vivo.session.takeHeldRaise(at: ei) }
        } label: {
            HStack(spacing: 6) {
                Text(verbatim: "▲").foregroundStyle(LiquidColor.verdeProfundo)
                if let raise = run.proposedRaise {
                    Text(String(localized: "Take the raise to \(vivo.plateNumber(vivo.displayWeight(raise.toKg))) \(vivo.weightUnit())"))
                }
            }
            .font(StrandFont.caption.weight(.semibold)).foregroundStyle(vivo.sheet.theme.ink)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .overlay(Capsule().strokeBorder(vivo.sheet.theme.hairlineStrong, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var tabla: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(run.sets.enumerated()), id: \.element.id) { si, set in
                if vivo.restSlotIndex(ei: ei) == si { vivo.restBand().padding(.vertical, 6) }
                filaSerie(si: si, set: set, esPrimera: si == 0)
            }
            // El descanso puede no tener dónde anclar (el ejercicio ya cerró todas sus filas visibles) —
            // mismo respaldo que `LiveStrengthSheet.activeExerciseFooter`.
            if vivo.session.phase == .resting, ei == vivo.accordionIndex, vivo.restSlotIndex(ei: ei) == nil {
                vivo.restBand().padding(.vertical, 6)
            }
        }
    }

    private func filaSerie(si: Int, set: StrengthSessionModel.WorkingSet, esPrimera: Bool) -> some View {
        let marca: HojaFilaSerie.Marca = set.done ? .hecha : (si == run.currentSet ? .activa : .fantasma)
        let usesReps = run.type == .weightReps || run.type == .bodyweight
        let workNumber = run.sets.prefix(si + 1).reduce(0) { $0 + ($1.kind == .work ? 1 : 0) }
        let repsText: String
        switch run.type {
        case .weightReps, .bodyweight: repsText = "\(set.reps)"
        case .time: repsText = (set.timeS ?? 0) > 0 ? SessionClock.format(set.timeS ?? 0) : "—"
        case .distance: repsText = (set.distanceM ?? 0) > 0 ? String(format: "%.1f", (set.distanceM ?? 0) / 1000) : "—"
        }
        let datos = HojaFilaSerie.Datos(
            numero: set.kind == .warmup ? String(localized: "C") : "\(workNumber)",
            esCalentamiento: set.kind == .warmup,
            peso: usesReps ? vivo.plateNumber(vivo.displayWeight(set.weightKg)) : "—",
            unidad: run.type == .weightReps ? vivo.weightUnit() : "",
            conSubida: set.kind == .work && run.proposedRaise?.waiting == false,
            reps: repsText,
            q: marca == .hecha ? set.rpe.map(LiveStrengthSheet.qLabel(fromRPE:)) : nil,
            ant: marca == .activa ? vivo.antPlayhead(run) : nil,
            esPrimera: esPrimera
        )
        return HojaFilaSerie(datos: datos, contexto: .sesion, marca: marca) {
            vivo.confirmOrToggleSet(ei: ei, si: si)
        }
    }

    @ViewBuilder private var footer: some View {
        let workSets = run.sets.filter { $0.kind == .work }
        let allDone = !workSets.isEmpty && workSets.allSatisfy(\.done)
        HStack {
            if !allDone {
                Button { withAnimation(.snappy) { vivo.session.addSet(exercise: ei) } } label: {
                    Text(verbatim: "＋ \(String(localized: "SET"))")
                        .font(InstrumentoType.grotesk(9.5, weight: .bold, relativeTo: .caption2)).tracking(1)
                        .foregroundStyle(LiquidColor.tinta900)
                        .padding(.horizontal, 11).padding(.vertical, 6)
                        .background(Capsule().fill(Color.white.opacity(0.72)))   // token-exempt: misma receta privada que HojaTarjetaEjercicio.agregarSerie (EntrenarCapsulaPuerta.fondoAlfa, sin token público)
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.9), lineWidth: 1))   // token-exempt: EntrenarCapsulaPuerta.highlightAlfa, no expuesto
                }
                .buttonStyle(.liquidPress)
                .accessibilityLabel(Text("Add set"))
            } else if let next = vivo.session.activeExercises.first(where: { $0.index > ei }) {
                Text("Done · Next: \(next.run.name)")
                    .font(StrandFont.caption).foregroundStyle(vivo.sheet.theme.inkSecondary)
            } else {
                Text("Done").font(StrandFont.caption).foregroundStyle(vivo.sheet.theme.inkSecondary)
            }
            Spacer()
        }
    }
}

/// Ejercicio SIN abrir — recibo de una línea (hecho/pendiente/«sigue»). El foco de la Hoja viva lo
/// decide el motor (`accordionIndex`), nunca un tap — a diferencia de F1, aquí no hay acordeón que abrir.
struct HojaPlegadaSesion: View {
    let vivo: HojaSesionViva
    let ei: Int

    private var run: StrengthSessionModel.ExerciseRun { vivo.session.runs[ei] }
    private var allDone: Bool {
        let work = run.sets.filter { $0.kind == .work }
        return !work.isEmpty && work.allSatisfy(\.done)
    }
    private var sigue: Bool {
        vivo.session.activeExercises.first { $0.index > vivo.accordionIndex }?.index == ei
    }

    var body: some View {
        EntrenarModulo(tono: .neutro) {
            HStack(spacing: 11) {
                if allDone {
                    ZStack {
                        Circle().fill(LiquidColor.verdePrimario)
                        Text(verbatim: "✓").font(StrandFont.caption.weight(.bold)).foregroundStyle(Color.white)
                    }
                    .frame(width: 22, height: 22)
                }
                Text(run.name).font(StrandFont.subhead.weight(.semibold)).foregroundStyle(vivo.sheet.theme.ink).lineLimit(1)
                Spacer(minLength: 8)
                if sigue {
                    Text("continues").font(StrandFont.caption).foregroundStyle(vivo.sheet.theme.inkTertiary)
                } else {
                    Text(vivo.recetaSummary(run))
                        .font(InstrumentoType.groteskNumber(12.5, weight: .bold, relativeTo: .caption))
                        .foregroundStyle(vivo.sheet.theme.inkTertiary).lineLimit(1)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(run.name), \(allDone ? String(localized: "done") : vivo.recetaSummary(run))"))
    }
}

/// La superserie en sesión (mapa C2/mock `.ss2`): una fila por MIEMBRO, su ronda actual, palomeo
/// intercalado — round-robin real del motor (`registerCurrentSet`), sin divisores de ronda (F3).
struct HojaTarjetaSuperserieSesion: View {
    let vivo: HojaSesionViva
    let members: [Int]

    private var nombre: String {
        members.map { vivo.session.runs[$0].name }.joined(separator: " ＋ ")
    }

    var body: some View {
        EntrenarModulo(tono: .indigo) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    SupersetTag()
                    Spacer()
                }
                Text(nombre).font(StrandFont.headline).foregroundStyle(vivo.sheet.theme.ink)
                    .padding(.top, 4).padding(.bottom, 6)
                ForEach(members, id: \.self) { ei in filaMiembro(ei) }
            }
        }
        .liquidEntrada()
    }

    private func filaMiembro(_ ei: Int) -> some View {
        let run = vivo.session.runs[ei]
        let si = run.currentSet
        let set = run.sets.indices.contains(si) ? run.sets[si] : nil
        let marca: HojaFilaSerie.Marca = (set?.done ?? false) ? .hecha : .activa
        let datos = HojaFilaSerie.Datos(
            numero: "\(si + 1)", esCalentamiento: false,
            peso: run.type == .weightReps ? vivo.plateNumber(vivo.displayWeight(set?.weightKg ?? 0)) : "—",
            unidad: run.type == .weightReps ? vivo.weightUnit() : "",
            conSubida: false,
            reps: (run.type == .weightReps || run.type == .bodyweight) ? "\(set?.reps ?? 0)" : "—",
            q: nil, ant: nil, esPrimera: ei == members.first
        )
        return VStack(alignment: .leading, spacing: 2) {
            Text(run.name).font(StrandFont.caption).foregroundStyle(vivo.sheet.theme.inkTertiary).lineLimit(1)
            HojaFilaSerie(datos: datos, contexto: .sesion, marca: marca) {
                guard let si = run.sets.indices.contains(si) ? si : nil else { return }
                vivo.confirmOrToggleSet(ei: ei, si: si)
            }
        }
    }
}
#endif
