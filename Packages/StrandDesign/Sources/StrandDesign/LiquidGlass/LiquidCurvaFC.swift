import SwiftUI

// MARK: - Liquid Glass · Curva FC 24h (épico hoja de resumen, F4)
//
// La curva continua de frecuencia cardiaca del día (heart_rate, variante clásica):
// cabecera título/subtítulo + último bpm, el plot alto (260, paridad
// `MetricInfoSheet:914`) con el mismo motor y scrub de la familia, y el pie de stats
// min/prom/max YA formateados por el caller (contrato §3 F4).
//
// Sin bandas de clasificación: la curva FC habla sola; el contexto lo dan el último valor,
// las stats y, opcionales, los ticks del eje Y, la referencia punteada y el punto marcado
// (ver TND-23 abajo). Estados `.cargando` (skeleton sobrio) y `.vacio` (mensaje del caller).
//
// FER-103 · TND-23 (detalle de FC intradía): la pieza aprende dos contextos OPCIONALES que
// el papel ya dibujaba y que sin ellos se perderían en la migración — `referencia` (la FC
// en reposo de anoche como punteada horizontal, contexto en tinta) y `puntoMarcado` (el
// PICO del día: la joya se ancla ahí en vez del último punto). Ambos con default `nil`,
// así que la hoja de Hoy no cambia ni un pixel.

public struct LiquidCurvaFC: View {
    private let titulo: String
    private let subtitulo: String
    private let ultimo: String?
    private let puntos: [(fecha: Date, valor: Double)]
    private let dominio: ClosedRange<Double>
    /// Punteada horizontal de referencia (la FC en reposo de anoche). El valor viene en el
    /// dominio del caller y la etiqueta que lo nombra vive en su caption (paridad del
    /// papel, `peakRestingCaption`). `nil` = sin línea. (TND-23)
    private let referencia: Double?
    /// El punto MARCADO de la curva (el pico del día): la joya se ancla ahí en vez del
    /// último punto. `nil` = joya en el último punto, el comportamiento de siempre. (TND-23)
    private let puntoMarcado: (fecha: Date, valor: Double)?
    private let stats: (min: String, prom: String, max: String)?
    /// Rótulos localizados de las tres stats («MÍN/PROM/MÁX»). El contrato §3 F4 no los
    /// lista, pero el DS no puede inventar copy (D3) — el caller los pasa junto a los
    /// valores; `nil` = solo valores.
    private let statsEtiquetas: (min: String, prom: String, max: String)?
    private let ticksY: [(valor: Double, etiqueta: String)]
    private let formatoScrub: ((Double, Date) -> String)?
    private let formatoValorScrub: ((Double) -> String)?
    private let formatoFechaScrub: ((Date) -> String)?
    private let formatoFechaEje: ((Date) -> String)?
    private let estado: LiquidChartEstado
    /// Rótulo de VoiceOver (regla de a11y de la familia; añadido igual que en el trend).
    private let a11yLabel: String
    /// SOLO previews/arnés: overlay de scrub asentado en un índice fijo.
    var scrubFijo: Int? = nil

    /// El punto bajo el dedo (lo publica el plot); mueve el `accessibilityValue`.
    @State private var iScrub: Int? = nil

    public init(titulo: String,
                subtitulo: String,
                ultimo: String? = nil,
                puntos: [(fecha: Date, valor: Double)],
                dominio: ClosedRange<Double>,
                referencia: Double? = nil,
                puntoMarcado: (fecha: Date, valor: Double)? = nil,
                stats: (min: String, prom: String, max: String)? = nil,
                statsEtiquetas: (min: String, prom: String, max: String)? = nil,
                ticksY: [(valor: Double, etiqueta: String)] = [],
                formatoScrub: ((Double, Date) -> String)? = nil,
                formatoValorScrub: ((Double) -> String)? = nil,
                formatoFechaScrub: ((Date) -> String)? = nil,
                formatoFechaEje: ((Date) -> String)? = nil,
                estado: LiquidChartEstado,
                a11yLabel: String) {
        self.titulo = titulo
        self.subtitulo = subtitulo
        self.ultimo = ultimo
        self.puntos = puntos
        self.dominio = dominio
        self.referencia = referencia
        self.puntoMarcado = puntoMarcado
        self.stats = stats
        self.statsEtiquetas = statsEtiquetas
        self.ticksY = ticksY
        self.formatoScrub = formatoScrub
        self.formatoValorScrub = formatoValorScrub
        self.formatoFechaScrub = formatoFechaScrub
        self.formatoFechaEje = formatoFechaEje
        self.estado = estado
        self.a11yLabel = a11yLabel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s300) {
            cabecera
            grafica
            if case .datos = estado, let stats {
                pieStats(stats)
            }
        }
    }

    private var cabecera: some View {
        HStack(alignment: .firstTextBaseline, spacing: LiquidSpace.s200) {
            VStack(alignment: .leading, spacing: LiquidSpace.s050) {
                Text(verbatim: titulo)
                    .font(LiquidType.titulo)
                    .foregroundStyle(LiquidColor.tinta900)
                Text(verbatim: subtitulo)
                    .font(LiquidType.captionLectura)
                    .foregroundStyle(LiquidColor.tinta500)
            }
            Spacer(minLength: LiquidSpace.s200)
            if let ultimo {
                Text(verbatim: ultimo)
                    .font(LiquidType.datoMenor)
                    .foregroundStyle(LiquidColor.rosa)
            }
        }
    }

    @ViewBuilder private var grafica: some View {
        switch estado {
        case .datos:
            LiquidChartPlot(puntos: puntos, bandas: [], dominio: dominio,
                            ticksY: ticksY, tono: LiquidColor.rosa,
                            // TND-23: con pico marcado la joya se ancla en el pico (la
                            // lectura que el caption nombra); sin él, en el último punto.
                            puntoHoy: puntoMarcado ?? puntos.last, hoyAnillo: false,
                            lineaRef: referencia,
                            formatoScrub: formatoScrub,
                            formatoValorScrub: formatoValorScrub,
                            formatoFechaScrub: formatoFechaScrub,
                            formatoFechaEje: formatoFechaEje,
                            // El eje de esta curva es el RELOJ, no el índice: los buckets
                            // vacíos no existen en la consulta (`GROUP BY ts / bucket`), así
                            // que repartir por índice etiquetaría «7 a. m. · 8 a. m. · 7 p. m.»
                            // a distancias iguales y afirmaría una linealidad que el motor
                            // no da. Con mapeo por tiempo, cada marca cae donde de verdad
                            // ocurrió.
                            mapeoPorTiempo: true,
                            alto: LiquidChartAlto.curvaFC,
                            scrubFijo: scrubFijo,
                            onScrub: { (i: Int?) in iScrub = i })
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: a11yLabel))
                .accessibilityValue(Text(verbatim: valorA11y))
        case .cargando:
            LiquidChartCargando(alto: LiquidChartAlto.curvaFC)
        case .vacio(let mensaje):
            LiquidChartVacio(mensaje: mensaje, alto: LiquidChartAlto.curvaFC)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: "\(a11yLabel). \(mensaje)"))
        }
    }

    private func pieStats(_ stats: (min: String, prom: String, max: String)) -> some View {
        HStack {
            statTile(etiqueta: statsEtiquetas?.min, valor: stats.min)
            Spacer(minLength: LiquidSpace.s200)
            statTile(etiqueta: statsEtiquetas?.prom, valor: stats.prom)
            Spacer(minLength: LiquidSpace.s200)
            statTile(etiqueta: statsEtiquetas?.max, valor: stats.max)
        }
    }

    private func statTile(etiqueta: String?, valor: String) -> some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s050) {
            if let etiqueta {
                Text(verbatim: etiqueta)
                    .font(LiquidType.microEstado)
                    .textCase(.uppercase)
                    .foregroundStyle(LiquidColor.tinta500)
            }
            Text(verbatim: valor)
                .font(LiquidType.datoMenor)
                .foregroundStyle(LiquidColor.tinta700)
        }
        .accessibilityElement(children: .combine)
    }

    /// VoiceOver nombra el punto SCRUBBEADO (o el último) con la frase compuesta del
    /// caller; el DS no une valor + hora por su cuenta (contrato D3).
    private var valorA11y: String {
        guard !puntos.isEmpty else { return "" }
        let p = puntos[LiquidChartA11y.indice(iScrub, puntos.count)]
        if let f = formatoScrub { return f(p.valor, p.fecha) }
        if let f = formatoValorScrub { return f(p.valor) }
        return ""
    }
}

#if DEBUG
private func curvaDemo() -> [(fecha: Date, valor: Double)] {
    let inicio: Date = Calendar.current.startOfDay(for: Date())
    return (0..<160).map { (i: Int) -> (fecha: Date, valor: Double) in
        let t: Double = Double(i) / 160.0
        let base: Double = 62.0 + 26.0 * sin(t * .pi * 3.1) * sin(t * .pi)
        let ruido: Double = Double((i * 13) % 9) - 4.0
        return (fecha: inicio.addingTimeInterval(Double(i) * 300.0), valor: base + ruido)
    }
}

#Preview("Liquid · Curva FC — datos") {
    let relojFmt: (Date) -> String = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("ha")
        return { (d: Date) -> String in f.string(from: d) }
    }()
    let popupFmt: (Date) -> String = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("jmm")
        return { (d: Date) -> String in f.string(from: d) }
    }()
    // TND-23: la punteada de referencia (FC en reposo) y la joya anclada al PICO del día.
    let demo = curvaDemo()
    let pico = demo.max { $0.valor < $1.valor }
    var curva = LiquidCurvaFC(
        titulo: "Pulsaciones por minuto",
        subtitulo: "Promedio de 5 min · desde medianoche",
        ultimo: "72 lpm",
        puntos: demo,
        dominio: 40...105,
        referencia: 52,
        puntoMarcado: pico,
        stats: (min: "48", prom: "64", max: "98"),
        statsEtiquetas: (min: "Mín", prom: "Prom", max: "Máx"),
        ticksY: [(100, "100"), (70, "70"), (45, "45")],
        formatoScrub: { v, _ in "\(Int(v)) lpm · 2 pm" },
        formatoValorScrub: { v in "\(Int(v)) lpm" },
        formatoFechaScrub: popupFmt,
        formatoFechaEje: relojFmt,
        estado: .datos,
        a11yLabel: "Frecuencia cardiaca de hoy")
    curva.scrubFijo = 90
    return curva
        .padding(LiquidSpace.s550)
        .background(LiquidSheetFondo(tone: LiquidColor.rosa))
        .environment(\.liquidMotionDisabled, true)
}

#Preview("Liquid · Curva FC — cargando y vacío") {
    VStack(alignment: .leading, spacing: LiquidSpace.s550) {
        LiquidCurvaFC(
            titulo: "Pulsaciones por minuto",
            subtitulo: "Promedio de 5 min · desde medianoche",
            puntos: [], dominio: 40...120,
            formatoScrub: { v, _ in "\(Int(v)) lpm" },
            estado: .cargando,
            a11yLabel: "Frecuencia cardiaca de hoy")
        LiquidCurvaFC(
            titulo: "Pulsaciones por minuto",
            subtitulo: "Promedio de 5 min · desde medianoche",
            puntos: [], dominio: 40...120,
            formatoScrub: { v, _ in "\(Int(v)) lpm" },
            estado: .vacio("Sin lecturas todavía hoy."),
            a11yLabel: "Frecuencia cardiaca de hoy")
    }
    .padding(LiquidSpace.s550)
    .background(LiquidSheetFondo(tone: LiquidColor.rosa))
    .environment(\.liquidMotionDisabled, true)
}
#endif
