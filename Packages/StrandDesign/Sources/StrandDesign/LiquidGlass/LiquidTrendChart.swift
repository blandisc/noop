import SwiftUI

// MARK: - Liquid Glass · Trend 14d del template clásico (épico hoja de resumen, F4)
//
// La gráfica «Últimos 14 días» de la variante clásica, con la MISMA gramática que
// `LiquidGraficaNiveles` (mismo motor, mismos washes I1, mismo scrub I2). El readout
// «{banda} · X de N días/noches» vive UNA vez, arriba (paridad FER-469/471,
// `MetricInfoSheet:852-882`), con la frase YA compuesta por el caller.
//
// Estados: `.datos` pinta el plot; `.cargando` un skeleton sobrio y estático; `.vacio`
// el mensaje del caller. Todo string llega ya localizado (contrato D3).

public struct LiquidTrendChart: View {
    /// Densidad visual del envoltorio. `.trend` es la gráfica de 14 días de la hoja
    /// (título + readout + ejes). `.mini` es el renglón del guardián: solo plot a
    /// `LiquidChartAlto.mini`, sin título/readout/ejes; hereda scrub y rotor VoiceOver.
    public enum Densidad: Sendable { case trend, mini }

    private let titulo: String
    private let readout: (etiqueta: String, tono: Color, frase: String)?
    private let puntos: [(fecha: Date, valor: Double)]
    private let bandas: [LiquidChartBanda]
    private let dominio: ClosedRange<Double>
    private let ticksY: [(valor: Double, etiqueta: String)]
    private let tono: Color
    private let formatoScrub: ((Double, Date) -> String)?
    private let formatoValorScrub: ((Double) -> String)?
    private let formatoFechaScrub: ((Date) -> String)?
    private let formatoFechaEje: ((Date) -> String)?
    /// Punto de HOY: se pinta como joya blanca (relleno papel, filo del tono) vía el plot.
    private let puntoHoy: (fecha: Date, valor: Double)?
    /// Si true, la joya de hoy se dibuja como anillo hueco (misma semántica que el explorador).
    private let hoyAnillo: Bool
    private let estado: LiquidChartEstado
    /// Rótulo de VoiceOver del plot (el contrato §3 F4 no lo lista; la regla de a11y de la
    /// familia — «cada gráfica con el a11yLabel del caller» — lo exige, así que se añade).
    private let a11yLabel: String
    private let densidad: Densidad
    /// SOLO previews/arnés: overlay de scrub asentado en un índice fijo.
    var scrubFijo: Int? = nil

    /// El punto bajo el dedo (lo publica el plot); mueve el `accessibilityValue`.
    @State private var iScrub: Int? = nil

    public init(titulo: String,
                readout: (etiqueta: String, tono: Color, frase: String)? = nil,
                puntos: [(fecha: Date, valor: Double)],
                bandas: [LiquidChartBanda],
                dominio: ClosedRange<Double>,
                ticksY: [(valor: Double, etiqueta: String)],
                tono: Color,
                formatoScrub: ((Double, Date) -> String)? = nil,
                formatoValorScrub: ((Double) -> String)? = nil,
                formatoFechaScrub: ((Date) -> String)? = nil,
                formatoFechaEje: ((Date) -> String)? = nil,
                puntoHoy: (fecha: Date, valor: Double)? = nil,
                hoyAnillo: Bool = false,
                estado: LiquidChartEstado,
                a11yLabel: String,
                densidad: Densidad = .trend) {
        self.titulo = titulo
        self.readout = readout
        self.puntos = puntos
        self.bandas = bandas
        self.dominio = dominio
        self.ticksY = ticksY
        self.tono = tono
        self.formatoScrub = formatoScrub
        self.formatoValorScrub = formatoValorScrub
        self.formatoFechaScrub = formatoFechaScrub
        self.formatoFechaEje = formatoFechaEje
        self.puntoHoy = puntoHoy
        self.hoyAnillo = hoyAnillo
        self.estado = estado
        self.a11yLabel = a11yLabel
        self.densidad = densidad
    }

    /// Alto del plot / pozos según densidad. El 32 vive en `LiquidChartAlto`, no aquí.
    private var altoPlot: CGFloat {
        densidad == .mini ? LiquidChartAlto.mini : LiquidChartAlto.trend
    }

    /// En `.mini` no caben ejes: se vacían aunque el caller mande ticks o formato.
    private var ticksYEfectivos: [(valor: Double, etiqueta: String)] {
        densidad == .mini ? [] : ticksY
    }
    private var formatoFechaEjeEfectivo: ((Date) -> String)? {
        densidad == .mini ? nil : formatoFechaEje
    }

    public var body: some View {
        // `.mini` es un renglón: sin título ni readout (el nombre de la señal vive arriba).
        if densidad == .mini {
            grafica
        } else {
            VStack(alignment: .leading, spacing: LiquidSpace.s300) {
                Text(verbatim: titulo)
                    .font(LiquidType.titulo)
                    .foregroundStyle(LiquidColor.tinta900)
                if let readout {
                    (Text(verbatim: readout.etiqueta)
                        .foregroundColor(readout.tono)
                        .fontWeight(.semibold)
                     + Text(verbatim: " · ")
                        .foregroundColor(LiquidColor.tinta500)
                     + Text(verbatim: readout.frase)
                        .foregroundColor(LiquidColor.tinta700))
                        .font(LiquidType.cuerpo)
                        .fixedSize(horizontal: false, vertical: true)
                }
                grafica
            }
        }
    }

    @ViewBuilder private var grafica: some View {
        switch estado {
        case .datos:
            // FER-29: `LiquidChartPlot` publica `AXChartDescriptor` (rotor «Gráficas»).
            // El label/value de abajo se conservan: el rotor es adicional, no los reemplaza.
            // `.mini` hereda el descriptor sin trabajo extra (mismo plot, mismo motor).
            plotDatos
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: a11yLabel))
                .accessibilityValue(Text(verbatim: valorA11y))
        case .cargando:
            LiquidChartCargando(alto: altoPlot)
        case .vacio(let mensaje):
            LiquidChartVacio(mensaje: mensaje, alto: altoPlot)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: "\(a11yLabel). \(mensaje)"))
        }
    }

    /// Plot de datos. En `.mini` el trazo mide `LiquidChartAlto.mini` (32) y el
    /// contenedor reclama al menos `LiquidControl.hitTarget` (44) de alto táctil.
    @ViewBuilder private var plotDatos: some View {
        let plot = LiquidChartPlot(puntos: puntos, bandas: bandas, dominio: dominio,
                                   ticksY: ticksYEfectivos, tono: tono,
                                   puntoHoy: puntoHoy, hoyAnillo: hoyAnillo,
                                   formatoScrub: formatoScrub,
                                   formatoValorScrub: formatoValorScrub,
                                   formatoFechaScrub: formatoFechaScrub,
                                   formatoFechaEje: formatoFechaEjeEfectivo,
                                   // Mismo motivo que el explorador: la serie de 14 días de las
                                   // submétricas de sueño trae solo las NOCHES que existen. Con
                                   // reparto por índice, una semana sin registrar se dibujaba como
                                   // si fueran días consecutivos.
                                   mapeoPorTiempo: true,
                                   alto: altoPlot,
                                   scrubFijo: scrubFijo,
                                   onScrub: { (i: Int?) in iScrub = i })
        if densidad == .mini {
            // Trazo 32, área táctil ≥44 (HIG). El plot se centra en el renglón de 44.
            // `scrubGesture` vive dentro del GeometryReader a alto 32: el drag real sigue
            // midiendo 32; este frame+contentShape reclama 44 al árbol exterior (a11y y
            // competencia con el ScrollView de la hoja). Ampliar el drag a 44 pediría el
            // mismo pad dentro del motor, fuera del alcance de F3b.
            plot
                .frame(minHeight: LiquidControl.hitTarget)
                .contentShape(Rectangle())
        } else {
            plot
        }
    }

    /// VoiceOver nombra el punto SCRUBBEADO (o el último) con la frase compuesta del
    /// caller; el DS no une valor + fecha por su cuenta (contrato D3).
    private var valorA11y: String {
        guard !puntos.isEmpty else { return "" }
        let p = puntos[LiquidChartA11y.indice(iScrub, puntos.count)]
        if let f = formatoScrub { return f(p.valor, p.fecha) }
        if let f = formatoValorScrub { return f(p.valor) }
        return ""
    }
}

#if DEBUG
private func trendDemo() -> [(fecha: Date, valor: Double)] {
    let cal: Calendar = Calendar.current
    return (0..<14).map { (i: Int) -> (fecha: Date, valor: Double) in
        let fecha: Date = cal.date(byAdding: .day, value: i - 13, to: Date())!
        let seno: Double = 0.9 * sin(Double(i) / 1.8)
        let ruido: Double = Double((i * 5) % 3) * 0.2
        return (fecha: fecha, valor: 7.1 + seno + ruido)
    }
}

#Preview("Liquid · Trend 14d — datos") {
    let ejeFmt: (Date) -> String = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("dMMM")
        return { (d: Date) -> String in f.string(from: d) }
    }()
    let popupFmt: (Date) -> String = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEEdMMM")
        return { (d: Date) -> String in f.string(from: d) }
    }()
    var chart = LiquidTrendChart(
        titulo: "Últimos 14 días",
        readout: (etiqueta: "Adecuado", tono: LiquidColor.indigo,
                  frase: "9 de las últimas 14 noches en este rango"),
        puntos: trendDemo(),
        bandas: [
            .init(lo: 7, hi: 9, color: LiquidColor.indigo, activa: true),
            .init(lo: 6, hi: 7, color: LiquidColor.teal, activa: false),
            .init(lo: nil, hi: 6, color: LiquidColor.atencion, activa: false),
        ],
        dominio: 5...10,
        ticksY: [(9, "9"), (7, "7"), (6, "6")],
        tono: LiquidColor.indigo,
        formatoScrub: { v, _ in String(format: "%.1f h · mar 14", v) },
        formatoValorScrub: { v in String(format: "%.1f h", v) },
        formatoFechaScrub: popupFmt,
        formatoFechaEje: ejeFmt,
        estado: .datos,
        a11yLabel: "Sueño, últimos 14 días")
    chart.scrubFijo = 5
    return chart
        .padding(LiquidSpace.s550)
        .background(LiquidSheetFondo(tone: LiquidColor.indigo))
        .environment(\.liquidMotionDisabled, true)
}

/// Joya de HOY: relleno papel + filo del tono (paridad con el explorador de niveles).
#Preview("Liquid · Trend 14d — joya de hoy") {
    let puntos = trendDemo()
    let ultimo = puntos[puntos.count - 1]
    let ejeFmt: (Date) -> String = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("dMMM")
        return { (d: Date) -> String in f.string(from: d) }
    }()
    let popupFmt: (Date) -> String = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEEdMMM")
        return { (d: Date) -> String in f.string(from: d) }
    }()
    return LiquidTrendChart(
        titulo: "Últimos 14 días",
        readout: (etiqueta: "Adecuado", tono: LiquidColor.indigo,
                  frase: "9 de las últimas 14 noches en este rango"),
        puntos: puntos,
        bandas: [
            .init(lo: 7, hi: 9, color: LiquidColor.indigo, activa: true),
            .init(lo: 6, hi: 7, color: LiquidColor.teal, activa: false),
            .init(lo: nil, hi: 6, color: LiquidColor.atencion, activa: false),
        ],
        dominio: 5...10,
        ticksY: [(9, "9"), (7, "7"), (6, "6")],
        tono: LiquidColor.indigo,
        formatoScrub: { v, _ in String(format: "%.1f h · mar 14", v) },
        formatoValorScrub: { v in String(format: "%.1f h", v) },
        formatoFechaScrub: popupFmt,
        formatoFechaEje: ejeFmt,
        puntoHoy: (fecha: ultimo.fecha, valor: ultimo.valor),
        hoyAnillo: true,
        estado: .datos,
        a11yLabel: "Sueño, últimos 14 días")
        .padding(LiquidSpace.s550)
        .background(LiquidSheetFondo(tone: LiquidColor.indigo))
        .environment(\.liquidMotionDisabled, true)
}

#Preview("Liquid · Trend 14d — cargando y vacío") {
    VStack(alignment: .leading, spacing: LiquidSpace.s550) {
        LiquidTrendChart(
            titulo: "Últimos 14 días", puntos: [], bandas: [], dominio: 0...1,
            ticksY: [], tono: LiquidColor.rosa,
            formatoScrub: { v, _ in "\(Int(v))" },
            estado: .cargando,
            a11yLabel: "FC en reposo, últimos 14 días")
        LiquidTrendChart(
            titulo: "Últimos 14 días", puntos: [], bandas: [], dominio: 0...1,
            ticksY: [], tono: LiquidColor.rosa,
            formatoScrub: { v, _ in "\(Int(v))" },
            estado: .vacio("Sin datos de los últimos 14 días."),
            a11yLabel: "FC en reposo, últimos 14 días")
    }
    .padding(LiquidSpace.s550)
    .background(LiquidSheetFondo(tone: LiquidColor.rosa))
    .environment(\.liquidMotionDisabled, true)
}

/// Densidad `.mini` (F3b · guardián): dos renglones a 32 pt (ámbar temp / azul resp),
/// con banda de patrón, joya de anoche y scrub asentado para ver el popup.
#Preview("Liquid · TrendChart mini") {
    let puntos = trendDemo()
    let ultimo = puntos[puntos.count - 1]
    let popupFmt: (Date) -> String = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEEdMMM")
        return { (d: Date) -> String in f.string(from: d) }
    }()
    func mini(titulo: String,
              tono: Color,
              banda: ClosedRange<Double>,
              dominio: ClosedRange<Double>,
              scrubFijo: Int,
              a11y: String) -> some View {
        var chart = LiquidTrendChart(
            titulo: titulo,
            puntos: puntos,
            bandas: [.init(lo: banda.lowerBound, hi: banda.upperBound,
                           color: tono, activa: true)],
            dominio: dominio,
            ticksY: [(banda.upperBound, ""), (banda.lowerBound, "")],
            tono: tono,
            formatoValorScrub: { v in String(format: "%.2f", v) },
            formatoFechaScrub: popupFmt,
            formatoFechaEje: { _ in "x" },
            puntoHoy: (fecha: ultimo.fecha, valor: ultimo.valor),
            hoyAnillo: true,
            estado: .datos,
            a11yLabel: a11y,
            densidad: .mini)
        chart.scrubFijo = scrubFijo
        return chart
    }
    return VStack(alignment: .leading, spacing: LiquidSpace.s550) {
        // Fila de señal + mini (como la hoja del guardián).
        VStack(alignment: .leading, spacing: LiquidSpace.s200) {
            Text(verbatim: "Temperatura de piel")
                .font(LiquidType.cuerpo)
                .foregroundStyle(LiquidColor.tinta700)
            mini(titulo: "Temperatura", tono: LiquidColor.ambar,
                 banda: 6.5...8.5, dominio: 5...10,
                 scrubFijo: 9, a11y: "Temperatura de piel, 14 noches")
        }
        VStack(alignment: .leading, spacing: LiquidSpace.s200) {
            Text(verbatim: "Respiración")
                .font(LiquidType.cuerpo)
                .foregroundStyle(LiquidColor.tinta700)
            mini(titulo: "Respiración", tono: LiquidColor.cian,
                 banda: 6.8...8.2, dominio: 5...10,
                 scrubFijo: 5, a11y: "Respiración, 14 noches")
        }
        // Glifo de escudo a 16 pt (cabecera del guardián).
        HStack(spacing: LiquidSpace.s200) {
            LiquidIcon(.escudo, size: 16, color: LiquidColor.tinta900)
            Text(verbatim: "El guardián")
                .font(LiquidType.titulo)
                .foregroundStyle(LiquidColor.tinta900)
        }
    }
    .padding(LiquidSpace.s550)
    .background(LiquidSheetFondo(tone: LiquidColor.ambar))
    .environment(\.liquidMotionDisabled, true)
}
#endif
