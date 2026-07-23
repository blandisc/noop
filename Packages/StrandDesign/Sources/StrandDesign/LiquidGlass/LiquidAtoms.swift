import SwiftUI

// MARK: - Liquid Glass · Átomos

/// La «gota de icono» (§4.5): círculo r/orbe con el tono del dato al 10–12 % de alfa,
/// borde blanco 0.5 e inner-highlight — el ÚNICO lugar (junto con el valor numérico)
/// donde el tono tiñe una tarjeta. Tamaños del sistema: 22 (tiles, sugerencia) y
/// 28 (ModeTile, que sube el alfa a 12 %).
public struct LiquidIconDrop: View {
    private let glyph: LiquidIcon.Glyph
    private let tone: Color
    private let size: CGFloat
    private let iconSize: CGFloat
    private let fillAlpha: Double

    /// La gota de tile: 22 pt con icono 13, tono al 10 %.
    public init(_ glyph: LiquidIcon.Glyph, tone: Color) {
        self.init(glyph, tone: tone, size: 22, iconSize: 13, fillAlpha: 0.10)
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

/// Origen del dato de un tile (paridad con el SourceChip FER-878 en mundo Apple-only):
/// medido por Apple Salud, o calculado/estimado por Cénit (p. ej. pasos estimados FER-663).
public enum LiquidOrigen: Sendable, Equatable {
    case medido
    case calculado
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
