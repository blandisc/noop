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
        // Un valor no finito no tiene «altura»: al centro, sin NaN en el path (FER-128, Grok).
        guard span > 0, span.isFinite, v.isFinite else { return 0.5 }
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
        // Una sola lectura = HOY: al final del ancho útil, como la regla y las columnas (FER-128).
        guard count > 1 else { return width - inset }
        let usable = max(width - inset * 2, 1)
        // `index` acotado a [0, count − 1]: un `count` declarado menor que la serie real no
        // proyecta puntos fuera del lienzo (FER-128, Grok).
        let i = min(max(index, 0), count - 1)
        return inset + CGFloat(i) / CGFloat(count - 1) * usable
    }

    /// Parte la serie en tramos contiguos (los huecos nil cortan el trazo).
    static func tramos(_ puntos: [Double?], count: Int, width: CGFloat,
                       dominio: ClosedRange<Double>, height: CGFloat,
                       inset: CGFloat = MatrizTokens.chartInset) -> [[CGPoint]] {
        var out: [[CGPoint]] = []
        var actual: [CGPoint] = []
        for (i, val) in puntos.enumerated() {
            guard let v = val, v.isFinite else {
                if !actual.isEmpty { out.append(actual) }
                actual.removeAll()
                continue
            }
            actual.append(CGPoint(x: xAt(index: i, count: count, width: width, inset: inset),
                                  y: yTop(v, domain: dominio, height: height)))
        }
        if !actual.isEmpty { out.append(actual) }
        // Los tramos de UN punto también salen (FER-128, explorador Grok: una lectura aislada
        // entre dos huecos desaparecía de la línea): el consumidor los pinta como punto suelto.
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
                            MatrizChartDraw.cursorScrub(ctx, x: cx, height: size.height, hue: hue, fantasma: true)
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
                        // El mismo cursor que barras, escalera e hilos (Q2-12): a todo lo alto.
                        MatrizChartDraw.cursorScrub(ctx, x: x + colW / 2, height: size.height, hue: hue, fantasma: false)
                    }
                    if noche.alerta != .ninguna {
                        let centro = CGPoint(x: x + colW / 2, y: size.height - h)
                        // El aro no puede ser más ancho que el paso entre columnas: dos noches
                        // marcadas seguidas se cruzaban como un ocho (FER-128, explorador).
                        let radioAro = min(colW * 0.35, (colW + gap) / 2 - MatrizTokens.aroGap - 0.5)
                        MatrizChartDraw.dibujarAlerta(ctx, en: centro, radioBase: max(radioAro, 1),
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
            // Cromo de LIENZO, no texto de lectura: fijo como `etiquetaEje` — su canal (`tagCanal`)
            // es fijo y a AX un rótulo que escala entraba al territorio de la columna de HOY (Q2-11).
            let tag = Text(referenciaTag)
                .font(LiquidType.caption)
                .foregroundColor(LiquidColor.tinta500)
                .monospacedDigit()
            // Cuando el dedo lee una de las dos últimas columnas, el cursor cruzaba el rótulo: el
            // tag se pasa a la izquierda mientras tanto (FER-128, explorador r3).
            let cursorALaDerecha = resaltado.map { $0 >= n - 2 } ?? false
            ctx.draw(ctx.resolve(tag),
                     at: CGPoint(x: cursorALaDerecha ? MatrizTokens.rielInset : size.width - MatrizTokens.rielInset,
                                 y: MatrizTokens.chartPadV),
                     anchor: cursorALaDerecha ? .topLeading : .topTrailing)
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
                        if tramo.count == 1, let p = tramo.first {
                            // Lectura aislada entre huecos: un punto, no una curva de cero largo.
                            MatrizChartDraw.punto(ctx, en: p, radio: MatrizTokens.histRadio, hue: hue,
                                                  alfa: MatrizTokens.lineaAlfa * alfa)
                            continue
                        }
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
        // FER-73 · M5: sin `minHeight` — el host fija el alto de la fila (VFC va en 40 pt) y
        // el piso de 56 lo desbordaba sobre las filas vecinas.
        .frame(maxWidth: .infinity, idealHeight: MatrizChartDraw.defaultHeight)
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
    /// Índice leído por el scrub (Skin temp/Breathing, dueño 2026-08-15): cursor + punto pleno.
    private let resaltado: Int?

    public init(chartID: String, puntos: [Double?], banda: ClosedRange<Double>?,
                dominio: ClosedRange<Double>, hue: Color,
                alertaHoy: MedidorLunar.Alerta = .ninguna, resaltado: Int? = nil) {
        self.chartID = chartID
        self.puntos = puntos
        self.banda = banda
        self.dominio = dominio
        self.hue = hue
        self.alertaHoy = alertaHoy
        self.resaltado = resaltado
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
                // La banda «tu patrón»: la MISMA franja pálida de la mini-gráfica de la hoja
                // del guardián (dueño 2026-08-15: «que se vean como esas»). Sin filos — la
                // referencia no los tiene; el patrón es un colchón, no un umbral marcado.
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

            // FER-73 · M3/M4: UNA sola rejilla. La línea usaba `xAt` (inset 4) y los puntos, el
            // anillo de HOY y el cursor del scrub un mapeo crudo `W·i/(n−1)`: dos rejillas que se
            // separaban hasta 4 pt en los extremos, y el anillo de HOY caía justo en x=W, donde el
            // Canvas lo recorta a la mitad. El aire vive ADENTRO del mapeo (como `LiquidChartPlot`),
            // así que ya no hace falta el `.padding` exterior que encogía la banda.
            // P-3: el MISMO inset que usa el mapeo del dedo (una sola fuente).
            let insetX = MatrizHoyFace.chartInset(.lineaSerena(puntos: puntos, banda: banda,
                                                               dominio: dominio, alertaHoy: alertaHoy))
            func x(_ i: Int) -> CGFloat {
                MatrizChartDraw.xAt(index: i, count: count, width: size.width, inset: insetX)
            }

            // El MISMO idioma que la mini-gráfica de la hoja del guardián (LiquidChartPlot
            // .mini), con SUS tokens (LiquidChart.*) para que sean literalmente una familia:
            // trazo lineaAncho (2.2) en tono PLENO con líneas rectas entre puntos (no curva),
            // un punto sólido puntoDatoRadio (3.0) POR NOCHE, y HOY = anillo hueco (papel +
            // borde del tono). Dueño 2026-08-15: «que se vean como esas, que tienen cada punto».
            let idxHoy = puntos.lastIndex(where: { $0 != nil })
            for tramo in MatrizChartDraw.tramos(puntos, count: count, width: size.width,
                                                dominio: dom, height: size.height, inset: insetX)
                where tramo.count > 1 {   // los puntos por noche ya se pintan aparte abajo
                var linea = Path()
                for (k, pt) in tramo.enumerated() { k == 0 ? linea.move(to: pt) : linea.addLine(to: pt) }
                ctx.stroke(linea, with: .color(hue),
                           style: StrokeStyle(lineWidth: LiquidChart.lineaAncho, lineCap: .round, lineJoin: .round))
            }
            for (i, v) in puntos.enumerated() where i != idxHoy {
                guard let v else { continue }
                let y = MatrizChartDraw.yTop(v, domain: dom, height: size.height)
                MatrizChartDraw.punto(ctx, en: CGPoint(x: x(i), y: y),
                                      radio: LiquidChart.puntoDatoRadio, hue: hue, alfa: 1)
            }
            if let idxHoy, let vHoy = puntos[idxHoy] {
                let y = MatrizChartDraw.yTop(vHoy, domain: dom, height: size.height)
                let c = CGPoint(x: x(idxHoy), y: y)
                // Anillo hueco de HOY: papel adentro, borde del tono (endpointBorde) afuera.
                let rExt = LiquidChart.puntoDatoRadio + LiquidChart.endpointBorde * 0.5
                MatrizChartDraw.punto(ctx, en: c, radio: rExt, hue: hue, alfa: 1)
                MatrizChartDraw.punto(ctx, en: c, radio: rExt - LiquidChart.endpointBorde,
                                      hue: LiquidColor.papelAlto, alfa: 1)
                MatrizChartDraw.dibujarAlerta(ctx, en: c, radioBase: rExt, alerta: alertaHoy)
            }

            // Scrub (dueño 2026-08-15): cursor + punto pleno en la noche leída. Serie de tiempo:
            // el índice mapea a x uniforme, el cursor sigue al dedo.
            if let r = resaltado, puntos.indices.contains(r) {
                let cursorX = x(r)
                if let v = puntos[r] {
                    let y = MatrizChartDraw.yTop(v, domain: dom, height: size.height)
                    MatrizChartDraw.punto(ctx, en: CGPoint(x: cursorX, y: y),
                                          radio: MatrizTokens.hoyRadio, hue: hue,
                                          alfa: MatrizChartDraw.hoyAlfa)
                }
                MatrizChartDraw.cursorScrub(ctx, x: cursorX, height: size.height, hue: hue,
                                            fantasma: puntos[r] == nil)
            }
        }
        // FER-73 · M5: `idealHeight` SIN `minHeight`. El renglón del guardián reserva 32 pt y
        // el `minHeight: 56` del Canvas le ganaba: la gráfica medía 56 y sus valores fuera de
        // banda se pintaban encima del encabezado y del renglón vecino.
        .frame(maxWidth: .infinity, idealHeight: MatrizChartDraw.defaultHeight)
        .accessibilityHidden(true)
    }
}

// MARK: - MatrizColina (CARGA)

/// La colina de Carga: desde FER-125 es la CAMPANA del prototipo aprobado por el dueño (antes,
/// FER-60, la cuesta de `LiquidHill`). La razón se posiciona en x sobre `colinaLo…colinaHi`; la
/// campana (centrada en la mitad de la zona ideal) es la forma que enseña dónde vive «tu
/// costumbre», no un dato; la banda 0.8–1.3 va de arriba abajo con sus dos etiquetas; la
/// estela de días previos son puntos tenues sobre la curva; HOY es punto lleno con centro de
/// papel y guía punteada al pie; el aro §8 corona a HOY cuando la carga se dispara. Con scrub
/// el punto camina la campana al día leído (FER-62 · /inject del dueño).
public struct MatrizColina: View {
    private let chartID: String
    private let p: Double?
    private let zona: ClosedRange<Double>
    private let estela: [Double]
    private let hue: Color
    private let alertaHoy: MedidorLunar.Alerta
    /// Índice leído por el scrub (dueño /inject): el punto CAMINA la campana al día leído.
    /// La serie completa es `estela + [p]` (viejo → HOY), así que resaltado ∈ 0…estela.count.
    private let resaltado: Int?

    public init(chartID: String, p: Double?, zona: ClosedRange<Double>,
                estela: [Double], hue: Color, alertaHoy: MedidorLunar.Alerta = .ninguna,
                resaltado: Int? = nil) {
        self.chartID = chartID
        self.p = p
        self.zona = zona
        self.estela = estela
        self.hue = hue
        self.alertaHoy = alertaHoy
        self.resaltado = resaltado
    }

    // FER-125 (dueño en simulador, «Carga como el mockup»): la colina es la CAMPANA del
    // prototipo aprobado — una gaussiana centrada en la mitad de la zona ideal — con la banda
    // 0.8–1.3 pintada de arriba abajo, el trazo y el área en el hue de la sección, la estela
    // de los días previos como puntos tenues SOBRE la curva, y HOY como punto lleno con centro
    // de papel y una guía punteada hasta el pie, entre las dos etiquetas de la zona. La altura
    // de la campana NO es dato: es la forma que enseña dónde vive «tu costumbre»; el dato es
    // la x. Reduce Motion: nada respira aquí (la campana no tiene aliento).
    public var body: some View {
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

            // 1 · La banda de la zona ideal (0.8–1.3): de arriba abajo, en el hue, tenue.
            let xZ0 = Self.xDe(zona.lowerBound, width: w, inset: inset)
            let xZ1 = Self.xDe(zona.upperBound, width: w, inset: inset)
            let banda = CGRect(x: xZ0, y: 0, width: max(xZ1 - xZ0, 1), height: baseY)
            ctx.fill(Path(roundedRect: banda, cornerRadius: MatrizTokens.colinaBandaRadio),
                     with: .color(hue.opacity(MatrizTokens.colinaBandaAlfa)))

            // 2 · La campana: área en el hue + trazo en el hue (como el prototipo).
            let area = Self.areaCampana(width: w, height: h, inset: inset, baseY: baseY)
            ctx.fill(area, with: .color(hue.opacity(MatrizTokens.colinaAreaAlfa)))
            ctx.stroke(Self.lineaCampana(width: w, height: h, inset: inset),
                       with: .color(hue),
                       style: StrokeStyle(lineWidth: MatrizTokens.colinaTrazo, lineCap: .round, lineJoin: .round))

            // 3 · Estela: los días previos sobre la curva, tenues (más antiguo → más tenue).
            let nE = estela.count
            for (i, v) in estela.enumerated() {
                let t = nE > 1 ? Double(i) / Double(nE - 1) : 1
                let alfa = MatrizTokens.colinaEstelaAlfaMin
                    + (MatrizTokens.colinaEstelaAlfa - MatrizTokens.colinaEstelaAlfaMin) * t
                let x = Self.xDe(v, width: w, inset: inset)
                let y = Self.yEnX(x, width: w, height: h, inset: inset)
                MatrizChartDraw.punto(ctx, en: CGPoint(x: x, y: y),
                                      radio: MatrizTokens.histRadio, hue: hue, alfa: alfa)
            }

            // 4 · HOY (o el día leído por el scrub): guía punteada hasta el pie + punto lleno con
            //     centro de papel + el aro §8 (una alarma no late para leerse).
            let serie = estela + (p.map { [$0] } ?? [])
            let iLeido: Int? = resaltado.flatMap { serie.indices.contains($0) ? $0 : nil }
            let vHoy: Double? = iLeido.map { serie[$0] } ?? p
            if let v = vHoy {
                let x = Self.xDe(v, width: w, inset: inset)
                let y = Self.yEnX(x, width: w, height: h, inset: inset)
                var guia = Path()
                guia.move(to: CGPoint(x: x, y: y))
                guia.addLine(to: CGPoint(x: x, y: baseY))
                ctx.stroke(guia, with: .color(hue),
                           style: StrokeStyle(lineWidth: MatrizTokens.colinaGuiaTrazo, lineCap: .round,
                                              dash: MatrizTokens.colinaGuiaDash))
                MatrizChartDraw.punto(ctx, en: CGPoint(x: x, y: y),
                                      radio: MatrizTokens.colinaHoyRadio, hue: hue, alfa: MatrizChartDraw.hoyAlfa)
                MatrizChartDraw.punto(ctx, en: CGPoint(x: x, y: y),
                                      radio: MatrizTokens.colinaHoyCentro, hue: LiquidColor.papelTarjeta, alfa: 1)
                // El aro §8 es de HOY: solo si HOY existe (`p`) y es lo que se está mostrando —
                // no sobre el último día de la estela cuando hoy no tiene dato.
                if p != nil, iLeido == nil || iLeido == serie.count - 1 {
                    MatrizChartDraw.dibujarAlerta(ctx, en: CGPoint(x: x, y: y),
                                                  radioBase: MatrizTokens.colinaHoyRadio, alerta: alertaHoy)
                }
                if iLeido != nil {
                    MatrizChartDraw.cursorScrub(ctx, x: x, height: h, hue: hue, fantasma: false)
                }
            }

            // 5 · Las etiquetas de la zona (0.8 · 1.3), bajo sus bordes, en caption tinta500.
            for (v, x) in [(zona.lowerBound, xZ0), (zona.upperBound, xZ1)] {
                let etiqueta = Text(String(format: "%.1f", v))
                    .font(LiquidType.etiquetaEje)
                    .foregroundColor(LiquidColor.tinta500)
                    .monospacedDigit()
                ctx.draw(ctx.resolve(etiqueta), at: CGPoint(x: x, y: h), anchor: .bottom)
            }
        }
        .frame(maxWidth: .infinity, minHeight: MatrizTokens.alturaRiel, idealHeight: MatrizTokens.alturaRiel)
        .accessibilityHidden(true)
        .modifier(MatrizEntrada())
    }

    // MARK: Geometría de la campana (la del prototipo aprobado, escalada a la celda)

    /// Razón → x lineal en [inset, w-inset] sobre el dominio `colinaLo…colinaHi` (clampeada).
    static func xDe(_ v: Double, width w: CGFloat, inset: CGFloat) -> CGFloat {
        let usable = max(w - inset * 2, 1)
        guard v.isFinite else { return inset }   // no finito: al pie, sin NaN en el path
        let frac = CGFloat(min(max((v - MatrizTokens.colinaLo) / (MatrizTokens.colinaHi - MatrizTokens.colinaLo), 0), 1))
        return inset + frac * usable
    }

    /// x → razón (inversa de `xDe`, sin clamp: la campana se evalúa en todo el ancho).
    private static func vDe(_ x: CGFloat, width w: CGFloat, inset: CGFloat) -> Double {
        let usable = max(w - inset * 2, 1)
        return MatrizTokens.colinaLo + Double((x - inset) / usable) * (MatrizTokens.colinaHi - MatrizTokens.colinaLo)
    }

    /// La altura relativa de la campana en la razón `v`: exp(−((v − centro)/σ)²), 1 en el centro.
    static func campana(_ v: Double) -> Double {
        let z = (v - MatrizTokens.colinaCentro) / MatrizTokens.colinaSigma
        return exp(-z * z)
    }

    /// y sobre la campana en una x dada: pie en `baseY`, cima en `colinaPadAlto`.
    static func yEnX(_ x: CGFloat, width w: CGFloat, height h: CGFloat, inset: CGFloat) -> CGFloat {
        let baseY = h - MatrizTokens.colinaPadBajo
        let topY = MatrizTokens.colinaPadAlto
        return baseY - CGFloat(campana(vDe(x, width: w, inset: inset))) * max(baseY - topY, 1)
    }

    static func lineaCampana(width w: CGFloat, height h: CGFloat, inset: CGFloat) -> Path {
        var p = Path()
        let pasos = 40
        for k in 0...pasos {
            let x = inset + CGFloat(k) / CGFloat(pasos) * max(w - inset * 2, 1)
            let pt = CGPoint(x: x, y: yEnX(x, width: w, height: h, inset: inset))
            if k == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        return p
    }

    static func areaCampana(width w: CGFloat, height h: CGFloat, inset: CGFloat,
                            baseY: CGFloat) -> Path {
        var p = lineaCampana(width: w, height: h, inset: inset)
        p.addLine(to: CGPoint(x: w - inset, y: baseY))
        p.addLine(to: CGPoint(x: inset, y: baseY))
        p.closeSubpath()
        return p
    }
}

// MARK: - MatrizBarrasMini (ESFUERZO / PASOS)

/// N barras finas redondeadas; HOY saturado; SIN juicio (nunca aro).
public struct MatrizBarrasMini: View {
    private let chartID: String
    private let valores: [Double?]
    private let hue: Color
    /// Línea punteada de referencia (el promedio de la ventana en Pasos, FER-125); nil = nada.
    private let promedio: Double?
    /// Índice leído por el scrub (FER-62): esa barra va a alfa pleno + cursor.
    private let resaltado: Int?

    public init(chartID: String, valores: [Double?], hue: Color, promedio: Double? = nil,
                resaltado: Int? = nil) {
        self.chartID = chartID
        self.valores = valores
        self.hue = hue
        self.promedio = promedio
        self.resaltado = resaltado
    }

    public var body: some View {
        Canvas { ctx, size in
            let n = max(valores.count, 1)
            if !MatrizChartDraw.tieneDatos(valores) {
                MatrizChartDraw.rejillaFantasma(ctx, size: size, chartID: chartID)
                return
            }
            let maxV = valores.compactMap { $0 }.filter(\.isFinite).max() ?? 1
            let gap = MatrizTokens.barraGap
            let inset = MatrizTokens.chartInset
            let usable: CGFloat = size.width - inset * 2 - gap * CGFloat(n - 1)
            let barW: CGFloat = max(usable / CGFloat(n), 1)
            let last = valores.count - 1
            // La referencia punteada (promedio) va DEBAJO de las barras, en tinta tenue: es una
            // guía, no un dato. Misma escala que las barras (0…máximo).
            if let promedio, maxV > 0 {
                let y = size.height - max(CGFloat(promedio / maxV) * (size.height - MatrizTokens.chartPadV), 1)
                var linea = Path()
                linea.move(to: CGPoint(x: inset, y: y))
                linea.addLine(to: CGPoint(x: size.width - inset, y: y))
                ctx.stroke(linea, with: .color(LiquidColor.tinta500.opacity(MatrizTokens.barrasPromedioAlfa)),
                           style: StrokeStyle(lineWidth: 1, dash: MatrizTokens.barrasPromedioDash))
            }
            for (i, val) in valores.enumerated() {
                let x = inset + CGFloat(i) * (barW + gap)
                let cx = x + barW / 2
                let seleccionada = resaltado == i
                guard let v = val, v.isFinite else {
                    // Día leído sin lectura: cursor fantasma en su cajón (paridad columnas).
                    if seleccionada {
                        MatrizChartDraw.cursorScrub(ctx, x: cx, height: size.height, hue: hue, fantasma: true)
                    }
                    continue
                }
                let esHoy = i == last
                // El cero es un DATO, no un hueco: piso visible (`barrasPiso`) — y una serie
                // toda en cero pinta sus pisos en vez de un lienzo vacío (FER-128, Grok).
                let fraccion = maxV > 0 ? CGFloat(v / maxV) : 0
                let h = max(fraccion * (size.height - MatrizTokens.chartPadV), MatrizTokens.barrasPiso)
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

/// La escalerita de estrés como CUADRÍCULA (FER-125, el prototipo aprobado): 7 días × 3 celdas
/// apiladas; cada día enciende tantas celdas como su nivel (bajo 1 · medio 2 · alto 3), del
/// pie hacia arriba, y las apagadas quedan como rejilla tenue. El nivel se lee por la ALTURA
/// de la pila; el color de la pila es la rampa de calor de FER-60 (`colorNivel`: bajo tinta,
/// medio ocre, alto siena — nunca el hue de alerta ni el verde del veredicto). HOY va pleno,
/// la historia serena; el día leído por el scrub se enciende como HOY + cursor. Sin lectura:
/// columna apagada (y cursor fantasma si se lee). Sin ningún dato: rejilla fantasma.
public struct MatrizEscalerita: View {
    private let chartID: String
    private let niveles: [Int?]
    private let hue: Color
    /// Índice leído por el scrub (FER-62): esa columna va a alfa pleno + cursor.
    private let resaltado: Int?

    public init(chartID: String, niveles: [Int?], hue: Color, resaltado: Int? = nil) {
        self.chartID = chartID
        self.niveles = niveles
        self.hue = hue
        self.resaltado = resaltado
    }

    public var body: some View {
        Canvas { ctx, size in
            let count = max(niveles.count, 1)
            if niveles.allSatisfy({ $0 == nil }) {
                MatrizChartDraw.rejillaFantasma(ctx, size: size, chartID: chartID)
                return
            }
            let inset = MatrizTokens.chartInset
            let paso = (size.width - inset * 2) / CGFloat(count)
            let filas = MatrizTokens.escaleraFilas
            let altoFila = size.height / CGFloat(filas)
            let gap = MatrizTokens.escaleraCeldaGap
            let last = niveles.count - 1
            for (i, niv) in niveles.enumerated() {
                let x0 = inset + CGFloat(i) * paso + gap / 2
                let cx = inset + CGFloat(i) * paso + paso / 2
                let seleccionada = resaltado == i
                let esHoy = i == last
                let nivel = niv.map { min(max($0, 0), filas - 1) }
                for k in 0..<filas {
                    // Fila k = 0 abajo. Encendida si el día tiene nivel y k ≤ nivel.
                    let y0 = size.height - CGFloat(k + 1) * altoFila + gap / 2
                    let celda = CGRect(x: x0, y: y0, width: max(paso - gap, 1), height: max(altoFila - gap, 1))
                    let camino = Path(roundedRect: celda, cornerRadius: MatrizTokens.escaleraCeldaRadio)
                    if let nivel, k <= nivel {
                        ctx.fill(camino, with: .color(Self.colorNivel(nivel).opacity(
                            (esHoy || seleccionada) ? MatrizChartDraw.hoyAlfa : MatrizTokens.heatHistAlfa)))
                    } else {
                        ctx.fill(camino, with: .color(LiquidColor.tinta900.opacity(MatrizTokens.escaleraApagadaAlfa)))
                    }
                }
                if seleccionada {
                    MatrizChartDraw.cursorScrub(ctx, x: cx, height: size.height, hue: hue, fantasma: nivel == nil)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: MatrizTokens.alturaEscalera, idealHeight: MatrizTokens.alturaEscalera)
        .accessibilityHidden(true)
        .modifier(MatrizEntrada())
    }

    /// FER-60 · Color de calor por nivel de estrés: bajo = tinta neutra (sin calor),
    /// medio = ocre, alto = siena. Es una rampa de CALOR, no de juicio: nunca el verde del
    /// veredicto ni el ámbar/rojo de alerta del guardián (que sí votan). `static` para
    /// testear la distinción como contrato (MatrizContrasteTests). Clampa fuera de 0…2.
    public static func colorNivel(_ nivel: Int) -> Color {
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
