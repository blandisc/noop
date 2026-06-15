import SwiftUI
import StrandDesign

// MARK: - MetricInfo

/// Data model for the "tap a metric to learn more" bottom sheet.
/// Each metric defines its bands (fixed ranges + colors) and which band is active
/// for the user's current value.
struct MetricInfo: Identifiable {
    let id: String
    let name: LocalizedStringKey
    let headline: LocalizedStringKey
    let displayValue: String
    let unit: String?
    let currentColor: Color
    let bands: [Band]
    let note: LocalizedStringKey?

    // Progressive-disclosure extras for composite metrics (Recovery; reused by HRV in FER-109).
    // All optional with defaults so the band-based factories above stay untouched.
    var weights: [WeightRow]? = nil
    var weightsNote: LocalizedStringKey? = nil
    var method: Method? = nil
    var disclaimer: LocalizedStringKey? = nil
    var calibration: Calibration? = nil

    struct Band {
        let label: LocalizedStringKey
        let range: String
        let color: Color
        var isActive: Bool
    }

    /// One driver in the recovery weight breakdown: a labeled bar whose fill length and tint
    /// show how much it contributes to the score.
    struct WeightRow {
        let label: LocalizedStringKey
        let percent: Int
        let color: Color
    }

    /// The "See the method" disclosure: plain-language prose plus an optional citation line.
    struct Method {
        let prose: LocalizedStringKey
        let citation: LocalizedStringKey?
    }

    /// Cold-start: recovery isn't scored yet, so show progress toward the seed gate instead
    /// of a number.
    struct Calibration {
        let done: Int
        let needed: Int
    }
}

// MARK: - Static factories

extension MetricInfo {

    static func strain(_ value: Double?) -> MetricInfo {
        let bands: [Band] = [
            Band(label: "Rest / Light", range: "0 – 7",
                 color: StrandPalette.strain000,
                 isActive: value.map { $0 < 7 } ?? false),
            Band(label: "Moderate", range: "7 – 14",
                 color: StrandPalette.strain033,
                 isActive: value.map { $0 >= 7 && $0 < 14 } ?? false),
            Band(label: "Hard", range: "14 – 18",
                 color: StrandPalette.strain066,
                 isActive: value.map { $0 >= 14 && $0 < 18 } ?? false),
            Band(label: "Extreme", range: "18 – 21",
                 color: StrandPalette.strain100,
                 isActive: value.map { $0 >= 18 } ?? false),
        ]
        return MetricInfo(
            id: "strain",
            name: "Day Strain",
            headline: "Cardiovascular load scored 0–21. Each second of the day your heart rate is recorded, it's assigned to a zone (1–5). Higher zones carry more weight. The total is compressed logarithmically so 21 represents a theoretical maximum — a full day at peak intensity.",
            displayValue: value.map { String(format: "%.1f", $0) } ?? "—",
            unit: nil,
            currentColor: value.map { StrandPalette.strainColor($0) } ?? StrandPalette.textSecondary,
            bands: bands,
            note: nil
        )
    }

    static func sleep(_ totalMinutes: Int?) -> MetricInfo {
        let hours = totalMinutes.map { Double($0) / 60.0 }
        let bands: [Band] = [
            Band(label: "Short", range: "< 6 h",
                 color: StrandPalette.metricRose,
                 isActive: hours.map { $0 < 6 } ?? false),
            Band(label: "Adequate", range: "6 – 7 h",
                 color: StrandPalette.statusWarning,
                 isActive: hours.map { $0 >= 6 && $0 < 7 } ?? false),
            Band(label: "Optimal", range: "7 – 9 h",
                 color: StrandPalette.accent,
                 isActive: hours.map { $0 >= 7 && $0 <= 9 } ?? false),
            Band(label: "Extended", range: "> 9 h",
                 color: StrandPalette.textSecondary,
                 isActive: hours.map { $0 > 9 } ?? false),
        ]
        let display: String
        if let m = totalMinutes {
            let h = m / 60, min = m % 60
            display = min > 0 ? "\(h)h \(min)m" : "\(h)h"
        } else {
            display = "—"
        }
        return MetricInfo(
            id: "sleep",
            name: "Sleep",
            headline: "Total time asleep last night, estimated from movement and heart rate. Sleep contributes ~15% of your recovery score and feeds the strain-to-load balance (ACWR).",
            displayValue: display,
            unit: nil,
            currentColor: hours.map { h -> Color in
                switch h {
                case ..<6:   return StrandPalette.metricRose
                case ..<7:   return StrandPalette.statusWarning
                case ...9:   return StrandPalette.accent
                default:     return StrandPalette.textSecondary
                }
            } ?? StrandPalette.textSecondary,
            bands: bands,
            note: nil
        )
    }

    /// HRV (RMSSD, ms). Plain-language headline + the existing "it's personal" note, plus a
    /// "See the method" disclosure (reusing FER-108's component) with the real cleaning pipeline.
    /// When there's no reading, the note explains why instead of leaving a bare "—". (FER-109)
    static func hrv(_ value: Double?) -> MetricInfo {
        MetricInfo(
            id: "hrv",
            name: "HRV",
            headline: "HRV is how much the time between your heartbeats varies, in milliseconds, while you sleep. More variation usually means better recovery. What matters isn't the number itself, but how it compares with your own average.",
            displayValue: value.map { "\(Int($0.rounded()))" } ?? "—",
            unit: "ms",
            currentColor: StrandPalette.metricPurple,
            bands: [],
            note: value == nil
                ? "No HRV from last night. That can happen if you didn't wear the strap, or the night was too short to gather 20 clean beats."
                : "HRV is personal. There are no universal good/bad thresholds — only your trend over time.",
            method: Method(
                prose: "We take the intervals between your heartbeats overnight, drop any outside 300–2000 ms and any that deviate more than 20% from their neighbours (ectopic beats). If at least 20 clean beats remain, we compute RMSSD.",
                citation: "RMSSD (Task Force, 1996); ectopic rejection by Malik's rule. HRV is about 60% of your recovery score."
            )
        )
    }

    static func restingHR(_ value: Int?) -> MetricInfo {
        let bands: [Band] = [
            Band(label: "Athlete", range: "< 50 bpm",
                 color: StrandPalette.accent,
                 isActive: value.map { $0 < 50 } ?? false),
            Band(label: "Excellent", range: "50 – 60 bpm",
                 color: StrandPalette.accent,
                 isActive: value.map { $0 >= 50 && $0 < 60 } ?? false),
            Band(label: "Normal", range: "60 – 80 bpm",
                 color: StrandPalette.textSecondary,
                 isActive: value.map { $0 >= 60 && $0 < 80 } ?? false),
            Band(label: "Elevated", range: "> 80 bpm",
                 color: StrandPalette.statusWarning,
                 isActive: value.map { $0 >= 80 } ?? false),
        ]
        return MetricInfo(
            id: "rhr",
            name: "Resting HR",
            headline: "Your heart rate when your body is fully at rest — how hard your heart has to work doing nothing. Lower generally means a stronger, more efficient cardiovascular system. NOOP uses it as ~20% of your recovery score; a rise from your norm signals fatigue or illness.",
            displayValue: value.map { "\($0)" } ?? "—",
            unit: "bpm",
            currentColor: StrandPalette.metricRose,
            bands: bands,
            note: "Measured overnight from your strap; when the strap isn't worn, NOOP uses Apple Health's resting heart rate instead."
        )
    }

    static func spo2(_ value: Double?) -> MetricInfo {
        let bands: [Band] = [
            Band(label: "Normal", range: "95 – 100%",
                 color: StrandPalette.metricCyan,
                 isActive: value.map { $0 >= 95 } ?? false),
            Band(label: "Borderline", range: "90 – 94%",
                 color: StrandPalette.statusWarning,
                 isActive: value.map { $0 >= 90 && $0 < 95 } ?? false),
            Band(label: "Low", range: "< 90%",
                 color: StrandPalette.metricRose,
                 isActive: value.map { $0 < 90 } ?? false),
        ]
        return MetricInfo(
            id: "spo2",
            name: "Blood Oxygen",
            headline: "Percentage of haemoglobin carrying oxygen in your blood. Healthy adults typically stay above 95%. A drop can indicate altitude effects, sleep apnea, or respiratory illness.",
            displayValue: value.map { String(format: "%.0f", $0) } ?? "—",
            unit: "%",
            currentColor: StrandPalette.metricCyan,
            bands: bands,
            note: "Wrist-based sensors have lower accuracy than medical pulse oximeters — treat values as a trend, not a clinical reading."
        )
    }

    static func steps(_ value: Int?) -> MetricInfo {
        let bands: [Band] = [
            Band(label: "Sedentary", range: "< 5 000",
                 color: StrandPalette.textSecondary,
                 isActive: value.map { $0 < 5_000 } ?? false),
            Band(label: "Light", range: "5 000 – 8 000",
                 color: StrandPalette.metricCyan.opacity(0.7),
                 isActive: value.map { $0 >= 5_000 && $0 < 8_000 } ?? false),
            Band(label: "Active", range: "8 000 – 10 000",
                 color: StrandPalette.metricCyan,
                 isActive: value.map { $0 >= 8_000 && $0 < 10_000 } ?? false),
            Band(label: "Very active", range: "> 10 000",
                 color: StrandPalette.accent,
                 isActive: value.map { $0 >= 10_000 } ?? false),
        ]
        return MetricInfo(
            id: "steps",
            name: "Steps",
            headline: "Daily step count. Consistent activity — even a 30-minute walk — supports cardiovascular health, mood, and recovery quality.",
            displayValue: value.map { v in
                let f = NumberFormatter(); f.numberStyle = .decimal
                return f.string(from: NSNumber(value: v)) ?? "\(v)"
            } ?? "—",
            unit: nil,
            currentColor: StrandPalette.metricCyan,
            bands: bands,
            note: "Steps come from Apple Health and are not recorded by the WHOOP strap."
        )
    }

    /// Recovery (0–100) is a weighted composite, not a banded range, so it gets its own body:
    /// a weight breakdown + a "See the method" disclosure. Weights mirror `RecoveryScorer`
    /// (HRV .60 · RHR .20 · sleep .15 · skin-temp .10 · resp .05); the bars normalize to the
    /// top driver so the row reads as relative contribution. While the baseline is still seeding
    /// (`calibrationNights` non-nil) it shows honest progress instead of a made-up number. (FER-108)
    static func recovery(score: Int?, calibrationNights: Int?, nightsNeeded: Int) -> MetricInfo {
        let weights: [WeightRow] = [
            WeightRow(label: "HRV",         percent: 60, color: StrandPalette.recoveryColor(92)),
            WeightRow(label: "Resting HR",  percent: 20, color: StrandPalette.recoveryColor(74)),
            WeightRow(label: "Sleep",       percent: 15, color: StrandPalette.recoveryColor(60)),
            WeightRow(label: "Skin temp",   percent: 10, color: StrandPalette.recoveryColor(48)),
            WeightRow(label: "Respiration", percent:  5, color: StrandPalette.recoveryColor(40)),
        ]
        let weightsNote: LocalizedStringKey =
            "If a signal is missing on a given night, its weight is shared among the others."
        let disclaimer: LocalizedStringKey = "It's an estimate, not a diagnosis."

        if let done = calibrationNights {
            return MetricInfo(
                id: "recovery",
                name: "Recovery",
                headline: "We can't score your recovery yet. We need at least \(nightsNeeded) nights with your strap to learn your baseline; you're at \(done) of \(nightsNeeded). We'd rather not show you a made-up number.",
                displayValue: "\(done)/\(nightsNeeded)",
                unit: nil,
                currentColor: StrandPalette.textSecondary,
                bands: [],
                note: nil,
                weights: weights,
                weightsNote: weightsNote,
                method: nil,
                disclaimer: disclaimer,
                calibration: Calibration(done: done, needed: nightsNeeded)
            )
        }

        return MetricInfo(
            id: "recovery",
            name: "Recovery",
            headline: "Your recovery sums up how ready your body is today, from 0 to 100. It blends several signals from your night — your HRV above all — and compares them with your own average from recent weeks, not anyone else's.",
            displayValue: score.map { "\($0)" } ?? "—",
            unit: nil,
            currentColor: score.map { StrandPalette.recoveryColor(Double($0)) } ?? StrandPalette.textTertiary,
            bands: [],
            note: nil,
            weights: weights,
            weightsNote: weightsNote,
            method: Method(
                prose: "Each signal becomes a score of how far above or below your personal average it sits; they're averaged with the weights above and mapped onto a 0–100 scale, calibrated so a typical day lands near 58.",
                citation: "A composite of z-scores through a logistic curve. HRV via RMSSD (Task Force, 1996)."
            ),
            disclaimer: disclaimer,
            calibration: nil
        )
    }
}

// MARK: - MetricInfoSheet

struct MetricInfoSheet: View {
    let info: MetricInfo

    /// Loads today's accumulated-strain curve. Supplied only for the Day Strain sheet; nil for every
    /// other metric (and on macOS). Run lazily when the sheet appears. (FER-110)
    var strainCurveLoader: (() async -> [TrendPoint])? = nil

    @State private var strainCurve: [TrendPoint] = []
    @State private var strainLoading = false
    /// Measured natural height of the sheet's content — used to size the Day Strain detent to its
    /// content so it never opens taller than it needs to. (FER-112 follow-up)
    @State private var contentHeight: CGFloat = 0

    /// "See the method" disclosure — collapsed each time the sheet opens. (FER-108)
    @State private var methodExpanded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                Text(info.headline)
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let calibration = info.calibration { calibrationCard(calibration) }
                if let weights = info.weights {
                    weightsBlock(weights, note: info.weightsNote, dimmed: info.calibration != nil)
                }
                if !info.bands.isEmpty { bandsTable }
                if info.id == "strain" { strainSection }
                if let method = info.method { methodDisclosure(method) }
                if let note = info.note {
                    Text(note)
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let disclaimer = info.disclaimer {
                    Text(disclaimer)
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GeometryReader { g in
                Color.clear.preference(key: SheetContentHeightKey.self, value: g.size.height)
            })
        }
        .onPreferenceChange(SheetContentHeightKey.self) { contentHeight = $0 }
        .background(StrandPalette.surfaceBase)
        .presentationDetents(strainDetents)
        .presentationDragIndicator(.visible)
        .modifier(PresentationBackgroundModifier())
        .task {
            guard info.id == "strain", let loader = strainCurveLoader else { return }
            strainLoading = true
            strainCurve = await loader()
            strainLoading = false
        }
    }

    /// Day Strain carries the accumulation chart below the zones table, so the sheet is sized to its
    /// own content: it opens tall enough to show the whole chart and can't be dragged up into empty
    /// space (a single content-height detent). Until the first layout pass measures it, fall back to
    /// `.large`. Every other metric is short and stays compact at `.medium`. (FER-112 follow-up)
    private var strainDetents: Set<PresentationDetent> {
        guard info.id == "strain" else { return [.medium] }
        return contentHeight > 0 ? [.height(contentHeight)] : [.large]
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(info.name)
                .font(StrandFont.title2)
                .foregroundStyle(StrandPalette.textPrimary)
            Spacer()
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(info.displayValue)
                    .font(StrandFont.number(28))
                    .foregroundStyle(info.currentColor)
                if let unit = info.unit {
                    Text(unit)
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textTertiary)
                }
            }
        }
    }

    private var bandsTable: some View {
        VStack(spacing: 0) {
            ForEach(Array(info.bands.enumerated()), id: \.offset) { i, band in
                bandRow(band)
                if i < info.bands.count - 1 {
                    Divider().overlay(StrandPalette.hairline).padding(.leading, 36)
                }
            }
        }
        .background(StrandPalette.surfaceRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func bandRow(_ band: MetricInfo.Band) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(band.isActive ? band.color : band.color.opacity(0.35))
                .frame(width: 8, height: 8)
                .padding(.leading, 14)
            Text(band.label)
                .font(StrandFont.subhead)
                .foregroundStyle(band.isActive ? StrandPalette.textPrimary : StrandPalette.textSecondary)
            Spacer()
            Text(band.range)
                .font(StrandFont.captionNumber)
                .foregroundStyle(band.isActive ? band.color : StrandPalette.textTertiary)
            if band.isActive {
                Image(systemName: "arrowshape.left.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(band.color)
                    .padding(.trailing, 14)
            } else {
                Spacer().frame(width: 22)
            }
        }
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity)
        .background(band.isActive ? band.color.opacity(0.07) : Color.clear)
    }

    // MARK: - Day-strain accumulation chart (FER-110)

    /// "How today added up" — the day's strain building from 0 to the score in the header. Shows the
    /// curve once loaded, a quiet placeholder while loading, and a short message when there isn't
    /// enough of today's activity to chart.
    @ViewBuilder private var strainSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How today added up")
                .font(StrandFont.headline)
                .foregroundStyle(StrandPalette.textPrimary)
            if strainCurve.count > 1 {
                TrendChart(
                    points: strainCurve,
                    gradient: StrandPalette.strainGradient,
                    valueRange: strainCurveRange,
                    showsArea: true,
                    height: 132,
                    showsHover: true,
                    valueFormat: { String(format: "%.1f", $0) },
                    dateFormat: { Self.hourString($0) }
                )
                .accessibilityElement()
                .accessibilityLabel(Text("Accumulated day strain, rising through the day."))
            } else if strainLoading {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(StrandPalette.surfaceRaised)
                    .frame(height: 132)
                    .overlay { ProgressView().tint(StrandPalette.textTertiary) }
            } else {
                strainEmpty
            }
        }
    }

    private var strainEmpty: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 22))
                .foregroundStyle(StrandPalette.textTertiary)
            Text("Not enough activity yet today to chart.")
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .background(StrandPalette.surfaceRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// Auto-scale the Y axis to the day's own buildup (0 → a little above the peak) so a low-strain
    /// day still reads as a clear curve instead of a flat line pinned to the 0–21 floor.
    private var strainCurveRange: ClosedRange<Double> {
        let peak = strainCurve.map(\.value).max() ?? 1
        return 0...max(peak * 1.15, 1)
    }

    private static let hourFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("j")   // locale hour, 12/24h per region
        return f
    }()
    private static func hourString(_ date: Date) -> String { hourFormatter.string(from: date) }

    // MARK: - Recovery weight breakdown + method disclosure (FER-108)

    /// Cold-start progress: "Calibrating baseline" over a thin accent track, shown instead of a
    /// score while the recovery baseline is still seeding.
    private func calibrationCard(_ cal: MetricInfo.Calibration) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Calibrating baseline").strandOverline()
                Spacer()
                Text("\(cal.done) of \(cal.needed) nights")
                    .font(StrandFont.captionNumber)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(StrandPalette.surfaceInset).frame(height: 6)
                    Capsule().fill(StrandPalette.accent)
                        .frame(width: max(6, geo.size.width * CGFloat(cal.done) / CGFloat(max(cal.needed, 1))),
                               height: 6)
                }
            }
            .frame(height: 6)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StrandPalette.surfaceRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// The weight breakdown — one labeled bar per driver, longest = top contributor. A single
    /// raised surface, no per-row rules: bar length already separates the rows (Tufte). Dimmed
    /// while calibrating, since the method exists but doesn't apply yet.
    private func weightsBlock(_ weights: [MetricInfo.WeightRow], note: LocalizedStringKey?, dimmed: Bool) -> some View {
        let maxPct = max(weights.map(\.percent).max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(weights.enumerated()), id: \.offset) { _, w in
                weightRow(w, fraction: Double(w.percent) / Double(maxPct))
            }
            if let note {
                Text(note)
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StrandPalette.surfaceRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .opacity(dimmed ? StrandPalette.disabledOpacity : 1)
    }

    private func weightRow(_ w: MetricInfo.WeightRow, fraction: Double) -> some View {
        HStack(spacing: 10) {
            Text(w.label)
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textPrimary)
                .lineLimit(1)
                .frame(width: 96, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(StrandPalette.surfaceInset).frame(height: 8)
                    Capsule().fill(w.color)
                        .frame(width: max(8, geo.size.width * CGFloat(fraction)), height: 8)
                }
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 8)
            Text(verbatim: "\(w.percent)%")
                .font(StrandFont.captionNumber)
                .foregroundStyle(StrandPalette.textSecondary)
                .frame(width: 40, alignment: .trailing)
        }
    }

    /// Progressive disclosure: the technical "how" lives one tap down, collapsed by default.
    private func methodDisclosure(_ method: MetricInfo.Method) -> some View {
        DisclosureGroup(isExpanded: $methodExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                Divider().overlay(StrandPalette.hairline)
                Text(method.prose)
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let citation = method.citation {
                    Text(citation)
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text("See the method")
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textPrimary)
        }
        .tint(StrandPalette.textTertiary)
        .padding(14)
        .background(StrandPalette.surfaceRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Helpers

/// Carries the sheet content's measured natural height up to size the Day Strain detent. (FER-112)
private struct SheetContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct PresentationBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 13.3, iOS 16.4, *) {
            content.presentationBackground(StrandPalette.surfaceBase)
        } else {
            content
        }
    }
}

// MARK: - Preview

#if DEBUG
/// A rising sample curve from local midnight, ending at `score`, for previews/renders.
private func sampleStrainCurve(score: Double) -> [TrendPoint] {
    let midnight = Calendar.current.startOfDay(for: Date())
    let shape: [(h: Double, f: Double)] = [
        (0, 0), (6.5, 0.09), (8, 0.19), (10, 0.32), (12, 0.49),
        (12.75, 0.67), (13.25, 0.80), (14, 0.90), (15, 1.0),
    ]
    return shape.map { p in
        TrendPoint(date: midnight.addingTimeInterval(p.h * 3600), value: score * p.f)
    }
}

#Preview("MetricInfoSheet — Strain (curve)") {
    Color.clear.sheet(isPresented: .constant(true)) {
        MetricInfoSheet(info: .strain(11.5),
                        strainCurveLoader: { sampleStrainCurve(score: 11.5) })
    }
    .preferredColorScheme(.dark)
}

#Preview("MetricInfoSheet — Strain (no data)") {
    Color.clear.sheet(isPresented: .constant(true)) {
        MetricInfoSheet(info: .strain(3.9))
    }
    .preferredColorScheme(.dark)
}

#Preview("MetricInfoSheet — HRV") {
    Color.clear.sheet(isPresented: .constant(true)) {
        MetricInfoSheet(info: .hrv(66))
    }
    .preferredColorScheme(.dark)
}

#Preview("MetricInfoSheet — HRV (no data)") {
    Color.clear.sheet(isPresented: .constant(true)) {
        MetricInfoSheet(info: .hrv(nil))
    }
    .preferredColorScheme(.dark)
}

#Preview("MetricInfoSheet — SpO₂") {
    Color.clear.sheet(isPresented: .constant(true)) {
        MetricInfoSheet(info: .spo2(97))
    }
    .preferredColorScheme(.dark)
}

#Preview("MetricInfoSheet — Recovery") {
    Color.clear.sheet(isPresented: .constant(true)) {
        MetricInfoSheet(info: .recovery(score: 92, calibrationNights: nil, nightsNeeded: 4))
    }
    .preferredColorScheme(.dark)
}

#Preview("MetricInfoSheet — Recovery (calibrating)") {
    Color.clear.sheet(isPresented: .constant(true)) {
        MetricInfoSheet(info: .recovery(score: nil, calibrationNights: 2, nightsNeeded: 4))
    }
    .preferredColorScheme(.dark)
}
#endif
