#if os(iOS)
import SwiftUI
import UniformTypeIdentifiers
import CenitDesign
import StrandAnalytics
import StrandImport
import StrandTraining

/// Four-step Strong / Hevy / Cénit CSV history import (FER-333 · E9). Self-contained sheet;
/// callers present it and optionally wire history / «Arm your week» exits.
struct StrengthHistoryImportSheet: View {

    var onComplete: () async -> Void
    var onOpenHistory: (() -> Void)? = nil
    var onArmWeek: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var repo: Repository

    fileprivate enum Phase {
        case archivo, leyendo, revisar, resolver, guardando, listo
    }

    private struct MappingName: Identifiable {
        let name: String
        var id: String { name }
    }

    @State private var phase: Phase = .archivo
    @State private var showFileImporter = false
    @State private var parseErrorKey: String?
    @State private var fileData: Data?
    @State private var history: StrengthCSVImporter.ImportedStrengthHistory?
    @State private var dialectLabel = ""
    @State private var needsWeightUnit = false
    @State private var weightUnit: WorkoutWeightUnit = .kg
    @State private var maxWeightRaw: Double?
    @State private var existingIds: Set<String> = []
    @State private var forcedDuplicateIds: Set<String> = []
    @State private var duplicatesExpanded = false

    @State private var catalog: [Exercise] = []
    @State private var learnedAliases: [String: String] = [:]
    @State private var reconciler: WorkoutExerciseReconciler?
    @State private var unresolved: [UnresolvedName] = []
    @State private var resolution: [String: Exercise] = [:]
    @State private var autoMatched: Set<String> = []
    @State private var omitted: Set<String> = []
    @State private var mappingTarget: MappingName?
    @State private var creationTarget: MappingName?

    @State private var confirmDiscard = false
    @State private var saveError = false
    @State private var savedSessionCount = 0
    @State private var loadCount = 0
    @State private var leftOutDuplicateCount = 0
    @State private var readTask: Task<Void, Never>?
    @State private var readingProgressLabel: LocalizedStringKey = "Reading…"

    private var midWork: Bool {
        phase == .revisar || phase == .resolver
    }

    private var csvTypes: [UTType] {
        var types: [UTType] = [.commaSeparatedText]
        if let csv = UTType(filenameExtension: "csv") { types.insert(csv, at: 0) }
        types.append(.plainText)
        return types
    }

    var body: some View {
        ScrollView {
            Group {
                switch phase {
                case .archivo: archivoFlow
                case .leyendo: leyendoFlow
                case .revisar: revisarFlow
                case .resolver: resolverFlow
                case .guardando: guardandoFlow
                case .listo: listoFlow
                }
            }
            .padding(LiquidSpace.s600)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .entrenarHojaFondo(tono: .neutro)
        .saveErrorToast(isPresented: $saveError)
        .overlay(alignment: .topTrailing) {
            if phase == .resolver || phase == .listo || phase == .leyendo {
                BackButton(role: .close, action: dismissImport)
                    .padding(.trailing, LiquidSpace.s200).padding(.top, LiquidSpace.s200)
                    .disabled(phase == .guardando)
            }
        }
        .interactiveDismissDisabled(midWork || phase == .guardando || phase == .leyendo)
        .edgeSwipeToExit {
            if phase != .guardando { dismissImport() }
        }
        .liquidConfirm(
            isPresented: $confirmDiscard,
            title: String(localized: "Discard this import?"),
            context: String(localized: "IMPORT · IN PROGRESS"),
            message: String(localized: "The mapping you've done so far won't be saved."),
            actions: [
                .init(String(localized: "Keep importing"), role: .primary),
                .init(String(localized: "Discard import"), role: .destructive) {
                    readTask?.cancel()
                    dismiss()
                }
            ]
        )
        .task {
            if catalog.isEmpty {
                catalog = await repo.allExercises()
                learnedAliases = await repo.learnedExerciseAliases()
            }
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: csvTypes) { handleImport($0) }
        .sheet(item: $mappingTarget) { target in
            NavigationStack {
                ExerciseLibraryScreen { picks in
                    if let chosen = picks.first { resolve(target.name, with: chosen) }
                }
            }
            .environmentObject(repo).preferredColorScheme(.light)
        }
        .sheet(item: $creationTarget) { target in
            CreateExerciseSheet(catalog: catalog, initialName: target.name) { exercise in
                createNew(target.name, as: exercise)
            }
            .environmentObject(repo).preferredColorScheme(.light)
        }
        .onChange(of: weightUnit) { _, newUnit in
            guard needsWeightUnit, let data = fileData else { return }
            retryParse(data: data, unit: newUnit)
        }
    }

    // MARK: - Step 1 · Archivo

    private var archivoFlow: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s700) {
            stepCaption(1)
            EntrenarHojaCabecera(
                titulo: String(localized: "Your history, from Strong or Hevy"),
                subtitulo: String(localized: "Import history · one file, zero network"),
                tono: .neutro, salida: .cerrar, onSalir: dismissImport)

            VStack(alignment: .leading, spacing: .zero) {
                exportHintRow(title: "Strong ›", detail: "Profile › Settings › Export data")
                Rectangle().fill(LiquidColor.vidrioBorde).frame(height: 0.5)
                exportHintRow(title: "Hevy ›", detail: "Settings › Export CSV")
            }
            .liquidGlass(.superficieSolida)

            LiquidGlassButton(String(localized: "Choose .csv file…"), variant: .primary, expands: true) {
                parseErrorKey = nil
                showFileImporter = true
            }

            if let parseErrorKey {
                LiquidAviso(
                    titulo: String(localized: "Couldn’t read the file"),
                    cuerpo: parseErrorKey,
                    tono: LiquidColor.negativo,
                    cta: String(localized: "Choose another"),
                    accion: { showFileImporter = true })
            }

            Text("Cénit recognizes which one it is by its columns. Nothing leaves your phone.")
                .font(LiquidType.caption)
                .foregroundStyle(LiquidColor.tinta500)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func exportHintRow(title: LocalizedStringKey, detail: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: LiquidSpace.s300) {
            Text(title).font(LiquidType.cuerpo.weight(.semibold)).foregroundStyle(LiquidColor.tinta900)
            Spacer(minLength: LiquidSpace.s200)
            Text(detail).font(LiquidType.caption).foregroundStyle(LiquidColor.tinta500)
                .multilineTextAlignment(.trailing)
        }
        .padding(LiquidSpace.s400)
        .frame(minHeight: LiquidControl.hitTarget, alignment: .center)
    }

    // MARK: - Progress · Leyendo / Guardando

    private var leyendoFlow: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s700) {
            stepCaption(2)
            Text(readingProgressLabel)
                .font(LiquidType.displayS)
                .tracking(LiquidType.displaySTracking)
                .foregroundStyle(LiquidColor.tinta900)
                .accessibilityAddTraits(.updatesFrequently)
            LiquidBarraProgreso(fraccion: 0.35, tono: LiquidColor.ambar, animada: true)
            LiquidGlassButton(String(localized: "Cancel"), variant: .quiet, expands: true) {
                readTask?.cancel()
                readTask = nil
                resetToArchivo()
            }
        }
    }

    private var guardandoFlow: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s700) {
            stepCaption(4)
            Text("Saving… Almost there")
                .font(LiquidType.displayS)
                .tracking(LiquidType.displaySTracking)
                .foregroundStyle(LiquidColor.tinta900)
                .accessibilityAddTraits(.updatesFrequently)
            LiquidBarraProgreso(fraccion: 0.7, tono: LiquidColor.verdePrimario, animada: true)
        }
    }

    // MARK: - Step 2 · Revisar

    private var revisarFlow: some View {
        let stats = reviewStats
        return VStack(alignment: .leading, spacing: LiquidSpace.s700) {
            stepCaption(2)
            EntrenarHojaCabecera(
                titulo: "\(stats.totalSessions)",
                subtitulo: reviewSubtitle(stats: stats),
                tono: .neutro, salida: .cerrar, onSalir: dismissImport)

            VStack(alignment: .leading, spacing: .zero) {
                reviewRow(
                    String(localized: "Recognized exercises"),
                    String(localized: "\(stats.recognized) of \(stats.uniqueNames)"))
                reviewDivider()
                Button {
                    if stats.unresolvedCount > 0 { phase = .resolver }
                } label: {
                    reviewRowContent(
                        String(localized: "Unresolved"),
                        stats.unresolvedCount > 0
                            ? String(localized: "\(stats.unresolvedCount) ›")
                            : String(localized: "0"))
                }
                .buttonStyle(.plain)
                .disabled(stats.unresolvedCount == 0)
                reviewDivider()
                reviewRow(
                    String(localized: "With effort"),
                    String(localized: "\(stats.withEffort) of \(stats.totalSessions)"))
                reviewDivider()
                duplicatesSection(stats: stats)
                reviewDivider()
                weightUnitRow
            }
            .liquidGlass(.superficieSolida)

            Text("Sessions with effort enter your load as estimated. The rest stay without load.")
                .font(LiquidType.caption)
                .foregroundStyle(LiquidColor.tinta500)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(reviewNotes(stats: stats), id: \.self) { (note: String) in
                Text(note)
                    .font(LiquidType.caption)
                    .foregroundStyle(LiquidColor.tinta500)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if stats.newCount == 0 && !needsWeightUnit {
                Text("Already there · \(stats.totalSessions)")
                    .font(LiquidType.cuerpo.weight(.semibold))
                    .foregroundStyle(LiquidColor.tinta700)
                LiquidGlassButton(String(localized: "Nothing new to import"),
                                  variant: .glass, expands: true) {}
                    .disabled(true)
            } else if stats.unresolvedCount > 0 {
                LiquidGlassButton(
                    String(localized: "Resolve \(stats.unresolvedCount) and continue"),
                    variant: .primary, expands: true) {
                        phase = .resolver
                    }
                    .disabled(needsWeightUnit && history == nil)
            } else {
                LiquidGlassButton(
                    String(localized: "Import \(stats.newCount) sessions"),
                    variant: .primary, expands: true) {
                        startSave()
                    }
                    .disabled(needsWeightUnit && history == nil)
            }
        }
    }

    private func duplicatesSection(stats: ReviewStats) -> some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s200) {
            Button {
                withAnimation(LiquidMotion.toque) { duplicatesExpanded.toggle() }
            } label: {
                reviewRowContent(
                    String(localized: "Possible duplicates"),
                    String(localized: "\(stats.duplicateCount) · out"))
            }
            .buttonStyle(.plain)
            .disabled(stats.duplicateCount == 0)

            if duplicatesExpanded, let history {
                ForEach(history.possibleDuplicates, id: \.session.id) { dup in
                    Toggle(isOn: Binding(
                        get: { forcedDuplicateIds.contains(dup.session.id) },
                        set: { on in
                            if on { forcedDuplicateIds.insert(dup.session.id) }
                            else { forcedDuplicateIds.remove(dup.session.id) }
                        }
                    )) {
                        VStack(alignment: .leading, spacing: LiquidSpace.s100) {
                            Text(verbatim: dup.session.title.isEmpty ? dup.session.id : dup.session.title)
                                .font(LiquidType.cuerpo)
                                .foregroundStyle(LiquidColor.tinta900)
                            Text(duplicateDetail(dup))
                                .font(LiquidType.caption)
                                .foregroundStyle(LiquidColor.tinta500)
                        }
                    }
                    .tint(LiquidColor.verdePrimario)
                    .padding(.horizontal, LiquidSpace.s400)
                    .padding(.vertical, LiquidSpace.s200)
                }
            }
        }
    }

    private var weightUnitRow: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s200) {
            if needsWeightUnit {
                HStack {
                    Text("Weight unit").font(LiquidType.cuerpo).foregroundStyle(LiquidColor.tinta900)
                    Spacer(minLength: LiquidSpace.s200)
                }
                .padding(.horizontal, LiquidSpace.s400)
                .padding(.top, LiquidSpace.s400)
                SegmentedPillControl([WorkoutWeightUnit.kg, .lb], selection: $weightUnit) { unit in
                    unit == .kg ? String(localized: "kg") : String(localized: "lb")
                }
                .padding(.horizontal, LiquidSpace.s400)
                .padding(.bottom, LiquidSpace.s300)
                if let maxWeightRaw {
                    let kg = (maxWeightRaw * WorkoutWeightUnit.lbToKg * 10).rounded() / 10
                    let kgText = kg.formatted(.number.precision(.fractionLength(0...1)))
                    Text("Highest weight in file: \(Int(maxWeightRaw)) → \(kgText) kg")
                        .font(LiquidType.caption)
                        .foregroundStyle(LiquidColor.tinta500)
                        .padding(.horizontal, LiquidSpace.s400)
                        .padding(.bottom, LiquidSpace.s300)
                }
            } else {
                reviewRow(String(localized: "Weight unit"),
                          String(localized: weightUnit == .kg ? "kg" : "lb"))
            }
        }
    }

    // MARK: - Step 3 · Resolver

    private var resolverFlow: some View {
        let remaining = unresolved.filter {
            resolution[norm($0.name)] == nil && !omitted.contains(norm($0.name))
        }.count
        return VStack(alignment: .leading, spacing: LiquidSpace.s700) {
            stepCaption(3)
            Text(remaining == 0
                 ? String(localized: "Unresolved · all set")
                 : String(localized: "Unresolved · \(remaining) of \(unresolved.count)"))
                .liquidKicker()
                .foregroundStyle(LiquidColor.tinta500)

            if let reconciler {
                ExerciseNameMappingPanel(
                    names: unresolved,
                    reconciler: reconciler,
                    resolution: $resolution,
                    omitted: $omitted,
                    autoMatched: $autoMatched,
                    onPickCatalog: { mappingTarget = MappingName(name: $0) },
                    onCreateOwn: { creationTarget = MappingName(name: $0) })
            }

            Text("Your decision is remembered forever.")
                .font(LiquidType.caption)
                .foregroundStyle(LiquidColor.tinta500)

            LiquidGlassButton(
                remaining == 0
                    ? String(localized: "Continue")
                    : String(localized: "Resolve \(remaining) more to continue"),
                variant: .primary, expands: true) {
                    startSave()
                }
                .disabled(remaining != 0)
                .accessibilityHint(remaining == 0
                    ? Text("Continue to save")
                    : Text("\(remaining) left to resolve, disabled"))
        }
    }

    // MARK: - Step 4 · Listo

    private var listoFlow: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s700) {
            stepCaption(4)
            Text("\(savedSessionCount) sessions in your history")
                .font(LiquidType.displayS)
                .tracking(LiquidType.displaySTracking)
                .foregroundStyle(LiquidColor.tinta900)
                .fixedSize(horizontal: false, vertical: true)

            Text("Records, 1RM and muscle map already recalculated with your history.")
                .font(LiquidType.cuerpo)
                .foregroundStyle(LiquidColor.tinta700)
                .fixedSize(horizontal: false, vertical: true)

            if loadCount > 0 {
                Text("\(loadCount) sessions enter your load")
                    .font(LiquidType.cuerpo)
                    .foregroundStyle(LiquidColor.tinta700)
            } else {
                Text("Your history already feeds records and 1RM. Your load starts with your watch or your next sessions.")
                    .font(LiquidType.cuerpo)
                    .foregroundStyle(LiquidColor.tinta700)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if leftOutDuplicateCount > 0 {
                Text("\(leftOutDuplicateCount) possible duplicates were left out; review them in Settings › Data Sources › Import")
                    .font(LiquidType.caption)
                    .foregroundStyle(LiquidColor.tinta500)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: LiquidSpace.s300) {
                if let onOpenHistory {
                    LiquidGlassButton(String(localized: "View history"), variant: .glass, expands: true) {
                        Task {
                            await onComplete()
                            onOpenHistory()
                            dismiss()
                        }
                    }
                }
                if let onArmWeek {
                    LiquidGlassButton(String(localized: "Arm your week"), variant: .glass, expands: true) {
                        Task {
                            await onComplete()
                            onArmWeek()
                            dismiss()
                        }
                    }
                }
                LiquidGlassButton(String(localized: "Done"), variant: .primary, expands: true) {
                    Task {
                        await onComplete()
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Shared chrome

    private func stepCaption(_ step: Int) -> some View {
        Text("Import · \(step) of 4")
            .font(LiquidType.tituloFilaMedia)
            .foregroundStyle(LiquidColor.tinta500)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.trailing, LiquidSpace.handoff44)
            .accessibilityLabel(Text("Step \(step) of 4"))
    }

    private func reviewRow(_ title: String, _ value: String) -> some View {
        reviewRowContent(title, value)
    }

    private func reviewRowContent(_ title: String, _ value: String) -> some View {
        HStack(spacing: LiquidSpace.s300) {
            Text(title).font(LiquidType.cuerpo).foregroundStyle(LiquidColor.tinta900)
            Spacer(minLength: LiquidSpace.s200)
            Text(value).font(LiquidType.cuerpo.weight(.semibold)).foregroundStyle(LiquidColor.tinta700)
        }
        .padding(LiquidSpace.s400)
        .frame(minHeight: LiquidControl.hitTarget)
        .contentShape(Rectangle())
    }

    private func reviewDivider() -> some View {
        Rectangle().fill(LiquidColor.vidrioBorde).frame(height: 0.5)
            .padding(.horizontal, LiquidSpace.s400)
    }

    // MARK: - Stats

    private struct ReviewStats {
        var totalSessions: Int
        var uniqueNames: Int
        var recognized: Int
        var unresolvedCount: Int
        var withEffort: Int
        var duplicateCount: Int
        var alreadyExisting: Int
        var newCount: Int
        var illegibleDates: Int
        var source: String
        var rangeStart: Date?
        var rangeEnd: Date?
    }

    private var reviewStats: ReviewStats {
        let sessions = history?.sessions ?? []
        let dups = history?.possibleDuplicates ?? []
        let dupIds = Set(dups.map(\.session.id))
        let names = uniqueExerciseNames(in: sessions)
        let recognized = names.filter { name in
            let key = norm(name)
            if resolution[key] != nil || omitted.contains(key) { return true }
            if let r = reconciler, r.match(name) != nil || r.autoMatch(name) != nil { return true }
            if learnedAliases[key] != nil { return true }
            return false
        }.count
        let already = sessions.filter { existingIds.contains($0.id) }.count
        let forcedIn = sessions.filter { forcedDuplicateIds.contains($0.id) }.count
        let defaultOut = sessions.filter {
            dupIds.contains($0.id) && !forcedDuplicateIds.contains($0.id) && !existingIds.contains($0.id)
        }.count
        let newCount = max(0, sessions.count - already - defaultOut)
        let illegible = history?.skipped.filter { $0.reason.contains("unparseable") }.count ?? 0
        let starts = sessions.map(\.startTs)
        let rangeStart = starts.min().map { Date(timeIntervalSince1970: TimeInterval($0)) }
        let rangeEnd = starts.max().map { Date(timeIntervalSince1970: TimeInterval($0)) }
        return ReviewStats(
            totalSessions: sessions.count,
            uniqueNames: names.count,
            recognized: recognized,
            unresolvedCount: unresolved.filter {
                resolution[norm($0.name)] == nil && !omitted.contains(norm($0.name))
            }.count,
            withEffort: sessions.filter(\.hasPerSetRPE).count,
            duplicateCount: dups.count,
            alreadyExisting: already,
            newCount: newCount + (forcedIn > 0 ? 0 : 0), // newCount already accounts for forced via defaultOut
            illegibleDates: illegible,
            source: dialectLabel,
            rangeStart: rangeStart,
            rangeEnd: rangeEnd)
    }

    private func reviewSubtitle(stats: ReviewStats) -> String {
        var parts: [String] = [String(localized: "sessions")]
        if !stats.source.isEmpty { parts.append(stats.source) }
        if let a = stats.rangeStart, let b = stats.rangeEnd {
            parts.append("\(monthYear(a)) \(String(localized: "to")) \(monthYear(b))")
        }
        return parts.joined(separator: " · ")
    }

    private func reviewNotes(stats: ReviewStats) -> [String] {
        var notes: [String] = []
        if stats.illegibleDates > 0 {
            notes.append(String(localized: "Illegible dates in \(stats.illegibleDates) rows"))
        }
        notes.append(String(localized: "Times are read in your current time zone."))
        if dialectLabel == "Hevy" {
            notes.append(String(localized: "Supersets are saved as consecutive exercises."))
        }
        return notes
    }

    private func monthYear(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = .autoupdatingCurrent
        f.setLocalizedDateFormatFromTemplate("MMMyyyy")
        return f.string(from: date)
    }

    private func duplicateDetail(_ dup: StrengthCSVImporter.PossibleDuplicate) -> String {
        let existing = dup.existingTitle?.isEmpty == false
            ? (dup.existingTitle ?? "")
            : (dup.existingSource ?? dup.existingId)
        return String(localized: "Overlaps \(existing)")
    }

    // MARK: - File / parse

    private func handleImport(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            parseErrorKey = String(localized: "We couldn’t read that file. Pick the original .csv and try again.")
            return
        }
        fileData = data
        beginRead(data: data, unit: needsWeightUnit ? weightUnit : nil)
    }

    private func beginRead(data: Data, unit: WorkoutWeightUnit?) {
        parseErrorKey = nil
        phase = .leyendo
        readingProgressLabel = "Reading…"
        readTask?.cancel()
        readTask = Task {
            let overlap = await repo.sessionSummariesForImportOverlap()
            if Task.isCancelled {
                await MainActor.run { resetToArchivo() }
                return
            }
            do {
                let parsed = try StrengthCSVImporter.parse(data: data, weightUnit: unit)
                if Task.isCancelled {
                    await MainActor.run { resetToArchivo() }
                    return
                }
                let annotated = StrengthCSVImporter.annotateDuplicates(parsed, existing: overlap)
                let ids = annotated.sessions.map(\.id)
                let existing = await repo.existingSessionIds(ids)
                if Task.isCancelled {
                    await MainActor.run { resetToArchivo() }
                    return
                }
                await MainActor.run {
                    applyParsed(annotated, existing: existing, unitAsked: false)
                    readingProgressLabel = "Reading… \(annotated.sessions.count) of \(annotated.sessions.count)"
                    phase = .revisar
                }
            } catch let err as StrengthCSVImporter.ImportError {
                await MainActor.run { handleParseError(err, data: data) }
            } catch {
                await MainActor.run {
                    parseErrorKey = String(localized: "We couldn’t read that file. Pick the original .csv and try again.")
                    resetToArchivo()
                }
            }
        }
    }

    private func retryParse(data: Data, unit: WorkoutWeightUnit) {
        phase = .leyendo
        readingProgressLabel = "Reading…"
        readTask?.cancel()
        readTask = Task {
            let overlap = await repo.sessionSummariesForImportOverlap()
            if Task.isCancelled {
                await MainActor.run { phase = .revisar }
                return
            }
            do {
                let parsed = try StrengthCSVImporter.parse(data: data, weightUnit: unit)
                let annotated = StrengthCSVImporter.annotateDuplicates(parsed, existing: overlap)
                let existing = await repo.existingSessionIds(annotated.sessions.map(\.id))
                if Task.isCancelled {
                    await MainActor.run { phase = .revisar }
                    return
                }
                await MainActor.run {
                    applyParsed(annotated, existing: existing, unitAsked: true)
                    phase = .revisar
                }
            } catch {
                await MainActor.run {
                    parseErrorKey = String(localized: "We couldn’t read that file. Pick the original .csv and try again.")
                    phase = .revisar
                }
            }
        }
    }

    private func handleParseError(_ err: StrengthCSVImporter.ImportError, data: Data) {
        switch err {
        case .unitRequired:
            needsWeightUnit = true
            weightUnit = .kg
            if let text = try? decodePreview(data) {
                maxWeightRaw = StrengthCSVImporter.strongMaxWeightRaw(text: text)
            }
            dialectLabel = "Strong"
            history = nil
            phase = .revisar
        case .unknownHeader:
            parseErrorKey = String(localized: "I don’t recognize this file. Cénit reads the CSV Strong and Hevy export. Make sure it’s the original .csv, unedited.")
            resetToArchivo()
        case .emptyInput:
            parseErrorKey = String(localized: "That file is empty. Export again from the app and try once more.")
            resetToArchivo()
        }
    }

    private func decodePreview(_ data: Data) throws -> String {
        if let s = String(data: data, encoding: .utf8) { return s }
        if let s = String(data: data, encoding: .utf16LittleEndian) { return s }
        if let s = String(data: data, encoding: .utf16BigEndian) { return s }
        throw StrengthCSVImporter.ImportError.emptyInput
    }

    private func applyParsed(_ annotated: StrengthCSVImporter.ImportedStrengthHistory,
                             existing: Set<String>, unitAsked: Bool) {
        history = annotated
        existingIds = existing
        forcedDuplicateIds = []
        duplicatesExpanded = false
        needsWeightUnit = false
        if unitAsked == false {
            // Infer display unit from first positive kg weight vs dialect label.
            weightUnit = .kg
        }
        dialectLabel = annotated.sessions.first.map { displaySource($0.source) } ?? dialectLabel
        rebuildReconciler(from: annotated)
    }

    private func rebuildReconciler(from annotated: StrengthCSVImporter.ImportedStrengthHistory) {
        let r = WorkoutExerciseReconciler(known: catalog, learned: learnedAliases,
                                          aliases: ExerciseAliasTable.bundled)
        reconciler = r
        let counts = nameCounts(in: annotated.sessions)
        var unresolvedNames: [UnresolvedName] = []
        var res: [String: Exercise] = [:]
        var auto: Set<String> = []
        for (name, counts) in counts.sorted(by: { $0.key < $1.key }) {
            let key = norm(name)
            if let hit = r.match(name) ?? learnedHit(key, in: r) {
                res[key] = hit
                continue
            }
            if let hit = r.autoMatch(name) {
                res[key] = hit
                auto.insert(key)
                unresolvedNames.append(UnresolvedName(name: name,
                                                      sessionCount: counts.sessions,
                                                      setCount: counts.sets))
                continue
            }
            unresolvedNames.append(UnresolvedName(name: name,
                                                  sessionCount: counts.sessions,
                                                  setCount: counts.sets))
        }
        unresolved = unresolvedNames
        resolution = res
        autoMatched = auto
        omitted = []
    }

    private func learnedHit(_ key: String, in r: WorkoutExerciseReconciler) -> Exercise? {
        // `match` already covers normalized names; learned aliases are applied via resolve on
        // WorkoutExercise — for free-text CSV names, autoMatch / match / learned index:
        guard let id = learnedAliases[key] else { return nil }
        return catalog.first { $0.id == id }
    }

    private func uniqueExerciseNames(in sessions: [StrengthCSVImporter.ImportedSession]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for s in sessions {
            for set in s.sets {
                let key = norm(set.exerciseName)
                if seen.insert(key).inserted { out.append(set.exerciseName) }
            }
        }
        return out
    }

    private func nameCounts(in sessions: [StrengthCSVImporter.ImportedSession])
    -> [String: (sessions: Int, sets: Int)] {
        var setsByKey: [String: Int] = [:]
        var sessionsByKey: [String: Set<String>] = [:]
        var display: [String: String] = [:]
        for s in sessions {
            var namesInSession = Set<String>()
            for set in s.sets {
                let key = norm(set.exerciseName)
                display[key] = display[key] ?? set.exerciseName
                setsByKey[key, default: 0] += 1
                namesInSession.insert(key)
            }
            for key in namesInSession {
                sessionsByKey[key, default: []].insert(s.id)
            }
        }
        var out: [String: (sessions: Int, sets: Int)] = [:]
        for (key, name) in display {
            out[name] = (sessionsByKey[key]?.count ?? 0, setsByKey[key] ?? 0)
        }
        return out
    }

    private func displaySource(_ raw: String) -> String {
        switch raw.lowercased() {
        case "strong": return "Strong"
        case "hevy": return "Hevy"
        case "cenit": return "Cénit"
        default: return raw.capitalized
        }
    }

    // MARK: - Resolve / save

    private func norm(_ name: String) -> String { WorkoutExerciseReconciler.normalize(name) }

    private func resolve(_ name: String, with exercise: Exercise) {
        let key = norm(name)
        resolution[key] = exercise
        autoMatched.remove(key)
        omitted.remove(key)
        mappingTarget = nil
    }

    private func createNew(_ name: String, as exercise: Exercise) {
        Task {
            do {
                try await repo.saveCustomExercise(exercise)
                catalog.append(exercise)
                resolution[norm(name)] = exercise
                autoMatched.remove(norm(name))
                omitted.remove(norm(name))
            } catch {
                saveError = true
            }
        }
    }

    private func startSave() {
        guard let history else { return }
        phase = .guardando
        let snapshot = history
        let resolutionSnap = resolution
        let omittedSnap = omitted
        let existingSnap = existingIds
        let forcedSnap = forcedDuplicateIds
        let reconcilerSnap = reconciler
            ?? WorkoutExerciseReconciler(known: catalog, learned: learnedAliases,
                                         aliases: ExerciseAliasTable.bundled)
        let trimp = StrengthLoadCalibration.current
        Task {
            do {
                let result = try await persist(
                    snapshot,
                    resolution: resolutionSnap,
                    omitted: omittedSnap,
                    existing: existingSnap,
                    forcedDuplicates: forcedSnap,
                    reconciler: reconcilerSnap,
                    trimpPerAU: trimp)
                for (key, ex) in resolutionSnap where !omittedSnap.contains(key) {
                    do {
                        try await repo.saveLearnedExerciseAlias(name: key, exerciseId: ex.id)
                    } catch {
                        saveError = true
                    }
                }
                await MainActor.run {
                    savedSessionCount = result.saved
                    loadCount = result.loadCount
                    leftOutDuplicateCount = result.leftOutDuplicates
                    phase = .listo
                }
            } catch {
                await MainActor.run {
                    saveError = true
                    phase = .revisar
                }
            }
        }
    }

    private func persist(
        _ history: StrengthCSVImporter.ImportedStrengthHistory,
        resolution: [String: Exercise],
        omitted: Set<String>,
        existing: Set<String>,
        forcedDuplicates: Set<String>,
        reconciler: WorkoutExerciseReconciler,
        trimpPerAU: Double
    ) async throws -> (saved: Int, loadCount: Int, leftOutDuplicates: Int) {
        let dupIds = Set(history.possibleDuplicates.map(\.session.id))
        var batch: [(session: StrengthSession, sets: [SetEntry])] = []
        var loadCount = 0
        var leftOut = 0

        for session in history.sessions {
            if existing.contains(session.id) { continue }
            if dupIds.contains(session.id) && !forcedDuplicates.contains(session.id) {
                leftOut += 1
                continue
            }
            let mapped: (String) -> String? = { raw in
                let key = WorkoutExerciseReconciler.normalize(raw)
                if omitted.contains(key) { return nil }
                if let ex = resolution[key] { return ex.id }
                if let hit = reconciler.match(raw) ?? reconciler.autoMatch(raw) { return hit.id }
                if let id = learnedAliases[key] { return id }
                return nil
            }
            guard let materialized = StrengthCSVImporter.materialize(session, exerciseIdByName: mapped)
            else { continue }
            var strengthSession = materialized.0
            let sets = materialized.1

            if let rpe = strengthSession.sessionRpe,
               let end = strengthSession.endTs {
                let duration = end - strengthSession.startTs
                if duration > 0,
                   let strain = SessionRPELoad.strain(durationS: duration, rpe: rpe,
                                                     trimpPerAU: trimpPerAU) {
                    strengthSession.strain = strain
                    strengthSession.strainSource = .rpe
                    strengthSession.trimpPerAU = trimpPerAU
                    loadCount += 1
                }
            }
            batch.append((session: strengthSession, sets: sets))
        }

        try await repo.saveSessions(batch)
        return (batch.count, loadCount, leftOut)
    }

    // MARK: - Dismiss / reset

    private func dismissImport() {
        switch phase {
        case .revisar, .resolver:
            confirmDiscard = true
        case .leyendo:
            readTask?.cancel()
            readTask = nil
            resetToArchivo()
        case .guardando:
            break
        case .archivo, .listo:
            dismiss()
        }
    }

    private func resetToArchivo() {
        phase = .archivo
        history = nil
        fileData = nil
        needsWeightUnit = false
        maxWeightRaw = nil
        unresolved = []
        resolution = [:]
        autoMatched = []
        omitted = []
        forcedDuplicateIds = []
        existingIds = []
    }
}
#endif
