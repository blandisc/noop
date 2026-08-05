import SwiftUI

/// FER-51 §3 · Modo de la pantalla Hoy: Cosmos (artístico) o Matriz (instrumento).
public enum HoyModo: String, Sendable, CaseIterable {
    case cosmos, matriz
}

/// Control tipográfico «COSMOS · MATRIZ»: caps 11 pt, letter-spacing 0.15 em;
/// activo en `tinta900` weight 600 + punto de 4 pt debajo; inactivo `tinta500` weight 500.
/// Hit ≥ 44×44 pt por rótulo. Estado inyectado por el caller (`Binding`).
public struct HoyModoConmutador: View {
    @Binding private var modo: HoyModo
    private let rotuloCosmos: String
    private let rotuloMatriz: String

    public init(modo: Binding<HoyModo>, rotuloCosmos: String, rotuloMatriz: String) {
        self._modo = modo
        self.rotuloCosmos = rotuloCosmos
        self.rotuloMatriz = rotuloMatriz
    }

    /// 0.15 em a 11 pt.
    private static let tracking: CGFloat = 11 * 0.15

    public var body: some View {
        HStack(spacing: 10) {
            rotulo(rotuloCosmos, modo: .cosmos)
            Text(verbatim: "·")
                .font(InstrumentoType.grotesk(11, weight: .medium))
                .foregroundStyle(LiquidColor.tinta500)
                .accessibilityHidden(true)
            rotulo(rotuloMatriz, modo: .matriz)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: "\(rotuloCosmos) · \(rotuloMatriz)"))
    }

    private func rotulo(_ texto: String, modo target: HoyModo) -> some View {
        let activo = modo == target
        return Button {
            modo = target
        } label: {
            VStack(spacing: 4) {
                Text(texto)
                    .font(InstrumentoType.grotesk(11, weight: activo ? .semibold : .medium))
                    .tracking(Self.tracking)
                    .textCase(.uppercase)
                    .foregroundStyle(activo ? LiquidColor.tinta900 : LiquidColor.tinta500)
                Circle()
                    .fill(activo ? LiquidColor.tinta900 : Color.clear)
                    .frame(width: 4, height: 4)
            }
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(activo ? .isSelected : [])
        .accessibilityLabel(Text(texto))
    }
}

// MARK: - Previews

#Preview("Conmutador · Cosmos activo") {
    StatefulPreview(modo: .cosmos)
}

#Preview("Conmutador · Matriz activa") {
    StatefulPreview(modo: .matriz)
}

private struct StatefulPreview: View {
    @State var modo: HoyModo
    var body: some View {
        HoyModoConmutador(modo: $modo, rotuloCosmos: "Cosmos", rotuloMatriz: "Matriz")
            .padding()
            .background(LiquidColor.papelMatriz)
    }
}
