import SwiftUI

// MARK: - Liquid Glass · Resumen de ventana (FER-33 F2a)
//
// Pie de la tarjeta de grafica: Promedio · Rango · Hoy en columnas separadas por
// capilares, bajo un hairline. No es tocable: describe lo que la grafica de arriba
// ya dibujo. Sin superficie propia: se apila DENTRO de la tarjeta.
//
// Por que NO es LiquidColumna: esa es un Button con action obligatorio, hit target
// de 44 pt y haptica de press. Un pie de tarjeta no es tocable; usarlo mentiria con
// affordance de boton y sumaria 44 pt por columna.

/// Resumen de la ventana visible en una grafica de hoja: 2 o 3 cifras en columnas
/// iguales, separadas por `LiquidCapilar`, bajo un hairline. El caller formatea y
/// localiza; el DS solo pinta.
public struct LiquidResumenVentana: View {
    public struct Celda: Sendable {
        /// Rotulo corto en versalitas («Promedio»), YA localizado.
        public let rotulo: String
        /// La cifra YA formateada por el caller («1.03», «0.90-1.66»). El DS no formatea numeros.
        public let valor: String
        /// `nil` = tinta quieta. Non-nil = la celda destacada (tipicamente «Hoy»), en el tono.
        public let tono: Color?

        public init(rotulo: String, valor: String, tono: Color? = nil) {
            self.rotulo = rotulo
            self.valor = valor
            self.tono = tono
        }
    }

    private let celdas: [Celda]
    private let a11yLabel: String?

    /// 2 o 3 celdas separadas por `LiquidCapilar`, bajo un hairline.
    /// SIN superficie propia: se apila DENTRO de la tarjeta de la grafica.
    public init(celdas: [Celda], a11yLabel: String? = nil) {
        self.celdas = celdas
        self.a11yLabel = a11yLabel
    }

    private var resolvedA11y: String {
        if let a11yLabel { return a11yLabel }
        return celdas.map { "\($0.rotulo), \($0.valor)" }.joined(separator: ", ")
    }

    public var body: some View {
        // s250 (~10) alinea con el padding-top del prototipo (11 px) entre hairline y fila.
        VStack(alignment: .leading, spacing: LiquidSpace.s250) {
            Rectangle()
                .fill(LiquidColor.tinta10)
                .frame(height: 1)
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(celdas.enumerated()), id: \.offset) { index, celda in
                    columna(celda)
                    if index < celdas.count - 1 {
                        LiquidCapilar()
                    }
                }
            }
            // El capilar crece con maxHeight: .infinity; sin fixedSize se come la fila
            // (misma trampa cazada en el Tablero).
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: resolvedA11y))
    }

    private func columna(_ celda: Celda) -> some View {
        VStack(spacing: LiquidSpace.s100) {
            Text(celda.rotulo)
                .font(LiquidType.label)
                .tracking(LiquidType.labelTracking)
                .textCase(.uppercase)
                .foregroundStyle(LiquidColor.tinta500)
            Text(celda.valor)
                // #inject r5 · `valorM` (17), no `valorL` (22): el tri-stat es contexto
                // secundario, no compite con el numeral héroe (pedido del dueño).
                .font(LiquidType.valorM)
                .monospacedDigit()
                .foregroundStyle(celda.tono ?? LiquidColor.tinta700)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity)
    }
}

#if DEBUG
#Preview("Liquid · ResumenVentana") {
    VStack(alignment: .leading, spacing: LiquidSpace.s550) {
        // (a) Carga: tres celdas; Hoy en verde.
        LiquidResumenVentana(celdas: [
            .init(rotulo: "Promedio", valor: "1.06"),
            .init(rotulo: "Rango", valor: "0.90-1.66"),
            .init(rotulo: "Hoy", valor: "1.03", tono: LiquidColor.verdePrimario),
        ])
        // (b) Solo dos celdas.
        LiquidResumenVentana(celdas: [
            .init(rotulo: "Promedio", valor: "1.06"),
            .init(rotulo: "Hoy", valor: "1.03", tono: LiquidColor.verdePrimario),
        ])
        // (c) Rango largo: no se parte ni desnivela el trio.
        LiquidResumenVentana(celdas: [
            .init(rotulo: "Promedio", valor: "1.06"),
            .init(rotulo: "Rango", valor: "0.1234-12.5678"),
            .init(rotulo: "Hoy", valor: "1.03", tono: LiquidColor.verdePrimario),
        ])
    }
    .padding(LiquidSpace.s550)
    .background(LiquidSheetFondo(tone: LiquidColor.verdePrimario))
}
#endif
