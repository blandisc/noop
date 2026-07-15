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
    /// Where this exercise's progression cycle stands (FER-F); nil = no slot opted in.
    @State private var cycleState: ProgressionState? = nil
    /// Which series the progress chart shows (FER-505). Est. 1RM is the default hero trend.
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
        var label: String {
            switch self {
            case .guide:    return String(localized: "Guide")
            case .progress: return String(localized: "Progress")
            case .history:  return String(localized: "History")
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

    /// A per-day metric the progress views derive from the raw history.
    private enum ProgressMetric {
        case weight, oneRM, volume
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CenitMetrics.sectionGap) {
                // Two-speed rhythm (handoff): the chrome block — title, hero, segmented — sits
                // tight at `gap`; `sectionGap` breathes only between the block and the tab content.
                VStack(alignment: .leading, spacing: CenitMetrics.gap) {
                    header
                    // Reserved media hero (FER-751, handoff 1g/1h): sits between the title and the
                    // segmented control. FER-722/778 fill this same slot with the cached loop/thumb
                    // (auto-play + top-right play/pause) without shifting the layout.
                    heroSection
                    SegmentedPillControl(DetailTab.allCases, selection: $tab, theme: theme,
                                         inkThumb: true) { $0.label }
                }
                switch tab {
                case .guide:    guideTab
                case .progress: progressTab
                case .history:  historyTab
                }
            }
            .padding(.top, CenitMetrics.gap)
            .padding(.horizontal, CenitMetrics.screenPadding)
            .padding(.bottom, CenitMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.paper.ignoresSafeArea())
        .task(id: exercise.id) {
            async let h = repo.exerciseHistory(exerciseId: exercise.id)
            async let ov = repo.exerciseTypeOverride(exercise.id)
            history = await h
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
                    // Handoff: the hero is a fixed 176pt banner, not a full-width square — the
                    // segmented control and the datum stay above the fold.
                    .frame(maxWidth: .infinity).frame(height: ExerciseThumbnail.heroHeight)
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
            // Handoff: the hero carries a 2px frame in the movement family's hue — the same frame
            // the Library draws on its thumbnails.
            .overlay(RoundedRectangle(cornerRadius: ExerciseThumbnail.heroCornerRadius, style: .continuous)
                .strokeBorder(familyTint, lineWidth: 2))
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("\(exercise.name) preview"))
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    ExerciseThumbnail(hero: nil)
                    if loadingMedia { ProgressView().tint(theme.inkTertiary) }
                }
                .overlay(RoundedRectangle(cornerRadius: ExerciseThumbnail.heroCornerRadius, style: .continuous)
                    .strokeBorder(familyTint, lineWidth: 2))
                if !mediaCoordinator.isEnabled { mediaOffHint }
            }
        }
    }

    /// The movement-family hue (push=ember · pull=teal · legs=indigo) — the same mapping the Library
    /// uses on its thumbnails, so the frame, the primary-muscle chips and the how-to numbers agree.
    private var familyTint: Color {
        let m = (exercise.primaryMuscles.first ?? "").lowercased()
        if ["chest", "shoulders", "triceps"].contains(where: m.contains) { return theme.dataStrain }
        if ["lats", "back", "biceps", "traps", "forearms"].contains(where: m.contains) { return theme.dataHrv }
        if ["quadriceps", "hamstrings", "glutes", "calves", "abductors", "adductors"].contains(where: m.contains) { return theme.dataSleep }
        return theme.dataStrain
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

    /// «Progreso» — the handoff's fixed composition: the estimated-1RM hero + delta chip, the axis
    /// chart in a card, and the BEST SET / VOLUME-PER-WEEK mini cards (or an honest empty).
    @ViewBuilder private var progressTab: some View {
        if loaded {
            if history.isEmpty { emptyHistory } else {
                progressSection
                cycleBlock
                Text("From your best set with the Epley (1985) formula. A progress signal, not a target to load.")
                    .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// «Historial» — every logged day for this exercise, newest first.
    @ViewBuilder private var historyTab: some View {
        if loaded {
            if history.isEmpty { emptyHistory } else { historyList }
        }
    }

    /// Handoff: one block per logged day — family-hue dot + date, a RECORD badge on the day that set
    /// the all-time top weight, and EVERY set of that day as quiet «82,5 × 8» chips.
    private var historyList: some View {
        let sessions = historySessions
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(sessions.enumerated()), id: \.offset) { idx, day in
                VStack(alignment: .leading, spacing: CenitMetrics.space2) {
                    HStack(spacing: CenitMetrics.space2) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(familyTint).frame(width: 8, height: 8)
                        Text(historyDayLabel(day.ts))
                            .font(StrandFont.body.weight(.medium)).foregroundStyle(theme.ink)
                        Spacer(minLength: 8)
                        if day.isRecord {
                            Text("RECORD")
                                .font(InstrumentoType.grotesk(10, weight: .bold)).tracking(0.5)
                                .foregroundStyle(theme.paper)
                                .padding(.horizontal, 7).padding(.vertical, 2)  // token-exempt: badge del handoff
                                .background(familyTint, in: RoundedRectangle(cornerRadius: 7, style: .continuous))  // token-exempt: radio 7 del handoff
                        }
                    }
                    ChipFlow(spacing: 7) {
                        ForEach(Array(day.sets.enumerated()), id: \.offset) { _, s in
                            Text(verbatim: "\(StrengthDisplay.weightNumber(s.kg, system: system)) × \(s.reps)")
                                .font(InstrumentoType.grotesk(13, weight: .semibold)).monospacedDigit()
                                .foregroundStyle(theme.ink)
                                .padding(.horizontal, 9).padding(.vertical, 4)  // token-exempt: chip 9/4 del handoff
                                .background(theme.patternBlock, in: RoundedRectangle(cornerRadius: CenitMetrics.chipRadius, style: .continuous))
                        }
                    }
                }
                .padding(.vertical, CenitMetrics.gap)
                .accessibilityElement(children: .combine)
                if idx < sessions.count - 1 { Divider().overlay(theme.hairline) }
            }
        }
    }

    /// All sets grouped by day, newest first; `isRecord` marks the newest day that reached the
    /// all-time top weight.
    private var historySessions: [(ts: Int, sets: [(kg: Double, reps: Int)], isRecord: Bool)] {
        var byDay: [String: (ts: Int, sets: [(kg: Double, reps: Int)])] = [:]
        for h in history.sorted(by: { $0.startTs < $1.startTs }) {
            let key = dayKey(h.startTs)
            var entry = byDay[key] ?? (h.startTs, [])
            entry.sets.append((h.weightKg, h.reps))
            byDay[key] = entry
        }
        let days = byDay.values.sorted { $0.ts > $1.ts }
        let maxKg = history.map(\.weightKg).max() ?? 0
        var recordMarked = false
        return days.map { day in
            let hits = maxKg > 0 && day.sets.contains { $0.kg >= maxKg - 0.0001 }
            let isRecord = hits && !recordMarked
            if isRecord { recordMarked = true }
            return (day.ts, day.sets, isRecord)
        }
    }

    /// «Hoy» for today, else a short day-month («8 jul»).
    private func historyDayLabel(_ ts: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(ts))
        if Calendar.current.isDateInToday(date) { return String(localized: "Today") }
        return date.formatted(.dateTime.day().month(.abbreviated))
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

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(metaLine)
                .instrumentoOverline().foregroundStyle(theme.inkTertiary)
            Text(StrengthDisplay.name(exercise))
                // §8.7: redesigned sheets title in Grotesk (handoff: 700 26px, tight tracking).
                .font(InstrumentoType.grotesk(26, weight: .bold)).tracking(InstrumentoType.groteskHeroTrackingScaled(26))
                .foregroundStyle(theme.ink)
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
                        StrandIcon.down.image.font(StrandFont.glyph(.chevron)).foregroundStyle(theme.inkTertiary)
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
            VStack(alignment: .leading, spacing: CenitMetrics.space2) {
                Text("Muscles").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                ChipFlow(spacing: 8) {
                    ForEach(exercise.primaryMuscles, id: \.self) { m in muscleChip(m, primary: true) }
                    ForEach(exercise.secondaryMuscles, id: \.self) { m in muscleChip(m, primary: false) }
                }
                if !exercise.secondaryMuscles.isEmpty {
                    Text("Primary in color · assisting in gray")
                        .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                }
            }
        }
    }

    /// Handoff: the primary mover is the datum — its chip carries the family hue on a 12% tint
    /// («Pecho · principal»); assistants sit quiet on the sunken gray. Rounded rects, not capsules.
    private func muscleChip(_ muscle: String, primary: Bool) -> some View {
        Group {
            if primary {
                Text("\(StrengthDisplay.muscle(muscle)) · \(String(localized: "primary"))")
                    .font(StrandFont.subhead).foregroundStyle(familyTint)
            } else {
                Text(StrengthDisplay.muscle(muscle))
                    .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
            }
        }
        .padding(.horizontal, 11).padding(.vertical, 5)  // token-exempt: chip 11/5 del handoff
        .background(primary ? familyTint.opacity(0.12) : theme.patternBlock,  // token-exempt: tinte 12% del handoff
                    in: RoundedRectangle(cornerRadius: CenitMetrics.chipRadius, style: .continuous))
        .accessibilityElement()
        .accessibilityLabel("\(StrengthDisplay.muscle(muscle)), \(String(localized: primary ? "primary" : "assisting"))")
    }

    // MARK: - Variants (FER-739) — other catalog exercises for the same primary muscle

    /// A row of chips for sibling exercises that load the same primary muscle; tapping one opens its
    /// sheet. Derived from the catalog (no new «variants» field), so it's empty for a bare custom
    /// exercise or one whose primary muscle nothing else shares.
    @ViewBuilder private var variantsSection: some View {
        if !variants.isEmpty {
            VStack(alignment: .leading, spacing: CenitMetrics.space2) {
                Divider().overlay(theme.hairline).padding(.bottom, CenitMetrics.space1)
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
                .padding(.horizontal, 11).padding(.vertical, 5)  // token-exempt: chip 11/5 del handoff
                .overlay(RoundedRectangle(cornerRadius: CenitMetrics.chipRadius, style: .continuous)
                    .strokeBorder(theme.hairlineStrong, lineWidth: 1))
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
        let cues = exercise.displayInstructions(localized: StrengthDisplay.localized)
        return VStack(alignment: .leading, spacing: 0) {
            Text("How to").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(cues.enumerated()), id: \.offset) { index, cue in
                    // Handoff: the step number leads in the family hue (Grotesk 15 bold), the cue in
                    // ink, hairline-divided rows.
                    HStack(alignment: .firstTextBaseline, spacing: CenitMetrics.gap) {
                        Text(verbatim: "\(index + 1)")
                            .font(InstrumentoType.grotesk(15, weight: .bold)).monospacedDigit()
                            .foregroundStyle(familyTint)
                            .frame(width: 15, alignment: .leading)
                        Text(cue)
                            .font(StrandFont.subhead).foregroundStyle(theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 11)  // token-exempt: fila 11pt del handoff
                    if index < cues.count - 1 { Divider().overlay(theme.hairline) }
                }
            }
            .padding(.top, 2)
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
            // Handoff: a flat row over a top hairline — no card. The icon sits in a small sunken square.
            VStack(spacing: 0) {
                Divider().overlay(theme.hairline)
                HStack(spacing: CenitMetrics.gap) {
                    Image(systemName: "play.rectangle").font(StrandFont.glyph(.inline)).foregroundStyle(theme.inkSecondary)
                        .frame(width: 34, height: 34)
                        .background(theme.patternBlock, in: RoundedRectangle(cornerRadius: CenitMetrics.insetRadius, style: .continuous))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Watch on YouTube").font(StrandFont.subhead).foregroundStyle(theme.ink)
                        Text("Opens outside the app · uses the internet")
                            .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                    }
                    Spacer(minLength: 8)
                    StrandIcon.disclosure.image.font(StrandFont.glyph(.chevron)).foregroundStyle(theme.inkTertiary)
                }
                .padding(.top, CenitMetrics.gap)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Watch \(exercise.name) on YouTube")
        .accessibilityHint("Opens YouTube outside the app")
    }

    // MARK: - Progress (a metric-switchable trend: max weight / estimated 1RM / volume · FER-505)

    private var progressSection: some View {
        let oneRM = series(.oneRM)
        return VStack(alignment: .leading, spacing: 0) {
            // Handoff: overline + the tab's ONE dominant number — today's estimated 1RM — with a
            // quiet green delta chip when the trend is up.
            Text("ESTIMATED 1RM · TODAY").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            HStack(alignment: .firstTextBaseline, spacing: CenitMetrics.gap) {
                if let latest = oneRM.last {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(verbatim: StrengthDisplay.weightNumber(latest, system: system))
                            .font(InstrumentoType.groteskHeroNumeral(44)).tracking(InstrumentoType.groteskHeroTrackingScaled(44))
                            .foregroundStyle(theme.ink).monospacedDigit()
                        Text(verbatim: StrengthDisplay.weightUnit(system))
                            .font(InstrumentoType.grotesk(22, weight: .bold)).foregroundStyle(theme.inkTertiary)
                    }
                }
                if let first = oneRM.first, let last = oneRM.last, last > first + 0.05 {
                    Text("↗ +\(StrengthDisplay.weight(last - first, system: system)) / \(weeksSpan) wk")
                        .font(InstrumentoType.grotesk(13, weight: .bold)).monospacedDigit()
                        .foregroundStyle(theme.dataRecovery)
                        .padding(.horizontal, 9).padding(.vertical, 3)  // token-exempt: chip delta del handoff
                        .background(theme.dataRecovery.opacity(0.12),   // token-exempt: tinte 12% del handoff
                                    in: RoundedRectangle(cornerRadius: CenitMetrics.chipRadius, style: .continuous))
                }
            }
            .padding(.top, 3)

            // The axis chart, in a raised card (handoff: gridlines + y labels + MAY/JUN/HOY).
            if oneRM.count >= 2, !historyDays.isEmpty {
                TrendAxisChart(values: oneRM, xFirst: monthLabel(historyDays.last?.ts),
                               xMid: monthLabel(historyDays[historyDays.count / 2].ts),
                               accent: familyTint, theme: theme)
                    .padding(.top, CenitMetrics.cardPadding)
                    .accessibilityLabel(Text("Est. 1RM") + Text(verbatim: " trend"))
            }

            // BEST SET · VOLUME / WK — two mini cards, each with its own mini chart.
            HStack(alignment: .top, spacing: CenitMetrics.gap) {
                bestSetCard
                volumeCard
            }
            .padding(.top, 14)  // token-exempt: 14 del handoff
        }
    }

    /// The whole logged span in weeks (≥1), for the delta chip and card captions.
    private var weeksSpan: Int {
        let days = historyDays
        guard days.count >= 2 else { return 1 }
        return max(1, (days.first!.ts - days.last!.ts) / 604_800)
    }

    /// A short uppercase month for the chart's x axis («MAY»), localized.
    private func monthLabel(_ ts: Int?) -> String {
        guard let ts else { return "" }
        return Date(timeIntervalSince1970: TimeInterval(ts))
            .formatted(.dateTime.month(.abbreviated)).uppercased()
    }

    /// «MEJOR SERIE» — the all-time heaviest set + the max-weight-by-day mini sparkline.
    @ViewBuilder private var bestSetCard: some View {
        if let best = history.max(by: { $0.weightKg < $1.weightKg }) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Best set").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(verbatim: StrengthDisplay.weightNumber(best.weightKg, system: system))
                        .font(InstrumentoType.grotesk(20, weight: .bold)).monospacedDigit()
                        .foregroundStyle(theme.ink)
                    Text(verbatim: "× \(best.reps)")
                        .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                }
                Sparkline(values: series(.weight),
                          gradient: Gradient(colors: [familyTint, familyTint]),
                          bandColor: .clear, showsArea: false, showsHead: true, showsScrub: false)
                    .frame(height: 36)
                    .padding(.top, 7)  // token-exempt: 7 del handoff
                    .accessibilityHidden(true)
                Text("max weight · \(weeksSpan) wk")
                    .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 13).padding(.vertical, CenitMetrics.gap)  // token-exempt: 13 del handoff
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))  // token-exempt: radio 14 del handoff
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(theme.hairline, lineWidth: 1))
            .accessibilityElement(children: .combine)
        }
    }

    /// «VOLUMEN / SEM» — last week's tonnage + seven weekly bars (the current week in full hue).
    private var volumeCard: some View {
        let vols = weeklyVolumes
        var streak = 0
        var i = vols.count - 1
        while i > 0, vols[i] > vols[i - 1] + 0.0001 { streak += 1; i -= 1 }
        return VStack(alignment: .leading, spacing: 3) {
            Text("Volume / wk").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            Text(verbatim: StrengthHistoryFormat.volume(vols.last ?? 0, system: system))
                .font(InstrumentoType.grotesk(20, weight: .bold)).monospacedDigit()
                .foregroundStyle(theme.ink)
            weeklyBars(vols)
                .frame(height: 36)
                .padding(.top, 7)  // token-exempt: 7 del handoff
                .accessibilityHidden(true)
            Group {
                if streak >= 1 {
                    Text("↗ up \(streak) wk").foregroundStyle(theme.dataRecovery)
                } else {
                    Text("steady").foregroundStyle(theme.inkTertiary)
                }
            }
            .font(StrandFont.caption)
            .padding(.top, 4)
        }
        .padding(.horizontal, 13).padding(.vertical, CenitMetrics.gap)  // token-exempt: 13 del handoff
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))  // token-exempt: radio 14 del handoff
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(theme.hairline, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    /// Volume (weight × reps) per calendar week, oldest→newest, over the last 7 weeks.
    private var weeklyVolumes: [Double] {
        let cal = Calendar.current
        guard let thisWeek = cal.dateInterval(of: .weekOfYear, for: Date())?.start else { return [] }
        return (0..<7).reversed().map { back in
            guard let start = cal.date(byAdding: .weekOfYear, value: -back, to: thisWeek),
                  let end = cal.date(byAdding: .weekOfYear, value: 1, to: start) else { return 0 }
            let s = Int(start.timeIntervalSince1970), e = Int(end.timeIntervalSince1970)
            return history.filter { $0.startTs >= s && $0.startTs < e }
                .reduce(0.0) { $0 + $1.weightKg * Double($1.reps) }
        }
    }

    /// Seven rounded weekly bars — tints of the family hue, the latest week in full hue.
    private func weeklyBars(_ vols: [Double]) -> some View {
        let top = max(vols.max() ?? 1, 0.0001)
        return GeometryReader { geo in
            HStack(alignment: .bottom, spacing: 5) {
                ForEach(Array(vols.enumerated()), id: \.offset) { idx, v in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(idx == vols.count - 1 ? familyTint : familyTint.opacity(0.28))  // token-exempt: tinte 28% del handoff
                        .frame(height: max(3, geo.size.height * v / top))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: geo.size.height, alignment: .bottom)
        }
    }

    /// «CICLO ACTUAL» — where this exercise's progression stands, in one sentence with real numbers.
    /// Only renders when some routine slot opted into progression for this exercise.
    @ViewBuilder private var cycleBlock: some View {
        if let line = cycleLine {
            NoteStrip(style: .info, theme: theme) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Current cycle").instrumentoOverline().foregroundStyle(theme.dataRecovery)
                    line.font(StrandFont.caption).foregroundStyle(theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
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

    /// A metric as a per-day series, oldest→newest. Max-weight takes the day's heaviest set;
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

    // MARK: - Honest empty

    private var emptyHistory: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider().overlay(theme.hairline)
            VStack(spacing: CenitMetrics.space2) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 30)).foregroundStyle(theme.inkTertiary) // token-exempt: 30pt, .empty(34) sería +4pt (>±1pt)
                Text("Not logged yet").font(StrandFont.title2).foregroundStyle(theme.ink)
                Text("Your best mark, your last session and your estimated 1RM appear here once you complete a work set.")
                    .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, CenitMetrics.cardPadding)
        }
    }

}

// MARK: - Trend chart with axes (handoff «Detalle · Progreso»)

/// The 1RM trend in the handoff's chart card: four hairline gridlines with Grotesk y labels, the
/// series as a hue line over a soft area fill, an end dot with halo, and MAY/JUN/TODAY x captions.
private struct TrendAxisChart: View {
    let values: [Double]
    let xFirst: String
    let xMid: String
    let accent: Color
    let theme: InstrumentoTheme

    private static let plotHeight: CGFloat = 150

    var body: some View {
        let lo = values.min() ?? 0
        let hi = Swift.max(values.max() ?? 1, lo + 1)
        let pad = (hi - lo) * 0.18 + 0.001
        let top = hi + pad, bottom = Swift.max(0, lo - pad)
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                // Gridlines + y labels, top→bottom; the bottom line slightly stronger (handoff).
                VStack(spacing: 0) {
                    ForEach(0..<4, id: \.self) { i in
                        HStack(spacing: 6) {
                            Text(verbatim: "\(Int((top - (top - bottom) * Double(i) / 3).rounded()))")
                                .font(InstrumentoType.grotesk(10, weight: .semibold)).monospacedDigit()
                                .foregroundStyle(theme.inkTertiary)
                                .frame(width: 28, alignment: .trailing)
                            Rectangle().fill(i == 3 ? theme.hairlineStrong : theme.hairline).frame(height: 1)
                        }
                        if i < 3 { Spacer(minLength: 0) }
                    }
                }
                // The series: area + line + end dot, inset past the y-label column.
                GeometryReader { geo in
                    let w = geo.size.width, h = geo.size.height
                    let points = values.enumerated().map { idx, v in
                        CGPoint(x: w * CGFloat(idx) / CGFloat(max(values.count - 1, 1)),
                                y: h * CGFloat(1 - (v - bottom) / (top - bottom)))
                    }
                    ZStack {
                        Path { p in
                            guard let first = points.first, let last = points.last else { return }
                            p.move(to: CGPoint(x: first.x, y: h))
                            points.forEach { p.addLine(to: $0) }
                            p.addLine(to: CGPoint(x: last.x, y: h))
                            p.closeSubpath()
                        }
                        .fill(accent.opacity(0.10))  // token-exempt: área 10% del handoff
                        Path { p in
                            guard let first = points.first else { return }
                            p.move(to: first)
                            points.dropFirst().forEach { p.addLine(to: $0) }
                        }
                        .stroke(accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                        if let last = points.last {
                            Circle().fill(accent.opacity(0.18)).frame(width: 16, height: 16).position(last)  // token-exempt: halo del handoff
                            Circle().fill(accent).frame(width: 9, height: 9).position(last)
                        }
                    }
                }
                .padding(.leading, 34)
                .padding(.vertical, 5)   // keeps the line inside the first/last gridline
            }
            .frame(height: Self.plotHeight)
            // X captions: first month · middle month · TODAY in the hue.
            HStack(spacing: 0) {
                Text(verbatim: xFirst)
                    .font(InstrumentoType.grotesk(9, weight: .semibold)).tracking(0.6)
                    .foregroundStyle(theme.inkTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(verbatim: xMid)
                    .font(InstrumentoType.grotesk(9, weight: .semibold)).tracking(0.6)
                    .foregroundStyle(theme.inkTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                Text("Today").textCase(.uppercase)
                    .font(InstrumentoType.grotesk(9, weight: .bold)).tracking(0.6)
                    .foregroundStyle(accent)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.leading, 34)
        }
        .padding(.top, CenitMetrics.cardPadding).padding(.horizontal, 14).padding(.bottom, CenitMetrics.gap)  // token-exempt: 14 del handoff
        .background(theme.surface, in: RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous)
            .strokeBorder(theme.hairline, lineWidth: 1))
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
