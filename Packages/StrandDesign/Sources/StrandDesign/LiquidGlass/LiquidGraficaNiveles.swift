import SwiftUI

// MARK: - Liquid Glass · Gráfica del explorador de niveles (épico hoja de resumen, F3b)
//
// La gráfica RAW del explorador de niveles, re-vestida en Liquid (contrato §3 F3b y §4:
// interacción intacta, piel nueva). Todo llega RESUELTO del host (ventana ya cortada,
// ticks ya formateados, mensaje de vacío ya localizado); la vista solo pinta y scrubbea.
//
//   · I1 — banda activa iluminada (washes 8/16/3, `LiquidChart.banda*Alfa`).
//   · I2 — scrub con regla vertical + anillo del color de su banda + chip negro
//          (mismo gesto/snap/háptica que `GraficaRangos`, vía las piezas públicas).
//   · Joya endpoint en `puntoHoy`; `hoyAnillo` la vuelve anillo hueco mientras el
//     usuario explora otro nivel (paridad `markedPointHollow`).

public struct LiquidGraficaNiveles: View {

    /// La banda del contrato §3 F3b — alias de la banda compartida de la familia.
    public typealias Banda = LiquidChartBanda

    private let puntos: [(fecha: Date, valor: Double)]
    private let bandas: [Banda]
    private let dominio: ClosedRange<Double>
    private let ticksY: [(valor: Double, etiqueta: String)]
    private let tono: Color
    private let puntoHoy: (fecha: Date, valor: Double)?
    private let hoyAnillo: Bool
    private let formatoScrub: (Double, Date) -> String
    private let estadoVacio: String
    private let a11yLabel: String
    /// SOLO previews/arnés: overlay de scrub asentado en un índice fijo.
    var scrubFijo: Int? = nil

    public init(puntos: [(fecha: Date, valor: Double)],
                bandas: [Banda],
                dominio: ClosedRange<Double>,
                ticksY: [(valor: Double, etiqueta: String)],
                tono: Color,
                puntoHoy: (fecha: Date, valor: Double)? = nil,
                hoyAnillo: Bool = false,
                formatoScrub: @escaping (Double, Date) -> String,
                estadoVacio: String,
                a11yLabel: String) {
        self.puntos = puntos
        self.bandas = bandas
        self.dominio = dominio
        self.ticksY = ticksY
        self.tono = tono
        self.puntoHoy = puntoHoy
        self.hoyAnillo = hoyAnillo
        self.formatoScrub = formatoScrub
        self.estadoVacio = estadoVacio
        self.a11yLabel = a11yLabel
    }

    public var body: some View {
        Group {
            if puntos.count > 1 {
                LiquidChartPlot(puntos: puntos, bandas: bandas, dominio: dominio,
                                ticksY: ticksY, tono: tono,
                                puntoHoy: puntoHoy, hoyAnillo: hoyAnillo,
                                formatoScrub: formatoScrub,
                                alto: LiquidChartAlto.explorador,
                                scrubFijo: scrubFijo)
            } else {
                LiquidChartVacio(mensaje: estadoVacio, alto: LiquidChartAlto.explorador)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: a11yLabel))
        .accessibilityValue(Text(verbatim: valorA11y))
    }

    /// VoiceOver lee el último punto con el mismo formato del scrub (paridad GraficaRangos).
    private var valorA11y: String {
        guard let ultimo = puntos.last else { return estadoVacio }
        return formatoScrub(ultimo.valor, ultimo.fecha)
    }
}

#if DEBUG
private func serieDemo(dias: Int = 30, base: Double = 58, onda: Double = 13)
    -> [(fecha: Date, valor: Double)] {
    let cal: Calendar = Calendar.current
    return (0..<dias).map { (i: Int) -> (fecha: Date, valor: Double) in
        let fecha: Date = cal.date(byAdding: .day, value: i - (dias - 1), to: Date())!
        let seno: Double = onda * sin(Double(i) / 2.4)
        let ruido: Double = Double((i * 11) % 7) - 3.0
        return (fecha: fecha, valor: base + seno + ruido)
    }
}

private func bandasDemo(activa: Int?) -> [LiquidChartBanda] {
    [
        .init(lo: 71, hi: nil, color: LiquidColor.positivo, activa: activa == 0),
        .init(lo: 49, hi: 71, color: LiquidColor.cian, activa: activa == 1),
        .init(lo: nil, hi: 49, color: LiquidColor.atencion, activa: activa == 2),
    ]
}

#Preview("Liquid · Niveles — banda activa") {
    let puntos = serieDemo()
    return LiquidGraficaNiveles(
        puntos: puntos, bandas: bandasDemo(activa: 1), dominio: 30...95,
        ticksY: [(71, "71"), (49, "49")], tono: LiquidColor.cian,
        puntoHoy: (puntos[puntos.count - 1].fecha, puntos[puntos.count - 1].valor),
        hoyAnillo: false,
        formatoScrub: { v, _ in "\(Int(v)) ms" },
        estadoVacio: "Sin lecturas en este rango.",
        a11yLabel: "VFC, últimos 30 días")
        .padding(LiquidSpace.s550)
        .background(LiquidSheetFondo(tone: LiquidColor.cian))
        .environment(\.liquidMotionDisabled, true)
}

#Preview("Liquid · Niveles — reposo + anillo hoy") {
    let puntos = serieDemo()
    return VStack(spacing: LiquidSpace.s400) {
        // Sin banda activa: todos los washes al reposo (8 %).
        LiquidGraficaNiveles(
            puntos: puntos, bandas: bandasDemo(activa: nil), dominio: 30...95,
            ticksY: [(71, "71"), (49, "49")], tono: LiquidColor.cian,
            puntoHoy: (puntos[puntos.count - 1].fecha, puntos[puntos.count - 1].valor),
            formatoScrub: { v, _ in "\(Int(v)) ms" },
            estadoVacio: "Sin lecturas en este rango.",
            a11yLabel: "VFC, últimos 30 días")
        // Explorando otro nivel: hoy conserva su anillo HUECO.
        LiquidGraficaNiveles(
            puntos: puntos, bandas: bandasDemo(activa: 0), dominio: 30...95,
            ticksY: [(71, "71"), (49, "49")], tono: LiquidColor.cian,
            puntoHoy: (puntos[puntos.count - 1].fecha, puntos[puntos.count - 1].valor),
            hoyAnillo: true,
            formatoScrub: { v, _ in "\(Int(v)) ms" },
            estadoVacio: "Sin lecturas en este rango.",
            a11yLabel: "VFC, últimos 30 días")
    }
    .padding(LiquidSpace.s550)
    .background(LiquidSheetFondo(tone: LiquidColor.cian))
    .environment(\.liquidMotionDisabled, true)
}

#Preview("Liquid · Niveles — scrub estático") {
    let puntos = serieDemo()
    var g = LiquidGraficaNiveles(
        puntos: puntos, bandas: bandasDemo(activa: 1), dominio: 30...95,
        ticksY: [(71, "71"), (49, "49")], tono: LiquidColor.cian,
        puntoHoy: (puntos[puntos.count - 1].fecha, puntos[puntos.count - 1].valor),
        formatoScrub: { v, _ in "\(Int(v)) ms · mar 14" },
        estadoVacio: "Sin lecturas en este rango.",
        a11yLabel: "VFC, últimos 30 días")
    g.scrubFijo = 9
    return g
        .padding(LiquidSpace.s550)
        .background(LiquidSheetFondo(tone: LiquidColor.cian))
        .environment(\.liquidMotionDisabled, true)
}

#Preview("Liquid · Niveles — vacío") {
    LiquidGraficaNiveles(
        puntos: [], bandas: bandasDemo(activa: nil), dominio: 30...95,
        ticksY: [], tono: LiquidColor.cian,
        formatoScrub: { v, _ in "\(Int(v)) ms" },
        estadoVacio: "Tus niveles salen de tu propia base. Aún no hay noches suficientes.",
        a11yLabel: "VFC, sin lecturas")
        .padding(LiquidSpace.s550)
        .background(LiquidSheetFondo(tone: LiquidColor.cian))
        .environment(\.liquidMotionDisabled, true)
}
#endif
