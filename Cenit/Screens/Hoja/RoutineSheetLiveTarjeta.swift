#if os(iOS)
import SwiftUI
import StrandDesign
import StrandTraining

// MARK: - Tarjetas de «La Hoja viva» (FER-167 · F2, ronda 2)
//
// `HojaTarjetaEjercicioSesion`: el ejercicio ACTIVO — mock `hoja-pantallas.html` P3/P4, vidrio
// índigo (`EntrenarModulo(tono: .indigo)`), filas `HojaFilaSerie` en contexto `.sesion`, la banda
// de descanso ANCLADA bajo la fila que la causó. `HojaTarjetaSuperserieSesion`: la superserie en
// sesión — una fila por MIEMBRO (su ronda actual, round-robin del motor vigente), palomeo
// intercalado, Y su propia banda de descanso al cerrar ronda (R4) — sin divisores de ronda ni
// rediseño interno, eso sigue siendo F3. `HojaPlegadaSesion`: el resto de la rutina, tocable (R5) —
// un tap mueve el foco guiado ahí, paridad `LiveStrengthSheet.doneRow`/`comingRow`.
//
// REGLA DURA: cero `ForEach(..., id: \.self)` sobre `Int`. Toda identidad de fila es el `id` del
// run/set — `ei`/`si` se derivan frescos en cada construcción, nunca sobreviven como ancla.

struct HojaTarjetaEjercicioSesion: View {
    let vivo: HojaSesionViva
    let ei: Int

    private var run: StrengthSessionModel.ExerciseRun { vivo.session.runs[ei] }

    var body: some View {
        EntrenarModulo(tono: .indigo) {
            VStack(alignment: .leading, spacing: 0) {
                chead
                notaF.padding(.top, 4)   // R11(b): ✎ Nota, adjudicado — misma hoja que F1
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

    /// R11(b): ✎ Nota — paridad `HojaTarjetaEjercicio.notaF` (F1), misma `NoteSheet` (capa 3).
    private var notaF: some View {
        Button { vivo.openNote(ei: ei) } label: {
            HStack(alignment: .top, spacing: 4) {
                Text(verbatim: "✎").font(StrandFont.footnote)
                let note = run.note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                Text(note.isEmpty ? String(localized: "Add note") : note)
                    .font(StrandFont.caption).foregroundStyle(vivo.sheet.theme.inkTertiary)
                    .lineLimit(2).multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// «Subida esperando ▲» — la propuesta de la barra RETENIDA (mapa: intervención vigente, alcanzable
    /// aquí). El «por qué» expandible es F4 (deload/intervención); esta hoja solo ofrece tomarla.
    private var raisePill: some View {
        Button {
            withAnimation(vivo.reduceMotion ? nil : .snappy) { _ = vivo.session.takeHeldRaise(at: ei) }
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
            ForEach(run.sets, id: \.id) { set in
                let si = run.sets.firstIndex { $0.id == set.id } ?? 0
                if vivo.restSlotIndex(ei: ei) == si { vivo.restBand().padding(.vertical, 6) }
                filaSerie(si: si, set: set, esPrimera: si == 0)
                    .id("hoja-viva-serie-\(set.id)")   // R14: ancla de scroll-to por identidad, no índice
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
        // R3: tap en peso/reps de una fila activa/fantasma abre la consola sobre ESA celda —
        // paridad de intención con las tap-zones de F1 (`HojaFilaSerieTapZones`).
        .overlay {
            if marca != .hecha, usesReps {
                TapZonesSesion(
                    onPeso: { vivo.beginEditing(.weight(ei, si)) },
                    onReps: { vivo.beginEditing(.reps(ei, si)) }
                )
            }
        }
        // R16: destello rosa breve al palomear con récord — sin animación si Reduce Motion.
        .background {
            if vivo.prFlashSetId == set.id {
                RoundedRectangle(cornerRadius: HojaMetrics.activaRadius, style: .continuous)
                    .fill(LiquidColor.rosa.opacity(0.16))   // token-exempt: destello breve R16, sin token de opacidad para «molde rosa» transitorio todavía
                    .transition(vivo.reduceMotion ? .identity : .opacity)
            }
        }
        .animation(vivo.reduceMotion ? nil : .easeOut(duration: 0.4), value: vivo.prFlashSetId)
    }

    @ViewBuilder private var footer: some View {
        let workSets = run.sets.filter { $0.kind == .work }
        let allDone = !workSets.isEmpty && workSets.allSatisfy(\.done)
        HStack {
            if !allDone {
                Button { withAnimation(vivo.reduceMotion ? nil : .snappy) { vivo.session.addSet(exercise: ei) } } label: {
                    Text(verbatim: "＋ \(String(localized: "SET"))")
                        .font(InstrumentoType.grotesk(9.5, weight: .bold, relativeTo: .caption2)).tracking(1)
                        .foregroundStyle(LiquidColor.tinta900)
                        .padding(.horizontal, 11).padding(.vertical, 6)
                        .background(Capsule().fill(HojaLiveMetrics.capsulaFondo))
                        .overlay(Capsule().strokeBorder(HojaLiveMetrics.capsulaBorde, lineWidth: 1))
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

/// Tira invisible con la geometría de `HojaFilaSerie` en contexto `.sesion` (`HojaMetrics`), para
/// distinguir toques por campo sin ensanchar el componente sellado — mismo patrón que
/// `HojaFilaSerieTapZones` de F1, con las columnas de sesión (peso 86 / reps flexible). La columna
/// de marca queda SIN gesto propio (`allowsHitTesting(false)`): el ✓/pendiente de `HojaFilaSerie`
/// ya tiene su botón ahí, y una zona encima se lo robaría.
private struct TapZonesSesion: View {
    let onPeso: (() -> Void)?
    let onReps: (() -> Void)?

    var body: some View {
        HStack(spacing: HojaMetrics.filaGap) {
            Color.clear.frame(width: HojaMetrics.colNumero)
            zone(onPeso).frame(width: HojaMetrics.colPesoSesion)
            zone(onReps).frame(maxWidth: .infinity)
            Color.clear.frame(width: HojaMetrics.colMarca).allowsHitTesting(false)
        }
        .padding(.horizontal, HojaMetrics.filaHPad)
    }

    @ViewBuilder private func zone(_ action: (() -> Void)?) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture { action?() }
            .allowsHitTesting(action != nil)
    }
}

/// Ejercicio SIN abrir — recibo de una línea, TOCABLE (R5, paridad `LiveStrengthSheet.doneRow`/
/// `comingRow`): mueve el foco guiado ahí, para corregir una hecha o saltar a una venidera sin
/// esperar a que el motor llegue solo. El foco de la Hoja viva lo decide el motor
/// (`accordionIndex`) — este tap solo lo REDIRIGE, no abre un acordeón propio.
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
        Button {
            withAnimation(vivo.reduceMotion ? nil : .snappy(duration: 0.22)) {
                session_select()
            }
        } label: {
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
        }
        .buttonStyle(.liquidPress)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(run.name), \(allDone ? String(localized: "done") : vivo.recetaSummary(run))"))
        .accessibilityHint(Text("Moves guided focus here"))
    }

    private func session_select() {
        let target = run.sets.firstIndex { !$0.done } ?? 0
        vivo.session.select(exerciseIndex: ei, setIndex: target)
    }
}

/// La superserie en sesión (mapa C2/mock `.ss2`): una fila por MIEMBRO, su ronda actual, palomeo
/// intercalado — round-robin real del motor (`registerCurrentSet`), sin divisores de ronda (F3).
/// R4: descansa igual que un ejercicio solo — la MISMA `restBand()` anclada al pie del bloque
/// cuando el descanso pertenece a cualquiera de sus miembros.
struct HojaTarjetaSuperserieSesion: View {
    let vivo: HojaSesionViva
    let members: [Int]

    private var runs: [StrengthSessionModel.ExerciseRun] { members.map { vivo.session.runs[$0] } }
    private var nombre: String { runs.map(\.name).joined(separator: " ＋ ") }

    var body: some View {
        EntrenarModulo(tono: .indigo) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    SupersetTag()
                    Spacer()
                }
                Text(nombre).font(StrandFont.headline).foregroundStyle(vivo.sheet.theme.ink)
                    .padding(.top, 4).padding(.bottom, 6)
                // REGLA DURA: identidad por `run.id`, no por el `Int` de `members`.
                ForEach(runs) { run in filaMiembro(run) }
                if vivo.session.phase == .resting, members.contains(vivo.accordionIndex) {
                    vivo.restBand().padding(.top, 6)
                }
            }
        }
        .liquidEntrada()
    }

    private func filaMiembro(_ run: StrengthSessionModel.ExerciseRun) -> some View {
        let ei = vivo.session.runs.firstIndex { $0.id == run.id } ?? (members.first ?? 0)
        let si = run.currentSet
        let set = run.sets.indices.contains(si) ? run.sets[si] : nil
        let marca: HojaFilaSerie.Marca = (set?.done ?? false) ? .hecha : .activa
        let datos = HojaFilaSerie.Datos(
            numero: "\(si + 1)", esCalentamiento: false,
            peso: run.type == .weightReps ? vivo.plateNumber(vivo.displayWeight(set?.weightKg ?? 0)) : "—",
            unidad: run.type == .weightReps ? vivo.weightUnit() : "",
            conSubida: false,
            reps: (run.type == .weightReps || run.type == .bodyweight) ? "\(set?.reps ?? 0)" : "—",
            q: nil, ant: nil, esPrimera: run.id == runs.first?.id
        )
        return VStack(alignment: .leading, spacing: 2) {
            Text(run.name).font(StrandFont.caption).foregroundStyle(vivo.sheet.theme.inkTertiary).lineLimit(1)
            HojaFilaSerie(datos: datos, contexto: .sesion, marca: marca) {
                guard set != nil else { return }   // sin serie corriente (miembro ya cerrado), nada que marcar
                vivo.confirmOrToggleSet(ei: ei, si: si)
            }
        }
    }
}

/// Constantes compartidas de «＋ SET» — F1 (`HojaTarjetaEjercicio.agregarSerie`) y la Hoja viva
/// pintan la MISMA cápsula («la última vez» seed sobre vidrio); antes cada archivo repetía los
/// literales `Color.white.opacity(0.72/0.9)` (Grok 15 + QA O5). Sin token público en StrandDesign
/// todavía — GAP anotado en el reporte por si conviene promoverlas.
enum HojaLiveMetrics {
    static let capsulaFondo = Color.white.opacity(0.72)   // token-exempt: EntrenarCapsulaPuerta.fondoAlfa, sin token público (R21, compartida con F1)
    static let capsulaBorde = Color.white.opacity(0.9)   // token-exempt: EntrenarCapsulaPuerta.highlightAlfa, sin token público (R21, compartida con F1)
}
#endif
