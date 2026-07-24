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
    private let formatoScrub: ((Double, Date) -> String)?
    private let formatoValorScrub: ((Double) -> String)?
    private let formatoFechaScrub: ((Date) -> String)?
    private let formatoFechaEje: ((Date) -> String)?
    /// Mismo contrato de estados que `LiquidTrendChart`. `.datos` es el default y conserva
    /// el comportamiento de siempre (con menos de 2 puntos cae al pozo de `estadoVacio`);
    /// `.cargando` y `.vacio` dan al caller los pozos del motor SIN volver públicos
    /// `LiquidChartVacio` / `LiquidChartCargando` / `LiquidChartAlto`, que son detalle
    /// interno del paquete.
    private let estado: LiquidChartEstado
    private let estadoVacio: String
    private let a11yLabel: String
    /// Apaga los puntos por dato fuera de la banda activa. `false` = todos a opacidad
    /// plena (la banda activa se dice solo con su wash, I1). Se enciende cuando el usuario
    /// EXPLORA un nivel, que es cuando `GraficaRangos` apaga.
    private let atenuarFuera: Bool
    /// SOLO previews/arnés: overlay de scrub asentado en un índice fijo.
    var scrubFijo: Int? = nil

    /// El punto bajo el dedo (lo publica el plot). Mueve el `accessibilityValue` con el
    /// scrub y vuelve a `nil` — es decir, al último punto — al soltar.
    @State private var iScrub: Int? = nil

    public init(puntos: [(fecha: Date, valor: Double)],
                bandas: [Banda],
                dominio: ClosedRange<Double>,
                ticksY: [(valor: Double, etiqueta: String)],
                tono: Color,
                puntoHoy: (fecha: Date, valor: Double)? = nil,
                hoyAnillo: Bool = false,
                formatoScrub: ((Double, Date) -> String)? = nil,
                formatoValorScrub: ((Double) -> String)? = nil,
                formatoFechaScrub: ((Date) -> String)? = nil,
                formatoFechaEje: ((Date) -> String)? = nil,
                atenuarFuera: Bool = false,
                estado: LiquidChartEstado = .datos,
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
        self.formatoValorScrub = formatoValorScrub
        self.formatoFechaScrub = formatoFechaScrub
        self.formatoFechaEje = formatoFechaEje
        self.atenuarFuera = atenuarFuera
        self.estado = estado
        self.estadoVacio = estadoVacio
        self.a11yLabel = a11yLabel
    }

    public var body: some View {
        Group {
            switch estado {
            case .cargando:
                LiquidChartCargando(alto: LiquidChartAlto.explorador)
            case .vacio(let mensaje):
                LiquidChartVacio(mensaje: mensaje, alto: LiquidChartAlto.explorador)
            case .datos:
                if puntos.count > 1 {
                    LiquidChartPlot(puntos: puntos, bandas: bandas, dominio: dominio,
                                ticksY: ticksY, tono: tono,
                                puntoHoy: puntoHoy, hoyAnillo: hoyAnillo,
                                formatoScrub: formatoScrub,
                                formatoValorScrub: formatoValorScrub,
                                formatoFechaScrub: formatoFechaScrub,
                                formatoFechaEje: formatoFechaEje,
                                // El eje del explorador es el CALENDARIO, no el índice: la
                                // ventana sale de `MetricWindowMath.slice`, que devuelve
                                // SOLO los días con lectura. Repartir por índice dibuja 12
                                // lecturas equiespaciadas mientras el eje afirma un span de
                                // 30 o 90 días: la gráfica borraría los huecos que son el
                                // dato (VFC / temp. piel / respiración se miden a ratos).
                                mapeoPorTiempo: true,
                                atenuarFuera: atenuarFuera,
                                alto: LiquidChartAlto.explorador,
                                scrubFijo: scrubFijo,
                                onScrub: { (i: Int?) in iScrub = i })
                } else {
                    LiquidChartVacio(mensaje: estadoVacio, alto: LiquidChartAlto.explorador)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: a11yLabel))
        .accessibilityValue(Text(verbatim: valorA11y))
    }

    /// VoiceOver lee el punto SCRUBBEADO (o el último) con la frase compuesta del caller
    /// — paridad GraficaRangos. El DS nunca une valor + fecha por su cuenta: si el caller
    /// no dio la frase compuesta, se degrada al valor solo (contrato D3).
    ///
    /// Interno (no `private`) para que el contrato se pruebe en frío: es justo el tipo de
    /// defecto que ningún compilador atrapa — dos ramas que deciden lo MISMO con umbrales
    /// distintos (ver el `guard` de abajo).
    var valorA11y: String {
        // Cargando no se anuncia con copy inventado: el rótulo del caller basta (el DS no
        // tiene catálogo, D3).
        if case .cargando = estado { return "" }
        if case .vacio(let mensaje) = estado { return mensaje }
        // E2 · el MISMO umbral que decide el pozo en `body` (`puntos.count > 1`). Con
        // `!puntos.isEmpty` la voz y la pantalla se contradecían: con UNA sola lectura
        // VoiceOver anunciaba «56 ms» mientras la pantalla decía «No hay lecturas en este
        // rango» — el caso del usuario nuevo, que es justo quien más depende de la voz.
        guard puntos.count > 1 else { return estadoVacio }
        let i: Int = LiquidChartA11y.indice(iScrub, puntos.count)
        let p = puntos[i]
        if let f = formatoScrub { return f(p.valor, p.fecha) }
        if let f = formatoValorScrub { return f(p.valor) }
        return estadoVacio
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

/// Formateadores de demo: el DS no conoce locales, el caller SÍ (contrato D3).
private func fmtDemo(_ plantilla: String) -> (Date) -> String {
    let f = DateFormatter()
    f.setLocalizedDateFormatFromTemplate(plantilla)
    return { (d: Date) -> String in f.string(from: d) }
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
    let ejeFmt: (Date) -> String = fmtDemo("dMMM")
    return LiquidGraficaNiveles(
        puntos: puntos, bandas: bandasDemo(activa: 1), dominio: 30...95,
        ticksY: [(71, "71"), (49, "49")], tono: LiquidColor.cian,
        puntoHoy: (puntos[puntos.count - 1].fecha, puntos[puntos.count - 1].valor),
        hoyAnillo: false,
        formatoScrub: { v, _ in "\(Int(v)) ms" },
        formatoFechaEje: ejeFmt,
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
    // Serie corta: se ven los PUNTOS POR DATO y el popup con sus dos líneas.
    let puntos = serieDemo(dias: 14)
    let ejeFmt: (Date) -> String = fmtDemo("dMMM")
    let popupFmt: (Date) -> String = fmtDemo("EEEdMMM")
    var g = LiquidGraficaNiveles(
        puntos: puntos, bandas: bandasDemo(activa: 1), dominio: 30...95,
        ticksY: [(71, "71"), (49, "49")], tono: LiquidColor.cian,
        puntoHoy: (puntos[puntos.count - 1].fecha, puntos[puntos.count - 1].valor),
        formatoScrub: { v, _ in "\(Int(v)) ms · mar 14" },
        formatoValorScrub: { v in "\(Int(v)) ms" },
        formatoFechaScrub: popupFmt,
        formatoFechaEje: ejeFmt,
        estadoVacio: "Sin lecturas en este rango.",
        a11yLabel: "VFC, últimos 30 días")
    g.scrubFijo = 9
    return g
        .padding(LiquidSpace.s550)
        .background(LiquidSheetFondo(tone: LiquidColor.cian))
        .environment(\.liquidMotionDisabled, true)
}

/// La serie que el mapeo por índice contaba mal: 12 lecturas repartidas de forma DESIGUAL
/// dentro de 90 días (dos racimos y un hueco de mes y medio), tal como sale
/// `MetricWindowMath.slice` para VFC / temp. piel / respiración, que no se miden a diario.
private func serieConHuecos() -> [(fecha: Date, valor: Double)] {
    let cal: Calendar = Calendar.current
    let offsets: [Int] = [-89, -87, -86, -84, -83, -38, -12, -9, -8, -6, -3, 0]
    return offsets.enumerated().map { (k: Int, d: Int) -> (fecha: Date, valor: Double) in
        let fecha: Date = cal.date(byAdding: .day, value: d, to: Date())!
        return (fecha: fecha, valor: 58.0 + 12.0 * sin(Double(k) / 1.7) + Double((k * 5) % 6))
    }
}

#Preview("Liquid · Niveles — serie con huecos (90 días)") {
    // Prueba del hueco (carril A, A1): con reparto por ÍNDICE los 12 puntos salían
    // equiespaciados y el eje mentía sobre el span. Con mapeo por TIEMPO se ven los dos
    // racimos y el vacío de mes y medio, y las fechas del eje caen sobre sus bolitas.
    let puntos = serieConHuecos()
    let ejeFmt: (Date) -> String = fmtDemo("dMMM")
    return LiquidGraficaNiveles(
        puntos: puntos, bandas: bandasDemo(activa: 1), dominio: 30...95,
        ticksY: [(71, "71"), (49, "49")], tono: LiquidColor.cian,
        puntoHoy: (puntos[puntos.count - 1].fecha, puntos[puntos.count - 1].valor),
        formatoScrub: { v, _ in "\(Int(v)) ms" },
        formatoFechaEje: ejeFmt,
        estadoVacio: "Sin lecturas en este rango.",
        a11yLabel: "VFC, últimos 90 días")
        .padding(LiquidSpace.s550)
        .background(LiquidSheetFondo(tone: LiquidColor.cian))
        .environment(\.liquidMotionDisabled, true)
}

#Preview("Liquid · Niveles — serie corta con racimo (n = 5, 7, 8)") {
    // El reparto `n <= 8 ⇒ todas las fechas` es el que muerde con mapeo por tiempo: dos
    // lecturas seguidas dentro de un rango largo caen a 3 pt una de otra. La poda por
    // geometría debe dejar solo las que caben, y NUNCA soltar la última.
    let ejeFmt: (Date) -> String = fmtDemo("dMMM")
    func corta(_ offsets: [Int]) -> [(fecha: Date, valor: Double)] {
        let cal: Calendar = Calendar.current
        return offsets.enumerated().map { (k: Int, d: Int) -> (fecha: Date, valor: Double) in
            (fecha: cal.date(byAdding: .day, value: d, to: Date())!,
             valor: 55.0 + 10.0 * sin(Double(k) / 1.3))
        }
    }
    return VStack(spacing: LiquidSpace.s400) {
        ForEach([[-60, -59, -58, -20, 0],
                 [-88, -86, -85, -84, -40, -2, 0],
                 [-90, -89, -88, -50, -49, -5, -4, 0]], id: \.self) { (offsets: [Int]) in
            let puntos = corta(offsets)
            LiquidGraficaNiveles(
                puntos: puntos, bandas: bandasDemo(activa: 1), dominio: 30...95,
                ticksY: [(71, "71"), (49, "49")], tono: LiquidColor.cian,
                puntoHoy: (puntos[puntos.count - 1].fecha, puntos[puntos.count - 1].valor),
                formatoScrub: { v, _ in "\(Int(v)) ms" },
                formatoFechaEje: ejeFmt,
                estadoVacio: "Sin lecturas en este rango.",
                a11yLabel: "VFC, últimos 90 días")
        }
    }
    .padding(LiquidSpace.s550)
    .background(LiquidSheetFondo(tone: LiquidColor.cian))
    .environment(\.liquidMotionDisabled, true)
}

#Preview("Liquid · Niveles — atenuación explícita (opt-in)") {
    // Sin `atenuarFuera` (el default, y lo que ve la app hoy) todos los puntos van a
    // opacidad plena; con el opt-in se apagan los de fuera de la banda activa.
    let puntos = serieDemo(dias: 14)
    let ejeFmt: (Date) -> String = fmtDemo("dMMM")
    return VStack(spacing: LiquidSpace.s400) {
        LiquidGraficaNiveles(
            puntos: puntos, bandas: bandasDemo(activa: 1), dominio: 30...95,
            ticksY: [(71, "71"), (49, "49")], tono: LiquidColor.cian,
            puntoHoy: (puntos[puntos.count - 1].fecha, puntos[puntos.count - 1].valor),
            formatoScrub: { v, _ in "\(Int(v)) ms" },
            formatoFechaEje: ejeFmt,
            estadoVacio: "Sin lecturas en este rango.",
            a11yLabel: "VFC, últimos 14 días")
        LiquidGraficaNiveles(
            puntos: puntos, bandas: bandasDemo(activa: 1), dominio: 30...95,
            ticksY: [(71, "71"), (49, "49")], tono: LiquidColor.cian,
            puntoHoy: (puntos[puntos.count - 1].fecha, puntos[puntos.count - 1].valor),
            formatoScrub: { v, _ in "\(Int(v)) ms" },
            formatoFechaEje: ejeFmt,
            atenuarFuera: true,
            estadoVacio: "Sin lecturas en este rango.",
            a11yLabel: "VFC, últimos 14 días")
    }
    .padding(LiquidSpace.s550)
    .background(LiquidSheetFondo(tone: LiquidColor.cian))
    .environment(\.liquidMotionDisabled, true)
}

#Preview("Liquid · Niveles — estados (cargando / vacío del caller)") {
    // El contrato de estados que el compositor necesita para NO imprimir ceros mientras la
    // serie viaja (D7): mismo `LiquidChartEstado` que `LiquidTrendChart`, sin volver
    // públicos los pozos ni el alto del explorador. Ambos miden lo MISMO que `.datos`, así
    // que la hoja no brinca al cargar.
    VStack(spacing: LiquidSpace.s400) {
        LiquidGraficaNiveles(
            puntos: [], bandas: bandasDemo(activa: nil), dominio: 30...95,
            ticksY: [], tono: LiquidColor.cian,
            estado: .cargando,
            estadoVacio: "Sin lecturas en este rango.",
            a11yLabel: "VFC, últimos 30 días")
        LiquidGraficaNiveles(
            puntos: [], bandas: bandasDemo(activa: nil), dominio: 30...95,
            ticksY: [], tono: LiquidColor.cian,
            estado: .vacio("Sin lecturas en este rango."),
            estadoVacio: "Sin lecturas en este rango.",
            a11yLabel: "VFC, últimos 30 días")
    }
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
