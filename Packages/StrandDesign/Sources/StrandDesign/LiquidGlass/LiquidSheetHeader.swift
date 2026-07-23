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
    private let infoMostrar: String?
    private let infoOcultar: String?
    private let a11y: String

    @State private var explicacionAbierta = false
    @Environment(\.dynamicTypeSize) private var tamanoTexto

    /// `icono == nil` = recovery (sin glifo). `numeral == nil` = la variante rica de sueño
    /// (el doble dato reemplaza al numeral). `explicacion == nil` = sin ⓘ.
    /// `origen == .medido` NO pinta punto (QA F1-D2, deliberado): lo medido se dice con
    /// `origenEtiqueta` («Apple Salud · anoche»); el punto es solo para lo CALCULADO.
    ///
    /// L5 · a11y del ⓘ: `infoMostrar`/`infoOcultar` son la etiqueta de VoiceOver del botón
    /// («Mostrar explicación» / «Ocultar explicación»), YA localizadas por el caller — el DS
    /// no conoce locales. Si llegan `nil` se conserva el contrato viejo (label = rótulo +
    /// value «1»/«0»), para que ningún caller sin migrar pierda su a11y en silencio.
    public init(icono: LiquidIcon.Glyph?, titulo: String, tono: Color,
                numeral: String?, unidad: String? = nil, sufijo: String? = nil,
                numeralTono: Color? = nil, origen: LiquidOrigen? = nil,
                origenEtiqueta: String? = nil, explicacion: String? = nil,
                infoMostrar: String? = nil, infoOcultar: String? = nil,
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
        self.infoMostrar = infoMostrar
        self.infoOcultar = infoOcultar
        self.a11y = a11yLabel ?? Self.a11yLabel(titulo: titulo, numeral: numeral,
                                                unidad: unidad, origen: origenEtiqueta)
    }

    /// L5 · Dynamic Type: en tamaños de accesibilidad la fila del numeral deja de truncar y
    /// envuelve (la que desborda es la etiqueta de origen, no el numeral).
    private var limiteNumeral: Int? {
        tamanoTexto.isAccessibilitySize ? nil : 1
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s150) {
            HStack(spacing: LiquidSpace.s150) {
                if let icono {
                    LiquidIconDrop(icono, tone: tono)
                }
                // El nombre de la métrica manda más (pedido del dueño /inject): sube del
                // rótulo chico al título del sistema, en tinta plena.
                Text(titulo)
                    .font(LiquidType.titulo).tracking(LiquidType.labelTracking)
                    .textCase(.uppercase)
                    .foregroundStyle(LiquidColor.tinta900)
                Spacer()
                if explicacion != nil {
                    LiquidInfoBoton(abierto: $explicacionAbierta,
                                    mostrar: infoMostrar, ocultar: infoOcultar,
                                    rotulo: titulo, alineacion: .trailing)
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
                .lineLimit(limiteNumeral)
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

// MARK: - Liquid Glass · ⓘ del sistema (L5)
//
// El único ⓘ de las hojas: glifo de 15 en tinta/500 sobre un target de 44×44 (HIG mínimo),
// que pliega/despliega la explicación con `LiquidMotion.lift` y respeta Reduce Motion.
// El área táctil crece hacia el interior del layout (`alineacion` ancla el GLIFO al borde
// que ya ocupaba), así que el ⓘ no se mueve de su sitio al ganar los 44 pt.
//
// Contrato: los strings de VoiceOver llegan YA localizados del caller. Sin ellos conserva
// el contrato viejo (label = rótulo del dato + value «1»/«0»), nunca inventa copy.
struct LiquidInfoBoton: View {
    @Binding var abierto: Bool
    let mostrar: String?
    let ocultar: String?
    /// Rótulo del dato al que pertenece el ⓘ — solo se usa como fallback de VoiceOver.
    let rotulo: String
    var alineacion: Alignment = .trailing

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var etiquetaVO: String? {
        abierto ? (ocultar ?? mostrar) : (mostrar ?? ocultar)
    }

    private func alternar() {
        if reduceMotion {
            abierto.toggle()
        } else {
            withAnimation(LiquidMotion.lift) { abierto.toggle() }
        }
    }

    var body: some View {
        let boton = Button {
            alternar()
        } label: {
            Image(systemName: "info.circle")
                .font(LiquidType.infoGlifo)
                .foregroundStyle(LiquidColor.tinta500)
                .frame(minWidth: 44, minHeight: 44, alignment: alineacion)
                .contentShape(Rectangle())
        }
        .buttonStyle(.liquidPress)

        if let etiquetaVO {
            boton.accessibilityLabel(Text(verbatim: etiquetaVO))
        } else {
            boton.accessibilityLabel(Text(verbatim: rotulo))
                .accessibilityValue(Text(verbatim: abierto ? "1" : "0"))
        }
    }
}

#if DEBUG
#Preview("Liquid · SheetHeader") {
    VStack(alignment: .leading, spacing: LiquidSpace.s800) {
        // ⓘ con etiquetas de VoiceOver del caller (L5) — el estado migrado.
        LiquidSheetHeader(icono: .onda, titulo: "VFC", tono: LiquidColor.cian,
                          numeral: "56", unidad: "ms",
                          origenEtiqueta: "Apple Salud · anoche",
                          explicacion: "La variación entre latidos mientras duermes — tu señal más temprana de recuperación.",
                          infoMostrar: "Mostrar explicación",
                          infoOcultar: "Ocultar explicación")
        // ⓘ sin etiquetas: contrato viejo (label = rótulo, value 1/0), mismo target 44.
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

/// L5 · en tamaños AX la fila del numeral envuelve en vez de truncar la etiqueta de origen.
#Preview("Liquid · SheetHeader AX") {
    LiquidSheetHeader(icono: .onda, titulo: "VFC", tono: LiquidColor.cian,
                      numeral: "56", unidad: "ms",
                      origenEtiqueta: "Apple Salud · anoche",
                      explicacion: "La variación entre latidos mientras duermes.",
                      infoMostrar: "Mostrar explicación",
                      infoOcultar: "Ocultar explicación")
        .padding(LiquidSpace.s550)
        .background(LiquidSheetFondo(tone: LiquidColor.cian))
        .environment(\.dynamicTypeSize, .accessibility3)
}
#endif
