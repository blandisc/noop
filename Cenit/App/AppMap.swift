#if DEBUG && os(iOS)
import SwiftUI
import WhoopStore
import StrandTraining
import StrandDesign

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

    @StateObject private var model = AppModel()
    @State private var seeded = false

    var body: some View {
        VStack(spacing: 10) {
            TodayView()
                .environmentObject(model.repo)
                .environmentObject(model)
                .environmentObject(TabRouter())
                .environmentObject(HealthKitBridge(repo: model.repo,
                                                   appleDeviceId: "map-apple",
                                                   noopDeviceId: "map"))
                .environment(model.live)
                .preferredColorScheme(.light)
                .frame(width: 393, height: 852)
                .clipShape(RoundedRectangle(cornerRadius: 42, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 42, style: .continuous)
                    .stroke(Color.black.opacity(0.12), lineWidth: 1))
                .scaleEffect(scale)
                .frame(width: 393 * scale, height: 852 * scale)

            Text(title)
                .font(.system(size: 13, weight: .semibold))
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
    private let columns = [GridItem(.adaptive(minimum: 393 * 0.42 + 24), spacing: 28)]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(title)
                .font(.system(size: 18, weight: .bold))
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
    .background(Color(white: 0.14))
}

/// Una celda que monta el hub de Entrenar REAL, sembrado con el fixture `train` (FER-943) — la pantalla
/// completa dentro del Canvas, con su plan, discos y la animación de entrada (FER-944). Los cierres de
/// navegación son no-ops: el preview es para mirar la portada, no para navegar.
private struct EntrenarMapCell: View {
    var locale: String = "es"
    @StateObject private var model = AppModel()
    @State private var seeded = false

    var body: some View {
        EntrenarView(openRoutine: { _ in }, openBreathe: {}, openIntervals: {}, openDiet: {},
                     openHistory: {}, openWeeklyPlan: {}, openRoutines: {}, openRestDay: {},
                     openOtherWays: {}, openWorkoutSession: { _ in })
            .environmentObject(model.repo)
            .environmentObject(model)
            .environmentObject(TabRouter())
            .environmentObject(HealthKitBridge(repo: model.repo,
                                               appleDeviceId: "map-apple",
                                               noopDeviceId: "map"))
            .environment(model.live)
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
    @StateObject private var model = AppModel()
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
    @StateObject private var model = AppModel()
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
    @StateObject private var model = AppModel()
    @StateObject private var media = MediaDownloadCoordinator()
    @State private var seeded = false

    var body: some View {
        Group {
            if seeded {
                NavigationStack { RoutineEditorScreen(origin: .today(routineId: nil)) }
            } else {
                ProgressView()
            }
        }
        .environmentObject(model.repo)
        .environmentObject(model)
        .environmentObject(media)
        .environmentObject(TabRouter())
        // FLUJO COMPLETO (FER-952): «Empezar» arranca la sesión de verdad
        // (`model.startStrengthSession`) y aquí se presenta la Serie activa REAL — el mismo cover que
        // RootView. Cerrar la sesión (Terminar/Descartar) regresa al editor.
        .overlay(alignment: .bottom) {
            // El pill flotante REAL (FER-716): aparece al minimizar la sesión («‹») y la re-abre.
            if model.strengthSession != nil && !model.strengthSheetPresented {
                MapSessionPillHost(model: model)
                    .padding(.bottom, CenitMetrics.space2)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(StrandMotion.gentle, value: model.strengthSheetPresented)
        .fullScreenCover(isPresented: $model.strengthSheetPresented, onDismiss: {
            if model.strengthSession?.summary != nil { model.closeStrengthSummary() }
        }) {
            if let session = model.strengthSession {
                LiveStrengthSheet(session: session)
                    .environmentObject(model.repo)
                    .environmentObject(model)
                    .environmentObject(TabRouter())
                    .environmentObject(media)
                    .environment(model.live)
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
/// (`RoutineEditorScreen`) en el mismo stack, así que desde este preview puedes recorrer el flujo
/// completo Tu Plan → Rutina, igual que en el app.
private struct WeeklyPlanMapCell: View {
    @StateObject private var model = AppModel()
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
                        RoutineEditorScreen(origin: route)
                    }
                }
            } else {
                ProgressView()
            }
        }
        .environmentObject(model.repo)
        .environmentObject(model)
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

/// FLUJO COMPLETO de una rutina nueva (FER-952): nace en «Mis Rutinas» (＋ Nueva rutina → builder),
/// al guardar aterriza en el editor unificado («Rutina»), y su «Empezar» presenta la Serie activa
/// REAL — todo navegable dentro del canvas, con el plan demo sembrado de fondo.
private struct NewRoutineFlowMapCell: View {
    @StateObject private var model = AppModel()
    @StateObject private var media = MediaDownloadCoordinator()
    @State private var seeded = false
    @State private var path = NavigationPath()

    var body: some View {
        Group {
            if seeded {
                NavigationStack(path: $path) {
                    MisRutinasScreen(
                        openRoutine: { path.append(RoutineEditorRoute.routine(routineId: $0)) },
                        openLibrary: {}
                    )
                    .navigationDestination(for: RoutineEditorRoute.self) { route in
                        RoutineEditorScreen(origin: route)
                    }
                }
            } else {
                ProgressView()
            }
        }
        .environmentObject(model.repo)
        .environmentObject(model)
        .environmentObject(media)
        .environmentObject(TabRouter())
        .overlay(alignment: .bottom) {
            // El pill flotante REAL (FER-716): aparece al minimizar la sesión («‹») y la re-abre.
            if model.strengthSession != nil && !model.strengthSheetPresented {
                MapSessionPillHost(model: model)
                    .padding(.bottom, CenitMetrics.space2)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(StrandMotion.gentle, value: model.strengthSheetPresented)
        .fullScreenCover(isPresented: $model.strengthSheetPresented, onDismiss: {
            if model.strengthSession?.summary != nil { model.closeStrengthSummary() }
        }) {
            if let session = model.strengthSession {
                LiveStrengthSheet(session: session)
                    .environmentObject(model.repo)
                    .environmentObject(model)
                    .environmentObject(TabRouter())
                    .environmentObject(media)
                    .environment(model.live)
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
    private enum Route: String, Hashable { case breathe, intervals, dieta, history, weeklyPlan, restDay, otherWays, library }

    @StateObject private var model = AppModel()
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
                        openDiet: { path.append(Route.dieta) },
                        openHistory: { path.append(Route.history) },
                        openWeeklyPlan: { path.append(Route.weeklyPlan) },
                        openRoutines: { path.append(Route.weeklyPlan) },
                        openRestDay: { path.append(Route.restDay) },
                        openOtherWays: { path.append(Route.otherWays) },
                        openWorkoutSession: { path.append($0) }
                    )
                    .navigationDestination(for: Route.self) { destination($0) }
                    .navigationDestination(for: RoutineEditorRoute.self) { route in
                        RoutineEditorScreen(origin: route).toolbar(.hidden, for: .navigationBar)
                    }
                    .navigationDestination(for: WorkoutSessionRoute.self) { route in
                        WorkoutSessionDetailScreen(route: route,
                            openRoutine: { path.append(RoutineEditorRoute.routine(routineId: $0)) })
                    }
                    .navigationDestination(for: MuscleVolumeRoute.self) { _ in MuscleVolumeScreen() }
                    .navigationDestination(for: SavedTicketsRoute.self) { _ in SavedTicketsScreen() }
                }
            } else {
                ProgressView()
            }
        }
        .environmentObject(model.repo)
        .environmentObject(model)
        .environmentObject(media)
        .environmentObject(TabRouter())
        .environmentObject(historyCoordinator)
        .environmentObject(HealthKitBridge(repo: model.repo, appleDeviceId: "map-apple", noopDeviceId: "map"))
        .environment(model.live)
        .overlay(alignment: .bottom) {
            // El pill flotante REAL (FER-716): aparece al minimizar la sesión («‹») y la re-abre.
            if model.strengthSession != nil && !model.strengthSheetPresented {
                MapSessionPillHost(model: model)
                    .padding(.bottom, CenitMetrics.space2)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(StrandMotion.gentle, value: model.strengthSheetPresented)
        .fullScreenCover(isPresented: $model.strengthSheetPresented, onDismiss: {
            if model.strengthSession?.summary != nil { model.closeStrengthSummary() }
        }) {
            if let session = model.strengthSession {
                LiveStrengthSheet(session: session)
                    .environmentObject(model.repo)
                    .environmentObject(model)
                    .environmentObject(TabRouter())
                    .environmentObject(media)
                    .environment(model.live)
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
        case .dieta:     DietCaptureView()
        case .history:   WorkoutHistoryScreen()
        case .weeklyPlan:
            WeeklyPlanEditorView(
                openRoutine: { path.append(RoutineEditorRoute.routine(routineId: $0)) },
                openLibrary: { path.append(Route.library) },
                openDay: { path.append(RoutineEditorRoute.planDay(weekday: $0)) })
        case .restDay:
            RestDayScreen(openIntervals: { path.append(Route.intervals) },
                          openBreathe: { path.append(Route.breathe) },
                          openRoutines: { path.append(Route.weeklyPlan) })
        case .otherWays:
            OtherWaysScreen(openIntervals: { path.append(Route.intervals) },
                            openBreathe: { path.append(Route.breathe) })
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
    @StateObject private var model = AppModel()
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
        .environmentObject(model)
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
    @ObservedObject var model: AppModel
    var body: some View {
        if let session = model.strengthSession {
            let theme = InstrumentoTheme.base
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let total = session.runs.filter { !$0.skipped }.reduce(0) { $0 + $1.sets.count }
                SessionPill(
                    routineName: session.routineName,
                    elapsed: SessionClock.format(session.elapsedSeconds(now: context.date)),
                    bpm: model.bpm,
                    detail: total > 0 ? String(localized: "set \(min(session.doneCount + 1, total))/\(total)") : nil,
                    paused: session.paused,
                    hue: theme.dataStrain,
                    theme: theme,
                    accessibilityLabel: Text(verbatim: session.routineName),
                    accessibilityHint: Text("Returns to the session"),
                    action: { model.resumeStrengthSession() },
                    onPlayPause: {
                        if session.paused { model.resumeStrengthSessionFromPause() }
                        else { model.pauseStrengthSession() }
                    }
                )
            }
        }
    }
}
#endif
