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
// Contrato: strings YA localizados y datos YA resueltos (el DS no conoce locales).

public struct LiquidDobleDato: View {
    private let principal: (valor: String, etiqueta: String)
    private let secundario: (valor: String, etiqueta: String)
    private let tono: Color

    public init(principal: (valor: String, etiqueta: String),
                secundario: (valor: String, etiqueta: String),
                tono: Color) {
        self.principal = principal
        self.secundario = secundario
        self.tono = tono
    }

    /// «··» = regularidad sin base todavía: el numeral habla en tinta, no en el tono.
    private var sinBase: Bool { secundario.valor == "··" }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: LiquidSpace.s400) {
            columna(valor: principal.valor, etiqueta: principal.etiqueta,
                    fuente: LiquidType.numeralHoja, color: tono)
            // El hairline apoya su base en la MISMA línea que los numerales (una vista
            // sin texto usa su borde inferior como baseline); 26 ≈ la altura de caja del
            // numeral principal — geometría interna del componente, no un token.
            Rectangle()
                .fill(LiquidColor.tinta10)
                .frame(width: 1, height: 26)
            columna(valor: secundario.valor, etiqueta: secundario.etiqueta,
                    fuente: LiquidType.valorL,
                    color: sinBase ? LiquidColor.tinta500 : tono)
        }
        .accessibilityElement(children: .combine)
    }

    private func columna(valor: String, etiqueta: String,
                         fuente: Font, color: Color) -> some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s100) {
            Text(verbatim: valor)
                .font(fuente)
                .foregroundStyle(color)
            Text(verbatim: etiqueta)
                .font(LiquidType.microEstado)
                .textCase(.uppercase)
                .foregroundStyle(LiquidColor.tinta500)
        }
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
    }
    .padding(LiquidSpace.s550)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(LiquidSheetFondo(tone: LiquidColor.indigo))
}
#endif
