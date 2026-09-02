import SwiftUI

// MARK: - Liquid Glass · Barra de conteo (FER-129, «Preparación»)
//
// Una fila [gota con glifo · rótulo · barra · «N d»] que cuenta CUÁNTAS VECES pasó algo en una
// ventana: «FC en reposo se salió 7 de 30 noches». Varias filas comparten UNA escala, que
// manda el caller (la ventana), para que se comparen entre sí de un vistazo.
//
// POR QUÉ NO ES `LiquidBarraMarca`: aquella normaliza POR FILA a propósito —«cada etapa se
// compara consigo misma, no con la de al lado»— y aquí la comparación ENTRE filas es justo
// la lectura («¿cuál de mis señales se sale más?»). Forzarla habría sido usar mal un token
// que ya significa otra cosa. POR QUÉ NO ES `LiquidBarrasContribucion`: aquella es
// divergente con eje cero (un efecto puede ser negativo); un conteo nunca lo es.
//
// `nil` y `0` NO son lo mismo (la lección de `LiquidBarrasDeuda`): `conteo == nil` = no se
// pudo contar (riel vacío, sin barra); `0` = se contó y fue cero (barra a cero, visible como
// pista llena del color del track). Un cero honesto no se esconde.
//
// El color es el de IDENTIDAD de la señal (rosa FC · índigo Sueño · doradoTemp el par) —
// la barra dice «cuál», el veredicto lo dice el mosaico. Nunca el ámbar/rojo de juicio.
//
// Contrato D3: `rotulo`, `valorTexto`, `a11yLabel`/`a11yValue` llegan YA localizados.

public struct LiquidBarraConteo: View {

    private let glifo: LiquidIcon.Glyph?
    private let rotulo: String
    private let conteo: Int?
    private let escala: Int
    private let tono: Color
    private let valorTexto: String
    private let indice: Int
    private let a11yLabel: String
    private let a11yValor: String

    @Environment(\.dynamicTypeSize) private var tamanoTexto

    // MARK: Geometría interna (de la pieza, no del sistema)

    /// Alto de la cápsula, 10 pt — el mismo que `LiquidBarraMarca`: son filas hermanas de
    /// la misma familia de listas, no el retrato de una noche (12, `LiquidStageBar`).
    private static let altoBarra: CGFloat = 10
    /// La gota del glifo: la MISMA receta que la fila de `LiquidBoletaCard` (28, ícono 14,
    /// lavado al 7 %), para que el piso «hoy» y el piso «el mes» de una misma sección alineen
    /// su columna de gotas. Si aquella cambia, esta debe cambiar con ella.
    private static let gota: CGFloat = 28
    private static let glifoLado: CGFloat = 14
    private static let gotaAlfa: Double = 0.07
    /// Ancho fijo del rótulo para que las barras de todas las filas arranquen en la misma
    /// vertical: sin él, «Sueño» y «Temp y respiración» dejan barras de distinto origen y
    /// la escala compartida deja de leerse.
    private static let anchoRotulo: CGFloat = 104

    /// - Parameters:
    ///   - conteo: las veces que pasó. `nil` = no se pudo contar (distinto de 0).
    ///   - escala: el tope COMPARTIDO de todas las filas (la ventana). Lo manda el caller.
    ///   - valorTexto: el número ya formateado con su unidad («7 d»).
    public init(glifo: LiquidIcon.Glyph? = nil,
                rotulo: String,
                conteo: Int?,
                escala: Int,
                tono: Color,
                valorTexto: String,
                indice: Int = 0,
                a11yLabel: String,
                a11yValue: String) {
        self.glifo = glifo
        self.rotulo = rotulo
        self.conteo = conteo
        self.escala = escala
        self.tono = tono
        self.valorTexto = valorTexto
        self.indice = indice
        self.a11yLabel = a11yLabel
        self.a11yValor = a11yValue
    }

    // MARK: - Contratos puros (los mismos que leen la vista y la prueba)

    /// Fracción del ancho que llena la barra. `nil` sin conteo; 0 con conteo cero; clampeada
    /// a 1 porque un conteo nunca puede superar la ventana que lo contiene.
    public static func fraccion(conteo: Int?, escala: Int) -> Double? {
        guard let conteo, escala > 0 else { return nil }
        return min(1, max(0, Double(conteo) / Double(escala)))
    }

    /// Arma el valor de VoiceOver con piezas YA localizadas («7 de 30 noches»).
    public static func a11yValue(conteo: String, escala: String) -> String {
        "\(conteo) " + escala
    }

    // MARK: - Cuerpo

    public var body: some View {
        Group {
            if tamanoTexto.isAccessibilitySize {
                // A tallas AX el rótulo se va a su renglón: en una fila, «Temp y respiración»
                // inflado exprimía la barra hasta desaparecer.
                VStack(alignment: .leading, spacing: LiquidSpace.s100) {
                    HStack(spacing: LiquidSpace.s250) { gotaVista; rotuloVista }
                    HStack(spacing: LiquidSpace.s250) { barra; valor }
                }
            } else {
                HStack(spacing: LiquidSpace.s250) {
                    gotaVista
                    rotuloVista.frame(width: Self.anchoRotulo, alignment: .leading)
                    barra
                    valor
                }
            }
        }
        .liquidEntrada(index: indice)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: a11yLabel))
        .accessibilityValue(Text(verbatim: a11yValor))
    }

    @ViewBuilder private var gotaVista: some View {
        if let glifo {
            LiquidIconDrop(glifo, tone: tono, size: Self.gota,
                           iconSize: Self.glifoLado, fillAlpha: Self.gotaAlfa)
        }
    }

    private var rotuloVista: some View {
        Text(verbatim: rotulo)
            .font(LiquidType.cuerpo)
            .foregroundStyle(LiquidColor.tinta900)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
    }

    private var barra: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(LiquidColor.tinta7)
                    .frame(height: Self.altoBarra)
                if let f = Self.fraccion(conteo: conteo, escala: escala) {
                    Capsule(style: .continuous)
                        .fill(tono)
                        .frame(width: max(f > 0 ? Self.altoBarra : 0, geo.size.width * CGFloat(f)),
                               height: Self.altoBarra)
                }
            }
        }
        .frame(height: Self.altoBarra)
    }

    private var valor: some View {
        Text(verbatim: valorTexto)
            .font(LiquidType.valorM)
            .foregroundStyle(conteo == nil ? LiquidColor.tinta500 : LiquidColor.tinta900)
            .monospacedDigit()
            .frame(minWidth: 44, alignment: .trailing)
    }
}

#if DEBUG
#Preview("Liquid · Barra de conteo") {
    VStack(alignment: .leading, spacing: LiquidSpace.s250) {
        LiquidBarraConteo(glifo: .corazon, rotulo: "FC en reposo", conteo: 7, escala: 30,
                          tono: LiquidColor.rosa, valorTexto: "7 d", indice: 0,
                          a11yLabel: "FC en reposo", a11yValue: "7 de 30 noches fuera")
        LiquidBarraConteo(glifo: .luna, rotulo: "Sueño", conteo: 4, escala: 30,
                          tono: LiquidColor.indigo, valorTexto: "4 d", indice: 1,
                          a11yLabel: "Sueño", a11yValue: "4 de 30 noches fuera")
        LiquidBarraConteo(glifo: .termo, rotulo: "Temp y respiración", conteo: 0, escala: 30,
                          tono: LiquidColor.doradoTemp, valorTexto: "0 d", indice: 2,
                          a11yLabel: "Temperatura y respiración", a11yValue: "0 de 30 noches fuera")
        LiquidBarraConteo(glifo: .onda, rotulo: "Sin contar", conteo: nil, escala: 30,
                          tono: LiquidColor.cian, valorTexto: "—", indice: 3,
                          a11yLabel: "Sin contar", a11yValue: "sin dato")
    }
    .padding(LiquidSpace.s550)
    .background(LiquidColor.fondoGradient)
}

#Preview("Liquid · Barra de conteo · AX3") {
    VStack(alignment: .leading, spacing: LiquidSpace.s250) {
        LiquidBarraConteo(glifo: .corazon, rotulo: "FC en reposo", conteo: 7, escala: 30,
                          tono: LiquidColor.rosa, valorTexto: "7 d",
                          a11yLabel: "FC en reposo", a11yValue: "7 de 30 noches fuera")
    }
    .padding(LiquidSpace.s550)
    .background(LiquidColor.fondoGradient)
    .environment(\.dynamicTypeSize, .accessibility3)
}
#endif
