import SwiftUI

// MARK: - LiquidFlowTitle (FER-293)
//
// Gemelo Liquid de `InstrumentoFlowTitle` para pantallas empujadas sin cabecera de salida
// (Tickets hoy; Historial/Semana cuando les toque). Kicker opcional arriba + título
// `displayS` — mismo orden de lectura que Biblioteca y Detalle. `InstrumentoFlowTitle`
// sigue vivo mientras tenga consumidores (p. ej. WorkoutHistoryScreen).

public struct LiquidFlowTitle: View {
    private let kicker: String?
    private let titulo: String

    public init(kicker: String? = nil, titulo: String) {
        self.kicker = kicker
        self.titulo = titulo
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s075) {
            if let kicker, !kicker.isEmpty {
                Text(verbatim: kicker)
                    .liquidKicker()
                    .foregroundStyle(LiquidColor.tinta700)
            }
            Text(verbatim: titulo)
                .font(LiquidType.displayS)
                .tracking(LiquidType.displaySTracking)
                .foregroundStyle(LiquidColor.tinta900)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

#if DEBUG
#Preview("Liquid · FlowTitle") {
    VStack(alignment: .leading, spacing: LiquidSpace.s550) {
        LiquidFlowTitle(kicker: "7 recibos · toca uno para reimprimir",
                        titulo: "Tickets guardados")
        LiquidFlowTitle(titulo: "Tickets guardados")
        LiquidFlowTitle(kicker: "0 recibos · toca uno para reimprimir",
                        titulo: "Tickets guardados")
    }
    .frame(width: 390, alignment: .leading)
    .padding(LiquidSpace.s600)
    .background(LiquidColor.fondoGradient)
}
#endif
