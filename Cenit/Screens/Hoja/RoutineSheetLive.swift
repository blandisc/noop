#if os(iOS)
import SwiftUI
import CenitDesign
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
    /// Nancy · ronda 1: `loadPersonalRecords()` es `async` y arranca en `.task`, así que hasta que
    /// termina `personalRecords` está VACÍO — y un diccionario vacío hacía que TODA serie palomeada
    /// en esos primeros instantes destellara «RÉCORD». El destello espera a que los PR estén cargados.
    ///
    /// Nancy · ronda 2: y por EJERCICIO, no una bandera global. Con un solo `Bool`, un movimiento
    /// agregado o sustituido a media sesión —cuyos PR nunca se consultaron— quedaba indistinguible de
    /// «no tiene marca previa», así que un récord REAL no destellaba nunca en esa sesión.
    @State var personalRecordsLoadedFor: Set<String> = []
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
    /// Nancy · ronda 1 (BLOQUEANTE): «Quitar de la sesión» borraba el run COMPLETO —con sus series
    /// ya palomeadas— de un solo tap y sin vuelta atrás. Cuando el ejercicio tiene trabajo real
    /// registrado, primero pregunta. Por `run.id` (regla dura), nunca por índice: B8 puede reordenar
    /// mientras la pregunta está en pantalla.
    @State var confirmRemoveRunId: String?

    // MARK: El menú de 4 opciones de una serie (ola 1 · FER-327 · E7 · ux-B §③)
    /// La serie cuyo menú («las que puedas» · «bajar y seguir» · «al fallo» · «quitar») está
    /// abierto — pulsación larga sobre la fila o el chip de marca. Por identidad (regla dura): un
    /// `Int` de índice no sobreviviría un reorden mientras el popover sigue en pantalla.
    struct SetMenuTarget: Equatable { let runId: String; let setId: String }
    @State var setMenuTarget: SetMenuTarget?
    /// B5: «Quitar serie» sobre una madre con escalones YA HECHOS pide confirmación con el conteo
    /// exacto; por identidad, igual que `confirmRemoveRunId`.
    struct RemoveSetTarget: Equatable { let runId: String; let setId: String; let doneDropCount: Int }
    @State var confirmRemoveSetTarget: RemoveSetTarget?

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
    /// FER-250: el aviso «descanso por tiempo (sin reloj)» ya se mostró esta sesión — máximo una vez.
    @State var shownNoWatchRestNote = false

    // MARK: B16b · «¿La rutina se queda así?» (FER-169)
    /// No-nil = hubo cambios estructurales y la pregunta está en pantalla; `nil` = cerrada/no aplica.
    @State var routineChangesToConfirm: RoutineChangesSummary?

    @ObserveInjection var inject

    var body: some View {
        ZStack {
            Group {
                if session.summary != nil {
                    // El acta de siempre — cero cambios (FER-167 §3: «el cierre de sesión NO cambia»).
                    LiveStrengthSheet(session: session)
                } else if session.routineId == nil && session.runs.isEmpty {
                    // D-r2.1 (ronda 3, regresión bloqueante): «Sesión rápida» vacía (`startQuickStrength`)
                    // — el buscador + sugerencias de frescura siguen siendo `LiveStrengthSheet.emptyAdHocSession`
                    // (B13 los rediseña en F4). Construir una instancia NORMAL (sin `summary`) hace que
                    // SU PROPIO `body` la muestre — mismo patrón de composición que ya usamos para el
                    // acta: cero líneas de ese estado tocadas. Al agregar el primer ejercicio
                    // `session.runs` deja de estar vacío (mismo `session`, por referencia) y este
                    // `body` vuelve a evaluar hacia `liveLoop` solo.
                    LiveStrengthSheet(session: session)
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
        
        .preferredColorScheme(.light)
        // B17: el gesto de borde minimiza — NUNCA termina la sesión (mismo modificador que
        // `LiveStrengthSheet` ya usaba en el mismo cover).
        .edgeSwipeToExit { sheet.model.strengthSheetPresented = false }
        // O-r2a (ronda 3): el auto-skip del descanso fijo (R1) vive AQUÍ, a nivel de la vista raíz —
        // sobrevive aunque la tarjeta del dueño se pliegue por un «espiar» (`peekRunId`). Es un
        // no-op mientras no hay `restEndsAt` fijo en vuelo (ver `RestAutoSkipModifier`).
        .modifier(restAutoSkipModifier())
        .task(id: session.routineId) { await loadRoutineREs() }
        // R16 · Nancy ronda 2: se re-dispara cuando cambia el elenco de ejercicios (B8 «Agregar»,
        // «Sustituir», o una restauración post-crash), para traer los PR del movimiento nuevo.
        .task(id: session.runs.map(\.exerciseId).joined(separator: "|")) { await loadPersonalRecords() }
        .saveErrorToast(isPresented: $routineWriteError)   // B8: falló persistir a la rutina (no la sesión)
        // B14 / FER-339: fallo FINAL de sesión → mismo toast con Retry (antes banner local).
        .saveErrorToast(
            isPresented: Binding(
                get: { session.saveError },
                set: { session.saveError = $0 }),
            message: String(localized: "Couldn't save the workout. Try again."),
            detail: String(localized: "Your sets are safe on this phone."),
            retryTitle: String(localized: "Retry"),
            onRetry: { sheet.model.retryStrengthSave() })
        .onChange(of: session.phase) { previous, phase in
            // FER-250 / FER-257 D2: al salir del primer descanso caído a reloj, bloquea el aviso
            // one-shot. Cubrir ambas rutas con la misma bandera: sin pulso al entrar
            // (`restStartBpm == nil`) y pulso muerto a mitad de un descanso por FC
            // (`watchBpm == nil` al salir — rama noStrapFallback).
            if previous == .resting, phase != .resting, !shownNoWatchRestNote,
               (restStartBpm == nil || sheet.model.watchBpm == nil) {
                shownNoWatchRestNote = true
            }
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
                        Button("Done") { detailExercise = nil }.foregroundStyle(LiquidColor.tinta900)
                    } }
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbarBackground(LiquidColor.fondoAlto, for: .navigationBar)
            }
            .environmentObject(sheet.repo).preferredColorScheme(.light)
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
            .environmentObject(sheet.repo).preferredColorScheme(.light)
        }
        .sheet(item: $changeExercise) { target in
            ChangeExerciseSheet(
                run: target.run, repo: sheet.model.repo,
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
            .preferredColorScheme(.light).presentationBackground(LiquidColor.fondoAlto)
        }
        .sheet(item: $platesTarget) { target in
            PlatesScreen(
                targetKg: target.weightKg,
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
            .presentationDetents([.large]).presentationDragIndicator(.hidden).presentationBackground(LiquidColor.fondoAlto)
        }
        .sheet(item: $rpeTarget) { target in
            RPESheet(target: target,
                     weightLabel: "\(plateNumber(displayWeight(target.weightKg))) \(weightUnit())",
                     onPick: { rpe in session.setRPE(exercise: target.runId, set: target.id, rpe: rpe); rpeTarget = nil },
                     onClose: { rpeTarget = nil })
                .presentationDetents([.height(560)]).presentationDragIndicator(.visible)
                .presentationBackground(LiquidColor.fondoAlto).preferredColorScheme(.light)
        }
        .sheet(item: $noteTarget) { target in
            if let run = session.runs.first(where: { $0.id == target.id }) {
                NoteSheet(
                    target: target, initialScope: .exercise,
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
                .presentationBackground(LiquidColor.fondoAlto).preferredColorScheme(.light)
            }
        }
        .sheet(item: $restEdit) { edit in
            if session.runs.indices.contains(edit.id) {
                let run = session.runs[edit.id]
                let si = edit.setIndex
                let current: RestConfig = (si.flatMap { run.sets.indices.contains($0) ? run.sets[$0].rest : nil }) ?? run.restConfig
                RestEditorScreen(
                    exerciseName: run.name, setNumber: si.map { $0 + 1 }, current: current,
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
                .preferredColorScheme(.light).presentationDetents([.large]).presentationDragIndicator(.hidden).presentationBackground(LiquidColor.fondoAlto)
            }
        }
        .sheet(item: $progressionEdit) { target in
            if session.runs.indices.contains(target.id) {
                let run = session.runs[target.id]
                ProgressionSetupScreen(
                    exercise: routineREs[run.id] ?? syntheticRE(from: run, position: target.id),
                    exerciseName: run.name, currentWeightKg: run.sets.first?.weightKg,
                    derivedIncrementKg: PlateMath.minimumIncrement(for: .from(equipment: ExerciseCatalog.byID(run.exerciseId)?.equipment), inventory: sheet.model.plates.inventory),
                    onBack: { progressionEdit = nil },
                    onSave: { _, _, _, _, _, _, _ in progressionEdit = nil }   // La escritura a la rutina sigue F4 (intervención) — F2 solo abre/cierra la hoja intacta.
                )
                .padding(.top, LiquidSpace.s300).presentationDragIndicator(.visible).presentationBackground(LiquidColor.fondoAlto).preferredColorScheme(.light)
            }
        }
        // Confirm de Terminar en la raíz; los otros tres cuelgan de subvistas de `liveLoop` (FER-174).
        .liquidConfirm(
            isPresented: $confirmFinish,
            title: String(localized: "Finish workout?"),
            context: String(localized: "SESSION · IN PROGRESS"),
            // FER-250: con 0 series no promete guardar; con ≥1 reusa la clave de siempre.
            message: finishConfirmMessage,
            actions: finishConfirmActions
        )
        .enableInjection()
    }

    // MARK: - El bucle (B1-B4)

    /// Tres confirms en nodos distintos (cabecera / avance / bucle) — dos en el mismo nodo se rompen (FER-174).
    private var liveLoop: some View {
        VStack(spacing: .zero) {
            HojaCabeceraSesion.header(vivo: self)
                // Nancy · ronda 1: confirma antes de tirar un ejercicio que YA tiene series hechas.
                .liquidConfirm(
                    isPresented: Binding(get: { confirmRemoveRunId != nil }, set: { if !$0 { confirmRemoveRunId = nil } }),
                    title: String(localized: "Remove it with its logged sets?"),
                    context: String(localized: "SESSION · IN PROGRESS"),
                    message: removeExerciseMessage,
                    actions: [
                        .init(String(localized: "Keep it"), role: .primary),
                        .init(String(localized: "Remove anyway"), role: .destructive) { confirmRemoveExercise() }
                    ]
                )
            HojaCabeceraSesion.avance(vivo: self)
                // R8: confirma antes de robarle la pareja de superserie al vecino — misma clave que F1.
                .liquidConfirm(
                    isPresented: Binding(get: { confirmSupersetSteal != nil }, set: { if !$0 { confirmSupersetSteal = nil } }),
                    title: String(localized: "Break its current superset?"),
                    context: String(localized: "SESSION · IN PROGRESS"),
                    message: supersetStealMessage,
                    actions: [
                        .init(String(localized: "Pair here"), role: .primary) { confirmSupersetStealAndPair() },
                        .init(String(localized: "Keep as is"), role: .secondary)
                    ]
                )
            // R14 (Grok 6): scroll-to cuando el foco avanza — paridad `LiveStrengthSheet` (línea 646),
            // ancla por `run.id` (regla dura), nunca por índice.
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: LiquidSpace.s300) {
                        // REGLA DURA: `ForEach` por `run.id` — `session.runs.enumerated()` da `ei` fresco
                        // en cada construcción (nunca un ancla que sobreviva un reorden).
                        ForEach(Array(session.runs.enumerated()), id: \.element.id) { ei, run in
                            if !run.skipped { row(ei).id("hoja-viva-ejercicio-\(run.id)") }
                        }
                    }
                    .padding(.horizontal, LiquidSpace.s600)
                    .padding(.top, LiquidSpace.s350)
                    .padding(.bottom, LiquidSpace.s600)
                }
                .onChange(of: accordionIndex) { _, newIndex in
                    guard session.runs.indices.contains(newIndex) else { return }
                    let id = session.runs[newIndex].id
                    withAnimation(reduceMotion ? nil : LiquidMotion.suave.delay(0.15)) {
                        proxy.scrollTo("hoja-viva-ejercicio-\(id)", anchor: .center)
                    }
                }
            }
            // B5 (ola 1 · FER-327 · E7): confirma antes de quitar una madre cuyos escalones YA
            // registraron trabajo real — nodo propio (`ScrollViewReader`), distinto del de la
            // cabecera/avance/VStack exterior (FER-174: dos `.liquidConfirm` en el mismo nodo se rompen).
            .liquidConfirm(
                isPresented: Binding(get: { confirmRemoveSetTarget != nil }, set: { if !$0 { confirmRemoveSetTarget = nil } }),
                title: String(localized: "Remove this set?"),
                context: String(localized: "SESSION · IN PROGRESS"),
                message: removeSetMessage,
                actions: [
                    .init(String(localized: "Keep set"), role: .primary),
                    .init(String(localized: "Remove set and drops"), role: .destructive) { confirmRemoveSet() }
                ]
            )
        }
        .safeAreaInset(edge: .bottom, spacing: .zero) {
            // B16: sesión llena → el CTA sustituye a la consola (ya no hay nada que capturar).
            if session.isComplete { HojaCabeceraSesion.ctaTerminar(vivo: self) } else { keypadInset }
        }
        // B16b (FER-169): «¿La rutina se queda así?» — solo aparece cuando SÍ hubo cambios (mapa: una
        // pregunta, una vez); si no hay ninguno, `requestFinish()` ya terminó sin pasar por aquí.
        .liquidConfirm(
            isPresented: Binding(get: { routineChangesToConfirm != nil }, set: { if !$0 { routineChangesToConfirm = nil } }),
            title: String(localized: "Keep the routine this way?"),
            context: String(localized: "SESSION · IN PROGRESS"),
            message: routineChangesToConfirm?.phrase ?? "",
            actions: [
                .init(String(localized: "Save to the routine"), role: .primary) { finishAndSaveRoutineChanges() },
                .init(String(localized: "Just for today"), role: .secondary) { finishWithoutSavingRoutineChanges() }
            ]
        )
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

    // MARK: - B15b — sesión zombie («quedó abierta ayer»; ver `isZombie` en el archivo de lógica)

    private var zombieGate: some View {
        VStack(spacing: LiquidSpace.s300) {
            Spacer()
            (Text(verbatim: "✓ ").foregroundStyle(LiquidColor.verdeProfundo)
             + Text("You left a session open yesterday · \(session.routineName), \(serieSubtitle)"))
                .font(LiquidType.cuerpoBanner.weight(.semibold)).foregroundStyle(LiquidColor.tinta900)
                .multilineTextAlignment(.center).padding(.horizontal, LiquidSpace.s600)
            HStack(spacing: LiquidSpace.s250) {
                Button { archivarZombie() } label: {
                    Text("Archive").font(LiquidType.cuerpoBanner.weight(.semibold)).foregroundStyle(LiquidColor.tinta900)
                        .outlineCapsule(
                            .outline,
                            size: .aMedida(
                                insets: EdgeInsets(top: LiquidSpace.s250, leading: LiquidSpace.s400,
                                                   bottom: LiquidSpace.s250, trailing: LiquidSpace.s400),
                                minHeight: nil,
                                touchInset: .zero))
                }
                .buttonStyle(.plain)
                OutlineCapsule(
                    size: .aMedida(
                        insets: EdgeInsets(top: LiquidSpace.s250, leading: LiquidSpace.s400,
                                           bottom: LiquidSpace.s250, trailing: LiquidSpace.s400),
                        minHeight: nil,
                        touchInset: .zero),
                    filled: true,
                    fill: LiquidColor.verdePrimario,
                    action: { zombieAcknowledged = true }
                ) {
                    (Text("Keep training") + Text(verbatim: " ›"))
                        .font(LiquidType.cuerpoBanner.weight(.bold))
                        .foregroundStyle(LiquidColor.papelTarjeta)
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func syntheticRE(from run: StrengthSessionModel.ExerciseRun, position: Int) -> RoutineExercise {
        // Ola 1 (E7 · D2): un escalón de «bajar y seguir» no es una serie prescrita — `targetSets`
        // solo cuenta series numeradas (`isNumberedWorkSet`, único oráculo).
        RoutineExercise(routineId: session.routineId ?? "", exerciseId: run.exerciseId, position: position,
                        targetSets: run.sets.filter(\.isNumberedWorkSet).count,
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
/// CenitDesign no formatea); `nil` cuando el ejercicio no tenía PR previo de ese tipo («primera vez»).
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
