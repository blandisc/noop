import SwiftUI

// MARK: - Liquid Glass · Tooltip multi-serie (FER-99 · F0b)
//
// La pieza hermana de `LiquidGraficaSuperpuesta`: la tarjeta que lee el punto bajo el dedo
// cuando hay VARIAS series a la vez. Port de `MultiTooltip` (`CompareView.swift:1003`) con
// tokens Liquid puros.
//
// Es una pieza aparte y no un overlay dentro de la gráfica por una razón de contrato: la
// gráfica no formatea fechas (no conoce locales), y el encabezado de este tooltip ES una
// fecha. Separarlos deja a la gráfica muda en copy y al caller dueño de su formato — la misma
// disciplina que resolvió el problema del calendario de papel, que formateaba fechas sin fijar
// time zone y por eso Estrés no pudo reusarlo.
//
// **Una fila por serie, siempre, en el orden que manda el caller** (el mismo de la leyenda).
// Una serie sin lectura ese día imprime «—» en tinta terciaria y NO se omite: esconder la fila
// haría que el tooltip cambiara de alto al pasar por un hueco, y —peor— insinuaría que esa
// métrica no existe en la comparación.
//
// Contrato: `fecha`, `nombre` y `valor` llegan YA formateados y localizados. El componente
// no calcula ni redondea nada.

public struct LiquidTooltipMulti: View {

    /// Una fila del tooltip: el color de identidad de la serie, su nombre y su valor leído,
    /// ambos ya formateados. `valor == nil` = esa serie no tiene lectura en el punto tocado.
    public struct Fila: Identifiable, Sendable {
        public let id: String
        public let color: Color
        public let nombre: String
        public let valor: String?

        public init(id: String, color: Color, nombre: String, valor: String?) {
            self.id = id
            self.color = color
            self.nombre = nombre
            self.valor = valor
        }
    }

    private let fecha: String
    private let filas: [Fila]
    /// Texto para la serie sin lectura. Llega del caller porque «—» es copy, no geometría.
    private let sinLectura: String

    @Environment(\.dynamicTypeSize) private var tamanoTexto

    public init(fecha: String, filas: [Fila], sinLectura: String = "—") {
        self.fecha = fecha
        self.filas = filas
        self.sinLectura = sinLectura
    }

    // MARK: - Geometría interna
    //
    // Del papel (`MultiTooltip`), traducida a tokens donde existe el paso y conservada como
    // constante privada donde no. Ninguno de estos números es una decisión de pantalla: son la
    // spec del componente, igual que `altoBarra` en `LiquidStageBar`.

    /// Diámetro de la gota de identidad de cada serie. El papel usa 7; es el mismo diámetro
    /// del punto del `ChartTooltip` de una sola serie, y mantenerlo hace que las dos lecturas
    /// se reconozcan como parientes.
    private let gotaDiametro: CGFloat = 7
    /// Aire entre la gota de identidad y el nombre de la serie. El papel usa 7, que cae entre
    /// `s150` (6) y `s200` (8); se conserva el valor del papel como geometría interna en vez de
    /// redondearlo a un token, porque es la distancia que ata visualmente el punto a su nombre.
    private let gotaSeparacion: CGFloat = 7
    /// Aire mínimo entre el nombre de la serie y su valor: sin él, un nombre largo y un valor
    /// ancho se tocan y la fila deja de leerse como dos columnas.
    private let separacionMinima: CGFloat = 12
    /// Ancho fijo del papel. Se conserva para que el tooltip no cambie de tamaño al moverse
    /// entre puntos con valores de distinto largo — un tooltip que respira distrae del dato.
    private let anchoBase: CGFloat = 220

    /// En tallas de accesibilidad el ancho fijo estrangula el texto, así que se suelta y la
    /// tarjeta abraza su contenido.
    private var ancho: CGFloat? { tamanoTexto.isAccessibilitySize ? nil : anchoBase }

    public var body: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s125) {
            Text(verbatim: fecha)
                .font(LiquidType.caption)
                .foregroundStyle(LiquidColor.tinta500)

            ForEach(filas) { fila in
                filaVista(fila)
            }
        }
        .padding(LiquidSpace.s250)
        .frame(width: ancho, alignment: .leading)
        .liquidGlass(.superficieSolida)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: fecha))
        .accessibilityValue(Text(verbatim: Self.a11yValor(filas: filas, sinLectura: sinLectura)))
    }

    @ViewBuilder
    private func filaVista(_ fila: Fila) -> some View {
        let contenido = HStack(spacing: gotaSeparacion) {
            Circle()
                .fill(fila.color)
                .frame(width: gotaDiametro, height: gotaDiametro)
                .accessibilityHidden(true)
            Text(verbatim: fila.nombre)
                .font(LiquidType.cuerpo)
                .foregroundStyle(LiquidColor.tinta700)
            Spacer(minLength: separacionMinima)
            Text(verbatim: fila.valor ?? sinLectura)
                .font(LiquidType.valorS)
                .monospacedDigit()
                // Un hueco no se disfraza de dato: baja a tinta terciaria, como el «··» de la
                // regularidad en la hoja de sueño.
                .foregroundStyle(fila.valor == nil ? LiquidColor.tinta500 : LiquidColor.tinta900)
        }

        if tamanoTexto.isAccessibilitySize {
            // A tallas AX la fila se parte en dos renglones en vez de recortar el nombre.
            VStack(alignment: .leading, spacing: LiquidSpace.s050) {
                HStack(spacing: gotaSeparacion) {
                    Circle()
                        .fill(fila.color)
                        .frame(width: gotaDiametro, height: gotaDiametro)
                        .accessibilityHidden(true)
                    Text(verbatim: fila.nombre)
                        .font(LiquidType.cuerpo)
                        .foregroundStyle(LiquidColor.tinta700)
                }
                Text(verbatim: fila.valor ?? sinLectura)
                    .font(LiquidType.valorS)
                    .monospacedDigit()
                    .foregroundStyle(fila.valor == nil ? LiquidColor.tinta500 : LiquidColor.tinta900)
            }
        } else {
            contenido
        }
    }

    // MARK: - Voz (pura, testeable)

    /// Lo que VoiceOver dice del punto leído. Nombra TODAS las series, incluidas las que no
    /// tienen lectura — si las omitiera, el usuario que no ve la tarjeta creería que esa
    /// métrica no está en la comparación.
    static func a11yValor(filas: [Fila], sinLectura: String) -> String {
        filas
            .map { "\($0.nombre) \($0.valor ?? sinLectura)" }
            .joined(separator: ", ")
    }
}

// MARK: - Previews

#if DEBUG
private extension LiquidTooltipMulti.Fila {
    static let ejemplo: [LiquidTooltipMulti.Fila] = [
        .init(id: "hrv", color: LiquidColor.cian, nombre: "VFC", valor: "66 ms"),
        .init(id: "rhr", color: LiquidColor.rosa, nombre: "FC en reposo", valor: "52 lpm"),
        .init(id: "sleep", color: LiquidColor.indigo, nombre: "Sueño", valor: "7:12"),
    ]
}

#Preview("Tooltip multi · 3 series") {
    LiquidTooltipMulti(fecha: "mar 12 ago 2026", filas: LiquidTooltipMulti.Fila.ejemplo)
        .padding(LiquidSpace.s550)
        .background(LiquidColor.papelAlto)
}

#Preview("Tooltip multi · con hueco") {
    LiquidTooltipMulti(
        fecha: "dom 10 ago 2026",
        filas: [
            .init(id: "hrv", color: LiquidColor.cian, nombre: "VFC", valor: "61 ms"),
            .init(id: "rhr", color: LiquidColor.rosa, nombre: "FC en reposo", valor: nil),
            .init(id: "steps", color: LiquidColor.teal, nombre: "Pasos", valor: "8,412"),
        ]
    )
    .padding(LiquidSpace.s550)
    .background(LiquidColor.papelAlto)
}

#Preview("Tooltip multi · 4 series") {
    LiquidTooltipMulti(
        fecha: "lun 11 ago 2026",
        filas: LiquidTooltipMulti.Fila.ejemplo + [
            .init(id: "steps", color: LiquidColor.teal, nombre: "Pasos", valor: "10,204")
        ]
    )
    .padding(LiquidSpace.s550)
    .background(LiquidColor.papelAlto)
}

#Preview("Tooltip multi · AX") {
    LiquidTooltipMulti(fecha: "mar 12 ago 2026", filas: LiquidTooltipMulti.Fila.ejemplo)
        .padding(LiquidSpace.s550)
        .background(LiquidColor.papelAlto)
        .dynamicTypeSize(.accessibility3)
}
#endif
