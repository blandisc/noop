import SwiftUI

// MARK: - Liquid Glass · Lane activa (épico hoja Liquid, F5)
//
// El rótulo de la lane activa sobre el selector de niveles («ÓPTIMO · ANOCHE»): caja alta
// chica con un punto del tono adelante — discreto, es contexto, no un segundo veredicto.
// El texto llega YA compuesto y localizado del caller (paridad
// `MetricInfoSheet.sleepActiveLaneLabel`, FER-710); el color vive en el punto y el texto
// del tono de la métrica, como todo dato Liquid.

public struct LiquidLaneLabel: View {
    private let texto: String
    private let tono: Color

    public init(texto: String, tono: Color) {
        self.texto = texto
        self.tono = tono
    }

    public var body: some View {
        HStack(spacing: LiquidSpace.s150) {
            Circle()
                .fill(tono)
                .frame(width: 4, height: 4)
            Text(verbatim: texto)
                .font(LiquidType.microEstado)
                .textCase(.uppercase)
                .foregroundStyle(tono)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: texto))
    }
}

#if DEBUG
#Preview("Liquid · LaneLabel") {
    VStack(alignment: .leading, spacing: LiquidSpace.s400) {
        LiquidLaneLabel(texto: "ÓPTIMO · ANOCHE", tono: LiquidColor.indigo)
        LiquidLaneLabel(texto: "CORTO · ANOCHE", tono: LiquidColor.atencionTexto)
    }
    .padding(LiquidSpace.s550)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(LiquidSheetFondo(tone: LiquidColor.indigo))
}
#endif
