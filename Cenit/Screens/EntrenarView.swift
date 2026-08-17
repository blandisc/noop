#if os(iOS)
import SwiftUI
import StrandDesign
import StrandTraining
import StrandAnalytics
import Inject   // recarga en caliente (dev-only, inerte en Release)

// MARK: - Entrenar (the Train tab root) — «Pulir · arranque directo» (handoff, sobre «La Semana» FER-530)
//
// The Train landing as a PLANNER in the light «Instrumento diurno» language (warm paper, color only on
// the datum, hierarchy by space). Today's session is the spine now: the hero «Hoy» sits up top behind a
// SINGLE solid «Empezar {rutina}» that starts the guided session in ONE tap (F1) — no chooser, no
// intermediate screen. «¿otro tipo?» under it opens the secondary chooser (otra rutina / intervals /
// breathe / live). A rest day swaps the door for a quiet outline button that opens the «Hoy descansas»
// sheet (F3). Below the hero: a contextual suggestion, the week strip + streak in one card (F10), the
// plan as a collapsible disclosure with a single «Editar» action (F5).
//
// Color appears ONLY on the recovery datum (the today-dot, the Today recovery
// line); everything else is ink on paper. Navigation is owned by the tab's `NavigationStack` in
// RootTabView; the landing pushes via the injected closures and hosts the guided session + sheets here.

struct EntrenarView: View {
    /// Inject: los hooks de recarga en caliente van AQUÍ y no en `EntrenarLanding`. Swift emite los
    /// miembros de un tipo `private` como símbolos locales, y `-interposable` solo puede interponer
    /// símbolos globales — así que el `body` de `EntrenarLanding` es inalcanzable para la inyección.
    /// El de `EntrenarView` sí es global, y es quien construye el Landing: al interponerlo, construye
    /// la copia nueva que trae el dylib inyectado, con todo el código privado del archivo adentro.
    /// Regla general: los hooks van en la vista NO privada más externa del archivo.
    @ObserveInjection private var inject

    var openRoutine: (String) -> Void
    var openBreathe: () -> Void
    var openIntervals: () -> Void
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
                        openBreathe: openBreathe, openIntervals: openIntervals,
                        openHistory: openHistory, openWeeklyPlan: openWeeklyPlan,
                        openRoutines: openRoutines, openRestDay: openRestDay,
                        openOtherWays: openOtherWays, openWorkoutSession: openWorkoutSession)
            .instrumentoTheme(.base)
            .enableInjection()   // Inject: ver la nota en `inject` arriba (no-op en Release)
    }
}

private struct EntrenarLanding: View {
    @EnvironmentObject var repo: Repository
    @Environment(AppModel.self) var model
    @EnvironmentObject var tabRouter: TabRouter
    @Environment(\.instrumentoTheme) private var theme

    var openRoutine: (String) -> Void
    var openBreathe: () -> Void
    var openIntervals: () -> Void
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
    /// Exercises whose earned raise today's verdict is holding — with the weight that waits, so the
    /// hero can name it and the athlete knows exactly what is one tap away in the session (FER-82).
    @State private var deferredToday: [(name: String, kg: Double)] = []
    /// The verdict `todaySlots` were seeded with; `nil` until the first load. Guards «Empezar» from
    /// handing the session a table built under a verdict that has since changed (FER-82).
    @State private var slotsAdvice: TrainingRegulation.Advice?
    /// El puente de Apple Salud, para que la boleta de esta pestaña reciba el MISMO contexto que la
    /// de Hoy (sin él afirmaba «anoche no llegó nada» a quien no ha conectado Salud).
    @EnvironmentObject private var health: HealthKitBridge

    /// FER-85/FER-84: la boleta del veredicto, servida DENTRO de Entrenar. El hilo la abre como
    /// hoja; nunca cambia de pestaña. Es la misma acta que Hoy sirve, con el mismo modelo.
    @State private var showVeredictoActa = false
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
    /// Constancia month buckets (last ~90 days), computed once per `load()` — not on every body pass.
    /// `trainedThisWeek` and the Constancia grid both read this; re-bucketing 200 sessions per access
    /// was ~9–10× work per layout evaluation (FER-948).
    @State private var constancyMonthsCache: [ConstancyMonth] = []
    /// Today's routine resolved into guided-session slots, prefetched on load so «Empezar» starts in one
    /// tap (F1). Empty when today is a rest day or the routine has no exercises.
    @State private var todaySlots: [StrengthSessionModel.PlanSlot] = []
    /// Drives the templates sheet opened straight on the mobility routine from the ③ «softer» suggestion
    /// (a TRAINING-day nudge; the rest sheet starts mobility directly instead). FER-554.
    @State private var showMobilityTemplate = false
    /// «Empezar» from the mobility template stashes its (name, slots) here; the session starts on the
    /// sheet's dismiss so it never stacks on the templates sheet (FER-560).
    @State private var pendingMobility: (name: String, slots: [StrengthSessionModel.PlanSlot])? = nil
    /// The Daily Brief's «Empezar» arrived (via `TabRouter`) before this view finished loading its
    /// prefetched slots — start today's session as soon as `load()` completes (FER-613).
    @State private var startWhenLoaded = false
    /// Presents the live-HR workout sheet from the «Formas de entrenar» → «En vivo» chip (same sheet the
    /// rest-day / other-ways screens use).
    /// The Constancia day currently popped open (tap-to-reveal what you trained that day).
    @State private var constancyPopup: ConstancyPopup? = nil
    /// Presents the starter-templates list from the first-use «Rutinas de plantilla» row (mock 5a).
    @State private var showTemplates = false
    /// FER-952: the hub's Import door-chip.
    @State private var showHubImport = false
    /// «Lo que Cénit sabe hacer» (decisión Fer 2026-07-16): puerta permanente + tarjeta única.
    @State private var showTricks = false
    /// FER-952: the hub's «New routine» — pushes the unified create flow (library → editor).
    @State private var showCreateRoutine = false
    /// FER-950: Quick / Mobility discs with a live strength session — confirm resume instead of
    /// silently re-presenting via `startStrengthSession`'s no-op guard (which looks like "start new").
    @State private var confirmResumeStrength = false
    @State private var saveError = false

    /// Monday-first display order in the Calendar weekday convention.
    private let orderedWeekdays = [2, 3, 4, 5, 6, 7, 1]
    private var todayWeekday: Int { Calendar.current.component(.weekday, from: Date()) }
    /// FER-82 «un solo oráculo»: Entrenar advises from the SAME verdict Hoy is painting, resolved once
    /// in `Repository.trainingAdvice`. There is no recovery-score fallback here on purpose — a second
    /// source of truth is exactly what let this section contradict Hoy on the same day.
    private var advice: TrainingRegulation.Advice { repo.trainingAdvice }

    /// Salud «conectada» efectiva, con la misma excepción de fixtures que usa Hoy: en DEBUG con un
    /// estado sembrado el permiso real nunca está concedido y la hoja caería al copy de conectar.
    private var healthConnected: Bool {
        #if DEBUG
        if ScreenshotFixtures.activeState() != nil { return true }
        #endif
        return health.auth == .authorized
    }

    var body: some View {
        // Fixed section rhythm in a plain ScrollView (FER-786 hotfix): the earlier GeometryReader +
        // `.frame(minHeight: geo.size.height)` + flexible/capped spacers (FER-784/785) fed the measured
        // height back into layout and looped as the plan grew — 99% CPU, «Invalid frame dimension», freeze.
        // `sectionGap` (28) still gives more air between blocks than the old 18; no measured-height feedback.
        ScrollView {
            VStack(alignment: .leading, spacing: CenitMetrics.sectionGap) {
                // FER-952 (owner): the «Train» wordmark + tab glyph row retired — the dock already
                // names the tab.
                // FER-85: el hilo del veredicto — el ÚNICO portador del veredicto en Entrenar y la
                // primera cosa que se lee. Vive FUERA del gate de carga porque habla del CUERPO, no
                // del plan: no tiene por qué esperar a que la base de datos conteste, y así el «?»
                // de ayuda tampoco aparece a destiempo.
                HStack(spacing: CenitMetrics.space2) {
                    hiloDelVeredicto
                    // El «?» del handoff: los trucos siguen ahí para quien los busque, pero
                    // dejan de ocupar una tarjeta en la pantalla principal (decisión del dueño).
                    Button { showTricks = true } label: {
                        Image(systemName: "questionmark.circle")
                            .font(StrandFont.glyph(.lead))
                            .foregroundStyle(theme.inkTertiary)
                            .frame(width: EntrenarMetrics.row, height: EntrenarMetrics.row)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(EntrenarPressStyle())
                    .accessibilityLabel(Text("Tricks"))
                }
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
                        footRows          // ⑥ history (Dieta off — FER-992)
                    }
                }
            }
            .padding(.top, CenitMetrics.screenTop)   // shared titled-tab top inset
            .padding(.horizontal, CenitMetrics.screenPadding)
            .padding(.bottom, CenitMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.paper.ignoresSafeArea())
        // FER-969: el fallo de escritura es un banner honesto, no éxito silencioso. Componente
        // compartido desde 2026-07-19 (era la misma copia en tres pantallas).
        .saveErrorToast(isPresented: $saveError)
        // The ③ «softer» suggestion (FER-554) opens the templates sheet straight on the mobility routine.
        // «Empezar» starts a one-off guided session (on the sheet's dismiss, so it never stacks — FER-171),
        // with «Add to my routines» as the secondary action. Theme doesn't cross the sheet boundary.
        // La boleta del veredicto, dentro de Entrenar (FER-85): el mismo modelo y la misma vista
        // que sirve Hoy, así que las dos pantallas no pueden divergir ni en la tabla ni en la
        // gráfica de cajas. «Ver más» cierra la hoja sin cambiar de pestaña.
        .sheet(isPresented: $showVeredictoActa) {
            LiquidMetricSheet(tono: LiquidHoyBuilder.actaTono(repo.todayPreparedness),
                              detent: .porContenido) {
                // El MISMO contexto que Hoy le pasa a su acta: sin `healthConnected` la hoja afirmaba
                // «anoche no llegó nada» a quien simplemente no ha conectado Salud, y sin él las dos
                // pantallas contaban historias distintas del mismo día — justo lo que este épico mata.
                LiquidActaVeredicto(
                    LiquidHoyBuilder.acta(prep: repo.todayPreparedness,
                                          healthConnected: healthConnected,
                                          verdictPending: repo.todayPreparedness == nil && !repo.fullyLoaded),
                    // Sin «Ver más»: ese botón lleva a Tendencias, y la decisión del handoff es que
                    // esta hoja no cambia de pestaña. Un CTA de ancho completo que solo cierra la hoja
                    // promete un viaje que no ocurre (y su hint de VoiceOver lo dice en voz alta).
                    onVerMas: nil)
            }
            .preferredColorScheme(.light)
        }
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
        // FER-952: the hub's Import chip opens the importer right here (same sheet as Tu Plan).
        .sheet(isPresented: $showHubImport) {
            WorkoutImportView { await load() }
                .instrumentoTheme(theme).environmentObject(repo).preferredColorScheme(.light)
        }
        // FER-952: «＋ Nueva rutina» del hub — el flujo unificado directo (Biblioteca → editor).
        .navigationDestination(isPresented: $showCreateRoutine) {
            ExerciseLibraryScreen(createFlow: true) { picks in createRoutineFromHub(picks) }
        }
        .navigationDestination(isPresented: $showTricks) {
            WorkshopTricksScreen()
        }
        // «En vivo» from the expanded «Más formas» pill — the live-HR free workout, same sheet the
        // rest-day / other-ways screens present (theme passed explicitly; it doesn't cross `.sheet`).
        // FER-950: disc said «Rápido»/«Movilidad» but AppModel only re-opens the live session — make
        // that resume path explicit (ConfirmCard), never clobber.
        .instrumentoConfirm(
            isPresented: $confirmResumeStrength,
            title: String(localized: "You have a session in progress. Resume it?"),
            context: String(localized: "SESSION · IN PROGRESS"),
            message: String(localized: "A new routine can't start until this one ends."),
            actions: [
                .init(String(localized: "Resume session"), role: .primary) {
                    model.resumeStrengthSession()
                },
                .init(String(localized: "Not now"), role: .secondary)
            ]
        )
        // The guided strength session (FER-347) is now presented at the shell (`RootTabView`) as a
        // full-screen cover with a floating pill on all five tabs (FER-716), so it survives tab switches
        // and no longer needs a «Resume» row here. The session lives in AppModel.
        //
        // Keyed to the repository's publish counter (FER-82): the seed and the advice line must come
        // from the SAME pass. On a cold start the verdict only lands with the full refresh, and an
        // unkeyed `.task` left the prefetched raise frozen on the pre-verdict evaluation while the
        // advice line (a computed property) already spoke the new verdict.
        .task(id: repo.refreshSeq) { await load() }
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

    // MARK: - ① Open hero + «Empezar» + discs (handoff v4b, FER-939)
    //
    // The hero sits OPEN on the paper — no card, no border. Hierarchy by space (Instrumento): the
    // routine name is the dominant datum (Grotesk 32, handoff spec), the meta/recovery/raise detail
    // moves down to its own «LA SESIÓN DE HOY» band, and the five training discs ride directly under
    // «Empezar» as the screen's second decision (FER-920 decision #1, applied here).

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(hoyOverline)
                .groteskSheetTitle().textCase(.uppercase).foregroundStyle(theme.inkTertiary)
            if let r = todayRoutine {
                // «Bisel»: la marca de familia es una regla vertical, no un cuadro en línea. El cuadro vivía
                // dentro del HStack, así que le robaba ancho al título y lo empujaba a la derecha; con
                // nombres de dos líneas el bloque perdía el eje. Ahora la REGLA marca el margen —queda a
                // plomo con «Empezar» y los discos— y el texto se indenta después de ella, en vez de que
                // la regla se salga al canalón. Su alto lo deriva del contenido: crece sola con la segunda
                // línea y con Dynamic Type.
                VStack(alignment: .leading, spacing: 8) {
                    Text(r.name)
                        .font(InstrumentoType.grotesk(32, weight: .bold)).tracking(-1)
                        .foregroundStyle(theme.ink)
                        .lineLimit(2).minimumScaleFactor(0.65)
                        .fixedSize(horizontal: false, vertical: true)
                    if let muscles = routineMuscleLine(r.id) {
                        Text(muscles).font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                    }
                }
                .padding(.leading, 11)
                .padding(.top, 8)
                .background(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)  // token-exempt: geometría de dato
                        .fill(routineFill(region(name: r.name)))
                        .frame(width: 3)
                        .padding(.vertical, 2)
                        .accessibilityHidden(true)   // el color no porta significado por sí solo
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
            // FER-944 rhythm: the datum→action border (16) reads clearly wider than the hero's inner
            // gaps (4/8), so the block squints as three masses — text, button, discs.
            empezarButton.padding(.top, CenitMetrics.sectionGapCompact)
            formasDiscos.padding(.top, CenitMetrics.gap)
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
    private var empezarLabel: LocalizedStringKey { model.strengthSession != nil ? "Continue" : "Empezar" }

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

    /// Routine-day CTA: `StrandCTAButton` con el tinte de región de la rutina (auditoría FER-952:
    /// el chrome se copiaba a mano; ahora el componente acepta `tint`).
    private var tintedEmpezarButton: some View {
        StrandCTAButton(empezarLabel, tint: routineTint(region(name: todayRoutine?.name ?? ""))) {
            startOrResume()
        }
    }

    /// F1: a day with a routine starts the guided session in one tap (slots prefetched on load); an empty
    /// routine opens its plan to edit instead of an empty session; a rest day opens the «Hoy descansas» sheet.
    private func startToday() {
        guard let r = todayRoutine else { openRestDay(); return }
        // FER-82: the slots carry the verdict they were seeded with. If it moved since the prefetch
        // (the case that matters: they were built while the verdict was still being computed and it
        // landed a second later), rebuild ONCE before starting — otherwise the whole session runs on
        // a verdict the screen has already stopped showing. Exactly one retry, never a loop.
        if let seeded = slotsAdvice, seeded != repo.trainingAdvice {
            Task {
                // Un intento de reconstrucción, y luego SE ARRANCA pase lo que pase: el usuario pidió
                // entrenar y el tap no se puede convertir en otra pantalla. Pero si la reconstrucción
                // NO publicó, los slots que quedan son del pase anterior y pueden traer la subida
                // APLICADA bajo un consejo que hoy la retiene: en ese caso se retiene aquí, para que
                // por esta ruta nunca se entrene de más, solo a lo sumo de menos.
                if await load() == false, !TrainingRegulation.allowsRaise(repo.trainingAdvice) {
                    todaySlots = todaySlots.map { slot in
                        guard var raise = slot.raise, !raise.waiting else { return slot }
                        raise.waiting = true
                        var held = slot
                        held.raise = raise
                        return held
                    }
                }
                startTodayNow(r)
            }
            return
        }
        startTodayNow(r)
    }

    /// Start with the slots as they are — the terminal half of `startToday`, so the rebuild path can
    /// call it without ever re-entering the verdict check.
    private func startTodayNow(_ r: Routine) {
        guard !todaySlots.isEmpty else { openRoutine(r.id); return }
        model.startStrengthSession(routineId: r.id, routineName: r.name, slots: todaySlots)
    }


    /// «Entrenamiento rápido de fuerza» (mock 1p, FER-762): no routine, no slots — the session starts
    /// empty and `LiveStrengthSheet` shows its own empty-state (search + freshness suggestions) until the
    /// first exercise is added. With a live session, confirm resume instead of looking like a new start
    /// (FER-950 — AppModel's guard only re-presents the existing sheet).
    /// FER-952 unified flow, hub edition: the library's picks become a routine right here and the
    /// unified editor opens to name and tune it (post-pop push — FER-171 lesson).
    private func createRoutineFromHub(_ picks: [Exercise]) {
        guard !picks.isEmpty else { return }
        let now = Int(Date().timeIntervalSince1970)
        let r = Routine(name: String(localized: "New routine"), createdTs: now, updatedTs: now, sortOrder: 0)
        let exercises = picks.enumerated().map { idx, ex -> RoutineExercise in
            let usesReps = ex.type == .weightReps || ex.type == .bodyweight
            let reps: Int? = usesReps ? 8 : nil
            let sets = (0..<3).map { RoutineSet(position: $0, kind: .work, reps: reps, weightKg: nil) }
            return RoutineExercise(routineId: r.id, exerciseId: ex.id, position: idx,
                                   targetSets: 3, targetReps: reps, targetWeightKg: nil, sets: sets)
        }
        Task {
            do {
                try await repo.saveRoutine(r, exercises: exercises)
                await load()
                try? await Task.sleep(nanoseconds: 550_000_000)
                openRoutine(r.id)
            } catch {
                saveError = true
            }
        }
    }

    private func startQuickStrength() {
        if model.strengthSession != nil {
            confirmResumeStrength = true
            return
        }
        model.startStrengthSession(routineId: nil, routineName: String(localized: "Quick strength"), slots: [])
    }

    /// Mobility disc: one-off guided session, or explicit resume confirm when one is already live (FER-950).
    private func startMobilityFromDisc() {
        if model.strengthSession != nil {
            confirmResumeStrength = true
            return
        }
        model.startMobilityOneOff()
    }

    // MARK: - ③ «LA SESIÓN DE HOY» (handoff v4b: the day's detail in its own band section)
    // (The sunken section band itself is `InstrumentoSectionBand` in StrandDesign — promoted in
    // FER-940 when «Tu Plan» adopted the same header.)
    //
    // Big Grotesk numerals for the session's shape (min · exercises · sets), the earned raise as the
    // green line (FER-G — it lives where you start), and the recovery hint on a thin green filete.
    // Rest days and empty routines skip the whole section — nothing to detail.

    @ViewBuilder private var sesionDeHoy: some View {
        if let r = todayRoutine {
            VStack(alignment: .leading, spacing: 12) {
                InstrumentoSectionBand("The session today")
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
                        .frame(minHeight: 44)   // HIG tap target — the row is one thin subhead line (FER-944)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                // Both rows can be true at once: a slot with «Baja recuperación · Ignorar» raises on
                // its log alone while the rest of the day is held. They coexist rather than one
                // hiding the other, so the held weights never vanish from the screen (FER-82).
                if showsHeldRaise, !deferredToday.isEmpty {
                    // FER-82: the raise is held, not lost. Name the weight that waits and open the
                    // session, where taking it is one tap. Editing by hand is never blocked.
                    Button { openRoutine(r.id) } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            heldRaiseText
                                .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                            StrandIcon.disclosure.image
                                .font(StrandFont.glyph(.chevron, weight: .semibold)).foregroundStyle(theme.inkTertiary)
                        }
                        .frame(minHeight: 44)   // HIG tap target — the row is one thin subhead line (FER-944)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                // FER-85: la línea de consejo se RETIRA de aquí. El veredicto entra por un solo
                // portador —el hilo, arriba— y esta línea decía exactamente lo mismo tres bloques
                // abajo, con su propio filete verde aunque el consejo fuera «Recupera».
            }
        }
    }

    /// «~50 min · 6 ejercicios · 18 series» — each numeral big (Grotesk 20), its unit word quiet.
    private func sesionMetrics(_ rid: String) -> some View {
        let sets = todaySlots.reduce(0) { $0 + max(0, $1.re.targetSets) }
        // The three numerals share ONE accent — the routine's tint (same hue as the hero dot and
        // «Empezar»). They're a single piece of information (today's session shape), so one hue, not
        // three: three colours here would compete with the five coloured discs right above. The unit
        // words stay quiet ink. (FER-944)
        let accent = routineTint(region(name: todayRoutine?.name ?? ""))
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            if estMinutes > 0 {
                bigStat(Text(verbatim: "~\(estMinutes)"), unit: Text("min"), valueColor: accent)
                dotSeparator
            }
            bigStat(Text(verbatim: "\(exerciseCounts[rid] ?? 0)"), unit: Text("exercises"), valueColor: accent)
            if sets > 0 {
                dotSeparator
                bigStat(Text(verbatim: "\(sets)"), unit: Text("sets"), valueColor: accent)
            }
        }
        // VoiceOver reads the cluster as ONE phrase — the numerals combine into their unit words and
        // the «·» separators are hidden, so it says «~50 min, 6 exercises, 18 sets», not the glyphs. (FER-944)
        .accessibilityElement(children: .combine)
    }

    private func bigStat(_ value: Text, unit: Text, valueColor: Color? = nil) -> Text {
        value.font(InstrumentoType.groteskNumber(20)).foregroundStyle(valueColor ?? theme.ink)
            + Text(verbatim: " ")
            + unit.font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
    }

    private var dotSeparator: some View {
        Text(verbatim: "·").font(StrandFont.caption).foregroundStyle(theme.inkDim)
            .accessibilityHidden(true)   // VoiceOver reads the cluster as a phrase, not the «·» glyphs (FER-944)
    }

    /// «Hoy subes Press banca · 82,5 kg y Press militar · 26 kg» — the names+loads in the raise green.
    private var raiseText: Text {
        let parts = raisesToday.map { "\($0.name) · \(UnitFormatter.massFromKilograms($0.kg, system: unitSystem))" }
        // Grotesk RELATIVO al subhead, igual que su fila hermana: las dos pueden estar en pantalla a
        // la vez y con Dynamic Type una crecía y la otra se quedaba clavada en 13 pt.
        let strong = parts.map {
            Text(verbatim: $0)
                .font(InstrumentoType.groteskNumber(13, weight: .bold, relativeTo: .subheadline))
                // `dataRecovery` a 13 pt da 3.63:1 sobre el papel: reprueba el piso de texto normal.
                // `positiveText` es el MISMO verde, oscurecido lo justo para llegar a 4.5:1.
                .foregroundStyle(theme.positiveText)
        }
        var t = Text("Today you raise") + Text(verbatim: " ")
        for (i, s) in strong.enumerated() {
            if i > 0 { t = t + Text(verbatim: " · ") }
            t = t + s
        }
        return t
    }

    /// «Te espera la subida: Press banca · 82,5 kg. Puedes tomarla en la sesión.» — the held raise,
    /// named. Same shape as `raiseText` but in reading ink: a fact being held, not a green go-ahead.
    ///
    /// Two separators, two jobs: « · » binds a name to its weight, «, » separates exercises, and the
    /// list closes with a period before the second sentence. Long days are capped at three names and
    /// summarised, so the hero never turns into a paragraph.
    private var heldRaiseText: Text {
        let shown = deferredToday.prefix(3)
        let rest = deferredToday.count - shown.count
        let parts = shown.map { "\($0.name) · \(UnitFormatter.massFromKilograms($0.kg, system: unitSystem))" }
        // Grotesk RELATIVE to the surrounding subhead: the weights are the datum of this sentence, so
        // they have to grow with it — a fixed 13 pt stayed put while the prose reached xxxLarge.
        let strong = parts.map {
            Text(verbatim: $0)
                .font(InstrumentoType.groteskNumber(13, weight: .bold, relativeTo: .subheadline))
                .foregroundStyle(theme.ink)
        }
        var t = (deferredToday.count == 1 ? Text("The raise waits:") : Text("The raises wait:"))
            + Text(verbatim: " ")
        for (i, s) in strong.enumerated() {
            if i > 0 { t = t + Text(verbatim: ", ") }
            t = t + s
        }
        // Spanish takes no comma before «y», so the tail joins with a plain space.
        if rest > 0 { t = t + Text(verbatim: " ") + Text("and \(rest) more") }
        return t + Text(verbatim: ". ")
            + (deferredToday.count == 1 ? Text("You can take it in the session.")
                                        : Text("You can take them in the session."))
    }

    // MARK: - ② Suggestion (engine is FER-532 — TrainingRegulation.lightAlternative)
    //
    // A CONTEXTUAL lighter/heavier alternative, derived from today's recovery against your personal
    // baseline. Within the normal band or with no signal the engine returns nil and the row falls back to
    // an INFORMATIONAL placeholder (FER-559) — not tappable, no destination.

    /// The gentler option, from the ONE oracle: only «Recupera» offers one. Silent and pending states
    /// return nil, so the row hides instead of inventing a direction from a score.
    private var suggestionAlternative: TrainingRegulation.LightAlternative? {
        TrainingRegulation.lightAlternative(advice)
    }

    @ViewBuilder private var suggestionRow: some View {
        if let alt = suggestionAlternative {
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
            InstrumentoSectionBand("Your plan") {
                // Decisión Fer (2026-07-16 v2): la puerta habla en la MISMA voz sutil que el
                // «N sesiones · 90 días» de Consistencia, con chevron para decir «tócame».
                Button { openWeeklyPlan() } label: {
                    HStack(spacing: 4) {
                        Text("Edit routines and week")
                            .font(StrandFont.captionNumber).foregroundStyle(theme.inkSecondary)
                        StrandIcon.disclosure.image
                            .font(StrandFont.glyph(.chevron, weight: .semibold)).foregroundStyle(theme.inkTertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Edit routines and week"))
            }
            weekStrip
            // Handoff v4b: EVERY routine lists here (today's included — its «↗ N suben» badge is the
            // reason it earns a row beyond the hero). Reversal of the earlier hero-only decision (FER-939).
            ForEach(planRows, id: \.routineId) { row in
                planRoutineRow(row)
            }
            // Sin día asignado: visibles igual (antes una rutina nueva no salía en ningún lado del
            // hub). El «—» honesto va en inkDim; asignarle día se hace en Tu Plan.
            ForEach(unscheduledRoutines, id: \.id) { r in
                planRoutineRow((routineId: r.id, name: r.name, days: String(localized: "no day yet")))
            }
            nuevaRutinaRow
        }
    }

    /// Tarjeta de una-sola-vez hacia los trucos del taller (decisión Fer 2026-07-16): se descarta
    /// con ✕ y no vuelve; la puerta permanente es el chip «? Trucos».
    /// «＋ Nueva rutina» + the styled door-chips (FER-952). New routine goes STRAIGHT into the
    /// unified create flow (library push → editor) — no detour through Tu Plan. Folders left the
    /// hub: managing folders belongs where the routine list lives (Tu Plan).
    private var nuevaRutinaRow: some View {
        VStack(alignment: .leading, spacing: CenitMetrics.space2) {
            // Mismo componente que el botón de agregar de la Biblioteca (decisión Fer 2026-07-19). El
            // relleno `patternBlock` que traía medía 1.06:1 contra el papel — la forma casi no existía;
            // el componente lo cambia por superficie con borde.
            InstrumentoAddButton(theme: theme, label: String(localized: "New routine")) {
                showCreateRoutine = true
            }
            HStack(spacing: CenitMetrics.space2) {
                InstrumentoToolChip(systemImage: "square.stack.3d.up", label: Text("Templates")) { showTemplates = true }
                InstrumentoToolChip(systemImage: "square.and.arrow.down", label: Text("Import")) { showHubImport = true }
                InstrumentoToolChip(systemImage: "questionmark.circle", label: Text("Tricks")) { showTricks = true }
            }
        }
        .padding(.top, CenitMetrics.space2)
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
        .padding(.top, CenitMetrics.gap).padding(.bottom, CenitMetrics.space2)
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
        let doneRegion = trainedThisWeek(wd).map { self.region(name: $0) }   // `region` local shadows the func
        let doneTint = doneRegion.map { routineTint($0) }
        /// Entrenaste algo distinto a lo planeado ese día: el contorno lo delata.
        let swapped = doneRegion != nil && hasRoutine && doneRegion! != region
        let a11y = weekStripAccessibilityLabel(wd)
        let cell = VStack(spacing: 5) {
            Text(weekdayLetter(wd))
                .font(InstrumentoType.grotesk(10, weight: .semibold))
                .foregroundStyle(isToday ? theme.ink : (hasRoutine ? routineTint(region) : theme.inkTertiary))
                .accessibilityHidden(true)
            ZStack {
                if let doneTint {
                    // Relleno = lo que ENTRENASTE. Si además había algo planeado y NO fue lo que hiciste,
                    // el contorno lleva el color de lo planeado (decisión Fer 2026-07-18): el mismo cuadro
                    // carga las dos dimensiones sin inventar un cuarto estado, y cuando coinciden se lee
                    // como un cuadro sólido normal. Ese desvío hoy se perdía por completo.
                    RoundedRectangle(cornerRadius: CenitMetrics.chipRadius, style: .continuous).fill(doneTint)
                    if swapped {
                        RoundedRectangle(cornerRadius: CenitMetrics.chipRadius, style: .continuous)
                            .strokeBorder(routineTint(region), lineWidth: 2.5)
                    }
                    StrandIcon.confirm.image
                        .font(StrandFont.glyph(.chevron, weight: .semibold)).foregroundStyle(theme.paper)
                } else if isToday {
                    RoundedRectangle(cornerRadius: CenitMetrics.chipRadius, style: .continuous).fill(theme.surface)
                    RoundedRectangle(cornerRadius: CenitMetrics.chipRadius, style: .continuous)
                        .strokeBorder(todayRingTint, lineWidth: 1.5)
                } else if hasRoutine {
                    // 2026-07-16 (bug Fer «no se actualizan los cuadritos»): un día asignado solo cambiaba
                    // el tinte de la LETRA — invisible. Se le puso un wash con anillo suave, pero seguía
                    // leyéndose como descanso (bug Fer 2026-07-18: «el martes tiene rutina y no aparece»):
                    // `tintFill` + `strokeSoft` a 1pt desaparecen sobre el papel. Ahora el CONTORNO lleva
                    // el color a plena opacidad y el relleno es papel: la diferencia vive en el cuadro,
                    // que es lo que se mira, y no en una letra de 10pt. Lleno = hecho, contorno =
                    // planeado pendiente, liso = descanso — tres estados que ya no se confunden.
                    RoundedRectangle(cornerRadius: CenitMetrics.chipRadius, style: .continuous)
                        .fill(theme.paper)
                    RoundedRectangle(cornerRadius: CenitMetrics.chipRadius, style: .continuous)
                        .strokeBorder(routineTint(region), lineWidth: 2)
                } else {
                    RoundedRectangle(cornerRadius: CenitMetrics.chipRadius, style: .continuous).fill(theme.patternBlock)
                }
            }
            // FER-85 (decisión del dueño): los cuadros CONSERVAN lo que dicen —el desvío del plan
            // en doble color y el toque por día— y solo cambian de piel para hacer juego con la
            // sección nueva: el token de la semana en vez de un 26 suelto.
            .frame(width: EntrenarMetrics.weekToken, height: EntrenarMetrics.weekToken)
            .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: EntrenarMetrics.row)   // HIG tap target (FER-947) — el dibujo es menor; la celda absorbe
        .contentShape(Rectangle())

        if let routineId {
            Button { openRoutine(routineId) } label: { cell }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: a11y))
        } else {
            cell
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: a11y))
        }
    }

    /// VoiceOver label for a week-strip day: weekday + trained / assigned / rest (and «today» when it is).
    private func weekStripAccessibilityLabel(_ wd: Int) -> String {
        let head: String = {
            if wd == todayWeekday { return String(localized: "Today") }
            return Calendar.current.standaloneWeekdaySymbols[(wd - 1) % 7]
        }()
        if let name = trainedThisWeek(wd) {
            if name.isEmpty { return String(localized: "\(head), trained") }
            return String(localized: "\(head), you trained \(name)")
        }
        if let rid = split[wd], let name = routinesById[rid]?.name {
            return String(localized: "\(head), assigned to \(name)")
        }
        return String(localized: "\(head), rest day")
    }

    // MARK: - «Formas de entrenar» — the six training doors, always visible at the foot (FER-787)
    //
    // No longer a collapsible button (FER-783): the six doors sit as a permanent icon row below Constancia,
    // at the foot of the screen. Color still lands ONLY on the datum (each icon's data-token tint over
    // paper), so no raw hex or new tokens.

    private struct FormOption: Identifiable {
        let icon: String            // SF Symbol — native, static
        let label: LocalizedStringKey
        let hint: LocalizedStringKey
        let tint: Color
        let action: () -> Void
        var id: String { icon }
    }

    /// The five training doors in the icon grid. Diet sits as a quiet full-width row below (not a chip).
    /// Icons are native SF Symbols, static (FER-944, «reposo + toque»). Labels + hints are
    /// `LocalizedStringKey`, so the disc row follows the app language (es/en).
    private var formOptions: [FormOption] {
        [
            FormOption(icon: "bolt.fill", label: "Quick",
                       hint: "Starts a quick strength session, no routine.",
                       tint: theme.dataStrain) { startQuickStrength() },
            FormOption(icon: "timer", label: "Intervals",
                       hint: "Opens the interval timer.",
                       tint: theme.dataSleep) { openIntervals() },
            FormOption(icon: "figure.run", label: "Mobility",
                       hint: "Starts a guided mobility session.",
                       tint: theme.dataHrv) { startMobilityFromDisc() },
            FormOption(icon: "wind", label: "Breathe",
                       hint: "Opens guided breathing.",
                       tint: theme.dataRecovery) { openBreathe() },
        ]
    }

    /// The five discs alone — they now ride the hero, directly under «Empezar» (FER-939, the FER-920
    /// placement decision finally applied). No overline: their position IS the label. Static icons at
    /// rest; the only motion is the press feedback when you tap one (FER-944, «reposo + toque»).
    private var formasDiscos: some View {
        HStack(alignment: .top, spacing: CenitMetrics.space2) {
            ForEach(formOptions) { opt in
                formChip(opt)
            }
        }
    }

    /// Quiet standalone foot row at the very bottom: history («consultar»), distinct from the discs'
    /// «empezar» (mock 1a / v4b).
    ///
    /// FER-92: la fila de Dieta llevaba comentada desde FER-992 y su cableado seguía vivo (el
    /// closure viajaba por dos vistas hasta una ruta que nadie podía alcanzar). El dueño pidió
    /// retirar la ruta muerta; la PANTALLA (`DietCaptureView`) se queda intacta, esperando su issue.
    private var footRows: some View {
        VStack(alignment: .leading, spacing: 0) {
            utilityRow(icon: "chart.line.uptrend.xyaxis", label: "Mis entrenamientos y progreso") { openHistory() }
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
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)   // HIG tap target (FER-944)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// One card chip in the «Formas de entrenar» row (FER-939): the handoff's square card SHAPE
    /// (rounded rect, label inside) carrying the FER-920 «troquel» color — solid data-token fill,
    /// glyph AND label knocked out in paper. The dark `dataEdge` rim is gone (FER-944): the solid
    /// fill on paper cuts itself out; less line, more instrument. Static native icon; the only motion
    /// is the press feedback (`DiscPressStyle`). Runs its door's action.
    private func formChip(_ opt: FormOption) -> some View {
        Button {
            opt.action()
        } label: {
            VStack(spacing: CenitMetrics.space1 + 1) {
                Image(systemName: opt.icon).font(StrandFont.glyph(.lead, weight: .semibold))
                    .foregroundStyle(theme.paper)
                    .frame(height: 20)   // equal glyph slot — SF symbols vary in intrinsic height
                    .accessibilityHidden(true)
                // Uniform label (FER-944): the real cause of the uneven look was the 2pt letter-spacing,
                // which inflated the long words («Intervalos»/«Movilidad») until they scaled down while
                // the short ones didn't. Tight tracking at 9pt lets ALL five fit on one line at the SAME
                // size; the minimumScaleFactor is only a safety net for the largest Dynamic Type steps.
                Text(opt.label)
                    .font(InstrumentoType.groteskOverlineSmall).tracking(0.2)
                    .foregroundStyle(theme.paper)
                    .multilineTextAlignment(.center)
                    .lineLimit(2).minimumScaleFactor(0.9)   // AX5: the long labels wrap instead of truncating
            }
            .padding(.vertical, CenitMetrics.gap - 1)
            .padding(.horizontal, CenitMetrics.space1)
            .frame(maxWidth: .infinity, minHeight: 52)   // HIG tap target + a touch taller for even discs
            .background(opt.tint, in: RoundedRectangle(cornerRadius: CenitMetrics.controlRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(DiscPressStyle())
        .accessibilityLabel(opt.label)
        .accessibilityHint(opt.hint)
    }

    /// «En vivo» from the expanded pill: start (or resume) the live HR workout and present its sheet — the
    /// same door `RestDayScreen`/`OtherWaysScreen` use, so it lands directly without the 3e chooser.

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
        let months = constancyMonthsCache
        let total = months.reduce(0) { $0 + $1.count }
        return VStack(alignment: .leading, spacing: 12) {
            InstrumentoSectionBand("Consistency") {
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
                .groteskOverline()
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
        // Expand the hit/VO frame to ≥44pt without growing the visible 14pt dot: pad out, shape, then
        // cancel the layout growth with equal negative padding (FER-947).
        let hitPad = max(0, (44 - cell) / 2)
        let inMonth = day <= m.daysInMonth
        let trainedName = inMonth ? m.trained[day] : nil
        ZStack {
            if inMonth {
                Circle().fill(theme.hairlineStrong).frame(width: 4, height: 4)
                if let name = trainedName {
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
        .padding(hitPad)
        .contentShape(Rectangle())
        .onTapGesture {
            guard let name = trainedName else { return }
            constancyPopup = ConstancyPopup(monthId: m.id, day: day, name: name)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: inMonth ? dayCellAccessibilityLabel(m, day: day) : ""))
        .accessibilityAddTraits(trainedName != nil ? .isButton : [])
        .accessibilityHidden(!inMonth)
        .padding(-hitPad)
        .popover(isPresented: Binding(
            get: { constancyPopup?.monthId == m.id && constancyPopup?.day == day },
            set: { if !$0 { constancyPopup = nil } }
        )) {
            if let popup = constancyPopup { constancyPopoverContent(popup, month: m) }
        }
    }

    /// VoiceOver label for a Constancia day: date + trained-with-routine / no training / today.
    private func dayCellAccessibilityLabel(_ m: ConstancyMonth, day: Int) -> String {
        let isToday = m.isCurrent && day == todayDayOfMonth
        let head: String = {
            if isToday { return String(localized: "Today") }
            guard let date = Calendar.current.date(from: DateComponents(year: m.year, month: m.month, day: day)) else {
                return "\(day)"
            }
            return date.formatted(.dateTime.day().month(.wide))
        }()
        if let name = m.trained[day] {
            if name.isEmpty { return String(localized: "\(head), trained") }
            return String(localized: "\(head), you trained \(name)")
        }
        return String(localized: "\(head), no training")
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
            return constancyMonthsCache.first { $0.year == y && $0.month == mo }?.trained[d]
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
        // `presentationBackground` paints the popover container AND its anchor arrow in one paper
        // piece — a plain `.background` leaves the arrow in the system tint (same seam PaperMenu had).
        .presentationBackground(theme.surface)
        .presentationCompactAdaptation(.popover)
    }

    // MARK: - Empty state B (no split yet → build the week)

    private var emptyStateB: some View {
        VStack(spacing: 14) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 36, weight: .regular)).foregroundStyle(theme.inkTertiary).accessibilityHidden(true)  // token-exempt: glifo 36pt fuera de banda empty
            Text("No plan yet").font(InstrumentoType.groteskHeadline(20)).foregroundStyle(theme.ink).multilineTextAlignment(.center)
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
                Text("We couldn't read your routines").font(InstrumentoType.groteskHeadline(20)).foregroundStyle(theme.ink)
                Text("Something went wrong opening your data.")
                    .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                StrandCTAButton("Retry", kind: .outline) { Task { await load() } }
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

    /// Localized short weekday letter (respects locale), single character. Solo para la TIRA de 7 celdas:
    /// ahí la posición desambigua, igual que en cualquier calendario. Fuera de esa retícula usa
    /// `weekdayShort`, porque la inicial sola es ambigua —«M» es martes Y miércoles en español, y en
    /// inglés «T» es Tuesday Y Thursday.
    private func weekdayLetter(_ wd: Int) -> String {
        let s = Calendar.current.veryShortWeekdaySymbols[(wd - 1) % 7]
        return s.uppercased()
    }

    /// Localized two-letter weekday, para cuando NO hay retícula que desambigüe (el subtítulo «Ma · Sá» de
    /// una rutina del plan). Sale de `shortWeekdaySymbols` («mar» → «Ma»), así que respeta el idioma:
    /// es-MX da Lu/Ma/Mi/Ju/Vi/Sá/Do y en inglés Mo/Tu/We/Th/Fr/Sa/Su, ambos sin repetidos.
    private func weekdayShort(_ wd: Int) -> String {
        let s = Calendar.current.shortWeekdaySymbols[(wd - 1) % 7]
        return s.prefix(2).capitalized
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
    /// Called once per `load()` into `constancyMonthsCache` (FER-948) — not from the view body.
    private func computeConstancyMonths() -> [ConstancyMonth] {
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
            let days = (daysOf[id] ?? []).map(weekdayShort).joined(separator: " · ")
            return (id, n, days)
        }
    }

    /// «También en tu plan» lists every scheduled routine EXCEPT today's (which is the hero).
    private var otherPlanRoutines: [(routineId: String, name: String, days: String)] {
        planRows.filter { $0.routineId != todayRoutineId }
    }

    /// Rutinas SIN día asignado (2026-07-16, bug Fer): una rutina recién creada no aparecía en
    /// NINGÚN lado del hub (la lista era solo el split). Van al final con «—» de días.
    private var unscheduledRoutines: [Routine] {
        let scheduled = Set(split.values)
        return routines.filter { !scheduled.contains($0.id) }
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

    /// El hilo del veredicto: la misma pastilla que es la puerta de Hoy, construida por el MISMO
    /// constructor (`LiquidHoyBuilder.hiloEntrenar`) para que las dos pantallas no puedan divergir.
    ///
    /// Derivarlo aquí por mi cuenta ya había producido dos contradicciones que el gate cazó: decía
    /// la palabra-veredicto las mañanas en que Hoy la retira por no tener la noche anclada, y
    /// colapsaba los tres estados sin veredicto en «Conociéndote», que le decía «te estoy
    /// conociendo» a quien nunca conectó Apple Salud.
    @ViewBuilder private var hiloDelVeredicto: some View {
        if let hilo = LiquidHoyBuilder.hiloEntrenar(
            prep: repo.todayPreparedness,
            nights: repo.todayPreparedness?.autonomicNights ?? 0,
            healthConnected: healthConnected,
            verdictPending: repo.todayPreparedness == nil && !repo.fullyLoaded,
            hasPlan: todayRoutine != nil) {
            EntrenarHilo(tone: hiloTono(hilo.tono),
                         word: LocalizedStringKey(hilo.palabra),
                         advice: hilo.consejo.map { LocalizedStringKey($0) },
                         hint: "Opens today's ballot") {
                showVeredictoActa = true
            }
        }
    }

    private func hiloTono(_ t: LiquidHoyBuilder.HiloEntrenar.Tono) -> EntrenarHilo.Tone {
        switch t {
        case .claro:    return .clear
        case .atencion: return .caution
        case .alerta:   return .ease
        case .hueco:    return .hollow
        }
    }

    /// Whether the hero may explain a held raise. Silence must be total: with no usable read (or none
    /// yet) the section neither advises nor announces a raise it is holding.
    private var showsHeldRaise: Bool { TrainingRegulation.explainsHeldRaise(advice) }


    // MARK: - Data

    /// Rebuild the whole screen from the store. Returns whether THIS pass published its work: false
    /// when the store is unavailable or a newer pass won the race, so a caller that depends on fresh
    /// slots (the «Empezar» rebuild) can tell «rebuilt» from «gave up» (FER-82).
    @discardableResult
    private func load() async -> Bool {
        loadFailed = false   // clear on every (re)try
        // Sequence guard, same as TodayView/CuerpoView: `.task(id:)` cancels the old pass but none of
        // the awaits below is a cancellation point, so without this an in-flight pre-verdict load
        // would still reach the end and overwrite the post-verdict one it lost the race to (FER-82).
        let seq = repo.refreshSeq
        guard let store = await repo.storeHandle() else { loadFailed = true; loaded = true; return false }
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
        var raisingToday: [(name: String, kg: Double)] = []
        var heldToday: [(name: String, kg: Double)] = []
        // The verdict this whole pass was built with, published together with the slots it seeded.
        var passAdvice = repo.trainingAdvice
        if let tid = WeeklySplit.todayRoutineId(split: splitMap, todayWeekday: todayWeekday) {
            let exs = (try? await store.routineExercises(routineId: tid)) ?? []
            let custom = (try? await store.customExercises()) ?? []
            let customByID = Dictionary(custom.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let overrides = (try? await store.exerciseTypeOverrides()) ?? [:]
            // FER-E/G: «la última vez» + progression per slot, via the ONE `sessionSeed` implementation
            // the «Rutina» editor also calls — the raise the hero names is exactly the raise it seeds.
            let inventory = await MainActor.run { PlatesStore().inventory }
            // One verdict for the whole table (FER-82): read before the loop, never inside it.
            let advice = repo.trainingAdvice
            passAdvice = advice
            var raising: [(name: String, kg: Double)] = []
            var held: [(name: String, kg: Double)] = []
            for re in exs {
                let ex = (ExerciseCatalog.byID(re.exerciseId) ?? customByID[re.exerciseId])?.applying(overrides)
                let seed = await repo.sessionSeed(re: re, exercise: ex, inventory: inventory, advice: advice)
                if let raise = seed.evaluation?.raise {
                    let name = ex.map(StrengthDisplay.name) ?? re.exerciseId
                    // One evaluation, two readings: applied to the seed, or held by today's verdict.
                    if raise.waiting { held.append((name: name, kg: raise.toKg)) }
                    else { raising.append((name: name, kg: raise.toKg)) }
                }
                slots.append(.init(re: re, exercise: ex, lastSets: seed.lastSets, raise: seed.evaluation?.raise))
            }
            raisingToday = raising
            heldToday = held
        }
        let recent = (try? await store.recentSessions(limit: 200)) ?? []
        // Every read is done: from here on there is no await, so the publish below is atomic. A pass
        // that lost the race drops its work y NO toca `loaded`: el pase ganador ya está en vuelo y lo
        // encenderá con datos. Encenderlo aquí pintaba el estado de PRIMER USO («Empecemos por tu
        // plan») a alguien que sí tiene plan — cambiar un parpadeo en blanco por una mentira.
        guard seq == repo.refreshSeq else { return false }
        raisesToday = raisingToday
        deferredToday = heldToday
        slotsAdvice = passAdvice
        routines = rs
        exerciseCounts = counts
        routineMuscles = muscles
        routineCategory = categories
        split = splitMap
        todaySlots = slots
        sessions = recent
        // After sessions + routines (→ routinesById): bucket once for Constancia + week strip (FER-948).
        constancyMonthsCache = computeConstancyMonths()
        loaded = true
        // A «Empezar» from the Daily Brief that arrived before the prefetch finished now has its slots (FER-613).
        if startWhenLoaded { startWhenLoaded = false; startToday() }
        return true
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

// MARK: - Disc press feedback (FER-944 · «reposo + toque»)
//
// The discs sit still; the only motion is the tactile press — the chip dips slightly and springs back
// when tapped, so the tap registers physically. Feedback, not decoration (HIG). Reduce Motion drops
// the scale to a plain opacity dip so there's still a press cue without movement.

private struct DiscPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(!reduceMotion && configuration.isPressed ? 0.93 : 1)
            .opacity(reduceMotion && configuration.isPressed ? 0.7 : 1)
            .animation(StrandMotion.interactive, value: configuration.isPressed)
    }
}

// MARK: - «Hoy descansas. También cuenta.» (v3 · 2B) — a PUSHED screen now (FER-718)
//
// What «Empezar» opens on a rest day, and what the streak row protects. Reframed to the mock: the streak
// is explicitly SAFE (resting does not break it), a card carries the one cited light alternative, a
// quieter «Si aun así quieres entrenar» section lists the other ways, and a footer names tomorrow's
// routine from the split.
//
// FER-82: that card now speaks from the SAME verdict as Hoy and the landing (`repo.trainingAdvice`).
// It used to read the 0–100 score, which meant a rest day could offer an OPTIONAL EXTRA session while
// Hoy was painting «Recupera» — a second oracle, inside Entrenar, recommending the one thing the new
// mapping says it must never recommend. Only «Recupera» surfaces a suggestion here now.

struct RestDayScreen: View {
    var openIntervals: () -> Void
    var openBreathe: () -> Void
    var openRoutines: () -> Void

    @Environment(\.instrumentoTheme) private var theme
    @EnvironmentObject private var repo: Repository
    @Environment(AppModel.self) private var model

    @State private var split: [Int: String] = [:]
    @State private var routineNames: [String: String] = [:]
    /// Inject: recarga en caliente para esta pantalla (dev-only, no-op en Release).
    @ObserveInjection private var inject

    /// The gentler option, from the one oracle: present only when today's verdict is «Recupera».
    private var alt: TrainingRegulation.LightAlternative? {
        TrainingRegulation.lightAlternative(repo.trainingAdvice)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Today you rest").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                Text("Today you rest. It counts too.")
                    .font(InstrumentoType.groteskScreenTitle).tracking(InstrumentoType.groteskScreenTitleTracking)
                    .foregroundStyle(theme.ink).padding(.top, 3)
                    .fixedSize(horizontal: false, vertical: true)

                streakBullet.padding(.top, 16)

                if alt == .softer {
                    suggestedCard.padding(.top, CenitMetrics.sectionGap)
                }

                Text("If you still want to train").instrumentoOverline()
                    .foregroundStyle(theme.inkTertiary).padding(.top, CenitMetrics.sectionGap)
                VStack(spacing: 0) {
                    // Mobility moves up into the card when the day suggests it; the rest of the ways
                    // to move are always here, because this list is a choice, not a recommendation.
                    if alt != .softer { row("figure.cooldown", "Mobility · 20 min") { model.startMobilityOneOff() } }
                    row("timer", "Intervals · 12 min") { openIntervals() }
                    row("list.bullet", "Pick a routine") { openRoutines() }
                    row("wind", "Breathe", last: true) { openBreathe() }
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
        .task { await load() }
        .enableInjection()
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

    /// The one cited light alternative, in a card. Shown only when today's verdict is «Recupera», so
    /// there is a single case to render: the gentler session. The overline names the day's verdict,
    /// not a score — the same word Hoy is showing (FER-82).
    private var suggestedCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Because today you recover").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text("Mobility · 20 min").font(StrandFont.title2).foregroundStyle(theme.ink)
                Text("gentle").font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
                    .padding(.horizontal, 9).padding(.vertical, 2)
                    .background(theme.paper, in: Capsule())
                    .overlay(Capsule().strokeBorder(theme.hairlineStrong, lineWidth: 1))
            }
            .padding(.top, 5)
            StrandCTAButton("Empezar") { model.startMobilityOneOff() }
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
    @Environment(AppModel.self) private var model
    /// Inject: recarga en caliente para esta pantalla (dev-only, no-op en Release).
    @ObserveInjection private var inject

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Another type?").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                Text("Another way to train").font(InstrumentoType.groteskScreenTitle).tracking(InstrumentoType.groteskScreenTitleTracking)
                    .foregroundStyle(theme.ink).padding(.top, 3)

                VStack(spacing: 0) {
                    bigRow("figure.cooldown", "Mobility", subtitle: String(localized: "Gentle · 20 min")) { model.startMobilityOneOff() }
                    bigRow("timer", "Intervals", subtitle: String(localized: "Bursts · 12 min")) { openIntervals() }
                    bigRow("wind", "Breathe", subtitle: String(localized: "Slow it down"), last: true) { openBreathe() }
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
        .enableInjection()
    }

    private func bigRow(_ icon: String, _ title: LocalizedStringKey, subtitle: String, last: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 15) {
                Image(systemName: icon).font(.system(size: 22)).foregroundStyle(theme.inkSecondary).frame(width: 30)  // token-exempt: glifo 22pt fuera de banda lead
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(InstrumentoType.grotesk(16, weight: .semibold)).foregroundStyle(theme.ink)
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

}
#endif
