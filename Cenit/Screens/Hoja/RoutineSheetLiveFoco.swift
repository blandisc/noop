#if os(iOS)
import SwiftUI
import StrandDesign
import StrandTraining

// MARK: - HojaFoco — el modo enfoque (FER-170 · F5, épico FER-165)
//
// El enfoque como EXPANSIÓN de la tarjeta activa de La Hoja viva (mock `hoja-mapa.html` sección D,
// `hoja-pantallas.html` P6): D0 la puerta vive en la tarjeta/cabecera/«···» (`RoutineSheetLiveTarjeta.swift`,
// `RoutineSheetLiveCabecera.swift`, `HojaSesionViva.enterFoco()` en `RoutineSheetLiveLogic.swift`) —
// las tres llaman al MISMO gesto, con continuidad geométrica vía `focoNS`/`namespaceId`
// (`matchedGeometryEffect`, compartido con el fondo invisible que `HojaSesionViva.focoDoor(_:)`
// cuelga detrás de la tarjeta activa). FER-187: también el tap del cromo (thumb+nombre) de la
// tarjeta activa, y el arrastre-hacia-abajo del grabber (`FocoCabecera.onArrastrarCerrar`) — el
// DragGesture NO vive sobre el ScrollView. Este archivo es D1 (captura) · D2 (descanso) · D3 (HECHO),
// compuestos con `FocoHeroe`/`FocoCabecera` (StrandDesign/Entrenar, F3) — NO se redibujan.
//
// REGLA DURA: cero identidad por índice. `focusDoneRunId`/`pendingFocusDoneRunId` (en
// `HojaSesionViva`) son `run.id`; ‹ › resuelve el vecino por identidad (`focoNeighbor`) y solo
// convierte a índice al momento de saltar, nunca antes.
//
// Retira el modo Foco vigente de `LiveStrengthSheet.swift` (ver ese archivo: la instancia efímera
// `startInFocus`/`onExitFocus` que F2 montaba se quitó entera). `LiveStrengthSheet.focusDoneTiming`
// (pura, tested en `LiveStrengthSheetRIRTests`) SOBREVIVE — la reusa `registerFromFoco` tal cual.

struct HojaFoco: View {
    let vivo: HojaSesionViva

    /// El id compartido de `matchedGeometryEffect` entre la tarjeta activa (`HojaSesionViva.focoDoor`)
    /// y este overlay — UNO solo para toda la Hoja: nunca hay más de una tarjeta «Now Playing» a la
    /// vez (`accordionIndex`), así que un id fijo no puede cruzarse con otro.
    static let namespaceId = "hoja-foco-tarjeta"

    /// D2 (ronda 2 del gate, bloqueante — criterio explícito del mapa): el toggle TIEMPO/FC. `false`
    /// (default) = lo que el motor eligió (FC si resolvió un objetivo honesto); `true` = el usuario
    /// forzó la vista de reloj. Vive AQUÍ (no en `HojaSesionViva`): es una preferencia de PANTALLA, no
    /// de sesión. `HojaFoco` no se remonta entre descansos (Foco se queda abierto D1↔D2↔D3), así que
    /// sin ayuda este `@State` arrastraría la elección de UN descanso al siguiente — el `.onChange(of:
    /// session.restStartedAt)` en `body` lo resetea a `false` cada vez que arranca un descanso nuevo,
    /// para que el default sea siempre lo que el motor decide, no lo último que tocaste hace 3 series.
    @State private var forzarVistaTiempo = false

    var body: some View {
        VStack(spacing: 0) {
            if let doneRunId = vivo.focusDoneRunId,
               let ei = vivo.session.runs.firstIndex(where: { $0.id == doneRunId }) {
                d3Hecho(ei: ei)
            } else if vivo.session.phase == .resting {
                d2Descanso
            } else {
                d1Captura
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            vivo.sheet.theme.paper
                .matchedGeometryEffect(id: Self.namespaceId, in: vivo.focoNS)
                .ignoresSafeArea()
        }
        .zIndex(2)
        .transition(.identity)   // el `matchedGeometryEffect` del fondo ya anima el marco.
        // D2: cada descanso NUEVO vuelve al default del motor — el toggle no arrastra la elección
        // manual de un descanso anterior en la misma sesión de Foco.
        .onChange(of: vivo.session.restStartedAt) { _, _ in forzarVistaTiempo = false }
    }

    private func salir() {
        withAnimation(vivo.reduceMotion ? nil : .snappy) { vivo.focusMode = false }
    }

    // MARK: - D1 · Captura

    @ViewBuilder private var d1Captura: some View {
        if let run = vivo.session.current {
            let ei = vivo.session.currentIndex
            FocoCabecera(titulo: focoTitulo(ei: ei), onCerrar: salir,
                        onArrastrarCerrar: salir,
                        etiquetaCerrar: String(localized: "Close focus mode"))
            ScrollView {
                VStack(spacing: 0) {
                    heroes(run: run, ei: ei)
                    if let ant = vivo.antPlayhead(run) {
                        Text(verbatim: ant)
                            .font(InstrumentoType.grotesk(FocoMetrics.antSize, weight: .bold, relativeTo: .caption2))
                            .tracking(FocoMetrics.antTracking)
                            .foregroundStyle(LiquidColor.tinta500)
                            .padding(.top, FocoMetrics.antTop)
                    }
                    capsulas(run: run, ei: ei)
                        .padding(.top, FocoMetrics.capsulasTop)
                    if let raise = run.proposedRaise, !raise.waiting {
                        Text(verbatim: String(localized: "raise earned: \(massText(raise.toKg)) ▲"))
                            .font(StrandFont.subhead).foregroundStyle(LiquidColor.verdeProfundo)
                            .padding(.top, FocoMetrics.raiseTop)
                    }
                    // R3 (ronda 2 del gate, bloqueante): UN solo camino de registro por tipo. Tiempo/
                    // distancia registran con su propio botón Start/Stop-and-save (`heroes`, abajo) —
                    // el «✓ Serie hecha» genérico (peso/reps) no aplica ahí y por poco tiempo mostraba
                    // los DOS a la vez (doble registro posible, Grok G5).
                    if run.type == .weightReps || run.type == .bodyweight {
                        ctaSerieHecha(ei: ei)
                            .padding(.top, FocoMetrics.ctaTop)
                    }
                    prevNextBar(ei: ei)
                        .padding(.top, FocoMetrics.prevNextTop)
                }
                .padding(.horizontal, CenitMetrics.screenPadding)
                .padding(.top, FocoMetrics.contentTop)
                .padding(.bottom, CenitMetrics.screenPadding)
            }
        } else {
            // Respaldo genérico (paridad `LiveStrengthSheet.focusCapturePhase`'s `else`): no debería
            // alcanzarse — `enterFoco()` solo lo ofrecen `puedeEnfocar`/las puertas gateadas por él,
            // que ya exigen `!session.isComplete` — pero una serie pendiente que el motor no resuelve
            // aquí no debe mostrar una pantalla en blanco.
            FocoCabecera(titulo: String(localized: "Focus"), onCerrar: salir,
                        onArrastrarCerrar: salir,
                        etiquetaCerrar: String(localized: "Close focus mode"))
            VStack(spacing: CenitMetrics.gap) {
                Spacer(minLength: 0)
                Text("All done").font(InstrumentoType.grotesk(24, weight: .semibold)).foregroundStyle(LiquidColor.tinta900)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// D1 · «{ejercicio} · serie N de M» (`Set %lld of %lld`, catálogo YA traducido «Serie %lld de
    /// %lld») — en superserie, «{ejercicio} · ronda N de M» (`Round %lld of %lld`, misma clave que
    /// `HojaTarjetaSuperserieSesion.rondaTexto`). Serie C (calentamiento): el número cede a
    /// «Calentamiento» — mismo criterio que `HojaFilaSerie.Datos.numero` («C»).
    private func focoTitulo(ei: Int) -> String {
        let run = vivo.session.runs[ei]
        if run.sets.indices.contains(run.currentSet), run.sets[run.currentSet].kind == .warmup {
            return "\(run.name) · " + String(localized: "Warm-up")
        }
        if vivo.session.isInSuperset(ei) {
            let members = vivo.session.supersetMembers(at: ei)
            let total = members.map { vivo.session.supersetRounds(at: $0) }.max() ?? 1
            let actual = min(total, vivo.session.closedSupersetRounds(members: members) + 1)
            return "\(run.name) · " + String(localized: "Round \(actual) of \(total)")
        }
        let work = run.sets.filter { $0.kind == .work }
        let n = run.sets.prefix(run.currentSet + 1).reduce(0) { $0 + ($1.kind == .work ? 1 : 0) }
        return "\(run.name) · " + String(localized: "Set \(max(1, n)) of \(work.count)")
    }

    /// Los héroes de D1, por tipo — `FocoHeroe` para kg/reps (weightReps, el molde del mock P6) y
    /// reps sola (bodyweight); tiempo/distancia reusan el MISMO componente para el numeral editable,
    /// con el cronómetro corriendo debajo (paridad `LiveStrengthSheet.focusTimeControls`/
    /// `focusDistanceControls`, sin redibujar esa lógica).
    @ViewBuilder private func heroes(run: StrengthSessionModel.ExerciseRun, ei: Int) -> some View {
        switch run.type {
        case .weightReps:
            VStack(spacing: 0) {
                FocoHeroe(
                    valor: vivo.plateNumber(vivo.displayWeight(vivo.session.currentSet?.weightKg ?? 0)),
                    unidad: " " + vivo.weightUnit(),
                    onMenos: { vivo.session.bumpWeight(byKg: -vivo.weightStepKg) },
                    onMas: { vivo.session.bumpWeight(byKg: vivo.weightStepKg) },
                    etiquetaAccesible: "\(String(localized: "Weight")), \(vivo.plateNumber(vivo.displayWeight(vivo.session.currentSet?.weightKg ?? 0))) \(vivo.weightUnit())",
                    etiquetaMenos: String(localized: "Decrease weight"),
                    etiquetaMas: String(localized: "Increase weight")
                )
                // «cero pérdida»: el atajo a discos — solo en barra (r15 heredado). `FocoHeroe` no
                // trae ranura de leyenda; va debajo, sin tocar el componente sellado.
                if vivo.usesBarbell(ei) {
                    Button {
                        vivo.platesTarget = LiveStrengthSheet.PlatesTarget(ei: ei, weightKg: vivo.session.currentSet?.weightKg ?? 0)
                    } label: {
                        Text(verbatim: "±\(StrengthDisplay.incrementNumber(vivo.weightStepKg, system: vivo.sheet.system)) · " + String(localized: "plates"))
                            .font(StrandFont.caption).foregroundStyle(LiquidColor.tinta500).underline()
                    }
                    .buttonStyle(.plain)
                    .padding(.top, FocoMetrics.capcionTop)
                }
            }
            VStack(spacing: 0) {
                FocoHeroe(
                    valor: "\(vivo.session.currentSet?.reps ?? 0)",
                    unidad: " " + String(localized: "Reps").lowercased(),
                    onMenos: { vivo.session.bumpReps(-1) },
                    onMas: { vivo.session.bumpReps(1) },
                    etiquetaAccesible: "\(String(localized: "Reps")), \(vivo.session.currentSet?.reps ?? 0)",
                    etiquetaMenos: String(localized: "Decrease reps"),
                    etiquetaMas: String(localized: "Increase reps")
                )
                if let lr = run.lastReps {
                    Text(String(localized: "target \(lr)"))
                        .font(StrandFont.caption).foregroundStyle(LiquidColor.tinta500)
                        .padding(.top, FocoMetrics.capcionTop)
                }
            }
            .padding(.top, FocoMetrics.heroGap)
        case .bodyweight:
            FocoHeroe(
                valor: "\(vivo.session.currentSet?.reps ?? 0)",
                unidad: " " + String(localized: "Reps").lowercased(),
                onMenos: { vivo.session.bumpReps(-1) },
                onMas: { vivo.session.bumpReps(1) },
                etiquetaAccesible: "\(String(localized: "Reps")), \(vivo.session.currentSet?.reps ?? 0)",
                etiquetaMenos: String(localized: "Decrease reps"),
                etiquetaMas: String(localized: "Increase reps")
            )
            let kg = vivo.session.currentSet?.weightKg ?? 0
            FocoHeroe(
                valor: (kg > 0 ? "+" : "") + vivo.plateNumber(vivo.displayWeight(kg)),
                unidad: " " + vivo.weightUnit(),
                onMenos: { vivo.session.bumpWeight(byKg: -vivo.weightStepKg) },
                onMas: { vivo.session.bumpWeight(byKg: vivo.weightStepKg) },
                etiquetaAccesible: "\(String(localized: "Weight")), \(vivo.plateNumber(vivo.displayWeight(kg))) \(vivo.weightUnit())",
                etiquetaMenos: String(localized: "Decrease added weight"),
                etiquetaMas: String(localized: "Increase added weight")
            )
            .padding(.top, FocoMetrics.heroGap)
        case .time:
            let running = vivo.session.timerStart != nil
            FocoHeroe(
                valor: Self.clock(vivo.session.currentSet?.timeS ?? 0),
                unidad: "",
                onMenos: {}, onMas: {}, menosHabilitado: false, masHabilitado: false,
                etiquetaAccesible: String(localized: "Timing, \(vivo.session.currentSet?.timeS ?? 0) seconds")
            )
            if running {
                TimelineView(.periodic(from: Date(), by: 1)) { ctx in
                    Text(Self.clock(vivo.session.timerElapsed(now: ctx.date)))
                        .font(InstrumentoType.groteskNumber(FocoMetrics.runningClockSize, weight: .bold))
                        .foregroundStyle(LiquidColor.tinta900).monospacedDigit()
                        .padding(.top, FocoMetrics.capcionTop)
                }
            }
            if let bpm = vivo.sheet.model.watchBpm { zonaBadge(bpm).padding(.top, FocoMetrics.capcionTop) }
            Button {
                withAnimation(vivo.reduceMotion ? nil : StrandMotion.gentle) {
                    if running { vivo.registerFromFoco() } else { vivo.session.startSetTimer() }
                }
            } label: {
                Text(running ? String(localized: "Stop and save") : String(localized: "Start"))
                    .font(StrandFont.subhead.weight(.semibold)).foregroundStyle(LiquidColor.tinta900)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .overlay(Capsule().strokeBorder(LiquidColor.tinta10, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(.top, FocoMetrics.capcionTop)
        case .distance:
            let dist = vivo.session.currentSet?.distanceM ?? 0
            let running = vivo.session.timerStart != nil
            FocoHeroe(
                valor: vivo.distanceNumber(dist), unidad: " " + (vivo.imperial ? "mi" : "km"),
                onMenos: { vivo.session.bumpDistance(byMeters: -vivo.distanceStepM) },
                onMas: { vivo.session.bumpDistance(byMeters: vivo.distanceStepM) },
                etiquetaAccesible: "\(String(localized: "Distance")), \(vivo.distanceNumber(dist))",
                etiquetaMenos: String(localized: "Decrease distance"),
                etiquetaMas: String(localized: "Increase distance")
            )
            Group {
                if running {
                    TimelineView(.periodic(from: Date(), by: 1)) { ctx in
                        Text(Self.clock(vivo.session.timerElapsed(now: ctx.date)))
                    }
                } else {
                    Text(Self.clock(vivo.session.currentSet?.timeS ?? 0))
                }
            }
            .font(InstrumentoType.groteskNumber(FocoMetrics.runningClockSize, weight: .bold))
            .foregroundStyle(LiquidColor.tinta900).monospacedDigit()
            .padding(.top, FocoMetrics.capcionTop)
            if let bpm = vivo.sheet.model.watchBpm { zonaBadge(bpm).padding(.top, FocoMetrics.capcionTop) }
            // R3 (ronda 2 del gate, bloqueante): el MISMO patrón que `.time` arriba — Start/Stop-and-
            // save es el ÚNICO camino de registro (antes, «Stop» solo detenía el cronómetro y el «✓
            // Serie hecha» genérico de abajo registraba aparte — dos caminos para un mismo dato,
            // Grok G5). `registerCurrentSet` ya detiene el cronómetro internamente al registrar
            // (`if timerStart != nil { stopSetTimer(...) }`), así que `registerFromFoco()` sola
            // captura lo corrido y cierra la serie, sin un `stopSetTimer()` aparte.
            Button {
                withAnimation(vivo.reduceMotion ? nil : StrandMotion.gentle) {
                    if running { vivo.registerFromFoco() } else { vivo.session.startSetTimer() }
                }
            } label: {
                Text(running ? String(localized: "Stop and save") : String(localized: "Start"))
                    .font(StrandFont.subhead.weight(.semibold)).foregroundStyle(LiquidColor.tinta900)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .overlay(Capsule().strokeBorder(LiquidColor.tinta10, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(.top, FocoMetrics.capcionTop)
        }
    }

    /// Las puertas RPE / ✎ NOTA (D1, decisión Multica 2026-08-26: «RPE», nunca «Q» — la equivalencia
    /// Q↔RPE vive en la hoja 6-10 que esta puerta abre). SIN puerta de descanso manual — la banda
    /// cae sola al palomear (D2).
    private func capsulas(run: StrengthSessionModel.ExerciseRun, ei: Int) -> some View {
        HStack(spacing: 8) {
            EntrenarCapsulaPuerta(String(localized: "RPE"), mostrarFlecha: false) {
                vivo.openRPE(ei: ei, si: run.currentSet)
            }
            EntrenarCapsulaPuerta("✎ " + String(localized: "Note").uppercased(), mostrarFlecha: false) {
                vivo.openNote(ei: ei)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func ctaSerieHecha(ei: Int) -> some View {
        LiquidGlassButton("✓ " + String(localized: "Set done"), variant: .primary, expands: true) {
            withAnimation(vivo.reduceMotion ? nil : StrandMotion.gentle) { vivo.registerFromFoco() }
        }
        .accessibilityLabel(Text(String(localized: "Set done")))
    }

    /// ‹ anterior — siguiente › (D1, extremos): el vecino no-saltado más cercano, por IDENTIDAD
    /// (regla dura) — el índice solo se resuelve al saltar (`focoJump`), nunca se guarda.
    @ViewBuilder private func prevNextBar(ei: Int) -> some View {
        let prev = focoNeighbor(from: ei, delta: -1)
        let next = focoNeighbor(from: ei, delta: 1)
        if prev != nil || next != nil {
            HStack {
                if let prev {
                    Button { focoJump(to: prev.id) } label: {
                        Text(verbatim: "‹ \(prev.name)").font(StrandFont.subhead).foregroundStyle(LiquidColor.tinta500).lineLimit(1)
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 12)
                if let next {
                    Button { focoJump(to: next.id) } label: {
                        Text(verbatim: "\(next.name) ›").font(StrandFont.subhead.weight(.semibold)).foregroundStyle(LiquidColor.tinta900).lineLimit(1)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func focoNeighbor(from ei: Int, delta: Int) -> StrengthSessionModel.ExerciseRun? {
        var i = ei + delta
        while vivo.session.runs.indices.contains(i) {
            if !vivo.session.runs[i].skipped { return vivo.session.runs[i] }
            i += delta
        }
        return nil
    }

    private func focoJump(to runId: String) {
        guard let idx = vivo.session.runs.firstIndex(where: { $0.id == runId }) else { return }
        withAnimation(vivo.reduceMotion ? nil : StrandMotion.gentle) {
            vivo.session.select(exerciseIndex: idx, setIndex: vivo.session.runs[idx].sets.firstIndex { !$0.done } ?? 0)
        }
    }

    // MARK: - D2 · Descanso

    /// La banda cae sola — reusa `RestBand` de F2 tal cual (`vivo.restBand`, `large: true`), la MISMA
    /// lógica de descanso (FC vs reloj, CASI, tope honesto, SALTAR) que la lista en línea. R2 (ronda
    /// 2 del gate, bloqueante — criterio explícito del mapa): el toggle TIEMPO/FC — SOLO cuando el
    /// motor resolvió un objetivo de FC honesto (`puedeElegirCombustibleDescanso`; sin Watch/objetivo
    /// no hay «vista FC» que enseñar sin inventar uno). `forzarVistaTiempo` fuerza el reloj de
    /// respaldo que `RestBand`/`restBand(forzarTiempo:)` YA exponían para el caso sin señal — sin
    /// caso nuevo en `RestBand` (F2), sin tocar su API pública.
    private var d2Descanso: some View {
        let esRonda = vivo.restOwnerExerciseIndex.map { vivo.session.isInSuperset($0) } ?? false
        return VStack(spacing: 0) {
            FocoCabecera(titulo: String(localized: "Rest"), onCerrar: salir,
                        onArrastrarCerrar: salir,
                        etiquetaCerrar: String(localized: "Close focus mode"))
            ScrollView {
                VStack(spacing: 0) {
                    if vivo.puedeElegirCombustibleDescanso {
                        combustibleToggle.padding(.bottom, FocoMetrics.capsulasTop)
                    }
                    vivo.restBand(esRonda: esRonda, large: true, forzarTiempo: forzarVistaTiempo)
                }
                .padding(.horizontal, CenitMetrics.screenPadding)
                .padding(.top, FocoMetrics.contentTop)
            }
        }
    }

    /// El toggle TIEMPO/FC — mismo lenguaje de pastilla de dos segmentos que `CompactTrendToggle`
    /// (StrandDesign), sin generalizar ese componente (está acoplado a `TrendMode`, un concepto
    /// ajeno): misma receta (padding 3, cápsula, segmento activo en tinta), en `InstrumentoTheme`
    /// (el ambiente de esta pantalla, igual que `RestBand`).
    private var combustibleToggle: some View {
        HStack(spacing: 3) {
            combustibleSegmento(String(localized: "Time"), activo: forzarVistaTiempo) { forzarVistaTiempo = true }
            combustibleSegmento(String(localized: "HR"), activo: !forzarVistaTiempo) { forzarVistaTiempo = false }
        }
        .padding(3)
        .background(vivo.sheet.theme.surface, in: Capsule())
    }

    private func combustibleSegmento(_ label: String, activo: Bool, action: @escaping () -> Void) -> some View {
        Text(verbatim: label)
            .font(InstrumentoType.grotesk(10, weight: .semibold)).tracking(0.6).textCase(.uppercase)
            .foregroundStyle(activo ? vivo.sheet.theme.paper : vivo.sheet.theme.inkTertiary)
            .padding(.horizontal, 11).padding(.vertical, 5).frame(minHeight: 34)
            .background { if activo { Capsule().fill(vivo.sheet.theme.ink) } }
            .contentShape(Capsule())
            .onTapGesture { withAnimation(vivo.reduceMotion ? nil : StrandMotion.interactive) { action() } }
            .accessibilityAddTraits(activo ? [.isSelected, .isButton] : .isButton)
    }

    // MARK: - D3 · HECHO

    /// Cierra el ejercicio (o la ronda, en superserie) SOLO tras el descanso real — `registerFromFoco`
    /// decide el timing (paridad `LiveStrengthSheet.focusDoneTiming`, reusada tal cual). El botón
    /// avanza a lo que `session.current` YA apunta (el motor adelantó el foco al registrar) o
    /// termina la sesión si no queda nada — sin lógica de superserie especial aquí: el round-robin
    /// del motor es transparente a este botón.
    private func d3Hecho(ei: Int) -> some View {
        let run = vivo.session.runs[ei]
        let inSuperset = vivo.session.isInSuperset(ei)
        let members = inSuperset ? vivo.session.supersetMembers(at: ei) : [ei]
        let nombre = inSuperset ? members.map { vivo.session.runs[$0].name }.joined(separator: " ＋ ") : run.name
        let (doneN, totalN): (Int, Int) = {
            if inSuperset {
                let total = members.map { vivo.session.supersetRounds(at: $0) }.max() ?? 0
                return (vivo.session.closedSupersetRounds(members: members), total)
            }
            let work = run.sets.filter { $0.kind == .work }
            return (work.filter(\.done).count, work.count)
        }()
        let isLast = vivo.session.isComplete
        let nextRun = isLast ? nil : vivo.session.current
        return VStack(spacing: 0) {
            FocoCabecera(titulo: String(localized: "Done heading"), onCerrar: salir,
                        onArrastrarCerrar: salir,
                        etiquetaCerrar: String(localized: "Close focus mode"))
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                Circle().fill(LiquidColor.verdePrimario)
                    .frame(width: 44, height: 44)
                    .overlay { Image(systemName: "checkmark").font(StrandFont.glyph(.lead, weight: .bold)).foregroundStyle(LiquidColor.tintaSobreVerde) }
                    .accessibilityHidden(true)
                // «Hecho · {nombre}» — NO «{nombre}, hecha» (el mapa lo dibuja así, pero esa
                // concordancia rompe con nombres femeninos/masculinos mixtos del catálogo — decisión
                // ya tomada en FER-150, portada tal cual; ver reporte).
                (Text("Done heading") + Text(verbatim: " · \(nombre)"))
                    .font(InstrumentoType.grotesk(FocoMetrics.doneTitleSize, weight: .bold))
                    .foregroundStyle(LiquidColor.tinta900).multilineTextAlignment(.center)
                    .padding(.top, FocoMetrics.doneTitleTop)
                Group {
                    if let next = nextRun {
                        Text(verbatim: String(localized: "\(doneN) of \(totalN) · next: \(next.name)"))
                    } else {
                        Text(verbatim: String(localized: "\(doneN) of \(totalN) · complete"))
                    }
                }
                .font(StrandFont.subhead).foregroundStyle(LiquidColor.tinta500).multilineTextAlignment(.center)
                .padding(.top, FocoMetrics.capcionTop)
                if let raise = run.proposedRaise, !raise.waiting {
                    Text(verbatim: String(localized: "the raise to \(massText(raise.toKg)) is on record"))
                        .font(StrandFont.caption).foregroundStyle(LiquidColor.verdeProfundo)
                        .padding(.top, FocoMetrics.capcionTop)
                }
                Button {
                    withAnimation(vivo.reduceMotion ? nil : StrandMotion.gentle) { vivo.focusDoneRunId = nil }
                    if isLast {
                        withAnimation(vivo.reduceMotion ? nil : .snappy) { vivo.focusMode = false }
                        vivo.requestFinish()
                    }
                } label: {
                    Group {
                        if let next = nextRun {
                            Text("Next") + Text(verbatim: ": \(next.name) ›")
                        } else {
                            Text("Finish workout") + Text(verbatim: " ›")
                        }
                    }
                    .font(InstrumentoType.groteskHeadline(15)).foregroundStyle(LiquidColor.tintaSobreVerde)
                    .padding(.horizontal, CenitMetrics.sectionGap)
                    .frame(height: EntrenarMetrics.primaryButton)
                    .background(LiquidColor.verdePrimario, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, CenitMetrics.sectionGap)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, CenitMetrics.screenPadding)
        }
    }

    /// «ZONA 2 · 118» (variante tiempo/distancia del mock: «FocoHeroe con unidad de tiempo/distancia
    /// + zona FC») — la MISMA regla de 5 zonas que `HojaTarjetaEjercicioSesion.zonaBadge` (% de tu
    /// FC máx), aquí porque D1 no monta esa tarjeta. Solo aparece con Watch — sin pulso no se inventa
    /// una zona.
    private func zonaBadge(_ bpm: Int) -> some View {
        let maxHR = Double(vivo.sheet.model.profile.hrMax)
        let pct = maxHR > 0 ? Double(bpm) / maxHR : 0
        let zone = max(1, min(5, Int((pct * 5).rounded(.up))))
        return Text("ZONE \(zone) · \(bpm)")
            .font(StrandFont.caption.weight(.bold)).foregroundStyle(LiquidColor.tinta500)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .overlay(Capsule().strokeBorder(LiquidColor.tinta10, lineWidth: 1))
    }

    // MARK: - Formato

    private func massText(_ kg: Double) -> String { "\(vivo.plateNumber(vivo.displayWeight(kg))) \(vivo.weightUnit())" }

    private static func clock(_ seconds: Int) -> String { SessionClock.format(seconds) }
}

/// Constantes locales de `HojaFoco` (mock `hoja-pantallas.html` P6 / `hoja-mapa.html` D1-D3). No
/// viven en `EntrenarTokens`: son geometría propia de ESTA composición, no un molde reusado en otra
/// pantalla — mismo criterio que `FocoHeroeMetrics`/`FocoCabeceraMetrics` en StrandDesign.
private enum FocoMetrics {
    static var contentTop: CGFloat { 26 }
    static var heroGap: CGFloat { 16 }
    static var capcionTop: CGFloat { 6 }
    static var antSize: CGFloat { 9 }
    static var antTracking: CGFloat { 0.4 }
    static var antTop: CGFloat { 14 }
    static var capsulasTop: CGFloat { 18 }
    static var raiseTop: CGFloat { 12 }
    static var ctaTop: CGFloat { 22 }
    static var prevNextTop: CGFloat { 18 }
    static var runningClockSize: CGFloat { 22 }
    static var doneTitleSize: CGFloat { 22 }
    static var doneTitleTop: CGFloat { 12 }
}
#endif
