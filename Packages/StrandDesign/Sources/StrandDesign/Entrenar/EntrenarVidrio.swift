import SwiftUI

// MARK: - Entrenar · vidrio del hub v18 (FER-171 · Parte A)
//
// La receta ÚNICA de vidrio del hub «La Principal» (mock `eje-hub-v18.html`), parametrizada por
// tono: cada módulo/tile del hub tiñe su vidrio con la identidad de color de su dato (índigo del
// héroe, cian de la dosis, rosa de marcas, ámbar de volumen, verde de subidas) sobre el mismo
// fondo casi blanco de «El Tablero». Reusa el patrón de refracción/filos/sombra de `LiquidModulo`
// (backdrop saturado 1.28×, highlight blanco superior, canto exterior, sombra de dos capas) — no
// lo reinventa, solo lo hace tomar un tono además de un índice de profundidad.
//
// `EntrenarModulo` y `EntrenarTile` son la MISMA receta (`EntrenarVidrioReceta`); lo único que
// cambia entre los dos contenedores es el padding y el `minHeight` (el mock lo confirma: la
// variante neutra de tile, `.tDes`, usa exactamente el mismo `box-shadow`/fondo que el módulo
// neutro `.mod`, y las tres variantes teñidas de tile comparten `box-shadow` con el módulo
// teñido `.dos`).

/// El tono de vidrio de un módulo/tile de Entrenar — la identidad de color de la sección que lo
/// contiene. Deliberadamente distinto de `EntrenarFamily` (push/pull/legs/fullBody, la familia de
/// una RUTINA): `EntrenarTono` es la paleta del HUB, no de una rutina — «Marcas» siempre es rosa,
/// «Volumen» siempre ámbar, sin importar qué se entrenó ese día.
public enum EntrenarTono: Sendable, Equatable, CaseIterable {
    case neutro, indigo, cian, verde, rosa, ambar

    /// El color base del tono: `neutro` es blanco (el vidrio no tiñe); el resto son los MISMOS
    /// hex 1:1 que ya usa el resto del sistema vía `LiquidColor` — ninguno se redefine aquí.
    public var base: Color {
        switch self {
        case .neutro: return .white
        case .indigo: return LiquidColor.indigo
        case .cian:   return LiquidColor.cian
        case .verde:  return LiquidColor.verdePrimario
        case .rosa:   return LiquidColor.rosa
        case .ambar:  return LiquidColor.ambar
        }
    }

    /// El color del rótulo (REGLA) sobre el vidrio teñido de SU PROPIO tono — oscurecido para AA
    /// (mock v18, auditado ahí, no recalculado con `LiquidColor.tonoCampo` porque el campo aquí
    /// es vidrio translúcido, no un relleno opaco). `indigo`/`cian`/`verde`/`rosa` son la ÚNICA
    /// familia de hex nuevos de este archivo — declarados una sola vez, aquí. `ambar` reusa
    /// `LiquidColor.atencionTexto` (ya es el mismo ámbar AA que pide el mock) y `neutro` reusa
    /// `LiquidColor.tinta500` — ninguno de los dos es un hex nuevo.
    public var rotulo: Color {
        switch self {
        case .neutro: return LiquidColor.tinta500
        case .indigo: return Color(hex: "#514E86")
        case .cian:   return Color(hex: "#136A78")
        case .verde:  return Color(hex: "#0A6B4A")
        case .rosa:   return Color(hex: "#93445A")
        case .ambar:  return LiquidColor.atencionTexto
        }
    }

    /// El color de una TESELA (celda de día, `EntrenarSemana` en la Parte B) que lleva texto
    /// claro encima. `indigo`/`cian`/`verde`/`rosa` sostienen AA con blanco en su propio `base` —
    /// la tesela es la misma. `ambar` NO: `base` (#C4631F) se queda corto contra texto claro, así
    /// que usa este oscurecido dedicado (mock v18 `.d-a{background:#A0500F}`, auditado en v15 —
    /// el quinto y último hex nuevo del archivo). `neutro` no aparece como tesela en el mock (no
    /// hay «día sin familia» pintado); resuelve a `base` para no dejar el `switch` sin caso.
    public var tesela: Color {
        switch self {
        case .ambar: return Color(hex: "#A0500F")
        default:     return base
        }
    }
}

/// El puente familia→tono del hub v18 (FER-171 · Parte B): qué `EntrenarTono` tiñe el HÉROE (que
/// tiñe por la familia de la rutina del día) y las TESELAS de semana / celdas de constancia (que
/// tiñen por la familia de cada sesión) — los tres únicos lugares del hub donde la identidad de
/// color viene de una FAMILIA en vez del rol fijo del módulo (Marcas siempre rosa, Volumen siempre
/// ámbar, con o sin importar qué se entrenó). Mapeo 1:1 con `EntrenarFamily.tint` (push → ember,
/// pull → teal, legs/fullBody → índigo) para que un mismo día lea el mismo color en el héroe, la
/// tesela y la celda — una sola tabla, no una por consumidor.
public extension EntrenarFamily {
    var tono: EntrenarTono {
        switch self {
        case .push:             return .ambar
        case .pull:             return .cian
        case .legs, .fullBody:  return .indigo
        }
    }
}

/// Las constantes con nombre de la receta — nada suelto en `EntrenarVidrioReceta`. Cada valor
/// cita su origen exacto en el mock `eje-hub-v18.html` para que un cambio de diseño futuro sepa
/// qué línea de CSS está tocando. `public`: `moduloInsets` es el default-argument de un `init`
/// público (Swift exige que el default sea al menos tan visible como el `init`), y el resto viaja
/// con ella por consistencia — mismo criterio que `EntrenarMetrics`/`LiquidSpace`/`LiquidRadius`.
public enum EntrenarVidrioMetrics {
    /// Padding por defecto de `EntrenarModulo`: v11/h18, el valor que más se repite en el mock
    /// (`sem`/`dos`/`cuerpo`/`mesFull`/`hist` — todos `padding:11px 18px …`). El héroe (v16) pasa
    /// su propio `insets`.
    public static let moduloInsets = EdgeInsets(top: 11, leading: 18, bottom: 11, trailing: 18)
    /// Padding fijo de `EntrenarTile` (mock `.tile{padding:12px 18px}`).
    public static let tileInsets = EdgeInsets(top: 12, leading: 18, bottom: 12, trailing: 18)
    /// Alto mínimo del tile del grid 2-col (mock `.tile{min-height:104px}`).
    public static let tileMinHeight: CGFloat = 104

    /// Fondo neutro — blanco al 50 % (mock `.mod{background:rgba(255,255,255,.50)}`; `.tDes`, el
    /// ÚNICO tile neutro del mock, usa exactamente el mismo valor).
    public static let rellenoNeutroAlfa: Double = 0.50
    /// Fondo teñido por defecto — 0.10 uniforme (mock: la mayoría de módulos/tiles teñidos caen
    /// en 0.09–0.10). El héroe índigo pide 0.11 vía el parámetro `intensidad` de `EntrenarModulo`.
    public static let intensidadDefault: Double = 0.10

    /// Highlight superior — aproximación de `inset 0 1px 0 rgba(255,255,255,X)` como
    /// `strokeBorder` completo (mismo patrón que `LiquidColor.vidrioBordeSuperficie` en
    /// `LiquidModulo`: SwiftUI no tiene sombra-inset de un solo filo). Neutro .70, teñido .75
    /// (mock: `.mod` inset .7 vs `.hero`/`.dos`/tiles teñidos inset .75).
    public static let highlightNeutro = Color.white.opacity(0.70)
    public static let highlightTeñido = Color.white.opacity(0.75)
    /// Segundo aro, SOLO en la variante teñida (mock `inset 0 0 0 1px rgba(255,255,255,.35)` en
    /// `.hero`/`.dos`/`.tMar`/`.tVol`/`.tSub`; el vidrio neutro `.mod`/`.tDes` no lo trae).
    public static let aroTeñido = Color.white.opacity(0.35)

    /// Canto exterior teñido — 30 % del tono (mock `0 0 0 .5px rgba(tono,.30)`, redondeado desde
    /// el rango real .28–.30). El canto neutro reusa `LiquidColor.vidrioCanto` directamente: es
    /// LITERALMENTE `rgba(34,29,22,.08)`, el mismo `--canto` del mock.
    public static let cantoAlfaTeñido: Double = 0.30

    /// Sombra de contacto — misma geometría en ambas variantes (mock `0 2px 3px`: el radius de
    /// SwiftUI es el blur CSS ÷ 2, igual convención que `LiquidElevation`), solo cambia el alfa.
    public static let contactoY: CGFloat = 2
    public static let contactoRadius: CGFloat = 1.5
    public static let contactoAlfaNeutro: Double = 0.06
    public static let contactoAlfaTeñido: Double = 0.04

    /// Sombra ambiente — neutro (mock `.mod`/`.tDes`: `0 7px 14px rgba(tinta,.07)`) vs teñido
    /// (mock `.dos`/`.tMar`/`.tVol`/`.tSub`: `0 10px 20px`, alfa real .13–.14 → .14 canónico). El
    /// héroe sube a `0 12px 24px @ .15` en el mock — GAP documentado en el reporte del agente: la
    /// receta comparte un solo nivel «teñido» por los dos contenedores (según contrato §3c), así
    /// que ese realce extra específico del héroe no se reproduce aquí.
    public static let ambienteYNeutro: CGFloat = 7
    public static let ambienteRadiusNeutro: CGFloat = 7
    public static let ambienteAlfaNeutro: Double = 0.10
    public static let ambienteYTeñido: CGFloat = 10
    public static let ambienteRadiusTeñido: CGFloat = 10
    public static let ambienteAlfaTeñido: Double = 0.14
}

/// La receta compartida, aplicada como `ViewModifier` — `EntrenarModulo`/`EntrenarTile` solo le
/// dan padding/tamaño distintos (ver cabecera del archivo).
private struct EntrenarVidrioReceta: ViewModifier {
    let tono: EntrenarTono
    let intensidad: Double

    @Environment(\.liquidMotionDisabled) private var motionDisabled

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: CenitMetrics.tileRadius, style: .continuous)
    }

    func body(content: Content) -> some View {
        content
            .background { fondo }
            .overlay { shape.strokeBorder(highlight, lineWidth: 1) }
            .overlay {
                if tono != .neutro {
                    shape.strokeBorder(EntrenarVidrioMetrics.aroTeñido, lineWidth: 1)
                }
            }
            .overlay { shape.stroke(canto, lineWidth: 0.5) }
            .liquidShadow(sombrasTarjeta, silhouette: shape)
    }

    /// La sombra del tile/módulo: el tono neutro usa el token ÚNICO compartido (`LiquidElevation.tarjeta`),
    /// el mismo que las tarjetas de Tendencias — así el espacio entre tarjetas se lee igual en toda la
    /// app. Los tonos teñidos conservan su sombra del color de su propio dato (contacto + ambiente).
    private var sombrasTarjeta: [LiquidShadowLayer] {
        tono == .neutro ? LiquidElevation.tarjeta : [contacto, ambiente]
    }

    /// Mismo patrón que `LiquidModulo.glass`: vidrio nativo en iOS 26, material + backdrop
    /// saturado 1.28× (`LiquidColor.vidrioRefraccion`) antes de eso.
    @ViewBuilder
    private var fondo: some View {
        if #available(iOS 26.0, macOS 26.0, watchOS 26.0, *), !motionDisabled {
            Color.clear
                .background { shape.fill(relleno) }
                .glassEffect(.regular, in: shape)
        } else {
            ZStack {
                shape.fill(.ultraThinMaterial).saturation(LiquidColor.vidrioRefraccion)
                shape.fill(relleno)
            }
        }
    }

    private var relleno: Color {
        tono == .neutro ? Color.white.opacity(EntrenarVidrioMetrics.rellenoNeutroAlfa)
                         : tono.base.opacity(intensidad)
    }

    private var highlight: Color {
        tono == .neutro ? EntrenarVidrioMetrics.highlightNeutro : EntrenarVidrioMetrics.highlightTeñido
    }

    private var canto: Color {
        tono == .neutro ? LiquidColor.tinta900.opacity(0.16) : tono.base.opacity(EntrenarVidrioMetrics.cantoAlfaTeñido)
    }

    private var contacto: LiquidShadowLayer {
        let alfa = tono == .neutro ? EntrenarVidrioMetrics.contactoAlfaNeutro
                                    : EntrenarVidrioMetrics.contactoAlfaTeñido
        return LiquidShadowLayer(color: LiquidColor.tinta900.opacity(alfa),
                                 radius: EntrenarVidrioMetrics.contactoRadius, y: EntrenarVidrioMetrics.contactoY)
    }

    private var ambiente: LiquidShadowLayer {
        if tono == .neutro {
            return LiquidShadowLayer(color: LiquidColor.tinta900.opacity(EntrenarVidrioMetrics.ambienteAlfaNeutro),
                                     radius: EntrenarVidrioMetrics.ambienteRadiusNeutro,
                                     y: EntrenarVidrioMetrics.ambienteYNeutro)
        }
        return LiquidShadowLayer(color: tono.base.opacity(EntrenarVidrioMetrics.ambienteAlfaTeñido),
                                 radius: EntrenarVidrioMetrics.ambienteRadiusTeñido,
                                 y: EntrenarVidrioMetrics.ambienteYTeñido)
    }
}

/// Un módulo de vidrio a lo ancho del hub (héroe, semana, dosis, constancia, historial…).
public struct EntrenarModulo<Content: View>: View {
    private let tono: EntrenarTono
    private let intensidad: Double
    private let insets: EdgeInsets
    private let content: Content

    /// El contrato base: solo el tono, con el padding/intensidad por defecto del mock (v11/h18,
    /// 0.10).
    public init(tono: EntrenarTono = .neutro, @ViewBuilder content: () -> Content) {
        self.init(tono: tono, intensidad: EntrenarVidrioMetrics.intensidadDefault,
                  insets: EntrenarVidrioMetrics.moduloInsets, content: content)
    }

    /// Override explícito — el héroe del hub lo usa para su intensidad 0.11 y su padding v16
    /// propio (mock `.hero{padding:16px 18px}`).
    public init(tono: EntrenarTono, intensidad: Double,
                insets: EdgeInsets = EntrenarVidrioMetrics.moduloInsets,
                @ViewBuilder content: () -> Content) {
        self.tono = tono
        self.intensidad = intensidad
        self.insets = insets
        self.content = content()
    }

    public var body: some View {
        content
            .padding(insets)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(EntrenarVidrioReceta(tono: tono, intensidad: intensidad))
    }
}

/// Un tile del grid 2-col del hub (Subidas listas, Descanso real, Marcas, Volumen…). `minHeight`
/// fijo en 104 — no es un parámetro: las cuatro tarjetas del hub comparten la misma rejilla.
public struct EntrenarTile<Content: View>: View {
    private let tono: EntrenarTono
    private let content: Content

    public init(tono: EntrenarTono = .neutro, @ViewBuilder content: () -> Content) {
        self.tono = tono
        self.content = content()
    }

    public var body: some View {
        content
            .padding(EntrenarVidrioMetrics.tileInsets)
            .frame(maxWidth: .infinity, minHeight: EntrenarVidrioMetrics.tileMinHeight,
                   maxHeight: .infinity, alignment: .topLeading)
            .modifier(EntrenarVidrioReceta(tono: tono, intensidad: EntrenarVidrioMetrics.intensidadDefault))
    }
}

#if DEBUG
#Preview("EntrenarVidrio · los 6 tonos, módulo y tile") {
    ScrollView {
        VStack(spacing: 14) {
            ForEach(EntrenarTono.allCases, id: \.self) { tono in
                VStack(alignment: .leading, spacing: 8) {
                    EntrenarModulo(tono: tono) {
                        Text(verbatim: "MÓDULO · \(String(describing: tono))")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(tono.rotulo)
                    }
                    HStack(spacing: 12) {
                        EntrenarTile(tono: tono) {
                            Text(verbatim: "TILE").font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(tono.rotulo)
                        }
                        EntrenarTile(tono: tono) {
                            Circle().fill(tono.tesela).frame(width: 20, height: 20)
                        }
                    }
                }
            }
        }
        .padding(20)
    }
    .background(LiquidColor.fondoGradient)
}
#endif
