import SwiftUI

// MARK: - Liquid Glass · Tarjeta de regularidad de sueño (épico hoja Liquid, F4a)
//
// Slot opcional de la hoja de Sueño: el puntaje 0–100 de regularidad (cuánto se mueve
// el punto medio de sueño noche a noche) con su propia ⓘ y una leyenda que traduce el
// número. Papel OPACO (`.superficieSolida`) — tarjetas internas de la hoja no muestrean
// el backdrop (fix de raíz de la reconstrucción de las 9 sheets).
//
// Sin medidor 0–100: el numeral manda (paridad prototipo `sheet-sueno-final.html`); la
// valencia la lleva la `leyenda`, no el color. Con `puntaje == nil` se pinta «··» en
// tinta/500 (calibrando) — el numeral nunca miente, sin barra fingida.
//
// Contrato: strings YA localizados (el DS no conoce locales). La `explicacion` del ⓘ y
// las etiquetas de VoiceOver del botón llegan del caller.

public struct LiquidRegularityCard: View {
    private let titulo: String
    private let puntaje: Int?
    private let leyenda: String
    private let tono: Color
    private let explicacion: String
    private let infoMostrar: String?
    private let infoOcultar: String?
    private let a11y: String

    @State private var explicacionAbierta = false
    @ScaledMetric(relativeTo: .footnote) private var lecturaSize = LiquidType.lecturaHojaBase

    public init(titulo: String,
                puntaje: Int?,
                leyenda: String,
                tono: Color,
                explicacion: String,
                infoMostrar: String?,
                infoOcultar: String?,
                a11yLabel: String? = nil) {
        self.titulo = titulo
        self.puntaje = puntaje
        self.leyenda = leyenda
        self.tono = tono
        self.explicacion = explicacion
        self.infoMostrar = infoMostrar
        self.infoOcultar = infoOcultar
        self.a11y = a11yLabel
            ?? Self.a11yLabel(titulo: titulo, puntaje: puntaje, leyenda: leyenda)
    }

    /// «{titulo}, {puntaje o «sin dato»}, {leyenda}» — contrato de VoiceOver
    /// (testeable en frío, patrón `LiquidSheetHeader.a11yLabel` / `LiquidStageBar.a11yValue`).
    /// Con `puntaje == nil` la voz dice «sin dato», nunca «··» (dos puntos no significan
    /// nada en VoiceOver). La valencia la lleva la leyenda; el color no habla.
    public static func a11yLabel(titulo: String, puntaje: Int?, leyenda: String) -> String {
        let dato = puntaje.map(String.init) ?? "sin dato"
        return [titulo, dato, leyenda].joined(separator: ", ")
    }

    /// Calibrando: el numeral habla en tinta, no en el tono (mismo gesto que
    /// `LiquidDobleDato` con «··» y el «—» de `LiquidSheetHeader`).
    private var calibrando: Bool { puntaje == nil }

    private var textoPuntaje: String {
        puntaje.map(String.init) ?? "··"
    }

    /// #inject r2 · La leyenda partida en «palabra · detalle»: la palabra-veredicto («Muy
    /// regular») pesa en semibold/tinta900 y el detalle queda en tinta/500 — jerarquía
    /// sin sumar color (el único dato en color es el puntaje). Acepta « · » y « — » como
    /// separador; sin separador, todo es palabra.
    private var leyendaPartes: (palabra: String, detalle: String?) {
        for sep in [" · ", " — "] {
            if let r = leyenda.range(of: sep) {
                return (String(leyenda[..<r.lowerBound]), String(leyenda[r.upperBound...]))
            }
        }
        return (leyenda, nil)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s250) {
            // #inject r4 · Columna de texto a la izquierda (overline + palabra-veredicto)
            // y el puntaje CENTRADO verticalmente contra las dos líneas (dueño: «el 88 más
            // centrado, y subir la palabra — hay un espacio vacío»). La tarjeta ya no deja
            // aire muerto bajo la leyenda.
            HStack(alignment: .center, spacing: LiquidSpace.s200) {
                VStack(alignment: .leading, spacing: LiquidSpace.s100) {
                    // s200 (no s150): el target táctil expandido del ⓘ compacto sobresale
                    // 10 pt de su marco — con 6 pt invadía la cola del título (revisión).
                    HStack(alignment: .center, spacing: LiquidSpace.s200) {
                        Text(verbatim: titulo)
                            .liquidLabel()
                            .foregroundStyle(LiquidColor.tinta500)
                            // El título entra al label compuesto del bloque de dato; no es
                            // parada propia (mismo patrón B3 de `LiquidSheetHeader`).
                            .accessibilityHidden(true)
                        // #inject r2 · ⓘ compacto: a 15 pesaba lo mismo que las letras del
                        // overline y «se leía como una letra más» (dueño). El marco de 24
                        // no infla la fila; el target sigue ~44 (contentShape expandido).
                        LiquidInfoBoton(abierto: $explicacionAbierta,
                                        mostrar: infoMostrar, ocultar: infoOcultar,
                                        rotulo: titulo, alineacion: .leading,
                                        tono: tono, compacto: true)
                    }
                    // Una sola parada de VoiceOver para el bloque de lectura: título +
                    // puntaje + leyenda (el label compuesto vive aquí). Calibrando no
                    // grita: sin puntaje, la leyenda va en peso normal — el semibold es
                    // para la palabra-VEREDICTO (revisión adversarial Grok).
                    (Text(verbatim: leyendaPartes.palabra)
                        .fontWeight(calibrando ? .regular : .semibold)
                        .foregroundStyle(calibrando ? LiquidColor.tinta700 : LiquidColor.tinta900)
                     + Text(verbatim: leyendaPartes.detalle.map { " · \($0)" } ?? "")
                        .foregroundStyle(LiquidColor.tinta500))
                        .font(.system(size: lecturaSize))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(Text(verbatim: a11y))
                }
                Spacer(minLength: LiquidSpace.s200)
                Text(verbatim: textoPuntaje)
                    .font(LiquidType.valorL)
                    .monospacedDigit()
                    .foregroundStyle(calibrando ? LiquidColor.tinta500 : tono)
                    .accessibilityHidden(true)
            }
            if explicacionAbierta {
                // Voz de LECTURA, como el plegado de `LiquidSheetHeader`.
                Text(verbatim: explicacion)
                    .font(.system(size: lecturaSize))
                    .foregroundStyle(LiquidColor.tinta700)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(LiquidSpace.s400)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(.superficieSolida)
        // `.contain` mantiene al ⓘ como elemento accionable aparte. El label compuesto
        // vive en la leyenda (la parada de lectura del bloque).
        .accessibilityElement(children: .contain)
    }
}

#if DEBUG
#Preview("Liquid · RegularityCard") {
    VStack(spacing: LiquidSpace.s400) {
        LiquidRegularityCard(
            titulo: "Regularidad",
            puntaje: 82,
            leyenda: "Muy regular · tu cuerpo sabe cuándo dormir",
            tono: LiquidColor.indigo,
            explicacion: "La regularidad mide cuánto se mueve el punto medio de tu sueño de una noche a otra (entre dormirte y despertar): predice tu salud mejor que las horas totales. Las siestas no cuentan.",
            infoMostrar: "Mostrar explicación",
            infoOcultar: "Ocultar explicación")
        LiquidRegularityCard(
            titulo: "Regularidad",
            puntaje: nil,
            leyenda: "Aún conociendo tu ritmo",
            tono: LiquidColor.indigo,
            explicacion: "Necesitamos varias noches para medir qué tan parejo es tu horario.",
            infoMostrar: "Mostrar explicación",
            infoOcultar: "Ocultar explicación")
    }
    .padding(LiquidSpace.s550)
    .background(LiquidSheetFondo(tone: LiquidColor.indigo))
    .environment(\.liquidMotionDisabled, true)
}

#Preview("Liquid · RegularityCard (AX)") {
    // Tamaño de accesibilidad: apila, no trunca; ⓘ target ≥ 44 pt (lo garantiza
    // `LiquidInfoBoton`).
    LiquidRegularityCard(
        titulo: "Regularidad",
        puntaje: 82,
        leyenda: "Muy regular · tu cuerpo sabe cuándo dormir",
        tono: LiquidColor.indigo,
        explicacion: "La regularidad mide cuánto se mueve el punto medio de tu sueño de una noche a otra (entre dormirte y despertar): predice tu salud mejor que las horas totales. Las siestas no cuentan.",
        infoMostrar: "Mostrar explicación",
        infoOcultar: "Ocultar explicación")
    .padding(LiquidSpace.s550)
    .background(LiquidSheetFondo(tone: LiquidColor.indigo))
    .environment(\.dynamicTypeSize, .accessibility3)
    .environment(\.liquidMotionDisabled, true)
}
#endif
