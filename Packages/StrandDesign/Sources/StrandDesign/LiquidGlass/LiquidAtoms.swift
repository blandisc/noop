import SwiftUI

// MARK: - Liquid Glass · Átomos

/// La «gota de icono» (§4.5): círculo r/orbe con el tono del dato al 10–12 % de alfa,
/// borde blanco 0.5 e inner-highlight — el ÚNICO lugar (junto con el valor numérico)
/// donde el tono tiñe una tarjeta. Tamaños del sistema: 22 (tiles, sugerencia) y
/// 28 (ModeTile, que sube el alfa a 12 %).
/// El sobretítulo en versalitas del sistema («DECIDEN TU DÍA», «QUÉ ES CADA UNA»): una sola
/// voz para las cabeceras de estante de Hoy y las secciones de sus hojas-manual (FER-125:
/// el mismo rol tipográfico cambiaba de tamaño y de tinta al cruzar la hoja).
public struct LiquidOverline: View {
    private let texto: String
    public init(_ texto: String) { self.texto = texto }
    public var body: some View {
        Text(texto)
            .font(LiquidType.cabeceraEstante)
            .tracking(LiquidType.cabeceraEstanteTracking)
            .textCase(.uppercase)
            .foregroundStyle(LiquidColor.tinta900)
    }
}

public struct LiquidIconDrop: View {
    private let glyph: LiquidIcon.Glyph
    private let tone: Color
    private let size: CGFloat
    private let iconSize: CGFloat
    private let fillAlpha: Double

    /// La gota de tile: 24 pt con icono 14, tono al 10 % (subida del 22 del handoff,
    /// elevación /inject — más presencia sin robarle al valor).
    public init(_ glyph: LiquidIcon.Glyph, tone: Color) {
        self.init(glyph, tone: tone, size: 24, iconSize: 14, fillAlpha: 0.10)
    }

    /// Variante dimensionada (ModeTile usa 28/15 con alfa 0.12).
    public init(_ glyph: LiquidIcon.Glyph, tone: Color, size: CGFloat, iconSize: CGFloat,
                fillAlpha: Double = 0.10) {
        self.glyph = glyph
        self.tone = tone
        self.size = size
        self.iconSize = iconSize
        self.fillAlpha = fillAlpha
    }

    public var body: some View {
        ZStack {
            Circle().fill(tone.opacity(fillAlpha))
            Circle()
                .strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.9), location: 0),
                            .init(color: .white.opacity(0), location: 1),
                        ],
                        startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1)
            Circle().strokeBorder(LiquidColor.vidrioBordeFuerte, lineWidth: 0.5)
            LiquidIcon(glyph, size: iconSize, color: tone)
        }
        .frame(width: size, height: size)
        // B2 · La gota es SIEMPRE decorativa: nunca lleva label propio, el rótulo del dato
        // vive al lado. Sin esto, los glifos de métrica —que se dibujan como SF Symbols—
        // le regalaban a VoiceOver una parada con el nombre del símbolo EN INGLÉS
        // («moon», «waveform path ecg») antes del dato, porque el `children: .contain` de
        // la cabecera y de los tiles no absorbe hijos. Mismo patrón que ya usa
        // `LiquidVerMas` con el glifo de Tendencias.
        .accessibilityHidden(true)
    }
}

/// El caption de delta bajo un valor («+2 ms vs tu base»): caption 9/500 con el color
/// semántico del tono de delta — nunca un color propio. Es texto de lectura: escala con
/// Dynamic Type.
public struct LiquidDeltaCaption: View {
    private let text: String
    private let tone: LiquidDeltaTone

    public init(_ text: String, tone: LiquidDeltaTone) {
        self.text = text
        self.tone = tone
    }

    public var body: some View {
        Text(text)
            .font(LiquidType.captionLectura)
            .foregroundStyle(tone.color)
    }
}

/// Origen del dato en una superficie Liquid — el vocabulario CERRADO de procedencia (FER-29 · C2).
///
/// El tipo no nombra «Apple» en su lógica; la etiqueta localizada («Apple Salud», «Apple Watch»,
/// «Calculado») la pasa el caller. Regla dura: nunca mezclar un dato CALCULADO con una etiqueta de
/// medición (el bug de Carga, que rotulaba «Apple Health» sobre un cálculo nuestro); nunca la palabra
/// «Band» en estas superficies.
///
/// Los dos casos originales (`medido`/`calculado`) son el vocabulario LEGADO de los tiles de «Hoy»
/// (FER-28) y se conservan para no tocar esa superficie fuera de alcance. Las hojas de detalle migran
/// al vocabulario cerrado de abajo (`appleSalud`/`appleWatch`/`calculadoEnTelefono`/`sinOrigen`) en F1;
/// `esCalculado` unifica el comportamiento del punto de procedencia entre ambos mundos mientras coexisten.
public enum LiquidOrigen: Sendable, Equatable {
    // Vocabulario legado (tiles de «Hoy», FER-28) — no extender a superficies nuevas.
    case medido
    case calculado

    // Vocabulario cerrado de las hojas (FER-29 · C2).
    /// Lectura directa de Apple Salud (fuente no afirmable como el Watch).
    case appleSalud
    /// Medido por el Apple Watch (cuando la procedencia sí se puede afirmar).
    case appleWatch
    /// Derivado en el teléfono por Cénit (recovery/strain/stress, carga ACWR): NUNCA etiqueta de Apple.
    case calculadoEnTelefono
    /// Sin dato / calibrando: no se afirma procedencia (numeral «—»/«··»).
    case sinOrigen

    /// ¿Es un dato calculado por Cénit? (legado `.calculado` o el cerrado `.calculadoEnTelefono`.)
    /// El punto de procedencia marca SOLO lo calculado; lo medido se dice con la etiqueta, sin punto.
    public var esCalculado: Bool {
        self == .calculado || self == .calculadoEnTelefono
    }
}

/// El punto de origen que marca un dato CALCULADO junto a su delta; la leyenda bajo la
/// retícula lo decodifica. Decorativo para VoiceOver (la leyenda es quien habla).
public struct LiquidOrigenDot: View {
    public init() {}

    public var body: some View {
        Circle()
            .fill(LiquidColor.tinta500.opacity(0.55))
            .frame(width: 3, height: 3)
            .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("Liquid · Átomos") {
    VStack(spacing: LiquidSpace.s400) {
        HStack(spacing: LiquidSpace.s300) {
            LiquidIconDrop(.onda, tone: LiquidColor.cian)
            LiquidIconDrop(.luna, tone: LiquidColor.indigo)
            LiquidIconDrop(.corazon, tone: LiquidColor.rosa)
            LiquidIconDrop(.llama, tone: LiquidColor.ambar)
            LiquidIconDrop(.rayo, tone: LiquidColor.ambar, size: 28, iconSize: 15, fillAlpha: 0.12)
        }
        VStack(alignment: .leading, spacing: LiquidSpace.s100) {
            LiquidDeltaCaption("+2 ms vs tu base", tone: .up)
            LiquidDeltaCaption("−0.7 vs tu base", tone: .down)
            LiquidDeltaCaption("En tu base", tone: .neutral)
        }
    }
    .padding(LiquidSpace.s800)
    .background(LiquidColor.papelGradient)
}
#endif
