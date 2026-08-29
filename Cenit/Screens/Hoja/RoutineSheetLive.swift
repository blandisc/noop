#if os(iOS)
import SwiftUI
import StrandDesign
import StrandTraining
import StrandAnalytics
import Inject

// MARK: - HojaSesionViva — «La Hoja» en modo `.live` (FER-167 · F2, épico FER-165, ronda 2)
//
// El bucle capturar → descansar → repetir (mapa B1-B4) + la integridad de la sesión (B14-B17),
// montada por `RoutineSheet(mode: .live)` en sus 5 hosts. Compone piezas YA CONSTRUIDAS —
// `HojaFilaSerie` en contexto `.sesion`, `RestBand` (ya dice la meta), `SessionKeypad` — sobre el
// MOTOR vigente (`StrengthSessionModel`, cero reescritura salvo los 2 toques quirúrgicos
// autorizados: `lastRPE` para el playhead Q y `closeOpenRest` para la pausa abierta). El acta final
// sigue siendo `LiveStrengthSheet.swift`, sin tocar una línea de su cuerpo. El modo Foco (FER-170 ·
// F5) YA NO vive ahí — es `HojaFoco` (`RoutineSheetLiveFoco.swift`), una expansión de la tarjeta
// activa DENTRO de esta misma vista, con continuidad geométrica vía `focoNS`.
//
// REGLA DURA (ronda 2, 3.ª aparición de la clase): cero identidad por índice. `ForEach` va por
// `run.id`; el ancla del descanso (`accordionIndex`, en `RoutineSheetLiveLogic.swift`) se DERIVA de
// `session.restOwnerSetId` (v40) — no hay `@State … Int` que un reorden pueda desincronizar.

struct HojaSesionViva: View {
    let sheet: RoutineSheet
    @ObservedObject var session: StrengthSessionModel
    @EnvironmentObject var tabRouter: TabRouter
    /// R24: la Hoja viva respeta Reduce Motion — cada `withAnimation(.snappy/.gentle)` de este
    /// árbol pasa por esta bandera (`reduceMotion ? nil : …`).
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    // MARK: Captura por teclado — mismos tipos que `LiveStrengthSheet` (cero duplicado de contrato)
    @State var activeCell: LiveStrengthSheet.CellRef?
    /// FER-inject 2026-08-29 (orden del dueño): revierte parcialmente FER-167 R19 — la consola de la
    /// sesión viva ahora SÍ se puede ocultar (tecla ⌄) para ver la tabla completa; se reabre al tocar
    /// cualquier celda de peso/reps (`beginEditing`). `true` = oculta aunque haya celda activa.
    @State var keypadHidden = false
    @State var buffer: String = ""
    @State var bufferTyped = false
    @State var selectedRIR: Int?
    @State var selectedRIRTarget: LiveStrengthSheet.RIRTarget?

    // MARK: Descanso (R7: SIN ancla `Int` — `accordionIndex` se deriva de `session.restOwnerSetId`)
    @State var restStartBpm: Int?
    /// O-r2a (ronda 3): la tarjeta que el usuario tocó explícitamente para verla mientras descansa
    /// en OTRO ejercicio — por `id` (regla dura), nunca un índice. `nil` = sin espiar, el acordeón
    /// sigue al dueño del descanso como siempre. Ver `accordionIndex`/`restSlotIndex` en
    /// `RoutineSheetLiveLogic.swift` y el tap de `HojaPlegadaSesion`.
    @State var peekRunId: String?

    // MARK: R16/B11 · destello de récord
    @State var personalRecords: [String: [PRMetric: PersonalRecord]] = [:]
    @State var prFlash: PRFlash?

    // MARK: B10 · guard de captura absurda (FER-169)
    @State var absurdCapture: AbsurdCaptureTarget?

    // MARK: B8 · «＋ Agregar ejercicio» desde el ··· en sesión (FER-169)
    /// El `run.id` tras el cual insertar — no-nil abre `ExerciseLibraryScreen`; `nil` = cerrada.
    /// Por identidad (regla dura), no por índice: el picker es un `.sheet` async y B8 puede reordenar
    /// (saltar-al-final, mover) mientras está abierto.
    @State var addExerciseAfterRunId: String?
    /// FER-969: persistir el ejercicio agregado a la RUTINA falló — toast, no el banner persistente
    /// (ese es solo para el guardado FINAL de la sesión, `session.saveError`). La sesión en sí ya
    /// tiene el ejercicio; solo no sobrevivirá a la próxima vez que se abra esta rutina a editar.
    @State var routineWriteError = false

    // MARK: B6b · «Volver a X» sobre una subida ya tomada (FER-169)
    /// El `run.id` cuya tarjeta «Volver a {anterior} / Seguir en {actual}» está abierta — un tap en el
    /// ▲ de una fila con subida aplicada la abre; solo una a la vez, por identidad (regla dura).
    @State var raiseRevertOpenRunId: String?

    // MARK: Capa 3 (hojas ya existentes — mismos tipos, mismas pantallas)
    @State var platesTarget: LiveStrengthSheet.PlatesTarget?
    @State var rpeTarget: LiveStrengthSheet.RPETarget?
    @State var noteTarget: LiveStrengthSheet.NoteTarget?
    @State var noteHistory: [ExerciseNote]?
    @State var restEdit: LiveStrengthSheet.RestEdit?
    @State var detailExercise: Exercise?
    @State var changeExercise: LiveStrengthSheet.ChangeTarget?
    @State var progressionEdit: LiveStrengthSheet.ProgressionEditTarget?
    @State var routineREs: [String: RoutineExercise] = [:]
    @State var menuExerciseIndex: Int?
    /// R8: el «robo» de superserie pide confirmar antes de deshacer la pareja del vecino.
    @State var confirmSupersetSteal: Int?

    // MARK: Modo foco (FER-170 · F5, épico FER-165) — expansión de la tarjeta activa, DENTRO de
    // esta misma vista (ya no una instancia efímera de `LiveStrengthSheet`). `focoNS` amarra la
    // continuidad geométrica entre la tarjeta chica (`row(_:)`) y `HojaFoco` a pantalla completa.
    @Namespace var focoNS
    @State var focusMode = false
    /// D3 · HECHO: el `run.id` cuyo cierre (ejercicio completo, o ronda cerrada en superserie) ya
    /// puede mostrarse — `nil` mientras no hay ninguno pendiente de reconocer. Por `id` (regla
    /// dura): un `Int` no sobreviviría un reorden mientras la pantalla de HECHO sigue en foco.
    @State var focusDoneRunId: String?
    /// El `run.id` que cerró hacia un descanso REAL — retenido hasta que ese descanso termina
    /// (`session.phase` deja `.resting`), momento en el que `onChange` lo promueve a
    /// `focusDoneRunId` (paridad `LiveStrengthSheet.focusDoneTiming`, reusada tal cual).
    @State var pendingFocusDoneRunId: String?

    // MARK: Integridad (B14 en `session.saveError`/`model.retryStrengthSave()`; B15b aquí; B16 en la cabecera)
    @State var confirmFinish = false
    @State var zombieAcknowledged = false

    // MARK: B16b · «¿La rutina se queda así?» (FER-169)
    /// No-nil = hubo cambios estructurales y la pregunta está en pantalla; `nil` = cerrada/no aplica.
    @State var routineChangesToConfirm: RoutineChangesSummary?

    @ObserveInjection var inject

    var body: some View {
        ZStack {
            Group {
                if session.summary != nil {
                    // El acta de siempre — cero cambios (FER-167 §3: «el cierre de sesión NO cambia»).
                    LiveStrengthSheet(session: session, theme: sheet.theme)
                } else if session.routineId == nil && session.runs.isEmpty {
                    // D-r2.1 (ronda 3, regresión bloqueante): «Sesión rápida» vacía (`startQuickStrength`)
                    // — el buscador + sugerencias de frescura siguen siendo `LiveStrengthSheet.emptyAdHocSession`
                    // (B13 los rediseña en F4). Construir una instancia NORMAL (sin `summary`) hace que
                    // SU PROPIO `body` la muestre — mismo patrón de composición que ya usamos para el
                    // acta: cero líneas de ese estado tocadas. Al agregar el primer ejercicio
                    // `session.runs` deja de estar vacío (mismo `session`, por referencia) y este
                    // `body` vuelve a evaluar hacia `liveLoop` solo.
                    LiveStrengthSheet(session: session, theme: sheet.theme)
                } else if isZombie, !zombieAcknowledged {
                    zombieGate   // B15b
                } else {
                    liveLoop
                }
            }
            // FER-170 (F5): el enfoque expande la tarjeta activa DENTRO de esta misma pantalla — un
            // overlay que comparte `focoNS` con la tarjeta, no un `.fullScreenCover` (ese sería una
            // hoja NUEVA sin continuidad geométrica posible con lo que había debajo). Corte seco con
            // Reduce Motion (R4, ronda 2 del gate): el toggle de `focusMode` SIEMPRE pasa por
            // `withAnimation(reduceMotion ? nil : .snappy)` (`HojaSesionViva.enterFoco`/`HojaFoco.salir`)
            // — con Reduce Motion activo, ese `withAnimation` recibe `nil` (sin transacción animada),
            // así que el `matchedGeometryEffect` compartido no interpola y el cambio salta directo,
            // sin envolver el toggle en NINGÚN `withAnimation` con animación real.
            if focusMode { HojaFoco(vivo: self) }
        }
        .entrenarHojaFondo(tono: .indigo)
        .instrumentoTheme(sheet.theme)
        .preferredColorScheme(.light)
        // B17: el gesto de borde minimiza — NUNCA termina la sesión (mismo modificador que
        // `LiveStrengthSheet` ya usaba en el mismo cover).
        .edgeSwipeToExit { sheet.model.strengthSheetPresented = false }
        // O-r2a (ronda 3): el auto-skip del descanso fijo (R1) vive AQUÍ, a nivel de la vista raíz —
        // sobrevive aunque la tarjeta del dueño se pliegue por un «espiar» (`peekRunId`). Es un
        // no-op mientras no hay `restEndsAt` fijo en vuelo (ver `RestAutoSkipModifier`).
        .modifier(restAutoSkipModifier())
        .task(id: session.routineId) { await loadRoutineREs() }
        .task { await loadPersonalRecords() }   // R16
        .saveErrorToast(isPresented: $routineWriteError)   // B8: falló persistir a la rutina (no la sesión)
        .onChange(of: session.phase) { _, phase in
            restStartBpm = phase == .resting ? sheet.model.watchBpm : nil
            peekRunId = nil   // O-r2a: cualquier cambio de fase limpia el «espiar» — nunca queda rancio
            // FER-170 (F5, D3): el descanso real que arrancó al cerrar un ejercicio/ronda ya terminó
            // (se acabó o se saltó) — hasta ahora es cuando HECHO puede aparecer, nunca antes (paridad
            // `LiveStrengthSheet.focusDoneTiming`, `.pending`).
            if phase != .resting, let pending = pendingFocusDoneRunId {
                pendingFocusDoneRunId = nil
                focusDoneRunId = pending
            }
        }
        .sheet(item: $detailExercise) { ex in
            NavigationStack {
                ExerciseDetailScreen(exercise: ex)
                    .toolbar { ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { detailExercise = nil }.foregroundStyle(sheet.theme.ink)
                    } }
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbarBackground(sheet.theme.paper, for: .navigationBar)
            }
            .instrumentoTheme(sheet.theme).environmentObject(sheet.repo).preferredColorScheme(.light)
        }
        // B8 (FER-169): «＋ Agregar ejercicio» — mismo picker que la Hoja fría/`LiveStrengthSheet`
        // (`ExerciseLibraryScreen`), reusado tal cual; insertar+persistir es 1:1 con
        // `LiveStrengthSheet.addExercises`/`persistInsertedExercises`.
        .sheet(isPresented: Binding(get: { addExerciseAfterRunId != nil }, set: { if !$0 { addExerciseAfterRunId = nil } })) {
            ExerciseLibraryScreen { picks in
                let afterRunId = addExerciseAfterRunId
                addExerciseAfterRunId = nil
                Task { await addExercisesFromLibrary(picks, afterRunId: afterRunId) }
            }
            .instrumentoTheme(sheet.theme).environmentObject(sheet.repo).preferredColorScheme(.light)
        }
        .sheet(item: $changeExercise) { target in
            ChangeExerciseSheet(
                theme: sheet.theme, run: target.run, repo: sheet.model.repo,
                onUse: { ex in
                    changeExercise = nil
                    Task {
                        let last = await sheet.model.repo.exerciseHistory(exerciseId: ex.id).last
                        await MainActor.run {
                            withAnimation(reduceMotion ? nil : .snappy) {
                                session.replaceExercise(at: target.ei, with: ex, lastWeightKg: last?.weightKg, lastReps: last?.reps)
                            }
                        }
                    }
                },
                onClose: { changeExercise = nil }
            )
            .instrumentoTheme(sheet.theme).preferredColorScheme(.light).presentationBackground(sheet.theme.paper)
        }
        .sheet(item: $platesTarget) { target in
            PlatesScreen(
                theme: sheet.theme, targetKg: target.weightKg,
                exerciseName: session.runs.indices.contains(target.ei) ? session.runs[target.ei].name : "",
                store: sheet.model.plates,
                onInsertWarmup: { sets in
                    session.insertWarmup(exercise: target.ei, sets: sets)
                    if session.runs.indices.contains(target.ei) {
                        sheet.model.plates.setWarmupAlways(session.runs[target.ei].exerciseId, true)
                    }
                    platesTarget = nil
                },
                onClose: { platesTarget = nil }, startAtWarmup: target.startAtWarmup
            )
            .presentationDetents([.large]).presentationDragIndicator(.hidden).presentationBackground(sheet.theme.paper)
        }
        .sheet(item: $rpeTarget) { target in
            RPESheet(theme: sheet.theme, target: target,
                     weightLabel: "\(plateNumber(displayWeight(target.weightKg))) \(weightUnit())",
                     onPick: { rpe in session.setRPE(exercise: target.runId, set: target.id, rpe: rpe); rpeTarget = nil },
                     onClose: { rpeTarget = nil })
                .presentationDetents([.height(560)]).presentationDragIndicator(.visible)
                .presentationBackground(sheet.theme.paper).preferredColorScheme(.light)
        }
        .sheet(item: $noteTarget) { target in
            if let run = session.runs.first(where: { $0.id == target.id }) {
                NoteSheet(
                    theme: sheet.theme, target: target, initialScope: .exercise,
                    exerciseText: run.note ?? "",
                    setText: run.sets.first(where: { $0.id == target.setId })?.note ?? "",
                    history: noteHistory,
                    onSave: { scope, text in
                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        let value: String? = trimmed.isEmpty ? nil : trimmed
                        switch scope {
                        case .exercise: session.setExerciseNote(exercise: target.id, text: value)
                        case .set: session.setSetNote(exercise: target.id, set: target.setId, text: value)
                        }
                        noteTarget = nil
                    },
                    onClose: { noteTarget = nil }
                )
                .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
                .presentationBackground(sheet.theme.paper).preferredColorScheme(.light)
            }
        }
        .sheet(item: $restEdit) { edit in
            if session.runs.indices.contains(edit.id) {
                let run = session.runs[edit.id]
                let si = edit.setIndex
                let current: RestConfig = (si.flatMap { run.sets.indices.contains($0) ? run.sets[$0].rest : nil }) ?? run.restConfig
                RestEditorScreen(
                    theme: sheet.theme, exerciseName: run.name, setNumber: si.map { $0 + 1 }, current: current,
                    persistsToRoutine: session.routineId != nil,
                    restingHR: sheet.repo.days.compactMap(\.restingHr).last.map(Double.init),
                    maxHR: Double(sheet.model.profile.hrMax), defaultApplyToAll: si == nil, closeAsDismiss: true,
                    onCancel: { restEdit = nil },
                    onApply: { config, applyToAll, _ in
                        if applyToAll { session.updateRest(exercise: edit.id, mode: config.mode, seconds: config.seconds, reference: config.hrReference, value: config.hrValue) }
                        else if let si { session.updateRest(exercise: edit.id, set: si, rest: config) }
                        restEdit = nil
                    }
                )
                .preferredColorScheme(.light).presentationDetents([.large]).presentationDragIndicator(.hidden).presentationBackground(sheet.theme.paper)
            }
        }
        .sheet(item: $progressionEdit) { target in
            if session.runs.indices.contains(target.id) {
                let run = session.runs[target.id]
                ProgressionSetupScreen(
                    theme: sheet.theme, exercise: routineREs[run.id] ?? syntheticRE(from: run, position: target.id),
                    exerciseName: run.name, currentWeightKg: run.sets.first?.weightKg,
                    derivedIncrementKg: PlateMath.minimumIncrement(for: .from(equipment: ExerciseCatalog.byID(run.exerciseId)?.equipment), inventory: sheet.model.plates.inventory),
                    onBack: { progressionEdit = nil },
                    onSave: { _, _, _, _, _, _ in progressionEdit = nil }   // La escritura a la rutina sigue F4 (intervención) — F2 solo abre/cierra la hoja intacta.
                )
                .padding(.top, CenitMetrics.gap).presentationDragIndicator(.visible).presentationBackground(sheet.theme.paper).preferredColorScheme(.light)
            }
        }
        .instrumentoConfirm(
            isPresented: $confirmFinish,
            title: String(localized: "Finish workout?"),
            context: String(localized: "SESSION · IN PROGRESS"),
            // R6: DEDUPLICADA — la clave existente de `LiveStrengthSheet`, no una nueva.
            message: String(localized: "You logged \(session.doneCount) sets. Finish to save this workout."),
            actions: [
                // R18 (Grok 12): guardar NO es destructivo — primaria, como el confirm viejo.
                // B16b (FER-169): pasa por el detector de cambios de rutina antes de terminar de verdad.
                .init(String(localized: "Finish and save"), role: .primary) { requestFinish() },
                .init(String(localized: "Keep training"), role: .secondary)
            ]
        )
        // B16b (FER-169): «¿La rutina se queda así?» — solo aparece cuando SÍ hubo cambios (mapa: una
        // pregunta, una vez); si no hay ninguno, `requestFinish()` ya terminó sin pasar por aquí.
        .instrumentoConfirm(
            isPresented: Binding(get: { routineChangesToConfirm != nil }, set: { if !$0 { routineChangesToConfirm = nil } }),
            title: String(localized: "Keep the routine this way?"),
            context: String(localized: "SESSION · IN PROGRESS"),
            message: routineChangesToConfirm?.phrase ?? "",
            actions: [
                .init(String(localized: "Save to the routine"), role: .primary) { finishAndSaveRoutineChanges() },
                .init(String(localized: "Just for today"), role: .secondary) { finishWithoutSavingRoutineChanges() }
            ]
        )
        // R8: confirma antes de robarle la pareja de superserie al vecino — misma clave que F1.
        .instrumentoConfirm(
            isPresented: Binding(get: { confirmSupersetSteal != nil }, set: { if !$0 { confirmSupersetSteal = nil } }),
            title: String(localized: "Break its current superset?"),
            context: String(localized: "SESSION · IN PROGRESS"),
            message: supersetStealMessage,
            actions: [
                .init(String(localized: "Pair here"), role: .primary) { confirmSupersetStealAndPair() },
                .init(String(localized: "Keep as is"), role: .secondary)
            ]
        )
        .enableInjection()
    }

    // MARK: - El bucle (B1-B4)

    private var liveLoop: some View {
        VStack(spacing: 0) {
            HojaCabeceraSesion.header(vivo: self)
            HojaCabeceraSesion.avance(vivo: self)
            if session.saveError { saveErrorBanner }   // B14
            // R14 (Grok 6): scroll-to cuando el foco avanza — paridad `LiveStrengthSheet` (línea 646),
            // ancla por `run.id` (regla dura), nunca por índice.
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: CenitMetrics.sectionGap) {
                        // REGLA DURA: `ForEach` por `run.id` — `session.runs.enumerated()` da `ei` fresco
                        // en cada construcción (nunca un ancla que sobreviva un reorden).
                        ForEach(Array(session.runs.enumerated()), id: \.element.id) { ei, run in
                            if !run.skipped { row(ei).id("hoja-viva-ejercicio-\(run.id)") }
                        }
                    }
                    .padding(.horizontal, CenitMetrics.screenPadding)
                    .padding(.top, 14)
                    .padding(.bottom, CenitMetrics.screenPadding)
                }
                .onChange(of: accordionIndex) { _, newIndex in
                    guard session.runs.indices.contains(newIndex) else { return }
                    let id = session.runs[newIndex].id
                    withAnimation(reduceMotion ? nil : StrandMotion.gentle.delay(0.15)) {
                        proxy.scrollTo("hoja-viva-ejercicio-\(id)", anchor: .center)
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // B16: sesión llena → el CTA sustituye a la consola (ya no hay nada que capturar).
            if session.isComplete { HojaCabeceraSesion.ctaTerminar(vivo: self) } else { keypadInset }
        }
    }

    @ViewBuilder private func row(_ ei: Int) -> some View {
        if session.isInSuperset(ei) {
            let members = session.supersetMembers(at: ei)
            if members.first == ei {
                // R1 (ronda 2 del gate, Grok G1/G4, bloqueante): F3 NO pliega las tarjetas de
                // superserie — con 2+ bloques en la misma sesión, esta rama se evalúa una vez POR
                // bloque. `esActiva` decide cuál de ellos (a lo más uno) es la «Now Playing» real.
                focoDoor(esActiva: members.contains(accordionIndex)) {
                    HojaTarjetaSuperserieSesion(vivo: self, members: members)
                }
            }
        } else if ei == accordionIndex {
            // Esta rama solo se evalúa para el ÚNICO `ei` que iguala `accordionIndex` — siempre activa.
            focoDoor(esActiva: true) { HojaTarjetaEjercicioSesion(vivo: self, ei: ei) }
        } else {
            HojaPlegadaSesion(vivo: self, ei: ei)
        }
    }

    /// D0 (FER-170 · F5): la puerta de Foco es la tarjeta activa misma (como Now Playing). Este
    /// wrapper solo aporta el ancla de `matchedGeometryEffect` que amarra su marco al de `HojaFoco`
    /// — la continuidad geométrica de la expansión; el tap real («⤢» junto al «···») y la acción de
    /// VoiceOver viven DENTRO de `HojaTarjetaEjercicioSesion`/`HojaTarjetaSuperserieSesion` (mismo
    /// patrón que el «···» de cada una, que ya conocía `focusMode`). Sin ancla mientras Foco está
    /// abierto (`!focusMode`): una vez expandido, `HojaFoco` es la única dueña del marco compartido
    /// — dejar las dos vivas fuerza a SwiftUI a reconciliar el mismo id dos veces por frame.
    ///
    /// R1 (ronda 2 del gate, bloqueante): `esActiva` es el segundo candado — nunca cuelga el ancla en
    /// una tarjeta que NO es la «Now Playing» real. Sin él, 2+ tarjetas de superserie sin plegar (F3)
    /// reclamarían el MISMO id de `matchedGeometryEffect` a la vez — SwiftUI no puede elegir una
    /// fuente indefinida entre varias, y el morph podía salir del marco equivocado.
    @ViewBuilder private func focoDoor<Content: View>(esActiva: Bool, @ViewBuilder content: () -> Content) -> some View {
        content()
            .background {
                if !focusMode, esActiva {
                    Color.clear.matchedGeometryEffect(id: HojaFoco.namespaceId, in: focoNS)
                }
            }
    }

    // MARK: - B14 — fallo de guardado

    private var saveErrorBanner: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(StrandFont.glyph(.chevron)).foregroundStyle(sheet.theme.critical)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("Couldn't save the workout. Try again.")
                    .font(StrandFont.caption).fontWeight(.medium).foregroundStyle(sheet.theme.ink)
                Text("Your sets are safe on this phone.")
                    .font(StrandFont.caption).foregroundStyle(sheet.theme.inkSecondary)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            Button { sheet.model.retryStrengthSave() } label: {
                Text("Retry").font(StrandFont.caption).fontWeight(.medium).foregroundStyle(sheet.theme.ink)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, CenitMetrics.screenPadding)
        .padding(.vertical, 10)
        .entrenarHojaBarraFondo(tono: .indigo)
        .overlay(alignment: .bottom) { Rectangle().fill(sheet.theme.hairline).frame(height: 1) }
    }

    // MARK: - B15b — sesión zombie («quedó abierta ayer»; ver `isZombie` en el archivo de lógica)

    private var zombieGate: some View {
        VStack(spacing: CenitMetrics.gap) {
            Spacer()
            (Text(verbatim: "✓ ").foregroundStyle(LiquidColor.verdeProfundo)
             + Text("You left a session open yesterday · \(session.routineName), \(serieSubtitle)"))
                .font(StrandFont.subhead.weight(.semibold)).foregroundStyle(sheet.theme.ink)
                .multilineTextAlignment(.center).padding(.horizontal, CenitMetrics.screenPadding)
            HStack(spacing: 10) {
                Button { archivarZombie() } label: {
                    Text("Archive").font(StrandFont.subhead.weight(.semibold)).foregroundStyle(sheet.theme.ink)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .overlay(Capsule().strokeBorder(sheet.theme.hairlineStrong, lineWidth: 1))
                }
                .buttonStyle(.plain)
                Button { zombieAcknowledged = true } label: {
                    (Text("Keep going") + Text(verbatim: " ›"))
                        .font(StrandFont.subhead.weight(.bold)).foregroundStyle(sheet.theme.paper)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(LiquidColor.verdePrimario, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func syntheticRE(from run: StrengthSessionModel.ExerciseRun, position: Int) -> RoutineExercise {
        RoutineExercise(routineId: session.routineId ?? "", exerciseId: run.exerciseId, position: position,
                        targetSets: run.sets.filter { $0.kind == .work }.count,
                        targetReps: run.sets.first?.reps, targetWeightKg: run.sets.first?.weightKg)
    }

    func loadRoutineREs() async {
        guard let rid = session.routineId, let store = await sheet.repo.storeHandle(),
              let res = try? await store.routineExercises(routineId: rid) else { return }
        routineREs = Dictionary(uniqueKeysWithValues: res.map { ($0.id, $0) })
    }
}

/// B11 (FER-169): la serie que acaba de batir un récord y qué copy le corresponde — «RÉCORD {metric}
/// · antes {priorText}» (mapa). `priorText` ya viene formateado (unidad del sistema del usuario,
/// StrandDesign no formatea); `nil` cuando el ejercicio no tenía PR previo de ese tipo («primera vez»).
struct PRFlash: Equatable {
    let setId: String
    let metric: PRMetric
    let priorText: String?
}

/// B16b (FER-169): qué cambió en la marcha respecto a la rutina base — series por ejercicio y
/// sustituciones. `phraseEs`/`phrase` es la línea del mapa («prensa 3 → 4 series · zancadas por
/// búlgaras»), ya armada, para no reconstruir gramática dispersa en la vista.
struct RoutineChangesSummary: Equatable {
    let phrase: String
}

/// B10 (FER-169): la serie que está pidiendo confirmación por captura absurda — `nil` mientras no hay
/// ninguna pregunta en pantalla. Por identidad (regla dura), no por índice: B8 puede reordenar
/// (saltar-al-final, mover) mientras el aviso sigue en pantalla. `weightKg`/`referenceKg` viajan tal
/// como se evaluó el guard, para que el copy («¿825 KG? es 8× tu récord») y la corrección («ERA 82.5»)
/// no tengan que releer el modelo — solo `runId`/`setId` se resuelven a índice fresco al confirmar.
struct AbsurdCaptureTarget: Equatable {
    let runId: String
    let setId: String
    let weightKg: Double
    let referenceKg: Double
}
#endif
