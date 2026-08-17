import SwiftUI

// MARK: - La COSTURA del guardián (FER-80 · propuesta C2, elegida por el dueño)
//
// El guardián tiene UNA regla: una señal sola nunca empuja tu día; solo el PAR, dos noches
// seguidas. Hasta ahora la dibujábamos como dos gráficas separadas que jamás se miraban.
// Esta las junta: temperatura arriba (dorado), respiración abajo (azul), espejadas sobre un
// eje común, y lo que se pinta es EL ESPACIO ENTRE LAS DOS.
//
// Por qué esa forma y no otra: la figura hace lo que hace la regla.
//   · Las dos en su sitio  → una costura delgada y serena. No hay nada que decir.
//   · Una se aleja         → se abre de SU lado, en su tono, sin color de alarma (una sola
//                            no vota).
//   · Las dos se van juntas → la boca se abre entera y se tiñe de ámbar: el único día en que
//                            el guardián empuja tu día.
//
// Cada señal se normaliza contra SU PROPIA banda antes de dibujarse (la temperatura tiene un
// corte absoluto en °C; la respiración se juzga contra tu base), así que el ESPESOR es
// comparable entre las dos: 1 = justo en el filo de su banda. Sin eso, la costura mezclaría
// grados con respiraciones por minuto y su ancho no significaría nada.
public struct MatrizCostura: View {
    /// Una noche del par, ya normalizada: 0 = en el centro de tu banda, 1 = en su filo,
    /// >1 = fuera. `nil` = esa señal no se leyó (o no se pudo juzgar) esa noche.
    public struct Noche: Sendable, Equatable {
        public let temp: Double?
        public let resp: Double?
        /// El motor marcó las DOS fuera esa noche: el día que el par vota.
        public let parFuera: Bool
        /// Revisión adversarial P-2: una señal sin magnitud no puede dibujarse como si hubiera
        /// caído en el centro de tu banda. Un hueco es un hueco: su orilla se interrumpe.
        ///
        /// Se DERIVAN del valor, no se reciben: mientras fueron parámetros con default, el tipo
        /// permitía construir `Noche(temp: nil, resp: 0.5)` —bandera en false, valor nil— y esa
        /// noche se dibujaba pegada al eje con su joya encima. La mentira que P-2 mató seguía
        /// siendo representable, esperando al próximo llamador (tercera vuelta adversarial).
        public var tempSinLectura: Bool { temp == nil }
        public var respSinLectura: Bool { resp == nil }

        public init(temp: Double?, resp: Double?, parFuera: Bool = false) {
            self.temp = temp
            self.resp = resp
            self.parFuera = parFuera
        }
    }

    private let chartID: String
    private let noches: [Noche]
    private let hueTemp: Color
    private let hueResp: Color
    private let resaltado: Int?

    public init(chartID: String, noches: [Noche],
                hueTemp: Color = LiquidColor.doradoTemp,
                hueResp: Color = LiquidColor.azul,
                resaltado: Int? = nil) {
        self.chartID = chartID
        self.noches = noches
        self.hueTemp = hueTemp
        self.hueResp = hueResp
        self.resaltado = resaltado
    }

    /// Cuánto se separa del eje, como fracción del medio alto, la noche MÁS extrema que el
    /// dibujo puede representar. Deja aire arriba y abajo: el marco no se rompe nunca.
    private static let filoFrac: CGFloat = 0.58
    /// La separación mínima del eje: la costura nunca se cierra del todo, para que se lea como
    /// un objeto y no como una línea partida.
    private static let labioMin: CGFloat = 2.6
    /// Dónde cae el filo de tu banda por el lado de ADENTRO, y dónde por el de AFUERA.
    ///
    /// El hueco entre los dos (0.17 del recorrido ≈ 3.2 pt) es DELIBERADO y es la pieza que
    /// hace visible una garantía que antes solo era cierta en los números: lo que el motor
    /// marcó fuera se dibuja más lejos del eje que lo que no marcó. Con el mapeo continuo
    /// anterior, esas dos noches quedaban a 0.245 pt una de otra —bajo un trazo de 2.2 pt—,
    /// así que el chip decía «vigilando tu temperatura» y la gráfica no lo respaldaba.
    private static let filoDentro: CGFloat = 0.58
    private static let filoFuera: CGFloat = 0.75
    /// La suavidad de cada tramo (rpm/°C→pixeles).
    private static let kDentro: Double = 0.8
    private static let kFuera: Double = 1.2
    /// Cuánto del recorrido puede ocupar el lado BAJO (por debajo de tu centro).
    private static let ladoBajoFrac: CGFloat = 0.22

    /// Magnitud firmada contra la banda de esa señal → fracción del recorrido del labio [0,1].
    ///
    /// Por tramos, con un salto en el filo. Tres cosas que el mapeo tiene que cumplir a la vez:
    ///
    /// 1. EL MARCO ES INVIOLABLE. Los dos tramos saturan (nunca pasan de 1), así que el labio
    ///    es siempre menor que el medio alto. Recortar en seco —lo que hacía la primera vuelta
    ///    de esta revisión— sacaba la orilla del Canvas y mandaba al mismo pixel una noche de
    ///    17 rpm y una de 25.
    /// 2. EL DIBUJO NO PUEDE CONTRADECIR AL MOTOR. De ahí el hueco: cualquier noche marcada
    ///    fuera cae por encima de `filoFuera` y cualquiera no marcada, por debajo de
    ///    `filoDentro`. **Esto solo se sostiene si el ANCLA del builder sigue viva** (empuja lo
    ///    marcado a ≥1.02 y lo no marcado a ≤0.98): es ella la que mantiene VACÍA la banda
    ///    (0.98, 1.02), y sin ella la escala aproximada de la respiración podría saltar el
    ///    hueco por su cuenta y afirmar «fuera» donde el motor no dijo nada. El ancla no es
    ///    cosmética: es el invariante que hace honesta esta discontinuidad.
    /// 3. EL LADO BAJO EXISTE PERO NO GRITA. El centinela nunca marca una noche fría ni una
    ///    respiración lenta, así que ese lado no puede parecer que te saliste — pero tampoco
    ///    puede desaparecer contra el eje: dos noches distintas jamás se dibujan al mismo alto.
    ///    (Su altura sí comparte rango con la parte baja del lado alto; es ambigüedad entre dos
    ///    estados que NO votan, y el scrub la desambigua con el número.)
    public static func fraccionFilo(_ v: Double) -> CGFloat {
        func dentro(_ x: Double) -> CGFloat {
            let norm = 1 / (1 + kDentro)                    // para que 1 banda = filoDentro
            return filoDentro * CGFloat((x / (x + kDentro)) / norm)
        }
        if v < 0 { return min(dentro(-v), filoDentro) * ladoBajoFrac }
        if v < 1 { return dentro(v) }
        let u = v - 1
        return filoFuera + (1 - filoFuera) * CGFloat(u / (u + kFuera))
    }

    public var body: some View {
        Canvas(rendersAsynchronously: false) { ctx, size in
            let n = noches.count
            guard n > 0, noches.contains(where: { $0.temp != nil || $0.resp != nil }) else {
                MatrizChartDraw.rejillaFantasma(ctx, size: size, chartID: chartID)
                return
            }

            let medio = size.height / 2
            // P-3: el MISMO inset que usa el mapeo del dedo (una sola fuente).
            let inset = MatrizHoyFace.chartInset(.costura(noches: noches))
            func x(_ i: Int) -> CGFloat {
                MatrizChartDraw.xAt(index: i, count: n, width: size.width, inset: inset)
            }
            /// El labio de una señal: su distancia al eje, hacia arriba (temp) o abajo (resp).
            func labio(_ v: Double?) -> CGFloat {
                guard let v else { return Self.labioMin }
                return Self.labioMin + Self.fraccionFilo(v) * (medio * Self.filoFrac - Self.labioMin)
            }

            let arriba = noches.map { medio - labio($0.temp) }
            let abajo  = noches.map { medio + labio($0.resp) }
            // P-2: los índices donde SÍ hubo lectura de cada señal. La boca solo existe donde
            // existen las dos: sobre un hueco no se pinta un espacio que nadie midió.
            let vivaT = noches.map { !$0.tempSinLectura }
            let vivaR = noches.map { !$0.respSinLectura }

            // 1 · El relleno: el ESPACIO entre las dos señales. Neutro casi siempre; ámbar solo
            //     en el tramo donde el par votó (la única vez que el guardián empuja tu día).
            //     Se dibuja por TRAMOS de noches con el par completo.
            let paso = n > 1 ? (size.width - inset * 2) / CGFloat(n - 1) : size.width
            var boca = Path()
            var tramo: [Int] = []
            func cerrarTramo() {
                defer { tramo.removeAll() }
                guard let primero = tramo.first else { return }
                // Una noche SUELTA (el par completo entre dos huecos) también se pinta: como
                // columna angosta centrada en su día. Descartarla —lo que hacía el primer
                // arreglo por tramos— borraba la boca entera en una serie de noches alternas,
                // y con ella el ÁMBAR: el único día que el guardián empuja tu día desaparecía
                // del dibujo mientras el sello y el chip seguían afirmándolo (COS-1).
                guard tramo.count > 1 else {
                    let cx = x(primero), semi = min(paso, 10) / 2
                    boca.addRect(CGRect(x: cx - semi, y: arriba[primero],
                                        width: semi * 2, height: abajo[primero] - arriba[primero]))
                    return
                }
                boca.move(to: CGPoint(x: x(primero), y: arriba[primero]))
                for i in tramo.dropFirst() { boca.addLine(to: CGPoint(x: x(i), y: arriba[i])) }
                for i in tramo.reversed() { boca.addLine(to: CGPoint(x: x(i), y: abajo[i])) }
                boca.closeSubpath()
            }
            for i in 0..<n {
                if vivaT[i] && vivaR[i] { tramo.append(i) } else { cerrarTramo() }
            }
            cerrarTramo()
            ctx.fill(boca, with: .color(LiquidColor.tinta500.opacity(MatrizTokens.costuraFillAlfa)))

            // El tramo del par fuera se tiñe encima. Donde HAY boca se recorta a ella (la lente
            // que abre el par); donde no la hay —porque una de las dos señales no se pudo
            // colocar en ninguna escala— se pinta la columna igual, más tenue.
            //
            // El ámbar es el JUICIO DEL MOTOR, no una consecuencia del dibujo: colgarlo de la
            // boca hacía que el único día en que el guardián empuja tu día desapareciera de la
            // gráfica mientras el sello seguía en ámbar y el chip seguía gritándolo (COS-1, y
            // otra vez en la tercera vuelta cuando el arreglo hermano dejó la boca vacía).
            let alerta = LiquidColor.atencion.opacity(MatrizTokens.costuraAlertaAlfa)
            for (i, noche) in noches.enumerated() where noche.parFuera {
                let rect = Path(CGRect(x: x(i) - paso / 2, y: 0, width: paso, height: size.height))
                if vivaT[i] && vivaR[i] {
                    ctx.drawLayer { capa in
                        capa.clip(to: boca)
                        capa.fill(rect, with: .color(alerta))
                    }
                } else {
                    ctx.fill(rect, with: .color(LiquidColor.atencion
                        .opacity(MatrizTokens.costuraAlertaAlfa * 0.6)))
                }
            }

            // 2 · Las dos orillas, cada una en su tono, POR TRAMOS: la línea se interrumpe en las
            //     noches sin lectura (P-2) en vez de cruzarlas por el centro como si fueran
            //     perfectas. Una noche suelta entre huecos se dibuja como punto.
            func orilla(_ ys: [CGFloat], viva: [Bool], hue: Color) {
                var actual: [Int] = []
                func trazar() {
                    defer { actual.removeAll() }
                    guard let primero = actual.first else { return }
                    if actual.count == 1 {
                        MatrizChartDraw.punto(ctx, en: CGPoint(x: x(primero), y: ys[primero]),
                                              radio: LiquidChart.puntoDatoRadio, hue: hue, alfa: 1)
                        return
                    }
                    var p = Path()
                    p.move(to: CGPoint(x: x(primero), y: ys[primero]))
                    for i in actual.dropFirst() { p.addLine(to: CGPoint(x: x(i), y: ys[i])) }
                    ctx.stroke(p, with: .color(hue),
                               style: StrokeStyle(lineWidth: LiquidChart.lineaAncho,
                                                  lineCap: .round, lineJoin: .round))
                }
                for i in 0..<n {
                    if viva[i] { actual.append(i) } else { trazar() }
                }
                trazar()
            }
            orilla(arriba, viva: vivaT, hue: hueTemp)
            orilla(abajo, viva: vivaR, hue: hueResp)

            // 3 · HOY: el anillo hueco de la familia, en las dos orillas.
            let iHoy = n - 1
            for (ys, hue, viva) in [(arriba, hueTemp, vivaT[iHoy]), (abajo, hueResp, vivaR[iHoy])] {
                guard viva else { continue }        // P-2: sin lectura de hoy, sin joya de hoy
                let c = CGPoint(x: x(iHoy), y: ys[iHoy])
                let rExt = LiquidChart.puntoDatoRadio + LiquidChart.endpointBorde * 0.5
                MatrizChartDraw.punto(ctx, en: c, radio: rExt, hue: hue, alfa: 1)
                MatrizChartDraw.punto(ctx, en: c, radio: rExt - LiquidChart.endpointBorde,
                                      hue: LiquidColor.papelAlto, alfa: 1)
            }

            // 4 · Scrub: el cursor cruza LAS DOS orillas (se lee la noche, no una señal).
            if let r = resaltado, noches.indices.contains(r) {
                let cx = x(r)
                MatrizChartDraw.cursorScrub(ctx, x: cx, height: size.height,
                                            hue: LiquidColor.tinta500,
                                            fantasma: noches[r].temp == nil && noches[r].resp == nil)
                // Cada joya sigue a SU señal (P-2, que el cursor se había saltado 14 líneas más
                // abajo del guard que lo prohíbe): sobre una noche sin lectura de respiración,
                // la joya azul pegada al eje afirmaba una medición que nadie tomó.
                if vivaT[r] {
                    MatrizChartDraw.punto(ctx, en: CGPoint(x: cx, y: arriba[r]),
                                          radio: MatrizTokens.hoyRadio, hue: hueTemp, alfa: 1)
                }
                if vivaR[r] {
                    MatrizChartDraw.punto(ctx, en: CGPoint(x: cx, y: abajo[r]),
                                          radio: MatrizTokens.hoyRadio, hue: hueResp, alfa: 1)
                }
            }
        }
        .frame(maxWidth: .infinity, idealHeight: MatrizTokens.alturaCostura)
        .accessibilityHidden(true)
    }
}

#if DEBUG
/// Series de ejemplo para el preview (fuera del `body`: el type-checker no las resuelve inline).
private enum CosturaDemo {
    static func serie(_ f: (Int) -> (Double?, Double?, Bool)) -> [MatrizCostura.Noche] {
        var out: [MatrizCostura.Noche] = []
        for i in 0..<20 {
            let (t, r, par) = f(i)
            out.append(MatrizCostura.Noche(temp: t, resp: r, parFuera: par))
        }
        return out
    }

    static var calma: [MatrizCostura.Noche] {
        serie { i in
            let t: Double = 0.18 + 0.10 * sin(Double(i) / 2)
            let r: Double = 0.22 + 0.10 * cos(Double(i) / 3)
            return (t, r, false)
        }
    }

    static var unaFuera: [MatrizCostura.Noche] {
        serie { i in (i > 16 ? 1.35 : 0.20, 0.25, false) }
    }

    static var parFuera: [MatrizCostura.Noche] {
        serie { i in
            let fuera = i > 17
            return (fuera ? 1.50 : 0.20, fuera ? 1.40 : 0.24, fuera)
        }
    }
}

private struct CosturaDemoFila: View {
    let titulo: String
    let noches: [MatrizCostura.Noche]
    let id: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: titulo).font(LiquidType.tituloFila)
            MatrizCostura(chartID: id, noches: noches)
                .frame(height: MatrizTokens.alturaCostura)
        }
    }
}

#Preview("Costura · los tres estados") {
    VStack(spacing: 26) {
        CosturaDemoFila(titulo: "Las dos en calma", noches: CosturaDemo.calma, id: "p1")
        CosturaDemoFila(titulo: "Una se aleja", noches: CosturaDemo.unaFuera, id: "p2")
        CosturaDemoFila(titulo: "Las dos, juntas", noches: CosturaDemo.parFuera, id: "p3")
    }
    .padding(22)
    .background(LiquidColor.papelMatriz)
}
#endif
