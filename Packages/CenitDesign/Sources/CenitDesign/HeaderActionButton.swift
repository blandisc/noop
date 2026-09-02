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
                .headerCapsule(theme)
                // El marco táctil lo pone el BOTÓN, no el cromo: la sesión activa mete sus cápsulas
                // en una fila de 32 junto al reloj, y forzarles 44 desde el modificador le crecería
                // el encabezado 12pt a una pantalla ya publicada.
                .frame(minHeight: 44)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

public extension View {
    /// El cromo de la cápsula de encabezado — relleno, filo y altura del dibujo, en un solo lugar.
    ///
    /// Existe como modificador y no solo dentro de `HeaderActionButton` porque la sesión activa tiene
    /// cuatro acciones (Reanudar, Pausar, Terminar, Descartar) cuyo contenido no es un rótulo simple:
    /// un `Label` con icono, un glifo solo, dos voces tipográficas distintas. Todas comparten ESTE
    /// cromo; lo que cambia es lo que va adentro.
    ///
    /// Dibuja 32 de alto y NO impone área táctil: quien lo use decide si envolverlo en un marco de
    /// 44. `HeaderActionButton` lo hace; la sesión no puede, porque sus cápsulas comparten fila con
    /// el reloj y crecerían el encabezado.
    func headerCapsule(_ theme: InstrumentoTheme) -> some View {
        self
            .padding(.horizontal, 14)
            .frame(height: 32)
            .background(Capsule().fill(theme.surface))
            .overlay(Capsule().strokeBorder(theme.hairlineStrong, lineWidth: 1))
    }
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
