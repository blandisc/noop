import SwiftUI

// MARK: - Liquid Glass · Barras de contribución (port de `ContributionBars`, FER-145)
//
// El desglose de la hoja de Edad corporal («Qué la está moviendo»): una barra divergente
// por factor, que empuja a la IZQUIERDA o a la DERECHA desde un eje cero central, sobre una
// escala COMPARTIDA para que «un año» mida lo mismo en todas las filas. Port de la
// geometría de `ContributionBars` (etiqueta 96 · pista 22 con barra de 14 · eje de 1×16 ·
// número a la derecha) con tokens Liquid puros.
//
// ─────────────────────────────────────────────────────────────────────────────────────────
// CONVENCIÓN DE SIGNO — léela antes de tocar el color, porque es CONTRAINTUITIVA.
//
// `efecto` viene en AÑOS y viene FIRMADO. Menos edad corporal es BUENA noticia, así que
// aquí el número NEGATIVO es el que se celebra:
//
//   · efecto < 0  → te QUITA años  → `LiquidColor.positivo` (verde) · barra a la IZQUIERDA
//   · efecto > 0  → te SUMA años   → `LiquidColor.atencion` (ámbar) · barra a la DERECHA
//   · efecto ≈ 0  → no te está moviendo → `LiquidColor.tinta500`, sin barra
//
// Un factor que te quita años y uno que te suma NO pueden verse igual: es lo único que
// convierte la lista en una lectura. Y el signo viaja por TRES canales —largo de la barra,
// LADO del eje y el número firmado— así que la lectura sobrevive al daltonismo: el lado ya
// codifica el signo sin depender del hue.
//
// Un factor con `efecto == 0` SE MUESTRA. «Esto no te está moviendo» también es
// información; esconderlo dejaría al usuario creyendo que la señal no se midió.
// ─────────────────────────────────────────────────────────────────────────────────────────
//
// El color vive SOLO en la barra y en su número; el eje cero, la etiqueta y las columnas
// van en tinta. `maximo` lo manda el CALLER —no se deriva del máximo local— para que la
// escala sea estable entre sesiones: si cada visita normalizara contra su propio pico, el
// mismo factor mediría distinto cada día y la barra dejaría de ser comparable consigo misma.
//
// Contrato: `etiqueta` y `detalle` («−1.2 años») llegan YA localizados y formateados, igual
// que `a11yLabel` / `a11yValue` — el DS no conoce catálogo, locales ni formato numérico.
// Pásale los factores YA ordenados (típicamente por |efecto| descendente).

public struct LiquidBarrasContribucion: View {

    /// La contribución de UN factor, en años. Ver la convención de signo, arriba.
    public struct Factor: Identifiable, Sendable {
        public let id: String
        /// El nombre del factor, YA localizado («VO₂max», «FC en reposo»).
        public let etiqueta: String
        /// Años FIRMADOS: negativo te quita edad, positivo te la suma.
        public let efecto: Double
        /// El número YA formateado («−1.2 años»). `nil` deja la columna vacía —el signo lo
        /// siguen contando el largo y el lado de la barra—; el DS no formatea números.
        public let detalle: String?

        public init(id: String, etiqueta: String, efecto: Double, detalle: String? = nil) {
            self.id = id
            self.etiqueta = etiqueta
            self.efecto = efecto
            self.detalle = detalle
        }
    }

    /// Los dos rótulos de polo, YA localizados («← te rejuvenece» / «te envejece →»).
    ///
    /// **No son decorativos: son el eje.** En una gráfica divergente sin eje rotulado,
    /// izquierda y derecha dejan de significar algo, y la cabecera de esta pieza presume que
    /// «el LADO ya codifica el signo sin depender del hue». Sin los polos, ese canal es
    /// indescifrable — y para quien no distingue verde de ámbar, es el ÚNICO canal.
    /// El original de papel los dibuja una vez sobre las barras y el caller real los pasa.
    private let poloIzquierdo: String
    private let poloDerecho: String
    private let factores: [Factor]
    private let maximo: Double
    private let a11y: String
    private let a11yVal: String

    /// A tallas de accesibilidad las dos columnas fijas ahogan a la pista: ahí la fila se
    /// APILA (etiqueta arriba, pista + número abajo) en vez de recortar el texto.
    @Environment(\.dynamicTypeSize) private var tamanoTexto
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.liquidMotionDisabled) private var motionDisabled
    @State private var crecida = false

    /// La etiqueta escala con Dynamic Type (el patrón que `LiquidType.cuerpoLecturaBase`
    /// publica y que ya usa `LiquidLevelRow`): con una fuente fija, a tallas AX el nombre
    /// del factor acababa más chico que el número que lo acompaña.
    @ScaledMetric(relativeTo: .footnote)
    private var etiquetaPt: CGFloat = LiquidType.cuerpoLecturaBase

    // MARK: Geometría portada de `ContributionBars`
    //
    // Las dos columnas laterales son FIJAS a propósito: lo que hace legible un gráfico
    // divergente es que el eje cero caiga en la MISMA x en todas las filas (Cleveland-McGill:
    // posición sobre un eje común). Una columna que se ajusta a su contenido movería el eje
    // fila por fila y rompería justo eso.

    /// Ancho de la columna de la etiqueta (96 en el papel).
    private let anchoEtiqueta: CGFloat = 96
    /// Ancho de la columna del número. Sube del 40 del papel porque aquí el caller manda la
    /// cifra CON unidad («−1.2 años»), no un `%+.1f` pelón.
    private let anchoDetalle: CGFloat = 64
    /// Alto de la pista y de la barra dentro de ella.
    private let altoPista: CGFloat = 22
    private let altoBarra: CGFloat = 14
    /// El eje cero: 1 pt de ancho, 16 de alto (asoma un punto por arriba y por abajo de la
    /// barra, para que se lea como referencia y no como una barra más).
    private let grosorEje: CGFloat = 1
    private let altoEje: CGFloat = 16

    /// - Parameters:
    ///   - factores: YA ordenados por el caller. Los de `efecto == 0` SE PINTAN.
    ///   - maximo: el tope |años| de la escala compartida. Lo manda el caller para que la
    ///     escala sea estable entre sesiones; el componente no normaliza contra su máximo local.
    ///   - a11yLabel: qué es esto, para VoiceOver.
    ///   - a11yValue: qué dice hoy — obligatorio: esto es una gráfica.
    public init(factores: [Factor], maximo: Double,
                poloIzquierdo: String, poloDerecho: String,
                a11yLabel: String, a11yValue: String) {
        self.poloIzquierdo = poloIzquierdo
        self.poloDerecho = poloDerecho
        self.factores = factores
        self.maximo = maximo
        self.a11y = a11yLabel
        self.a11yVal = a11yValue
    }

    // MARK: Contrato del signo (puro, testeable en frío)

    /// Zona muerta del signo: por debajo de ±0.05 años el efecto se imprime como «0.0», así
    /// que teñirlo de verde o de ámbar afirmaría una dirección que el número visible no
    /// respalda. Umbral portado de `ContributionBars`.
    static let zonaMuerta: Double = 0.05

    /// El color de un efecto según su SIGNO. Ver la convención de la cabecera.
    static func tono(para efecto: Double) -> Color {
        if efecto < -zonaMuerta { return LiquidColor.positivo }   // te quita años
        if efecto > zonaMuerta { return LiquidColor.atencion }    // te suma años
        return LiquidColor.tinta500                                // no te está moviendo
    }

    /// Fracción 0…1 del semi-ancho que ocupa la barra, contra el `maximo` del CALLER. Un
    /// efecto mayor que el máximo se clampea (la barra llena su mitad, no se desborda); con
    /// `maximo <= 0` no hay escala y no se dibuja barra alguna.
    static func fraccion(efecto: Double, maximo: Double) -> Double {
        guard maximo > 0 else { return 0 }
        return min(1, abs(efecto) / maximo)
    }

    private var apilado: Bool { tamanoTexto.isAccessibilitySize }

    // MARK: Cuerpo

    /// El eje de la gráfica divergente: qué significa cada lado. Se dibuja UNA vez, arriba.
    private var polos: some View {
        HStack(spacing: LiquidSpace.s200) {
            Text(verbatim: poloIzquierdo)
            Spacer(minLength: LiquidSpace.s300)
            Text(verbatim: poloDerecho)
        }
        .font(LiquidType.captionLectura)
        .foregroundStyle(LiquidColor.tinta500)
        .accessibilityHidden(true)   // el valor del bloque ya dice el signo de cada factor
    }

    public var body: some View {
        // Sin factores el bloque no dibuja nada (ni inventa un vacío): es el CALLER quien
        // decide no pintar la sección cuando no hay desglose que mostrar.
        VStack(alignment: .leading, spacing: LiquidSpace.s250) {
            polos
            ForEach(factores) { fila($0) }
        }
        .onAppear {
            guard !crecida else { return }
            if motionDisabled || reduceMotion {
                crecida = true
            } else {
                withAnimation(LiquidMotion.ringProgress) { crecida = true }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: a11y))
        .accessibilityValue(Text(verbatim: a11yVal))
    }

    @ViewBuilder
    private func fila(_ factor: Factor) -> some View {
        if apilado {
            VStack(alignment: .leading, spacing: LiquidSpace.s100) {
                etiqueta(factor)
                HStack(spacing: LiquidSpace.s250) {
                    pista(factor)
                    detalle(factor).fixedSize()
                }
            }
        } else {
            // Baseline compartida entre la etiqueta y el número (misma familia que
            // `LiquidChecklistRow` / `LiquidCajita`): a `.center` los dos textos, de tamaños
            // distintos, no compartían línea. La pista (barra de 22 pt, sin texto) alinea su
            // fondo a esa baseline, como la marca de `LiquidChecklistRow`. (FER-105 · T8)
            HStack(alignment: .firstTextBaseline, spacing: LiquidSpace.s250) {
                etiqueta(factor).frame(width: anchoEtiqueta, alignment: .leading)
                pista(factor)
                detalle(factor).frame(width: anchoDetalle, alignment: .trailing)
            }
        }
    }

    private func etiqueta(_ factor: Factor) -> some View {
        Text(verbatim: factor.etiqueta)
            .font(.system(size: etiquetaPt, weight: .semibold))
            .foregroundStyle(LiquidColor.tinta900)
            .lineLimit(apilado ? nil : 1)
            .minimumScaleFactor(0.85)
    }

    /// El número, teñido por el mismo signo que la barra. Sin `detalle` la columna queda
    /// vacía pero RESERVADA: mover el ancho movería el eje cero de esa fila.
    private func detalle(_ factor: Factor) -> some View {
        Text(verbatim: factor.detalle ?? "")
            .font(LiquidType.captionLectura)
            .monospacedDigit()
            .foregroundStyle(Self.tono(para: factor.efecto))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    private func pista(_ factor: Factor) -> some View {
        let fraccion = Self.fraccion(efecto: factor.efecto, maximo: maximo)
        let color = Self.tono(para: factor.efecto)
        let haciaLaIzquierda = factor.efecto < 0
        return GeometryReader { geo in
            let medio = geo.size.width / 2
            let cy = geo.size.height / 2
            let ancho = medio * CGFloat(crecida ? fraccion : 0)
            ZStack(alignment: .topLeading) {
                // Eje cero — «el promedio para tu edad». Referencia en tinta, nunca teñida.
                Rectangle().fill(LiquidColor.tinta10)
                    .frame(width: grosorEje, height: altoEje)
                    .position(x: medio, y: cy)
                // La barra, creciendo del eje hacia su polo.
                Capsule().fill(color)
                    .frame(width: ancho, height: altoBarra)
                    .position(x: haciaLaIzquierda ? medio - ancho / 2 : medio + ancho / 2, y: cy)
            }
        }
        .frame(height: altoPista)
    }
}

#if DEBUG
/// Los seis factores del motor, con uno EN CERO a propósito (Sueño): la fila se pinta,
/// en tinta y sin barra — «esto no te está moviendo» es información.
private let factoresDemo: [LiquidBarrasContribucion.Factor] = [
    .init(id: "vo2", etiqueta: "VO₂max", efecto: -1.8, detalle: "−1.8 años"),
    .init(id: "fc", etiqueta: "FC en reposo", efecto: -1.4, detalle: "−1.4 años"),
    .init(id: "vfc", etiqueta: "VFC", efecto: -0.6, detalle: "−0.6 años"),
    .init(id: "sueno", etiqueta: "Sueño", efecto: 0, detalle: "0.0 años"),
    .init(id: "pasos", etiqueta: "Pasos", efecto: 0.3, detalle: "+0.3 años"),
    .init(id: "regularidad", etiqueta: "Regularidad", efecto: 0.9, detalle: "+0.9 años"),
]

#Preview("Liquid · Barras de contribución (con datos)") {
    LiquidBarrasContribucion(
        factores: factoresDemo, maximo: 2,
        poloIzquierdo: "← te rejuvenece",
        poloDerecho: "te envejece →",
        a11yLabel: "Qué la está moviendo",
        a11yValue: "VO₂max te quita 1.8 años; FC en reposo, 1.4; VFC, 0.6. "
            + "Sueño no te mueve. Pasos te suma 0.3 años y Regularidad, 0.9.")
    .padding(LiquidSpace.s550)
    .background(LiquidSheetFondo(tone: LiquidColor.positivo))
}

/// Caso extremo: un factor que se pasa del `maximo` del caller (se clampea a media pista, no
/// se desborda) y otro sin `detalle` (la columna del número queda vacía pero reservada — el
/// signo lo siguen contando el largo y el lado).
#Preview("Liquid · Barras de contribución (tope y sin número)") {
    LiquidBarrasContribucion(
        factores: [
            .init(id: "vo2", etiqueta: "VO₂max", efecto: -4.6, detalle: "−4.6 años"),
            .init(id: "pasos", etiqueta: "Pasos", efecto: 0.7),
            .init(id: "sueno", etiqueta: "Sueño", efecto: 0, detalle: "0.0 años"),
        ],
        maximo: 2,
        poloIzquierdo: "← te rejuvenece",
        poloDerecho: "te envejece →",
        a11yLabel: "Qué la está moviendo",
        a11yValue: "VO₂max te quita 4.6 años; Pasos te suma 0.7. Sueño no te mueve.")
    .padding(LiquidSpace.s550)
    .background(LiquidSheetFondo(tone: LiquidColor.positivo))
}

/// Sin factores: el bloque no dibuja nada y no inventa un vacío. Es el caller quien decide
/// no pintar la sección cuando no hay desglose.
#Preview("Liquid · Barras de contribución (sin factores)") {
    LiquidBarrasContribucion(
        factores: [], maximo: 2,
        poloIzquierdo: "← te rejuvenece",
        poloDerecho: "te envejece →",
        a11yLabel: "Qué la está moviendo",
        a11yValue: "Todavía sin desglose")
    .padding(LiquidSpace.s550)
    .background(LiquidSheetFondo())
}

#Preview("Liquid · Barras de contribución (AX)") {
    LiquidBarrasContribucion(
        factores: factoresDemo, maximo: 2,
        poloIzquierdo: "← te rejuvenece",
        poloDerecho: "te envejece →",
        a11yLabel: "Qué la está moviendo",
        a11yValue: "VO₂max te quita 1.8 años; FC en reposo, 1.4; VFC, 0.6. "
            + "Sueño no te mueve. Pasos te suma 0.3 años y Regularidad, 0.9.")
    .padding(LiquidSpace.s550)
    .background(LiquidSheetFondo(tone: LiquidColor.positivo))
    .environment(\.dynamicTypeSize, .accessibility3)
}
#endif
