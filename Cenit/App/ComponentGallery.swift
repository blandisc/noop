#if os(iOS) && DEBUG
import SwiftUI
import CenitDesign

/// **Galería de componentes** — catálogo vivo de las piezas de `CenitDesign` (FER-315), hermano del
/// `AppMap` de pantallas. Cada entrada renderiza UNA pieza del sistema **Liquid Glass · El Eje** sobre
/// el lienzo casi-blanco canónico (`LiquidColor.fondoGradient`), con un uso representativo tomado de su
/// propio `#Preview` — el código gana, esto solo lo expone.
///
/// Se alcanza por launch-arg `-noop.component <Nombre>` (igual disciplina que los fixtures de pantalla):
/// `ContentView` monta `ComponentGalleryHost(name:)` a pantalla completa cuando el arg está presente, y
/// `CenitScreenshotTests.test_components()` recorre `ComponentGallery.names` para capturar un PNG por
/// pieza hacia el muro `docs/appmap/` (grupo «Componentes» de `Tools/build-appmap.py`).
///
/// Mantener: al añadir/renombrar una pieza del núcleo, edita `entries`. La lista de nombres vive en el
/// código (no en el test) para que una pieza nueva entre a la captura sin tocar el harness.
enum ComponentGallery {

    /// Una pieza del catálogo: nombre canónico (== símbolo de CenitDesign), familia para agrupar en el
    /// muro, y el `View` de muestra (uso representativo, sin fondo — el host pinta el lienzo).
    struct Entry: Identifiable {
        let name: String
        let family: String
        let make: () -> AnyView
        var id: String { name }
    }

    /// El núcleo (~30 piezas del sistema NUEVO, Liquid Glass · El Eje). Corte transversal por familia.
    /// Las piezas de la era «Instrumento» (legacy en migración) quedan fuera a propósito.
    static let entries: [Entry] = [

        // MARK: Botones
        Entry(name: "LiquidGlassButton", family: "Botones") {
            AnyView(VStack(spacing: LiquidSpace.s300) {
                LiquidGlassButton("Empezar", variant: .primary, minWidth: 168) {}
                LiquidGlassButton("Ver detalle", variant: .glass) {}
                LiquidGlassButton("Crear ejercicio", variant: .solida) {}
                LiquidGlassButton("Editar semana", variant: .quiet) {}
                LiquidGlassButton("Turn off automatic backup", variant: .destructive, expands: true) {}
            })
        },

        // MARK: Tiles / datos
        Entry(name: "LiquidMetricTile", family: "Tiles") {
            AnyView(LazyVGrid(columns: [GridItem(.flexible(), spacing: LiquidSpace.s200), GridItem(.flexible())],
                              spacing: LiquidSpace.s200) {
                LiquidMetricTile(label: "SUEÑO", value: "7:20", delta: "En tu base",
                                 tone: LiquidColor.indigo, icon: .luna)
                LiquidMetricTile(label: "HRV", value: "56", unit: "ms", delta: "+2 ms vs tu base",
                                 deltaTone: .up, tone: LiquidColor.cian, icon: .onda)
                LiquidMetricTile(label: "FC EN REPOSO", value: "52", unit: "lpm", delta: "En tu base",
                                 tone: LiquidColor.rosa, icon: .corazon)
                LiquidMetricTile(label: "ESFUERZO", value: "10.0", delta: "−0.7 vs tu base",
                                 deltaTone: .down, tone: LiquidColor.ambar, icon: .llama, action: {})
            })
        },

        // MARK: Chips
        Entry(name: "LiquidChipSeleccion", family: "Chips") {
            AnyView(LiquidFlujoLeyenda(espacioH: LiquidSpace.s150, espacioV: LiquidSpace.s150) {
                LiquidChipSeleccion(nombre: "VFC", tono: LiquidColor.cian, a11yQuitar: "Quitar VFC") {}
                LiquidChipSeleccion(nombre: "Esfuerzo", tono: LiquidColor.ambar, a11yQuitar: "Quitar Esfuerzo") {}
                LiquidChipSeleccion(nombre: "Sueño", tono: LiquidColor.indigo, a11yQuitar: "Quitar Sueño") {}
                LiquidChipSeleccion(nombre: "FC en reposo", tono: LiquidColor.rosa, a11yQuitar: "Quitar FC en reposo") {}
            })
        },
    ]

    /// Nombres en orden de catálogo — lo que recorre el harness de captura.
    static var names: [String] { entries.map(\.name) }

    static func entry(named name: String) -> Entry? { entries.first { $0.name == name } }
}

/// Monta UNA pieza del catálogo a pantalla completa sobre el lienzo Liquid, centrada, con aire.
/// `ContentView` la usa cuando el launch-arg `-noop.component` está presente.
struct ComponentGalleryHost: View {
    let name: String

    var body: some View {
        ZStack {
            LiquidColor.fondoGradient.ignoresSafeArea()
            if let entry = ComponentGallery.entry(named: name) {
                entry.make()
                    .padding(LiquidSpace.s550)
                    .frame(maxWidth: 402)
            } else {
                // Pieza no registrada: lo decimos fuerte (un PNG en blanco sería un falso verde).
                Text(verbatim: "¿componente no registrado?: \(name)")
                    .font(LiquidType.tituloFila)
                    .foregroundStyle(LiquidColor.rosa)
                    .padding(LiquidSpace.s550)
            }
        }
        .accessibilityIdentifier("component-gallery-\(name)")
    }
}

/// Lee el launch-arg `-noop.component <Nombre>` (poblado en `UserDefaults` por el harness).
/// `nil` en un arranque normal → la galería no aparece nunca fuera de la captura DEBUG.
enum ComponentGalleryLaunch {
    static var requestedName: String? {
        guard let n = UserDefaults.standard.string(forKey: "noop.component"), !n.isEmpty else { return nil }
        return n
    }
}
#endif
