import SwiftUI

// MARK: - Liquid Glass · La Plasta (FER-28 «El Tablero»)
//
// El fondo de Hoy rediseñado: NO orbes con núcleo ni bokeh — el dueño probó el campo de
// orbes y eligió «la plasta»: cuatro masas suaves MONOCROMAS de la familia del veredicto
// (blur 52) que laten y derivan detrás del vidrio. Una sola familia de clima a la vez,
// derivada de UN dial (`LiquidAmbiente`), con crossfade de 1.6 s al cambiar.
//
// Un solo reloj: todas las capas ambientales del sistema leen el MISMO tiempo de pared
// (`timeIntervalSinceReferenceDate`), así que la plasta (9 s) y la respiración del orbe del
// Ecosistema (4.5 s) quedan en fase por construcción — 4.5 = 9/2— sin cablear un reloj común.
//
// Reduce Motion / pausa de escena: la plasta se congela en su composición balanceada (t = 0)
// y el crossfade de color SÍ se conserva (un fade no es movimiento).

/// Una masa de la plasta: tamaño fijo (pt), alfa, y su recorrido. La principal (`pulse`)
/// late anclada tras el orbe; las demás derivan entre dos centros expresados en fracciones
/// de la pantalla (independiente de resolución).
private struct LiquidPlastaMasa {
    let size: CGFloat
    let alpha: Double
    /// Centro en reposo/keyframe A, en fracción de (ancho, alto).
    let a: UnitPoint
    /// Keyframe B del drift (para masas que derivan); igual a `a` si sólo late.
    let b: UnitPoint
    /// Periodo del drift (medio ciclo, como el resto del sistema: ciclo completo = 2×).
    let period: Double
    /// La masa principal late en escala 1 → 1.12 con el reloj de 9 s.
    let pulses: Bool

    static let hoy: [LiquidPlastaMasa] = [
        // Principal: anclada tras el orbe, latiendo con el reloj de 9 s.
        .init(size: 320, alpha: 0.5, a: UnitPoint(x: 0.5, y: 0.30),
              b: UnitPoint(x: 0.5, y: 0.30), period: 9, pulses: true),
        // Tres derivas lentas por la mitad inferior (28–34 s de ciclo completo).
        .init(size: 280, alpha: 0.5, a: UnitPoint(x: 0.72, y: 0.52),
              b: UnitPoint(x: 0.46, y: 0.68), period: 10, pulses: false),
        .init(size: 260, alpha: 0.3, a: UnitPoint(x: 0.10, y: 0.62),
              b: UnitPoint(x: 0.42, y: 0.50), period: 9, pulses: false),
        .init(size: 230, alpha: 0.55, a: UnitPoint(x: 0.74, y: 0.72),
              b: UnitPoint(x: 0.32, y: 0.80), period: 12, pulses: false),
    ]
}

/// La plasta del veredicto: fondo casi blanco + 4 masas monocromas del clima + viñeta de luz.
/// Es el fondo completo de la pantalla «El Tablero» (los orbes drift de Hoy se retiraron en
/// FER-118: Hoy vive sobre `LiquidAtmosfera`).
struct LiquidPlasta: View {
    private let ambiente: LiquidAmbiente

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.liquidMotionDisabled) private var motionDisabled
    @Environment(\.liquidAmbientPaused) private var ambientPaused
    @Environment(\.liquidDebugHide) private var debugHide

    init(ambiente: LiquidAmbiente = .bien) {
        self.ambiente = ambiente
    }

    var body: some View {
        let still = reduceMotion || motionDisabled || ambientPaused
        let tonos = ambiente.plasta
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                // Suelo casi blanco (#FEFEFD → #F3F4F2): el color lo pone la plasta, no el papel.
                LiquidColor.fondoGradient
                if !debugHide.contains("plasta") {
                    TimelineView(.animation(minimumInterval: LiquidMotion.intervaloAmbiente, paused: still)) { context in
                        let t = still ? 0 : context.date.timeIntervalSinceReferenceDate
                        ZStack {
                            ForEach(Array(LiquidPlastaMasa.hoy.enumerated()), id: \.offset) { i, masa in
                                let tono = tonos[i % tonos.count]
                                // LÁMPARA DE LAVA (dueño 2026-08-06): la deriva A↔B lineal
                                // se leía muerta. Cada masa viaja su eje A→B y ADEMÁS
                                // vaga en Lissajous perpendicular con fase propia — el
                                // camino nunca se repite igual y se VE vivo.
                                let u = still ? 0 : LiquidMotion.driftProgress(time: t, period: masa.period)
                                let fase = Double(i) * 1.7
                                let theta = still ? 0 : 2 * .pi * t / (masa.period * 1.31) + fase
                                let wx = still ? 0.0 : 0.045 * sin(theta)
                                let wy = still ? 0.0 : 0.035 * sin(theta * 0.62 + fase)
                                let cx = masa.a.x + (masa.b.x - masa.a.x) * CGFloat(u) + CGFloat(wx)
                                let cy = masa.a.y + (masa.b.y - masa.a.y) * CGFloat(u) + CGFloat(wy)
                                // TODAS las masas respiran (la lava se hincha y se
                                // encoge); la principal conserva su latido más hondo.
                                let respira = still ? 1.0
                                    : 1 + (masa.pulses ? 0.06 : 0.035)
                                        * (1 - cos(2 * .pi * t / masa.period + fase))
                                Circle()
                                    .fill(tono.opacity(masa.alpha))
                                    .frame(width: masa.size, height: masa.size)
                                    .scaleEffect(respira)
                                    .blur(radius: 52)
                                    .position(x: cx * w, y: cy * h)
                            }
                        }
                        // Crossfade de clima: al cambiar `ambiente` los rellenos interpolan 1.6 s.
                        .animation(LiquidEcosistemaMotion.ambienteCrossfadeAnim,
                                   value: ambiente)
                    }
                }
                // Viñeta de luz: radial blanco .28 → 0 centrado en el orbe (tercio superior),
                // blend screen — el héroe es «cielo», el tablero «instrumento».
                if !debugHide.contains("plasta") {
                    Circle()
                        .fill(RadialGradient(
                            colors: [Color.white.opacity(0.28), Color.white.opacity(0)],
                            center: .center, startRadius: 0, endRadius: 150))
                        .frame(width: 300, height: 300)
                        .position(x: w * 0.5, y: h * 0.20)
                        .blendMode(.screen)
                        .allowsHitTesting(false)
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        // Decorativa: la plasta es ambiente, no habla a VoiceOver (AC10, par de la aurora).
        .accessibilityHidden(true)
    }
}

public extension LiquidAmbientBackground {
    /// El fondo de «El Tablero» (FER-28): la plasta del veredicto. (Su hermano `.hoy(_:)`, los
    /// orbes drift, se retiró en FER-118: Hoy vive sobre `LiquidAtmosfera`.)
    static func tablero(_ ambiente: LiquidAmbiente = .bien) -> some View {
        LiquidPlasta(ambiente: ambiente)
    }
}

#if DEBUG
#Preview("Liquid · Plasta (por clima)") {
    VStack(spacing: 0) {
        LiquidPlasta(ambiente: .bien)
        LiquidPlasta(ambiente: .atencion)
        LiquidPlasta(ambiente: .alerta)
        LiquidPlasta(ambiente: .neutro)
    }
    .environment(\.liquidMotionDisabled, true)
}

#Preview("Liquid · Plasta (viva, verde)") {
    LiquidPlasta(ambiente: .bien)
}
#endif
