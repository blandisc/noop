import SwiftUI

// MARK: - «Los dos hilos de puntos» del guardián (FER-118)
//
// La gráfica del par —temperatura de piel arriba (dorado), respiración abajo (azul)— como dos
// hilos horizontales de PUNTOS, uno por noche, cada uno con la banda de tu rango detrás y un
// hilo finísimo al centro (tu base). Elegida por el dueño sobre el prototipo aprobado en lugar
// de la costura (FER-80): la costura pintaba el ESPACIO entre las dos señales; ésta las deja
// leer noche por noche, que es como el scrub las recorre.
//
// La honestidad es la MISMA de la costura y no se negocia:
//   · cada punto se coloca con `MatrizCostura.fraccionFilo`, FIRMADO: caliente/rápido arriba de
//     la base, frío/lento abajo y apretado al 22 % (el centinela nunca marca una noche fría);
//   · el ancla del builder (marcado fuera ≥ 1.02, no marcado ≤ 0.98) + el hueco del filo del
//     mapeo garantizan que lo que el motor marcó fuera cae por encima de `filoFuera` y lo que no,
//     por debajo de `filoDentro`: «fuera» se lee del valor (v ≥ 1), sin banderas aparte (P-2);
//   · la banda de tu rango va de `A·filoBanda` (0.58, el borde de ADENTRO del hueco del filo —
//     NO `fraccionFilo(1)` = 0.75) arriba a `y(−1)` abajo, asimétrica a propósito: el borde de
//     arriba es el filo que el guardián vigila; el de abajo existe pero no grita. Un punto al filo
//     (v = 1) cae FUERA de la banda, con aire (≥ 2.5 pt): ese es el punto (§13.21);
//   · la banda SOLO se dibuja si ese hilo tiene al menos una noche con valor (sin base
//     —respiración sin juicio, calibración— no hay banda ni hilo central en ese hilo);
//   · sin lectura = una marca mínima gris sobre la base, del color de nadie (P-2);
//   · la noche en que el PAR votó (`parFuera`, el juicio del motor) es la única con ámbar
//     (`atencion`, el mismo de la costura — el claro de ambiente no pasa 3:1 sobre blanco):
//     columna, los dos puntos y un nudo punteado que los une.
public struct MatrizHilos: View {
    private let chartID: String
    private let noches: [MatrizCostura.Noche]
    private let hueTemp: Color
    private let hueResp: Color
    private let resaltado: Int?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.liquidAmbientPaused) private var ambientPaused
    @Environment(\.liquidMotionDisabled) private var motionDisabled

    public init(chartID: String, noches: [MatrizCostura.Noche],
                hueTemp: Color = LiquidColor.doradoTemp,
                hueResp: Color = LiquidColor.azul,
                resaltado: Int? = nil) {
        self.chartID = chartID
        self.noches = noches
        self.hueTemp = hueTemp
        self.hueResp = hueResp
        self.resaltado = resaltado
    }

    /// El latido del anillo de HOY sigue el reloj del sello vivo; quieto = anillo fijo.
    private var quieto: Bool { reduceMotion || ambientPaused || motionDisabled }

    // MARK: La geometría, pura (lo que se prueba sin Canvas)

    public enum Geometria {
        /// La `y` del punto para el valor firmado `v` alrededor de `base`: caliente/rápido
        /// (v > 0) arriba, frío/lento (v < 0) abajo y apretado. `fraccionFilo` ya devuelve la
        /// magnitud [0, 1) con el hueco del filo y el lado bajo comprimido.
        public static func y(_ v: Double, base: CGFloat) -> CGFloat {
            let d = MatrizCostura.fraccionFilo(v) * MatrizTokens.hilosAmplitud
            return v < 0 ? base + d : base - d
        }

        /// La banda de tu rango detrás de un hilo: arriba `A·filoBanda` (0.58 — el borde de
        /// ADENTRO del hueco del filo, no `fraccionFilo(1)` = 0.75) y abajo `y(−1)` (apretado).
        /// Así todo lo que el motor NO marcó (≤ 0.98) cae dentro y todo lo marcado (≥ 1.02) cae
        /// fuera con su centro a ≥ 2.5 pt del borde: el hueco del filo se ve.
        public static func banda(base: CGFloat) -> ClosedRange<CGFloat> {
            (base - MatrizCostura.filoBanda * MatrizTokens.hilosAmplitud)...y(-1, base: base)
        }

        /// ¿Ese hilo tiene base? Sí en cuanto una noche trae valor (nil = no se leyó o no se pudo
        /// juzgar). Sin base no hay banda ni hilo central: no se inventa rango.
        public static func hayBase(_ valores: [Double?]) -> Bool {
            valores.contains { $0 != nil }
        }

        public enum Estilo: Equatable {
            /// |v| < 1 y no votó: tenue, chico.
            case dentro
            /// v ≥ 1: el motor lo marcó (o la temperatura cruzó su corte público): lleno, mayor.
            case fuera
            /// La noche en que el par votó: ámbar, lleno.
            case par
            /// La noche que el dedo está leyendo: la mayor.
            case leido
        }

        public static func estilo(v: Double, parFuera: Bool, leido: Bool) -> Estilo {
            if leido { return .leido }
            if parFuera { return .par }
            return v >= 1 ? .fuera : .dentro
        }

        public static func radio(_ e: Estilo) -> CGFloat {
            switch e {
            case .dentro: return MatrizTokens.hilosPuntoDentro
            case .fuera, .par: return MatrizTokens.hilosPuntoFuera
            case .leido: return MatrizTokens.hilosPuntoLeido
            }
        }

        public static func alfa(_ e: Estilo) -> Double {
            e == .dentro ? MatrizTokens.hilosPuntoDentroAlfa : 1
        }

        /// La fase del latido del anillo de HOY en [0, 1] (0 = anillo fijo). Misma frecuencia
        /// que el sello vivo en calma (`sin(t·1.15)`).
        public static func fase(_ t: TimeInterval, quieto: Bool) -> Double {
            quieto ? 0 : (sin(t * MatrizTokens.hilosLatidoW) + 1) / 2
        }
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: LiquidMotion.intervaloSello, paused: quieto)) { tl in
            let t = quieto ? 0 : tl.date.timeIntervalSinceReferenceDate
            lienzo(fase: Geometria.fase(t, quieto: quieto))
        }
        .frame(maxWidth: .infinity, idealHeight: MatrizTokens.alturaHilos)
        .accessibilityHidden(true)
    }

    private func lienzo(fase: Double) -> some View {
        Canvas(rendersAsynchronously: false) { ctx, size in
            let n = noches.count
            let temps = noches.map(\.temp), resps = noches.map(\.resp)
            guard n > 0, Geometria.hayBase(temps) || Geometria.hayBase(resps) else {
                MatrizChartDraw.rejillaFantasma(ctx, size: size, chartID: chartID)
                return
            }
            // P-3: el MISMO inset que usa el mapeo del dedo (una sola fuente).
            let inset = MatrizHoyFace.chartInset(.costura(noches: noches))
            func x(_ i: Int) -> CGFloat {
                MatrizChartDraw.xAt(index: i, count: n, width: size.width, inset: inset)
            }
            let paso = n > 1 ? (size.width - inset * 2) / CGFloat(n - 1) : size.width
            // La columna del par no puede alcanzar a la noche vecina (con n = 2 el paso es casi
            // el lienzo) ni inundarlo (n = 1): tope a la mitad del ancho útil (revisión final).
            let anchoColumna = min(paso * MatrizTokens.hilosColumnaFactor, (size.width - inset * 2) * 0.5)
            let iHoy = n - 1
            let leyendo = resaltado.map { noches.indices.contains($0) ? $0 : nil } ?? nil

            /// Un hilo: banda + base + puntos (o el hueco).
            func hilo(_ valores: [Double?], base: CGFloat, hue: Color) {
                guard Geometria.hayBase(valores) else { return }
                let banda = Geometria.banda(base: base)
                let alto = banda.upperBound - banda.lowerBound
                let rect = CGRect(x: inset, y: banda.lowerBound,
                                  width: size.width - inset * 2, height: alto)
                ctx.fill(Path(roundedRect: rect, cornerRadius: alto / 2),
                         with: .color(hue.opacity(MatrizTokens.hilosFillAlfa)))
                var linea = Path()
                linea.move(to: CGPoint(x: inset, y: base))
                linea.addLine(to: CGPoint(x: size.width - inset, y: base))
                ctx.stroke(linea, with: .color(hue.opacity(MatrizTokens.hilosBaseAlfa)), lineWidth: 1)
            }
            hilo(temps, base: MatrizTokens.hilosBaseTemp, hue: hueTemp)
            hilo(resps, base: MatrizTokens.hilosBaseResp, hue: hueResp)

            // La noche en que el par votó: columna ámbar y nudo entre los dos puntos. Es el
            // juicio del motor (`parFuera`), nunca re-derivado del dibujo (COS-1).
            // …y solo si esa noche tiene al menos un punto que la sostenga: con < 3 lecturas
            // de respiración en la ventana el builder no arma su escala (`resp` nil en todas) y
            // el hilo no se dibuja; una columna ámbar sobre nada afirmaría con el dibujo lo que
            // solo el scrub puede decir con palabras (revisión final).
            for (i, noche) in noches.enumerated() where noche.parFuera && (noche.temp != nil || noche.resp != nil) {
                let col = CGRect(x: x(i) - anchoColumna / 2, y: LiquidSpace.s100,
                                 width: anchoColumna,
                                 height: size.height - LiquidSpace.s100 * 2)
                // `atencion`, no `ambarClaro`: el claro es un tono de AMBIENTE (2.3:1 sobre blanco)
                // y ésta es la marca de dato más importante de la gráfica (revisión ronda 3).
                ctx.fill(Path(roundedRect: col, cornerRadius: LiquidSpace.s150),
                         with: .color(LiquidColor.atencion.opacity(MatrizTokens.hilosAlertaAlfa * 0.5)))
                if let t = noche.temp, let r = noche.resp {
                    var nudo = Path()
                    nudo.move(to: CGPoint(x: x(i), y: Geometria.y(t, base: MatrizTokens.hilosBaseTemp)))
                    nudo.addLine(to: CGPoint(x: x(i), y: Geometria.y(r, base: MatrizTokens.hilosBaseResp)))
                    ctx.stroke(nudo, with: .color(LiquidColor.atencion),
                               style: StrokeStyle(lineWidth: MatrizTokens.hilosNudoTrazo,
                                                  dash: MatrizTokens.hilosNudoDash))
                }
            }

            // Scrub: el cursor cruza la noche entera (se lee la noche, no una señal).
            if let r = leyendo {
                MatrizChartDraw.cursorScrub(ctx, x: x(r), height: size.height,
                                            hue: LiquidColor.tinta500,
                                            fantasma: noches[r].temp == nil && noches[r].resp == nil)
            }

            /// Los puntos de un hilo (o el hueco cuando no hay lectura).
            func puntos(_ valores: [Double?], base: CGFloat, hue: Color) {
                guard Geometria.hayBase(valores) else { return }
                for (i, v) in valores.enumerated() {
                    guard let v else {
                        MatrizChartDraw.punto(ctx, en: CGPoint(x: x(i), y: base),
                                              radio: MatrizTokens.hilosHuecoRadio,
                                              hue: LiquidColor.tinta500, alfa: MatrizTokens.hilosHuecoAlfa)
                        continue
                    }
                    let estilo = Geometria.estilo(v: v, parFuera: noches[i].parFuera, leido: leyendo == i)
                    let tinta = noches[i].parFuera ? LiquidColor.atencion : hue
                    let c = CGPoint(x: x(i), y: Geometria.y(v, base: base))
                    MatrizChartDraw.punto(ctx, en: c, radio: Geometria.radio(estilo),
                                          hue: tinta, alfa: Geometria.alfa(estilo))
                    // HOY late (los dos puntos de anoche): anillo que crece y se apaga con la
                    // fase del sello vivo; se calla mientras el dedo lee otra noche.
                    if i == iHoy, leyendo == nil {
                        let radio = MatrizTokens.hilosAnillo + MatrizTokens.hilosAnilloLatido * fase
                        let anillo = Path(ellipseIn: CGRect(x: c.x - radio, y: c.y - radio,
                                                            width: radio * 2, height: radio * 2))
                        ctx.stroke(anillo, with: .color(hue.opacity(1 - MatrizTokens.hilosLatidoAlfa * fase)),
                                   lineWidth: MatrizTokens.hilosAnilloTrazo)
                    }
                }
            }
            puntos(temps, base: MatrizTokens.hilosBaseTemp, hue: hueTemp)
            puntos(resps, base: MatrizTokens.hilosBaseResp, hue: hueResp)
        }
    }
}

#if DEBUG
/// Series de ejemplo para el preview (fuera del `body`: el type-checker no las resuelve inline).
private enum HilosDemo {
    static func serie(_ f: (Int) -> (Double?, Double?, Bool)) -> [MatrizCostura.Noche] {
        (0..<20).map { i in
            let (t, r, par) = f(i)
            return MatrizCostura.Noche(temp: t, resp: r, parFuera: par)
        }
    }
    static var calma: [MatrizCostura.Noche] {
        serie { i in (0.18 + 0.30 * sin(Double(i) / 2), 0.22 + 0.30 * cos(Double(i) / 3), false) }
    }
    static var unaFuera: [MatrizCostura.Noche] {
        serie { i in (i == 15 ? 1.35 : 0.20 + 0.2 * sin(Double(i)), 0.25 - 0.3 * cos(Double(i)), false) }
    }
    static var parFuera: [MatrizCostura.Noche] {
        serie { i in
            let fuera = i == 15
            return (fuera ? 1.50 : 0.20 + 0.25 * sin(Double(i)), fuera ? 1.40 : 0.24 + 0.2 * cos(Double(i)), fuera)
        }
    }
    static var sinBaseResp: [MatrizCostura.Noche] {
        serie { i in (0.2 + 0.3 * sin(Double(i)), nil, false) }
    }
}

private struct HilosDemoFila: View {
    let titulo: String
    let noches: [MatrizCostura.Noche]
    let id: String
    var resaltado: Int? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: titulo).font(LiquidType.tituloFila)
            MatrizHilos(chartID: id, noches: noches, resaltado: resaltado)
                .frame(height: MatrizTokens.alturaHilos)
        }
    }
}

#Preview("Hilos · los estados del guardián") {
    VStack(spacing: 22) {
        HilosDemoFila(titulo: "Las dos en calma (HOY late)", noches: HilosDemo.calma, id: "p1")
        HilosDemoFila(titulo: "Una se aleja", noches: HilosDemo.unaFuera, id: "p2")
        HilosDemoFila(titulo: "Las dos, juntas: ámbar y nudo", noches: HilosDemo.parFuera, id: "p3")
        HilosDemoFila(titulo: "Sin base de respiración (sin banda abajo)", noches: HilosDemo.sinBaseResp, id: "p4")
        HilosDemoFila(titulo: "Leyendo la noche 12", noches: HilosDemo.calma, id: "p5", resaltado: 12)
    }
    .padding(22)
    .background(LiquidColor.papelTarjeta)
}
#endif
