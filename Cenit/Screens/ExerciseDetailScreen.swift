#if os(iOS)
import SwiftUI
import UIKit
import StrandDesign
import StrandTraining
import StrandAnalytics

// ExerciseDetailScreen.swift — one exercise: which muscles it loads, your history, and an estimated-1RM
// trend (FER-346). Presented as a sheet from the library. «Báscula de papel»: weights are the heroes,
// in ink; the only color is the 1RM trend line (`dataStrain`, the output hue). With no logged work yet
// it stays honest — muscles + why the history is empty, nothing fabricated.

struct ExerciseDetailScreen: View {
    let exercise: Exercise

    @Environment(\.instrumentoTheme) private var theme
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var mediaCoordinator: MediaDownloadCoordinator
    @EnvironmentObject private var tabRouter: TabRouter
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    private var system: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }
    /// FER-722/778/790: the exercise's cached media — a single animated GIF that the hero shows both
    /// as a still (when paused) and animated (when playing). One asset, not a thumb/loop split.
    @State private var mediaURL: URL?
    @State private var loadingMedia = false
    @State private var isLoopPlaying = true

    /// Work sets across sessions (oldest→newest), the raw material for the progress chart + PRs.
    @State private var history: [(startTs: Int, weightKg: Double, reps: Int, optedOut: Bool)] = []
    /// Stored best-per-metric records for this exercise (FER-504/505). Read-only; derived on save.
    @State private var prs: [PersonalRecord] = []
    /// Where this exercise's progression cycle stands (FER-F); nil = no slot opted in.
    @State private var cycleState: ProgressionState? = nil
    /// Which series the progress chart shows (FER-505). Est. 1RM is the default hero trend.
    @State private var metric: ProgressMetric = .oneRM
    /// The v3 · 1g/1h segmented view: Guide (muscles + how-to) / Progress (trend + records) / History (per-day sets).
    @State private var tab: DetailTab = .guide
    @State private var loaded = false
    /// A tapped variant chip opens that exercise's own sheet (FER-739). Self-contained here so it works
    /// regardless of which screen presented this one.
    @State private var variant: Exercise?
    /// Other catalog exercises that share this one's primary muscle — derived once (FER-739).
    @State private var variants: [Exercise] = []

    private enum DetailTab: String, CaseIterable, Identifiable {
        case guide, progress, history
        var id: String { rawValue }
        var label: LocalizedStringKey {
            switch self {
            case .guide:    return "Guide"
            case .progress: return "Progress"
            case .history:  return "History"
            }
        }
    }
    /// The effective measurement type to display — nil falls back to the passed-in (already resolved)
    /// `exercise.type`; set when the user changes it so the header + control update live (FER-541).
    @State private var shownType: ExerciseType?
    /// Whether this exercise currently carries a user type override (→ show «revert to default»).
    @State private var hasTypeOverride = false
    @State private var showTypeMenu = false
    private var effectiveType: ExerciseType { shownType ?? exercise.type }

    /// The metric the progress chart plots over time.
    private enum ProgressMetric: String, CaseIterable, Identifiable {
        case weight, oneRM, volume
        var id: String { rawValue }
        var label: LocalizedStringKey {
            switch self {
            case .weight: return "Max weight"
            case .oneRM:  return "Est. 1RM"
            case .volume: return "Volume"
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CenitMetrics.sectionGap) {
                header
                // Reserved media hero (FER-751, handoff 1g/1h): sits between the title and the
                // segmented control. FER-722/778 fill this same slot with the cached loop/thumb
                // (auto-play + top-right play/pause) without shifting the layout.
                heroSection
                Picker("View", selection: $tab) {
                    ForEach(DetailTab.allCases) { t in Text(t.label).tag(t) }
                }
                .pickerStyle(.segmented)
                switch tab {
                case .guide:    guideTab
                case .progress: progressTab
                case .history:  historyTab
                }
            }
            .padding(.top, 20)
            .padding(.horizontal, CenitMetrics.screenPadding)
            .padding(.bottom, CenitMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.paper.ignoresSafeArea())
        .task(id: exercise.id) {
            async let h = repo.exerciseHistory(exerciseId: exercise.id)
            async let p = repo.personalRecords(exerciseId: exercise.id)
            async let ov = repo.exerciseTypeOverride(exercise.id)
            (history, prs) = await (h, p)
            hasTypeOverride = await ov != nil
            // FER-F: where the progression cycle stands — only if some routine slot opted in for this
            // exercise (first enabled slot wins; multi-routine overlap is rare and reads the same history).
            cycleState = nil
            if exercise.type == .weightReps, let store = await repo.storeHandle() {
                let rs = (try? await store.routines()) ?? []
                var slot: RoutineExercise? = nil
                for r in rs where slot == nil {
                    let exs = (try? await store.routineExercises(routineId: r.id)) ?? []
                    slot = exs.first { $0.exerciseId == exercise.id && $0.progressionEnabled }
                }
                if let re = slot {
                    let inventory = PlatesStore().inventory
                    cycleState = ProgressionPlanner.evaluate(
                        re: re, history: history, inventory: inventory,
                        equipment: exercise.equipment, recovery: repo.today?.recovery)?.state
                }
            }
            variants = Self.variants(for: exercise)
            loaded = true
            mediaURL = nil
            isLoopPlaying = true
            // Auto-play (1g/1h): fetch (or reuse the cached) GIF as soon as the sheet opens, no tap
            // needed. `mediaIfNeeded` no-ops with zero requests when the toggle is off and nothing
            // is cached.
            if mediaCoordinator.isEnabled {
                loadingMedia = true
                mediaURL = await mediaCoordinator.mediaIfNeeded(for: exercise)
                loadingMedia = false
            }
        }
        .sheet(item: $variant) { ex in
            NavigationStack {
                ExerciseDetailScreen(exercise: ex)
                    .toolbar { ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { variant = nil }.foregroundStyle(theme.ink)
                    } }
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbarBackground(theme.paper, for: .navigationBar)
            }
            .instrumentoTheme(theme)
            .environmentObject(repo)
            .environmentObject(mediaCoordinator)
            .preferredColorScheme(.light)
        }
    }

    // MARK: - Tabs (v3 · 1g/1h)

    /// «Guía» — how the exercise loads the body and how to do it. In the handoff's order (FER-739):
    /// muscles (chips) → how-to → variants → «measured by» + YouTube at the foot. The media hero
    /// (FER-751/722/778) already sits above the segmented control, so nothing repeats it here.
    @ViewBuilder private var guideTab: some View {
        musclesSection
        if !exercise.displayInstructions(localized: StrengthDisplay.localized).isEmpty { howToSection }
        variantsSection
        measurementSection
        youtubeRow
    }

    // MARK: - Media hero (FER-751 reserved slot, filled by FER-722/778/790)
    // The GIF renders INSIDE the same reserved `ExerciseThumbnail` slot — one animated asset, no
    // secondary card, nothing to duplicate. Toggle off or no cached media (default) → plain
    // placeholder, pixel-identical to before FER-722; a discreet hint appears ONLY when the toggle
    // itself is off. `UIImage(contentsOfFile:)` gates on a decodable first frame so a corrupt/partial
    // download quietly falls back to the placeholder instead of a blank box.

    @ViewBuilder private var heroSection: some View {
        if mediaCoordinator.isEnabled, let mediaURL, UIImage(contentsOfFile: mediaURL.path) != nil {
            ZStack(alignment: .topTrailing) {
                AnimatedGIFView(url: mediaURL, isPlaying: isLoopPlaying)
                    .aspectRatio(1, contentMode: .fit).frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: ExerciseThumbnail.heroCornerRadius, style: .continuous))
                    .accessibilityHidden(true)
                Button { isLoopPlaying.toggle() } label: {
                    Image(systemName: isLoopPlaying ? "pause.fill" : "play.fill")
                        .font(StrandFont.glyph(.chevron, weight: .semibold)).foregroundStyle(.white)
                        .padding(8).background(.black.opacity(StrandOpacity.strokeSoft), in: Circle())
                }
                .buttonStyle(.plain).padding(10)
                .accessibilityLabel(Text(isLoopPlaying ? "Pause preview" : "Play preview"))
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("\(exercise.name) preview"))
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    ExerciseThumbnail(hero: nil)
                    if loadingMedia { ProgressView().tint(theme.inkTertiary) }
                }
                if !mediaCoordinator.isEnabled { mediaOffHint }
            }
        }
    }

    /// Discreet nudge shown only when the media download toggle is off — never when it's on and this
    /// exercise simply has no EDB match (that's a quiet, honest miss, not something to fix in Ajustes).
    private var mediaOffHint: some View {
        Button {
            tabRouter.select(.settings)
            dismiss()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "play.rectangle").font(StrandFont.glyph(.chevron))
                Text("Turn on library downloads in Settings to see video")
                    .font(StrandFont.footnote)
            }
            .foregroundStyle(theme.inkTertiary)
        }
        .buttonStyle(.plain)
    }

    /// «Progreso» — the metric trend + personal records (or an honest empty when nothing's logged).
    @ViewBuilder private var progressTab: some View {
        if loaded {
            if history.isEmpty { emptyHistory } else { progressSection; recordsSection; trendsLink }
        }
    }

    /// «Historial» — every logged day for this exercise (its best set that day), newest first.
    @ViewBuilder private var historyTab: some View {
        if loaded {
            if history.isEmpty { emptyHistory } else { historyList }
        }
    }

    /// One row per logged day (its heaviest work set), newest first — the per-exercise history (1h).
    private var historyList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Every session").instrumentoOverline().foregroundStyle(theme.inkTertiary).padding(.bottom, 6)
            ForEach(Array(historyDays.enumerated()), id: \.offset) { idx, day in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(historyDate(day.ts)).font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                    Spacer(minLength: 8)
                    Text("\(StrengthDisplay.weight(day.weightKg, system: system)) × \(day.reps)")
                        .font(StrandFont.subhead).foregroundStyle(theme.ink).monospacedDigit()
                }
                .padding(.vertical, 7)
                .overlay(alignment: .top) { if idx > 0 { Divider().overlay(theme.hairline) } }
                .accessibilityElement(children: .combine)
            }
        }
    }

    /// The best (heaviest) work set per day, newest first, for the history list.
    private var historyDays: [(ts: Int, weightKg: Double, reps: Int)] {
        var byDay: [String: (ts: Int, weightKg: Double, reps: Int)] = [:]
        for h in history {
            let key = dayKey(h.startTs)
            if let cur = byDay[key], cur.weightKg >= h.weightKg { continue }
            byDay[key] = (h.startTs, h.weightKg, h.reps)
        }
        return byDay.values.sorted { $0.ts > $1.ts }
    }

    private func historyDate(_ ts: Int) -> String {
        Self.relativeFormatter.localizedString(for: Date(timeIntervalSince1970: TimeInterval(ts)), relativeTo: Date())
    }

    /// «Ver más en Tendencias» — a quiet hand-off to the deeper trend view. Cross-tab from a sheet isn't
    /// wired here, so it's an honest label pointing to where the full trend lives (no dead jump).
    private var trendsLink: some View {
        Text("See more in Trends")
            .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(metaLine)
                .instrumentoOverline().foregroundStyle(theme.inkTertiary)
            Text(StrengthDisplay.name(exercise))
                .font(StrandFont.title1).foregroundStyle(theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The overline under the title: «equipment · type» (e.g. «Barra · Peso × reps»). Collapses to a
    /// single term when they'd read the same (a bodyweight exercise's equipment «body only» and its type
    /// both localize to «Peso corporal») — fixing the doubled-equipment overline (FER-739).
    private var metaLine: String {
        let type = StrengthDisplay.typeName(effectiveType)
        guard let eq = exercise.equipment, !eq.isEmpty else { return type }
        let eqLabel = StrengthDisplay.equipment(eq)
        if eqLabel.caseInsensitiveCompare(type) == .orderedSame { return type }
        return "\(eqLabel) · \(type)"
    }

    // MARK: - Measurement type (FER-541) — let the user re-type any exercise, incl. a catalog one

    private var measurementSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider().overlay(theme.hairline).padding(.bottom, 10)
            Text("Measured by").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            HStack(spacing: 12) {
                Button { showTypeMenu = true } label: {
                    HStack(spacing: 6) {
                        Text(StrengthDisplay.typeLabel(effectiveType)).font(StrandFont.body).foregroundStyle(theme.ink)
                        Image(systemName: "chevron.down").font(StrandFont.glyph(.chevron)).foregroundStyle(theme.inkTertiary)
                    }
                }
                .buttonStyle(.plain)
                .paperMenu(isPresented: $showTypeMenu, items: ExerciseType.allCases.map { t in
                    PaperMenuItem(StrengthDisplay.typeName(t),
                                  systemImage: t == effectiveType ? "checkmark" : nil) { setType(t) }
                })
                Spacer(minLength: 8)
                if hasTypeOverride {
                    Button { revertType() } label: {
                        Text("Revert to default").font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(minHeight: 36)
        }
    }

    /// Override this exercise's measurement type (works for catalog and custom). The header + control
    /// update immediately; downstream readers pick it up via the resolver on their next load.
    private func setType(_ t: ExerciseType) {
        shownType = t
        hasTypeOverride = true
        Task { await repo.setExerciseTypeOverride(exercise.id, type: t) }
    }

    /// Drop the override → re-resolve the catalog/custom default and show it.
    private func revertType() {
        hasTypeOverride = false
        Task {
            await repo.clearExerciseTypeOverride(exercise.id)
            let resolved = await repo.resolvedExercise(exercise.id)
            await MainActor.run { shownType = resolved?.type }
        }
    }

    // MARK: - Muscles (chips: primary at full ink, assistants outlined · FER-739)
    // The handoff has no anatomical figure and no bars — the muscles read as chips. A primary mover is a
    // full-ink chip; an assistant is an outlined one. Derived from the exercise's own muscle data (no
    // bundled art, no network). Hidden when an exercise carries no muscles (a bare custom one).

    @ViewBuilder private var musclesSection: some View {
        if !exercise.primaryMuscles.isEmpty || !exercise.secondaryMuscles.isEmpty {
            VStack(alignment: .leading, spacing: 11) {
                Text("Muscles").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                ChipFlow(spacing: 8) {
                    ForEach(exercise.primaryMuscles, id: \.self) { m in muscleChip(m, primary: true) }
                    ForEach(exercise.secondaryMuscles, id: \.self) { m in muscleChip(m, primary: false) }
                }
                if !exercise.secondaryMuscles.isEmpty {
                    Text("Primary at full ink · assisting at half")
                        .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                }
            }
        }
    }

    private func muscleChip(_ muscle: String, primary: Bool) -> some View {
        Text(StrengthDisplay.muscle(muscle))
            .font(StrandFont.subhead)
            .foregroundStyle(primary ? theme.paper : theme.inkSecondary)
            .padding(.horizontal, 13).padding(.vertical, 6)
            .background(primary ? theme.ink : Color.clear, in: Capsule(style: .continuous))
            .overlay(Capsule(style: .continuous)
                .strokeBorder(primary ? theme.ink : theme.hairlineStrong, lineWidth: 1))
            .accessibilityElement()
            .accessibilityLabel("\(StrengthDisplay.muscle(muscle)), \(String(localized: primary ? "primary" : "assisting"))")
    }

    // MARK: - Variants (FER-739) — other catalog exercises for the same primary muscle

    /// A row of chips for sibling exercises that load the same primary muscle; tapping one opens its
    /// sheet. Derived from the catalog (no new «variants» field), so it's empty for a bare custom
    /// exercise or one whose primary muscle nothing else shares.
    @ViewBuilder private var variantsSection: some View {
        if !variants.isEmpty {
            VStack(alignment: .leading, spacing: 11) {
                Divider().overlay(theme.hairline).padding(.bottom, 4)
                Text("Variants").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                ChipFlow(spacing: 8) {
                    ForEach(variants) { ex in variantChip(ex) }
                }
            }
        }
    }

    private func variantChip(_ ex: Exercise) -> some View {
        Button { variant = ex } label: {
            Text(StrengthDisplay.name(ex))
                .font(StrandFont.subhead).foregroundStyle(theme.ink)
                .padding(.horizontal, 13).padding(.vertical, 6)
                .overlay(Capsule(style: .continuous).strokeBorder(theme.hairlineStrong, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(StrengthDisplay.name(ex)))
    }

    /// Sibling exercises for the variants row: catalog entries that share this exercise's first primary
    /// muscle, minus itself, by display name, capped so the row stays a couple of lines. Pure + static so
    /// it's computed once in `.task`, not on every body pass over the 800-entry catalog.
    private static func variants(for exercise: Exercise) -> [Exercise] {
        guard let key = exercise.primaryMuscles.first else { return [] }
        let localized = StrengthDisplay.localized
        return ExerciseCatalog.all
            .filter { $0.id != exercise.id && $0.primaryMuscles.contains(key) }
            .sorted { $0.displayName(localized: localized) < $1.displayName(localized: localized) }
            .prefix(8).map { $0 }
    }

    // MARK: - How to (offline text cues from the bundled catalog · FER-387)

    private var howToSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider().overlay(theme.hairline)
            Text("How to").instrumentoOverline().foregroundStyle(theme.inkTertiary).padding(.top, 18)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(exercise.displayInstructions(localized: StrengthDisplay.localized).enumerated()), id: \.offset) { index, cue in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(verbatim: "\(index + 1)")
                            .font(StrandFont.captionNumber).foregroundStyle(theme.inkTertiary)
                            .frame(width: 18, alignment: .trailing)
                        Text(cue)
                            .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(.top, 11)
        }
    }

    // MARK: - Watch on YouTube (opt-in external hand-off · FER-387)
    // Offline rule: NOOP itself makes NO network call — this only hands off to the system browser /
    // YouTube app on an explicit user tap, and is clearly marked as leaving the app. Chrome, so it
    // carries no saturated color (ink/surface only).

    private var youtubeRow: some View {
        Button {
            let query = "\(exercise.name) exercise form"
            let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            if let url = URL(string: "https://www.youtube.com/results?search_query=\(encoded)") {
                openURL(url)
            }
        } label: {
            HStack(spacing: 11) {
                Image(systemName: "play.rectangle").foregroundStyle(theme.inkSecondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Watch on YouTube").font(StrandFont.subhead).foregroundStyle(theme.ink)
                    Text("Opens outside the app · uses the internet")
                        .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                }
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.forward").font(.caption).foregroundStyle(theme.inkTertiary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous)
                .strokeBorder(theme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Watch \(exercise.name) on YouTube")
        .accessibilityHint("Opens YouTube outside the app")
    }

    // MARK: - Progress (a metric-switchable trend: max weight / estimated 1RM / volume · FER-505)

    private var progressSection: some View {
        let values = series(metric)
        return VStack(alignment: .leading, spacing: 10) {
            Divider().overlay(theme.hairline).padding(.bottom, 8)
            Text("Progress").instrumentoOverline().foregroundStyle(theme.inkTertiary)

            Picker("Progress metric", selection: $metric) {
                ForEach(ProgressMetric.allCases) { m in Text(m.label).tag(m) }
            }
            .pickerStyle(.segmented)

            HStack(alignment: .firstTextBaseline) {
                Text(metric.label).instrumentoOverline().foregroundStyle(theme.inkTertiary)
                Spacer(minLength: 8)
                if let latest = values.last {
                    Text(latestText(latest))
                        .font(StrandFont.number(22, weight: .semibold)).foregroundStyle(theme.ink)
                        .monospacedDigit()
                }
            }
            .padding(.top, 2)

            StatTile(label: String(localized: "VOLUME"),
                     value: weeklyVolumeText,
                     unit: String(localized: "/ WEEK"),
                     theme: theme)

            if values.count >= 2 {
                if metric == .weight {
                    // FER-F · 2d: the working weight moves in JUMPS — a step render is the honest shape.
                    // Green dot = confirmed raise; amber dot = a deload (the drop is the datum too).
                    StepChart(values: values, line: theme.ink.opacity(0.75),   // token-exempt: alfa de línea de dato (StepChart)
                              raiseDot: theme.dataRecovery, deloadDot: theme.warning)
                        .frame(height: 64)
                        .accessibilityLabel(Text(metric.label) + Text(verbatim: " trend"))
                    weightStrip(values)
                } else {
                    // Quiet axis grid + month/TODAY labels — local to this screen only (shared Sparkline stays bare).
                    ZStack(alignment: .leading) {
                        VStack(spacing: 0) {
                            ForEach(0..<4, id: \.self) { i in
                                Rectangle().fill(theme.hairline).frame(height: 1)
                                if i < 3 { Spacer(minLength: 0) }
                            }
                        }
                        .frame(height: 64)
                        Sparkline(values: values,
                                  gradient: ChartWell.fillGradient(theme.dataStrain),
                                  bandColor: theme.hairlineStrong,
                                  showsScrub: true,
                                  valueFormat: { latestText($0) })
                            .frame(height: 64)
                    }
                    .accessibilityLabel(Text(metric.label) + Text(verbatim: " trend"))
                    progressAxisLabels
                }
            }
            cycleBlock
            Text(metricNote)
                .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Total volume (weight × reps) logged in the last 7 days, for the VOLUME / WEEK tile.
    private var weeklyVolumeText: String {
        let cutoff = Int(Date().timeIntervalSince1970) - 7 * 24 * 3600
        let total = history
            .filter { $0.startTs >= cutoff }
            .reduce(0.0) { $0 + $1.weightKg * Double($1.reps) }
        return StrengthHistoryFormat.volume(total, system: system)
    }

    /// Three quiet captions under the 1RM/volume sparkline: first month · middle month · TODAY.
    @ViewBuilder private var progressAxisLabels: some View {
        // Chronological (oldest→newest) so left→right matches the sparkline series.
        let days = historyDays.sorted { $0.ts < $1.ts }
        if days.count >= 3 {
            let first = Self.monthAbbrev(days.first!.ts)
            let middle = Self.monthAbbrev(days[days.count / 2].ts)
            HStack(spacing: 0) {
                Text(first)
                    .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(middle)
                    .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                Text("TODAY")
                    .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private static func monthAbbrev(_ ts: Int) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: Date(timeIntervalSince1970: TimeInterval(ts))).uppercased()
    }

    // MARK: Weight strip + current cycle (FER-F · 2d)

    /// Under the step chart: Now (green — it's the datum) · raises («N · X wk») · change (+%).
    private func weightStrip(_ values: [Double]) -> some View {
        let raises = zip(values, values.dropFirst()).filter { $1 > $0 + 0.0001 }.count
        let weeks = historyDays.count >= 2
            ? max(1, (historyDays.last!.ts - historyDays.first!.ts) / 604_800) : 0
        let change = (values.first ?? 0) > 0 ? ((values.last! - values.first!) / values.first!) * 100 : 0
        return HStack(spacing: 14) {
            stripStat(Text("Now"), Text(verbatim: StrengthDisplay.weight(values.last ?? 0, system: system)),
                      color: theme.dataRecovery)
            stripStat(Text("Raises"), Text(verbatim: "\(raises) · \(weeks) wk"), color: theme.ink)
            stripStat(Text("Change"),
                      Text(verbatim: (change >= 0 ? "+" : "") + change.formatted(.number.precision(.fractionLength(0...1))) + " %"),
                      color: change >= 0 ? theme.dataRecovery : theme.warning)
            Spacer(minLength: 0)
        }
    }

    private func stripStat(_ label: Text, _ value: Text, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            label.instrumentoOverline().foregroundStyle(theme.inkTertiary)
            value.font(InstrumentoType.grotesk(13, weight: .bold)).monospacedDigit().foregroundStyle(color)
        }
    }

    /// «CICLO ACTUAL» — where this exercise's progression stands, in one sentence with real numbers.
    /// Only renders when some routine slot opted into progression for this exercise.
    @ViewBuilder private var cycleBlock: some View {
        if let line = cycleLine {
            VStack(alignment: .leading, spacing: 5) {
                Text("Current cycle").instrumentoOverline().foregroundStyle(theme.dataRecovery)
                line.font(StrandFont.caption).foregroundStyle(theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 13).padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surface)
            .overlay(alignment: .leading) { Rectangle().fill(theme.dataRecovery).frame(width: 2.5) }
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0,
                                              bottomTrailingRadius: 8, topTrailingRadius: 8))
        }
    }

    private var cycleLine: Text? {
        guard let state = cycleState else { return nil }
        let kg = { (v: Double) in StrengthDisplay.weight(v, system: system) }
        switch state {
        case .inCycle(let done, let of):
            let at = historyDays.last.map { kg($0.weightKg) } ?? ""
            return Text("You're \(done) of \(of) sessions in with \(at).")
        case .readyToAdvance(let newKg):
            return Text("Cycle complete: your next session arrives with \(kg(newKg)).")
        case .deferred(let newKg):
            return Text("The raise to \(kg(newKg)) waits for your next session: recovery ran low.")
        case .stalled(let sessions):
            return Text("\(sessions) sessions without hitting the goal at this weight.")
        case .deloading(let fromKg, let toKg):
            return Text("Proposed deload: \(kg(fromKg)) → \(kg(toKg)), then rebuild.")
        }
    }

    /// Formats the headline + tooltip value for the selected metric (weights in the user's unit; volume
    /// grouped with thousands, reusing the history screen's formatter).
    private func latestText(_ v: Double) -> String {
        switch metric {
        case .weight, .oneRM: return StrengthDisplay.weight(v, system: system)
        case .volume:         return StrengthHistoryFormat.volume(v, system: system)
        }
    }

    private var metricNote: LocalizedStringKey {
        switch metric {
        case .weight: return "The heaviest set you logged, by day."
        case .oneRM:  return "From your best set with the Epley (1985) formula. A progress signal, not a target to load."
        case .volume: return "Weight × reps per day."
        }
    }

    /// The selected metric as a per-day series, oldest→newest. Max-weight takes the day's heaviest set;
    /// volume sums weight×reps over the day; 1RM reuses the cited `OneRepMax.dailySparkline`.
    private func series(_ metric: ProgressMetric) -> [Double] {
        switch metric {
        case .oneRM:
            return OneRepMax.dailySparkline(history.map {
                (day: dayKey($0.startTs), weightKg: $0.weightKg, reps: $0.reps)
            }).map(\.estimatedKg)
        case .weight:
            return byDay { Swift.max($0, $1.weightKg) }
        case .volume:
            return byDay { $0 + $1.weightKg * Double($1.reps) }
        }
    }

    private func byDay(_ combine: (Double, (startTs: Int, weightKg: Double, reps: Int, optedOut: Bool)) -> Double) -> [Double] {
        var acc: [String: Double] = [:]
        for s in history { acc[dayKey(s.startTs)] = combine(acc[dayKey(s.startTs)] ?? 0, s) }
        return acc.sorted { $0.key < $1.key }.map(\.value)
    }

    private func dayKey(_ ts: Int) -> String {
        Repository.localDayKey(Date(timeIntervalSince1970: TimeInterval(ts)))
    }

    // MARK: - Personal records (best-per-metric, stored on save · FER-505)

    @ViewBuilder
    private var recordsSection: some View {
        let rows = recordRows
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Divider().overlay(theme.hairline).padding(.vertical, 8)
                Text("Personal records").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                ForEach(rows, id: \.id) { row in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(row.label).font(StrandFont.subhead).foregroundStyle(theme.ink)
                            if let detail = row.detail {
                                Text(detail).font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                            }
                        }
                        Spacer(minLength: 8)
                        Text(row.value).font(StrandFont.number(17, weight: .semibold))
                            .foregroundStyle(theme.ink).monospacedDigit()
                    }
                    .padding(.vertical, 5)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private struct RecordRow { let id: String; let label: LocalizedStringKey; let detail: String?; let value: String }

    /// The stored PRs (maxWeight / maxReps / maxVolume) as display rows, in that fixed order.
    private var recordRows: [RecordRow] {
        let byMetric = Dictionary(prs.map { ($0.metric, $0) }, uniquingKeysWith: { a, _ in a })
        var rows: [RecordRow] = []
        if let pr = byMetric[.maxWeight], let kg = pr.valueKg {
            rows.append(RecordRow(id: "weight", label: "Max weight", detail: relative(pr.ts),
                                  value: StrengthDisplay.weight(kg, system: system)))
        }
        if let pr = byMetric[.maxReps], let reps = pr.reps {
            rows.append(RecordRow(id: "reps", label: "Most reps", detail: relative(pr.ts), value: "\(reps)"))
        }
        if let pr = byMetric[.maxVolume], let kg = pr.valueKg, let reps = pr.reps {
            rows.append(RecordRow(id: "volume", label: "Best set volume",
                                  detail: "\(StrengthDisplay.weight(kg, system: system)) × \(reps) · \(relative(pr.ts))",
                                  value: StrengthHistoryFormat.volume(kg * Double(reps), system: system)))
        }
        return rows
    }

    // MARK: - Honest empty

    private var emptyHistory: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider().overlay(theme.hairline)
            VStack(spacing: 11) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 30)).foregroundStyle(theme.inkTertiary) // token-exempt: 30pt, .empty(34) sería +4pt (>±1pt)
                Text("Not logged yet").font(StrandFont.title2).foregroundStyle(theme.ink)
                Text("Your best mark, your last session and your estimated 1RM appear here once you complete a work set.")
                    .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
        }
    }

    // MARK: - Derived + formatting

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .short; return f
    }()

    private func relative(_ ts: Int) -> String {
        Self.relativeFormatter.localizedString(for: Date(timeIntervalSince1970: TimeInterval(ts)), relativeTo: Date())
    }
}

// MARK: - Chip flow (FER-739)

/// Minimal flow layout: lays chips left-to-right, wrapping to a new row when the next would overflow the
/// proposed width — so the muscle + variant chips wrap instead of truncating at large Dynamic Type sizes.
/// (Same shape as `LiveStrengthSheet`'s private `ChipFlow`; kept local so neither file exports it.)
private struct ChipFlow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for v in subviews {
            let sz = v.sizeThatFits(.unspecified)
            if x > 0, x + sz.width > maxW { x = 0; y += rowH + spacing; rowH = 0 }
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
        return CGSize(width: maxW.isFinite ? maxW : x, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for v in subviews {
            let sz = v.sizeThatFits(.unspecified)
            if x > 0, x + sz.width > bounds.width { x = 0; y += rowH + spacing; rowH = 0 }
            v.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
    }
}
#endif
