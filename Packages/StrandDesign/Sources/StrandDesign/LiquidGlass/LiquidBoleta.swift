import SwiftUI

// MARK: - Liquid Glass · La Boleta (hoja del veredicto, rediseño «acta de escrutinio»)
//
// Tres piezas nuevas de la boleta del veredicto (spec /ux + /ui, sesión 2026-08-04):
//  · `LiquidVotoRiel` — el mini-riel de un voto: eje hairline de instrumento (no un track
//    de slider), banda con gradiente de densidad (= tu patrón), ticks de umbral cuyo NÚMERO
//    codifica el tipo de comparación (1 = contra un mínimo · 2 = contra tu base), y la joya
//    de papel ribeteada (= tu amanecer, misma gramática que el punto de HOY en las gráficas).
//  · `LiquidBoletaCard` — la tarjeta-acta: filas de votante, cada una con el hue de su
//    métrica (rosa FC · indigo Sueño) cuando hay veredicto (revisión del dueño 2026-08).
//  · `LiquidVigilanteChip` — la ficha punteada de quien mide pero no vota (anillo hueco:
//    un voto que nunca se llena; borde punteado: no es votante).
//
// Vocabulario visual (fijado por el spec): joya blanca ribeteada = el dato de hoy · hueco
// sólido = mide sin votar · punteado = sin dato / sin derecho. El riel es cromo geométrico
// exento de Dynamic Type (misma exención que `LiquidChart.ejeXAlto`); la palabra sí escala.
// Contrato D3: strings YA localizados; el riel es decorativo para VoiceOver — la lectura
// viaja en el label compuesto de la fila.

// MARK: - El mini-riel

public struct LiquidVotoRiel: View {
    /// Contra qué se compara el voto — el número de ticks ES la semántica.
    public enum Umbral: Sendable {
        /// Banda bilateral centrada («contra tu base»): 2 ticks.
        case rango
        /// Piso unilateral («contra un mínimo fijo»): 1 tick; la banda corre del tick a la derecha.
        case minimo
    }

    /// El estado del voto. Sin magnitud: la posición de la joya es CANÓNICA por estado
    /// (pictograma, como el dominó del guardián) — esta superficie no publica números del
    /// motor, así que un riel cualitativo es la representación honesta.
    public enum Estado: Sendable, Equatable {
        case dentro
        /// Fuera por abajo (sueño corto, señal baja): la joya a la izquierda de la banda.
        case fueraAbajo
        /// Fuera por arriba (FC alta, temperatura elevada): la joya a la derecha.
        case fueraArriba
        /// Aún sin base propia: joya punteada centrada, banda plana sin ticks.
        case calibrando
        /// Sin lectura anoche: eje punteado, sin banda ni joya.
        case sinLectura
    }

    private let estado: Estado
    private let umbral: Umbral
    private let tono: Color
    private let palabra: String
    /// FER-84: la desviación REAL de hoy, en la dirección del riel (negativa = a la izquierda,
    /// positiva = a la derecha), en unidades de σ contra tu propia base. `nil` = colocar por la
    /// posición canónica del estado, como antes.
    ///
    /// Es la diferencia entre un pictograma y una lectura: con ella, la joya no dice «fuera», dice
    /// CUÁNTO fuera, contra la MISMA banda de ±1σ que usa el veredicto para votar. Sigue sin haber
    /// un solo número impreso: la posición es el dato.
    private let desviacion: Double?
    /// Progreso del sellado (0 = votos sin caer, 1 = asentado). El caller lo anima UNA vez
    /// al abrir; con Reduce Motion pasa directo a 1.
    private let sellado: Double

    // Geometría del instrumento (constantes internas, patrón `LiquidDominoRegla`).
    static let ancho: CGFloat = 104
    private static let ejeGrosor: CGFloat = 1.5
    private static let bandaAlto: CGFloat = 10
    private static let tickAlto: CGFloat = 7
    private static let tickGrosor: CGFloat = 1.5
    private static let joyaDiametro: CGFloat = 11
    private static let dashJoya: [CGFloat] = [2, 2]
    private static let dashEje: [CGFloat] = [3, 3]
    // Bordes de la banda (fracción del ancho): rango = ventana centrada; mínimo = piso→derecha.
    private static let rangoLo: CGFloat = 0.22, rangoHi: CGFloat = 0.78
    private static let minimoLo: CGFloat = 0.36
    // Posiciones canónicas de la joya por estado.
    private static let posDentro: CGFloat = 0.52
    private static let posFueraAbajo: CGFloat = 0.10
    private static let posFueraArriba: CGFloat = 0.90
    /// El borde de la banda en unidades de posición: ahí vive tu ±1σ.
    static let posBandaHi: CGFloat = 0.78
    /// Los topes del bigote: el rango plausible. La joya se detiene aquí — y la saturación ocurre
    /// EXACTAMENTE en `zTope`, no antes: con los valores viejos el mapa se plantaba en 1.64σ y
    /// dibujaba 1.7σ y 12σ en el mismo pixel, que es justo lo que la caja venía a resolver.
    static let bigoteLo: CGFloat = 0.04, bigoteHi: CGFloat = 0.96
    /// La desviación que llega al tope del bigote.
    static let zTope: Double = 2.5
    private static let bigoteGrosor: CGFloat = 1
    private static let bigoteAlto: CGFloat = 5

    public init(estado: Estado, umbral: Umbral, tono: Color, palabra: String,
                desviacion: Double? = nil, sellado: Double = 1) {
        self.estado = estado
        self.umbral = umbral
        self.tono = tono
        self.palabra = palabra
        self.desviacion = desviacion
        self.sellado = sellado
    }

    /// Dónde cae una desviación en el riel. El centro es tu base; el borde de la banda, tu ±1σ —
    /// el mismo corte con el que el motor decide si un eje se salió. Más allá, la joya sigue
    /// caminando hasta el tope del bigote y ahí se detiene: un valor extremo se ve extremo, pero
    /// nunca se sale del instrumento ni miente sobre cuánto más lejos está.
    static func posicion(desviacion z: Double) -> CGFloat {
        // NaN (base degenerada) no tiene dirección: se planta en el centro, porque `.position(x:)`
        // con NaN es la familia de «Invalid frame dimension» que este repo ya sufrió una vez. Un
        // infinito SÍ tiene dirección, así que sigue el camino normal y satura en su bigote.
        guard !z.isNaN else { return 0.5 }
        // Dentro de la banda, ±1σ cae en su borde. Más allá, el recorrido restante se reparte hasta
        // el tope del bigote, de modo que la saturación ocurra en `zTope` y no antes.
        let magnitud = min(abs(z), zTope)
        let dentro = posBandaHi - 0.5
        let fuera = bigoteHi - posBandaHi
        let avance: CGFloat = magnitud <= 1
            ? CGFloat(magnitud) * dentro
            : dentro + CGFloat((magnitud - 1) / (zTope - 1)) * fuera
        return 0.5 + (z < 0 ? -avance : avance)
    }

    private var bandaRango: ClosedRange<CGFloat> {
        umbral == .rango ? Self.rangoLo...Self.rangoHi : Self.minimoLo...1.0
    }

    private var posJoya: CGFloat? {
        // Sin base usable no hay dónde colocarla: «calibrando» se queda centrada y punteada, y
        // «sin lectura» no dibuja joya. La desviación solo manda cuando hay un veredicto que leer.
        switch estado {
        case .calibrando:  return 0.5
        case .sinLectura:  return nil
        case .dentro, .fueraAbajo, .fueraArriba:
            if let z = desviacion { return Self.posicion(desviacion: z) }
            return estado == .dentro ? Self.posDentro
                 : (estado == .fueraAbajo ? Self.posFueraAbajo : Self.posFueraArriba)
        }
    }

    public var body: some View {
        VStack(alignment: .trailing, spacing: LiquidSpace.s150) {
            plot
                .frame(width: Self.ancho, height: Self.bandaAlto + 4)
            Text(verbatim: palabra)
                .font(LiquidType.microEstado)
                .foregroundStyle(tonoPalabra)
                .opacity(0.4 + 0.6 * sellado)   // token-exempt: la opacidad ES el progreso del sellado
                .scaleEffect(0.92 + 0.08 * sellado, anchor: .trailing)
        }
        // Decorativo: la lectura audible es el label compuesto de la fila (contrato D3).
        .accessibilityHidden(true)
    }

    /// Si este voto salió — y eso lo dice el VOTO, no un recálculo de la magnitud.
    ///
    /// Recalcularlo como `abs(z) > 1` parecía equivalente y no lo es: el eje autonómico vota por UN
    /// lado (peor que tu base), así que una mañana espléndida —FC en reposo muy por debajo— daba
    /// |z| > 1 y encendía el aro de alerta junto a la palabra «dentro». El aro dice «este voto se
    /// salió»; quien sabe eso es el estado.
    private var fueraDeBanda: Bool { estado == .fueraAbajo || estado == .fueraArriba }

    private var tonoPalabra: Color {
        switch estado {
        case .calibrando, .sinLectura: return LiquidColor.tinta500
        default: return tonoTexto
        }
    }

    /// El tono del voto dicho para TEXTO chico (AA): ámbar/rojo bajan a su voz de lectura.
    private var tonoTexto: Color {
        if tono == LiquidColor.ambar || tono == LiquidColor.atencion {
            return LiquidColor.atencionTexto
        }
        if tono == LiquidColor.verdePrimario { return LiquidColor.verdeProfundo }
        return tono
    }

    private var plot: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let cy = geo.size.height / 2
            ZStack(alignment: .leading) {
                // Eje del instrumento (hairline; punteado cuando no hubo lectura).
                Path { p in
                    p.move(to: CGPoint(x: 0, y: cy))
                    p.addLine(to: CGPoint(x: w, y: cy))
                }
                .stroke(LiquidColor.tinta10,
                        style: StrokeStyle(lineWidth: Self.ejeGrosor,
                                           lineCap: .round,
                                           dash: estado == .sinLectura ? Self.dashEje : []))

                // Banda = tu patrón (gradiente de densidad: el patrón no tiene bordes duros).
                if estado != .sinLectura {
                    banda(w: w, cy: cy)
                }

                // Ticks de umbral: su NÚMERO dice contra qué se compara.
                if estado != .sinLectura && estado != .calibrando {
                    tick(x: bandaRango.lowerBound * w, cy: cy)
                    if umbral == .rango {
                        tick(x: bandaRango.upperBound * w, cy: cy)
                    }
                }

                // Bigotes: los topes del rango plausible. Enseñan que la banda no es el mundo
                // entero — sin ellos, una joya pegada al borde parecía el extremo del instrumento.
                if estado != .sinLectura && estado != .calibrando && desviacion != nil {
                    bigote(x: Self.bigoteLo * w, cy: cy)
                    bigote(x: Self.bigoteHi * w, cy: cy)
                }

                // La joya: papel ribeteado (nunca bola sólida), cae con el sellado.
                if let pos = posJoya {
                    joya
                        .position(x: pos * w, y: cy - (1 - sellado) * 10)
                        .opacity(estado == .calibrando ? 1 : (0.2 + 0.8 * sellado))
                }
            }
        }
    }

    private func banda(w: CGFloat, cy: CGFloat) -> some View {
        let lo = bandaRango.lowerBound * w
        let hi = bandaRango.upperBound * w
        let tonoBanda = estado == .calibrando ? LiquidColor.tinta500 : tono
        return Capsule()
            .fill(LinearGradient(
                stops: [
                    .init(color: tonoBanda.opacity(LiquidChart.rielBandaFiloAlfa), location: 0),
                    .init(color: tonoBanda.opacity(estado == .calibrando
                                                   ? LiquidChart.rielBandaFiloAlfa
                                                   : LiquidChart.bandaActivaAlfa), location: 0.22),
                    .init(color: tonoBanda.opacity(estado == .calibrando
                                                   ? LiquidChart.rielBandaFiloAlfa
                                                   : LiquidChart.bandaActivaAlfa), location: 0.78),
                    .init(color: tonoBanda.opacity(LiquidChart.rielBandaFiloAlfa), location: 1),
                ],
                startPoint: .leading, endPoint: .trailing))
            .frame(width: hi - lo, height: Self.bandaAlto)
            .position(x: (lo + hi) / 2, y: cy)
    }

    /// Un tope del bigote: hairline de tinta, más corto que el tick de umbral, para que el ojo
    /// distinga «el corte que vota» de «hasta dónde puede llegar el dato».
    private func bigote(x: CGFloat, cy: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: LiquidRadius.hairline, style: .continuous)
            // En el color del eje eran invisibles: el tope tiene que leerse como tope.
            .fill(LiquidColor.tinta500)
            .frame(width: Self.bigoteGrosor, height: Self.bigoteAlto)
            .position(x: x, y: cy)
    }

    private func tick(x: CGFloat, cy: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: LiquidRadius.hairline, style: .continuous)
            .fill(tono.opacity(LiquidChart.marcaAnilloAlfa))
            .frame(width: Self.tickGrosor, height: Self.tickAlto)
            .position(x: x, y: cy)
    }

    @ViewBuilder private var joya: some View {
        if estado == .calibrando {
            Circle()
                .stroke(LiquidColor.tinta500,
                        style: StrokeStyle(lineWidth: 1.4, dash: Self.dashJoya))
                .frame(width: Self.joyaDiametro, height: Self.joyaDiametro)
        } else {
            Circle()
                .fill(LiquidColor.papelAlto)
                .overlay(Circle().strokeBorder(tono, lineWidth: LiquidChart.endpointBorde))
                // Gramática de alerta del sistema: fuera de la banda se AÑADE un aro, nunca se
                // cambia el hue. El color sigue diciendo qué señal es; el aro, que se salió.
                .overlay {
                    if fueraDeBanda {
                        Circle().strokeBorder(tono.opacity(LiquidChart.marcaAnilloAlfa), lineWidth: 1)
                            .padding(-3)
                    }
                }
                .frame(width: Self.joyaDiametro, height: Self.joyaDiametro)
        }
    }
}

// MARK: - La tarjeta-boleta

public struct LiquidBoletaCard: View {

    public struct Votante: Sendable, Identifiable {
        public let id: String
        public let glifo: LiquidIcon.Glyph
        public let nombre: String
        public let sub: String
        public let estado: LiquidVotoRiel.Estado
        public let umbral: LiquidVotoRiel.Umbral
        /// Wash de fila («esta es la que se salió»). Lo decide el caller — con histéresis
        /// puede encender bajo una palabra verde.
        public let fuera: Bool
        /// El tono del VOTO de esta fila (no del veredicto): verde dentro, ámbar/rojo fuera,
        /// tinta sin veredicto.
        public let tonoVoto: Color
        public let palabra: String
        /// El hue de IDENTIDAD de la métrica (revisión del dueño): rosa para FC en reposo,
        /// indigo para Sueño — el mismo color de su celda en la Matriz. Tiñe la gota y el
        /// título para amarrar la fila a su métrica; el estado del voto lo sigue diciendo el
        /// riel/palabra/wash. `tinta700` = sin identidad (comportamiento previo).
        public let hueMetrica: Color
        /// Label compuesto de VoiceOver, YA localizado («Sueño, votó fuera, anoche contra
        /// un mínimo fijo, fuera de tu rango.»).
        public let a11y: String
        /// FER-84: la desviación real del día en la dirección del riel. `nil` = posición canónica.
        public var desviacion: Double?

        public init(id: String, glifo: LiquidIcon.Glyph, nombre: String, sub: String,
                    estado: LiquidVotoRiel.Estado, umbral: LiquidVotoRiel.Umbral,
                    fuera: Bool, tonoVoto: Color, palabra: String,
                    hueMetrica: Color = LiquidColor.tinta700, a11y: String,
                    desviacion: Double? = nil) {
            self.id = id
            self.glifo = glifo
            self.nombre = nombre
            self.sub = sub
            self.estado = estado
            self.umbral = umbral
            self.fuera = fuera
            self.tonoVoto = tonoVoto
            self.palabra = palabra
            self.hueMetrica = hueMetrica
            self.a11y = a11y
            self.desviacion = desviacion
        }
    }

    private let votantes: [Votante]

    @Environment(\.dynamicTypeSize) private var tamanoTexto
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.liquidMotionDisabled) private var motionDisabled

    /// El sellado: los votos caen y se estampan UNA vez al abrir (spec /ux D3). 0→1 por
    /// fila con stagger; Reduce Motion (o el arnés) abre ya asentado.
    @State private var sellado: [Double]

    private static let gotaSize: CGFloat = 28

    public init(votantes: [Votante]) {
        self.votantes = votantes
        _sellado = State(initialValue: Array(repeating: 0, count: votantes.count))
    }

    private var apilada: Bool { tamanoTexto >= .accessibility1 }

    public var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(votantes.enumerated()), id: \.element.id) { i, v in
                fila(v, indice: i)
                if i < votantes.count - 1,
                   !votantes[i].fuera, !votantes[i + 1].fuera {
                    separador
                }
            }
            // La «doble raya contable» de cierre se retiró (revisión del dueño): la línea
            // bajo la última fila leía como ruido. La tarjeta cierra con su propio borde.
        }
        .clipShape(RoundedRectangle(cornerRadius: LiquidRadius.tarjeta, style: .continuous))
        .liquidGlass(.superficieSolida)
        .onAppear(perform: sellar)
    }

    private func sellar() {
        guard sellado.contains(where: { $0 < 1 }) else { return }
        if reduceMotion || motionDisabled {
            sellado = sellado.map { _ in 1 }
            return
        }
        for i in sellado.indices {
            withAnimation(LiquidMotion.lift.delay(Double(i) * 0.09)) {
                sellado[i] = 1
            }
        }
    }

    @ViewBuilder private func fila(_ v: Votante, indice: Int) -> some View {
        let progreso = sellado.indices.contains(indice) ? sellado[indice] : 1
        Group {
            if apilada {
                VStack(alignment: .leading, spacing: LiquidSpace.s150) {
                    HStack(spacing: LiquidSpace.s300) {
                        gota(v)
                        nombre(v)
                        Spacer(minLength: 0)
                    }
                    LiquidVotoRiel(estado: v.estado, umbral: v.umbral,
                                   tono: v.tonoVoto, palabra: v.palabra,
                                   desviacion: v.desviacion, sellado: progreso)
                        .padding(.leading, Self.gotaSize + LiquidSpace.s300)
                }
            } else {
                HStack(spacing: LiquidSpace.s300) {
                    gota(v)
                    nombre(v)
                    Spacer(minLength: LiquidSpace.s200)
                    LiquidVotoRiel(estado: v.estado, umbral: v.umbral,
                                   tono: v.tonoVoto, palabra: v.palabra,
                                   desviacion: v.desviacion, sellado: progreso)
                }
            }
        }
        .padding(.horizontal, LiquidSpace.s400)
        .padding(.vertical, LiquidSpace.s300)
        // El wash respira con el sellado y reposa en el token de fila activa (I1).
        .background(v.fuera
                    ? v.tonoVoto.opacity(LiquidChart.filaActivaAlfa * progreso)
                    : Color.clear)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: v.a11y))
    }

    private func gota(_ v: Votante) -> some View {
        // Gota en el HUE de la métrica (revisión del dueño): el átomo de la familia teñido
        // de la identidad de su señal (rosa/indigo) — glifo en el hue sobre su lavado al 7 %.
        LiquidIconDrop(v.glifo, tone: v.hueMetrica,
                       size: Self.gotaSize, iconSize: 14, fillAlpha: 0.07)
    }

    private func nombre(_ v: Votante) -> some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s050) {
            // El título lleva el color de su métrica (revisión del dueño): amarra la fila a
            // su señal. El estado del voto (verde/ámbar) sigue viviendo en el riel y la palabra.
            Text(verbatim: v.nombre)
                .font(LiquidType.tituloFila)
                .foregroundStyle(v.hueMetrica)
            Text(verbatim: v.sub)
                .font(LiquidType.captionLectura)
                .foregroundStyle(LiquidColor.tinta500)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var separador: some View {
        Rectangle()
            .fill(LiquidColor.tinta10)
            .frame(height: 1)
            .padding(.leading, LiquidSpace.s400 + Self.gotaSize + LiquidSpace.s300)
    }

}

// MARK: - La ficha del vigilante

public struct LiquidVigilanteChip: View {
    private let nombre: String

    public init(nombre: String) {
        self.nombre = nombre
    }

    public var body: some View {
        HStack(spacing: LiquidSpace.s150) {
            Circle()
                .stroke(LiquidColor.tinta500, lineWidth: 1.4)
                .frame(width: 6, height: 6)
            Text(verbatim: nombre)
                .font(LiquidType.captionLectura)
                .foregroundStyle(LiquidColor.tinta700)
        }
        .padding(.horizontal, LiquidSpace.s225)
        .padding(.vertical, LiquidSpace.s075)
        .overlay(
            Capsule()
                .stroke(LiquidColor.tinta10,
                        style: StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
        )
    }
}

#if DEBUG
#Preview("Boleta · estados") {
    VStack(alignment: .leading, spacing: LiquidSpace.s550) {
        LiquidBoletaCard(votantes: [
            .init(id: "auto", glifo: .corazon, nombre: "FC en reposo", sub: "de la noche · contra tu base",
                  estado: .dentro, umbral: .rango, fuera: false,
                  tonoVoto: LiquidColor.verdePrimario, palabra: "dentro",
                  hueMetrica: LiquidColor.rosa,
                  a11y: "FC en reposo, votó dentro, contra tu base."),
            .init(id: "sleep", glifo: .luna, nombre: "Sueño", sub: "anoche · según lo recomendado",
                  estado: .fueraAbajo, umbral: .minimo, fuera: true,
                  tonoVoto: LiquidColor.atencion, palabra: "fuera",
                  hueMetrica: LiquidColor.indigo,
                  a11y: "Sueño, votó fuera, anoche según lo recomendado, fuera de tu rango."),
        ])
        HStack(spacing: LiquidSpace.s150) {
            LiquidVigilanteChip(nombre: "Respiración")
            LiquidVigilanteChip(nombre: "Temperatura")
        }
        // Sin veredicto (calibrando / sin lectura): el hue va GATEADO a tinta — la fila no
        // toma su identidad de color hasta que hay veredicto (regla de la hoja).
        LiquidBoletaCard(votantes: [
            .init(id: "auto", glifo: .corazon, nombre: "FC en reposo", sub: "aprendiendo tu base",
                  estado: .calibrando, umbral: .rango, fuera: false,
                  tonoVoto: LiquidColor.tinta500, palabra: "··",
                  a11y: "FC en reposo, aún sin voto, aprendiendo tu base."),
            .init(id: "sleep", glifo: .luna, nombre: "Sueño", sub: "según lo recomendado",
                  estado: .sinLectura, umbral: .minimo, fuera: false,
                  tonoVoto: LiquidColor.tinta500, palabra: "sin dato",
                  a11y: "Sueño, sin dato, según lo recomendado."),
        ])
    }
    .padding(LiquidSpace.s550)
    .background(LiquidSheetFondo(tone: LiquidColor.verdePrimario))
    .environment(\.liquidMotionDisabled, true)
}

#Preview("Boleta · AX5") {
    LiquidBoletaCard(votantes: [
        .init(id: "auto", glifo: .corazon, nombre: "FC en reposo", sub: "de la noche · contra tu base",
              estado: .fueraArriba, umbral: .rango, fuera: true,
              tonoVoto: LiquidColor.negativo, palabra: "fuera",
              hueMetrica: LiquidColor.rosa,
              a11y: "FC en reposo, votó fuera, contra tu base, fuera de tu rango."),
        .init(id: "sleep", glifo: .luna, nombre: "Sueño", sub: "anoche · según lo recomendado",
              estado: .fueraAbajo, umbral: .minimo, fuera: true,
              tonoVoto: LiquidColor.negativo, palabra: "fuera",
              hueMetrica: LiquidColor.indigo,
              a11y: "Sueño, votó fuera, anoche según lo recomendado, fuera de tu rango."),
    ])
    .padding(LiquidSpace.s550)
    .background(LiquidSheetFondo(tone: LiquidColor.negativo))
    .environment(\.dynamicTypeSize, .accessibility5)
    .environment(\.liquidMotionDisabled, true)
}
#endif
