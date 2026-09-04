#if os(iOS)
import SwiftUI
import CenitDesign
import StrandTraining

// PersonalRecordsScreen.swift — «Tus marcas» (FER-360, ola 2 de Entrenar): every exercise with at
// least one personal record, most-recent-mark first. Pushed onto the Entrenar `trainStack` from the
// hub's «Marcas» tile (`PersonalRecordsRoute`, same empty-Hashable-route pattern as
// `MuscleVolumeRoute`/`SavedTicketsRoute`) — never a tab/sheet/modal. Read-only; a row opens the SAME
// `ExerciseDetailScreen` every other progress list uses, on its Progress tab (`startOnProgress: true`,
// same `.sheet(item:)` WorkoutHistoryScreen's own «Progreso por ejercicio» rows use) — no third
// surface for "look at this PR".

/// Route pushed onto the Entrenar stack for «Tus marcas».
struct PersonalRecordsRoute: Hashable {}

struct PersonalRecordsScreen: View {
    @EnvironmentObject private var repo: Repository
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    private var system: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }
    @Environment(\.dynamicTypeSize) private var typeSize

    /// One row: the exercise, its dominant number already formatted for `type`, when that number was
    /// set, and whether it falls inside the «nuevo» window.
    fileprivate struct Row: Identifiable {
        let id: String   // exerciseId
        let exercise: Exercise
        let name: String
        let valueText: String
        let ts: Int
        let isNew: Bool
    }

    @State private var rows: [Row] = []
    @State private var totalCount = 0
    @State private var thisMonthCount = 0
    @State private var loaded = false
    /// `repo.storeHandle()` came back nil — a real read failure, distinct from «cero marcas».
    @State private var readError = false
    @State private var detailExercise: Exercise?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LiquidSpace.s700) {
                header
                if loaded {
                    if readError {
                        errorState
                    } else if rows.isEmpty {
                        emptyState
                    } else {
                        list
                    }
                }
            }
            .padding(.top, LiquidSpace.topeScroll)
            .padding(.horizontal, LiquidSpace.s600)
            .padding(.bottom, LiquidSpace.s600)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // FER-360: mismo fondo de vidrio El Eje que el resto de las pantallas empujadas al
        // trainStack (`SavedTicketsScreen`, `TrainingBodyScreen`) — llega empujada y conserva la
        // navegación/toolbar del stack ambiente tal cual.
        .entrenarHojaFondo(tono: .neutro)
        .task { await load() }
        .sheet(item: $detailExercise) { ex in
            NavigationStack {
                ExerciseDetailScreen(exercise: ex, startOnProgress: true)
                    .toolbar { ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { detailExercise = nil }.foregroundStyle(LiquidColor.tinta900)
                    } }
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbarBackground(LiquidColor.fondoAlto, for: .navigationBar)
            }
            .environmentObject(repo)
        }
    }

    // MARK: - Header

    private var header: some View {
        LiquidFlowTitle(kicker: totalCount > 0 ? kickerText : nil, titulo: String(localized: "Your marks"))
    }

    /// «{N} marks · {M} this month», or just «{N} marks» when nothing fell this month (spec: «Si M=0,
    /// solo "{N} marcas"»). `1 mark`/`%lld marks` is the SAME manual singular/plural split the hub's
    /// `EntrenarMarcaChip` already uses — one existing pair of catalog keys, not a new one.
    private var kickerText: String {
        let marks = totalCount == 1 ? String(localized: "1 mark") : String(localized: "\(totalCount) marks")
        guard thisMonthCount > 0 else { return marks }
        return "\(marks) · \(String(localized: "\(thisMonthCount) this month"))"
    }

    // MARK: - List

    private var list: some View {
        VStack(spacing: .zero) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                markRow(row, divider: idx != rows.count - 1)
            }
        }
        .padding(.horizontal, LiquidSpace.handoff14)
        .padding(.vertical, LiquidSpace.s050)
        .liquidGlass(.superficieSolida)
    }

    private func markRow(_ row: Row, divider: Bool) -> some View {
        Button { detailExercise = row.exercise } label: {
            Group {
                if typeSize.isAccessibilitySize {
                    markRowAccessible(row)
                } else {
                    markRowCompact(row)
                }
            }
            .padding(.vertical, LiquidSpace.s150)
            .padding(.horizontal, LiquidSpace.s100)
            .frame(minHeight: EntrenarMetrics.row)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                if divider { LiquidCapilar(eje: .horizontal) }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(markRowA11yLabel(row))
        .accessibilityHint(Text("Opens the full detail"))
    }

    private func markRowCompact(_ row: Row) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: LiquidSpace.s050) {
                Text(verbatim: row.name).font(LiquidType.tituloGemela).foregroundStyle(LiquidColor.tinta900)
                    .lineLimit(1)
                StrengthDisplay.recordDate(row.ts).font(LiquidType.filaConteo).foregroundStyle(LiquidColor.tinta500)
            }
            Spacer(minLength: LiquidSpace.s200)
            VStack(alignment: .trailing, spacing: LiquidSpace.s050) {
                Text(verbatim: row.valueText).font(LiquidType.tituloGemela).monospacedDigit()
                    .foregroundStyle(LiquidColor.tinta900)
                if row.isNew { newBadge }
            }
        }
    }

    /// AX5 (spec: «el número no se recorta, la fila apila»): el numeral y «nuevo» bajan bajo el
    /// nombre en vez de vivir en una columna angosta a la derecha — mismo truco de
    /// `EntrenarFilaFuerza.filaAccesible`.
    private func markRowAccessible(_ row: Row) -> some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s050) {
            Text(verbatim: row.name).font(LiquidType.tituloGemela).foregroundStyle(LiquidColor.tinta900)
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: row.valueText).font(LiquidType.tituloGemela).monospacedDigit()
                .foregroundStyle(LiquidColor.tinta900)
            HStack(spacing: LiquidSpace.s150) {
                StrengthDisplay.recordDate(row.ts).font(LiquidType.filaConteo).foregroundStyle(LiquidColor.tinta500)
                if row.isNew { newBadge }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var newBadge: some View {
        Text("New")
            .font(LiquidType.microEstado).tracking(0.5)
            .foregroundStyle(LiquidColor.papelTarjeta)
            .padding(.horizontal, LiquidSpace.s200).padding(.vertical, LiquidSpace.s050)
            .background(LiquidColor.positivo, in: RoundedRectangle(cornerRadius: LiquidRadius.chip, style: .continuous))
    }

    /// One VoiceOver stop per row (spec): name, value, date, and «nuevo» when it applies — read in
    /// that order regardless of which layout (`markRowCompact`/`markRowAccessible`) is on screen.
    private func markRowA11yLabel(_ row: Row) -> Text {
        var t = Text(verbatim: row.name) + Text(verbatim: ", ") + Text(verbatim: row.valueText)
            + Text(verbatim: ", ") + StrengthDisplay.recordDate(row.ts)
        if row.isNew { t = t + Text(verbatim: ", ") + Text("New") }
        return t
    }

    // MARK: - Empty / error

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: .zero) {
            Rectangle().fill(LiquidColor.tinta10).frame(height: LiquidRadius.hairline)
            VStack(alignment: .leading, spacing: LiquidSpace.s200) {
                Image(systemName: "trophy")
                    .font(LiquidType.infoGlifoTitular).foregroundStyle(LiquidColor.tinta500)
                    .accessibilityHidden(true)
                Text("You don't have any marks yet").font(LiquidType.titulo).foregroundStyle(LiquidColor.tinta900)
                Text("Once you log a strength set (weight or reps), your best mark shows up here.")
                    .font(LiquidType.cuerpoBanner).foregroundStyle(LiquidColor.tinta700)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, LiquidSpace.s400)
        }
    }

    /// «Error de lectura», distinto de «cero marcas» — con CTA real de reintento (spec), mismo patrón
    /// `LiquidAviso(cta:accion:)` que `SaveErrorToast` ya usa para «No se pudo guardar».
    private var errorState: some View {
        LiquidAviso(
            titulo: "",
            cuerpo: String(localized: "Couldn't read your marks. Try again."),
            tono: LiquidColor.negativo,
            cta: String(localized: "Retry"),
            accion: { Task { await load() } })
    }

    // MARK: - Load

    private func load() async {
        guard await repo.storeHandle() != nil else {
            readError = true
            loaded = true
            return
        }
        readError = false
        let all = await repo.allPersonalRecords()
        let byExercise = Dictionary(grouping: all, by: \.exerciseId)

        let cal = Calendar.current
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: Date())) ?? Date()
        let monthEnd = cal.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
        let stats = await repo.personalRecordExerciseStats(monthStart: monthStart.timeIntervalSince1970,
                                                            monthEnd: monthEnd.timeIntervalSince1970)
        let newCutoff = cal.date(byAdding: .day, value: -StrengthDisplay.recordRecentWindowDays,
                                 to: cal.startOfDay(for: Date())) ?? Date()

        var built: [Row] = []
        for (exerciseId, records) in byExercise {
            guard let maxTs = records.map(\.ts).max() else { continue }
            guard let ex = await repo.resolvedExercise(exerciseId) else { continue }
            guard let valueText = Self.dominantValueText(records: records, type: ex.type, system: system) else { continue }
            built.append(Row(id: exerciseId, exercise: ex, name: StrengthDisplay.name(ex),
                             valueText: valueText, ts: maxTs,
                             isNew: Double(maxTs) >= newCutoff.timeIntervalSince1970))
        }

        totalCount = stats.total
        thisMonthCount = stats.thisMonth
        rows = built.sorted { $0.ts > $1.ts }
        loaded = true
    }

    /// El número dominante de una fila (spec): `.bodyweight` prefiere `maxReps` («18 reps»);
    /// cualquier otro tipo prefiere `maxWeight` («102.5 kg»); si la métrica preferida no existe
    /// todavía para este ejercicio, cae a la otra. `nil` solo si NINGUNA de las dos existe.
    fileprivate static func dominantValueText(records: [PersonalRecord], type: ExerciseType,
                                              system: UnitSystem) -> String? {
        let byMetric = Dictionary(records.map { ($0.metric, $0) }, uniquingKeysWith: { a, _ in a })
        func text(_ metric: PRMetric, _ pr: PersonalRecord) -> String {
            metric == .maxReps ? String(localized: "\(pr.reps ?? 0) reps")
                               : StrengthDisplay.weight(pr.valueKg ?? 0, system: system)
        }
        let preferred: PRMetric = type == .bodyweight ? .maxReps : .maxWeight
        let fallback: PRMetric = preferred == .maxReps ? .maxWeight : .maxReps
        if let pr = byMetric[preferred] { return text(preferred, pr) }
        if let pr = byMetric[fallback] { return text(fallback, pr) }
        return nil
    }
}
#endif
