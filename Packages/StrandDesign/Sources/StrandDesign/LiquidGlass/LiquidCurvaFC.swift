import SwiftUI

// MARK: - Liquid Glass · Curva FC 24h (épico hoja de resumen, F4)
//
// La curva continua de frecuencia cardiaca del día (heart_rate, variante clásica):
// cabecera título/subtítulo + último bpm, el plot alto (260, paridad
// `MetricInfoSheet:914`) con el mismo motor y scrub de la familia, y el pie de stats
// min/prom/max YA formateados por el caller (contrato §3 F4).
//
// Sin bandas ni ticks: la curva FC habla sola; el contexto lo dan el último valor y las
// stats. Estados `.cargando` (skeleton sobrio) y `.vacio` (mensaje del caller).

public struct LiquidCurvaFC: View {
    private let titulo: String
    private let subtitulo: String
    private let ultimo: String?
    private let puntos: [(fecha: Date, valor: Double)]
    private let dominio: ClosedRange<Double>
    private let stats: (min: String, prom: String, max: String)?
    /// Rótulos localizados de las tres stats («MÍN/PROM/MÁX»). El contrato §3 F4 no los
    /// lista, pero el DS no puede inventar copy (D3) — el caller los pasa junto a los
    /// valores; `nil` = solo valores.
    private let statsEtiquetas: (min: String, prom: String, max: String)?
    private let formatoScrub: (Double, Date) -> String
    private let estado: LiquidChartEstado
    /// Rótulo de VoiceOver (regla de a11y de la familia; añadido igual que en el trend).
    private let a11yLabel: String
    /// SOLO previews/arnés: overlay de scrub asentado en un índice fijo.
    var scrubFijo: Int? = nil

    public init(titulo: String,
                subtitulo: String,
                ultimo: String? = nil,
                puntos: [(fecha: Date, valor: Double)],
                dominio: ClosedRange<Double>,
                stats: (min: String, prom: String, max: String)? = nil,
                statsEtiquetas: (min: String, prom: String, max: String)? = nil,
                formatoScrub: @escaping (Double, Date) -> String,
                estado: LiquidChartEstado,
                a11yLabel: String) {
        self.titulo = titulo
        self.subtitulo = subtitulo
        self.ultimo = ultimo
        self.puntos = puntos
        self.dominio = dominio
        self.stats = stats
        self.statsEtiquetas = statsEtiquetas
        self.formatoScrub = formatoScrub
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
                            ticksY: [], tono: LiquidColor.rosa,
                            puntoHoy: puntos.last, hoyAnillo: false,
                            formatoScrub: formatoScrub,
                            alto: LiquidChartAlto.curvaFC,
                            scrubFijo: scrubFijo)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: a11yLabel))
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
    var curva = LiquidCurvaFC(
        titulo: "Pulsaciones por minuto",
        subtitulo: "Promedio de 5 min · desde medianoche",
        ultimo: "72 lpm",
        puntos: curvaDemo(),
        dominio: 40...105,
        stats: (min: "48", prom: "64", max: "98"),
        statsEtiquetas: (min: "Mín", prom: "Prom", max: "Máx"),
        formatoScrub: { v, _ in "\(Int(v)) lpm · 2 pm" },
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
