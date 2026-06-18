#if os(iOS)
import SwiftUI
import StrandDesign
import WhoopStore
import Foundation

// MARK: - Workouts — la bitácora de actividad en «Instrumento diurno» (FER-260)
//
// Migrada del sistema oscuro legacy (tabla densa de 7 columnas + grid de StatTiles + zonas agregadas) al
// lenguaje claro: UN número protagonista (sesiones del periodo), jerarquía por espacio, color SOLO en el
// dato. Se presenta como `.sheet` clara desde Cuerpo, con el `InstrumentoTheme` inyectado al raíz de la
// sheet (no propaga solo, FER-162) y un único `NavigationStack` que la envuelve — cada fila de sesión
// PUSHEA `WorkoutDetailScreen` (sin stack anidado, FER-171). El CRUD completo vive en el menú ••• del
// detalle (reemplaza el `contextMenu` de escritorio, invisible en iPhone). Reusa `Repository` tal cual.
//
// Destilado a: héroe (conteo) · filtro de rango (+ auto-ampliación) · apoyos (tiempo/más frecuente) ·
// «Por deporte» (lista quieta) · «Sesiones» (filas tap-eables). La barra de zonas agregada se movió al
// detalle de cada sesión (donde sí informa). Estados: cargando · vacío (onboarding) · con datos.

struct WorkoutsView: View {
    @EnvironmentObject var repo: Repository
    @EnvironmentObject var health: HealthKitBridge
    @Environment(\.instrumentoTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    private var unitSystem: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }

    @State private var allRows: [WorkoutRow]
    @State private var loaded: Bool
    @State private var range: Range = .all
    @State private var sheet: WorkoutSheetTarget?
    /// Opens the (legacy dark) Data Sources screen from the empty state / the connect line. Self-contained.
    @State private var showDataSources = false

    /// `.some(nil)` = add a new workout, `.some(row)` = edit `row`, `nil` = closed.
    private struct WorkoutSheetTarget: Identifiable { let editing: WorkoutRow?; let id = UUID() }

    init(previewRows: [WorkoutRow]? = nil) {
        _allRows = State(initialValue: previewRows ?? [])
        _loaded = State(initialValue: previewRows != nil)
    }

    var body: some View {
        Group {
            if !loaded {
                LoadingStateView("Reading your sessions…")
            } else if allRows.isEmpty {
                emptyState
            } else {
                populated
            }
        }
        .background(theme.paper.ignoresSafeArea())
        .navigationTitle("Workouts")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }.foregroundStyle(theme.ink)
            }
            ToolbarItem(placement: .primaryAction) {
                Button { addWorkout() } label: { Image(systemName: "plus") }
                    .foregroundStyle(theme.ink)
                    .accessibilityLabel("Add a workout")
            }
        }
        .toolbarBackground(theme.paper, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .navigationDestination(for: WorkoutRow.self) { row in
            WorkoutDetailScreen(theme: theme, row: row, onChange: { await reload() })
        }
        .sheet(item: $sheet) { target in
            ManualWorkoutSheet(editing: target.editing) { row, replacing in
                Task { await repo.saveManualWorkout(row, replacing: replacing); await reload() }
            }
        }
        .sheet(isPresented: $showDataSources) { dataSourcesSheet }
        .task {
            guard !loaded else { return }
            let r = await repo.workoutRows()
            allRows = r
            loaded = true
            range = defaultRange(for: r)
        }
        .onAppear { if loaded { range = defaultRange(for: allRows) } }
    }

    // MARK: - Populated

    private var populated: some View {
        // Compute the windowed rows + per-sport groups ONCE per body (SwiftUI re-runs body on every
        // state tick); thread them into each section. Same windowing as before.
        let resolved = effectiveRange
        let windowRows = sessions(for: resolved)
        let groups = sportGroups(from: windowRows)
        return ScrollView {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                heroBlock(rows: windowRows, effectiveRange: resolved)
                supportsRow(rows: windowRows, groups: groups)
                bySportSection(groups: groups)
                sessionsSection(rows: windowRows)
                healthHint
            }
            .padding(NoopMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Hero (sessions in the period) + range control

    private func heroBlock(rows: [WorkoutRow], effectiveRange: Range) -> some View {
        let fellBack = effectiveRange != range
        let n = rows.count
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: effectiveRange.caption).instrumentoOverline().foregroundStyle(theme.inkTertiary)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(n)").instrumentoHero(64).foregroundStyle(theme.dataStrain)
                    Text(n == 1 ? "session" : "sessions").font(StrandFont.unit).foregroundStyle(theme.inkTertiary)
                }
                .accessibilityElement(children: .combine)
            }
            SegmentedPillControl(Range.allCases, selection: $range, theme: theme) { $0.label }
            Text(rangeCaption(count: n, effectiveRange: effectiveRange, fellBack: fellBack))
                .font(StrandFont.footnote)
                .foregroundStyle(fellBack ? theme.warning : theme.inkTertiary)
        }
    }

    private func rangeCaption(count: Int, effectiveRange: Range, fellBack: Bool) -> String {
        let unit = count == 1 ? String(localized: "session") : String(localized: "sessions")
        let countUnit = "\(count) \(unit)"
        if fellBack {
            return String(format: String(localized: "%@ · sparse — widened to %@"), countUnit, effectiveRange.caption)
        }
        return "\(countUnit) · \(effectiveRange.caption)"
    }

    // MARK: - Supports (active time · most frequent) — quiet, ink, hairline-separated

    private func supportsRow(rows: [WorkoutRow], groups: [SportGroup]) -> some View {
        let totalTimeH = rows.compactMap(\.durationS).reduce(0, +) / 3600.0
        let modal = groups.first
        return VStack(alignment: .leading, spacing: 16) {
            Rectangle().fill(theme.hairline).frame(height: 1)
            HStack(alignment: .top, spacing: 48) {
                support("Active time", oneDecimal(totalTimeH) + "h")
                if let modal { support("Most frequent", WorkoutSource.displaySport(modal.sport)) }
            }
        }
    }

    private func support(_ label: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).instrumentoOverline().foregroundStyle(theme.inkTertiary)
            Text(value).font(StrandFont.number(17)).foregroundStyle(theme.ink).lineLimit(1)
        }
    }

    // MARK: - By sport (quiet list — no card-in-card)

    private func bySportSection(groups: [SportGroup]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("By sport").instrumentoOverline().foregroundStyle(theme.inkTertiary).padding(.bottom, 6)
            ForEach(Array(groups.enumerated()), id: \.element.id) { idx, g in
                HStack(spacing: 12) {
                    Image(systemName: WorkoutSource.sfSymbol(for: g.sport))
                        .font(.system(size: 14, weight: .medium)).foregroundStyle(theme.inkSecondary)
                        .frame(width: 22)
                    Text(WorkoutSource.displaySport(g.sport)).font(StrandFont.body).foregroundStyle(theme.ink)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text("\(g.count) · \(oneDecimal(g.totalTimeH))h")
                        .font(StrandFont.captionNumber).foregroundStyle(theme.inkSecondary)
                }
                .padding(.vertical, 9)
                .accessibilityElement(children: .combine)
                if idx != groups.count - 1 {
                    Rectangle().fill(theme.hairline).frame(height: 1).padding(.leading, 34)
                }
            }
        }
    }

    // MARK: - Sessions (tappable rows → detail)

    private func sessionsSection(rows: [WorkoutRow]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Sessions").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                Spacer()
                Text("\(rows.count)").font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
            }
            .padding(.bottom, 6)
            ForEach(Array(rows.enumerated()), id: \.offset) { idx, row in
                NavigationLink(value: row) { sessionRow(row) }
                    .buttonStyle(.plain)
                if idx != rows.count - 1 {
                    Rectangle().fill(theme.hairline).frame(height: 1)
                }
            }
        }
    }

    private func sessionRow(_ row: WorkoutRow) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: WorkoutSource.sfSymbol(for: row.sport))
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(theme.inkSecondary)
                    Text(WorkoutSource.displaySport(row.sport)).font(StrandFont.body).foregroundStyle(theme.ink)
                        .lineLimit(1)
                }
                Text("\(WorkoutDetailScreen.dateLabel(row.startTs)) · \(WorkoutDetailScreen.timeLabel(row.startTs))")
                    .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                sessionDatum(row)
                workoutSourceBadge(for: row.source, theme: theme)
            }
        }
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// The per-session protagonist on the right: effort if the session carries it, else avg HR, else
    /// duration. Effort/HR read in the ember effort hue; duration stays ink (not a saturated datum).
    @ViewBuilder private func sessionDatum(_ row: WorkoutRow) -> some View {
        if let s = row.strain {
            Text(String(format: "%.1f", s)).font(StrandFont.number(17)).foregroundStyle(theme.dataStrain)
        } else if let hr = row.avgHr {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(hr)").font(StrandFont.number(17)).foregroundStyle(theme.dataStrain)
                Text("bpm").font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
            }
        } else {
            Text(durationLabel(row.durationS ?? Double(max(0, row.endTs - row.startTs))))
                .font(StrandFont.number(17)).foregroundStyle(theme.ink)
        }
    }

    // MARK: - Apple Health connect line (optional, never a wall)

    @ViewBuilder private var healthHint: some View {
        let notConnected = health.auth != .authorized && health.auth != .unavailable
        let noAppleSessions = !allRows.contains { WorkoutSource.classify($0.source) == .apple }
        if notConnected && noAppleSessions {
            Button { showDataSources = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "heart.fill").font(.system(size: 12)).foregroundStyle(theme.dataSpO2)
                    Text("Connect Apple Health to bring in your workouts from there.")
                        .font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
                    Spacer(minLength: 6)
                    Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(theme.inkTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Empty state (onboarding — not a dead end)

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "figure.run").font(.system(size: 38, weight: .regular))
                .foregroundStyle(theme.inkTertiary).accessibilityHidden(true)
            Text("No workouts yet").font(StrandFont.title2).foregroundStyle(theme.ink)
                .multilineTextAlignment(.center)
            Text("They come from your WHOOP and Apple Health history. Import them in Data Sources — or add one you tracked elsewhere.")
                .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 300)
            QuietButton("Add workout") { addWorkout() }.padding(.top, 4)
            QuietButton("Data Sources") { showDataSources = true }
        }
        .padding(NoopMetrics.screenPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Data Sources bridge (legacy dark screen, self-contained sheet)

    private var dataSourcesSheet: some View {
        NavigationStack {
            DataSourcesView()
                .background(StrandPalette.surfaceBase.ignoresSafeArea())
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(StrandPalette.surfaceBase, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showDataSources = false }.foregroundStyle(StrandPalette.accent)
                    }
                }
        }
        .environmentObject(repo)
        .environmentObject(health)
        .preferredColorScheme(.dark)
    }

    // MARK: - Actions

    private func addWorkout() { sheet = WorkoutSheetTarget(editing: nil) }

    /// Re-read the rows after a mutation (from the detail's CRUD or the add/edit sheet). Keeps the range.
    private func reload() async { allRows = await repo.workoutRows() }

    // MARK: - Windowing (unchanged math)

    private var latestTs: Int? { allRows.map(\.startTs).max() }

    private func sessions(for r: Range) -> [WorkoutRow] {
        guard let days = r.days else { return allRows }
        guard let last = latestTs else { return [] }
        let cutoff = last - days * 86_400
        return allRows.filter { $0.startTs >= cutoff }
    }

    /// The selected range when it holds ≥1 session, else the smallest larger range that does.
    private var effectiveRange: Range {
        guard !allRows.isEmpty else { return range }
        for r in range.widening where !sessions(for: r).isEmpty { return r }
        return .all
    }

    /// Tightest range that still holds ≥2 sessions; else All.
    private func defaultRange(for source: [WorkoutRow]) -> Range {
        guard let last = source.map(\.startTs).max() else { return .all }
        for r in Range.allCases where r.days != nil {
            let cutoff = last - (r.days ?? 0) * 86_400
            if source.filter({ $0.startTs >= cutoff }).count >= 2 { return r }
        }
        return .all
    }

    // MARK: - Aggregation

    struct SportGroup: Identifiable {
        let sport: String
        let count: Int
        let totalTimeS: Double
        var id: String { sport }
        var totalTimeH: Double { totalTimeS / 3600.0 }
    }

    private func sportGroups(from rows: [WorkoutRow]) -> [SportGroup] {
        var bySport: [String: (count: Int, time: Double)] = [:]
        for r in rows {
            var acc = bySport[r.sport] ?? (0, 0)
            acc.count += 1
            acc.time += r.durationS ?? 0
            bySport[r.sport] = acc
        }
        return bySport
            .map { SportGroup(sport: $0.key, count: $0.value.count, totalTimeS: $0.value.time) }
            .sorted { ($0.count, $0.totalTimeS) > ($1.count, $1.totalTimeS) }
    }

    // MARK: - Range model

    enum Range: CaseIterable, Hashable {
        case week, month, quarter, year, all
        var label: String {
            switch self {
            case .week:    return String(localized: "7D")
            case .month:   return String(localized: "30D")
            case .quarter: return String(localized: "90D")
            case .year:    return String(localized: "1Y")
            case .all:     return String(localized: "All")
            }
        }
        var caption: String {
            switch self {
            case .week:    return String(localized: "last 7 days")
            case .month:   return String(localized: "last 30 days")
            case .quarter: return String(localized: "last 90 days")
            case .year:    return String(localized: "last year")
            case .all:     return String(localized: "all time")
            }
        }
        var days: Int? {
            switch self {
            case .week: return 7
            case .month: return 30
            case .quarter: return 90
            case .year: return 365
            case .all: return nil
            }
        }
        var widening: [Range] {
            let order: [Range] = [.week, .month, .quarter, .year, .all]
            guard let i = order.firstIndex(of: self) else { return [.all] }
            return Array(order[i...])
        }
    }

    // MARK: - Formatting

    private func durationLabel(_ s: Double) -> String {
        let total = Int(s.rounded())
        let h = total / 3600, m = (total % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
    private func oneDecimal(_ v: Double) -> String { String(format: "%.1f", v) }
}

#if DEBUG
@MainActor
private func previewWorkoutRows() -> [WorkoutRow] {
    let now = Int(Date().timeIntervalSince1970)
    let day = 86_400
    return [
        WorkoutRow(startTs: now - day * 0 - 3600, endTs: now - day * 0, sport: "Running", source: "whoop",
                   durationS: 3600, energyKcal: 712, avgHr: 152, maxHr: 178, strain: 14.2, distanceM: 10_400,
                   zonesJSON: #"{"z1":12.5,"z2":28.0,"z3":33.5,"z4":18.0,"z5":6.0}"#, notes: nil),
        WorkoutRow(startTs: now - day * 1 - 2700, endTs: now - day * 1, sport: "Strength Training", source: "whoop",
                   durationS: 2700, energyKcal: 388, avgHr: 118, maxHr: 156, strain: 9.4, distanceM: nil,
                   zonesJSON: nil, notes: nil),
        WorkoutRow(startTs: now - day * 2 - 1800, endTs: now - day * 2, sport: "Cycling", source: "apple_health",
                   durationS: 1800, energyKcal: 240, avgHr: 134, maxHr: nil, strain: nil, distanceM: 12_800,
                   zonesJSON: nil, notes: nil),
        WorkoutRow(startTs: now - day * 4 - 2400, endTs: now - day * 4, sport: "Yoga", source: "manual",
                   durationS: 2400, energyKcal: nil, avgHr: nil, maxHr: nil, strain: nil, distanceM: nil,
                   zonesJSON: nil, notes: "Morning flow"),
    ]
}

#Preview("Workouts — con datos") {
    NavigationStack { WorkoutsView(previewRows: previewWorkoutRows()) }
        .environmentObject(Repository(deviceId: "preview"))
        .environmentObject(HealthKitBridge(repo: Repository(deviceId: "preview"), appleDeviceId: "a", noopDeviceId: "preview"))
}

#Preview("Workouts — vacío") {
    NavigationStack { WorkoutsView(previewRows: []) }
        .environmentObject(Repository(deviceId: "preview"))
        .environmentObject(HealthKitBridge(repo: Repository(deviceId: "preview"), appleDeviceId: "a", noopDeviceId: "preview"))
}
#endif
#endif
