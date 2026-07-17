import SwiftUI

// MARK: - Tool chip (FER-952 · decisión de auditoría)
//
// La «puerta de herramienta» del flujo Entrenar: un chip ancho y quieto (glifo + rótulo en tinta
// sobre `patternBlock`) para acciones secundarias que no son datos — Templates, Import, Folders.
// Vivía copiado byte a byte en el hub, Tu Plan y Mis Rutinas; una sola fuente aquí. El paquete no
// tiene catálogo de strings, así que el rótulo llega como `Text` ya localizado por el caller
// (mismo contrato que SessionPill).

public struct InstrumentoToolChip: View {
    @Environment(\.instrumentoTheme) private var theme
    let systemImage: String
    let label: Text
    let action: () -> Void

    public init(systemImage: String, label: Text, action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.label = label
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage).font(StrandFont.glyph(.chevron, weight: .medium))
                label.font(StrandFont.subhead.weight(.medium))
            }
            .foregroundStyle(theme.ink)
            // 44: mínimo de toque HIG (§8.7-4) — las copias originales traían 40.
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(theme.patternBlock, in: RoundedRectangle(cornerRadius: CenitMetrics.insetRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#if DEBUG
#Preview("Tool chips") {
    HStack(spacing: 8) {
        InstrumentoToolChip(systemImage: "square.stack.3d.up", label: Text(verbatim: "Plantillas")) {}
        InstrumentoToolChip(systemImage: "square.and.arrow.down", label: Text(verbatim: "Importar")) {}
        InstrumentoToolChip(systemImage: "folder", label: Text(verbatim: "Carpetas")) {}
    }
    .padding(24)
    .background(InstrumentoTheme.base.paper)
    .environment(\.instrumentoTheme, .base)
    .preferredColorScheme(.light)
}
#endif
