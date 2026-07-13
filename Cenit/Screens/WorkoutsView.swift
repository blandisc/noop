#if os(iOS)
import SwiftUI
import StrandDesign
import StrandTraining
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
// Esqueleto Final (misma forma que `MetricDetailScreen.narrativeBodyFinal` / `SkinTempDetailScreen`):
// HeroInvertido → range control on paper → SeccionBloque tiles / By sport / Sessions → PieMetodo.
// Full-bleed (franjas edge-to-edge). Math and windowing are preserved; this is a reskin.
//
// Destilado a: héroe (conteo) · filtro de rango (+ auto-ampliación) · apoyos (horas/kcal) ·
// «Por deporte» (lista quieta) · «Sesiones» (tarjetas tap-eables). La barra de zonas agregada se movió al
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
    /// Strength-tracker sessions + their Σ weight×reps volume (FER-821) — the ONLY source of workout
    /// volume. `WorkoutRow` (Apple/journal cache) has no load field, so the «Volume» tile and the
    /// weekly-volume chart aggregate these instead. Loaded alongside `allRows` in `.task`.
    @State private var strengthSessions: [StrengthSession] = []
    @State private var sessionVolumes: [String: (volumeKg: Double, setCount: Int)] = [:]
    @State private var sheet: WorkoutSheetTarget?
    /// Opens the (legacy dark) Data Sources screen from the empty state / the connect line. Self-contained.
    @State private var showDataSources = false

    /// `.some(nil)` = add a new workout, `.some(row)` = edit `row`, `nil` = closed.
    private struct WorkoutSheetTarget: Identifiable { let editing: WorkoutRow?; let id = UUID() }

    init(previewRows: [WorkoutRow]? = nil,
         previewStrengthSessions: [StrengthSession] = [],
         previewSessionVolumes: [String: (volumeKg: Double, setCount: Int)] = [:]) {
        _allRows = State(initialValue: previewRows ?? [])
        _loaded = State(initialValue: previewRows != nil)
        _strengthSessions = State(initialValue: previewStrengthSessions)
        _sessionVolumes = State(initialValue: previewSessionVolumes)
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
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }.foregroundStyle(theme.ink)
            }
            ToolbarItem(placement: .primaryAction) {
                Button { addWorkout() } label: { StrandIcon.add.image }
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
            ManualWorkoutSheet(editing: target.editing, theme: theme) { row, replacing in
                Task { await repo.saveManualWorkout(row, replacing: replacing); await reload() }
            }
        }
        .sheet(isPresented: $showDataSources) { dataSourcesSheet }
        .task {
            guard !loaded else { return }
            let r = await repo.workoutRows()
            // Strength volume (FER-821) loads in parallel with the journal rows; it never gates the
            // loaded/empty state — a user with workouts but no strength sessions still lands on `populated`.
            async let sessions = repo.recentSessions()
            async let volumes = repo.sessionVolumes()
            allRows = r
            strengthSessions = await sessions
            sessionVolumes = await volumes
            loaded = true
            range = defaultRange(for: r)
        }
        .onAppear { if loaded { range = defaultRange(for: allRows) } }
    }

    // MARK: - Populated (Final skeleton)

    private var populated: some View {
        // Compute the windowed rows + per-sport groups ONCE per body (SwiftUI re-runs body on every
        // state tick); thread them into each section. Same windowing as before.
        let resolved = effectiveRange
        let windowRows = sessions(for: resolved)
        let groups = sportGroups(from: windowRows)
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                heroFinal(rows: windowRows, effectiveRange: resolved)
                // Segmented range control lives on paper BELOW the inverted hero: HeroInvertido has no
                // slot for an interactive @State binding control (same pattern as streak chip on SkinTemp).
                SegmentedPillControl(Range.allCases, selection: $range, theme: theme) { $0.label }
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                    .padding(.bottom, 4)
                totalsSection(rows: windowRows, effectiveRange: resolved)
                volumeByWeekSection
                SeccionBloque(String(localized: "By sport"), theme: theme) {
                    bySportSection(groups: groups)
                }
                SeccionBloque(String(localized: "Sessions"),
                              pista: "\(windowRows.count)",
                              theme: theme) {
                    sessionsSection(rows: windowRows)
                }
                healthHint
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                pieMetodoFinal
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Hero Final (HeroInvertido · dataStrain · session count)

    private func heroFinal(rows: [WorkoutRow], effectiveRange: Range) -> some View {
        let fellBack = effectiveRange != range
        let n = rows.count
        return HeroInvertido(
            glyph: .workouts,
            title: "My workouts",
            hue: theme.dataStrain,
            theme: theme,
            numeral: {
                HeroNumeral("\(n)",
                            suffix: n == 1 ? String(localized: "session") : String(localized: "sessions"),
                            size: 60,
                            theme: theme)
            },
            verdict: {
                Text(rangeCaption(count: n, effectiveRange: effectiveRange, fellBack: fellBack))
                    .font(InstrumentoType.grotesk(15, weight: .semibold))
                    .foregroundStyle(fellBack ? theme.warning : theme.paper)
                    .fixedSize(horizontal: false, vertical: true)
            }
        )
    }

    private func rangeCaption(count: Int, effectiveRange: Range, fellBack: Bool) -> String {
        let unit = count == 1 ? String(localized: "session") : String(localized: "sessions")
        let countUnit = "\(count) \(unit)"
        if fellBack {
            return String(format: String(localized: "%@ · sparse: widened to %@"), countUnit, effectiveRange.caption)
        }
        return "\(countUnit) · \(effectiveRange.caption)"
    }

    // MARK: - Totals (hours · volume placeholder · kcal) — TileSurface strip

    /// Window totals for the selected (effective) range. Volume kg is not on `WorkoutRow`, so the volume
    /// tile aggregates strength-tracker sessions (FER-821) over the SAME time window as Hours/Kcal.
    private func totalsSection(rows: [WorkoutRow], effectiveRange: Range) -> some View {
        let totalTimeH = rows.compactMap(\.durationS).reduce(0, +) / 3600.0
        let kcalValues = rows.compactMap(\.energyKcal)
        let totalKcal: String = {
            guard !kcalValues.isEmpty else { return "—" }
            return "\(Int(kcalValues.reduce(0, +).rounded()))"
        }()
        let volKg = strengthVolumeKg(in: effectiveRange)
        let volValue = volKg > 0 ? StrengthHistoryFormat.volume(volKg, system: unitSystem) : "—"
        return SeccionBloque(String(localized: "This period"),
                             pista: effectiveRange.caption,
                             theme: theme) {
            HStack(alignment: .top, spacing: 8) {
                TileSurface(
                    label: String(localized: "Hours"),
                    value: oneDecimal(totalTimeH) + "h",
                    theme: theme
                )
                // Volume comes from strength-tracker sessions only (Σ weight×reps); tinted amber to tie it
                // to the weekly-volume chart below. «—» when the window holds no strength volume.
                TileSurface(
                    label: String(localized: "Volume"),
                    value: volValue,
                    valueColor: volKg > 0 ? theme.dataStrain : nil,
                    theme: theme
                )
                TileSurface(
                    label: String(localized: "Kcal"),
                    value: totalKcal,
                    theme: theme
                )
            }
        }
    }

    // MARK: - Volume by week (8 bars, strength-tracker volume — FER-821)

    /// Weekly strength volume over the last 8 Monday-anchored weeks, the current week in amber. Hidden
    /// entirely when every week is zero (no all-flat chart). Mirrors `WorkoutHistoryScreen.weeklyBars`.
    @ViewBuilder private var volumeByWeekSection: some View {
        let weeks = weeklyStrengthVolumes()
        if weeks.contains(where: { $0.volumeKg > 0 }) {
            let peak = max(weeks.map(\.volumeKg).max() ?? 1, 1)
            SeccionBloque(String(localized: "Volume by week"),
                          pista: String(localized: "8 wk"),
                          theme: theme) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .bottom, spacing: 6) {
                        ForEach(weeks) { w in
                            RoundedRectangle(cornerRadius: 3, style: .continuous) // token-exempt: geometría de dato
                                .fill(w.isCurrent ? theme.dataStrain : theme.hairlineStrong)
                                .frame(height: max(3, CGFloat(w.volumeKg / peak) * 54))
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: 54)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("Volume over the last 8 weeks"))
                    BarraAncla(String(localized: "This week in amber · strength volume, last 8 weeks"),
                               color: theme.dataStrain, theme: theme)
                }
            }
        }
    }

    private struct WeekVolume: Identifiable { let id: Int; let volumeKg: Double; let isCurrent: Bool }

    /// Total strength volume per week over the last 8 weeks (oldest→newest), Monday-anchored; last bucket
    /// = current week. Same bucketing as `WorkoutHistoryScreen.weeklyVolumes`.
    private func weeklyStrengthVolumes() -> [WeekVolume] {
        var cal = Calendar.current; cal.firstWeekday = 2
        let thisWeekStart = cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        var buckets = [Double](repeating: 0, count: 8)
        for s in strengthSessions {
            let date = Date(timeIntervalSince1970: TimeInterval(s.startTs))
            guard let ws = cal.dateInterval(of: .weekOfYear, for: date)?.start else { continue }
            let weeksAgo = cal.dateComponents([.weekOfYear], from: ws, to: thisWeekStart).weekOfYear ?? 0
            guard weeksAgo >= 0, weeksAgo < 8 else { continue }
            buckets[7 - weeksAgo] += sessionVolumes[s.id]?.volumeKg ?? 0
        }
        return buckets.enumerated().map { WeekVolume(id: $0.offset, volumeKg: $0.element, isCurrent: $0.offset == 7) }
    }

    /// Σ strength volume for sessions whose `startTs` falls in the SAME window as the Hours/Kcal tiles
    /// (cutoff = latest workout-row ts − range days; no cutoff for `.all`), so the tile tracks the range.
    private func strengthVolumeKg(in r: Range) -> Double {
        let inWindow: [StrengthSession]
        if let days = r.days, let last = latestTs {
            let cutoff = last - days * 86_400
            inWindow = strengthSessions.filter { $0.startTs >= cutoff }
        } else {
            inWindow = strengthSessions
        }
        return inWindow.reduce(0) { $0 + (sessionVolumes[$1.id]?.volumeKg ?? 0) }
    }

    // MARK: - By sport (quiet list — no card-in-card; markup preserved inside SeccionBloque)

    private func bySportSection(groups: [SportGroup]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(groups.enumerated()), id: \.element.id) { idx, g in
                HStack(spacing: 12) {
                    Image(systemName: WorkoutSource.sfSymbol(for: g.sport))
                        .font(StrandFont.glyph(.inline, weight: .medium)).foregroundStyle(theme.inkSecondary)
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

    // MARK: - Sessions (TarjetaSesion A → detail)

    private func sessionsSection(rows: [WorkoutRow]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                NavigationLink(value: row) {
                    sessionCard(row)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Variant-A session card. Volume column omitted: WorkoutRow has no kg load field (see totals tile).
    /// Colored `workoutSourceBadge` does not map 1:1 onto TarjetaSesion chrome; source label goes in `chip`.
    private func sessionCard(_ row: WorkoutRow) -> some View {
        let duration = WorkoutFormat.duration(row.durationS ?? Double(max(0, row.endTs - row.startTs)))
        var metrics: [TarjetaSesion.Metric] = [
            .init(value: duration, label: String(localized: "Duration"))
        ]
        // No per-row volume: rows are `WorkoutRow` (journal), with no reliable join to strength sessions.
        if let s = row.strain, s > 0 {
            metrics.append(.init(
                value: String(format: "%.1f", s),
                label: String(localized: "Effort"),
                color: theme.dataStrain
            ))
        } else if let hr = row.avgHr {
            metrics.append(.init(
                value: "\(hr)",
                unit: "bpm",
                label: String(localized: "Avg HR"),
                color: theme.dataStrain
            ))
        }
        return TarjetaSesion(
            titulo: WorkoutSource.displaySport(row.sport),
            meta: "\(WorkoutFormat.date(row.startTs)) · \(WorkoutFormat.time(row.startTs))",
            chip: sourceChipKey(for: row.source),
            metrics: metrics,
            theme: theme
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// Plain source label for `TarjetaSesion.chip` (same taxonomy as `workoutSourceBadge`, without tint).
    private func sourceChipKey(for source: String) -> LocalizedStringKey {
        switch WorkoutSource.classify(source) {
        case .whoop:    return "Whoop"
        case .apple:    return "Apple"
        case .detected: return "Detected"
        case .manual:   return "Manual"
        }
    }

    // MARK: - PieMetodo (method + origin seal)

    @ViewBuilder private var pieMetodoFinal: some View {
        PieMetodo(theme: theme) {
            Metodo(title: String(localized: "How it's calculated"), theme: theme) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Each session is a workout from your WHOOP, Apple Health, or a manual entry. The count and totals follow the range you pick above (widened if that range is empty).")
                        .font(StrandFont.subhead)
                        .foregroundStyle(theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("They come from your WHOOP and Apple Health history. Import them in Data Sources, or add one you tracked elsewhere.")
                        .font(StrandFont.caption)
                        .foregroundStyle(theme.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } sello: {
            // Standardized origin seal (FER-805): the most recent session's source + when.
            if let latest = allRows.max(by: { $0.startTs < $1.startTs }) {
                OriginStamp(origin: latest.source.lowercased().contains("apple") ? .apple : .computed,
                            when: relativeAgo(Double(latest.startTs)), theme: theme)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 2)
            }
        }
    }

    // MARK: - Apple Health connect line (optional, never a wall)

    @ViewBuilder private var healthHint: some View {
        let notConnected = health.auth != .authorized && health.auth != .unavailable
        let noAppleSessions = !allRows.contains { WorkoutSource.classify($0.source) == .apple }
        if notConnected && noAppleSessions {
            Button { showDataSources = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "heart.fill").font(StrandFont.glyph(.chevron)).foregroundStyle(theme.dataSpO2)
                    Text("Connect Apple Health to bring in your workouts from there.")
                        .font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
                    Spacer(minLength: 6)
                    StrandIcon.disclosure.image.font(StrandFont.glyph(.chevron)).foregroundStyle(theme.inkTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Empty state (onboarding — not a dead end)

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "figure.run").font(.system(size: 38, weight: .regular))  // token-exempt: glifo 38pt fuera de banda empty
                .foregroundStyle(theme.inkTertiary).accessibilityHidden(true)
            Text("No workouts yet").font(StrandFont.title2).foregroundStyle(theme.ink)
                .multilineTextAlignment(.center)
            Text("They come from your WHOOP and Apple Health history. Import them in Data Sources, or add one you tracked elsewhere.")
                .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 300)
            QuietButton("Add workout") { addWorkout() }.padding(.top, 4)
            QuietButton("Data Sources") { showDataSources = true }
        }
        .padding(CenitMetrics.screenPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Data Sources bridge (light «Instrumento» screen, self-contained sheet)

    /// Data Sources, reskinned to the light «Instrumento» language (FER-338): a light sheet with its own
    /// NavigationStack (so «Ver datos importados» pushes the Apple Health viewer), the theme injected at
    /// the root (it doesn't cross the `.sheet` boundary, FER-162). A light sheet from a light tab keeps
    /// the status bar honest (no dark pin needed).
    private var dataSourcesSheet: some View {
        NavigationStack {
            DataSourcesView()
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(theme.paper, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showDataSources = false }.foregroundStyle(theme.ink)
                    }
                }
        }
        .instrumentoTheme(theme)
        .environmentObject(repo)
        .environmentObject(health)
        .preferredColorScheme(.light)
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

@MainActor
private func previewStrengthSessions() -> (sessions: [StrengthSession],
                                           volumes: [String: (volumeKg: Double, setCount: Int)]) {
    let now = Int(Date().timeIntervalSince1970)
    let week = 7 * 86_400
    // One strength session per week for the last 6 weeks (leaves 2 empty weeks so the chart isn't flat).
    let specs: [(weeksAgo: Int, vol: Double)] = [(0, 5_200), (1, 6_800), (2, 4_100), (3, 7_400), (4, 3_600), (5, 6_100)]
    var sessions: [StrengthSession] = []
    var volumes: [String: (volumeKg: Double, setCount: Int)] = [:]
    for (i, s) in specs.enumerated() {
        let id = "prev-strength-\(i)"
        let start = now - s.weeksAgo * week - 3600
        sessions.append(StrengthSession(id: id, startTs: start, endTs: start + 3600, strain: 9.1))
        volumes[id] = (volumeKg: s.vol, setCount: 18)
    }
    return (sessions, volumes)
}

@MainActor
private func previewWorkoutsPopulated() -> some View {
    let strength = previewStrengthSessions()
    return NavigationStack {
        WorkoutsView(previewRows: previewWorkoutRows(),
                     previewStrengthSessions: strength.sessions,
                     previewSessionVolumes: strength.volumes)
    }
    .environmentObject(Repository(deviceId: "preview"))
    .environmentObject(HealthKitBridge(repo: Repository(deviceId: "preview"), appleDeviceId: "a", noopDeviceId: "preview"))
}

#Preview("Workouts: con datos") {
    previewWorkoutsPopulated()
}

#Preview("Workouts: vacío") {
    NavigationStack { WorkoutsView(previewRows: []) }
        .environmentObject(Repository(deviceId: "preview"))
        .environmentObject(HealthKitBridge(repo: Repository(deviceId: "preview"), appleDeviceId: "a", noopDeviceId: "preview"))
}
#endif
#endif
