import SwiftUI

// MARK: - FER-51 · El orbe vivo (componente ÚNICO reutilizable)
//
// TODOS los cuerpos celestes del rediseño de Hoy son ESTE componente con otro radio
// (decisión del dueño en vivo, 2026-08-06): las lunas del Cosmos abierto, los planetas
// del reunido y los sellos de la Matriz. La materia es la receta EXACTA del héroe
// (`EcosistemaSimulacion`: esfera de Fibonacci proyectada con tamaño/alfa por
// profundidad) y está VIVA — rota lento y respira con el jitter del ecosistema.
// Bajo Reduce Motion queda quieta. `huePar` alterna por índice (binaria del guardián).

public struct OrbeVivo: View {
    /// Silueta del cuerpo: esfera plena (default), luna creciente (Sueño) o corazón
    /// (FC en reposo) — la MISMA materia, tallada en 2D. Luna y corazón son QUIETOS:
    /// motas fijas, contorno denso (decisión del dueño, FER-55).
    public enum Forma: Sendable, Equatable { case esfera, luna, corazon }

    private let radio: CGFloat
    private let hue: Color
    private let huePar: Color?
    private let semillaID: String
    private let fps: Double
    private let forma: Forma
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// `fps`: los cuerpos chicos (sellos) viven bien a 12; los grandes a 24
    /// (hallazgo Grok #2 — N relojes en la única cara).
    public init(radio: CGFloat, hue: Color, semillaID: String = "",
                huePar: Color? = nil, fps: Double = 24, forma: Forma = .esfera) {
        self.radio = radio
        self.hue = hue
        self.huePar = huePar
        self.semillaID = semillaID
        self.fps = fps
        self.forma = forma
    }

    public var body: some View {
        let lado = radio * 2.5
        Group {
            if forma != .esfera {
                // Luna y corazón son QUIETOS (revisión del dueño, FER-55): motas fijas
                // trazando la silueta — sin reloj, cero costo por frame.
                Canvas { ctx, size in
                    Self.dibujar(ctx, centro: CGPoint(x: size.width / 2, y: size.height / 2),
                                 radio: radio, hue: hue, huePar: huePar, t: 0,
                                 faseID: semillaID, forma: forma)
                }
            } else {
                // La rotación es de 0.12 rad/s: más cuadros no se ven, solo cuestan
                // (hallazgos DeepSeek #2 / Grok #2 — perf de N orbes).
                TimelineView(.animation(minimumInterval: 1.0 / fps, paused: reduceMotion)) { tl in
                    let t = reduceMotion ? 0 : tl.date.timeIntervalSinceReferenceDate
                    Canvas { ctx, size in
                        Self.dibujar(ctx, centro: CGPoint(x: size.width / 2, y: size.height / 2),
                                     radio: radio, hue: hue, huePar: huePar, t: t,
                                     faseID: semillaID, forma: forma)
                    }
                }
            }
        }
        .frame(width: lado, height: lado)
        .accessibilityHidden(true)
    }

    /// Direcciones fibonacci por conteo — geometría PURA (no depende de `t`): se
    /// calcula una vez por tamaño y se comparte entre todos los orbes y frames
    /// (hallazgo DeepSeek #1: la trigonometría por frame era basura pura). El Canvas
    /// puede dibujar fuera de MainActor → candado clásico, no aislamiento.
    private static let cacheCandado = NSLock()
    nonisolated(unsafe) private static var dirsCache: [Int: [SIMD3<Double>]] = [:]

    private static func direcciones(_ n: Int) -> [SIMD3<Double>] {
        cacheCandado.lock()
        defer { cacheCandado.unlock() }
        if let d = dirsCache[n] { return d }
        let d = EcosistemaSimulacion.fibonacci(n)
        dirsCache[n] = d
        return d
    }

    /// El trazo compartido — quien ya tiene su propio Canvas + reloj (el reunido) lo
    /// llama directo con su `t`. Una sola definición de materia para todo el rediseño.
    public static func dibujar(_ ctx: GraphicsContext, centro: CGPoint, radio: CGFloat,
                               hue: Color, huePar: Color? = nil,
                               t: Double = 0, faseID: String = "",
                               forma: Forma = .esfera) {
        // El corazón NO se talla de la esfera (a tamaño de sello quedan pocas motas,
        // grandes y dispersas en 3D → amasijo ilegible, revisión del dueño FER-56). Se
        // SIEMBRA en 2D sobre la forma del corazón: puntos chicos y densos, contorno
        // marcado — misma materia visual, silueta que sí se lee. Quieto.
        if forma == .corazon {
            dibujarCorazon(ctx, centro: centro, radio: radio, hue: hue, faseID: faseID)
            return
        }
        // Densidad del héroe (~0.4 pt²/partícula) — más rala que un relleno: se ven
        // los puntos individuales, como arriba. Tope por rendimiento. La luna pierde
        // ~30 % de su silueta a la mordida → se compensa la cuenta para no ralear.
        let base = min(240, max(36, Int(0.4 * radio * radio)))
        // La luna pierde parte de la esfera a la mordida → compensar la cuenta.
        let cuenta: Int = forma == .luna ? min(240, Int(Double(base) * 1.35)) : base
        // Mordida 2D del creciente (mismas proporciones que el mock aprobado): centro
        // desplazado a la derecha-arriba, radio 0.86·R. Se descartan las motas cuyo
        // punto PROYECTADO cae dentro (front y back juntas → lee como luna).
        let mordida = centro.applying(.init(translationX: radio * 0.42, y: -radio * 0.16))
        let mordidaR = radio * 0.86
        // Fase estable por identidad: cada orbe mira distinto y gira desde su ángulo.
        let fase = Double(MatrizDither.semilla(chartID: faseID, index: 0) % 628) / 100.0
        // La luna no rota ni tiembla: motas fijas (dueño, FER-55).
        let quieta = forma == .luna
        let rot = quieta ? fase : fase + t * 0.12
        for (i, dir) in direcciones(cuenta).enumerated() {
            let p = EcosistemaSimulacion.particula(
                dir: dir, indice: i, centro: centro, radio: radio,
                rotacion: rot, jitterAmp: (quieta || radio <= 10) ? 0 : 0.7,
                t: quieta ? 0 : t, alfaK: 1.4)
            if forma == .luna {
                let dx = p.pos.x - mordida.x, dy = p.pos.y - mordida.y
                if dx * dx + dy * dy < mordidaR * mordidaR { continue }
            }
            let pr = p.tamano * (0.55 + radio / 60)
            let color = (huePar != nil && i % 2 == 1) ? huePar! : hue
            ctx.fill(Path(ellipseIn: CGRect(x: p.pos.x - pr, y: p.pos.y - pr,
                                            width: pr * 2, height: pr * 2)),
                     with: .color(color.opacity(min(1, p.alfa))))
        }
    }

    /// El corazón sembrado en 2D (FER-56): rejection-sampling DETERMINISTA sobre la
    /// curva implícita del corazón `(x²+y²−1)³ − x²·y³ ≤ 0` (misma que el mock). Motas
    /// chicas y densas; las del CONTORNO (cercanas al borde) más grandes, plenas y
    /// oscuras trazan la silueta; el interior más tenue. Quieto (sin `t`): la semilla
    /// fija la nube, cero shimmer y cero costo por frame.
    private static func dibujarCorazon(_ ctx: GraphicsContext, centro: CGPoint,
                                       radio: CGFloat, hue: Color, faseID: String) {
        let esc = Double(radio) * 0.062     // ±16 de la paramétrica → mismo Ø que la luna
        let yCentro = -2.3                   // centra el peso vertical (cúspide abajo)
        // Paramétrica clásica del corazón: x=16sin³t, y=13cos t−5cos2t−2cos3t−cos4t.
        // Lóbulos arriba, cúspide abajo (en pantalla, y invertida).
        func punto(_ tt: Double) -> CGPoint {
            let x = 16 * pow(sin(tt), 3)
            let y = 13 * cos(tt) - 5 * cos(2 * tt) - 2 * cos(3 * tt) - cos(4 * tt)
            return CGPoint(x: centro.x + CGFloat(x) * esc,
                           y: centro.y - CGFloat(y - yCentro) * esc)
        }
        // El contorno como POLÍGONO (para el test dentro/fuera del relleno uniforme).
        let nContorno = min(72, max(36, Int(radio * 3.6)))
        var poligono: [CGPoint] = []
        poligono.reserveCapacity(nContorno)
        for k in 0..<nContorno {
            poligono.append(punto(Double(k) / Double(nContorno) * 2 * .pi))
        }
        // 1 · RELLENO UNIFORME primero (debajo): rejection-sampling dentro del polígono,
        // DENSO como la luna. PRNG determinista → misma nube cada frame.
        var estado = UInt64(MatrizDither.semilla(chartID: faseID, index: 7)) | 1
        func rnd() -> Double {
            estado ^= estado << 13; estado ^= estado >> 7; estado ^= estado << 17
            return Double(estado % 100_000) / 100_000
        }
        func dentro(_ px: CGFloat, _ py: CGFloat) -> Bool {
            var d = false, j = poligono.count - 1
            for i in 0..<poligono.count {
                let a = poligono[i], b = poligono[j]
                if (a.y > py) != (b.y > py),
                   px < (b.x - a.x) * (py - a.y) / (b.y - a.y) + a.x { d.toggle() }
                j = i
            }
            return d
        }
        let minX = poligono.map(\.x).min() ?? centro.x
        let maxX = poligono.map(\.x).max() ?? centro.x
        let minY = poligono.map(\.y).min() ?? centro.y
        let maxY = poligono.map(\.y).max() ?? centro.y
        // Densidad calcada de la luna (~0.4 pt²·1.35 por partícula): misma sensación.
        let nRelleno = min(180, max(48, Int(0.55 * radio * radio)))
        let prIn = 0.62 * (0.55 + radio / 44)
        var puestas = 0, intentos = 0
        while puestas < nRelleno && intentos < nRelleno * 40 {
            intentos += 1
            let px = minX + CGFloat(rnd()) * (maxX - minX)
            let py = minY + CGFloat(rnd()) * (maxY - minY)
            guard dentro(px, py) else { continue }
            let alfa = 0.5 + rnd() * 0.4          // como la luna: motas plenas, no fantasmas
            ctx.fill(Path(ellipseIn: CGRect(x: px - prIn, y: py - prIn,
                                            width: prIn * 2, height: prIn * 2)),
                     with: .color(hue.opacity(alfa)))
            puestas += 1
        }
        // 2 · CONTORNO encima — motas parejas sobre la curva = silueta nítida y plena.
        let prBorde = 0.85 * (0.55 + radio / 44)
        for c in poligono {
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - prBorde, y: c.y - prBorde,
                                            width: prBorde * 2, height: prBorde * 2)),
                     with: .color(hue))
        }
    }
}

#Preview("Orbe vivo · tamaños") {
    HStack(spacing: 24) {
        OrbeVivo(radio: 8, hue: LiquidColor.indigo, semillaID: "a")
        OrbeVivo(radio: 15, hue: LiquidColor.rosa, semillaID: "b")
        OrbeVivo(radio: 24, hue: LiquidColor.verdePrimario, semillaID: "c")
        OrbeVivo(radio: 12, hue: LiquidColor.doradoTemp, semillaID: "d",
                 huePar: LiquidColor.azul)
        OrbeVivo(radio: 15, hue: LiquidColor.indigo, semillaID: "luna", forma: .luna)
        OrbeVivo(radio: 15, hue: LiquidColor.rosa, semillaID: "cor", forma: .corazon)
    }
    .padding(32)
    .background(LiquidColor.fondoGradient)
}
