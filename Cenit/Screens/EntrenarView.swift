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
    @State private var loadFailed = false   // store couldn't be read — a real error, NOT «no plan yet»
    @State private var routines: [Routine] = []
    @State private var exerciseCounts: [String: Int] = [:]
    /// Exercises whose earned raise seeds today's session (FER-G): name + proposed kg for the hero's «Hoy subes» line.
    @State private var raisesToday: [(name: String, kg: Double)] = []
    /// Exercises whose earned raise is deferred by low recovery today (gate copy in the hero).
    @State private var deferredToday: [String] = []
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    private var unitSystem: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }
    /// Top primary muscles per routine (Spanish display labels), built from the same per-routine exercise
    /// fetch that feeds `exerciseCounts` — drives the hero muscle line and the «También en tu plan» subtitles.
    @State private var routineMuscles: [String: [String]] = [:]
    /// The classified training region per routine id (`RoutineClassifier`, FER-775), built from the same
    /// per-routine exercise fetch as `routineMuscles`. Drives every routine-tinted mark (hero dot, plan
    /// dots + «Empezar» pills, Constancia grid). Absent = no classifiable exercises → default hue.
    @State private var routineCategory: [String: RoutineRegion] = [:]
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
    /// Presents the live-HR workout sheet from the «Formas de entrenar» → «En vivo» chip (same sheet the
    /// rest-day / other-ways screens use).
    @State private var showLive = false
    /// The Constancia day currently popped open (tap-to-reveal what you trained that day).
    @State private var constancyPopup: ConstancyPopup? = nil
    /// Presents the starter-templates list from the first-use «Rutinas de plantilla» row (mock 5a).
    @State private var showTemplates = false

    /// Monday-first display order in the Calendar weekday convention.
    private let orderedWeekdays = [2, 3, 4, 5, 6, 7, 1]
    private var todayWeekday: Int { Calendar.current.component(.weekday, from: Date()) }
    private var recovery: Double? { repo.today?.recovery }

    var body: some View {
        // Fixed section rhythm in a plain ScrollView (FER-786 hotfix): the earlier GeometryReader +
        // `.frame(minHeight: geo.size.height)` + flexible/capped spacers (FER-784/785) fed the measured
        // height back into layout and looped as the plan grew — 99% CPU, «Invalid frame dimension», freeze.
        // `sectionGap` (28) still gives more air between blocks than the old 18; no measured-height feedback.
        ScrollView {
            VStack(alignment: .leading, spacing: CenitMetrics.sectionGap) {
                header
                if loaded {
                    if loadFailed {
                        loadErrorState       // store couldn't be read — «No pudimos leer tus rutinas · Reintentar»
                    } else if split.isEmpty {
                        emptyStateB          // hero «Empecemos por tu plan» + «Crear mi plan» (mock 5a)
                        plantillaRow         // «O empieza sin plan» → Rutinas de plantilla (the one kept row)
                        formasDiscos         // the five training discs (same doors as the planned state)
                        constanciaSection    // empty Constancia — «tus sesiones aparecerán aquí»
                        footRows
                    } else {
                        // Handoff v4b order (FER-939): open hero + discs up top, then the sunken-band
                        // sections (session · plan · consistency), then the quiet foot rows.
                        heroSection       // ① open hero «Hoy · {día}» + «Empezar» + the five discs
                        suggestionRow     // ② contextual FER-532 nudge (shown only when the engine fires)
                        sesionDeHoy       // ③ «LA SESIÓN DE HOY» — big numerals + raise + recovery hint
                        tuPlanSection     // ④ «TU PLAN» — week squares + every routine + new-routine row
                        constanciaSection // ⑤ 90-day dot grid — no streak guilt (mock 1a)
                        footRows          // ⑥ history + diet
                    }
                }
            }
            .padding(.top, CenitMetrics.screenTop)   // shared titled-tab top inset
            .padding(.horizontal, CenitMetrics.screenPadding)
            .padding(.bottom, CenitMetrics.screenPadding)
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
        // First-use «Rutinas de plantilla» (mock 5a): the grouped templates list. «Add to my routines»
        // is the only action here (no `onStart`), so a copy lands in «My routines» and the landing
        // reloads out of the empty state on dismiss.
        .sheet(isPresented: $showTemplates) {
            StarterTemplatesSheet { await load() }
                .instrumentoTheme(theme).environmentObject(repo).preferredColorScheme(.light)
        }
        // Recovery detail from the chip — same sheet Today/Cuerpo open; theme passed explicitly (it
        // doesn't cross the `.sheet` boundary, FER-162), no nested NavigationStack (FER-171). (FER-557)
        .sheet(item: $recoveryDetail) { item in
            RecoveryDetailScreen(theme: theme, model: item.model)
        }
        // «En vivo» from the expanded «Más formas» pill — the live-HR free workout, same sheet the
        // rest-day / other-ways screens present (theme passed explicitly; it doesn't cross `.sheet`).
        .sheet(isPresented: $showLive) {
            LiveWorkoutSheet(theme: theme)
                .environmentObject(model)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(theme.paper)
                .preferredColorScheme(.light)
        }
        // The guided strength session (FER-347) is now presented at the shell (`RootTabView`) as a
        // full-screen cover with a floating pill on all five tabs (FER-716), so it survives tab switches
        // and no longer needs a «Resume» row here. The session lives in AppModel.
        .task { await load() }
        // The Daily Brief's «Hoy en tu plan» → «Empezar» lands here via TabRouter: start today's session
        // reusing the slots this view prefetched on load (FER-613). Consumed once; if we're not loaded yet,
        // defer until `load()` finishes.
        .onAppear {
            if tabRouter.startTodaySession { consumeBriefStart() }
            // Refresh the plan when returning (e.g. from «Editar» / the weekly plan editor): the initial
            // `.task` doesn't re-run on a NavigationStack pop, so edits wouldn't reflect otherwise (FER-787).
            if loaded { Task { await load() } }
        }
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
                .font(.system(size: 20)).foregroundStyle(theme.ink)  // token-exempt: glifo 20pt fuera de banda lead
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
        .accessibilityLabel(Text("Recuperación \(Int(rec.rounded())). Ver detalle."))
    }

    // MARK: - ① Open hero + «Empezar» + discs (handoff v4b, FER-939)
    //
    // The hero sits OPEN on the paper — no card, no border. Hierarchy by space (Instrumento): the
    // routine name is the dominant datum (Grotesk 32, handoff spec), the meta/recovery/raise detail
    // moves down to its own «LA SESIÓN DE HOY» band, and the five training discs ride directly under
    // «Empezar» as the screen's second decision (FER-920 decision #1, applied here).

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(hoyOverline)
                .font(InstrumentoType.groteskSheetTitle).tracking(InstrumentoType.groteskSheetTitleTracking)
                .textCase(.uppercase).foregroundStyle(theme.inkTertiary)
            if let r = todayRoutine {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)  // token-exempt: geometría de dato
                        .fill(routineFill(region(name: r.name))).frame(width: 12, height: 12)
                        .alignmentGuide(.firstTextBaseline) { d in d[.bottom] - 1 }
                    Text(r.name)
                        .font(InstrumentoType.grotesk(32, weight: .bold)).tracking(-1)
                        .foregroundStyle(theme.ink)
                        .lineLimit(2).minimumScaleFactor(0.65)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 8)
                if let muscles = routineMuscleLine(r.id) {
                    Text(muscles).font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                        .padding(.top, 4)
                }
            } else {
                Text("Rest")
                    .font(InstrumentoType.grotesk(32, weight: .bold)).tracking(-1)
                    .foregroundStyle(theme.inkSecondary)
                    .padding(.top, 8)
                Text("Your plan doesn't schedule today. A good day to recover.")
                    .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
            empezarButton.padding(.top, 14)
            formasDiscos.padding(.top, 12)
        }
    }

    /// The handoff's per-routine tint (mock 1a). The family is derived from the routine's exercises'
    /// `primaryMuscles` via the shared `RoutineClassifier` (FER-775) — never guessed from the name or a
    /// per-process hash, so a routine keeps the same color across launches. The flow colors coincide with
    /// existing Instrumento data tokens, so we reuse them: push → `dataStrain` (ember), pull → `dataHrv`
    /// (teal), leg / full body → `dataSleep` (indigo). A routine with no classifiable exercises (cardio,
    /// «Rápido» without a routine) falls back to `dataStrain`, the screen's default hue. Used for the SOLID
    /// marks (text, borders); full body reads as indigo here and only becomes a gradient in `routineFill`.
    private func routineTint(_ region: RoutineRegion?) -> Color {
        return region.tint(theme)
    }

    /// The FILL for a routine's dot/square. Same as `routineTint` except full body reads as the mock's
    /// 135° ember→indigo gradient (its whole point is that it spans the split).
    private func routineFill(_ region: RoutineRegion?) -> AnyShapeStyle {
        if region == .fullBody {
            return AnyShapeStyle(LinearGradient(colors: [theme.dataStrain, theme.dataSleep],
                                                startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        return AnyShapeStyle(routineTint(region))
    }

    /// The classified region for a routine name — the hero, plan rows and Constancia grid all key
    /// their tinted marks by the routine's name (that's what completed sessions record), so resolve the
    /// name back to its routine's precomputed category. `nil` (unknown / unclassifiable) → default hue.
    private func region(name: String) -> RoutineRegion? {
        guard let id = routines.first(where: { $0.name == name })?.id else { return nil }
        return routineCategory[id]
    }

    /// Rough time estimate for the session's shape line («LA SESIÓN DE HOY»): a transparent
    /// approximation (planned sets × ~40 s work + the slot's rest), rounded to 5 min — a glance, not a clock.
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
    /// The CTA verb: a live session in progress makes this «Continuar» (tapping re-opens it — `startToday`
    /// ends in `startStrengthSession`, whose guard re-presents the existing session, AppModel), otherwise
    /// «Empezar». Spanish literals, matching the rest of this screen.
    private var empezarLabel: LocalizedStringKey { model.strengthSession != nil ? "Continuar" : "Empezar" }

    /// Re-open the live session if one is running (any day, incl. rest days), otherwise start today's.
    private func startOrResume() {
        if model.strengthSession != nil { model.resumeStrengthSession() } else { startToday() }
    }

    @ViewBuilder private var empezarButton: some View {
        if todayRoutine != nil {
            tintedEmpezarButton
        } else {
            StrandCTAButton(empezarLabel, kind: .outline) { startOrResume() }
        }
    }

    /// Routine-day CTA: same chrome as `StrandCTAButton` solid, but fill uses the routine's region tint
    /// instead of `theme.ink` (shared component stays ink-only for other screens).
    private var tintedEmpezarButton: some View {
        let tint = routineTint(region(name: todayRoutine?.name ?? ""))
        return Button(action: startOrResume) {
            Text(empezarLabel)
                .font(InstrumentoType.grotesk(15, weight: .bold))
                .tracking(0.3)
                .foregroundStyle(theme.paperHi)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(
                    RoundedRectangle(cornerRadius: CenitMetrics.ctaRadius, style: .continuous)
                        .fill(tint)
                )
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


    /// «Entrenamiento rápido de fuerza» (mock 1p, FER-762): no routine, no slots — the session starts
    /// empty and `LiveStrengthSheet` shows its own empty-state (search + freshness suggestions) until the
    /// first exercise is added.
    private func startQuickStrength() {
        model.startStrengthSession(routineId: nil, routineName: String(localized: "Quick strength"), slots: [])
    }

    // MARK: - Sunken section band (handoff v4b: every section opens with a full-bleed sunken strip)

    /// The handoff's section header: an uppercase overline on a full-bleed sunken strip (`patternBlock`),
    /// with an optional trailing action. The negative padding undoes the screen inset so the band runs
    /// edge to edge; the inner padding restores the text to the 24pt margin.
    private func sectionBand<T: View>(_ title: LocalizedStringKey,
                                      @ViewBuilder trailing: () -> T) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(InstrumentoType.grotesk(11, weight: .semibold)).tracking(1.4)
                .textCase(.uppercase).foregroundStyle(theme.inkSecondary)
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, CenitMetrics.screenPadding)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.patternBlock)
        .padding(.horizontal, -CenitMetrics.screenPadding)
    }

    private func sectionBand(_ title: LocalizedStringKey) -> some View {
        sectionBand(title) { EmptyView() }
    }

    // MARK: - ③ «LA SESIÓN DE HOY» (handoff v4b: the day's detail in its own band section)
    //
    // Big Grotesk numerals for the session's shape (min · exercises · sets), the earned raise as the
    // green line (FER-G — it lives where you start), and the recovery hint on a thin green filete.
    // Rest days and empty routines skip the whole section — nothing to detail.

    @ViewBuilder private var sesionDeHoy: some View {
        if let r = todayRoutine {
            VStack(alignment: .leading, spacing: 12) {
                sectionBand("The session today")
                sesionMetrics(r.id)
                if !raisesToday.isEmpty {
                    Button { openRoutine(r.id) } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            StrandIcon.up.image
                                .font(StrandFont.glyph(.chevron, weight: .bold)).foregroundStyle(theme.dataRecovery)
                            raiseText
                                .font(StrandFont.subhead).foregroundStyle(theme.ink)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                            StrandIcon.disclosure.image
                                .font(StrandFont.glyph(.chevron, weight: .semibold)).foregroundStyle(theme.inkTertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else if !deferredToday.isEmpty {
                    Text("The raise for \(deferredToday.joined(separator: ", ")) waits for your next session.")
                        .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if recovery != nil {
                    HStack(spacing: 7) {
                        Rectangle().fill(theme.dataRecovery).frame(width: 2, height: 10)  // token-exempt: filete de dato
                        Text(recoveryLine(recovery ?? 0))
                            .font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    /// «~50 min · 6 ejercicios · 18 series» — each numeral big (Grotesk 20), its unit word quiet.
    private func sesionMetrics(_ rid: String) -> some View {
        let sets = todaySlots.reduce(0) { $0 + max(0, $1.re.targetSets) }
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            if estMinutes > 0 {
                bigStat(Text(verbatim: "~\(estMinutes)"), unit: Text("min"))
                dotSeparator
            }
            bigStat(Text(verbatim: "\(exerciseCounts[rid] ?? 0)"), unit: Text("exercises"))
            if sets > 0 {
                dotSeparator
                bigStat(Text(verbatim: "\(sets)"), unit: Text("sets"))
            }
        }
    }

    private func bigStat(_ value: Text, unit: Text) -> Text {
        value.font(InstrumentoType.groteskNumber(20)).foregroundStyle(theme.ink)
            + Text(verbatim: " ")
            + unit.font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
    }

    private var dotSeparator: Text {
        Text(verbatim: "·").font(StrandFont.caption).foregroundStyle(theme.inkDim)
    }

    /// «Hoy subes Press banca · 82,5 kg y Press militar · 26 kg» — the names+loads in the raise green.
    private var raiseText: Text {
        let parts = raisesToday.map { "\($0.name) · \(UnitFormatter.massFromKilograms($0.kg, system: unitSystem))" }
        let strong = parts.map {
            Text(verbatim: $0).font(InstrumentoType.grotesk(13, weight: .bold)).foregroundStyle(theme.dataRecovery)
        }
        var t = Text("Today you raise") + Text(verbatim: " ")
        for (i, s) in strong.enumerated() {
            if i > 0 { t = t + Text(verbatim: " · ") }
            t = t + s
        }
        return t
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
                    Image(systemName: suggestionIcon(alt)).font(StrandFont.glyph(.lead)).foregroundStyle(theme.inkSecondary)
                    Text(suggestionLabel(alt)).font(StrandFont.subhead).foregroundStyle(theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    StrandIcon.disclosure.image.font(StrandFont.glyph(.chevron, weight: .semibold)).foregroundStyle(theme.inkTertiary)
                }
                .padding(.horizontal, 15).padding(.vertical, 13)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: CenitMetrics.ctaRadius, style: .continuous)
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

    private var tuPlanSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionBand("Your plan") {
                Button { openWeeklyPlan() } label: {
                    Text("Edit week").font(StrandFont.subhead).foregroundStyle(theme.ink)
                }
                .buttonStyle(.plain)
            }
            weekStrip
            // Handoff v4b: EVERY routine lists here (today's included — its «↗ N suben» badge is the
            // reason it earns a row beyond the hero). Reversal of the earlier hero-only decision (FER-939).
            ForEach(planRows, id: \.routineId) { row in
                planRoutineRow(row)
            }
            nuevaRutinaRow
        }
    }

    /// «＋ Nueva rutina · plantillas · importar» — one quiet row into the weekly plan editor, where
    /// creating, templates and import all live.
    private var nuevaRutinaRow: some View {
        Button { openWeeklyPlan() } label: {
            HStack(spacing: 10) {
                Text(verbatim: "＋").font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                Text("New routine · templates · import")
                    .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                Spacer(minLength: 8)
            }
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Mon→Sun strip of the weekly split under «Also in your plan»: one equal cell per weekday, tinted
    /// when a routine is assigned, muted on rest days, and today marked with the same ring language as
    /// Constancia. Tapping an assigned day opens that routine.
    private var weekStrip: some View {
        HStack(spacing: 0) {
            ForEach(orderedWeekdays, id: \.self) { wd in
                weekStripCell(wd)
            }
        }
        .padding(.vertical, CenitMetrics.space2)
    }

    @ViewBuilder
    private func weekStripCell(_ wd: Int) -> some View {
        let routineId = split[wd]
        let region = routineId.flatMap { routineCategory[$0] }
        let isToday = wd == todayWeekday
        let hasRoutine = routineId != nil
        // Handoff v4b: 26pt rounded squares. A day already trained this week fills with that session's
        // routine tint and takes a paper check; today is a paper square ringed in its routine's tint;
        // an assigned future day keeps its tinted letter over the wash; a rest day is just wash.
        let doneTint = trainedThisWeek(wd).map { routineTint(self.region(name: $0)) }   // `region` local shadows the func
        let cell = VStack(spacing: 5) {
            Text(weekdayLetter(wd))
                .font(InstrumentoType.grotesk(10, weight: .semibold))
                .foregroundStyle(isToday ? theme.ink : (hasRoutine ? routineTint(region) : theme.inkTertiary))
            ZStack {
                if let doneTint {
                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(doneTint)
                    StrandIcon.confirm.image
                        .font(StrandFont.glyph(.chevron, weight: .semibold)).foregroundStyle(theme.paper)
                } else if isToday {
                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.surface)
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(todayRingTint, lineWidth: 1.5)
                } else {
                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.patternBlock)
                }
            }
            .frame(width: 26, height: 26)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())

        if let routineId {
            Button { openRoutine(routineId) } label: { cell }
                .buttonStyle(.plain)
        } else {
            cell
        }
    }

    // MARK: - «Formas de entrenar» — the six training doors, always visible at the foot (FER-787)
    //
    // No longer a collapsible button (FER-783): the six doors sit as a permanent icon row below Constancia,
    // at the foot of the screen. Color still lands ONLY on the datum (each icon's data-token tint over
    // paper), so no raw hex or new tokens.

    private struct FormOption: Identifiable {
        let icon: String
        let label: LocalizedStringKey
        let tint: Color
        let action: () -> Void
        var id: String { icon }
    }

    /// The five training doors in the icon grid. Diet sits as a quiet full-width row below (not a chip).
    private var formOptions: [FormOption] {
        [
            FormOption(icon: "bolt", label: "Quick", tint: theme.dataStrain) { startQuickStrength() },
            FormOption(icon: "dot.radiowaves.left.and.right", label: "Live", tint: theme.dataHeart) { startLive() },
            FormOption(icon: "timer", label: "Interval", tint: theme.dataSleep) { openIntervals() },
            FormOption(icon: "figure.flexibility", label: "Mobility", tint: theme.dataHrv) { model.startMobilityOneOff() },
            FormOption(icon: "wind", label: "Breathe", tint: theme.dataRecovery) { openBreathe() },
        ]
    }

    /// The five discs alone — they now ride the hero, directly under «Empezar» (FER-939, the FER-920
    /// placement decision finally applied). No overline: their position IS the label.
    private var formasDiscos: some View {
        HStack(alignment: .top, spacing: 6) {
            ForEach(formOptions) { opt in
                formChip(opt)
            }
        }
    }

    /// Quiet standalone foot rows at the very bottom: history + diet, each with a verb of its own
    /// («consultar» / «registrar»), distinct from the discs' «empezar» (mock 1a / v4b).
    private var footRows: some View {
        VStack(alignment: .leading, spacing: 0) {
            utilityRow(icon: "chart.line.uptrend.xyaxis", label: "Mis entrenamientos y progreso") { openHistory() }
            utilityRow(icon: "fork.knife", label: "Dieta · registro de hoy") { openDiet() }
        }
    }

    /// One quiet full-width foot row (history / diet): leading glyph, label, trailing disclosure chevron.
    private func utilityRow(icon: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(StrandFont.glyph(.lead))
                    .foregroundStyle(theme.inkSecondary)
                Text(label)
                    .font(StrandFont.subhead)
                    .foregroundStyle(theme.inkSecondary)
                Spacer(minLength: 8)
                StrandIcon.disclosure.image.font(StrandFont.glyph(.inline, weight: .semibold))
                    .foregroundStyle(theme.inkDim)
            }
            .padding(.vertical, CenitMetrics.gap)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// One icon chip in the always-visible «Formas de entrenar» row: a tinted glyph on a paper circle over a
    /// small label. Runs its door's action.
    private func formChip(_ opt: FormOption) -> some View {
        Button {
            opt.action()
        } label: {
            VStack(spacing: CenitMetrics.space2) {
                // «Troquel en papel»: solid data-token disc, glyph knocked out in paper (the paper is seen
                // THROUGH the disc), rimmed with the same hue a step deeper (`dataEdge`) so it reads as a
                // die-cut token rather than a colored sticker. Color lands on the datum (the modality).
                Image(systemName: opt.icon).font(StrandFont.glyph(.lead, weight: .semibold))
                    .foregroundStyle(theme.paper)
                    .frame(width: 38, height: 38)
                    .background(opt.tint, in: Circle())
                    .overlay(Circle().strokeBorder(theme.dataEdge(opt.tint), lineWidth: 1))
                    .accessibilityHidden(true)
                Text(opt.label).font(StrandFont.overline).foregroundStyle(theme.inkTertiary)
                    .lineLimit(1).minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, minHeight: 44)   // HIG: keep the whole chip a ≥44pt tap target
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(opt.label)
    }

    /// «En vivo» from the expanded pill: start (or resume) the live HR workout and present its sheet — the
    /// same door `RestDayScreen`/`OtherWaysScreen` use, so it lands directly without the 3e chooser.
    private func startLive() {
        if model.activeWorkout == nil { model.startWorkout() }
        showLive = true
    }

    /// One «También en tu plan» routine: the whole row is a single tap target that opens the routine
    /// (FER-784). The trailing chevron carries THAT routine's tint (same color as the leading dot) — a
    /// glanceable «this opens» affordance, one color per routine, no new tokens.
    private func planRoutineRow(_ row: (routineId: String, name: String, days: String)) -> some View {
        Button { openRoutine(row.routineId) } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 7) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)  // token-exempt: geometría de dato
                            .fill(routineFill(region(name: row.name))).frame(width: 8, height: 8)
                        Text(row.name).font(StrandFont.body).foregroundStyle(theme.ink)
                    }
                    Text(planRowSubtitle(row)).font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                        .padding(.leading, 15)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // Handoff v4b: the earned-raise badge on its routine's row («↗ 2 suben»).
                if row.routineId == todayRoutineId, !raisesToday.isEmpty {
                    (Text(verbatim: "↗ ") + Text("\(raisesToday.count) raising"))
                        .font(InstrumentoType.grotesk(11, weight: .bold))
                        .foregroundStyle(theme.dataRecovery)
                }
                StrandIcon.disclosure.image.font(StrandFont.glyph(.inline, weight: .semibold))
                    .foregroundStyle(routineTint(region(name: row.name)))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) { Divider().overlay(theme.hairline) }
    }

    /// «day · muscles» for a plan routine: the weekdays it trains, then its top primary muscles (if known).
    private func planRowSubtitle(_ row: (routineId: String, name: String, days: String)) -> String {
        let muscles = routineMuscles[row.routineId] ?? []
        return muscles.isEmpty ? row.days : ([row.days] + muscles).joined(separator: " · ")
    }

    // MARK: - ④ Constancia — a 90-day dot grid above the dock (mock 1a, replaces the week strip + streak)
    //
    // Three months side by side; every day is a faint base dot, a day you trained lights up in its
    // routine's tint, today is a paper-filled ring in the scheduled routine's tint. No streak, no «2 of 4»,
    // no guilt: a gap breaks nothing — the pattern just reads itself. Data is the last-90-days of completed
    // strength sessions, bucketed by day and routine.

    private var constanciaSection: some View {
        let months = constancyMonths
        let total = months.reduce(0) { $0 + $1.count }
        return VStack(alignment: .leading, spacing: 12) {
            sectionBand("Consistency") {
                Text("\(total) sessions · 90 days")
                    .font(StrandFont.captionNumber).foregroundStyle(theme.inkSecondary)
            }
            HStack(alignment: .top, spacing: 0) {
                ForEach(months) { m in
                    monthColumn(m)
                    if m.id != months.last?.id { Spacer(minLength: 6) }
                }
            }
            if total == 0 {
                Text("Your sessions will appear here, each in its routine's color.")
                    .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// One month block: label «Jul · 6» over the dot grid, with the temporal fade (older months quieter).
    private func monthColumn(_ m: ConstancyMonth) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            (Text(m.label) + Text(verbatim: " · ") + Text("\(m.count)"))
                .font(StrandFont.overline).tracking(0.6)
                .foregroundStyle(m.isCurrent ? theme.ink : theme.inkTertiary)
            monthGrid(m)
        }
        .opacity(m.fade)
    }

    /// The 7-wide dot grid for a month: a faint base dot per day, a tinted dot for days trained, and a
    /// ring for today. Days fill row by row (day 1 top-left).
    private func monthGrid(_ m: ConstancyMonth) -> some View {
        let cell: CGFloat = 14, cols = 7
        let rows = (m.daysInMonth + cols - 1) / cols
        return VStack(spacing: 0) {
            ForEach(0..<rows, id: \.self) { r in
                HStack(spacing: 0) {
                    ForEach(0..<cols, id: \.self) { c in
                        let day = r * cols + c + 1
                        dayCell(m, day: day, cell: cell)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func dayCell(_ m: ConstancyMonth, day: Int, cell: CGFloat) -> some View {
        ZStack {
            if day <= m.daysInMonth {
                Circle().fill(theme.hairlineStrong).frame(width: 4, height: 4)
                if let name = m.trained[day] {
                    Circle().fill(routineFill(region(name: name))).frame(width: 9, height: 9)
                }
                if m.isCurrent && day == todayDayOfMonth {
                    Circle().fill(theme.surface)
                        .overlay(Circle().strokeBorder(todayRingTint, lineWidth: 1.5))
                        .frame(width: 12, height: 12)
                }
            }
        }
        .frame(width: cell, height: cell)
        .contentShape(Rectangle())
        .onTapGesture {
            guard day <= m.daysInMonth, let name = m.trained[day] else { return }
            constancyPopup = ConstancyPopup(monthId: m.id, day: day, name: name)
        }
        .popover(isPresented: Binding(
            get: { constancyPopup?.monthId == m.id && constancyPopup?.day == day },
            set: { if !$0 { constancyPopup = nil } }
        )) {
            if let popup = constancyPopup { constancyPopoverContent(popup, month: m) }
        }
    }

    /// The «hoy» ring tint: today's scheduled routine, or a neutral hairline on a rest day.
    private var todayRingTint: Color { todayRoutine.map { routineTint(region(name: $0.name)) } ?? theme.hairlineStrong }

    /// The routine trained on this week's `weekday`, if a completed session exists that day — read from
    /// the same 90-day Constancia buckets (they always cover the current week). Drives the week strip's
    /// filled-check squares (handoff v4b).
    private func trainedThisWeek(_ wd: Int) -> String? {
        let cal = Calendar.current
        guard let start = cal.dateInterval(of: .weekOfYear, for: Date())?.start else { return nil }
        for i in 0..<7 {
            guard let date = cal.date(byAdding: .day, value: i, to: start),
                  cal.component(.weekday, from: date) == wd else { continue }
            let y = cal.component(.year, from: date)
            let mo = cal.component(.month, from: date)
            let d = cal.component(.day, from: date)
            return constancyMonths.first { $0.year == y && $0.month == mo }?.trained[d]
        }
        return nil
    }

    /// Which Constancia day is popped open (month + day identify the cell; name is what to show) — one
    /// popover shared across the whole grid, gated per-cell by matching identity in `dayCell`.
    private struct ConstancyPopup: Equatable {
        let monthId: Int
        let day: Int
        let name: String
    }

    /// The tapped day's popover: routine name + its date, paper-toned to match Instrumento.
    @ViewBuilder
    private func constancyPopoverContent(_ popup: ConstancyPopup, month: ConstancyMonth) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(popup.name).font(StrandFont.subhead).foregroundStyle(theme.ink)
            if let date = Calendar.current.date(from: DateComponents(year: month.year, month: month.month, day: popup.day)) {
                Text(date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                    .font(StrandFont.footnote).foregroundStyle(theme.inkSecondary)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(theme.surface)
        .presentationCompactAdaptation(.popover)
    }

    // MARK: - Empty state B (no split yet → build the week)

    private var emptyStateB: some View {
        VStack(spacing: 14) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 36, weight: .regular)).foregroundStyle(theme.inkTertiary).accessibilityHidden(true)  // token-exempt: glifo 36pt fuera de banda empty
            Text("No plan yet").font(StrandFont.title2).foregroundStyle(theme.ink).multilineTextAlignment(.center)
            Text("Build your week to see today and your progress.")
                .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            StrandCTAButton("Build my week") { openWeeklyPlan() }
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 30).padding(.horizontal, 18)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous).strokeBorder(theme.hairline, lineWidth: 1))
    }

    // MARK: - First use · «O empieza sin plan» → Rutinas de plantilla (mock 5a)
    //
    // The one door kept from the mock's «empieza sin plan» trio: template routines, ready to edit. The
    // other two mock rows (Rápido de fuerza · Otra forma de entrenar) are dropped here — the always-visible
    // «Formas de entrenar» pill row below already carries Rápido and the alternative forms, so we don't
    // repeat them. A quiet overline, then a single tappable row that opens the templates list.

    private var plantillaRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Or start without a plan").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                .padding(.bottom, 4)
            Button { showTemplates = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "square.stack.3d.up").font(.system(size: 18)).foregroundStyle(theme.inkSecondary)  // token-exempt: glifo 18pt fuera de banda lead
                        .frame(width: 26)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Template routines").font(StrandFont.body).foregroundStyle(theme.ink)
                        Text("push · pull · legs · full body, ready to edit")
                            .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    StrandIcon.disclosure.image.font(.system(size: 14, weight: .semibold))  // token-exempt: chevron de fila fuera de banda
                        .foregroundStyle(theme.inkDim)
                }
                .padding(.vertical, 11).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Error state · store couldn't be read (distinct from «no plan yet»)
    //
    // When `repo.storeHandle()` returns nil the read failed — the user likely HAS a plan we just couldn't
    // open. Showing the onboarding empty state here would wrongly push them to rebuild their week, so we
    // surface a plain error with a retry that re-runs `load()`.
    private var loadErrorState: some View {
        card {
            VStack(alignment: .leading, spacing: CenitMetrics.gap) {
                Text("No pudimos leer tus rutinas").font(StrandFont.title3).foregroundStyle(theme.ink)
                Text("Algo falló al abrir tus datos.")
                    .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                StrandCTAButton("Reintentar", kind: .outline) { Task { await load() } }
            }
        }
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
            .padding(CenitMetrics.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous).strokeBorder(theme.hairline, lineWidth: 1))
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

    private var todayDayOfMonth: Int { Calendar.current.component(.day, from: Date()) }

    /// One month's worth of Constancia dot-grid data.
    private struct ConstancyMonth: Identifiable {
        let id: Int              // 0 = current month, 1 = last month, 2 = two months ago
        let label: String        // «Jul»
        let year: Int
        let month: Int           // calendar month (1...12) — lets a tapped day rebuild its exact date
        let count: Int           // sessions that month
        let daysInMonth: Int
        let trained: [Int: String]   // dayOfMonth → the (latest) routine's name that day («» = unknown routine)
        let isCurrent: Bool
        let fade: Double
    }

    /// The last three calendar months (oldest → current) as dot-grid data: for each, the days you trained
    /// keyed to the latest routine that day, plus the session count. Read from the last-200 completed
    /// sessions (well over 90 days' worth). No streak, no adherence — just the pattern.
    private var constancyMonths: [ConstancyMonth] {
        let cal = Calendar.current
        guard let startOfThisMonth = cal.date(from: cal.dateComponents([.year, .month], from: Date())) else { return [] }
        // Bucket completed sessions by (year, month); within a month keep the first-seen (latest) routine per day.
        var byYM: [DateComponents: (count: Int, trained: [Int: String])] = [:]
        for s in sessions where s.endTs != nil {
            let c = cal.dateComponents([.year, .month, .day], from: Date(timeIntervalSince1970: TimeInterval(s.startTs)))
            let key = DateComponents(year: c.year, month: c.month)
            var bucket = byYM[key] ?? (0, [:])
            bucket.count += 1
            if let day = c.day, bucket.trained[day] == nil {
                bucket.trained[day] = s.routineId.flatMap { routinesById[$0]?.name } ?? ""
            }
            byYM[key] = bucket
        }
        let fades: [Double] = [0.72, 0.88, 1.0]
        return (0..<3).reversed().compactMap { offset in     // 2,1,0 → oldest first
            guard let monthDate = cal.date(byAdding: .month, value: -offset, to: startOfThisMonth),
                  let month = cal.dateComponents([.month], from: monthDate).month else { return nil }
            let ym = cal.dateComponents([.year, .month], from: monthDate)
            guard let year = ym.year else { return nil }
            let bucket = byYM[DateComponents(year: ym.year, month: ym.month)] ?? (0, [:])
            return ConstancyMonth(id: offset,
                                  label: cal.shortMonthSymbols[(month - 1) % 12].capitalized,
                                  year: year,
                                  month: month,
                                  count: bucket.count,
                                  daysInMonth: cal.range(of: .day, in: .month, for: monthDate)?.count ?? 30,
                                  trained: bucket.trained,
                                  isCurrent: offset == 0,
                                  fade: fades[2 - offset])
        }
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
        loadFailed = false   // clear on every (re)try
        guard let store = await repo.storeHandle() else { loadFailed = true; loaded = true; return }
        let rs = (try? await store.routines()) ?? []
        let customAll = (try? await store.customExercises()) ?? []
        let customAllByID = Dictionary(customAll.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var counts: [String: Int] = [:]
        var muscles: [String: [String]] = [:]
        var categories: [String: RoutineRegion] = [:]
        for r in rs {
            let exs = (try? await store.routineExercises(routineId: r.id)) ?? []
            counts[r.id] = exs.count
            muscles[r.id] = Self.topMuscles(exs, customByID: customAllByID)
            // Derive the routine's color family from its exercises' primary muscles (FER-775) — the same
            // resolution `topMuscles` uses. Absent when nothing classifies → the tint falls back to the hue.
            let perExercise = exs.compactMap { re in
                (ExerciseCatalog.byID(re.exerciseId) ?? customAllByID[re.exerciseId])?.primaryMuscles
            }
            if let cat = RoutineClassifier.classify(primaryMusclesPerExercise: perExercise) {
                categories[r.id] = cat
            }
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
            // FER-E/G: «la última vez» + progression per slot, via the ONE `sessionSeed` implementation
            // the «Rutina» editor also calls — the raise the hero names is exactly the raise it seeds.
            let inventory = await MainActor.run { PlatesStore().inventory }
            let recovery = repo.today?.recovery
            var raising: [(name: String, kg: Double)] = []
            var deferredNames: [String] = []
            for re in exs {
                let ex = (ExerciseCatalog.byID(re.exerciseId) ?? customByID[re.exerciseId])?.applying(overrides)
                let seed = await repo.sessionSeed(re: re, exercise: ex, inventory: inventory, recovery: recovery)
                if let result = seed.evaluation {
                    let name = ex.map(StrengthDisplay.name) ?? re.exerciseId
                    if let raise = result.raise { raising.append((name: name, kg: raise.toKg)) }
                    else if case .deferred = result.state { deferredNames.append(name) }
                }
                slots.append(.init(re: re, exercise: ex, lastSets: seed.lastSets, raise: seed.evaluation?.raise))
            }
            raisesToday = raising
            deferredToday = deferredNames
        }
        routines = rs
        exerciseCounts = counts
        routineMuscles = muscles
        routineCategory = categories
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
                    suggestedCard(alt).padding(.top, CenitMetrics.sectionGap)
                }

                Text("If you still want to train").instrumentoOverline()
                    .foregroundStyle(theme.inkTertiary).padding(.top, CenitMetrics.sectionGap)
                VStack(spacing: 0) {
                    if alt != .softer { row("figure.cooldown", "Mobility · 20 min") { model.startMobilityOneOff() } }
                    if alt != .optionalLight { row("timer", "Intervals · 12 min") { openIntervals() } }
                    row("list.bullet", "Pick a routine") { openRoutines() }
                    row("wind", "Breathe") { openBreathe() }
                    row("dot.radiowaves.left.and.right", "Live", last: true) { startLive() }
                }
                .padding(.top, 6)

                if let tomorrow = tomorrowRoutineName {
                    Divider().overlay(theme.hairline).padding(.top, CenitMetrics.sectionGap)
                    Text("Tomorrow: \(tomorrow)")
                        .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary).padding(.top, 14)
                }
            }
            .padding(.top, 20)
            .padding(.horizontal, CenitMetrics.screenPadding)
            .padding(.bottom, CenitMetrics.screenPadding)
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
            StrandCTAButton("Empezar") { if alt == .softer { model.startMobilityOneOff() } else { openIntervals() } }
                .padding(.top, 14)
        }
        .padding(CenitMetrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous).strokeBorder(theme.hairline, lineWidth: 1))
    }

    private func row(_ icon: String, _ title: LocalizedStringKey, last: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(StrandFont.glyph(.lead)).foregroundStyle(theme.inkSecondary).frame(width: 26)
                Text(title).font(StrandFont.body).foregroundStyle(theme.ink)
                Spacer(minLength: 8)
                StrandIcon.disclosure.image.font(StrandFont.glyph(.chevron, weight: .semibold)).foregroundStyle(theme.inkDim)
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
                .padding(.top, CenitMetrics.sectionGap)

                Text("None of this breaks your streak or your plan.")
                    .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                    .frame(maxWidth: .infinity, alignment: .center).padding(.top, CenitMetrics.sectionGap)
            }
            .padding(.top, 20)
            .padding(.horizontal, CenitMetrics.screenPadding)
            .padding(.bottom, CenitMetrics.screenPadding)
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
                Image(systemName: icon).font(.system(size: 22)).foregroundStyle(theme.inkSecondary).frame(width: 30)  // token-exempt: glifo 22pt fuera de banda lead
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(StrandFont.headline).foregroundStyle(theme.ink)
                    Text(subtitle).font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                }
                Spacer(minLength: 8)
                StrandIcon.disclosure.image.font(StrandFont.glyph(.inline, weight: .semibold)).foregroundStyle(theme.inkDim)
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
