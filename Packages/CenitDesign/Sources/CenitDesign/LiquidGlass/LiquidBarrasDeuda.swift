import SwiftUI

// MARK: - Liquid Glass · Barras de deuda de sueño (port de `DebtBars`)
//
// La semana de deuda de la hoja de Sueño: una barra por noche medida contra tu necesidad
// (la regla del cero). Debajo de la regla es DEUDA (dormiste menos de lo que necesitas);
// encima es superávit. Port de `DebtBars.swift` (FER-249, Swift Charts) al sistema Liquid,
// con la geometría del papel intacta —regla de 1 pt, esquinas de 2, alto de 96, franja de
// etiquetas de día debajo, scrub con regla vertical punteada y tooltip— pero pintado con
// formas nativas y tokens Liquid, como TODA la familia de gráficas Liquid.
//
// Contrato: cada `etiqueta` («L», «M», …) llega YA localizada del caller, igual que
// `a11yLabel` / `a11yValue`; el paquete no conoce locales ni formatos.
//
// ─────────────────────────────────────────────────────────────────────────────────────
// LO QUE MEJORA SOBRE EL PAPEL — `nil` y `0` dejan de ser lo mismo
//
// `DebtBars` recibe `vsNeedMin: Double` (no opcional) y por construcción NO puede
// distinguir «esa noche no se midió» de «esa noche no hubo deuda»: las dos llegan como 0 y
// las dos se dibujan como nada. Una noche sin medir terminaba leyéndose como una noche
// perfecta — la peor mentira posible en una pantalla que existe para decirte cuánto debes.
//
// Aquí `minutos` es `Double?` y los dos estados se ven distinto:
//   · `nil` → riel VACÍO en tinta tenue, sin barra. El hueco de la semana se ve.
//   · `0`   → barra a CERO visible, asentada sobre la regla, en el tono del superávit
//             (el cero cuenta como superávit: cumpliste tu necesidad, no la debiste).
// ─────────────────────────────────────────────────────────────────────────────────────
//
// ESCALA ESTABLE — `maximo` lo manda el CALLER. El componente NO normaliza contra su propio
// máximo local: si lo hiciera, una semana de −20 min y una de −3 h dibujarían exactamente
// las mismas barras y la gráfica dejaría de comparar semanas (que es lo único para lo que
// sirve). El papel dejaba que Swift Charts derivara el dominio de los datos y caía justo en
// ese pozo. Contrato del caller: `maximo` debe cubrir la peor noche de la ventana — una
// noche por encima del tope se RECORTA al tope y deja de leerse como magnitud.
//
// De ahí sale la otra diferencia con el papel: la regla del cero va CENTRADA y el dominio es
// simétrico (±`maximo`). En el papel la regla flotaba donde cayera el dominio automático, así
// que su altura cambiaba de semana a semana; centrada, la línea de tu necesidad está siempre
// en el mismo sitio y dos semanas se pueden mirar una junto a otra. Se paga con la mitad del
// alto por lado — el precio de que la escala no mienta.
//
// El eje Y del papel iba en HORAS (`vsNeedMin / 60`); con el eje oculto —que es como el papel
// lo dibuja y como se consume— esa división es inerte: la barra depende solo de la fracción
// `minutos / maximo`, idéntica en horas o en minutos. Aquí la unidad es una sola (minutos) y
// no hay conversión que se pueda desincronizar del `maximo` del caller.
public struct LiquidBarrasDeuda: View {

    /// Una noche de la semana.
    public struct Dia: Identifiable, Equatable, Sendable {
        public let id: String
        /// La letra del día («L», «M», …) YA localizada por el caller.
        public let etiqueta: String
        /// Deuda de esa noche en MINUTOS, con signo: `< 0` te quedaste corto (deuda),
        /// `> 0` le ganaste a tu necesidad (superávit).
        /// **`nil` = esa noche NO se midió** — distinto de `0`, que es «se midió y no hubo
        /// deuda». Ver la nota de cabecera: confundirlos hace que un hueco se lea como una
        /// noche perfecta.
        public let minutos: Double?
        public let esHoy: Bool
        /// La SEGUNDA línea del popup: cuánto dormiste esa noche, YA formateado
        /// («dormiste 7h 30m»). El papel la tenía (`sleptMin` + `sleptFormat`) y el caller
        /// real la pasa; el port la había borrado. Sin ella el popup dice cuánto le debes a
        /// la noche pero no cuánto dormiste — la mitad de la lectura.
        public let detalle: String?

        public init(id: String, etiqueta: String, minutos: Double?, esHoy: Bool,
                    detalle: String? = nil) {
            self.id = id
            self.etiqueta = etiqueta
            self.minutos = minutos
            self.esHoy = esHoy
            self.detalle = detalle
        }
    }

    private let dias: [Dia]
    private let tono: Color
    private let maximo: Double
    private let a11yLabel: String
    private let a11yValue: String
    private let formatoValor: ((Double) -> String)?

    /// - Parameters:
    ///   - dias: la semana, en orden. `minutos == nil` = noche sin medir.
    ///   - tono: la identidad de la SEÑAL de esta gráfica, que es la deuda — el sujeto de
    ///     la sección. Tiñe las barras de DÉFICIT (la hoja de Sueño pasa
    ///     `LiquidColor.atencion`). El superávit NO es del caller: es siempre
    ///     `LiquidColor.positivo`, porque «le ganaste a tu necesidad» es un veredicto fijo,
    ///     no la identidad de una sección.
    ///   - maximo: el tope de la escala, en MINUTOS (misma unidad que `minutos`). Lo manda
    ///     el caller para que la escala sea estable entre semanas — ver la nota de cabecera.
    ///   - a11yLabel: qué es la gráfica, YA localizado.
    ///   - a11yValue: qué DICE la gráfica, YA localizado. **No es opcional a propósito**: el
    ///     papel dejaba el `accessibilityValue` a criterio del consumidor y la gráfica salió
    ///     muda. Aquí el tipo obliga al caller a decir cuántas noches tienen dato y cuánta
    ///     deuda suman.
    ///   - formatoValor: formatea los minutos de una noche para el tooltip del scrub. `nil`
    ///     (por defecto) = el scrub solo corta con la regla vertical, sin tooltip: el DS no
    ///     puede inventar «−1 h 30 m» sin conocer el locale del producto.
    public init(dias: [Dia],
                tono: Color,
                maximo: Double,
                a11yLabel: String,
                a11yValue: String,
                formatoValor: ((Double) -> String)? = nil) {
        self.dias = dias
        self.tono = tono
        self.maximo = maximo
        self.a11yLabel = a11yLabel
        self.a11yValue = a11yValue
        self.formatoValor = formatoValor
    }

    @State private var indiceScrub: Int?
    @State private var tooltipMedido: CGSize = .zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.liquidMotionDisabled) private var motionDisabled

    // MARK: Geometría interna (paridad `DebtBars`)

    /// Alto TOTAL, etiquetas de día incluidas — el `height: 96` que el papel recibe y que la
    /// hoja de Sueño pasa explícito. Es fijo: si creciera con el contenido, la sección
    /// brincaría entre una semana con huecos y una completa.
    private let altoTotal: CGFloat = 96
    /// Radio de la barra — el `.cornerRadius(2)` del `BarMark` del papel. No hay token: es
    /// el redondeo de un dato de 2 pt, no un radio de layout (`LiquidRadius` empieza en 12).
    private let radioBarra: CGFloat = 2
    /// Grosor de la regla del cero — el `lineWidth: 1` del `RuleMark` del papel.
    private let grosorRegla: CGFloat = 1
    /// Franja reservada ABAJO para la fila de letras de día, dentro del alto nominal.
    private var altoEje: CGFloat { LiquidChart.ejeXAlto }
    /// El área de datos: el alto total menos la franja del eje.
    private var altoPlot: CGFloat { altoTotal - altoEje }
    /// Respiro arriba y abajo: una barra a tope no besa el filo del marco.
    private var respiro: CGFloat { LiquidSpace.s100 }
    /// Lo que mide una noche MEDIDA sin deuda: la barra a cero tiene que verse. Es lo que
    /// separa «medí y no debiste» de «no medí» — el invariante de esta pieza.
    private var altoBarraCero: CGFloat { LiquidSpace.s075 }
    /// Canal entre barras vecinas.
    private var canal: CGFloat { LiquidSpace.s200 }

    // MARK: Escala (el contrato testeable de la pieza)

    /// La fracción del medio-alto que ocupa la barra de una noche, con signo.
    ///
    /// `nil` = **sin dato** (no hay barra: se pinta el riel vacío). `0` = **medida y sin
    /// deuda** (barra a cero, visible). Son ramas distintas del render, y este es el punto
    /// donde se separan — por eso el test las afirma aquí y no en un snapshot.
    ///
    /// Se divide entre `maximo`, NUNCA entre el máximo local de `dias`.
    static func alturaFraccion(minutos: Double?, maximo: Double) -> Double? {
        guard let minutos else { return nil }
        // Sin escala no hay altura que afirmar: la noche se asienta en la base (que sigue
        // siendo visible), jamás en el tope.
        guard maximo > 0 else { return 0 }
        return Swift.max(-1, Swift.min(1, minutos / maximo))
    }

    /// El cero cuenta como SUPERÁVIT (paridad literal del papel: `vsNeedMin < 0 ? deficit :
    /// surplus`). Cumplir tu necesidad no es deberla.
    static func esDeficit(_ minutos: Double) -> Bool { minutos < 0 }

    // MARK: Body

    public var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let medio = h / 2
                ZStack(alignment: .topLeading) {
                    // Blanco de toque a sangre: el scrub arranca al primer contacto, no
                    // solo sobre una barra (mismo arreglo que el papel, #118).
                    Color.clear
                    rieles(w, h)
                    regla(w, medio)
                    barras(w, medio)
                    if let i = indiceScrub, dias.indices.contains(i) {
                        overlayScrub(i, w, h)
                    }
                }
                .contentShape(Rectangle())
                // El pan que NO se roba el scroll: esta gráfica vive dentro del scroll de la
                // hoja de Sueño, y un `DragGesture` a secas congela la página en cuanto el
                // dedo arranca sobre ella (FER-73).
                .liquidScrubPan(
                    enabled: dias.count > 1,
                    onChange: { p in indiceScrub = indice(desdeX: p.x, ancho: w) },
                    onEnd: { indiceScrub = nil })
            }
            .frame(height: altoPlot)
            etiquetas
        }
        .frame(maxWidth: .infinity)
        .frame(height: altoTotal)
        // SNAP, no morph, al cambiar de semana (paridad `.animation(.none, value: nights)`).
        // Interpolar entre dos semanas distintas dibuja barras que nunca existieron y afirma
        // una continuidad que los datos no tienen.
        .animation(nil, value: dias)
        .animation(animacionScrub, value: indiceScrub)
        .onChange(of: indiceScrub) { _, nuevo in
            // Háptica solo al caer en una noche nueva, nunca al soltar (paridad de la familia).
            if nuevo != nil { ChartHaptics.datumChanged() }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: a11yLabel))
        .accessibilityValue(Text(verbatim: a11yValue))
    }

    /// Con Reduce Motion (o motion congelado en previews/renders) el corte del scrub aparece
    /// COLOCADO, sin viaje.
    private var animacionScrub: Animation? {
        (reduceMotion || motionDisabled) ? nil : LiquidMotion.lift
    }

    // MARK: Capas

    /// El riel vacío de una noche SIN DATO. Ocupa el mismo hueco que ocuparía su barra, en
    /// tinta tenue: se ve que la ranura existe y que nadie la llenó.
    @ViewBuilder private func rieles(_ w: CGFloat, _ h: CGFloat) -> some View {
        let ancho = anchoBarra(w)
        ForEach(Array(dias.enumerated()), id: \.element.id) { i, dia in
            if dia.minutos == nil {
                RoundedRectangle(cornerRadius: radioBarra, style: .continuous)
                    .fill(LiquidColor.tinta7)
                    .frame(width: ancho, height: Swift.max(0, h - respiro * 2))
                    .offset(x: centro(i, w) - ancho / 2, y: respiro)
            }
        }
    }

    /// La regla del cero: TU NECESIDAD. Todo lo que cuelga de ella es lo que le debes al
    /// cuerpo. El papel le admite una anotación de texto; el consumidor real nunca la pasa,
    /// así que aquí la línea va desnuda y ningún string se inventa.
    private func regla(_ w: CGFloat, _ medio: CGFloat) -> some View {
        Rectangle()
            .fill(LiquidColor.tinta10)
            .frame(width: w, height: grosorRegla)
            .offset(y: medio - grosorRegla / 2)
    }

    @ViewBuilder private func barras(_ w: CGFloat, _ medio: CGFloat) -> some View {
        let ancho = anchoBarra(w)
        let util = Swift.max(0, medio - respiro)
        ForEach(Array(dias.enumerated()), id: \.element.id) { i, dia in
            if let minutos = dia.minutos,
               let f = Self.alturaFraccion(minutos: minutos, maximo: maximo) {
                let deficit = Self.esDeficit(minutos)
                // Piso de altura: una noche medida SIEMPRE deja marca sobre la regla, aunque
                // su deuda sea 0 o casi 0.
                let alto = Swift.max(altoBarraCero, CGFloat(abs(f)) * util)
                RoundedRectangle(cornerRadius: radioBarra, style: .continuous)
                    .fill(color(deficit: deficit))
                    .frame(width: ancho, height: alto)
                    .offset(x: centro(i, w) - ancho / 2,
                            y: deficit ? medio : medio - alto)
            }
        }
    }

    /// Las letras de día bajo el plot. Son CHROME geométrico y no escalan con Dynamic Type
    /// —misma decisión y misma exención que el eje X de la familia (`LiquidChart.ejeXAlto`)—:
    /// siete letras en un ancho de iPhone no tienen a dónde crecer sin encimarse. La lectura
    /// accesible la sirve el `accessibilityValue`, que sí escala sin tope.
    ///
    /// HOY se marca con la etiqueta en TINTA PLENA; su barra no cambia de relleno, para que
    /// el color siga diciendo una sola cosa (deuda vs superávit).
    /// Cada letra va CENTRADA en su columna con el mismo `centro(_:_:)` que las barras — un
    /// solo origen de verdad para la geometría horizontal. Repartirlas con un `HStack` de
    /// anchos flexibles las desincroniza de sus barras (las letras no miden todas lo mismo).
    private var etiquetas: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ForEach(Array(dias.enumerated()), id: \.element.id) { i, dia in
                Text(verbatim: dia.etiqueta)
                    .font(LiquidType.caption)
                    .foregroundStyle(dia.esHoy ? LiquidColor.tinta900 : LiquidColor.tinta500)
                    .lineLimit(1)
                    .fixedSize()
                    .position(x: centro(i, w), y: altoEje / 2)
            }
        }
        .frame(height: altoEje)
    }

    // MARK: Scrub (I2 — regla vertical punteada + tooltip)

    @ViewBuilder private func overlayScrub(_ i: Int, _ w: CGFloat, _ h: CGFloat) -> some View {
        let cx = centro(i, w)
        CrosshairRule(x: cx, height: h,
                      color: LiquidColor.tinta900.opacity(LiquidChart.scrubReglaAlfa))
        // Sin `formatoValor` no hay tooltip; y una noche SIN DATO tampoco lo tiene — no hay
        // número que decir, y fabricar «0 m» sería exactamente la mentira que esta pieza
        // existe para no contar.
        if let fmt = formatoValor, let minutos = dias[i].minutos {
            tooltip(texto: fmt(minutos),
                    detalle: dias[i].detalle,
                    deficit: Self.esDeficit(minutos),
                    cx: cx,
                    plot: CGSize(width: w, height: h))
        }
    }

    /// El popup de la familia, MEDIDO y colocado al lado del corte (nunca encima), anclado
    /// arriba como en el papel (`plot.minY + 8`) y clampeado al área de datos.
    private func tooltip(texto: String, detalle: String?, deficit: Bool,
                         cx: CGFloat, plot: CGSize) -> some View {
        let tam: CGSize = tooltipMedido == .zero ? CGSize(width: 72, height: 30) : tooltipMedido
        let p = ChartTooltipPlacement.positionBeside(
            anchor: CGPoint(x: cx, y: LiquidSpace.s200),
            tooltipSize: tam,
            in: plot,
            gap: LiquidSpace.s200)
        // La segunda línea es «cuánto dormiste», que el papel sí decía (`sleptFormat`) y el
        // caller real pasa. La primera dice cuánto le debes a la noche; sin la segunda, la
        // lectura queda a medias.
        return LiquidScrubPopup(valor: texto, fecha: detalle, color: color(deficit: deficit))
            .background {
                GeometryReader { g in
                    Color.clear
                        .onAppear { tooltipMedido = g.size }
                        .onChange(of: g.size) { _, nuevo in tooltipMedido = nuevo }
                }
            }
            .position(x: p.x, y: p.y)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    // MARK: Mapeo

    /// El tono tiñe el DATO: la deuda lleva la identidad de la sección, el superávit el
    /// verde fijo del veredicto.
    private func color(deficit: Bool) -> Color { deficit ? tono : LiquidColor.positivo }

    /// Paso de columna: la semana se reparte por ÍNDICE, no por tiempo — cada `Dia` es un
    /// día y la ventana no tiene huecos de calendario (los huecos son de DATO, y esos los
    /// dice el riel vacío).
    private func paso(_ w: CGFloat) -> CGFloat {
        dias.isEmpty ? w : w / CGFloat(dias.count)
    }

    private func centro(_ i: Int, _ w: CGFloat) -> CGFloat {
        paso(w) * (CGFloat(i) + 0.5)
    }

    private func anchoBarra(_ w: CGFloat) -> CGFloat {
        Swift.max(radioBarra * 2, paso(w) - canal)
    }

    /// La noche bajo el dedo. Fuera del borde se queda en la primera/última (paridad del
    /// `nearestNight` del papel, que tampoco suelta la serie). La x se acota ANTES de dividir:
    /// un `Int(_:)` sobre un cociente infinito o NaN no se recorta, revienta.
    private func indice(desdeX x: CGFloat, ancho: CGFloat) -> Int? {
        guard !dias.isEmpty, ancho > 0, x.isFinite else { return nil }
        let p = paso(ancho)
        guard p > 0 else { return nil }
        let acotada = Swift.max(0, Swift.min(ancho, x))
        return Swift.min(dias.count - 1, Int(acotada / p))
    }
}

#if DEBUG
/// Formato de demo de las previews: el producto inyecta el suyo (el DS no conoce locales).
private func demoDeuda(_ m: Double) -> String {
    let v = Int(abs(m).rounded())
    let cuerpo = v >= 60 ? "\(v / 60) h \(v % 60) m" : "\(v) m"
    return m < 0 ? "−\(cuerpo)" : "+\(cuerpo)"
}

private let demoLetras = ["L", "M", "M", "J", "V", "S", "D"]

/// La semana típica: casi toda en deuda, un día que le ganó a la necesidad.
#Preview("Deuda · semana con deuda") {
    LiquidBarrasDeuda(
        dias: [
            LiquidBarrasDeuda.Dia(id: "0", etiqueta: "L", minutos: -30, esHoy: false),
            LiquidBarrasDeuda.Dia(id: "1", etiqueta: "M", minutos: -132, esHoy: false),
            LiquidBarrasDeuda.Dia(id: "2", etiqueta: "M", minutos: 18, esHoy: false),
            LiquidBarrasDeuda.Dia(id: "3", etiqueta: "J", minutos: -66, esHoy: false),
            LiquidBarrasDeuda.Dia(id: "4", etiqueta: "V", minutos: -24, esHoy: false),
            LiquidBarrasDeuda.Dia(id: "5", etiqueta: "S", minutos: -36, esHoy: false),
            LiquidBarrasDeuda.Dia(id: "6", etiqueta: "D", minutos: -30, esHoy: true),
        ],
        tono: LiquidColor.atencion,
        maximo: 180,
        a11yLabel: "Horas arriba o abajo de tu necesidad, cada una de las últimas 7 noches",
        a11yValue: "7 de 7 noches con dato, 5 h 18 m de deuda acumulada",
        formatoValor: demoDeuda)
    .padding(LiquidSpace.s550)
    .background(LiquidSheetFondo(tone: LiquidColor.atencion))
}

/// TODAS en 0: siete noches MEDIDAS, ninguna deuda. Se ven siete barras a cero asentadas
/// sobre la regla — el estado que el papel no sabía dibujar y que confundía con el hueco.
#Preview("Deuda · semana sin deuda") {
    LiquidBarrasDeuda(
        dias: (0..<7).map { (i: Int) -> LiquidBarrasDeuda.Dia in
            LiquidBarrasDeuda.Dia(id: "\(i)", etiqueta: demoLetras[i],
                                  minutos: 0, esHoy: i == 6)
        },
        tono: LiquidColor.atencion,
        maximo: 180,
        a11yLabel: "Horas arriba o abajo de tu necesidad, cada una de las últimas 7 noches",
        a11yValue: "7 de 7 noches con dato, sin deuda esta semana",
        formatoValor: demoDeuda)
    .padding(LiquidSpace.s550)
    .background(LiquidSheetFondo(tone: LiquidColor.atencion))
}

/// Dos noches SIN MEDIR (`nil`) junto a una noche medida sin deuda (`0`): el contraste que
/// da razón de ser a esta pieza. Riel vacío ≠ barra a cero.
#Preview("Deuda · con huecos") {
    LiquidBarrasDeuda(
        dias: [
            LiquidBarrasDeuda.Dia(id: "0", etiqueta: "L", minutos: -30, esHoy: false),
            LiquidBarrasDeuda.Dia(id: "1", etiqueta: "M", minutos: nil, esHoy: false),
            LiquidBarrasDeuda.Dia(id: "2", etiqueta: "M", minutos: 0, esHoy: false),
            LiquidBarrasDeuda.Dia(id: "3", etiqueta: "J", minutos: -96, esHoy: false),
            LiquidBarrasDeuda.Dia(id: "4", etiqueta: "V", minutos: nil, esHoy: false),
            LiquidBarrasDeuda.Dia(id: "5", etiqueta: "S", minutos: -42, esHoy: false),
            LiquidBarrasDeuda.Dia(id: "6", etiqueta: "D", minutos: -12, esHoy: true),
        ],
        tono: LiquidColor.atencion,
        maximo: 180,
        a11yLabel: "Horas arriba o abajo de tu necesidad, cada una de las últimas 7 noches",
        a11yValue: "5 de 7 noches con dato, 3 h de deuda acumulada; 2 noches sin medir",
        formatoValor: demoDeuda)
    .padding(LiquidSpace.s550)
    .background(LiquidSheetFondo(tone: LiquidColor.atencion))
}

/// AX: las letras del eje son chrome y no crecen (misma exención que el eje X de la
/// familia), así que la gráfica se ve igual y nada se recorta. Quien usa AX la lee por
/// VoiceOver, y ese texto sí escala sin tope.
#Preview("Deuda · AX") {
    LiquidBarrasDeuda(
        dias: [
            LiquidBarrasDeuda.Dia(id: "0", etiqueta: "L", minutos: -30, esHoy: false),
            LiquidBarrasDeuda.Dia(id: "1", etiqueta: "M", minutos: nil, esHoy: false),
            LiquidBarrasDeuda.Dia(id: "2", etiqueta: "M", minutos: 0, esHoy: false),
            LiquidBarrasDeuda.Dia(id: "3", etiqueta: "J", minutos: -96, esHoy: false),
            LiquidBarrasDeuda.Dia(id: "4", etiqueta: "V", minutos: -24, esHoy: false),
            LiquidBarrasDeuda.Dia(id: "5", etiqueta: "S", minutos: -42, esHoy: false),
            LiquidBarrasDeuda.Dia(id: "6", etiqueta: "D", minutos: -12, esHoy: true),
        ],
        tono: LiquidColor.atencion,
        maximo: 180,
        a11yLabel: "Horas arriba o abajo de tu necesidad, cada una de las últimas 7 noches",
        a11yValue: "6 de 7 noches con dato, 3 h 24 m de deuda acumulada; 1 noche sin medir",
        formatoValor: demoDeuda)
    .padding(LiquidSpace.s550)
    .background(LiquidSheetFondo(tone: LiquidColor.atencion))
    .environment(\.dynamicTypeSize, .accessibility3)
}
#endif
