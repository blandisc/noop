#if os(iOS)
import SwiftUI
import StrandDesign
import StrandTraining
import StrandAnalytics
import Inject

// MARK: - HojaSesionViva — «La Hoja» en modo `.live` (FER-167 · F2, épico FER-165)
//
// El bucle capturar → descansar → repetir (mapa B1-B4) + la integridad de la sesión (B14-B17),
// montada por `RoutineSheet(mode: .live)` en sus 4 hosts. Compone piezas YA CONSTRUIDAS —
// `HojaFilaSerie` en contexto `.sesion` (F1, nunca ejercitado fuera de su #Preview hasta hoy),
// `RestBand` (ya dice la meta), `SessionKeypad` (QUEDABAN/DISCOS/pausa ya existían) — sobre el MOTOR
// vigente (`StrengthSessionModel`, cero reescritura). `LiveStrengthSheet.swift` NO se borra: sigue
// siendo quien pinta el modo Foco (`startInFocus`) y el acta final (`session.summary`) — ver la nota
// en ese archivo. Lo demás (superserie con banda propia, intervenciones nuevas, capa 3 rediseñada)
// es F3/F4/F5; aquí solo se compone lo que YA existe para esos casos.

struct HojaSesionViva: View {
    let sheet: RoutineSheet
    @ObservedObject var session: StrengthSessionModel
    @EnvironmentObject var tabRouter: TabRouter

    // MARK: Captura por teclado — mismos tipos que `LiveStrengthSheet` (cero duplicado de contrato)
    @State var activeCell: LiveStrengthSheet.CellRef?
    @State var buffer: String = ""
    @State var bufferTyped = false
    @State var selectedRIR: Int?
    @State var selectedRIRTarget: LiveStrengthSheet.RIRTarget?

    // MARK: Descanso — qué ejercicio ancla la banda mientras `currentIndex` ya avanzó
    @State var restAnchorEi: Int?
    @State var restStartBpm: Int?

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

    // MARK: Modo foco — sigue viviendo en `LiveStrengthSheet.swift` (F5 lo rediseña)
    @State var focusMode = false

    // MARK: Integridad (B14 en `session.saveError`/`model.retryStrengthSave()`; B15b aquí; B16 en la cabecera)
    @State var confirmFinish = false
    @State var zombieAcknowledged = false

    @ObserveInjection var inject

    var body: some View {
        Group {
            if session.summary != nil {
                // El acta de siempre — cero cambios (FER-167 §3: «el cierre de sesión NO cambia»).
                LiveStrengthSheet(session: session, theme: sheet.theme)
            } else if isZombie, !zombieAcknowledged {
                zombieGate   // B15b
            } else {
                liveLoop
            }
        }
        .background(sheet.theme.paper.ignoresSafeArea())
        .instrumentoTheme(sheet.theme)
        .preferredColorScheme(.light)
        // B17: el gesto de borde minimiza — NUNCA termina la sesión (mismo modificador que
        // `LiveStrengthSheet` ya usaba en el mismo cover).
        .edgeSwipeToExit { sheet.model.strengthSheetPresented = false }
        .task(id: session.routineId) { await loadRoutineREs() }
        .onChange(of: session.phase) { _, phase in
            if phase != .resting { restAnchorEi = nil }
            restStartBpm = phase == .resting ? sheet.model.watchBpm : nil
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
        .sheet(item: $changeExercise) { target in
            ChangeExerciseSheet(
                theme: sheet.theme, run: target.run, repo: sheet.model.repo,
                onUse: { ex in
                    changeExercise = nil
                    Task {
                        let last = await sheet.model.repo.exerciseHistory(exerciseId: ex.id).last
                        await MainActor.run {
                            withAnimation(.snappy) {
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
        .fullScreenCover(isPresented: $focusMode) {
            // El modo foco vigente, sin tocar una línea de su cuerpo (ver `LiveStrengthSheet.init`).
            LiveStrengthSheet(session: session, theme: sheet.theme, startInFocus: true)
        }
        .instrumentoConfirm(
            isPresented: $confirmFinish,
            title: String(localized: "Finish workout?"),
            context: String(localized: "SESSION · IN PROGRESS"),
            message: String(localized: "\(session.doneCount) set(s) logged, ready to save."),
            actions: [
                .init(String(localized: "Keep training"), role: .primary),
                .init(String(localized: "Finish and save"), role: .destructive) { sheet.model.endStrengthSession(save: true) }
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
            ScrollView {
                LazyVStack(spacing: CenitMetrics.sectionGap) {
                    ForEach(rows, id: \.self) { ei in row(ei) }
                }
                .padding(.horizontal, CenitMetrics.screenPadding)
                .padding(.top, 14)
                .padding(.bottom, CenitMetrics.screenPadding)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // B16: sesión llena → el CTA sustituye a la consola (ya no hay nada que capturar).
            if session.isComplete { HojaCabeceraSesion.ctaTerminar(vivo: self) } else { keypadInset }
        }
    }

    /// Los ejercicios activos (no saltados), en orden del plan.
    private var rows: [Int] { session.runs.indices.filter { !session.runs[$0].skipped } }

    @ViewBuilder private func row(_ ei: Int) -> some View {
        if session.isInSuperset(ei) {
            let members = session.supersetMembers(at: ei)
            if members.first == ei { HojaTarjetaSuperserieSesion(vivo: self, members: members) }
        } else if ei == accordionIndex {
            HojaTarjetaEjercicioSesion(vivo: self, ei: ei)
        } else {
            HojaPlegadaSesion(vivo: self, ei: ei)
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
        .background(sheet.theme.paper)
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

    private func loadRoutineREs() async {
        guard let rid = session.routineId, let store = await sheet.repo.storeHandle(),
              let res = try? await store.routineExercises(routineId: rid) else { return }
        routineREs = Dictionary(uniqueKeysWithValues: res.map { ($0.id, $0) })
    }
}
#endif
