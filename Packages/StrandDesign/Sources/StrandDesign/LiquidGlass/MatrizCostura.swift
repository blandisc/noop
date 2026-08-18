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
        // El lado bajo usa la MISMA curva, escalada. Sin `min`: acotarlo con un recorte lo
        // aplanaba a partir de una banda —−0.9 °C y −1.1 °C caían en el mismo pixel—, que es
        // justo lo que este mapeo existe para no hacer. La curva ya está acotada sola (tiende a
        // 1.044·0.22 ≈ 0.23, muy por debajo del filo), así que el recorte nunca hizo falta.
        if v < 0 { return dentro(-v) * ladoBajoFrac }
        if v < 1 { return dentro(v) }
        let u = v - 1
        return filoFuera + (1 - filoFuera) * CGFloat(u / (u + kFuera))
    }

    /// El ancho de cada vara, acotado para que no se toquen ni desaparezcan.
    private static let varaAncho: CGFloat = 7
    /// El aire que queda arriba y abajo: ninguna vara llega al borde del marco.
    private static let aire: CGFloat = 5
    /// El cuerpo mínimo de una vara. Una noche serena dibuja casi nada —que es la verdad— pero
    /// «casi nada» tiene que leerse como una fila pareja y tranquila, no como manchas sueltas.
    private static let varaMin: CGFloat = 2
    /// El hueco entre el eje y el nacimiento de cada vara. Sin él, las dos varas cortas de una
    /// noche serena se tocaban y se leían como UNA sola píldora partida por el eje.
    private static let cuello: CGFloat = 2

    public var body: some View {
        Canvas(rendersAsynchronously: false) { ctx, size in
            let n = noches.count
            guard n > 0, noches.contains(where: { $0.temp != nil || $0.resp != nil }) else {
                MatrizChartDraw.rejillaFantasma(ctx, size: size, chartID: chartID)
                return
            }

            let medio = size.height / 2
            let alcance = medio - Self.aire          // lo que puede crecer una vara
            // P-3: el MISMO inset que usa el mapeo del dedo (una sola fuente).
            let inset = MatrizHoyFace.chartInset(.costura(noches: noches))
            func x(_ i: Int) -> CGFloat {
                MatrizChartDraw.xAt(index: i, count: n, width: size.width, inset: inset)
            }
            let paso = n > 1 ? (size.width - inset * 2) / CGFloat(n - 1) : size.width
            let ancho = min(Self.varaAncho, max(3, paso * 0.55))

            // EL FILO, DIBUJADO. El mapeo deja un hueco deliberado entre «dentro» (0.58 del
            // recorrido) y «fuera» (0.75): la guía va justo en medio, así que ninguna vara que
            // el motor NO marcó la cruza y toda vara marcada sí. La garantía deja de ser una
            // promesa del código y pasa a ser algo que se ve.
            let filoFrac = (Self.filoDentro + Self.filoFuera) / 2
            for signo in [-1.0, 1.0] as [CGFloat] {
                var guia = Path()
                let y = medio - signo * filoFrac * alcance
                guia.move(to: CGPoint(x: inset, y: y))
                guia.addLine(to: CGPoint(x: size.width - inset, y: y))
                ctx.stroke(guia, with: .color(LiquidColor.tinta7),
                           style: StrokeStyle(lineWidth: 1, dash: [2.5, 3.5]))
            }

            // EL EJE: tu centro. Las dos varas nacen aquí y crecen en direcciones opuestas —
            // la temperatura hacia arriba, la respiración hacia abajo— así que una noche es UNA
            // columna y leerla no exige seguir ninguna línea.
            var eje = Path()
            eje.move(to: CGPoint(x: inset, y: medio))
            eje.addLine(to: CGPoint(x: size.width - inset, y: medio))
            ctx.stroke(eje, with: .color(LiquidColor.tinta500.opacity(0.28)), lineWidth: 1)

            /// La vara de una señal: nace en el eje y crece `fraccionFilo` del alcance.
            func vara(_ v: Double?, i: Int, arriba: Bool, hue: Color, par: Bool) {
                guard let v else {
                    // Sin magnitud —no se leyó, o el motor no pudo juzgarla— la noche existe
                    // pero no se coloca: una marca mínima sobre el eje, del color de nadie.
                    MatrizChartDraw.punto(ctx, en: CGPoint(x: x(i), y: medio),
                                          radio: 1.4, hue: LiquidColor.tinta500, alfa: 0.35)
                    return
                }
                let frac = Self.fraccionFilo(v)
                let alto = max(Self.varaMin, frac * alcance)
                let y = arriba ? medio - Self.cuello - alto : medio + Self.cuello
                let rect = CGRect(x: x(i) - ancho / 2, y: y, width: ancho, height: alto)
                let fuera = frac >= Self.filoFuera
                let tinta = par ? LiquidColor.atencion : hue
                ctx.fill(Path(roundedRect: rect, cornerRadius: min(3, ancho / 2)),
                         with: .color(tinta.opacity(par ? 0.95 : (fuera ? 0.92 : 0.46))))
            }

            for (i, noche) in noches.enumerated() {
                vara(noche.temp, i: i, arriba: true, hue: hueTemp, par: noche.parFuera)
                vara(noche.resp, i: i, arriba: false, hue: hueResp, par: noche.parFuera)
            }

            // EL DÍA QUE EL PAR VOTÓ: su columna se marca entera, de arriba abajo. El ámbar no
            // depende de que el dibujo tenga con qué pintarlo (COS-1): es el juicio del motor.
            for (i, noche) in noches.enumerated() where noche.parFuera {
                let col = CGRect(x: x(i) - paso / 2, y: 0, width: paso, height: size.height)
                ctx.fill(Path(col), with: .color(LiquidColor.atencion
                    .opacity(MatrizTokens.costuraAlertaAlfa * 0.5)))
            }

            // HOY se marca con su COLUMNA, no con anillos: sobre dos varas cortas los dos
            // anillos casi se tocaban y el par de hoy se leía como un «8» suelto al final de la
            // gráfica. Una banda tenue detrás dice «esta es la de hoy» sin inventar una forma.
            let iHoy = n - 1
            var marcaHoy = Path()
            marcaHoy.move(to: CGPoint(x: x(iHoy), y: Self.aire))
            marcaHoy.addLine(to: CGPoint(x: x(iHoy), y: size.height - Self.aire))
            ctx.stroke(marcaHoy, with: .color(LiquidColor.tinta500.opacity(0.22)), lineWidth: 1)

            // Scrub: el cursor cruza la noche entera (se lee la noche, no una señal).
            if let r = resaltado, noches.indices.contains(r) {
                MatrizChartDraw.cursorScrub(ctx, x: x(r), height: size.height,
                                            hue: LiquidColor.tinta500,
                                            fantasma: noches[r].temp == nil && noches[r].resp == nil)
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
