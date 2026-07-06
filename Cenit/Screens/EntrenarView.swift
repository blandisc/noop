#if os(iOS)
import SwiftUI
import StrandDesign
import StrandTraining
import StrandAnalytics

// MARK: - Entrenar (the Train tab root) — «Pulir · arranque directo» (handoff, sobre «La Semana» FER-530)
//
// The Train landing as a PLANNER in the light «Instrumento diurno» language (warm paper, color only on
// the datum, hierarchy by space). Today's session is the spine now: the hero «Hoy» sits up top behind a
// SINGLE solid «Empezar {rutina}» that starts the guided session in ONE tap (F1) — no chooser, no
// intermediate screen. «¿otro tipo?» under it opens the secondary chooser (otra rutina / intervals /
// breathe / live). A rest day swaps the door for a quiet outline button that opens the «Hoy descansas»
// sheet (F3). Below the hero: a contextual suggestion, the week strip + streak in one card (F10), the
// plan as a collapsible disclosure with a single «Editar» action (F5), and Diet as a footer link.
//
// Color appears ONLY on the recovery datum (the chip ring/numeral, the today-dot, the Today recovery
// line); everything else is ink on paper. Navigation is owned by the tab's `NavigationStack` in
// RootTabView; the landing pushes via the injected closures and hosts the guided session + sheets here.

struct EntrenarView: View {
    var openRoutine: (String) -> Void
    var openBreathe: () -> Void
    var openIntervals: () -> Void
    var openDiet: () -> Void
    /// Push «Mis entrenamientos» (the completed-session history, FER-504).
    var openHistory: () -> Void
    /// Push the weekly plan editor (FER-533) — opened from «Tu plan · Editar» and the empty state.
    var openWeeklyPlan: () -> Void
    /// Push «Mis rutinas» (the routine library) — the single home for create/import/templates/library now
    /// (F4): reached from the secondary chooser's «Otra rutina» and the rest sheet's «Elegir una rutina».
    var openRoutines: () -> Void
    /// Push «Hoy descansas» (v3 · 2B) — the rest-day screen (was a sheet, now a push, FER-718).
    var openRestDay: () -> Void
    /// Push «Otra forma de entrenar» (v3 · 3e) — the alternative-training chooser (was a sheet, now a push).
    var openOtherWays: () -> Void
    /// Push a completed strength session's detail (from a «done» day in the week strip).
    var openWorkoutSession: (WorkoutSessionRoute) -> Void

    var body: some View {
        EntrenarLanding(openRoutine: openRoutine,
                        openBreathe: openBreathe, openIntervals: openIntervals, openDiet: openDiet,
                        openHistory: openHistory, openWeeklyPlan: openWeeklyPlan,
                        openRoutines: openRoutines, openRestDay: openRestDay,
                        openOtherWays: openOtherWays, openWorkoutSession: openWorkoutSession)
            .instrumentoTheme(.base)
    }
}

private struct EntrenarLanding: View {
    @EnvironmentObject var repo: Repository
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var tabRouter: TabRouter
    @Environment(\.instrumentoTheme) private var theme

    var openRoutine: (String) -> Void
    var openBreathe: () -> Void
    var openIntervals: () -> Void
    var openDiet: () -> Void
    var openHistory: () -> Void
    var openWeeklyPlan: () -> Void
    var openRoutines: () -> Void
    var openRestDay: () -> Void
    var openOtherWays: () -> Void
    var openWorkoutSession: (WorkoutSessionRoute) -> Void

    @State private var loaded = false
    @State private var routines: [Routine] = []
    @State private var exerciseCounts: [String: Int] = [:]
    /// Top primary muscles per routine (Spanish display labels), built from the same per-routine exercise
    /// fetch that feeds `exerciseCounts` — drives the hero muscle line and the «También en tu plan» subtitles.
    @State private var routineMuscles: [String: [String]] = [:]
    /// The weekly split, `weekday → routineId` (Calendar convention, 1 = Sun … 7 = Sat). FER-531.
    @State private var split: [Int: String] = [:]
    /// Completed strength sessions (newest first), for the week strip's day states and the daily streak.
    @State private var sessions: [StrengthSession] = []
    /// Today's routine resolved into guided-session slots, prefetched on load so «Empezar» starts in one
    /// tap (F1). Empty when today is a rest day or the routine has no exercises.
    @State private var todaySlots: [StrengthSessionModel.PlanSlot] = []
    /// Drives the templates sheet opened straight on the mobility routine from the ③ «softer» suggestion
    /// (a TRAINING-day nudge; the rest sheet starts mobility directly instead). FER-554.
    @State private var showMobilityTemplate = false
    /// «Empezar» from the mobility template stashes its (name, slots) here; the session starts on the
    /// sheet's dismiss so it never stacks on the templates sheet (FER-560).
    @State private var pendingMobility: (name: String, slots: [StrengthSessionModel.PlanSlot])? = nil
    /// Drives the Recovery Detail sheet opened from the recovery chip (FER-557).
    @State private var recoveryDetail: RecoveryDetailItem? = nil
    /// The Daily Brief's «Empezar» arrived (via `TabRouter`) before this view finished loading its
    /// prefetched slots — start today's session as soon as `load()` completes (FER-613).
    @State private var startWhenLoaded = false

    /// Monday-first display order in the Calendar weekday convention.
    private let orderedWeekdays = [2, 3, 4, 5, 6, 7, 1]
    /// Tighter section rhythm than the global `NoopMetrics.sectionGap` (28): the planner stacks several
    /// sections, so the default rhythm left too much dead vertical space (FER-578). Local to Entrenar.
    private let sectionRhythm: CGFloat = 18
    private var todayWeekday: Int { Calendar.current.component(.weekday, from: Date()) }
    private var recovery: Double? { repo.today?.recovery }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: sectionRhythm) {
                header
                if loaded {
                    if split.isEmpty {
                        emptyStateB
                    } else {
                        hoyCard          // ① hero «Hoy · {día}» — routine tint + recovery bullet (mock 1a)
                        suggestionRow    // ② contextual FER-532 nudge (shown only when the engine fires)
                        tambienEnTuPlan  // ③ the rest of the plan + utility rows (otra forma, Dieta)
                        weekInstrument   // ④ compact week progress + streak above the dock
                    }
                }
            }
            .padding(.top, NoopMetrics.screenTop)   // shared titled-tab top inset
            .padding(.horizontal, NoopMetrics.screenPadding)
            .padding(.bottom, NoopMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.paper.ignoresSafeArea())
        // The ③ «softer» suggestion (FER-554) opens the templates sheet straight on the mobility routine.
        // «Empezar» starts a one-off guided session (on the sheet's dismiss, so it never stacks — FER-171),
        // with «Add to my routines» as the secondary action. Theme doesn't cross the sheet boundary.
        .sheet(isPresented: $showMobilityTemplate, onDismiss: startPendingMobility) {
            StarterTemplatesSheet(initialSelection: StarterTemplates.byID("mobility"),
                                  onStart: { name, slots in pendingMobility = (name, slots) }) { await load() }
                .instrumentoTheme(theme).environmentObject(repo).preferredColorScheme(.light)
        }
        // Recovery detail from the chip — same sheet Today/Cuerpo open; theme passed explicitly (it
        // doesn't cross the `.sheet` boundary, FER-162), no nested NavigationStack (FER-171). (FER-557)
        .sheet(item: $recoveryDetail) { item in
            RecoveryDetailScreen(theme: theme, model: item.model)
        }
        // The guided strength session (FER-347) is now presented at the shell (`RootTabView`) as a
        // full-screen cover with a floating pill on all five tabs (FER-716), so it survives tab switches
        // and no longer needs a «Resume» row here. The session lives in AppModel.
        .task { await load() }
        // The Daily Brief's «Hoy en tu plan» → «Empezar» lands here via TabRouter: start today's session
        // reusing the slots this view prefetched on load (FER-613). Consumed once; if we're not loaded yet,
        // defer until `load()` finishes.
        .onAppear { if tabRouter.startTodaySession { consumeBriefStart() } }
        .onChange(of: tabRouter.startTodaySession) { _, requested in
            if requested { consumeBriefStart() }
        }
    }

    /// Consume the one-shot start request from the Daily Brief. Reuses `startToday()` (the same path as the
    /// hero «Empezar», so the prefetched slots and the «empty routine → edit» / «rest → sheet» fallbacks all
    /// hold). Defers until loaded so the prefetch is ready.
    private func consumeBriefStart() {
        tabRouter.startTodaySession = false
        if loaded { startToday() } else { startWhenLoaded = true }
    }

    // MARK: - Header + recovery chip

    private var header: some View {
        // Shared wordmark row — same lockup, size and baseline as «Tendencias»/«Patrones» so the three
        // tab titles align as you swipe. Glyph = the dock's tab icon; the recovery chip rides the trailing
        // slot, which is anchored to the title's height so it never pushes the title down.
        // `String(localized:)` so the wordmark follows the app language — the header takes a plain String,
        // which `Text` would render verbatim, leaving «Train» in English even in Spanish. (es → «Entrenar».)
        InstrumentoTabHeader(String(localized: "Train")) {
            Image(systemName: "figure.strengthtraining.functional")
                .font(.system(size: 20)).foregroundStyle(theme.ink)
        } trailing: {
            if let rec = recovery { recoveryChip(rec) }   // hidden while calibrating (no score)
        }
    }

    /// The recovery chip: a small arc (`dataRecovery`) + the numeral. Tapping opens the Recovery Detail
    /// sheet (same as Today/Cuerpo) — it does NOT switch tabs. The one glanceable point of color here.
    private func recoveryChip(_ rec: Double) -> some View {
        Button { recoveryDetail = RecoveryDetailItem(model: RecoveryDetailModel.build(repo: repo)) } label: {
            HStack(spacing: 7) {
                RecoveryChipRing(score: rec).frame(width: 22, height: 22)
                Text("\(Int(rec.rounded()))")
                    .font(StrandFont.number(17, weight: .semibold)).foregroundStyle(theme.ink)
            }
            .padding(.leading, 8).padding(.trailing, 11).padding(.vertical, 5)
            .background(theme.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(theme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Recovery \(Int(rec.rounded())). See details."))
    }

    // MARK: - ① Today + «Empezar» (the single door — now a one-tap start, F1)

    private var hoyCard: some View {
        card {
            Text(hoyOverline).instrumentoOverline().foregroundStyle(theme.inkTertiary)
            if let r = todayRoutine {
                // Name + a routine-tinted square (the handoff's per-routine color), with the exercise/time
                // meta trailing on the same line. The tint is the ONE point of color the mock allows here.
                HStack(alignment: .center, spacing: 9) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(routineTint(r.name)).frame(width: 8, height: 8)
                    Text(r.name).font(StrandFont.title3).foregroundStyle(theme.ink)
                        // Long routine names («Día A — Empuje y cuádriceps») sit at the quieter
                        // title3 and shrink further to fit two lines instead of wrapping tall;
                        // short names read at full title3 size.
                        .lineLimit(2).minimumScaleFactor(0.75)
                    Spacer(minLength: 8)
                    metaText(r.id).font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
                }
                .padding(.top, 3)
                if let muscles = routineMuscleLine(r.id) {
                    Text(muscles).font(StrandFont.subhead).foregroundStyle(theme.inkSecondary).padding(.top, 2)
                }
            } else {
                Text("Rest").font(StrandFont.title2).foregroundStyle(theme.inkSecondary).padding(.top, 3)
                Text("Your plan doesn't schedule today. A good day to recover.")
                    .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary).padding(.top, 2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let rec = recovery {
                Divider().overlay(theme.hairline).padding(.vertical, 12)
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Circle().fill(theme.dataRecovery).frame(width: 8, height: 8)
                    Text(recoveryLine(rec)).font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            empezarButton.padding(.top, 12)
        }
    }

    /// The handoff's per-routine tint (mock 1a). The four flow colors coincide with existing Instrumento
    /// data tokens, so we reuse them rather than hand-editing the generated theme: push → `dataStrain`
    /// (ember), pull → `dataHrv` (teal), leg → `dataSleep` (indigo). We map by the routine name's split
    /// keyword (es/en); anything else gets a stable pick so each routine keeps one consistent dot.
    private func routineTint(_ name: String) -> Color {
        let n = name.lowercased()
        if n.contains("empuj") || n.contains("push") || n.contains("pecho") { return theme.dataStrain }
        if n.contains("tir") || n.contains("pull") || n.contains("espalda") { return theme.dataHrv }
        if n.contains("pierna") || n.contains("leg") || n.contains("quad") || n.contains("glúteo") { return theme.dataSleep }
        let tints = [theme.dataStrain, theme.dataHrv, theme.dataSleep]
        return tints[abs(name.hashValue) % tints.count]
    }

    /// Exercise count + a rough time estimate for the hero meta line. The estimate is a transparent
    /// approximation (planned sets × ~40 s work + the slot's rest), rounded to 5 min — a glance, not a clock.
    private func metaText(_ rid: String) -> Text {
        var t = Text("\(exerciseCounts[rid] ?? 0) exercises")
        let m = estMinutes
        if m > 0 { t = t + Text(verbatim: " · ") + Text("~\(m) min") }
        return t
    }

    private var estMinutes: Int {
        guard !todaySlots.isEmpty else { return 0 }
        var sec = 0
        for s in todaySlots {
            let rest = s.re.restMode == .fixed ? s.re.restSeconds : 90
            sec += max(1, s.re.targetSets) * (40 + rest)
        }
        return max(5, Int((Double(sec) / 60 / 5).rounded()) * 5)
    }

    /// The one solid button per screen (F8): a day with a routine fills it («Empezar {rutina}»); a rest
    /// day leaves it open but quiet (outline). Both route through `startToday`.
    private var empezarButton: some View {
        Button { startToday() } label: {
            (todayRoutine.map { Text("Empezar") + Text(verbatim: " \($0.name)") } ?? Text("Empezar"))
                .font(StrandFont.headline)
                .foregroundStyle(todayRoutine != nil ? theme.paperHi : theme.ink)
                .frame(maxWidth: .infinity).padding(.vertical, 15)
                .background {
                    let s = RoundedRectangle(cornerRadius: 13, style: .continuous)
                    if todayRoutine != nil { s.fill(theme.ink) } else { s.strokeBorder(theme.hairlineStrong, lineWidth: 1) }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// F1: a day with a routine starts the guided session in one tap (slots prefetched on load); an empty
    /// routine opens its plan to edit instead of an empty session; a rest day opens the «Hoy descansas» sheet.
    private func startToday() {
        guard let r = todayRoutine else { openRestDay(); return }
        guard !todaySlots.isEmpty else { openRoutine(r.id); return }
        model.startStrengthSession(routineId: r.id, routineName: r.name, slots: todaySlots)
    }

    /// «Empezar» on a «También en tu plan» routine (mock 1a): load that routine's slots on demand (same
    /// catalog + override + «la última vez» resolution as today's prefetch) and start the guided session.
    /// An empty routine opens its plan to edit instead of an empty session.
    private func startRoutine(_ rid: String, name: String) {
        Task {
            guard let store = await repo.storeHandle() else { return }
            let exs = (try? await store.routineExercises(routineId: rid)) ?? []
            guard !exs.isEmpty else { openRoutine(rid); return }
            let custom = (try? await store.customExercises()) ?? []
            let customByID = Dictionary(custom.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let overrides = (try? await store.exerciseTypeOverrides()) ?? [:]
            var slots: [StrengthSessionModel.PlanSlot] = []
            for re in exs {
                let ex = (ExerciseCatalog.byID(re.exerciseId) ?? customByID[re.exerciseId])?.applying(overrides)
                let last = (try? await store.lastWorkSets(exerciseId: re.exerciseId, limit: 4)) ?? []
                slots.append(.init(re: re, exercise: ex, lastSets: last))
            }
            model.startStrengthSession(routineId: rid, routineName: name, slots: slots)
        }
    }

    // MARK: - ② Suggestion (engine is FER-532 — TrainingRegulation.lightAlternative)
    //
    // A CONTEXTUAL lighter/heavier alternative, derived from today's recovery against your personal
    // baseline. Within the normal band or with no signal the engine returns nil and the row falls back to
    // an INFORMATIONAL placeholder (FER-559) — not tappable, no destination.

    @ViewBuilder private var suggestionRow: some View {
        if let alt = TrainingRegulation.lightAlternative(recovery: recovery) {
            Button { suggestionAction(alt) } label: {
                HStack(spacing: 11) {
                    Image(systemName: suggestionIcon(alt)).font(.system(size: 17)).foregroundStyle(theme.inkSecondary)
                    Text(suggestionLabel(alt)).font(StrandFont.subhead).foregroundStyle(theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.inkTertiary)
                }
                .padding(.horizontal, 15).padding(.vertical, 13)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(theme.hairlineStrong, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    private func suggestionIcon(_ alt: TrainingRegulation.LightAlternative) -> String {
        switch alt {
        case .softer:        return "figure.cooldown"
        case .optionalLight: return "figure.run"
        }
    }

    private func suggestionLabel(_ alt: TrainingRegulation.LightAlternative) -> LocalizedStringKey {
        switch alt {
        case .softer:        return "Lighter day? Mobility · 20 min"
        case .optionalLight: return "Feeling good? Add intervals · 12 min"
        }
    }

    private func suggestionAction(_ alt: TrainingRegulation.LightAlternative) {
        switch alt {
        case .softer:        showMobilityTemplate = true
        case .optionalLight: openIntervals()
        }
    }

    // MARK: - ③ Week strip + streak (one card now — F10)

    // MARK: - ③ «También en tu plan» — the rest of the plan + utility rows (mock 1a)
    //
    // Today's routine is the hero; every OTHER routine in the split lists here with its tint, its
    // «day · muscles» line and an «Empezar» pill that starts THAT session directly (loading its slots on
    // demand). Below the routines, two utility rows: «otra forma de entrenar» (the secondary chooser
    // until 3e lands in F3) and Diet. The section overline keeps a quiet «Editar» into the weekly plan.

    private var tambienEnTuPlan: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Also in your plan").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                Spacer(minLength: 8)
                Button { openWeeklyPlan() } label: {
                    Text("Edit").font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 4)
            ForEach(otherPlanRoutines, id: \.routineId) { row in
                planRoutineRow(row)
            }
            utilityRow(icon: "figure.cooldown",
                       title: String(localized: "Mobility · intervals · breathe · live")) { openOtherWays() }
            utilityRow(icon: "fork.knife",
                       title: String(localized: "Diet · log today's meals"), last: true) { openDiet() }
        }
    }

    /// One «También en tu plan» routine: tint + name + «day · muscles», with an «Empezar» pill that starts
    /// that routine's session (its slots load on tap). Tapping the rest of the row opens the routine.
    private func planRoutineRow(_ row: (routineId: String, name: String, days: String)) -> some View {
        HStack(spacing: 12) {
            Button { openRoutine(row.routineId) } label: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 7) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(routineTint(row.name)).frame(width: 8, height: 8)
                        Text(row.name).font(StrandFont.body).foregroundStyle(theme.ink)
                    }
                    Text(planRowSubtitle(row)).font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                        .padding(.leading, 15)
                }
                .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button { startRoutine(row.routineId, name: row.name) } label: {
                Text("Empezar").font(StrandFont.subhead).foregroundStyle(theme.ink)
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .overlay(Capsule().strokeBorder(theme.hairlineStrong, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) { Divider().overlay(theme.hairline) }
    }

    /// A utility row in «También en tu plan» (otra forma de entrenar, Diet): glyph + label + chevron.
    private func utilityRow(icon: String, title: String, last: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 15)).foregroundStyle(theme.inkSecondary).frame(width: 18)
                Text(title).font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.inkTertiary)
            }
            .padding(.vertical, 12).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { if !last { Divider().overlay(theme.hairline) } }
    }

    /// «day · muscles» for a plan routine: the weekdays it trains, then its top primary muscles (if known).
    private func planRowSubtitle(_ row: (routineId: String, name: String, days: String)) -> String {
        let muscles = routineMuscles[row.routineId] ?? []
        return muscles.isEmpty ? row.days : ([row.days] + muscles).joined(separator: " · ")
    }

    // MARK: - ④ Week instrument — compact progress + streak above the dock (mock 1a)

    private var weekInstrument: some View {
        let states = WeeklySplit.weekStates(split: split, completedWeekdays: completedWeekdays,
                                            todayWeekday: todayWeekday, orderedWeekdays: orderedWeekdays)
        return VStack(alignment: .leading, spacing: 0) {
            Divider().overlay(theme.hairline).padding(.bottom, 12)
            HStack(alignment: .firstTextBaseline) {
                (Text("Your week") + Text(verbatim: " · ") + weekSummary)
                    .instrumentoOverline().foregroundStyle(theme.inkTertiary)
                Spacer(minLength: 8)
                Button { openHistory() } label: {
                    Text(streakText).font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text("See full history"))
            }
            HStack(spacing: 6) {
                ForEach(states, id: \.weekday) { st in dayToken(st) }
            }
            .padding(.top, 9)
        }
    }

    /// This week's progress («2 of 4»), as `Text` so it composes flush inside the overline.
    private var weekSummary: Text {
        Text("\(weekDoneCount) of \(weekPlannedCount)")
    }

    /// The adherence streak in the mock's «12 días en racha» voice.
    private var streakText: String {
        streakDays == 1 ? String(localized: "1 day on streak") : String(localized: "\(streakDays) days on streak")
    }

    private func dayToken(_ st: WeeklySplit.DayStatus) -> some View {
        let initial = split[st.weekday].flatMap { routinesById[$0]?.name }.map { String($0.prefix(1)).uppercased() } ?? ""
        return VStack(spacing: 6) {
            Text(weekdayLetter(st.weekday)).font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
            tokenBody(st, initial: initial)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        // F7: a done day opens its session; today's token starts the session (the same door as the hero).
        // Upcoming / rest tokens are inert (and never look tappable).
        .onTapGesture {
            switch st.state {
            case .done:  openSession(st.weekday)
            case .today: startToday()
            default:     break
            }
        }
    }

    @ViewBuilder
    private func tokenBody(_ st: WeeklySplit.DayStatus, initial: String) -> some View {
        let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)
        ZStack {
            switch st.state {
            case .done:
                shape.fill(theme.ink)
                Image(systemName: "checkmark").font(.system(size: 16, weight: .semibold)).foregroundStyle(theme.paper)
            case .today:
                shape.fill(theme.paperHi).overlay(shape.strokeBorder(theme.ink, lineWidth: 1.5))
                Text(initial).font(StrandFont.title2).foregroundStyle(theme.ink)
                Circle().fill(theme.dataRecovery).frame(width: 6, height: 6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(5)
            case .upcoming:
                shape.strokeBorder(theme.hairlineStrong, lineWidth: 1)
                Text(initial).font(StrandFont.title2).foregroundStyle(theme.inkSecondary)
            case .rest:
                shape.strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 3])).foregroundStyle(theme.hairlineStrong)
                Text("—").font(StrandFont.body).foregroundStyle(theme.inkDim)
            }
        }
        .frame(height: 46)
    }

    // MARK: - Empty state B (no split yet → build the week)

    private var emptyStateB: some View {
        VStack(spacing: 14) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 36, weight: .regular)).foregroundStyle(theme.inkTertiary).accessibilityHidden(true)
            Text("No plan yet").font(StrandFont.title2).foregroundStyle(theme.ink).multilineTextAlignment(.center)
            Text("Build your week to see today and your progress.")
                .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            Button { openWeeklyPlan() } label: {
                Text("Build my week").font(StrandFont.headline).foregroundStyle(theme.paperHi)
                    .frame(maxWidth: .infinity).padding(.vertical, 15)
                    .background(theme.ink, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            .buttonStyle(.plain).padding(.top, 4)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 30).padding(.horizontal, 18)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous).strokeBorder(theme.hairline, lineWidth: 1))
    }

    /// Start the mobility session «Empezar» queued from the TRAINING-day template sheet (FER-560).
    private func startPendingMobility() {
        guard let p = pendingMobility else { return }
        pendingMobility = nil
        model.startStrengthSession(routineId: nil, routineName: p.name, slots: p.slots)
    }

    // MARK: - Card shell + bits

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0, content: content)
            .padding(NoopMetrics.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous).strokeBorder(theme.hairline, lineWidth: 1))
    }

    /// Localized short weekday letter (respects locale), single character.
    private func weekdayLetter(_ wd: Int) -> String {
        let s = Calendar.current.veryShortWeekdaySymbols[(wd - 1) % 7]
        return s.uppercased()
    }

    // MARK: - Derived

    private var routinesById: [String: Routine] { Dictionary(routines.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }) }
    private var todayRoutineId: String? { WeeklySplit.todayRoutineId(split: split, todayWeekday: todayWeekday) }
    private var todayRoutine: Routine? { todayRoutineId.flatMap { routinesById[$0] } }

    /// A Monday-anchored calendar for bucketing sessions into weeks.
    private var weekCalendar: Calendar { var c = Calendar.current; c.firstWeekday = 2; return c }
    private func weekStart(_ date: Date) -> Date { weekCalendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date }
    private var thisWeekStart: Date { weekStart(Date()) }

    /// Completed sessions of THIS week, keyed by local weekday (the most recent per day).
    private var completedThisWeek: [Int: StrengthSession] {
        var out: [Int: StrengthSession] = [:]
        for s in sessions where s.endTs != nil {
            let date = Date(timeIntervalSince1970: TimeInterval(s.startTs))
            guard weekStart(date) == thisWeekStart else { continue }
            let wd = Calendar.current.component(.weekday, from: date)
            if out[wd] == nil { out[wd] = s }   // sessions are newest-first → first seen is the latest
        }
        return out
    }
    private var completedWeekdays: Set<Int> { Set(completedThisWeek.keys) }
    private var weekPlannedCount: Int { split.keys.count }
    private var weekDoneCount: Int { Set(split.keys).intersection(completedWeekdays).count }

    private func openSession(_ weekday: Int) {
        guard let s = completedThisWeek[weekday] else { return }
        let name = s.routineId.flatMap { routinesById[$0]?.name } ?? String(localized: "Workout")
        openWorkoutSession(WorkoutSessionRoute(id: s.id, startTs: s.startTs, endTs: s.endTs,
                                               strain: s.strain, avgHr: s.avgHr, routineName: name))
    }

    /// «Días cumpliendo el plan» — delega en el helper compartido `TrainingStreak` para que el número sea
    /// EXACTAMENTE el mismo que muestra el bloque «Hoy en tu plan» del Daily Brief (FER-613).
    private var adherenceStates: [WeeklySplit.DayAdherence] {
        TrainingStreak.adherenceStates(sessions: sessions, split: split)
    }
    private var streakDays: Int { WeeklySplit.adherenceStreak(adherenceStates) }

    /// One row per distinct routine in the split: its name + the weekdays it's assigned to.
    private var planRows: [(routineId: String, name: String, days: String)] {
        var order: [String] = []; var daysOf: [String: [Int]] = [:]
        for wd in orderedWeekdays {
            guard let id = split[wd] else { continue }
            if daysOf[id] == nil { order.append(id) }
            daysOf[id, default: []].append(wd)
        }
        return order.compactMap { id in
            guard let n = routinesById[id]?.name else { return nil }
            let days = (daysOf[id] ?? []).map(weekdayLetter).joined(separator: " · ")
            return (id, n, days)
        }
    }

    /// «También en tu plan» lists every scheduled routine EXCEPT today's (which is the hero).
    private var otherPlanRoutines: [(routineId: String, name: String, days: String)] {
        planRows.filter { $0.routineId != todayRoutineId }
    }

    /// The hero's muscle line: today's routine's top primary muscles, «·»-joined (nil when unknown).
    private func routineMuscleLine(_ rid: String) -> String? {
        let m = routineMuscles[rid] ?? []
        return m.isEmpty ? nil : m.joined(separator: " · ")
    }

    private var hoyOverline: String {
        let day = Calendar.current.standaloneWeekdaySymbols[(todayWeekday - 1) % 7]
        return String(localized: "Today · \(day)")
    }

    private func recoveryLine(_ rec: Double) -> String {
        switch TrainingRegulation.suggest(recovery: rec)?.reason {
        case .recoveryHigh: return String(localized: "Recovery high for you · you can take on your full plan.")
        case .recoveryLow:  return String(localized: "Recovery low for you · maybe ease the volume today.")
        default:            return String(localized: "Recovery in your range · train at your usual load.")
        }
    }

    // MARK: - Data

    private func load() async {
        guard let store = await repo.storeHandle() else { loaded = true; return }
        let rs = (try? await store.routines()) ?? []
        let customAll = (try? await store.customExercises()) ?? []
        let customAllByID = Dictionary(customAll.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var counts: [String: Int] = [:]
        var muscles: [String: [String]] = [:]
        for r in rs {
            let exs = (try? await store.routineExercises(routineId: r.id)) ?? []
            counts[r.id] = exs.count
            muscles[r.id] = Self.topMuscles(exs, customByID: customAllByID)
        }
        let sched = (try? await store.routineSchedule()) ?? []
        let splitMap = Dictionary(sched.map { ($0.weekday, $0.routineId) }, uniquingKeysWith: { a, _ in a })
        // Prefetch today's routine into guided-session slots so «Empezar» starts in one tap (F1). Only
        // today's routine is loaded (bounded), with the same catalog + override + «la última vez» resolution
        // «Rutina de hoy» uses, so the prefill matches.
        var slots: [StrengthSessionModel.PlanSlot] = []
        if let tid = WeeklySplit.todayRoutineId(split: splitMap, todayWeekday: todayWeekday) {
            let exs = (try? await store.routineExercises(routineId: tid)) ?? []
            let custom = (try? await store.customExercises()) ?? []
            let customByID = Dictionary(custom.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let overrides = (try? await store.exerciseTypeOverrides()) ?? [:]
            for re in exs {
                let ex = (ExerciseCatalog.byID(re.exerciseId) ?? customByID[re.exerciseId])?.applying(overrides)
                let last = (try? await store.lastWorkSets(exerciseId: re.exerciseId, limit: 4)) ?? []
                slots.append(.init(re: re, exercise: ex, lastSets: last))
            }
        }
        routines = rs
        exerciseCounts = counts
        routineMuscles = muscles
        split = splitMap
        todaySlots = slots
        sessions = (try? await store.recentSessions(limit: 200)) ?? []
        loaded = true
        // A «Empezar» from the Daily Brief that arrived before the prefetch finished now has its slots (FER-613).
        if startWhenLoaded { startWhenLoaded = false; startToday() }
    }

    /// Tally the primary muscles across a routine's exercises → the top three, as Spanish display labels
    /// (`MuscleVocabulary`). Frequency-ranked; ties keep first-seen order. Feeds the hero muscle line and
    /// the «También en tu plan» subtitles from the same per-routine fetch that counts exercises.
    private static func topMuscles(_ exs: [RoutineExercise], customByID: [String: Exercise]) -> [String] {
        var tally: [String: Int] = [:]
        var order: [String] = []
        for re in exs {
            guard let ex = ExerciseCatalog.byID(re.exerciseId) ?? customByID[re.exerciseId] else { continue }
            for m in ex.primaryMuscles {
                if tally[m] == nil { order.append(m) }
                tally[m, default: 0] += 1
            }
        }
        let idx = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        let top = order.sorted {
            let a = tally[$0] ?? 0, b = tally[$1] ?? 0
            return a != b ? a > b : (idx[$0] ?? 0) < (idx[$1] ?? 0)
        }.prefix(3)
        return top.map { MuscleVocabulary.es[$0] ?? $0.capitalized }
    }
}

// MARK: - Recovery chip ring (FER-534)

/// A small 240° recovery arc in the `dataRecovery` token — no bloom, no bead (the full `RecoveryRing` is
/// geometry-heavy for a 22pt chip). The fraction of the arc filled reads as the score; the caller draws
/// the numeral beside it. Single-token color (not the multi-stop ring gradient) so the chip stays
/// token-pure at 22pt, where the gradient nuance wouldn't read anyway.
private struct RecoveryChipRing: View {
    @Environment(\.instrumentoTheme) private var theme
    let score: Double   // 0…100

    var body: some View {
        let frac = max(0, min(1, score / 100))
        ZStack {
            Circle().trim(from: 0, to: 0.75)
                .stroke(theme.hairline, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(135))
            Circle().trim(from: 0, to: 0.75 * frac)
                .stroke(theme.dataRecovery, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(135))
        }
    }
}

// MARK: - «Hoy descansas. También cuenta.» (v3 · 2B) — a PUSHED screen now (FER-718)
//
// What «Empezar» opens on a rest day, and what the streak row protects. Reframed to the mock: the streak
// is explicitly SAFE (resting does not break it), a card «Sugerido por tu recuperación» carries the one
// cited light alternative (`TrainingRegulation.lightAlternative` — the only solid gate), a quieter «Si aun
// así quieres entrenar» section lists the other ways, and a footer names tomorrow's routine from the split.

struct RestDayScreen: View {
    var openIntervals: () -> Void
    var openBreathe: () -> Void
    var openRoutines: () -> Void

    @Environment(\.instrumentoTheme) private var theme
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var model: AppModel

    @State private var split: [Int: String] = [:]
    @State private var routineNames: [String: String] = [:]
    @State private var showLive = false

    private var recovery: Double? { repo.today?.recovery }
    private var alt: TrainingRegulation.LightAlternative? {
        TrainingRegulation.lightAlternative(recovery: recovery)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Today you rest").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                Text("Today you rest. It counts too.")
                    .font(StrandFont.title1).foregroundStyle(theme.ink).padding(.top, 3)
                    .fixedSize(horizontal: false, vertical: true)

                streakBullet.padding(.top, 16)

                if let alt {
                    suggestedCard(alt).padding(.top, NoopMetrics.sectionGap)
                }

                Text("If you still want to train").instrumentoOverline()
                    .foregroundStyle(theme.inkTertiary).padding(.top, NoopMetrics.sectionGap)
                VStack(spacing: 0) {
                    if alt != .softer { row("figure.cooldown", "Mobility · 20 min") { model.startMobilityOneOff() } }
                    if alt != .optionalLight { row("timer", "Intervals · 12 min") { openIntervals() } }
                    row("list.bullet", "Pick a routine") { openRoutines() }
                    row("wind", "Breathe") { openBreathe() }
                    row("dot.radiowaves.left.and.right", "Live", last: true) { startLive() }
                }
                .padding(.top, 6)

                if let tomorrow = tomorrowRoutineName {
                    Divider().overlay(theme.hairline).padding(.top, NoopMetrics.sectionGap)
                    Text("Tomorrow: \(tomorrow)")
                        .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary).padding(.top, 14)
                }
            }
            .padding(.top, 20)
            .padding(.horizontal, NoopMetrics.screenPadding)
            .padding(.bottom, NoopMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.paper.ignoresSafeArea())
        .sheet(isPresented: $showLive) {
            LiveWorkoutSheet(theme: theme)
                .environmentObject(model)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(theme.paper)
                .preferredColorScheme(.light)
        }
        .task { await load() }
    }

    /// The streak-protected reassurance: color only on the recovery bullet, copy explicit that resting
    /// keeps the streak intact.
    private var streakBullet: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle().fill(theme.dataRecovery).frame(width: 8, height: 8)
            Text("Resting doesn't break your streak. A planned rest day keeps it going.")
                .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The one cited light alternative, in a card — the only solid recovery gate we surface here.
    private func suggestedCard(_ alt: TrainingRegulation.LightAlternative) -> some View {
        let name: LocalizedStringKey = alt == .softer ? "Mobility · 20 min" : "Intervals · 12 min"
        let tag: LocalizedStringKey = alt == .softer ? "gentle" : "extra"
        return VStack(alignment: .leading, spacing: 0) {
            Text("Suggested by your recovery").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text(name).font(StrandFont.title2).foregroundStyle(theme.ink)
                Text(tag).font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
                    .padding(.horizontal, 9).padding(.vertical, 2)
                    .background(theme.paper, in: Capsule())
                    .overlay(Capsule().strokeBorder(theme.hairlineStrong, lineWidth: 1))
            }
            .padding(.top, 5)
            Button { if alt == .softer { model.startMobilityOneOff() } else { openIntervals() } } label: {
                Text("Empezar").font(StrandFont.headline).foregroundStyle(theme.paperHi)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(theme.ink, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain).padding(.top, 14)
        }
        .padding(NoopMetrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous).strokeBorder(theme.hairline, lineWidth: 1))
    }

    private func row(_ icon: String, _ title: LocalizedStringKey, last: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 18)).foregroundStyle(theme.inkSecondary).frame(width: 26)
                Text(title).font(StrandFont.body).foregroundStyle(theme.ink)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.inkDim)
            }
            .padding(.vertical, 14).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { if !last { Divider().overlay(theme.hairline) } }
    }

    private func startLive() {
        if model.activeWorkout == nil { model.startWorkout() }
        showLive = true
    }

    /// Tomorrow's routine name from the weekly split (nil = tomorrow is also a rest day).
    private var tomorrowRoutineName: String? {
        let tomorrow = (Calendar.current.component(.weekday, from: Date()) % 7) + 1
        return split[tomorrow].flatMap { routineNames[$0] }
    }

    private func load() async {
        guard let store = await repo.storeHandle() else { return }
        let sched = (try? await store.routineSchedule()) ?? []
        split = Dictionary(sched.map { ($0.weekday, $0.routineId) }, uniquingKeysWith: { a, _ in a })
        let rs = (try? await store.routines()) ?? []
        routineNames = Dictionary(rs.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
    }
}

// MARK: - «Otra forma de entrenar» (v3 · 3e) — a PUSHED screen now (FER-718)
//
// The alternative-training chooser, reframed to the mock: four large rows (Mobility · Intervals · Breathe
// · Live) and a footer that reassures nothing here breaks the streak or the plan.

struct OtherWaysScreen: View {
    var openIntervals: () -> Void
    var openBreathe: () -> Void

    @Environment(\.instrumentoTheme) private var theme
    @EnvironmentObject private var model: AppModel
    @State private var showLive = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Another type?").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                Text("Another way to train").font(StrandFont.title1).foregroundStyle(theme.ink).padding(.top, 3)

                VStack(spacing: 0) {
                    bigRow("figure.cooldown", "Mobility", subtitle: String(localized: "Gentle · 20 min")) { model.startMobilityOneOff() }
                    bigRow("timer", "Intervals", subtitle: String(localized: "Bursts · 12 min")) { openIntervals() }
                    bigRow("wind", "Breathe", subtitle: String(localized: "Slow it down")) { openBreathe() }
                    bigRow("dot.radiowaves.left.and.right", "Live", subtitle: String(localized: "Beat by beat"), last: true) { startLive() }
                }
                .padding(.top, NoopMetrics.sectionGap)

                Text("None of this breaks your streak or your plan.")
                    .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                    .frame(maxWidth: .infinity, alignment: .center).padding(.top, NoopMetrics.sectionGap)
            }
            .padding(.top, 20)
            .padding(.horizontal, NoopMetrics.screenPadding)
            .padding(.bottom, NoopMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.paper.ignoresSafeArea())
        .sheet(isPresented: $showLive) {
            LiveWorkoutSheet(theme: theme)
                .environmentObject(model)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(theme.paper)
                .preferredColorScheme(.light)
        }
    }

    private func bigRow(_ icon: String, _ title: LocalizedStringKey, subtitle: String, last: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 15) {
                Image(systemName: icon).font(.system(size: 22)).foregroundStyle(theme.inkSecondary).frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(StrandFont.headline).foregroundStyle(theme.ink)
                    Text(subtitle).font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.inkDim)
            }
            .padding(.vertical, 18).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { if !last { Divider().overlay(theme.hairline) } }
    }

    private func startLive() {
        if model.activeWorkout == nil { model.startWorkout() }
        showLive = true
    }
}
#endif
