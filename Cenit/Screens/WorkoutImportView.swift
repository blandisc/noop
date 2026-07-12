#if os(iOS)
import SwiftUI
import UniformTypeIdentifiers
import StrandDesign
import StrandImport
import StrandTraining

/// Import an LLM-generated workout program (FER-496) — the «trae-tu-propio-LLM» path, mirroring Diet
/// capture (FER-371). NOOP hands out a prompt, the user runs it in their own AI with their plan, and
/// brings back a `noop.workout.v1` file; importing it creates the real routines of the strength tracker.
/// NOOP never calls the network — the user runs the LLM step.
///
/// «Instrumento diurno»: there's no measured datum here, so the screen is all-ink on warm paper; the
/// Confirm step accents each routine with its type's hue (owner decision, Jul 2026), and the rest of
/// the screen remains all-ink — `critical` on a parse error and `verdict` (green) on a just-resolved
/// exercise. The one piece the format can't carry is the catalog identity of each exercise, so unmatched
/// names get a mapping step (map to an existing exercise or create it) before the routines are written.
struct WorkoutImportView: View {

    /// Called after routines are created, so the hub can reload «Mis rutinas».
    var onComplete: () async -> Void

    @Environment(\.instrumentoTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var repo: Repository

    private enum Phase { case capture, mapping, confirm, done }

    /// The unmatched exercise name being mapped (wraps the name so `.sheet(item:)` has an `Identifiable`
    /// without a global `String` conformance). Names are deduped by normalization, so they're unique.
    private struct MappingName: Identifiable { let name: String; var id: String { name } }

    @State private var phase: Phase = .capture
    @State private var pasteText = ""
    @State private var program: WorkoutProgram?
    @State private var parseError: WorkoutProgramParseError?
    @State private var copied = false
    @State private var showFileImporter = false

    // Exercise reconciliation: the on-device catalog (seed + custom), the unmatched names that need a
    // decision, and the user's resolution per normalized name (an existing or just-created exercise).
    @State private var catalog: [Exercise] = []
    @State private var learnedAliases: [String: String] = [:]   // remembered mappings (FER-523)
    @State private var reconciler: WorkoutExerciseReconciler?   // built once at parse, reused at save
    @State private var unmatched: [String] = []
    @State private var resolution: [String: Exercise] = [:]
    @State private var autoMatched: Set<String> = []   // resolved by autoMatch (FER-794) — marked, reversible
    @State private var omitted: Set<String> = []   // normalized names the user chose not to import (FER-536)
    @State private var mappingTarget: MappingName?  // name being mapped → drives the library picker sheet
    @State private var createdCount = 0

    /// The user's weight unit (kg / lb), for the confirm-step preview only — stored weights are kg.
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    private var unitSystem: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }

    private let importer = WorkoutProgramImporter()

    var body: some View {
        ScrollView {
            Group {
                switch phase {
                case .capture: captureFlow
                case .mapping: mappingFlow
                case .confirm: if let p = program { confirmFlow(p) }
                case .done:    doneFlow
                }
            }
            .padding(NoopMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.paper.ignoresSafeArea())
        .task {
            if catalog.isEmpty {
                catalog = await repo.allExercises()
                learnedAliases = await repo.learnedExerciseAliases()   // FER-523: remembered mappings
            }
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.json]) { handleImport($0) }
        .sheet(item: $mappingTarget) { target in
            NavigationStack {
                ExerciseLibraryScreen { picks in
                    if let chosen = picks.first { resolve(target.name, with: chosen) }
                }
            }
            .instrumentoTheme(theme).environmentObject(repo).preferredColorScheme(.light)
        }
    }

    // MARK: - Capture

    private var captureFlow: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
            header("Import plan", "Bring your plan from your AI")

            step(1, "Copy the prompt and paste it into your trusted AI, along with your plan (text, photo or PDF).") {
                QuietButton(copied ? "Copied" : "Copy prompt") { copyPrompt() }
            }

            step(2, "Bring back the file it gives you: paste it or upload it.") {
                VStack(alignment: .leading, spacing: NoopMetrics.gap) {
                    pasteField
                    HStack(spacing: NoopMetrics.gap) {
                        QuietButton("Upload .json file") { showFileImporter = true }
                        QuietButton("Continue") { parse(text: pasteText) }
                            .disabled(pasteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    if let parseError { errorNote(parseError) }
                }
            }

            Text("Your routines are created on your iPhone. NOOP never connects: you run the AI step yourself.")
                .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var pasteField: some View {
        TextEditor(text: $pasteText)
            .font(StrandFont.mono)
            .foregroundStyle(theme.ink)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 96)
            .padding(NoopMetrics.cardPadding)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous)
                .strokeBorder(theme.hairlineStrong, lineWidth: 1))
            .overlay(alignment: .topLeading) {
                if pasteText.isEmpty {
                    Text("Paste the result here…")
                        .font(StrandFont.subhead).foregroundStyle(theme.inkTertiary)
                        .padding(NoopMetrics.cardPadding).allowsHitTesting(false)
                }
            }
            .accessibilityLabel("Paste your plan")
    }

    private func errorNote(_ error: WorkoutProgramParseError) -> some View {
        HStack(alignment: .top, spacing: NoopMetrics.gap) {
            Image(systemName: "exclamationmark.triangle")
                .font(StrandFont.glyph(.lead)).foregroundStyle(theme.critical)
                .accessibilityHidden(true)
            Text(message(for: error))
                .font(StrandFont.subhead).foregroundStyle(theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Mapping (the names that aren't in the catalog yet)

    private var mappingFlow: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
            header("Import plan", "\(unmatched.count) exercises to set up")
            Text("These aren't in your library. Match each one to an exercise you have, or create it.")
                .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(unmatched.enumerated()), id: \.offset) { index, name in
                    mappingRow(name)
                    if index < unmatched.count - 1 {
                        Rectangle().fill(theme.hairline).frame(height: 0.5)
                    }
                }
            }

            // A name is "settled" once it's matched OR omitted — both let you continue.
            let remaining = unmatched.filter { resolution[norm($0)] == nil && !omitted.contains(norm($0)) }.count
            QuietButton(remaining == 0 ? "Continue" : "Resolve \(remaining) more to continue") {
                phase = .confirm
            }
            .disabled(remaining != 0)
        }
    }

    private func mappingRow(_ name: String) -> some View {
        let key = norm(name)
        let resolved = resolution[key]
        let isOmitted = omitted.contains(key)
        return VStack(alignment: .leading, spacing: NoopMetrics.space2) {
            Text(verbatim: name).font(StrandFont.body)
                .foregroundStyle(isOmitted ? theme.inkTertiary : theme.ink)
            if isOmitted {
                HStack(spacing: NoopMetrics.space2) {
                    Text("Omitted").font(StrandFont.subhead).foregroundStyle(theme.inkTertiary)
                    Spacer(minLength: NoopMetrics.space2)
                    undoLink { omitted.remove(key) }
                }
                .accessibilityElement(children: .combine)
            } else if let resolved {
                let isAuto = autoMatched.contains(key)   // FER-794: pre-resolved, marked as automatic
                HStack(spacing: NoopMetrics.space2) {
                    Image(systemName: isAuto ? "sparkles" : "checkmark.circle.fill")
                        .font(StrandFont.subhead).foregroundStyle(theme.verdict)
                        .accessibilityHidden(true)
                    Group {
                        if isAuto { Text("Matched automatically · \(StrengthDisplay.name(resolved))") }
                        else { Text("Matched · \(StrengthDisplay.name(resolved))") }
                    }
                    .font(StrandFont.subhead).foregroundStyle(theme.verdict)
                    Spacer(minLength: NoopMetrics.space2)
                    undoLink { resolution[key] = nil; autoMatched.remove(key) }
                    Button { mappingTarget = MappingName(name: name) } label: {
                        Text("Change mapping").font(StrandFont.footnote).foregroundStyle(theme.inkTertiary).underline()
                    }
                    .buttonStyle(.plain)
                }
                .accessibilityElement(children: .combine)
            } else {
                let suggestions = reconciler?.suggestions(for: name) ?? []
                if !suggestions.isEmpty {
                    Text("Did you mean…").font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                    ForEach(suggestions, id: \.id) { s in
                        Button { resolve(name, with: s) } label: {
                            HStack(spacing: NoopMetrics.space2) {
                                Image(systemName: "sparkles").font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                                Text(StrengthDisplay.name(s)).font(StrandFont.subhead).foregroundStyle(theme.ink)
                                Spacer(minLength: NoopMetrics.space2)
                                Text("Use").font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
                            }
                            .padding(.vertical, NoopMetrics.space1).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(Text("Use \(StrengthDisplay.name(s)) for \(name)"))
                    }
                }
                HStack(spacing: NoopMetrics.space2) {
                    chip("Match") { mappingTarget = MappingName(name: name) }
                    chip("Create new") { createNew(name) }
                    chip("Omit") { omitted.insert(key) }
                }
            }
        }
        .padding(.vertical, NoopMetrics.gap)
    }

    /// A small underlined «Undo» link — reverts a suggestion/omit so the row goes back to unmatched.
    private func undoLink(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("Undo").font(StrandFont.footnote).foregroundStyle(theme.inkTertiary).underline()
        }
        .buttonStyle(.plain)
    }

    private func chip(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
                .padding(.horizontal, 13).padding(.vertical, 6)
                .overlay(Capsule().stroke(theme.hairlineStrong, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Confirm

    private func confirmFlow(_ program: WorkoutProgram) -> some View {
        VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Import plan").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                nameText(program.name, fallback: "Your program").font(StrandFont.title1).foregroundStyle(theme.ink)
                Text(programSummary(program)).font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
            }

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(program.routines.enumerated()), id: \.offset) { index, routine in
                    routinePreview(routine)
                    if index < program.routines.count - 1 {
                        Rectangle().fill(theme.hairline).frame(height: 0.5)
                    }
                }
            }

            QuietButton(createRoutinesTitle(program.routines.count)) { save(program) }
        }
    }

    private func routinePreview(_ routine: WorkoutRoutine) -> some View {
        let muscles = routine.exercises.compactMap { resolution[norm($0.name)]?.primaryMuscles }
        let region = RoutineClassifier.classify(primaryMusclesPerExercise: muscles)
        let accent: Color = {
            switch region {
            case .push:            return theme.dataStrain
            case .pull:            return theme.dataHrv
            case .legs, .fullBody: return theme.dataSleep
            case nil:              return theme.dataStrain
            }
        }()
        return VStack(alignment: .leading, spacing: NoopMetrics.space2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Circle().fill(accent).frame(width: 8, height: 8)
                nameText(routine.name, fallback: "Routine").font(StrandFont.body).foregroundStyle(theme.ink)
                if let tag = routine.tag {
                    Text(verbatim: "· \(tag)").font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                }
            }
            ForEach(Array(routine.exercises.enumerated()), id: \.offset) { _, ex in
                if !omitted.contains(norm(ex.name)) {   // omitted exercises aren't imported (FER-536)
                    Text(verbatim: exerciseLine(ex))
                        .font(StrandFont.footnote).foregroundStyle(theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, NoopMetrics.gap)
    }

    // MARK: - Done

    private var doneFlow: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
            VStack(alignment: .leading, spacing: NoopMetrics.gap) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 40, weight: .regular)).foregroundStyle(theme.verdict)   // token-exempt: glifo de éxito 40pt (empty token es 34)
                    .accessibilityHidden(true)
                Text(createdRoutinesTitle(createdCount)).font(StrandFont.title2).foregroundStyle(theme.ink)
                Text("They're in «My routines», ready to train.")
                    .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
            }
            QuietButton("Done") { Task { await onComplete(); dismiss() } }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Shared pieces

    private func header(_ overline: LocalizedStringKey, _ title: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(overline).instrumentoOverline().foregroundStyle(theme.inkTertiary)
            Text(title).font(StrandFont.title1).foregroundStyle(theme.ink)
        }
    }

    private func step<Action: View>(_ n: Int, _ text: LocalizedStringKey,
                                    @ViewBuilder action: () -> Action) -> some View {
        HStack(alignment: .top, spacing: NoopMetrics.gap) {
            Text("\(n)").font(StrandFont.headline).monospacedDigit().foregroundStyle(theme.inkTertiary)
            VStack(alignment: .leading, spacing: NoopMetrics.gap) {
                Text(text).font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                action()
            }
        }
    }

    /// Verbatim user content (program/routine names are the plan's words) with a localized fallback.
    private func nameText(_ value: String, fallback: LocalizedStringKey) -> Text {
        value.isEmpty ? Text(fallback) : Text(verbatim: value)
    }

    // MARK: - Reconciliation helpers

    private func norm(_ name: String) -> String { WorkoutExerciseReconciler.normalize(name) }

    /// The program's declared type for a name (first occurrence) — so a created exercise keeps it.
    private func declaredType(_ name: String) -> ExerciseType {
        let key = norm(name)
        for routine in program?.routines ?? [] {
            for ex in routine.exercises where norm(ex.name) == key { return ex.type }
        }
        return .weightReps
    }

    private func resolve(_ name: String, with exercise: Exercise) {
        let key = norm(name)
        resolution[key] = exercise
        autoMatched.remove(key)    // a user pick is no longer "automatic" (FER-794)
        omitted.remove(key)        // resolving overrides a prior omit
        mappingTarget = nil
        // The learned alias is persisted at save() (FER-536), not here, so Undo can revert cleanly.
    }

    /// «Create new» fast path: a user exercise from the LLM's name, with the type the plan declared.
    /// Saved so the muscle map / library can see it; the user can flesh it out later in the library. The
    /// learned alias for the import name is persisted at save(), not here (FER-536).
    private func createNew(_ name: String) {
        let exercise = Exercise(id: UUID().uuidString, name: name, type: declaredType(name),
                                equipment: nil, primaryMuscles: [], secondaryMuscles: [], instructions: [])
        Task {
            try? await repo.saveCustomExercise(exercise)
            catalog.append(exercise)   // keep the local catalog current without a full re-fetch
            resolution[norm(name)] = exercise
        }
    }

    // MARK: - Actions

    private func copyPrompt() {
        PlatformPasteboard.copy(WorkoutPrompt.forCurrentLocale())
        withAnimation { copied = true }
        Task {
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            withAnimation { copied = false }
        }
    }

    private func parse(text: String) { parse(data: Data(text.utf8)) }

    private func parse(data: Data) {
        do {
            let p = try importer.parse(data)
            program = p
            parseError = nil
            let r = WorkoutExerciseReconciler(known: catalog, learned: learnedAliases,
                                              aliases: ExerciseAliasTable.bundled)
            reconciler = r
            unmatched = r.unmatchedNames(in: p)
            resolution = [:]
            autoMatched = []
            // FER-794: pre-resolve what autoMatch can (content-key / derived alias / confident fuzzy)
            // and MARK it — the mapping step still shows it, reversible, before anything is imported.
            for (name, hit) in r.autoMatches(in: p) {
                let key = norm(name)
                resolution[key] = hit
                autoMatched.insert(key)
            }
            phase = unmatched.isEmpty ? .confirm : .mapping
        } catch let error as WorkoutProgramParseError {
            parseError = error
        } catch {
            parseError = .notJSON
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { parseError = .notJSON; return }
        parse(data: data)
    }

    /// Resolve every exercise to a catalog id (matched or user-resolved) and write one `Routine` per
    /// program routine, in order. Idempotent ids are fresh UUIDs — re-importing makes new routines.
    private func save(_ program: WorkoutProgram) {
        let reconciler = self.reconciler
            ?? WorkoutExerciseReconciler(known: catalog, aliases: ExerciseAliasTable.bundled)
        let now = Int(Date().timeIntervalSince1970)
        let omittedSnapshot = omitted
        let resolutionSnapshot = resolution
        Task {
            var created = 0
            for (rIndex, routine) in program.routines.enumerated() {
                let routineId = UUID().uuidString
                var slots: [RoutineExercise] = []
                for ex in routine.exercises {
                    let key = norm(ex.name)
                    if omittedSnapshot.contains(key) { continue }   // omitted → not imported (FER-536)
                    guard let exercise = reconciler.resolve(ex) ?? resolutionSnapshot[key] else { continue }
                    let hasRest = ex.restSeconds != nil
                    slots.append(RoutineExercise(
                        routineId: routineId, exerciseId: exercise.id, position: slots.count,
                        targetSets: ex.sets, targetReps: ex.reps, targetWeightKg: ex.weightKg,
                        warmupPercents: ex.warmupPercents,
                        restMode: hasRest ? .fixed : .heartRate, restSeconds: ex.restSeconds ?? 90,
                        supersetGroup: ex.supersetGroup))
                }
                guard !slots.isEmpty else { continue }
                let r = Routine(id: routineId,
                                name: routine.name.isEmpty ? String(localized: "Routine") : routine.name,
                                tag: routine.tag, createdTs: now, updatedTs: now, sortOrder: rIndex)
                try? await repo.saveRoutine(r, exercises: slots)
                created += 1
            }
            // Remember the confirmed mappings only now (FER-536) — so Undo before saving leaves no learned
            // alias behind. Omitted names are never remembered.
            for (key, ex) in resolutionSnapshot where !omittedSnapshot.contains(key) {
                await repo.saveLearnedExerciseAlias(name: key, exerciseId: ex.id)
            }
            createdCount = created
            phase = .done
        }
    }

    // MARK: - Display

    private func programSummary(_ p: WorkoutProgram) -> LocalizedStringKey {
        // Count only what will actually be imported — omitted exercises don't count (FER-536).
        let exercises = p.routines.reduce(0) { $0 + $1.exercises.filter { !omitted.contains(norm($0.name)) }.count }
        return "\(p.routines.count) routines · \(exercises) exercises"
    }

    private func exerciseLine(_ ex: WorkoutExercise) -> String {
        var parts = [ex.name]
        switch ex.type {
        case .weightReps, .bodyweight:
            if let reps = ex.reps { parts.append("\(ex.sets)×\(reps)") } else { parts.append("\(ex.sets)×") }
            if let kg = ex.weightKg { parts.append(StrengthDisplay.weight(kg, system: unitSystem)) }
            else if ex.type == .bodyweight { parts.append(String(localized: "bodyweight")) }
        case .time:
            parts.append("\(ex.sets)×")
            if let reps = ex.reps { parts.append("\(reps) s") }
        case .distance:
            parts.append("\(ex.sets)×")
        }
        return parts.joined(separator: " · ")
    }

    private func createRoutinesTitle(_ n: Int) -> LocalizedStringKey { "Create \(n) routines" }
    private func createdRoutinesTitle(_ n: Int) -> LocalizedStringKey { "Created \(n) routines" }

    // MARK: - Error copy (es-MX via the String Catalog)

    private func message(for error: WorkoutProgramParseError) -> LocalizedStringKey {
        switch error {
        case .notJSON:
            return "We couldn't read that as a plan file. Paste the full result your AI gave you, or upload the .json."
        case .unsupportedSchema:
            return "That file isn't a NOOP workout plan. Make sure you used the prompt above."
        case .unsupportedIdioma:
            return "The plan's language isn't supported: it must be Spanish or English."
        case .unsupportedUnidad:
            return "The plan's unit isn't supported: it must be kg or lb."
        case .unsupportedTipo:
            return "One of the exercises has an unsupported type. Check the file and try again."
        case .noRoutines:
            return "That plan has no routines. Check the file and try again."
        case .routineWithoutExercises:
            return "One of the routines has no exercises. Check the file and try again."
        case .exerciseWithoutName:
            return "One of the exercises has no name. Check the file and try again."
        }
    }
}
#endif
