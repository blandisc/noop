import SwiftUI

// MARK: - FER-51 · Familia de gráficas de la Matriz (Canvas puro, sin lógica de datos)
//
// Cada forma recibe datos YA derivados + `chartID` (semilla estable). Revisión del dueño
// en vivo (2026-08-06): el dato se dibuja en el lenguaje LIQUID del app — curvas suaves,
// rellenos de gradiente tenue, barras redondeadas — nada de tramados de puntos (se leían
// sucios). La punteada HORIZONTAL queda solo para referencia/base/banda; HOY es el único
// punto marcado (más el aro de alerta de la gramática §8). Rejilla fantasma tenue cuando
// no hay datos.

// MARK: Shared draw helpers (internal — MatrizRegla los reutiliza)

enum MatrizChartDraw {
    static let cell: CGFloat = 2.0
    static let histAlfa: Double = MatrizTokens.histAlfa
    static let hoyAlfa: Double = MatrizTokens.hoyAlfa
    static let ghostDensidad: Double = 0.05
    static let dash: [CGFloat] = [3, 4]
    static let defaultHeight: CGFloat = MatrizTokens.alturaLinea

    static func yNorm(_ v: Double, domain: ClosedRange<Double>) -> CGFloat {
        let span = domain.upperBound - domain.lowerBound
        guard span > 0 else { return 0.5 }
        return CGFloat(min(max((v - domain.lowerBound) / span, 0), 1))
    }

    /// y desde el borde superior (0 = top). Valores altos → y menor.
    static func yTop(_ v: Double, domain: ClosedRange<Double>, height: CGFloat,
                     pad: CGFloat = MatrizTokens.chartPadV) -> CGFloat {
        let n = yNorm(v, domain: domain)
        let usable = max(height - pad * 2, 1)
        return pad + (1 - n) * usable
    }

    static func aro(_ ctx: GraphicsContext, en punto: CGPoint, radio: CGFloat, color: Color) {
        var p = Path()
        p.addArc(center: punto, radius: radio,
                 startAngle: .degrees(0), endAngle: .degrees(360), clockwise: false)
        ctx.stroke(p, with: .color(color.opacity(MatrizTokens.aroAlfa)),
                   style: StrokeStyle(lineWidth: 1))
    }

    static func dibujarAlerta(_ ctx: GraphicsContext, en punto: CGPoint,
                              radioBase: CGFloat, alerta: MedidorLunar.Alerta) {
        switch alerta {
        case .ninguna: break
        case .atencion:
            aro(ctx, en: punto, radio: radioBase + MatrizTokens.aroGap, color: LiquidColor.atencion)
        case .alarma:
            aro(ctx, en: punto, radio: radioBase + MatrizTokens.aroGap, color: LiquidColor.negativo)
            aro(ctx, en: punto, radio: radioBase + MatrizTokens.aroGap2, color: LiquidColor.negativo)
        }
    }

    /// HOY: el único marcador saturado + su aro §8 — compartido por toda la familia
    /// (un solo radio, un solo alfa; el alfa de sección NUNCA apaga a HOY). `aliento`
    /// escala SOLO el radio de HOY (respiro continuo, FER-60); el aro no respira.
    static func marcarHoy(_ ctx: GraphicsContext, puntos: [Double?], count: Int,
                          width: CGFloat, dominio: ClosedRange<Double>, height: CGFloat,
                          hue: Color, alerta: MedidorLunar.Alerta, aliento: CGFloat = 1) {
        guard let idx = puntos.lastIndex(where: { $0 != nil }), let v = puntos[idx] else { return }
        let pt = CGPoint(x: xAt(index: idx, count: count, width: width),
                         y: yTop(v, domain: dominio, height: height))
        punto(ctx, en: pt, radio: MatrizTokens.hoyRadio * aliento, hue: hue, alfa: MatrizTokens.hoyAlfa)
        if idx == count - 1 {
            dibujarAlerta(ctx, en: pt, radioBase: MatrizTokens.hoyRadio, alerta: alerta)
        }
    }

    /// Proyección horizontal de un valor (compartida: riel de carga y series).
    static func xNorm(_ v: Double, domain: ClosedRange<Double>,
                      width: CGFloat, inset: CGFloat) -> CGFloat {
        let n = yNorm(v, domain: domain)
        let usable = max(width - inset * 2, 1)
        return inset + n * usable
    }

    /// Cursor del scrub (FER-62): hilo fino vertical en la x leída — compartido por la
    /// familia (columnas lo tenía inline; ahora barras/escalera/línea lo reusan). `fantasma`
    /// (día sin lectura) → punteado tenue; con dato → sólido presente.
    static func cursorScrub(_ ctx: GraphicsContext, x: CGFloat, height: CGFloat,
                            hue: Color, fantasma: Bool) {
        var hilo = Path()
        hilo.move(to: CGPoint(x: x, y: 0))
        hilo.addLine(to: CGPoint(x: x, y: height))
        ctx.stroke(hilo, with: .color(hue.opacity(fantasma ? 0.35 : 0.9)),
                   style: StrokeStyle(lineWidth: 1.5, lineCap: .round,
                                      dash: fantasma ? [2, 3] : []))
    }

    /// Punto sólido (marcador de dato en el lenguaje Liquid).
    static func punto(_ ctx: GraphicsContext, en c: CGPoint, radio: CGFloat,
                      hue: Color, alfa: Double) {
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - radio, y: c.y - radio,
                                        width: radio * 2, height: radio * 2)),
                 with: .color(hue.opacity(alfa)))
    }

    /// Curva suave (Catmull-Rom → Bézier) por los puntos — la voz Liquid del app.
    static func curva(_ pts: [CGPoint]) -> Path {
        var path = Path()
        guard let first = pts.first else { return path }
        path.move(to: first)
        guard pts.count > 1 else { return path }
        for i in 0..<(pts.count - 1) {
            let p0 = i > 0 ? pts[i - 1] : pts[i]
            let p1 = pts[i]
            let p2 = pts[i + 1]
            let p3 = i + 2 < pts.count ? pts[i + 2] : p2
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
        return path
    }

    /// Curva + su relleno de gradiente (hue tenue → casi nada) hasta el piso del lienzo.
    static func curvaRellena(_ ctx: GraphicsContext, pts: [CGPoint], size: CGSize,
                             hue: Color, alfaLinea: Double, alfaRelleno: Double,
                             grosor: CGFloat = 1.5) {
        guard pts.count > 1 else { return }
        var area = curva(pts)
        area.addLine(to: CGPoint(x: pts[pts.count - 1].x, y: size.height))
        area.addLine(to: CGPoint(x: pts[0].x, y: size.height))
        area.closeSubpath()
        let topY = pts.map(\.y).min() ?? 0
        ctx.fill(area, with: .linearGradient(
            Gradient(colors: [hue.opacity(alfaRelleno), hue.opacity(alfaRelleno * 0.1)]),
            startPoint: CGPoint(x: 0, y: topY),
            endPoint: CGPoint(x: 0, y: size.height)))
        ctx.stroke(curva(pts), with: .color(hue.opacity(alfaLinea)),
                   style: StrokeStyle(lineWidth: grosor, lineCap: .round, lineJoin: .round))
    }

    /// Barra redondeada sólida (columna Liquid).
    static func barra(_ ctx: GraphicsContext, rect: CGRect, hue: Color, alfa: Double) {
        guard rect.height > 0.5, rect.width > 0.5 else { return }
        let radio = min(rect.width / 2, 2)
        ctx.fill(Path(roundedRect: rect, cornerRadius: radio), with: .color(hue.opacity(alfa)))
    }

    /// Rejilla fantasma: puntos de tinta al 5 % (sin hue de señal) — estado sin datos.
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

    static func tieneDatos(_ valores: [Double?]) -> Bool {
        valores.contains { $0 != nil }
    }

    static func xAt(index: Int, count: Int, width: CGFloat,
                    inset: CGFloat = MatrizTokens.chartInset) -> CGFloat {
        guard count > 1 else { return width / 2 }
        let usable = max(width - inset * 2, 1)
        return inset + CGFloat(index) / CGFloat(count - 1) * usable
    }

    /// Parte la serie en tramos contiguos (los huecos nil cortan el trazo).
    static func tramos(_ puntos: [Double?], count: Int, width: CGFloat,
                       dominio: ClosedRange<Double>, height: CGFloat) -> [[CGPoint]] {
        var out: [[CGPoint]] = []
        var actual: [CGPoint] = []
        for (i, val) in puntos.enumerated() {
            guard let v = val else {
                if actual.count > 1 { out.append(actual) }
                actual.removeAll()
                continue
            }
            actual.append(CGPoint(x: xAt(index: i, count: count, width: width),
                                  y: yTop(v, domain: dominio, height: height)))
        }
        if actual.count > 1 { out.append(actual) }
        return out
    }
}

// MARK: - Respiración de la Matriz (FER-60)

/// Entrada de asentado (settle-in one-shot): el chart aparece con un respiro —opacidad
/// 0.4→1 y una pizca de escala— UNA sola vez. Porta el ESPÍRITU de `MatrizRegla.entrar()`
/// (que escribe la curva con `.trim`) a los charts Canvas del contexto, donde no hay trim
/// posible. Reduce Motion: aparece asentado, sin animación.
struct MatrizEntrada: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // FER-audit: en previews/fixtures «sin motion» la entrada aparece asentada, como con RM.
    @Environment(\.liquidMotionDisabled) private var motionDisabled
    @State private var asentado = false
    func body(content: Content) -> some View {
        content
            .opacity(asentado ? 1 : 0.4)
            .scaleEffect(asentado ? 1 : 0.99, anchor: .bottom)
            .onAppear {
                guard !reduceMotion, !motionDisabled else { asentado = true; return }
                withAnimation(.easeOut(duration: 0.5).delay(0.05)) { asentado = true }
            }
    }
}

/// El respiro continuo de HOY (~1.07 de pico, ciclo sereno). Sólo el punto de HOY respira
/// (§ «solo hoy respira»); la historia queda quieta. Se alimenta de la fecha de un
/// `TimelineView`; con Reduce Motion el TimelineView se pausa y esto devuelve 1 (quieto).
enum MatrizAliento {
    static let periodo: Double = 3.4   // s por ciclo — lento, no distrae
    static func escala(_ date: Date, quieto: Bool) -> CGFloat {
        guard !quieto else { return 1 }
        let fase = date.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: periodo) / periodo
        return 1 + 0.07 * CGFloat(0.5 - 0.5 * cos(2 * .pi * fase))   // 1 → 1.07 → 1
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
    /// Índice resaltado por el scrub (FER-55): esa barra va a alfa pleno + cursor.
    private let resaltado: Int?

    public init(chartID: String, noches: [Noche], referencia: Double, referenciaTag: String,
                dominio: ClosedRange<Double>, hue: Color, resaltado: Int? = nil) {
        self.chartID = chartID
        self.noches = noches
        self.referencia = referencia
        self.referenciaTag = referenciaTag
        self.dominio = dominio
        self.hue = hue
        self.resaltado = resaltado
    }

    public var body: some View {
        Canvas { ctx, size in
            let n = max(noches.count, 1)
            let hay = noches.contains { $0.valor != nil }
            if !hay {
                MatrizChartDraw.rejillaFantasma(ctx, size: size, chartID: chartID)
            } else {
                let gap = MatrizTokens.barraGap
                let inset = MatrizTokens.chartInset
                // Sub-expresiones TIPADAS: la forma anidada agota el budget del type-checker en
                // el compile de iOS (ad-hoc CI) — «unable to type-check in reasonable time». Y el
                // set `0`-duplicado (idéntico) se consolidó en éste: doblaba la carga (FER-55).
                let usable: CGFloat = size.width - inset * 2 - gap * CGFloat(n - 1)
                let colW: CGFloat = max(usable / CGFloat(n), 1)
                let last = n - 1
                for (i, noche) in noches.enumerated() {
                    guard let v = noche.valor else {
                        // Noche sin lectura resaltada por el scrub: aún así damos feedback
                        // — un cursor tenue a lo alto en su columna (Grok #4: scrub fantasma).
                        if resaltado == i {
                            let cx = inset + CGFloat(i) * (colW + gap) + colW / 2
                            var hueco = Path()
                            hueco.move(to: CGPoint(x: cx, y: 0))
                            hueco.addLine(to: CGPoint(x: cx, y: size.height))
                            ctx.stroke(hueco, with: .color(hue.opacity(0.35)),
                                       style: StrokeStyle(lineWidth: 1.5, lineCap: .round,
                                                          dash: [2, 3]))
                        }
                        continue
                    }
                    let esHoy = i == last
                    // Durante el scrub la barra elegida toma el alfa pleno de HOY; el
                    // resto se atenúa a histórico (FER-55: la noche leída manda).
                    let seleccionada = resaltado == i
                    let alfa = (esHoy || seleccionada) ? MatrizTokens.hoyAlfa
                                                       : MatrizTokens.histAlfa
                    let x = inset + CGFloat(i) * (colW + gap)
                    let yn = MatrizChartDraw.yNorm(v, domain: dominio)
                    // Canal superior: territorio del tag de referencia — HOY nunca
                    // queda tapado por el rótulo (Grok-UI #5 / UX #7).
                    let h = max(yn * (size.height - MatrizTokens.tagCanal), 1)
                    let rect = CGRect(x: x, y: size.height - h, width: colW, height: h)
                    MatrizChartDraw.barra(ctx, rect: rect, hue: hue, alfa: alfa)
                    // Cursor del scrub: hilo fino sobre la columna leída (como las
                    // gráficas de adentro). Sube desde la barra hasta el tope del canal.
                    if seleccionada {
                        var hilo = Path()
                        let cx = x + colW / 2
                        hilo.move(to: CGPoint(x: cx, y: max(size.height - h - 3, 0)))
                        hilo.addLine(to: CGPoint(x: cx, y: size.height))
                        ctx.stroke(hilo, with: .color(hue.opacity(0.9)),
                                   style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    }
                    if noche.alerta != .ninguna {
                        let centro = CGPoint(x: x + colW / 2, y: size.height - h)
                        MatrizChartDraw.dibujarAlerta(ctx, en: centro, radioBase: colW * 0.35,
                                                      alerta: noche.alerta)
                    }
                }
            }

            // Referencia punteada horizontal + tag — en la MISMA escala del canal de
            // barras (auditoría de simetría Grok R1: antes yTop usaba otro pad y la
            // punteada quedaba 8 pt arriba del valor que decía marcar).
            let ynRef = MatrizChartDraw.yNorm(referencia, domain: dominio)
            let yRef = size.height - max(ynRef * (size.height - MatrizTokens.tagCanal), 1)
            var linea = Path()
            linea.move(to: CGPoint(x: 0, y: yRef))
            linea.addLine(to: CGPoint(x: size.width, y: yRef))
            ctx.stroke(linea, with: .color(LiquidColor.tinta900.opacity(MatrizTokens.refAlfa)),
                       style: StrokeStyle(lineWidth: 1, dash: MatrizChartDraw.dash))

            // El rótulo vive en el CANAL SUPERIOR (arriba-derecha), no pegado a la
            // punteada: con referencia baja en el dominio, el tag caía a media gráfica
            // y se encimaba con la barra de hoy (revisión del dueño, FER-55). Las barras
            // nunca entran a este canal (tope `tagCanal`), así que aquí está siempre libre.
            let tag = Text(referenciaTag)
                .font(LiquidType.caption)
                .foregroundColor(LiquidColor.tinta500)
                .monospacedDigit()
            ctx.draw(ctx.resolve(tag),
                     at: CGPoint(x: size.width - MatrizTokens.rielInset,
                                 y: MatrizTokens.chartPadV),
                     anchor: .topTrailing)
        }
        .frame(maxWidth: .infinity, minHeight: MatrizChartDraw.defaultHeight,
               idealHeight: MatrizChartDraw.defaultHeight)
        .accessibilityHidden(true)
    }
}

// MARK: - MatrizLineaRellena (FC / VFC)

/// Curva suave + relleno de gradiente + punteada horizontal = tu base. HOY marcado.
public struct MatrizLineaRellena: View {
    private let chartID: String
    private let puntos: [Double?]
    private let base: Double?
    private let dominio: ClosedRange<Double>
    private let hue: Color
    private let alfa: Double
    private let alertaHoy: MedidorLunar.Alerta
    /// Índice leído por el scrub (FER-62): marca su punto + cursor.
    private let resaltado: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.liquidAmbientPaused) private var ambientPaused
    @Environment(\.liquidMotionDisabled) private var motionDisabled
    private var quieto: Bool { reduceMotion || ambientPaused || motionDisabled }

    public init(chartID: String, puntos: [Double?], base: Double?, dominio: ClosedRange<Double>,
                hue: Color, alfa: Double = 1.0, alertaHoy: MedidorLunar.Alerta = .ninguna,
                resaltado: Int? = nil) {
        self.chartID = chartID
        self.puntos = puntos
        self.base = base
        self.dominio = dominio
        self.hue = hue
        self.alfa = alfa
        self.alertaHoy = alertaHoy
        self.resaltado = resaltado
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: LiquidMotion.intervaloAmbiente, paused: quieto)) { tl in
            let aliento = MatrizAliento.escala(tl.date, quieto: quieto)
            Canvas { ctx, size in
                let count = puntos.count
                if count == 0 || !MatrizChartDraw.tieneDatos(puntos) {
                    MatrizChartDraw.rejillaFantasma(ctx, size: size, chartID: chartID)
                } else {
                    for tramo in MatrizChartDraw.tramos(puntos, count: count, width: size.width,
                                                        dominio: dominio, height: size.height) {
                        MatrizChartDraw.curvaRellena(ctx, pts: tramo, size: size, hue: hue,
                                                     alfaLinea: MatrizTokens.lineaAlfa * alfa,
                                                     alfaRelleno: MatrizTokens.rellenoAlfa * alfa)
                    }

                    // HOY: el único punto marcado (+ aro §8) — saturado SIEMPRE, aunque
                    // la sección sea secundaria (hallazgo DeepSeek #5). Respira (FER-60).
                    MatrizChartDraw.marcarHoy(ctx, puntos: puntos, count: count,
                                              width: size.width, dominio: dominio,
                                              height: size.height, hue: hue, alerta: alertaHoy,
                                              aliento: aliento)
                }

                if let base {
                    let yB = MatrizChartDraw.yTop(base, domain: dominio, height: size.height)
                    var linea = Path()
                    linea.move(to: CGPoint(x: 0, y: yB))
                    linea.addLine(to: CGPoint(x: size.width, y: yB))
                    ctx.stroke(linea, with: .color(LiquidColor.tinta900.opacity(MatrizTokens.refAlfa)),
                               style: StrokeStyle(lineWidth: 1, dash: MatrizChartDraw.dash))
                }

                // FER-62 · Scrub: cursor en el día leído + su punto con halo de papel (se
                // separa de la curva, como la gota de la regla). Día sin lectura → cursor
                // fantasma en esa x (el texto dice «sin lectura»; la gráfica señala el día).
                if let r = resaltado, puntos.indices.contains(r) {
                    let x = MatrizChartDraw.xAt(index: r, count: max(count, 1), width: size.width)
                    if let v = puntos[r] {
                        let y = MatrizChartDraw.yTop(v, domain: dominio, height: size.height)
                        MatrizChartDraw.cursorScrub(ctx, x: x, height: size.height, hue: hue, fantasma: false)
                        MatrizChartDraw.punto(ctx, en: CGPoint(x: x, y: y),
                                              radio: MatrizTokens.hoyRadio + 1.6,
                                              hue: LiquidColor.papelMatriz, alfa: 1)
                        MatrizChartDraw.punto(ctx, en: CGPoint(x: x, y: y),
                                              radio: MatrizTokens.hoyRadio, hue: hue,
                                              alfa: MatrizChartDraw.hoyAlfa)
                    } else {
                        MatrizChartDraw.cursorScrub(ctx, x: x, height: size.height, hue: hue, fantasma: true)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: MatrizChartDraw.defaultHeight,
               idealHeight: MatrizChartDraw.defaultHeight)
        .accessibilityHidden(true)
        .modifier(MatrizEntrada())
    }
}

// MARK: - MatrizLineaSerena (GUARDIÁN)

/// Filo central + banda ± tenue + curva serena casi plana (brincos fuera visibles).
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

            // Rediseño del guardián (Grok-UI #4): CON banda, una sola tinta estructural —
            // el relleno redondeado «tu zona» — y el dominio se aprieta a banda×1.6 para
            // que la vena respire (antes: 4 líneas de estructura por 1 de dato y la curva
            // era un electro plano). SIN banda (resp: se juzga contra tu base z, no hay
            // corte fijo honesto que dibujar): filo central de referencia + curva.
            let dom: ClosedRange<Double> = {
                guard let banda else { return dominio }
                let c = (banda.lowerBound + banda.upperBound) / 2
                let half = (banda.upperBound - banda.lowerBound) / 2 * 1.6
                return (c - half)...(c + half)
            }()

            if let banda {
                let yLo = MatrizChartDraw.yTop(banda.upperBound, domain: dom, height: size.height)
                let yHi = MatrizChartDraw.yTop(banda.lowerBound, domain: dom, height: size.height)
                let bandRect = CGRect(x: 0, y: yLo, width: size.width,
                                      height: max(yHi - yLo, 1))
                ctx.fill(Path(roundedRect: bandRect, cornerRadius: 3),
                         with: .color(hue.opacity(MatrizTokens.bandaFillAlfa)))
            } else {
                let mid = (dom.lowerBound + dom.upperBound) / 2
                let yMid = MatrizChartDraw.yTop(mid, domain: dom, height: size.height)
                var filo = Path()
                filo.move(to: CGPoint(x: 0, y: yMid))
                filo.addLine(to: CGPoint(x: size.width, y: yMid))
                ctx.stroke(filo, with: .color(LiquidColor.tinta900.opacity(MatrizTokens.filoCentralAlfa)),
                           style: StrokeStyle(lineWidth: 1))
            }

            guard count > 0, MatrizChartDraw.tieneDatos(puntos) else { return }

            for tramo in MatrizChartDraw.tramos(puntos, count: count, width: size.width,
                                                dominio: dom, height: size.height) {
                ctx.stroke(MatrizChartDraw.curva(tramo), with: .color(hue.opacity(MatrizTokens.lineaSerenaAlfa)),
                           style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
            }

            MatrizChartDraw.marcarHoy(ctx, puntos: puntos, count: count,
                                      width: size.width, dominio: dom,
                                      height: size.height, hue: hue, alerta: alertaHoy)
        }
        .frame(maxWidth: .infinity, minHeight: MatrizChartDraw.defaultHeight,
               idealHeight: MatrizChartDraw.defaultHeight)
        .accessibilityHidden(true)
    }
}

// MARK: - MatrizColina (CARGA)

/// La mini-colina de Carga (FER-60): la silueta de `LiquidHill` destilada al tamaño de
/// celda. La forma ES la identidad de Carga — subes la cuesta, la cresta es tu equilibrio,
/// la bajada es la sobrecarga. Reemplaza al riel plano de antes: la razón se
/// posiciona en la escala 0…`maximo` y su punto CAMINA la pendiente; la estela de días
/// previos deja su rastro subiendo la cuesta; la zona de equilibrio se marca a susurro
/// (verde tenue, sin gritar «aprobado»); el aro §8 corona a HOY cuando la carga se dispara.
/// Sin scrub (eje de VALOR, no de día — Carga no se arrastra por día). El color vive en el
/// dato (el punto) y en la zona-susurro, nunca en un smear de bandas que a 40 pt mentiría.
public struct MatrizColina: View {
    private let chartID: String
    private let p: Double?
    private let zona: ClosedRange<Double>
    private let estela: [Double]
    private let hue: Color
    private let alertaHoy: MedidorLunar.Alerta
    /// Tope de la escala (paridad con `LiquidHill`): la razón vive en 0…`maximo`.
    private let maximo: Double
    /// Índice leído por el scrub (dueño /inject): el cursor CAMINA la cuesta al día leído.
    /// La serie completa es `estela + [p]` (viejo → HOY), así que resaltado ∈ 0…estela.count.
    private let resaltado: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.liquidAmbientPaused) private var ambientPaused
    @Environment(\.liquidMotionDisabled) private var motionDisabled
    private var quieto: Bool { reduceMotion || ambientPaused || motionDisabled }

    public init(chartID: String, p: Double?, zona: ClosedRange<Double>,
                estela: [Double], hue: Color, alertaHoy: MedidorLunar.Alerta = .ninguna,
                maximo: Double = 2.0, resaltado: Int? = nil) {
        self.chartID = chartID
        self.p = p
        self.zona = zona
        self.estela = estela
        self.hue = hue
        self.alertaHoy = alertaHoy
        self.maximo = maximo
        self.resaltado = resaltado
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: LiquidMotion.intervaloAmbiente, paused: quieto)) { tl in
            let aliento = MatrizAliento.escala(tl.date, quieto: quieto)
            Canvas { ctx, size in
            let w = max(size.width, 1)
            let h = size.height
            let inset = MatrizTokens.rielInset
            let baseY = h - MatrizTokens.colinaPadBajo

            // Sin dato ni estela → rejilla fantasma (misma familia).
            if p == nil, estela.isEmpty {
                MatrizChartDraw.rejillaFantasma(ctx, size: size, chartID: chartID)
                return
            }

            // 1 · Zona de equilibrio A SUSURRO: una barra verde tenue al pie, marcando en
            //     el eje dónde vive «tu costumbre» (lenguaje de zona de LiquidHill, pero un
            //     solo tramo y en susurro — sin el smear que a 40 pt leería «aprobado»).
            let xZ0 = Self.xDe(zona.lowerBound, maximo: maximo, width: w, inset: inset)
            let xZ1 = Self.xDe(zona.upperBound, maximo: maximo, width: w, inset: inset)
            let zonaRect = CGRect(x: xZ0, y: baseY - MatrizTokens.colinaZonaAlto,
                                  width: max(xZ1 - xZ0, 1), height: MatrizTokens.colinaZonaAlto)
            ctx.fill(Path(roundedRect: zonaRect, cornerRadius: MatrizTokens.colinaZonaAlto / 2),
                     with: .color(hue.opacity(MatrizTokens.colinaZonaAlfa)))

            // 2 · La colina: área tenue (tinta) + trazo (chrome, nunca color de dato).
            let area = Self.areaColina(width: w, height: h, inset: inset, baseY: baseY)
            ctx.fill(area, with: .linearGradient(
                Gradient(colors: [LiquidColor.tinta900.opacity(MatrizTokens.colinaAreaAlfa),
                                  LiquidColor.tinta900.opacity(0)]),
                startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: baseY)))
            ctx.stroke(Self.lineaColina(width: w, height: h, inset: inset),
                       with: .color(LiquidColor.tinta700.opacity(MatrizTokens.colinaLineaAlfa)),
                       style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))

            // 3 · Estela: los días previos caminando la cuesta (más antiguo → más tenue).
            let nE = estela.count
            for (i, v) in estela.enumerated() {
                let t = nE > 1 ? Double(i) / Double(nE - 1) : 1
                let alfa = 0.22 + 0.30 * t
                let x = Self.xDe(v, maximo: maximo, width: w, inset: inset)
                let y = Self.yEnX(x, width: w, height: h, inset: inset)
                MatrizChartDraw.punto(ctx, en: CGPoint(x: x, y: y),
                                      radio: MatrizTokens.histRadio, hue: hue, alfa: alfa)
            }

            // 4 · HOY: el punto en la pendiente + halo de papel + aro §8. El halo lo separa
            //     de la línea de la colina (como la gota de la regla); el aro reaparece
            //     igual en las dos caras (paridad Cosmos/Matriz — un pico ≥1.5 se ve).
            if let p {
                let x = Self.xDe(p, maximo: maximo, width: w, inset: inset)
                let y = Self.yEnX(x, width: w, height: h, inset: inset)
                // HOY respira (FER-60): el punto y su halo de papel crecen con `aliento`;
                // el aro §8 NO respira (una alarma no debe latir para leerse).
                MatrizChartDraw.punto(ctx, en: CGPoint(x: x, y: y),
                                      radio: (MatrizTokens.hoyRadio + 1.6) * aliento,
                                      hue: LiquidColor.papelMatriz, alfa: 1)
                MatrizChartDraw.punto(ctx, en: CGPoint(x: x, y: y),
                                      radio: MatrizTokens.hoyRadio * aliento, hue: hue,
                                      alfa: MatrizChartDraw.hoyAlfa)
                MatrizChartDraw.dibujarAlerta(ctx, en: CGPoint(x: x, y: y),
                                              radioBase: MatrizTokens.hoyRadio, alerta: alertaHoy)
            }

            // 5 · SCRUB (dueño /inject): el cursor CAMINA la cuesta al día leído. La serie es
            //     `estela + HOY`; el día resaltado toma halo de papel + punto pleno + cursor —
            //     se lee como HOY pero en su posición de VALOR sobre la pendiente.
            if let r = resaltado {
                let serie = estela + (p.map { [$0] } ?? [])
                if serie.indices.contains(r) {
                    let xr = Self.xDe(serie[r], maximo: maximo, width: w, inset: inset)
                    let yr = Self.yEnX(xr, width: w, height: h, inset: inset)
                    MatrizChartDraw.punto(ctx, en: CGPoint(x: xr, y: yr),
                                          radio: MatrizTokens.hoyRadio + 1.6,
                                          hue: LiquidColor.papelMatriz, alfa: 1)
                    MatrizChartDraw.punto(ctx, en: CGPoint(x: xr, y: yr),
                                          radio: MatrizTokens.hoyRadio, hue: hue,
                                          alfa: MatrizChartDraw.hoyAlfa)
                    MatrizChartDraw.cursorScrub(ctx, x: xr, height: h, hue: hue, fantasma: false)
                }
            }
            }
        }
        .frame(maxWidth: .infinity, minHeight: MatrizTokens.alturaRiel, idealHeight: MatrizTokens.alturaRiel)
        .accessibilityHidden(true)
        .modifier(MatrizEntrada())
    }

    // MARK: Geometría de la colina (bezier de LiquidHill escalada a la celda)

    /// Razón → x lineal en [inset, w-inset] sobre la escala 0…maximo (clampeada).
    static func xDe(_ v: Double, maximo: Double, width w: CGFloat, inset: CGFloat) -> CGFloat {
        let usable = max(w - inset * 2, 1)
        let frac = CGFloat(min(max(v / maximo, 0), 1))
        return inset + frac * usable
    }

    /// Puntos de control de la bezier (mock de LiquidHill: M0 92 C60 90,100 74,140 52
    /// C180 30,240 16,320 14) escalados a la celda: x a [inset, w-inset], y a [padAlto,
    /// baseY] con yN=(my-14)/78 (0 = cresta arriba, 1 = pie abajo).
    private static func ctrl(width w: CGFloat, height h: CGFloat, inset: CGFloat)
        -> [CGPoint] {
        let baseY = h - MatrizTokens.colinaPadBajo
        let topY = MatrizTokens.colinaPadAlto
        let usableY = max(baseY - topY, 1)
        let usableX = max(w - inset * 2, 1)
        func cx(_ mx: CGFloat) -> CGFloat { inset + (mx / 320) * usableX }
        func cy(_ my: CGFloat) -> CGFloat { topY + ((my - 14) / 78) * usableY }
        return [
            CGPoint(x: cx(0),   y: cy(92)),   // 0 · pie izquierdo (carga baja)
            CGPoint(x: cx(60),  y: cy(90)), CGPoint(x: cx(100), y: cy(74)),
            CGPoint(x: cx(140), y: cy(52)),  // 3 · cresta media
            CGPoint(x: cx(180), y: cy(30)), CGPoint(x: cx(240), y: cy(16)),
            CGPoint(x: cx(320), y: cy(14)),  // 6 · cima derecha (sobrecarga)
        ]
    }

    static func lineaColina(width w: CGFloat, height h: CGFloat, inset: CGFloat) -> Path {
        let c = ctrl(width: w, height: h, inset: inset)
        var p = Path()
        p.move(to: c[0])
        p.addCurve(to: c[3], control1: c[1], control2: c[2])
        p.addCurve(to: c[6], control1: c[4], control2: c[5])
        return p
    }

    static func areaColina(width w: CGFloat, height h: CGFloat, inset: CGFloat,
                           baseY: CGFloat) -> Path {
        let c = ctrl(width: w, height: h, inset: inset)
        var p = lineaColina(width: w, height: h, inset: inset)
        p.addLine(to: CGPoint(x: c[6].x, y: baseY))
        p.addLine(to: CGPoint(x: c[0].x, y: baseY))
        p.closeSubpath()
        return p
    }

    /// y sobre la curva en una x dada (muestreo de las dos cúbicas — port compacto de
    /// `LiquidHill.hillY`). Para colocar la estela y HOY «en la pendiente».
    static func yEnX(_ xTarget: CGFloat, width w: CGFloat, height h: CGFloat,
                     inset: CGFloat) -> CGFloat {
        let c = ctrl(width: w, height: h, inset: inset)
        var bestY = c[0].y
        var bestDist = CGFloat.greatestFiniteMagnitude
        var t: CGFloat = 0
        while t <= 1 {
            let (x1, y1) = Self.cubic(c[0], c[1], c[2], c[3], t)
            let d1 = abs(x1 - xTarget)
            if d1 < bestDist { bestDist = d1; bestY = y1 }
            let (x2, y2) = Self.cubic(c[3], c[4], c[5], c[6], t)
            let d2 = abs(x2 - xTarget)
            if d2 < bestDist { bestDist = d2; bestY = y2 }
            t += 0.02
        }
        return bestY
    }

    private static func cubic(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint,
                              _ t: CGFloat) -> (CGFloat, CGFloat) {
        let u = 1 - t
        let uu = u * u, tt = t * t
        let uuu = uu * u, ttt = tt * t
        let x = uuu * p0.x + 3 * uu * t * p1.x + 3 * u * tt * p2.x + ttt * p3.x
        let y = uuu * p0.y + 3 * uu * t * p1.y + 3 * u * tt * p2.y + ttt * p3.y
        return (x, y)
    }
}

// MARK: - MatrizBarrasMini (ESFUERZO / PASOS)

/// N barras finas redondeadas; HOY saturado; SIN juicio (nunca aro).
public struct MatrizBarrasMini: View {
    private let chartID: String
    private let valores: [Double?]
    private let hue: Color
    /// Índice leído por el scrub (FER-62): esa barra va a alfa pleno + cursor.
    private let resaltado: Int?

    public init(chartID: String, valores: [Double?], hue: Color, resaltado: Int? = nil) {
        self.chartID = chartID
        self.valores = valores
        self.hue = hue
        self.resaltado = resaltado
    }

    public var body: some View {
        Canvas { ctx, size in
            let n = max(valores.count, 1)
            if !MatrizChartDraw.tieneDatos(valores) {
                MatrizChartDraw.rejillaFantasma(ctx, size: size, chartID: chartID)
                return
            }
            let maxV = valores.compactMap { $0 }.max() ?? 1
            let gap = MatrizTokens.barraGap
            let inset = MatrizTokens.chartInset
            let usable: CGFloat = size.width - inset * 2 - gap * CGFloat(n - 1)
            let barW: CGFloat = max(usable / CGFloat(n), 1)
            let last = valores.count - 1
            for (i, val) in valores.enumerated() {
                let x = inset + CGFloat(i) * (barW + gap)
                let cx = x + barW / 2
                let seleccionada = resaltado == i
                guard let v = val, maxV > 0 else {
                    // Día leído sin lectura: cursor fantasma en su cajón (paridad columnas).
                    if seleccionada {
                        MatrizChartDraw.cursorScrub(ctx, x: cx, height: size.height, hue: hue, fantasma: true)
                    }
                    continue
                }
                let esHoy = i == last
                let h = max(CGFloat(v / maxV) * (size.height - MatrizTokens.chartPadV), 1)
                let rect = CGRect(x: x, y: size.height - h, width: barW, height: h)
                // La barra leída toma el alfa pleno de HOY; el cursor la distingue de HOY.
                MatrizChartDraw.barra(ctx, rect: rect, hue: hue,
                                      alfa: (esHoy || seleccionada) ? MatrizTokens.hoyAlfa : MatrizTokens.histAlfa)
                if seleccionada {
                    MatrizChartDraw.cursorScrub(ctx, x: cx, height: size.height, hue: hue, fantasma: false)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: MatrizTokens.alturaBarras, idealHeight: MatrizTokens.alturaBarras)
        .accessibilityHidden(true)
        // Entrada de asentado como sus vecinas de contexto; las barras no respiran (HOY
        // ya se distingue por saturación — un punto respira, una barra no).
        .modifier(MatrizEntrada())
    }
}

// MARK: - MatrizEscalerita (ESTRÉS)

/// 7 puntos-día en 3 niveles verticales (geometría de forma; sin color de juicio).
public struct MatrizEscalerita: View {
    private let chartID: String
    private let niveles: [Int?]
    private let hue: Color
    /// Índice leído por el scrub (FER-62): ese punto va a alfa pleno + cursor.
    private let resaltado: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.liquidAmbientPaused) private var ambientPaused
    @Environment(\.liquidMotionDisabled) private var motionDisabled
    private var quieto: Bool { reduceMotion || ambientPaused || motionDisabled }

    public init(chartID: String, niveles: [Int?], hue: Color, resaltado: Int? = nil) {
        self.chartID = chartID
        self.niveles = niveles
        self.hue = hue
        self.resaltado = resaltado
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: LiquidMotion.intervaloAmbiente, paused: quieto)) { tl in
            let aliento = MatrizAliento.escala(tl.date, quieto: quieto)
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
                    riel.move(to: CGPoint(x: MatrizTokens.chartInset, y: y))
                    riel.addLine(to: CGPoint(x: size.width - MatrizTokens.chartInset, y: y))
                    ctx.stroke(riel, with: .color(LiquidColor.tinta900.opacity(MatrizTokens.rielFantasmaAlfa)),
                               style: StrokeStyle(lineWidth: 1))
                }

                // La escalera como curva suave por los niveles: NEUTRA (tinta de sección)
                // para que el color viva en los puntos, no en la línea conectora.
                let pts: [CGPoint] = niveles.enumerated().compactMap { i, niv in
                    guard let nivel = niv else { return nil }
                    let clamped = min(max(nivel, 0), 2)
                    return CGPoint(x: MatrizChartDraw.xAt(index: i, count: count, width: size.width),
                                   y: Self.y(nivel: clamped, height: size.height))
                }
                if pts.count > 1 {
                    ctx.stroke(MatrizChartDraw.curva(pts), with: .color(hue.opacity(MatrizTokens.lineaEscaleraAlfa)),
                               style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
                }

                let last = niveles.count - 1
                for (i, niv) in niveles.enumerated() {
                    let cx = MatrizChartDraw.xAt(index: i, count: count, width: size.width)
                    let seleccionada = resaltado == i
                    guard let nivel = niv else {
                        // Día leído sin lectura: cursor fantasma en su x (paridad familia).
                        if seleccionada {
                            MatrizChartDraw.cursorScrub(ctx, x: cx, height: size.height, hue: hue, fantasma: true)
                        }
                        continue
                    }
                    let clamped = min(max(nivel, 0), 2)
                    let esHoy = i == last
                    let pt = CGPoint(x: cx, y: Self.y(nivel: clamped, height: size.height))
                    // FER-60 · Heatmap por-punto: cada día toma el COLOR de su nivel (no el
                    // hue de sección). La historia usa `heatHistAlfa` para que el ocre/siena
                    // se lea; HOY sigue saturado y RESPIRA (radio × aliento). FER-62: el punto
                    // leído por el scrub se agranda a HOY (sin respirar) + su cursor.
                    let radio = esHoy ? MatrizTokens.hoyRadio * aliento
                                      : (seleccionada ? MatrizTokens.hoyRadio : MatrizTokens.histRadio)
                    MatrizChartDraw.punto(ctx, en: pt, radio: radio,
                                          hue: Self.colorNivel(clamped),
                                          alfa: (esHoy || seleccionada) ? MatrizChartDraw.hoyAlfa : MatrizTokens.heatHistAlfa)
                    if seleccionada {
                        MatrizChartDraw.cursorScrub(ctx, x: cx, height: size.height, hue: hue, fantasma: false)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: MatrizTokens.alturaEscalera, idealHeight: MatrizTokens.alturaEscalera)
        .accessibilityHidden(true)
        .modifier(MatrizEntrada())
    }

    /// nivel 0 = bajo (abajo), 2 = alto (arriba) — proyección compartida.
    private static func y(nivel: Int, height: CGFloat) -> CGFloat {
        MatrizChartDraw.yTop(Double(min(max(nivel, 0), 2)), domain: 0...2,
                             height: height, pad: MatrizTokens.escaleraPadV)
    }

    /// FER-60 · Color de calor por nivel de estrés: bajo = tinta neutra (sin calor),
    /// medio = ocre, alto = siena. Es una rampa de CALOR, no de juicio: nunca el verde del
    /// veredicto ni el ámbar/rojo de alerta del guardián (que sí votan). `static` para
    /// testear la distinción como contrato (MatrizContrasteTests). Clampa fuera de 0…2.
    static func colorNivel(_ nivel: Int) -> Color {
        switch min(max(nivel, 0), 2) {
        case 0: return LiquidColor.tinta500
        case 1: return LiquidColor.estresMedio
        default: return LiquidColor.estresAlto
        }
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
        MatrizColina(chartID: "carga", p: 1.12, zona: 0.8...1.3,
                       estela: estela, hue: LiquidColor.verdePrimario)
        MatrizBarrasMini(chartID: "esfuerzo", valores: esfuerzo, hue: LiquidColor.teal)
        MatrizEscalerita(chartID: "estres", niveles: niveles, hue: LiquidColor.tinta900)
    }
    .padding()
    .background(LiquidColor.papelMatriz)
}
