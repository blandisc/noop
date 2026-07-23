import SwiftUI

// MARK: - Liquid Glass · Cabecera de hoja de resumen (épico hoja Liquid, F1)
//
// La cabecera ÚNICA de todas las variantes de la hoja: gota del icono (24, mismo átomo que
// los tiles) + rótulo en caja alta + ⓘ que pliega/despliega la explicación, y debajo el
// DATO héroe (`numeralHoja`) con unidad, sufijo («/ 100») y el punto de origen con su
// etiqueta. Reemplaza al header bifurcado de MetricInfoSheet en el cutover F6.
//
// Contrato (LIQUID-SHEET-CONTRACT §3): strings YA localizados, datos YA resueltos; el
// `numeralTono` lo decide el caller (banda/neutral/hue) — el DS no opina del dato.
// D3 (revote Grok): la etiqueta de origen es copy honesto Apple-only del caller
// («Apple Salud · anoche»), nunca el legado «Band».

public struct LiquidSheetHeader: View {
    private let icono: LiquidIcon.Glyph?
    private let titulo: String
    private let tono: Color
    private let numeral: String?
    private let unidad: String?
    private let sufijo: String?
    private let numeralTono: Color
    private let origen: LiquidOrigen?
    private let origenEtiqueta: String?
    private let explicacion: String?
    private let a11y: String

    @State private var explicacionAbierta = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// `icono == nil` = recovery (sin glifo). `numeral == nil` = la variante rica de sueño
    /// (el doble dato reemplaza al numeral). `explicacion == nil` = sin ⓘ.
    public init(icono: LiquidIcon.Glyph?, titulo: String, tono: Color,
                numeral: String?, unidad: String? = nil, sufijo: String? = nil,
                numeralTono: Color? = nil, origen: LiquidOrigen? = nil,
                origenEtiqueta: String? = nil, explicacion: String? = nil,
                a11yLabel: String? = nil) {
        self.icono = icono
        self.titulo = titulo
        self.tono = tono
        self.numeral = numeral
        self.unidad = unidad
        self.sufijo = sufijo
        self.numeralTono = numeralTono ?? tono
        self.origen = origen
        self.origenEtiqueta = origenEtiqueta
        self.explicacion = explicacion
        self.a11y = a11yLabel ?? Self.a11yLabel(titulo: titulo, numeral: numeral,
                                                unidad: unidad, origen: origenEtiqueta)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s150) {
            HStack(spacing: LiquidSpace.s150) {
                if let icono {
                    LiquidIconDrop(icono, tone: tono)
                }
                Text(titulo).liquidLabel().foregroundStyle(LiquidColor.tinta500)
                Spacer()
                if explicacion != nil {
                    Button {
                        if reduceMotion {
                            explicacionAbierta.toggle()
                        } else {
                            withAnimation(LiquidMotion.lift) { explicacionAbierta.toggle() }
                        }
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 15))
                            .foregroundStyle(LiquidColor.tinta500)
                    }
                    .buttonStyle(.liquidPress)
                    .accessibilityLabel(Text(verbatim: titulo))
                    .accessibilityValue(Text(verbatim: explicacionAbierta ? "1" : "0"))
                }
            }
            if let numeral {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(numeral)
                        .font(LiquidType.numeralHoja)
                        .foregroundStyle(numeral == "—" ? LiquidColor.tinta500 : numeralTono)
                    if let unidad, numeral != "—" {
                        Text(unidad)
                            .font(LiquidType.numeralHojaUnidad)
                            .foregroundStyle(LiquidColor.tinta500)
                    }
                    if let sufijo, numeral != "—" {
                        Text(sufijo)
                            .font(LiquidType.numeralHojaUnidad)
                            .foregroundStyle(LiquidColor.tinta500)
                    }
                    if origen == .calculado {
                        LiquidOrigenDot()
                    }
                    if let origenEtiqueta {
                        Text(origenEtiqueta)
                            .font(LiquidType.captionLectura)
                            .foregroundStyle(LiquidColor.tinta500)
                            .padding(.leading, LiquidSpace.s100)
                    }
                }
                .lineLimit(1)
            }
            if explicacionAbierta, let explicacion {
                Text(explicacion)
                    .font(LiquidType.captionLectura)
                    .foregroundStyle(LiquidColor.tinta700)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: a11y))
        .accessibilityAddTraits(.isHeader)
    }

    /// «{titulo}, {numeral} {unidad}[, {origen}]» — contrato de VoiceOver (testeable en frío).
    static func a11yLabel(titulo: String, numeral: String?, unidad: String?,
                          origen: String?) -> String {
        var parts = [titulo]
        if let numeral {
            parts.append(unidad.map { "\(numeral) \($0)" } ?? numeral)
        }
        if let origen { parts.append(origen) }
        return parts.joined(separator: ", ")
    }
}

#if DEBUG
#Preview("Liquid · SheetHeader") {
    VStack(alignment: .leading, spacing: LiquidSpace.s800) {
        LiquidSheetHeader(icono: .onda, titulo: "VFC", tono: LiquidColor.cian,
                          numeral: "56", unidad: "ms",
                          origenEtiqueta: "Apple Salud · anoche",
                          explicacion: "La variación entre latidos mientras duermes — tu señal más temprana de recuperación.")
        LiquidSheetHeader(icono: nil, titulo: "RECUPERACIÓN", tono: LiquidColor.verdePrimario,
                          numeral: "78", sufijo: "/ 100",
                          numeralTono: LiquidColor.verdeProfundo, origen: .calculado,
                          explicacion: "Qué tan listo amaneció tu cuerpo.")
        LiquidSheetHeader(icono: .llama, titulo: "ESFUERZO", tono: LiquidColor.ambar,
                          numeral: "10.0", origen: .calculado)
        LiquidSheetHeader(icono: .corazon, titulo: "FC EN REPOSO", tono: LiquidColor.rosa,
                          numeral: "—")
    }
    .padding(LiquidSpace.s550)
    .background(LiquidSheetFondo(tone: LiquidColor.cian))
}
#endif
