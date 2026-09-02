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

    /// Sobre qué fondo se dibuja. No es decoración: el disco de papel desaparece sobre un relleno de
    /// color, así que sobre acento se invierte a crema translúcida (el descanso de la sesión pinta la
    /// pantalla de verde debajo de este botón).
    public enum Surface {
        /// El papel normal de la app.
        case paper
        /// Un relleno de color saturado (el verde del descanso, FER-934).
        case accent
    }

    private let role: Role
    private let surface: Surface
    private let theme: InstrumentoTheme
    private let action: () -> Void

    public init(role: Role = .back, surface: Surface = .paper,
                theme: InstrumentoTheme, action: @escaping () -> Void) {
        self.role = role; self.surface = surface; self.theme = theme; self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: role.symbol)
                .font(StrandFont.glyph(.inline, weight: .semibold))
                .foregroundStyle(glyphColor)
                // El disco mide 40; el marco de 44 le da el área táctil mínima de HIG sin
                // engordar el dibujo.
                .frame(width: Self.disc, height: Self.disc)
                .background(Circle().fill(fillColor))
                .overlay(Circle().strokeBorder(strokeColor, lineWidth: 1))
                .frame(width: Self.hitTarget, height: Self.hitTarget)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(role.label))
    }

    private var glyphColor: Color {
        surface == .accent ? theme.paper : theme.ink
    }
    private var fillColor: Color {
        surface == .accent ? theme.paper.opacity(CenitOpacity.tintFillStrong) : theme.surface
    }
    private var strokeColor: Color {
        surface == .accent ? theme.paper.opacity(CenitOpacity.strokeSoft) : theme.hairlineStrong
    }

    private static let disc: CGFloat = 40
    private static let hitTarget: CGFloat = 44
}

#if DEBUG
#Preview("BackButton") {
    let t = InstrumentoTheme.base
    VStack(spacing: 0) {
        HStack(spacing: 20) {
            BackButton(role: .back, theme: t, action: {})
            BackButton(role: .close, theme: t, action: {})
        }
        .frame(maxWidth: .infinity)
        .padding(40)
        .background(t.paper)
        // Sobre acento: el mismo botón, invertido — así se ve durante el descanso de la sesión.
        HStack(spacing: 20) {
            BackButton(role: .back, surface: .accent, theme: t, action: {})
            BackButton(role: .close, surface: .accent, theme: t, action: {})
        }
        .frame(maxWidth: .infinity)
        .padding(40)
        .background(t.verdict)
    }
    .instrumentoTheme(t)
}
#endif
