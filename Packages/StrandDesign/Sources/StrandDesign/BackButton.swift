import SwiftUI

/// La salida de una pantalla empujada, en un solo lugar (FER-988).
///
/// Antes cada pantalla dibujaba su propio `chevron.left` a mano y ninguna coincidía con la de al
/// lado. Este es el disco de papel del lenguaje «Instrumento diurno» — la misma superficie y el
/// mismo filo que `StepperButton`, para que los controles de la app se lean como una sola familia.
///
/// El rol importa y no es cosmético: `.back` vuelve a la pantalla anterior, `.close` descarta una
/// hoja. Son gestos distintos y VoiceOver los anuncia distinto.
public struct BackButton: View {
    public enum Role {
        /// Vuelve a la pantalla anterior de la pila. Chevron.
        case back
        /// Descarta una presentación modal. Aspa.
        case close

        var symbol: String { self == .back ? "chevron.left" : "xmark" }
        var label: LocalizedStringKey { self == .back ? "Back" : "Close" }
    }

    private let role: Role
    private let theme: InstrumentoTheme
    private let action: () -> Void

    public init(role: Role = .back, theme: InstrumentoTheme, action: @escaping () -> Void) {
        self.role = role; self.theme = theme; self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: role.symbol)
                .font(StrandFont.glyph(.inline, weight: .semibold))
                .foregroundStyle(theme.ink)
                // El disco mide 40; el marco de 44 le da el área táctil mínima de HIG sin
                // engordar el dibujo.
                .frame(width: Self.disc, height: Self.disc)
                .background(Circle().fill(theme.surface))
                .overlay(Circle().strokeBorder(theme.hairlineStrong, lineWidth: 1))
                .frame(width: Self.hitTarget, height: Self.hitTarget)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(role.label))
    }

    private static let disc: CGFloat = 40
    private static let hitTarget: CGFloat = 44
}

#if DEBUG
#Preview("BackButton") {
    let t = InstrumentoTheme.base
    HStack(spacing: 20) {
        BackButton(role: .back, theme: t, action: {})
        BackButton(role: .close, theme: t, action: {})
    }
    .padding(40)
    .background(t.paper)
    .instrumentoTheme(t)
}
#endif
