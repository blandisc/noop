#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

// MARK: - Carga de entrenamiento — hoja explicativa (FER-705)
//
// The «Training load» card in Tendencias opens this light «Instrumento» sheet: the load BAND in a plain
// word is the dominant datum (never the bare ratio — the user can't interpret 1.09 unexplained), then a
// one-line meaning, the band scale with a «today» marker, the glossed ratio, the recent mini-trend, and
// the honest hedge. The jargon («acute:chronic», ACWR) lives ONLY inside the ⓘ accordion — FER-684's
// descriptive framing: load balance is context for recovery, never an injury prediction (Gabbett 2016;
// Impellizzeri 2020). All math comes from `ReadinessEngine` (thresholds untouched); the sheet only
// presents `acwr` + `acwrSeries`. Tokens only; theme passed explicitly (it doesn't cross `.sheet`).

/// Everything the sheet (and the Tendencias card) draws, built once in `CuerpoView.loadAll` from the
/// band-masked dashboard. `acwr == nil` → calibrating (< ~2 weeks of recorded strain).
struct TrainingLoadModel {
    /// Today's acute:chronic ratio (nil while there isn't enough strain history).
    let acwr: Double?
    /// The ratio replayed per day (oldest → newest) for the mini-trend — `ReadinessEngine.acwrSeries`.
    let series: [(day: String, value: Double)]

    /// The band for today's ratio — the same `LoadBand` scale every surface shares.
    var band: ReadinessEngine.LoadBand? { acwr.map(ReadinessEngine.loadBand(forACWR:)) }
}

/// Identifiable wrapper so the sheet can ride `.sheet(item:)` (the model itself isn't Identifiable).
struct TrainingLoadItem: Identifiable {
    let id = UUID()
    let model: TrainingLoadModel
}

struct TrainingLoadSheet: View {
    let model: TrainingLoadModel
    /// The active «Instrumento» theme, passed explicitly (sheets start a fresh environment). (FER-162)
    var theme: InstrumentoTheme = .base

    /// Measured natural height, so the detent fits the content (same pattern as `MetricInfoSheet`).
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoopMetrics.gap) {
                header
                if let acwr = model.acwr, let band = model.band {
                    Text(meaning(band))
                        .font(StrandFont.subhead)
                        .foregroundStyle(theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    bandScale(acwr: acwr, band: band)
                    ratioCard(acwr: acwr)
                    if model.series.count > 1 { trendBlock(band: band) }
                    methodAccordion(acwr: acwr)
                } else {
                    calibratingBlock
                }
                Text("It's context for your recovery, not an injury prediction.")
                    .font(StrandFont.footnote)
                    .foregroundStyle(theme.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GeometryReader { g in
                Color.clear.preference(key: TrainingLoadHeightKey.self, value: g.size.height)
            })
        }
        .onPreferenceChange(TrainingLoadHeightKey.self) { contentHeight = $0 }
        .background(theme.paper)
        .presentationDetents(contentHeight > 0 ? [.height(contentHeight)] : [.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: Header — the band word is the dominant datum (a word the user understands, not a bare ratio)

    private var header: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space2) {
            Text("Training load")
                .instrumentoOverline()
                .foregroundStyle(theme.inkTertiary)
            if let band = model.band {
                Text(band.shortLabel)
                    .font(StrandFont.number(30, weight: .semibold))
                    .foregroundStyle(band.flag.color(theme))
            } else {
                Text(verbatim: "—")
                    .font(StrandFont.number(30, weight: .semibold))
                    .foregroundStyle(theme.inkTertiary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// One plain sentence per band — what the word means, purely descriptive (no imperative).
    private func meaning(_ band: ReadinessEngine.LoadBand) -> LocalizedStringKey {
        switch band {
        case .rampingDown:  return "These days you've trained less than your body is used to."
        case .sweetSpot:    return "Your recent load is in line with what your body is used to."
        case .buildingFast: return "These days you've trained more than your body is used to."
        case .spiking:      return "Your recent load is well above what your body is used to."
        }
    }

    // MARK: Band scale — the four bands as one bar, with a «today» marker on the active spot

    /// The scale's display domain: ratios plotted 0…2 (a spike beyond 2 pins to the right edge).
    private static let scaleMax = 2.0
    /// The band cut points, read from the engine so the scale can never drift from `loadBand(forACWR:)`.
    private static let cuts: [Double] = [ReadinessEngine.acwrSweetSpotLow,
                                         ReadinessEngine.acwrSweetSpotHigh,
                                         ReadinessEngine.acwrSpikeAt]

    private func bandScale(acwr: Double, band: ReadinessEngine.LoadBand) -> some View {
        let bounds: [(lo: Double, hi: Double, band: ReadinessEngine.LoadBand)] = [
            (0, Self.cuts[0], .rampingDown), (Self.cuts[0], Self.cuts[1], .sweetSpot),
            (Self.cuts[1], Self.cuts[2], .buildingFast), (Self.cuts[2], Self.scaleMax, .spiking),
        ]
        let x = min(max(acwr, 0), Self.scaleMax) / Self.scaleMax
        return VStack(alignment: .leading, spacing: 6) {
            GeometryReader { g in
                ZStack(alignment: .topLeading) {
                    HStack(spacing: 2) {
                        ForEach(bounds, id: \.lo) { seg in
                            Capsule()
                                .fill(seg.band == band ? seg.band.flag.color(theme) : theme.hairline)
                                .frame(width: max(0, g.size.width * (seg.hi - seg.lo) / Self.scaleMax - 2),
                                       height: 6)
                        }
                    }
                    .frame(height: 14, alignment: .center)
                    // «Today» marker — a small ink dot riding the bar at the ratio's position.
                    Circle()
                        .fill(theme.ink)
                        .frame(width: 10, height: 10)
                        .offset(x: g.size.width * x - 5, y: 2)
                }
            }
            .frame(height: 14)
            // Cut points in quiet mono under the bar, plus the «today» word under the marker.
            GeometryReader { g in
                ZStack(alignment: .topLeading) {
                    ForEach(Self.cuts, id: \.self) { cut in
                        Text(String(format: "%.1f", cut))
                            .font(StrandFont.number(10, weight: .regular))
                            .foregroundStyle(theme.inkTertiary)
                            .position(x: g.size.width * cut / Self.scaleMax, y: 7)
                    }
                    Text("today")
                        .font(StrandFont.footnote)
                        .foregroundStyle(theme.ink)
                        .position(x: min(max(g.size.width * x, 16), g.size.width - 16), y: 22)
                }
            }
            .frame(height: 30)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Load scale. Today: \(model.band?.shortLabel ?? "—")."))
    }

    // MARK: The glossed ratio — the number shows, but explained (never bare)

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
        .background(theme.surface, in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous)
            .strokeBorder(theme.hairline, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    // MARK: Recent mini-trend — the replayed ratio, the balance band shaded behind (ink, not a hue)

    private func trendBlock(band: ReadinessEngine.LoadBand) -> some View {
        let color = band.flag.color(theme)
        return VStack(alignment: .leading, spacing: 6) {
            Sparkline(values: model.series.map(\.value),
                      gradient: Gradient(colors: [color.opacity(0.5), color]),
                      referenceBand: ReadinessEngine.acwrSweetSpotLow...ReadinessEngine.acwrSweetSpotHigh,
                      bandColor: theme.hairlineStrong,
                      lineWidth: 2.0, showsArea: false, showsHead: true, showsScrub: false)
                .frame(height: 44)
                .accessibilityHidden(true)
            Text("Last few weeks · the shaded strip is your balance zone (0.8–1.3)")
                .font(StrandFont.footnote)
                .foregroundStyle(theme.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: ⓘ — the jargon's one home (acute:chronic / ACWR + citations)

    private func methodAccordion(acwr: Double) -> some View {
        InfoAccordion(
            title: "Behind the number",
            explanation: "The ratio compares your average load over the last ~7 days against your last ~28 — the acute:chronic workload ratio (ACWR). 1.0 means you trained exactly your usual; 0.8–1.3 reads as balanced (Gabbett 2016). It's a debated heuristic and does not predict injuries (Impellizzeri 2020).",
            accessibilityLabel: "Information about the training-load method",
            theme: theme
        ) {
            Text("acute:chronic \(String(format: "%.2f", acwr)) · ACWR")
                .font(StrandFont.bodyNumber)
                .foregroundStyle(theme.ink)
        }
    }

    // MARK: Calibrating — no number, the honest wait (mirrors the app's «—» while it learns)

    private var calibratingBlock: some View {
        Text("Needs about 2 weeks of recorded strain. Keep wearing the strap and this read will appear.")
            .font(StrandFont.subhead)
            .foregroundStyle(theme.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct TrainingLoadHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

// MARK: - Preview

#if DEBUG
#Preview("Carga — en equilibrio") {
    TrainingLoadSheet(model: TrainingLoadModel(
        acwr: 1.09,
        series: (0..<28).map { (day: "d\($0)", value: 0.9 + 0.4 * sin(Double($0) / 5)) }))
}

#Preview("Carga — subiendo rápido") {
    TrainingLoadSheet(model: TrainingLoadModel(
        acwr: 1.62,
        series: (0..<28).map { (day: "d\($0)", value: 1.0 + Double($0) * 0.025) }))
}

#Preview("Carga — calibrando") {
    TrainingLoadSheet(model: TrainingLoadModel(acwr: nil, series: []))
}
#endif
#endif
