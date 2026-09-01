#if os(iOS)
import SwiftUI
import StrandDesign
import StrandTraining
import StrandAnalytics

// MARK: - Tarjetas de «La Hoja viva» (FER-167 · F2, ronda 2)
//
// `HojaTarjetaEjercicioSesion`: el ejercicio ACTIVO — mock `hoja-pantallas.html` P3/P4, vidrio
// índigo (`EntrenarModulo(tono: .indigo)`), filas `HojaFilaSerie` en contexto `.sesion`, la banda
// de descanso ANCLADA bajo la fila que la causó. `HojaTarjetaSuperserieSesion`: la superserie en
// sesión (FER-168 · F3) — tarjeta única con RONDAS INTERCALADAS: «Ronda K de M» (`HojaRondaDivisor`)
// antes de cada grupo, una fila por MIEMBRO por ronda, sin letras A1/A2, sin descanso entre
// miembros, y la banda de descanso ADENTRO de la tarjeta al cerrar cada ronda. `HojaPlegadaSesion`:
// el resto de la rutina, tocable (R5) — un tap mueve el foco guiado ahí, paridad
// `LiveStrengthSheet.doneRow`/`comingRow`.
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
                notaF.padding(.top, CenitMetrics.space1)   // R11(b): ✎ Nota, adjudicado — misma hoja que F1
                if vivo.session.canTakeHeldRaise(at: ei) { raisePill.padding(.top, CenitMetrics.space1) }
                if let deload = run.deloadDisplay { deloadPill(deload).padding(.top, CenitMetrics.space1) }   // B7 (FER-169)
                tabla.padding(.top, LiquidSpace.s150)
                footer.padding(.top, CenitMetrics.space2)
            }
        }
        .liquidEntrada()
        .accessibilityElement(children: .contain)
        // D0 (FER-170 · F5) + FER-187: la acción de VoiceOver, alcanzable sin ver el «⤢» — respaldo
        // del mismo gesto que el botón de `chead`, el tap del cromo (thumb+nombre) y el «Enfoque»
        // del «···» (puertas, un solo destino).
        .accessibilityAction(named: Text("Focus")) { vivo.enterFoco() }
    }

    private var chead: some View {
        HStack(spacing: LiquidSpace.s250) {
            // FER-187 · colisión 1: tap-para-foco SOLO en el cromo sin celdas (thumb + nombre).
            // Las filas `HojaFilaSerie` / `TapZonesSesion` NO se tocan — peso/reps siguen editando.
            // Esta vista (`HojaTarjetaEjercicioSesion`) solo se monta cuando `ei == accordionIndex`
            // (tarjeta activa); una plegada sigue en `HojaPlegadaSesion` (select/peek).
            cromoSinCeldas
            // D0 (FER-170 · F5): «⤢» — la puerta directa a Foco (mock `hoja-mapa.html` D0), junto al
            // «···» que ya trae «Enfoque» como respaldo. Solo sobre la tarjeta que SÍ puede enfocarse
            // (`puedeEnfocar` — no en sesión llena/zombie/acta).
            if vivo.puedeEnfocar {
                Button { vivo.enterFoco() } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(StrandFont.glyph(.inline, weight: .semibold))
                        .foregroundStyle(vivo.sheet.theme.inkTertiary).frame(width: 30, height: CenitMetrics.touchTarget).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHidden(true)   // la acción vive en `.accessibilityAction` del cuerpo — sin botón duplicado en el rotor
            }
            Button { vivo.menuExerciseIndex = ei } label: {
                StrandIcon.more.image.font(StrandFont.glyph(.inline, weight: .semibold))
                    .foregroundStyle(vivo.sheet.theme.inkTertiary).frame(width: 30, height: CenitMetrics.touchTarget).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("More options for \(run.name)"))
            .paperMenu(
                isPresented: Binding(get: { vivo.menuExerciseIndex == ei }, set: { if !$0 { vivo.menuExerciseIndex = nil } }),
                items: vivo.exerciseMenuItems(ei: ei, run: run)
            )
        }
    }

    /// Thumb + nombre: un tap abre el DETALLE del ejercicio (`detailExercise`), no el foco. Orden del
    /// dueño 2026-08-29: revierte el tap-para-foco del cromo de FER-187 — el foco es SOLO del «⤢»
    /// (y del «Enfoque» del ···). Tocar el ejercicio lleva a su subpágina; expandir lleva a Focus.
    @ViewBuilder private var cromoSinCeldas: some View {
        let thumb = SessionRunThumb(exerciseId: run.exerciseId, side: 40)
        let nombre = Text(run.name).font(StrandFont.headline).foregroundStyle(vivo.sheet.theme.ink)
            .frame(maxWidth: .infinity, alignment: .leading).lineLimit(1)
        HStack(spacing: LiquidSpace.s250) {
            thumb
            nombre
        }
        .contentShape(Rectangle())
        .onTapGesture { vivo.detailExercise = ExerciseCatalog.byID(run.exerciseId) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(Text("Opens the exercise"))
    }

    /// R11(b): ✎ Nota — paridad `HojaTarjetaEjercicio.notaF` (F1), misma `NoteSheet` (capa 3).
    private var notaF: some View {
        Button { vivo.openNote(ei: ei) } label: {
            HStack(alignment: .top, spacing: CenitMetrics.space1) {
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
        OutlineCapsule(theme: vivo.sheet.theme, size: .sm, action: {
            withAnimation(vivo.reduceMotion ? nil : .snappy) { _ = vivo.session.takeHeldRaise(at: ei) }
        }) {
            HStack(spacing: LiquidSpace.s150) {
                Text(verbatim: "▲").foregroundStyle(LiquidColor.verdeProfundo)
                if let raise = run.proposedRaise {
                    Text(String(localized: "Take the raise to \(vivo.plateNumber(vivo.displayWeight(raise.toKg))) \(vivo.weightUnit())"))
                }
            }
            .font(StrandFont.caption.weight(.semibold)).foregroundStyle(vivo.sheet.theme.ink)
        }
    }

    /// B7 (FER-169): la bajada propuesta — «↓ 3 sesiones igual · propone 76» con BAJAR/SEGUIR (mapa),
    /// o, con la política «solo avisar», la misma línea sin botones (nada que aplicar, solo el aviso).
    private func deloadPill(_ display: StrengthSessionModel.ExerciseRun.DeloadDisplay) -> some View {
        HStack(spacing: CenitMetrics.space2) {
            Text(verbatim: "↓").foregroundStyle(vivo.sheet.theme.inkSecondary)
            switch display {
            case .propose(let fromKg, let toKg):
                Text(String(localized: "\(ProgressionMath.deloadStallThreshold) sessions unmoved · proposes \(vivo.plateNumber(vivo.displayWeight(toKg))) \(vivo.weightUnit())"))
                    .font(StrandFont.caption.weight(.semibold)).foregroundStyle(vivo.sheet.theme.ink)
                Spacer(minLength: LiquidSpace.s150)
                Button { vivo.applyDeload(ei: ei, toKg: toKg) } label: {
                    Text("Drop to \(vivo.plateNumber(vivo.displayWeight(toKg)))")
                        .font(StrandFont.caption.weight(.bold)).foregroundStyle(LiquidColor.verdeProfundo)
                }
                .buttonStyle(.plain)
                Button { vivo.dismissDeload(ei: ei) } label: {
                    Text("Keep \(vivo.plateNumber(vivo.displayWeight(fromKg)))")
                        .font(StrandFont.caption.weight(.semibold)).foregroundStyle(vivo.sheet.theme.inkSecondary)
                }
                .buttonStyle(.plain)
            case .warnOnly(let sessions):
                Text(String(localized: "\(sessions) sessions unmoved · goal not met"))
                    .font(StrandFont.caption.weight(.semibold)).foregroundStyle(vivo.sheet.theme.inkSecondary)
                Spacer(minLength: LiquidSpace.s150)
                Button { vivo.dismissDeload(ei: ei) } label: {
                    Image(systemName: "xmark").font(StrandFont.glyph(.chevron)).foregroundStyle(vivo.sheet.theme.inkTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Dismiss"))
            }
        }
        .padding(.horizontal, LiquidSpace.s250).padding(.vertical, LiquidSpace.s150)
        .accessibilityElement(children: .combine)
    }

    private var tabla: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(run.sets, id: \.id) { set in
                let si = run.sets.firstIndex { $0.id == set.id } ?? 0
                if vivo.restSlotIndex(ei: ei) == si { vivo.restBand().padding(.vertical, LiquidSpace.s150) }
                // B12 (FER-169): la fila ACTIVA de tiempo/distancia es su propio cronómetro compacto
                // (piel de La Hoja sobre el flujo vigente `startSetTimer`/`stopSetTimer`/`timerElapsed`
                // de `LiveStrengthSheet` — arranca/detiene, zona de FC solo con Watch) — las demás
                // filas (pendientes/hechas) siguen la tabla genérica de siempre.
                if (run.type == .time || run.type == .distance), !set.done, si == run.currentSet {
                    cardioRow(si: si, set: set)
                        .id("hoja-viva-serie-\(set.id)")
                } else {
                    filaSerie(si: si, set: set, esPrimera: si == 0)
                        .id("hoja-viva-serie-\(set.id)")   // R14: ancla de scroll-to por identidad, no índice
                }
                // B10 (FER-169): el aviso vive justo bajo la fila que lo disparó — una pregunta a la vez.
                // Por identidad (regla dura), no por índice: B8 puede reordenar mientras el aviso sigue abierto.
                if vivo.absurdCapture?.runId == run.id, vivo.absurdCapture?.setId == set.id, let target = vivo.absurdCapture {
                    absurdCaptureBanner(target).padding(.vertical, LiquidSpace.s150)
                }
                // B11 (FER-169): el destello de récord trae su copy justo bajo la fila que lo bate.
                if vivo.prFlash?.setId == set.id, let flash = vivo.prFlash {
                    prFlashBanner(flash).padding(.vertical, LiquidSpace.s150)
                }
            }
            // El descanso puede no tener dónde anclar (el ejercicio ya cerró todas sus filas visibles) —
            // mismo respaldo que `LiveStrengthSheet.activeExerciseFooter`. Contra el DUEÑO real
            // (O-r2a), no `accordionIndex`: si el usuario espía otra tarjeta, esta banda no reaparece
            // aquí — la tarjeta dueña puede estar plegada en ese momento.
            if vivo.session.phase == .resting, ei == vivo.restOwnerExerciseIndex, vivo.restSlotIndex(ei: ei) == nil {
                vivo.restBand().padding(.vertical, LiquidSpace.s150)
            }
            // B6b (FER-169): la tarjeta «Volver a X» de esta tarjeta, si el tap en el ▲ la abrió.
            if vivo.raiseRevertOpenRunId == run.id, let raise = run.proposedRaise {
                raiseRevertCard(raise).padding(.vertical, LiquidSpace.s150)
            }
        }
    }

    /// B6b: «Volver a {fromKg}» revierte la subida ya aplicada (celdas sin palomear); «Seguir en
    /// {toKg}» solo cierra la tarjeta — ni acierto ni fallo, la aritmética lo respeta (mapa B6b).
    private func raiseRevertCard(_ raise: ProgressionPlanner.Raise) -> some View {
        NoteStrip(style: .info, theme: vivo.sheet.theme) {
            HStack(spacing: LiquidSpace.s400) {
                Button {
                    withAnimation(vivo.reduceMotion ? nil : .snappy) { vivo.raiseRevertOpenRunId = nil }
                } label: {
                    Text("Keep \(vivo.plateNumber(vivo.displayWeight(raise.toKg))) \(vivo.weightUnit())")
                        .font(StrandFont.caption.weight(.semibold)).foregroundStyle(vivo.sheet.theme.dataRecovery)
                }
                .buttonStyle(.plain)
                Button { vivo.revertRaise(ei: ei) } label: {
                    Text("Back to \(vivo.plateNumber(vivo.displayWeight(raise.fromKg))) \(vivo.weightUnit())")
                        .font(StrandFont.caption.weight(.semibold)).foregroundStyle(vivo.sheet.theme.inkSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .transition(LiquidMotion.fadeOrIdentity(reduceMotion: vivo.reduceMotion))
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
        // paridad de intención con las tap-zones de F1 (`HojaFilaSerieTapZones`). D-r2.2 (ronda 3):
        // en una fila HECHA la misma zona de reps (donde vive el sufijo «· Q») abre la hoja de RPE —
        // el viejo también lo hacía desde la tabla en línea (`tapEntrenarCell` case `.rpe`).
        .overlay {
            if usesReps {
                if marca == .hecha {
                    // B9 (FER-169): tap en peso REABRE la fila — el valor vuelve a la consola para
                    // corregirlo; re-✓ la vuelve a cerrar (mismo `confirmOrToggleSet` de siempre, sin
                    // tocar el descanso en curso: `toggleDone` al DESmarcar nunca lo cierra). Reps
                    // sigue abriendo la hoja de RPE (D-r2.2) — esa puerta ya existía y no se pierde.
                    TapZonesSesion(
                        onPeso: { vivo.reopenDoneSetForCorrection(ei: ei, si: si) },
                        onReps: { vivo.openRPE(ei: ei, si: si) }
                    )
                } else if datos.conSubida {
                    // B6b (FER-169): tocar el ▲ de una subida YA aplicada ofrece «Volver a X», no la
                    // consola — la misma zona de peso, otra intención mientras haya subida que revertir.
                    TapZonesSesion(
                        onPeso: {
                            withAnimation(vivo.reduceMotion ? nil : .snappy) {
                                vivo.raiseRevertOpenRunId = (vivo.raiseRevertOpenRunId == run.id) ? nil : run.id
                            }
                        },
                        onReps: { vivo.beginEditing(.reps(ei, si)) }
                    )
                } else {
                    TapZonesSesion(
                        onPeso: { vivo.beginEditing(.weight(ei, si)) },
                        onReps: { vivo.beginEditing(.reps(ei, si)) }
                    )
                }
            }
        }
        // R16/B11: destello rosa breve al palomear con récord — sin animación si Reduce Motion.
        .background {
            if vivo.prFlash?.setId == set.id {
                RoundedRectangle(cornerRadius: HojaMetrics.activaRadius, style: .continuous)
                    .fill(LiquidColor.rosa.opacity(0.16))   // token-exempt: destello breve R16, sin token de opacidad para «molde rosa» transitorio todavía
                    .transition(LiquidMotion.fadeOrIdentity(reduceMotion: vivo.reduceMotion))
            }
        }
        .animation(vivo.reduceMotion ? nil : .easeOut(duration: 0.4), value: vivo.prFlash)  // token-exempt(unico): destello rosa de PR al palomear serie — duración escénica de una sola fila
        // FER-223: el destello visual de PR no tenía háptico — el patrón de éxito ascendente,
        // reservado para esto y para el cierre de sesión, nunca para una serie más.
        .entrenarHaptic(.prNuevo, trigger: vivo.prFlash)
    }

    /// B12 (FER-169): el cronómetro compacto de la fila ACTIVA de tiempo/distancia (mapa: nombre ·
    /// ZONA · reloj · meta · DETENER, una sola línea) — piel de La Hoja sobre `session.startSetTimer`/
    /// `stopSetTimer`/`timerElapsed`, el mismo motor que `LiveStrengthSheet.cardioInlineRow`. Detener
    /// registra la serie (mismo `confirmOrToggleSet`, así que B10/B11 lo revisan igual que cualquiera).
    @ViewBuilder private func cardioRow(si: Int, set: StrengthSessionModel.WorkingSet) -> some View {
        let running = vivo.session.timerStart != nil
        let metaS = run.type == .time ? (set.timeS ?? 0) : nil   // «meta» solo tiene sentido con time
        EntrenarModulo(tono: .indigo) {
            HStack(alignment: .firstTextBaseline, spacing: LiquidSpace.s250) {
                Text(run.name).font(StrandFont.subhead.weight(.semibold)).foregroundStyle(vivo.sheet.theme.ink).lineLimit(1)
                if let bpm = vivo.sheet.model.watchBpm { zonaBadge(bpm) }
                Spacer(minLength: CenitMetrics.space2)
                Group {
                    if running {
                        TimelineView(.periodic(from: Date(), by: 1)) { ctx in
                            let texto = SessionClock.format(vivo.session.timerElapsed(now: ctx.date))
                            Text(texto).numeroVivo(value: texto)
                        }
                    } else {
                        let texto = SessionClock.format(set.timeS ?? 0)
                        Text(texto).numeroVivo(value: texto)
                    }
                }
                .font(InstrumentoType.groteskNumber(20, weight: .bold)).foregroundStyle(vivo.sheet.theme.ink)
                if let metaS, metaS > 0 {
                    Text("goal \(SessionClock.format(metaS))").font(StrandFont.caption).foregroundStyle(vivo.sheet.theme.inkTertiary)
                }
                OutlineCapsule(running ? "Stop" : "Start",
                               theme: vivo.sheet.theme, size: .sm, weight: .bold) {
                    if running {
                        withAnimation(vivo.reduceMotion ? nil : .snappy) { vivo.confirmOrToggleSet(ei: ei, si: si) }
                    } else {
                        vivo.session.startSetTimer()
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// «ZONA 2 · 118» — la MISMA regla de 5 zonas que `LiveStrengthSheet.hrZone` (% de tu FC máx),
    /// en la cápsula compacta de La Hoja en vez del ramp Z1–Z5 completo (ese es de la hoja vieja).
    private func zonaBadge(_ bpm: Int) -> some View {
        let maxHR = Double(vivo.sheet.model.profile.hrMax)
        let pct = maxHR > 0 ? Double(bpm) / maxHR : 0
        let zone = max(1, min(5, Int((pct * 5).rounded(.up))))
        return Text("ZONE \(zone) · \(bpm)")
            .font(StrandFont.caption.weight(.bold)).foregroundStyle(vivo.sheet.theme.inkSecondary)
            .padding(.horizontal, CenitMetrics.space2).padding(.vertical, LiquidSpace.s075)
            .overlay(Capsule().strokeBorder(vivo.sheet.theme.hairlineStrong, lineWidth: 1))
    }

    /// B11 (FER-169): el copy del mapa — «RÉCORD peso máx · antes 100.0» — bajo la fila que acaba de
    /// batirlo. Mismo rosa que el destello de la fila (R16, `LiquidColor.rosa` — sin token de acento
    /// rosa en `NoteStrip`, que solo trae `.warning`/`.info`, así que este banner queda propio con las
    /// mismas anotaciones `token-exempt` que ya usa el destello de arriba y `HojaLiveMetrics` abajo).
    @ViewBuilder private func prFlashBanner(_ flash: PRFlash) -> some View {
        HStack(spacing: LiquidSpace.s150) {
            Text("RECORD").font(StrandFont.caption.weight(.bold)).foregroundStyle(LiquidColor.rosa)
            Text(recordMetricLabel(flash.metric)).font(StrandFont.caption).foregroundStyle(vivo.sheet.theme.inkSecondary)
            if let prior = flash.priorText {
                Text(verbatim: "· ") + Text("before \(prior)")
            }
        }
        .font(StrandFont.caption).foregroundStyle(vivo.sheet.theme.inkSecondary)
        .padding(.horizontal, CenitMetrics.gap).padding(.vertical, CenitMetrics.space2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LiquidColor.rosa.opacity(0.10),   // token-exempt: mismo molde rosa transitorio que el destello R16, arriba
            in: RoundedRectangle(cornerRadius: CenitMetrics.controlRadius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: CenitMetrics.controlRadius, style: .continuous)
                .strokeBorder(LiquidColor.rosa.opacity(0.30), lineWidth: 0.5)   // token-exempt: mismo molde rosa transitorio que el destello R16, arriba
        )
        .transition(LiquidMotion.fadeOrIdentity(reduceMotion: vivo.reduceMotion))
        .accessibilityElement(children: .combine)
    }

    private func recordMetricLabel(_ metric: PRMetric) -> LocalizedStringKey {
        switch metric {
        case .maxWeight: return "max weight"
        case .maxReps:   return "max reps"
        case .maxVolume: return "max volume"
        }
    }

    /// B10 (FER-169): el aviso del mapa — «¿825 KG? es 8× tu récord» con ERA X / SÍ, N — bajo la fila
    /// que lo disparó. `NoteStrip(.warning)` (mismo cristal que otros avisos del app), reversible: ERA
    /// corrige y vuelve a pasar por el guard; SÍ guarda tal cual.
    @ViewBuilder private func absurdCaptureBanner(_ target: AbsurdCaptureTarget) -> some View {
        NoteStrip(style: .warning, theme: vivo.sheet.theme) {
            VStack(alignment: .leading, spacing: LiquidSpace.s150) {
                (Text("\(vivo.plateNumber(vivo.displayWeight(target.weightKg))) \(vivo.weightUnit().uppercased())?")
                    .font(StrandFont.caption.weight(.bold))
                 + Text(verbatim: " ")
                 + Text("is 8× your record").font(StrandFont.caption))
                    .foregroundStyle(vivo.sheet.theme.ink)
                HStack(spacing: LiquidSpace.s250) {
                    OutlineCapsule(theme: vivo.sheet.theme, size: .md, action: { vivo.correctAbsurdCapture() }) {
                        Text("It was \(vivo.plateNumber(vivo.displayWeight(target.weightKg / 10)))")
                            .font(StrandFont.caption.weight(.semibold)).foregroundStyle(vivo.sheet.theme.ink)
                    }
                    Button { vivo.confirmAbsurdCaptureAsIs() } label: {
                        Text("Yes, \(vivo.plateNumber(vivo.displayWeight(target.weightKg)))")
                            .font(StrandFont.caption.weight(.semibold)).foregroundStyle(vivo.sheet.theme.critical)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .transition(LiquidMotion.fadeOrIdentity(reduceMotion: vivo.reduceMotion))
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
                        .padding(.horizontal, CenitMetrics.gap).padding(.vertical, LiquidSpace.s150)
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
/// esperar a que el motor llegue solo.
///
/// O-r2a (ronda 3): el select explícito GANA la tarjeta abierta, SIEMPRE — al instante, sin
/// excepción. Cómo se logra difiere según si se está descansando: fuera de descanso, es el mismo
/// `session.select(...)` de siempre (paridad exacta con el viejo). DURANTE el descanso,
/// `session.select(...)` NO se llama — ese método fuerza `phase = .capturing` como efecto de lado,
/// lo que apagaría el descanso entero (el reloj, el auto-skip, la consola) solo por abrir OTRA
/// tarjeta a mirarla. En su lugar se arma `peekRunId` (un «espiar» a nivel de vista, por `id`, sin
/// tocar el modelo): la tarjeta tocada se abre igual de instantáneo, pero el descanso sigue
/// corriendo intacto en segundo plano — la banda deja de verse (su tarjeta, la del dueño, quedó
/// plegada) y eso es lo esperado, no un bug. Si el usuario palomea algo en la tarjeta espiada,
/// `confirmOrToggleSet` ya llama `session.select` cuando hace falta — ahí sí, a propósito.
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
                openTapped()
            }
        } label: {
            EntrenarModulo(tono: .neutro) {
                HStack(spacing: CenitMetrics.gap) {
                    if allDone {
                        ZStack {
                            Circle().fill(LiquidColor.verdePrimario)
                            Text(verbatim: "✓").font(StrandFont.caption.weight(.bold)).foregroundStyle(Color.white)
                        }
                        .frame(width: HojaMetrics.marcaDiametro, height: HojaMetrics.marcaDiametro)
                    }
                    Text(run.name).font(StrandFont.subhead.weight(.semibold)).foregroundStyle(vivo.sheet.theme.ink).lineLimit(1)
                    Spacer(minLength: CenitMetrics.space2)
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

    private func openTapped() {
        if vivo.session.phase == .resting {
            vivo.peekRunId = run.id   // «espiar»: el descanso del dueño sigue corriendo, sin tocar el modelo
        } else {
            let target = run.sets.firstIndex { !$0.done } ?? 0
            vivo.session.select(exerciseIndex: ei, setIndex: target)
        }
    }
}

/// La superserie en sesión (mapa C1/mock P5 `.ss2`): tarjeta única con RONDAS INTERCALADAS — un
/// divisor «Ronda K de M» (`HojaRondaDivisor`) antes de cada grupo, una fila por MIEMBRO por ronda
/// (round-robin real del motor, `registerCurrentSet`), sin letras A1/A2. Reusa `HojaTarjetaSuperserie`
/// (StrandDesign) — el mismo cristal cian + header + pastilla + «···» que ya monta C2/edición — en
/// vez de un cristal propio: la única pieza nueva de este archivo es CÓMO se arman las filas.
///
/// N3: las rondas son series de TRABAJO — un calentamiento no cuenta ni se intercala; si un miembro
/// trae rampa, sus filas «C» van ANTES del primer divisor, estilo tabla normal (`calentamientos`).
///
/// «Fila activa = la que el motor señala» (spec F3): la marca no se decide por-miembro en
/// aislamiento — se compara contra `session.currentIndex`/`currentSet`, el ÚNICO puntero real del
/// motor, así que exactamente una fila del bloque entero es `.activa` a la vez; el resto de las
/// pendientes son `.fantasma` (el «ghost» del mock). R4: la banda de descanso ya NO vive al pie del
/// bloque — se inserta ADENTRO, justo tras la ronda que la abrió (`rondaDelDescanso`).
struct HojaTarjetaSuperserieSesion: View {
    let vivo: HojaSesionViva
    let members: [Int]

    private var runs: [StrengthSessionModel.ExerciseRun] { members.map { vivo.session.runs[$0] } }
    private var nombre: String { runs.map(\.name).joined(separator: " ＋ ") }
    private var primerMiembro: Int { members.first ?? 0 }

    /// M — total de rondas del bloque. R2 (ronda 2 del gate FER-168, bloqueante): el MÁXIMO de
    /// `session.supersetRounds(at:)` sobre TODOS los miembros, no solo el primero — con un miembro
    /// posterior con más series de trabajo, anclar M al primero dejaba esas rondas sin dibujarse Y
    /// sin ninguna fila `.activa` (el puntero del motor caía fuera del rango renderizado).
    private var totalRondas: Int { members.map { vivo.session.supersetRounds(at: $0) }.max() ?? 0 }

    /// Cuántas rondas RENDERIZAR (1-based): crecen conforme se completan — nunca se adelantan a una
    /// que el motor no ha alcanzado (el mock nunca dibuja una ronda 3 futura mientras la 2 sigue
    /// abierta). Fuente: el work-index del `currentSet` del miembro con el foco REAL
    /// (`session.currentIndex` — tras el round-robin, ya apunta a la ronda siguiente aun DURANTE el
    /// descanso de la anterior, que es justo lo que P5 dibuja). Si el foco está fuera del bloque (no
    /// alcanzado todavía, o ya avanzó a otro ejercicio), cae al máximo de rondas YA cerradas por
    /// cualquier miembro — 0 antes de empezar (se enseña la ronda 1 en blanco), `totalRondas` cuando
    /// el bloque queda completo.
    private var rondasARenderizar: Int {
        if members.contains(vivo.session.currentIndex) {
            let ei = vivo.session.currentIndex
            let run = vivo.session.runs[ei]
            if run.sets.indices.contains(run.currentSet) {
                let work = run.sets.filter { $0.kind == .work }
                if let workIdx = work.firstIndex(where: { $0.id == run.sets[run.currentSet].id }) {
                    return min(totalRondas, workIdx + 1)
                }
            }
        }
        let maxCerradas = runs.map { r in r.sets.filter { $0.kind == .work && $0.done }.count }.max() ?? 0
        return max(1, min(totalRondas, maxCerradas))
    }

    /// La ronda (1-based) que el descanso EN VUELO cierra — `nil` si este bloque no está
    /// descansando ahora. R3 (ronda 2 del gate FER-168, bloqueante): busca `restOwnerSetId` en
    /// CUALQUIER miembro del bloque, no asume `members.last` — el motor descansa tras quien de
    /// verdad cierra la ronda, que NO es siempre el último índice del grupo (un miembro posterior
    /// saltado, o uno anterior con más rondas de trabajo que el resto). Anclar por posición hacía
    /// desaparecer la banda entera en esos casos.
    private var rondaDelDescanso: Int? {
        guard vivo.session.phase == .resting, let ownerId = vivo.session.restOwnerSetId else { return nil }
        for ei in members where vivo.session.runs.indices.contains(ei) {
            let work = vivo.session.runs[ei].sets.filter { $0.kind == .work }
            if let workIdx = work.firstIndex(where: { $0.id == ownerId }) { return workIdx + 1 }
        }
        return nil
    }

    /// R3: la banda solo se pinta cuando la ronda `r` está visualmente CERRADA — todas sus filas
    /// (las que de verdad tienen slot en esa ronda, `miembros(enRonda:)`) ya `.hecha`. Antes se
    /// pintaba con solo `rondaDelDescanso == r`, sin exigirlo (Grok G4): un miembro con más rondas
    /// que el que acaba de cerrar podía quedar sin su fila visualmente marcada todavía.
    private func rondaCerrada(_ r: Int) -> Bool {
        let slots = miembros(enRonda: r)
        return !slots.isEmpty && slots.allSatisfy { $0.run.sets[$0.si].done }
    }

    var body: some View {
        HojaTarjetaSuperserie(
            nombre: nombre, pie: nil,
            onMenu: { vivo.menuExerciseIndex = primerMiembro },
            // D0 (FER-170 · F5): la puerta directa a Foco — `nil` cuando la sesión ya no puede
            // enfocarse (llena/zombie/acta), mismo gate que la tarjeta de un ejercicio suelto.
            onEnfocar: vivo.puedeEnfocar ? { vivo.enterFoco() } : nil
        ) {
            calentamientos
            // REGLA DURA: identidad por ronda (un `Int` semántico y estable — el bloque no gana
            // rondas en vivo, no es posición de un array reorderable), nunca por posición de fila.
            ForEach(rondaSlots) { slot in bloqueRonda(slot.numero) }
        }
        .liquidEntrada()
        // R1 (ronda 2 del gate FER-168, bloqueante): menú CONSCIENTE de superserie, no el de un
        // ejercicio suelto aplicado a `members[0]` — ver `menuItemsSuperserie`.
        .paperMenu(
            isPresented: Binding(get: { vivo.menuExerciseIndex == primerMiembro }, set: { if !$0 { vivo.menuExerciseIndex = nil } }),
            items: menuItemsSuperserie
        )
        .accessibilityElement(children: .contain)
    }

    // MARK: - «···» del BLOQUE (R1, ronda 2 del gate FER-168)
    //
    // Antes: `vivo.exerciseMenuItems(ei: primerMiembro)` — el menú de UN ejercicio, aplicado al
    // primer miembro. Rompía dos veces: «Deshacer superserie» llamaba `toggleSupersetWithNext`
    // (desempareja DOS vecinos — con 3+ miembros dejaba 2 sueltos + 1 huérfano, QA D1/D2/D3), y
    // «Mover arriba/abajo» hacía `swapAt` de un solo índice sin conciencia de grupo, fragmentando el
    // bloque. Ahora: acciones de BLOQUE arriba (Foco — ya es global al motor, no por-miembro; Deshacer
    // superserie — `breakSupersetBlock`, el grupo COMPLETO de una vez) + un submenú POR MIEMBRO,
    // rotulado con su nombre, para lo que sí es individual (Progresión / Cambiar ejercicio / Quitar
    // de la sesión) — paridad con el patrón que ya usa `HojaTarjetaSuperserieCompuesta` en edición.
    // «Mover» se RETIRA del menú vivo (decisión, spec R1): mover el bloque como unidad es F4/B8,
    // fuera de esta ronda; no hay «mover a medias» aquí.
    private var menuItemsSuperserie: [PaperMenuItem] {
        var rows: [PaperMenuItem] = []
        if vivo.puedeEnfocar {
            rows.append(.init(String(localized: "Focus"), systemImage: "arrow.up.left.and.arrow.down.right") {
                vivo.enterFoco()
            })
        }
        rows.append(.init(String(localized: "Undo superset"), systemImage: "link", isDestructive: true) {
            vivo.breakSupersetBlock(members: members)
        })
        for (ei, run) in zip(members, runs) {
            rows.append(.init(run.name, systemImage: nil,
                              children: vivo.exerciseMenuItems(ei: ei, run: run, incluirEstructura: false)))
        }
        return rows
    }

    // MARK: - Rondas

    private struct RondaSlot: Identifiable { let numero: Int; var id: Int { numero } }
    private var rondaSlots: [RondaSlot] { (1...max(1, rondasARenderizar)).map(RondaSlot.init) }

    @ViewBuilder
    private func bloqueRonda(_ r: Int) -> some View {
        HojaRondaDivisor(texto: rondaTexto(r))
        let slots = miembros(enRonda: r)
        ForEach(slots) { m in filaRonda(m, ronda: r, esPrimera: m.id == slots.first?.id) }
        // R3: además de ser la ronda dueña del descanso, exige que esté CERRADA (todas sus filas
        // hechas) — sin este guard se podía pintar antes de que la última fila terminara de marcar.
        if rondaDelDescanso == r, rondaCerrada(r) {
            // R6: la banda de RONDA dice «Descanso · ronda», no «Descanso · serie N → M» (ese
            // conteo es de UN ejercicio; no significa nada cerrando una ronda de varios miembros).
            vivo.restBand(esRonda: true).padding(.top, CenitMetrics.space2)
        }
    }

    private func rondaTexto(_ r: Int) -> String {
        String(format: String(localized: "Round %lld of %lld"), r, totalRondas)
    }

    private struct MiembroRondaSlot: Identifiable {
        let ei: Int
        let run: StrengthSessionModel.ExerciseRun
        let si: Int
        var id: String { run.id }
    }

    /// Los miembros que SÍ llegan a la ronda `r` — normalmente todos (rondas sincronizadas por el
    /// editor), pero una superserie legada con rondas ya desiguales (R8/`RoutineSheet`) no revienta
    /// aquí: el miembro corto simplemente no aporta fila en esa ronda.
    private func miembros(enRonda r: Int) -> [MiembroRondaSlot] {
        zip(members, runs).compactMap { ei, run in
            workSetIndex(run, round: r).map { si in MiembroRondaSlot(ei: ei, run: run, si: si) }
        }
    }

    /// El índice REAL en `run.sets` de la K-ésima serie de TRABAJO (1-based) — N3: los calentamientos
    /// no cuentan para la numeración de ronda.
    private func workSetIndex(_ run: StrengthSessionModel.ExerciseRun, round r: Int) -> Int? {
        var seen = 0
        for (si, set) in run.sets.enumerated() where set.kind == .work {
            seen += 1
            if seen == r { return si }
        }
        return nil
    }

    private func filaRonda(_ slot: MiembroRondaSlot, ronda: Int, esPrimera: Bool) -> some View {
        let set = slot.run.sets[slot.si]
        let esActiva = slot.ei == vivo.session.currentIndex && slot.si == slot.run.currentSet
        let marca: HojaFilaSerie.Marca = set.done ? .hecha : (esActiva ? .activa : .fantasma)
        let usesReps = slot.run.type == .weightReps || slot.run.type == .bodyweight
        let datos = HojaFilaSerie.Datos(
            numero: "\(ronda)", esCalentamiento: false,
            peso: usesReps ? vivo.plateNumber(vivo.displayWeight(set.weightKg)) : "—",
            unidad: slot.run.type == .weightReps ? vivo.weightUnit() : "",
            conSubida: false,
            reps: usesReps ? "\(set.reps)" : "—",
            // N4 (spec F3, «filas ssrow … reps(+Q)»): el sufijo Q solo en filas HECHAS, mismo
            // patrón que `HojaTarjetaEjercicioSesion.filaSerie`. Sin playhead ANT: el mock P5 no lo
            // dibuja para miembros de superserie (decisión documentada en el reporte).
            q: marca == .hecha ? set.rpe.map(LiveStrengthSheet.qLabel(fromRPE:)) : nil,
            ant: nil, esPrimera: esPrimera
        )
        return VStack(alignment: .leading, spacing: CenitMetrics.space1) {
            Text(slot.run.name)
                .font(StrandFont.caption).foregroundStyle(vivo.sheet.theme.inkTertiary).lineLimit(1)
                // A11y: «Zancadas, ronda 2 de 3» — el nombre por sí solo no basta para orientar en
                // una tabla intercalada; `.combine` (abajo) lo funde con el label de `HojaFilaSerie`
                // en UN elemento («fila = un elemento», spec F3), sin reabrir ese componente sellado.
                .accessibilityLabel(Text(verbatim: "\(slot.run.name), \(rondaTexto(ronda))"))
            HojaFilaSerie(datos: datos, contexto: .sesion, marca: marca) {
                vivo.confirmOrToggleSet(ei: slot.ei, si: slot.si)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Calentamiento (N3: fuera de ronda, antes del primer divisor)

    private struct CalentamientoSlot: Identifiable {
        let ei: Int
        let run: StrengthSessionModel.ExerciseRun
        let si: Int
        let set: StrengthSessionModel.WorkingSet
        // `self.` obligatorio: Swift lee un `{ set` a secas como el inicio de un accessor `set { }`
        // (el campo se llama literalmente `set`), no como la expresión `set.id`.
        var id: String { self.set.id }
    }

    /// R8/N3: el editor de superserie no ofrece «Add warm-up» a un miembro (`HojaTarjetaSuperserieCompuesta`
    /// ya lo excluye a propósito), pero una rampa heredada de antes de agrupar sigue viva en datos —
    /// esto la sigue mostrando en vez de tragársela en silencio.
    private var calentamientoSlots: [CalentamientoSlot] {
        zip(members, runs).flatMap { ei, run in
            run.sets.enumerated().compactMap { si, set in
                set.kind == .warmup ? CalentamientoSlot(ei: ei, run: run, si: si, set: set) : nil
            }
        }
    }

    @ViewBuilder private var calentamientos: some View {
        ForEach(Array(calentamientoSlots.enumerated()), id: \.element.id) { pos, slot in
            filaCalentamiento(slot, esPrimera: pos == 0)
        }
    }

    private func filaCalentamiento(_ slot: CalentamientoSlot, esPrimera: Bool) -> some View {
        let esActiva = slot.ei == vivo.session.currentIndex && slot.si == slot.run.currentSet
        let marca: HojaFilaSerie.Marca = slot.set.done ? .hecha : (esActiva ? .activa : .fantasma)
        let usesReps = slot.run.type == .weightReps || slot.run.type == .bodyweight
        let datos = HojaFilaSerie.Datos(
            numero: String(localized: "C"), esCalentamiento: true,
            peso: usesReps ? vivo.plateNumber(vivo.displayWeight(slot.set.weightKg)) : "—",
            unidad: slot.run.type == .weightReps ? vivo.weightUnit() : "",
            conSubida: false,
            reps: usesReps ? "\(slot.set.reps)" : "—",
            q: marca == .hecha ? slot.set.rpe.map(LiveStrengthSheet.qLabel(fromRPE:)) : nil,
            ant: nil, esPrimera: esPrimera
        )
        return VStack(alignment: .leading, spacing: CenitMetrics.space1) {
            Text(slot.run.name)
                .font(StrandFont.caption).foregroundStyle(vivo.sheet.theme.inkTertiary).lineLimit(1)
                // R4 (Grok G5): paridad con `filaRonda` — un label EXPLÍCITO en la cápita, no
                // implícito por el texto visible. Aquí no hay «ronda» que inyectar (el sufijo «C»
                // ya lo dice `HojaFilaSerie` como «Warm-up»), pero la fila queda igual de intencional.
                .accessibilityLabel(Text(verbatim: slot.run.name))
            HojaFilaSerie(datos: datos, contexto: .sesion, marca: marca) {
                vivo.confirmOrToggleSet(ei: slot.ei, si: slot.si)
            }
        }
        .accessibilityElement(children: .combine)
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
