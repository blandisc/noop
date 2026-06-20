import SwiftUI

// MARK: - Onboarding / action buttons (Instrumento)
//
// La jerarquía la da el RELLENO DE TINTA, no el color (DESIGN.md §8.4 r2): el
// primario (`InkButton`) es tinta sólida sobre papel; el secundario
// (`OutlineButton`) es contorno. Verde/rojo quedan libres para el único lugar
// legítimo en Instrumento: el dato/estado medido. Ningún hex nuevo — ambos reusan
// roles del `InstrumentoTheme`. Pensados para CTAs de ancho completo (onboarding,
// y luego Perfil/Import/Listo y el onboarding de aprendizaje).

/// Press feedback compartido: un hundido sutil, sin glow ni cambio de color.
private struct InstrumentoPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(StrandMotion.interactive, value: configuration.isPressed)
    }
}

/// CTA primario: relleno `ink`, label `paper`. El elemento de más peso de la
/// pantalla **sin un solo pixel de color** — la inversión exacta del papel.
public struct InkButton: View {
    @Environment(\.instrumentoTheme) private var theme
    private let title: LocalizedStringKey
    private let action: () -> Void

    public init(_ title: LocalizedStringKey, action: @escaping () -> Void) {
        self.title = title; self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(StrandFont.headline)
                .foregroundStyle(theme.paper)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(theme.ink, in: RoundedRectangle(cornerRadius: NoopMetrics.controlRadius, style: .continuous))
        }
        .buttonStyle(InstrumentoPressStyle())
    }
}

/// Salida secundaria de PRIMERA CLASE: contorno legible, ancho completo, alto
/// táctil holgado. Es el `QuietButton` llevado a CTA — nunca un gris-fantasma.
public struct OutlineButton: View {
    @Environment(\.instrumentoTheme) private var theme
    private let title: LocalizedStringKey
    private let action: () -> Void

    public init(_ title: LocalizedStringKey, action: @escaping () -> Void) {
        self.title = title; self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(StrandFont.headline)
                .foregroundStyle(theme.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(theme.surface, in: RoundedRectangle(cornerRadius: NoopMetrics.controlRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: NoopMetrics.controlRadius, style: .continuous)
                    .strokeBorder(theme.hairlineStrong, lineWidth: 1))
        }
        .buttonStyle(InstrumentoPressStyle())
    }
}

#if DEBUG
#Preview("Instrumento · onboarding buttons") {
    VStack(spacing: NoopMetrics.gap) {
        InkButton("Conectar Apple Health", action: {})
        OutlineButton("Ahora no", action: {})
    }
    .padding(NoopMetrics.screenPadding)
    .frame(width: 390)
    .background(InstrumentoTheme.base.paper)
    .instrumentoTheme(.base)
}
#endif
