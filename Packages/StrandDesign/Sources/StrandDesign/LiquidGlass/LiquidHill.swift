import SwiftUI

// MARK: - Liquid Glass · La colina de carga (hoja de Carga · migración FER-sheet-carga)
//
// El instrumento firma de la hoja de Carga, portado del `LoadHillView` de «Instrumento» al
// sistema Liquid: una curva tipo colina sobre la escala 0…`maximo`, con el punto del día,
// un readout de vidrio anclado (`LiquidScrubPopup`) y drag horizontal que explora cada zona.
// Subes la cuesta → la cresta es tu equilibrio → la bajada es la sobrecarga. Al soltar, vuelve
// a HOY. NO reusa `LiquidGraficaNiveles`: es un instrumento distinto (posición-en-escala, no
// serie de tiempo).
//
// EXCEPCIÓN DE COLOR SANCIONADA (decisión del dueño, 2026-07-24): la colina conserva su
// lenguaje de zonas coloreadas (cuesta y cresta en verde, descenso en ámbar, caída en rojo),
// rompiendo a propósito la regla «color solo en el dato» del DNA. Es la identidad del
// instrumento; documentado en docs/design-system/LIQUID-GLASS.md.
//
// Contrato D3: los colores llegan RESUELTOS por el caller (en `Zona.color`) y los strings YA
// localizados. El DS no conoce el motor ni los umbrales — el caller pasa las zonas leídas de
// `ReadinessEngine`. El formato del número es locale-neutral (`%.2f`, mismo criterio que
// `LiquidCargaEscala`): el número es dato, no copy.

public struct LiquidHill: View {

    /// Una zona de la escala, con su color YA resuelto y sus frases YA localizadas. El caller
    /// las pasa ordenadas y cubriendo 0…`maximo` sin huecos.
    public struct Zona: Sendable, Equatable {
        public let lo: Double
        public let hi: Double
        /// Color pleno de la zona (el que toma el punto/readout/ancla cuando el dato cae aquí).
        public let color: Color
        /// La palabra de la zona para el readout, MAYÚSCULAS ya localizada («EQUILIBRIO»).
        public let etiqueta: String
        /// La frase de la barra-ancla, ya localizada.
        public let ancla: String

        public init(lo: Double, hi: Double, color: Color, etiqueta: String, ancla: String) {
            self.lo = lo
            self.hi = hi
            self.color = color
            self.etiqueta = etiqueta
            self.ancla = ancla
        }

        func contiene(_ v: Double) -> Bool { v >= lo && v < hi }
    }

    private let razon: Double?
    private let zonas: [Zona]
    private let maximo: Double
    private let referencia: Double
    private let ticks: [LiquidCargaEscala.Tick]
    private let titulo: String
    private let hint: String
    private let hoyEtiqueta: String
    private let calibrando: Bool
    private let calibrandoTitulo: String
    private let calibrandoAncla: String
    private let progreso: (hechas: Int, necesarias: Int)?
    private let a11yTitulo: String
    /// Compone el value de VoiceOver: `(razón, etiqueta de zona) -> «Hoy: 1.03, en equilibrio.»`.
    private let a11yValor: (Double, String) -> String

    /// `nil` = mostrando HOY; non-nil = ratio bajo el dedo.
    @State private var scrubRatio: Double? = nil
    /// El ancho MEDIDO del readout de vidrio, para clampearlo dentro del plot sin cortarlo
    /// en los extremos (el popup mide `fixedSize` y crece con el texto/Dynamic Type; una
    /// estimación fija lo recortaba con «HOY · 1.62 · SOBRECARGA» pegado a un borde).
    @State private var readoutW: CGFloat = 96
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.liquidMotionDisabled) private var motionDisabled

    /// Alto fijo del plot (paridad con el mock del `LoadHillView` original).
    private let chartH: CGFloat = 132
    /// Ancho del path del mock; la x se escala al ancho vivo.
    private let mockW: CGFloat = 320

    public init(
        razon: Double?,
        zonas: [Zona],
        maximo: Double = 2.0,
        referencia: Double = 1.0,
        ticks: [LiquidCargaEscala.Tick] = LiquidCargaEscala.ticksPorDefecto,
        titulo: String,
        hint: String,
        hoyEtiqueta: String,
        calibrando: Bool = false,
        calibrandoTitulo: String = "",
        calibrandoAncla: String = "",
        progreso: (hechas: Int, necesarias: Int)? = nil,
        a11yTitulo: String,
        a11yValor: @escaping (Double, String) -> String
    ) {
        self.razon = razon
        self.zonas = zonas
        self.maximo = maximo
        self.referencia = referencia
        self.ticks = ticks
        self.titulo = titulo
        self.hint = hint
        self.hoyEtiqueta = hoyEtiqueta
        self.calibrando = calibrando
        self.calibrandoTitulo = calibrandoTitulo
        self.calibrandoAncla = calibrandoAncla
        self.progreso = progreso
        self.a11yTitulo = a11yTitulo
        self.a11yValor = a11yValor
    }

    // MARK: Estado derivado

    private var esCalibrando: Bool { calibrando || razon == nil }
    private var displayRatio: Double { scrubRatio ?? (razon ?? 0) }
    private var isShowingToday: Bool { scrubRatio == nil }
    private var displayZona: Zona? {
        zonas.first { $0.contiene(displayRatio) } ?? zonas.last
    }
    /// La zona que se ilumina a color pleno (la cresta): la que contiene «tu costumbre».
    private func esCresta(_ z: Zona) -> Bool { z.contiene(referencia) }

    private static func fmt(_ v: Double) -> String { String(format: "%.2f", v) }

    // MARK: Cuerpo

    public var body: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s300) {
            cabecera
            if esCalibrando {
                colinaDormida
                if !calibrandoAncla.isEmpty {
                    Text(verbatim: calibrandoAncla)
                        .font(LiquidType.captionLectura)
                        .foregroundStyle(LiquidColor.tinta500)
                }
                if let progreso {
                    barraProgreso(progreso)
                }
            } else {
                colinaViva
                if let z = displayZona {
                    ancla(z)
                }
            }
        }
        .padding(LiquidSpace.s400)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(.superficie)
    }

    // MARK: Cabecera

    private var cabecera: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(verbatim: esCalibrando ? calibrandoTitulo : titulo)
                .font(LiquidType.cargaLabel).tracking(LiquidType.cargaLabelTracking)
                .textCase(.uppercase)
                .foregroundStyle(esCalibrando ? LiquidColor.tinta500 : LiquidColor.tinta700)
            Spacer(minLength: LiquidSpace.s200)
            if !esCalibrando {
                Text(verbatim: hint)
                    .font(LiquidType.microEstado)
                    .foregroundStyle(LiquidColor.tinta500)
            }
        }
    }

    // MARK: La colina viva (con dato + scrub)

    private var colinaViva: some View {
        GeometryReader { g in
            let w = max(g.size.width, 1)
            let r = displayRatio
            let hx = xForRatio(r, width: w)
            let hy = hillY(atX: hx, width: w) - 6
            let zona = displayZona
            let color = zona?.color ?? LiquidColor.tinta500

            ZStack(alignment: .topLeading) {
                // Área + trazo de la colina (chrome en tinta, nunca color de dato).
                hillAreaPath(width: w)
                    .fill(LinearGradient(colors: [LiquidColor.tinta7, LiquidColor.tinta7.opacity(0)],
                                         startPoint: .top, endPoint: .bottom))
                hillLinePath(width: w)
                    .stroke(LiquidColor.tinta700,
                            style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                // Barras de zona (la cresta a color pleno; el resto al 35 %).
                zoneBars(width: w)

                // Ticks en los cortes del motor.
                ForEach(ticks.indices, id: \.self) { i in
                    let tx = xForRatio(ticks[i].valor, width: w)
                    Text(verbatim: ticks[i].etiqueta)
                        .font(LiquidType.caption)
                        .foregroundStyle(LiquidColor.tinta500)
                        .position(x: tx, y: 120)
                }

                // Fantasma de HOY mientras se explora.
                if !isShowingToday, let acwr = razon {
                    let gx = xForRatio(acwr, width: w)
                    let gy = hillY(atX: gx, width: w) - 6
                    Circle()
                        .strokeBorder(LiquidColor.tinta500, lineWidth: 1.2)
                        .frame(width: LiquidChart.puntoDatoRadio * 2,
                               height: LiquidChart.puntoDatoRadio * 2)
                        .position(x: gx, y: gy)
                }

                // Regla vertical del punto a la franja (paridad scrub Liquid, sólida).
                Path { p in
                    p.move(to: CGPoint(x: hx, y: hy + 6))
                    p.addLine(to: CGPoint(x: hx, y: 100))
                }
                .stroke(LiquidColor.tinta900.opacity(LiquidChart.scrubReglaAlfa),
                        style: StrokeStyle(lineWidth: LiquidChart.scrubReglaAncho))

                // Punto del ratio mostrado (anillo de scrub, relleno de papel).
                Circle()
                    .fill(LiquidColor.papelAlto)
                    .overlay(Circle().strokeBorder(color, lineWidth: LiquidChart.scrubAnilloBorde))
                    .frame(width: LiquidChart.scrubAnilloDiametro,
                           height: LiquidChart.scrubAnilloDiametro)
                    .position(x: hx, y: hy)

                // Readout de vidrio anclado arriba del punto (clampeado al ancho).
                readout(w: w, hx: hx, hy: hy, zona: zona, color: color)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        scrubRatio = min(max(ratioForX(value.location.x, width: w), 0), maximo)
                    }
                    .onEnded { _ in
                        if reduceMotion || motionDisabled {
                            scrubRatio = nil
                        } else {
                            withAnimation(LiquidMotion.glassOut(LiquidMotion.quick)) { scrubRatio = nil }
                        }
                    }
            )
        }
        .frame(height: chartH)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: a11yTitulo))
        .accessibilityValue(Text(verbatim: a11yValor(displayRatio, displayZona?.etiqueta ?? "")))
    }

    @ViewBuilder
    private func readout(w: CGFloat, hx: CGFloat, hy: CGFloat, zona: Zona?, color: Color) -> some View {
        let etiqueta = zona?.etiqueta ?? ""
        let valor = isShowingToday
            ? "\(hoyEtiqueta) · \(Self.fmt(displayRatio))"
            : Self.fmt(displayRatio)
        // Clamp con el ancho MEDIDO del popup (no una estimación): así nunca se corta en los
        // bordes, ni con la etiqueta más ancha ni en Dynamic Type grande.
        let mitad = min(readoutW, w) / 2
        let x = min(max(mitad, hx), w - mitad)
        LiquidScrubPopup(valor: valor, fecha: etiqueta, color: color)
            .background(GeometryReader { g in
                Color.clear
                    .onAppear { readoutW = g.size.width }
                    .onChange(of: g.size.width) { _, nuevo in readoutW = nuevo }
            })
            .position(x: x, y: max(14, hy - 26))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    // MARK: La colina dormida (calibrando)

    private var colinaDormida: some View {
        GeometryReader { g in
            let w = max(g.size.width, 1)
            ZStack(alignment: .topLeading) {
                hillLinePath(width: w)
                    .stroke(LiquidColor.tinta500.opacity(0.5),
                            style: StrokeStyle(lineWidth: 2, lineCap: .round,
                                               lineJoin: .round, dash: [4, 5]))
                Capsule()
                    .fill(LiquidColor.tinta7)
                    .frame(height: 4)
                    .position(x: w / 2, y: 102)
                ForEach(ticks.indices, id: \.self) { i in
                    let tx = xForRatio(ticks[i].valor, width: w)
                    Text(verbatim: ticks[i].etiqueta)
                        .font(LiquidType.caption)
                        .foregroundStyle(LiquidColor.tinta500.opacity(0.6))
                        .position(x: tx, y: 120)
                }
            }
        }
        .frame(height: chartH)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: a11yTitulo))
        .accessibilityValue(Text(verbatim: calibrandoTitulo))
    }

    private func barraProgreso(_ p: (hechas: Int, necesarias: Int)) -> some View {
        GeometryReader { g in
            let frac = p.necesarias > 0 ? min(1, max(0, Double(p.hechas) / Double(p.necesarias))) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(LiquidColor.tinta7)
                Capsule().fill(LiquidColor.tinta500)
                    .frame(width: g.size.width * frac)
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }

    // MARK: Ancla

    private func ancla(_ z: Zona) -> some View {
        HStack(alignment: .top, spacing: LiquidSpace.s200) {
            Capsule()
                .fill(z.color)
                .frame(width: 3)
            Text(verbatim: z.ancla)
                .font(LiquidType.captionLectura)
                .foregroundStyle(LiquidColor.tinta700)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Mapeo x ↔ ratio

    private func xForRatio(_ r: Double, width w: CGFloat) -> CGFloat {
        CGFloat(r / maximo) * w
    }

    private func ratioForX(_ x: CGFloat, width w: CGFloat) -> Double {
        Double(x / w) * maximo
    }

    // MARK: Bezier de la colina (path del mock escalado al ancho vivo)

    /// Mock path: M0 92 C60 90, 100 74, 140 52 C180 30, 240 16, 320 14
    private func hillY(atX x: CGFloat, width w: CGFloat) -> CGFloat {
        let sx = x * (mockW / w)
        var bestY: CGFloat = 92
        var bestDist = CGFloat.greatestFiniteMagnitude
        var t: CGFloat = 0
        while t <= 1 {
            let (x1, y1) = cubic(0, 92, 60, 90, 100, 74, 140, 52, t)
            let d1 = abs(x1 - sx)
            if d1 < bestDist { bestDist = d1; bestY = y1 }
            let (x2, y2) = cubic(140, 52, 180, 30, 240, 16, 320, 14, t)
            let d2 = abs(x2 - sx)
            if d2 < bestDist { bestDist = d2; bestY = y2 }
            t += 0.02
        }
        return bestY
    }

    private func cubic(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat,
                       _ x2: CGFloat, _ y2: CGFloat, _ x3: CGFloat, _ y3: CGFloat,
                       _ t: CGFloat) -> (CGFloat, CGFloat) {
        let u = 1 - t
        let uu = u * u, tt = t * t
        let uuu = uu * u, ttt = tt * t
        let x = uuu * x0 + 3 * uu * t * x1 + 3 * u * tt * x2 + ttt * x3
        let y = uuu * y0 + 3 * uu * t * y1 + 3 * u * tt * y2 + ttt * y3
        return (x, y)
    }

    private func hillLinePath(width w: CGFloat) -> Path {
        let s = w / mockW
        var p = Path()
        p.move(to: CGPoint(x: 0, y: 92))
        p.addCurve(to: CGPoint(x: 140 * s, y: 52),
                   control1: CGPoint(x: 60 * s, y: 90),
                   control2: CGPoint(x: 100 * s, y: 74))
        p.addCurve(to: CGPoint(x: w, y: 14),
                   control1: CGPoint(x: 180 * s, y: 30),
                   control2: CGPoint(x: 240 * s, y: 16))
        return p
    }

    private func hillAreaPath(width w: CGFloat) -> Path {
        var p = hillLinePath(width: w)
        p.addLine(to: CGPoint(x: w, y: 92))
        p.addLine(to: CGPoint(x: 0, y: 92))
        p.closeSubpath()
        return p
    }

    /// Barras de zona bajo el eje: la cresta (la que contiene «tu costumbre») a color pleno;
    /// el resto al 35 %. Posiciones desde los límites de cada zona.
    private func zoneBars(width w: CGFloat) -> some View {
        let gap: CGFloat = 2
        let y: CGFloat = 100
        let h: CGFloat = 4
        return ZStack(alignment: .topLeading) {
            ForEach(zonas.indices, id: \.self) { i in
                let z = zonas[i]
                let x0 = xForRatio(z.lo, width: w)
                let x1 = xForRatio(min(z.hi, maximo), width: w)
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(z.color.opacity(esCresta(z) ? 1 : 0.35))
                    .frame(width: max(0, x1 - x0 - gap), height: h)
                    .offset(x: x0 + gap / 2, y: y)
            }
        }
    }
}

#if DEBUG
private extension LiquidHill {
    /// Fixtures de zonas de carga (colores de la excepción sancionada: cuesta+cresta verdes,
    /// descenso ámbar, caída roja).
    static func zonasCarga() -> [Zona] {
        [
            Zona(lo: 0, hi: 0.8, color: LiquidColor.verdePrimario,
                 etiqueta: "A LA BAJA", ancla: "Menos de lo que tu cuerpo acostumbra: la cuesta."),
            Zona(lo: 0.8, hi: 1.3, color: LiquidColor.verdePrimario,
                 etiqueta: "EQUILIBRIO", ancla: "La cresta: tu equilibrio 0.8 a 1.3."),
            Zona(lo: 1.3, hi: 1.5, color: LiquidColor.atencion,
                 etiqueta: "SUBIENDO", ancla: "Más que lo usual: bajando de la cresta."),
            Zona(lo: 1.5, hi: 2.0, color: LiquidColor.negativo,
                 etiqueta: "SOBRECARGA", ancla: "Bastante por encima de lo usual: la bajada."),
        ]
    }

    static func demo(_ razon: Double?, calibrando: Bool = false) -> LiquidHill {
        LiquidHill(
            razon: razon,
            zonas: zonasCarga(),
            titulo: "LA COLINA",
            hint: "Arrastra para explorar",
            hoyEtiqueta: "HOY",
            calibrando: calibrando,
            calibrandoTitulo: "ARMANDO TU COSTUMBRE",
            calibrandoAncla: "8 de 14 días con esfuerzo registrado.",
            progreso: calibrando ? (8, 14) : nil,
            a11yTitulo: "La colina",
            a11yValor: { r, z in "Hoy: \(String(format: "%.2f", r)), \(z.lowercased())." })
    }
}

#Preview("Liquid · Colina (5 estados)") {
    ScrollView {
        VStack(spacing: LiquidSpace.s550) {
            LiquidHill.demo(1.03)   // equilibrio
            LiquidHill.demo(0.62)   // a la baja
            LiquidHill.demo(1.40)   // subiendo rápido
            LiquidHill.demo(1.62)   // sobrecarga
            LiquidHill.demo(nil, calibrando: true)
        }
        .padding(LiquidSpace.s550)
    }
    .background(LiquidSheetFondo(tone: LiquidColor.verdePrimario))
}
#endif
