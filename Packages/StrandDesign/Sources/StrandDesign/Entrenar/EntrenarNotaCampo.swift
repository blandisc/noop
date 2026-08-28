import SwiftUI

// MARK: - EntrenarNotaCampo — el contenedor de nota (FER-197 · Ola 1)
//
// El editor de `NoteSheet` re-vestido: `TextEditor` INTACTO (nunca envuelto en `LiquidMetricSheet`
// ni en ningún cascarón — REGLA DURA del épico) dentro de un marco de papel opaco con borde
// teñido por `tono` y su placeholder propio. El binding de texto es del caller; este componente
// no sabe de historial ni de alcance (ejercicio/serie), solo dibuja el campo.

public struct EntrenarNotaCampo: View {
    @Binding private var texto: String
    private let placeholder: String
    private let tono: EntrenarTono

    public init(texto: Binding<String>, placeholder: String, tono: EntrenarTono = .ambar) {
        self._texto = texto
        self.placeholder = placeholder
        self.tono = tono
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            if texto.isEmpty {
                Text(placeholder)
                    .font(LiquidType.cuerpo)
                    .foregroundStyle(LiquidColor.tinta500)
                    .padding(.horizontal, LiquidSpace.s300)
                    .padding(.vertical, LiquidSpace.s300)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $texto)
                .font(LiquidType.cuerpo)
                .foregroundStyle(LiquidColor.tinta900)
                .scrollContentBackground(.hidden)
                .tint(tono.base)
                .padding(LiquidSpace.s200)
        }
        .frame(minHeight: EntrenarNotaCampoMetrics.altoMinimo)
        .liquidGlass(.superficieSolida)
        .overlay {
            RoundedRectangle(cornerRadius: LiquidRadius.tarjeta, style: .continuous)
                .strokeBorder(tono.base, lineWidth: EntrenarNotaCampoMetrics.bordeGrosor)
        }
    }
}

private enum EntrenarNotaCampoMetrics {
    static let altoMinimo: CGFloat = 100
    static let bordeGrosor: CGFloat = 1.5
}

#if DEBUG
#Preview("EntrenarNotaCampo · vacío y con texto") {
    VStack(spacing: LiquidSpace.s400) {
        EntrenarNotaCampo(texto: .constant(""),
                          placeholder: "Anota algo para la próxima: cómo se sintió, técnica, un ajuste de carga…",
                          tono: .ambar)
        EntrenarNotaCampo(texto: .constant("Se sintió pesado en la última serie, bajar 2,5 kg."),
                          placeholder: "Anota algo para la próxima…", tono: .ambar)
    }
    .padding(LiquidSpace.s550)
    .entrenarHojaFondo(tono: .ambar)
}
#endif
