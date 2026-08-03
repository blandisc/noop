import SwiftUI

// MARK: - Liquid Glass · Espaciado (handoff §4.3)
//
// Escala cerrada, base 4 con medios pasos. Un espaciado nuevo es un cambio al sistema,
// no una decisión de pantalla.

public enum LiquidSpace {
    /// 2 — gaps de segmentos de barra.
    public static let s050: CGFloat = 2
    /// 4.
    public static let s100: CGFloat = 4
    /// 6 — gota ↔ label.
    public static let s150: CGFloat = 6
    /// 8 — gap del grid de tiles.
    public static let s200: CGFloat = 8
    /// 12 — padding H de tile, separación entre bloques chicos.
    public static let s300: CGFloat = 12
    /// 16 — padding H de pastilla.
    public static let s400: CGFloat = 16
    /// 22 — margen horizontal de pantalla.
    public static let s550: CGFloat = 22
    /// 32.
    public static let s800: CGFloat = 32
    /// 56 — safe-area top (velo de status).
    public static let s1400: CGFloat = 56

    /// 324 — alto de la zona del héroe «El Ecosistema» (FER-10): el lienzo de las esferas
    /// de partículas + la palabra del veredicto. Sustituye a `senalesAlto` (140), que
    /// murió con la fila de orbes y sus cables.
    public static let ecosistemaAlto: CGFloat = 324

    /// Margen inferior del dock flotante. Negativo entra al área segura para pegarlo
    /// más al borde (pedido del dueño /inject: a 8 y a 0 seguía flotando muy arriba).
    public static let dockBottom: CGFloat = -22
    /// Margen lateral del dock flotante (absolute left/right 16 en el handoff).
    public static let dockSide: CGFloat = 16
}

// MARK: - Liquid Glass · Radios (handoff §4.4 — cinco tokens, ninguno más)

public enum LiquidRadius {
    /// 12 — swatches, chips de día, inputs.
    public static let control: CGFloat = 12
    /// 18 — tiles, tarjetas, contenedores de lista.
    public static let tarjeta: CGFloat = 18
    /// 28 — sheets y modales (reservado).
    public static let hoja: CGFloat = 28
    /// 999 — botones, dock, barras, badges (en SwiftUI: `Capsule`).
    public static let pastilla: CGFloat = 999
    // r/orbe = 50 % → en SwiftUI es `Circle`; no necesita constante.
}

// MARK: - Liquid Glass · Elevación (handoff §4.6)
//
// Cuatro niveles de sombra. El blur CSS ≈ 2× el radius de SwiftUI, por eso cada spec
// trae el radius ya convertido. `e/2 señal` tiñe su primera capa con el tono del dato.

/// Una capa de sombra (SwiftUI la aplica con `.shadow`).
public struct LiquidShadowLayer: Sendable {
    public let color: Color
    public let radius: CGFloat
    public let y: CGFloat

    public init(color: Color, radius: CGFloat, y: CGFloat) {
        self.color = color
        self.radius = radius
        self.y = y
    }
}

public enum LiquidElevation {
    /// Tinta base de las sombras (tinta/900 en distintos alfas).
    private static let tintaSombra = Color(hex: "#221D16")

    /// `e/0 reposo` — 0 2px 8px tinta al 5 %. Tiles en reposo.
    public static let e0: [LiquidShadowLayer] = [
        .init(color: tintaSombra.opacity(0.05), radius: 4, y: 2)
    ]

    /// `e/1 tarjeta` — 0 5px 14px tinta al 6 %. Pastillas, tarjetas destacadas.
    public static let e1: [LiquidShadowLayer] = [
        .init(color: tintaSombra.opacity(0.06), radius: 7, y: 5)
    ]

    /// `e/2 señal` — glow del tono del dato + apoyo neutro. Orbes, hover-lift.
    public static func e2(tone: Color) -> [LiquidShadowLayer] {
        [
            .init(color: tone.opacity(0.18), radius: 12, y: 10),
            .init(color: tintaSombra.opacity(0.06), radius: 3, y: 2),
        ]
    }

    /// `e/3 flotante` — dock, dial, flotantes.
    public static let e3: [LiquidShadowLayer] = [
        .init(color: tintaSombra.opacity(0.16), radius: 16, y: 12),
        .init(color: tintaSombra.opacity(0.08), radius: 3, y: 2),
    ]
}

public extension View {
    /// Aplica una elevación del sistema (una o dos capas de sombra). Ninguna pantalla
    /// escribe `.shadow` a mano: o usa esto, o usa una receta de vidrio que ya lo trae.
    func liquidShadow(_ layers: [LiquidShadowLayer]) -> some View {
        modifier(LiquidShadowModifier(layers: layers))
    }
}

private struct LiquidShadowModifier: ViewModifier {
    let layers: [LiquidShadowLayer]

    func body(content: Content) -> some View {
        layers.reduce(AnyView(content)) { view, layer in
            AnyView(view.shadow(color: layer.color, radius: layer.radius, x: 0, y: layer.y))
        }
    }
}

public extension View {
    /// Elevación dibujada como GEOMETRÍA: la silueta de `shape`, difuminada, DETRÁS de la
    /// vista. Obligatoria cuando la vista contiene material del sistema — `.shadow` sobre
    /// material proyecta el RECTÁNGULO de su capa de fondo (y `compositingGroup` no lo
    /// salva, porque el backdrop no se deja aplanar). Una silueta difuminada no puede
    /// volverse rectángulo, por construcción.
    func liquidShadow<S: Shape>(_ layers: [LiquidShadowLayer], silhouette shape: S) -> some View {
        background {
            ZStack {
                ForEach(Array(layers.enumerated()), id: \.offset) { _, layer in
                    shape
                        .fill(layer.color)
                        .blur(radius: layer.radius)
                        .offset(y: layer.y)
                }
            }
            .allowsHitTesting(false)
        }
    }
}
