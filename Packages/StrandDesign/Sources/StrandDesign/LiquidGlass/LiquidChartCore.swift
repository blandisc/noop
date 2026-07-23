import SwiftUI

// MARK: - Liquid Glass · Núcleo de gráficas (épico hoja de resumen, F3b/F4)
//
// Las piezas COMPARTIDAS de la familia de gráficas Liquid (explorador de niveles, trend
// 14d, curva FC): el estado común, la banda común y el motor de plot que dibuja washes
// (I1), grid, serie con joya y el overlay de scrub (I2). Decisión del contrato §4:
// RE-VESTIR la interacción existente, no rediseñarla — el gesto es el `scrubGesture`
// público de TrendChart, el snap es `ChartScrubMath`, la háptica es `ChartHaptics` y la
// regla es `CrosshairRule`; aquí solo cambia la PIEL (tokens `LiquidChart`/`LiquidColor`).
//
// Copy: todo string llega YA localizado del caller (contrato D3); el DS no conoce locales.

// MARK: - Estado común

/// El estado de una gráfica de la hoja Liquid. `.vacio` carga el mensaje ya localizado
/// del caller («Sin lecturas en este rango»).
public enum LiquidChartEstado: Equatable, Sendable {
    case datos
    case cargando
    case vacio(String)
}

// MARK: - Banda común (I1)

/// Una banda de clasificación detrás de la serie. Intervalo half-open `[lo, hi)` como
/// `MetricLevels`; `lo == nil` = abierta por abajo, `hi == nil` = abierta por arriba.
/// `activa` ilumina su wash (I1: 8 % reposo / 16 % activa / 3 % el resto).
public struct LiquidChartBanda: Sendable {
    public let lo: Double?
    public let hi: Double?
    public let color: Color
    public let activa: Bool

    public init(lo: Double?, hi: Double?, color: Color, activa: Bool) {
        self.lo = lo
        self.hi = hi
        self.color = color
        self.activa = activa
    }

    func contiene(_ v: Double) -> Bool {
        (lo == nil || v >= lo!) && (hi == nil || v < hi!)
    }
}

// MARK: - Altos de gráfica (paridad Instrumento, contrato §5 «candidatos menores»)

/// Los tres altos de la hoja: 168 explorador (`MetricLevelsExplorer:137`), 140 trend 14d
/// (`MetricInfoSheet:1001`), 260 curva FC (`MetricInfoSheet:914`).
enum LiquidChartAlto {
    static let explorador: CGFloat = 168
    static let trend: CGFloat = 140
    static let curvaFC: CGFloat = 260
}

// MARK: - Motor de plot compartido

/// El plot compartido de la familia: washes de banda (I1), grid con `gridAlfa`, serie con
/// joya endpoint y scrub (I2: regla vertical + anillo por banda + chip negro con clamping,
/// paridad `GraficaRangos.scrubOverlay`). La interacción reusa las piezas públicas del
/// paquete (`scrubGesture` / `ChartScrubMath` / `ChartHaptics` / `CrosshairRule`) — nunca
/// se reimplementa el gesto.
struct LiquidChartPlot: View {
    let puntos: [(fecha: Date, valor: Double)]
    let bandas: [LiquidChartBanda]
    let dominio: ClosedRange<Double>
    let ticksY: [(valor: Double, etiqueta: String)]
    let tono: Color
    let puntoHoy: (fecha: Date, valor: Double)?
    let hoyAnillo: Bool
    let formatoScrub: (Double, Date) -> String
    let alto: CGFloat
    /// SOLO previews/arnés: pinta el overlay de scrub asentado en un índice fijo.
    var scrubFijo: Int? = nil

    @State private var hoverX: CGFloat? = nil
    @State private var entrado = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.liquidMotionDisabled) private var motionDisabled

    /// Canaleta izquierda para los labels del eje Y (geometría de paridad `GraficaRangos`);
    /// sin ticks no hay canaleta (curva FC).
    private var canaleta: CGFloat { ticksY.isEmpty ? 0 : 26 }
    /// Respiro vertical del plot (la serie nunca pega contra el borde).
    private static let margenV: CGFloat = 10

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            // Snap del dedo al punto más cercano: el MISMO `ChartScrubMath` del explorador.
            let iHover = hoverX.flatMap {
                ChartScrubMath.nearestIndex(toX: $0 - canaleta,
                                            count: puntos.count,
                                            width: max(1, w - canaleta))
            }
            let iActivo = iHover ?? scrubFijo
            ZStack(alignment: .topLeading) {
                washes(w, h)
                grid(w, h)
                serie(w, h)
                    .opacity(entrado || motionDisabled ? 1 : 0)
                if let i = iActivo, puntos.indices.contains(i) {
                    overlayScrub(i, w, h)
                }
            }
            .contentShape(Rectangle())
            // El gesto público de TrendChart:642 — drag `minimumDistance: 0` en iOS (gana
            // el touch al ScrollView de la hoja), hover en macOS; limpia al soltar.
            .scrubGesture(enabled: puntos.count > 1, hoverX: $hoverX)
            .onChange(of: iHover) { _, nuevo in
                // Háptica solo al caer en un punto NUEVO (no al soltar) — paridad GraficaRangos.
                if nuevo != nil { ChartHaptics.datumChanged() }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: alto)
        .onAppear {
            // Entrada: fade dur/gentle. Con motion congelado (previews/renders) o Reduce
            // Motion el chart se pinta ASENTADO, sin animación de entrada.
            guard !entrado, !motionDisabled else { return }
            if reduceMotion {
                entrado = true
            } else {
                withAnimation(LiquidMotion.entrada) { entrado = true }
            }
        }
    }

    // MARK: Geometría

    private func x(_ i: Int, _ w: CGFloat) -> CGFloat {
        let n = puntos.count
        guard n > 1 else { return (canaleta + w) / 2 }
        return canaleta + CGFloat(i) * (w - canaleta) / CGFloat(n - 1)
    }

    private func y(_ v: Double, _ h: CGFloat) -> CGFloat {
        let lo = dominio.lowerBound, hi = dominio.upperBound
        let clamped = Swift.max(lo, Swift.min(hi, v))
        let f = hi > lo ? (clamped - lo) / (hi - lo) : 0.5
        let piso = h - Self.margenV
        return piso - CGFloat(f) * (piso - Self.margenV)
    }

    /// Índice del punto de `fecha` (exacto, o el más cercano en tiempo).
    private func indiceDe(_ fecha: Date) -> Int? {
        guard !puntos.isEmpty else { return nil }
        if let i = puntos.firstIndex(where: { $0.fecha == fecha }) { return i }
        var mejor = 0
        var mejorD = TimeInterval.greatestFiniteMagnitude
        for (i, p) in puntos.enumerated() {
            let d = abs(p.fecha.timeIntervalSince(fecha))
            if d < mejorD { mejorD = d; mejor = i }
        }
        return mejor
    }

    // MARK: Washes de banda (I1 — luminosidad de lo seleccionado)

    private func washes(_ w: CGFloat, _ h: CGFloat) -> some View {
        let hayActiva = bandas.contains { $0.activa }
        let indiceActiva = bandas.firstIndex { $0.activa }
        return ForEach(Array(bandas.enumerated()), id: \.offset) { _, b in
            let top = y(Swift.min(b.hi ?? dominio.upperBound, dominio.upperBound), h)
            let fondo = y(Swift.max(b.lo ?? dominio.lowerBound, dominio.lowerBound), h)
            Rectangle()
                .fill(b.color)
                .opacity(hayActiva
                         ? (b.activa ? LiquidChart.bandaActivaAlfa : LiquidChart.bandaApagadaAlfa)
                         : LiquidChart.bandaReposoAlfa)
                .frame(width: Swift.max(0, w - canaleta), height: Swift.max(0, fondo - top))
                .offset(x: canaleta, y: top)
        }
        .animation(reduceMotion || motionDisabled ? nil : LiquidMotion.lift, value: indiceActiva)
    }

    // MARK: Grid + labels del eje Y

    @ViewBuilder private func grid(_ w: CGFloat, _ h: CGFloat) -> some View {
        ForEach(Array(ticksY.enumerated()), id: \.offset) { _, t in
            Rectangle()
                .fill(LiquidColor.tinta900.opacity(LiquidChart.gridAlfa))
                .frame(width: Swift.max(0, w - canaleta), height: 1)
                .offset(x: canaleta, y: y(t.valor, h) - 0.5)
            Text(verbatim: t.etiqueta)
                .font(LiquidType.unidadCompacta)
                .monospacedDigit()
                .foregroundStyle(LiquidColor.tinta500)
                .offset(x: 0, y: y(t.valor, h) - 6)
        }
    }

    // MARK: Serie + joya endpoint

    @ViewBuilder private func serie(_ w: CGFloat, _ h: CGFloat) -> some View {
        if puntos.count > 1 {
            Path { p in
                for (i, punto) in puntos.enumerated() {
                    let pt = CGPoint(x: x(i, w), y: y(punto.valor, h))
                    if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                }
            }
            .stroke(tono, style: StrokeStyle(lineWidth: LiquidChart.lineaAncho,
                                             lineCap: .round, lineJoin: .round))
        }
        if let hoy = puntoHoy, let i = indiceDe(hoy.fecha) {
            let px = x(i, w)
            let py = y(hoy.valor, h)
            if hoyAnillo {
                // Anillo hueco: hoy sigue marcado mientras exploras otro nivel (paridad
                // `markedPointHollow`, MetricLevelsExplorer:145) — misma geometría que el
                // anillo del scrub para hablar un solo lenguaje.
                Circle()
                    .fill(LiquidColor.papelAlto)
                    .overlay(Circle().strokeBorder(tono, lineWidth: LiquidChart.scrubAnilloBorde))
                    .frame(width: LiquidChart.scrubAnilloDiametro,
                           height: LiquidChart.scrubAnilloDiametro)
                    .offset(x: px - LiquidChart.scrubAnilloDiametro / 2,
                            y: py - LiquidChart.scrubAnilloDiametro / 2)
            } else {
                // La joya del endpoint (mismo lenguaje que el orbe).
                Circle()
                    .fill(tono)
                    .overlay(Circle().strokeBorder(Color.white, lineWidth: LiquidChart.endpointBorde))
                    .frame(width: LiquidChart.endpointRadio * 2,
                           height: LiquidChart.endpointRadio * 2)
                    .offset(x: px - LiquidChart.endpointRadio,
                            y: py - LiquidChart.endpointRadio)
            }
        }
    }

    // MARK: Overlay de scrub (I2 — regla + anillo por banda + chip negro)

    @ViewBuilder private func overlayScrub(_ i: Int, _ w: CGFloat, _ h: CGFloat) -> some View {
        let px = x(i, w)
        let py = y(puntos[i].valor, h)
        let colorAnillo = bandas.first { $0.contiene(puntos[i].valor) }?.color ?? tono

        // La regla vertical que corta el plot — la pieza pública compartida, con la tinta
        // Liquid (`scrubReglaAlfa`).
        CrosshairRule(x: px, height: h,
                      color: LiquidColor.tinta900.opacity(LiquidChart.scrubReglaAlfa))

        // El anillo sobre el punto, en el color de SU banda (paridad HighlightDot flat).
        Circle()
            .fill(LiquidColor.papelAlto)
            .overlay(Circle().strokeBorder(colorAnillo, lineWidth: LiquidChart.scrubAnilloBorde))
            .frame(width: LiquidChart.scrubAnilloDiametro,
                   height: LiquidChart.scrubAnilloDiametro)
            .offset(x: px - LiquidChart.scrubAnilloDiametro / 2,
                    y: py - LiquidChart.scrubAnilloDiametro / 2)
            .allowsHitTesting(false)

        // El chip negro «valor · fecha» FLOTA junto al punto: arriba del anillo (gap 8) y,
        // si se saldría por el techo, abajo; clampeado al plot — paridad GraficaRangos.
        let texto = formatoScrub(puntos[i].valor, puntos[i].fecha)
        let chipW = CGFloat(texto.count) * 5.6 + 16
        let chipX = Swift.max(canaleta, Swift.min(w - chipW, px - chipW / 2))
        let gap: CGFloat = 8
        let arribaY = py - gap - LiquidChart.scrubChipAlto
        let chipY = arribaY >= 0 ? arribaY : Swift.min(h - LiquidChart.scrubChipAlto, py + gap)
        Text(verbatim: texto)
            .font(LiquidChart.scrubChipFuente)
            .foregroundStyle(LiquidColor.papelAlto)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 6)
            .frame(width: chipW, height: LiquidChart.scrubChipAlto)
            .background(LiquidColor.tinta900, in: Capsule(style: .continuous))
            .offset(x: chipX, y: chipY)
            .accessibilityHidden(true)
    }
}

// MARK: - Pozos de estado compartidos

/// El pozo de gráfica vacía: el mensaje ya localizado del caller sobre un wash quieto.
struct LiquidChartVacio: View {
    let mensaje: String
    let alto: CGFloat

    var body: some View {
        Text(verbatim: mensaje)
            .font(LiquidType.cuerpo)
            .foregroundStyle(LiquidColor.tinta500)
            .multilineTextAlignment(.center)
            .padding(.horizontal, LiquidSpace.s400)
            .frame(maxWidth: .infinity)
            .frame(height: alto)
            .background(LiquidColor.tinta7,
                        in: RoundedRectangle(cornerRadius: LiquidRadius.control, style: .continuous))
    }
}

/// El pozo de carga: skeleton sobrio y ESTÁTICO (tres trazos mudos) — nada parpadea, y con
/// motion congelado se ve exactamente igual.
struct LiquidChartCargando: View {
    let alto: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s300) {
            Capsule().fill(LiquidColor.tinta10).frame(height: 2)
            Capsule().fill(LiquidColor.tinta10).frame(height: 2)
                .padding(.trailing, LiquidSpace.s800)
            Capsule().fill(LiquidColor.tinta10).frame(height: 2)
                .padding(.trailing, LiquidSpace.s400)
        }
        .padding(.horizontal, LiquidSpace.s400)
        .frame(maxWidth: .infinity)
        .frame(height: alto)
        .background(LiquidColor.tinta7,
                    in: RoundedRectangle(cornerRadius: LiquidRadius.control, style: .continuous))
        .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("Liquid · Chart core (plot + pozos)") {
    let bandas: [LiquidChartBanda] = [
        .init(lo: 71, hi: nil, color: LiquidColor.positivo, activa: false),
        .init(lo: 49, hi: 71, color: LiquidColor.cian, activa: true),
        .init(lo: nil, hi: 49, color: LiquidColor.atencion, activa: false),
    ]
    let cal: Calendar = Calendar.current
    let puntos: [(fecha: Date, valor: Double)] = (0..<14).map { (i: Int) -> (fecha: Date, valor: Double) in
        let fecha: Date = cal.date(byAdding: .day, value: i - 13, to: Date())!
        let onda: Double = 14.0 * sin(Double(i) / 2.1)
        let ruido: Double = Double((i * 7) % 5)
        return (fecha: fecha, valor: 56.0 + onda + ruido)
    }
    return VStack(alignment: .leading, spacing: LiquidSpace.s400) {
        // Plot con banda activa iluminada + joya + scrub asentado en un índice fijo.
        LiquidChartPlot(puntos: puntos, bandas: bandas, dominio: 30...95,
                        ticksY: [(71, "71"), (49, "49")], tono: LiquidColor.cian,
                        puntoHoy: (puntos[13].fecha, puntos[13].valor), hoyAnillo: false,
                        formatoScrub: { v, _ in "\(Int(v)) ms · mar 14" },
                        alto: LiquidChartAlto.explorador, scrubFijo: 7)
            .liquidGlass(.superficie)
        LiquidChartCargando(alto: LiquidChartAlto.trend)
        LiquidChartVacio(mensaje: "Sin lecturas en este rango.", alto: LiquidChartAlto.trend)
    }
    .padding(LiquidSpace.s550)
    .background(LiquidSheetFondo(tone: LiquidColor.cian))
    .environment(\.liquidMotionDisabled, true)
}
#endif
