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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(radio: CGFloat, hue: Color, semillaID: String = "", huePar: Color? = nil) {
        self.radio = radio
        self.hue = hue
        self.huePar = huePar
        self.semillaID = semillaID
    }

    public var body: some View {
        let lado = radio * 2.5
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { tl in
            let t = reduceMotion ? 0 : tl.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                Self.dibujar(ctx, centro: CGPoint(x: size.width / 2, y: size.height / 2),
                             radio: radio, hue: hue, huePar: huePar, t: t, faseID: semillaID)
            }
        }
        .frame(width: lado, height: lado)
        .accessibilityHidden(true)
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
        for i in 0..<cuenta {
            let dir = EcosistemaSimulacion.direccion(i, de: cuenta)
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
