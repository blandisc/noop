#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import StrandTraining
import CenitStore   // WorkoutRow — the journal join that carries zones / max HR (FER-952)

// WorkoutHistoryScreen.swift — «Mis entrenamientos» (FER-504): the completed strength sessions, newest
// first, each opening a per-exercise breakdown. Read-only — it never edits or deletes a session. Pure
// «Instrumento diurno»: warm paper, weights/sets in ink, the only color on the *physiological* datum
// (effort/strain and heart rate, in `dataStrain`). The data already exists (strengthSession + setEntry,
// FER-345); this is the screen that finally surfaces it. Pushed onto the Entrenar NavigationStack.

/// A session pushed onto the train stack for its detail. Carries the scalar fields the detail header
/// needs (so it doesn't refetch the row); the per-exercise sets are loaded by the detail screen. A
/// distinct Hashable type so the type-erased `trainStack` carries it alongside the other routes.
struct WorkoutSessionRoute: Hashable {
    let id: String
    let startTs: Int
    let endTs: Int?
    let strain: Double?
    let avgHr: Int?
    let routineName: String
}

/// Route pushed onto the Entrenar stack for the saved thermal-receipts grid.
struct SavedTicketsRoute: Hashable {}


/// Cross-screen state for the workout-history stack (FER-556). The detail is a sibling pushed onto the
/// same NavigationStack as the list, not its child — so a delete or edit done in the detail can't reach
/// the list directly. This shared object bridges them: the detail seeds `pendingUndo` (the list shows the
/// «Undo» banner after the pop) and bumps `reloadToken` (the list reloads, since `.task` isn't re-run on
/// pop-back). Injected once on the Entrenar NavigationStack in RootTabView.
@MainActor final class WorkoutHistoryCoordinator: ObservableObject {
    /// A just-deleted session + its sets, kept so «Undo» can restore it intact (reused from FER-527).
    struct DeletedSession: Identifiable, Equatable {
        let id = UUID()
        let session: StrengthSession
        let sets: [SetEntry]
    }
    @Published var pendingUndo: DeletedSession?
    /// Bumped after an edit/delete deeper in the stack so the list refreshes when shown again.
    @Published var reloadToken = 0
    func bumpReload() { reloadToken &+= 1 }
}

// MARK: - List

struct WorkoutHistoryScreen: View {
    @Environment(\.instrumentoTheme) private var theme
    @EnvironmentObject private var repo: Repository
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    private var system: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }

    @EnvironmentObject private var coordinator: WorkoutHistoryCoordinator
    @State private var sessions: [StrengthSession] = []
    @State private var routineNames: [String: String] = [:]
    @State private var volumes: [String: (volumeKg: Double, setCount: Int)] = [:]
    /// Trailing-30-day muscle set events for the compact «Volume per muscle» summary (FER-719 math).
    @State private var muscleEvents: [MuscleFatigueMap.MuscleSetEvent] = []
    /// Progression signals (raised / waiting / stalled) for exercises with progression enabled.
    @State private var progressionRows: [ProgressionRow] = []
    /// Movement family per routine (for the session rows' glyph/tint) — classified once at load.
    @State private var routineRegions: [String: RoutineRegion] = [:]
    @State private var loaded = false
    /// FER-969 / X-05a: undo-restore write failure on the list.
    @State private var saveError = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CenitMetrics.sectionGap) {
                header
                if loaded {
                    if sessions.isEmpty {
                        emptyState
                    } else {
                        // Handoff v2: TU MES (card) → progression → muscle → sessions → tickets.
                        tuMes
                        progressionBlock
                        muscleVolumeInline
                        sessionsSection
                        savedTicketsEntry
                    }
                }
            }
            .padding(.top, 20)
            .padding(.horizontal, CenitMetrics.screenPadding)
            .padding(.bottom, CenitMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.paper.ignoresSafeArea())
        // The detail push (`WorkoutSessionRoute`) is registered once on the Entrenar NavigationStack in
        // RootTabView (alongside the other train routes), so it isn't re-declared here.
        // «Undo» toast after a delete (FER-527), now seeded by the list OR the detail via the coordinator.
        .overlay(alignment: .bottom) { if let d = coordinator.pendingUndo { undoBanner(d) } }
        // FER-969: undo-restore failure banner (delete itself lives on the detail screen).
        .overlay(alignment: .top) {
            if saveError {
                Text("Couldn't save the workout. Try again.")
                    .font(.system(size: 13))   // token-exempt: cuerpo de banner (13pt, igual que el mensaje de ConfirmCard)
                    .foregroundStyle(theme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .patternBlock(theme, bar: theme.critical)
                    .padding(.horizontal, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task {
                        try? await Task.sleep(for: .seconds(4))
                        saveError = false
                    }
            }
        }
        .animation(StrandMotion.fade, value: saveError)
        .sensoryFeedback(trigger: coordinator.pendingUndo?.id) { _, new in new != nil ? .warning : nil }
        // Reloads on first appear (token 0) and whenever a delete/edit deeper in the stack bumps it.
        .task(id: coordinator.reloadToken) { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Decisión Fer (2026-07-16): «On the rise» se retiró — el título principal es el nombre
            // de la pantalla, sin editorializar.
            InstrumentoFlowTitle(Text("My workouts"))
            // Handoff v2: sessions this month, plus the count of load raises when any (from progression).
            Group {
                if raisedThisMonth > 0 {
                    Text("\(monthAggregate.count) sessions this month · \(raisedThisMonth) load raises")
                } else {
                    Text("\(monthAggregate.count) sessions this month")
                }
            }
            .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - «TU MES» (handoff v2, FER-941) — the weekly-volume card + the three month tiles

    @State private var selectedWeek: Int? = nil   // nil / 7 = current week

    /// Split for type-check cost (FER-981): volume card + month tiles are separate ViewBuilders.
    private var tuMes: some View {
        VStack(alignment: .leading, spacing: 12) {
            InstrumentoSectionBand("Your month")
            tuMesVolumeCard
            tuMesMonthTiles
        }
    }

    /// Weekly volume card (header, bars, selected-week strip) — extracted so its CGFloat/ternary
    /// chains type-check alone (FER-981).
    @ViewBuilder
    private var tuMesVolumeCard: some View {
        let weeks: [WeekVolume] = weeklyVolumes
        let peakRaw: Double = weeks.map(\.volumeKg).max() ?? 1.0
        let peak: Double = max(peakRaw, 1.0)
        let selectedId: Int = selectedWeek ?? 7
        let sel: WeekVolume = weeks.first { (w: WeekVolume) in w.id == selectedId } ?? weeks[7]
        VStack(alignment: .leading, spacing: 10) {
            tuMesVolumeHeader
            tuMesWeeklyBars(weeks: weeks, peak: peak, selectedId: selectedId)
            tuMesSelectedWeekStrip(sel: sel)
        }
        .padding(CenitMetrics.cardPadding)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous)
            .strokeBorder(theme.hairline, lineWidth: 1))
    }

    @ViewBuilder
    private var tuMesVolumeHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Volume per week").font(StrandFont.subhead).fontWeight(.semibold).foregroundStyle(theme.ink)
            Spacer(minLength: 8)
            if let delta: Double = monthVolumeDeltaPercent {
                tuMesDeltaChip(delta: delta)
            }
        }
    }

    /// «↗ +N% / ↘ −N% vs. last month» chip — valence color pre-bound so the ternary isn't re-inferred
    /// on every modifier (FER-981).
    @ViewBuilder
    private func tuMesDeltaChip(delta: Double) -> some View {
        let up: Bool = delta >= 0
        let n: Int = abs(Int(delta.rounded()))
        let valence: Color = up ? theme.positiveText : theme.warning
        Group {
            if up { Text("↗ +\(n)% vs. last month") } else { Text("↘ −\(n)% vs. last month") }
        }
        .font(InstrumentoType.grotesk(11, weight: .bold))
        // §8.7: valence en texto <24pt usa positiveText (5.0:1), no el hue del dato.
        .foregroundStyle(valence)
        .padding(.horizontal, 9).padding(.vertical, 3)
        .background(valence.opacity(StrandOpacity.tintFill),
                    in: RoundedRectangle(cornerRadius: CenitMetrics.chipRadius, style: .continuous))
    }

    /// 8-week bar chart + axis labels. Bar height uses fully-typed CGFloat math (FER-981).
    private func tuMesWeeklyBars(weeks: [WeekVolume], peak: Double, selectedId: Int) -> some View {
        VStack(spacing: 4) {
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(weeks) { (w: WeekVolume) in
                    let isSelected: Bool = w.id == selectedId
                    let fill: Color = isSelected ? theme.dataRecovery : theme.hairlineStrong
                    let ratio: Double = w.volumeKg / peak
                    let barH: CGFloat = max(CGFloat(3), CGFloat(ratio) * CGFloat(54))
                    UnevenRoundedRectangle(topLeadingRadius: 3, topTrailingRadius: 3)  // token-exempt: geometría de dato
                        .fill(fill)
                        .frame(height: barH)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture { withAnimation(StrandMotion.interactive) { selectedWeek = w.id } }
                }
            }
            .frame(height: 58, alignment: .bottom)
            Rectangle().fill(theme.hairlineStrong).frame(height: 1.2)  // token-exempt: eje de dato
            HStack {
                Text(weekLabel(weeks.first?.start)).font(InstrumentoType.grotesk(9)).foregroundStyle(theme.inkTertiary)
                Spacer(minLength: 8)
                Text("this week").font(InstrumentoType.grotesk(9)).foregroundStyle(theme.inkTertiary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Volume over the last 8 weeks"))
    }

    @ViewBuilder
    private func tuMesSelectedWeekStrip(sel: WeekVolume) -> some View {
        let volumeText: String = StrengthHistoryFormat.volume(sel.volumeKg, system: system)
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 1) {
                Group {
                    if sel.isCurrent {
                        Text("This week · in progress").instrumentoOverline()
                    } else {
                        Text("Week of \(weekLabel(sel.start))").instrumentoOverline()
                    }
                }
                .foregroundStyle(theme.inkTertiary)
                Text("\(sel.count) sessions · tap another bar to switch")
                    .font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
            }
            Spacer(minLength: 10)
            Text(volumeText)
                .font(InstrumentoType.groteskNumber(17)).foregroundStyle(theme.ink)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(theme.patternBlock, in: RoundedRectangle(cornerRadius: CenitMetrics.insetRadius, style: .continuous))
    }

    /// The three month tiles (Sessions / Hours / Energy) with pre-formatted strings (FER-981).
    @ViewBuilder
    private var tuMesMonthTiles: some View {
        let m: MonthAggregate = monthAggregate
        let sessionsValue: String = "\(m.count)"
        let hoursValue: String = m.hours > 0 ? String(format: "%.1f", m.hours) : "—"
        let energyValue: String = m.energyKcal.map(StrandFormat.groupedInt) ?? "—"
        let energyUnit: LocalizedStringKey? = m.energyKcal != nil ? "kcal" : nil
        HStack(spacing: 8) {
            monthTile("Sessions", sessionsValue, caption: "this month")
            monthTile("Hours", hoursValue, caption: "trained")
            monthTile("Energy", energyValue, unit: energyUnit, caption: "measured")
        }
    }

    private func monthTile(_ label: LocalizedStringKey, _ value: String,
                           unit: LocalizedStringKey? = nil, caption: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).instrumentoOverline().foregroundStyle(theme.inkTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(InstrumentoType.groteskNumber(22)).foregroundStyle(theme.ink)
                if let unit { Text(unit).font(StrandFont.caption).foregroundStyle(theme.inkTertiary) }
            }
            Text(caption).font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: CenitMetrics.controlRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: CenitMetrics.controlRadius, style: .continuous)
            .strokeBorder(theme.hairline, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    /// «18 may» — a week-start date as the axis/strip label.
    private func weekLabel(_ d: Date?) -> String {
        guard let d else { return "" }
        return d.formatted(.dateTime.day().month(.abbreviated)).lowercased()
    }

    // MARK: - «VOLUMEN POR MÚSCULO · 30 DÍAS» (handoff v2, FER-941)
    //
    // Top four muscles by weekly work sets plus the weakest one, each with a proportional bar in its
    // movement-family tint; «Ver mapa» rides the band. The honest footnote names the neglected muscle.

    @ViewBuilder
    private var muscleVolumeInline: some View {
        let all = MuscleFatigueMap.weeklyVolumes(events: muscleEvents, days: 30)
        if !all.isEmpty {
            let sorted = all.sorted { $0.setsPerWeek > $1.setsPerWeek }
            let shown = muscleRowsToShow(sorted)
            let weakest = sorted.last
            let maxV = max(sorted.first?.setsPerWeek ?? 1, 0.1)
            VStack(alignment: .leading, spacing: 9) {
                InstrumentoSectionBand("Volume per muscle · 30 days") {
                    NavigationLink(value: MuscleVolumeRoute()) {
                        Text("See map").font(StrandFont.subhead).foregroundStyle(theme.ink)
                            .frame(minHeight: 44)   // toque 44 (HIG §8.7-4)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                ForEach(shown, id: \.muscle) { v in
                    HStack(spacing: 10) {
                        Text(MuscleAtlas.name(v.muscle))
                            .font(StrandFont.footnote).foregroundStyle(theme.inkSecondary)
                            .lineLimit(1).minimumScaleFactor(0.8)
                            .frame(width: 86, alignment: .leading)
                        Capsule().fill(theme.patternBlock)
                            .frame(height: 12)
                            .overlay(alignment: .leading) {
                                GeometryReader { geo in
                                    Capsule()
                                        .fill(v.setsPerWeek <= 0 ? theme.hairlineStrong : muscleTint(v.muscle))
                                        .frame(width: max(6, geo.size.width * CGFloat(min(v.setsPerWeek, maxV) / maxV)))
                                }
                            }
                            .clipShape(Capsule())
                        Text(MuscleFatigueMap.formattedSets(v.setsPerWeek))
                            .font(InstrumentoType.grotesk(12, weight: .semibold)).foregroundStyle(theme.inkSecondary)
                            .frame(minWidth: 34, alignment: .trailing).lineLimit(1)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(MuscleAtlas.name(v.muscle)))
                    .accessibilityValue(Text("\(MuscleFatigueMap.formattedSets(v.setsPerWeek)) sets per week"))
                }
                BarraAncla(muscleNote(weakest), color: theme.inkTertiary, theme: theme)
            }
        }
    }

    /// Top four by weekly sets, plus the weakest one (the honest tail) when it isn't already shown.
    private func muscleRowsToShow(_ sorted: [MuscleFatigueMap.MuscleWeeklyVolume]) -> [MuscleFatigueMap.MuscleWeeklyVolume] {
        var shown = Array(sorted.prefix(4))
        if let weakest = sorted.last, !shown.contains(where: { $0.muscle == weakest.muscle }) { shown.append(weakest) }
        return shown
    }

    /// «Series de trabajo por grupo.» + the neglected muscle when one sits at zero.
    private func muscleNote(_ weakest: MuscleFatigueMap.MuscleWeeklyVolume?) -> String {
        guard let weakest, weakest.setsPerWeek <= 0 else { return String(localized: "Work sets per muscle.") }
        return String(localized: "Work sets per muscle. \(MuscleAtlas.name(weakest.muscle)) has no volume in 30 days.")
    }

    /// The movement-family tint for a muscle key (push=ember · pull=teal · legs=indigo; else ink-ish).
    private func muscleTint(_ muscle: String) -> Color {
        // r21: mapeo PROMOVIDO a StrandDesign (`movementFamilyTint`) — una sola fuente de verdad.
        theme.movementFamilyTint(primaryMuscles: [muscle])
    }

    // MARK: - Your progression (raised / waiting / stalled signals)

    @ViewBuilder
    private var progressionBlock: some View {
        if !progressionRows.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                InstrumentoSectionBand("Your progression")
                ForEach(progressionRows) { row in
                    HStack(spacing: 10) {
                        Text(row.name)
                            .font(StrandFont.body).foregroundStyle(theme.ink)
                            .lineLimit(1).minimumScaleFactor(0.85)
                        Spacer(minLength: 8)
                        switch row.kind {
                        case .raised(let kg):
                            HStack(spacing: 4) {
                                StrandIcon.up.image
                                Text(StrengthDisplay.weight(kg, system: system))
                            }
                            .font(StrandFont.caption)
                            .foregroundStyle(theme.positiveText)   // §8.7 valence <24pt
                            .monospacedDigit()
                        case .deferred(let kg):
                            HStack(spacing: 4) {
                                Text("…")
                                Text(StrengthDisplay.weight(kg, system: system))
                            }
                            .font(StrandFont.caption)
                            .foregroundStyle(theme.inkTertiary)
                            .monospacedDigit()
                        case .stalled:
                            Text("=")
                                .font(StrandFont.caption)
                                .foregroundStyle(theme.warning)
                        }
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                }
                BarraAncla(String(localized: "What rose, what waits on recovery, and what stalled."),
                           color: theme.dataRecovery, theme: theme)
            }
        }
    }

    private var sessionsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            InstrumentoSectionBand("Sessions")
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(sessions) { session in
                    NavigationLink(value: route(for: session)) {
                        sessionRow(session)
                    }
                    .buttonStyle(.plain)
                    // The long-press delete `contextMenu` was retired (FER-951): iOS draws it as a
                    // system balloon that ignores the theme; «Delete» lives in the detail's «···» menu.
                    if session.id != sessions.last?.id { Divider().overlay(theme.hairline) }
                }
            }
        }
    }

    /// Handoff v2 session row: family glyph chip · name + «vie 10 jul · 48 min · 4.320 kg» · one right
    /// datum (effort in the strain hue, else kcal, else the honest «—»). Replaces the tall cards.
    private func sessionRow(_ session: StrengthSession) -> some View {
        HStack(spacing: 12) {
            RoutineRegionGlyph(sessionGlyph(session), tint: sessionTint(session))
                .frame(width: 22, height: 22)
                .frame(width: 38, height: 38)
                .background(theme.patternBlock, in: RoundedRectangle(cornerRadius: CenitMetrics.insetRadius, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(name(for: session)).font(StrandFont.subhead).fontWeight(.semibold).foregroundStyle(theme.ink)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Text(sessionMeta(session)).font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 8)
            if let strain = session.strain {
                Text(StrengthHistoryFormat.strain(strain))
                    .font(InstrumentoType.grotesk(13, weight: .bold)).foregroundStyle(theme.dataStrain)
            } else if let k = session.energyKcal {
                (Text(StrandFormat.groupedInt(k)) + Text(verbatim: " ") + Text("kcal"))
                    .font(InstrumentoType.grotesk(13, weight: .bold)).foregroundStyle(theme.inkSecondary)
            } else {
                Text(verbatim: "—").font(InstrumentoType.grotesk(13, weight: .bold)).foregroundStyle(theme.inkTertiary)
            }
        }
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }

    /// «vie 10 jul · 48 min · 4.320 kg» — everything the old card said, in one quiet line.
    private func sessionMeta(_ session: StrengthSession) -> String {
        var parts: [String] = [Date(timeIntervalSince1970: TimeInterval(session.startTs))
            .formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)).lowercased()]
        if let mins = StrengthHistoryFormat.durationMinutes(start: session.startTs, end: session.endTs) {
            parts.append(StrengthHistoryFormat.durationText(mins))
        }
        if let vol = volumes[session.id], vol.volumeKg > 0 {
            parts.append(StrengthHistoryFormat.volume(vol.volumeKg, system: system))
        }
        return parts.joined(separator: " · ")
    }

    /// The session routine's movement family (loaded per routine in `load()`); routine-less → dumbbell.
    private func sessionGlyph(_ session: StrengthSession) -> RoutineGlyphKind {
        guard let rid = session.routineId, let region = routineRegions[rid] else { return .fullBody }
        switch region {
        case .push: return .push
        case .pull: return .pull
        case .legs: return .legs
        case .fullBody: return .fullBody
        }
    }

    private func sessionTint(_ session: StrengthSession) -> Color {
        guard let rid = session.routineId else { return theme.dataStrain }
        return routineRegions[rid].tint(theme)
    }

    // MARK: - Saved tickets entry (thermal receipts peek)

    private var savedTicketsEntry: some View {
        VStack(alignment: .leading, spacing: 12) {
            InstrumentoSectionBand("My saved tickets")
            NavigationLink(value: SavedTicketsRoute()) {
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: CenitMetrics.insetRadius, style: .continuous)
                        .fill(theme.hairline)
                        .frame(width: 38, height: 38)
                        .overlay(
                            Image(systemName: "doc.plaintext")
                                .font(StrandFont.glyph(.inline, weight: .semibold))
                                .foregroundStyle(theme.ink)
                        )
                    VStack(alignment: .leading, spacing: 2) {
                        Text("My saved tickets").font(StrandFont.title2).foregroundStyle(theme.ink)
                        Text("\(sessions.count) receipts · today's on top")
                            .font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
                    }
                    Spacer(minLength: 8)
                    StrandIcon.disclosure.image
                        .font(StrandFont.glyph(.chevron, weight: .semibold))
                        .foregroundStyle(theme.inkTertiary)
                }
                .padding(CenitMetrics.cardPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.surface, in: RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous)
                    .strokeBorder(theme.hairline, lineWidth: 1))
            }
            .buttonStyle(.plain)

            HStack(spacing: 10) {
                ForEach(Array(sessions.prefix(3).enumerated()), id: \.element.id) { index, session in
                    MiniTicketView(ticket: TicketMapping.miniTicket(
                        for: session,
                        index: index,
                        routineName: session.routineId.flatMap { routineNames[$0] },
                        volumeKg: volumes[session.id]?.volumeKg ?? 0,
                        system: system
                    ))
                    .frame(width: 110)
                }
            }

            BarraAncla(
                String(localized: "Each session saves its receipt. Open them to reprint or share."),
                color: theme.dataStrain,
                theme: theme
            )
        }
    }

    private var emptyState: some View {
        VStack(spacing: 11) {
            Image(systemName: "clock.arrow.circlepath")
                .font(StrandFont.glyph(.empty)).foregroundStyle(theme.inkTertiary)
                .accessibilityHidden(true)
            Text("No workouts yet").font(StrandFont.title2).foregroundStyle(theme.ink)
            Text("When you finish a strength session, it shows up here with its breakdown, volume and effort.")
                .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
    }

    // MARK: - Monthly + weekly aggregates (v3 · 1m)

    private struct MonthAggregate { let count: Int; let hours: Double; let volumeKg: Double; let energyKcal: Double? }

    /// One row in «Your progression»: an exercise whose cycle is raised, deferred, or stalled.
    private struct ProgressionRow: Identifiable {
        enum Kind {
            case raised(newKg: Double)
            case deferred(newKg: Double)
            case stalled
        }
        let id: String
        let name: String
        let kind: Kind
    }

    /// Count of exercises whose cycle just raised (the hero's «N subidas de carga»), from the same
    /// progression signals the «Your progression» block shows.
    private var raisedThisMonth: Int {
        progressionRows.filter { if case .raised = $0.kind { return true }; return false }.count
    }

    /// This calendar month's totals across finished sessions. kcal sums only sessions that carry it; nil
    /// when none do (so the cell is omitted rather than showing a partial or zero total).
    private var monthAggregate: MonthAggregate { aggregate(forMonthOf: Date()) }

    /// Previous calendar month's totals — same pattern as `monthAggregate`, one month back.
    private var previousMonthAggregate: MonthAggregate {
        let cal = Calendar.current
        let prev = cal.date(byAdding: .month, value: -1, to: Date()) ?? Date.distantPast
        return aggregate(forMonthOf: prev)
    }

    /// Percent volume change this month vs last. nil when either side has no volume (avoids ÷0 / ∞%).
    private var monthVolumeDeltaPercent: Double? {
        let this = monthAggregate.volumeKg
        let prev = previousMonthAggregate.volumeKg
        guard prev > 0, this > 0 else { return nil }
        return (this - prev) / prev * 100
    }

    private func aggregate(forMonthOf reference: Date) -> MonthAggregate {
        let cal = Calendar.current
        let inMonth = sessions.filter {
            cal.isDate(Date(timeIntervalSince1970: TimeInterval($0.startTs)), equalTo: reference, toGranularity: .month)
        }
        var seconds = 0
        var kcal = 0.0
        var hasKcal = false
        var vol = 0.0
        for s in inMonth {
            if let end = s.endTs, end > s.startTs { seconds += end - s.startTs }
            if let k = s.energyKcal { kcal += k; hasKcal = true }
            vol += volumes[s.id]?.volumeKg ?? 0
        }
        return MonthAggregate(count: inMonth.count, hours: Double(seconds) / 3600,
                              volumeKg: vol, energyKcal: hasKcal ? kcal : nil)
    }

    private struct WeekVolume: Identifiable { let id: Int; let volumeKg: Double; let count: Int; let start: Date?; let isCurrent: Bool }

    /// Total volume per week over the last 8 weeks (oldest→newest), Monday-anchored. The last bucket is
    /// the current week (drawn in `dataRecovery`).
    private var weeklyVolumes: [WeekVolume] {
        var cal = Calendar.current; cal.firstWeekday = 2
        let thisWeekStart = cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        var buckets = [Double](repeating: 0, count: 8)
        var counts = [Int](repeating: 0, count: 8)
        for s in sessions where s.endTs != nil {
            let date = Date(timeIntervalSince1970: TimeInterval(s.startTs))
            guard let ws = cal.dateInterval(of: .weekOfYear, for: date)?.start else { continue }
            let weeksAgo = cal.dateComponents([.weekOfYear], from: ws, to: thisWeekStart).weekOfYear ?? 0
            guard weeksAgo >= 0, weeksAgo < 8 else { continue }
            buckets[7 - weeksAgo] += volumes[s.id]?.volumeKg ?? 0
            counts[7 - weeksAgo] += 1
        }
        return buckets.enumerated().map { i, kg in
            WeekVolume(id: i, volumeKg: kg, count: counts[i],
                       start: cal.date(byAdding: .weekOfYear, value: i - 7, to: thisWeekStart),
                       isCurrent: i == 7)
        }
    }

    // MARK: - Derived

    private func name(for session: StrengthSession) -> String {
        session.routineId.flatMap { routineNames[$0] } ?? String(localized: "Strength workout")
    }

    private func route(for session: StrengthSession) -> WorkoutSessionRoute {
        WorkoutSessionRoute(id: session.id, startTs: session.startTs, endTs: session.endTs,
                            strain: session.strain, avgHr: session.avgHr, routineName: name(for: session))
    }

    // MARK: - Delete / undo (FER-527)

    private func undoDelete(_ d: WorkoutHistoryCoordinator.DeletedSession) {
        Task {
            do {
                try await repo.saveSession(d.session, sets: d.sets)   // re-saving re-derives its PRs
                await load()
                withAnimation { coordinator.pendingUndo = nil }
            } catch {
                // Keep the Undo banner so the user can retry; surface the write failure.
                saveError = true
            }
        }
    }

    private func undoBanner(_ d: WorkoutHistoryCoordinator.DeletedSession) -> some View {
        HStack(spacing: 12) {
            Text("Workout deleted").font(StrandFont.subhead).foregroundStyle(theme.surface)
            Spacer(minLength: 8)
            Button { undoDelete(d) } label: {
                Text("Undo").font(StrandFont.headline).foregroundStyle(theme.surface)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .background(theme.ink, in: RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous))
        .padding(.horizontal, CenitMetrics.screenPadding)
        .padding(.bottom, 8)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .task(id: d.id) {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            withAnimation { if coordinator.pendingUndo?.id == d.id { coordinator.pendingUndo = nil } }
        }
    }

    private func load() async {
        async let s = repo.recentSessions()
        async let r = repo.routines()
        async let v = repo.sessionVolumes()
        // Compact muscle summary: trailing 30 days (not the full year the dedicated screen fetches).
        let cal = Calendar.current
        let muscleSinceTs: Int = {
            guard let d = cal.date(byAdding: .day, value: -30, to: cal.startOfDay(for: Date())) else { return 0 }
            return Int(d.timeIntervalSince1970)
        }()
        async let muscle = repo.muscleSetEvents(sinceTs: muscleSinceTs)
        let (sessions, routines, volumes, muscleEvents) = await (s, r, v, muscle)
        self.sessions = sessions
        self.routineNames = Dictionary(routines.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        self.volumes = volumes
        self.muscleEvents = muscleEvents
        self.loaded = true
        // Classify each routine's movement family for the session rows (same resolution as the hub).
        if let store = await repo.storeHandle() {
            var regions: [String: RoutineRegion] = [:]
            let custom = (try? await store.customExercises()) ?? []
            let customByID = Dictionary(custom.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            for r in routines {
                let exs = (try? await store.routineExercises(routineId: r.id)) ?? []
                let perExercise = exs.compactMap { re in
                    (ExerciseCatalog.byID(re.exerciseId) ?? customByID[re.exerciseId])?.primaryMuscles
                }
                if let cat = RoutineClassifier.classify(primaryMusclesPerExercise: perExercise) {
                    regions[r.id] = cat
                }
            }
            self.routineRegions = regions
        }
        // Progression can take a beat (routines × exercises); paint the rest of the screen first.
        self.progressionRows = await loadProgressionRows()
    }

    /// Exercises with progression enabled (deduped by exerciseId, first routine slot wins — same rule as
    /// ExerciseDetailScreen), classified into raised / deferred / stalled. Cap ~6 rows.
    private func loadProgressionRows() async -> [ProgressionRow] {
        let inventory = await MainActor.run { PlatesStore().inventory }
        let recovery = repo.today?.recovery
        let routines = await repo.routines()
        var seen = Set<String>()
        var slots: [RoutineExercise] = []
        for r in routines {
            let exs = await repo.routineExercises(routineId: r.id)
            for re in exs where re.progressionEnabled {
                if seen.insert(re.exerciseId).inserted { slots.append(re) }
            }
        }
        var rows: [ProgressionRow] = []
        for re in slots {
            let ex = await repo.resolvedExercise(re.exerciseId)
            let seed = await repo.sessionSeed(re: re, exercise: ex, inventory: inventory, recovery: recovery)
            guard let eval = seed.evaluation else { continue }
            let name = ex.map(StrengthDisplay.name) ?? re.exerciseId
            switch eval.state {
            case .readyToAdvance(let newKg):
                rows.append(.init(id: re.exerciseId, name: name, kind: .raised(newKg: newKg)))
            case .deferred(let newKg):
                rows.append(.init(id: re.exerciseId, name: name, kind: .deferred(newKg: newKg)))
            case .stalled(_), .deloading(_, _):
                rows.append(.init(id: re.exerciseId, name: name, kind: .stalled))
            case .inCycle:
                break
            }
            if rows.count >= 6 { break }
        }
        return rows
    }
}

// MARK: - Detail (per-exercise breakdown of one session)

struct WorkoutSessionDetailScreen: View {
    let route: WorkoutSessionRoute
    /// Opens a routine on the unified «Rutina» editor — «Duplicar como rutina» lands there after saving
    /// (FER-840). Injected by RootTabView (it owns the Entrenar stack); nil in contexts with no stack.
    var openRoutine: ((String) -> Void)? = nil

    @Environment(\.instrumentoTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var repo: Repository
    @Environment(AppModel.self) private var model
    @EnvironmentObject private var coordinator: WorkoutHistoryCoordinator
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    private var system: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }

    /// Drives «Duplicar como rutina» — a routine builder pre-filled with this session's exercises (2A).
    @State private var showDuplicate = false
    /// The routine the duplicate-builder just created; pushed onto «Rutina» when its sheet finishes
    /// dismissing (pushing mid-dismiss stacks transitions, FER-171 lesson).
    @State private var savedRoutineId: String? = nil

    /// Work sets grouped by exercise, in the order they were performed.
    @State private var groups: [(exerciseId: String, name: String, sets: [SetEntry])] = []
    /// Resolved exercises by id, so tapping a block opens its detail (FER-517).
    @State private var exercisesByID: [String: Exercise] = [:]
    /// The session's routine exercises (when it came from a saved routine), keyed by exerciseId — feeds the
    /// superset identification (v3 · 2A, FER-718). Empty for off-plan/one-off sessions.
    @State private var routineExercises: [RoutineExercise] = []
    /// Stored best-per-metric records per exercise, so a set that IS a personal best is flagged (2A).
    @State private var prsByExercise: [String: [PersonalRecord]] = [:]
    /// The exercise whose detail sheet is open (nil = none).
    @State private var detailExercise: Exercise?
    @State private var volumeKg: Double = 0
    @State private var setCount = 0
    @State private var loaded = false
    /// The full session row (incl. notes/routineId the route doesn't carry) — seeds the edit sheet (FER-556).
    @State private var fullSession: StrengthSession?
    @State private var allSets: [SetEntry] = []
    @State private var routineNames: [String: String] = [:]
    @State private var showEdit = false
    @State private var showDeleteConfirm = false
    @State private var showMoreMenu = false
    @State private var saveError = false

    // Display prefers the reloaded `fullSession` (so an edit's new date/routine shows at once), falling
    // back to the immutable route while it loads (FER-556).
    private var dispStart: Int { fullSession?.startTs ?? route.startTs }
    private var dispEnd: Int? { fullSession.map(\.endTs) ?? route.endTs }
    private var dispStrain: Double? { fullSession.map(\.strain) ?? route.strain }
    private var dispAvgHr: Int? { fullSession.map(\.avgHr) ?? route.avgHr }
    /// Energy is only on the full row (the route doesn't carry it). nil for a pre-v26 session (FER-715/718).
    private var dispEnergyKcal: Double? { fullSession?.energyKcal }
    private var dispRoutineName: String {
        guard let s = fullSession else { return route.routineName }
        return s.routineId.flatMap { routineNames[$0] } ?? String(localized: "Strength workout")
    }
    private var dispRoutineId: String? { fullSession?.routineId }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CenitMetrics.sectionGap) {
                heading
                hero
                // Handoff «Progreso C» (FER-952): zones ramp → FC media/máx → supports → note → source,
                // each block on a thin hairline.
                if let zones = WorkoutZones.percents(journalRow?.zonesJSON) {
                    Divider().overlay(theme.hairline)
                    zonesBlock(zones)
                }
                if dispAvgHr != nil || journalRow?.maxHr != nil {
                    Divider().overlay(theme.hairline)
                    heartBlock
                }
                Divider().overlay(theme.hairline)
                secondaries
                if let note = fullSession?.notes, !note.isEmpty {
                    noteBlock(note)
                }
                sourceBadge
                if loaded {
                    // Handoff: exercise blocks breathe compact (16), not the section's 28.
                    VStack(alignment: .leading, spacing: CenitMetrics.sectionGapCompact) {
                        ForEach(Array(groups.enumerated()), id: \.element.exerciseId) { idx, g in
                            Divider().overlay(theme.hairline)
                            exerciseBlock(g, index: idx)
                        }
                    }
                    Divider().overlay(theme.hairline)
                    actions
                }
            }
            .padding(.top, 20)
            .padding(.horizontal, CenitMetrics.screenPadding)
            .padding(.bottom, CenitMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.paper.ignoresSafeArea())
        // FER-969 / X-05a: delete (or undo-restore) failure — banner; do NOT pop or seed pendingUndo.
        .overlay(alignment: .top) {
            if saveError {
                Text("Couldn't delete the workout. Try again.")
                    .font(.system(size: 13))   // token-exempt: cuerpo de banner (13pt, igual que el mensaje de ConfirmCard)
                    .foregroundStyle(theme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .patternBlock(theme, bar: theme.critical)
                    .padding(.horizontal, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task {
                        try? await Task.sleep(for: .seconds(4))
                        saveError = false
                    }
            }
        }
        .animation(StrandMotion.fade, value: saveError)
        // «Editar» / «Borrar entrenamiento» — visible from the detail, so deleting no longer needs the
        // list's long-press, and editing a saved session is finally possible (FER-556).
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showMoreMenu = true } label: {
                    Image(systemName: "ellipsis.circle").foregroundStyle(theme.ink)
                }
                .accessibilityLabel(Text("More options"))
                .paperMenu(isPresented: $showMoreMenu, items: [
                    // Both actions wait for the full row to load.
                    .init(String(localized: "Edit"), systemImage: "pencil") {
                        if fullSession != nil { showEdit = true }
                    },
                    .init(String(localized: "Delete workout"), systemImage: "trash", isDestructive: true) {
                        if fullSession != nil { showDeleteConfirm = true }
                    }
                ])
            }
        }
        .instrumentoConfirm(
            isPresented: $showDeleteConfirm,
            title: String(localized: "Delete this workout?"),
            context: String(localized: "HISTORY"),
            message: String(localized: "This removes the workout from your history."),
            actions: [
                .init(String(localized: "Keep workout"), role: .primary),
                .init(String(localized: "Delete workout"), role: .destructive) { performDelete() }
            ]
        )
        .sheet(item: $detailExercise) { ex in
            NavigationStack {
                ExerciseDetailScreen(exercise: ex)
                    .toolbar { ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { detailExercise = nil }.foregroundStyle(theme.ink)
                    } }
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbarBackground(theme.paper, for: .navigationBar)
            }
            .instrumentoTheme(theme).environmentObject(repo).preferredColorScheme(.light)
        }
        .sheet(isPresented: $showEdit) {
            if let s = fullSession {
                WorkoutEditSheet(session: s, sets: allSets) { await onEdited() }
                    .instrumentoTheme(theme).environmentObject(repo).preferredColorScheme(.light)
            }
        }
        // «Duplicar como rutina» (2A): a routine builder pre-filled with this session's exercises. Saving
        // creates a NEW routine (never touches this session) and opens it on «Rutina» once the sheet is
        // down (FER-840). Theme/repo passed explicitly across the sheet.
        .sheet(isPresented: $showDuplicate, onDismiss: {
            if let id = savedRoutineId { savedRoutineId = nil; openRoutine?(id) }
        }) {
            RoutineBuilderScreen(seedName: duplicateName, seed: duplicateSeed) { id in savedRoutineId = id }
                .instrumentoTheme(theme).environmentObject(repo).preferredColorScheme(.light)
        }
        .task { await load() }
    }

    // MARK: - Parity actions (v3 · 2A) — «Duplicar como rutina» + «Repetir hoy»

    private var actions: some View {
        VStack(spacing: 10) {
            StrandCTAButton("Repeat today") { repeatToday() }
                .disabled(groups.isEmpty)
            StrandCTAButton("Duplicate as routine", kind: .outline) { showDuplicate = true }
                .disabled(groups.isEmpty)
        }
    }

    /// This session's exercises re-based onto builder items for «Duplicar como rutina». Each exercise gets
    /// as many sets as it had work sets in the session, carrying the logged reps/weight as the targets.
    /// Explicit types on the compactMap / RoutineExercise init cut inference cost (FER-981, ~:919).
    private var duplicateSeed: [(re: RoutineExercise, exercise: Exercise)] {
        typealias SeedItem = (re: RoutineExercise, exercise: Exercise)
        typealias Group = (exerciseId: String, name: String, sets: [SetEntry])
        return groups.compactMap { (g: Group) -> SeedItem? in
            guard let ex: Exercise = exercisesByID[g.exerciseId] else { return nil }
            let work: [SetEntry] = g.sets.filter { (s: SetEntry) in s.kind == .work }
            let sets: [RoutineSet] = work.enumerated().map { (i: Int, s: SetEntry) -> RoutineSet in
                RoutineSet(position: i, kind: .work, reps: s.reps, weightKg: s.weightKg)
            }
            let targetSets: Int = max(1, sets.count)
            let targetReps: Int? = work.first?.reps
            let targetWeightKg: Double? = work.first?.weightKg
            let group: Int? = supersetGroup(g.exerciseId)
            let re: RoutineExercise = RoutineExercise(
                routineId: "",
                exerciseId: g.exerciseId,
                position: 0,
                targetSets: targetSets,
                targetReps: targetReps,
                targetWeightKg: targetWeightKg,
                supersetGroup: group,
                sets: sets
            )
            let pair: SeedItem = (re: re, exercise: ex)
            return pair
        }
    }

    private var duplicateName: String {
        let defaultName: String = String(localized: "Strength workout")
        let newName: String = String(localized: "New routine")
        let name: String = dispRoutineName
        return name == defaultName ? newName : name
    }

    /// «Repetir hoy» (2A): start a fresh guided session from this session's exercises. Reuses each
    /// exercise's logged sets as its plan (targets + «la última vez» reference).
    private func repeatToday() {
        // The plan comes from each exercise's re.sets (targets); `lastSets` is the «la última vez» prefill,
        // left empty here so the session model seeds straight from the planned sets.
        typealias SeedItem = (re: RoutineExercise, exercise: Exercise)
        let seed: [SeedItem] = duplicateSeed
        let emptyLast: [SetEntry] = []
        let slots: [StrengthSessionModel.PlanSlot] = seed.map { (item: SeedItem) -> StrengthSessionModel.PlanSlot in
            StrengthSessionModel.PlanSlot(re: item.re, exercise: item.exercise, lastSets: emptyLast)
        }
        guard !slots.isEmpty else { return }
        // Fully-typed args so the startStrengthSession call doesn't re-infer through @Observable (FER-981).
        let routineId: String? = dispRoutineId
        let routineName: String = dispRoutineName
        let planSlots: [StrengthSessionModel.PlanSlot] = slots
        model.startStrengthSession(routineId: routineId, routineName: routineName, slots: planSlots)
    }

    /// Delete from the detail: read the sets (so an undo can restore them), delete (the store recomputes
    /// the affected PRs), seed the coordinator's «Undo» + reload, then pop back to the list (FER-556).
    /// FER-969: on failure stay on the detail — no optimistic pop, no pendingUndo.
    private func performDelete() {
        Task {
            let sets = allSets.isEmpty ? await repo.sessionSets(sessionId: route.id) : allSets
            do {
                try await repo.deleteSession(id: route.id)
                let session = fullSession ?? StrengthSession(id: route.id, startTs: route.startTs,
                                                             endTs: route.endTs, strain: route.strain, avgHr: route.avgHr)
                coordinator.pendingUndo = .init(session: session, sets: sets)
                coordinator.bumpReload()
                dismiss()
            } catch {
                saveError = true
            }
        }
    }

    /// After the edit sheet saves: reload the detail in place and bump the list so its row reflects the
    /// new date/routine/volume when popped back to.
    private func onEdited() async {
        await load()
        coordinator.bumpReload()
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 3) {
            InstrumentoFlowTitle(overline: Text(StrengthHistoryFormat.dateTime(dispStart)),
                                 Text(verbatim: dispRoutineName))
        }
    }

    // Effort (strain) is the hero in the effort hue, or duration in ink when the session had no HR —
    // the same rule as the post-session receipt (FER-409).
    @ViewBuilder
    private var hero: some View {
        if let strain = dispStrain {
            heroStat("Effort", StrengthHistoryFormat.strain(strain), unit: nil,
                     color: theme.dataStrain, caption: "What this session cost your body.")
        } else if let mins = StrengthHistoryFormat.durationMinutes(start: dispStart, end: dispEnd) {
            heroStat("Duration", "\(mins)", unit: "min",
                     color: theme.ink, caption: "No heart rate this session.")
        }
    }

    private func heroStat(_ label: LocalizedStringKey, _ value: String, unit: String?,
                          color: Color, caption: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).instrumentoOverline().foregroundStyle(theme.inkTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).instrumentoHero(54).foregroundStyle(color)
                    .monospacedDigit().minimumScaleFactor(0.5).lineLimit(1)
                if let unit { Text(unit).font(StrandFont.unit).foregroundStyle(theme.inkTertiary) }
            }
            Text(caption).font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    /// The support figures as a REGULAR two-column grid (FER-952: the old auto-fit row read as
    /// off-center) — every cell speaks the heartBlock's grammar: overline on top, Grotesk 19 under.
    private var secondaries: some View {
        LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading),
                            GridItem(.flexible(), alignment: .leading)],
                  alignment: .leading, spacing: CenitMetrics.sectionGapCompact) {
            if volumeKg > 0 {
                supportCell("Volume", StrengthHistoryFormat.volume(volumeKg, system: system))
            }
            supportCell("Sets", "\(setCount)")
            // Duration is the hero when there's no strain → don't repeat it as a secondary.
            if dispStrain != nil,
               let mins = StrengthHistoryFormat.durationMinutes(start: dispStart, end: dispEnd) {
                supportCell("Duration", StrengthHistoryFormat.durationText(mins))
            }
            // Avg HR lives in its own FC block (handoff «Progreso C») — not repeated here. Energy only
            // when the session carries it (FER-715/718): pre-v26 → omitted, never a fabricated 0.
            if let k = dispEnergyKcal { supportCell("Energy", StrandFormat.groupedInt(k)) }
        }
    }

    private func supportCell(_ label: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).instrumentoOverline().foregroundStyle(theme.inkTertiary)
            Text(verbatim: value)
                .font(InstrumentoType.groteskNumber(19)).foregroundStyle(theme.ink)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - HR zones + heart + note + source (handoff «Progreso C», FER-952)

    /// Time-overlapping journal `WorkoutRow` — zones/max HR live only on the journal (no FK).
    @State private var journalRow: WorkoutRow? = nil

    /// The handoff's continuous warm ramp: one 34pt bar sliced by zone share, Z-labels + % below.
    /// Shares `theme.hrZoneRamp` (1 of 3 distinct HR-zone surfaces — palettes shared, geometry not, FER-908).
    private func zonesBlock(_ percents: [Double]) -> some View {
        let total = max(percents.reduce(0, +), 0.001)
        return VStack(alignment: .leading, spacing: CenitMetrics.gap) {
            Text("Heart-rate zones").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(percents.indices, id: \.self) { i in
                        Rectangle().fill(theme.hrZoneRamp[i])
                            .frame(width: max(0, (geo.size.width - 8) * percents[i] / total))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: CenitMetrics.chipRadius, style: .continuous))
            }
            .frame(height: 34)  // token-exempt: barra de zonas 34 del handoff
            HStack(spacing: 0) {
                ForEach(percents.indices, id: \.self) { i in
                    VStack(spacing: 2) {
                        Text(verbatim: "Z\(i + 1)").font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                        Text(verbatim: "\(Int(percents[i].rounded()))%")
                            .font(InstrumentoType.groteskNumber(12, weight: .semibold)).foregroundStyle(theme.ink)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Heart-rate zones"))
        .accessibilityValue(Text(verbatim: percents.enumerated()
            .map { "Z\($0.offset + 1) \(Int($0.element.rounded()))%" }.joined(separator: ", ")))
    }

    /// «FC MEDIA / FC MÁX» — the wine-hued pair (handoff): Grotesk 19 numerals, unit quiet.
    private var heartBlock: some View {
        HStack(spacing: 44) {  // token-exempt: 44 del handoff
            if let hr = dispAvgHr {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Avg HR").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(verbatim: "\(hr)")
                            .font(InstrumentoType.groteskNumber(19)).foregroundStyle(theme.dataHeart)
                        Text(verbatim: "bpm").font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                    }
                }
            }
            if let maxHr = journalRow?.maxHr {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Max HR").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(verbatim: "\(maxHr)")
                            .font(InstrumentoType.groteskNumber(19)).foregroundStyle(theme.dataHeart)
                        Text(verbatim: "bpm").font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    /// «NOTA» — the session's own words, on the sunken block (handoff).
    private func noteBlock(_ note: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Note").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            Text(note).font(StrandFont.subhead).foregroundStyle(theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(CenitMetrics.gap)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.patternBlock, in: RoundedRectangle(cornerRadius: CenitMetrics.insetRadius, style: .continuous))
        }
    }

    /// «FUENTE» — measured with the band (journal join) vs estimated; honest, quiet, never a guess.
    private var sourceBadge: some View {
        HStack(spacing: 8) {
            Text("Source").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            if journalRow != nil {
                // Idioma de origen del sistema (OriginStamp): punto `originBand` + copy en ink —
                // el hue del dato (dataHeart) no marca procedencia (§8.7, auditoría FER-952).
                HStack(spacing: 5) {
                    Circle().fill(theme.originBand).frame(width: 5, height: 5)
                    Text("Measured with your band")
                        .font(StrandFont.caption).foregroundStyle(theme.ink)
                }
                .padding(.horizontal, 9).padding(.vertical, 3)
                .background(theme.patternBlock, in: Capsule(style: .continuous))
            } else {
                Text("Estimated")
                    .font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
                    .padding(.horizontal, 9).padding(.vertical, 3)
                    .background(theme.patternBlock, in: Capsule(style: .continuous))
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    /// Match this strength session to a journal workout by interval overlap
    /// (`a.start < b.end && b.start < a.end`); closest `startTs` wins.
    private func loadJournalRow() async {
        journalRow = nil
        let sStart = dispStart
        let sEnd = dispEnd ?? dispStart + 1
        let now = Int(Date().timeIntervalSince1970)
        let daysBack = max(3, (now - sStart) / 86_400 + 3)
        let rows = await repo.workoutRows(days: min(daysBack, 90))
        let matches = rows.filter { r in sStart < r.endTs && r.startTs < sEnd }
        journalRow = matches.min(by: { abs($0.startTs - sStart) < abs($1.startTs - sStart) })
    }


    private func exerciseBlock(_ g: (exerciseId: String, name: String, sets: [SetEntry]), index: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // A superset tag when this exercise shares its routine's `supersetGroup` with an adjacent one
            // in performed order (v3 · 2A). The datum here is anatomical/structural, so it stays in ink.
            if isInSuperset(index) {
                Text("Superset").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                    .padding(.bottom, 4)
            }
            exerciseTitle(g)
                .padding(.bottom, 6)
            ForEach(Array(g.sets.enumerated()), id: \.element.id) { idx, set in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Set \(idx + 1)").font(StrandFont.subhead).foregroundStyle(theme.inkTertiary)
                    if isPRSet(set, exerciseId: g.exerciseId) {
                        Text("PR").font(StrandFont.captionNumber).foregroundStyle(theme.dataStrain)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .overlay(Capsule().strokeBorder(theme.dataStrain.opacity(0.5), lineWidth: 1)) // token-exempt: stroke chip PR 0.5 (alfa propio)
                            .accessibilityLabel(Text("Personal record"))
                    }
                    Spacer(minLength: 8)
                    Text(StrengthHistoryFormat.setLine(set, system: system))
                        .font(StrandFont.subhead).foregroundStyle(theme.ink).monospacedDigit()
                }
                .padding(.vertical, 5)
                .overlay(alignment: .top) {
                    if idx > 0 { Divider().overlay(theme.hairline) }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    /// Whether the exercise at `groups[index]` belongs to a superset — it shares a non-nil routine
    /// `supersetGroup` with the exercise immediately before or after it in performed order.
    private func isInSuperset(_ index: Int) -> Bool {
        guard let g = supersetGroup(groups[index].exerciseId) else { return false }
        let before = index > 0 ? supersetGroup(groups[index - 1].exerciseId) : nil
        let after = index < groups.count - 1 ? supersetGroup(groups[index + 1].exerciseId) : nil
        return before == g || after == g
    }
    private func supersetGroup(_ exerciseId: String) -> Int? {
        routineExercises.first { $0.exerciseId == exerciseId }?.supersetGroup
    }

    /// Whether a work set matches this exercise's stored best (weight or single-set volume) — a personal
    /// record. Compared on the physical values, so an equal-best set still reads as a PR.
    private func isPRSet(_ set: SetEntry, exerciseId: String) -> Bool {
        guard set.kind == .work, let w = set.weightKg, w > 0, let reps = set.reps else { return false }
        let prs = prsByExercise[exerciseId] ?? []
        for pr in prs {
            switch pr.metric {
            case .maxWeight where pr.valueKg == w: return true
            case .maxVolume where pr.valueKg == w && pr.reps == reps: return true
            default: break
            }
        }
        return false
    }

    /// The exercise's name — a tappable row (name + chevron) that opens its detail when the exercise
    /// resolves (FER-517); plain text otherwise, so there's no dead tap on an unknown id.
    @ViewBuilder
    private func exerciseTitle(_ g: (exerciseId: String, name: String, sets: [SetEntry])) -> some View {
        if let ex = exercisesByID[g.exerciseId] {
            Button { detailExercise = ex } label: {
                HStack(spacing: 6) {
                    Text(g.name).font(StrandFont.headline).foregroundStyle(theme.ink)
                    StrandIcon.disclosure.image
                        .font(StrandFont.glyph(.chevron, weight: .semibold)).foregroundStyle(theme.inkTertiary)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("Opens the exercise"))
        } else {
            Text(g.name).font(StrandFont.headline).foregroundStyle(theme.ink)
        }
    }

    private func load() async {
        let sets = await repo.sessionSets(sessionId: route.id)
        let exercises = await repo.allExercises()
        let routines = await repo.routines()
        fullSession = await repo.session(id: route.id)
        allSets = sets
        routineNames = Dictionary(routines.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        let names = Dictionary(exercises.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        exercisesByID = Dictionary(exercises.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        // Only work sets, in performed order, grouped by exercise (first-seen order preserved).
        let work = sets.filter { $0.kind == .work }
        var order: [String] = []
        var byExercise: [String: [SetEntry]] = [:]
        for s in work {
            if byExercise[s.exerciseId] == nil { order.append(s.exerciseId) }
            byExercise[s.exerciseId, default: []].append(s)
        }
        groups = order.map { id in
            (exerciseId: id,
             name: names[id].map(StrengthDisplay.titleCase) ?? String(localized: "Exercise"),
             sets: byExercise[id] ?? [])
        }
        volumeKg = work.reduce(0) { acc, s in
            guard let w = s.weightKg, let r = s.reps else { return acc }
            return acc + w * Double(r)
        }
        setCount = work.count

        // Superset identification (2A): the session's routine exercises carry `supersetGroup`. Loaded only
        // when the session links to a saved routine — off-plan/one-off sessions have none.
        if let rid = fullSession?.routineId {
            routineExercises = await repo.routineExercises(routineId: rid)
        }
        // Personal records per exercise, so a set that matches a stored best is flagged (2A).
        var prMap: [String: [PersonalRecord]] = [:]
        for id in order { prMap[id] = await repo.personalRecords(exerciseId: id) }
        prsByExercise = prMap

        // Journal join (zones / max HR live only on the journal — handoff «Progreso C», FER-952).
        await loadJournalRow()

        loaded = true
    }
}

// MARK: - Formatting (shared by list + detail)

enum StrengthHistoryFormat {
    private static let dateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = .current
        f.setLocalizedDateFormatFromTemplate("d MMM y · HH:mm")
        return f
    }()

    static func dateTime(_ ts: Int) -> String {
        dateTimeFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(ts)))
    }

    /// Whole minutes between start and end, or nil when the session has no end time.
    static func durationMinutes(start: Int, end: Int?) -> Int? {
        guard let end, end > start else { return nil }
        return (end - start) / 60
    }

    /// "42 min" or "1 h 12 min".
    static func durationText(_ minutes: Int) -> String {
        if minutes < 60 { return String(localized: "\(minutes) min") }
        return String(localized: "\(minutes / 60) h \(minutes % 60) min")
    }

    /// Reused across every session row's volume label — building a `NumberFormatter` is hundreds of µs,
    /// and `volume(_:system:)` is called once per visible row in the history `LazyVStack` (was allocating
    /// a fresh formatter each time → scroll jank). Same `static let` pattern as `dateTimeFormatter` above.
    private static let volumeFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f
    }()

    /// Total volume in the user's unit, with thousands grouping: "3,325 kg" / "7,330 lb".
    static func volume(_ kg: Double, system: UnitSystem) -> String {
        let value = system == .imperial ? UnitFormatter.kgToPounds(kg) : kg
        let num = volumeFormatter.string(from: NSNumber(value: value.rounded())) ?? "\(Int(value.rounded()))"
        return "\(num) \(StrengthDisplay.weightUnit(system))"
    }

    static func strain(_ v: Double) -> String { String(format: "%.1f", v) }

    /// One performed set as "20 kg × 6", "8 reps" (bodyweight), or a time/distance fallback.
    static func setLine(_ s: SetEntry, system: UnitSystem) -> String {
        if let w = s.weightKg, w > 0, let r = s.reps {
            return "\(StrengthDisplay.weight(w, system: system)) × \(r)"
        }
        if let r = s.reps { return String(localized: "\(r) reps") }
        if let t = s.timeS { return "\(Int(t)) s" }
        if let d = s.distanceM { return "\(Int(d)) m" }
        return "—"
    }
}
#endif
