import SwiftUI

// MARK: - «Instrumento diurno» card surface (auditoría jul-2026, H2 · H3)
//
// La ÚNICA forma sancionada de dibujar una tarjeta: fondo `surface` (o un `fill`
// tintado) + borde hairline con un radio semántico. Antes de esto el patrón
// `.background(theme.surface, in: RoundedRectangle(cornerRadius: N)) + .overlay(stroke)`
// se redibujaba a mano ~80 veces con radios literales (6/8/9/10/11/12/13/14/18) que
// conviven con los tokens de `NoopMetrics`. Este modifier elimina el literal del call
// site: el radio se elige por ROL, nunca por CGFloat.
//
// El tema viaja por environment (`\.instrumentoTheme`), así que el call site NO pasa
// `theme`: `SomeCard { … }.instrumentoCard(.card)` — igual que el resto de componentes
// del paquete. Los defaults (`surface` + `hairline`, lineWidth 1) reproducen el patrón
// más común; para tarjetas con fondo tintado o borde de color se pasan `fill:`/`stroke:`.

/// El rol del radio de una tarjeta «Instrumento diurno». Nunca un `CGFloat` literal.
public enum InstrumentoCardRadius {
    /// `NoopMetrics.cardRadius` (16) — tarjetas de sección.
    case card
    /// `NoopMetrics.ctaRadius` (14) — tarjetas destacadas / CTA.
    case cta
    /// `NoopMetrics.controlRadius` (12) — tarjetas estándar (el caso más común). Absorbe 13.
    case control
    /// `NoopMetrics.insetRadius` (10) — sub-tarjetas anidadas. Absorbe 9/11.
    case inset

    public var value: CGFloat {
        switch self {
        case .card:    return NoopMetrics.cardRadius
        case .cta:     return NoopMetrics.ctaRadius
        case .control: return NoopMetrics.controlRadius
        case .inset:   return NoopMetrics.insetRadius
        }
    }
}

private struct InstrumentoCardModifier: ViewModifier {
    @Environment(\.instrumentoTheme) private var envTheme
    let explicitTheme: InstrumentoTheme?
    let radius: InstrumentoCardRadius
    let fill: Color?
    let stroke: Color?
    let lineWidth: CGFloat

    func body(content: Content) -> some View {
        // El tema explícito gana; `InstrumentoTheme` NO se propaga por environment a través de `.sheet`
        // (FER-162), así que las pantallas presentadas como hoja DEBEN pasar su `theme`.
        let theme = explicitTheme ?? envTheme
        let shape = RoundedRectangle(cornerRadius: radius.value, style: .continuous)
        content
            .background(fill ?? theme.surface, in: shape)
            .overlay(shape.strokeBorder(stroke ?? theme.hairline, lineWidth: lineWidth))
    }
}

public extension View {
    /// Dibuja el subtree como una tarjeta «Instrumento diurno»: fondo + borde hairline con un radio
    /// semántico.
    ///
    /// - Parameters:
    ///   - radius: rol del radio (nunca un `CGFloat` literal). Default `.control` — el caso más común.
    ///   - theme: tema explícito. Pasarlo SIEMPRE en pantallas presentadas como `.sheet` (el environment
    ///     no lo lleva, FER-162). En un subtree que sí inyecta `.instrumentoTheme(_:)` puede omitirse.
    ///   - fill: fondo; por defecto `theme.surface`. Pasar un color tintado (`theme.tint(c)`) para badges.
    ///   - stroke: color del borde; por defecto `theme.hairline`.
    ///   - lineWidth: 1 por defecto; 0.5 solo para tarjetas grandes (`.card`).
    func instrumentoCard(_ radius: InstrumentoCardRadius = .control,
                         theme: InstrumentoTheme? = nil,
                         fill: Color? = nil,
                         stroke: Color? = nil,
                         lineWidth: CGFloat = 1) -> some View {
        modifier(InstrumentoCardModifier(explicitTheme: theme, radius: radius,
                                         fill: fill, stroke: stroke, lineWidth: lineWidth))
    }
}

#if DEBUG
#Preview("InstrumentoCard · radios") {
    let t = InstrumentoTheme.base
    return VStack(spacing: 16) {
        ForEach([("card", InstrumentoCardRadius.card), ("cta", .cta), ("control", .control), ("inset", .inset)], id: \.0) { name, r in
            Text(name)
                .font(StrandFont.caption)
                .foregroundStyle(t.inkSecondary)
                .frame(maxWidth: .infinity, minHeight: 56)
                .padding(NoopMetrics.cardPadding)
                .instrumentoCard(r)
        }
        Text("tintada")
            .font(StrandFont.caption)
            .foregroundStyle(t.warning)
            .frame(maxWidth: .infinity, minHeight: 56)
            .padding(NoopMetrics.cardPadding)
            .instrumentoCard(.control, fill: t.warning.opacity(StrandOpacity.tintFill), stroke: t.warning.opacity(StrandOpacity.strokeSoft))
    }
    .padding(24)
    .background(t.paper)
    .instrumentoTheme(t)
    .preferredColorScheme(.light)
}
#endif
