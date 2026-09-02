#if DEBUG && os(iOS)
import SwiftUI
import CenitStore
import StrandTraining
import CenitDesign

/// **Canvas del mapa de estados** — todas las variantes de una pantalla, lado a lado, dentro del
/// `#Preview` de Xcode. Cada celda construye un `AppModel`, lo siembra con el MISMO `ScreenshotFixtures`
/// que alimenta las capturas del muro (`docs/appmap/`), y muestra la pantalla REAL escalada. Es el
/// código vivo: el canvas está siempre al día, gratis, sin correr el harness.
///
/// Hermano del muro HTML (`Tools/build-appmap.py`): el muro es PNGs para compartir; este es el mismo
/// mapa pero interactivo dentro de Xcode. Uno y otro salen del mismo código y de los mismos fixtures.
enum AppMap {
    /// (fixture, título) por estado de Hoy. `nil` de fixture = arranque limpio (Vacío).
    static let hoy: [(state: String?, title: String)] = [
        (nil,             "Vacío"),
        ("calibrating",   "Calibrando"),
        ("downloading",   "Descargando"),
        ("primed",        "A punto"),
        ("balanced",      "Equilibrado"),
        ("strained",      "Exigido"),
        ("rundown",       "Desgastado"),
        ("insufficient",  "Insufficient"),
    ]
}

/// Una celda del mapa: siembra su propio `AppModel` en `.task` y monta `TodayView` con el entorno real.
private struct AppMapCell: View {
    let fixture: String?
    let title: String
    var scale: CGFloat = 0.42

    @State private var model = AppModel()
    @State private var seeded = false

    var body: some View {
        VStack(spacing: LiquidSpace.s250) {
            TodayView()
                .environmentObject(model.repo)
                .environment(model)
                .environmentObject(TabRouter())
                .environmentObject(HealthKitBridge(repo: model.repo,
                                                   appleDeviceId: "map-apple",
                                                   noopDeviceId: "map"))
                .preferredColorScheme(.light)
                .frame(width: 393, height: 852)
                // Marco de iPhone del mapa de pantallas (42; ya en baseline no-radius-literal).
                .clipShape(RoundedRectangle(cornerRadius: 42, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 42, style: .continuous)
                    .stroke(LiquidColor.tinta900.opacity(CenitOpacity.tintFill), lineWidth: 1))
                .scaleEffect(scale)
                .frame(width: 393 * scale, height: 852 * scale)

            Text(title)
                .font(LiquidType.tituloFila)
                .foregroundStyle(.primary)
        }
        .task {
            guard !seeded else { return }
            seeded = true
            if let fixture { await ScreenshotFixtures.seed(model, state: fixture) }
        }
    }
}

/// La rejilla del mapa. Envolver en un `ScrollView` para el canvas.
private struct AppMapGrid: View {
    let title: String
    let states: [(state: String?, title: String)]
    private let columns = [GridItem(.adaptive(minimum: 393 * 0.42 + LiquidSpace.s600),
                                    spacing: LiquidSpace.s700)]

    var body: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.seccionAire) {
            Text(title)
                .font(LiquidType.nivelTitulo)
                .textCase(.uppercase)
                .tracking(2)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 36) {
                ForEach(states, id: \.title) { s in
                    AppMapCell(fixture: s.state, title: s.title)
                }
            }
        }
        .padding(40)
    }
}

#Preview("Mapa · Hoy (todos los estados)") {
    ScrollView([.vertical, .horizontal]) {
        AppMapGrid(title: "Hoy · TodayView", states: AppMap.hoy)
    }
    .background(LiquidColor.tinta900)
}

/// Una celda que monta el hub de Entrenar REAL, sembrado con el fixture `train` (FER-943) — la pantalla
/// completa dentro del Canvas, con su plan, discos y la animación de entrada (FER-944). Los cierres de
/// navegación son no-ops: el preview es para mirar la portada, no para navegar.
private struct EntrenarMapCell: View {
    var locale: String = "es"
    @State private var model = AppModel()
    @State private var seeded = false

    var body: some View {
        EntrenarView(openRoutine: { _ in }, openBreathe: {}, openIntervals: {},
                     openHistory: {}, openWeeklyPlan: {}, openRoutines: {},
                     openWorkoutSession: { _ in }, openMuscleMap: {})
            .environmentObject(model.repo)
            .environment(model)
            .environmentObject(TabRouter())
            .environmentObject(HealthKitBridge(repo: model.repo,
                                               appleDeviceId: "map-apple",
                                               noopDeviceId: "map"))
            .environment(\.locale, .init(identifier: locale))
            .preferredColorScheme(.light)
            .frame(width: 393, height: 852)
            .task {
                guard !seeded else { return }
                seeded = true
                await ScreenshotFixtures.seed(model, state: "train")
            }
    }
}

// Dos previews del MISMO hub — uno en español, otro en inglés — para comprobar de un vistazo que todo
// (discos, secciones, hints) está parametrizado por idioma (FER-944).
#Preview("Entrenar · hub · Español") {
    EntrenarMapCell(locale: "es")
}

#Preview("Entrenar · hub · English") {
    EntrenarMapCell(locale: "en")
}

/// La Biblioteca de ejercicios REAL en el Canvas (FER-951): `allExercises()` devuelve el catálogo
/// empaquetado aunque no haya semilla, así que la lista se llena sola. Sin media (paper placeholder),
/// para mirar el buscador, las bandas por músculo y las miniaturas de 52px con marco de familia.
/// OJO idioma: NO forzamos `\.locale` — los strings computados (músculos, equipo) siguen el idioma
/// del proceso, así que forzar «es» mezclaba idiomas en el canvas. En el iPhone en español todo sale
/// en español; el canvas se ve consistente en el idioma del Mac.
private struct ExerciseLibraryMapCell: View {
    @State private var model = AppModel()
    @StateObject private var media = MediaDownloadCoordinator()
    /// Seed first, mount after — the screen loads its history on appear (see ExerciseDetailMapCell).
    @State private var seeded = false

    var body: some View {
        Group {
            if seeded {
                NavigationStack {
                    ExerciseLibraryScreen()
                        .environmentObject(model.repo)
                        .environmentObject(media)
                }
            } else {
                ProgressView()
            }
        }
        .preferredColorScheme(.light)
        .frame(width: 393, height: 852)
        .task {
            guard !seeded else { return }
            // `seedTrainingPlan` (no `seed(state: "train")`) — es la que guarda las SESIONES
            // (la progresión de banca) además de las rutinas; la otra solo siembra el plan.
            await ScreenshotFixtures.seedTrainingPlan(model)
            seeded = true
        }
    }
}

#Preview("Biblioteca") {
    ExerciseLibraryMapCell()
}

/// El Detalle de ejercicio REAL, sembrado con la progresión de banca del fixture `train` (FER-951):
/// 8 semanas de sesiones → la tendencia 1RM con ejes, la mini-sparkline de mejor serie, las barras
/// de volumen semanal y el Historial con chips por día + badge RÉCORD hoy. Las tres gráficas
/// responden al arrastre (scrub) dentro del canvas.
private struct ExerciseDetailMapCell: View {
    @State private var model = AppModel()
    @StateObject private var media = MediaDownloadCoordinator()
    /// The screen mounts only AFTER seeding finishes — its `.task` loads the history the moment it
    /// appears, so mounting first raced the seed and rendered the honest-empty state (FER-951).
    @State private var seeded = false

    var body: some View {
        Group {
            if !seeded {
                ProgressView()
            } else if let ex = ExerciseCatalog.all.first(where: { $0.id == "Barbell_Bench_Press_-_Medium_Grip" }) {
                NavigationStack { ExerciseDetailScreen(exercise: ex) }
            } else {
                Text(verbatim: "Bench press no está en el catálogo")
            }
        }
        .environmentObject(model.repo)
        .environmentObject(media)
        .environmentObject(TabRouter())
        .preferredColorScheme(.light)
        .frame(width: 393, height: 852)
        .task {
            guard !seeded else { return }
            // `seedTrainingPlan` (no `seed(state: "train")`) — es la que guarda las SESIONES
            // (la progresión de banca) además de las rutinas; la otra solo siembra el plan.
            await ScreenshotFixtures.seedTrainingPlan(model)
            seeded = true
        }
    }
}

#Preview("Detalle · Press banca (con datos)") {
    ExerciseDetailMapCell()
}

/// El editor de rutina REAL (Crear/Editar Rutina, FER-952), sembrado con el plan del fixture y
/// abierto en la rutina de HOY («Día A — Empuje»: banca + inclinado + laterales) — para iterar la
/// fidelidad al hand-off «Rediseño - Crear Rutina» en el canvas: header, tabla SERIE/KG/REPS,
/// superserie, chips de descanso/nota y el menú «···».
private struct RoutineEditorMapCell: View {
    @State private var model = AppModel()
    @StateObject private var media = MediaDownloadCoordinator()
    @State private var seeded = false

    var body: some View {
        Group {
            if seeded {
                NavigationStack { RoutineSheet(origin: .today(routineId: nil), mode: .editing) }
            } else {
                ProgressView()
            }
        }
        .environmentObject(model.repo)
        .environment(model)
        .environmentObject(media)
        .environmentObject(TabRouter())
        // FLUJO COMPLETO (FER-952): «Empezar» arranca la sesión de verdad
        // (`model.startStrengthSession`) y aquí se presenta la Serie activa REAL — el mismo cover que
        // RootView. Cerrar la sesión (Terminar/Descartar) regresa al editor.
        .overlay(alignment: .bottom) {
            // El pill flotante REAL (FER-716): aparece al minimizar la sesión («‹») y la re-abre.
            if model.strengthSession != nil && !model.strengthSheetPresented {
                MapSessionPillHost(model: model)
                    .padding(.bottom, LiquidSpace.s200)
                    .transition(LiquidMotion.risingFadeTransition)
            }
        }
        .animation(LiquidMotion.suave, value: model.strengthSheetPresented)
        .fullScreenCover(isPresented: $model.strengthSheetPresented, onDismiss: {
            if model.strengthSession?.summary != nil { model.closeStrengthSummary() }
        }) {
            // FER-167 (F2): La Hoja viva sustituye a `LiveStrengthSheet` como superficie montada.
            if model.strengthSession != nil {
                RoutineSheet(origin: .today(routineId: model.strengthSession?.routineId), mode: .live)
                    .environmentObject(model.repo)
                    .environment(model)
                    .environmentObject(TabRouter())
                    .environmentObject(media)
                    .preferredColorScheme(.light)
            }
        }
        .preferredColorScheme(.light)
        .frame(width: 393, height: 852)
        .task {
            guard !seeded else { return }
            await ScreenshotFixtures.seedTrainingPlan(model)
            seeded = true
        }
    }
}

#Preview("Crear Rutina · Día A (con plan)") {
    RoutineEditorMapCell()
}

/// «Tu Plan» (WeeklyPlanEditorView) — la pantalla madre del editor de rutina: la semana con su split,
/// las rutinas y las carpetas. NAVEGABLE: tocar una rutina o un día del plan empuja el editor REAL
/// (`RoutineSheet`) en el mismo stack, así que desde este preview puedes recorrer el flujo
/// completo Tu Plan → Rutina, igual que en el app.
private struct WeeklyPlanMapCell: View {
    @State private var model = AppModel()
    @StateObject private var media = MediaDownloadCoordinator()
    @State private var seeded = false
    @State private var path = NavigationPath()

    var body: some View {
        Group {
            if seeded {
                NavigationStack(path: $path) {
                    WeeklyPlanEditorView(
                        openRoutine: { path.append(RoutineEditorRoute.routine(routineId: $0)) },
                        openLibrary: {},
                        openDay: { path.append(RoutineEditorRoute.planDay(weekday: $0)) }
                    )
                    .navigationDestination(for: RoutineEditorRoute.self) { route in
                        RoutineSheet(origin: route, mode: .editing)
                    }
                }
            } else {
                ProgressView()
            }
        }
        .environmentObject(model.repo)
        .environment(model)
        .environmentObject(media)
        .environmentObject(TabRouter())
        .preferredColorScheme(.light)
        .frame(width: 393, height: 852)
        .task {
            guard !seeded else { return }
            await ScreenshotFixtures.seedTrainingPlan(model)
            seeded = true
        }
    }
}

#Preview("Tu Plan → Rutina (navegable)") {
    WeeklyPlanMapCell()
}

/// FLUJO COMPLETO de una rutina nueva (FER-952): nace en Tu Plan (＋ Nueva → biblioteca),
/// al guardar aterriza en el editor unificado («Rutina»), y su «Empezar» presenta la Serie activa
/// REAL — todo navegable dentro del canvas, con el plan demo sembrado. (MisRutinasScreen se retiró
/// en FER-962: Tu Plan es la única casa de la biblioteca.)
private struct NewRoutineFlowMapCell: View {
    @State private var model = AppModel()
    @StateObject private var media = MediaDownloadCoordinator()
    @State private var seeded = false
    @State private var path = NavigationPath()

    var body: some View {
        Group {
            if seeded {
                NavigationStack(path: $path) {
                    WeeklyPlanEditorView(
                        openRoutine: { path.append(RoutineEditorRoute.routine(routineId: $0)) },
                        openLibrary: {},
                        openDay: { path.append(RoutineEditorRoute.planDay(weekday: $0)) }
                    )
                    .navigationDestination(for: RoutineEditorRoute.self) { route in
                        RoutineSheet(origin: route, mode: .editing)
                    }
                }
            } else {
                ProgressView()
            }
        }
        .environmentObject(model.repo)
        .environment(model)
        .environmentObject(media)
        .environmentObject(TabRouter())
        .overlay(alignment: .bottom) {
            // El pill flotante REAL (FER-716): aparece al minimizar la sesión («‹») y la re-abre.
            if model.strengthSession != nil && !model.strengthSheetPresented {
                MapSessionPillHost(model: model)
                    .padding(.bottom, LiquidSpace.s200)
                    .transition(LiquidMotion.risingFadeTransition)
            }
        }
        .animation(LiquidMotion.suave, value: model.strengthSheetPresented)
        .fullScreenCover(isPresented: $model.strengthSheetPresented, onDismiss: {
            if model.strengthSession?.summary != nil { model.closeStrengthSummary() }
        }) {
            // FER-167 (F2): La Hoja viva sustituye a `LiveStrengthSheet` como superficie montada.
            if model.strengthSession != nil {
                RoutineSheet(origin: .today(routineId: model.strengthSession?.routineId), mode: .live)
                    .environmentObject(model.repo)
                    .environment(model)
                    .environmentObject(TabRouter())
                    .environmentObject(media)
                    .preferredColorScheme(.light)
            }
        }
        .preferredColorScheme(.light)
        .frame(width: 393, height: 852)
        .task {
            guard !seeded else { return }
            await ScreenshotFixtures.seedTrainingPlan(model)
            seeded = true
        }
    }
}

#Preview("Flujo · Nueva rutina → Editar → Activa") {
    NewRoutineFlowMapCell()
}

/// EL HUB CON TODOS SUS CAMINOS (FER-952): EntrenarView con el MISMO cableado que RootTabView — cada
/// disco, fila y CTA navega de verdad: Rutina de hoy / Tu Plan / Nueva rutina→Biblioteca→editor /
/// Mis entrenamientos→detalle / Respira / Intervalos / Dieta / Descanso / Otras formas / mapa de
/// músculo / tickets, y «Empezar» presenta la Serie activa. Para verificar los flujos de punta a punta.
private struct EntrenarFlowsMapCell: View {
    // FER-92 / FER-239: `dieta` retirada y la pantalla huérfana archivada.
    private enum Route: String, Hashable { case breathe, intervals, history, weeklyPlan, library }

    @State private var model = AppModel()
    @StateObject private var media = MediaDownloadCoordinator()
    @StateObject private var historyCoordinator = WorkoutHistoryCoordinator()
    @State private var seeded = false
    @State private var path = NavigationPath()

    var body: some View {
        Group {
            if seeded {
                NavigationStack(path: $path) {
                    EntrenarView(
                        openRoutine: { path.append(RoutineEditorRoute.today(routineId: $0)) },
                        openBreathe: { path.append(Route.breathe) },
                        openIntervals: { path.append(Route.intervals) },
                        openHistory: { path.append(Route.history) },
                        openWeeklyPlan: { path.append(Route.weeklyPlan) },
                        openRoutines: { path.append(Route.weeklyPlan) },
                        openWorkoutSession: { path.append($0) },
                        openMuscleMap: { path.append(MuscleVolumeRoute()) }
                    )
                    .navigationDestination(for: Route.self) { destination($0) }
                    .navigationDestination(for: RoutineEditorRoute.self) { route in
                        RoutineSheet(origin: route, mode: .editing).toolbar(.hidden, for: .navigationBar)
                    }
                    .navigationDestination(for: WorkoutSessionRoute.self) { route in
                        WorkoutSessionDetailScreen(route: route,
                            openRoutine: { path.append(RoutineEditorRoute.routine(routineId: $0)) })
                    }
                    // FER-91 · E10 fusionó el mapa muscular y el volumen en una sola pantalla.
                    .navigationDestination(for: MuscleVolumeRoute.self) { _ in TrainingBodyScreen() }
                    .navigationDestination(for: SavedTicketsRoute.self) { _ in SavedTicketsScreen() }
                }
            } else {
                ProgressView()
            }
        }
        .environmentObject(model.repo)
        .environment(model)
        .environmentObject(media)
        .environmentObject(TabRouter())
        .environmentObject(historyCoordinator)
        .environmentObject(HealthKitBridge(repo: model.repo, appleDeviceId: "map-apple", noopDeviceId: "map"))
        // FER-132 DEROGADA (FER-167 · F2): el héroe de sesión viva que cubría este estado se retiró
        // — la píldora ahora vive en TODOS los tabs, Entrenar incluido, igual que las otras celdas.
        .overlay(alignment: .bottom) {
            if model.strengthSession != nil && !model.strengthSheetPresented {
                MapSessionPillHost(model: model)
                    .padding(.bottom, LiquidSpace.s200)
                    .transition(LiquidMotion.risingFadeTransition)
            }
        }
        .animation(LiquidMotion.suave, value: model.strengthSheetPresented)
        .fullScreenCover(isPresented: $model.strengthSheetPresented, onDismiss: {
            if model.strengthSession?.summary != nil { model.closeStrengthSummary() }
        }) {
            // FER-167 (F2): La Hoja viva sustituye a `LiveStrengthSheet` como superficie montada.
            if model.strengthSession != nil {
                RoutineSheet(origin: .today(routineId: model.strengthSession?.routineId), mode: .live)
                    .environmentObject(model.repo)
                    .environment(model)
                    .environmentObject(TabRouter())
                    .environmentObject(media)
                    .preferredColorScheme(.light)
            }
        }
        .preferredColorScheme(.light)
        .frame(width: 393, height: 852)
        .task {
            guard !seeded else { return }
            await ScreenshotFixtures.seed(model, state: "train")
            await ScreenshotFixtures.seedTrainingPlan(model)
            seeded = true
        }
    }

    @ViewBuilder private func destination(_ r: Route) -> some View {
        switch r {
        case .breathe:   BreathingView()
        case .intervals: IntervalTimerView()
        // FER-90 · E9: el toque de un día del calendario navega a su detalle — mismo patrón que
        // `EntrenarView`'s `openWorkoutSession` dos líneas arriba, la única `.navigationDestination(for:
        // WorkoutSessionRoute.self)` de este mapa (línea 418).
        case .history:   WorkoutHistoryScreen(openWorkoutSession: { path.append($0) })
        case .weeklyPlan:
            WeeklyPlanEditorView(
                openRoutine: { path.append(RoutineEditorRoute.routine(routineId: $0)) },
                openLibrary: { path.append(Route.library) },
                openDay: { path.append(RoutineEditorRoute.planDay(weekday: $0)) })
        case .library:   ExerciseLibraryScreen()
        }
    }
}

#Preview("Entrenar · TODOS los flujos") {
    EntrenarFlowsMapCell()
}

/// El detalle de la SESIÓN ESTRELLA de hoy (FER-952): banca + inclinado + crunch con esfuerzo 11.2,
/// FC 132/168, 316 kcal, nota y las zonas de FC (8/22/40/25/5) vía el join con el journal — la
/// pantalla completa para verificar hero, zonas, FC, volumen y récords de una sesión real.
private struct WorkoutSessionDetailMapCell: View {
    @State private var model = AppModel()
    @StateObject private var media = MediaDownloadCoordinator()
    @StateObject private var historyCoordinator = WorkoutHistoryCoordinator()
    @State private var route: WorkoutSessionRoute? = nil

    var body: some View {
        Group {
            if let route {
                NavigationStack {
                    WorkoutSessionDetailScreen(route: route, openRoutine: { _ in })
                }
            } else {
                ProgressView()
            }
        }
        .environmentObject(model.repo)
        .environment(model)
        .environmentObject(media)
        .environmentObject(TabRouter())
        .environmentObject(historyCoordinator)
        .preferredColorScheme(.light)
        .frame(width: 393, height: 852)
        .task {
            guard route == nil else { return }
            await ScreenshotFixtures.seedTrainingPlan(model)
            if let star = await model.repo.recentSessions(limit: 1).first {
                route = WorkoutSessionRoute(id: star.id, startTs: star.startTs, endTs: star.endTs,
                                            strain: star.strain, avgHr: star.avgHr,
                                            routineName: "Día A — Empuje")
            }
        }
    }
}

#Preview("Sesión · detalle completo (con zonas)") {
    WorkoutSessionDetailMapCell()
}

/// El `SessionPill` flotante del app real (FER-716), replicado para las celdas del canvas: reloj vivo
/// por `TimelineView`, BPM en vivo si hay banda, y tocar re-abre la sesión minimizada.
private struct MapSessionPillHost: View {
    @Bindable var model: AppModel
    @State private var confirmDiscard = false
    var body: some View {
        hostBody
            // En el canvas el host es la única superficie disponible: el velo se estira él mismo a
            // pantalla con el frame del cell (393×852), suficiente para validar las esquinas.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .liquidConfirm(
                isPresented: $confirmDiscard,
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
    }
    @ViewBuilder private var hostBody: some View {
        if let session = model.strengthSession {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let total = session.runs.filter { !$0.skipped }.reduce(0) { $0 + $1.sets.count }
                // FER-167 ronda 2 (R20): misma unidad que `HojaCabeceraSesion` — «Serie N de M» / «N de N · completa».
                let isComplete = total > 0 && session.pendingCount == 0
                let detail: String? = total == 0 ? nil : (isComplete
                    ? String(localized: "\(total) of \(total) · complete")
                    : String(localized: "Set \(min(session.doneCount + 1, total)) of \(total)"))
                SessionPill(
                    routineName: session.routineName,
                    elapsed: SessionClock.format(session.elapsedSeconds(now: context.date)),
                    bpm: model.watchBpm,
                    detail: detail,
                    paused: session.paused,
                    hue: LiquidColor.ambar,
                    accessibilityLabel: Text(verbatim: session.routineName),
                    accessibilityHint: Text("Returns to the session"),
                    action: { model.resumeStrengthSession() },
                    onDiscard: { confirmDiscard = true },
                    discardAccessibilityLabel: Text("Discard session")
                )
            }
        }
    }
}
#endif
