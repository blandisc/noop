import SwiftUI

// MARK: - HojaRondaDivisor — divisor de ronda en superserie viva (FER-168 · F3)
//
// Mock `hoja-pantallas.html` P5 `.ronda` + `.ronda .fil`: rótulo cian + línea que llena el ancho.

/// Constantes locales del divisor (mock `.ronda` / `.fil`). No viven en `HojaMetrics`.
private enum HojaRondaDivisorMetrics {
    /// `.ronda` `font-size: 8.5px`.
    static var rotuloSize: CGFloat { 8.5 }
    /// `.ronda` `letter-spacing: 1.8px`.
    static var rotuloTracking: CGFloat { 1.8 }
    /// `.ronda` `padding: 8px 2px 2px`.
    static var padTop: CGFloat { 8 }
    static var padH: CGFloat { 2 }
    static var padBottom: CGFloat { 2 }
    /// `.ronda` `gap: 8px` entre rótulo y `.fil`.
    static var gap: CGFloat { 8 }
    /// `.ronda .fil` `height: 1px`.
    static var filGrosor: CGFloat { 1 }
    /// `.ronda .fil` `rgba(20,124,140,.25)` (= `LiquidColor.cian` al 25 %).
    static var filAlfa: Double { 0.25 }
    /// Rótulo cian canónico del vidrio teñido (mock `.ronda` / `.ssL`).
    static var cianRotulo: Color { LiquidTono.cian.rotulo }
}

/// Divisor de ronda dentro de la tarjeta de superserie viva: rótulo + línea cian.
public struct HojaRondaDivisor: View {
    private let texto: String

    /// - Parameter texto: ya localizado por el caller (p. ej. «Ronda 1 de 3»).
    public init(texto: String) {
        self.texto = texto
    }

    public var body: some View {
        HStack(alignment: .center, spacing: HojaRondaDivisorMetrics.gap) {
            Text(verbatim: texto)
                .font(InstrumentoType.grotesk(
                    HojaRondaDivisorMetrics.rotuloSize,
                    weight: .bold,
                    relativeTo: .caption2))
                .tracking(HojaRondaDivisorMetrics.rotuloTracking)
                .textCase(.uppercase)
                .foregroundStyle(HojaRondaDivisorMetrics.cianRotulo)
                .fixedSize(horizontal: true, vertical: false)

            Rectangle()
                .fill(LiquidColor.cian.opacity(HojaRondaDivisorMetrics.filAlfa))
                .frame(height: HojaRondaDivisorMetrics.filGrosor)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
        }
        .padding(.top, HojaRondaDivisorMetrics.padTop)
        .padding(.horizontal, HojaRondaDivisorMetrics.padH)
        .padding(.bottom, HojaRondaDivisorMetrics.padBottom)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

#if DEBUG
#Preview("HojaRondaDivisor · rondas") {
    VStack(alignment: .leading, spacing: 12) {
        HojaRondaDivisor(texto: "Ronda 1 de 3")
        HojaRondaDivisor(texto: "Ronda 2 de 3")
    }
    .padding(16)
    .background(LiquidColor.fondoGradient)
}
#endif
