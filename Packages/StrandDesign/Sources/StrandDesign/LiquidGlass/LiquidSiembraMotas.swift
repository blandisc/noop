import SwiftUI

// MARK: - «La siembra» (FER-21 · C.4 «Materia continua»)
//
// La mitad-hoja de la ilusión en dos mitades: al abrir el acta, una constelación
// DECORATIVA de motas llega desde el borde superior, se asienta detrás del header y se
// DISUELVE del todo (variante A, decisión del dueño en el preview-gate): un saludo de
// materia, no un residente — la hoja termina en papel puro.
//
// Reglas que este componente respeta a propósito:
// · Texto es texto: las motas JAMÁS forman glifos aquí (el acta no tiene dato numérico).
// · Determinismo: misma `semilla` ⇒ misma constelación (sin random; hash como DatoDeMotas).
// · Reduce Motion: NADA — el estado final de la variante A es papel puro, y un cuadro
//   congelado a media siembra sería deshonesto.
// · Presupuesto: un solo Canvas, ≤ 90 motas, timeline muerta al disolverse (~3.2 s).
public struct LiquidSiembraMotas: View {
    private let tono: Color
    private let semilla: Int
    private let cuenta: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.liquidMotionDisabled) private var motionDisabled
    /// La convención del sistema (cazado por /qa): Reduce Motion REAL o el override
    /// de previews/tests — cualquiera de los dos apaga la siembra.
    private var still: Bool { reduceMotion || motionDisabled }
    /// El ancla del reloj: la siembra corre UNA vez por aparición de la hoja.
    @State private var inicio: Date = .distantPast

    public init(tono: Color, semilla: Int = 7, cuenta: Int = 70) {
        self.tono = tono
        self.semilla = semilla
        self.cuenta = min(90, max(1, cuenta))
    }

    /// Recetas de la siembra (variante A). Viven aquí: un solo consumidor.
    enum Receta {
        /// Escalón máximo de llegada por mota (s).
        static let escalon = 0.55
        /// Duración del viaje de una mota (s).
        static let viaje = 0.7
        /// Cuándo arranca la disolución (s desde `inicio`).
        static let disolucionDesde = 2.3
        /// Duración de la disolución (s).
        static let disolucionDur = 0.9
        /// Vida total (s) — después la timeline se pausa y el body queda vacío.
        static var vida: Double { disolucionDesde + disolucionDur + 0.1 }
        /// Alfa asentada de la mota más brillante (susurro: el texto real manda).
        static let alfaAsentada = 0.14
        /// Alfa durante el viaje (más visible: el movimiento ES el mensaje).
        static let alfaViaje = 0.30
    }

    /// Una mota de la constelación, en coordenadas NORMALIZADAS [0,1]² del lienzo.
    /// Pura y determinista — el contrato testeable de la siembra.
    struct Punto: Equatable {
        var destinoX: Double
        var destinoY: Double
        var origenX: Double
        var radio: Double      // pt
        var retraso: Double    // s, dentro de [0, escalon]
        var fase: Double       // rad, para la respiración
        var brillo: Double     // 0.5…1, multiplicador de alfa
    }

    /// La constelación completa para una semilla. Misma semilla ⇒ mismos puntos.
    static func puntos(semilla: Int, cuenta: Int) -> [Punto] {
        (0..<cuenta).map { k in
            let s = Double((k * 137 + semilla * 31) % 97) / 97
            let s2 = Double((k * 29 + semilla * 17) % 89) / 89
            let s3 = Double((k * 71 + semilla * 13) % 83) / 83
            return Punto(destinoX: 0.03 + s * 0.94,
                         // Sesgo hacia arriba (pow 1.4): la siembra vive tras el header,
                         // no regada por toda la hoja.
                         destinoY: 0.06 + pow(s2, 1.4) * 0.88,
                         origenX: 0.10 + s3 * 0.80,
                         radio: 1.1 + s2 * 1.5,
                         retraso: s * Receta.escalon,
                         fase: s2 * 2 * .pi,
                         brillo: 0.5 + 0.5 * s)
        }
    }

    public var body: some View {
        // Reduce Motion: papel puro desde el primer cuadro (ver nota de cabecera).
        if !still {
            TimelineView(.animation(minimumInterval: 1.0 / 60, paused: terminada)) { tl in
                Canvas { ctx, size in
                    dibujar(ctx: &ctx, size: size, ahora: tl.date)
                }
            }
            .onAppear { if inicio == .distantPast { inicio = Date() } }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private var terminada: Bool {
        inicio == .distantPast ? false : Date().timeIntervalSince(inicio) > Receta.vida
    }

    private func dibujar(ctx: inout GraphicsContext, size: CGSize, ahora: Date) {
        guard inicio != .distantPast else { return }
        let t = ahora.timeIntervalSince(inicio)
        guard t < Receta.vida else { return }
        let apagado = 1 - suave((t - Receta.disolucionDesde) / Receta.disolucionDur)
        guard apagado > 0.01 else { return }
        for p in Self.puntos(semilla: semilla, cuenta: cuenta) {
            let u = suave((t - 0.15 - p.retraso) / Receta.viaje)
            guard u > 0 else { continue }
            let dx = p.destinoX * size.width
            let dy = p.destinoY * size.height
            let ox = p.origenX * size.width
            let x = ox + (dx - ox) * u
            let y = -14 + (dy + 14) * u
            let alfa: Double = u < 1
                ? Receta.alfaViaje * p.brillo * min(1, u * 1.6)
                : Receta.alfaAsentada * p.brillo
                    * (0.9 + 0.1 * sin(t * 2.2 + p.fase))
            let r = p.radio * (1.5 - 0.5 * u)
            ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r,
                                            width: r * 2, height: r * 2)),
                     with: .color(tono.opacity(alfa * apagado)))
        }
    }

    private func suave(_ u: Double) -> Double {
        let c = min(1, max(0, u))
        return c * c * (3 - 2 * c)
    }
}

#if DEBUG
#Preview("Siembra · sobre papel") {
    ZStack(alignment: .top) {
        LiquidColor.fondoAlto.ignoresSafeArea()
        LiquidSiembraMotas(tono: LiquidColor.verdePrimario)
            .frame(height: 180)
    }
}
#endif
