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

    public init(alignment: Alignment, offset: CGSize, size: CGSize, tone: Color,
                opacity: Double, blur: CGFloat, period: Double, reverse: Bool = false) {
        self.alignment = alignment
        self.offset = offset
        self.size = size
        self.tone = tone
        self.opacity = opacity
        self.blur = blur
        self.period = period
        self.reverse = reverse
    }
}

/// El fondo de una pantalla Liquid: degradado de papel + aurora superior + orbes drift.
/// La animación es un `TimelineView` ambiental (16–26 s); con Reduce Motion queda quieta.
public struct LiquidAmbientBackground: View {
    private let auroraStops: [Gradient.Stop]
    private let orbs: [LiquidOrbSpec]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.liquidMotionDisabled) private var motionDisabled

    public init(auroraStops: [Gradient.Stop], orbs: [LiquidOrbSpec]) {
        self.auroraStops = auroraStops
        self.orbs = orbs
    }

    /// El fondo de Hoy: aurora verde + 3 orbes (verde ×2, índigo ×1) — ensamble §7.1.
    public static var hoy: LiquidAmbientBackground {
        LiquidAmbientBackground(
            auroraStops: [
                .init(color: LiquidColor.verdeAurora.opacity(0.28), location: 0),
                .init(color: LiquidColor.verdePrimario.opacity(0.16), location: 0.46),
                .init(color: LiquidColor.verdePrimario.opacity(0), location: 0.78),
            ],
            orbs: [
                .init(alignment: .topLeading, offset: CGSize(width: -50, height: 110),
                      size: CGSize(width: 280, height: 240), tone: LiquidColor.verdeOrbe,
                      opacity: 0.24, blur: 28, period: 16),
                .init(alignment: .topTrailing, offset: CGSize(width: 60, height: 430),
                      size: CGSize(width: 300, height: 260), tone: LiquidColor.verdePrimario,
                      opacity: 0.18, blur: 30, period: 21, reverse: true),
                .init(alignment: .bottomLeading, offset: CGSize(width: 90, height: -60),
                      size: CGSize(width: 240, height: 200), tone: LiquidColor.indigo,
                      opacity: 0.13, blur: 28, period: 26),
            ])
    }

    public var body: some View {
        let still = reduceMotion || motionDisabled
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                LiquidColor.papelGradient
                // Aurora: radial 120 % × 55 % anclada arriba (50 % / −8 %).
                RadialGradient(stops: auroraStops,
                               center: UnitPoint(x: 0.5, y: -0.08),
                               startRadius: 0, endRadius: max(1, w * 1.2))
                    .scaleEffect(x: 1, y: max(0.01, (h * 0.55) / (w * 1.2)),
                                 anchor: UnitPoint(x: 0.5, y: -0.08))
                TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: still)) { context in
                    let t = still ? 0 : context.date.timeIntervalSinceReferenceDate
                    ZStack {
                        ForEach(Array(orbs.enumerated()), id: \.offset) { _, orb in
                            let u = still ? 0 : LiquidMotion.driftProgress(
                                time: t, period: orb.period, reverse: orb.reverse)
                            Ellipse()
                                .fill(EllipticalGradient(
                                    colors: [orb.tone.opacity(orb.opacity), orb.tone.opacity(0)],
                                    center: .center))
                                .frame(width: orb.size.width, height: orb.size.height)
                                .blur(radius: orb.blur)
                                .scaleEffect(1 + (LiquidMotion.driftScaleMax - 1) * u)
                                .offset(x: orb.offset.width + LiquidMotion.driftTranslation.width * u,
                                        y: orb.offset.height + LiquidMotion.driftTranslation.height * u)
                                .frame(maxWidth: .infinity, maxHeight: .infinity,
                                       alignment: orb.alignment)
                        }
                    }
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

// MARK: Cabecera (kicker + elemento circular 36)

/// Fila de cabecera: kicker de fecha/contexto a la izquierda, un elemento circular de 36
/// (dial-sello o anillo de progreso) a la derecha.
public struct LiquidScreenHeader<Trailing: View>: View {
    private let kicker: String
    private let trailing: Trailing

    public init(kicker: String, @ViewBuilder trailing: () -> Trailing) {
        self.kicker = kicker
        self.trailing = trailing()
    }

    public var body: some View {
        HStack {
            Text(kicker).liquidKicker().foregroundStyle(LiquidColor.tinta700)
            Spacer()
            trailing
        }
    }
}

// MARK: Dial-sello 24 h (Hoy)

/// El sello circular de 36: vidrio de lente en miniatura con el día como dial de 24 h —
/// arco de noche (índigo), arco de día (tinta), marcador verde en la hora actual y un
/// punto de papel a medianoche (arriba).
public struct LiquidDialSeal: View {
    private let nightStart: Double
    private let nightEnd: Double
    private let marker: Double
    private let size: CGFloat

    /// Horas en reloj de 24 (medianoche arriba). Defaults = ensamble de Hoy
    /// (noche 20:00–04:00, marcador 08:00).
    public init(nightStart: Double = 20, nightEnd: Double = 4, marker: Double = 8,
                size: CGFloat = 36) {
        self.nightStart = nightStart
        self.nightEnd = nightEnd
        self.marker = marker
        self.size = size
    }

    private func angle(_ hour: Double) -> Double {
        -90 + hour / 24 * 360
    }

    public var body: some View {
        let r = size * (10.5 / 36)
        let nightFrom = angle(nightStart)
        var nightTo = angle(nightEnd)
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
            // Dial: track + arco día + arco noche + medianoche + marcador.
            DialArc(from: 0, to: 360)
                .stroke(LiquidColor.tinta900.opacity(0.14), lineWidth: 2)
                .padding((size - 2 * r) / 2)
            DialArc(from: nightTo, to: nightFrom + 360)
                .stroke(LiquidColor.tinta900, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                .padding((size - 2 * r) / 2)
            DialArc(from: nightFrom, to: nightTo)
                .stroke(LiquidColor.indigo, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                .padding((size - 2 * r) / 2)
            Circle().fill(LiquidColor.papelAlto)
                .frame(width: size * 0.045, height: size * 0.045)
                .position(x: size / 2, y: size / 2 - r)
            Circle().fill(LiquidColor.verdePrimario)
                .overlay(Circle().strokeBorder(Color.white, lineWidth: 1))
                .frame(width: size * 0.117, height: size * 0.117)
                .position(x: size / 2 + r * CGFloat(cos(markerAngle)),
                          y: size / 2 + r * CGFloat(sin(markerAngle)))
        }
        .frame(width: size, height: size)
        .liquidShadow([
            .init(color: LiquidColor.tinta900.opacity(0.14), radius: 16, y: 12),
            .init(color: LiquidColor.tinta900.opacity(0.07), radius: 3, y: 2),
        ])
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

// MARK: Cables vivos (Hoy)

/// Las tres curvas que conectan los orbes de señal con el hero: trazo base en degradado
/// verde que se apaga + un pulso que viaja (flowDash · 9 s linear · delays 0/0.8/1.6).
/// Con Reduce Motion los pulsos quedan congelados en su fase inicial.
public struct LiquidSignalCables: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.liquidMotionDisabled) private var motionDisabled

    public init() {}

    /// Paths exactos del ensamble (viewBox 358 × 178) con el delay de su pulso.
    private static let cables: [(d: String, delay: Double, start: UnitPoint, end: UnitPoint)] = [
        ("M62 94 C52 122, 112 132, 130 148 S153 161, 156 165", 0.0,
         UnitPoint(x: 0, y: 0), UnitPoint(x: 0.6, y: 1)),
        ("M179 100 C171 120, 192 140, 187 156 S183 165, 182 170", 0.8,
         UnitPoint(x: 0, y: 0), UnitPoint(x: 0, y: 1)),
        ("M296 94 C305 126, 262 138, 234 152 S211 162, 207 166", 1.6,
         UnitPoint(x: 1, y: 0), UnitPoint(x: 0.4, y: 1)),
    ]

    public var body: some View {
        let still = reduceMotion || motionDisabled
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: still)) { context in
            let t = still ? 0 : context.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(Array(Self.cables.enumerated()), id: \.offset) { _, cable in
                    CablePath(d: cable.d)
                        .stroke(
                            LinearGradient(
                                colors: [LiquidColor.verdePrimario.opacity(0.45),
                                         LiquidColor.verdePrimario.opacity(0)],
                                startPoint: cable.start, endPoint: cable.end),
                            lineWidth: 1.2)
                    // El pulso viaja con `trim` (la gramática del sistema para progreso
                    // sobre Shape); congelado queda en el arranque del cable.
                    pulse(cable.d, progress: still
                          ? 0 : LiquidMotion.flowPulseProgress(time: t, delay: cable.delay))
                }
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func pulse(_ d: String, progress: Double) -> some View {
        let len = LiquidMotion.flowPulseLength
        let style = StrokeStyle(lineWidth: 1.6, lineCap: .round)
        ZStack {
            CablePath(d: d)
                .trim(from: progress, to: min(1, progress + len))
                .stroke(LiquidColor.verdePrimario, style: style)
            if progress + len > 1 {
                // El pulso cruza el final del cable: se completa desde el arranque.
                CablePath(d: d)
                    .trim(from: 0, to: progress + len - 1)
                    .stroke(LiquidColor.verdePrimario, style: style)
            }
        }
        .opacity(0.75)
    }
}

/// Un cable escalado del viewBox 358 × 178 al rect (preserveAspectRatio = none).
private struct CablePath: Shape {
    let d: String

    func path(in rect: CGRect) -> Path {
        SVGPathData.path(d).applying(
            CGAffineTransform(translationX: rect.minX, y: rect.minY)
                .scaledBy(x: rect.width / 358, y: rect.height / 178))
    }
}

// MARK: Hero de veredicto (Hoy)

/// El veredicto matinal: display/xl centrado con la palabra clave en verde/primario y el
/// subtítulo cuerpo a 8 pt.
public struct LiquidHeroVeredicto: View {
    private let title: String
    private let highlight: String
    private let subtitle: String

    /// `highlight` debe aparecer dentro de `title` (se pinta su última ocurrencia).
    public init(title: String, highlight: String, subtitle: String) {
        self.title = title
        self.highlight = highlight
        self.subtitle = subtitle
    }

    public var body: some View {
        VStack(spacing: LiquidSpace.s200) {
            // Las líneas del hero se apilan a mano para lograr el line-height 0.96.
            VStack(spacing: LiquidType.displayXLLineSpacing) {
                ForEach(Array(title.components(separatedBy: "\n").enumerated()),
                        id: \.offset) { _, line in
                    lineText(line)
                }
            }
            .multilineTextAlignment(.center)
            Text(subtitle)
                .font(LiquidType.cuerpo)
                .foregroundStyle(LiquidColor.tinta700)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private func lineText(_ line: String) -> Text {
        if let range = line.range(of: highlight, options: .backwards) {
            return Text(line[..<range.lowerBound]).liquidDisplayXL()
                .foregroundStyle(LiquidColor.tinta900)
                + Text(line[range]).liquidDisplayXL()
                .foregroundStyle(LiquidColor.verdePrimario)
                + Text(line[range.upperBound...]).liquidDisplayXL()
                .foregroundStyle(LiquidColor.tinta900)
        }
        return Text(line).liquidDisplayXL().foregroundStyle(LiquidColor.tinta900)
    }
}

#if DEBUG
#Preview("Liquid · Patrones") {
    ZStack {
        LiquidAmbientBackground.hoy
        VStack(spacing: LiquidSpace.s400) {
            LiquidScreenHeader(kicker: "MIÉ 22 DE JUL") { LiquidDialSeal() }
            ZStack(alignment: .top) {
                LiquidSignalCables()
                HStack(spacing: 53) {
                    LiquidSignalOrb(label: "AUTONÓMICO", caption: "EN TU RANGO",
                                    progress: 0.35, icon: .ondaSenal, state: .ok)
                    LiquidSignalOrb(label: "SUEÑO", caption: "EN TU RANGO",
                                    progress: 0.43, icon: .lunaSenal, state: .ok)
                    LiquidSignalOrb(label: "TÉRMICO", caption: "EN TU RANGO",
                                    progress: 0.5, icon: .termoSenal, state: .ok)
                }
            }
            .frame(height: 178)
            LiquidHeroVeredicto(title: "Dale\ncon todo", highlight: "todo",
                                subtitle: "Tus 3 señales amanecieron dentro de tu rango.")
        }
        .padding(LiquidSpace.s550)
    }
}
#endif
