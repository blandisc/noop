import SwiftUI

// MARK: - Liquid Glass · Aurora fina del filo (FER-28 «El Tablero»)
//
// El filo de cada módulo lleva dos capas, y el orden es lo que lo vuelve joyería y no feria:
//   1) el COLOR de los datos del módulo girando MUY lento por debajo (44–58 s por vuelta,
//      transiciones anchísimas, alfas ~48 %): una insinuación, no un arcoíris. En reposo casi
//      lo dudas; cuando lo notas, ya te ganó.
//   2) encima, FIJO, el especular: un brillo blanco quieto en el canto superior, porque la
//      luz del cuarto no gira. El color pasa POR DEBAJO de la luz — eso es lo fino.
//
// Un solo reloj: la rotación deriva del tiempo de pared (fase compartida con la plasta). Los
// módulos pares giran en sentido inverso para que jamás se sincronicen. Reduce Motion: el
// color queda estático (con su especular); el filo no gira.
//
// En Metal (FER-13 Fase B, fuera de alcance) esto será interferencia de película delgada real
// dependiente del ángulo; esta aurora SwiftUI es la versión canónica por ahora.

public struct LiquidAuroraEdge: View {
    private let tones: [Color]
    private let period: Double
    private let reverse: Bool
    private let radius: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.liquidMotionDisabled) private var motionDisabled
    @Environment(\.liquidAmbientPaused) private var ambientPaused

    /// - Parameters:
    ///   - tones: los tonos 1:1 de los datos del módulo (típicamente 3). El filo ES sus datos.
    ///   - period: segundos por vuelta (44 / 52 / 38 / 58 en los 4 módulos de Hoy).
    ///   - reverse: gira en sentido inverso (los módulos pares).
    ///   - radius: radio del contorno; por defecto el del módulo.
    public init(tones: [Color], period: Double, reverse: Bool = false,
                radius: CGFloat = LiquidRadius.modulo) {
        self.tones = tones
        self.period = period
        self.reverse = reverse
        self.radius = radius
    }

    /// Alfa de los tonos: insinuación, no arcoíris.
    private static let toneAlpha: Double = 0.48

    /// Paradas del gradiente angular de color: cada tono con huecos transparentes anchos entre
    /// medias (patrón del mockup: tono 0 % · transparente 22 % · tono 42 % · transparente 64 % ·
    /// tono 84 % · vuelta). Generalizado a N tonos.
    private var colorStops: [Gradient.Stop] {
        let list = tones.isEmpty ? [LiquidColor.tinta500] : tones
        var stops: [Gradient.Stop] = []
        let n = list.count
        for (i, tone) in list.enumerated() {
            let center = Double(i) / Double(n)
            stops.append(.init(color: tone.opacity(Self.toneAlpha), location: center))
            // Hueco transparente a mitad de camino hacia el siguiente tono.
            let gap = (Double(i) + 0.5) / Double(n)
            stops.append(.init(color: .clear, location: gap))
        }
        // Cierra el ciclo con el primer tono en 1.0.
        stops.append(.init(color: list[0].opacity(Self.toneAlpha), location: 1.0))
        return stops
    }

    /// El especular blanco fijo, centrado en el canto superior (~8 % del perímetro). En la
    /// convención de `AngularGradient` (0 = 3 en punto, horario) el tope está en 0.75.
    private static let specularStops: [Gradient.Stop] = [
        .init(color: .white.opacity(0), location: 0.0),
        .init(color: .white.opacity(0), location: 0.63),
        .init(color: .white.opacity(0.75), location: 0.72),
        .init(color: .white.opacity(0.75), location: 0.78),
        .init(color: .white.opacity(0), location: 0.87),
        .init(color: .white.opacity(0), location: 1.0),
    ]

    public var body: some View {
        let still = reduceMotion || motionDisabled || ambientPaused
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: still)) { context in
            let t = still ? 0 : context.date.timeIntervalSinceReferenceDate
            let turns = (t / period).truncatingRemainder(dividingBy: 1)
            let deg = turns * 360 * (reverse ? -1 : 1)
            ZStack {
                // Capa 1 — el color de los datos, girando lentísimo por debajo.
                shape
                    .strokeBorder(
                        AngularGradient(gradient: Gradient(stops: colorStops),
                                        center: .center, angle: .degrees(deg)),
                        lineWidth: 1)
                    .blur(radius: 0.4)
                // Capa 2 — el especular blanco FIJO en el canto superior.
                shape
                    .strokeBorder(
                        AngularGradient(gradient: Gradient(stops: Self.specularStops),
                                        center: .center, angle: .degrees(0)),
                        lineWidth: 1)
            }
        }
        .allowsHitTesting(false)
        // Decorativo: el color habla por el dato, no por el filo.
        .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("Liquid · Aurora del filo") {
    ZStack {
        LiquidColor.fondoGradient.ignoresSafeArea()
        VStack(spacing: LiquidSpace.s250) {
            ForEach(Array([
                ([LiquidColor.indigo, LiquidColor.rosa, LiquidColor.verdePrimario], 44.0, false),
                ([LiquidColor.verdePrimario, LiquidColor.ambar, LiquidColor.azul], 52.0, true),
                ([LiquidColor.ambar, LiquidColor.teal, LiquidColor.verdePrimario], 38.0, false),
                ([LiquidColor.cian, LiquidColor.ambar, LiquidColor.azul], 58.0, true),
            ].enumerated()), id: \.offset) { _, cfg in
                RoundedRectangle(cornerRadius: LiquidRadius.modulo, style: .continuous)
                    .fill(Color.white.opacity(0.5))
                    .frame(height: 72)
                    .overlay(LiquidAuroraEdge(tones: cfg.0, period: cfg.1, reverse: cfg.2))
            }
        }
        .padding(LiquidSpace.s600)
    }
}
#endif
