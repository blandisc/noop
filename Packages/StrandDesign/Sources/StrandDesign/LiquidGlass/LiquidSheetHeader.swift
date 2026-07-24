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
    /// Interno (no `private`) a propósito: es el contrato de VoiceOver de la cabecera y el
    /// único punto donde se ve que el `init` compone el label con TODAS sus piezas — el
    /// defecto C1 fue justo que el `init` no pasaba el sufijo, algo que un test de la
    /// función estática no puede atrapar.
    let a11y: String

    @State private var explicacionAbierta = false
    @ScaledMetric(relativeTo: .footnote) private var explicacionSize = LiquidType.lecturaHojaBase
    @Environment(\.dynamicTypeSize) private var tamanoTexto

    /// `icono == nil` = recovery (sin glifo). `numeral == nil` = la variante rica de sueño
    /// (el doble dato reemplaza al numeral). `explicacion == nil` = sin ⓘ.
    /// `origen == .medido` NO pinta punto (QA F1-D2, deliberado): lo medido se dice con
    /// `origenEtiqueta` («Apple Salud · anoche»); el punto es solo para lo CALCULADO.
    ///
    /// L5 · a11y del ⓘ: `infoMostrar`/`infoOcultar` son la etiqueta de VoiceOver del botón
    /// («Mostrar explicación» / «Ocultar explicación»), YA localizadas por el caller — el DS
    /// no conoce locales. Si llegan `nil` el label cae al rótulo del dato, para que ningún
    /// caller sin migrar pierda su a11y en silencio.
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
                                                unidad: unidad, sufijo: sufijo,
                                                origen: origenEtiqueta)
    }

    /// L5 · Dynamic Type: en tamaños grandes la fila del numeral deja de truncar y envuelve
    /// (la que desborda es la etiqueta de origen, no el numeral).
    ///
    /// B4 · el umbral baja de AX a `.xxLarge`: con `.xxLarge`/`.xxxLarge` —tamaños que NO
    /// son de accesibilidad y que mucha gente usa— «Apple Salud · anoche» ya no cabía y se
    /// truncaba con «…» en vez de envolver.
    private var limiteNumeral: Int? {
        tamanoTexto >= .xxLarge ? nil : 1
    }

    /// B1 · ¿hay procedencia que pintar? El punto solo marca lo CALCULADO (ver `init`), así
    /// que `origen == .medido` sin etiqueta no dibuja nada y no merece su propia fila.
    ///
    /// Y el punto SIN etiqueta tampoco: un bullet suelto colgando detrás del numeral
    /// («10.0 / 21 ·») no dice «calculado», dice «aquí falta algo» — así salió en el render
    /// de esfuerzo. El punto es la puntuación de la palabra, no un dato por su cuenta; sin
    /// palabra no se pinta.
    private var hayProcedencia: Bool {
        origenEtiqueta != nil
    }

    /// B1 · La procedencia («· Apple Salud»), que hasta ahora vivía DENTRO de la fila del
    /// numeral. Se compone aparte para poder emitirla también cuando no hay numeral.
    /// `inline` = va detrás del dato (necesita el respiro que la separa de la unidad);
    /// suelta arranca en el margen, alineada con el título.
    @ViewBuilder private func procedencia(inline: Bool) -> some View {
        if origen == .calculado, origenEtiqueta != nil {
            LiquidOrigenDot()
        }
        if let origenEtiqueta {
            Text(origenEtiqueta)
                .font(LiquidType.captionLectura)
                .foregroundStyle(LiquidColor.tinta500)
                .padding(.leading, inline ? LiquidSpace.s100 : 0)
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s150) {
            HStack(spacing: LiquidSpace.s150) {
                if let icono {
                    LiquidIconDrop(icono, tone: tono)
                }
                // El nombre de la métrica manda más (pedido del dueño /inject): sube del
                // rótulo chico al título del sistema, en tinta plena.
                // Grande pero QUIETO (pasada UI H3): caja alta + tracking + tinta900 lo
                // volvían un banner que le ganaba el foco al dato. El numeral manda.
                Text(titulo)
                    .font(LiquidType.tituloHoja)
                    .foregroundStyle(LiquidColor.tinta700)
                    // B3 · con numeral, el título ya va DENTRO del label compuesto de la
                    // fila del dato («VFC, 56 ms, Apple Salud», que empieza por él):
                    // dejarlo como parada propia lo dice dos veces. Sin numeral, esta ES
                    // la primera parada y carga el label compuesto entero.
                    .accessibilityHidden(numeral != nil)
                    .accessibilityLabel(Text(verbatim: a11y))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if explicacion != nil {
                    LiquidInfoBoton(abierto: $explicacionAbierta,
                                    mostrar: infoMostrar, ocultar: infoOcultar,
                                    rotulo: titulo, alineacion: .trailing,
                                    tono: tono)
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
                    procedencia(inline: true)
                }
                .lineLimit(limiteNumeral)
                // B3 · el dato dominante es UNA sola parada de VoiceOver: numeral, unidad,
                // sufijo y procedencia son fragmentos de la misma frase, no cuatro paradas.
                // `.ignore` sí fusiona (`.contain` del contenedor NO lo hacía, y encima
                // anteponía la etiqueta del grupo ⇒ el dato se oía dos veces).
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: a11y))
                .accessibilityAddTraits(.isHeader)
            } else if hayProcedencia {
                // B1 · La variante rica de sueño pasa `numeral: nil`, y con la procedencia
                // atrapada dentro del `if let numeral` la hoja NO mostraba de dónde salía
                // el dato mientras VoiceOver sí lo decía. Aquí baja a su propia fila.
                // Muda para VoiceOver: el título de arriba ya lo dice en su label.
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    procedencia(inline: false)
                }
                .accessibilityHidden(true)
            }
            if explicacionAbierta, let explicacion {
                // Voz de LECTURA, no de caption (pasada UX H3): era el texto más largo
                // de la hoja pintado con la tipografía más chica.
                Text(explicacion)
                    .font(.system(size: explicacionSize))
                    .foregroundStyle(LiquidColor.tinta700)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        // B3 · `.contain` mantiene al ⓘ como elemento accionable aparte. El label compuesto
        // NO va aquí: en un contenedor `.contain` se antepone a la primera parada real y
        // duplicaba el dato. Vive en la parada que de verdad lo dice (fila del numeral, o
        // el título cuando no hay numeral).
        .accessibilityElement(children: .contain)
    }

    /// «{titulo}, {numeral} {unidad} {sufijo}[, {origen}]» — contrato de VoiceOver
    /// (testeable en frío).
    ///
    /// C1 · El `sufijo` («/ 21», «/ 100») entra al label. La hoja vieja lo tenía como `Text`
    /// suelto —una parada fea, pero la escala SÍ se oía—; al fusionar la fila del dato en una
    /// sola parada (`children: .ignore`) el denominador se perdía y VoiceOver decía «Esfuerzo
    /// del día, 10.0, Calculado» sobre una pantalla que muestra «10.0 / 21».
    /// Va con valor por omisión: los callers que no tienen sufijo no cambian.
    ///
    /// C2 · Con `numeral == "—"` el CUERPO ya oculta unidad y sufijo; la voz los seguía
    /// concatenando y decía «VFC, — ms» sobre una pantalla que solo muestra «—». Mismo guard.
    static func a11yLabel(titulo: String, numeral: String?, unidad: String?,
                          sufijo: String? = nil, origen: String?) -> String {
        var parts = [titulo]
        if let numeral {
            var dato = numeral
            if numeral != "—" {
                if let unidad { dato += " \(unidad)" }
                if let sufijo { dato += " \(sufijo)" }
            }
            parts.append(dato)
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
// Contrato: los strings de VoiceOver llegan YA localizados del caller. Sin ellos cae al
// rótulo del dato, nunca inventa copy.
//
// C3 · El estado plegado/desplegado NO se expone con un rasgo: vive en el NOMBRE de la
// acción («Mostrar explicación» ⇄ «Ocultar explicación»), que es el patrón de Apple cuando
// no hay rasgo de expansión. `.isSelected` haría que VoiceOver diga «seleccionado» sobre un
// ⓘ que no es seleccionable, y el único rasgo real de expansión
// (`UIAccessibility.ExpandedStatus`) es iOS 18+ y de UIKit — el mínimo del paquete es
// iOS 17 y `SwiftUI.AccessibilityTraits` no tiene equivalente. Si el mínimo sube a 18,
// reevaluar. Por la misma razón que el pie (`LiquidMetodo`), aquí tampoco hay
// `accessibilityValue` «1»/«0»: VoiceOver leía «VFC, uno», que no significa nada.
struct LiquidInfoBoton: View {
    @Binding var abierto: Bool
    let mostrar: String?
    let ocultar: String?
    /// Rótulo del dato al que pertenece el ⓘ — solo se usa como fallback de VoiceOver.
    let rotulo: String
    var alineacion: Alignment = .trailing
    /// B5 · Tono de la métrica. Con él, el glifo ABIERTO se tiñe (en la hoja vieja el color
    /// ERA el indicador de estado); sin él (default) se queda en tinta/500 en ambos estados,
    /// que es el comportamiento que ya tiene `LiquidDobleDato`.
    var tono: Color? = nil

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
                .foregroundStyle(abierto ? (tono ?? LiquidColor.tinta500) : LiquidColor.tinta500)
                .frame(minWidth: 44, minHeight: 44, alignment: alineacion)
                .contentShape(Rectangle())
        }
        .buttonStyle(.liquidPress)

        boton.accessibilityLabel(Text(verbatim: etiquetaVO ?? rotulo))
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
        // ⓘ sin etiquetas: el label cae al rótulo del dato, mismo target 44.
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

/// B1 · Sin numeral (la variante rica de sueño y su skeleton) la procedencia baja a su
/// propia fila: antes desaparecía de la pantalla mientras VoiceOver la seguía diciendo.
#Preview("Liquid · SheetHeader sin numeral") {
    VStack(alignment: .leading, spacing: LiquidSpace.s800) {
        LiquidSheetHeader(icono: .luna, titulo: "SUEÑO", tono: LiquidColor.indigo,
                          numeral: nil,
                          origenEtiqueta: "Apple Salud",
                          explicacion: "Cuánto y qué tan parejo dormiste anoche.",
                          infoMostrar: "Mostrar explicación",
                          infoOcultar: "Ocultar explicación")
        // Calculado sin numeral: el punto de origen también sobrevive.
        LiquidSheetHeader(icono: .luna, titulo: "SUEÑO", tono: LiquidColor.indigo,
                          numeral: nil, origen: .calculado,
                          origenEtiqueta: "Calculado")
        // Sin procedencia de ningún tipo: no se agrega ninguna fila.
        LiquidSheetHeader(icono: .luna, titulo: "SUEÑO", tono: LiquidColor.indigo,
                          numeral: nil)
    }
    .padding(LiquidSpace.s550)
    .background(LiquidSheetFondo(tone: LiquidColor.indigo))
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

/// B4 · `.xxxLarge` NO es tamaño de accesibilidad: aquí es donde la unidad se quedaba
/// enana junto al numeral y «Apple Salud · anoche» se truncaba con «…».
#Preview("Liquid · SheetHeader xxxLarge") {
    VStack(alignment: .leading, spacing: LiquidSpace.s800) {
        LiquidSheetHeader(icono: .onda, titulo: "VFC", tono: LiquidColor.cian,
                          numeral: "56", unidad: "ms",
                          origenEtiqueta: "Apple Salud · anoche")
        LiquidSheetHeader(icono: nil, titulo: "RECUPERACIÓN", tono: LiquidColor.verdePrimario,
                          numeral: "78", sufijo: "/ 100",
                          numeralTono: LiquidColor.verdeProfundo, origen: .calculado,
                          origenEtiqueta: "Calculado")
    }
    .padding(LiquidSpace.s550)
    .background(LiquidSheetFondo(tone: LiquidColor.cian))
    .environment(\.dynamicTypeSize, .xxxLarge)
}
#endif
