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

    /// El fondo de Hoy, teñido por el ESTADO del día (ensamble §7.1 + ambiente semántico).
    public static func hoy(_ ambiente: LiquidAmbiente = .bien) -> LiquidAmbientBackground {
        let k = ambiente.intensidad
        return LiquidAmbientBackground(
            auroraStops: [
                .init(color: ambiente.aurora.0.opacity(0.34 * k), location: 0),
                .init(color: ambiente.aurora.1.opacity(0.20 * k), location: 0.46),
                .init(color: ambiente.aurora.1.opacity(0), location: 0.78),
            ],
            orbs: [
                // Arriba: presencia más fuerte (junto con la aurora).
                .init(alignment: .topLeading, offset: CGSize(width: -50, height: 110),
                      size: CGSize(width: 280, height: 240), tone: ambiente.orbes.0,
                      opacity: 0.32 * k, blur: 28, period: 13,
                      orbit: CGSize(width: 120, height: 200)),
                .init(alignment: .topTrailing, offset: CGSize(width: 60, height: 300),
                      size: CGSize(width: 300, height: 260), tone: ambiente.orbes.1,
                      opacity: 0.25 * k, blur: 30, period: 17, reverse: true,
                      orbit: CGSize(width: 140, height: 260)),
                // Abajo: manchas que también circulan (pedido del dueño /inject).
                .init(alignment: .bottomLeading, offset: CGSize(width: 60, height: -120),
                      size: CGSize(width: 260, height: 220), tone: LiquidColor.indigo,
                      opacity: 0.19 * k, blur: 28, period: 21,
                      orbit: CGSize(width: 110, height: 200)),
                .init(alignment: .bottomTrailing, offset: CGSize(width: 40, height: -40),
                      size: CGSize(width: 280, height: 230), tone: ambiente.orbes.0,
                      opacity: 0.21 * k, blur: 28, period: 15,
                      orbit: CGSize(width: 130, height: 220)),
            ])
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
                    TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: still)) { context in
                        let t = still ? 0 : context.date.timeIntervalSinceReferenceDate
                        ZStack {
                            ForEach(Array(orbs.enumerated()), id: \.offset) { index, orb in
                                let u = still ? 0 : LiquidMotion.driftProgress(
                                    time: t, period: orb.period, reverse: orb.reverse)
                                // Órbita suave por la pantalla (/inject): desplazamiento
                                // Lissajous que arranca en 0 (Reduce Motion = layout del
                                // handoff) con periodos ≥16 s, + un respiro sutil de
                                // intensidad. Sin `.blur` (el degradado radial YA es suave).
                                let theta = still ? 0 : 2 * .pi * t / orb.period
                                    + Double(index) * 2.1
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
                marker: Double = 8, size: CGFloat = 36) {
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

// MARK: Cables vivos (Hoy)

/// Las tres curvas que conectan los orbes de señal con el hero: trazo base en degradado
/// verde que se apaga + un pulso que viaja (flowDash · 9 s linear · delays 0/0.8/1.6).
/// Con Reduce Motion los pulsos quedan congelados en su fase inicial.
public struct LiquidSignalCables: View {
    /// El tono semántico del flujo (el `acento` del ambiente del día).
    private let tone: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.liquidMotionDisabled) private var motionDisabled
    @Environment(\.liquidAmbientPaused) private var ambientPaused
    @Environment(\.liquidDebugHide) private var debugHide

    public init(tone: Color = LiquidColor.verdePrimario) {
        self.tone = tone
    }

    /// Paths del ensamble (viewBox 358 × 178) con el delay de su pulso. Cada cable lleva un
    /// TRAMO DE CONEXIÓN inicial (línea desde y=72, el pie de su orbe) para que el pulso
    /// nazca visiblemente EN el orbe (pedido del dueño, sesión /inject 2026-07-22).
    // Zona comprimida ~25 % (pasada UI /inject): el vacío entre orbes y héroe se recorta
    // para que veredicto + carga + primera fila de tiles entren al primer pantallazo.
    private static let cables: [(d: String, delay: Double)] = [
        ("M62 56 L62 88 C54 104, 108 110, 124 118 S148 126, 152 128", 0.0),
        ("M179 56 L179 92 C173 102, 190 110, 186 118 S183 124, 182 127", 0.8),
        ("M296 56 L296 88 C304 106, 260 112, 238 120 S212 126, 208 128", 1.6),
    ]

    public var body: some View {
        let still = reduceMotion || motionDisabled || ambientPaused
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: still)) { context in
            let t = still ? 0 : context.date.timeIntervalSinceReferenceDate
            ZStack {
                if !debugHide.contains("cables") {
                    // Trazo base SÓLIDO + máscara vertical de desvanecimiento: el stroke con
                    // gradiente directo era candidato a artefactos de placa en device; la
                    // máscara reproduce el mismo apagado hacia el hero, cable por cable.
                    ZStack {
                        ForEach(Array(Self.cables.enumerated()), id: \.offset) { _, cable in
                            CablePath(d: cable.d)
                                .stroke(tone.opacity(0.45), lineWidth: 1.2)
                        }
                    }
                    .mask {
                        LinearGradient(
                            stops: [
                                .init(color: .black, location: 0),
                                .init(color: .black.opacity(0.15), location: 0.85),
                                .init(color: .clear, location: 1),
                            ],
                            startPoint: .top, endPoint: .bottom)
                    }
                    ForEach(Array(Self.cables.enumerated()), id: \.offset) { _, cable in
                        // El pulso viaja con `trim` (la gramática del sistema para progreso
                        // sobre Shape); congelado queda en el arranque del cable.
                        pulse(cable.d, progress: still
                              ? 0 : LiquidMotion.flowPulseProgress(time: t, delay: cable.delay))
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func pulse(_ d: String, progress: Double) -> some View {
        let len = LiquidMotion.flowPulseLength
        let style = StrokeStyle(lineWidth: 1.6, lineCap: .round)
        // 3 pulsos por cable, equiespaciados. Cada pulso NACE suave bajo su orbe (fade-in
        // corto) y SE APAGA en fade al llegar al final, en vez de cortarse o teletransportarse
        // al inicio (pedido del dueño, sesión /inject).
        ZStack {
            ForEach(0..<3, id: \.self) { k in
                let p = (progress + Double(k) / 3).truncatingRemainder(dividingBy: 1)
                let fadeIn = min(1, p / 0.08)
                let fadeOut = min(1, max(0, (1 - p - len) / 0.18))
                CablePath(d: d)
                    .trim(from: p, to: min(1, p + len))
                    .stroke(tone, style: style)
                    .opacity(0.75 * fadeIn * fadeOut)
            }
        }
    }
}

/// Un cable del viewBox 358 × 178, CENTRADO sin escalar en x: los orbes van con anchos y
/// separación FIJOS (64 + gap 53 → centros a ±117 del medio), así que en pantallas más
/// anchas que 402 pt un escalado proporcional desalineaba los cables exteriores de sus
/// orbes (~12 pt en un Pro Max). Centrar el dibujo mantiene cada cable naciendo EXACTO
/// bajo su orbe en cualquier ancho.
private struct CablePath: Shape {
    let d: String

    func path(in rect: CGRect) -> Path {
        SVGPathData.path(d).applying(
            CGAffineTransform(translationX: rect.minX + (rect.width - 358) / 2,
                              y: rect.minY))
    }
}

// MARK: Hero de veredicto (Hoy)

/// El veredicto matinal: display/xl centrado con la palabra clave en el tono del estado
/// (verde para «dale», atención para los matices) y el subtítulo cuerpo a 8 pt.
/// `confianza` es el tether honesto ya localizado («Confianza: 12 de 21 noches»), opcional.
public struct LiquidHeroVeredicto: View {
    private let title: String
    private let highlight: String
    private let highlightTone: Color
    private let subtitle: String
    private let confianza: String?

    /// `highlight` debe aparecer dentro de `title` (se pinta su última ocurrencia).
    public init(title: String, highlight: String,
                highlightTone: Color = LiquidColor.verdePrimario,
                subtitle: String, confianza: String? = nil) {
        self.title = title
        self.highlight = highlight
        self.highlightTone = highlightTone
        self.subtitle = subtitle
        self.confianza = confianza
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
            LiquidHeroSubtitle(subtitle: subtitle, confianza: confianza)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isHeader)
        .accessibilityLabel(Self.a11yLabel(title: title, subtitle: subtitle, confianza: confianza))
    }

    /// El label combinado que lee VoiceOver (testeable en frío). No duplica puntuación
    /// cuando una parte ya cierra su frase.
    static func a11yLabel(title: String, subtitle: String, confianza: String?) -> String {
        let flat = title.replacingOccurrences(of: "\n", with: " ")
        return ([flat, subtitle] + (confianza.map { [$0] } ?? [])).reduce("") { acc, part in
            acc.isEmpty ? part : acc + (acc.hasSuffix(".") ? " " : ". ") + part
        }
    }

    private func lineText(_ line: String) -> Text {
        if let range = line.range(of: highlight, options: .backwards) {
            return Text(line[..<range.lowerBound]).liquidDisplayXL()
                .foregroundStyle(LiquidColor.tinta900)
                + Text(line[range]).liquidDisplayXL()
                .foregroundStyle(highlightTone)
                + Text(line[range.upperBound...]).liquidDisplayXL()
                .foregroundStyle(LiquidColor.tinta900)
        }
        return Text(line).liquidDisplayXL().foregroundStyle(LiquidColor.tinta900)
    }
}

/// El héroe demotado (lectura de día FER-1033 / fallback de sueño): display/l SIN palabra
/// destacada — la jerarquía baja un escalón porque el dato es menos preciso. El título es
/// texto que se LEE, así que escala con Dynamic Type (relativo a .title2).
public struct LiquidHeroDemotado: View {
    private let kicker: String?
    private let title: String
    private let subtitle: String

    public init(kicker: String? = nil, title: String, subtitle: String) {
        self.kicker = kicker
        self.title = title
        self.subtitle = subtitle
    }

    public var body: some View {
        VStack(spacing: LiquidSpace.s200) {
            if let kicker {
                Text(kicker).liquidLabel().foregroundStyle(LiquidColor.tinta500)
            }
            Text(title)
                .font(InstrumentoType.grotesk(30, weight: .bold, relativeTo: .title2))
                .tracking(LiquidType.displayLTracking)
                .foregroundStyle(LiquidColor.tinta900)
                .multilineTextAlignment(.center)
            LiquidHeroSubtitle(subtitle: subtitle, confianza: nil)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isHeader)
        .accessibilityLabel(
            LiquidHeroVeredicto.a11yLabel(
                title: kicker.map { "\($0). \(title)" } ?? title,
                subtitle: subtitle, confianza: nil))
    }
}

/// Subtítulo del héroe + tether de confianza — texto de lectura: escala con Dynamic Type.
private struct LiquidHeroSubtitle: View {
    let subtitle: String
    let confianza: String?
    @ScaledMetric(relativeTo: .footnote) private var cuerpoSize: CGFloat = 12.5
    @ScaledMetric(relativeTo: .caption2) private var captionSize: CGFloat = 9

    var body: some View {
        VStack(spacing: LiquidSpace.s100) {
            Text(subtitle)
                .font(.system(size: cuerpoSize))
                .foregroundStyle(LiquidColor.tinta700)
                .multilineTextAlignment(.center)
            if let confianza {
                Text(confianza)
                    .font(InstrumentoType.grotesk(captionSize, weight: .medium))
                    .foregroundStyle(LiquidColor.tinta500)
            }
        }
    }
}

#if DEBUG
#Preview("Liquid · Patrones") {
    ZStack {
        LiquidAmbientBackground.hoy()
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
