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
// breathe / live). A rest day is a STATE of this same hero (`heroSectionDescanso`, FER-132): title
// «Descanso», no numerals, a paper «Movilidad» door and the full loaded-muscles module — no separate
// screen. Below the hero, the three handoff levels (FER-131): TU SEMANA · MÚSCULOS CARGADOS · BITÁCORA.
//
// Color appears ONLY on the recovery datum (the today-dot, the Today recovery
// line); everything else is ink on paper. Navigation is owned by the tab's `NavigationStack` in
// RootTabView; the landing pushes via the injected closures and hosts the guided session + sheets here.

/// La boleta del veredicto de Hoy, compartida por la landing de Entrenar (FER-85) y la cabecera de la
/// sesión en vivo (FER-133): el MISMO `LiquidActaVeredicto` con el MISMO contexto, para que ninguna
/// de las dos pantallas pueda contar el día distinto. Sin «Ver más»: ninguna de las dos cambia de
/// pestaña desde aquí, solo cierran la hoja.
struct VeredictoActaSheet: View {
    let prep: Preparedness.Read?
    let healthConnected: Bool
    let fullyLoaded: Bool

    var body: some View {
        LiquidMetricSheet(tono: LiquidHoyBuilder.actaTono(prep), detent: .porContenido) {
            LiquidActaVeredicto(
                LiquidHoyBuilder.acta(prep: prep, healthConnected: healthConnected,
                                      verdictPending: prep == nil && !fullyLoaded),
                onVerMas: nil)
        }
        .preferredColorScheme(.light)
    }
}

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
    /// (F4): reached from the secondary chooser's «Otra rutina».
    var openRoutines: () -> Void
    /// Push «Otra forma de entrenar» (v3 · 3e) — the alternative-training chooser (was a sheet, now a push).
    /// Push a completed strength session's detail (from a «done» day in the week strip).
    var openWorkoutSession: (WorkoutSessionRoute) -> Void
    /// Push «Tu cuerpo» (`MuscleVolumeRoute`, FER-131) — from the landing's «Músculos cargados» line.
    var openMuscleMap: () -> Void

    var body: some View {
        EntrenarLanding(openRoutine: openRoutine,
                        openBreathe: openBreathe, openIntervals: openIntervals,
                        openHistory: openHistory, openWeeklyPlan: openWeeklyPlan,
                        openRoutines: openRoutines,
                        openWorkoutSession: openWorkoutSession, openMuscleMap: openMuscleMap)
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
    var openWorkoutSession: (WorkoutSessionRoute) -> Void
    var openMuscleMap: () -> Void

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
    /// FER-138: TU SEMANA (encabezado y tira) abre la hoja rápida de rotar días — pero solo cuando
    /// ya hay al menos una rutina en el split (`semanaSection`); en primer uso (`split` vacío,
    /// `primerUsoSection`) TU SEMANA sigue abriendo el editor completo vía `openWeeklyPlan`, porque
    /// la hoja rápida solo rota entre rutinas YA programadas y no tiene forma de asignar la primera.
    /// «Editar rutinas y semana ›» (`utilityRow` en `semanaSection`) también sigue llevando a
    /// `WeeklyPlanEditorView` vía `openWeeklyPlan`.
    @State private var showWeekEditorSheet = false
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    private var unitSystem: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }
    /// El MISMO «Marcar todo recuperado» que lee `TrainingBodyScreen` (FER-525): sin este filtro
    /// «Músculos cargados» seguía anunciando una espalda cargada después de que el atleta ya la
    /// marcó fresca en «Tu cuerpo» — la misma línea, dos respuestas.
    @AppStorage("muscleRecoveryResetAt") private var muscleRecoveryResetAt: Double = 0
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
    /// FER-131 «Niveles»: per-muscle load events over the trailing 84 days — the SAME engine
    /// (`MuscleFatigueMap`, via `repo.muscleSetEvents`) `TrainingBodyScreen` reads, never a second
    /// derivation of the map. Feeds the «Músculos cargados» line only; empty ⇒ that level stays hidden.
    @State private var muscleEvents: [MuscleFatigueMap.MuscleSetEvent] = []
    /// Per-session volume/set count, keyed by session id (FER-131 · Bitácora rows) — one aggregate read.
    @State private var sessionVolumes: [String: (volumeKg: Double, setCount: Int)] = [:]
    /// How many personal records landed inside each of the two most-recent sessions (FER-131 · el chip
    /// «N marca(s)»), keyed by session id. Only computed for the rows the landing actually shows.
    @State private var bitacoraMarcas: [String: Int] = [:]
    /// El pliegue de «Otra forma»: privado de la vista y SIN persistir — cada visita abre cerrado.
    @State private var otraFormaAbierta = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The Daily Brief's «Empezar» arrived (via `TabRouter`) before this view finished loading its
    /// prefetched slots — start today's session as soon as `load()` completes (FER-613).
    @State private var startWhenLoaded = false
    /// Presents the live-HR workout sheet from the «Formas de entrenar» → «En vivo» chip (the same sheet
    /// «Otra forma» presents).
    /// Presents the starter-templates list from the first-use «Rutinas de plantilla» row (mock 5a).
    @State private var showTemplates = false
    /// FER-952: the hub's Import door-chip.
    @State private var showHubImport = false
    /// «Lo que Cénit sabe hacer» (decisión Fer 2026-07-16): puerta permanente + tarjeta única.
    @State private var showTricks = false
    /// FER-952: the hub's «New routine» — pushes the unified create flow (library → editor).
    @State private var showCreateRoutine = false
    /// FER-137: «Crear plan» — the single door into «Tres caminos» (plantillas / desde cero / importar).
    @State private var showCreatePlan = false
    /// Success toast after a template group is applied from `CrearPlanScreen` — auto-dismisses.
    @State private var showPlanAppliedToast = false
    /// FER-950: Quick / Mobility discs with a live strength session — confirm resume instead of
    /// silently re-presenting via `startStrengthSession`'s no-op guard (which looks like "start new").
    @State private var confirmResumeStrength = false
    @State private var saveError = false
    /// «Terminar sesión ›» del héroe de sesión viva (FER-132 · ⑤): el MISMO confirm de descarte que
    /// el pill flotante ya presenta desde `RootTabView` — solo que la landing no tiene acceso a ese
    /// binding, así que sostiene el suyo propio y llama al mismo `endStrengthSession(save: false)`.
    @State private var confirmEndLiveSession = false

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
            // Ritmo 1b (handoff FER-130): el VStack raíz ya no reparte un `sectionGap` uniforme —
            // cada bloque carga su propio margen superior, así que la cabecera / el hilo / el héroe
            // pueden llevar el aire literal del handoff sin heredar uno genérico encima. Los estados
            // fuera de alcance (sin plan, error de carga) conservan el `sectionGap` de antes como su
            // propio padding explícito, para no moverles ni un punto.
            VStack(alignment: .leading, spacing: 0) {
                // FER-952 (owner): the «Train» wordmark + tab glyph row retired — the dock already
                // names the tab.
                // FER-130: la cabecera del hub — «Entrenar · {fecha}» a la izquierda, el «?» de los
                // trucos a la derecha. Reemplaza al wordmark retirado arriba; vive FUERA del gate de
                // carga porque no depende del plan.
                cabecera
                // FER-85: el hilo del veredicto — el ÚNICO portador del veredicto en Entrenar y la
                // primera cosa que se lee del cuerpo. Vive FUERA del gate de carga porque habla del
                // CUERPO, no del plan: no tiene por qué esperar a que la base de datos conteste.
                //
                // FER-132 §5: con `loadFailed` el hilo se OCULTA — el hilo habla del cuerpo, pero
                // esta pantalla ya no pudo leer NADA de la base, y un veredicto flotando sobre un
                // error de lectura sugiere que el resto sí cargó cuando no fue así.
                if !loadFailed {
                    hiloDelVeredicto.padding(.top, CenitMetrics.space2)
                }
                if loaded {
                    if loadFailed {
                        loadErrorState       // §5 — «No pude leer tu plan» + Reintentar, niveles ocultos
                            .padding(.top, CenitMetrics.sectionGap)
                    } else if let live = model.strengthSession {
                        // ⑤ Sesión viva: gana sobre CUALQUIER otro estado — incluido «sin plan todavía»
                        // (un entrenamiento rápido, sin rutina, puede arrancar sin split armado). Sin
                        // «Otra forma» ni Músculos (el prototipo excluye la línea de músculos con
                        // `s.viva` — `muestraMuscLinea`) — pero SÍ Bitácora: `muestraBitacora` del
                        // prototipo NO excluye `s.viva` (a propósito, `bitacoraDef` incluso define una
                        // fila dedicada para ese caso), así que la sesión que corre no calla el
                        // historial de las que ya cerraron. TU SEMANA SIEMPRE debajo, con o sin split:
                        // `muestraSemana` del prototipo solo se apaga en `errorLectura`; sin plan la
                        // tira cae en contornos vacíos y el valor dice «toca un día ›».
                        heroSectionSesionViva(live)
                            .padding(.top, EntrenarMetrics.heroKickerTop)
                        semanaSection
                            .padding(.top, EntrenarMetrics.firstLevelTop)
                        if !recentSessions90.isEmpty {
                            bitacoraSection
                                .padding(.top, EntrenarMetrics.levelTop)
                        }
                    } else if split.isEmpty {
                        primerUsoSection     // ④ Primer uso — «Arma tu semana» + plantillas + Crear mi plan
                            .padding(.top, EntrenarMetrics.heroKickerTop)
                    } else {
                        // FER-131 «Niveles»: los tres niveles del handoff, en el orden del prototipo —
                        // TU SEMANA (tira de tokens) → MÚSCULOS CARGADOS (estimación, una línea, o el
                        // módulo completo en descanso — FER-132) → BITÁCORA (2 filas + puerta). La
                        // rejilla de 90 días (Constancia) se retira: el handoff la tumba (§11), el dato
                        // vive en Bitácora → Historial. Ritmo 1b (FER-130): cada nivel carga su propio
                        // margen — primer nivel 18, los siguientes 2.
                        heroSection       // ① en rango / ② recupera / ③ descanso
                            .padding(.top, EntrenarMetrics.heroKickerTop)
                        semanaSection     // TU SEMANA — week tokens + every OTHER routine + new-routine row
                            .padding(.top, EntrenarMetrics.firstLevelTop)
                        if sessions.isEmpty {
                            // «Músculos cargados y Bitácora aparecen después de tu primera sesión.
                            // Mientras, silencio.» — plan armado, cero sesiones registradas todavía (§5).
                            silencioPrimeraSesion
                                .padding(.top, EntrenarMetrics.levelTop)
                        } else if todayRoutine == nil {
                            // ③ Descanso: el módulo completo de músculos reemplaza la línea (FER-132).
                            // Ronda 3 (grok, menor): mismo guard que `muscleSection` — sin sets recientes
                            // el módulo no tiene nada que mostrar (encabezado + columnas vacías).
                            if !muscleLoads.isEmpty {
                                muscleSectionModulo
                                    .padding(.top, EntrenarMetrics.levelTop)
                            }
                            bitacoraSection
                                .padding(.top, EntrenarMetrics.levelTop)
                        } else {
                            if !muscleLoads.isEmpty {
                                muscleSection   // MÚSCULOS CARGADOS — una línea, estimación
                                    .padding(.top, EntrenarMetrics.levelTop)
                            }
                            bitacoraSection     // BITÁCORA — 2 filas + «Historial y progreso ›»
                                .padding(.top, EntrenarMetrics.levelTop)
                        }
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
        // FER-137: el eco de «Plantilla aplicada» tras volver de `CrearPlanScreen`.
        .planAppliedToast(isPresented: $showPlanAppliedToast)
        // La boleta del veredicto, dentro de Entrenar (FER-85): el mismo modelo y la misma vista
        // que sirve Hoy, así que las dos pantallas no pueden divergir ni en la tabla ni en la
        // gráfica de cajas. «Ver más» cierra la hoja sin cambiar de pestaña.
        .sheet(isPresented: $showVeredictoActa) {
            // El MISMO contexto que Hoy le pasa a su acta: sin `healthConnected` la hoja afirmaba
            // «anoche no llegó nada» a quien simplemente no ha conectado Salud, y sin él las dos
            // pantallas contaban historias distintas del mismo día — justo lo que este épico mata.
            // `VeredictoActaSheet` (compartida con `LiveStrengthSheet`, FER-133) es el único sitio que
            // arma este contenido, para que las dos pantallas no puedan divergir.
            VeredictoActaSheet(prep: repo.todayPreparedness, healthConnected: healthConnected,
                               fullyLoaded: repo.fullyLoaded)
        }
        // FER-138: la hoja rápida de rotar días — TU SEMANA (encabezado y tira) la abre, en las dos
        // secciones que la muestran. `$split` es un binding: rotar un día en la hoja actualiza esta
        // misma landing al instante, sin esperar a que la hoja cierre.
        .sheet(isPresented: $showWeekEditorSheet) {
            WeekEditorSheet(theme: theme, split: $split, routines: routines,
                            orderedWeekdays: orderedWeekdays, todayWeekday: todayWeekday,
                            doneWeekdays: Set(orderedWeekdays.filter { trainedThisWeek($0) != nil }),
                            dayLetter: weekdayLetter)
                .environmentObject(repo)
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
        // FER-137: «Crear plan» — la puerta única de «Tres caminos».
        .navigationDestination(isPresented: $showCreatePlan) {
            CrearPlanScreen(openRoutine: openRoutine, onChange: { await load() }) {
                showPlanAppliedToast = true
            }
        }
        .navigationDestination(isPresented: $showTricks) {
            WorkshopTricksScreen()
        }
        // «En vivo» from the expanded «Más formas» pill — the live-HR free workout, the same sheet
        // «Otra forma» presents (theme passed explicitly; it doesn't cross `.sheet`).
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
        // «Terminar sesión ›» del héroe de sesión viva (FER-132 · ⑤): la MISMA copia y la MISMA
        // acción que el ✕ del pill flotante ya usa en `RootTabView` — un solo confirm de descarte,
        // repetido a propósito porque cada anfitrión sostiene su propio `@State`.
        .instrumentoConfirm(
            isPresented: $confirmEndLiveSession,
            title: String(localized: "Discard this session?"),
            context: String(localized: "SESSION · IN PROGRESS"),
            message: String(localized: "Its logged sets won't be saved."),
            actions: [
                .init(String(localized: "Keep training"), role: .primary),
                .init(String(localized: "Discard session"), role: .destructive) {
                    model.endStrengthSession(save: false)
                }
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
        Group {
            if let r = todayRoutine {
                heroSectionRoutineDay(r)
            } else {
                heroSectionDescanso
            }
        }
    }

    /// ① En rango / ② Recupera: el héroe con la rutina de hoy. Sin cambios de fondo (FER-132 solo
    /// toca los OTROS estados) salvo el kicker, que ya lee el consejo de hoy (`hoyOverline`).
    private func heroSectionRoutineDay(_ r: Routine) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(hoyOverline)
                .entrenarCabeceraKicker().foregroundStyle(theme.inkTertiary)
            // «Bisel»: la marca de familia es una regla vertical, no un cuadro en línea. El cuadro vivía
            // dentro del HStack, así que le robaba ancho al título y lo empujaba a la derecha; con
            // nombres de dos líneas el bloque perdía el eje. Ahora la REGLA marca el margen —queda a
            // plomo con «Empezar» y los discos— y el texto se indenta después de ella, en vez de que
            // la regla se salga al canalón. Su alto lo deriva del contenido: crece sola con la segunda
            // línea y con Dynamic Type.
            //
            // Ritmo 1b (FER-130): cada línea carga su propio margen superior (`EntrenarMetrics`),
            // ya no un espaciado uniforme de 8 — título, subtítulo, numerales y progresión llevan
            // aire distinto en el handoff.
            VStack(alignment: .leading, spacing: 0) {
                Text(r.name)
                    .font(InstrumentoType.grotesk(32, weight: .bold)).tracking(-1)
                    .foregroundStyle(theme.ink)
                    .lineLimit(2).minimumScaleFactor(0.65)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, EntrenarMetrics.heroTitleTop)
                // §5 «plan sin sesiones» (FER-132 ronda 2): cero sesiones registradas todavía ⇒ el
                // subtítulo lo dice — «tu plan está listo · primera vez con esta rutina» (copy.md,
                // prototipo `planNuevo.sub`) — en vez de la línea de músculos, que hoy no tiene una
                // «última vez» real que anunciar.
                if sessions.isEmpty {
                    Text("Your plan is ready · first time with this routine")
                        .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, EntrenarMetrics.heroSubTop)
                } else if let muscles = routineMuscleLine(r.id) {
                    Text(muscles).font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                        .padding(.top, EntrenarMetrics.heroSubTop)
                }
                // Los tres numerales suben al héroe (handoff v2 §4): la forma de la sesión se lee
                // junto a su nombre, no tres bloques abajo. Y son la ÚNICA marca de familia del
                // bloque — la regla vertical teñida que iba junto al nombre se retiró: dos marcas
                // del mismo color en el mismo sitio es decir la identidad dos veces.
                sesionMetrics(r.id).padding(.top, EntrenarMetrics.heroNumeralsTop)
                subidaDelDia.padding(.top, EntrenarMetrics.heroProgressTop)
            }
            // Fila CTA (FER-130, handoff «Ritmo 1b»): «Empezar» y «Otra forma ›» viven en la MISMA
            // fila ahora — antes «Otra forma» ocupaba su propia fila debajo. El enlace conserva su
            // pliegue (decisión del dueño): lo que se despliega se inserta DEBAJO de la fila entera,
            // no dentro de ella. Con Dynamic Type grande, `ViewThatFits` apila los dos en vez de
            // recortarlos.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: EntrenarMetrics.ctaRowGap) {
                    empezarButton
                    otraFormaEnlace(fillsWidth: false)
                }
                VStack(alignment: .leading, spacing: CenitMetrics.space2) {
                    empezarButton
                    otraFormaEnlace(fillsWidth: false)
                }
            }
            .padding(.top, EntrenarMetrics.ctaRowTop)
            otraFormaPliegue
        }
    }

    /// ③ Descanso (+ leve): el héroe del handoff «Descanso» — título a 40 pt, SIN numerales ni
    /// progresión (no hay sesión que medir), y la única puerta es «Movilidad · 20 min» en papel. El
    /// hilo de arriba ya pinta ámbar cuando el consejo de hoy es `.lighter`; este bloque solo añade
    /// la cláusula de texto — nunca reordena ni repite el veredicto.
    private var heroSectionDescanso: some View {
        VStack(alignment: .leading, spacing: 0) {
            // FER-132 ronda 2: kicker FIJO «Hoy» — copy literal del prototipo (`descansoLeve.hk: "Hoy"`,
            // sin el día). `hoyOverline` interpola el día para los héroes con rutina; reusarlo aquí
            // colaba «Hoy · Martes» en cualquier descanso que no fuera `.recover`.
            Text("Today").entrenarCabeceraKicker().foregroundStyle(theme.inkTertiary)
            Text("Rest")
                .font(InstrumentoType.grotesk(EntrenarMetrics.restHeroTitle, weight: .bold)).tracking(-1)
                .foregroundStyle(theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, EntrenarMetrics.heroTitleTop)
            Text(descansoSubtitulo)
                .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, EntrenarMetrics.heroSubTop)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: EntrenarMetrics.ctaRowGap) {
                    movilidadButton
                    otraFormaEnlace(fillsWidth: false)
                }
                VStack(alignment: .leading, spacing: CenitMetrics.space2) {
                    movilidadButton
                    otraFormaEnlace(fillsWidth: false)
                }
            }
            .padding(.top, EntrenarMetrics.ctaRowTop)
            otraFormaPliegue
        }
    }

    /// «Movilidad · 20 min» — papel, la única puerta del héroe de descanso (copy.md «Héroe»).
    private var movilidadButton: some View {
        StrandCTAButton("Mobility · 20 min", kind: .outline, fillsWidth: false) { startMobilityFromDisc() }
    }

    /// «tu semana marca descanso» + (si el consejo de hoy es `.lighter`) la cláusula ámbar del
    /// handoff — LA MISMA señal que ya tiñe el hilo de arriba, nombrada en el subtítulo.
    private var descansoSubtitulo: String {
        advice == .lighter
            ? String(localized: "Your week marks rest · you woke up with a signal off")
            : String(localized: "Your week marks rest")
    }

    /// ⑤ Sesión viva: el héroe entero habla de la sesión en curso, no del plan del día — kicker «EN
    /// CURSO · N MIN», el nombre de la rutina que corre (puede no ser la de hoy — FER-86), el avance
    /// como numerales, y SOLO «Continuar» + «Terminar sesión»: sin «Otra forma» (ya hay una sesión
    /// abierta) y sin progresión (no hay subida que anunciar a mitad de sesión).
    private func heroSectionSesionViva(_ session: StrengthSessionModel) -> some View {
        // FER-132 ronda 2: `TimelineView` — igual que `ActiveSessionPillHost`, el pill que este héroe
        // reemplaza en Entrenar — para que «N min» avance solo mientras la landing está en pantalla,
        // en vez de quedarse congelado hasta el siguiente cambio de estado ajeno.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            heroSesionVivaBody(session, now: context.date)
        }
    }

    private func heroSesionVivaBody(_ session: StrengthSessionModel, now: Date) -> some View {
        let minutes = max(0, session.elapsedSeconds(now: now) / 60)
        let progress = liveSessionProgress(session)
        let accent = routineTint(region(name: session.routineName))
        return VStack(alignment: .leading, spacing: 0) {
            Text(String(localized: "In progress · \(minutes) min"))
                .entrenarCabeceraKicker().foregroundStyle(theme.inkTertiary)
            Text(session.routineName)
                .font(InstrumentoType.grotesk(32, weight: .bold)).tracking(-1)
                .foregroundStyle(theme.ink)
                .lineLimit(2).minimumScaleFactor(0.65)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, EntrenarMetrics.heroTitleTop)
            Text(liveSessionSubtitle(session, progress))
                .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                .padding(.top, EntrenarMetrics.heroSubTop)
            HStack(alignment: .firstTextBaseline, spacing: EntrenarMetrics.heroNumeralsGap) {
                bigStat(Text(verbatim: "\(minutes)"), unit: Text("min"), valueColor: accent)
                // Ronda 3 (ux, grave): una sesión rápida sin rutina arranca con `activeExercises`/`runs`
                // vacíos — sin este guard se mostraba «0 / 0» tanto de ejercicio como de series, justo
                // lo que `liveSessionSubtitle` (línea 557) ya evita con el mismo dato.
                if progress.total > 0 {
                    bigStat(Text(verbatim: "\(progress.index)"), unit: Text(verbatim: "/ \(progress.total)"), valueColor: accent)
                }
                if progress.totalSets > 0 {
                    bigStat(Text(verbatim: "\(progress.doneSets)"),
                            unit: Text(verbatim: "/ \(progress.totalSets)") + Text(verbatim: " ") + Text("sets"),
                            valueColor: accent)
                }
            }
            .padding(.top, EntrenarMetrics.heroNumeralsTop)
            .accessibilityElement(children: .combine)
            HStack(alignment: .center, spacing: EntrenarMetrics.ctaRowGap) {
                StrandCTAButton("Continue", tint: theme.positiveText, fillsWidth: false) {
                    model.resumeStrengthSession()
                }
                Button { confirmEndLiveSession = true } label: {
                    HStack(spacing: CenitMetrics.space1) {
                        Text("End session").font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                        StrandIcon.disclosure.image
                            .font(StrandFont.glyph(.chevron, weight: .semibold)).foregroundStyle(theme.inkTertiary)
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, CenitMetrics.space1 + 2)
                    .frame(minHeight: EntrenarMetrics.row, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(EntrenarPressStyle())
                .accessibilityElement(children: .combine)
            }
            .padding(.top, EntrenarMetrics.ctaRowTop)
        }
    }

    /// «ejercicio 2 de 6 · 5 series hechas · última: Sentadilla trasera 80 kg × 8» — el avance de la
    /// sesión en curso, cerrando con la última serie marcada (copy.md «Héroe»: «omite partes sin
    /// dato» — la cláusula «última:» solo se omite cuando de verdad no hay ningún set `done` todavía,
    /// p. ej. justo al arrancar la sesión).
    private func liveSessionSubtitle(_ session: StrengthSessionModel,
                                      _ p: (index: Int, total: Int, doneSets: Int, totalSets: Int)) -> String {
        let head = p.total > 0
            ? String(localized: "exercise \(p.index) of \(p.total) · \(p.doneSets) sets done")
            : String(localized: "\(p.doneSets) sets done")
        guard let last = lastDoneSet(session) else { return head }
        let kg = UnitFormatter.massFromKilograms(last.kg, system: unitSystem)
        return head + " · " + String(localized: "last: \(last.name) \(kg) × \(last.reps)")
    }

    /// El último set marcado `done` en toda la sesión (cualquier corrida, no solo la enfocada), por
    /// `doneTs` más reciente — la misma fuente que `doneCount` ya recorre, sin inventar un segundo
    /// modelo. `nil` cuando ninguna serie se ha marcado todavía (arranque de sesión).
    private func lastDoneSet(_ session: StrengthSessionModel) -> (name: String, kg: Double, reps: Int)? {
        var best: (ts: Int, name: String, kg: Double, reps: Int)?
        for run in session.runs {
            for s in run.sets where s.done {
                let ts = s.doneTs ?? 0
                if best == nil || ts > best!.ts { best = (ts, run.name, s.weightKg, s.reps) }
            }
        }
        return best.map { (name: $0.name, kg: $0.kg, reps: $0.reps) }
    }

    /// El avance de la sesión viva: qué ejercicio activo enfoca (1-based, entre los NO saltados) y
    /// cuántas series ya se marcaron sobre el total planeado.
    private func liveSessionProgress(_ session: StrengthSessionModel) -> (index: Int, total: Int, doneSets: Int, totalSets: Int) {
        let active = session.activeExercises
        let total = active.count
        let index = (active.firstIndex { $0.index == session.currentIndex }.map { $0 + 1 }) ?? min(total, 1)
        let totalSets = active.reduce(0) { $0 + $1.run.sets.count }
        return (max(index, total > 0 ? 1 : 0), total, session.doneCount, totalSets)
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
    ///
    /// FER-132 ronda 2: el chequeo de «sesión viva de otra rutina» (FER-86) que este botón cargaba
    /// (`sesionVivaDeOtraRutina` / la rama «Continue {otra}») quedó MUERTO cuando ⑤ ganó su propio
    /// héroe (`heroSectionSesionViva`) — `heroSectionRoutineDay`, el único llamador de este botón,
    /// solo se pinta cuando `model.strengthSession == nil` (ver el `body`, línea ~199). Ese caso lo
    /// resuelve ahora el héroe de sesión viva, con su propio «Continuar» + «Terminar sesión».
    private var empezarLabel: LocalizedStringKey { "Empezar" }

    @ViewBuilder private var empezarButton: some View {
        if todayRoutine != nil {
            tintedEmpezarButton
        } else {
            StrandCTAButton(empezarLabel, kind: .outline, fillsWidth: false) { startToday() }
        }
    }

    /// Routine-day CTA: `StrandCTAButton` con el tinte de región de la rutina (auditoría FER-952:
    /// el chrome se copiaba a mano; ahora el componente acepta `tint`).
    private var tintedEmpezarButton: some View {
        // FER-86, decisión del dueño: como el handoff. VERDE y COMPACTO, no ámbar de ancho completo.
        //
        // No es gusto, es contraste medido: el texto blanco sobre el tinte de familia daba 4.08:1
        // con el ámbar de empuje — bajo el piso de 4.5 — porque `StrandCTAButton` calibró su
        // etiqueta contra el fondo de tinta, no contra un hue que lo sustituye. El verde del
        // handoff da 5.61:1. Y el tinte de familia se queda donde sí significa algo: los tres
        // numerales de arriba, que son el dato.
        //
        // Que sea el MISMO verde de «avanza» en toda la app, y no un verde nuevo, es a propósito:
        // `positiveText` es el verde del veredicto ya oscurecido hasta cumplir contraste de texto.
        StrandCTAButton(empezarLabel, tint: theme.positiveText, fillsWidth: false) {
            startToday()
        }
    }

    /// F1: a day with a routine starts the guided session in one tap (slots prefetched on load); an empty
    /// routine opens its plan to edit instead of an empty session; a rest day starts guided mobility
    /// directly (FER-132 — the old standalone rest-day screen is retired, no sheet in between).
    private func startToday() {
        // FER-132: el descanso ya NO empuja una pantalla propia — es un estado de la landing
        // (la pantalla dedicada al descanso se retira). «Empezar» en un día de descanso no existe como botón (el héroe
        // ofrece «Movilidad · 20 min» en su lugar), pero un llamador externo (p. ej. la muñeca o el
        // Daily Brief) puede seguir pidiendo «empezar hoy» en un día sin rutina: arranca la misma
        // movilidad guiada que el botón del héroe.
        guard let r = todayRoutine else { startMobilityFromDisc(); return }
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

    /// La subida del día, dentro del héroe. La banda «LA SESIÓN DE HOY» que la envolvía se colapsó
    /// (FER-85): con los numerales ya en el héroe, la banda quedaba como un encabezado sobre nada el
    /// día que no hay subida — un rótulo de sección vacío. Lo que decía de verdad son estas dos
    /// filas, y su sitio es junto al botón: la subida vive donde empiezas.
    @ViewBuilder private var subidaDelDia: some View {
        if let r = todayRoutine {
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
            // Las dos filas pueden ser verdad a la vez: un ejercicio con «Baja recuperación · Ignorar»
            // sube por su propia bitácora mientras el resto del día se detiene. Conviven en vez de
            // taparse, para que los kilos que esperan nunca desaparezcan de la pantalla (FER-82).
            if showsHeldRaise, !deferredToday.isEmpty {
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
        // FER-130 · ritmo 1b: tres columnas con canal 28 (`heroNumeralsGap`), como el handoff — no una
        // frase unida por «·». El layout cambia; la LECTURA no: `.combine` sigue diciendo «~50 min,
        // 6 exercises, 18 sets» de un tirón (FER-944). Layout y VoiceOver son cosas distintas.
        return HStack(alignment: .firstTextBaseline, spacing: EntrenarMetrics.heroNumeralsGap) {
            if estMinutes > 0 {
                bigStat(Text(verbatim: "~\(estMinutes)"), unit: Text("min"), valueColor: accent)
            }
            bigStat(Text(verbatim: "\(exerciseCounts[rid] ?? 0)"), unit: Text("exercises"), valueColor: accent)
            if sets > 0 {
                bigStat(Text(verbatim: "\(sets)"), unit: Text("sets"), valueColor: accent)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func bigStat(_ value: Text, unit: Text, valueColor: Color? = nil) -> Text {
        // 24 pt, no 22: el tinte de familia solo está sancionado en numerales de 24 para arriba
        // («Hue saturado: … numerales ≥ 24 pt», EntrenarTokens). A 22, el ámbar da 3.61:1 y el teal
        // 3.48:1 sobre el papel — bajo el piso. El handoff los dibujó a 22 pero solo rendereó días
        // de pierna, y el índigo (5.43:1) es el único de los tres que pasaba.
        value.font(InstrumentoType.groteskNumber(24)).foregroundStyle(valueColor ?? theme.ink)
            + Text(verbatim: " ")
            + unit.font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
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

    /// «Hoy mantienes: Press banca · 82,5 kg · la subida espera» — el copy literal del handoff
    /// (copy.md «Héroe»: `Hoy mantienes: 80 kg · la subida espera`, Hoy ve leve / Recupera) para la
    /// subida retenida. El prefijo va en tinta500 (`inkTertiary`), el peso en 600/tinta (bold, ink) —
    /// misma jerarquía que `raiseText` — y la cláusula final en tinta500 otra vez. Nombra el ejercicio
    /// (el ejemplo del handoff no lo hace porque solo ilustra un caso, pero con más de una subida
    /// retenida el nombre es la única forma de no ambigüar cuál kilaje corresponde a cuál).
    ///
    /// Dos separadores, dos trabajos: « · » une un nombre a su peso, «, » separa ejercicios. Los días
    /// largos se limitan a tres nombres y se resumen, para que el héroe no se vuelva un párrafo.
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
        var t = Text("Today you keep:").foregroundStyle(theme.inkTertiary) + Text(verbatim: " ")
        for (i, s) in strong.enumerated() {
            if i > 0 { t = t + Text(verbatim: ", ") }
            t = t + s
        }
        // Spanish takes no comma before «y», so the tail joins with a plain space.
        if rest > 0 { t = t + Text(verbatim: " ") + Text("and \(rest) more") }
        return t + Text(verbatim: " · ")
            + (deferredToday.count == 1 ? Text("the raise waits") : Text("the raises wait"))
                .foregroundStyle(theme.inkTertiary)
    }

    // MARK: - ② «Tu semana» — WeekTokens + «También en tu plan» (FER-131 «Niveles»)

    /// «TU SEMANA» (FER-131 «Niveles»): kicker + valor (`semanaValor`) + la tira de `WeekTokens` —
    /// la misma pieza que StrandDesign ya expone para «hecho» relleno / «hoy» aro de tinta / «futuro»
    /// contorno / «descanso» punteado, en vez del cuadro de 26 pt dibujado a mano que la landing traía
    /// (FER-83 · E2 lo construyó, nadie lo consumía todavía). Debajo, «También en tu plan» (decisión
    /// del dueño, no re-litigar): una fila por rutina que NO es la de hoy — `otherPlanRoutines`, que
    /// ya existía sin llamador — con la piel nueva de `planRoutineRow` (`EntrenarFamilyDot`).
    private var semanaSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // FER-138: el encabezado y la tira abren la hoja rápida de rotar días (`WeekEditorSheet`),
            // no `WeeklyPlanEditorView` — ese editor completo se mudó a «Editar rutinas y semana ›»
            // (`utilityRow` más abajo), así que sigue teniendo una puerta y ninguna de las dos queda
            // huérfana.
            nivelHub { EntrenarNivel("Your week", value: semanaValor, kickerStyle: .handoff) { showWeekEditorSheet = true } }
            WeekTokens(days: weekTokenDays, labels: orderedWeekdays.map(weekdayLetter)) { showWeekEditorSheet = true }
                .padding(.top, CenitMetrics.space2)
            ForEach(otherPlanRoutines, id: \.routineId) { row in
                planRoutineRow(row)
            }
            // Sin día asignado: visibles igual (antes una rutina nueva no salía en ningún lado del
            // hub). El «—» honesto va en inkDim; asignarle día se hace en Tu Plan.
            ForEach(unscheduledRoutines, id: \.id) { r in
                planRoutineRow((routineId: r.id, name: r.name, days: String(localized: "no day yet")))
            }
            // FER-138: la puerta al editor COMPLETO (`WeeklyPlanEditorView`) — asignar rutinas a días,
            // gestionar carpetas — ya no vive en el encabezado/tira (que ahora abren la hoja rápida de
            // rotar); sin esta fila `openWeeklyPlan` quedaría sin llamador.
            utilityRow(icon: "calendar.badge.clock", label: "Edit routines and week") { openWeeklyPlan() }
            nuevaRutinaRow
        }
    }

    /// Los 7 tokens de `WeekTokens`, en el orden L→D (`orderedWeekdays`): hecho = lo que de verdad se
    /// entrenó esa semana (`trainedThisWeek`, gana sobre lo planeado); hoy = aro de tinta, SIEMPRE,
    /// nunca el color del veredicto; planeado = contorno del tinte de familia; descanso = punteado.
    /// Sin ejercicios clasificables una rutina cae en `.push` (mismo respaldo que `routineTint(nil)`
    /// ya usaba: `dataStrain`), así que el color de reserva no cambia.
    private var weekTokenDays: [EntrenarDayToken] {
        orderedWeekdays.map { wd in
            if let doneName = trainedThisWeek(wd) {
                return .done(region(name: doneName)?.family ?? .push)
            }
            if wd == todayWeekday {
                return .today(isRest: todayRoutine == nil)
            }
            if let rid = split[wd] {
                return .planned(routineCategory[rid]?.family ?? .push)
            }
            return .rest
        }
    }

    /// «2 de 3 ›» — entrenado esta semana / días con rutina asignada. Sin ningún día asignado (una
    /// sesión viva arrancada sin plan, FER-132) la tira se pinta igual, en contornos, y el valor dice
    /// «toca un día ›» — el mismo literal de copy.md que usa `primerUsoSection`.
    private var semanaValor: LocalizedStringKey {
        guard !split.isEmpty else { return "Tap a day" }
        let done = orderedWeekdays.filter { trainedThisWeek($0) != nil }.count
        return "\(done) of \(split.count)"
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
                // FER-137: el chip abre «Tres caminos» (`CrearPlanScreen`) directo, ya no el paperMenu
                // de dos ítems de `CrearPlanChip` — ese componente sigue vivo para «Tu Plan» (FER-88),
                // que aún reparte Plantilla/Importar en su propio menú.
                InstrumentoToolChip(systemImage: "rectangle.stack.badge.plus", label: Text("Create plan")) {
                    showCreatePlan = true
                }
                InstrumentoToolChip(systemImage: "questionmark.circle", label: Text("Tricks")) { showTricks = true }
            }
        }
        .padding(.top, CenitMetrics.space2)
    }

    // MARK: - «Otra forma ›» — el pliegue de las cuatro puertas (FER-85)
    //
    // Los cuatro discos teñidos que vivían aquí se fueron: llenaban cajas con el hue —lo único que
    // el ADN prohíbe sin excepción— y le peleaban el ojo al botón y al orbe. Las mismas cuatro
    // puertas siguen vivas, con los mismos destinos, detrás de un enlace tranquilo.
    //
    // No navega: se despliega en su sitio. La flecha va HACIA ABAJO y no «›» a propósito — en esta
    // misma pantalla «›» aparece tres veces en los encabezados de nivel y ahí siempre significa «te
    // llevo a otro lado». El pliegue abre aquí.
    //
    // REGLA DURA: este bloque NUNCA lee `repo.trainingAdvice`. Reordenar las puertas por el
    // veredicto —subir Movilidad el día que dice «Recupera»— es exactamente la funcionalidad
    // «suave» que este mismo issue retira, resucitada detrás de un toque. Lo único que sabe es un
    // HECHO, no una opinión: si ya hay una sesión abierta, las dos puertas que rebotan al confirm
    // de FER-950 lo dicen en su subtítulo, en vez de sorprender. La prueba de aceptación es que el
    // pliegue se vea idéntico en los ocho estados de veredicto.

    /// Una puerta del pliegue: el mismo destino que tenía su disco.
    private struct Puerta: Identifiable {
        let icon: String            // SF Symbol — nativo, estático
        let label: LocalizedStringKey
        let subtitle: LocalizedStringKey
        let hint: LocalizedStringKey
        let action: () -> Void
        var id: String { icon }
    }

    /// Las cuatro puertas, SIEMPRE en el mismo orden: la memoria del dedo no se traiciona.
    ///
    /// Movilidad usa `figure.cooldown`, no `figure.run`: las otras dos puertas a la misma sesión
    /// (día de descanso y «Otra forma de entrenar») ya usaban cooldown. Un solo vocabulario.
    /// FER-132 ronda 2: el chequeo `sesionViva` que estas cuatro puertas cargaban quedó MUERTO — este
    /// pliegue solo se dibuja desde `heroSectionRoutineDay` y `heroSectionDescanso`, y el `body` (ver
    /// línea ~199) solo pinta esos dos héroes cuando `model.strengthSession == nil`. La subtítulo
    /// «Resumes the session you have open» nunca se alcanzaba.
    private var puertas: [Puerta] {
        [
            Puerta(icon: "bolt.fill", label: "Quick",
                   subtitle: "Starts empty, you log as you go",
                   hint: "Starts a quick strength session, no routine.") { startQuickStrength() },
            Puerta(icon: "timer", label: "Intervals",
                   subtitle: "Rounds by time, same logging",
                   hint: "Opens the interval timer.") { openIntervals() },
            Puerta(icon: "figure.cooldown", label: "Mobility",
                   subtitle: "Guided, no weights · 20 min",
                   hint: "Starts a guided mobility session.") { startMobilityFromDisc() },
            Puerta(icon: "wind", label: "Breathe",
                   subtitle: "Guided breathing · 3 min",
                   hint: "Opens guided breathing.") { openBreathe() },
        ]
    }

    /// El toggle «Other ways ›» solo. `fillsWidth` (default `true`, el comportamiento de antes):
    /// `false` lo compacta para vivir junto a «Empezar» en el héroe (handoff: «min-h 44, 13px,
    /// tinta700, padding 0 6px»). El handoff dibuja ahí el chevron fijo de navegación, pero esta
    /// pantalla ya reserva «›» (`.disclosure`) para «te llevo a otro lado» en los tres encabezados
    /// de nivel — reciclarlo aquí, junto al CTA principal, le enseñaría al usuario vidente que este
    /// enlace navega cuando en realidad despliega en su sitio. Las dos variantes usan `.down`, el
    /// mismo chevron que rota; se prioriza la regla dura del comentario de arriba sobre la lectura
    /// literal del handoff.
    private func otraFormaEnlace(fillsWidth: Bool = true) -> some View {
        Button {
            withAnimation(reduceMotion ? StrandMotion.fade : StrandMotion.gentle) {
                otraFormaAbierta.toggle()
            }
        } label: {
            HStack(spacing: CenitMetrics.space1) {
                Text("Other ways")
                    .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                StrandIcon.down.image
                    .font(StrandFont.glyph(.chevron, weight: .semibold))
                    .foregroundStyle(theme.inkTertiary)
                    .rotationEffect(.degrees(otraFormaAbierta ? 180 : 0))
                    .accessibilityHidden(true)
                if fillsWidth { Spacer(minLength: 0) }
            }
            .padding(.horizontal, fillsWidth ? 0 : CenitMetrics.space1 + 2)   // handoff «padding 0 6px»
            .frame(maxWidth: fillsWidth ? .infinity : nil, minHeight: EntrenarMetrics.row, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(EntrenarPressStyle())
        .accessibilityValue(Text(otraFormaAbierta ? "expanded" : "collapsed"))
    }

    /// El contenido que se despliega bajo el enlace — las cuatro puertas. Se coloca DEBAJO de la
    /// fila entera del toggle (y, en el héroe, debajo de la fila CTA completa), nunca dentro de ella.
    @ViewBuilder private var otraFormaPliegue: some View {
        if otraFormaAbierta {
            VStack(alignment: .leading, spacing: 0) {
                filoDelPliegue
                ForEach(Array(puertas.enumerated()), id: \.element.id) { i, puerta in
                    puertaRow(puerta)
                    if i < puertas.count - 1 { filoDelPliegue }
                }
                filoDelPliegue
                Text("Your routine for today stays put: this is separate, no guilt.")
                    .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, CenitMetrics.rowVPad)
            }
            .padding(.top, CenitMetrics.space2)
            .transition(.opacity)
            .accessibilityElement(children: .contain)
        }
    }

    private var filoDelPliegue: some View {
        Rectangle().fill(theme.hairline).frame(height: 1)
    }

    /// La cabecera de un nivel del hub (FER-130 «Ritmo 1b»): filo superior de 1 pt + el aire del
    /// handoff antes de la fila — envuelve el mismo `EntrenarNivel` que ya sirve «Ver toda la
    /// biblioteca» en la sesión en vivo, sin tocar ese componente ni su otro llamador. El margen
    /// EXTERNO del nivel (18 el primero, 2 los siguientes) lo pone quien coloca `semanaSection` /
    /// `muscleSection` / `bitacoraSection`, no esta función — así un mismo nivel sirve como primero
    /// o como segundo.
    private func nivelHub<Nivel: View>(@ViewBuilder _ nivel: () -> Nivel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            filoDelPliegue
            nivel().padding(.top, EntrenarMetrics.levelPadTop)
        }
    }

    /// Una fila del pliegue: glifo, título y subtítulo. Sin «›» al final — dos de las cuatro no
    /// navegan, arrancan, y «›» ya significa «navega» en esta pantalla.
    ///
    /// El glifo va en `StrandFont.body`, no en `StrandFont.glyph(.lead)`: el doc de `glyph` lo
    /// reserva para chrome pareado a texto QUE NO ESCALA, y aquí el texto sí escala. Y `minWidth`,
    /// nunca `width`, para que a AX5 no le corte la cabeza al símbolo.
    private func puertaRow(_ puerta: Puerta) -> some View {
        Button {
            otraFormaAbierta = false   // cierra SIEMPRE, en las cuatro: una regla, no cuatro casos
            puerta.action()
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Image(systemName: puerta.icon)
                    .font(StrandFont.body).foregroundStyle(theme.inkSecondary)
                    .frame(minWidth: 22, alignment: .leading)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(puerta.label).font(StrandFont.body).foregroundStyle(theme.ink)
                    Text(puerta.subtitle)
                        .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: CenitMetrics.space2)
            }
            .padding(.vertical, CenitMetrics.space2)
            .frame(maxWidth: .infinity, minHeight: EntrenarMetrics.row, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(EntrenarPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(puerta.hint)
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
                    .accessibilityHidden(true)
            }
            .padding(.vertical, CenitMetrics.gap)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)   // HIG tap target (FER-944)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    /// One «También en tu plan» routine (FER-131 «Niveles»: fila 44 con `EntrenarFamilyDot` + nombre +
    /// días + ›). Since this row only ever lists routines OTHER than today's (`otherPlanRoutines`),
    /// the earned-raise badge that used to condition on `row.routineId == todayRoutineId` could never
    /// fire here — retired with the reskin instead of carrying dead reachability forward. The whole row
    /// is a single tap target that opens the routine (FER-784); the trailing chevron carries THAT
    /// routine's tint, same color as the leading dot.
    private func planRoutineRow(_ row: (routineId: String, name: String, days: String)) -> some View {
        Button { openRoutine(row.routineId) } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 7) {
                        EntrenarFamilyDot(routineFill(region(name: row.name)))
                        Text(row.name).font(StrandFont.body).foregroundStyle(theme.ink)
                    }
                    Text(planRowSubtitle(row)).font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                        .padding(.leading, EntrenarMetrics.familyDotIndent)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                StrandIcon.disclosure.image.font(StrandFont.glyph(.inline, weight: .semibold))
                    .foregroundStyle(routineTint(region(name: row.name)))
                    .accessibilityHidden(true)
            }
            .frame(minHeight: EntrenarMetrics.row)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .overlay(alignment: .bottom) { Divider().overlay(theme.hairline) }
    }

    /// «day · muscles» for a plan routine: the weekdays it trains, then its top primary muscles (if known).
    private func planRowSubtitle(_ row: (routineId: String, name: String, days: String)) -> String {
        let muscles = routineMuscles[row.routineId] ?? []
        return muscles.isEmpty ? row.days : ([row.days] + muscles).joined(separator: " · ")
    }

    // MARK: - ③ Músculos cargados — una línea, estimación (FER-131 «Niveles»)
    //
    // La rejilla de 90 días (Constancia) se retira aquí: el handoff la tumba (§11), y el dato vive en
    // Bitácora → Historial. `TrainingCalendar` sigue vivo en StrandDesign — lo sigue usando el
    // historial (`WorkoutHistoryScreen`) — solo esta landing deja de dibujarlo.

    /// El MISMO motor que «Tu cuerpo» (`MuscleFatigueMap`, vía `repo.muscleSetEvents`) — nunca una
    /// segunda derivación del mapa. `load()` llena `muscleEvents`; aquí solo se reduce a `loads`.
    private var muscleLoads: [MuscleFatigueMap.MuscleLoad] { MuscleFatigueMap.loads(events: muscleEvents) }

    private var muscleSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            nivelHub { EntrenarNivel("Loaded muscles", value: "estimate", kickerStyle: .handoff) }
            if let line = muscleLine {
                Button { openMuscleMap() } label: {
                    HStack(alignment: .firstTextBaseline, spacing: CenitMetrics.space1) {
                        line
                            .frame(maxWidth: .infinity, alignment: .leading)
                        StrandIcon.disclosure.image
                            .font(StrandFont.glyph(.inline, weight: .semibold))
                            .foregroundStyle(theme.inkTertiary)
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: EntrenarMetrics.row)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
            }
        }
    }

    /// ③ Descanso: el módulo COMPLETO de músculos cargados (handoff «Descanso»), en vez de la línea
    /// — hasta 5 filas `MuscleLoadRow`, la MISMA pieza y el MISMO `muscleLoads` que `muscleSection`
    /// y `TrainingBodyScreen` leen, nunca una segunda derivación del mapa. Cierra con «Mañana:
    /// {rutina}» cuando el split ya nombra la rutina de mañana.
    private var muscleSectionModulo: some View {
        VStack(alignment: .leading, spacing: 0) {
            // El encabezado «últimos 7 días ›» SÍ navega a Tu cuerpo: en el prototipo el <div> del
            // encabezado del módulo lleva `onClick nav.cuerpo` (a diferencia de la LÍNEA de músculos,
            // donde solo la fila de dato navega). Las filas de abajo son lectura, no puertas.
            nivelHub {
                EntrenarNivel("Loaded muscles", value: "last 7 days", kickerStyle: .handoff) { openMuscleMap() }
            }
            HStack {
                Text("Load").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                Spacer(minLength: CenitMetrics.space2)
                Text("Sets · 7 d").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            }
            .padding(.top, CenitMetrics.space2)
            ForEach(Array(muscleLoads.prefix(5)), id: \.muscle) { load in
                muscleModuloRow(load)
            }
            if let tomorrow = tomorrowRoutineName {
                Divider().overlay(theme.hairline)
                Text("Tomorrow: \(tomorrow)")
                    .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                    .frame(minHeight: EntrenarMetrics.row, alignment: .leading)
            }
        }
    }

    /// Una fila del módulo — misma receta que `TrainingBodyScreen.loadRow`: «hoy» / «ayer» / «hace N
    /// d» / «fresco», la MISMA escalera de recencia, para que las dos pantallas nunca contradigan.
    private func muscleModuloRow(_ load: MuscleFatigueMap.MuscleLoad) -> MuscleLoadRow {
        MuscleLoadRow(
            name: MuscleAtlas.name(load.muscle),
            load: load.relative,
            recency: load.state == .fresh ? "fresh"
                : load.daysSinceLast == 0 ? "today" : load.daysSinceLast == 1 ? "yesterday" : "\(load.daysSinceLast) d ago",
            sets: load.weeklySets,
            isFresh: load.state == .fresh,
            action: { openMuscleMap() }
        )
    }

    /// Tomorrow's routine name from the weekly split — `nil` = tomorrow is also a rest day. (Movida
    /// aquí de la pantalla dedicada al descanso, retirada con FER-132: el descanso ya no empuja pantalla propia.)
    private var tomorrowRoutineName: String? {
        let tomorrow = (todayWeekday % 7) + 1
        return split[tomorrow].flatMap { routinesById[$0]?.name }
    }

    /// «Espalda baja · hace 3 días · Fresco: pecho · hombros» — el músculo más cargado (600, tinta900)
    /// + su estado de recencia (13 SF, tinta700): «hoy» / «hace N d», y la segunda cláusula de
    /// copy.md con los músculos frescos, cuando los hay. Separados por «·» en vez de un adjetivo
    /// flexionado («cargada»/«cargado»/«cargadas»): el catálogo mezcla géneros y números (femenino
    /// singular «Espalda baja», femenino plural «Pantorrillas», masculino plural «Cuádriceps»,
    /// «Glúteos»…) y un solo adjetivo fijo no concuerda con todos. `nil` cuando no hay eventos (el
    /// nivel se oculta en el llamador).
    ///
    /// Recencia en los cuatro estados del handoff (copy.md «Niveles»): «hoy» · «ayer» · «hace N d» ·
    /// «fresco». `TrainingBodyScreen` (la pantalla a la que este renglón navega, `loadRow`/`lastText`)
    /// usa la misma escalera, para que la MISMA recencia no se lea distinto entre pantallas hermanas.
    private var muscleLine: Text? {
        guard let top = muscleLoads.first else { return nil }
        let mainName = Text(MuscleAtlas.name(top.muscle))
            .font(StrandFont.subhead).fontWeight(.semibold).foregroundStyle(theme.ink)
        let state: Text = top.daysSinceLast == 0 ? muscleLineReading(Text("today"))
                        : top.daysSinceLast == 1 ? muscleLineReading(Text("yesterday"))
                                                 : muscleLineReading(Text("\(top.daysSinceLast) d ago"))
        var line = mainName + muscleLineReading(Text(verbatim: " · ")) + state
        if let fresh = freshMusclesClause {
            line = line + muscleLineReading(Text(verbatim: " · ")) + fresh
        }
        return line
    }

    private func muscleLineReading(_ t: Text) -> Text { t.font(StrandFont.subhead).foregroundStyle(theme.inkSecondary) }

    /// «Fresco: pecho · hombros» — hasta 2 músculos en estado `.fresh` (quisquilloso ronda 3: el
    /// músculo PRINCIPAL, `muscleLoads.first`, siempre tiene `relative == 1.0` así que nunca cae aquí
    /// — no hay riesgo de listarlo dos veces). Reusa la MISMA etiqueta «Fresh: »/«Fresco: » y el
    /// MISMO patrón de unión sin adjetivo flexionado que `TrainingBodyScreen.freshLine`, para que la
    /// landing y su pantalla hermana no inventen dos vocabularios para lo mismo. `nil` cuando ningún
    /// músculo está fresco (primeras sesiones: todo lo tocado carga, nada está fresco todavía).
    private var freshMusclesClause: Text? {
        let fresh = muscleLoads.filter { $0.state == .fresh }.sorted { $0.load < $1.load }.prefix(2)
        guard !fresh.isEmpty else { return nil }
        let names = fresh.enumerated().reduce(Text(verbatim: "")) { acc, pair in
            let (i, load) = pair
            let sep = i == 0 ? Text(verbatim: "") : muscleLineReading(Text(verbatim: " · "))
            return acc + sep + muscleLineReading(Text(MuscleAtlas.name(load.muscle)))
        }
        return muscleLineReading(Text("Fresh: ")) + names
    }

    // MARK: - ④ Bitácora — 2 filas + «Historial y progreso ›» (FER-131 «Niveles»)

    private var bitacoraSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            nivelHub { EntrenarNivel("Training log", value: bitacoraValor, kickerStyle: .handoff) }
            ForEach(Array(recentSessions90.prefix(2)), id: \.id) { session in
                bitacoraRow(session)
            }
            utilityRow(icon: "chart.line.uptrend.xyaxis", label: "History and progress") { openHistory() }
        }
    }

    /// Sesiones COMPLETADAS en los últimos 90 días naturales, del más reciente al más viejo — la
    /// MISMA ventana que anuncia `bitacoraValor`, para que sus dos filas nunca contradigan al
    /// encabezado (quisquilloso ronda 2: `sessions.prefix(2)` sin filtro podía enseñar dos sesiones
    /// mientras el encabezado decía «0 sesiones · 90 días»). `sessions` ya viene ordenado
    /// `startTs DESC` (`recentSessions(limit:)`).
    ///
    /// `endTs != nil` — igual que `WorkoutHistoryScreen.latestSessionByLocalDay`/`weeklyVolumes` filtran
    /// el MISMO array `sessions` — para que una sesión EN CURSO nunca aparezca como fila terminada con
    /// duración/volumen mal calculados, ni abra el acta de un entrenamiento que aún no cerró
    /// (quisquilloso ronda 3).
    private var recentSessions90: [StrengthSession] {
        let cutoff = Date().timeIntervalSince1970 - 90 * 86_400
        return sessions.filter { $0.endTs != nil && Double($0.startTs) >= cutoff }
    }

    /// «11 sesiones · 90 días» — singular aparte, mismo patrón que `marcaChip` («1 marca» vs «N marcas»):
    /// una `LocalizedStringKey` interpolada nunca resuelve plural sola.
    private var bitacoraValor: LocalizedStringKey {
        recentSessions90.count == 1 ? "1 session · 90 days" : "\(recentSessions90.count) sessions · 90 days"
    }

    /// Una fila de Bitácora: «Mié 12 · Tirón A» + chip «N marca(s)» (si hubo) · «44 min · 4,880 kg» ·
    /// esfuerzo «11.1 /21» (si hay FC del Watch). Toca → la misma hoja que abre el historial.
    private func bitacoraRow(_ session: StrengthSession) -> some View {
        Button { openWorkoutSession(bitacoraRoute(session)) } label: {
            HStack(alignment: .center, spacing: CenitMetrics.space2) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: CenitMetrics.space1) {
                        Text(verbatim: bitacoraTitle(session))
                            .font(StrandFont.body).foregroundStyle(theme.ink).lineLimit(1)
                        if let marks = bitacoraMarcas[session.id], marks > 0 {
                            marcaChip(marks)
                        }
                    }
                    Text(verbatim: bitacoraSubtitle(session))
                        .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                }
                Spacer(minLength: CenitMetrics.space2)
                if let strain = session.strain {
                    // 13 pt está bajo el piso de 24 pt: `dataStrain` puro (#C4631F) da ~3.6:1 sobre el
                    // papel, no los 4.5:1 que pide texto chico. Mismo remedio que `SessionStatsBar` ya
                    // usa con `dataHeart` — oscurecer a contraste, no el hue crudo.
                    (Text(verbatim: StrengthHistoryFormat.strain(strain))
                        .font(InstrumentoType.grotesk(13, weight: .bold))
                        .foregroundStyle(OKLab.darkened(theme.dataStrain, toContrast: 4.5, against: theme.paper))
                     + Text(verbatim: " /21").font(StrandFont.caption).foregroundStyle(theme.inkTertiary))
                }
            }
            .frame(minHeight: EntrenarMetrics.row)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .overlay(alignment: .bottom) { Divider().overlay(theme.hairline) }
    }

    /// El chip «N marca(s)»: mismo componente compartido que Historial (`EntrenarMarcaChip`,
    /// StrandDesign — quisquilloso ronda 4: antes dos copias `private` idénticas).
    private func marcaChip(_ count: Int) -> some View {
        EntrenarMarcaChip(count, theme: theme)
    }

    /// «Mié 12 · Tirón A».
    private func bitacoraTitle(_ session: StrengthSession) -> String {
        let day = Date(timeIntervalSince1970: TimeInterval(session.startTs))
            .formatted(.dateTime.weekday(.abbreviated).day())
        let capitalized = day.prefix(1).uppercased() + day.dropFirst()
        let name = session.routineId.flatMap { routinesById[$0]?.name } ?? String(localized: "Strength workout")
        return "\(capitalized) · \(name)"
    }

    /// «44 min · 4,880 kg».
    private func bitacoraSubtitle(_ session: StrengthSession) -> String {
        var parts: [String] = []
        if let mins = StrengthHistoryFormat.durationMinutes(start: session.startTs, end: session.endTs) {
            parts.append(StrengthHistoryFormat.durationText(mins))
        }
        if let vol = sessionVolumes[session.id], vol.volumeKg > 0 {
            parts.append(StrengthHistoryFormat.volume(vol.volumeKg, system: unitSystem))
        }
        return parts.joined(separator: " · ")
    }

    private func bitacoraRoute(_ session: StrengthSession) -> WorkoutSessionRoute {
        let name = session.routineId.flatMap { routinesById[$0]?.name } ?? String(localized: "Strength workout")
        return WorkoutSessionRoute(id: session.id, startTs: session.startTs, endTs: session.endTs,
                                   strain: session.strain, avgHr: session.avgHr, routineName: name)
    }

    /// «Músculos cargados y Bitácora aparecen después de tu primera sesión. Mientras, silencio.» —
    /// plan armado, cero sesiones registradas todavía (copy.md «Primer uso»).
    private var silencioPrimeraSesion: some View {
        // Mismo filo superior que cualquier otro nivel (`nivelHub`): sin él el corte entre TU SEMANA y
        // este mensaje no se leía igual que el corte entre dos niveles cualesquiera.
        VStack(alignment: .leading, spacing: 0) {
            filoDelPliegue
            Text("Loaded muscles and Log appear after your first session. Until then, silence.")
                .font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, EntrenarMetrics.levelPadTop)
        }
    }

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

    // MARK: - ④ Primer uso (sin rutinas) — «Arma tu semana» (FER-132)
    //
    // Sin ningún día asignado todavía: el héroe habla del arranque, no de un día — mismo lenguaje
    // tipográfico que `heroSectionRoutineDay` (kicker + título Grotesk 32), plantillas tocables +
    // «Importar tu plan de tu IA ›» en vez de «Empezar», y TU SEMANA vacía (`weekTokenDays` ya cae
    // en contornos por sí solo cuando `split` está vacío — no hace falta un caso especial). SIN
    // «Otra forma» (no hay sesión de hoy que ofrecer una alternativa) y SIN Músculos/Bitácora — la
    // misma nota de silencio que «plan sin sesiones» los explica.

    private var primerUsoSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Let's start")
                .entrenarCabeceraKicker().foregroundStyle(theme.inkTertiary)
            Text("Build your week")
                .font(InstrumentoType.grotesk(32, weight: .bold)).tracking(-1)
                .foregroundStyle(theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, EntrenarMetrics.heroTitleTop)
            Text("Choose a template or build your own routine · Entrenar serves it to you every day after that")
                .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, EntrenarMetrics.heroSubTop)
            primerUsoChips.padding(.top, CenitMetrics.gap)
            Button { showHubImport = true } label: {
                HStack(spacing: CenitMetrics.space1) {
                    Text("Import your AI's plan").font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                    StrandIcon.disclosure.image
                        .font(StrandFont.glyph(.chevron, weight: .semibold)).foregroundStyle(theme.inkTertiary)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: EntrenarMetrics.row, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(EntrenarPressStyle())
            .accessibilityElement(children: .combine)
            // FER-137: el CTA de primer uso abre «Tres caminos» — antes saltaba derecho a la hoja de
            // plantillas, un solo camino de los tres que ahora ofrece la puerta.
            StrandCTAButton("Build my plan", tint: theme.positiveText, fillsWidth: false) { showCreatePlan = true }
                .padding(.top, CenitMetrics.space1)
            // FER-138 (ronda 2, grave): con `split` vacío no hay nada que rotar — la hoja rápida
            // solo tiene sentido una vez que ya existe al menos una rutina programada. Aquí TU
            // SEMANA sigue abriendo el editor completo (`openWeeklyPlan` → `WeeklyPlanEditorView`),
            // el único lugar donde se puede asignar la primera rutina a un día.
            nivelHub { EntrenarNivel("Your week", value: "Tap a day", kickerStyle: .handoff) { openWeeklyPlan() } }
                .padding(.top, EntrenarMetrics.firstLevelTop)
            WeekTokens(days: weekTokenDays, labels: orderedWeekdays.map(weekdayLetter)) { openWeeklyPlan() }
                .padding(.top, CenitMetrics.space2)
            silencioPrimeraSesion.padding(.top, EntrenarMetrics.levelTop)
        }
    }

    /// Tres plantillas tocables (nombre + «lista para editar»): tocar cualquiera abre la misma hoja
    /// de plantillas (`StarterTemplatesSheet`) — el mismo destino que «Crear mi plan», solo un atajo
    /// más corto para quien ya sabe cuál quiere.
    private var primerUsoChips: some View {
        HStack(spacing: CenitMetrics.space2) {
            ForEach(Self.primerUsoGroupNames, id: \.self) { name in
                Button { showTemplates = true } label: {
                    // token-exempt: 1 pt es el hairline entre nombre y «lista para editar» dentro del
                    // chip, más chico que `CenitMetrics.space1` (4). El archivo ya tiene otros gaps sin
                    // token (2, 7, 8, 9, 12); no es una regresión nueva de este PR.
                    VStack(alignment: .leading, spacing: 1) {
                        Text(LocalizedStringKey(name)).font(StrandFont.body).fontWeight(.semibold).foregroundStyle(theme.ink)
                        Text("Ready to edit").font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                    }
                    .padding(.horizontal, CenitMetrics.space2)
                    // El prototipo pide 36 pt; sube a EntrenarMetrics.row (44 pt) por el mínimo de
                    // tap target de HIG — misma regla que el resto de filas de esta pantalla
                    // (sesionMetrics, heroSesionVivaBody). Deviation documentada ronda 3 (quisquilloso).
                    .frame(minHeight: EntrenarMetrics.row, alignment: .leading)
                    .background(theme.surface, in: Capsule())
                    .overlay(Capsule().strokeBorder(theme.hairline, lineWidth: 1))
                }
                .buttonStyle(EntrenarPressStyle())
                .accessibilityLabel(Text(LocalizedStringKey(name)) + Text(verbatim: ", ") + Text("Ready to edit"))
            }
        }
    }

    /// Nombres de las tres plantillas destacadas (mismo vocabulario que `StarterTemplatesSheet`, sin
    /// re-exponer su enum privado): Empuje · Jalón · Pierna, Cuerpo completo, Torso / Pierna — el
    /// catálogo es-MX real (`Localizable.xcstrings`), corregido ronda 3 (quisquilloso, menor): el
    /// comentario decía «Tirón»/«Superior·Inferior», vocabulario que el catálogo no produce.
    private static let primerUsoGroupNames: [String] = ["Push Pull Legs", "Full body", "Upper / Lower"]

    // MARK: - Error state · store couldn't be read (distinct from «no plan yet»)
    //
    // When `repo.storeHandle()` returns nil the read failed — the user likely HAS a plan we just couldn't
    // open. Showing the onboarding empty state here would wrongly push them to rebuild their week, so we
    // surface a plain error with a retry that re-runs `load()`.
    private var loadErrorState: some View {
        card {
            VStack(alignment: .leading, spacing: CenitMetrics.gap) {
                Text("I couldn't read your plan").font(InstrumentoType.groteskHeadline(20)).foregroundStyle(theme.ink)
                Text("Something failed opening your routines · your data is intact")
                    .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                StrandCTAButton("Retry", kind: .outline) { Task { await load() } }
            }
        }
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

    /// One month's worth of «which days did I train» data — all that survives now that the Constancia
    /// dot-grid itself is retired (§11): `trainedThisWeek` only ever reads `year`/`month`/`trained`.
    /// The grid used to also read a month label, session count, day count, current-month flag and a
    /// fade — those went with it (FER-131, quisquilloso ronda 2: don't keep computing what nothing
    /// reads any more).
    private struct ConstancyMonth {
        let year: Int
        let month: Int           // calendar month (1...12)
        let trained: [Int: String]   // dayOfMonth → the (latest) routine's name that day («» = unknown routine)
    }

    /// The last three calendar months (oldest → current): for each, the days you trained keyed to the
    /// latest routine that day. Read from the last-200 completed sessions (well over 90 days' worth).
    /// Called once per `load()` into `constancyMonthsCache` (FER-948) — not from the view body.
    private func computeConstancyMonths() -> [ConstancyMonth] {
        let cal = Calendar.current
        guard let startOfThisMonth = cal.date(from: cal.dateComponents([.year, .month], from: Date())) else { return [] }
        // Bucket completed sessions by (year, month); within a month keep the first-seen (latest) routine per day.
        var byYM: [DateComponents: [Int: String]] = [:]
        for s in sessions where s.endTs != nil {
            let c = cal.dateComponents([.year, .month, .day], from: Date(timeIntervalSince1970: TimeInterval(s.startTs)))
            let key = DateComponents(year: c.year, month: c.month)
            var trained = byYM[key] ?? [:]
            if let day = c.day, trained[day] == nil {
                trained[day] = s.routineId.flatMap { routinesById[$0]?.name } ?? ""
            }
            byYM[key] = trained
        }
        return (0..<3).reversed().compactMap { offset in     // 2,1,0 → oldest first
            guard let monthDate = cal.date(byAdding: .month, value: -offset, to: startOfThisMonth) else { return nil }
            let ym = cal.dateComponents([.year, .month], from: monthDate)
            guard let year = ym.year, let month = ym.month else { return nil }
            let trained = byYM[DateComponents(year: year, month: month)] ?? [:]
            return ConstancyMonth(year: year, month: month, trained: trained)
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
        // FER-132 · ② Recupera: el kicker nombra la fuente del consejo («tu semana marca»), no el
        // día — el día ya vive en la cabecera de arriba. Copy literal del handoff (copy.md «Héroe»).
        if advice == .recover {
            return String(localized: "Today · your week marks")
        }
        let day = Calendar.current.standaloneWeekdaySymbols[(todayWeekday - 1) % 7]
        return String(localized: "Today · \(day)")
    }

    // MARK: - Cabecera (FER-130 «Ritmo 1b»)
    //
    // «Entrenar · {fecha}» a la izquierda, el «?» de los trucos a la derecha — reemplaza al wordmark
    // retirado en FER-952. Antes el «?» vivía en la misma fila que el hilo del veredicto; el handoff
    // los separa: la cabecera es de la PANTALLA (nombra el tab y el día), el hilo es del CUERPO.

    private var cabecera: some View {
        HStack(spacing: CenitMetrics.space2) {
            Text(cabeceraKicker)
                .entrenarCabeceraKicker()
                .foregroundStyle(theme.inkSecondary)
            Spacer(minLength: CenitMetrics.space2)
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
    }

    /// «Entrenar · Sáb 15 ago» — el nombre del tab más la fecha real de hoy, no un rótulo fijo.
    private var cabeceraKicker: String {
        String(localized: "Train · \(cabeceraFecha)")
    }

    /// La fecha de hoy en la plantilla localizada «EEE d MMM» («sáb 15 ago» / «Sat 15 Aug»), con la
    /// inicial en mayúscula — la plantilla de weekday corto sale toda en minúsculas en es-MX.
    /// `StrandFormat.weekdayHeading` (StrandDesign): mismo helper compartido con la cabecera de «Tu
    /// cuerpo» (quisquilloso ronda 4: antes dos copias a mano).
    private var cabeceraFecha: String { StrandFormat.weekdayHeading(Date()) }

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
            EntrenarHilo(tone: hilo.tono.entrenarTone,
                         word: LocalizedStringKey(hilo.palabra),
                         advice: hilo.consejo.map { LocalizedStringKey($0) },
                         hint: "Opens today's ballot") {
                showVeredictoActa = true
            }
        }
    }

    /// Whether the hero may explain a held raise. Silence must be total: with no usable read (or none
    /// yet) the section neither advises nor announces a raise it is holding.
    private var showsHeldRaise: Bool { TrainingRegulation.explainsHeldRaise(advice) }


    // MARK: - Data

    /// How many personal records fall inside one session's [inicio, fin] — el chip «N marca(s)» de
    /// Bitácora. Solo se llama para las 2 filas que la landing muestra (acotado, no un barrido).
    private func marcaCount(for session: StrengthSession) async -> Int {
        let sets = await repo.sessionSets(sessionId: session.id)
        let exerciseIds = Set(sets.map(\.exerciseId))
        let start = session.startTs, end = session.endTs ?? session.startTs
        var count = 0
        for exerciseId in exerciseIds {
            let prs = await repo.personalRecords(exerciseId: exerciseId)
            count += prs.filter { $0.ts >= start && $0.ts <= end }.count
        }
        return count
    }

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
            // FER-124: los slots los siembra `repo.seedTodaySlots` — EL MISMO método que usa el
            // arranque desde la muñeca, así que el teléfono y el reloj no pueden ofrecer rutinas
            // distintas. El héroe deriva la subida/retención de los slots ya sembrados, no de un
            // segundo bucle. Un veredicto para toda la tabla (FER-82), leído antes de sembrar.
            let advice = repo.trainingAdvice
            passAdvice = advice
            let inventory = await MainActor.run { PlatesStore().inventory }
            let seeded = await repo.seedTodaySlots(routineId: tid, advice: advice, inventory: inventory)
            slots.append(contentsOf: seeded)
            var raising: [(name: String, kg: Double)] = []
            var held: [(name: String, kg: Double)] = []
            for slot in seeded {
                guard let raise = slot.raise else { continue }
                let name = slot.exercise.map(StrengthDisplay.name) ?? slot.re.exerciseId
                // Una evaluación, dos lecturas: aplicada al seed, o retenida por el veredicto de hoy.
                if raise.waiting { held.append((name: name, kg: raise.toKg)) }
                else { raising.append((name: name, kg: raise.toKg)) }
            }
            raisingToday = raising
            heldToday = held
        }
        let recent = (try? await store.recentSessions(limit: 200)) ?? []
        // FER-131 «Niveles»: el mismo fetch que `TrainingBodyScreen` (84 días) para «Músculos
        // cargados» — nunca una segunda derivación del mapa — más el volumen agregado por sesión y si
        // alguna de las 2 filas de Bitácora trajo una marca (el rango de la sesión toca un PR).
        let cal = Calendar.current
        let muscleSince = cal.date(byAdding: .day, value: -84, to: cal.startOfDay(for: Date())) ?? Date()
        let muscleEv = await repo.muscleSetEvents(sinceTs: Int(muscleSince.timeIntervalSince1970),
                                                  resetTs: Int(muscleRecoveryResetAt))
        let volumes = await repo.sessionVolumes()
        // FER-131 quisquilloso ronda 3: las 2 filas que Bitácora muestra son `recentSessions90`
        // (completadas, `endTs != nil`, ventana de 90 días) — no `recent.prefix(2)`, que podía incluir
        // una sesión en curso y desperdiciar el cómputo en una fila que la landing ni siquiera pinta.
        let cutoff90 = Date().timeIntervalSince1970 - 90 * 86_400
        let bitacoraRows = recent.filter { $0.endTs != nil && Double($0.startTs) >= cutoff90 }.prefix(2)
        var marcas: [String: Int] = [:]
        for s in bitacoraRows { marcas[s.id] = await marcaCount(for: s) }
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
        muscleEvents = muscleEv
        sessionVolumes = volumes
        bitacoraMarcas = marcas
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

#endif

// MARK: - El tono del hilo, una sola vez

extension LiquidHoyBuilder.HiloEntrenar.Tono {
    /// El mapeo `Tono` → `EntrenarHilo.Tone` que comparten la landing (`hiloDelVeredicto`) y la
    /// cabecera de la sesión en vivo (`LiveStrengthSheet`, FER-133). Una sola definición: antes
    /// vivía copiada en los dos archivos.
    var entrenarTone: EntrenarHilo.Tone {
        switch self {
        case .claro:    return .clear
        case .atencion: return .caution
        case .alerta:   return .ease
        case .hueco:    return .hollow
        }
    }
}
