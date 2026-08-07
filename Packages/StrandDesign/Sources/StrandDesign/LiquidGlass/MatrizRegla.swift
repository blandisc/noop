import SwiftUI

// MARK: - FER-55 · La regla al margen (FC en reposo)
//
// La gráfica final de FC aprobada por el dueño (prototipo «regla + relleno +
// coreografía»): la curva Liquid con un relleno que nace en la curva y muere a nada
// antes del piso; a la derecha una REGLA — capilar de dominio + tramo sólido de «tu
// rango» (±1σ del motor) — con la lectura de HOY viviendo en ambos lados (punto con
// halo de papel). El scrub desliza los puntos gemelos y revela un hilo-susurro; en
// reposo la celda calla. Entrada en tres tiempos: la tinta ESCRIBE la curva, el
// relleno respira detrás, los puntos se asientan con muelle. Reduce Motion: todo
// aparece asentado, quieto.
//
// Reutilizable a propósito: «capilar + tramo + punto» sirve igual para VFC o
// respiración — solo cambian puntos/banda/hue.
public struct MatrizRegla: View {
    private let chartID: String
    private let puntos: [Double?]
    /// Rango típico del motor (±1σ). nil → la regla muestra solo el capilar (sin
    /// tramo): no se dibuja un rango que el motor no tiene.
    private let banda: ClosedRange<Double>?
    private let dominio: ClosedRange<Double>
    private let hue: Color
    private let alertaHoy: MedidorLunar.Alerta
    /// Índice leído por el scrub; nil = reposo (HOY).
    private let resaltado: Int?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Coreografía de entrada (0→1 escribe la curva; el resto se cuelga de fases).
    @State private var escrito: CGFloat = 0
    @State private var rellenoVivo = false
    @State private var asentado = false

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
        GeometryReader { geo in
            let size = geo.size
            if puntos.isEmpty || !puntos.contains(where: { $0 != nil }) {
                Canvas { ctx, size in
                    MatrizChartDraw.rejillaFantasma(ctx, size: size, chartID: chartID)
                }
            } else {
                contenido(size: size)
            }
        }
        .frame(maxWidth: .infinity, minHeight: MatrizTokens.alturaLinea,
               idealHeight: MatrizTokens.alturaLinea)
        .accessibilityHidden(true)
        .onAppear(perform: entrar)
    }

    // MARK: Coreografía

    private func entrar() {
        guard !reduceMotion else {
            escrito = 1; rellenoVivo = true; asentado = true
            return
        }
        withAnimation(.easeInOut(duration: 0.9).delay(0.1)) { escrito = 1 }
        withAnimation(.easeOut(duration: 0.6).delay(0.75)) { rellenoVivo = true }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7).delay(1.0)) {
            asentado = true
        }
    }

    // MARK: Piezas

    @ViewBuilder
    private func contenido(size: CGSize) -> some View {
        let pts = puntosXY(size: size)
        let hoyIdx = puntos.lastIndex(where: { $0 != nil })
        let leidoIdx = resaltado.flatMap { puntos.indices.contains($0) ? $0 : nil }
        // La lectura activa: la del scrub si el día leído tiene dato; si no, HOY.
        let activoIdx = leidoIdx.flatMap { puntos[$0] != nil ? $0 : nil } ?? hoyIdx
        // Hueco leído: el ÚNICO marcador es el hilo fantasma en esa x — las gotas se
        // esconden (dejarlas en HOY contradecía al texto; panel C, Grok #1).
        let leyendoHueco = leidoIdx.map { puntos[$0] == nil } == true
        ZStack(alignment: .topLeading) {
            // 1 · Relleno: nace EN la curva y muere a nada antes del piso.
            AreaCurva(puntos: pts, piso: size.height)
                .fill(LinearGradient(
                    colors: [hue.opacity(MatrizTokens.reglaRellenoAlfa), hue.opacity(0)],
                    startPoint: .top, endPoint: .bottom))
                .opacity(rellenoVivo ? 1 : 0)
            // 2 · La curva, escrita por la tinta. El trim escribe SOLO el tramo más
            // largo (trim sobre un path multipieza teletransporta la tinta entre islas
            // — panel C, Grok #3); las islas restantes aparecen con el relleno.
            TrazoCurva(puntos: pts, soloPrincipal: true)
                .trim(from: 0, to: escrito)
                .stroke(hue.opacity(MatrizTokens.lineaAlfa),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            TrazoCurva(puntos: pts, soloPrincipal: false)
                .stroke(hue.opacity(MatrizTokens.lineaAlfa),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .opacity(rellenoVivo ? 1 : 0)
            // 3 · La regla: capilar de dominio + tramo de tu rango.
            regla(size: size)
                .opacity(asentado ? 1 : 0)
            // 4 · Hilo-susurro + puntos gemelos (solo con dato activo y sin hueco).
            if !leyendoHueco, let i = activoIdx, let v = puntos[i] {
                let p = punto(en: i, valor: v, size: size)
                // ¿El dedo lee un día CON dato? (nil-dato se maneja aparte abajo.)
                let leyendo = leidoIdx.map { puntos[$0] != nil } == true
                if leyendo {
                    HiloLectura(desde: p, hastaX: reglaX(size: size) - 8)
                        .stroke(hue.opacity(0.25),
                                style: StrokeStyle(lineWidth: 1, dash: [1.5, 3.5]))
                        .transition(.opacity)
                }
                gota(radioHalo: 5.4, radioPunto: 3.4)
                    .position(p)
                // El aro de alerta §8 (gramática) — SOLO sobre HOY, jamás sobre una
                // lectura histórica del scrub (panel C, DeepSeek ALTA #1).
                if i == hoyIdx, alertaHoy != .ninguna {
                    aros(alerta: alertaHoy)
                        // Mismo tercer tiempo que las gotas (panel C, Grok #2): los
                        // anillos jamás flotan solos antes del asentado.
                        .opacity(asentado ? 1 : 0)
                        .scaleEffect(asentado ? 1 : 0.4)
                        .position(p)
                }
                gota(radioHalo: 5.6, radioPunto: 3.6)
                    .position(x: reglaX(size: size), y: p.y)
            }
            // Scrub sobre un día SIN dato: hilo fantasma vertical en ESE día (paridad
            // con las columnas de Sueño) — el texto dice «sin lectura» y la gráfica
            // señala el mismo día, no HOY (panel C, DeepSeek MEDIA #2).
            if let i = leidoIdx, puntos[i] == nil {
                let x = xEn(i, size: size)
                Path { p in
                    p.move(to: CGPoint(x: x, y: 0))
                    p.addLine(to: CGPoint(x: x, y: size.height))
                }
                .stroke(hue.opacity(0.35),
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [2, 3]))
            }
        }
        // El deslizado del scrub: los gemelos viajan, no se teletransportan.
        .animation(reduceMotion ? nil : .snappy(duration: 0.16), value: resaltado)
    }

    /// El aro de alerta §8: atención = un aro; alarma = dos (mismos tokens que el
    /// resto de la familia — aroGap/aroGap2/aroAlfa).
    @ViewBuilder
    private func aros(alerta: MedidorLunar.Alerta) -> some View {
        let base: CGFloat = 3.4
        switch alerta {
        case .ninguna:
            EmptyView()
        case .atencion:
            Circle().strokeBorder(LiquidColor.atencion.opacity(MatrizTokens.aroAlfa), lineWidth: 1)
                .frame(width: (base + MatrizTokens.aroGap) * 2,
                       height: (base + MatrizTokens.aroGap) * 2)
        case .alarma:
            ZStack {
                Circle().strokeBorder(LiquidColor.negativo.opacity(MatrizTokens.aroAlfa), lineWidth: 1)
                    .frame(width: (base + MatrizTokens.aroGap) * 2,
                           height: (base + MatrizTokens.aroGap) * 2)
                Circle().strokeBorder(LiquidColor.negativo.opacity(MatrizTokens.aroAlfa), lineWidth: 1)
                    .frame(width: (base + MatrizTokens.aroGap2) * 2,
                           height: (base + MatrizTokens.aroGap2) * 2)
            }
        }
    }

    /// Punto + halo de papel (la lectura se separa de la curva con elegancia).
    private func gota(radioHalo: CGFloat, radioPunto: CGFloat) -> some View {
        ZStack {
            Circle().fill(LiquidColor.papelMatriz)
                .frame(width: radioHalo * 2, height: radioHalo * 2)
            Circle().fill(hue)
                .frame(width: radioPunto * 2, height: radioPunto * 2)
        }
        .opacity(asentado ? 1 : 0)
        .scaleEffect(asentado ? 1 : 0.4)
    }

    @ViewBuilder
    private func regla(size: CGSize) -> some View {
        let x = reglaX(size: size)
        // Capilar: todo el dominio, finísimo.
        Path { p in
            p.move(to: CGPoint(x: x, y: MatrizTokens.chartPadV + 2))
            p.addLine(to: CGPoint(x: x, y: size.height - MatrizTokens.chartPadV - 2))
        }
        .stroke(hue.opacity(MatrizTokens.reglaCapilarAlfa),
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        if let banda {
            // El tramo de TU RANGO — mismo ±1σ del corte del veredicto.
            let yHi = MatrizChartDraw.yTop(banda.upperBound, domain: dominio, height: size.height)
            let yLo = MatrizChartDraw.yTop(banda.lowerBound, domain: dominio, height: size.height)
            Path { p in
                p.move(to: CGPoint(x: x, y: yHi))
                p.addLine(to: CGPoint(x: x, y: yLo))
            }
            .stroke(hue.opacity(MatrizTokens.reglaTramoAlfa),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round))
        }
    }

    // MARK: Geometría (compartida con el gesto vía los mismos tokens)

    /// x de la regla: pegada al borde derecho con su propio aire.
    private func reglaX(size: CGSize) -> CGFloat {
        size.width - MatrizTokens.reglaAire
    }

    /// x del índice `i` — LA fórmula única (curva, gemelos, hilo fantasma y el gesto
    /// deben coincidir; testeable como estática).
    static func xIndice(_ i: Int, count: Int, width: CGFloat) -> CGFloat {
        let n = max(count - 1, 1)
        let usable = width - MatrizTokens.chartInset - MatrizTokens.reglaZona
        return MatrizTokens.chartInset + CGFloat(i) / CGFloat(n) * usable
    }

    private func xEn(_ i: Int, size: CGSize) -> CGFloat {
        Self.xIndice(i, count: puntos.count, width: size.width)
    }

    /// La curva reserva la zona de la regla a la derecha.
    private func puntosXY(size: CGSize) -> [CGPoint?] {
        puntos.enumerated().map { i, v in
            guard let v else { return nil }
            return CGPoint(x: xEn(i, size: size),
                           y: MatrizChartDraw.yTop(v, domain: dominio, height: size.height))
        }
    }

    private func punto(en i: Int, valor: Double, size: CGSize) -> CGPoint {
        CGPoint(x: xEn(i, size: size),
                y: MatrizChartDraw.yTop(valor, domain: dominio, height: size.height))
    }
}

// MARK: Shapes

/// La curva Catmull-Rom como Shape. `soloPrincipal: true` = el tramo contiguo MÁS
/// LARGO (el que la tinta escribe con `.trim`); `false` = las demás islas (aparecen
/// con el relleno, sin escritura — panel C, Grok #3).
private struct TrazoCurva: Shape {
    let puntos: [CGPoint?]
    let soloPrincipal: Bool
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let tramos = MatrizRegla.tramos(puntos).filter { $0.count > 1 }
        guard let principal = tramos.max(by: { $0.count < $1.count }) else { return path }
        for tramo in tramos {
            let esPrincipal = tramo.elementsEqual(principal)
            if esPrincipal == soloPrincipal {
                path.addPath(MatrizRegla.catmull(tramo))
            }
        }
        return path
    }
}

/// El área bajo la curva (relleno). Cierra cada tramo a su propio piso.
private struct AreaCurva: Shape {
    let puntos: [CGPoint?]
    let piso: CGFloat
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for tramo in MatrizRegla.tramos(puntos) where tramo.count > 1 {
            var area = MatrizRegla.catmull(tramo)
            area.addLine(to: CGPoint(x: tramo[tramo.count - 1].x, y: piso))
            area.addLine(to: CGPoint(x: tramo[0].x, y: piso))
            area.closeSubpath()
            path.addPath(area)
        }
        return path
    }
}

/// El hilo-susurro horizontal de la lectura al margen.
private struct HiloLectura: Shape {
    let desde: CGPoint
    let hastaX: CGFloat
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: desde)
        p.addLine(to: CGPoint(x: hastaX, y: desde.y))
        return p
    }
}

extension MatrizRegla {
    /// Tramos contiguos no-nil (mismo criterio que MatrizChartDraw.tramos).
    static func tramos(_ puntos: [CGPoint?]) -> [[CGPoint]] {
        var out: [[CGPoint]] = []
        var actual: [CGPoint] = []
        for p in puntos {
            if let p { actual.append(p) } else if !actual.isEmpty {
                out.append(actual); actual = []
            }
        }
        if !actual.isEmpty { out.append(actual) }
        return out
    }

    /// Catmull-Rom → Bézier (la MISMA receta de MatrizChartDraw.curva).
    static func catmull(_ pts: [CGPoint]) -> Path {
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
}

// MARK: - Previews

#Preview("Regla · con banda") {
    let pts: [Double?] = [52, 51, 53, 50, 49, 51, 52, 50, 48, 51,
                          49, 50, 52, 49, 47, 50, 48, 49, 51, 46]
    return VStack(spacing: 24) {
        MatrizRegla(chartID: "regla-demo", puntos: pts, banda: 47...53,
                    dominio: 43...56, hue: LiquidColor.rosa)
            .frame(height: MatrizTokens.alturaLinea)
        MatrizRegla(chartID: "regla-scrub", puntos: pts, banda: 47...53,
                    dominio: 43...56, hue: LiquidColor.rosa, resaltado: 7)
            .frame(height: MatrizTokens.alturaLinea)
        MatrizRegla(chartID: "regla-sinbanda", puntos: pts, banda: nil,
                    dominio: 43...56, hue: LiquidColor.rosa)
            .frame(height: MatrizTokens.alturaLinea)
    }
    .padding(24)
    .background(LiquidColor.papelMatriz)
}
