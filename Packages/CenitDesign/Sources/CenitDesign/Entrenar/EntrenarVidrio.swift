import SwiftUI

// MARK: - LiquidTono · vidrio teñido unificado (FER-234 · épico FER-229)
//
// La receta de vidrio teñido de Entrenar (antes enum de tono del hub + ViewModifier privado)
// vive ahora como régimen de la puerta `liquidGlass(tono:regimen:)`. `.mosaico` = identidad
// por relleno teñido (hub Entrenar); `.sobrio` = superficie neutra, el color lo pinta el
// consumidor en el numeral (Hoy/detalles).
//
// `EntrenarModulo` y `EntrenarTile` son la MISMA receta (`LiquidTonoReceta`) con `regimen:
// .mosaico` por construcción; lo único que cambia entre los dos contenedores es el padding y el
// `minHeight` (el mock lo confirma: la variante neutra de tile, `.tDes`, usa exactamente el mismo
// `box-shadow`/fondo que el módulo neutro `.mod`, y las tres variantes teñidas de tile comparten
// `box-shadow` con el módulo teñido `.dos`).

/// El tono de vidrio teñido — identidad de color de una sección/dato. Deliberadamente distinto
/// de `EntrenarFamily` (push/pull/legs/fullBody, la familia de una RUTINA): `LiquidTono` es la
/// paleta del HUB y del vidrio unificado, no de una rutina — «Marcas» siempre es rosa,
/// «Volumen» siempre ámbar, sin importar qué se entrenó ese día.
public enum LiquidTono: Sendable, Equatable, CaseIterable {
    case neutro, indigo, cian, verde, rosa, ambar

    /// Intensidad default del vidrio teñido (0.10). Canónico para `liquidGlass(tono:)`.
    public static let intensidadDefault: Double = 0.10

    /// El color base del tono: `neutro` es blanco (el vidrio no tiñe); el resto son los MISMOS
    /// hex 1:1 que ya usa el resto del sistema vía `LiquidColor` — ninguno se redefine aquí.
    /// `verde` es `verdeCarga` (identidad de carga), nunca `verdePrimario` (voz de marca).
    public var base: Color {
        switch self {
        case .neutro: return .white
        case .indigo: return LiquidColor.indigo
        case .cian:   return LiquidColor.cian
        case .verde:  return LiquidColor.verdeCarga
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

/// El puente familia→tono del hub v18 (FER-171 · Parte B): qué `LiquidTono` tiñe el HÉROE (que
/// tiñe por la familia de la rutina del día) y las TESELAS de semana / celdas de constancia (que
/// tiñen por la familia de cada sesión) — los tres únicos lugares del hub donde la identidad de
/// color viene de una FAMILIA en vez del rol fijo del módulo (Marcas siempre rosa, Volumen siempre
/// ámbar, con o sin importar qué se entrenó). Mapeo 1:1 con `EntrenarFamily.tint` (push → ember,
/// pull → teal, legs/fullBody → índigo) para que un mismo día lea el mismo color en el héroe, la
/// tesela y la celda — una sola tabla, no una por consumidor.
public extension EntrenarFamily {
    var tono: LiquidTono {
        switch self {
        case .push:             return .ambar
        case .pull:             return .cian
        case .legs, .fullBody:  return .indigo
        }
    }
}

/// Las constantes con nombre de la receta — nada suelto en `LiquidTonoReceta`. Cada valor
/// cita su origen exacto en el mock `eje-hub-v18.html` para que un cambio de diseño futuro sepa
/// qué línea de CSS está tocando. `public`: `moduloInsets` es el default-argument de un `init`
/// público (Swift exige que el default sea al menos tan visible como el `init`), y el resto viaja
/// con ella por consistencia — mismo criterio que `EntrenarMetrics`/`LiquidSpace`/`LiquidRadius`.
public enum LiquidTonoMetrics {
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
    public static let intensidadDefault: Double = LiquidTono.intensidadDefault

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

/// Resolución de colores de superficie para `LiquidTonoReceta` — `@testable` para que el
/// contrato AA y los cinturones mosaico/sobrio crucen la frontera real de la receta.
enum LiquidTonoSuperficie {
    /// En `.sobrio` el tono no toca la superficie: se compone como si `tono == .neutro`.
    static func tonoDeSuperficie(_ tono: LiquidTono, regimen: LiquidRegimen) -> LiquidTono {
        regimen == .sobrio ? .neutro : tono
    }

    static func rellenoResuelto(tono: LiquidTono, regimen: LiquidRegimen, intensidad: Double) -> Color {
        let t = tonoDeSuperficie(tono, regimen: regimen)
        return t == .neutro
            ? Color.white.opacity(LiquidTonoMetrics.rellenoNeutroAlfa)
            : t.base.opacity(intensidad)
    }

    static func highlightResuelto(tono: LiquidTono, regimen: LiquidRegimen) -> Color {
        let t = tonoDeSuperficie(tono, regimen: regimen)
        return t == .neutro ? LiquidTonoMetrics.highlightNeutro : LiquidTonoMetrics.highlightTeñido
    }

    static func cantoResuelto(tono: LiquidTono, regimen: LiquidRegimen) -> Color {
        let t = tonoDeSuperficie(tono, regimen: regimen)
        return t == .neutro
            ? LiquidColor.tinta900.opacity(0.16)
            : t.base.opacity(LiquidTonoMetrics.cantoAlfaTeñido)
    }

    static func usaAroTeñido(tono: LiquidTono, regimen: LiquidRegimen) -> Bool {
        tonoDeSuperficie(tono, regimen: regimen) != .neutro
    }

    static func sombrasResueltas(tono: LiquidTono, regimen: LiquidRegimen) -> [LiquidShadowLayer] {
        let t = tonoDeSuperficie(tono, regimen: regimen)
        if t == .neutro { return LiquidElevation.tarjeta }
        let contacto = LiquidShadowLayer(
            color: LiquidColor.tinta900.opacity(LiquidTonoMetrics.contactoAlfaTeñido),
            radius: LiquidTonoMetrics.contactoRadius,
            y: LiquidTonoMetrics.contactoY)
        let ambiente = LiquidShadowLayer(
            color: t.base.opacity(LiquidTonoMetrics.ambienteAlfaTeñido),
            radius: LiquidTonoMetrics.ambienteRadiusTeñido,
            y: LiquidTonoMetrics.ambienteYTeñido)
        return [contacto, ambiente]
    }
}

/// La receta compartida, aplicada como `ViewModifier` — `EntrenarModulo`/`EntrenarTile` y la
/// sobrecarga `liquidGlass(tono:regimen:)` solo le dan padding/tamaño/régimen distintos.
struct LiquidTonoReceta: ViewModifier {
    let tono: LiquidTono
    let regimen: LiquidRegimen
    let intensidad: Double

    @Environment(\.liquidMotionDisabled) private var motionDisabled

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: LiquidRadius.tile, style: .continuous)
    }

    func body(content: Content) -> some View {
        content
            .background { fondo }
            .overlay { shape.strokeBorder(highlight, lineWidth: 1) }
            .overlay {
                if LiquidTonoSuperficie.usaAroTeñido(tono: tono, regimen: regimen) {
                    shape.strokeBorder(LiquidTonoMetrics.aroTeñido, lineWidth: 1)
                }
            }
            .overlay { shape.stroke(canto, lineWidth: 0.5) }
            .liquidShadow(sombrasTarjeta, silhouette: shape)
    }

    private var sombrasTarjeta: [LiquidShadowLayer] {
        LiquidTonoSuperficie.sombrasResueltas(tono: tono, regimen: regimen)
    }

    /// Mismo patrón que `LiquidModulo.glass`: vidrio nativo en iOS 26, material +backdrop
    /// saturado 1.28× (`LiquidColor.vidrioRefraccion`) antes de eso.
    @ViewBuilder
    private var fondo: some View {
        if #available(iOS 26.0, macOS 26.0, watchOS 26.0, *), !motionDisabled {
            Color.clear
                .background { shape.fill(relleno) }
                .glassEffect(.regular, in: shape)
        } else {
            ZStack {
                LiquidGlassBase.ultraFino(shape).saturation(LiquidColor.vidrioRefraccion)
                shape.fill(relleno)
            }
        }
    }

    private var relleno: Color {
        LiquidTonoSuperficie.rellenoResuelto(tono: tono, regimen: regimen, intensidad: intensidad)
    }

    private var highlight: Color {
        LiquidTonoSuperficie.highlightResuelto(tono: tono, regimen: regimen)
    }

    private var canto: Color {
        LiquidTonoSuperficie.cantoResuelto(tono: tono, regimen: regimen)
    }
}

/// Un módulo de vidrio a lo ancho del hub (héroe, semana, dosis, constancia, historial…).
/// Fija `regimen: .mosaico` por construcción — el default `.sobrio` de `liquidGlass(tono:)` no
/// alcanza al hub.
public struct EntrenarModulo<Content: View>: View {
    private let tono: LiquidTono
    private let intensidad: Double
    private let insets: EdgeInsets
    private let content: Content

    /// El contrato base: solo el tono, con el padding/intensidad por defecto del mock (v11/h18,
    /// 0.10).
    public init(tono: LiquidTono = .neutro, @ViewBuilder content: () -> Content) {
        self.init(tono: tono, intensidad: LiquidTonoMetrics.intensidadDefault,
                  insets: LiquidTonoMetrics.moduloInsets, content: content)
    }

    /// Override explícito — el héroe del hub lo usa para su intensidad 0.11 y su padding v16
    /// propio (mock `.hero{padding:16px 18px}`).
    public init(tono: LiquidTono, intensidad: Double,
                insets: EdgeInsets = LiquidTonoMetrics.moduloInsets,
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
            .modifier(LiquidTonoReceta(tono: tono, regimen: .mosaico, intensidad: intensidad))
    }
}

/// Un tile del grid 2-col del hub (Subidas listas, Descanso real, Marcas, Volumen…). `minHeight`
/// fijo en 104 — no es un parámetro: las cuatro tarjetas del hub comparten la misma rejilla.
/// Fija `regimen: .mosaico` por construcción.
public struct EntrenarTile<Content: View>: View {
    private let tono: LiquidTono
    private let content: Content

    public init(tono: LiquidTono = .neutro, @ViewBuilder content: () -> Content) {
        self.tono = tono
        self.content = content()
    }

    public var body: some View {
        content
            .padding(LiquidTonoMetrics.tileInsets)
            .frame(maxWidth: .infinity, minHeight: LiquidTonoMetrics.tileMinHeight,
                   maxHeight: .infinity, alignment: .topLeading)
            .modifier(LiquidTonoReceta(tono: tono, regimen: .mosaico,
                                       intensidad: LiquidTonoMetrics.intensidadDefault))
    }
}

#if DEBUG
#Preview("LiquidTono · los 6 tonos, módulo y tile") {
    ScrollView {
        VStack(spacing: 14) {
            ForEach(LiquidTono.allCases, id: \.self) { tono in
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
