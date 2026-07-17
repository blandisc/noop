import SwiftUI

// MARK: - GraficaRangos — el historial de las cuatro pantallas de detalle (FER-856/857)
//
// La gráfica de historial estandarizada del handoff «Detalle de Tendencias Final», con dos modos que
// comparten la MISMA gráfica (nunca desaparece al cambiar):
//
//   · MEDIA  — línea 2.2px del hue + área con gradiente hue→0 (`recFade`) + punto final r4 + grid en
//              los ticks + wash opcional (banda óptima al 10%) + línea de referencia punteada opcional
//              («tu base · N»). Debajo, su `BarraAncla` opcional.
//   · RANGOS — la misma serie como puntos coloreados por su banda sobre una línea gris tenue; washes
//              de banda al 8%. Debajo, carriles tocables: tocar uno resalta sus puntos (100% r3.5, el
//              resto 0.25 r2.5; su wash sube a 16%, los otros bajan a 3%) y marca la fila; re-tocar
//              limpia; cambiar a MEDIA resetea la selección.
//
// Cabecera: valor de media del periodo (Grotesk 20/700 en el hue) + nota + Δ% opcional (color solo
// con valencia) + `CompactTrendToggle`. El estado (`mode` + `activeLane`) vive aquí dentro; el
// periodo lo recalcula el caller (PeriodSelector externo) pasando `points` nuevos.
//
// Copy: todo llega localizado desde la app (el paquete no carga catálogo).

public struct GraficaRangos: View {

    /// Una banda/carril del modo RANGOS. `lo == nil` = abierta por abajo; `hi == nil` = abierta por
    /// arriba. Intervalo half-open `[lo, hi)`, como `MetricLevels`.
    public struct Banda {
        public let label: String
        public let lo: Double?
        public let hi: Double?
        public let color: Color
        /// El rango legible («70–88», «≥ 88»).
        public let range: String

        public init(label: String, lo: Double?, hi: Double?, color: Color, range: String) {
            self.label = label; self.lo = lo; self.hi = hi; self.color = color; self.range = range
        }

        func contains(_ v: Double) -> Bool {
            (lo == nil || v >= lo!) && (hi == nil || v < hi!)
        }
    }

    /// Un tick horizontal del eje Y (línea de grid + label a la izquierda).
    public struct Tick {
        public let v: Double
        public let label: String
        public init(v: Double, label: String) { self.v = v; self.label = label }
    }

    /// El wash opcional del modo MEDIA (la banda óptima al 10% del hue).
    public struct Wash {
        public let lo: Double
        public let hi: Double
        public let label: String?
        public init(lo: Double, hi: Double, label: String? = nil) {
            self.lo = lo; self.hi = hi; self.label = label
        }
    }

    /// La línea de referencia punteada opcional («tu base · 72»).
    public struct RefLine {
        public let v: Double
        public let label: String?
        public init(v: Double, label: String? = nil) { self.v = v; self.label = label }
    }

    private let points: [Double]
    private let bands: [Banda]
    private let ticks: [Tick]
    private let wash: Wash?
    private let refLine: RefLine?
    private let hue: Color
    private let ymin: Double
    private let ymax: Double
    private let startLabel: String
    private let endLabel: String
    private let mediaValue: String
    private let mediaNote: String
    private let mediaDelta: String?
    private let deltaColor: Color?
    /// Sufijo de conteo de los carriles («d» días / «n» noches), ya localizado.
    private let countUnit: String
    private let anchorMedia: String?
    private let anchorRangos: String?
    /// Scrub opt-in (rev 2026-07-10b): arrastrar sobre la gráfica lee cada punto con una regla
    /// vertical + anillo del color de su banda + chip negro «valor · fecha». Al soltar se limpia.
    private let scrub: Bool
    /// Fecha legible por punto («10 jun»), paralela a `points`. Solo se usa con `scrub`.
    private let labels: [String]
    /// Formato del valor en el chip del scrub (default: entero/2 decimales según magnitud).
    private let fmt: (Double) -> String
    private let theme: InstrumentoTheme

    @State private var mode: TrendMode = .media
    @State private var activeLane: Int? = nil
    @State private var scrubIndex: Int? = nil

    public init(points: [Double], bands: [Banda], ticks: [Tick],
                wash: Wash? = nil, refLine: RefLine? = nil,
                hue: Color, ymin: Double, ymax: Double,
                startLabel: String, endLabel: String,
                mediaValue: String, mediaNote: String,
                mediaDelta: String? = nil, deltaColor: Color? = nil,
                countUnit: String = "d",
                anchorMedia: String? = nil, anchorRangos: String? = nil,
                scrub: Bool = false, labels: [String] = [],
                fmt: ((Double) -> String)? = nil,
                theme: InstrumentoTheme) {
        self.points = points; self.bands = bands; self.ticks = ticks
        self.wash = wash; self.refLine = refLine
        self.hue = hue; self.ymin = ymin; self.ymax = ymax
        self.startLabel = startLabel; self.endLabel = endLabel
        self.mediaValue = mediaValue; self.mediaNote = mediaNote
        self.mediaDelta = mediaDelta; self.deltaColor = deltaColor
        self.countUnit = countUnit
        self.anchorMedia = anchorMedia; self.anchorRangos = anchorRangos
        self.scrub = scrub; self.labels = labels
        self.fmt = fmt ?? { v in
            v == v.rounded() ? "\(Int(v))" : String(format: "%.2f", v)
        }
        self.theme = theme
    }

    /// VoiceOver value: scrubbed point if active, else the last point. (FER-977)
    private var accessibilityValueText: String {
        if let i = scrubIndex, points.indices.contains(i) {
            let v = fmt(points[i])
            if labels.indices.contains(i) { return "\(v), \(labels[i])" }
            return v
        }
        guard let last = points.last else { return "No data" }
        let v = fmt(last)
        if let label = labels.last { return "\(v), \(label)" }
        return v
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            chart
                .frame(height: 178)
                .accessibilityLabel(Text(verbatim: "\(mediaValue) \(mediaNote)"))
                .accessibilityValue(Text(accessibilityValueText))
            if mode == .media, let anchorMedia {
                BarraAncla(anchorMedia, color: hue, theme: theme)
            }
            if mode == .rangos {
                lanes
            }
        }
        .onChange(of: mode) { _, new in
            // Cambiar a MEDIA resetea la selección de carril (contrato del handoff).
            if new == .media { activeLane = nil }
        }
    }

    // MARK: Cabecera — media del periodo + Δ% + toggle

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            (Text(verbatim: mediaValue)
                .font(InstrumentoType.groteskNumber(20, weight: .bold))
                .foregroundColor(hue)
             + Text(verbatim: " · \(mediaNote)")
                .font(StrandFont.scaled(12))
                .foregroundColor(theme.inkTertiary)
             + Text(verbatim: mediaDelta.map { " \($0)" } ?? "")
                .font(InstrumentoType.grotesk(12, weight: .semibold))
                .foregroundColor(deltaColor ?? theme.inkSecondary))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 8)
            CompactTrendToggle(mode: $mode, theme: theme)
        }
    }

    // MARK: Gráfica (geometría del mock: plot x 26→ancho, y 20→152 de 178; piso 1.2px + fechas)

    private static let plotTop: CGFloat = 20
    private static let floorY: CGFloat = 152
    private static let gutter: CGFloat = 26

    private func x(_ i: Int, _ w: CGFloat) -> CGFloat {
        let n = points.count
        guard n > 1 else { return (Self.gutter + w) / 2 }
        return Self.gutter + CGFloat(i) * (w - Self.gutter) / CGFloat(n - 1)
    }

    private func y(_ v: Double) -> CGFloat {
        let clamped = Swift.max(ymin, Swift.min(ymax, v))
        let f = (clamped - ymin) / (ymax - ymin)
        return Self.floorY - CGFloat(f) * (Self.floorY - Self.plotTop)
    }

    private var chart: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .topLeading) {
                if mode == .rangos {
                    bandWashes(w)
                } else if let wash {
                    washRect(wash, w)
                }
                gridAndRef(w)
                if mode == .media {
                    mediaSeries(w)
                } else {
                    rangosSeries(w)
                }
                floorAndDates(w)
                if let i = scrubIndex, points.indices.contains(i) {
                    scrubOverlay(i, w)
                }
            }
            .contentShape(Rectangle())
            .gesture(scrub ? scrubGesture(w) : nil)
        }
    }

    // MARK: Scrub — regla + anillo por banda + chip negro (rev 2026-07-10b)

    /// El overlay del scrub: regla vertical 1px tinta 0.35 (de y=16 al piso), anillo r5 con borde
    /// 2.5px del color de la banda del punto, y chip negro (radio 8, alto 16) con «valor · fecha»
    /// en Grotesk 9.5/600 papel. El chip FLOTA junto al punto: por defecto arriba del anillo y, cuando
    /// el punto está muy alto (el chip se saldría por el techo del plot), salta abajo — así nunca se
    /// encaballa con el anillo ni se recorta. El chip es SIEMPRE negro: la valencia vive solo en el
    /// anillo.
    private static let scrubChipH: CGFloat = 16
    @ViewBuilder private func scrubOverlay(_ i: Int, _ w: CGFloat) -> some View {
        let px = x(i, w)
        let py = y(points[i])
        let ringColor = bandIndex(points[i]).map { bands[$0].color } ?? hue
        let text = labels.indices.contains(i) ? "\(fmt(points[i])) · \(labels[i])" : fmt(points[i])

        Rectangle()
            .fill(theme.ink.opacity(0.35))
            .frame(width: 1, height: Self.floorY - 16)
            .offset(x: px - 0.5, y: 16)
        Circle()
            .fill(theme.paper)
            .overlay(Circle().strokeBorder(ringColor, lineWidth: 2.5))
            .frame(width: 10, height: 10)
            .offset(x: px - 5, y: py - 5)
        // Ancho estimado por caracteres (mismo truco del mock) para poder clampear el chip al plot.
        let chipW = CGFloat(text.count) * 5.6 + 16
        let chipX = Swift.max(Self.gutter, Swift.min(w - chipW, px - chipW / 2))
        // Vertical: arriba del anillo (gap 8); si eso lo sacaría del techo, va abajo del anillo.
        let gap: CGFloat = 8
        let aboveY = py - gap - Self.scrubChipH
        let chipY = aboveY >= 0 ? aboveY : Swift.min(Self.floorY - Self.scrubChipH, py + gap)
        Text(verbatim: text)
            .font(InstrumentoType.groteskNumber(9.5, weight: .semibold))
            .foregroundStyle(theme.paper)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 6)
            .frame(width: chipW, height: Self.scrubChipH)
            .background(theme.ink, in: Capsule(style: .continuous))
            .offset(x: chipX, y: chipY)
            .accessibilityHidden(true)
    }

    /// El gesto de scrub: drag con `minimumDistance: 0` sobre la gráfica; snap al punto más
    /// cercano (`ChartScrubMath`), háptica al cambiar de punto, y limpia al soltar.
    private func scrubGesture(_ w: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                let plotW = Swift.max(1, w - Self.gutter)
                let i = ChartScrubMath.nearestIndex(toX: g.location.x - Self.gutter,
                                                    count: points.count, width: plotW)
                if let i, i != scrubIndex {
                    scrubIndex = i
                    ChartHaptics.datumChanged()
                }
            }
            .onEnded { _ in scrubIndex = nil }
    }

    /// Los washes de banda del modo RANGOS: 8% en reposo; con carril activo, 16% el suyo y 3% el resto.
    private func bandWashes(_ w: CGFloat) -> some View {
        ForEach(Array(bands.enumerated()), id: \.offset) { i, b in
            let top = y(b.hi ?? ymax)
            let bottom = y(b.lo ?? ymin)
            Rectangle()
                .fill(b.color)
                .opacity(activeLane == nil ? 0.08 : (activeLane == i ? 0.16 : 0.03))
                .frame(width: Swift.max(0, w - Self.gutter), height: Swift.max(0, bottom - top))
                .offset(x: Self.gutter, y: top)
        }
    }

    /// El wash del modo MEDIA (banda óptima al 10% del hue) + su label opcional.
    private func washRect(_ wash: Wash, _ w: CGFloat) -> some View {
        let top = y(wash.hi)
        let bottom = y(wash.lo)
        return ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(hue)
                .opacity(0.10)
                .frame(width: Swift.max(0, w - Self.gutter), height: Swift.max(0, bottom - top))
                .offset(x: Self.gutter, y: top)
            if let label = wash.label {
                Text(label)
                    .font(StrandFont.scaled(9))
                    .foregroundStyle(theme.inkTertiary)
                    .offset(x: Self.gutter + 4, y: top + 3)
            }
        }
    }

    /// Grid en los ticks (+ labels de eje, Grotesk 9) y la línea de referencia punteada.
    private func gridAndRef(_ w: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(ticks.enumerated()), id: \.offset) { _, t in
                Rectangle()
                    .fill(theme.hairline)
                    .frame(width: Swift.max(0, w - Self.gutter), height: 1)
                    .offset(x: Self.gutter, y: y(t.v) - 0.5)
                Text(t.label)
                    .font(InstrumentoType.grotesk(9))
                    .monospacedDigit()
                    .foregroundStyle(theme.inkTertiary)
                    .offset(x: 0, y: y(t.v) - 5)
            }
            if let ref = refLine {
                Line(from: CGPoint(x: Self.gutter, y: y(ref.v)),
                     to: CGPoint(x: w, y: y(ref.v)))
                    .stroke(theme.baseMark, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                if let label = ref.label {
                    Text(label)
                        .font(StrandFont.scaled(9))
                        .foregroundStyle(theme.inkTertiary)
                        .offset(x: Self.gutter + 4, y: y(ref.v) - 14)
                }
            }
        }
    }

    /// Modo MEDIA: área con gradiente hue→0 (recFade) + línea 2.2px + punto final r4.
    @ViewBuilder private func mediaSeries(_ w: CGFloat) -> some View {
        if points.count > 1 {
            let line = linePath(w)
            var area = line
            let _ = area.addLine(to: CGPoint(x: x(points.count - 1, w), y: Self.floorY))
            let _ = area.addLine(to: CGPoint(x: x(0, w), y: Self.floorY))
            let _ = area.closeSubpath()

            // Área con gradiente hue 0.26→0 (spec del handoff; constante del componente, no del call site).
            area
                .fill(LinearGradient(colors: [hue.opacity(0.26), hue.opacity(0)],
                                     startPoint: .top, endPoint: .bottom))
                .recFade()
            line
                .stroke(hue, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
            Circle()
                .fill(theme.paper)
                .overlay(Circle().strokeBorder(hue, lineWidth: 2))
                .frame(width: 8, height: 8)
                .offset(x: x(points.count - 1, w) - 4, y: y(points[points.count - 1]) - 4)
        }
    }

    /// Modo RANGOS: la MISMA serie como línea gris tenue + puntos coloreados por su banda.
    @ViewBuilder private func rangosSeries(_ w: CGFloat) -> some View {
        if points.count > 1 {
            linePath(w)
                .stroke(theme.baseMark.opacity(0.55),
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            ForEach(Array(points.enumerated()), id: \.offset) { i, v in
                let bi = bandIndex(v)
                let hot = activeLane == nil || activeLane == bi
                let r: CGFloat = hot ? 3.5 : 2.5
                Circle()
                    .fill(bi.map { bands[$0].color } ?? theme.ink)
                    .opacity(hot ? 1 : 0.25)
                    .frame(width: r * 2, height: r * 2)
                    .offset(x: x(i, w) - r, y: y(v) - r)
            }
        }
    }

    /// El piso 1.2px + las fechas del eje X (Grotesk 9): inicio/fin en los extremos y, cuando hay
    /// `labels` suficientes (pantallas con scrub), un par de fechas intermedias equiespaciadas para
    /// dar más referencia temporal sin saturar.
    private func floorAndDates(_ w: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(theme.hairlineStrong)
                .frame(width: Swift.max(0, w - Self.gutter), height: 1.2)
                .offset(x: Self.gutter, y: Self.floorY)
            Text(startLabel)
                .font(InstrumentoType.grotesk(9))
                .foregroundStyle(theme.inkTertiary)
                .offset(x: Self.gutter, y: Self.floorY + 7)
            // Fechas intermedias: hasta 3 marcas interiores equiespaciadas, centradas en su punto y
            // clampeadas al plot (ancho estimado por caracteres, como el chip del scrub) para que no
            // choquen con los extremos.
            ForEach(interiorDateTicks, id: \.i) { tick in
                let cx = x(tick.i, w)
                let halfW = CGFloat(tick.text.count) * 2.7
                Text(tick.text)
                    .font(InstrumentoType.grotesk(9))
                    .foregroundStyle(theme.inkTertiary)
                    .fixedSize()
                    .offset(x: Swift.max(Self.gutter, Swift.min(w - halfW * 2, cx - halfW)),
                            y: Self.floorY + 7)
            }
            Text(endLabel)
                .font(InstrumentoType.grotesk(9))
                .foregroundStyle(theme.inkTertiary)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .offset(y: Self.floorY + 7)
        }
    }

    /// Índices (+ texto) de las fechas intermedias del eje X. Vacío cuando no hay `labels` o la serie
    /// es corta; si no, 3 marcas a ¼, ½ y ¾ de la serie (sin repetir los extremos ni entre sí).
    private var interiorDateTicks: [(i: Int, text: String)] {
        let n = points.count
        guard labels.count == n, n >= 8 else { return [] }
        let raw = [0.25, 0.5, 0.75].map { Int((Double(n - 1) * $0).rounded()) }
        var seen = Set([0, n - 1])
        var out: [(i: Int, text: String)] = []
        for i in raw where !seen.contains(i) && labels.indices.contains(i) {
            seen.insert(i)
            out.append((i, labels[i]))
        }
        return out
    }

    private func linePath(_ w: CGFloat) -> Path {
        Path { p in
            for (i, v) in points.enumerated() {
                let pt = CGPoint(x: x(i, w), y: y(v))
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
        }
    }

    private func bandIndex(_ v: Double) -> Int? {
        bands.firstIndex { $0.contains(v) }
    }

    // MARK: Carriles (modo RANGOS)

    private var lanes: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(bands.enumerated()), id: \.offset) { i, b in
                laneRow(i, b)
            }
            if let anchorRangos {
                BarraAncla(anchorRangos, color: hue, theme: theme)
                    .padding(.top, 8)
            }
        }
    }

    private func laneRow(_ i: Int, _ b: Banda) -> some View {
        let active = activeLane == i
        let count = points.filter { b.contains($0) }.count
        return Button {
            withAnimation(StrandMotion.interactive) {
                activeLane = active ? nil : i
            }
        } label: {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(b.color)
                    .frame(width: 9, height: 9)
                Text(b.label)
                    .font(StrandFont.scaled(14, weight: active ? .semibold : .regular))
                    .foregroundStyle(active ? theme.ink : theme.inkSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(b.range)
                    .font(InstrumentoType.groteskNumber(12, weight: .regular))
                    .foregroundStyle(theme.inkTertiary)
                Text(verbatim: "\(count) \(countUnit)")
                    .font(InstrumentoType.groteskNumber(12, weight: .semibold))
                    .foregroundStyle(active ? b.color : theme.inkSecondary)
                    .frame(width: 44, alignment: .trailing)
            }
            .padding(.vertical, 9)
            .padding(.horizontal, 8)
            .background(active ? theme.ink.opacity(0.05) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

// MARK: - Line shape helper

private struct Line: Shape {
    let from: CGPoint
    let to: CGPoint
    init(from: CGPoint, to: CGPoint) { self.from = from; self.to = to }
    func path(in rect: CGRect) -> Path {
        Path { p in p.move(to: from); p.addLine(to: to) }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("GraficaRangos · recuperación") {
    let t = InstrumentoTheme.base
    GraficaRangos(
        points: [62, 55, 48, 71, 80, 67, 73, 58, 84, 70, 66, 88, 74, 72, 78],
        bands: [
            .init(label: "Pleno", lo: 88, hi: nil, color: t.verdictDeep, range: "≥ 88"),
            .init(label: "A punto", lo: 70, hi: 88, color: t.verdict, range: "70–88"),
            .init(label: "Moderado", lo: 50, hi: 70, color: t.warning, range: "50–70"),
            .init(label: "Bajo", lo: 25, hi: 50, color: t.critical, range: "25–50"),
            .init(label: "Agotado", lo: nil, hi: 25, color: t.criticalDeep, range: "< 25"),
        ],
        ticks: [.init(v: 88, label: "88"), .init(v: 70, label: "70"),
                .init(v: 50, label: "50"), .init(v: 25, label: "25")],
        wash: .init(lo: 70, hi: 88),
        refLine: .init(v: 72, label: "tu base · 72"),
        hue: t.verdict, ymin: 20, ymax: 95,
        startLabel: "jun 6", endLabel: "jul 6",
        mediaValue: "A punto", mediaNote: "tu banda típica del mes", mediaDelta: "+4%",
        deltaColor: t.verdictDeep,
        anchorRangos: "Cuántos días del periodo cayeron en cada banda. Toca una para ver sus días en la gráfica.",
        scrub: true,
        labels: ["10 jun", "12 jun", "14 jun", "16 jun", "18 jun", "20 jun", "22 jun", "24 jun",
                 "26 jun", "28 jun", "30 jun", "2 jul", "4 jul", "6 jul", "8 jul"],
        theme: t)
        .padding(20)
        .background(t.paper)
}
#endif
