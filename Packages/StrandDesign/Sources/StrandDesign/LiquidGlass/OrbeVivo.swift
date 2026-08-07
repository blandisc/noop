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
        // Densidad del héroe (~0.4 pt²/partícula) — más rala que un relleno: se ven
        // los puntos individuales, como arriba. Tope por rendimiento. La luna pierde
        // ~30 % de su silueta a la mordida → se compensa la cuenta para no ralear.
        let base = min(240, max(36, Int(0.4 * radio * radio)))
        // Las siluetas talladas pierden parte de la esfera → compensar la cuenta.
        let cuenta: Int = switch forma {
        case .esfera: base
        case .luna: min(240, Int(Double(base) * 1.35))
        case .corazon: min(280, Int(Double(base) * 2.2))
        }
        // Mordida 2D del creciente (mismas proporciones que el mock aprobado): centro
        // desplazado a la derecha-arriba, radio 0.86·R. Se descartan las motas cuyo
        // punto PROYECTADO cae dentro (front y back juntas → lee como luna).
        let mordida = centro.applying(.init(translationX: radio * 0.42, y: -radio * 0.16))
        let mordidaR = radio * 0.86
        // Fase estable por identidad: cada orbe mira distinto y gira desde su ángulo.
        let fase = Double(MatrizDither.semilla(chartID: faseID, index: 0) % 628) / 100.0
        // Luna y corazón no rotan ni tiemblan: motas fijas (dueño, FER-55).
        let quieta = forma != .esfera
        let rot = quieta ? fase : fase + t * 0.12
        // Corazón implícito: (x²+y²−1)³ − x²·y³ ≤ 0 (x,y normalizados). El CONTORNO
        // se detecta por cercanía al borde y se marca: motas más grandes y plenas
        // trazan la silueta; el interior queda más tenue (receta aprobada en mock).
        let escalaCorazon = Double(radio) * 0.82
        func corazonF(_ px: CGFloat, _ py: CGFloat) -> Double {
            let x = Double(px - centro.x) / escalaCorazon
            let y = Double(centro.y - py) / escalaCorazon + 0.12
            let a = x * x + y * y - 1
            return a * a * a - x * x * y * y * y
        }
        for (i, dir) in direcciones(cuenta).enumerated() {
            let p = EcosistemaSimulacion.particula(
                dir: dir, indice: i, centro: centro, radio: radio,
                rotacion: rot, jitterAmp: (quieta || radio <= 10) ? 0 : 0.7,
                t: quieta ? 0 : t, alfaK: 1.4)
            var esBorde = false
            switch forma {
            case .esfera: break
            case .luna:
                let dx = p.pos.x - mordida.x, dy = p.pos.y - mordida.y
                if dx * dx + dy * dy < mordidaR * mordidaR { continue }
            case .corazon:
                let f = corazonF(p.pos.x, p.pos.y)
                if f > 0 { continue }               // fuera del corazón
                esBorde = f > -0.09                  // cerca del borde → contorno
            }
            let pr = p.tamano * (0.55 + radio / 60) * (esBorde ? 1.45 : 1)
            let color = (huePar != nil && i % 2 == 1) ? huePar! : hue
            let alfa = esBorde ? 1.0 : min(1, p.alfa) * (forma == .corazon ? 0.55 : 1)
            ctx.fill(Path(ellipseIn: CGRect(x: p.pos.x - pr, y: p.pos.y - pr,
                                            width: pr * 2, height: pr * 2)),
                     with: .color(color.opacity(alfa)))
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
