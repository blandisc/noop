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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var repo: Repository

    fileprivate enum Phase { case capture, mapping, confirm, done }

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
    @State private var celebrate = false   // done-screen pop-in (respects Reduce Motion)
    /// M4 (decisión Fer): cerrar con el mapeo/confirmación a medias pide confirmación — antes el
    /// swipe-down tiraba todo el trabajo sin avisar.
    @State private var confirmDiscard = false
    private var midWork: Bool { phase == .mapping || phase == .confirm }

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
            .padding(CenitMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.paper.ignoresSafeArea())
        .overlay(alignment: .topTrailing) {
            Button {
                if midWork { confirmDiscard = true } else { dismiss() }
            } label: {
                StrandIcon.close.image.font(StrandFont.glyph(.inline, weight: .semibold))
                    .foregroundStyle(theme.inkSecondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Close"))
            .padding(.trailing, CenitMetrics.space2).padding(.top, CenitMetrics.space2)
        }
        .interactiveDismissDisabled(midWork)
        .instrumentoConfirm(
            isPresented: $confirmDiscard,
            title: String(localized: "Discard this import?"),
            context: String(localized: "IMPORT · IN PROGRESS"),
            message: String(localized: "The mapping you've done so far won't be saved."),
            actions: [
                .init(String(localized: "Keep importing"), role: .primary),
                .init(String(localized: "Discard import"), role: .destructive) { dismiss() }
            ]
        )
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
        VStack(alignment: .leading, spacing: CenitMetrics.sectionGap) {
            stepper(current: .capture)
            header("Import plan", "Bring your plan from your AI")

            step(1, "Copy the prompt and paste it into your trusted AI, along with your plan (text, photo or PDF).") {
                emberButton(copied ? "Copied" : "Copy prompt") { copyPrompt() }
            }

            step(2, "Bring back the file it gives you: paste it or upload it.") {
                VStack(alignment: .leading, spacing: CenitMetrics.gap) {
                    pasteField
                    HStack(spacing: CenitMetrics.gap) {
                        QuietButton("Upload .json file") { showFileImporter = true }
                        QuietButton("Continue") { parse(text: pasteText) }
                            .disabled(pasteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    if let parseError { errorNote(parseError) }
                }
            }

            privacyNote
        }
    }

    /// Handoff: la promesa offline como tarjeta con barra verde — es la garantía del flujo, no letra chica.
    private var privacyNote: some View {
        HStack(alignment: .top, spacing: CenitMetrics.gap) {
            RoundedRectangle(cornerRadius: 1.5)  // token-exempt: geometría de la barra de acento (3pt de ancho)
                .fill(theme.verdict).frame(width: 3)
            Text("Your routines are created on your iPhone. Cénit never connects: you run the AI step yourself.")
                .font(StrandFont.footnote).foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(CenitMetrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous))
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }

    /// Handoff: acción de acento dentro de un paso (ember lleno) — distinta del CTA canónico de tinta.
    private func emberButton(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        // Compacto (abraza su contenido), pero en la MISMA voz del CTA del módulo (Grotesk 15/bold/0.3)
        // — antes hablaba SF headline (auditoría D).
        Button(action: action) {
            Text(title)
                .font(InstrumentoType.grotesk(15, weight: .bold)).tracking(0.3).foregroundStyle(theme.paperHi)
                .padding(.horizontal, 18).padding(.vertical, 10)
                .background(theme.dataStrain, in: RoundedRectangle(cornerRadius: CenitMetrics.controlRadius, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var pasteField: some View {
        TextEditor(text: $pasteText)
            .font(StrandFont.mono)
            .foregroundStyle(theme.ink)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 96)
            .padding(CenitMetrics.cardPadding)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous)
                .strokeBorder(theme.hairlineStrong, lineWidth: 1))
            .overlay(alignment: .topLeading) {
                if pasteText.isEmpty {
                    Text("Paste the result here…")
                        .font(StrandFont.subhead).foregroundStyle(theme.inkTertiary)
                        .padding(CenitMetrics.cardPadding).allowsHitTesting(false)
                }
            }
            .accessibilityLabel("Paste your plan")
    }

    private func errorNote(_ error: WorkoutProgramParseError) -> some View {
        HStack(alignment: .top, spacing: CenitMetrics.gap) {
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
        VStack(alignment: .leading, spacing: CenitMetrics.sectionGap) {
            stepper(current: .mapping)
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
        return VStack(alignment: .leading, spacing: CenitMetrics.space2) {
            Text(verbatim: name).font(StrandFont.body)
                .foregroundStyle(isOmitted ? theme.inkTertiary : theme.ink)
            if isOmitted {
                HStack(spacing: CenitMetrics.space2) {
                    Text("Omitted").font(StrandFont.subhead).foregroundStyle(theme.inkTertiary)
                    Spacer(minLength: CenitMetrics.space2)
                    undoLink { omitted.remove(key) }
                }
                .accessibilityElement(children: .combine)
            } else if let resolved {
                let isAuto = autoMatched.contains(key)   // FER-794: pre-resolved, marked as automatic
                HStack(spacing: CenitMetrics.space2) {
                    // Handoff: el match como pill verde lavada — el veredicto se lee de un vistazo.
                    HStack(spacing: 5) {
                        Image(systemName: isAuto ? "sparkles" : "checkmark.circle.fill")
                            .font(StrandFont.caption)
                            .accessibilityHidden(true)
                        Group {
                            if isAuto { Text("Matched automatically · \(StrengthDisplay.name(resolved))") }
                            else { Text("Matched · \(StrengthDisplay.name(resolved))") }
                        }
                        .font(StrandFont.caption.weight(.semibold))
                        .lineLimit(1).minimumScaleFactor(0.85)
                    }
                    .foregroundStyle(theme.verdict)
                    .padding(.horizontal, 9).padding(.vertical, 3)
                    .background(theme.verdict.opacity(StrandOpacity.tintFill), in: RoundedRectangle(cornerRadius: CenitMetrics.chipRadius, style: .continuous))
                    Spacer(minLength: CenitMetrics.space2)
                    undoLink { resolution[key] = nil; autoMatched.remove(key) }
                }
                .accessibilityElement(children: .combine)
                Button { mappingTarget = MappingName(name: name) } label: {
                    Text("Change mapping").font(StrandFont.footnote).foregroundStyle(theme.inkTertiary).underline()
                }
                .buttonStyle(.plain)
            } else {
                let suggestions = reconciler?.suggestions(for: name) ?? []
                if !suggestions.isEmpty {
                    Text("Did you mean…").font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                    ForEach(suggestions, id: \.id) { s in
                        // Handoff: la sugerencia como tarjeta — sparkle ember, nombre, y «Usar» como botón oscuro.
                        Button { resolve(name, with: s) } label: {
                            HStack(spacing: CenitMetrics.space2) {
                                Image(systemName: "sparkles").font(StrandFont.caption).foregroundStyle(theme.dataStrain)
                                Text(StrengthDisplay.name(s)).font(StrandFont.subhead.weight(.medium)).foregroundStyle(theme.ink)
                                Spacer(minLength: CenitMetrics.space2)
                                Text("Use").font(StrandFont.caption.weight(.bold)).foregroundStyle(theme.paperHi)
                                    .padding(.horizontal, 11).padding(.vertical, 4)
                                    .background(theme.ink, in: RoundedRectangle(cornerRadius: CenitMetrics.chipRadius, style: .continuous))
                            }
                            .padding(.horizontal, 10).padding(.vertical, 8)
                            .background(theme.surface, in: RoundedRectangle(cornerRadius: CenitMetrics.insetRadius, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: CenitMetrics.insetRadius, style: .continuous)
                                .strokeBorder(theme.hairline, lineWidth: 1))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(Text("Use \(StrengthDisplay.name(s)) for \(name)"))
                    }
                }
                HStack(spacing: CenitMetrics.space2) {
                    chip("Match") { mappingTarget = MappingName(name: name) }
                    chip("Create new") { createNew(name) }
                    chip("Omit") { omitted.insert(key) }
                }
            }
        }
        .padding(.vertical, CenitMetrics.gap)
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
        VStack(alignment: .leading, spacing: CenitMetrics.sectionGap) {
            stepper(current: .confirm)
            VStack(alignment: .leading, spacing: 4) {
                Text("Import plan").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                nameText(program.name, fallback: "Your program").font(InstrumentoType.groteskScreenTitle).tracking(InstrumentoType.groteskScreenTitleTracking).foregroundStyle(theme.ink)
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

            StrandCTAButton(createRoutinesTitle(program.routines.count)) { save(program) }
        }
    }

    private func routinePreview(_ routine: WorkoutRoutine) -> some View {
        // Resolver con la misma precedencia que save(): reconciliador (matches directos/aliases) y
        // luego las decisiones manuales — si no, las rutinas con puros matches directos no clasifican.
        let muscles = routine.exercises.compactMap { ex in
            (reconciler?.resolve(ex) ?? resolution[norm(ex.name)])?.primaryMuscles
        }
        let region = RoutineClassifier.classify(primaryMusclesPerExercise: muscles)
        let accent = region.tint(theme)
        // Handoff: glyph de familia de movimiento en chip lavado con borde del tinte — espejo de Tu Plan.
        return HStack(alignment: .top, spacing: CenitMetrics.gap) {
            RoutineRegionGlyph(glyphKind(region), tint: accent)
                .frame(width: 22, height: 22)
                .frame(width: 40, height: 40)
                .background(accent.opacity(StrandOpacity.tintFill),
                            in: RoundedRectangle(cornerRadius: CenitMetrics.insetRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: CenitMetrics.insetRadius, style: .continuous)
                    .strokeBorder(accent, lineWidth: 1.5))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: CenitMetrics.space2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    nameText(routine.name, fallback: "Routine")
                        .font(StrandFont.body.weight(.semibold)).foregroundStyle(theme.ink)
                    if let tag = routine.tag {
                        Text(verbatim: "· \(tag)").font(StrandFont.footnote).foregroundStyle(accent)
                    }
                }
                ForEach(Array(routine.exercises.enumerated()), id: \.offset) { _, ex in
                    if !omitted.contains(norm(ex.name)) {   // omitted exercises aren't imported (FER-536)
                        Text(verbatim: exerciseLine(ex))
                            .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(.vertical, CenitMetrics.gap)
    }

    private func glyphKind(_ region: RoutineRegion?) -> RoutineGlyphKind {
        switch region {
        case .push: return .push
        case .pull: return .pull
        case .legs: return .legs
        case .fullBody, .none: return .fullBody
        }
    }

    // MARK: - Done

    /// Handoff: el cierre celebratorio — a diferencia de los pasos de trabajo, aquí el contenido se
    /// centra y respira. Un solo color (verdict verde), un solo gesto (el sello aparece con un pop
    /// suave). Sin confeti: la celebración a la «Instrumento» es espacio + un verde honesto.
    private var doneFlow: some View {
        VStack(spacing: 0) {
            stepper(current: .done)
            Spacer(minLength: CenitMetrics.sectionGap)

            VStack(spacing: CenitMetrics.sectionGap) {
                ZStack {
                    Circle().fill(theme.verdict.opacity(StrandOpacity.tintFill)).frame(width: 116, height: 116)
                    Image(systemName: "checkmark")
                        .font(.system(size: 44, weight: .semibold)).foregroundStyle(theme.verdict)  // token-exempt: glifo héroe del cierre (44pt, pareado al círculo de 116)
                }
                .scaleEffect(celebrate ? 1 : 0.72)
                .opacity(celebrate ? 1 : 0)
                .accessibilityHidden(true)

                VStack(spacing: CenitMetrics.space2) {
                    Text(createdRoutinesTitle(createdCount))
                        .font(InstrumentoType.groteskScreenTitle).tracking(InstrumentoType.groteskScreenTitleTracking).foregroundStyle(theme.ink)
                        .multilineTextAlignment(.center)
                    Text("They're in «My routines», ready to train.")
                        .font(StrandFont.body).foregroundStyle(theme.inkSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .opacity(celebrate ? 1 : 0)
            }

            Spacer(minLength: CenitMetrics.sectionGap)
            StrandCTAButton("Done") { Task { await onComplete(); dismiss() } }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 520)
        .onAppear {
            guard !celebrate else { return }
            if reduceMotion { celebrate = true }
            else { withAnimation(StrandMotion.hero.delay(0.05)) { celebrate = true } }
        }
    }

    // MARK: - Shared pieces

    /// 4-step progress strip: Capture → Map → Confirm → Done. Current + past steps use the strain/ember
    /// accent; future steps stay hairline. Labels dim except the active step.
    private func stepper(current: Phase) -> some View {
        let labels: [LocalizedStringKey] = ["Capture", "Map", "Confirm", "Done"]
        let currentIndex = phaseIndex(current)
        return VStack(alignment: .leading, spacing: CenitMetrics.space2) {
            HStack(spacing: CenitMetrics.space2) {
                ForEach(0..<labels.count, id: \.self) { i in
                    Capsule()
                        .fill(i <= currentIndex ? theme.dataStrain : theme.hairline)
                        .frame(height: 3)
                        .frame(maxWidth: .infinity)
                }
            }
            HStack(spacing: CenitMetrics.space2) {
                ForEach(0..<labels.count, id: \.self) { i in
                    Text(labels[i])
                        .font(StrandFont.footnote)
                        .foregroundStyle(i == currentIndex ? theme.ink : theme.inkTertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Step \(currentIndex + 1) of 4"))
    }

    private func phaseIndex(_ phase: Phase) -> Int {
        switch phase {
        case .capture: return 0
        case .mapping: return 1
        case .confirm: return 2
        case .done:    return 3
        }
    }

    private func header(_ overline: LocalizedStringKey, _ title: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(overline).instrumentoOverline().foregroundStyle(theme.inkTertiary)
            Text(title).font(InstrumentoType.groteskScreenTitle).tracking(InstrumentoType.groteskScreenTitleTracking).foregroundStyle(theme.ink)
        }
    }

    private func step<Action: View>(_ n: Int, _ text: LocalizedStringKey,
                                    @ViewBuilder action: () -> Action) -> some View {
        HStack(alignment: .top, spacing: CenitMetrics.gap) {
            Text("\(n)").font(StrandFont.subhead.weight(.bold)).monospacedDigit()
                .foregroundStyle(theme.paperHi)
                .frame(width: 26, height: 26)
                .background(Circle().fill(theme.dataStrain))
            VStack(alignment: .leading, spacing: CenitMetrics.gap) {
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
            return "That file isn't a Cénit workout plan. Make sure you used the prompt above."
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

// MARK: - Previews (FER-946 — canvas del rediseño; datos espejo del handoff «Importar Plan»)

#if DEBUG
extension WorkoutImportView {

    /// Canvas-only: freeze the view at a phase with seeded state, so each step renders without
    /// driving the real flow. The live path (init(onComplete:)) is untouched.
    fileprivate init(previewPhase: Phase,
                     program: WorkoutProgram?,
                     pasteText: String = "",
                     unmatched: [String] = [],
                     resolution: [String: Exercise] = [:],
                     autoMatched: Set<String> = [],
                     omitted: Set<String> = [],
                     createdCount: Int = 0) {
        self.onComplete = {}
        _phase = State(initialValue: previewPhase)
        _program = State(initialValue: program)
        _pasteText = State(initialValue: pasteText)
        _catalog = State(initialValue: ExerciseCatalog.all)
        _reconciler = State(initialValue: WorkoutExerciseReconciler(
            known: ExerciseCatalog.all, aliases: ExerciseAliasTable.bundled))
        _unmatched = State(initialValue: unmatched)
        _resolution = State(initialValue: resolution)
        _autoMatched = State(initialValue: autoMatched)
        _omitted = State(initialValue: omitted)
        _createdCount = State(initialValue: createdCount)
    }

    /// El plan del handoff: «Bloque de fuerza 5×5» — Empuje A · Tirón A · Pierna.
    fileprivate static let previewProgram = WorkoutProgram(
        language: .es, name: "Bloque de fuerza 5×5", routines: [
            WorkoutRoutine(name: "Empuje A", tag: "Lun", exercises: [
                WorkoutExercise(name: "Press banca con barra", sets: 4, reps: 6, weightKg: 82.5),
                WorkoutExercise(name: "Press militar con barra", sets: 4, reps: 8, weightKg: 45),
                WorkoutExercise(name: "Contractor de pecho (máquina)", sets: 3, reps: 12),
                WorkoutExercise(name: "Elevaciones laterales", sets: 3, reps: 15, weightKg: 10),
            ]),
            WorkoutRoutine(name: "Tirón A", tag: "Mié", exercises: [
                WorkoutExercise(name: "Peso muerto", sets: 3, reps: 5, weightKg: 120),
                WorkoutExercise(name: "Remo con barra", sets: 4, reps: 8, weightKg: 70),
                WorkoutExercise(name: "Jalón al pecho", sets: 3, reps: 10, weightKg: 60),
                WorkoutExercise(name: "Curl con barra", sets: 3, reps: 12, weightKg: 30),
            ]),
            WorkoutRoutine(name: "Pierna", tag: "Vie", exercises: [
                WorkoutExercise(name: "Sentadilla con barra", sets: 4, reps: 6, weightKg: 100),
                WorkoutExercise(name: "Prensa", sets: 3, reps: 10, weightKg: 180),
                WorkoutExercise(name: "Curl femoral", sets: 3, reps: 12, weightKg: 40),
                WorkoutExercise(name: "Gemelos de pie", sets: 4, reps: 15, weightKg: 80),
            ]),
        ])

    fileprivate static func previewCapture() -> WorkoutImportView {
        WorkoutImportView(previewPhase: .capture, program: nil)
    }

    /// Mapping con los tres estados del handoff: auto-match ✦, sin match (sugerencia + chips), omitido.
    fileprivate static func previewMapping() -> WorkoutImportView {
        let r = WorkoutExerciseReconciler(known: ExerciseCatalog.all, aliases: ExerciseAliasTable.bundled)
        var resolution: [String: Exercise] = [:]
        var auto: Set<String> = []
        let autoName = "Press de banca plano"
        if let hit = r.suggestions(for: autoName).first {
            let key = WorkoutExerciseReconciler.normalize(autoName)
            resolution[key] = hit
            auto.insert(key)
        }
        return WorkoutImportView(
            previewPhase: .mapping, program: previewProgram,
            unmatched: [autoName, "Aperturas en pec-deck", "Cardio 20 min · caminadora"],
            resolution: resolution, autoMatched: auto,
            omitted: [WorkoutExerciseReconciler.normalize("Cardio 20 min · caminadora")])
    }

    fileprivate static func previewConfirm() -> WorkoutImportView {
        WorkoutImportView(previewPhase: .confirm, program: previewProgram)
    }

    fileprivate static func previewDone() -> WorkoutImportView {
        WorkoutImportView(previewPhase: .done, program: previewProgram, createdCount: 3)
    }
}

@MainActor
private func importPreview(_ view: WorkoutImportView) -> some View {
    view
        .environmentObject(Repository(deviceId: "preview"))
        .preferredColorScheme(.light)
        .environment(\.locale, Locale(identifier: "es"))   // canvas en es-MX; quitar para ver el copy en inglés
}

#Preview("1 · Captura") { importPreview(.previewCapture()) }
#Preview("2 · Mapear") { importPreview(.previewMapping()) }
#Preview("3 · Confirmar") { importPreview(.previewConfirm()) }
#Preview("4 · Listo") { importPreview(.previewDone()) }
#endif
#endif
