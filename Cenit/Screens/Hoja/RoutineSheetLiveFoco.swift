#if os(iOS)
import SwiftUI
import CenitDesign
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
// compuestos con `FocoHeroe`/`FocoCabecera` (CenitDesign/Entrenar, F3) — NO se redibujan.
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
        VStack(spacing: .zero) {
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
            LiquidColor.fondoGradient
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
                VStack(spacing: .zero) {
                    heroes(run: run, ei: ei)
                    if let ant = vivo.antPlayhead(run) {
                        Text(verbatim: ant)
                            .font(LiquidType.captionLecturaNegrita)
                            .tracking(FocoMetrics.antTracking)
                            .foregroundStyle(LiquidColor.tinta500)
                            .padding(.top, FocoMetrics.antTop)
                    }
                    capsulas(run: run, ei: ei)
                        .padding(.top, FocoMetrics.capsulasTop)
                    if let raise = run.proposedRaise, !raise.waiting {
                        Text(verbatim: String(localized: "raise earned: \(massText(raise.toKg)) ▲"))
                            .font(LiquidType.cuerpoBanner).foregroundStyle(LiquidColor.verdeProfundo)
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
                .padding(.horizontal, LiquidSpace.s600)
                .padding(.top, FocoMetrics.contentTop)
                .padding(.bottom, LiquidSpace.s600)
            }
        } else {
            // Respaldo genérico (paridad `LiveStrengthSheet.focusCapturePhase`'s `else`): no debería
            // alcanzarse — `enterFoco()` solo lo ofrecen `puedeEnfocar`/las puertas gateadas por él,
            // que ya exigen `!session.isComplete` — pero una serie pendiente que el motor no resuelve
            // aquí no debe mostrar una pantalla en blanco.
            FocoCabecera(titulo: String(localized: "Focus"), onCerrar: salir,
                        onArrastrarCerrar: salir,
                        etiquetaCerrar: String(localized: "Close focus mode"))
            VStack(spacing: LiquidSpace.s300) {
                Spacer(minLength: 0)
                Text("All done").font(LiquidType.displayS).foregroundStyle(LiquidColor.tinta900)
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
            VStack(spacing: .zero) {
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
                            .font(LiquidType.caption).foregroundStyle(LiquidColor.tinta500).underline()
                    }
                    .buttonStyle(.plain)
                    .padding(.top, FocoMetrics.capcionTop)
                }
            }
            VStack(spacing: .zero) {
                FocoHeroe(
                    valor: vivo.session.currentSet?.reps.map { "\($0)" } ?? "",
                    unidad: " " + String(localized: "Reps").lowercased(),
                    onMenos: { vivo.session.bumpReps(-1) },
                    onMas: { vivo.session.bumpReps(1) },
                    etiquetaAccesible: "\(String(localized: "Reps")), \(vivo.session.currentSet?.reps.map { "\($0)" } ?? String(localized: "pending"))",
                    etiquetaMenos: String(localized: "Decrease reps"),
                    etiquetaMas: String(localized: "Increase reps")
                )
                if let lr = run.lastReps {
                    Text(String(localized: "target \(lr)"))
                        .font(LiquidType.caption).foregroundStyle(LiquidColor.tinta500)
                        .padding(.top, FocoMetrics.capcionTop)
                }
            }
            .padding(.top, FocoMetrics.heroGap)
        case .bodyweight:
            FocoHeroe(
                valor: vivo.session.currentSet?.reps.map { "\($0)" } ?? "",
                unidad: " " + String(localized: "Reps").lowercased(),
                onMenos: { vivo.session.bumpReps(-1) },
                onMas: { vivo.session.bumpReps(1) },
                etiquetaAccesible: "\(String(localized: "Reps")), \(vivo.session.currentSet?.reps.map { "\($0)" } ?? String(localized: "pending"))",
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
                    let texto = Self.clock(vivo.session.timerElapsed(now: ctx.date))
                    Text(texto)
                        .font(LiquidType.displayS).monospacedDigit()
                        .tracking(LiquidType.displaySTracking)
                        .foregroundStyle(LiquidColor.tinta900)
                        .numeroVivo(value: texto)
                        .padding(.top, FocoMetrics.capcionTop)
                }
            }
            if let bpm = vivo.sheet.model.watchBpm { zonaBadge(bpm).padding(.top, FocoMetrics.capcionTop) }
            OutlineCapsule(size: .lg, estilo: .outline, action: {
                withAnimation(vivo.reduceMotion ? nil : LiquidMotion.suave) {
                    if running { vivo.registerFromFoco() } else { vivo.session.startSetTimer() }
                }
            }) {
                Text(running ? String(localized: "Stop and save") : String(localized: "Start"))
                    .font(LiquidType.cuerpoBanner.weight(.semibold)).foregroundStyle(LiquidColor.tinta900)
            }
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
                        let texto = Self.clock(vivo.session.timerElapsed(now: ctx.date))
                        Text(texto).numeroVivo(value: texto)
                    }
                } else {
                    let texto = Self.clock(vivo.session.currentSet?.timeS ?? 0)
                    Text(texto).numeroVivo(value: texto)
                }
            }
            .font(LiquidType.displayS).monospacedDigit()
            .tracking(LiquidType.displaySTracking)
            .foregroundStyle(LiquidColor.tinta900)
            .padding(.top, FocoMetrics.capcionTop)
            if let bpm = vivo.sheet.model.watchBpm { zonaBadge(bpm).padding(.top, FocoMetrics.capcionTop) }
            // R3 (ronda 2 del gate, bloqueante): el MISMO patrón que `.time` arriba — Start/Stop-and-
            // save es el ÚNICO camino de registro (antes, «Stop» solo detenía el cronómetro y el «✓
            // Serie hecha» genérico de abajo registraba aparte — dos caminos para un mismo dato,
            // Grok G5). `registerCurrentSet` ya detiene el cronómetro internamente al registrar
            // (`if timerStart != nil { stopSetTimer(...) }`), así que `registerFromFoco()` sola
            // captura lo corrido y cierra la serie, sin un `stopSetTimer()` aparte.
            OutlineCapsule(size: .lg, estilo: .outline, action: {
                withAnimation(vivo.reduceMotion ? nil : LiquidMotion.suave) {
                    if running { vivo.registerFromFoco() } else { vivo.session.startSetTimer() }
                }
            }) {
                Text(running ? String(localized: "Stop and save") : String(localized: "Start"))
                    .font(LiquidType.cuerpoBanner.weight(.semibold)).foregroundStyle(LiquidColor.tinta900)
            }
            .padding(.top, FocoMetrics.capcionTop)
        }
    }

    /// Las puertas RPE / ✎ NOTA (D1, decisión Multica 2026-08-26: «RPE», nunca «Q» — la equivalencia
    /// Q↔RPE vive en la hoja 6-10 que esta puerta abre). SIN puerta de descanso manual — la banda
    /// cae sola al palomear (D2).
    private func capsulas(run: StrengthSessionModel.ExerciseRun, ei: Int) -> some View {
        HStack(spacing: LiquidSpace.s200) {
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
        // FER-223: SIN háptico propio aquí — `vivo.registerFromFoco()` llega a `registerActiveSet`,
        // el único funnel que da `EntrenarHaptic.serieCompletada` (poner otro aquí duplicaba el golpe).
        LiquidGlassButton(String(localized: "Set done"), variant: .primary, expands: true) {
            withAnimation(vivo.reduceMotion ? nil : LiquidMotion.suave) { vivo.registerFromFoco() }
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
                        Text(verbatim: "‹ \(prev.name)").font(LiquidType.cuerpoBanner).foregroundStyle(LiquidColor.tinta500).lineLimit(1)
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: LiquidSpace.s300)
                if let next {
                    Button { focoJump(to: next.id) } label: {
                        Text(verbatim: "\(next.name) ›").font(LiquidType.cuerpoBanner.weight(.semibold)).foregroundStyle(LiquidColor.tinta900).lineLimit(1)
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
        withAnimation(vivo.reduceMotion ? nil : LiquidMotion.suave) {
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
        return VStack(spacing: .zero) {
            FocoCabecera(titulo: String(localized: "Rest"), onCerrar: salir,
                        onArrastrarCerrar: salir,
                        etiquetaCerrar: String(localized: "Close focus mode"))
            ScrollView {
                VStack(spacing: .zero) {
                    if vivo.puedeElegirCombustibleDescanso {
                        combustibleToggle.padding(.bottom, FocoMetrics.capsulasTop)
                    }
                    vivo.restBand(esRonda: esRonda, large: true, forzarTiempo: forzarVistaTiempo)
                }
                .padding(.horizontal, LiquidSpace.s600)
                .padding(.top, FocoMetrics.contentTop)
            }
        }
    }

    /// El toggle TIEMPO/FC — mismo lenguaje de pastilla de dos segmentos que `CompactTrendToggle`
    /// (CenitDesign), sin generalizar ese componente (está acoplado a `TrendMode`, un concepto
    /// ajeno): misma receta (padding 3, cápsula, segmento activo en tinta), igual que `RestBand`.
    private var combustibleToggle: some View {
        HStack(spacing: LiquidSpace.s075) {
            combustibleSegmento(String(localized: "Time"), activo: forzarVistaTiempo) { forzarVistaTiempo = true }
            combustibleSegmento(String(localized: "HR"), activo: !forzarVistaTiempo) { forzarVistaTiempo = false }
        }
        .padding(LiquidSpace.s075)
        .liquidGlass(.pastillaSolida)
    }

    private func combustibleSegmento(_ label: String, activo: Bool, action: @escaping () -> Void) -> some View {
        Text(verbatim: label)
            .font(LiquidType.captionFuerte).tracking(0.6).textCase(.uppercase)
            .foregroundStyle(activo ? LiquidColor.papelTarjeta : LiquidColor.tinta500)
            .padding(.horizontal, LiquidSpace.s300).padding(.vertical, LiquidSpace.s125)
            .frame(minHeight: EntrenarMetrics.secondaryButton)
            // Segmento activo: fill tinta vía ShapeStyle-in-Shape (misma API que OutlineCapsule).
            .background(activo ? LiquidColor.tinta900 : Color.clear, in: Capsule())
            .contentShape(Capsule())
            .onTapGesture { withAnimation(vivo.reduceMotion ? nil : LiquidMotion.toque) { action() } }
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
        return VStack(spacing: .zero) {
            FocoCabecera(titulo: String(localized: "Done heading"), onCerrar: salir,
                        onArrastrarCerrar: salir,
                        etiquetaCerrar: String(localized: "Close focus mode"))
            VStack(spacing: .zero) {
                Spacer(minLength: 0)
                Circle().fill(LiquidColor.verdePrimario)
                    .frame(width: LiquidControl.hitTarget, height: LiquidControl.hitTarget)
                    .overlay { Image(systemName: "checkmark").font(LiquidType.iconSF(size: 18).weight(.bold)).foregroundStyle(LiquidColor.tintaSobreVerde) }
                    .accessibilityHidden(true)
                // «Hecho · {nombre}» — NO «{nombre}, hecha» (el mapa lo dibuja así, pero esa
                // concordancia rompe con nombres femeninos/masculinos mixtos del catálogo — decisión
                // ya tomada en FER-150, portada tal cual; ver reporte).
                (Text("Done heading") + Text(verbatim: " · \(nombre)"))
                    .font(LiquidType.displayS)
                    .tracking(LiquidType.displaySTracking)
                    .foregroundStyle(LiquidColor.tinta900).multilineTextAlignment(.center)
                    .padding(.top, FocoMetrics.doneTitleTop)
                Group {
                    if let next = nextRun {
                        Text(verbatim: String(localized: "\(doneN) of \(totalN) · next: \(next.name)"))
                    } else {
                        Text(verbatim: String(localized: "\(doneN) of \(totalN) · complete"))
                    }
                }
                .font(LiquidType.cuerpoBanner).foregroundStyle(LiquidColor.tinta500).multilineTextAlignment(.center)
                .padding(.top, FocoMetrics.capcionTop)
                if let raise = run.proposedRaise, !raise.waiting {
                    Text(verbatim: String(localized: "the raise to \(massText(raise.toKg)) is on record"))
                        .font(LiquidType.caption).foregroundStyle(LiquidColor.verdeProfundo)
                        .padding(.top, FocoMetrics.capcionTop)
                }
                OutlineCapsule(
                    size: .aMedida(
                        insets: EdgeInsets(top: .zero, leading: LiquidSpace.s700,
                                           bottom: .zero, trailing: LiquidSpace.s700),
                        minHeight: EntrenarMetrics.primaryButton,
                        touchInset: .zero),
                    filled: true,
                    fill: LiquidColor.verdePrimario,
                    action: {
                        withAnimation(vivo.reduceMotion ? nil : LiquidMotion.suave) { vivo.focusDoneRunId = nil }
                        if isLast {
                            withAnimation(vivo.reduceMotion ? nil : .snappy) { vivo.focusMode = false }
                            vivo.requestFinish()
                        }
                    }
                ) {
                    Group {
                        if let next = nextRun {
                            Text("Next") + Text(verbatim: ": \(next.name) ›")
                        } else {
                            Text("Finish") + Text(verbatim: " ›")
                        }
                    }
                    .font(LiquidType.tituloGemela)
                    .foregroundStyle(LiquidColor.tintaSobreVerde)
                }
                .padding(.top, LiquidSpace.s700)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, LiquidSpace.s600)
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
            .font(LiquidType.captionNegrita).foregroundStyle(LiquidColor.tinta500)
            .outlineCapsule(.outline, size: .sm)
    }

    // MARK: - Formato

    private func massText(_ kg: Double) -> String { "\(vivo.plateNumber(vivo.displayWeight(kg))) \(vivo.weightUnit())" }

    private static func clock(_ seconds: Int) -> String { SessionClock.format(seconds) }
}

/// Constantes locales de `HojaFoco` (mock `hoja-pantallas.html` P6 / `hoja-mapa.html` D1-D3). No
/// viven en `EntrenarTokens`: son geometría propia de ESTA composición, no un molde reusado en otra
/// pantalla — mismo criterio que `FocoHeroeMetrics`/`FocoCabeceraMetrics` en CenitDesign.
private enum FocoMetrics {
    /// 26 — sin token exacto en la escala (s600=24, s700=28).
    static let contentTop: CGFloat = 26  // token-exempt(falta-pieza): tope de foco 26 sin escalón
    static let heroGap = LiquidSpace.s400
    static let capcionTop = LiquidSpace.s150
    static var antTracking: CGFloat { 0.4 }
    static let antTop = LiquidSpace.s350
    static let capsulasTop = LiquidSpace.s450
    static let raiseTop = LiquidSpace.s300
    static let ctaTop = LiquidSpace.s550
    static let prevNextTop = LiquidSpace.s450
    static let doneTitleTop = LiquidSpace.s300
}
#endif
