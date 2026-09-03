#if os(iOS)
import SwiftUI
import CenitDesign
import StrandTraining
import StrandAnalytics
import Inject   // recarga en caliente (dev-only, inerte en Release)

// MARK: - Entrenar (the Train tab root) — «Pulir · arranque directo» (handoff, sobre «La Semana» FER-530)
//
// Landing de Entrenar en Liquid Glass · El Eje: planificador con «Hoy» arriba, un solo «Empezar
// {rutina}» (F1), «¿otro tipo?» debajo, descanso como estado del mismo héroe (FER-132), y debajo
// TU SEMANA · MÚSCULOS CARGADOS · BITÁCORA (FER-131). Color solo en el dato; el `NavigationStack`
// del tab es dueño de la navegación.

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
            .enableInjection()   // Inject: ver la nota en `inject` arriba (no-op en Release)
    }
}

private struct EntrenarLanding: View {
    @EnvironmentObject var repo: Repository
    @Environment(AppModel.self) var model
    @EnvironmentObject var tabRouter: TabRouter

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
    /// Ronda 2 · D1: conserva `fromKg` además de `toKg` — la píldora del héroe sigue mostrando el
    /// peso NUEVO (`toKg`), pero la tile «Subidas listas» del mosaico necesita el ESCALÓN
    /// (`toKg − fromKg`, mock «▲ 2.5 kg»).
    @State private var raisesToday: [(name: String, fromKg: Double, toKg: Double,
                                      rhythmNote: ProgressionPlanner.RaiseRhythmNote?)] = []
    /// Ola 1 · E5: ejercicios que HOY cumplieron las reps pero al fallo (0 en reserva) — el ritmo
    /// «según reps en reserva» los deja invisibles al ciclo, así que mantienen en vez de subir. La
    /// píldora del héroe se pinta ámbar («Hoy mantienes») SOLO cuando no hay ningún ejercicio en
    /// `raisesToday` — una sesión que sí sube siempre gana el espacio del héroe.
    @State private var atLimitHeldToday: [(name: String, weightKg: Double)] = []
    /// The verdict `todaySlots` were seeded with; `nil` until the first load. Guards «Empezar» from
    /// handing the session a table built under a verdict that has since changed (FER-82).
    @State private var slotsAdvice: TrainingRegulation.Advice?
    /// Ola 1 · E10 (FER-329): el programa activo y la semana en la que van los `todaySlots`, publicado
    /// JUNTO con ellos en el mismo pase (igual que `slotsAdvice`) — así la sesión que arranca desde
    /// aquí se guarda con la misma semana con la que se sembró la tabla. `nil` = no hay programa.
    @State private var todayServing: ProgramServing.Context?
    /// El puente de Apple Salud, para que la boleta de esta pestaña reciba el MISMO contexto que la
    /// de Hoy (sin él afirmaba «anoche no llegó nada» a quien no ha conectado Salud).
    @EnvironmentObject private var health: HealthKitBridge

    /// FER-85/FER-84: la boleta del veredicto, servida DENTRO de Entrenar. El hilo la abre como
    /// hoja; nunca cambia de pestaña. Es la misma acta que Hoy sirve, con el mismo modelo.
    @State private var showVeredictoActa = false
    /// FER-138: las teselas de SEMANA (`EntrenarHubSemana`, salvo la de HOY) abren la hoja rápida de
    /// rotar días — pero solo cuando ya hay al menos una rutina en el split; en primer uso (`split`
    /// vacío, `primerUsoSection`) TU SEMANA sigue abriendo el editor completo vía `openWeeklyPlan`,
    /// porque la hoja rápida solo rota entre rutinas YA programadas y no tiene forma de asignar la
    /// primera. FER-171 · Parte B: «EDITAR ›» del hub v18 (`EntrenarCapsulaPuerta` en
    /// `EntrenarHubSemana`) lleva directo a `WeeklyPlanEditorView` vía `openWeeklyPlan`, no a esta hoja.
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
    /// El PR más reciente de todo el historial — MARCAS del hub v18 (FER-171 · Parte B). `nil` sin PRs.
    @State private var latestPR: PersonalRecord?
    /// El PR anterior del mismo ejercicio+métrica que `latestPR` — «antes X · hace N días». `nil` sin
    /// marca anterior (el PR actual es la primera marca de ese ejercicio+métrica).
    @State private var previousPR: PersonalRecord?
    /// El nombre a mostrar del ejercicio de `latestPR` — resuelto una vez (catálogo o custom), no en
    /// cada `body`.
    @State private var latestPRExerciseName: String = ""
    /// Cuántos PRs cayeron desde el inicio del mes calendario actual — «Marcas · N en {mes}».
    @State private var personalRecordCountThisMonth: Int = 0
    /// El pliegue de «Otra forma»: privado de la vista y SIN persistir — cada visita abre cerrado.
    @State private var otraFormaAbierta = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The Daily Brief's «Empezar» arrived (via `TabRouter`) before this view finished loading its
    /// prefetched slots — start today's session as soon as `load()` completes (FER-613).
    @State private var startWhenLoaded = false
    /// Presents the live-HR workout sheet from the «Formas de entrenar» → «En vivo» chip (the same sheet
    /// «Otra forma» presents).
    /// Presents the starter-templates sheet (catálogo completo o acotado a un grupo — FER-251).
    @State private var showTemplates = false
    /// Grupo con el que abrir `StarterTemplatesSheet` (nil = catálogo completo). Se limpia al cerrar.
    @State private var templatesGroup: StarterTemplate.Group?
    /// FER-952: the hub's Import door-chip / primer-uso «Importar tu plan de tu IA».
    @State private var showHubImport = false
    /// FER-251: «Desde cero» del primer uso — misma Biblioteca → crear rutina que «Tres caminos».
    @State private var showLibrary = false
    /// «Lo que Cénit sabe hacer» (decisión Fer 2026-07-16): puerta permanente + tarjeta única.
    @State private var showTricks = false
    /// Success toast after a template group is applied — auto-dismisses.
    @State private var showPlanAppliedToast = false
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
            // Ritmo 1b (handoff FER-130): el VStack raíz ya no reparte un `sectionGap` uniforme —
            // cada bloque carga su propio margen superior, así que la cabecera / el hilo / el héroe
            // pueden llevar el aire literal del handoff sin heredar uno genérico encima. Los estados
            // fuera de alcance (sin plan, error de carga) conservan el `sectionGap` de antes como su
            // propio padding explícito, para no moverles ni un punto.
            VStack(alignment: .leading, spacing: .zero) {
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
                    hiloDelVeredicto.padding(.top, LiquidSpace.s200)
                }
                if loaded {
                    if loadFailed {
                        loadErrorState       // §5 — «No pude leer tu plan» + Reintentar, niveles ocultos
                            .padding(.top, LiquidSpace.s700)
                    } else if model.strengthSession != nil {
                        // ⑤ Sesión viva: gana sobre CUALQUIER otro estado — incluido «sin plan todavía»
                        // (un entrenamiento rápido, sin rutina, puede arrancar sin split armado).
                        // FER-167 (F2, orden del épico): el héroe de sesión viva se RETIRA — deroga
                        // FER-132. Entrenar pasa a ser mosaico v18 + píldora, como los otros 4 tabs
                        // (Continuar = tap en la píldora; Terminar/Descartar = su confirm vigente).
                        v18Mosaico.padding(.top, EntrenarMetrics.heroKickerTop)
                    } else if split.isEmpty {
                        primerUsoSection     // ④ Primer uso — «Arma tu semana» + plantillas + Crear mi plan
                            .padding(.top, EntrenarMetrics.heroKickerTop)
                    } else if todayRoutine == nil {
                        // ③ Descanso: héroe viejo (FER-132, intacto) + el mosaico v18 completo debajo
                        // (spec §«Estados no-rutina» — reemplaza a `muscleSectionModulo`+`bitacoraSection`).
                        heroSectionDescanso
                            .padding(.top, EntrenarMetrics.heroKickerTop)
                        v18Mosaico.padding(.top, LiquidSpace.s300)
                    } else if let r = todayRoutine {
                        // ① en rango / ② recupera — el héroe v18 (FER-171 · Parte B) + el mismo mosaico.
                        heroeV18(r)
                            .padding(.top, EntrenarMetrics.heroKickerTop)
                        v18Mosaico.padding(.top, LiquidSpace.s300)
                    }
                }
            }
            .padding(.top, LiquidSpace.s350)   // shared titled-tab top inset
            .padding(.horizontal, LiquidSpace.s600)
            .padding(.bottom, LiquidSpace.s600)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .pantallaFondo()
        // FER-969: el fallo de escritura es un banner honesto, no éxito silencioso. Componente
        // compartido desde 2026-07-19 (era la misma copia en tres pantallas).
        .saveErrorToast(isPresented: $saveError)
        // FER-137/251: el eco de «Plantilla aplicada» tras aplicar un plan desde la hoja de plantillas.
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
            WeekEditorSheet(split: $split, routines: routines,
                            orderedWeekdays: orderedWeekdays, todayWeekday: todayWeekday,
                            doneWeekdays: Set(orderedWeekdays.filter { trainedThisWeek($0) != nil }),
                            dayLetter: weekdayLetter)
                .environmentObject(repo)
        }
        // FER-251: plantillas — catálogo completo (`templatesGroup == nil`) o acotado al chip tocado.
        .sheet(isPresented: $showTemplates, onDismiss: { templatesGroup = nil }) {
            StarterTemplatesSheet(grupo: templatesGroup, onApplied: { showPlanAppliedToast = true }) {
                await load()
            }
            .environmentObject(repo).preferredColorScheme(.light)
        }
        // FER-952: the hub's Import chip opens the importer right here (same sheet as Tu Plan).
        .sheet(isPresented: $showHubImport) {
            WorkoutImportView { await load() }
                .environmentObject(repo).preferredColorScheme(.light)
        }
        // FER-251: «Desde cero» del primer uso — Biblioteca → crear (3×8), directo, sin menú previo.
        // «Tres caminos» (CrearPlanScreen) se archivó aquí mismo: la opción A del dueño dejó sus
        // tres puertas accesibles en directo (chips = plantillas, Desde cero, Importar) y la
        // pantalla quedó sin ninguna entrada — puerta fantasma fuera, no dormida.
        .navigationDestination(isPresented: $showLibrary) {
            ExerciseLibraryScreen(createFlow: true) { picks in createRoutineFromLibrary(picks) }
        }
        .navigationDestination(isPresented: $showTricks) {
            WorkshopTricksScreen()
        }
        // «En vivo» from the expanded «Más formas» pill — the live-HR free workout, the same sheet
        // «Otra forma» presents (sheet boundary).
        // FER-950: disc said «Rápido»/«Movilidad» but AppModel only re-opens the live session — make
        // that resume path explicit (ConfirmCard), never clobber.
        .liquidConfirm(
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
        // FER-167 (F2): el confirm «Terminar sesión ›» del héroe de sesión viva se retiró junto con
        // el héroe (FER-132 derogada) — Terminar/Descartar viven en el confirm de la píldora, que ya
        // cubre los 5 tabs incluido este.
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

    /// ① en rango / ② recupera — el héroe del hub v18 (FER-171 · Parte B). El pliegue de «Otra
    /// forma» que aloja es el EXISTENTE (`otraFormaPliegue`, sus cuatro puertas intactas).
    private func heroeV18(_ r: Routine) -> some View {
        EntrenarHubHeroe(
            // Ronda 2 · G13: `routineCategory[r.id]` directo — `load()` ya la llena por id; resolver
            // por NOMBRE (`region(name:)`) es un paso de más que además puede fallar si dos rutinas
            // comparten nombre. Mismo respaldo `.push` que el resto de la pantalla.
            tono: (routineCategory[r.id]?.family ?? .push).tono,
            routineName: r.name,
            meta: sesionMetaTexto(r.id),
            exerciseNames: todaySlotsExerciseNames,
            raiseLine: heroPillLine,
            // Ola 1 · E5: ámbar «Hoy mantienes» SOLO cuando no hay ninguna subida que mostrar —
            // ver `atLimitHeldToday`.
            raiseTono: raisesToday.isEmpty ? .ambar : .verde,
            onOpenRaise: { openRoutine(r.id) },
            onStart: { startToday() },
            otraFormaAbierta: otraFormaAbierta,
            onToggleOtraForma: { otraFormaAbierta.toggle() },
            pliegue: { otraFormaPliegue }
        )
    }

    /// «6 ejercicios · 18 series · ~50 min» en texto plano — el mismo dato que `sesionMetrics(_:)`
    /// ya componía como `View` teñida, aquí sin color (el héroe v18 lo pinta tinta700 uniforme).
    private func sesionMetaTexto(_ rid: String) -> String {
        let sets = todaySlots.reduce(0) { $0 + max(0, $1.re.targetSets) }
        var parts = [String(localized: "\(exerciseCounts[rid] ?? 0) exercises")]
        if sets > 0 { parts.append(String(localized: "\(sets) sets")) }
        if estMinutes > 0 { parts.append(String(localized: "~\(estMinutes) min")) }
        return parts.joined(separator: " · ")
    }

    /// Los nombres de los ejercicios de hoy, en el orden del plan — de `todaySlots` (ya prefetched
    /// por `load()`), no una segunda consulta al catálogo.
    private var todaySlotsExerciseNames: String {
        todaySlots.compactMap { $0.exercise.map(StrengthDisplay.name) }.joined(separator: " · ")
    }

    // MARK: - Mosaico v18 (FER-171 · Parte B)
    //
    // Semana → Dosis → Par → Cuerpo → Marcas+Volumen → Constancia → Historial, debajo del héroe (v18
    // o el viejo, según el estado) en los tres estados «con cuerpo» (rutina del día, descanso, sesión
    // viva — spec §«Estados no-rutina»). Cada módulo se auto-silencia con su propia regla; el mosaico
    // solo decide el aire (12 pt, `LiquidSpace.s300`) entre los que sí hablan.

    @ViewBuilder private var v18Mosaico: some View {
        EntrenarHubSemana(
            days: weekTokenDays, labels: orderedWeekdays.map(weekdayLetter),
            sessionsDone: orderedWeekdays.filter { trainedThisWeek($0) != nil }.count,
            sessionsPlanned: split.count, noPlanYet: split.isEmpty,
            todayIndex: orderedWeekdays.firstIndex(of: todayWeekday),
            onTapToday: { if let r = todayRoutine { openRoutine(r.id) } else { showWeekEditorSheet = true } },
            onTapOtherDay: { showWeekEditorSheet = true },
            onEdit: { openWeeklyPlan() }
        )
        EntrenarHubDosis(rows: dosisRows)
            .padding(.top, dosisRows.isEmpty ? 0 : LiquidSpace.s100)
        EntrenarHubPar(raises: parRaises, restReal: nil,
                      onOpenRaises: { if let r = todayRoutine { openRoutine(r.id) } })
            .padding(.top, parRaises.isEmpty ? 0 : LiquidSpace.s100)
        if let cuerpo = cuerpoData {
            EntrenarHubCuerpo(topMuscleName: cuerpo.name, topMuscleKey: cuerpo.key, onOpenMap: openMuscleMap)
                .padding(.top, LiquidSpace.s100)
        }
        if marcasData != nil || volumenData != nil {
            EntrenarHubMarcasVolumen(marca: marcasData, volumen: volumenData)
                .padding(.top, LiquidSpace.s100)
        }
        EntrenarHubConstancia(
            semanas: constanciaSemanas,
            sessionsThisMonth: TrainingWeeks.sessionsThisMonth(
                sessionTs: sessions.compactMap { $0.endTs != nil ? Double($0.startTs) : nil },
                now: Date(), calendar: Calendar.current),
            monthLabels: constanciaMonthLabels, todaySlot: constanciaTodaySlot
        )
        .padding(.top, LiquidSpace.s100)
        EntrenarHubHistorial(filas: historialFilas, gapDays: historialGapDays, promedio: historialPromedio,
                             onOpenHistory: openHistory)
            .padding(.top, LiquidSpace.s100)
    }

    // MARK: - DOSIS (v18) — top 4 músculos por series en 7 días; silencio con <3 sesiones en la ventana.

    private var dosisRows: [EntrenarHubDosis.Fila] {
        let sevenDaysAgo = Date().timeIntervalSince1970 - 7 * 86_400
        let sessionsIn7Days = sessions.filter { $0.endTs != nil && Double($0.startTs) >= sevenDaysAgo }.count
        guard sessionsIn7Days >= 3 else { return [] }
        let volumes = MuscleFatigueMap.weeklyVolumes(events: muscleEvents, days: 7)
        return volumes.prefix(4).map { v in
            let name = MuscleVocabulary.es[v.muscle] ?? v.muscle.capitalized
            return EntrenarHubDosis.Fila(id: v.muscle, label3: String(name.prefix(3)).uppercased(),
                                         sets: v.setsPerWeek,
                                         fraction: v.setsPerWeek / MuscleFatigueMap.weeklyBandHigh,
                                         low: v.band == .below)
        }
    }

    // MARK: - PAR (v18) — «Subidas listas» de `raisesToday`; «Descanso real» SIEMPRE nil (F2).

    /// Ronda 2 · D1: el ESCALÓN (`toKg − fromKg`), no el peso nuevo — mock «▲ 2.5 kg».
    /// `incrementNumber` (no `weightNumber`): es un incremento, conserva su decimal en las dos
    /// unidades (`StrengthDisplay` ya documenta por qué redondear un salto de progresión miente).
    /// Sin escalón real (`delta <= 0` — primera vez, o `toKg` no superó `fromKg`) la fila muestra el
    /// peso nuevo, SIN «▲» (el spec es explícito: el triángulo es exclusivo del escalón).
    private var parRaises: [EntrenarHubPar.Subida] {
        raisesToday.map { raise in
            let delta = raise.toKg - raise.fromKg
            guard delta > 0 else {
                return EntrenarHubPar.Subida(id: raise.name, name: raise.name,
                                             valueText: StrengthDisplay.weight(raise.toKg, system: unitSystem),
                                             isStep: false)
            }
            let valueText = "\(StrengthDisplay.incrementNumber(delta, system: unitSystem)) \(StrengthDisplay.weightUnit(unitSystem))"
            return EntrenarHubPar.Subida(id: raise.name, name: raise.name, valueText: valueText, isStep: true)
        }
    }

    // MARK: - CUERPO (v18) — el músculo más cargado, mismo `muscleLoads` que el resto de la sección.

    private var cuerpoData: (name: Text, key: String)? {
        guard let top = muscleLoads.first else { return nil }
        return (Text(MuscleAtlas.name(top.muscle)), top.muscle)
    }

    // MARK: - MARCAS (v18) — el PR más reciente + cuántos cayeron este mes + el PR anterior.

    /// Ronda 2 · O1: minúsculas — mock «Sentadilla · peso máx» (línea 317). Claves NUEVAS, en
    /// minúsculas, distintas de «Max weight»/«Peso máximo» (esas siguen usándose en Resumen de
    /// sesión con su propia mayúscula inicial — no se re-litiga esa pantalla).
    private static func prMetricLabel(_ m: PRMetric) -> String {
        switch m {
        case .maxWeight: return String(localized: "max weight")
        case .maxReps:   return String(localized: "most reps")
        case .maxVolume: return String(localized: "best set")
        }
    }

    private func prValueText(_ pr: PersonalRecord) -> (value: String, unit: String?) {
        switch pr.metric {
        case .maxWeight:
            return (StrengthDisplay.weightNumber(pr.valueKg ?? 0, system: unitSystem), StrengthDisplay.weightUnit(unitSystem))
        case .maxReps:
            return ("\(pr.reps ?? 0)", nil)
        case .maxVolume:
            let totalKg = (pr.valueKg ?? 0) * Double(pr.reps ?? 0)
            return (StrengthDisplay.weightNumber(totalKg, system: unitSystem), StrengthDisplay.weightUnit(unitSystem))
        }
    }

    private var marcasData: EntrenarHubMarcasVolumen.Marca? {
        guard let latestPR else { return nil }
        let cal = Calendar.current
        let monthLabel = cal.shortMonthSymbols[cal.component(.month, from: Date()) - 1].lowercased()
        let (valueText, unitText) = prValueText(latestPR)
        var previousText: String?
        if let previousPR {
            let (prevValue, prevUnit) = prValueText(previousPR)
            let prevText = prevUnit.map { "\(prevValue) \($0)" } ?? prevValue
            // Ronda 2 · G12: días CALENDARIO, no ÷86,400 — cerca de medianoche esa división daba
            // «hace 0 días» para un PR de ayer (mismo criterio que `historialGapDays`).
            let prevDay = cal.startOfDay(for: Date(timeIntervalSince1970: Double(previousPR.ts)))
            let today = cal.startOfDay(for: Date())
            let daysAgo = max(0, cal.dateComponents([.day], from: prevDay, to: today).day ?? 0)
            previousText = daysAgo == 1
                ? String(localized: "before \(prevText) · 1 day ago")
                : String(localized: "before \(prevText) · \(daysAgo) days ago")
        }
        return EntrenarHubMarcasVolumen.Marca(
            // Ronda 2 · O2: «Marcas · 0 en {mes}» es alcanzable (PR vigente de un mes anterior) —
            // 0 este mes ⇒ `countThisMonth: nil`, la regla dice solo «MARCAS» (decisión registrada).
            countThisMonth: personalRecordCountThisMonth > 0 ? personalRecordCountThisMonth : nil,
            monthLabel: monthLabel,
            valueText: valueText, unitText: unitText,
            exerciseAndMetric: "\(latestPRExerciseName) · \(Self.prMetricLabel(latestPR.metric))",
            previousText: previousText)
    }

    // MARK: - VOLUMEN (v18) — 8 semanas de tonelaje; silencio con <3 sesiones en el rango.

    private var volumenBuckets: [WeekVolumeBucket] {
        let raw = sessions.compactMap { s -> (ts: Double, volumeKg: Double)? in
            guard s.endTs != nil, let vol = sessionVolumes[s.id]?.volumeKg else { return nil }
            return (ts: Double(s.startTs), volumeKg: vol)
        }
        return TrainingWeeks.volumeBuckets(sessions: raw, weeks: 8, now: Date(), calendar: Calendar.current)
    }

    /// Ronda 2 · G5: con 3+ sesiones históricas pero 0 esta semana (p. ej. lunes, apenas arrancando),
    /// el numeral describía la semana ACTUAL — «0.0 t» fabricado. El numeral y la barra acentuada
    /// describen ahora la ÚLTIMA semana CON sesiones (la actual si tiene ≥1; si no, la última cubeta
    /// con `sessionCount ≥ 1`).
    ///
    /// Ronda 3 (anexo Grok r2): el delta es la TENDENCIA de semanas completas —
    /// `TrainingWeeks.volumeDeltaPercent` siempre compara «última semana completa vs. el promedio de
    /// las 3 completas anteriores», sin importar cuál semana resalta el numeral. Condicionarlo a
    /// `active.isCurrent` invertía el criterio: lo mostraba cuando el numeral SÍ era la semana en
    /// curso (numeral de esta semana, delta de otra) y lo callaba en lunes (el único caso en que
    /// numeral y delta describirían la MISMA semana). El mock empareja numeral de semana en curso +
    /// delta de tendencia — sin condición; las reglas de silencio del propio motor (`nil` con <4
    /// semanas completas) siguen aplicando solas.
    private var volumenData: EntrenarHubMarcasVolumen.Volumen? {
        let buckets = volumenBuckets
        let totalSessions = buckets.reduce(0) { $0 + $1.sessionCount }
        guard totalSessions >= 3, let activeIndex = buckets.lastIndex(where: { $0.sessionCount > 0 }) else { return nil }
        let active = buckets[activeIndex]
        let maxKg = buckets.map(\.volumeKg).max() ?? 0
        let bars = buckets.map { maxKg > 0 ? $0.volumeKg / maxKg : 0 }
        let delta = TrainingWeeks.volumeDeltaPercent(buckets: buckets)
        return EntrenarHubMarcasVolumen.Volumen(tons: active.volumeKg / 1000, deltaPercent: delta,
                                                bars: bars, accentIndex: activeIndex)
    }

    // MARK: - CONSTANCIA (v18) — 13 semanas × 3 huecos, la MISMA familia por sesión que el calendario
    // de `WorkoutHistoryScreen` (`routineCategory[routineId]?.family`). Ronda 3: comentario corregido
    // — desde G3 (ronda 2) una sesión SIN familia clasificable ya NO cae en `.push`, cae en
    // `.sesion(nil)` → celda LLENA neutra (`EntrenarHubConstancia.celda`); ver `constanciaSemanas`.

    /// Huecos por semana en la rejilla — `TrainingWeeks.consistency(slotsPerWeek:)` usa el mismo tope.
    private static let constanciaSlotsPerWeek = 3

    private var consistencyWeeks: [TrainingWeeks.ConsistencyWeek] {
        let raw = sessions.compactMap { s -> (ts: Double, family: RoutineRegion?)? in
            guard s.endTs != nil else { return nil }
            return (ts: Double(s.startTs), family: s.routineId.flatMap { routineCategory[$0] })
        }
        return TrainingWeeks.consistency(sessions: raw, weeks: 13, slotsPerWeek: Self.constanciaSlotsPerWeek,
                                         now: Date(), calendar: Calendar.current)
    }

    /// Ronda 2 · G3: `week.sessions` (de `TrainingWeeks.consistency`) es literalmente «la familia de
    /// cada sesión real de esa semana» — un `nil` AHÍ significa «sesión sin familia clasificable»
    /// (p. ej. «Rápido»), NUNCA «sin sesión». El hueco VACÍO es que el arreglo sea más corto que
    /// `constanciaSlotsPerWeek`. Antes `$0?.family` colapsaba los dos casos en el mismo `nil` y una
    /// sesión sin familia desaparecía de la rejilla — se rellena aquí a los 3 huecos explícitos.
    private var constanciaSemanas: [EntrenarHubConstancia.Semana] {
        consistencyWeeks.map { week in
            var huecos = week.sessions.map { EntrenarHubConstancia.Semana.Hueco.sesion($0?.family) }
            while huecos.count < Self.constanciaSlotsPerWeek { huecos.append(.vacio) }
            return EntrenarHubConstancia.Semana(huecos: huecos, isCurrent: week.isCurrent)
        }
    }

    private var constanciaMonthLabels: [Int: String] {
        let cal = Calendar.current
        var labels: [Int: String] = [:]
        var lastMonth: Int?
        for (i, week) in consistencyWeeks.enumerated() {
            let month = cal.component(.month, from: week.weekStart)
            if i == 0 || month != lastMonth {
                labels[i] = cal.shortMonthSymbols[(month - 1) % 12].lowercased()
            }
            lastMonth = month
        }
        return labels
    }

    /// La celda de HOY: la última columna, en el primer hueco todavía vacío de esa semana — `nil`
    /// cuando la semana actual ya llenó sus 3 huecos (no hay dónde resaltar «hoy»).
    private var constanciaTodaySlot: (week: Int, slot: Int)? {
        guard let lastIndex = consistencyWeeks.indices.last else { return nil }
        let count = consistencyWeeks[lastIndex].sessions.count
        guard count < Self.constanciaSlotsPerWeek else { return nil }
        return (week: lastIndex, slot: count)
    }

    // MARK: - HISTORIAL (v18) — 2 filas + hueco + promedio 7 días.

    private var historialFilas: [EntrenarHubHistorial.Fila] {
        recentSessions90.prefix(2).map { session in
            EntrenarHubHistorial.Fila(
                id: session.id, family: session.routineId.flatMap { routineCategory[$0] }?.family,
                title: bitacoraTitle(session), subtitle: bitacoraSubtitle(session),
                action: { openWorkoutSession(bitacoraRoute(session)) })
        }
    }

    /// Días naturales sin registrar ENTRE las dos filas (0 = sin hueco).
    private var historialGapDays: Int {
        let rows = Array(recentSessions90.prefix(2))
        guard rows.count == 2 else { return 0 }
        let cal = Calendar.current
        let newerDay = cal.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(rows[0].startTs)))
        let olderDay = cal.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(rows[1].startTs)))
        let days = cal.dateComponents([.day], from: olderDay, to: newerDay).day ?? 0
        return max(0, days - 1)
    }

    private var historialPromedio: (minutes: Int, kcal: Int?, tons: Double)? {
        let raw = sessions.compactMap { s -> (ts: Double, durationS: Double, volumeKg: Double, kcal: Double?)? in
            guard let end = s.endTs, end > s.startTs else { return nil }
            return (ts: Double(s.startTs), durationS: Double(end - s.startTs),
                   volumeKg: sessionVolumes[s.id]?.volumeKg ?? 0, kcal: s.energyKcal)
        }
        guard let avg = TrainingWeeks.sevenDayAverage(sessions: raw, now: Date()) else { return nil }
        return (minutes: avg.minutes, kcal: avg.kcal, tons: avg.tons)
    }

    /// ③ Descanso (+ leve): el héroe del handoff «Descanso» — título a 40 pt, SIN numerales ni
    /// progresión (no hay sesión que medir), y la única puerta es «Movilidad · 20 min» en verde de
    /// marca. El hilo de arriba ya pinta ámbar cuando el consejo de hoy es `.lighter`; este bloque
    /// solo añade la cláusula de texto — nunca reordena ni repite el veredicto.
    private var heroSectionDescanso: some View {
        EntrenarModulo(tono: .neutro, intensidad: LiquidTonoMetrics.intensidadDefault,
                       insets: EntrenarHubMetrics.heroInsets) {
            VStack(alignment: .leading, spacing: .zero) {
                // FER-132 ronda 2: kicker FIJO «Hoy» — copy literal del prototipo (`descansoLeve.hk: "Hoy"`,
                // sin el día). `hoyOverline` interpola el día para los héroes con rutina; reusarlo aquí
                // colaba «Hoy · Martes» en cualquier descanso que no fuera `.recover`.
                Text("Today").entrenarCabeceraKicker().foregroundStyle(LiquidColor.tinta500)
                Text("Rest")
                    .font(LiquidType.displayM).tracking(LiquidType.displayMTracking)
                    .foregroundStyle(LiquidColor.tinta900)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, EntrenarMetrics.heroTitleTop)
                Text(descansoSubtitulo)
                    .font(LiquidType.cuerpoBanner).foregroundStyle(LiquidColor.tinta700)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, EntrenarMetrics.heroSubTop)
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: EntrenarMetrics.ctaRowGap) {
                        movilidadButton
                        otraFormaEnlace(fillsWidth: false)
                    }
                    VStack(alignment: .leading, spacing: LiquidSpace.s200) {
                        movilidadButton
                        otraFormaEnlace(fillsWidth: false)
                    }
                }
                .padding(.top, EntrenarMetrics.ctaRowTop)
                otraFormaPliegue
            }
        }
    }

    /// «Movilidad · 20 min» — verde de marca también en descanso (FER-249, decisión del dueño).
    private var movilidadButton: some View {
        LiquidGlassButton("Mobility · 20 min", variant: .primary) { startMobilityFromDisc() }
    }

    /// «tu semana marca descanso» + (si el consejo de hoy es `.lighter`) la cláusula ámbar del
    /// handoff — LA MISMA señal que ya tiñe el hilo de arriba, nombrada en el subtítulo.
    private var descansoSubtitulo: String {
        advice == .lighter
            ? String(localized: "Your week marks rest · you woke up with a signal off")
            : String(localized: "Your week marks rest")
    }

    /// The handoff's per-routine tint (mock 1a). The family is derived from the routine's exercises'
    /// `primaryMuscles` via the shared `RoutineClassifier` (FER-775) — never guessed from the name or a
    /// per-process hash, so a routine keeps the same color across launches. Via `EntrenarFamily.tono`:
    /// push → ámbar, pull → cian, leg / full body → índigo. A routine with no classifiable exercises
    /// (cardio, «Rápido» without a routine) falls back to ámbar, the screen's default hue. Used for the
    /// SOLID marks (text, borders); full body reads as indigo here and only becomes a gradient in
    /// `routineFill`.
    private func routineTint(_ region: RoutineRegion?) -> Color {
        region?.family.tono.base ?? LiquidColor.ambar
    }

    /// The FILL for a routine's dot/square. Same as `routineTint` except full body reads as the mock's
    /// 135° ember→indigo gradient (its whole point is that it spans the split).
    private func routineFill(_ region: RoutineRegion?) -> AnyShapeStyle {
        if region == .fullBody {
            return AnyShapeStyle(LinearGradient(colors: [LiquidColor.ambar, LiquidColor.indigo],
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
        // Ola 1 · E10: la sesión se guarda con la semana con la que se SEMBRÓ esta tabla — la misma
        // que ya recortó los slots si tocaba ligera.
        model.startStrengthSession(routineId: r.id, routineName: r.name, slots: todaySlots,
                                   programWeek: todayServing.flatMap(\.stampWeek),
                                   deload: todayServing.flatMap(\.stampDeload))
    }


    /// «Entrenamiento rápido de fuerza» (mock 1p, FER-762): no routine, no slots — the session starts
    /// empty and `LiveStrengthSheet` shows its own empty-state (search + freshness suggestions) until the
    /// first exercise is added. With a live session, confirm resume instead of looking like a new start
    /// (FER-950 — AppModel's guard only re-presents the existing sheet).
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
    // (The sunken section band itself is `LiquidFranjaSeccion` / `LiquidSectionHeader` in CenitDesign
    // — promoted in FER-940 when «Tu Plan» adopted the same header.)
    //
    // Big Grotesk numerals for the session's shape (min · exercises · sets), the earned raise as the
    // green line (FER-G — it lives where you start), and the recovery hint on a thin green filete.
    // Rest days and empty routines skip the whole section — nothing to detail.

    /// «Hoy subes: Press banca · 82,5 kg y Press militar · 26 kg» — the names+loads in the raise
    /// green. La píldora sigue mostrando el peso NUEVO (`toKg`) — el escalón es cosa de la tile
    /// «Subidas listas» del mosaico (Ronda 2 · D1), no del héroe.
    private var raiseText: Text {
        let parts = raisesToday.map { "\($0.name) · \(StrengthDisplay.weight($0.toKg, system: unitSystem))" }
        // Grotesk RELATIVO al subhead, igual que su fila hermana: las dos pueden estar en pantalla a
        // la vez y con Dynamic Type una crecía y la otra se quedaba clavada en 13 pt.
        let strong = parts.map {
            Text(verbatim: $0)
                .font(LiquidType.tituloFilaNegrita)
                .monospacedDigit()
                // Verde profundo (AA ≥ 4.5:1) — mismo rol que el verde de lectura de subidas.
                .foregroundStyle(LiquidColor.verdeProfundo)
        }
        // Ronda 2 · O1: dos puntos — mock «Hoy subes: sentadilla · 82.5 kg» (línea 254).
        var t = Text("Today you raise") + Text(verbatim: ": ")
        for (i, s) in strong.enumerated() {
            if i > 0 { t = t + Text(verbatim: " · ") }
            t = t + s
        }
        return t
    }

    /// Ola 1 · E5 (Pasada 2, `ola1-pantallas.html` §②): la píldora del héroe, verde con `raiseText`
    /// cuando algo sube hoy, o ámbar con `mantieneText` cuando nada sube pero un ejercicio se quedó
    /// al fallo. Una sesión que sube siempre gana el espacio del héroe sobre una que mantiene.
    private var heroPillLine: Text? {
        if !raisesToday.isEmpty {
            guard let line2 = raiseRhythmLine else { return raiseText }
            return raiseText + Text(verbatim: "\n") + line2
        }
        return mantieneText
    }

    /// «Llegaste a las reps y te sobraban 3. Una sesión bastó.» / «Tres veces al fallo y con las
    /// reps: subes, o cambia el ritmo.» — SOLO cuando hay una única subida y su ritmo explica el
    /// porqué (D-Q1/D-Q6). Con 0 o 2+ subidas, o sin nota de ritmo, el héroe queda idéntico a hoy
    /// (normal / sin RPE): esta pantalla no re-abre FER-171 combinando varias razones en una línea.
    private var raiseRhythmLine: Text? {
        guard raisesToday.count == 1, let note = raisesToday[0].rhythmNote else { return nil }
        switch note {
        case .comfortable(let reserveReps):
            return Text(String(localized: "You hit the reps with \(reserveReps) to spare. One session was enough."))
        case .atLimitCap:
            return Text("Three sessions at your limit and you still hit the reps: you raise, or change the rhythm.")
        case .atLimitHold:
            return nil   // este caso nunca sube — no debería llegar aquí, pero no hay línea que decir.
        }
    }

    /// «Hoy mantienes: Sentadilla · 100 kg» — el ejercicio que cumplió las reps al fallo (0 en
    /// reserva) y por eso el ritmo lo deja invisible al ciclo, en vez de subir. Solo el primero
    /// (días con más de uno son un edge case raro; ver GAPS del reporte de E5).
    private var mantieneText: Text? {
        guard raisesToday.isEmpty, let held = atLimitHeldToday.first else { return nil }
        let strong = Text(verbatim: "\(held.name) · \(StrengthDisplay.weight(held.weightKg, system: unitSystem))")
            .font(LiquidType.tituloFilaNegrita).monospacedDigit()
            .foregroundStyle(LiquidTono.ambar.rotulo)
        let line1 = Text("Today you maintain") + Text(verbatim: ": ") + strong
        return line1 + Text(verbatim: "\n")
            + Text("You hit the reps, but at your limit. One easier session and it counts toward the raise.")
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
    // MARK: - SEMANA (v18) — datos compartidos con `EntrenarHubSemana`

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
    /// pliegue solo se aloja desde el héroe v18 (`heroeV18`) y `heroSectionDescanso`, y el `body`
    /// solo pinta esos dos héroes cuando `model.strengthSession == nil`. La subtítulo «Resumes the
    /// session you have open» nunca se alcanzaba.
    private var puertas: [Puerta] {
        [
            // FER-246 — misma etiqueta que la sesión que abre (`Quick strength` / «Rápido de fuerza»).
            Puerta(icon: "bolt.fill", label: "Quick strength",
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
            withAnimation(reduceMotion ? LiquidMotion.fundido : LiquidMotion.suave) {
                otraFormaAbierta.toggle()
            }
        } label: {
            HStack(spacing: LiquidSpace.s100) {
                Text("Other ways")
                    .font(LiquidType.cuerpoBanner).foregroundStyle(LiquidColor.tinta700)
                CenitIcon.down.image
                    .font(LiquidType.iconSF(size: 12).weight(.semibold))
                    .foregroundStyle(LiquidColor.tinta500)
                    .rotationEffect(.degrees(otraFormaAbierta ? 180 : 0))
                    .accessibilityHidden(true)
                if fillsWidth { Spacer(minLength: 0) }
            }
            .padding(.horizontal, fillsWidth ? 0 : LiquidSpace.s100 + 2)   // handoff «padding 0 6px»
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
            VStack(alignment: .leading, spacing: .zero) {
                filoDelPliegue
                ForEach(Array(puertas.enumerated()), id: \.element.id) { i, puerta in
                    puertaRow(puerta)
                    if i < puertas.count - 1 { filoDelPliegue }
                }
                filoDelPliegue
                Text("Your routine for today stays put: this is separate, no guilt.")
                    .font(LiquidType.cuerpo).foregroundStyle(LiquidColor.tinta500)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, LiquidSpace.s250)
            }
            .padding(.top, LiquidSpace.s200)
            .transition(LiquidMotion.fadeTransition)
            .accessibilityElement(children: .contain)
        }
    }

    private var filoDelPliegue: some View {
        Rectangle().fill(LiquidColor.tinta10).frame(height: 1)
    }

    /// La cabecera de un nivel del hub (FER-130 «Ritmo 1b»): filo superior de 1 pt + el aire del
    /// handoff antes de la fila — envuelve el mismo `EntrenarNivel` que ya sirve «Ver toda la
    /// biblioteca» en la sesión en vivo, sin tocar ese componente ni su otro llamador. El margen
    /// EXTERNO del nivel (18 el primero, 2 los siguientes) lo pone quien coloca `semanaSection` /
    /// `muscleSection` / `bitacoraSection`, no esta función — así un mismo nivel sirve como primero
    /// o como segundo.
    private func nivelHub<Nivel: View>(@ViewBuilder _ nivel: () -> Nivel) -> some View {
        VStack(alignment: .leading, spacing: .zero) {
            filoDelPliegue
            nivel().padding(.top, EntrenarMetrics.levelPadTop)
        }
    }

    /// Una fila del pliegue: glifo, título y subtítulo. Sin «›» al final — dos de las cuatro no
    /// navegan, arrancan, y «›» ya significa «navega» en esta pantalla.
    ///
    /// El glifo va en `LiquidType.infoGlifo` (escala con el texto), no en `iconSF` fijo: aquí el
    /// texto sí escala. Y `minWidth`, nunca `width`, para que a AX5 no le corte la cabeza al símbolo.
    private func puertaRow(_ puerta: Puerta) -> some View {
        Button {
            otraFormaAbierta = false   // cierra SIEMPRE, en las cuatro: una regla, no cuatro casos
            puerta.action()
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: LiquidSpace.s225) {
                Image(systemName: puerta.icon)
                    .font(LiquidType.infoGlifo).foregroundStyle(LiquidColor.tinta700)
                    .frame(minWidth: HojaMetrics.marcaDiametro, alignment: .leading)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: LiquidSpace.s050) {
                    Text(puerta.label).font(LiquidType.tituloGemela).foregroundStyle(LiquidColor.tinta900)
                    Text(puerta.subtitle)
                        .font(LiquidType.cuerpo).foregroundStyle(LiquidColor.tinta500)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: LiquidSpace.s200)
            }
            .padding(.vertical, LiquidSpace.s200)
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
            HStack(spacing: LiquidSpace.s225) {
                Image(systemName: icon)
                    .font(LiquidType.iconSF(size: 18))
                    .foregroundStyle(LiquidColor.tinta700)
                Text(label)
                    .font(LiquidType.cuerpoBanner)
                    .foregroundStyle(LiquidColor.tinta700)
                Spacer(minLength: LiquidSpace.s200)
                CenitIcon.disclosure.image.font(LiquidType.iconSF(size: 15).weight(.semibold))
                    .foregroundStyle(LiquidColor.tinta500)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, LiquidSpace.s300)
            .frame(maxWidth: .infinity, minHeight: LiquidControl.hitTarget, alignment: .leading)   // HIG tap target (FER-944)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    // MARK: - CUERPO (v18) — datos compartidos con `EntrenarHubCuerpo`

    /// El MISMO motor que «Tu cuerpo» (`MuscleFatigueMap`, vía `repo.muscleSetEvents`) — nunca una
    /// segunda derivación del mapa. `load()` llena `muscleEvents`; aquí solo se reduce a `loads`.
    private var muscleLoads: [MuscleFatigueMap.MuscleLoad] { MuscleFatigueMap.loads(events: muscleEvents) }

    // MARK: - HISTORIAL (v18) — datos compartidos con `EntrenarHubHistorial`

    /// Sesiones COMPLETADAS en los últimos 90 días naturales, del más reciente al más viejo.
    /// `endTs != nil` — igual que `WorkoutHistoryScreen.latestSessionByLocalDay`/`weeklyVolumes` filtran
    /// el MISMO array `sessions` — para que una sesión EN CURSO nunca aparezca como fila terminada con
    /// duración/volumen mal calculados, ni abra el acta de un entrenamiento que aún no cerró.
    private var recentSessions90: [StrengthSession] {
        let cutoff = Date().timeIntervalSince1970 - 90 * 86_400
        return sessions.filter { $0.endTs != nil && Double($0.startTs) >= cutoff }
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

    /// «Músculos cargados e Historial aparecen después de tu primera sesión. Mientras, silencio.» —
    /// plan armado, cero sesiones registradas todavía (copy.md «Primer uso»).
    private var silencioPrimeraSesion: some View {
        // Mismo filo superior que cualquier otro nivel (`nivelHub`): sin él el corte entre TU SEMANA y
        // este mensaje no se leía igual que el corte entre dos niveles cualesquiera.
        VStack(alignment: .leading, spacing: .zero) {
            filoDelPliegue
            Text("Loaded muscles and History appear after your first session. Until then, silence.")
                .font(LiquidType.cuerpo).foregroundStyle(LiquidColor.tinta700)
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

    // MARK: - ④ Primer uso (`split` vacío) — «Arma tu semana» (FER-132 · FER-251)
    //
    // Sin ningún día asignado: héroe de arranque intacto + UNA primaria (3 chips honestos, cada uno
    // abre SU grupo con preview) + DOS secundarias («Desde cero», «Importar»). FER-251 apaga el CTA
    // «Crear mi plan» y la tira WeekTokens vacía. Si ya hay rutinas sin día (`!routines.isEmpty`),
    // aparece «TU SEMANA — Asigna un día» hacia el editor semanal. SIN «Otra forma» / Músculos /
    // Bitácora — la nota de silencio los explica. `loadErrorState` gana sobre esta sección.

    private var primerUsoSection: some View {
        VStack(alignment: .leading, spacing: .zero) {
            EntrenarModulo(tono: .neutro, intensidad: LiquidTonoMetrics.intensidadDefault,
                           insets: EntrenarHubMetrics.heroInsets) {
                VStack(alignment: .leading, spacing: .zero) {
                    Text("Let's start")
                        .entrenarCabeceraKicker().foregroundStyle(LiquidColor.tinta500)
                    Text("Build your week")
                        .font(LiquidType.displayL).tracking(LiquidType.displayLTracking)
                        .foregroundStyle(LiquidColor.tinta900)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, EntrenarMetrics.heroTitleTop)
                    Text("Choose a template or build your own routine · Entrenar serves it to you every day after that")
                        .font(LiquidType.cuerpoBanner).foregroundStyle(LiquidColor.tinta700)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, EntrenarMetrics.heroSubTop)
                    primerUsoChips.padding(.top, LiquidSpace.s300)
                    // Secundarias: «Desde cero» (biblioteca) + «Importar» — sin «Crear mi plan».
                    Button { showLibrary = true } label: {
                        HStack(spacing: LiquidSpace.s100) {
                            Text("From scratch").font(LiquidType.cuerpoBanner).foregroundStyle(LiquidColor.tinta700)
                            CenitIcon.disclosure.image
                                .font(LiquidType.iconSF(size: 12).weight(.semibold)).foregroundStyle(LiquidColor.tinta500)
                                .accessibilityHidden(true)
                        }
                        .frame(minHeight: EntrenarMetrics.row, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(EntrenarPressStyle())
                    .accessibilityElement(children: .combine)
                    Button { showHubImport = true } label: {
                        HStack(spacing: LiquidSpace.s100) {
                            Text("Import your AI's plan").font(LiquidType.cuerpoBanner).foregroundStyle(LiquidColor.tinta700)
                            CenitIcon.disclosure.image
                                .font(LiquidType.iconSF(size: 12).weight(.semibold)).foregroundStyle(LiquidColor.tinta500)
                                .accessibilityHidden(true)
                        }
                        .frame(minHeight: EntrenarMetrics.row, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(EntrenarPressStyle())
                    .accessibilityElement(children: .combine)
                }
            }
            // FER-251: rutinas creadas pero sin día — fila hacia el editor; ausente con 0 rutinas.
            if !routines.isEmpty {
                nivelHub {
                    EntrenarNivel("Your week", value: "Assign a day", kickerStyle: .handoff) {
                        openWeeklyPlan()
                    }
                }
                .padding(.top, EntrenarMetrics.firstLevelTop)
            }
            silencioPrimeraSesion.padding(.top, EntrenarMetrics.levelTop)
        }
    }

    /// Tres chips honestos (FER-251): cada uno abre `StarterTemplatesSheet` ACOTADA a su grupo.
    /// Subtítulo = conteo real («3 rutinas» / «1 rutina» / «2 rutinas»). A tamaños AX se apilan.
    private var primerUsoChips: some View {
        let chips = Self.primerUsoGroups
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: LiquidSpace.s200) {
                ForEach(chips, id: \.name) { item in
                    primerUsoChip(name: item.name, group: item.group)
                }
            }
            VStack(alignment: .leading, spacing: LiquidSpace.s200) {
                ForEach(chips, id: \.name) { item in
                    primerUsoChip(name: item.name, group: item.group)
                }
            }
        }
    }

    private func primerUsoChip(name: String, group: StarterTemplate.Group) -> some View {
        let count = StarterTemplates.inGroup(group).count
        let countText = count == 1
            ? String(localized: "1 routine")
            : String(localized: "\(count) routines")
        return Button {
            templatesGroup = group
            showTemplates = true
        } label: {
            // 1 pt es el hairline entre nombre y conteo dentro del chip, más chico
            // que `LiquidSpace.s100` (4). El archivo ya tiene otros gaps sin token.
            VStack(alignment: .leading, spacing: LiquidSpace.s025) {
                Text(LocalizedStringKey(name)).font(LiquidType.tituloGemela).foregroundStyle(LiquidColor.tinta900)
                Text(countText).font(LiquidType.cuerpo).foregroundStyle(LiquidColor.tinta500)
            }
            .padding(.horizontal, LiquidSpace.s200)
            // EntrenarMetrics.row (44 pt) = mínimo HIG — no bajar.
            .frame(maxWidth: .infinity, minHeight: EntrenarMetrics.row, alignment: .leading)
            .liquidGlass(.pastillaSolida)
        }
        .buttonStyle(EntrenarPressStyle())
        .disabled(!loaded)
        .accessibilityLabel(Text(LocalizedStringKey(name)) + Text(verbatim: ", ") + Text(verbatim: countText))
        .accessibilityHint(Text("Show the plan"))
    }

    /// Los tres splits destacados del primer uso (mismo vocabulario que `StarterTemplatesSheet`).
    private static let primerUsoGroups: [(name: String, group: StarterTemplate.Group)] = [
        ("Push Pull Legs", .pushPullLegs),
        ("Full body", .fullBody),
        ("Upper / Lower", .upperLower),
    ]

    /// «Desde cero» del primer uso: misma materialización 3×8 que `CrearPlanScreen.createRoutine`.
    private func createRoutineFromLibrary(_ picks: [Exercise]) {
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

    // MARK: - Error state · store couldn't be read (distinct from «no plan yet»)
    //
    // When `repo.storeHandle()` returns nil the read failed — the user likely HAS a plan we just couldn't
    // open. Showing the onboarding empty state here would wrongly push them to rebuild their week, so we
    // surface a plain error with a retry that re-runs `load()`.
    private var loadErrorState: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s300) {
            LiquidPatternBlock(
                overline: nil,
                lineas: [
                    String(localized: "I couldn't read your plan"),
                    String(localized: "Something failed opening your routines · your data is intact"),
                ],
                tono: LiquidColor.tinta500)
            LiquidGlassButton("Retry", variant: .solida) { Task { await load() } }
        }
    }

    /// Localized short weekday letter (respects locale), single character. Solo para la TIRA de 7 celdas:
    /// ahí la posición desambigua, igual que en cualquier calendario. Fuera de esa retícula usa
    /// `weekdayShort`, porque la inicial sola es ambigua —«M» es martes Y miércoles en español, y en
    /// inglés «T» es Tuesday Y Thursday.
    private func weekdayLetter(_ wd: Int) -> String {
        let s = Calendar.current.veryShortWeekdaySymbols[(wd - 1) % 7]
        return s.uppercased()
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

    // MARK: - Cabecera (FER-130 «Ritmo 1b»)
    //
    // «Entrenar · {fecha}» a la izquierda, el «?» de los trucos a la derecha — reemplaza al wordmark
    // retirado en FER-952. Antes el «?» vivía en la misma fila que el hilo del veredicto; el handoff
    // los separa: la cabecera es de la PANTALLA (nombra el tab y el día), el hilo es del CUERPO.

    private var cabecera: some View {
        HStack(spacing: LiquidSpace.s200) {
            Text(cabeceraKicker)
                .liquidKicker()
                .foregroundStyle(LiquidColor.tinta700)
            Spacer(minLength: LiquidSpace.s200)
            Button { showTricks = true } label: {
                Image(systemName: "questionmark.circle")
                    .font(LiquidType.iconSF(size: 18))
                    .foregroundStyle(LiquidColor.tinta500)
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
    /// `CenitFormat.weekdayHeading` (CenitDesign): mismo helper compartido con la cabecera de «Tu
    /// cuerpo» (quisquilloso ronda 4: antes dos copias a mano).
    private var cabeceraFecha: String { CenitFormat.weekdayHeading(Date()) }

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
        var raisingToday: [(name: String, fromKg: Double, toKg: Double,
                            rhythmNote: ProgressionPlanner.RaiseRhythmNote?)] = []
        var heldToday: [(name: String, weightKg: Double)] = []
        // The verdict this whole pass was built with, published together with the slots it seeded.
        var passAdvice = repo.trainingAdvice
        // Ola 1 · E10: la semana del programa se lee UNA vez por pase, igual que el veredicto.
        var passServing: ProgramServing.Context?
        if let tid = WeeklySplit.todayRoutineId(split: splitMap, todayWeekday: todayWeekday) {
            // FER-124: los slots los siembra `repo.seedTodaySlots` — EL MISMO método que usa el
            // arranque desde la muñeca, así que el teléfono y el reloj no pueden ofrecer rutinas
            // distintas. El héroe deriva la subida de los slots ya sembrados, no de un segundo bucle.
            // Un veredicto para toda la tabla (FER-82), leído antes de sembrar.
            let advice = repo.trainingAdvice
            passAdvice = advice
            let inventory = await MainActor.run { PlatesStore().inventory }
            passServing = await repo.programServing()
            let seeded = await repo.seedTodaySlots(routineId: tid, advice: advice, inventory: inventory,
                                                   serving: passServing)
            slots.append(contentsOf: seeded)
            // FER-171 · hub v18: la subida RETENIDA (`raise.waiting`) ya no tiene pastilla propia en
            // el héroe — el mock v18 solo muestra la subida APLICADA; ver el reporte del agente.
            raisingToday = seeded.compactMap { slot in
                guard let raise = slot.raise, !raise.waiting else { return nil }
                let name = slot.exercise.map(StrengthDisplay.name) ?? slot.re.exerciseId
                return (name: name, fromKg: raise.fromKg, toKg: raise.toKg, rhythmNote: slot.raiseRhythmNote)
            }
            // Ola 1 · E5: cumplió las reps al fallo — el ritmo lo deja invisible al ciclo (mantiene).
            // Gate QA FER-331 O2: el peso viaja EN la nota (`workingKg`, del planner) — no se
            // re-deriva de `lastSets`, que puede traer una sesión más nueva que `visible` ya excluyó
            // (opted-out / semana ligera).
            heldToday = seeded.compactMap { slot in
                guard case .atLimitHold(let kg)? = slot.raiseRhythmNote else { return nil }
                let name = slot.exercise.map(StrengthDisplay.name) ?? slot.re.exerciseId
                return (name: name, weightKg: kg)
            }
        }
        let recent = (try? await store.recentSessions(limit: 200)) ?? []
        // FER-131 «Niveles»: el mismo fetch que `TrainingBodyScreen` (84 días) para «Músculos
        // cargados» — nunca una segunda derivación del mapa — más el volumen agregado por sesión.
        let cal = Calendar.current
        let muscleSince = cal.date(byAdding: .day, value: -84, to: cal.startOfDay(for: Date())) ?? Date()
        let muscleEv = await repo.muscleSetEvents(sinceTs: Int(muscleSince.timeIntervalSince1970),
                                                  resetTs: Int(muscleRecoveryResetAt))
        let volumes = await repo.sessionVolumes()
        // FER-171 · hub v18 «Marcas»: el PR más reciente + cuántos cayeron este mes + el PR anterior
        // del mismo ejercicio+métrica (el nombre del ejercicio se resuelve solo si hay marca).
        let latest = await repo.latestPersonalRecord()
        let startOfMonth = cal.date(from: cal.dateComponents([.year, .month], from: Date())) ?? Date()
        let countThisMonth = await repo.personalRecordCount(sinceTs: startOfMonth.timeIntervalSince1970)
        var previous: PersonalRecord?
        var latestName = ""
        if let latest {
            previous = await repo.previousPersonalRecord(exerciseId: latest.exerciseId, metric: latest.metric,
                                                          beforeTs: Double(latest.ts))
            latestName = await repo.resolvedExercise(latest.exerciseId).map(StrengthDisplay.name) ?? latest.exerciseId
        }
        // Every read is done: from here on there is no await, so the publish below is atomic. A pass
        // that lost the race drops its work y NO toca `loaded`: el pase ganador ya está en vuelo y lo
        // encenderá con datos. Encenderlo aquí pintaba el estado de PRIMER USO («Empecemos por tu
        // plan») a alguien que sí tiene plan — cambiar un parpadeo en blanco por una mentira.
        guard seq == repo.refreshSeq else { return false }
        raisesToday = raisingToday
        atLimitHeldToday = heldToday
        slotsAdvice = passAdvice
        todayServing = passServing
        routines = rs
        exerciseCounts = counts
        routineMuscles = muscles
        routineCategory = categories
        split = splitMap
        todaySlots = slots
        sessions = recent
        muscleEvents = muscleEv
        sessionVolumes = volumes
        latestPR = latest
        previousPR = previous
        latestPRExerciseName = latestName
        personalRecordCountThisMonth = countThisMonth
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
