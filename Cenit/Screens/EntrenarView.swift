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
    /// Push a completed strength session's detail (from a «done» day in the week strip).
    var openWorkoutSession: (WorkoutSessionRoute) -> Void

    var body: some View {
        EntrenarLanding(openRoutine: openRoutine,
                        openBreathe: openBreathe, openIntervals: openIntervals, openDiet: openDiet,
                        openHistory: openHistory, openWeeklyPlan: openWeeklyPlan,
                        openRoutines: openRoutines, openWorkoutSession: openWorkoutSession)
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
    var openWorkoutSession: (WorkoutSessionRoute) -> Void

    @State private var loaded = false
    @State private var routines: [Routine] = []
    @State private var exerciseCounts: [String: Int] = [:]
    /// The weekly split, `weekday → routineId` (Calendar convention, 1 = Sun … 7 = Sat). FER-531.
    @State private var split: [Int: String] = [:]
    /// Completed strength sessions (newest first), for the week strip's day states and the daily streak.
    @State private var sessions: [StrengthSession] = []
    /// Today's routine resolved into guided-session slots, prefetched on load so «Empezar» starts in one
    /// tap (F1). Empty when today is a rest day or the routine has no exercises.
    @State private var todaySlots: [StrengthSessionModel.PlanSlot] = []
    /// Drives the secondary «¿otro tipo?» chooser (otra rutina / intervals / breathe / live).
    @State private var showChooser = false
    /// What the chooser picked — performed on its dismiss, so we never stack two sheets.
    @State private var pendingStart: StartKind? = nil
    /// Drives the «Hoy descansas» rest sheet (F3).
    @State private var showRestSheet = false
    /// What the rest sheet picked — performed on its dismiss (so the session sheet / a push never stacks).
    @State private var pendingRest: RestAction? = nil
    /// Drives the live-workout sheet (the chooser's / rest sheet's «En vivo»).
    @State private var showLive = false
    /// Whether «Tu plan» is expanded. Collapsed each visit (not persisted) so the landing stays short.
    @State private var planExpanded = false
    /// Drives the templates sheet opened straight on the mobility routine from the ③ «softer» suggestion
    /// (a TRAINING-day nudge; the rest sheet starts mobility directly instead). FER-554.
    @State private var showMobilityTemplate = false
    /// «Empezar» from the mobility template stashes its (name, slots) here; the session starts on the
    /// sheet's dismiss so it never stacks on the templates sheet (FER-560).
    @State private var pendingMobility: (name: String, slots: [StrengthSessionModel.PlanSlot])? = nil
    /// Drives the Recovery Detail sheet opened from the recovery chip (FER-557).
    @State private var recoveryDetail: RecoveryDetailItem? = nil

    private enum StartKind { case routine, intervals, breathe, live }
    /// What the rest sheet can launch. `mobility` is a one-off guided session (not saved to the plan).
    private enum RestAction { case mobility, intervals, chooseRoutine, breathe, live }

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
                        if model.strengthSession != nil { resumeRow }
                        hoyCard          // ① hero «Hoy» — first now (F10)
                        suggestionRow    // ② contextual lighter/heavier nudge
                        weekStrip        // ③ week + streak in one card
                        tuPlan           // ④ plan, collapsible, single «Editar» (F5)
                        dietFooter       // ⑤ Diet as a quiet footer link (F10)
                    }
                }
            }
            .padding(.top, 14)   // same top inset as «Patrones»/«Tendencias» so the headers align across tabs
            .padding(.horizontal, NoopMetrics.screenPadding)
            .padding(.bottom, NoopMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.paper.ignoresSafeArea())
        // The secondary «¿otro tipo?» chooser. Its choice is performed on dismiss so a push / live-sheet
        // never races the chooser's own dismissal.
        .sheet(isPresented: $showChooser, onDismiss: performPendingStart) {
            chooserSheet
                .presentationDetents([.height(340)])
                .presentationDragIndicator(.visible)
                .presentationBackground(theme.paper)
                .preferredColorScheme(.light)
        }
        // The «Hoy descansas» rest sheet (F3). Like the chooser, its action runs on dismiss.
        .sheet(isPresented: $showRestSheet, onDismiss: performPendingRest) {
            restSheet
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(theme.paper)
                .preferredColorScheme(.light)
        }
        // The ③ «softer» suggestion (FER-554) opens the templates sheet straight on the mobility routine.
        // «Empezar» starts a one-off guided session (on the sheet's dismiss, so it never stacks — FER-171),
        // with «Add to my routines» as the secondary action. Theme doesn't cross the sheet boundary.
        .sheet(isPresented: $showMobilityTemplate, onDismiss: startPendingMobility) {
            StarterTemplatesSheet(initialSelection: StarterTemplates.byID("mobility"),
                                  onStart: { name, slots in pendingMobility = (name, slots) }) { await load() }
                .instrumentoTheme(theme).environmentObject(repo).preferredColorScheme(.light)
        }
        // Live workout (the chooser's / rest sheet's «En vivo»).
        .sheet(isPresented: $showLive) {
            LiveWorkoutSheet(theme: theme)
                .environmentObject(model)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(theme.paper)
                .preferredColorScheme(.light)
        }
        // Recovery detail from the chip — same sheet Today/Cuerpo open; theme passed explicitly (it
        // doesn't cross the `.sheet` boundary, FER-162), no nested NavigationStack (FER-171). (FER-557)
        .sheet(item: $recoveryDetail) { item in
            RecoveryDetailScreen(theme: theme, model: item.model)
        }
        // The guided strength session (FER-347), hosted at the landing root so it survives tab switches;
        // the session lives in AppModel, so swiping the sheet down only hides it (the «Resume» row re-opens).
        .sheet(isPresented: $model.strengthSheetPresented, onDismiss: {
            if model.strengthSession?.summary != nil { model.closeStrengthSummary() }
        }) {
            if let session = model.strengthSession {
                LiveStrengthSheet(session: session, theme: theme)
                    .environmentObject(model)
                    .environmentObject(tabRouter)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(theme.paper)
                    .preferredColorScheme(.light)
            }
        }
        .task { await load() }
    }

    // MARK: - Header + recovery chip

    private var header: some View {
        // Shared wordmark row — same lockup, size and baseline as «Tendencias»/«Patrones» so the three
        // tab titles align as you swipe. Glyph = the dock's tab icon; the recovery chip rides the trailing
        // slot, which is anchored to the title's height so it never pushes the title down.
        InstrumentoTabHeader("Train") {
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
                Text(r.name).font(StrandFont.title2).foregroundStyle(theme.ink).padding(.top, 3)
                metaText(r.id).font(StrandFont.subhead).foregroundStyle(theme.inkSecondary).padding(.top, 2)
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
            // The secondary chooser only makes sense when there's a session to start instead — on a rest
            // day the door itself opens the rest sheet, which already lists the other options.
            if todayRoutine != nil {
                Button { showChooser = true } label: {
                    Text("Another type? · intervals · breathe · live")
                        .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                        .frame(maxWidth: .infinity, alignment: .center).padding(.top, 7).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
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
        guard let r = todayRoutine else { showRestSheet = true; return }
        guard !todaySlots.isEmpty else { openRoutine(r.id); return }
        model.startStrengthSession(routineId: r.id, routineName: r.name, slots: todaySlots)
    }

    // MARK: - ② Suggestion (engine is FER-532 — TrainingRegulation.lightAlternative)
    //
    // A CONTEXTUAL lighter/heavier alternative, derived from today's recovery against your personal
    // baseline. Within the normal band or with no signal the engine returns nil and the row falls back to
    // an INFORMATIONAL placeholder (FER-559) — not tappable, no destination.

    @ViewBuilder private var suggestionRow: some View {
        if let alt = TrainingRegulation.lightAlternative(recovery: recovery) {
            Button { suggestionAction(alt) } label: {
                suggestionRowBody(icon: suggestionIcon(alt), label: suggestionLabel(alt),
                                  iconTint: theme.inkSecondary, labelTint: theme.ink, showsChevron: true, dashed: false)
            }
            .buttonStyle(.plain)
        } else {
            suggestionRowBody(icon: "sparkles",
                              label: "Suggestions will appear here based on your recovery",
                              iconTint: theme.inkDim, labelTint: theme.inkTertiary, showsChevron: false, dashed: true)
        }
    }

    private func suggestionRowBody(icon: String, label: LocalizedStringKey, iconTint: Color,
                                   labelTint: Color, showsChevron: Bool, dashed: Bool) -> some View {
        HStack(spacing: 11) {
            Image(systemName: icon).font(.system(size: 17)).foregroundStyle(iconTint)
            Text(label).font(StrandFont.subhead).foregroundStyle(labelTint)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if showsChevron {
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.inkTertiary)
            }
        }
        .padding(.horizontal, 15).padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(style: dashed ? StrokeStyle(lineWidth: 1, dash: [3, 3]) : StrokeStyle(lineWidth: 1))
            .foregroundStyle(theme.hairlineStrong))
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

    private var weekStrip: some View {
        let states = WeeklySplit.weekStates(split: split, completedWeekdays: completedWeekdays,
                                            todayWeekday: todayWeekday, orderedWeekdays: orderedWeekdays)
        return card {
            HStack {
                Text("Your week").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                Spacer()
                // Progress + streak in one line; the whole right side opens the full history (FER-574).
                Button { openHistory() } label: {
                    HStack(spacing: 5) {
                        weekSummary.font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(theme.inkTertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text("See full history"))
            }
            HStack(spacing: 6) {
                ForEach(states, id: \.weekday) { st in dayToken(st) }
            }
            .padding(.top, 13)
            Text("Tap today to start · a done day to see the session")
                .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                .padding(.top, 9)
        }
    }

    /// Progress («2 of 4») plus the streak («· streak 12 days»). Built as a single `Text` so the chevron
    /// sits flush after it.
    private var weekSummary: Text {
        var t = Text("\(weekDoneCount) of \(weekPlannedCount)")
        if streakDays > 0 {
            let s = streakDays == 1 ? Text("streak 1 day") : Text("streak \(streakDays) days")
            t = t + Text(verbatim: " · ") + s
        }
        return t
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

    // MARK: - ④ Tu plan — a collapsible disclosure with a single «Editar» action (F5)
    //
    // The day list folds behind the «Tu plan» header (collapsed by default each visit) so the landing
    // stays short. The header is the toggle; expanded it reveals the day rows and an «Editar» action.
    // Create / import / templates / library no longer live here — they're consolidated in «Mis rutinas»
    // (F4), reached from the editor's «Gestionar rutinas».

    private var tuPlan: some View {
        VStack(alignment: .leading, spacing: 6) {
            planHeader
            if planExpanded {
                card {
                    ForEach(Array(planRows.enumerated()), id: \.offset) { idx, row in
                        if idx > 0 { Divider().overlay(theme.hairline) }
                        Button { openRoutine(row.routineId) } label: {
                            HStack(spacing: 10) {
                                Text(row.name).font(StrandFont.body).foregroundStyle(theme.ink)
                                Spacer(minLength: 8)
                                Text(row.days).font(StrandFont.mono).foregroundStyle(theme.inkTertiary)
                            }
                            .frame(minHeight: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    /// The «Tu plan» disclosure header. The whole row toggles the day list; «Editar» (only when expanded)
    /// is a distinct button that captures its own tap, the rest of the row toggles.
    private var planHeader: some View {
        HStack {
            Text("Your plan").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            Spacer(minLength: 8)
            if planExpanded {
                Button { openWeeklyPlan() } label: {
                    Text("Edit").font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                }
                .buttonStyle(.plain)
            } else {
                Text(planDaysText).font(StrandFont.subhead).foregroundStyle(theme.inkTertiary)
            }
            Image(systemName: "chevron.down")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.inkTertiary)
                .rotationEffect(.degrees(planExpanded ? 180 : 0))
        }
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeInOut(duration: 0.22)) { planExpanded.toggle() } }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(Text(planExpanded ? "Collapse your plan" : "Expand your plan"))
    }

    /// Collapsed-header hint: how many days the split trains.
    private var planDaysText: String {
        let n = split.keys.count
        return n == 1 ? String(localized: "1 day") : String(localized: "\(n) days")
    }

    // MARK: - ⑤ Diet footer (parking — F10)

    private var dietFooter: some View {
        Button { openDiet() } label: {
            HStack(spacing: 7) {
                Image(systemName: "fork.knife").font(.system(size: 13)).foregroundStyle(theme.inkTertiary)
                Text("Diet").font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                Text("for now").font(StrandFont.footnote).foregroundStyle(theme.inkDim)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.inkDim)
            }
            .padding(.horizontal, 2).padding(.top, 2).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Resume (in-progress guided session)

    private var resumeRow: some View {
        Button { model.resumeStrengthSession() } label: {
            HStack(spacing: 12) {
                Image(systemName: "figure.strengthtraining.functional").frame(width: 30)
                    .font(.system(size: 17)).foregroundStyle(theme.dataStrain)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Workout in progress").font(StrandFont.body).foregroundStyle(theme.ink)
                    Text(model.strengthSession?.routineName ?? "").font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                }
                Spacer(minLength: 8)
                Text("Resume").font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.inkTertiary)
            }
            .padding(.horizontal, 15).padding(.vertical, 13)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous).strokeBorder(theme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Resume workout in progress"))
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

    // MARK: - Secondary «¿otro tipo?» chooser

    private var chooserSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Another type?").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            Text("What are you training?").font(StrandFont.title2).foregroundStyle(theme.ink).padding(.top, 2)
            chooserOption("dumbbell", "Another routine", subtitle: String(localized: "Pick or build one")) { pick(.routine) }
            chooserOption("timer", "Intervals", subtitle: nil) { pick(.intervals) }
            chooserOption("wind", "Breathe", subtitle: nil) { pick(.breathe) }
            chooserOption("dot.radiowaves.left.and.right", "Live", subtitle: nil) { pick(.live) }
            Spacer(minLength: 0)
        }
        .padding(NoopMetrics.screenPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.paper)
    }

    private func chooserOption(_ icon: String, _ title: LocalizedStringKey, subtitle: String?,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Image(systemName: icon).font(.system(size: 20)).foregroundStyle(theme.inkSecondary).frame(width: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(StrandFont.headline).foregroundStyle(theme.ink)
                    if let subtitle { Text(subtitle).font(StrandFont.caption).foregroundStyle(theme.inkTertiary) }
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.inkDim)
            }
            .padding(.vertical, 14).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) { Divider().overlay(theme.hairline) }
    }

    private func pick(_ kind: StartKind) { pendingStart = kind; showChooser = false }

    private func performPendingStart() {
        guard let kind = pendingStart else { return }
        pendingStart = nil
        switch kind {
        case .routine:   openRoutines()   // pick / build a different routine in «Mis rutinas»
        case .intervals: openIntervals()
        case .breathe:   openBreathe()
        case .live:      if model.activeWorkout == nil { model.startWorkout() }; showLive = true
        }
    }

    // MARK: - «Hoy descansas» rest sheet (F3)
    //
    // What «Empezar» presents on a rest day: a hero suggested by recovery (one-off, never saved to the
    // plan), the other ways to train (a routine off-plan, breathe, live), and a reminder that resting is
    // valid. The hero/title is driven by the cited `TrainingRegulation.lightAlternative` (StrandAnalytics):
    //   • .softer (low/normal recovery) → «Movilidad · 20 min»
    //   • .optionalLight (high recovery) → «Intervalos · 12 min»
    //   • nil (no signal) → no hero, just the options.

    private var restSheet: some View {
        let alt = TrainingRegulation.lightAlternative(recovery: recovery)
        return VStack(alignment: .leading, spacing: 0) {
            Text("Today you rest").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            if let alt {
                Text(restTitle(alt)).font(StrandFont.title2).foregroundStyle(theme.ink).padding(.top, 3)
                restHero(alt).padding(.top, 18)
            } else {
                Text("Your plan doesn't train today.")
                    .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary).padding(.top, 6)
            }
            VStack(spacing: 0) {
                restOption("list.bullet", "Pick a routine") { pendingRest = .chooseRoutine; showRestSheet = false }
                restOption("wind", "Breathe") { pendingRest = .breathe; showRestSheet = false }
                restOption("dot.radiowaves.left.and.right", "Live") { pendingRest = .live; showRestSheet = false }
            }
            .padding(.top, alt != nil ? 14 : 18)
            Text("Resting keeps your streak too.")
                .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                .frame(maxWidth: .infinity, alignment: .center).padding(.top, 16)
            Spacer(minLength: 0)
        }
        .padding(NoopMetrics.screenPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.paper)
    }

    private func restTitle(_ alt: TrainingRegulation.LightAlternative) -> LocalizedStringKey {
        switch alt {
        case .softer:        return "Up for something light?"
        case .optionalLight: return "Feeling energetic?"
        }
    }

    private func restHero(_ alt: TrainingRegulation.LightAlternative) -> some View {
        let name: LocalizedStringKey = alt == .softer ? "Mobility · 20 min" : "Intervals · 12 min"
        let tag: LocalizedStringKey = alt == .softer ? "gentle" : "extra"
        return card {
            Text("Suggested by your recovery").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text(name).font(StrandFont.title2).foregroundStyle(theme.ink)
                Text(tag).font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
                    .padding(.horizontal, 9).padding(.vertical, 2)
                    .background(theme.paper, in: Capsule())
                    .overlay(Capsule().strokeBorder(theme.hairlineStrong, lineWidth: 1))
            }
            .padding(.top, 5)
            Button { pendingRest = (alt == .softer ? .mobility : .intervals); showRestSheet = false } label: {
                Text("Empezar").font(StrandFont.headline).foregroundStyle(theme.paperHi)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(theme.ink, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain).padding(.top, 14)
        }
    }

    private func restOption(_ icon: String, _ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
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
        .overlay(alignment: .top) { Divider().overlay(theme.hairline) }
    }

    private func performPendingRest() {
        guard let action = pendingRest else { return }
        pendingRest = nil
        switch action {
        case .mobility:      startMobilityOneOff()
        case .intervals:     openIntervals()
        case .chooseRoutine: openRoutines()
        case .breathe:       openBreathe()
        case .live:          if model.activeWorkout == nil { model.startWorkout() }; showLive = true
        }
    }

    /// Start the mobility one-off queued from the rest sheet's hero (FER-554/560): a guided session built
    /// from the bundled mobility template, NOT saved to the plan (`routineId: nil`).
    private func startMobilityOneOff() {
        guard let t = StarterTemplates.byID("mobility") else { return }
        let name = String(localized: "Mobility")
        let (_, exercises) = t.makeRoutine(name: name, now: Int(Date().timeIntervalSince1970))
        let slots = exercises.map {
            StrengthSessionModel.PlanSlot(re: $0, exercise: ExerciseCatalog.byID($0.exerciseId), lastSets: [])
        }
        model.startStrengthSession(routineId: nil, routineName: name, slots: slots)
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

    /// Local day-starts with ≥1 completed session — the lookup the daily streak reads.
    private var completedDayStarts: Set<Date> {
        let cal = Calendar.current
        var out = Set<Date>()
        for s in sessions where s.endTs != nil {
            out.insert(cal.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(s.startTs))))
        }
        return out
    }

    /// «Días cumpliendo el plan» over a bounded trailing window (oldest → newest, last = today). A day is a
    /// training day if the CURRENT split assigns its weekday, trained if a session completed that day. The
    /// window only bounds the loop — the streak itself stops at the most recent missed training day.
    private static let streakWindowDays = 120
    private var adherenceStates: [WeeklySplit.DayAdherence] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let done = completedDayStarts
        var plans: [WeeklySplit.DayPlan] = []
        plans.reserveCapacity(Self.streakWindowDays)
        for offset in stride(from: Self.streakWindowDays - 1, through: 0, by: -1) {
            guard let day = cal.date(byAdding: .day, value: -offset, to: today) else { continue }
            let wd = cal.component(.weekday, from: day)
            plans.append(.init(isTrainingDay: split[wd] != nil, trained: done.contains(day)))
        }
        return WeeklySplit.dailyAdherence(days: plans, includesToday: true)
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
        var counts: [String: Int] = [:]
        for r in rs { counts[r.id] = (try? await store.routineExercises(routineId: r.id))?.count ?? 0 }
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
        split = splitMap
        todaySlots = slots
        sessions = (try? await store.recentSessions(limit: 200)) ?? []
        loaded = true
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

// MARK: - Honest «coming soon» sheet (for builder/guided start — FER-346 / FER-347)

/// A quiet Instrumento sheet that names what's coming, instead of a dead button.
struct TrainingSoonSheet: View {
    @Environment(\.instrumentoTheme) private var theme
    let overline: LocalizedStringKey
    let title: LocalizedStringKey
    let message: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
            VStack(alignment: .leading, spacing: 4) {
                Text(overline).instrumentoOverline().foregroundStyle(theme.inkTertiary)
                Text(title).font(StrandFont.title1).foregroundStyle(theme.ink)
            }
            Text(message).font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(NoopMetrics.screenPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.paper.ignoresSafeArea())
    }
}
#endif
