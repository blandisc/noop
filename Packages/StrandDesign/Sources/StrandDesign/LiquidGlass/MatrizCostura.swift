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

    /// Cuánto se separa del eje una señal «en su filo» (normalizada = 1), en fracción del
    /// medio alto. Deja aire arriba y abajo para que una noche MUY fuera siga cabiendo.
    private static let filoFrac: CGFloat = 0.58
    /// La separación mínima del eje: la costura nunca se cierra del todo, para que se lea como
    /// un objeto y no como una línea partida.
    private static let labioMin: CGFloat = 2.6

    public var body: some View {
        Canvas(rendersAsynchronously: false) { ctx, size in
            let n = noches.count
            guard n > 0, noches.contains(where: { $0.temp != nil || $0.resp != nil }) else {
                MatrizChartDraw.rejillaFantasma(ctx, size: size, chartID: chartID)
                return
            }

            let medio = size.height / 2
            let inset = max(MatrizTokens.chartInset,
                            LiquidChart.puntoDatoRadio + LiquidChart.endpointBorde)
            func x(_ i: Int) -> CGFloat {
                MatrizChartDraw.xAt(index: i, count: n, width: size.width, inset: inset)
            }
            /// El labio de una señal: su distancia al eje, hacia arriba (temp) o abajo (resp).
            func labio(_ v: Double?) -> CGFloat {
                guard let v else { return Self.labioMin }
                let mag = min(abs(v), 1.9)          // techo: una noche extrema no rompe el marco
                return Self.labioMin + CGFloat(mag) * (medio * Self.filoFrac - Self.labioMin)
            }

            let arriba = noches.map { medio - labio($0.temp) }
            let abajo  = noches.map { medio + labio($0.resp) }

            // 1 · El relleno: el ESPACIO entre las dos señales. Neutro casi siempre; ámbar solo
            //     en el tramo donde el par votó (la única vez que el guardián empuja tu día).
            var boca = Path()
            boca.move(to: CGPoint(x: x(0), y: arriba[0]))
            for i in 1..<n { boca.addLine(to: CGPoint(x: x(i), y: arriba[i])) }
            for i in stride(from: n - 1, through: 0, by: -1) {
                boca.addLine(to: CGPoint(x: x(i), y: abajo[i]))
            }
            boca.closeSubpath()
            ctx.fill(boca, with: .color(LiquidColor.tinta500.opacity(MatrizTokens.costuraFillAlfa)))

            // El tramo del par fuera se tiñe encima, recortado a la boca.
            if noches.contains(where: { $0.parFuera }) {
                ctx.drawLayer { capa in
                    capa.clip(to: boca)
                    for (i, noche) in noches.enumerated() where noche.parFuera {
                        let ancho = n > 1 ? (size.width - inset * 2) / CGFloat(n - 1) : size.width
                        let rect = CGRect(x: x(i) - ancho / 2, y: 0, width: ancho, height: size.height)
                        capa.fill(Path(rect), with: .color(LiquidColor.atencion.opacity(MatrizTokens.costuraAlertaAlfa)))
                    }
                }
            }

            // 2 · Las dos orillas, cada una en su tono.
            func orilla(_ ys: [CGFloat], hue: Color) {
                var p = Path()
                p.move(to: CGPoint(x: x(0), y: ys[0]))
                for i in 1..<n { p.addLine(to: CGPoint(x: x(i), y: ys[i])) }
                ctx.stroke(p, with: .color(hue),
                           style: StrokeStyle(lineWidth: LiquidChart.lineaAncho,
                                              lineCap: .round, lineJoin: .round))
            }
            orilla(arriba, hue: hueTemp)
            orilla(abajo, hue: hueResp)

            // 3 · HOY: el anillo hueco de la familia, en las dos orillas.
            let iHoy = n - 1
            for (ys, hue) in [(arriba, hueTemp), (abajo, hueResp)] {
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
                MatrizChartDraw.punto(ctx, en: CGPoint(x: cx, y: arriba[r]),
                                      radio: MatrizTokens.hoyRadio, hue: hueTemp, alfa: 1)
                MatrizChartDraw.punto(ctx, en: CGPoint(x: cx, y: abajo[r]),
                                      radio: MatrizTokens.hoyRadio, hue: hueResp, alfa: 1)
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
