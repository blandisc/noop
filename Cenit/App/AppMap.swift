#if DEBUG && os(iOS)
import SwiftUI
import WhoopStore
import StrandTraining

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

    var body: some View {
        NavigationStack {
            ExerciseLibraryScreen()
                .environmentObject(model.repo)
                .environmentObject(media)
        }
        .preferredColorScheme(.light)
        .frame(width: 393, height: 852)
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
    @State private var seeded = false

    var body: some View {
        Group {
            if let ex = ExerciseCatalog.all.first(where: { $0.id == "Barbell_Bench_Press_-_Medium_Grip" }) {
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
            seeded = true
            await ScreenshotFixtures.seed(model, state: "train")
        }
    }
}

#Preview("Detalle · Press banca (con datos)") {
    ExerciseDetailMapCell()
}
#endif
