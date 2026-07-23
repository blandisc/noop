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
    private let origen: LiquidOrigen
    private let a11yValencia: String?
    private let a11yOrigen: String?
    private let action: (() -> Void)?

    public init(label: String, value: String, unit: String = "", delta: String,
                deltaTone: LiquidDeltaTone = .neutral, tone: Color, icon: LiquidIcon.Glyph,
                origen: LiquidOrigen = .medido, a11yValencia: String? = nil,
                a11yOrigen: String? = nil, action: (() -> Void)? = nil) {
        self.label = label
        self.value = value
        self.unit = unit
        self.delta = delta
        self.deltaTone = deltaTone
        self.tone = tone
        self.icon = icon
        self.origen = origen
        self.a11yValencia = a11yValencia
        self.a11yOrigen = a11yOrigen
        self.action = action
    }

    public var body: some View {
        if let action {
            Button(action: action) { content }
                .buttonStyle(.liquidPress)
                .liquidLift(tone: tone)
                .accessibilityLabel(Self.a11yLabel(label: label, value: value,
                                                   unit: unit, delta: delta,
                                                   valencia: a11yValencia))
                .accessibilityValue(Text(verbatim: a11yOrigen ?? ""))
        } else {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Self.a11yLabel(label: label, value: value,
                                                   unit: unit, delta: delta,
                                                   valencia: a11yValencia))
                .accessibilityValue(Text(verbatim: a11yOrigen ?? ""))
        }
    }

    /// «{label}, {value} {unit}, {delta}[, {valencia}]» — el contrato de VoiceOver del
    /// tile; la valencia hace audible lo que el color solo muestra (pasada UX).
    static func a11yLabel(label: String, value: String, unit: String, delta: String,
                          valencia: String? = nil) -> String {
        let valor = unit.isEmpty ? value : "\(value) \(unit)"
        let base = "\(label), \(valor), \(delta)"
        return valencia.map { "\(base), \($0)" } ?? base
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
            HStack(spacing: LiquidSpace.s100) {
                LiquidDeltaCaption(delta, tone: deltaTone)
                if origen == .calculado {
                    LiquidOrigenDot()
                }
            }
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
