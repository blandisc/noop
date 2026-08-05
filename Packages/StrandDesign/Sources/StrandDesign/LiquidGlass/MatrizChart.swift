import SwiftUI

// MARK: - FER-51 · Familia de gráficas «medios tonos» (Canvas puro, sin lógica de datos)
//
// Cada forma recibe datos YA derivados + `chartID` (semilla del dither compartido con F2).
// Historia en dither del hue a ~50 % alfa; HOY (último elemento, si no es nil) a ~95 %.
// Aro de alerta por punto/columna fuera (`MedidorLunar.Alerta`); rejilla fantasma
// (puntos tinta 5 %) cuando no hay datos. Punteada HORIZONTAL solo para referencia/base/banda.

// MARK: Shared draw helpers (file-private)

private enum MatrizChartDraw {
    static let cell: CGFloat = 2.0
    static let histAlfa: Double = 0.50
    static let hoyAlfa: Double = 0.95
    static let ghostDensidad: Double = 0.05
    static let dash: [CGFloat] = [3, 4]
    static let histR: CGFloat = 1.7
    static let hoyR: CGFloat = 2.5
    static let defaultHeight: CGFloat = 56

    static func yNorm(_ v: Double, domain: ClosedRange<Double>) -> CGFloat {
        let span = domain.upperBound - domain.lowerBound
        guard span > 0 else { return 0.5 }
        return CGFloat(min(max((v - domain.lowerBound) / span, 0), 1))
    }

    /// y desde el borde superior (0 = top). Valores altos → y menor.
    static func yTop(_ v: Double, domain: ClosedRange<Double>, height: CGFloat, pad: CGFloat = 2) -> CGFloat {
        let n = yNorm(v, domain: domain)
        let usable = max(height - pad * 2, 1)
        return pad + (1 - n) * usable
    }

    static func aro(_ ctx: GraphicsContext, en punto: CGPoint, radio: CGFloat, color: Color) {
        var p = Path()
        p.addArc(center: punto, radius: radio,
                 startAngle: .degrees(0), endAngle: .degrees(360), clockwise: false)
        ctx.stroke(p, with: .color(color.opacity(0.8)), style: StrokeStyle(lineWidth: 1))
    }

    static func dibujarAlerta(_ ctx: GraphicsContext, en punto: CGPoint,
                              radioBase: CGFloat, alerta: MedidorLunar.Alerta) {
        switch alerta {
        case .ninguna: break
        case .atencion:
            aro(ctx, en: punto, radio: radioBase + 2.4, color: LiquidColor.atencion)
        case .alarma:
            aro(ctx, en: punto, radio: radioBase + 2.4, color: LiquidColor.negativo)
            aro(ctx, en: punto, radio: radioBase + 4.6, color: LiquidColor.negativo)
        }
    }

    /// Rejilla fantasma: puntos de tinta al 5 % (sin hue de señal).
    static func rejillaFantasma(_ ctx: GraphicsContext, size: CGSize, chartID: String) {
        let step = cell * 2
        var i = 0
        var y: CGFloat = cell
        while y < size.height {
            var x: CGFloat = cell
            while x < size.width {
                if MatrizDither.encendido(x: Int(x / cell), y: Int(y / cell),
                                          densidad: ghostDensidad) {
                    let s = MatrizDither.semilla(chartID: chartID, index: i)
                    let p = MatrizDither.particula(s)
                    let r = 0.7 * CGFloat(p.dScale)
                    let px = x + CGFloat(p.dx)
                    let py = y + CGFloat(p.dy)
                    ctx.fill(Path(ellipseIn: CGRect(x: px - r, y: py - r,
                                                    width: r * 2, height: r * 2)),
                             with: .color(LiquidColor.tinta900.opacity(0.05 * p.dAlpha)))
                }
                i += 1
                x += step
            }
            y += step
        }
    }

    /// Rellena un rect con tramado Bayer + partícula irregular del hue.
    static func ditherRect(_ ctx: GraphicsContext, rect: CGRect, chartID: String,
                           seedIndex: Int, densidad: Double, hue: Color, alfa: Double) {
        guard rect.width > 0.5, rect.height > 0.5, densidad > 0 else { return }
        let dens = min(max(densidad, 0), 1)
        let originX = Int(floor(rect.minX / cell))
        let originY = Int(floor(rect.minY / cell))
        let endX = Int(ceil(rect.maxX / cell))
        let endY = Int(ceil(rect.maxY / cell))
        var k = 0
        for gy in originY..<endY {
            for gx in originX..<endX {
                guard MatrizDither.encendido(x: gx, y: gy, densidad: dens) else {
                    k += 1
                    continue
                }
                let s = MatrizDither.semilla(chartID: chartID, index: seedIndex &* 10_000 &+ k)
                let p = MatrizDither.particula(s)
                let cx = CGFloat(gx) * cell + cell * 0.5 + CGFloat(p.dx)
                let cy = CGFloat(gy) * cell + cell * 0.5 + CGFloat(p.dy)
                guard rect.contains(CGPoint(x: cx, y: cy)) else {
                    k += 1
                    continue
                }
                let r = 0.85 * CGFloat(p.dScale)
                ctx.fill(Path(ellipseIn: CGRect(x: cx - r, y: cy - r,
                                                width: r * 2, height: r * 2)),
                         with: .color(hue.opacity(alfa * p.dAlpha)))
                k += 1
            }
        }
    }

    /// Punto-partícula en la línea/columna (semilla = chartID+index del dato).
    static func puntoParticula(_ ctx: GraphicsContext, en centro: CGPoint,
                               chartID: String, index: Int, hue: Color,
                               alfa: Double, radio: CGFloat) {
        let s = MatrizDither.semilla(chartID: chartID, index: index)
        let p = MatrizDither.particula(s)
        let r = radio * CGFloat(p.dScale)
        let c = CGPoint(x: centro.x + CGFloat(p.dx), y: centro.y + CGFloat(p.dy))
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                 with: .color(hue.opacity(alfa * p.dAlpha)))
    }

    static func tieneDatos(_ valores: [Double?]) -> Bool {
        valores.contains { $0 != nil }
    }

    static func xAt(index: Int, count: Int, width: CGFloat, inset: CGFloat = 4) -> CGFloat {
        guard count > 1 else { return width / 2 }
        let usable = max(width - inset * 2, 1)
        return inset + CGFloat(index) / CGFloat(count - 1) * usable
    }
}

// MARK: - MatrizColumnas (SUEÑO)

/// 14 columnas-noche (alto = valor) + punteada horizontal de referencia con tag.
public struct MatrizColumnas: View {
    public struct Noche: Sendable, Equatable {
        public let valor: Double?
        public let alerta: MedidorLunar.Alerta
        public init(valor: Double?, alerta: MedidorLunar.Alerta = .ninguna) {
            self.valor = valor
            self.alerta = alerta
        }
    }

    private let chartID: String
    private let noches: [Noche]
    private let referencia: Double
    private let referenciaTag: String
    private let dominio: ClosedRange<Double>
    private let hue: Color

    public init(chartID: String, noches: [Noche], referencia: Double, referenciaTag: String,
                dominio: ClosedRange<Double>, hue: Color) {
        self.chartID = chartID
        self.noches = noches
        self.referencia = referencia
        self.referenciaTag = referenciaTag
        self.dominio = dominio
        self.hue = hue
    }

    public var body: some View {
        Canvas { ctx, size in
            let n = max(noches.count, 1)
            let hay = noches.contains { $0.valor != nil }
            if !hay {
                MatrizChartDraw.rejillaFantasma(ctx, size: size, chartID: chartID)
            } else {
                let gap: CGFloat = 2
                let colW = max((size.width - gap * CGFloat(n - 1)) / CGFloat(n), 1)
                let last = n - 1
                for (i, noche) in noches.enumerated() {
                    guard let v = noche.valor else { continue }
                    let esHoy = i == last
                    let alfa = esHoy ? MatrizChartDraw.hoyAlfa : MatrizChartDraw.histAlfa
                    let x = CGFloat(i) * (colW + gap)
                    let yn = MatrizChartDraw.yNorm(v, domain: dominio)
                    let h = max(yn * (size.height - 2), 1)
                    let rect = CGRect(x: x, y: size.height - h, width: colW, height: h)
                    // Densidad mayor hacia la cima de la columna (gradiente de medios tonos).
                    MatrizChartDraw.ditherRect(ctx, rect: rect, chartID: chartID,
                                               seedIndex: i, densidad: 0.55 + 0.35 * yn,
                                               hue: hue, alfa: alfa)
                    if esHoy {
                        // Tope de HOY más denso / saturado.
                        let cap = CGRect(x: x, y: size.height - h, width: colW,
                                         height: min(h, 4))
                        MatrizChartDraw.ditherRect(ctx, rect: cap, chartID: chartID,
                                                   seedIndex: i &+ 500, densidad: 0.9,
                                                   hue: hue, alfa: MatrizChartDraw.hoyAlfa)
                    }
                    if noche.alerta != .ninguna {
                        let centro = CGPoint(x: x + colW / 2, y: size.height - h)
                        MatrizChartDraw.dibujarAlerta(ctx, en: centro, radioBase: colW * 0.35,
                                                      alerta: noche.alerta)
                    }
                }
            }

            // Referencia punteada horizontal + tag.
            let yRef = MatrizChartDraw.yTop(referencia, domain: dominio, height: size.height)
            var linea = Path()
            linea.move(to: CGPoint(x: 0, y: yRef))
            linea.addLine(to: CGPoint(x: size.width, y: yRef))
            ctx.stroke(linea, with: .color(LiquidColor.tinta900.opacity(0.28)),
                       style: StrokeStyle(lineWidth: 1, dash: MatrizChartDraw.dash))

            let tag = Text(referenciaTag)
                .font(InstrumentoType.grotesk(9, weight: .medium))
                .foregroundColor(LiquidColor.tinta500)
                .monospacedDigit()
            ctx.draw(ctx.resolve(tag),
                     at: CGPoint(x: size.width - 2, y: yRef - 8),
                     anchor: .topTrailing)
        }
        .frame(maxWidth: .infinity, minHeight: MatrizChartDraw.defaultHeight,
               idealHeight: MatrizChartDraw.defaultHeight)
        .accessibilityHidden(true)
    }
}

// MARK: - MatrizLineaRellena (FC / VFC)

/// Línea + área rellena con dither + punteada horizontal = tu base.
public struct MatrizLineaRellena: View {
    private let chartID: String
    private let puntos: [Double?]
    private let base: Double?
    private let dominio: ClosedRange<Double>
    private let hue: Color
    private let alfa: Double
    private let alertaHoy: MedidorLunar.Alerta

    public init(chartID: String, puntos: [Double?], base: Double?, dominio: ClosedRange<Double>,
                hue: Color, alfa: Double = 1.0, alertaHoy: MedidorLunar.Alerta = .ninguna) {
        self.chartID = chartID
        self.puntos = puntos
        self.base = base
        self.dominio = dominio
        self.hue = hue
        self.alfa = alfa
        self.alertaHoy = alertaHoy
    }

    public var body: some View {
        Canvas { ctx, size in
            let count = puntos.count
            guard count > 0 else {
                MatrizChartDraw.rejillaFantasma(ctx, size: size, chartID: chartID)
                return
            }
            if !MatrizChartDraw.tieneDatos(puntos) {
                MatrizChartDraw.rejillaFantasma(ctx, size: size, chartID: chartID)
            } else {
                // Área rellena (dither por franjas verticales entre puntos consecutivos).
                for i in 0..<(count - 1) {
                    guard let a = puntos[i], let b = puntos[i + 1] else { continue }
                    let x0 = MatrizChartDraw.xAt(index: i, count: count, width: size.width)
                    let x1 = MatrizChartDraw.xAt(index: i + 1, count: count, width: size.width)
                    let y0 = MatrizChartDraw.yTop(a, domain: dominio, height: size.height)
                    let y1 = MatrizChartDraw.yTop(b, domain: dominio, height: size.height)
                    let midY = (y0 + y1) / 2
                    let rect = CGRect(x: x0, y: midY,
                                      width: max(x1 - x0, 1),
                                      height: max(size.height - midY, 1))
                    let dens = 0.28 + 0.25 * Double(MatrizChartDraw.yNorm((a + b) / 2,
                                                                          domain: dominio))
                    MatrizChartDraw.ditherRect(ctx, rect: rect, chartID: chartID,
                                               seedIndex: i, densidad: dens,
                                               hue: hue, alfa: MatrizChartDraw.histAlfa * alfa)
                }

                // Trazo de la línea (segmentos entre puntos no-nil consecutivos).
                var path = Path()
                var started = false
                for (i, val) in puntos.enumerated() {
                    guard let v = val else {
                        started = false
                        continue
                    }
                    let pt = CGPoint(x: MatrizChartDraw.xAt(index: i, count: count, width: size.width),
                                     y: MatrizChartDraw.yTop(v, domain: dominio, height: size.height))
                    if started { path.addLine(to: pt) } else { path.move(to: pt); started = true }
                }
                ctx.stroke(path, with: .color(hue.opacity(0.55 * alfa)),
                           style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))

                // Puntos-partícula.
                let last = count - 1
                for (i, val) in puntos.enumerated() {
                    guard let v = val else { continue }
                    let esHoy = i == last
                    let pt = CGPoint(x: MatrizChartDraw.xAt(index: i, count: count, width: size.width),
                                     y: MatrizChartDraw.yTop(v, domain: dominio, height: size.height))
                    let a = (esHoy ? MatrizChartDraw.hoyAlfa : MatrizChartDraw.histAlfa) * alfa
                    let r = esHoy ? MatrizChartDraw.hoyR : MatrizChartDraw.histR
                    MatrizChartDraw.puntoParticula(ctx, en: pt, chartID: chartID, index: i,
                                                   hue: hue, alfa: a, radio: r)
                    if esHoy {
                        MatrizChartDraw.dibujarAlerta(ctx, en: pt, radioBase: r,
                                                      alerta: alertaHoy)
                    }
                }
            }

            if let base {
                let yB = MatrizChartDraw.yTop(base, domain: dominio, height: size.height)
                var linea = Path()
                linea.move(to: CGPoint(x: 0, y: yB))
                linea.addLine(to: CGPoint(x: size.width, y: yB))
                ctx.stroke(linea, with: .color(LiquidColor.tinta900.opacity(0.28)),
                           style: StrokeStyle(lineWidth: 1, dash: MatrizChartDraw.dash))
            }
        }
        .frame(maxWidth: .infinity, minHeight: MatrizChartDraw.defaultHeight,
               idealHeight: MatrizChartDraw.defaultHeight)
        .accessibilityHidden(true)
    }
}

// MARK: - MatrizLineaSerena (GUARDIÁN)

/// Filo central + banda ± tenue + puntos-día casi sobre la línea (brincos fuera visibles).
public struct MatrizLineaSerena: View {
    private let chartID: String
    private let puntos: [Double?]
    private let banda: ClosedRange<Double>?
    private let dominio: ClosedRange<Double>
    private let hue: Color
    private let alertaHoy: MedidorLunar.Alerta

    public init(chartID: String, puntos: [Double?], banda: ClosedRange<Double>?,
                dominio: ClosedRange<Double>, hue: Color,
                alertaHoy: MedidorLunar.Alerta = .ninguna) {
        self.chartID = chartID
        self.puntos = puntos
        self.banda = banda
        self.dominio = dominio
        self.hue = hue
        self.alertaHoy = alertaHoy
    }

    public var body: some View {
        Canvas { ctx, size in
            let count = puntos.count
            if count == 0 || !MatrizChartDraw.tieneDatos(puntos) {
                MatrizChartDraw.rejillaFantasma(ctx, size: size, chartID: chartID)
            }

            // Banda ± (relleno dither tenue entre lower/upper).
            if let banda {
                let yLo = MatrizChartDraw.yTop(banda.upperBound, domain: dominio, height: size.height)
                let yHi = MatrizChartDraw.yTop(banda.lowerBound, domain: dominio, height: size.height)
                let bandRect = CGRect(x: 0, y: yLo, width: size.width,
                                      height: max(yHi - yLo, 1))
                MatrizChartDraw.ditherRect(ctx, rect: bandRect, chartID: chartID,
                                           seedIndex: 900, densidad: 0.18,
                                           hue: hue, alfa: 0.22)
                // Bordes de banda punteados (referencia).
                for y in [yLo, yHi] {
                    var p = Path()
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: size.width, y: y))
                    ctx.stroke(p, with: .color(LiquidColor.tinta900.opacity(0.18)),
                               style: StrokeStyle(lineWidth: 1, dash: MatrizChartDraw.dash))
                }
            }

            // Filo central (cero / base de la señal).
            let mid = (dominio.lowerBound + dominio.upperBound) / 2
            let yMid = MatrizChartDraw.yTop(mid, domain: dominio, height: size.height)
            var filo = Path()
            filo.move(to: CGPoint(x: 0, y: yMid))
            filo.addLine(to: CGPoint(x: size.width, y: yMid))
            ctx.stroke(filo, with: .color(LiquidColor.tinta900.opacity(0.22)),
                       style: StrokeStyle(lineWidth: 1))

            guard count > 0, MatrizChartDraw.tieneDatos(puntos) else { return }

            // Línea serena conectando puntos.
            var path = Path()
            var started = false
            for (i, val) in puntos.enumerated() {
                guard let v = val else { started = false; continue }
                let pt = CGPoint(x: MatrizChartDraw.xAt(index: i, count: count, width: size.width),
                                 y: MatrizChartDraw.yTop(v, domain: dominio, height: size.height))
                if started { path.addLine(to: pt) } else { path.move(to: pt); started = true }
            }
            ctx.stroke(path, with: .color(hue.opacity(0.45)),
                       style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round))

            let last = count - 1
            for (i, val) in puntos.enumerated() {
                guard let v = val else { continue }
                let esHoy = i == last
                let pt = CGPoint(x: MatrizChartDraw.xAt(index: i, count: count, width: size.width),
                                 y: MatrizChartDraw.yTop(v, domain: dominio, height: size.height))
                let a = esHoy ? MatrizChartDraw.hoyAlfa : MatrizChartDraw.histAlfa
                let r = esHoy ? MatrizChartDraw.hoyR : MatrizChartDraw.histR
                MatrizChartDraw.puntoParticula(ctx, en: pt, chartID: chartID, index: i,
                                               hue: hue, alfa: a, radio: r)
                if esHoy {
                    MatrizChartDraw.dibujarAlerta(ctx, en: pt, radioBase: r, alerta: alertaHoy)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: MatrizChartDraw.defaultHeight,
               idealHeight: MatrizChartDraw.defaultHeight)
        .accessibilityHidden(true)
    }
}

// MARK: - MatrizRielZona (CARGA)

/// Riel horizontal + zona dulce en dither + punto de la razón + estela de 5 previos.
public struct MatrizRielZona: View {
    private let chartID: String
    private let p: Double?
    private let zona: ClosedRange<Double>
    private let estela: [Double]
    private let hue: Color

    public init(chartID: String, p: Double?, zona: ClosedRange<Double>,
                estela: [Double], hue: Color) {
        self.chartID = chartID
        self.p = p
        self.zona = zona
        self.estela = estela
        self.hue = hue
    }

    public var body: some View {
        Canvas { ctx, size in
            let dominio = Self.dominio(p: p, zona: zona, estela: estela)
            let y = size.height / 2
            let inset: CGFloat = 8

            // Riel base.
            var riel = Path()
            riel.move(to: CGPoint(x: inset, y: y))
            riel.addLine(to: CGPoint(x: size.width - inset, y: y))
            ctx.stroke(riel, with: .color(LiquidColor.tinta900.opacity(0.14)),
                       style: StrokeStyle(lineWidth: 2, lineCap: .round))

            // Zona dulce en dither.
            let xZ0 = Self.x(zona.lowerBound, domain: dominio, width: size.width, inset: inset)
            let xZ1 = Self.x(zona.upperBound, domain: dominio, width: size.width, inset: inset)
            let zonaRect = CGRect(x: xZ0, y: y - 7, width: max(xZ1 - xZ0, 1), height: 14)
            MatrizChartDraw.ditherRect(ctx, rect: zonaRect, chartID: chartID,
                                       seedIndex: 0, densidad: 0.55,
                                       hue: hue, alfa: 0.40)
            // Ticks de borde de zona.
            for x in [xZ0, xZ1] {
                var tick = Path()
                tick.move(to: CGPoint(x: x, y: y - 6))
                tick.addLine(to: CGPoint(x: x, y: y + 6))
                ctx.stroke(tick, with: .color(hue.opacity(0.55)),
                           style: StrokeStyle(lineWidth: 1, lineCap: .round))
            }

            // Estela (más antigua → más transparente).
            let nE = estela.count
            for (i, v) in estela.enumerated() {
                let t = nE > 1 ? Double(i) / Double(nE - 1) : 1
                let alfa = 0.15 + 0.35 * t
                let x = Self.x(v, domain: dominio, width: size.width, inset: inset)
                MatrizChartDraw.puntoParticula(ctx, en: CGPoint(x: x, y: y),
                                               chartID: chartID, index: i,
                                               hue: hue, alfa: alfa, radio: 1.6)
            }

            // Punto HOY.
            if let p {
                let x = Self.x(p, domain: dominio, width: size.width, inset: inset)
                MatrizChartDraw.puntoParticula(ctx, en: CGPoint(x: x, y: y),
                                               chartID: chartID, index: 100 + nE,
                                               hue: hue, alfa: MatrizChartDraw.hoyAlfa,
                                               radio: 3.4)
            } else if estela.isEmpty {
                MatrizChartDraw.rejillaFantasma(ctx, size: size, chartID: chartID)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 28, idealHeight: 28)
        .accessibilityHidden(true)
    }

    private static func dominio(p: Double?, zona: ClosedRange<Double>,
                                estela: [Double]) -> ClosedRange<Double> {
        var vals = [zona.lowerBound, zona.upperBound] + estela
        if let p { vals.append(p) }
        let lo = (vals.min() ?? 0) - 0.15
        let hi = (vals.max() ?? 1) + 0.15
        return lo...max(hi, lo + 0.1)
    }

    private static func x(_ v: Double, domain: ClosedRange<Double>,
                          width: CGFloat, inset: CGFloat) -> CGFloat {
        let n = MatrizChartDraw.yNorm(v, domain: domain)
        let usable = max(width - inset * 2, 1)
        return inset + n * usable
    }
}

// MARK: - MatrizBarrasMini (ESFUERZO / PASOS)

/// N barras finas; HOY saturado; SIN juicio (nunca aro).
public struct MatrizBarrasMini: View {
    private let chartID: String
    private let valores: [Double?]
    private let hue: Color

    public init(chartID: String, valores: [Double?], hue: Color) {
        self.chartID = chartID
        self.valores = valores
        self.hue = hue
    }

    public var body: some View {
        Canvas { ctx, size in
            let n = max(valores.count, 1)
            if !MatrizChartDraw.tieneDatos(valores) {
                MatrizChartDraw.rejillaFantasma(ctx, size: size, chartID: chartID)
                return
            }
            let maxV = valores.compactMap { $0 }.max() ?? 1
            let gap: CGFloat = 1.5
            let barW = max((size.width - gap * CGFloat(n - 1)) / CGFloat(n), 1)
            let last = valores.count - 1
            for (i, val) in valores.enumerated() {
                guard let v = val, maxV > 0 else { continue }
                let esHoy = i == last
                let h = max(CGFloat(v / maxV) * (size.height - 2), 1)
                let x = CGFloat(i) * (barW + gap)
                let rect = CGRect(x: x, y: size.height - h, width: barW, height: h)
                let dens = esHoy ? 0.85 : 0.45
                let alfa = esHoy ? MatrizChartDraw.hoyAlfa : MatrizChartDraw.histAlfa
                MatrizChartDraw.ditherRect(ctx, rect: rect, chartID: chartID,
                                           seedIndex: i, densidad: dens,
                                           hue: hue, alfa: alfa)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 40, idealHeight: 40)
        .accessibilityHidden(true)
    }
}

// MARK: - MatrizEscalerita (ESTRÉS)

/// 7 puntos-día en 3 niveles verticales (geometría de forma; sin color de juicio).
public struct MatrizEscalerita: View {
    private let chartID: String
    private let niveles: [Int?]
    private let hue: Color

    public init(chartID: String, niveles: [Int?], hue: Color) {
        self.chartID = chartID
        self.niveles = niveles
        self.hue = hue
    }

    public var body: some View {
        Canvas { ctx, size in
            let count = max(niveles.count, 1)
            if niveles.allSatisfy({ $0 == nil }) {
                MatrizChartDraw.rejillaFantasma(ctx, size: size, chartID: chartID)
                return
            }
            // Tres rieles fantasma (niveles 0/1/2).
            for nivel in 0...2 {
                let y = Self.y(nivel: nivel, height: size.height)
                var riel = Path()
                riel.move(to: CGPoint(x: 2, y: y))
                riel.addLine(to: CGPoint(x: size.width - 2, y: y))
                ctx.stroke(riel, with: .color(LiquidColor.tinta900.opacity(0.08)),
                           style: StrokeStyle(lineWidth: 1))
            }

            let last = niveles.count - 1
            var prev: CGPoint?
            for (i, niv) in niveles.enumerated() {
                guard let nivel = niv else {
                    prev = nil
                    continue
                }
                let clamped = min(max(nivel, 0), 2)
                let esHoy = i == last
                let pt = CGPoint(x: MatrizChartDraw.xAt(index: i, count: count, width: size.width),
                                 y: Self.y(nivel: clamped, height: size.height))
                if let prev {
                    var seg = Path()
                    seg.move(to: prev)
                    seg.addLine(to: pt)
                    ctx.stroke(seg, with: .color(hue.opacity(0.35)),
                               style: StrokeStyle(lineWidth: 1, lineCap: .round))
                }
                let a = esHoy ? MatrizChartDraw.hoyAlfa : MatrizChartDraw.histAlfa
                let r = esHoy ? MatrizChartDraw.hoyR : MatrizChartDraw.histR
                MatrizChartDraw.puntoParticula(ctx, en: pt, chartID: chartID, index: i,
                                               hue: hue, alfa: a, radio: r)
                prev = pt
            }
        }
        .frame(maxWidth: .infinity, minHeight: 36, idealHeight: 36)
        .accessibilityHidden(true)
    }

    /// nivel 0 = bajo (abajo), 2 = alto (arriba).
    private static func y(nivel: Int, height: CGFloat) -> CGFloat {
        let pad: CGFloat = 6
        let usable = max(height - pad * 2, 1)
        let t = CGFloat(2 - min(max(nivel, 0), 2)) / 2  // 0→1, 1→0.5, 2→0
        return pad + t * usable
    }
}


// MARK: - Previews
//
// Los datasets se izan a locales con tipo EXPLÍCITO antes del view-builder: dentro de un
// `.map` con aritmética + ternario, el type-checker de Swift infiere a través de toda la
// cadena de la vista y revienta el presupuesto en CI (Xcode 26.6). Tipar aquí lo corta.

#Preview("Columnas · sueño") {
    let conDatos: [MatrizColumnas.Noche] = (0..<14).map { i in
        let alerta: MedidorLunar.Alerta = i == 13 ? .atencion : (i == 3 ? .alarma : .ninguna)
        return MatrizColumnas.Noche(valor: 5.5 + Double(i % 5) * 0.4, alerta: alerta)
    }
    let vacio = [MatrizColumnas.Noche](repeating: .init(valor: nil), count: 14)
    return VStack(spacing: 16) {
        MatrizColumnas(chartID: "sueno", noches: conDatos,
                       referencia: 7, referenciaTag: "7 h", dominio: 4...10, hue: LiquidColor.indigo)
        MatrizColumnas(chartID: "sueno-vacio", noches: vacio,
                       referencia: 7, referenciaTag: "7 h", dominio: 4...10, hue: LiquidColor.indigo)
    }
    .padding()
    .background(LiquidColor.papelMatriz)
}

#Preview("Línea rellena · FC") {
    let fc: [Double?] = (0..<20).map { i in 58 + Double(i % 7) - 2 }
    let vfc = [Double?](repeating: nil, count: 20)
    return VStack(spacing: 16) {
        MatrizLineaRellena(chartID: "fc", puntos: fc, base: 60, dominio: 50...75,
                           hue: LiquidColor.rosa, alertaHoy: .atencion)
        MatrizLineaRellena(chartID: "vfc", puntos: vfc, base: 40, dominio: 20...80,
                           hue: LiquidColor.cian, alfa: 0.6)
    }
    .padding()
    .background(LiquidColor.papelMatriz)
}

#Preview("Serena · riel · barras · escalera") {
    let temp: [Double?] = (0..<20).map { i in Double(i % 5) * 0.15 - 0.3 }
    let esfuerzo: [Double?] = (0..<14).map { i in Double(20 + i * 3) }
    let niveles: [Int?] = [0, 1, 1, 2, 1, 0, 2]
    let estela: [Double] = [0.95, 1.05, 1.2, 0.9, 1.0]
    return VStack(spacing: 16) {
        MatrizLineaSerena(chartID: "guardian-temp", puntos: temp, banda: -0.4...0.4,
                          dominio: -1...1, hue: LiquidColor.doradoTemp, alertaHoy: .alarma)
        MatrizRielZona(chartID: "carga", p: 1.12, zona: 0.8...1.3,
                       estela: estela, hue: LiquidColor.verdePrimario)
        MatrizBarrasMini(chartID: "esfuerzo", valores: esfuerzo, hue: LiquidColor.teal)
        MatrizEscalerita(chartID: "estres", niveles: niveles, hue: LiquidColor.tinta900)
    }
    .padding()
    .background(LiquidColor.papelMatriz)
}
