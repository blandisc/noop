import SwiftUI

// MARK: - Liquid Glass · Doble dato de sueño (épico hoja Liquid, F5)
//
// Los dos numerales héroe de la hoja de sueño — horas dormido | regularidad /100 —
// separados por un hairline vertical, con las bases de texto ALINEADAS
// (`firstTextBaseline`): el principal manda en `numeralHoja` (34 tabular) al tono de la
// métrica; el secundario baja UN escalón a `valorL` (22 tabular) — no a `datoMenor` (15),
// que es la voz de micro-valores de orbes/carga y dejaría a la regularidad leyendo como
// chrome cuando es el segundo dato de la hoja. Las etiquetas van en caja alta chica
// (`microEstado`, que escala con Dynamic Type: la etiqueta explica el dato, se LEE) en
// tinta/500.
//
// El secundario acepta «··» (regularidad aún sin base): ahí el numeral baja a tinta/500
// — el numeral nunca miente (paridad `MetricInfoSheet.sleepDobleDato`, FER-710). Mismo
// gesto que el «—» de `LiquidSheetHeader`.
//
// L5 · el secundario puede traer su propio ⓘ (`secundarioInfo`): el mismo botón del
// sistema que la cabecera (`LiquidInfoBoton`, 44×44), que despliega la explicación DEBAJO
// del par de numerales. Vive como HERMANO de la columna, no dentro de ella: con 44 pt
// metidos en la fila del rótulo la columna crecía ~31 pt y rompía la línea base común.
//
// Contrato: strings YA localizados y datos YA resueltos (el DS no conoce locales).

public struct LiquidDobleDato: View {
    private let principal: (valor: String, etiqueta: String)
    private let secundario: (valor: String, etiqueta: String)
    private let tono: Color
    private let secundarioInfo: String?
    private let secundarioA11y: String?
    private let infoMostrar: String?
    private let infoOcultar: String?

    @State private var infoAbierta = false

    /// L5 · `secundarioInfo` = explicación desplegable del segundo dato (sin ella no hay ⓘ).
    /// `secundarioA11y` = lo que VoiceOver dice EN LUGAR del valor pintado — para que «··»
    /// se lea como la frase honesta del caller («aún sin base»), nunca como dos puntos.
    /// `infoMostrar`/`infoOcultar` son la etiqueta del botón; sin ellas el ⓘ conserva el
    /// contrato viejo (label = rótulo del secundario + value «1»/«0»).
    public init(principal: (valor: String, etiqueta: String),
                secundario: (valor: String, etiqueta: String),
                tono: Color,
                secundarioInfo: String? = nil,
                secundarioA11y: String? = nil,
                infoMostrar: String? = nil,
                infoOcultar: String? = nil) {
        self.principal = principal
        self.secundario = secundario
        self.tono = tono
        self.secundarioInfo = secundarioInfo
        self.secundarioA11y = secundarioA11y
        self.infoMostrar = infoMostrar
        self.infoOcultar = infoOcultar
    }

    /// «··» = regularidad sin base todavía: el numeral habla en tinta, no en el tono.
    private var sinBase: Bool { secundario.valor == "··" }

    private var colorSecundario: Color {
        sinBase ? LiquidColor.tinta500 : tono
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s300) {
            HStack(alignment: .firstTextBaseline, spacing: LiquidSpace.s400) {
                columna(valor: principal.valor, etiqueta: principal.etiqueta,
                        fuente: LiquidType.numeralHoja, color: tono, valorA11y: nil)
                // El hairline apoya su base en la MISMA línea que los numerales (una vista
                // sin texto usa su borde inferior como baseline); 26 ≈ la altura de caja del
                // numeral principal — geometría interna del componente, no un token.
                Rectangle()
                    .fill(LiquidColor.tinta10)
                    .frame(width: 1, height: 26)
                // Pedido del dueño (/inject): el secundario mide LO MISMO que el principal
                // y va centrado sobre su rótulo; así los dos rótulos caen al mismo nivel.
                columna(valor: secundario.valor, etiqueta: secundario.etiqueta,
                        fuente: LiquidType.numeralHoja, color: colorSecundario,
                        valorA11y: secundarioA11y, alineacion: .center)
                if secundarioInfo != nil {
                    LiquidInfoBoton(abierto: $infoAbierta,
                                    mostrar: infoMostrar, ocultar: infoOcultar,
                                    rotulo: secundario.etiqueta, alineacion: .leading)
                        // El botón no tiene línea base propia (una vista sin texto usaría su
                        // borde inferior y flotaría muy arriba): se centra en la base de los
                        // numerales, y así sus 44 pt caben en el alto que ya tenía la fila.
                        .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] }
                }
            }
            .accessibilityElement(children: .contain)
            if infoAbierta, let secundarioInfo {
                Text(verbatim: secundarioInfo)
                    .font(LiquidType.captionLectura)
                    .foregroundStyle(LiquidColor.tinta700)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Un dato = UN elemento de VoiceOver («7:12, horas dormido»): la junta la hace
    /// `children: .combine`, no un separador acuñado aquí (el DS no escribe copy).
    private func columna(valor: String, etiqueta: String, fuente: Font,
                         color: Color, valorA11y: String?,
                         alineacion: HorizontalAlignment = .leading) -> some View {
        VStack(alignment: alineacion, spacing: LiquidSpace.s100) {
            Text(verbatim: valor)
                .font(fuente)
                .foregroundStyle(color)
                .accessibilityLabel(Text(verbatim: valorA11y ?? valor))
            Text(verbatim: etiqueta)
                .font(LiquidType.microEstado)
                .textCase(.uppercase)
                .foregroundStyle(LiquidColor.tinta500)
        }
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview("Liquid · DobleDato") {
    VStack(alignment: .leading, spacing: LiquidSpace.s800) {
        // Con regularidad medida.
        LiquidDobleDato(principal: (valor: "7:12", etiqueta: "horas dormido"),
                        secundario: (valor: "84", etiqueta: "regularidad"),
                        tono: LiquidColor.indigo)
        // Regularidad aún sin base: «··» en tinta (el numeral nunca miente).
        LiquidDobleDato(principal: (valor: "6:48", etiqueta: "horas dormido"),
                        secundario: (valor: "··", etiqueta: "regularidad"),
                        tono: LiquidColor.indigo)
        // L5 · con ⓘ en el secundario: explicación desplegable + a11y honesto del «··».
        LiquidDobleDato(principal: (valor: "7:12", etiqueta: "horas dormido"),
                        secundario: (valor: "84", etiqueta: "regularidad"),
                        tono: LiquidColor.indigo,
                        secundarioInfo: "Qué tan parejo es tu horario de sueño: tomamos el centro de cada noche (entre dormirte y despertar) y medimos cuánto brinca de noche a noche. Menos brincos, más cerca de 100.",
                        infoMostrar: "Mostrar explicación",
                        infoOcultar: "Ocultar explicación")
        LiquidDobleDato(principal: (valor: "6:48", etiqueta: "horas dormido"),
                        secundario: (valor: "··", etiqueta: "regularidad"),
                        tono: LiquidColor.indigo,
                        secundarioInfo: "Necesitamos siete noches para medir qué tan parejo es tu horario.",
                        secundarioA11y: "aún sin base",
                        infoMostrar: "Mostrar explicación",
                        infoOcultar: "Ocultar explicación")
    }
    .padding(LiquidSpace.s550)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(LiquidSheetFondo(tone: LiquidColor.indigo))
}
#endif
