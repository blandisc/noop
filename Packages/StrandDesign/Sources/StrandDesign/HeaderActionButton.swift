import SwiftUI

/// La acción con nombre de una barra de encabezado — la pareja de `BackButton`.
///
/// `BackButton` es un disco porque salir no necesita nombrarse; esta acción sí (Guardar, Terminar),
/// así que es una cápsula. Comparten relleno y filo a propósito: son dos objetos de la misma familia
/// y la barra deja de leerse asimétrica cuando conviven.
///
/// El relleno es de papel, no de tinta: en «Instrumento diurno» el peso visual se reserva para el
/// dato, y una barra de navegación es chrome.
public struct HeaderActionButton: View {
    private let label: Text
    private let enabled: Bool
    private let theme: InstrumentoTheme
    private let action: () -> Void

    public init(_ label: Text, enabled: Bool = true,
                theme: InstrumentoTheme, action: @escaping () -> Void) {
        self.label = label; self.enabled = enabled; self.theme = theme; self.action = action
    }

    public var body: some View {
        Button(action: action) {
            label
                .font(StrandFont.subhead.weight(.medium))
                .foregroundStyle(enabled ? theme.ink : theme.inkTertiary)
                .padding(.horizontal, 14)
                .frame(height: Self.height)
                .background(Capsule().fill(theme.surface))
                .overlay(Capsule().strokeBorder(theme.hairlineStrong, lineWidth: 1))
                .frame(minHeight: Self.hitTarget)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    /// 32 es la altura de cápsula que la sesión ya usa en Pausar/Terminar; el marco de 44 le da el
    /// área táctil de HIG sin engordar el dibujo (misma disciplina que `BackButton`).
    private static let height: CGFloat = 32
    private static let hitTarget: CGFloat = 44
}

#if DEBUG
#Preview("HeaderActionButton") {
    let t = InstrumentoTheme.base
    VStack(spacing: 20) {
        // La barra completa: el disco para salir, la cápsula para la acción con nombre.
        HStack {
            BackButton(role: .close, theme: t, action: {})
            Spacer()
            Text(verbatim: "Nueva rutina").font(StrandFont.body).foregroundStyle(t.ink)
            Spacer()
            HeaderActionButton(Text(verbatim: "Guardar"), theme: t, action: {})
        }
        HStack(spacing: 12) {
            HeaderActionButton(Text(verbatim: "Guardar"), theme: t, action: {})
            HeaderActionButton(Text(verbatim: "Guardar"), enabled: false, theme: t, action: {})
        }
    }
    .padding(24)
    .background(t.paper)
    .instrumentoTheme(t)
}
#endif
