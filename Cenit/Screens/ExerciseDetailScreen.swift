#if os(iOS)
import SwiftUI
import UIKit
import CenitDesign
import StrandTraining
import StrandAnalytics
import CenitStore

// ExerciseDetailScreen.swift — one exercise: which muscles it loads, your history, and an estimated-1RM
// trend (FER-346). Presented as a sheet from the library. «Báscula de papel»: weights are the heroes,
// in ink; the only color is the 1RM trend line (`dataStrain`, the output hue). With no logged work yet
// it stays honest — muscles + why the history is empty, nothing fabricated.

struct ExerciseDetailScreen: View {
    let exercise: Exercise

    /// Opens straight into the «Progress» tab (FER-136 · V7: `WorkoutHistoryScreen`'s «Progreso por
    /// ejercicio» rows land here on the 1RM trend, not the guide). Every other call site keeps the
    /// default `.guide` landing.
    init(exercise: Exercise, startOnProgress: Bool = false) {
        self.exercise = exercise
        _tab = State(initialValue: startOnProgress ? .progress : .guide)
    }

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
    @State private var history: [WorkSetHistoryRow] = []
    /// «Historial» tab, one row per day: sets, the RPEs captured that day (feeds «QUEDABAN»), and the
    /// routine name of the day's first set (nil = free session).
    @State private var historySessions: [(ts: Int, sets: [(kg: Double, reps: Int)], isRecord: Bool,
                                           rpes: [Double], routineName: String?)] = []
    @State private var historyDays: [(ts: Int, weightKg: Double, reps: Int)] = []
    @State private var historyDaysAscending: [(ts: Int, weightKg: Double, reps: Int)] = []
    @State private var seriesCache: [ProgressMetric: [Double]] = [:]
    /// Stored best-per-metric records for this exercise (FER-504/505). Read-only; derived on save.
    /// Where this exercise's progression cycle stands (FER-F); nil = no slot opted in.
    @State private var cycleState: ProgressionState? = nil
    /// The cycle's own `fromKg` (FER-149) — `ProgressionPlanner.evaluate`'s `Raise.fromKg`, the SAME
    /// current weight the classifier used to reach `cycleState` (opted-out sessions already excluded,
    /// same as the planner's `visible.last?.workingKg`). `cycleLine`'s «sube N kg hoy» increment reads
    /// this instead of re-deriving "current" from `historyDays`, which carries every logged day
    /// including opted-out ones the classifier itself ignores.
    @State private var cycleFromKg: Double? = nil
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
    /// Write failure on type override / revert (FER-969 pattern).
    @State private var saveError = false
    private var effectiveType: ExerciseType { shownType ?? exercise.type }

    /// A per-day metric the progress views derive from the raw history. `.weight`'s only consumer
    /// (the retired «Best set» mini-card) is gone as of FER-149; `.volume` predates this screen's
    /// records rows and was already unread before this change (its own byDay sum, not the
    /// per-SESSION grouping `SessionVolume.best` now uses) — left as-is, unrelated pre-existing dead
    /// code, not something this change should silently delete.
    private enum ProgressMetric: Hashable {
        case oneRM, volume
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LiquidSpace.s700) {
                // Two-speed rhythm (handoff): the chrome block — title, hero, segmented — sits
                // tight at `gap`; `sectionGap` breathes only between the block and the tab content.
                VStack(alignment: .leading, spacing: LiquidSpace.s300) {
                    header
                    // Reserved media hero (FER-751, handoff 1g/1h): sits between the title and the
                    // segmented control. FER-722/778 fill this same slot with the cached loop/thumb
                    // (auto-play + top-right play/pause) without shifting the layout.
                    heroSection
                    SegmentedPillControl(DetailTab.allCases, selection: $tab,
                                         squared: true) { $0.label }
                }
                switch tab {
                case .guide:    guideTab
                case .progress: progressTab
                case .history:  historyTab
                }
                // Handoff V10 (FER-139): «Cambiar tipo de medida» is a persistent footer, visible
                // under any of the three tabs — not only Guía.
                measurementSection
            }
            .padding(.top, LiquidSpace.s300)
            .padding(.horizontal, LiquidSpace.s600)
            .padding(.bottom, LiquidSpace.s600)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // FER-198 (Ola 2, épico FER-195): fondo de vidrio El Eje (Ola 1, FER-197) — este tipo no
        // trae `NavigationStack` propio (lo pone el caller, ver `.sheet(item:$variant)` abajo, que
        // se CONSERVA tal cual con su toolbar «Done»); solo cambia el papel plano de su raíz.
        .entrenarHojaFondo(tono: .neutro)
        .pantallaFondo()
        .saveErrorToast(isPresented: $saveError)
        // Keyed to the repository pass too (FER-82): the cycle line reads today's verdict, so a visit
        // opened during a cold start corrects itself the moment the verdict lands.
        .task(id: [exercise.id, String(repo.refreshSeq)]) {
            async let h = repo.exerciseHistory(exerciseId: exercise.id)
            async let ov = repo.exerciseTypeOverride(exercise.id)
            history = await h
            rebuildHistoryDerived()
            hasTypeOverride = await ov != nil
            // FER-F: where the progression cycle stands — only if some routine slot opted in for this
            // exercise (first enabled slot wins; multi-routine overlap is rare and reads the same history).
            cycleState = nil
            cycleFromKg = nil
            if exercise.type == .weightReps, let store = await repo.storeHandle() {
                let rs = (try? await store.routines()) ?? []
                var slot: RoutineExercise? = nil
                for r in rs where slot == nil {
                    let exs = (try? await store.routineExercises(routineId: r.id)) ?? []
                    slot = exs.first { $0.exerciseId == exercise.id && $0.progressionEnabled }
                }
                if let re = slot {
                    let inventory = PlatesStore().inventory
                    // FER-82: while the day's verdict is still being computed this line would claim
                    // «la subida espera un día en rango» about a day nobody has judged. `speaks` is
                    // the same silence gate the hero uses; the task re-runs when the verdict lands.
                    let advice = repo.trainingAdvice
                    if TrainingRegulation.hasLanded(advice) {
                        let evaluated = ProgressionPlanner.evaluate(
                            re: re, history: history, inventory: inventory,
                            equipment: exercise.equipment, advice: advice)
                        cycleState = evaluated?.state
                        cycleFromKg = evaluated?.raise?.fromKg
                    }
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
                        Button("Done") { variant = nil }.foregroundStyle(LiquidColor.tinta900)
                    } }
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbarBackground(LiquidColor.papelTarjeta, for: .navigationBar)
            }
            .environmentObject(repo)
            .environmentObject(mediaCoordinator)
            .preferredColorScheme(.light)
        }
    }

    // MARK: - Tabs (v3 · 1g/1h)

    /// «Guía» — how the exercise loads the body and how to do it. In the handoff's order (FER-739):
    /// muscles (chips) → how-to → variants → YouTube at the foot. «Measured by» moved out to
    /// `measurementSection` as a persistent footer (handoff V10 · FER-139): «Cambiar tipo de
    /// medida» reads the same whichever tab you're on, not just Guía. The media hero
    /// (FER-751/722/778) already sits above the segmented control, so nothing repeats it here.
    @ViewBuilder private var guideTab: some View {
        musclesSection
        if !exercise.displayInstructions(localized: StrengthDisplay.localized).isEmpty { howToSection }
        variantsSection
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
                    // Handoff (FER-149): the hero is a fixed 150pt banner (`detailHeroMedia`, its
                    // OWN token — `ExerciseThumbnail.heroHeight` (176) stays untouched, it's shared
                    // with every other tile that component draws), not a full-width square — the
                    // segmented control and the datum stay above the fold.
                    .frame(maxWidth: .infinity).frame(height: EntrenarMetrics.detailHeroMedia)
                    .clipShape(RoundedRectangle(cornerRadius: ExerciseThumbnail.heroCornerRadius, style: .continuous))
                    .accessibilityHidden(true)
                Button { isLoopPlaying.toggle() } label: {
                    Image(systemName: isLoopPlaying ? "pause.fill" : "play.fill")
                        .font(LiquidType.infoGlifoCompacto.weight(.semibold))
                        .foregroundStyle(LiquidColor.papelTarjeta)
                        .padding(LiquidSpace.s200).background(.black.opacity(CenitOpacity.strokeSoft), in: Circle())
                }
                .buttonStyle(EntrenarPressStyle())
                // FER-121: círculo visible ≈28pt; el toque real crece a 44 (HIG) sin mover el
                // círculo — padding + contentShape + padding negativo se cancelan en layout
                // (mismo truco FER-947 / `LiquidControl.hitTarget`).
                .padding(LiquidSpace.s200).contentShape(Rectangle()).padding(-LiquidSpace.s200)  // token-exempt(unico): hit slop pair simétrico ±s200
                .padding(LiquidSpace.filaRespiro)
                .accessibilityLabel(Text(isLoopPlaying ? "Pause preview" : "Play preview"))
            }
            // Handoff: the hero carries a frame in the movement family's hue — the same frame
            // the Library draws on its thumbnails (1.5pt El Eje).
            .overlay(RoundedRectangle(cornerRadius: ExerciseThumbnail.heroCornerRadius, style: .continuous)
                .strokeBorder(familyTint, lineWidth: 1.5))  // token-exempt(optico): aro del hero El Eje (1.5)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("\(exercise.name) preview"))
        } else {
            VStack(alignment: .leading, spacing: LiquidSpace.s200) {
                ZStack {
                    ExerciseThumbnail(hero: nil)
                    if loadingMedia { ProgressView().tint(LiquidColor.tinta500) }
                }
                // `ExerciseThumbnail(hero:)` draws its own fixed 176pt slot (shared component, not
                // touched) — clipped down to the screen's own 150pt token so the placeholder matches
                // the real media hero above without a second height living on the component itself.
                .frame(maxWidth: .infinity).frame(height: EntrenarMetrics.detailHeroMedia).clipped()
                .overlay(RoundedRectangle(cornerRadius: ExerciseThumbnail.heroCornerRadius, style: .continuous)
                    .strokeBorder(familyTint, lineWidth: 1.5))  // token-exempt(optico): aro del hero El Eje (1.5)
                if !mediaCoordinator.isEnabled { mediaOffHint }
            }
        }
    }

    /// The movement-family hue (push=ember · pull=teal · legs=indigo) — the same mapping the Library
    /// uses on its thumbnails, so the frame, the primary-muscle chips and the how-to numbers agree.
    private var familyTint: Color {
        // r21: mapeo PROMOVIDO a CenitDesign (`LiquidRampas.movementFamilyTint`) — misma clasificación, una
        // sola fuente de verdad (se conserva el «solo el primer músculo» de esta pantalla).
        LiquidRampas.movementFamilyTint([exercise.primaryMuscles.first ?? ""])
    }

    /// Discreet nudge shown only when the media download toggle is off — never when it's on and this
    /// exercise simply has no EDB match (that's a quiet, honest miss, not something to fix in Ajustes).
    private var mediaOffHint: some View {
        Button {
            tabRouter.select(.settings)
            dismiss()
        } label: {
            HStack(spacing: LiquidSpace.s150) {
                Image(systemName: "play.rectangle").font(LiquidType.iconSF(size: 12))
                Text("Turn on library downloads in Settings to see video")
                    .font(LiquidType.cuerpo)
            }
            .foregroundStyle(LiquidColor.tinta500)
        }
        .buttonStyle(EntrenarPressStyle())
    }

    /// «Progreso» — the handoff's fixed composition: the estimated-1RM hero + delta chip, the axis
    /// chart in a card, and the BEST SET / VOLUME-PER-WEEK mini cards (or an honest empty).
    @ViewBuilder private var progressTab: some View {
        if loaded {
            if history.isEmpty { emptyHistory } else {
                progressSection
                recordsSection
                Text("From your best set with the Epley (1985) formula. A progress signal, not a target to load.")
                    .font(LiquidType.cuerpo).foregroundStyle(LiquidColor.tinta500)
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

    /// Handoff: one block per logged day — family-hue dot + date (+ routine name, when the day was
    /// logged against one), a RECORD badge on the day that set the all-time top weight, a subrow with
    /// the set count and the day's «QUEDABAN» range (omitted entirely when no set captured effort),
    /// and EVERY set of that day as quiet «82,5 × 8» chips.
    private var historyList: some View {
        let sessions = historySessions
        return VStack(alignment: .leading, spacing: .zero) {
            ForEach(Array(sessions.enumerated()), id: \.offset) { idx, day in
                VStack(alignment: .leading, spacing: LiquidSpace.s200) {
                    HStack(spacing: LiquidSpace.s200) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)  // token-exempt(falta-pieza): geometría del punto de familia (8×8)
                            .fill(familyTint).frame(width: 8, height: 8)
                        historyDayText(day.ts, routineName: day.routineName)
                            .font(LiquidType.tituloGemela).foregroundStyle(LiquidColor.tinta900)
                        Spacer(minLength: LiquidSpace.s200)
                        if day.isRecord {
                            Text("RECORD")
                                .font(LiquidType.microEstado).tracking(0.5)
                                .foregroundStyle(LiquidColor.papelTarjeta)
                                .padding(.horizontal, LiquidSpace.s200).padding(.vertical, LiquidSpace.s050)
                                .background(familyTint, in: RoundedRectangle(cornerRadius: LiquidRadius.chip, style: .continuous))
                        }
                    }
                    historyDaySubtitle(day)
                        .font(LiquidType.cuerpo).foregroundStyle(LiquidColor.tinta500)
                    ChipFlow(spacing: LiquidSpace.s200) {
                        ForEach(Array(day.sets.enumerated()), id: \.offset) { _, s in
                            Text(verbatim: "\(StrengthDisplay.weightNumber(s.kg, system: system)) × \(s.reps)")
                                .font(LiquidType.tituloFila).monospacedDigit()
                                .foregroundStyle(LiquidColor.tinta900)
                                .padding(.horizontal, LiquidChip.compactoHorizontal).padding(.vertical, LiquidChip.compactoVertical)
                                .liquidGlass(.pastillaSolida)
                        }
                    }
                }
                .padding(.vertical, LiquidSpace.s300)
                .accessibilityElement(children: .combine)
                if idx < sessions.count - 1 {
                    Rectangle().fill(LiquidColor.tinta10).frame(height: LiquidRadius.hairline)
                }
            }
        }
    }

    /// «Hoy» for today, else a short day-month («8 jul»), plus «· routineName» when the day was logged
    /// against a routine — a `Text` so the date part follows the view's locale.
    private func historyDayText(_ ts: Int, routineName: String?) -> Text {
        let date = Date(timeIntervalSince1970: TimeInterval(ts))
        let base = Calendar.current.isDateInToday(date)
            ? Text("Today") : Text(date, format: .dateTime.day().month(.abbreviated))
        guard let routineName, !routineName.isEmpty else { return base }
        return base + Text(verbatim: " · \(routineName)")
    }

    /// «4 series · QUEDABAN 2-3» — set count plus the day's RIR range, reusing the same «quedaban»
    /// kicker as the live keypad (FER-134). The QUEDABAN fragment is OMITTED entirely, not zeroed,
    /// when no set of the day captured an RPE.
    private func historyDaySubtitle(_ day: (ts: Int, sets: [(kg: Double, reps: Int)], isRecord: Bool,
                                            rpes: [Double], routineName: String?)) -> Text {
        var text = Text("\(day.sets.count) sets")
        if let rir = StrengthHistoryFormat.rirRange(rpes: day.rpes) {
            // `.textCase(.uppercase)` needs a `View`, not the `Text` this chain concatenates (`+` is
            // `Text`-only) — uppercase the localized string itself instead, same visual result as
            // `SessionKeypad`'s «QUEDABAN» kicker.
            let kicker = String(localized: "Reps left kicker").uppercased()
            text = text + Text(verbatim: " · \(kicker) \(rir)")
        }
        return text
    }

    private func rebuildHistoryDerived() {
        var byDaySessions: [String: (ts: Int, sets: [(kg: Double, reps: Int)], rpes: [Double],
                                     routineName: String?)] = [:]
        for h in history.sorted(by: { $0.startTs < $1.startTs }) {
            let key = dayKey(h.startTs)
            var entry = byDaySessions[key] ?? (h.startTs, [], [], h.routineName)
            entry.sets.append((h.weightKg, h.reps))
            if let rpe = h.rpe { entry.rpes.append(rpe) }
            byDaySessions[key] = entry
        }
        let sessionDays = byDaySessions.values.sorted { $0.ts > $1.ts }
        let maxKg = history.map(\.weightKg).max() ?? 0
        var recordMarked = false
        historySessions = sessionDays.map { day in
            let hits = maxKg > 0 && day.sets.contains { $0.kg >= maxKg - 0.0001 }
            let isRecord = hits && !recordMarked
            if isRecord { recordMarked = true }
            return (day.ts, day.sets, isRecord, day.rpes, day.routineName)
        }

        var byDayBest: [String: (ts: Int, weightKg: Double, reps: Int)] = [:]
        for h in history {
            let key = dayKey(h.startTs)
            if let cur = byDayBest[key], cur.weightKg >= h.weightKg { continue }
            byDayBest[key] = (h.startTs, h.weightKg, h.reps)
        }
        historyDays = byDayBest.values.sorted { $0.ts > $1.ts }
        historyDaysAscending = historyDays.sorted { $0.ts < $1.ts }

        seriesCache = [
            .oneRM: OneRepMax.dailySparkline(history.map {
                (day: dayKey($0.startTs), weightKg: $0.weightKg, reps: $0.reps)
            }).map(\.estimatedKg),
            .volume: byDay { $0 + $1.weightKg * Double($1.reps) },
        ]
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s075) {
            Text(metaLine)
                .liquidKicker().foregroundStyle(LiquidColor.tinta700)
            Text(StrengthDisplay.name(exercise))
                // FER-291: displayS (22) — HTML fuente de verdad; no se mintió un token nuevo de 30.
                .font(LiquidType.displayS).tracking(LiquidType.displaySTracking)
                .foregroundStyle(LiquidColor.tinta900)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The overline over the title (handoff V10 · FER-139): «primary muscle(s) · equipment ·
    /// measurement type» — «PECHO · BARRA · PESO × REPS», or «PIERNA / ESPALDA · BARRA · …» for a
    /// compound with two primaries. Falls back to the bare measurement type when the exercise
    /// carries neither muscle nor equipment (a bare custom one).
    private var metaLine: String {
        let muscles = exercise.primaryMuscles.prefix(2).map { StrengthDisplay.muscle($0) }
        let equip = exercise.equipment.flatMap { $0.isEmpty ? nil : StrengthDisplay.equipment($0) }
        var parts: [String] = []
        if !muscles.isEmpty { parts.append(muscles.joined(separator: " / ")) }
        if let equip { parts.append(equip) }
        guard !parts.isEmpty else { return StrengthDisplay.typeName(effectiveType) }
        parts.append(StrengthDisplay.typeName(effectiveType))
        return parts.joined(separator: " · ")
    }

    // MARK: - Measurement type (FER-541) — let the user re-type any exercise, incl. a catalog one

    private var measurementSection: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s200) {
            Rectangle().fill(LiquidColor.tinta10).frame(height: LiquidRadius.hairline)
                .padding(.bottom, LiquidSpace.seccionCanto)
            Text("Measured by").liquidKicker().foregroundStyle(LiquidColor.tinta700)
            HStack(spacing: LiquidSpace.s300) {
                Button { showTypeMenu = true } label: {
                    HStack(spacing: LiquidSpace.s150) {
                        Text(StrengthDisplay.typeLabel(effectiveType))
                            .font(LiquidType.tituloGemela).foregroundStyle(LiquidColor.tinta900)
                        CenitIcon.down.image.font(LiquidType.iconSF(size: 12))
                            .foregroundStyle(LiquidColor.tinta500)
                    }
                }
                .buttonStyle(EntrenarPressStyle())
                .liquidMenu(isPresented: $showTypeMenu, items: ExerciseType.allCases.map { t in
                    LiquidMenuItem(StrengthDisplay.typeName(t),
                                  systemImage: t == effectiveType ? "checkmark" : nil) { setType(t) }
                })
                Spacer(minLength: LiquidSpace.s200)
                if hasTypeOverride {
                    OutlineCapsule("Revert to default", size: .sm, action: revertType)
                }
            }
            .frame(minHeight: EntrenarMetrics.secondaryButton)
        }
    }

    /// Override this exercise's measurement type (works for catalog and custom). The header + control
    /// update immediately; downstream readers pick it up via the resolver on their next load.
    private func setType(_ t: ExerciseType) {
        let previous = shownType
        let previousOverride = hasTypeOverride
        shownType = t
        hasTypeOverride = true
        Task {
            do {
                try await repo.setExerciseTypeOverride(exercise.id, type: t)
            } catch {
                shownType = previous
                hasTypeOverride = previousOverride
                saveError = true
            }
        }
    }

    /// Drop the override → re-resolve the catalog/custom default and show it.
    private func revertType() {
        let previous = shownType
        hasTypeOverride = false
        Task {
            do {
                try await repo.clearExerciseTypeOverride(exercise.id)
                let resolved = await repo.resolvedExercise(exercise.id)
                await MainActor.run { shownType = resolved?.type }
            } catch {
                hasTypeOverride = true
                shownType = previous
                saveError = true
            }
        }
    }

    // MARK: - Muscles (chips: primary at full ink, assistants outlined · FER-739)
    // The handoff has no anatomical figure and no bars — the muscles read as chips. A primary mover is a
    // full-ink chip; an assistant is an outlined one. Derived from the exercise's own muscle data (no
    // bundled art, no network). Hidden when an exercise carries no muscles (a bare custom one).

    @ViewBuilder private var musclesSection: some View {
        if !exercise.primaryMuscles.isEmpty || !exercise.secondaryMuscles.isEmpty {
            VStack(alignment: .leading, spacing: LiquidSpace.s200) {
                Text("Muscles").liquidKicker().foregroundStyle(LiquidColor.tinta700)
                ChipFlow(spacing: LiquidSpace.s200) {
                    ForEach(exercise.primaryMuscles, id: \.self) { m in muscleChip(m, primary: true) }
                    ForEach(exercise.secondaryMuscles, id: \.self) { m in muscleChip(m, primary: false) }
                }
                if !exercise.secondaryMuscles.isEmpty {
                    Text("Primary in color · assisting in gray")
                        .font(LiquidType.cuerpo).foregroundStyle(LiquidColor.tinta500)
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
                    .font(LiquidType.tituloFila).foregroundStyle(familyTint)
            } else {
                Text(StrengthDisplay.muscle(muscle))
                    .font(LiquidType.tituloFila).foregroundStyle(LiquidColor.tinta700)
            }
        }
        .padding(.horizontal, LiquidChip.compactoHorizontal).padding(.vertical, LiquidChip.compactoVertical)
        // El principal es el dato: lleva el tono de la familia (identidad). El asistente queda quieto
        // sobre la superficie sólida de El Eje (`.pastillaSolida`), no el gris papel legacy.
        .modifier(MuscleChipSurface(primary: primary, familyTint: familyTint))
        .accessibilityElement()
        .accessibilityLabel("\(StrengthDisplay.muscle(muscle)), \(String(localized: primary ? "primary" : "assisting"))")
    }

    /// Superficie del chip de músculo: el principal lleva el tono de familia (identidad, 12 % tint);
    /// el asistente queda quieto sobre la pastilla sólida de El Eje — reemplaza el gris papel legacy.
    private struct MuscleChipSurface: ViewModifier {
        let primary: Bool
        let familyTint: Color
        func body(content: Content) -> some View {
            if primary {
                content.background(familyTint.opacity(CenitOpacity.tintFill),
                                   in: RoundedRectangle(cornerRadius: LiquidRadius.chip, style: .continuous))
            } else {
                content.liquidGlass(.pastillaSolida)
            }
        }
    }

    // MARK: - Variants (FER-739) — other catalog exercises for the same primary muscle

    /// A row of chips for sibling exercises that load the same primary muscle; tapping one opens its
    /// sheet. Derived from the catalog (no new «variants» field), so it's empty for a bare custom
    /// exercise or one whose primary muscle nothing else shares.
    @ViewBuilder private var variantsSection: some View {
        if !variants.isEmpty {
            VStack(alignment: .leading, spacing: LiquidSpace.s200) {
                LiquidSectionHeader("Variants")
                ChipFlow(spacing: LiquidSpace.s200) {
                    ForEach(variants) { ex in variantChip(ex) }
                }
            }
        }
    }

    private func variantChip(_ ex: Exercise) -> some View {
        OutlineCapsule(size: .sm, action: { variant = ex }) {
            Text(StrengthDisplay.name(ex))
                .font(LiquidType.tituloFila)
                .foregroundStyle(LiquidColor.tinta900)
        }
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
        return VStack(alignment: .leading, spacing: .zero) {
            LiquidSectionHeader("How to")
            VStack(alignment: .leading, spacing: .zero) {
                ForEach(Array(cues.enumerated()), id: \.offset) { index, cue in
                    // Handoff: the step number leads in the family hue, the cue in ink,
                    // capillary-divided rows.
                    HStack(alignment: .firstTextBaseline, spacing: LiquidSpace.s300) {
                        Text(verbatim: "\(index + 1)")
                            .font(LiquidType.titulo).monospacedDigit()
                            .foregroundStyle(familyTint)
                            .frame(width: 15, alignment: .leading)
                        Text(cue)
                            .font(Font.system(size: LiquidType.lecturaHojaBase))
                            .foregroundStyle(LiquidColor.tinta900)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, LiquidSpace.filaRespiro)
                    if index < cues.count - 1 {
                        Rectangle().fill(LiquidColor.tinta10).frame(height: LiquidRadius.hairline)
                    }
                }
            }
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
            // Handoff: a flat row over a top capillary — no card. The icon sits in a small sunken square.
            VStack(spacing: .zero) {
                Rectangle().fill(LiquidColor.tinta10).frame(height: LiquidRadius.hairline)
                HStack(spacing: LiquidSpace.s300) {
                    Image(systemName: "play.rectangle")
                        .font(LiquidType.iconSF(size: 15))
                        .foregroundStyle(LiquidColor.tinta700)
                        .frame(width: 34, height: 34)
                        .liquidGlass(.pastillaSolida)
                    VStack(alignment: .leading, spacing: LiquidSpace.s025) {
                        Text("Watch on YouTube")
                            .font(LiquidType.tituloGemela).foregroundStyle(LiquidColor.tinta900)
                        Text("Opens outside the app · uses the internet")
                            .font(LiquidType.cuerpo).foregroundStyle(LiquidColor.tinta500)
                    }
                    Spacer(minLength: LiquidSpace.s200)
                    CenitIcon.disclosure.image.font(LiquidType.iconSF(size: 12))
                        .foregroundStyle(LiquidColor.tinta500)
                }
                .padding(.top, LiquidSpace.s300)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(EntrenarPressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Watch \(exercise.name) on YouTube")
        .accessibilityHint("Opens YouTube outside the app")
    }

    // MARK: - Progress (a metric-switchable trend: max weight / estimated 1RM / volume · FER-505)

    private var progressSection: some View {
        let oneRM = series(.oneRM)
        let deltaPercent = trendDeltaPercent
        return VStack(alignment: .leading, spacing: .zero) {
            // FER-149 spec A: the kicker is the FIXED text below, no conditional variant — it never
            // claims «TODAY»/«HOY» over stale data (the old bug the spec's collateral fix targeted)
            // because it says «90 DAYS», not a same-day claim, regardless of when the last log was.
            Text("TREND · ESTIMATED 1RM · 90 DAYS")
                .liquidKicker().foregroundStyle(LiquidColor.tinta700)
            HStack(alignment: .firstTextBaseline, spacing: LiquidSpace.s300) {
                if let latest = oneRM.last {
                    // FER-291: numeral 22 índigo via LiquidType.valorL + LiquidColor.indigo.
                    // Chart accent / frame / muscle-dot stay on `familyTint`.
                    HStack(alignment: .firstTextBaseline, spacing: LiquidSpace.s075) {
                        Text(verbatim: StrengthDisplay.weightNumber(latest, system: system))
                            .font(LiquidType.valorL)
                            .foregroundStyle(LiquidColor.indigo)
                        Text(verbatim: StrengthDisplay.weightUnit(system))
                            .font(LiquidType.titulo).foregroundStyle(LiquidColor.tinta500)
                    }
                }
                // Fortnight-vs-fortnight delta over the fixed 90-day window (`trendDeltaPercent`,
                // FER-149 · CSO+CDO-signed formula). Up → positivo; down → atencionTexto (AA on small text).
                if let deltaPercent {
                    LiquidStatePill(
                        valencia: "≈ \(deltaPercent > 0 ? "+" : "")\(deltaPercent) %",
                        tono: deltaPercent > 0 ? LiquidColor.positivo : LiquidColor.atencionTexto
                    )
                    .accessibilityLabel(deltaAccessibilityLabel(deltaPercent))
                }
            }
            .padding(.top, LiquidSpace.s075)

            // The axis chart, in a raised card (handoff: gridlines + y labels + MAY/JUN/HOY).
            if oneRM.count >= 2, !historyDays.isEmpty {
                TrendAxisChart(values: oneRM,
                               dates: historyDaysAscending
                                   .map { Date(timeIntervalSince1970: TimeInterval($0.ts)) },
                               xFirst: monthLabel(historyDays.last?.ts),
                               xMid: monthLabel(historyDays[historyDays.count / 2].ts),
                               accent: familyTint,
                               valueFormat: { StrengthDisplay.weight($0, system: system) })
                    .padding(.top, LiquidSpace.s400)
                    .accessibilityLabel(Text("Est. 1RM") + Text(verbatim: " trend"))
            }
        }
    }

    /// «≈ +N %» — fortnight-vs-fortnight change in estimated 1RM over the FIXED 90-day window
    /// anchored at today, calendar LOCAL (`OneRepMax.windowDeltaPercent`, FER-149; formula + guards
    /// documented and tested there). `nil` — no chip at all, never «0 %» — when the data doesn't
    /// clear the window's own minimums or the noise floor. The anchor is passed as
    /// `Repository.localDayKey(Date())` — the SAME local-zone day-key convention as every set's own
    /// `day` below (`dayKey`, which wraps the same call) — never a bare `Date` the callee would have
    /// to reconvert itself (that mismatch was the FER-149 QA UTC-vs-local bug).
    private var trendDeltaPercent: Int? {
        OneRepMax.windowDeltaPercent(
            history.map { (day: dayKey($0.startTs), weightKg: $0.weightKg, reps: $0.reps) },
            todayKey: Repository.localDayKey(Date()))
    }

    /// VoiceOver reading of the delta chip («aproximadamente 6 por ciento más en 90 días» /
    /// «… menos …») — the visual chip is a bare glyph-and-number string, not a sentence.
    private func deltaAccessibilityLabel(_ percent: Int) -> Text {
        let n = abs(percent)
        return percent > 0
            ? Text("Approximately \(n) percent more over 90 days")
            : Text("Approximately \(n) percent less over 90 days")
    }

    /// A short uppercase month for the chart's x axis («MAY»), localized.
    private func monthLabel(_ ts: Int?) -> String {
        guard let ts else { return "" }
        return Date(timeIntervalSince1970: TimeInterval(ts))
            .formatted(.dateTime.month(.abbreviated)).uppercased()
    }

    /// «RECORDS» — 3 plain text rows (FER-149; replaces the retired best-set/volume mini-cards and
    /// the cycle notice wholesale). Each row is independently optional and hidden on its own —
    /// the block itself only renders once at least one has something to say.
    @ViewBuilder private var recordsSection: some View {
        let bestSet = bestSetLine
        let bestVolume = bestVolumeLine
        let cycle = cycleLine
        if bestSet != nil || bestVolume != nil || cycle != nil {
            VStack(alignment: .leading, spacing: .zero) {
                LiquidSectionHeader("Records")
                if let bestSet {
                    recordRow(Text("Best weight"), bestSet)
                    if bestVolume != nil || cycle != nil {
                        Rectangle().fill(LiquidColor.tinta10).frame(height: LiquidRadius.hairline)
                    }
                }
                if let bestVolume {
                    recordRow(Text("Best volume in one session"), bestVolume)
                    if cycle != nil {
                        Rectangle().fill(LiquidColor.tinta10).frame(height: LiquidRadius.hairline)
                    }
                }
                if let cycle {
                    recordRow(Text("Progression cycle"), cycle)
                }
            }
        }
    }

    /// One RECORDS row: a quiet label, the raw value on the trailing edge. `value` carries its OWN
    /// foreground color per case (set by its source below) — this helper only sets the shared font,
    /// so it never overrides the «▲» accent `cycleLine` paints on `.readyToAdvance`.
    private func recordRow(_ label: Text, _ value: Text) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: LiquidSpace.s300) {
            label.font(Font.system(size: LiquidType.lecturaHojaBase)).foregroundStyle(LiquidColor.tinta700)
            Spacer(minLength: LiquidSpace.s200)
            value.font(LiquidType.datoMenor).monospacedDigit()
        }
        .padding(.vertical, LiquidSpace.s300)
        .accessibilityElement(children: .combine)
    }

    /// «Mejor peso» — the all-time heaviest set, raw, no hedge («82,5 kg × 8»).
    private var bestSetLine: Text? {
        guard let best = history.max(by: { $0.weightKg < $1.weightKg }) else { return nil }
        return Text(verbatim: "\(StrengthDisplay.weight(best.weightKg, system: system)) × \(best.reps)")
            .foregroundColor(LiquidColor.tinta900)
    }

    /// «Mejor volumen en una sesión» — grouped by `WorkSetHistoryRow.sessionId`, NEVER by calendar
    /// day (`SessionVolume.best`, FER-149): two sessions logged the same day stay two records, not
    /// one merged one. All-time, no window; hidden when nothing logged has positive volume.
    private var bestVolumeLine: Text? {
        guard let best = SessionVolume.best(history.map {
            (sessionId: $0.sessionId, startTs: $0.startTs, weightKg: $0.weightKg, reps: $0.reps)
        }) else { return nil }
        return Text(verbatim: StrengthHistoryFormat.volume(best.volumeKg, system: system))
            .foregroundColor(LiquidColor.tinta900)
    }

    /// «Ciclo de progresión» — where this exercise's progression stands, in one sentence with real
    /// numbers. `nil` unless some routine slot opted into progression for this exercise.
    private var cycleLine: Text? {
        guard let state = cycleState else { return nil }
        let kg = { (v: Double) in StrengthDisplay.weight(v, system: system) }
        switch state {
        case .inCycle(let done, let of):
            let at = historyDays.last.map { kg($0.weightKg) } ?? ""
            return Text("You're \(done) of \(of) sessions in with \(at).").foregroundColor(LiquidColor.tinta900)
        case .readyToAdvance(let newKg):
            // FER-149: the OLD copy named the destination weight («arrives with 65 kg»); the CSO's
            // records row instead names the INCREMENT — «raise 2.5 kg today» — with a green «▲»
            // that appears ONLY in this state, never elsewhere in the row.
            // FER-149 QA: `actual` MUST be the same "current weight" the classifier itself used to
            // reach `.readyToAdvance` — `cycleFromKg` (`ProgressionPlanner.evaluate`'s `Raise.fromKg`)
            // already excludes opted-out sessions, exactly like the classifier does. Re-deriving it
            // from `historyDays` instead (a) risked reading the OLDEST logged day rather than the
            // newest (`historyDays` sorts descending — `.last` is the oldest) and (b) could include an
            // opted-out day's weight the classifier had already ignored, either of which could show
            // an increment nowhere close to `newKg − actual`. `cycleFromKg` is nil only if the
            // classifier's own `raise` came back nil (shouldn't happen in `.readyToAdvance`); the
            // fallback keeps the row from crashing rather than claiming perfect data.
            let current = cycleFromKg ?? historyDaysAscending.last?.weightKg ?? newKg
            let increment = max(0, newKg - current)
            return Text("Raise \(kg(increment)) today").foregroundColor(LiquidColor.tinta900)
                + Text(verbatim: " ▲").foregroundColor(LiquidColor.positivo)
        case .deferred(let newKg):
            // FER-82: the cause is the day's verdict, not a recovery score. Naming the score here
            // was a third voice that could contradict both Hoy and Entrenar on the same morning.
            // FER-86: decía «espera un día en rango», pero el oráculo también la libera con
            // `.silent` — un día SIN lectura, que el hilo rotula «Sin lectura de hoy», jamás «En
            // rango». El texto prometía una condición más estrecha que la real, y se cumplía sola
            // el día que la pantalla llamaba de otro modo.
            return Text("The raise to \(kg(newKg)) waits for a day that doesn't hold it back. You can take it anyway.")
                .foregroundColor(LiquidColor.tinta900)
        case .stalled(let sessions):
            return Text("\(sessions) sessions without hitting the goal at this weight.")
                .foregroundColor(LiquidColor.tinta900)
        case .deloading(let fromKg, let toKg):
            return Text("Proposed deload: \(kg(fromKg)) → \(kg(toKg)), then rebuild.")
                .foregroundColor(LiquidColor.tinta900)
        }
    }

    /// A metric as a per-day series, oldest→newest. `.oneRM` reuses the cited
    /// `OneRepMax.dailySparkline`; the only current caller (the trend chart above).
    private func series(_ metric: ProgressMetric) -> [Double] {
        seriesCache[metric] ?? []
    }

    private func byDay(_ combine: (Double, WorkSetHistoryRow) -> Double) -> [Double] {
        var acc: [String: Double] = [:]
        for s in history {
            let key = dayKey(s.startTs)
            acc[key] = combine(acc[key] ?? 0, s)
        }
        return acc.sorted { $0.key < $1.key }.map(\.value)
    }

    private func dayKey(_ ts: Int) -> String {
        Repository.localDayKey(Date(timeIntervalSince1970: TimeInterval(ts)))
    }

    // MARK: - Honest empty

    private var emptyHistory: some View {
        VStack(alignment: .leading, spacing: .zero) {
            Rectangle().fill(LiquidColor.tinta10).frame(height: LiquidRadius.hairline)
            VStack(alignment: .leading, spacing: LiquidSpace.s200) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(LiquidType.infoGlifoTitular).foregroundStyle(LiquidColor.tinta500)
                Text("Not logged yet").font(LiquidType.titulo).foregroundStyle(LiquidColor.tinta900)
                Text("Your best mark, your last session and your estimated 1RM appear here once you complete a work set.")
                    .font(LiquidType.cuerpoBanner).foregroundStyle(LiquidColor.tinta700)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, LiquidSpace.s400)
        }
    }

}

// MARK: - Trend chart with axes (handoff «Detalle · Progreso»)

/// The 1RM trend in the handoff's chart card: four hairline gridlines with Grotesk y labels, the
/// series as a hue line over a soft area fill, an end dot with halo, and MAY/JUN/TODAY x captions.
/// Dragging scrubs the series — a hairline + dot pin the nearest sample and the header swaps to
/// «value · date», same reading model as the Trends charts.
private struct TrendAxisChart: View {
    let values: [Double]
    let dates: [Date]
    let xFirst: String
    let xMid: String
    let accent: Color
    let valueFormat: (Double) -> String

    @State private var scrubIndex: Int? = nil
    private static let plotHeight: CGFloat = 150

    private var lo: Double { values.min() ?? 0.0 }
    private var hi: Double { Swift.max(values.max() ?? 1.0, lo + 1.0) }
    private var pad: Double { (hi - lo) * 0.18 + 0.001 }
    private var top: Double { hi + pad }
    private var bottom: Double { Swift.max(0.0, lo - pad) }

    /// Scrub readout: value + date of the pinned sample; empty until you drag.
    @ViewBuilder private var scrubReadout: some View {
        if let i = scrubIndex, values.indices.contains(i) {
            HStack(spacing: LiquidSpace.s150) {
                Text(verbatim: valueFormat(values[i]))
                    .font(LiquidType.valorS).monospacedDigit()
                    .foregroundStyle(accent)
                if dates.indices.contains(i) {
                    Text(dates[i], format: .dateTime.day().month(.abbreviated))
                        .font(LiquidType.filaConteo).foregroundStyle(LiquidColor.tinta500)
                }
            }
            .padding(.bottom, LiquidSpace.s050)
        }
    }

    /// Gridlines + y labels + the series (area, line, end/scrub dots).
    private var chartPlot: some View {
        let topY: Double = top
        let botY: Double = bottom
        return ZStack(alignment: .topLeading) {
            // Gridlines + y labels, top→bottom; the bottom line slightly stronger (handoff).
            VStack(spacing: .zero) {
                ForEach(0..<4, id: \.self) { (i: Int) in
                    let span: Double = topY - botY
                    let yVal: Double = topY - span * Double(i) / 3.0
                    let yLabel: Int = Int(yVal.rounded())
                    HStack(spacing: LiquidSpace.s150) {
                        Text(verbatim: "\(yLabel)")
                            .font(LiquidType.caption).monospacedDigit()
                            .foregroundStyle(LiquidColor.tinta500)
                            .frame(width: 28, alignment: .trailing)
                        Rectangle().fill(i == 3 ? LiquidColor.tinta10 : LiquidColor.tinta7).frame(height: 1)
                    }
                    if i < 3 { Spacer(minLength: 0) }
                }
            }
            // The series: area + line + end dot, inset past the y-label column.
            GeometryReader { (geo: GeometryProxy) in
                let w: CGFloat = geo.size.width
                let h: CGFloat = geo.size.height
                let denom: Double = topY - botY
                let maxIdx: Int = max(values.count - 1, 1)
                let points: [CGPoint] = values.enumerated().map { (idx: Int, v: Double) -> CGPoint in
                    let nx: CGFloat = w * CGFloat(idx) / CGFloat(maxIdx)
                    let ny: CGFloat = h * CGFloat(1.0 - (v - botY) / denom)
                    return CGPoint(x: nx, y: ny)
                }
                ZStack {
                    Path { (p: inout Path) in
                        guard let first = points.first, let last = points.last else { return }
                        p.move(to: CGPoint(x: first.x, y: h))
                        points.forEach { (pt: CGPoint) in p.addLine(to: pt) }
                        p.addLine(to: CGPoint(x: last.x, y: h))
                        p.closeSubpath()
                    }
                    .fill(accent.opacity(0.10))  // token-exempt(dato): área 10% del handoff — LiquidChart.gridAlfa no es public fuera de CenitDesign
                    Path { (p: inout Path) in
                        guard let first = points.first else { return }
                        p.move(to: first)
                        points.dropFirst().forEach { (pt: CGPoint) in p.addLine(to: pt) }
                    }
                    .stroke(accent, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))  // token-exempt(dato): linea 2.2 del handoff — LiquidChart.lineaAncho no es public fuera de CenitDesign
                    if let last = points.last, scrubIndex == nil {
                        Circle().fill(accent.opacity(0.18)).frame(width: 16, height: 16).position(last)  // token-exempt(dato): halo del handoff
                        Circle().fill(accent).frame(width: 9, height: 9).position(last)
                    }
                    // The scrub pin: vertical hairline + dot at the nearest sample.
                    if let i = scrubIndex, points.indices.contains(i) {
                        Path { (p: inout Path) in
                            p.move(to: CGPoint(x: points[i].x, y: 0))
                            p.addLine(to: CGPoint(x: points[i].x, y: h))
                        }
                        .stroke(LiquidColor.tinta10, lineWidth: 1)  // token-exempt(dato): capilar de scrub
                        Circle().fill(accent.opacity(0.18)).frame(width: 16, height: 16).position(points[i])  // token-exempt(dato): halo del handoff
                        Circle().fill(accent).frame(width: 9, height: 9).position(points[i])
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { (g: DragGesture.Value) in
                            let wSafe: CGFloat = max(w, 1)
                            let frac: CGFloat = max(0, min(1, g.location.x / wSafe))
                            let i: Int = Int((frac * CGFloat(maxIdx)).rounded())
                            if i != scrubIndex { ChartHaptics.datumChanged() }
                            scrubIndex = i
                        }
                        .onEnded { (_: DragGesture.Value) in scrubIndex = nil }
                )
            }
            .padding(.leading, 34)  // token-exempt(dato): geometría de gráfica — ancho de la columna de labels Y (28) + separación al eje, alinea la serie con el eje
            .padding(.vertical, LiquidSpace.s125)
        }
        .frame(height: Self.plotHeight)
    }

    /// X captions: first month · middle month · TODAY in the hue.
    private var xCaptions: some View {
        HStack(spacing: .zero) {
            Text(verbatim: xFirst)
                .font(LiquidType.dato).tracking(LiquidType.datoTracking)
                .foregroundStyle(LiquidColor.tinta500)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(verbatim: xMid)
                .font(LiquidType.dato).tracking(LiquidType.datoTracking)
                .foregroundStyle(LiquidColor.tinta500)
                .frame(maxWidth: .infinity, alignment: .center)
            Text("Today").textCase(.uppercase)
                .font(LiquidType.dato).tracking(LiquidType.datoTracking)
                .foregroundStyle(accent)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.leading, 34)  // token-exempt(dato): geometría de gráfica — mismo offset que la serie para alinear las etiquetas X con el eje
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s150) {
            scrubReadout
            chartPlot
            xCaptions
        }
        .padding(.top, LiquidSpace.s400).padding(.horizontal, LiquidSpace.handoff14).padding(.bottom, LiquidSpace.s300)
        .liquidGlass(.superficieSolida)
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
