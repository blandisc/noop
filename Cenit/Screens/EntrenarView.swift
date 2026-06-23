#if os(iOS)
import SwiftUI
import StrandDesign
import StrandTraining
import StrandAnalytics

// MARK: - Entrenar (the Train tab root) — «Entrenar v2 · La Semana» (FER-534, épico FER-530)
//
// The Train landing as a PLANNER in the light «Instrumento diurno» language (warm paper, color only on
// the datum, hierarchy by space). The week is the spine: a recovery chip + a 7-day strip, today's
// session behind a single «Empezar» door, the split («Tu plan»), and a consistency card — all resolved
// from the weekly split (FER-531) and the completed-session history.
//
// Color appears ONLY on the recovery datum (the chip ring/numeral, the today-dot, the Today recovery
// line, the consistency bars); everything else is ink on paper. «Empezar» is the one door to training:
// it opens a session-type chooser (routine / intervals / breathe / live).
//
// Navigation is owned by the tab's `NavigationStack` in RootTabView; the landing pushes via the injected
// closures (routine, library, breathe, intervals, history, the weekly-plan editor F2, «Mis rutinas», and
// a completed session's detail). The guided session sheet is hosted here so it survives tab switches.

struct EntrenarView: View {
    var openRoutine: (String) -> Void
    var openLibrary: () -> Void
    var openBreathe: () -> Void
    var openIntervals: () -> Void
    var openDiet: () -> Void
    /// Push «Mis entrenamientos» (the completed-session history, FER-504).
    var openHistory: () -> Void
    /// Push the weekly plan editor (FER-533) — opened from «Tu plan · Editar» and the empty state.
    var openWeeklyPlan: () -> Void
    /// Push a completed strength session's detail (from a «done» day in the week strip).
    var openWorkoutSession: (WorkoutSessionRoute) -> Void

    var body: some View {
        EntrenarLanding(openRoutine: openRoutine, openLibrary: openLibrary,
                        openBreathe: openBreathe, openIntervals: openIntervals, openDiet: openDiet,
                        openHistory: openHistory, openWeeklyPlan: openWeeklyPlan,
                        openWorkoutSession: openWorkoutSession)
            .instrumentoTheme(.base)
    }
}

private struct EntrenarLanding: View {
    @EnvironmentObject var repo: Repository
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var tabRouter: TabRouter
    @Environment(\.instrumentoTheme) private var theme

    var openRoutine: (String) -> Void
    var openLibrary: () -> Void
    var openBreathe: () -> Void
    var openIntervals: () -> Void
    var openDiet: () -> Void
    var openHistory: () -> Void
    var openWeeklyPlan: () -> Void
    var openWorkoutSession: (WorkoutSessionRoute) -> Void

    @State private var loaded = false
    @State private var routines: [Routine] = []
    @State private var exerciseCounts: [String: Int] = [:]
    /// The weekly split, `weekday → routineId` (Calendar convention, 1 = Sun … 7 = Sat). FER-531.
    @State private var split: [Int: String] = [:]
    /// Completed strength sessions (newest first), for the strip's day states and the consistency streak.
    @State private var sessions: [StrengthSession] = []
    /// Drives the «Empezar» session-type chooser.
    @State private var showChooser = false
    /// What the chooser picked — performed on its dismiss, so we never stack two sheets.
    @State private var pendingStart: StartKind? = nil
    /// Drives the live-workout sheet (the chooser's «En vivo»).
    @State private var showLive = false
    /// «Import plan» (FER-496) from «Tu plan»'s footer.
    @State private var showImport = false
    /// Drives the templates sheet opened straight on the mobility routine from the ④ «softer» suggestion (FER-554).
    @State private var showMobilityTemplate = false
    /// Drives the Recovery Detail sheet opened from the recovery chip (FER-557).
    @State private var recoveryDetail: RecoveryDetailItem? = nil

    private enum StartKind { case routine, intervals, breathe, live }

    /// Monday-first display order in the Calendar weekday convention.
    private let orderedWeekdays = [2, 3, 4, 5, 6, 7, 1]
    private var todayWeekday: Int { Calendar.current.component(.weekday, from: Date()) }
    private var recovery: Double? { repo.today?.recovery }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                header
                if loaded {
                    if split.isEmpty {
                        emptyStateB
                    } else {
                        if model.strengthSession != nil { resumeRow }
                        weekStrip
                        hoyCard
                        suggestionRow
                        tuPlan
                        consistencia
                    }
                }
            }
            .padding(.top, 20)
            .padding(.horizontal, NoopMetrics.screenPadding)
            .padding(.bottom, NoopMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.paper.ignoresSafeArea())
        // The «Empezar» chooser. Its choice is performed on dismiss so a push/live-sheet never races the
        // chooser's own dismissal.
        .sheet(isPresented: $showChooser, onDismiss: performPendingStart) {
            chooserSheet
                .presentationDetents([.height(360)])
                .presentationDragIndicator(.visible)
                .presentationBackground(theme.paper)
                .preferredColorScheme(.light)
        }
        // «Import plan» (FER-496) from «Tu plan».
        .sheet(isPresented: $showImport) {
            WorkoutImportView { await load() }
                .instrumentoTheme(theme).environmentObject(repo).preferredColorScheme(.light)
        }
        // The ④ «softer» suggestion (FER-554) opens the templates sheet straight on the mobility routine —
        // selectable/startable like any other template. Theme doesn't cross the sheet boundary (FER-190).
        .sheet(isPresented: $showMobilityTemplate) {
            StarterTemplatesSheet(initialSelection: StarterTemplates.byID("mobility")) { await load() }
                .instrumentoTheme(theme).environmentObject(repo).preferredColorScheme(.light)
        }
        // Live workout (the chooser's «En vivo»).
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

    // MARK: - ① Header + recovery chip

    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            // One-piece wordmark row — same lockup, size and baseline as «Tendencias»/«Patrones» so the
            // three tab titles match. Glyph = the dock's tab icon; trailing = the recovery chip. (FER-557)
            HStack(alignment: .center) {
                HStack(spacing: 9) {
                    Image(systemName: "figure.strengthtraining.functional")
                        .font(.system(size: 19)).frame(width: 22, height: 22).foregroundStyle(theme.ink)
                    Text("Train").font(.system(size: 21, weight: .semibold)).tracking(-0.3).foregroundStyle(theme.ink)
                }
                .accessibilityElement(children: .combine).accessibilityLabel(Text("Train"))
                Spacer(minLength: 8)
                if let rec = recovery { recoveryChip(rec) }   // hidden while calibrating (no score)
            }
            // Cadence as a quiet context line below the wordmark (not stacked inside the lockup).
            if let cadence = cadenceText {
                Text(cadence).instrumentoOverline().foregroundStyle(theme.inkTertiary)
            }
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

    // MARK: - ② Week strip

    private var weekStrip: some View {
        let states = WeeklySplit.weekStates(split: split, completedWeekdays: completedWeekdays,
                                            todayWeekday: todayWeekday, orderedWeekdays: orderedWeekdays)
        return card {
            HStack {
                Text("Your week").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                Spacer()
                Text(weekProgressText).font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
            }
            HStack(spacing: 6) {
                ForEach(states, id: \.weekday) { st in dayToken(st) }
            }
            .padding(.top, 13)
            Text("Tap a done day to see that session")
                .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                .padding(.top, 11)
        }
    }

    private func dayToken(_ st: WeeklySplit.DayStatus) -> some View {
        let initial = split[st.weekday].flatMap { routinesById[$0]?.name }.map { String($0.prefix(1)).uppercased() } ?? ""
        return VStack(spacing: 6) {
            Text(weekdayLetter(st.weekday)).font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
            tokenBody(st, initial: initial)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { if st.state == .done { openSession(st.weekday) } }
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

    // MARK: - ③ Today + «Empezar» (the single door)

    private var hoyCard: some View {
        card {
            Text(hoyOverline).instrumentoOverline().foregroundStyle(theme.inkTertiary)
            if let r = todayRoutine {
                Text(r.name).font(StrandFont.title2).foregroundStyle(theme.ink).padding(.top, 3)
                Text(exerciseCountText(exerciseCounts[r.id] ?? 0))
                    .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary).padding(.top, 2)
            } else {
                Text("Rest").font(StrandFont.title2).foregroundStyle(theme.inkSecondary).padding(.top, 3)
                Text("Your plan doesn't schedule today. A good day to recover.")
                    .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary).padding(.top, 2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let rec = recovery {
                Divider().overlay(theme.hairline).padding(.vertical, 14)
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Circle().fill(theme.dataRecovery).frame(width: 8, height: 8)
                    Text(recoveryLine(rec)).font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            empezarButton.padding(.top, 15)
            Text("routine · intervals · breathe · live — you choose when you start")
                .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                .frame(maxWidth: .infinity, alignment: .center).padding(.top, 7)
        }
    }

    private var empezarButton: some View {
        Button { showChooser = true } label: {
            Text("Empezar")
                .font(StrandFont.headline)
                .foregroundStyle(todayRoutine != nil ? theme.paperHi : theme.ink)
                .frame(maxWidth: .infinity).padding(.vertical, 15)
                .background {
                    let s = RoundedRectangle(cornerRadius: 13, style: .continuous)
                    // A rest day doesn't push you: the door stays open but quiet (outline, not filled).
                    if todayRoutine != nil { s.fill(theme.ink) } else { s.strokeBorder(theme.hairlineStrong, lineWidth: 1) }
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: - ④ Suggestion (engine is FER-532 — TrainingRegulation.lightAlternative)
    //
    // A CONTEXTUAL lighter alternative, derived from today's recovery against your personal baseline
    // (same input the recovery line uses). It appears ONLY when there is something to suggest — recovery
    // below normal → a gentler option, above normal → an optional add-on — and HIDES within the normal
    // band or with no signal. Always advisory: it never blocks training, «tú decides».

    @ViewBuilder private var suggestionRow: some View {
        if let alt = TrainingRegulation.lightAlternative(recovery: recovery) {
            Button { suggestionAction(alt) } label: {
                HStack(spacing: 11) {
                    Image(systemName: suggestionIcon(alt)).font(.system(size: 17)).foregroundStyle(theme.inkTertiary)
                    Text(suggestionLabel(alt))
                        .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.inkDim)
                }
                .padding(.horizontal, 15).padding(.vertical, 13)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 3])).foregroundStyle(theme.hairlineStrong))
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

    // MARK: - ⑤ Tu plan

    private var tuPlan: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Your plan").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                Spacer()
                Button { openWeeklyPlan() } label: {
                    Text("Edit").font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                }
                .buttonStyle(.plain)
            }
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
                Divider().overlay(theme.hairline).padding(.top, 4)
                HStack(spacing: 8) {
                    planChip("Library", "book", action: openLibrary)
                    planChip("Import", "square.and.arrow.down") { showImport = true }
                    planChip("Diet", "fork.knife", tag: "for now", action: openDiet)
                }
                .padding(.top, 12)
            }
        }
    }

    private func planChip(_ title: LocalizedStringKey, _ icon: String, tag: LocalizedStringKey? = nil,
                          action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 12)).foregroundStyle(theme.inkSecondary)
                Text(title).font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
                if let tag { Text(tag).font(StrandFont.footnote).foregroundStyle(theme.inkDim) }
            }
            .padding(.horizontal, 11).padding(.vertical, 6)
            .overlay(Capsule().strokeBorder(theme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - ⑥ Consistency

    private var consistencia: some View {
        Button { openHistory() } label: {
            card {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(streakWeeksText).font(StrandFont.title2).foregroundStyle(theme.ink)
                        Text("active streak · see full history")
                            .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                    }
                    Spacer(minLength: 8)
                    consistencyBars
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var consistencyBars: some View {
        let bars = weeklyVolumeBars
        let peak = max(bars.max() ?? 1, 1)
        return HStack(alignment: .bottom, spacing: 4) {
            ForEach(Array(bars.enumerated()), id: \.offset) { _, v in
                Capsule().fill(theme.dataRecovery)
                    .opacity(0.35 + 0.6 * (Double(v) / Double(peak)))
                    .frame(width: 7, height: max(6, 34 * CGFloat(v) / CGFloat(peak)))
            }
        }
        .frame(height: 34)
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

    // MARK: - «Empezar» chooser

    private var chooserSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Empezar").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            Text("What are you training?").font(StrandFont.title2).foregroundStyle(theme.ink).padding(.top, 2)
            chooserOption("dumbbell", "Routine", subtitle: todayRoutine?.name, isDefault: true) { pick(.routine) }
            chooserOption("timer", "Intervals", subtitle: nil) { pick(.intervals) }
            chooserOption("wind", "Breathe", subtitle: nil) { pick(.breathe) }
            chooserOption("dot.radiowaves.left.and.right", "Live", subtitle: nil) { pick(.live) }
            Spacer(minLength: 0)
        }
        .padding(NoopMetrics.screenPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.paper)
    }

    private func chooserOption(_ icon: String, _ title: LocalizedStringKey, subtitle: String?, isDefault: Bool = false,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Image(systemName: icon).font(.system(size: 20)).foregroundStyle(theme.inkSecondary).frame(width: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(StrandFont.headline).foregroundStyle(theme.ink)
                    if let subtitle { Text(subtitle).font(StrandFont.caption).foregroundStyle(theme.inkTertiary) }
                }
                Spacer(minLength: 8)
                if isDefault {
                    Text("Default").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .overlay(Capsule().strokeBorder(theme.hairlineStrong, lineWidth: 1))
                } else {
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.inkDim)
                }
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
        case .routine:   if let id = todayRoutineId { openRoutine(id) }
        case .intervals: openIntervals()
        case .breathe:   openBreathe()
        case .live:      if model.activeWorkout == nil { model.startWorkout() }; showLive = true
        }
    }

    // MARK: - Card shell + bits

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0, content: content)
            .padding(NoopMetrics.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous).strokeBorder(theme.hairline, lineWidth: 1))
    }

    private func exerciseCountText(_ n: Int) -> String { String(localized: "\(n) exercises") }

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

    private func openSession(_ weekday: Int) {
        guard let s = completedThisWeek[weekday] else { return }
        let name = s.routineId.flatMap { routinesById[$0]?.name } ?? String(localized: "Workout")
        openWorkoutSession(WorkoutSessionRoute(id: s.id, startTs: s.startTs, endTs: s.endTs,
                                               strain: s.strain, avgHr: s.avgHr, routineName: name))
    }

    /// Completed-session counts per week, oldest → newest, for the last 12 weeks (index 11 = this week).
    private var weeklyCounts: [Int] {
        var counts = Array(repeating: 0, count: 12)
        for s in sessions where s.endTs != nil {
            let date = Date(timeIntervalSince1970: TimeInterval(s.startTs))
            let weeksAgo = (weekCalendar.dateComponents([.day], from: weekStart(date), to: thisWeekStart).day ?? 0) / 7
            if weeksAgo >= 0 && weeksAgo < 12 { counts[11 - weeksAgo] += 1 }
        }
        return counts
    }
    private var weeklyVolumeBars: [Int] { Array(weeklyCounts.suffix(8)) }
    private var streak: Int {
        WeeklySplit.consistencyStreak(weeklyCompletedCounts: weeklyCounts, currentAssignedCount: split.count,
                                      includesCurrentWeek: true)
    }

    /// Header cadence line — how many days a week the split trains. One line, not the (long) list of
    /// routine names; the names live in «Tu plan» and «Hoy». `nil` when there's no split. (FER-557)
    private var cadenceText: String? {
        let n = split.keys.count
        guard n > 0 else { return nil }
        return n == 1 ? String(localized: "1 day a week") : String(localized: "\(n) days a week")
    }

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
    private var weekProgressText: String {
        let planned = Set(split.keys)
        let done = planned.intersection(completedWeekdays).count
        return String(localized: "\(done) of \(planned.count) done")
    }
    private var streakWeeksText: String { String(localized: "\(streak) weeks") }

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
        routines = rs
        exerciseCounts = counts
        split = Dictionary(sched.map { ($0.weekday, $0.routineId) }, uniquingKeysWith: { a, _ in a })
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

// MARK: - Recovery band (the «sube / mantén / baja» autoregulation suggestion — FER-349)

/// The recovery band: an OPT-IN "push / hold / ease" suggestion driven by the cited `TrainingRegulation`
/// rule (StrandAnalytics). Kept as a reusable component (the «La Semana» landing now shows a compact
/// recovery line instead). It never appears without a recovery score.
struct RecoveryBand: View {
    @Environment(\.instrumentoTheme) private var theme
    let recovery: Double

    private var suggestion: TrainingRegulation.Suggestion? { TrainingRegulation.suggest(recovery: recovery) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Today's load").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            if let s = suggestion {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(word(s.adjustment)).font(StrandFont.title2).foregroundStyle(color(s.adjustment))
                    Text(detail(s.reason)).font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 5) {
                    Image(systemName: "info.circle").font(.system(size: 12)).foregroundStyle(theme.inkTertiary).accessibilityHidden(true)
                    Text("Suggestion · you decide").font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                }
                .padding(.top, 4)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func word(_ a: TrainingRegulation.Adjustment) -> LocalizedStringKey {
        switch a { case .dialUp: return "Push"; case .hold: return "Hold"; case .dialBack: return "Ease" }
    }
    private func color(_ a: TrainingRegulation.Adjustment) -> Color {
        switch a { case .dialUp: return theme.verdict; case .hold: return theme.ink; case .dialBack: return theme.warning }
    }
    private func detail(_ reason: TrainingRegulation.Reason) -> String {
        switch reason {
        case .recoveryHigh:  return String(localized: "Your recovery is high for you. A good day to add weight or sets.")
        case .withinNormal:  return String(localized: "Your recovery is in your normal range. Train at your usual load.")
        case .recoveryLow:   return String(localized: "Your recovery is low for you. Easing the volume or intensity helps today.")
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
