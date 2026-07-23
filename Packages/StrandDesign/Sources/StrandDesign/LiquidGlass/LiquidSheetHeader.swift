import SwiftUI

// MARK: - Liquid Glass · Cabecera de hoja de resumen (épico hoja Liquid, F1)
//
// La cabecera ÚNICA de todas las variantes de la hoja: gota del icono (24, mismo átomo que
// los tiles) + rótulo en caja alta + ⓘ opcional, y debajo el DATO héroe (`numeralHoja` en el
// tono de la métrica) con su unidad y el punto de origen. Reemplaza al header bifurcado de
// MetricInfoSheet (isRedesignedHeader) en el cutover F6.
//
// Contrato: strings YA localizados (el DS no conoce locales); datos ya resueltos.

public struct LiquidSheetHeader: View {
    private let icon: LiquidIcon.Glyph
    private let label: String
    private let value: String
    private let unit: String
    private let tone: Color
    private let origen: LiquidOrigen
    private let origenA11y: String?
    private let onInfo: (() -> Void)?

    /// `value == "—"` = sin dato: el numeral baja a tinta/500 (el tono no miente).
    public init(icon: LiquidIcon.Glyph, label: String, value: String, unit: String = "",
                tone: Color, origen: LiquidOrigen = .medido, origenA11y: String? = nil,
                onInfo: (() -> Void)? = nil) {
        self.icon = icon
        self.label = label
        self.value = value
        self.unit = unit
        self.tone = tone
        self.origen = origen
        self.origenA11y = origenA11y
        self.onInfo = onInfo
    }

    private var sinDato: Bool { value == "—" }

    public var body: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s150) {
            HStack(spacing: LiquidSpace.s150) {
                LiquidIconDrop(icon, tone: sinDato ? LiquidColor.tinta500 : tone)
                Text(label).liquidLabel().foregroundStyle(LiquidColor.tinta500)
                Spacer()
                if let onInfo {
                    Button(action: onInfo) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 15))
                            .foregroundStyle(LiquidColor.tinta500)
                    }
                    .buttonStyle(.liquidPress)
                    .accessibilityLabel(Text(verbatim: label))
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(LiquidType.numeralHoja)
                    .foregroundStyle(sinDato ? LiquidColor.tinta500 : tone)
                if !unit.isEmpty && !sinDato {
                    Text(unit)
                        .font(LiquidType.numeralHojaUnidad)
                        .foregroundStyle(LiquidColor.tinta500)
                }
                if origen == .calculado {
                    LiquidOrigenDot()
                }
            }
            .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isHeader)
        .accessibilityLabel(Self.a11yLabel(label: label, value: value, unit: unit,
                                           origen: origenA11y))
    }

    /// «{label}, {value} {unit}[, {origen}]» — contrato de VoiceOver (testeable en frío).
    static func a11yLabel(label: String, value: String, unit: String,
                          origen: String?) -> String {
        let valor = unit.isEmpty ? value : "\(value) \(unit)"
        let base = "\(label), \(valor)"
        return origen.map { "\(base), \($0)" } ?? base
    }
}

#if DEBUG
#Preview("Liquid · SheetHeader") {
    VStack(alignment: .leading, spacing: LiquidSpace.s800) {
        LiquidSheetHeader(icon: .onda, label: "VFC", value: "56", unit: "ms",
                          tone: LiquidColor.cian, onInfo: {})
        LiquidSheetHeader(icon: .luna, label: "SUEÑO", value: "7:20",
                          tone: LiquidColor.indigo, onInfo: {})
        LiquidSheetHeader(icon: .llama, label: "ESFUERZO", value: "10.0",
                          tone: LiquidColor.ambar, origen: .calculado,
                          origenA11y: "calculado en tu teléfono")
        LiquidSheetHeader(icon: .corazon, label: "FC EN REPOSO", value: "—",
                          tone: LiquidColor.rosa)
    }
    .padding(LiquidSpace.s550)
    .background(LiquidSheetFondo(tone: LiquidColor.cian))
}
#endif
