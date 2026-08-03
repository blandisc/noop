import SwiftUI

// MARK: - Liquid Glass · Patrones (handoff §6)
//
// Recetas fijas del sistema que aún no son componentes con contrato: fondo ambiental,
// cabecera, dial-sello 24 h, cables vivos y hero de veredicto. Se componetizan con props
// cuando aparezcan en una tercera pantalla.

// MARK: Fondo ambiental (aurora + orbes drift)

/// Un orbe de fondo: elipse radial del tono, difuminada, que deriva con `dur/drift`.
public struct LiquidOrbSpec: Sendable {
    let alignment: Alignment
    let offset: CGSize
    let size: CGSize
    let tone: Color
    let opacity: Double
    let blur: CGFloat
    let period: Double
    let reverse: Bool
    /// Radios del RECORRIDO del orbe (sesión /inject): el orbe circula por la pantalla en
    /// una órbita suave de esta amplitud (pt), con un respiro de intensidad sutil. `.zero`
    /// = el drift corto original del handoff.
    let orbit: CGSize

    public init(alignment: Alignment, offset: CGSize, size: CGSize, tone: Color,
                opacity: Double, blur: CGFloat, period: Double, reverse: Bool = false,
                orbit: CGSize = .zero) {
        self.alignment = alignment
        self.offset = offset
        self.size = size
        self.tone = tone
        self.opacity = opacity
        self.blur = blur
        self.period = period
        self.reverse = reverse
        self.orbit = orbit
    }
}

/// El ESTADO del ambiente (pedido del dueño /inject 2026-07-22): el color que respira
/// detrás del vidrio y viaja por los cables es SEMÁNTICO — verde cuando el día está bien,
/// ámbar con un detalle, rojo cuando el cuerpo pide bajarle, neutro sin veredicto.
public enum LiquidAmbiente: Sendable, Equatable {
    case bien, atencion, alerta, neutro

    /// El acento (pulsos de cables, punto activo).
    public var acento: Color {
        switch self {
        case .bien: return LiquidColor.verdePrimario
        case .atencion: return LiquidColor.atencion
        case .alerta: return LiquidColor.negativo
        case .neutro: return LiquidColor.tinta500
        }
    }

    /// (tono de arranque, tono medio) de la aurora.
    var aurora: (Color, Color) {
        switch self {
        case .bien: return (LiquidColor.verdeAurora, LiquidColor.verdePrimario)
        case .atencion: return (LiquidColor.ambarClaro, LiquidColor.atencion)
        case .alerta: return (LiquidColor.rosa, LiquidColor.negativo)
        case .neutro: return (LiquidColor.tinta500, LiquidColor.tinta500)
        }
    }

    /// (tono claro, tono profundo) de las manchas que circulan.
    var orbes: (Color, Color) {
        switch self {
        case .bien: return (LiquidColor.verdeOrbe, LiquidColor.verdePrimario)
        case .atencion: return (LiquidColor.ambarClaro, LiquidColor.atencion)
        case .alerta: return (LiquidColor.rosa, LiquidColor.negativo)
        case .neutro: return (LiquidColor.tinta500, LiquidColor.tinta500)
        }
    }

    /// Las 4 masas pálidas de la plasta de «El Tablero» (FER-28) para este clima. Un solo
    /// dial: la pantalla lee esto y `LiquidPlasta` las cruza con `ambienteCrossfade` (1.6 s).
    public var plasta: [Color] {
        switch self {
        case .bien: return LiquidColor.plastaVerde
        case .atencion: return LiquidColor.plastaAmbar
        case .alerta: return LiquidColor.plastaRojo
        case .neutro: return LiquidColor.plastaNeutra
        }
    }

    /// El neutro baja la intensidad a la mitad (calma, no celebración).
    var intensidad: Double { self == .neutro ? 0.5 : 1 }
}

/// El fondo de una pantalla Liquid: degradado de papel + aurora superior + orbes drift.
/// La animación es un `TimelineView` ambiental (16–26 s); con Reduce Motion queda quieta.
public struct LiquidAmbientBackground: View {
    private let auroraStops: [Gradient.Stop]
    private let orbs: [LiquidOrbSpec]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.liquidMotionDisabled) private var motionDisabled
    @Environment(\.liquidAmbientPaused) private var ambientPaused
    @Environment(\.liquidDebugHide) private var debugHide

    public init(auroraStops: [Gradient.Stop], orbs: [LiquidOrbSpec]) {
        self.auroraStops = auroraStops
        self.orbs = orbs
    }

    /// El fondo de Hoy (FER-10 «El Ecosistema»): UN SOLO COLOR — el del veredicto — en
    /// tres manchas monocromas que derivan detrás del vidrio, con crossfade de 1.6 s al
    /// cambiar de estado. La aurora multicolor y la mancha índigo se retiraron de Hoy
    /// (violaban «un solo color, el del veredicto»); `auroraStops` sigue disponible para
    /// otros presets.
    public static func hoy(_ ambiente: LiquidAmbiente = .bien) -> some View {
        LiquidHoyAmbient(ambiente: ambiente)
    }

    /// Las tres manchas monocromas de Hoy para un ambiente dado (alfas del prototipo v6).
    static func hoyOrbs(_ ambiente: LiquidAmbiente) -> [LiquidOrbSpec] {
        let (c1, c2, c3, a1, a2, a3): (Color, Color, Color, Double, Double, Double)
        switch ambiente {
        case .bien:
            (c1, c2, c3) = (LiquidColor.verdeAurora, LiquidColor.verdePrimario, LiquidColor.verdeAurora)
            (a1, a2, a3) = (0.22, 0.15, 0.13)
        case .atencion:
            (c1, c2, c3) = (LiquidColor.ambarClaro, LiquidColor.atencion, LiquidColor.ambarClaro)
            (a1, a2, a3) = (0.24, 0.15, 0.13)
        case .alerta:
            (c1, c2, c3) = (LiquidColor.negativo, LiquidColor.negativo, LiquidColor.rojoClaro)
            (a1, a2, a3) = (0.20, 0.13, 0.13)
        case .neutro:
            (c1, c2, c3) = (LiquidColor.tinta500, LiquidColor.tinta500, LiquidColor.tinta500)
            (a1, a2, a3) = (0.15, 0.10, 0.08)
        }
        return [
            .init(alignment: .topLeading, offset: CGSize(width: -80, height: 50),
                  size: CGSize(width: 300, height: 300), tone: c1, opacity: a1,
                  blur: 28, period: 21, orbit: CGSize(width: 64, height: 42)),
            .init(alignment: .topTrailing, offset: CGSize(width: 80, height: 210),
                  size: CGSize(width: 250, height: 250), tone: c2, opacity: a2,
                  blur: 28, period: 26, reverse: true,
                  orbit: CGSize(width: 48, height: 54)),
            .init(alignment: .bottomLeading, offset: CGSize(width: 40, height: -100),
                  size: CGSize(width: 210, height: 210), tone: c3, opacity: a3,
                  blur: 28, period: 18, orbit: CGSize(width: 40, height: 46)),
        ]
    }

    public var body: some View {
        let still = reduceMotion || motionDisabled || ambientPaused
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                // Fondo neutro (adiós beige en Hoy, /inject): el color lo ponen la aurora
                // y los orbes que circulan.
                LiquidColor.fondoGradient
                // Aurora: radial 120 % × 55 % anclada arriba (50 % / −8 %).
                if !debugHide.contains("aurora") {
                    RadialGradient(stops: auroraStops,
                                   center: UnitPoint(x: 0.5, y: -0.08),
                                   startRadius: 0, endRadius: max(1, w * 1.2))
                        .scaleEffect(x: 1, y: max(0.01, (h * 0.55) / (w * 1.2)),
                                     anchor: UnitPoint(x: 0.5, y: -0.08))
                }
                if !debugHide.contains("orbes") {
                    LiquidAmbientOrbs(orbs: orbs)
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// El loop de manchas drift (compartido por `LiquidAmbientBackground` y el fondo de Hoy).
struct LiquidAmbientOrbs: View {
    let orbs: [LiquidOrbSpec]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.liquidMotionDisabled) private var motionDisabled
    @Environment(\.liquidAmbientPaused) private var ambientPaused

    var body: some View {
        let still = reduceMotion || motionDisabled || ambientPaused
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: still)) { context in
            let t = still ? 0 : context.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(Array(orbs.enumerated()), id: \.offset) { index, orb in
                    let u = still ? 0 : LiquidMotion.driftProgress(
                        time: t, period: orb.period, reverse: orb.reverse)
                    // Órbita suave por la pantalla (/inject): desplazamiento Lissajous que
                    // arranca en 0 (Reduce Motion = layout del handoff) con periodos
                    // ≥16 s, + un respiro sutil de intensidad. Sin `.blur` (el degradado
                    // radial YA es suave).
                    let theta = still ? 0 : 2 * .pi * t / orb.period + Double(index) * 2.1
                    let ox = orb.orbit.width * CGFloat(sin(theta))
                    let oy = orb.orbit.height * CGFloat(sin(theta * 0.5))
                    let breathe = still ? 1.0 : 0.8 + 0.2 * (0.5 + 0.5 * sin(theta))
                    Ellipse()
                        .fill(EllipticalGradient(
                            colors: [orb.tone.opacity(orb.opacity * breathe),
                                     orb.tone.opacity(0)],
                            center: .center))
                        .frame(width: orb.size.width, height: orb.size.height)
                        .scaleEffect(1 + (LiquidMotion.driftScaleMax - 1) * u)
                        .offset(x: orb.offset.width + ox,
                                y: orb.offset.height + oy)
                        .frame(maxWidth: .infinity, maxHeight: .infinity,
                               alignment: orb.alignment)
                }
            }
        }
    }
}

/// El fondo de Hoy (FER-10): fondo neutro + las tres manchas MONOCROMAS del veredicto,
/// con crossfade `ambienteCrossfade` (1.6 s) entre climas. Bajo Reduce Motion el fade se
/// conserva (un fade no es movimiento); lo que se congela es el drift.
public struct LiquidHoyAmbient: View {
    private let ambiente: LiquidAmbiente

    public init(ambiente: LiquidAmbiente) {
        self.ambiente = ambiente
    }

    private static let todos: [LiquidAmbiente] = [.bien, .atencion, .alerta, .neutro]

    public var body: some View {
        ZStack {
            LiquidColor.fondoGradient
            ForEach(Array(Self.todos.enumerated()), id: \.offset) { _, amb in
                LiquidAmbientOrbs(orbs: LiquidAmbientBackground.hoyOrbs(amb))
                    .opacity(amb == ambiente ? 1 : 0)
            }
        }
        .animation(.easeInOut(duration: LiquidEcosistemaMotion.ambienteCrossfade),
                   value: ambiente)
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

// MARK: Cabecera (kicker + elemento circular 40)

/// Fila de cabecera: kicker de fecha/contexto a la izquierda, un elemento circular de 40
/// (dial-sello o anillo de progreso) a la derecha. `kickerA11y` = la versión para
/// VoiceOver («miércoles, 22 de julio de 2026») — la abreviatura en caja alta se
/// deletrea mal (revote /inject).
public struct LiquidScreenHeader<Trailing: View>: View {
    private let kicker: String
    private let kickerA11y: String?
    private let trailing: Trailing

    public init(kicker: String, kickerA11y: String? = nil,
                @ViewBuilder trailing: () -> Trailing) {
        self.kicker = kicker
        self.kickerA11y = kickerA11y
        self.trailing = trailing()
    }

    public var body: some View {
        HStack {
            Text(kicker).liquidKicker().foregroundStyle(LiquidColor.tinta700)
                .accessibilityLabel(Text(verbatim: kickerA11y ?? kicker))
            Spacer()
            trailing
        }
    }
}

// MARK: Dial-sello 24 h (Hoy)

/// El sello circular de 40: vidrio de lente en miniatura con el día como dial de 24 h —
/// arco de noche (índigo), arco de día (tinta), marcador verde en la hora actual y un
/// punto de papel a medianoche (arriba).
public struct LiquidDialSeal: View {
    private let night: (start: Double, end: Double)?
    private let sol: (start: Double, end: Double)?
    private let marker: Double
    private let size: CGFloat

    /// Horas en reloj de 24 (medianoche arriba). Defaults = ensamble de Hoy
    /// (noche 20:00–04:00, marcador 08:00). `night == nil` = sin sesión de sueño
    /// anoche → sin arco de noche. `sol` (amanecer/atardecer) pinta el arco del día
    /// en ORO siguiendo el sol real — la herencia del DiurnalDial (sesión /inject).
    public init(night: (start: Double, end: Double)? = (20, 4),
                sol: (start: Double, end: Double)? = nil,
                marker: Double = 8, size: CGFloat = 40) {
        self.night = night
        self.sol = sol
        self.marker = marker
        self.size = size
    }

    private func angle(_ hour: Double) -> Double {
        -90 + hour / 24 * 360
    }

    public var body: some View {
        let r = size * (10.5 / 36)
        let nightFrom = angle(night?.start ?? 0)
        var nightTo = angle(night?.end ?? 0)
        if nightTo <= nightFrom { nightTo += 360 }
        let markerAngle = angle(marker) * .pi / 180

        return ZStack {
            // Vidrio del sello (blur 14 / blanco .5 / borde .9 / especular chico).
            Circle().fill(.ultraThinMaterial)
            Circle().fill(LiquidColor.vidrioLente)
            Circle()
                .strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.95), location: 0),
                            .init(color: LiquidColor.tinta900.opacity(0.05), location: 1),
                        ],
                        startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1.5)
                .blur(radius: 0.5)
                .clipShape(Circle())
            Circle().strokeBorder(LiquidColor.vidrioBordeFuerte, lineWidth: 0.5)
            Ellipse()
                .fill(RadialGradient(colors: [.white.opacity(0.95), .white.opacity(0)],
                                     center: .center, startRadius: 0, endRadius: size * 0.21))
                .frame(width: size * 0.42, height: size * 0.24)
                .position(x: size * 0.18 + size * 0.21, y: size * 0.08 + size * 0.12)
            // Dial: marcas 24 h + track + arco solar (día) + arco de noche + medianoche +
            // marcador — la lectura del DiurnalDial dicha en vidrio.
            DialTicks(majors: false)
                .stroke(LiquidColor.tinta900.opacity(0.12), lineWidth: 0.7)
            DialTicks(majors: true)
                .stroke(LiquidColor.tinta900.opacity(0.25), lineWidth: 1)
            DialArc(from: 0, to: 360)
                .stroke(LiquidColor.tinta900.opacity(0.14), lineWidth: 2)
                .padding((size - 2 * r) / 2)
            if let sol {
                // El día según el sol real: amanecer → atardecer, en oro.
                DialArc(from: angle(sol.start), to: angle(sol.end) <= angle(sol.start)
                        ? angle(sol.end) + 360 : angle(sol.end))
                    .stroke(LiquidColor.oro, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                    .padding((size - 2 * r) / 2)
            } else if night != nil {
                // Sin ventana solar (caso polar): el día como complemento de la noche, en tinta.
                DialArc(from: nightTo, to: nightFrom + 360)
                    .stroke(LiquidColor.tinta900, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                    .padding((size - 2 * r) / 2)
            }
            if night != nil {
                DialArc(from: nightFrom, to: nightTo)
                    .stroke(LiquidColor.indigo, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                    .padding((size - 2 * r) / 2)
                Circle().fill(LiquidColor.papelAlto)
                    .frame(width: size * 0.045, height: size * 0.045)
                    .position(x: size / 2, y: size / 2 - r)
            }
            Circle().fill(LiquidColor.verdePrimario)
                .overlay(Circle().strokeBorder(Color.white, lineWidth: 1))
                .frame(width: size * 0.117, height: size * 0.117)
                .position(x: size / 2 + r * CGFloat(cos(markerAngle)),
                          y: size / 2 + r * CGFloat(sin(markerAngle)))
        }
        .frame(width: size, height: size)
        // Elevación como geometría (misma regla que las recetas: nada de .shadow sobre material).
        .liquidShadow([
            .init(color: LiquidColor.tinta900.opacity(0.14), radius: 16, y: 12),
            .init(color: LiquidColor.tinta900.opacity(0.07), radius: 3, y: 2),
        ], silhouette: Circle())
        // Decorativo para VoiceOver: la fecha ya vive en el kicker de la cabecera.
        .accessibilityHidden(true)
    }
}

/// Arco en grados con 0° a las 3 en punto, creciendo en sentido horario (pantalla).
private struct DialArc: Shape {
    let from: Double
    let to: Double

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addArc(center: CGPoint(x: rect.midX, y: rect.midY),
                 radius: min(rect.width, rect.height) / 2,
                 startAngle: .degrees(from), endAngle: .degrees(to), clockwise: false)
        return p
    }
}

/// Las 24 marcas horarias del dial (mayores en 0/6/12/18), entre el track y el borde.
private struct DialTicks: Shape {
    let majors: Bool

    func path(in rect: CGRect) -> Path {
        let R = min(rect.width, rect.height) / 2
        let c = CGPoint(x: rect.midX, y: rect.midY)
        var p = Path()
        for hour in 0..<24 where (hour % 6 == 0) == majors {
            let a = (-90 + Double(hour) * 15) * .pi / 180
            let r1 = R * 0.66
            let r2 = R * (majors ? 0.80 : 0.74)
            p.move(to: CGPoint(x: c.x + r1 * CGFloat(cos(a)), y: c.y + r1 * CGFloat(sin(a))))
            p.addLine(to: CGPoint(x: c.x + r2 * CGFloat(cos(a)), y: c.y + r2 * CGFloat(sin(a))))
        }
        return p
    }
}

#if DEBUG
#Preview("Liquid · Patrones (ambiente monocromo)") {
    ZStack {
        LiquidAmbientBackground.hoy(.bien)
        VStack(spacing: LiquidSpace.s400) {
            LiquidScreenHeader(kicker: "MIÉ 22 DE JUL") { LiquidDialSeal() }
            Spacer()
        }
        .padding(LiquidSpace.s550)
    }
}

#Preview("Liquid · Ambiente por estado") {
    VStack(spacing: 0) {
        LiquidAmbientBackground.hoy(.bien)
        LiquidAmbientBackground.hoy(.atencion)
        LiquidAmbientBackground.hoy(.alerta)
        LiquidAmbientBackground.hoy(.neutro)
    }
    .environment(\.liquidMotionDisabled, true)
}
#endif
