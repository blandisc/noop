import SwiftUI

// MARK: - Liquid Glass · MetricTile (handoff §5.1)
//
// Tile de métrica del grid de Hoy. vidrio/superficie (r/tarjeta, e/0) → columna gap 3:
// [gota 22 + label] · [valor 20 SG700 en TONO + unidad 11 tinta/500] · [delta caption].
// El tono tiñe SOLO gota y valor — nunca el fondo.

public struct LiquidMetricTile: View {
    private let label: String
    private let value: String
    private let unit: String
    private let delta: String
    private let deltaTone: LiquidDeltaTone
    private let tone: Color
    private let icon: LiquidIcon.Glyph
    private let action: (() -> Void)?

    public init(label: String, value: String, unit: String = "", delta: String,
                deltaTone: LiquidDeltaTone = .neutral, tone: Color, icon: LiquidIcon.Glyph,
                action: (() -> Void)? = nil) {
        self.label = label
        self.value = value
        self.unit = unit
        self.delta = delta
        self.deltaTone = deltaTone
        self.tone = tone
        self.icon = icon
        self.action = action
    }

    public var body: some View {
        if let action {
            Button(action: action) { content }
                .buttonStyle(.liquidPress)
                .liquidLift(tone: tone)
        } else {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: LiquidSpace.s150) {
                LiquidIconDrop(icon, tone: tone)
                Text(label).liquidLabel().foregroundStyle(LiquidColor.tinta500)
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(LiquidType.valorL).foregroundStyle(tone)
                if !unit.isEmpty {
                    Text(unit).font(LiquidType.unidad).foregroundStyle(LiquidColor.tinta500)
                }
            }
            .lineLimit(1)
            LiquidDeltaCaption(delta, tone: deltaTone)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, LiquidSpace.s300)
        .frame(maxWidth: .infinity, minHeight: 66, alignment: .topLeading)
        .liquidGlass(.superficie)
    }
}

#if DEBUG
#Preview("Liquid · MetricTile") {
    LazyVGrid(columns: [GridItem(.flexible(), spacing: LiquidSpace.s200), GridItem(.flexible())],
              spacing: LiquidSpace.s200) {
        LiquidMetricTile(label: "SUEÑO", value: "7:20", delta: "En tu base",
                         tone: LiquidColor.indigo, icon: .luna)
        LiquidMetricTile(label: "HRV", value: "56", unit: "ms", delta: "+2 ms vs tu base",
                         deltaTone: .up, tone: LiquidColor.cian, icon: .onda)
        LiquidMetricTile(label: "FC EN REPOSO", value: "52", unit: "lpm", delta: "En tu base",
                         tone: LiquidColor.rosa, icon: .corazon)
        LiquidMetricTile(label: "ESFUERZO", value: "10.0", delta: "−0.7 vs tu base",
                         deltaTone: .down, tone: LiquidColor.ambar, icon: .llama, action: {})
    }
    .padding(LiquidSpace.s550)
    .background(LiquidColor.papelGradient)
}
#endif
