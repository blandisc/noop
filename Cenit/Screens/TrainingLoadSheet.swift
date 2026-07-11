#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore
import Foundation

// MARK: - Carga de entrenamiento — franja en «Hoy» + hoja «Detalle de Tendencias Final» (FER-705 · FER-862)
//
// La carga de entrenamiento (ACWR) entra a «Hoy» como una FRANJA fija bajo las pestañas (visible en
// Señales y Brief) que al tocarla abre esta HOJA. La hoja sigue el esqueleto de las hermanas
// (Recuperación / Esfuerzo / Estrés / Sueño): héroe invertido → instrumento firma (la colina
// scrubbable) → historial (`GraficaRangos`) → método + sello. SIN calendario de 90 días (ventana
// móvil 7/28). Toda la matemática viene de `ReadinessEngine` (umbrales 0.8 / 1.3 / 1.5 intactos);
// estas vistas solo presentan `acwr`, `acwrSeries` y `loadBand`. Tokens únicamente; el tema se
// pasa explícito (no cruza `.sheet`).

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
                    .font(.system(size: 9, weight: .semibold)) // token-exempt: microtexto <10pt
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

// MARK: - Hoja «Carga de entrenamiento» — esqueleto «Detalle de Tendencias Final» (FER-862)

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
    /// El periodo del historial (S/M/3M/6M/1A/TODO).
    @State private var range: ExploreRange = .month
    /// Serie ACWR con día parseado una sola vez (lección FER-216).
    @State private var parsed: [(day: String, date: Date?, value: Double)] = []
    /// El ⓘ del héroe abre «Qué medimos».
    @State private var infoOpen = false

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let acwr = model.acwr, let band = model.band {
                    heroField(acwr: acwr, band: band)
                    if infoOpen { whatWeMeasureCard }
                    seccion(String(localized: "The hill"),
                            pista: String(localized: "Drag to explore"),
                            contentPadding: EdgeInsets(top: 14, leading: 14, bottom: 22, trailing: 14)) {
                        hillContent(acwr: acwr, band: band)
                    }
                    seccion(String(localized: "See your history")) { historyContent }
                    if let onSeeTrends {
                        seeTrendsButton(onSeeTrends)
                            .padding(.horizontal, 20)
                            .padding(.top, 4)
                    }
                    PieMetodo(theme: theme) {
                        metodoBlock
                    } sello: {
                        OriginStamp(origin: .computed, when: String(localized: "today"), theme: theme)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 2)
                    }
                } else {
                    // Calibrando: héroe plano honesto + método + sello (mismo fallback que las hermanas).
                    // Sin PieMetodo: no hay divisor y el VStack padre usa spacing 22, no 10.
                    VStack(alignment: .leading, spacing: 22) {
                        heroFlat
                        calibratingBlock
                        metodoBlock
                        OriginStamp(origin: .computed, when: String(localized: "today"), theme: theme)
                    }
                    .padding(NoopMetrics.screenPadding)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.paper)
        .presentationDragIndicator(.visible)
        .sheetPaper(theme)
        .environment(\.instrumentoTheme, theme)
        .task {
            range = .month
            parsed = chartSeriesPairs.map { ($0.day, Repository.parseDayKey($0.day), $0.value) }
        }
    }

    /// One skeleton section: shared `SeccionBloque` (franja + contentPadding handoff).
    private func seccion(_ title: String,
                         pista: String? = nil,
                         contentPadding: EdgeInsets = EdgeInsets(top: 14, leading: 20, bottom: 22, trailing: 20),
                         @ViewBuilder content: () -> some View) -> some View {
        SeccionBloque(title, pista: pista, contentPadding: contentPadding, theme: theme, content: content)
    }

    // MARK: - 1. Héroe invertido — palabra de banda pintada por el color de la banda

    private func heroField(acwr: Double, band: ReadinessEngine.LoadBand) -> some View {
        let hue = band.flag.color(theme)
        return HeroInvertido(
            glyph: .trainingLoad,
            title: "Training load",
            hue: hue,
            theme: theme,
            onInfo: { withAnimation(StrandMotion.interactive) { infoOpen.toggle() } },
            numeral: {
                // Hero is the band WORD (not a /100 number). Custom numeral markup.
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(band.shortLabel)
                        .font(InstrumentoType.grotesk(38, weight: .bold, relativeTo: .largeTitle))
                        .tracking(-1.2)
                        .foregroundStyle(theme.paper)
                        .recRise()
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(fmt(acwr))
                            .font(InstrumentoType.groteskNumber(13, weight: .semibold))
                            .foregroundStyle(theme.paper)
                        Text("vs your base")
                            .font(InstrumentoType.grotesk(11))
                            .foregroundStyle(theme.paper.opacity(OnFieldOpacity.secondary))
                    }
                    .heroCapsule(theme: theme)
                }
            },
            verdict: {
                Text(heroVerdict(band))
                    .font(InstrumentoType.grotesk(15, weight: .semibold))
                    .foregroundStyle(theme.paper)
                    .fixedSize(horizontal: false, vertical: true)
            }
        )
    }

    /// The ⓘ card under the hero: what the ratio measures, in plain language (no ACWR jargon).
    private var whatWeMeasureCard: some View {
        QueMedimosCard(title: "What we measure", explanation: heroExplanation,
                       theme: theme, bottomInset: 0)
    }

    /// Flat hero for the calibrating state: no inverted field for a ratio we don't have.
    private var heroFlat: some View {
        VStack(alignment: .leading, spacing: 10) {
            InstrumentoScreenTitle("Training load", theme: theme,
                                   explanation: heroExplanation, glyph: .trainingLoad)
            VStack(alignment: .leading, spacing: 10) {
                Text(verbatim: "—")
                    .instrumentoHero(46)
                    .foregroundStyle(theme.inkTertiary)
                Text("Needs about 2 weeks of recorded strain. Keep wearing the strap and this read will appear.")
                    .font(StrandFont.headline)
                    .foregroundStyle(theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var calibratingBlock: some View {
        Text("Needs about 2 weeks of recorded strain. Keep wearing the strap and this read will appear.")
            .font(StrandFont.subhead)
            .foregroundStyle(theme.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Short verdict under the band word. Descriptive, no imperative.
    private func heroVerdict(_ band: ReadinessEngine.LoadBand) -> LocalizedStringKey {
        switch band {
        case .rampingDown:  "Less than your body is used to these days."
        case .sweetSpot:    "In line with what your body is used to."
        case .buildingFast: "More than your body is used to these days."
        case .spiking:      "Well above what your body is used to."
        }
    }

    /// ⓘ copy: 7 vs 28, 1.0 = usual, balance band, hedge. ACWR jargon stays in `Metodo` only.
    private var heroExplanation: LocalizedStringKey {
        "We compare your average strain over the last ~7 days against your last ~28. 1.0 means you trained exactly your usual; 0.8 to 1.3 reads as balance. It's context for your recovery, not an injury prediction."
    }

    // MARK: - 2. La colina (instrumento firma scrubbable)

    private func hillContent(acwr: Double, band: ReadinessEngine.LoadBand) -> some View {
        LoadHillView(acwr: acwr, todayBand: band, theme: theme)
    }

    // MARK: - 3. Ver tu historial — PeriodSelector + GraficaRangos + tiles + observación

    private var historyContent: some View {
        let window = MetricWindowMath.make(parsed, selected: range)
        let stat = ComparisonEngine.stat(window.values)
        let seriesPairs = parsed.map { ($0.day, $0.value) }
        let pct = range.periodComparison(of: seriesPairs)?.pctChange
        return VStack(alignment: .leading, spacing: 8) {
            SegmentedPillControl(ExploreRange.allCases, selection: $range, theme: theme) { $0.label }
            if window.values.count > 1 {
                GraficaRangos(
                    points: window.values,
                    bands: Self.loadBands(theme),
                    ticks: [
                        .init(v: ReadinessEngine.acwrSpikeAt, label: cutLabel(ReadinessEngine.acwrSpikeAt)),
                        .init(v: 1.0, label: "1.0"),
                        .init(v: ReadinessEngine.acwrSweetSpotLow, label: cutLabel(ReadinessEngine.acwrSweetSpotLow)),
                    ],
                    hue: theme.dataStrain,
                    ymin: 0.45, ymax: 1.9,
                    startLabel: window.rows.first.flatMap { RecoveryDetailScreen.axisLabel($0.day) } ?? "",
                    endLabel: window.rows.last.flatMap { RecoveryDetailScreen.axisLabel($0.day) } ?? "",
                    mediaValue: fmt(stat.mean),
                    mediaNote: String(localized: "average of the \(range.name)"),
                    mediaDelta: pct.map { $0 >= 0 ? "+\(Int($0.rounded()))%" : "\(Int($0.rounded()))%" },
                    deltaColor: theme.inkSecondary,
                    countUnit: "d",
                    anchorMedia: historyAnchorMedia,
                    anchorRangos: String(localized: "How many days of the period fell in each band. Tap one to see its days on the chart."),
                    scrub: true,
                    labels: window.rows.map { RecoveryDetailScreen.axisLabel($0.day) ?? "" },
                    fmt: { String(format: "%.2f", $0) },
                    theme: theme)
                    .padding(.top, 6)
                    .id(range)
                HStack(alignment: .top, spacing: 8) {
                    TileSurface(label: String(localized: "Average"),
                                value: fmt(stat.mean),
                                theme: theme)
                    TileSurface(label: String(localized: "Range"),
                                value: "\(fmt(stat.min))–\(fmt(stat.max))",
                                theme: theme)
                    TileSurface(label: String(localized: "Today"),
                                value: model.acwr.map { fmt($0) } ?? "—",
                                valueColor: model.band.map { $0.flag.color(theme) },
                                theme: theme)
                }
                .padding(.top, 4)
            } else {
                ChartWell(theme).empty(text: "Not enough days in this range to draw a trend.")
                    .padding(.top, 6)
            }
            if let patternText, !patternText.isEmpty {
                historyObservationCard(patternText)
                    .padding(.top, 10)
            }
        }
    }

    /// «LO QUE VEMOS EN TU HISTORIAL» + chip «TENDENCIA, NO CAUSA» + observación del modelo (gated).
    @ViewBuilder
    private func historyObservationCard(_ text: String) -> some View {
        if let onSeePattern {
            Button { dismiss(); onSeePattern() } label: {
                observationCardContent(text)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            observationCardContent(text)
        }
    }

    private func observationCardContent(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            QueLaMueveHeader("What we see in your history", chip: "trend, not cause", theme: theme)
            Text(text)
                .font(StrandFont.subhead)
                .foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
        }
        .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
        .frame(maxWidth: .infinity, alignment: .leading)
        .instrumentoCard(.card, theme: theme)
    }

    /// Four load lanes for `GraficaRangos`, high→low. Bounds from `LoadScale` / `ReadinessEngine` only.
    static func loadBands(_ theme: InstrumentoTheme) -> [GraficaRangos.Banda] {
        let lo = ReadinessEngine.acwrSweetSpotLow
        let hi = ReadinessEngine.acwrSweetSpotHigh
        let spike = ReadinessEngine.acwrSpikeAt
        return [
            .init(label: ReadinessEngine.LoadBand.spiking.shortLabel,
                  lo: spike, hi: nil, color: theme.critical,
                  range: String(localized: "\(cutLabel(spike)) and up")),
            .init(label: ReadinessEngine.LoadBand.buildingFast.shortLabel,
                  lo: hi, hi: spike, color: theme.warning,
                  range: "\(cutLabel(hi))–\(cutLabel(spike))"),
            .init(label: ReadinessEngine.LoadBand.sweetSpot.shortLabel,
                  lo: lo, hi: hi, color: theme.verdict,
                  range: "\(cutLabel(lo))–\(cutLabel(hi))"),
            .init(label: ReadinessEngine.LoadBand.rampingDown.shortLabel,
                  lo: nil, hi: lo, color: theme.inkMuted,
                  range: String(localized: "Below \(cutLabel(lo))")),
        ]
    }

    private var historyAnchorMedia: String {
        let lo = cutLabel(ReadinessEngine.acwrSweetSpotLow)
        let hi = cutLabel(ReadinessEngine.acwrSweetSpotHigh)
        return String(localized: "Your day-to-day ratio: the green band is your balance \(lo) to \(hi). Drag the chart to read each day.")
    }

    // MARK: - Método + sello

    private var metodoBlock: some View {
        Metodo(title: String(localized: "How it's calculated"), theme: theme) {
            Text("The ratio compares your average load over the last ~7 days against your last ~28: what science calls ACWR (acute:chronic). 1.0 is training exactly your usual; 0.8 to 1.3 reads as balance (Gabbett 2016). It's a debated heuristic and does not predict injuries (Impellizzeri 2020).")
                .font(StrandFont.subhead)
                .foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Ver más en Tendencias (solo desde «Hoy»)

    private func seeTrendsButton(_ action: @escaping () -> Void) -> some View {
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

    // MARK: - Datos derivados

    /// Serie de ratios por día: recomputa desde `days` cuando hay (ventana larga para el selector);
    /// cae a la serie precomputada (28) del modelo.
    private var chartSeriesPairs: [(day: String, value: Double)] {
        if model.days.isEmpty { return model.series }
        return ReadinessEngine.acwrSeries(days: model.days, lastN: 365)
            .map { (day: $0.day, value: $0.ratio) }
    }

    /// Ratio with two decimals everywhere.
    private func fmt(_ v: Double) -> String { String(format: "%.2f", v) }

    /// One decimal for cut marks (0.8 / 1.3 / 1.5) from engine constants.
    private static func cutLabel(_ v: Double) -> String { String(format: "%.1f", v) }
    private func cutLabel(_ v: Double) -> String { Self.cutLabel(v) }
}

// MARK: - La colina scrubbable (instrumento firma de Carga)

/// Curva tipo colina sobre la escala 0…2, con punto del día, chip negro anclado y drag horizontal
/// que explora cada zona. Al soltar vuelve a HOY. No reusa `GraficaRangos`: es un instrumento distinto.
private struct LoadHillView: View {
    let acwr: Double
    let todayBand: ReadinessEngine.LoadBand
    let theme: InstrumentoTheme

    /// `nil` = mostrando HOY; non-nil = ratio bajo el dedo.
    @State private var scrubRatio: Double? = nil

    private var displayRatio: Double { scrubRatio ?? acwr }
    private var isShowingToday: Bool { scrubRatio == nil }
    private var displayBand: ReadinessEngine.LoadBand {
        ReadinessEngine.loadBand(forACWR: displayRatio)
    }

    /// Fixed drawing height matching the mock viewBox (132).
    private let chartH: CGFloat = 132
    /// Mock path coordinate width; x is scaled to the live width.
    private let mockW: CGFloat = 320

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { g in
                let w = max(g.size.width, 1)
                let r = displayRatio
                let hx = xForRatio(r, width: w)
                let hy = hillY(atX: hx, width: w) - 6
                let bandColor = hillPointColor(displayBand)
                let chip = chipText(ratio: r, band: displayBand, today: isShowingToday)
                let chipW = CGFloat(chip.count) * 5.6 + 16
                let chipX = max(0, min(w - chipW, hx - chipW / 2))
                let chipY = max(0, hy - 26)

                ZStack(alignment: .topLeading) {
                    // Área + trazo de la colina.
                    hillAreaPath(width: w)
                        .fill(LinearGradient(
                            colors: [theme.ink.opacity(0.07), theme.ink.opacity(0)],  // token-exempt: rampa decorativa (sombra de fondo)
                            startPoint: .top, endPoint: .bottom))
                        .recFade()
                    hillLinePath(width: w)
                        .stroke(theme.ink, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                    // Barras de zona (crest verde al 100%, el resto al 35%).
                    zoneBars(width: w)

                    // Ticks en los cortes del motor.
                    ForEach(LoadScale.cuts, id: \.self) { cut in
                        let tx = xForRatio(cut, width: w)
                        Text(String(format: "%.1f", cut))
                            .font(InstrumentoType.groteskNumber(9, weight: .regular))
                            .foregroundStyle(theme.inkTertiary)
                            .position(x: tx, y: 120)
                    }

                    // Fantasma de HOY mientras se explora.
                    if !isShowingToday {
                        let gx = xForRatio(acwr, width: w)
                        let gy = hillY(atX: gx, width: w) - 6
                        Circle()
                            .strokeBorder(theme.inkMuted, lineWidth: 1.5)
                            .frame(width: 6, height: 6)
                            .position(x: gx, y: gy)
                    }

                    // Guía punteada del punto a la franja.
                    Path { p in
                        p.move(to: CGPoint(x: hx, y: hy + 8))
                        p.addLine(to: CGPoint(x: hx, y: 98))
                    }
                    .stroke(theme.inkMuted, style: StrokeStyle(lineWidth: 1, dash: [2, 3]))

                    // Punto del ratio mostrado.
                    Circle()
                        .fill(theme.surface)
                        .overlay(Circle().strokeBorder(bandColor, lineWidth: 2.5))
                        .frame(width: 9, height: 9)
                        .position(x: hx, y: hy)

                    // Chip negro anclado (mismo look que el scrub de `GraficaRangos`).
                    Text(verbatim: chip)
                        .font(InstrumentoType.groteskNumber(9.5, weight: .semibold))
                        .foregroundStyle(theme.paper)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, 6)
                        .frame(width: chipW, height: 16)
                        .background(theme.ink, in: Capsule(style: .continuous))
                        .position(x: chipX + chipW / 2, y: chipY + 8)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let ratio = ratioForX(value.location.x, width: w)
                            scrubRatio = min(max(ratio, 0), LoadScale.max)
                        }
                        .onEnded { _ in
                            scrubRatio = nil
                        }
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("The hill"))
                .accessibilityValue(Text(chip))
            }
            .frame(height: chartH)

            BarraAncla(anchorText(for: displayBand),
                       color: hillPointColor(displayBand),
                       theme: theme)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .instrumentoCard(.card, theme: theme)
    }

    // MARK: Mapping x ↔ ratio (mock: HX(r) = (r / 2) * width)

    private func xForRatio(_ r: Double, width w: CGFloat) -> CGFloat {
        CGFloat(r / LoadScale.max) * w
    }

    private func ratioForX(_ x: CGFloat, width w: CGFloat) -> Double {
        Double(x / w) * LoadScale.max
    }

    // MARK: Bezier hill (mock path scaled to live width)

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

    private func cubic(_ x0: CGFloat, _ y0: CGFloat,
                       _ x1: CGFloat, _ y1: CGFloat,
                       _ x2: CGFloat, _ y2: CGFloat,
                       _ x3: CGFloat, _ y3: CGFloat,
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

    /// Zone strips under the axis: crest (sweet spot) at full green; the other three at 35%.
    /// Positions from `LoadScale.cuts` so the bars never desync from `loadBand(forACWR:)`.
    private func zoneBars(width w: CGFloat) -> some View {
        let gap: CGFloat = 2
        let y: CGFloat = 100
        let h: CGFloat = 4
        let x0: CGFloat = 0
        let x1 = xForRatio(LoadScale.cuts[0], width: w)
        let x2 = xForRatio(LoadScale.cuts[1], width: w)
        let x3 = xForRatio(LoadScale.cuts[2], width: w)
        return ZStack(alignment: .topLeading) {
            zoneBar(x: x0, width: max(0, x1 - gap), y: y, h: h, color: theme.verdict.opacity(0.35))  // token-exempt: sombreado de zona de carga
            zoneBar(x: x1 + gap, width: max(0, x2 - x1 - gap), y: y, h: h, color: theme.verdict)
            zoneBar(x: x2 + gap, width: max(0, x3 - x2 - gap), y: y, h: h, color: theme.warning.opacity(0.35))  // token-exempt: sombreado de zona de carga
            zoneBar(x: x3 + gap, width: max(0, w - x3 - gap), y: y, h: h, color: theme.critical.opacity(0.35))  // token-exempt: sombreado de zona de carga
        }
    }

    private func zoneBar(x: CGFloat, width: CGFloat, y: CGFloat, h: CGFloat, color: Color) -> some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)  // token-exempt: geometría de dato
            .fill(color)
            .frame(width: max(0, width), height: h)
            .offset(x: x, y: y)
    }

    // MARK: Chip + ancla

    private func chipText(ratio: Double, band: ReadinessEngine.LoadBand, today: Bool) -> String {
        let num = String(format: "%.2f", ratio)
        let word = band.shortLabel
        if today {
            return "\(String(localized: "Today").uppercased()) · \(num) · \(word)"
        }
        return "\(num) · \(word)"
    }

    /// Point/chip/ancla color for a band on the hill. Matches the zone-strip palette (mock): both
    /// the climb and the crest are green; the descent is amber; the drop is red. (Distinct from
    /// `LoadBand.flag`, which paints "easing off" as watch/amber in the strip and hero.)
    private func hillPointColor(_ band: ReadinessEngine.LoadBand) -> Color {
        switch band {
        case .rampingDown, .sweetSpot: return theme.verdict
        case .buildingFast:            return theme.warning
        case .spiking:                 return theme.critical
        }
    }

    private func anchorText(for band: ReadinessEngine.LoadBand) -> String {
        let lo = String(format: "%.1f", ReadinessEngine.acwrSweetSpotLow)
        let hi = String(format: "%.1f", ReadinessEngine.acwrSweetSpotHigh)
        switch band {
        case .rampingDown:
            return String(localized: "Less than your body is used to: the uphill slope.")
        case .sweetSpot:
            return String(localized: "The crest: your balance \(lo) to \(hi).")
        case .buildingFast:
            return String(localized: "More than usual: coming down from the crest.")
        case .spiking:
            return String(localized: "Well above usual: the drop.")
        }
    }
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

#Preview("Carga: en equilibrio") {
    TrainingLoadSheet(model: TrainingLoadModel(
        acwr: 1.09,
        series: (0..<28).map { (day: "d\($0)", value: 0.9 + 0.4 * sin(Double($0) / 5)) },
        days: demoDays { 10 + 3 * sin(Double($0) / 5) }),
        patternText: "Tus semanas en equilibrio terminan con mejor recuperación el lunes: +5 sobre tu promedio.",
        onSeePattern: {}, onSeeTrends: {})
}

#Preview("Carga: disparada") {
    TrainingLoadSheet(model: TrainingLoadModel(
        acwr: 1.62,
        series: (0..<28).map { (day: "d\($0)", value: 1.0 + Double($0) * 0.025) },
        days: demoDays { 8 + Double($0) * 0.12 }))
}

#Preview("Carga: calibrando") {
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
