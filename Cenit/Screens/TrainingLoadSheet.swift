#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

// MARK: - Carga de entrenamiento — franja en «Hoy» + hoja explicativa (FER-705 · handoff «Carga»)
//
// La carga de entrenamiento (ACWR) entra a «Hoy» como una FRANJA fija bajo las pestañas (visible en
// Señales y Brief) que al tocarla abre esta HOJA. La recuperación mide, la carga guía: son independientes.
// El dato dominante es SIEMPRE la palabra de banda en su color de flag, nunca el ratio pelado — la jerga
// («acute:chronic», ACWR, Gabbett 2016 / Impellizzeri 2020) vive SOLO dentro de «Cómo se calcula».
// Toda la matemática viene de `ReadinessEngine` (umbrales 0.8 / 1.3 / 1.5 intactos); estas vistas solo
// presentan `acwr`, `acwrSeries` y `loadBand`. Tokens únicamente; el tema se pasa explícito (no cruza `.sheet`).

/// Todo lo que la franja, la hoja y la tarjeta de Tendencias dibujan, construido una vez desde el
/// dashboard band-masked (`CuerpoView.loadAll` / `TodayView.recomputeDerived`). `acwr == nil` → calibrando.
struct TrainingLoadModel {
    /// El ratio agudo:crónico de hoy (nil mientras no hay ~2 semanas de esfuerzo).
    let acwr: Double?
    /// El ratio replay por día (viejo → nuevo) para la tarjeta de Tendencias — `ReadinessEngine.acwrSeries` (28).
    let series: [(day: String, value: Double)]
    /// Los días band-masked, para que la hoja recompute la serie por periodo (S/M/3M/6M/1A) y cuente los
    /// carriles sobre los últimos 28 días. Vacío en el fallback (la hoja cae a `series`). No lo usa la franja.
    var days: [DailyMetric] = []

    /// La banda del ratio de hoy — la misma escala `LoadBand` que comparte cada superficie.
    var band: ReadinessEngine.LoadBand? { acwr.map(ReadinessEngine.loadBand(forACWR:)) }
}

/// Wrapper Identifiable para montar la hoja en `.sheet(item:)` (el modelo no es Identifiable).
struct TrainingLoadItem: Identifiable {
    let id = UUID()
    let model: TrainingLoadModel
    /// «Tu patrón» (opcional, solo desde «Hoy»): el texto del hallazgo de carga + a dónde lleva «Ver patrón →».
    var patternText: String? = nil
    var onSeePattern: (() -> Void)? = nil
    /// «Ver más en Tendencias» (opcional, solo desde «Hoy»; redundante desde la propia Tendencias).
    var onSeeTrends: (() -> Void)? = nil
}

// MARK: - La escala de bandas (compartida por la franja y la colina)

/// Los cortes de banda leídos del motor, para que la escala nunca se desfase de `loadBand(forACWR:)`.
private enum LoadScale {
    static let max = 2.0
    static let cuts: [Double] = [ReadinessEngine.acwrSweetSpotLow,
                                 ReadinessEngine.acwrSweetSpotHigh,
                                 ReadinessEngine.acwrSpikeAt]
    /// Los cuatro tramos [lo, hi, banda] sobre la escala 0…2.
    static let bounds: [(lo: Double, hi: Double, band: ReadinessEngine.LoadBand)] = [
        (0, cuts[0], .rampingDown), (cuts[0], cuts[1], .sweetSpot),
        (cuts[1], cuts[2], .buildingFast), (cuts[2], max, .spiking),
    ]
}

// MARK: - Franja de carga (bloque fijo de «Hoy»)

/// La franja de dos filas bajo las pestañas SEÑALES/BRIEF: label + palabra de banda + ratio + chevron,
/// y una escala de 4 cápsulas con el punto de hoy. Tocarla abre la hoja. No respira (no es un dato vivo
/// intradía) y no participa del pull-to-refresh; solo el punto se reposiciona si el ratio cambió al sincronizar.
struct TrainingLoadStrip: View {
    let model: TrainingLoadModel
    var theme: InstrumentoTheme = .base
    let onTap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var band: ReadinessEngine.LoadBand? { model.band }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                labelRow
                scaleRow
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Training load"))
        .accessibilityValue(model.acwr == nil ? Text("Calibrating")
                            : Text(band?.shortLabel ?? ""))
        .accessibilityAddTraits(.isButton)
    }

    private var labelRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text("Load")
                .groteskOverline(small: true)
                .foregroundStyle(theme.inkMuted)
            Spacer(minLength: 8)
            if let band, let acwr = model.acwr {
                Text(band.shortLabel)
                    .font(InstrumentoType.grotesk(10, weight: .bold))
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .foregroundStyle(band.flag.color(theme))
                Text(String(format: "%.2f", acwr))
                    .font(InstrumentoType.groteskNumber(10, weight: .medium))
                    .foregroundStyle(theme.inkMuted)
                    .padding(.leading, 6)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(theme.inkMuted)
                    .padding(.leading, 6)
            } else {
                Text("Calibrating")
                    .font(InstrumentoType.grotesk(10, weight: .bold))
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .foregroundStyle(theme.inkMuted)
                Text(verbatim: "··")
                    .font(InstrumentoType.groteskNumber(10, weight: .medium))
                    .foregroundStyle(theme.inkMuted)
                    .padding(.leading, 6)
            }
        }
    }

    private var scaleRow: some View {
        GeometryReader { g in
            let w = g.size.width
            ZStack(alignment: .topLeading) {
                HStack(spacing: 2) {
                    ForEach(LoadScale.bounds, id: \.lo) { seg in
                        Capsule()
                            .fill(seg.band == band ? seg.band.flag.color(theme) : theme.hairline)
                            .frame(width: max(0, w * (seg.hi - seg.lo) / LoadScale.max - 2), height: 6)
                    }
                }
                .frame(height: 12, alignment: .center)
                if let acwr = model.acwr {
                    let x = min(max(acwr / LoadScale.max, 0.05), 0.95)
                    Circle()
                        .fill(theme.surface)
                        .overlay(Circle().strokeBorder(theme.ink, lineWidth: 3))
                        .frame(width: 12, height: 12)
                        .offset(x: w * x - 6, y: 0)
                        .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.8), value: acwr)
                }
            }
        }
        .frame(height: 12)
    }
}

// MARK: - Hoja «Carga de entrenamiento»

struct TrainingLoadSheet: View {
    let model: TrainingLoadModel
    /// El tema «Instrumento» activo, pasado explícito (las hojas arrancan un environment nuevo). (FER-162)
    var theme: InstrumentoTheme = .base
    /// «Tu patrón» (solo desde «Hoy»): el hallazgo de carga + a dónde lleva «Ver patrón →».
    var patternText: String? = nil
    var onSeePattern: (() -> Void)? = nil
    /// «Ver más en Tendencias» (solo desde «Hoy»).
    var onSeeTrends: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    /// Altura natural medida, para que el detent se ajuste al contenido (patrón de `MetricInfoSheet`).
    @State private var contentHeight: CGFloat = 0
    /// El periodo de la gráfica (S/M/3M/6M/1A). La franja de equilibrio y los carriles no cambian con él.
    @State private var period: LoadPeriod = .week
    /// El carril destacado en la gráfica (por defecto el de hoy); tocarlo re-sombrea la franja y la etiqueta.
    @State private var featured: ReadinessEngine.LoadBand? = nil

    // MARK: Periodo

    private enum LoadPeriod: Int, CaseIterable, Hashable {
        case week, month, quarter, half, year
        /// `lastN` días para recomputar `acwrSeries` en ese periodo.
        var lastN: Int { switch self { case .week: 7; case .month: 30; case .quarter: 90; case .half: 180; case .year: 365 } }
        /// Etiqueta corta (localizada: S/M/3M/6M/1A).
        var label: String { switch self {
            case .week:  String(localized: "W")
            case .month: String(localized: "M")
            case .quarter: String(localized: "3M")
            case .half:  String(localized: "6M")
            case .year:  String(localized: "1Y")
        } }
    }

    private var activeBand: ReadinessEngine.LoadBand? { featured ?? model.band }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoopMetrics.gap) {
                titleRow
                if let acwr = model.acwr, let band = model.band {
                    hero(band)
                    ratioCard(acwr: acwr)
                    hillBlock(acwr: acwr, band: band)
                    Divider().overlay(theme.hairline)
                    periodSelector
                    chartBlock(band: band)
                    lanes(todayBand: band)
                    if let patternText, onSeePattern != nil { patternBlockView(patternText) }
                    methodAccordion(acwr: acwr)
                } else {
                    hero(nil)
                    calibratingBlock
                    methodAccordion(acwr: nil)
                }
                if let onSeeTrends { seeTrendsButton(onSeeTrends) }
                hedgeFooter
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GeometryReader { g in
                Color.clear.preference(key: TrainingLoadHeightKey.self, value: g.size.height)
            })
        }
        .onPreferenceChange(TrainingLoadHeightKey.self) { contentHeight = $0 }
        .background(theme.paper)
        .environment(\.instrumentoTheme, theme)
        .presentationDetents(contentHeight > 0 ? [.height(contentHeight)] : [.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: Título + origen

    private var titleRow: some View {
        HStack(spacing: 6) {
            HillGlyph().stroke(theme.dataStrain, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                .frame(width: 14, height: 14)
            Text("Training load").groteskSheetTitle().foregroundStyle(theme.ink)
            Spacer(minLength: 8)
            HStack(spacing: 4) {
                Circle().fill(theme.inkMuted).frame(width: 6, height: 6)
                Text("Calculated · today").font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
            }
        }
    }

    // MARK: Héroe — la palabra de banda es el dato dominante (nunca el ratio pelado)

    @ViewBuilder private func hero(_ band: ReadinessEngine.LoadBand?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let band {
                Text(band.shortLabel)
                    .font(InstrumentoType.grotesk(34, weight: .bold, relativeTo: .largeTitle))
                    .tracking(-0.8)
                    .foregroundStyle(band.flag.color(theme))
                Text(meaning(band))
                    .font(StrandFont.subhead.weight(.semibold))
                    .foregroundStyle(theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(verbatim: "—")
                    .font(InstrumentoType.grotesk(34, weight: .bold, relativeTo: .largeTitle))
                    .tracking(-0.8)
                    .foregroundStyle(theme.inkDim)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Una frase por banda, descriptiva (sin imperativo).
    private func meaning(_ band: ReadinessEngine.LoadBand) -> LocalizedStringKey {
        switch band {
        case .rampingDown:  "These days you've trained less than your body is used to."
        case .sweetSpot:    "Your recent load is in line with what your body is used to."
        case .buildingFast: "These days you've trained more than your body is used to."
        case .spiking:      "Your recent load is well above what your body is used to."
        }
    }

    // MARK: Ratio glosado — el número se muestra, pero nunca solo

    private func ratioCard(acwr: Double) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(String(format: "%.2f", acwr))
                .font(StrandFont.number(24, weight: .semibold))
                .foregroundStyle(theme.ink)
            Text("your recent load (~7 days) vs. your usual (~28)")
                .font(StrandFont.caption)
                .foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 12).padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(theme.hairline, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    // MARK: La colina — el terreno + la franja de bandas + el punto que respira

    private func hillBlock(acwr: Double, band: ReadinessEngine.LoadBand) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text("The hill").groteskOverline().foregroundStyle(theme.inkTertiary)
                Spacer()
                Text("The green crest is your zone").groteskOverline(small: true).foregroundStyle(theme.inkMuted)
            }
            HillView(acwr: acwr, band: band, theme: theme)
                .frame(height: 128)
                .accessibilityHidden(true)
                .padding(.bottom, 4)
        }
    }

    // MARK: Selector de periodo

    private var periodSelector: some View {
        SegmentedPillControl(LoadPeriod.allCases, selection: $period, theme: theme, inkThumb: true) { $0.label }
    }

    // MARK: Carril activo + gráfica

    private func chartBlock(band todayBand: ReadinessEngine.LoadBand) -> some View {
        let shown = activeBand ?? todayBand
        let isToday = shown == todayBand
        let counts = laneCounts()
        return VStack(alignment: .leading, spacing: 4) {
            Text(isToday ? "\(shown.shortLabel) · \(String(localized: "today"))" : shown.shortLabel)
                .font(InstrumentoType.grotesk(12, weight: .bold)).tracking(1.8).textCase(.uppercase)
                .foregroundStyle(shown.flag.color(theme))
            LoadChartView(series: chartSeries, featured: shown, isTodayLane: isToday, theme: theme)
                .frame(height: 152)
                .accessibilityHidden(true)
            Text("\(counts[shown, default: 0]) of your last 28 days in this lane")
                .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
        }
    }

    // MARK: Carriles tocables

    private func lanes(todayBand: ReadinessEngine.LoadBand) -> some View {
        let counts = laneCounts()
        return VStack(spacing: 0) {
            ForEach([ReadinessEngine.LoadBand.rampingDown, .sweetSpot, .buildingFast, .spiking], id: \.self) { b in
                let isToday = b == todayBand
                Button {
                    withAnimation(StrandMotion.interactive) { featured = b }
                } label: {
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(b.flag.color(theme)).frame(width: 8, height: 8)
                        HStack(spacing: 4) {
                            Text(b.shortLabel).font(StrandFont.subhead.weight(.semibold)).foregroundStyle(theme.ink)
                            if isToday {
                                Text("· \(String(localized: "today"))")
                                    .font(StrandFont.subhead.weight(.semibold)).foregroundStyle(b.flag.color(theme))
                            }
                        }
                        Spacer(minLength: 8)
                        Text("\(counts[b, default: 0]) of your last 28 days")
                            .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(theme.inkMuted)
                    }
                    .padding(.vertical, 10).padding(.horizontal, 10)
                    .background(activeBand == b ? theme.verdict.opacity(0.07) : .clear,
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Tu patrón (solo desde «Hoy», solo cuando hay hallazgo real)

    private func patternBlockView(_ text: String) -> some View {
        Button { dismiss(); onSeePattern?() } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Your pattern").groteskOverline(small: true).foregroundStyle(theme.inkTertiary)
                (Text(text).foregroundStyle(theme.ink)
                 + Text(verbatim: "  ") + Text("See pattern →").foregroundStyle(theme.positiveText).fontWeight(.semibold))
                    .font(StrandFont.subhead)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
            .padding(.vertical, 12).padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .patternBlock(theme, bar: theme.dataStrain)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: ⓘ — la única casa de la jerga (acute:chronic / ACWR + citas)

    private func methodAccordion(acwr: Double?) -> some View {
        InfoAccordion(
            title: "Behind the number",
            explanation: "The ratio compares your average load over the last ~7 days against your last ~28 — the acute:chronic workload ratio (ACWR). 1.0 means you trained exactly your usual; 0.8–1.3 reads as balanced (Gabbett 2016). It's a debated heuristic and does not predict injuries (Impellizzeri 2020).",
            accessibilityLabel: "Information about the training-load method",
            theme: theme
        ) {
            if let acwr {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("Load ratio").font(StrandFont.subhead.weight(.semibold)).foregroundStyle(theme.ink)
                        Text(String(format: "%.2f", acwr)).font(StrandFont.bodyNumber).foregroundStyle(theme.ink)
                    }
                    Text("acute (~7 d) ÷ chronic (~28 d) · what science calls ACWR")
                        .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: Calibrando — sin número, la espera honesta

    private var calibratingBlock: some View {
        Text("Needs about 2 weeks of recorded strain. Keep wearing the strap and this read will appear.")
            .font(StrandFont.subhead)
            .foregroundStyle(theme.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Ver más en Tendencias + hedge

    private func seeTrendsButton(_ action: @escaping () -> Void) -> some View {
        // Botón ancho con borde ink + glifo de Tendencias, unificado con la hoja de resumen de cada métrica
        // (`MetricInfoSheet.seeMoreLink`), en vez de la cápsula chica que tenía antes.
        Button { dismiss(); action() } label: {
            HStack(spacing: 7) {
                TendenciasGlyph(color: theme.ink, lineWidth: 1.8).frame(width: 15, height: 15)
                Text("See more in Trends").font(StrandFont.subhead.weight(.medium))
            }
            .foregroundStyle(theme.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .overlay(RoundedRectangle(cornerRadius: NoopMetrics.controlRadius, style: .continuous)
                .strokeBorder(theme.ink, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }

    private var hedgeFooter: some View {
        Text("Context for your recovery, not an injury prediction · Calculated from your strap's strain")
            .font(StrandFont.footnote)
            .foregroundStyle(theme.inkMuted)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Datos derivados (por periodo / por carril)

    /// La serie de la gráfica, recomputada al `lastN` del periodo desde los días band-masked; cae a la
    /// serie precomputada (28) cuando no hay días (fallback del tap en la tarjeta).
    private var chartSeries: [Double] {
        if model.days.isEmpty { return model.series.map(\.value) }
        return ReadinessEngine.acwrSeries(days: model.days, lastN: period.lastN).map(\.ratio)
    }

    /// Cuántos de los últimos 28 días cayeron en cada banda (ventana fija, independiente del periodo).
    private func laneCounts() -> [ReadinessEngine.LoadBand: Int] {
        let ratios: [Double] = model.days.isEmpty
            ? model.series.suffix(28).map(\.value)
            : ReadinessEngine.acwrSeries(days: model.days, lastN: 28).map(\.ratio)
        var out: [ReadinessEngine.LoadBand: Int] = [:]
        for r in ratios { out[ReadinessEngine.loadBand(forACWR: r), default: 0] += 1 }
        return out
    }
}

// MARK: - La colina (terreno + franja de bandas + punto que respira)

private struct HillView: View {
    let acwr: Double
    let band: ReadinessEngine.LoadBand
    let theme: InstrumentoTheme

    /// El terreno: `y = base − amp·(x/W)^1.8` sobre un lienzo de 118 de alto (base 92, amp 78).
    private func terrainY(_ x: CGFloat, w: CGFloat) -> CGFloat { 92 - 78 * pow(x / w, 1.8) }
    private func cutX(_ r: Double, w: CGFloat) -> CGFloat { CGFloat(r) / 2 * w }

    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            let dx = cutX(min(max(acwr, 0.06), 1.94), w: w)
            let dy = terrainY(dx, w: w)
            ZStack(alignment: .topLeading) {
                Canvas { ctx, size in
                    let W = size.width
                    // Terreno (área + trazo).
                    var line = Path()
                    line.move(to: CGPoint(x: 0, y: terrainY(0, w: W)))
                    var x: CGFloat = 0
                    while x <= W { line.addLine(to: CGPoint(x: x, y: terrainY(x, w: W))); x += 6 }
                    line.addLine(to: CGPoint(x: W, y: terrainY(W, w: W)))
                    var area = line
                    area.addLine(to: CGPoint(x: W, y: 92)); area.addLine(to: CGPoint(x: 0, y: 92)); area.closeSubpath()
                    ctx.fill(area, with: .color(theme.ink.opacity(0.05)))
                    ctx.stroke(line, with: .color(theme.ink), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    // Franja de bandas bajo el terreno (y 98, alto 4): activa plena, inactivas al 35 %.
                    let segs: [(CGFloat, CGFloat, ReadinessEngine.LoadBand)] = [
                        (0, cutX(0.8, w: W), .rampingDown),
                        (cutX(0.8, w: W) + 2, cutX(1.3, w: W), .sweetSpot),
                        (cutX(1.3, w: W) + 2, cutX(1.5, w: W), .buildingFast),
                        (cutX(1.5, w: W) + 2, W, .spiking)]
                    for (x0, x1, b) in segs where x1 > x0 {
                        let r = Path(roundedRect: CGRect(x: x0, y: 98, width: x1 - x0, height: 4), cornerRadius: 2)
                        ctx.fill(r, with: .color(b.flag.color(theme).opacity(b == band ? 1 : 0.35)))
                    }
                    // Cortes 0.8 / 1.3 / 1.5.
                    for r in [0.8, 1.3, 1.5] {
                        let t = ctx.resolve(Text(String(format: "%.1f", r))
                            .font(InstrumentoType.groteskNumber(9, weight: .regular)).foregroundStyle(theme.inkMuted))
                        ctx.draw(t, at: CGPoint(x: cutX(r, w: W), y: 111), anchor: .top)
                    }
                    // Guía punteada del punto a la franja.
                    var guide = Path(); guide.move(to: CGPoint(x: dx, y: dy + 8)); guide.addLine(to: CGPoint(x: dx, y: 96))
                    ctx.stroke(guide, with: .color(theme.rangeMidline), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    // «HOY» sobre el punto.
                    let hoy = ctx.resolve(Text("Today").font(InstrumentoType.grotesk(8, weight: .bold))
                        .foregroundStyle(theme.ink))
                    ctx.draw(hoy, at: CGPoint(x: min(max(dx, 14), W - 14), y: dy - 12), anchor: .bottom)
                }
                // Punto que respira (componente compartido), centrado en la curva.
                BreathingDot(color: band.flag.color(theme), radius: 3.5)
                    .position(x: dx, y: dy)
            }
        }
    }
}

// MARK: - La gráfica de la hoja (serie + franja de equilibrio + punto que respira)

private struct LoadChartView: View {
    let series: [Double]
    let featured: ReadinessEngine.LoadBand
    let isTodayLane: Bool
    let theme: InstrumentoTheme

    /// La x del dedo que arrastra (nil sin arrastre) — dibuja la cruz + tooltip. (FER-748)
    @State private var hoverX: CGFloat? = nil

    /// Fecha corta y localizada para el tooltip de scrub (ej. «sáb 4 jul»).
    private static let dayFmt: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEEdMMM")
        return f
    }()

    /// La fecha del punto `i`: el último punto es hoy, cada índice previo es un día atrás. (FER-748)
    private func date(forIndex i: Int) -> Date {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        return Calendar.current.date(byAdding: .day, value: -(series.count - 1 - i), to: startOfToday) ?? startOfToday
    }

    /// El mapeo ratio → y sobre 130 de alto (0.3 abajo, subiendo con el ratio), como el mock.
    private func cy(_ r: Double) -> CGFloat { min(max(122 - (CGFloat(r) - 0.3) * 72, 10), 122) }

    /// El rango [lo, hi] en ratio de la banda destacada (para sombrear la franja).
    private var range: (lo: Double, hi: Double) {
        switch featured {
        case .rampingDown:  (0.3, ReadinessEngine.acwrSweetSpotLow)
        case .sweetSpot:    (ReadinessEngine.acwrSweetSpotLow, ReadinessEngine.acwrSweetSpotHigh)
        case .buildingFast: (ReadinessEngine.acwrSweetSpotHigh, ReadinessEngine.acwrSpikeAt)
        case .spiking:      (ReadinessEngine.acwrSpikeAt, 1.95)
        }
    }

    private var rangeLabel: String {
        switch featured {
        case .rampingDown:  String(localized: "Below 0.8")
        case .sweetSpot:    String(localized: "Your balance 0.8–1.3")
        case .buildingFast: String(localized: "1.3–1.5")
        case .spiking:      String(localized: "1.5 and up")
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            chart
            dateAxis
        }
    }

    /// El eje X: primera fecha · fecha del medio · «hoy» (el último punto de la serie es hoy). Complementa
    /// al tooltip del scrub (FER-748) con una referencia de tiempo siempre visible, en reposo.
    private var dateAxis: some View {
        HStack(spacing: 0) {
            Text(series.isEmpty ? "" : Self.axisFmt.string(from: date(forIndex: 0)))
            Spacer(minLength: 0)
            if series.count > 3 {
                Text(Self.axisFmt.string(from: date(forIndex: series.count / 2)))
                Spacer(minLength: 0)
            }
            Text("today")
        }
        .font(InstrumentoType.grotesk(9, weight: .regular))
        .foregroundStyle(theme.inkMuted)
    }

    /// «d MMM» localizado para las marcas del eje X.
    private static let axisFmt: DateFormatter = {
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("dMMM"); return f
    }()

    private var chart: some View {
        GeometryReader { g in
            let w = g.size.width
            let head: CGFloat = 8          // margen para que el punto final no se recorte
            let n = series.count
            let last = series.last ?? 1.0
            let endX = w - head
            ZStack(alignment: .topLeading) {
                Canvas { ctx, size in
                    let W = size.width - head
                    // Franja de la banda destacada.
                    let bandRect = CGRect(x: 0, y: cy(range.hi), width: size.width, height: cy(range.lo) - cy(range.hi))
                    ctx.fill(Path(roundedRect: bandRect, cornerRadius: 4), with: .color(theme.rangeBand))
                    if isTodayLane {
                        ctx.fill(Path(roundedRect: bandRect, cornerRadius: 4),
                                 with: .color(featured.flag.color(theme).opacity(0.07)))
                    }
                    // Media punteada en 1.0.
                    var mid = Path(); mid.move(to: CGPoint(x: 0, y: cy(1.0))); mid.addLine(to: CGPoint(x: size.width, y: cy(1.0)))
                    ctx.stroke(mid, with: .color(theme.rangeMidline), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    guard n > 1 else { return }
                    // Línea + área ámbar.
                    var line = Path()
                    for (i, v) in series.enumerated() {
                        let p = CGPoint(x: CGFloat(i) / CGFloat(n - 1) * W, y: cy(v))
                        if i == 0 { line.move(to: p) } else { line.addLine(to: p) }
                    }
                    var area = line
                    area.addLine(to: CGPoint(x: W, y: 122)); area.addLine(to: CGPoint(x: 0, y: 122)); area.closeSubpath()
                    ctx.fill(area, with: .linearGradient(
                        Gradient(colors: [theme.dataStrain.opacity(0.14), theme.dataStrain.opacity(0)]),
                        startPoint: CGPoint(x: 0, y: cy(range.hi)), endPoint: CGPoint(x: 0, y: 122)))
                    ctx.stroke(line, with: .color(theme.dataStrain), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    // Etiqueta de la franja, dentro.
                    let t = ctx.resolve(Text(rangeLabel).font(InstrumentoType.grotesk(8, weight: .semibold))
                        .foregroundStyle(theme.inkMuted))
                    ctx.draw(t, at: CGPoint(x: 6, y: cy(range.hi) - 4), anchor: .bottomLeading)
                }
                BreathingDot(color: theme.dataStrain, radius: 3.2)
                    .position(x: endX, y: cy(last))

                // Scrub: cruz + punto + tooltip (ratio · fecha · banda) que siguen el dedo. La banda
                // del punto se lee de su propio ratio, no de la destacada. Reusa el scrub compartido. (FER-748)
                let snapped: Int? = hoverX.flatMap {
                    ChartScrubMath.nearestIndex(toX: $0, count: n, width: endX)
                }
                Color.clear
                    .contentShape(Rectangle())
                    .scrubGesture(enabled: n > 1, hoverX: $hoverX)
                    .onChange(of: snapped) { if $0 != nil { ChartHaptics.datumChanged() } }
                if let i = snapped, series.indices.contains(i) {
                    let px = CGFloat(i) / CGFloat(max(n - 1, 1)) * endX
                    let py = cy(series[i])
                    let band = ReadinessEngine.loadBand(forACWR: series[i])
                    CrosshairRule(x: px, height: g.size.height)
                    HighlightDot(color: band.flag.color(theme)).position(x: px, y: py)
                    PositionedTooltip(
                        anchor: CGPoint(x: px, y: py),
                        container: g.size,
                        tooltip: ChartTooltip(
                            value: String(format: "%.2f", series[i]),
                            label: "\(Self.dayFmt.string(from: date(forIndex: i))) · \(band.shortLabel)",
                            accent: band.flag.color(theme)
                        )
                    )
                }
            }
            .environment(\.instrumentoTheme, theme)
            .environment(\.instrumentoFlat, true)
            .animation(StrandMotion.fade, value: hoverX)
        }
        .frame(height: 130)
    }
}

// MARK: - Glifo de colina (icono del título)

private struct HillGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        // Una curva de una línea: sube y baja como una loma (proporcional al frame).
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height) }
        var path = Path()
        path.move(to: p(0.05, 0.85))
        path.addCurve(to: p(0.55, 0.30), control1: p(0.30, 0.85), control2: p(0.40, 0.40))
        path.addCurve(to: p(0.95, 0.20), control1: p(0.75, 0.20), control2: p(0.85, 0.45))
        return path
    }
}

private struct TrainingLoadHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

// MARK: - Preview

#if DEBUG
private func demoDays(strainCurve: (Int) -> Double) -> [DailyMetric] {
    (0..<60).map { i in
        DailyMetric(day: String(format: "2026-%02d-%02d", (i / 28) + 4, (i % 28) + 1),
                    totalSleepMin: nil, efficiency: nil, deepMin: nil, remMin: nil, lightMin: nil,
                    disturbances: nil, restingHr: nil, avgHrv: nil, recovery: nil,
                    strain: strainCurve(i), exerciseCount: nil)
    }
}

#Preview("Carga — en equilibrio") {
    TrainingLoadSheet(model: TrainingLoadModel(
        acwr: 1.09,
        series: (0..<28).map { (day: "d\($0)", value: 0.9 + 0.4 * sin(Double($0) / 5)) },
        days: demoDays { 10 + 3 * sin(Double($0) / 5) }),
        patternText: "Tus semanas en equilibrio terminan con mejor recuperación el lunes: +5 sobre tu promedio.",
        onSeePattern: {}, onSeeTrends: {})
}

#Preview("Carga — disparada") {
    TrainingLoadSheet(model: TrainingLoadModel(
        acwr: 1.62,
        series: (0..<28).map { (day: "d\($0)", value: 1.0 + Double($0) * 0.025) },
        days: demoDays { 8 + Double($0) * 0.12 }))
}

#Preview("Carga — calibrando") {
    TrainingLoadSheet(model: TrainingLoadModel(acwr: nil, series: []))
}

#Preview("Franja") {
    VStack(spacing: 24) {
        TrainingLoadStrip(model: TrainingLoadModel(acwr: 1.09, series: [], days: []), theme: .base, onTap: {})
        TrainingLoadStrip(model: TrainingLoadModel(acwr: nil, series: [], days: []), theme: .base, onTap: {})
        TrainingLoadStrip(model: TrainingLoadModel(acwr: 1.62, series: [], days: []), theme: .base, onTap: {})
    }
    .padding(24).background(InstrumentoTheme.base.paper)
}
#endif
#endif
