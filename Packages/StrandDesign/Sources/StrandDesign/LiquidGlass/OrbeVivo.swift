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
    /// Silueta del cuerpo: esfera plena (default) o luna creciente (FER-55, Sueño):
    /// la MISMA materia, con una mordida 2D que talla el creciente.
    public enum Forma: Sendable, Equatable { case esfera, luna }

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
            if forma == .luna {
                // La luna es QUIETA (revisión del dueño, FER-55): las motas fijas
                // trazando el creciente — sin reloj, cero costo por frame.
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
        let cuenta = forma == .luna ? min(240, Int(Double(base) * 1.35)) : base
        // Mordida 2D del creciente (mismas proporciones que el mock aprobado): centro
        // desplazado a la derecha-arriba, radio 0.86·R. Se descartan las motas cuyo
        // punto PROYECTADO cae dentro (front y back juntas → lee como luna).
        let mordida = centro.applying(.init(translationX: radio * 0.42, y: -radio * 0.16))
        let mordidaR = radio * 0.86
        // Fase estable por identidad: cada orbe mira distinto y gira desde su ángulo.
        let fase = Double(MatrizDither.semilla(chartID: faseID, index: 0) % 628) / 100.0
        // La luna no rota ni tiembla: motas fijas con el contorno (dueño, FER-55).
        let rot = forma == .luna ? fase : fase + t * 0.12
        for (i, dir) in direcciones(cuenta).enumerated() {
            let p = EcosistemaSimulacion.particula(
                dir: dir, indice: i, centro: centro, radio: radio,
                rotacion: rot, jitterAmp: (forma == .luna || radio <= 10) ? 0 : 0.7,
                t: forma == .luna ? 0 : t, alfaK: 1.4)
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
}

#Preview("Orbe vivo · tamaños") {
    HStack(spacing: 24) {
        OrbeVivo(radio: 8, hue: LiquidColor.indigo, semillaID: "a")
        OrbeVivo(radio: 15, hue: LiquidColor.rosa, semillaID: "b")
        OrbeVivo(radio: 24, hue: LiquidColor.verdePrimario, semillaID: "c")
        OrbeVivo(radio: 12, hue: LiquidColor.doradoTemp, semillaID: "d",
                 huePar: LiquidColor.azul)
        OrbeVivo(radio: 15, hue: LiquidColor.indigo, semillaID: "luna", forma: .luna)
    }
    .padding(32)
    .background(LiquidColor.fondoGradient)
}
