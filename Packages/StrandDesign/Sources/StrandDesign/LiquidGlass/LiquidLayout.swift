import SwiftUI

// MARK: - Liquid Glass · Espaciado (handoff §4.3)
//
// Escala cerrada, base 4 con medios pasos. Un espaciado nuevo es un cambio al sistema,
// no una decisión de pantalla.

public enum LiquidSpace {
    /// 1 — micro-gap: rótulo ↔ dato dentro de una columna, respiro superior del bullet de
    /// carga. Paso fino de la escala (FER-31): existe porque la superficie lo pedía crudo.
    public static let s025: CGFloat = 1
    /// 2 — gaps de segmentos de barra.
    public static let s050: CGFloat = 2
    /// 3 — respiro EXTERIOR de la pastilla táctil (extiende el área a ≥44 sin engordar el
    /// vidrio) y micro-padding vertical. Paso fino (FER-31).
    public static let s075: CGFloat = 3
    /// 4.
    public static let s100: CGFloat = 4
    /// 5 — gap rótulo ↔ ratio / diámetro y separación de los puntos de progreso. Paso fino (FER-31).
    public static let s125: CGFloat = 5
    /// 6 — gota ↔ label.
    public static let s150: CGFloat = 6
    /// 8 — gap del grid de tiles.
    public static let s200: CGFloat = 8
    /// 9 — padding vertical INTERIOR de la pastilla táctil (carga/guardián/fila del ecosistema):
    /// el vidrio respira sin crecer y el toque llega a 44 con `s075` afuera. Paso fino (FER-31).
    public static let s225: CGFloat = 9
    /// 10 — medio paso: gap entre módulos de «El Tablero» y su padding vertical interior (FER-28).
    public static let s250: CGFloat = 10
    /// 12 — padding H de tile, separación entre bloques chicos.
    public static let s300: CGFloat = 12
    /// 16 — padding H de pastilla / interior horizontal de módulo.
    public static let s400: CGFloat = 16
    /// 22 — margen horizontal de pantalla (legacy Liquid).
    public static let s550: CGFloat = 22
    /// 24 — margen horizontal de la pantalla «El Tablero» (FER-28): un punto más de aire
    /// lateral que el resto, para que los módulos de vidrio no rocen el bisel.
    public static let s600: CGFloat = 24
    /// 32.
    public static let s800: CGFloat = 32
    /// 56 — safe-area top (velo de status).
    public static let s1400: CGFloat = 56

    /// 324 — alto de la zona del héroe «El Ecosistema» (FER-10): el lienzo de las esferas
    /// de partículas + la palabra del veredicto. Sustituye a `senalesAlto` (140), que
    /// murió con la fila de orbes y sus cables.
    public static let ecosistemaAlto: CGFloat = 324
    /// La compresión COMPACTA del héroe para «El Tablero» (FER-28), en dos recortes que NO
    /// tocan el arte ni el shader —solo la presentación—:
    ///   · `ecosistemaRecorteTop` sube el lienzo recortando el aire SUPERIOR (el estado
    ///     separado sigue librando la cabecera: sus etiquetas viven en y≈74, verificado);
    ///   · `ecosistemaAcercaVeredicto` jala el veredicto + la puerta HACIA el orbe, recortando
    ///     el aire de ABAJO — que es exactamente lo que el mockup aprobado ya muestra.
    /// El alto reservado compacto = `ecosistemaAlto − recorteTop − acercaVeredicto`.
    public static let ecosistemaRecorteTop: CGFloat = 42
    public static let ecosistemaAcercaVeredicto: CGFloat = 40
    /// Alto RESERVADO del héroe compacto: se fija directo (con `.frame(alignment: .top)`) para
    /// que el box ABRACE al contenido —orbe + veredicto + subtítulo + pastilla— sin espacio
    /// muerto abajo. Derivarlo de los recortes dejaba ~62 pt de aire reservado bajo la pastilla
    /// (el frame centrado); este valor + anclaje arriba lo eliminan y suben el módulo 1 pegado.
    public static let ecosistemaAltoCompacto: CGFloat = 250

    /// Margen inferior del dock flotante. Negativo entra al área segura para pegarlo
    /// más al borde (pedido del dueño /inject: a 8 y a 0 seguía flotando muy arriba).
    public static let dockBottom: CGFloat = -22
    /// Margen lateral del dock flotante (absolute left/right 16 en el handoff).
    public static let dockSide: CGFloat = 16
}

// MARK: - Liquid Glass · Radios (handoff §4.4 — cinco tokens, ninguno más)

public enum LiquidRadius {
    /// 0.5 — hairline: el redondeo mínimo de un trazo de 1 pt (el capilar divisor) para que no
    /// se lea como un pixel cuadrado. No es un radio de layout — es antialiasing de trazo (FER-31).
    public static let hairline: CGFloat = 0.5
    /// 12 — swatches, chips de día, inputs.
    public static let control: CGFloat = 12
    /// 18 — tiles, tarjetas, contenedores de lista.
    public static let tarjeta: CGFloat = 18
    /// 20 — módulos de vidrio de «El Tablero» (FER-28): un punto más que el tile para que la
    /// aurora fina del filo tenga curva donde correr.
    public static let modulo: CGFloat = 20
    /// 28 — sheets y modales (reservado).
    public static let hoja: CGFloat = 28
    /// 999 — botones, dock, barras, badges (en SwiftUI: `Capsule`).
    public static let pastilla: CGFloat = 999
    // r/orbe = 50 % → en SwiftUI es `Circle`; no necesita constante.
}

// MARK: - Liquid Glass · Tamaños de control (eje de tokenización: sm/md/lg + hit target)

/// Alturas de control por tamaño y el objetivo táctil mínimo. Ningún elemento tocable inventa
/// su alto: usa `hitTarget` como piso (HIG 44 pt) o una de las tallas.
public enum LiquidControl {
    /// Objetivo táctil mínimo (HIG): 44 pt. El piso de toda columna/fila/botón tocable.
    public static let hitTarget: CGFloat = 44
    /// `sm` — chips, filas densas.
    public static let sm: CGFloat = 32
    /// `md` — el control por defecto (== hit target).
    public static let md: CGFloat = 44
    /// `lg` — CTAs, controles destacados.
    public static let lg: CGFloat = 56
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

    /// `e/dial` — el sello del dial 24 h es PLANO, no lente (excepción consciente): una sola
    /// sombra de contacto suave, deliberadamente más ligera que `e3`. Nivel nombrado (FER-31)
    /// para que el `LiquidDialSeal` no lleve un arreglo de sombra ad-hoc inline.
    public static let dial: [LiquidShadowLayer] = [
        .init(color: tintaSombra.opacity(0.08), radius: 5, y: 3)
    ]

    /// `e/módulo` — la sombra de dos capas de un módulo de «El Tablero» (FER-28), por índice
    /// de profundidad: contacto corto (tinta 5 %, radius 3, y 2) + ambiente que se alarga
    /// conforme el módulo baja en la pila (tinta 7 %, radius 14, y 9 + índice × 1.5). El
    /// radius ya viene convertido del blur CSS (≈ 2×): 6/28 px → 3/14 pt.
    public static func modulo(index: Int) -> [LiquidShadowLayer] {
        [
            .init(color: tintaSombra.opacity(0.05), radius: 3, y: 2),
            .init(color: tintaSombra.opacity(0.07), radius: 14, y: 9 + CGFloat(index) * 1.5),
        ]
    }
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
