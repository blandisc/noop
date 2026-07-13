#if DEBUG && os(iOS)
import SwiftUI
import WhoopStore

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
#endif
