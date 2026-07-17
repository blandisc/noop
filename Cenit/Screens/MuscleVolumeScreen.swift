#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import StrandTraining

// MuscleVolumeScreen.swift — «Volumen por músculo» (Entrenar v3 · 3d, FER-719): average weekly
// sets per muscle over a chosen span, judged against the ~10–20 sets/week hypertrophy band
// (Schoenfeld 2017 anchors the 10-set floor; the 20-set ceiling is a product convention — see
// `MuscleFatigueMap`). Muscles below the band read amber, and the foot names them with an
// actionable line. Pushed from «Mis entrenamientos» onto the Entrenar NavigationStack.
//
// The math is `MuscleFatigueMap.weeklyVolumes` (pure, tested): total involvement-weighted sets in
// the span divided by the FULL span in weeks — an honest average, not a best week. Unlike the
// muscle map, this screen ignores the manual recovery reset: it reads history, not freshness.

/// Route pushed onto the Entrenar stack for the per-muscle volume screen.
struct MuscleVolumeRoute: Hashable {}

struct MuscleVolumeScreen: View {
    @Environment(\.instrumentoTheme) private var theme
    @EnvironmentObject private var repo: Repository

    /// The span the average runs over. Raw value = trailing days.
    private enum Span: Int, CaseIterable {
        case d30 = 30, d90 = 90, m6 = 182, y1 = 365
        var label: String {
            switch self {
            case .d30: return String(localized: "30 d")
            case .d90: return String(localized: "90 d")
            case .m6:  return String(localized: "6 m")
            case .y1:  return String(localized: "1 y")
            }
        }
    }

    @State private var span: Span = .d30
    /// The method note («sets per week · the 10–20 band»), shown on demand from the ⓘ (FER-952).
    @State private var showMethodInfo = false
    /// Measured height of the ⓘ sheet's content — drives a fitted detent (no dead paper below).
    @State private var infoSheetHeight: CGFloat = 220

    /// Work sets over the trailing year, expanded to per-muscle events (one fetch; the span slices).
    @State private var events: [MuscleFatigueMap.MuscleSetEvent] = []
    @State private var loaded = false

    /// The band rail draws 0…30 sets/week, like the muscle detail (band at 10–20 sits centered).
    private var railTop: Double { MuscleFatigueMap.weeklyVolumeRailTop }

    private var volumes: [MuscleFatigueMap.MuscleWeeklyVolume] {
        MuscleFatigueMap.weeklyVolumes(events: events, days: span.rawValue)
    }
    private var belowBand: [MuscleFatigueMap.MuscleWeeklyVolume] {
        volumes.filter { $0.band == .below }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Volume per muscle")
                        .font(InstrumentoType.groteskScreenTitle)
                        .tracking(InstrumentoType.groteskScreenTitleTracking)
                        .foregroundStyle(theme.ink)
                    // FER-952: the method note moved behind the ⓘ — it only speaks when asked.
                    Button { showMethodInfo = true } label: {
                        Image(systemName: "info.circle").font(StrandFont.glyph(.inline))
                            .foregroundStyle(theme.inkTertiary)
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("How this is measured"))
                }
                spanPicker
                    .padding(.top, 12)
                if loaded {
                    if volumes.isEmpty {
                        emptyState.padding(.top, 28)
                    } else {
                        rows.padding(.top, 6)
                        railAxisMarks.padding(.top, 4)
                        // FER-952 v2 (owner): the VERDICT stays on screen (it's today's datum); the
                        // METHOD paragraph moved behind the ⓘ.
                        insightLine.padding(.top, 12)
                    }
                }
            }
            .padding(.top, 20)
            .padding(.horizontal, CenitMetrics.screenPadding)
            .padding(.bottom, CenitMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.paper.ignoresSafeArea())
        .task { await load() }
        // The method + the verdict, on demand (FER-952). The sheet HUGS its content: a measured-height
        // detent, so there's no dead paper below the last line.
        .sheet(isPresented: $showMethodInfo) {
            VStack(alignment: .leading, spacing: CenitMetrics.gap) {
                Text("Volume per muscle").groteskSheetTitle().textCase(.uppercase)
                    .foregroundStyle(theme.inkTertiary)
                Text("Sets per week · the gray band is the 10–20 range (Schoenfeld 2017)")
                    .font(StrandFont.body).foregroundStyle(theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Each bar counts the WORK sets that loaded that muscle as a primary mover, averaged per week over the selected span. Warm-ups don't count.")
                    .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("The 10–20 band is a hypertrophy guide per muscle group (Schoenfeld 2017); the number shown is sets weighted by involvement, so secondary muscles count less.")
                    .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(CenitMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GeometryReader { geo in
                Color.clear.preference(key: SheetContentHeightKey.self, value: geo.size.height)
            })
            .onPreferenceChange(SheetContentHeightKey.self) { infoSheetHeight = $0 }
            .presentationDetents([.height(max(infoSheetHeight, 120))])
            .presentationBackground(theme.paper)
        }
    }

    // MARK: - Span picker (30 d / 90 d / 6 m / 1 y) — the shared Instrumento segmented control

    private var spanPicker: some View {
        SegmentedPillControl(Span.allCases, selection: $span, theme: theme) { $0.label }
    }

    // MARK: - Rows — one muscle per row, bar over the 10–20 band rail

    private var rows: some View {
        VStack(spacing: 0) {
            ForEach(volumes, id: \.muscle) { v in
                row(v)
            }
        }
    }

    private func row(_ v: MuscleFatigueMap.MuscleWeeklyVolume) -> some View {
        let below = v.band == .below
        return HStack(spacing: 12) {
            Text(MuscleAtlas.name(v.muscle))
                .font(StrandFont.body).foregroundStyle(theme.ink)
                .lineLimit(1).minimumScaleFactor(0.85)
                .frame(width: 96, alignment: .leading)
            GeometryReader { geo in
                let w = geo.size.width
                let lo = MuscleFatigueMap.weeklyBandLow / railTop
                let hi = MuscleFatigueMap.weeklyBandHigh / railTop
                ZStack(alignment: .leading) {
                    // the 10–20 band, the fixed reference
                    RoundedRectangle(cornerRadius: 3).fill(theme.hairline)  // token-exempt: geometría de dato
                        .frame(width: w * (hi - lo), height: 14)
                        .offset(x: w * lo)
                    // the datum — each muscle wears its movement-family hue (handoff «Mis
                    // entrenamientos»: bars tell apart at a glance); below-band keeps the warning.
                    RoundedRectangle(cornerRadius: 3)  // token-exempt: geometría de dato
                        .fill(below ? theme.warning : theme.movementFamilyTint(primaryMuscles: [v.muscle]))
                        .frame(width: max(4, w * min(v.setsPerWeek, railTop) / railTop), height: 6)
                }
                .frame(height: 14, alignment: .leading)
            }
            .frame(height: 14)
            Text(setsText(v.setsPerWeek))
                .font(StrandFont.captionNumber)
                .fontWeight(below ? .semibold : .regular)
                .foregroundStyle(below ? theme.warning : theme.ink)
                .frame(minWidth: 34, alignment: .trailing)
        }
        .frame(minHeight: 46)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(MuscleAtlas.name(v.muscle)))
        .accessibilityValue(Text("\(setsText(v.setsPerWeek)) sets per week") + Text(verbatim: ", ") + Text(bandWord(v.band)))
    }

    private func bandWord(_ b: MuscleFatigueMap.VolumeBand) -> LocalizedStringKey {
        switch b {
        case .below:  return "below the band"
        case .within: return "within the band"
        case .above:  return "above the band"
        }
    }

    // MARK: - Rail axis marks — 0 / railTop/3 / 2·railTop/3 / railTop, under the bars only

    /// Tick labels aligned to the flexible rail column (same 96 + 12 + rail + 12 + 34 layout as `row`).
    private var railAxisMarks: some View {
        // Derived from `railTop` so a future band-rail change keeps the ticks honest (today 0 / 10 / 20 / 30).
        let marks: [Double] = [0, railTop / 3, 2 * railTop / 3, railTop]
        return HStack(spacing: 12) {
            Color.clear.frame(width: 96)
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                ZStack {
                    // Edge ticks: "0" flush leading, top mark flush trailing (inside the rail width).
                    HStack {
                        Text("\(Int(marks[0].rounded()))")
                            .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                        Spacer(minLength: 0)
                        Text("\(Int(marks[marks.count - 1].rounded()))")
                            .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                    }
                    // Mid ticks centered on their proportional positions along the rail.
                    ForEach(Array(marks.dropFirst().dropLast().enumerated()), id: \.offset) { _, mark in
                        Text("\(Int(mark.rounded()))")
                            .font(StrandFont.footnote)
                            .foregroundStyle(theme.inkTertiary)
                            .position(x: w * CGFloat(mark / railTop), y: h / 2)
                    }
                }
            }
            .frame(height: 14)
            Color.clear.frame(width: 34)
        }
        .accessibilityHidden(true)
    }

    // MARK: - Insight foot — names the below-band muscles, actionably


    @ViewBuilder private var insightText: some View {
        if belowBand.isEmpty {
            Text("Every muscle you train is inside or above the band.")
        } else {
            let names = belowBand.prefix(2).map { MuscleAtlas.name($0.muscle) }
            let lead: Text = names.count >= 2
                ? Text(names[0]) + Text(" and ") + Text(names[1])
                : Text(names[0])
            lead + Text(" below the band · they could take 2–3 more sets a week.")
        }
    }

    /// The verdict line, ON the screen (FER-952 v2): which muscles sit below the band today.
    private var insightLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Circle().fill(belowBand.isEmpty ? theme.verdict : theme.warning)
                .frame(width: 8, height: 8)
                .alignmentGuide(.firstTextBaseline) { d in d[.bottom] - 1 }
            insightText
                .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No sets in this range")
                .font(StrandFont.title2).foregroundStyle(theme.ink)
            Text("Log your workouts and you'll see each muscle's weekly volume against the band.")
                .font(StrandFont.body).foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Data

    private func setsText(_ v: Double) -> String { MuscleFatigueMap.formattedSets(v) }

    /// Fetch the max span (a year) once; the span picker re-slices in memory (`volumes`) with no more I/O.
    private func load() async {
        let cal = Calendar.current
        guard let since = cal.date(byAdding: .day, value: -Span.y1.rawValue, to: cal.startOfDay(for: Date())) else {
            loaded = true; return
        }
        events = await repo.muscleSetEvents(sinceTs: Int(since.timeIntervalSince1970))
        loaded = true
    }
}
#endif
