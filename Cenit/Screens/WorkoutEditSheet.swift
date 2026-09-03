#if os(iOS)
import SwiftUI
import CenitDesign
import StrandTraining
import CenitStore   // store.routineExercises(routineId:) — clasificación de familia (Alcance punto 5, FER-90)
import Inject   // recarga en caliente (dev-only, inerte en Release)

// WorkoutEditSheet.swift — edit a SAVED strength session (FER-556 → Liquid Glass · FER-294 B.2).
// Opened from `WorkoutSessionDetailScreen`'s «Editar». Corrects the user-authored data: each set's
// weight/reps, add/remove a set, reassign an exercise, the date/time, the routine, and notes. It NEVER
// touches the strap's captured truth (`strain`/`avgHr`/`deviceId`) — those ride through unchanged and
// show here as a read-only «Del cuerpo» block. Persists via `repo.updateSession`, which recomputes the
// affected PRs exactly (a corrected weight can lower a record). Reuses the inline weight/reps
// vocabulary of `LiveStrengthSheet` so there's no new pattern to learn.

struct WorkoutEditSheet: View {
    let session: StrengthSession
    /// Called after a successful save (the detail reloads + bumps the list).
    let onSaved: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var repo: Repository
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    private var system: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }

    // MARK: Editable working copy

    @State private var startDate: Date
    @State private var routineId: String?
    @State private var notes: String
    @State private var groups: [EditGroup]
    private let otherSets: [SetEntry]          // non-work sets, preserved verbatim on save
    private let originalStartTs: Int
    private let originalEndTs: Int?
    private let original: Snapshot             // for dirty detection

    // MARK: Loaded context

    @State private var routines: [Routine] = []
    @State private var exercisesByID: [String: Exercise] = [:]
    /// La familia por rutina, para el punto de tinte junto a la rutina YA elegida (Alcance punto 5).
    /// Vacío si `storeHandle()` falla — el picker sigue funcionando, solo sin punto (Estados).
    @State private var routineRegions: [String: RoutineRegion] = [:]

    // MARK: Transient UI

    @FocusState private var focused: CellRef?
    @State private var buffers: [CellRef: String] = [:]
    @State private var reassignGroup: ReassignTarget?
    @State private var showDiscard = false
    @ScaledMetric(relativeTo: .footnote) private var lectura = LiquidType.lecturaHojaBase
    @State private var saveError = false
    @State private var showRoutineMenu = false

    init(session: StrengthSession, sets: [SetEntry], onSaved: @escaping () async -> Void) {
        self.session = session
        self.onSaved = onSaved
        _startDate = State(initialValue: Date(timeIntervalSince1970: TimeInterval(session.startTs)))
        _routineId = State(initialValue: session.routineId)
        _notes = State(initialValue: session.notes ?? "")
        let work = sets.filter { $0.kind == .work }
        otherSets = sets.filter { $0.kind != .work }
        var order: [String] = []
        var by: [String: [SetEntry]] = [:]
        for s in work {
            if by[s.exerciseId] == nil { order.append(s.exerciseId) }
            by[s.exerciseId, default: []].append(s)
        }
        let g = order.map { id in EditGroup(exerciseId: id, sets: (by[id] ?? []).map(EditSet.init)) }
        _groups = State(initialValue: g)
        originalStartTs = session.startTs
        originalEndTs = session.endTs
        original = Snapshot(startTs: session.startTs, routineId: session.routineId,
                            notes: session.notes ?? "", groups: g)
    }

    /// Inject: los hooks van en la vista NO privada más externa del archivo (ver `EntrenarView`).
    @ObserveInjection private var inject
    var body: some View {
        NavigationStack {
            listBody
            .navigationTitle("Edit workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(LiquidColor.fondoAlto, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // FER-998: el disco de papel en vez de la palabra «Cancel» — la misma salida que
                    // el resto de la app. `cancel()` conserva la confirmación de descartar.
                    BackButton(role: .close) { cancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    HeaderActionButton(Text("Save"), enabled: canSave) { save() }
                }
            }
        }
        // FER-199 (Ola 3, épico FER-195): fondo de vidrio El Eje EN LA RAÍZ del `NavigationStack`
        // propio — mismo patrón que `ChangeExerciseSheet`/`ExerciseDetailScreen` (Ola 2): el stack
        // trae SUS DOS acciones de salida nativas (Cancel a la izquierda, Save a la derecha), así
        // que se CONSERVA su toolbar tal cual en vez de reducirlo a la salida única de
        // `EntrenarHojaCabecera` — forzar la cabecera aquí le quitaría un control (REGLA SUPREMA).
        .entrenarHojaFondo(tono: .neutro)
        .interactiveDismissDisabled(isDirty)
        // FER-998: una hoja no tiene gesto de borde; se lo damos. Pasa por `cancel()`, así que con
        // cambios sin guardar sale la confirmación de descartar igual que al tocar el botón.
        .edgeSwipeToExit { cancel() }
        .liquidConfirm(
            isPresented: $showDiscard,
            title: String(localized: "Discard changes?"),
            context: String(localized: "WORKOUT · UNSAVED CHANGES"),
            message: String(localized: "Your edits to this workout will be lost."),
            actions: [
                .init(String(localized: "Keep editing"), role: .primary),
                .init(String(localized: "Discard changes"), role: .destructive) { dismiss() }
            ]
        )
        // FER-837: save failure is an inline banner (a result must not cover the screen), not an
        // alert. FER-199 (Ola 3): absorbe el banner hecho a mano en `SaveErrorToast` — ya en
        // cristal El Eje (mismo `patternBlock` + auto-descarte a 4s) y usado en el resto de
        // Entrenar (`WorkoutSessionDetailScreen.duplicateError`, `WorkoutDetailScreen`); mismo
        // disparador (`saveError = true` en el catch de `save()`), mismo cuándo/por qué. La copy
        // NO cambia: `message:` conserva el texto original de esta pantalla (revisión adversarial
        // — el genérico del componente le habría restado la palabra «workout»).
        .saveErrorToast(isPresented: $saveError,
                        message: String(localized: "Couldn't save the workout. Try again."))
        .sheet(item: $reassignGroup) { target in
            NavigationStack {
                ExerciseLibraryScreen { picks in
                    if let ex = picks.first { reassign(group: target.index, to: ex) }
                    reassignGroup = nil
                }
                .navigationTitle("Choose exercise")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(LiquidColor.fondoAlto, for: .navigationBar)
            }
        }
        .task {
            routines = await repo.routines()
            let all = await repo.allExercises()
            exercisesByID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            // Mismo patrón de clasificación que `WorkoutHistoryScreen.load()`, sin la segunda llamada a
            // `customExercises()`: `allExercises()` ya fusiona catálogo + ejercicios propios en
            // `exercisesByID` (Alcance punto 5).
            if let store = await repo.storeHandle() {
                var regions: [String: RoutineRegion] = [:]
                for r in routines {
                    let exs = (try? await store.routineExercises(routineId: r.id)) ?? []
                    let perExercise = exs.compactMap { exercisesByID[$0.exerciseId]?.primaryMuscles }
                    if let cat = RoutineClassifier.classify(primaryMusclesPerExercise: perExercise) {
                        regions[r.id] = cat
                    }
                }
                routineRegions = regions
            }
        }
        .enableInjection()   // Inject: recarga en caliente (no-op en Release)
    }

    // MARK: - List

    private var rowInsets: EdgeInsets {
        EdgeInsets(top: 0, leading: LiquidSpace.s600, bottom: 0, trailing: LiquidSpace.s600)
    }

    private var listBody: some View {
        List {
            Section {
                whenSection.plainRow(rowInsets)
                routineSection.plainRow(rowInsets)
                capturedSection.plainRow(rowInsets)
            }
            ForEach(Array(groups.enumerated()), id: \.element.id) { gi, _ in
                exerciseSection(gi)
            }
            if workSetCount == 0 {
                Section { validationNote("A workout needs at least one set.").plainRow(rowInsets) }
            } else if !repsValid {
                Section { validationNote("Check the weight and reps.").plainRow(rowInsets) }
            }
            Section { notesSection.plainRow(rowInsets) }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 0)
    }

    private func exerciseSection(_ gi: Int) -> some View {
        let type = exercisesByID[groups[gi].exerciseId]?.type ?? .weightReps
        return Section {
            ForEach(Array(groups[gi].sets.enumerated()), id: \.element.id) { si, _ in
                setRow(gi: gi, si: si, type: type).plainRow(rowInsets)
            }
            .onDelete { offsets in removeSets(gi: gi, offsets) }
            addSetRow(gi).plainRow(rowInsets)
        } header: {
            exerciseHeader(gi).textCase(nil)
        }
    }

    // MARK: - Sections

    private var whenSection: some View {
        HStack {
            Text("When").liquidLabel().foregroundStyle(LiquidColor.tinta500)
            Spacer(minLength: 12)
            DatePicker("", selection: $startDate, displayedComponents: [.date, .hourAndMinute])
                .labelsHidden().tint(LiquidColor.tinta900)
        }
    }

    private var routineSection: some View {
        HStack {
            Text("Routine").liquidLabel().foregroundStyle(LiquidColor.tinta500)
            Spacer(minLength: 12)
            Button { showRoutineMenu = true } label: {
                HStack(spacing: LiquidSpace.s150) {
                    // El punto vive solo junto a la rutina YA elegida (Alcance punto 5) — el picker
                    // (`LiquidMenuItem`) es un componente general de la app, sin swatch por opción.
                    if let region = routineId.flatMap({ routineRegions[$0] }) {
                        EntrenarFamilyDot(region.tint())
                    }
                    Text(routineLabel)
                        .font(LiquidType.tituloGemela)
                        .foregroundStyle(LiquidColor.tinta900)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(LiquidType.iconSF(size: 12))
                        .foregroundStyle(LiquidColor.tinta500)
                }
            }
            .buttonStyle(.plain)
            .liquidMenu(isPresented: $showRoutineMenu, items:
                [LiquidMenuItem(String(localized: "No routine"),
                               systemImage: routineId == nil ? "checkmark" : nil) { routineId = nil }]
                + routines.map { r in
                    LiquidMenuItem(r.name, systemImage: routineId == r.id ? "checkmark" : nil) { routineId = r.id }
                })
        }
    }

    /// The strap's captured truth — shown so the user knows it exists and why it isn't editable.
    @ViewBuilder
    private var capturedSection: some View {
        if session.strain != nil || session.avgHr != nil {
            VStack(alignment: .leading, spacing: LiquidSpace.s150) {
                Text("From your body").liquidLabel().foregroundStyle(LiquidColor.tinta500)
                HStack(spacing: LiquidSpace.seccionAire) {
                    if let strain = session.strain {
                        readonlyStat(StrengthHistoryFormat.strain(strain), label: "Effort")
                    }
                    if let hr = session.avgHr {
                        readonlyStat("\(hr)", unit: "bpm", label: "Avg HR")
                    }
                }
                Text("Effort and heart rate were measured during the session. They can't be edited.")
                    .font(LiquidType.captionLectura)
                    .foregroundStyle(LiquidColor.tinta500)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(LiquidSpace.handoff14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidGlass(.superficieSolida)
        }
    }

    private func readonlyStat(_ value: String, unit: String? = nil, label: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s025) {
            HStack(alignment: .firstTextBaseline, spacing: LiquidSpace.s075) {
                Text(value)
                    .font(LiquidType.valorM)
                    .foregroundStyle(LiquidColor.tinta500)
                    .monospacedDigit()
                if let unit {
                    Text(unit)
                        .font(LiquidType.unidad)
                        .foregroundStyle(LiquidColor.tinta500)
                }
            }
            Text(label).liquidLabel().foregroundStyle(LiquidColor.tinta500)
        }
        .accessibilityElement(children: .combine)
    }

    private func exerciseHeader(_ gi: Int) -> some View {
        Button { reassignGroup = ReassignTarget(index: gi) } label: {
            HStack(spacing: LiquidSpace.s150) {
                Text(exerciseName(groups[gi].exerciseId))
                    .font(LiquidType.titulo)
                    .foregroundStyle(LiquidColor.tinta900)
                CenitIcon.disclosure.image
                    .font(LiquidType.iconSF(size: 12))
                    .foregroundStyle(LiquidColor.tinta500)
                Spacer(minLength: 0)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, LiquidSpace.s200)
        .accessibilityLabel(Text(exerciseName(groups[gi].exerciseId)))
        .accessibilityHint(Text("Change exercise"))
    }

    private func addSetRow(_ gi: Int) -> some View {
        Button { addSet(gi) } label: {
            HStack(spacing: LiquidSpace.s150) {
                CenitIcon.add.image.font(LiquidType.iconSF(size: 12))
                Text("Add set").font(LiquidType.tituloFila)
            }
            .foregroundStyle(LiquidColor.tinta700)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Adds a set to this exercise"))
    }

    private func setRow(gi: Int, si: Int, type: ExerciseType) -> some View {
        HStack(spacing: LiquidSpace.s250) {
            Text("Set \(si + 1)")
                .font(LiquidType.cuerpo)
                .foregroundStyle(LiquidColor.tinta500)
                .frame(minWidth: 48, alignment: .leading)
            Spacer(minLength: 8)
            switch type {
            case .weightReps, .bodyweight:
                if type == .bodyweight {
                    Text("+")
                        .font(.system(size: lectura))
                        .foregroundStyle(LiquidColor.tinta500)
                }
                numberField(.init(g: gi, s: si, field: .weight), isInt: false)
                Text("×")
                    .font(.system(size: lectura))
                    .foregroundStyle(LiquidColor.tinta500)
                numberField(.init(g: gi, s: si, field: .reps), isInt: true)
            case .time, .distance:
                Text(StrengthHistoryFormat.setLine(setEntrySnapshot(gi, si, type: type), system: system))
                    .font(LiquidType.valorS)
                    .foregroundStyle(LiquidColor.tinta700)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, LiquidSpace.s125)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(setAccessibilityLabel(gi: gi, si: si, type: type)))
    }

    /// An editable numeric cell — the proven `LiveStrengthSheet` pattern: a faint underline you fill, with
    /// a transient text buffer so a half-typed entry isn't fought, and the model updated on each valid parse.
    private func numberField(_ ref: CellRef, isInt: Bool) -> some View {
        let value = ref.field == .weight ? displayWeight(groups[ref.g].sets[ref.s].weightKg)
                                         : Double(groups[ref.g].sets[ref.s].reps)
        let text = Binding<String>(
            get: { buffers[ref] ?? formatCell(value, isInt: isInt) },
            set: { raw in
                buffers[ref] = raw
                guard let v = Self.parseDouble(raw) else { return }
                if ref.field == .weight { groups[ref.g].sets[ref.s].weightKg = max(0, storedKg(fromDisplay: v)) }
                else { groups[ref.g].sets[ref.s].reps = max(0, Int(v.rounded())) }
            })
        // Cromo compartido (2026-07-19): celda con subrayado vía `setCellChrome`; el TextField
        // vive en `LiquidCampoTexto` (FER-339) sin superficie de vidrio.
        return LiquidCampoTexto(
            nil,
            texto: text,
            placeholder: "",
            teclado: isInt ? LiquidCampoTeclado.numberPad : LiquidCampoTeclado.decimalPad,
            a11y: "",
            conSuperficie: false,
            tipografia: LiquidType.valorM)
            .focused($focused, equals: ref)
            .setCellChrome(width: 64, focused: focused == ref)
            .onChange(of: focused) { _, now in if now != ref { buffers[ref] = nil } }   // drop buffer on blur
    }

    private var notesSection: some View {
        LiquidCampoTexto(
            String(localized: "Notes"),
            texto: $notes,
            placeholder: String(localized: "Add a note (optional)"),
            a11y: String(localized: "Notes"),
            eje: .vertical,
            limiteLineas: 1...5,
            conSuperficie: false,
            tipografia: .system(size: LiquidType.lecturaHojaBase))
    }

    private func validationNote(_ key: LocalizedStringKey) -> some View {
        HStack(spacing: LiquidSpace.s150) {
            Image(systemName: "exclamationmark.triangle")
                .font(LiquidType.iconSF(size: 12))
            Text(key).font(LiquidType.captionLectura)
        }
        .foregroundStyle(LiquidColor.atencionTexto)
    }

    // MARK: - Derived

    private var routineLabel: String {
        routineId.flatMap { id in routines.first { $0.id == id }?.name } ?? String(localized: "No routine")
    }

    private func exerciseName(_ id: String) -> String {
        exercisesByID[id].map(StrengthDisplay.name) ?? String(localized: "Exercise")
    }

    private var repsValid: Bool {
        for g in groups {
            let type = exercisesByID[g.exerciseId]?.type ?? .weightReps
            if type == .weightReps || type == .bodyweight, g.sets.contains(where: { $0.reps < 1 }) {
                return false
            }
        }
        return true
    }

    private var workSetCount: Int { groups.reduce(0) { $0 + $1.sets.count } }

    private var currentSnapshot: Snapshot {
        Snapshot(startTs: Int(startDate.timeIntervalSince1970), routineId: routineId,
                 notes: notes, groups: groups)
    }
    private var isDirty: Bool { currentSnapshot != original }
    private var canSave: Bool { isDirty && workSetCount >= 1 && repsValid }

    // MARK: - Mutations

    private func addSet(_ gi: Int) {
        let template = groups[gi].sets.last
        groups[gi].sets.append(EditSet(new: groups[gi].sets.last?.ts ?? originalStartTs, template: template))
    }

    private func removeSets(gi: Int, _ offsets: IndexSet) {
        guard groups.indices.contains(gi) else { return }
        groups[gi].sets.remove(atOffsets: offsets)
        if groups[gi].sets.isEmpty { groups.remove(at: gi) }   // an emptied exercise drops out
    }

    private func reassign(group gi: Int, to ex: Exercise) {
        guard groups.indices.contains(gi) else { return }
        groups[gi].exerciseId = ex.id
        exercisesByID[ex.id] = ex
    }

    // MARK: - Cancel / save

    private func cancel() {
        if isDirty { showDiscard = true } else { dismiss() }
    }

    private func save() {
        let newStart = Int(startDate.timeIntervalSince1970)
        let delta = newStart - originalStartTs
        // id / deviceId / strain / avgHr ride through unchanged — y con ellos `programWeek`/`deload`
        // (ola 1 · E10): editar una sesión NUNCA la saca de la semana en la que se hizo. Copiar la fila
        // entera, en vez de reconstruirla campo por campo, es exactamente lo que garantiza que un campo
        // nuevo no se pierda al editar sin que nadie se acuerde de este archivo.
        var updated = session
        updated.startTs = newStart
        updated.endTs = originalEndTs.map { $0 + delta }   // preserve duration
        updated.routineId = routineId
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.notes = trimmed.isEmpty ? nil : trimmed

        var out: [SetEntry] = []
        var pos = 0
        for g in groups {
            let type = exercisesByID[g.exerciseId]?.type ?? .weightReps
            let usesWeightReps = (type == .weightReps || type == .bodyweight)
            for s in g.sets {
                out.append(s.toSetEntry(sessionId: session.id, exerciseId: g.exerciseId, position: pos,
                                        usesWeightReps: usesWeightReps))
                pos += 1
            }
        }
        for var s in otherSets { s.position = pos; out.append(s); pos += 1 }   // preserve warm-ups etc.

        Task {
            do {
                try await repo.updateSession(updated, sets: out)
                await onSaved()
                dismiss()
            } catch {
                saveError = true
            }
        }
    }

    // MARK: - Unit + format helpers (mirror LiveStrengthSheet)

    private func displayWeight(_ kg: Double) -> Double {
        system == .imperial ? UnitFormatter.kgToPounds(kg) : kg
    }
    private func storedKg(fromDisplay shown: Double) -> Double {
        system == .imperial ? UnitFormatter.poundsToKg(shown) : shown
    }

    /// 2026-07-19: era una CUARTA copia del formateador de peso, con la misma deriva que las otras tres
    /// — conservaba el decimal en imperial, así que la misma serie se leía «181.9 lb» aquí y «182 lb» al
    /// editar la rutina o al entrenarla. Enruta por `StrengthDisplay`, la única fuente de la regla.
    private func formatCell(_ v: Double, isInt: Bool) -> String {
        if isInt { return "\(Int(v.rounded()))" }
        return StrengthDisplay.displayNumber(v, system: system)
    }

    private static func parseDouble(_ raw: String) -> Double? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        return trimmed.isEmpty ? nil : Double(trimmed)
    }

    /// A `SetEntry` snapshot for read-only time/distance display (the editor doesn't type those).
    private func setEntrySnapshot(_ gi: Int, _ si: Int, type: ExerciseType) -> SetEntry {
        let s = groups[gi].sets[si]
        return SetEntry(id: s.id, sessionId: session.id, exerciseId: groups[gi].exerciseId, position: si,
                        kind: .work, weightKg: nil, reps: nil, timeS: s.timeS, distanceM: s.distanceM,
                        done: true, ts: s.ts)
    }

    private func setAccessibilityLabel(gi: Int, si: Int, type: ExerciseType) -> String {
        let s = groups[gi].sets[si]
        switch type {
        case .weightReps, .bodyweight:
            return String(localized: "Set \(si + 1), \(StrengthDisplay.weight(s.weightKg, system: system)) by \(s.reps) reps, editable")
        case .time, .distance:
            return String(localized: "Set \(si + 1)")
        }
    }
}

// MARK: - Working-copy models

/// An editable exercise group: a (mutable) exercise id and its ordered work sets.
private struct EditGroup: Identifiable, Equatable {
    let id = UUID()
    var exerciseId: String
    var sets: [EditSet]
}

/// One editable work set. Keeps the original set id (so links/PRs stay stable); a fresh set gets a new id.
/// Not `private`: `toSetEntry(...)` is the exact reconstruction `save()` runs, exposed at module scope
/// (like `RoutineSetEditing`) so `CenitUnitTests` can drive it without a SwiftUI harness (FER-172).
struct EditSet: Identifiable, Equatable {
    let id: String
    var weightKg: Double
    var reps: Int
    var timeS: Double?
    var distanceM: Double?
    let ts: Int
    /// The real rest that followed this set (FER-167), carried through untouched so editing a session
    /// doesn't silently erase a measurement the editor never shows a control for.
    var restTakenS: Int?
    /// Perceived effort captured by the live session (FER-930). The editor shows no RPE control, so
    /// this rides through untouched on save — same class of bug as `restTakenS`, fixed in FER-172:
    /// `save()` used to reconstruct every `SetEntry` from scratch, and `EditSet` never carried `rpe` in
    /// the first place, so it silently dropped to `nil` on every edit.
    var rpe: Double?
    /// «Las que puedas» / «bajar y seguir» (FER-327). The editor shows no control for it, so it rides
    /// through untouched — otherwise every edit promoted a drop to a standard set and fed it to
    /// progression, records and 1RM (revisión adversarial E6, H1).
    var mode: SetMode

    init(_ s: SetEntry) {
        id = s.id; weightKg = s.weightKg ?? 0; reps = s.reps ?? 0
        timeS = s.timeS; distanceM = s.distanceM; ts = s.ts
        restTakenS = s.restTakenS; rpe = s.rpe; mode = s.mode
    }
    init(new ts: Int, template: EditSet?) {
        id = UUID().uuidString
        weightKg = template?.weightKg ?? 0
        reps = template?.reps ?? 8
        timeS = nil; distanceM = nil
        self.ts = ts
        restTakenS = nil   // a freshly added set never had a measured rest
        rpe = nil          // nor a reported RPE
        mode = .standard   // nor a variant: an added row is a plain work set
    }

    /// Rebuilds the persisted `SetEntry` for this row on save: only weight/reps (the editor's own
    /// controls, gated by `usesWeightReps`) come from the working copy — everything else the editor
    /// never shows a control for rides through untouched from what was loaded.
    func toSetEntry(sessionId: String, exerciseId: String, position: Int, usesWeightReps: Bool) -> SetEntry {
        SetEntry(id: id, sessionId: sessionId, exerciseId: exerciseId, position: position, kind: .work,
                 weightKg: usesWeightReps ? weightKg : nil, reps: usesWeightReps ? reps : nil,
                 timeS: timeS, distanceM: distanceM, done: true, ts: ts, rpe: rpe, restTakenS: restTakenS,
                 mode: mode)
    }
}

/// A value snapshot of everything editable — compared to detect unsaved changes.
private struct Snapshot: Equatable {
    let startTs: Int
    let routineId: String?
    let notes: String
    let groups: [EditGroup]
}

/// Identifies an editable inline cell (which set, which field).
private struct CellRef: Hashable {
    enum Field { case weight, reps }
    let g: Int
    let s: Int
    let field: Field
}

/// The exercise group whose reassignment picker is open (wraps an index so `.sheet(item:)` has identity).
private struct ReassignTarget: Identifiable {
    let id = UUID()
    let index: Int
}

private extension View {
    /// A list row that disappears into the hoja: clear background, no separator, screen-margin insets.
    func plainRow(_ insets: EdgeInsets) -> some View {
        self.listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(insets)
    }
}
#endif
