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
    private let radio: CGFloat
    private let hue: Color
    private let huePar: Color?
    private let semillaID: String
    private let fps: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// `fps`: los cuerpos chicos (sellos) viven bien a 12; los grandes a 24
    /// (hallazgo Grok #2 — N relojes en la única cara).
    public init(radio: CGFloat, hue: Color, semillaID: String = "",
                huePar: Color? = nil, fps: Double = 24) {
        self.radio = radio
        self.hue = hue
        self.huePar = huePar
        self.semillaID = semillaID
        self.fps = fps
    }

    public var body: some View {
        let lado = radio * 2.5
        // La rotación es de 0.12 rad/s: más cuadros no se ven, solo cuestan
        // (hallazgos DeepSeek #2 / Grok #2 — perf de N orbes).
        TimelineView(.animation(minimumInterval: 1.0 / fps, paused: reduceMotion)) { tl in
            let t = reduceMotion ? 0 : tl.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                Self.dibujar(ctx, centro: CGPoint(x: size.width / 2, y: size.height / 2),
                             radio: radio, hue: hue, huePar: huePar, t: t, faseID: semillaID)
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
                               t: Double = 0, faseID: String = "") {
        // Densidad del héroe (~0.4 pt²/partícula) — más rala que un relleno: se ven
        // los puntos individuales, como arriba. Tope por rendimiento.
        let cuenta = min(240, max(36, Int(0.4 * radio * radio)))
        // Fase estable por identidad: cada orbe mira distinto y gira desde su ángulo.
        let fase = Double(MatrizDither.semilla(chartID: faseID, index: 0) % 628) / 100.0
        let rot = fase + t * 0.12
        for (i, dir) in direcciones(cuenta).enumerated() {
            let p = EcosistemaSimulacion.particula(
                dir: dir, indice: i, centro: centro, radio: radio,
                rotacion: rot, jitterAmp: radio > 10 ? 0.7 : 0, t: t, alfaK: 1.4)
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
    }
    .padding(32)
    .background(LiquidColor.fondoGradient)
}
