#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore
import WhoopProtocol
import Foundation

// MARK: - SleepDetailScreen — el «Detalle de Sueño» en esqueleto «Tendencias Final» (FER-858)
//
// Hermana de `RecoveryDetailScreen` (FER-857): el mismo andamiaje del handoff «Detalle de
// Tendencias Final» — héroe invertido (hue fijo `dataSleep`) → Anoche (hipnograma) → Forma de
// la noche → Anoche vs tu típico → Métricas → Reserva para bajar de marcha → Deuda → Historial
// (`GraficaRangos`) → Calendario 90 noches → Método + sello. Solo presentación: reusa
// `SleepDetailModel` + `NightAutonomicShape` + `NocturnalDC` TAL CUAL; no toca motores.
//
// Se presenta vía `.sheet(item:)` con el tema vivo pasado EXPLÍCITO (no propaga por `.sheet`,
// FER-162) y SIN `NavigationStack` anidado (FER-171).

/// Light «Instrumento» Detalle de Sueño. Built once from a `SleepDetailModel` (the caller injects
/// the model so the screen stays DB-free), themed explicitly for the sheet boundary.
struct SleepDetailScreen: View {
    /// The live «Instrumento» theme, passed explicitly (sheets start a fresh environment). (FER-162)
    var theme: InstrumentoTheme = .base
    /// Everything the screen draws, derived ONCE by the caller from `repo` (no DB access here).
    let model: SleepDetailModel
    /// Loads the night's HR samples for a `[from, to)` window — injected by the caller (which owns
    /// `repo`) so the screen stays DB-free. The night-shape block (FER-832) needs the raw 1 Hz HR.
    var loadNightHR: (_ from: Int, _ to: Int) async -> [HRSample] = { _, _ in [] }
    /// Loads the night's raw R-R intervals for a `[from, to)` window — injected for nocturnal DC
    /// («reserva para bajar de marcha», FER-849). Empty by default.
    var loadNightRR: (_ from: Int, _ to: Int) async -> [RRInterval] = { _, _ in [] }
    /// Loads the user's recent DC baseline (ms) for the trend read. nil ⇒ no "vs your normal".
    var loadDCBaseline: () async -> Double? = { nil }

    /// The metric whose info card is open (tap a Tonight's-metrics tile). (FER-227)
    @State private var metricInfo: MetricInfo?
    /// Whether the combined "Sleep stages" explainer card is open (from «See the method»). (FER-227)
    @State private var showStages = false
    /// The hero's ⓘ toggles the «Qué medimos» card under the inverted field. (FER-858)
    @State private var infoOpen = false
    /// The duration history's period window. Defaults to a month.
    @State private var range: ExploreRange = .month
    /// Duration series with each day key parsed once in `.task`.
    @State private var durationParsed: [(day: String, date: Date?, value: Double)] = []
    /// The 90-night heat grid, built ONCE in `.task` (90 `DateFormatter` passes) instead of on every
    /// body eval — the recompute was jank on open. (FER-878+)
    @State private var sleepHeatCache: [RecoveryDay] = []
    /// The tapped night for the calendar read-out. (FER-830)
    @State private var selectedSleepNight: RecoveryDay? = nil
    /// The nocturnal HR-fall shape — loaded async; `nil` until loaded or when unreadable. (FER-832)
    @State private var nightShape: NightAutonomicShape.Result? = nil
    /// Downsampled HR series (asleep window) for the fall curve. Built with the shape. (FER-832)
    @State private var nightShapeCurve: [Double] = []
    /// Nocturnal Deceleration Capacity (FER-849). `nil` until loaded / Apple-only / no R-R.
    @State private var nightDC: NocturnalDC.Result? = nil

    // MARK: - Body — esqueleto estándar «Detalle de Tendencias Final» (FER-858)
    //
    // Héroe invertido → Anoche → Forma de la noche → Anoche vs tu típico → Métricas →
    // Reserva → Deuda → Historial → Calendario 90 noches → Método + sello.

    var body: some View {
        ScrollView {
            // FER-964: Lazy so the model reveal (FER-953 swap) only builds the visible sections —
            // an eager VStack laid out the whole fold (charts + Calendario 90 + método) in one frame.
            LazyVStack(alignment: .leading, spacing: 0) {
                if let night = model.night {
                    heroField(night)
                    if infoOpen { whatWeMeasureCard }
                    seccion(String(localized: "Last night")) { lastNightContent(night) }
                    if let shape = nightShape {
                        seccion(String(localized: "Night shape")) { nightShapeContent(shape) }
                    }
                    seccion(String(localized: "Last night vs your typical")) { stagesVsTypicalContent(night) }
                    seccion(String(localized: "Tonight's metrics")) { nightMetricsContent(night) }
                    if let dc = nightDC, dc.confidence != .unreadable {
                        seccion(String(localized: "Braking reserve"),
                                pista: String(localized: "EXPERIMENTAL")) {
                            nightDCContent(dc)
                        }
                    }
                    if let debt = model.weeklyDebtMinutes, debt >= 15, model.weeklyDebtNights.count >= 2 {
                        seccion(String(localized: "Weekly debt")) { weeklyDebtContent(debt) }
                    }
                    if durationParsed.count >= 2 {
                        seccion(String(localized: "History")) { trendContent }
                    }
                    if durationParsed.contains(where: { $0.value > 0 }) {
                        seccion(String(localized: "Calendar · 90 nights")) { calendarContent }
                    }
                    PieMetodo(theme: theme) {
                        metodoBlock
                    } sello: {
                        sourceFooter
                    }
                } else if !model.loaded {
                    Group {
                        heroFlat
                        ChartWell(theme).loading(height: 160).padding(.top, 22)
                    }
                    .padding(CenitMetrics.screenPadding)
                } else {
                    heroFlat.padding(CenitMetrics.screenPadding)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.paper)
        .presentationDragIndicator(.visible)
        .sheetPaper(theme)
        // FER-953: re-run when the placeholder model is replaced by the real one; parse + heat off-main.
        .task(id: model.loaded) {
            guard model.loaded else { return }   // placeholder pass — nothing to parse yet (FER-953)
            range = .month
            let series = model.durationSeries
            let todayKey = Repository.localDayKey(Date())   // main-isolated: resolve before the hop
            let (parsed, heat) = await Task.detached(priority: .userInitiated) {
                (series.map { ($0.day, Repository.parseDayKey($0.day), $0.value) },
                 Self.buildSleepHeat(durationSeries: series, todayKey: todayKey))
            }.value
            durationParsed = parsed
            sleepHeatCache = heat
        }
        .task(id: model.night?.startTs) {
            let (shape, curve) = await loadNightShape()
            nightShape = shape
            nightShapeCurve = curve
        }
        .task(id: model.night?.startTs) {
            nightDC = await loadNightDC()
        }
        .sheet(item: $metricInfo) { info in
            MetricInfoSheet(info: info, theme: theme, trendLoader: trendLoader(for: info.id))
        }
        .sheet(isPresented: $showStages) {
            SleepStagesInfoSheet(theme: theme)
        }
    }

    /// One skeleton section: shared `SeccionBloque` (franja + handoff padding 14 · 20 · 22).
    private func seccion(_ title: String, pista: String? = nil,
                         @ViewBuilder content: () -> some View) -> some View {
        SeccionBloque(title, pista: pista, theme: theme, content: content)
    }

    // MARK: - 1. Héroe invertido — hue fijo `dataSleep` (no semáforo)

    /// Inverted hero: the ONE field at 100% indigo. Double datum (hours | regularity) + two-level verdict.
    private func heroField(_ night: SleepDetailModel.Night) -> some View {
        HeroInvertido(
            glyph: .sleep,
            title: "Sleep",
            hue: theme.dataSleep,
            theme: theme,
            onInfo: { withAnimation(StrandMotion.interactive) { infoOpen.toggle() } },
            numeral: {
                // Dual 44pt datum (hours | regularity). Not HeroNumeral: compound layout.
                HStack(alignment: .center, spacing: 0) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(hoursOnly(night.stages.asleep))
                            .font(InstrumentoType.groteskNumber(44, weight: .bold))
                            .tracking(-1.2)
                            .foregroundStyle(theme.paper)
                            .monospacedDigit()
                            .recRise()
                        Text("hours")
                            .font(InstrumentoType.grotesk(10, weight: .semibold))
                            .tracking(1.2)
                            .textCase(.uppercase)
                            .foregroundStyle(theme.paper.opacity(OnFieldOpacity.secondary))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Rectangle()
                        .fill(theme.paper.opacity(OnFieldOpacity.divider))
                        .frame(width: 1, height: 52)
                    VStack(alignment: .leading, spacing: 4) {
                        if let r = model.regularity {
                            HStack(alignment: .firstTextBaseline, spacing: 2) {
                                Text("\(r.score)")
                                    .font(InstrumentoType.groteskNumber(44, weight: .bold))
                                    .tracking(-1.2)
                                    .foregroundStyle(theme.paper)
                                    .monospacedDigit()
                                    .recRise(second: true)
                                Text(verbatim: "/100")
                                    .font(InstrumentoType.grotesk(13))
                                    .foregroundStyle(theme.paper.opacity(OnFieldOpacity.secondary))
                            }
                        } else {
                            Text(verbatim: "—")
                                .font(InstrumentoType.groteskNumber(44, weight: .bold))
                                .foregroundStyle(theme.paper.opacity(OnFieldOpacity.secondary))
                                .recRise(second: true)
                        }
                        Text("regularity")
                            .font(InstrumentoType.grotesk(10, weight: .semibold))
                            .tracking(1.2)
                            .textCase(.uppercase)
                            .foregroundStyle(theme.paper.opacity(OnFieldOpacity.secondary))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 16)
                }
            },
            verdict: {
                // Dynamic String (already localized via String(localized:)); HeroVeredictoBicolor
                // takes LocalizedStringKey and would re-key lookup. Keep verbatim markup.
                (Text(verbatim: heroVerdictTitle(night))
                    .font(InstrumentoType.grotesk(15, weight: .semibold))
                    .foregroundColor(theme.paper)
                 + Text(verbatim: " · ")
                    .font(InstrumentoType.grotesk(14))
                    .foregroundColor(theme.paper.opacity(OnFieldOpacity.secondary))
                 + Text(verbatim: heroVerdictClause(night))
                    .font(InstrumentoType.grotesk(14))
                    .foregroundColor(theme.paper.opacity(OnFieldOpacity.secondary)))
                    .fixedSize(horizontal: false, vertical: true)
            },
            trailing: {
                VStack(alignment: .leading, spacing: 8) {
                    if model.excludedNapCount > 0 {
                        Text(napNotice)
                            .font(InstrumentoType.grotesk(11))
                            .foregroundStyle(theme.paper.opacity(OnFieldOpacity.secondary))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let tier = model.confidence {
                        tier.sello(theme: theme, onField: true)
                            .padding(.top, 2)
                    }
                }
            }
        )
    }

    /// The ⓘ card under the hero: what the score measures, in plain language (mock FER-858).
    private var whatWeMeasureCard: some View {
        QueMedimosCard(title: "What we measure", explanation: heroExplanation, theme: theme)
    }

    /// Flat hero for empty / loading: no inverted field without a night.
    private var heroFlat: some View {
        VStack(alignment: .leading, spacing: 10) {
            InstrumentoScreenTitle("Sleep", theme: theme, explanation: heroExplanation, glyph: .sleep)
            VStack(alignment: .leading, spacing: 10) {
                Text(verbatim: "—")
                    .instrumentoHero(46)
                    .foregroundStyle(theme.inkTertiary)
                Text(model.loaded
                     ? "No nights yet. Import your WHOOP export, or connect Apple Health, in Data Sources to see your sleep stages and trends. Or wear the strap to bed and open it again after the strap syncs."
                     : "Loading your sleep history…")
                    .font(StrandFont.headline)
                    .foregroundStyle(theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Hero ⓘ copy: regularity = mid-sleep point movement; naps don't count; need = 7–9 h target.
    private var heroExplanation: LocalizedStringKey {
        "Regularity is how much your mid-sleep point moves night to night (the midpoint between falling asleep and waking): it predicts your health better than total hours. Naps don't count. \"Need\" is the 7–9 h target, not a measurement of you."
    }

    /// Two-level verdict title (sufficiency + schedule), from the same model words as before.
    private func heroVerdictTitle(_ night: SleepDetailModel.Night) -> String {
        let perf = model.performancePct.map { Int(min(100, $0).rounded()) }
        let suff = sufficiencyWord(perf)
        if let r = model.regularity {
            return String(localized: "\(suff) and \(scheduleWord(r.score))")
        }
        return suff
    }

    /// Quiet second clause of the hero verdict (need % + regularity word, or calibration note).
    private func heroVerdictClause(_ night: SleepDetailModel.Night) -> String {
        let perf = model.performancePct.map { Int(min(100, $0).rounded()) }
        if let r = model.regularity, let p = perf {
            return String(localized: "\(p)% of your need, \(regularityWordText(r.score)) rhythm")
        }
        if let r = model.regularity {
            return String(localized: "\(regularityWordText(r.score)) rhythm")
        }
        if let p = perf {
            return String(localized: "\(p)% of your need")
        }
        if model.regularity == nil {
            let missing = max(0, SleepRegularity.minNights - model.regularityNights)
            return String(localized: "Still learning your schedule · \(missing) nights to go")
        }
        return String(localized: "Last night, logged.")
    }

    private func sufficiencyWord(_ perf: Int?) -> String {
        guard let p = perf else { return String(localized: "Logged") }
        if p >= 90 { return String(localized: "Enough") }
        if p >= 75 { return String(localized: "Almost enough") }
        return String(localized: "Short on sleep")
    }

    private func scheduleWord(_ score: Int) -> String {
        switch score {
        case 80...:   return String(localized: "right on schedule")
        case 55..<80: return String(localized: "fairly on schedule")
        default:      return String(localized: "on a shifting schedule")
        }
    }

    private func regularityWordText(_ score: Int) -> String {
        switch score {
        case 80...:   return String(localized: "very regular")
        case 55..<80: return String(localized: "regular")
        default:      return String(localized: "variable")
        }
    }

    // MARK: - 2. Anoche — hipnograma (instrumento firma) + tiles de etapa

    private func lastNightContent(_ night: SleepDetailModel.Night) -> some View {
        let s = night.stages
        return VStack(alignment: .leading, spacing: 12) {
            lastNightHeader(night)
            if model.intervals.count >= 2 {
                Hypnogram(intervals: model.intervals,
                          height: 176,
                          showsStageAxis: true,
                          showsScrub: true,
                          nightStart: night.onsetDate,
                          stageColor: { stage in
                              switch stage {
                              case .awake: return theme.dataSleepAwake
                              case .rem:   return theme.dataSleepLight
                              case .light: return theme.dataSleepLightest
                              case .deep:  return theme.dataSleepDeep
                              }
                          })
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .instrumentoCard(.card, theme: theme)
            } else {
                stageBar(s)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .instrumentoCard(.card, theme: theme)
                if model.isAppleHealth {
                    HStack(spacing: 6) {
                        StrandIcon.heart.image
                            .font(StrandFont.glyph(.chevron))
                            .foregroundStyle(theme.dataSpO2)
                        Text("Apple Health")
                            .font(StrandFont.footnote)
                            .foregroundStyle(theme.inkTertiary)
                    }
                }
            }
        }
    }

    /// Header for «Last night»: the shape of the night in words + the clock. The per-stage breakdown that
    /// used to live here as four tiles is gone — «Last night vs your typical» below already draws the same
    /// stages, against your average, as bars (no need to say it twice). Left: cycle count and how much of
    /// the night was awake. Right: the wall-clock the strap saw — asleep at / awake at. Apple-Health nights
    /// carry no reliable per-epoch clock, so the times hide there, same as the hypnogram. (FER · Anoche)
    private func lastNightHeader(_ night: SleepDetailModel.Night) -> some View {
        let awakePct = pct(night.stages.awake, night.stages.total)
        let title = remBoutCount.flatMap { $0 > 0 ? $0 : nil }
            .map { String(localized: "Night · \($0) cycles") } ?? String(localized: "Night")
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: title)
                    .font(InstrumentoType.grotesk(16, weight: .semibold))
                    .foregroundColor(theme.ink)
                Text(String(localized: "\(awakePct)% awake"))
                    .font(InstrumentoType.grotesk(14))
                    .foregroundColor(theme.inkSecondary)
            }
            Spacer(minLength: 0)
            if !model.isAppleHealth {
                VStack(alignment: .trailing, spacing: 3) {
                    clockLine(String(localized: "Asleep"), night.onsetDate)
                    clockLine(String(localized: "Awake"),
                              Date(timeIntervalSince1970: TimeInterval(night.endTs)))
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// One right-aligned clock line: a quiet label + the wall-clock time (locale-aware 12/24 h).
    private func clockLine(_ label: String, _ date: Date) -> some View {
        HStack(spacing: 5) {
            Text(verbatim: label)
                .font(InstrumentoType.grotesk(13))
                .foregroundColor(theme.inkTertiary)
            Text(verbatim: Self.clockFmt.string(from: date))
                .font(InstrumentoType.grotesk(14, weight: .semibold))
                .foregroundColor(theme.ink)
                .monospacedDigit()
        }
    }

    private static let clockFmt: DateFormatter = {
        let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none; return f
    }()

    /// Count contiguous REM bouts from the existing hypnogram intervals (presentation only).
    private var remBoutCount: Int? {
        guard !model.intervals.isEmpty else { return nil }
        var n = 0
        var inRem = false
        for iv in model.intervals.sorted(by: { $0.start < $1.start }) {
            if iv.stage == .rem {
                if !inRem { n += 1; inRem = true }
            } else {
                inRem = false
            }
        }
        return n
    }

    private func stageColor(_ stage: SleepStage) -> Color {
        switch stage {
        case .deep:  return theme.dataSleepDeep
        case .light: return theme.dataSleepLightest
        case .rem:   return theme.dataSleepLight
        case .awake: return theme.dataSleepAwake
        }
    }

    /// Full-width proportional stacked stage bar (fallback when there are no epoch segments).
    @ViewBuilder
    private func stageBar(_ s: SleepDetailModel.Stages) -> some View {
        let total = max(1, s.total)
        GeometryReader { geo in
            HStack(spacing: 2) {
                stageSegment(.deep, s.deep, total, geo.size.width)
                stageSegment(.light, s.light, total, geo.size.width)
                stageSegment(.rem, s.rem, total, geo.size.width)
                stageSegment(.awake, s.awake, total, geo.size.width)
            }
        }
        .frame(height: 30)
        .clipShape(RoundedRectangle(cornerRadius: CenitMetrics.chipRadius, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Sleep stages: deep \(pct(s.deep, s.total)) percent, light \(pct(s.light, s.total)) percent, REM \(pct(s.rem, s.total)) percent, awake \(pct(s.awake, s.total)) percent"))
    }

    @ViewBuilder
    private func stageSegment(_ stage: SleepStage, _ minutes: Double, _ total: Double, _ width: CGFloat) -> some View {
        Rectangle()
            .fill(stageColor(stage))
            .frame(width: max(0, CGFloat(minutes / total) * width))
    }

    // MARK: - 3. Forma de la noche (FER-832) — promovida a sección estándar

    @ViewBuilder
    private func nightShapeContent(_ shape: NightAutonomicShape.Result) -> some View {
        if shape.confidence == .unreadable {
            Text("There isn't enough signal tonight to read how your heart eased off.")
                .font(StrandFont.caption)
                .foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: "−\(Int(shape.dipPct.rounded()))%")
                        .font(InstrumentoType.groteskNumber(24, weight: .bold))
                        .foregroundStyle(theme.dataHeart)
                        .monospacedDigit()
                    Text("your pulse dropped as you fell asleep")
                        .font(InstrumentoType.grotesk(13))
                        .foregroundStyle(theme.inkSecondary)
                }
                if nightShapeCurve.count >= 2 {
                    // Line in `dataHeart`; area wash fades to transparent via Sparkline's own area path.
                    Sparkline(values: nightShapeCurve,
                              gradient: Gradient(colors: [theme.dataHeart, theme.dataHeart]),
                              lineWidth: 2,
                              showsArea: true,
                              showsHead: true,
                              showsScrub: false)
                        .frame(height: 64)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .recFade()
                        .accessibilityHidden(true)
                }
                HStack(alignment: .top, spacing: 8) {
                    TileSurface(label: String(localized: "lowest point"),
                                value: clockLabel(shape.nadirHour),
                                valueSize: 15, theme: theme)
                    if model.rhrBaseline != nil {
                        TileSurface(label: String(localized: "below your resting"),
                                    value: "\(Int((shape.fractionBelowRHR * 100).rounded()))%",
                                    valueSize: 15,
                                    caption: String(localized: "of the night"),
                                    theme: theme)
                    }
                }
                BarraAncla(String(localized: String.LocalizationValue(dipCopyKey(shape.dipShape))),
                           color: theme.dataHeart, theme: theme)
            }
        }
    }

    private func dipCopyKey(_ shape: NightAutonomicShape.DipShape) -> String {
        switch shape {
        case .pronounced:
            return "A marked, early drop: a sign you settled into rest. It's a pattern, not a diagnosis."
        case .moderate:
            return "A moderate drop overnight. It's a pattern, not a diagnosis."
        case .blunted:
            return "A gentler drop than a deep-rest night usually shows. It's a pattern, not a diagnosis."
        }
    }

    private static let clockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }()

    private func clockLabel(_ hour: Double) -> String {
        var h = Int(hour) % 24
        var m = Int(((hour - Double(Int(hour))) * 60).rounded())
        if m == 60 { m = 0; h = (h + 1) % 24 }
        var comps = DateComponents(); comps.hour = h; comps.minute = m
        let cal = Calendar.current
        if let date = cal.date(from: comps) {
            return Self.clockFormatter.string(from: date)
        }
        return String(format: "%d:%02d", h, m)
    }

    // MARK: - 4. Anoche vs tu típico — barras con marca de promedio

    private func stagesVsTypicalContent(_ night: SleepDetailModel.Night) -> some View {
        let s = night.stages
        return VStack(alignment: .leading, spacing: 12) {
            vsTypicalVerdictText(s)
                .fixedSize(horizontal: false, vertical: true)
            stageVsTypicalRow("Deep", lastMin: s.deep, total: s.total,
                              typicalPct: model.typicalDeepPct, color: theme.dataSleepDeep,
                              higherIsBetter: true, index: 0)
            stageVsTypicalRow("REM", lastMin: s.rem, total: s.total,
                              typicalPct: model.typicalRemPct, color: theme.dataSleepLight,
                              higherIsBetter: true, index: 1)
            stageVsTypicalRow("Light", lastMin: s.light, total: s.total,
                              typicalPct: model.typicalLightPct, color: theme.dataSleepLightest,
                              higherIsBetter: false, index: 2)
            BarraAncla(String(localized: "The mark is your average."),
                       color: theme.ink, theme: theme)
        }
    }

    /// Stage-name portion(s) in `theme.dataSleep`; rest of the phrase in `theme.ink`.
    /// Uses the same five localized full strings as before (no new copy keys).
    private func vsTypicalVerdictText(_ s: SleepDetailModel.Stages) -> Text {
        let font = InstrumentoType.grotesk(16, weight: .semibold)
        let deep = stageShareAbove(s.deep, s.total, model.typicalDeepPct)
        let rem = stageShareAbove(s.rem, s.total, model.typicalRemPct)
        let full: String
        let stageNames: [String]
        if deep && rem {
            full = String(localized: "Deep and REM above your typical")
            stageNames = [String(localized: "Deep"), String(localized: "REM")]
        } else if deep {
            full = String(localized: "Deep above your typical")
            stageNames = [String(localized: "Deep")]
        } else if rem {
            full = String(localized: "REM above your typical")
            stageNames = [String(localized: "REM")]
        } else if let light = model.typicalLightPct {
            let last = s.total > 0 ? s.light / s.total * 100 : 0
            if last > light + 1 {
                full = String(localized: "More light sleep than your typical")
                // EN source phrase uses "light sleep"; es-MX uses "sueño ligero".
                let candidates = ["light sleep", "sueño ligero"]
                stageNames = candidates.filter { full.range(of: $0, options: .caseInsensitive) != nil }
            } else {
                full = String(localized: "Close to your typical stage mix")
                stageNames = []
            }
        } else {
            full = String(localized: "Close to your typical stage mix")
            stageNames = []
        }
        return coloredStageVerdict(full: full, stageNames: stageNames, font: font)
    }

    /// Walks `full` and paints each occurrence of a stage name in `theme.dataSleep`.
    private func coloredStageVerdict(full: String, stageNames: [String], font: Font) -> Text {
        guard !stageNames.isEmpty else {
            return Text(verbatim: full)
                .font(font)
                .foregroundColor(theme.ink)
        }
        // Collect non-overlapping matches, left-to-right.
        var matches: [(range: Range<String.Index>, name: String)] = []
        for name in stageNames {
            var searchFrom = full.startIndex
            while searchFrom < full.endIndex,
                  let r = full.range(of: name, options: .caseInsensitive, range: searchFrom..<full.endIndex) {
                let overlaps = matches.contains { $0.range.overlaps(r) }
                if !overlaps { matches.append((r, name)) }
                searchFrom = r.upperBound
            }
        }
        matches.sort { $0.range.lowerBound < $1.range.lowerBound }
        guard !matches.isEmpty else {
            return Text(verbatim: full)
                .font(font)
                .foregroundColor(theme.ink)
        }
        var result: Text?
        var cursor = full.startIndex
        for m in matches {
            if cursor < m.range.lowerBound {
                let plain = String(full[cursor..<m.range.lowerBound])
                let t = Text(verbatim: plain).font(font).foregroundColor(theme.ink)
                result = result.map { $0 + t } ?? t
            }
            let stage = String(full[m.range])
            let t = Text(verbatim: stage).font(font).foregroundColor(theme.dataSleep)
            result = result.map { $0 + t } ?? t
            cursor = m.range.upperBound
        }
        if cursor < full.endIndex {
            let plain = String(full[cursor...])
            let t = Text(verbatim: plain).font(font).foregroundColor(theme.ink)
            result = result.map { $0 + t } ?? t
        }
        return result ?? Text(verbatim: full).font(font).foregroundColor(theme.ink)
    }

    private func stageShareAbove(_ min: Double, _ total: Double, _ typical: Double?) -> Bool {
        guard let typical, total > 0 else { return false }
        return (min / total * 100) > typical + 0.5
    }

    @ViewBuilder
    private func stageVsTypicalRow(_ label: LocalizedStringKey, lastMin: Double, total: Double,
                                   typicalPct: Double?, color: Color,
                                   higherIsBetter: Bool, index: Int) -> some View {
        let lastPct = total > 0 ? lastMin / total * 100 : 0
        let scaleMax = max(lastPct, typicalPct ?? 0) * 1.18
        let denom = scaleMax > 0 ? scaleMax : 1
        let deltaText: String? = {
            guard let typicalPct else { return nil }
            let diff = Int((lastPct - typicalPct).rounded())
            if diff == 0 { return "~0" }
            return diff > 0 ? "+\(abs(diff))" : "−\(abs(diff))"
        }()
        let improves: Bool = {
            guard let typicalPct else { return true }
            let diff = lastPct - typicalPct
            return higherIsBetter ? diff >= 0 : diff <= 0
        }()
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(InstrumentoType.grotesk(10, weight: .semibold))
                    .tracking(1.1)
                    .textCase(.uppercase)
                    .foregroundStyle(theme.inkTertiary)
                Spacer()
                Text("\(Int(lastPct.rounded()))%")
                    .font(InstrumentoType.groteskNumber(12, weight: .medium))
                    .foregroundStyle(theme.ink)
                    .monospacedDigit()
                if let deltaText {
                    Text(deltaText)
                        .font(InstrumentoType.groteskNumber(11, weight: .semibold))
                        .foregroundStyle(improves ? theme.verdict : theme.warning)
                        .monospacedDigit()
                }
            }
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(theme.trackWarm)
                        .frame(height: 10)
                    Capsule(style: .continuous)
                        .fill(color)
                        .frame(width: w * CGFloat(min(1, lastPct / denom)), height: 10)
                        .recGrow(index: index, origin: .leading)
                    if let typicalPct, typicalPct > 0 {
                        Rectangle()
                            .fill(theme.ink)
                            .frame(width: 2, height: 14)
                            .position(x: w * CGFloat(min(1, typicalPct / denom)), y: 5)
                    }
                }
            }
            .frame(height: 10)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(stageAccessibilityLabel(label, lastPct: lastPct, typicalPct: typicalPct))
        }
    }

    private func stageAccessibilityLabel(_ label: LocalizedStringKey, lastPct: Double, typicalPct: Double?) -> Text {
        let head = Text("\(Text(label)), \(Int(lastPct.rounded()))% last night")
        guard let typicalPct else { return head }
        return head + Text(", typical \(Int(typicalPct.rounded()))%")
    }

    // MARK: - 5. Métricas de la noche (grid 6 tiles; respiración promovida aquí)

    private func nightMetricsContent(_ night: SleepDetailModel.Night) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                  alignment: .leading, spacing: 8) {
            metricTileButton(label: String(localized: "Performance"),
                             value: model.performancePct.map { "\(Int(min(100, $0).rounded()))%" } ?? "—",
                             caption: performanceCaptionString,
                             info: .sleepPerformance(model.performancePct))
            metricTileButton(label: String(localized: "Efficiency"),
                             value: efficiencyPct(night).map { "\(Int($0.rounded()))%" } ?? "—",
                             caption: String(localized: "vs time in bed"),
                             info: .sleepEfficiency(efficiencyPct(night)))
            metricTileButton(label: String(localized: "Restorative"),
                             value: restorativePct(night.stages).map { "\(Int($0.rounded()))%" } ?? "—",
                             caption: String(localized: "Deep + REM"),
                             info: .sleepRestorative(restorativePct(night.stages)))
            if let latency = model.latencyMin {
                metricTileButton(label: String(localized: "Latency"),
                                 value: "\(Int(latency.rounded())) min",
                                 caption: String(localized: "10–20 healthy"),
                                 info: .sleepLatency(latency))
            } else {
                metricTileButton(label: String(localized: "Latency"),
                                 value: "—",
                                 caption: String(localized: "10–20 healthy"),
                                 info: .sleepLatency(nil))
            }
            metricTileButton(label: String(localized: "Respiration"),
                             value: night.respRate.map { String(format: "%.1f", $0) } ?? "—",
                             caption: String(localized: "rpm"),
                             valueColor: night.respRate != nil ? theme.dataSpO2 : nil,
                             info: .respiratory(night.respRate))
            metricTileButton(label: String(localized: "Awakenings"),
                             value: model.awakenings.map { "\($0)" } ?? "—",
                             caption: String(localized: "times"),
                             info: .sleepAwakenings(model.awakenings))
        }
    }

    private func metricTileButton(label: String, value: String, caption: String?,
                                  valueColor: Color? = nil, info: MetricInfo) -> some View {
        Button { metricInfo = info } label: {
            TileSurface(label: label, value: value,
                        valueColor: valueColor ?? (value == "—" ? theme.inkTertiary : theme.dataSleep),
                        valueSize: 21, caption: caption, theme: theme)
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Shows what this means"))
    }

    private var performanceCaptionString: String? {
        guard let missing = model.shortfallMinutes, missing >= 5 else {
            return String(localized: "vs your need")
        }
        return String(localized: "−\(hoursMinutes(missing)) vs your need")
    }

    private func trendLoader(for id: String) -> (() async -> [TrendPoint])? {
        let pts: [TrendPoint]
        switch id {
        case "sleep_performance": pts = model.performanceTrend
        case "sleep_efficiency":  pts = model.efficiencyTrend
        case "sleep_restorative": pts = model.restorativeTrend
        case "resp_rate":         pts = model.respirationTrend
        case "sleep_awakenings":  pts = model.awakeningsTrend
        default:                  return nil
        }
        return { pts }
    }

    // MARK: - 6. Reserva para bajar de marcha (FER-849) — promovida; sin flag experimental de carga

    @ViewBuilder
    private func nightDCContent(_ dc: NocturnalDC.Result) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: String(format: "%.1f", dc.dcMs))
                    .font(InstrumentoType.groteskNumber(24, weight: .bold))
                    .foregroundStyle(theme.dataHeart)
                    .monospacedDigit()
                Text(verbatim: "ms")
                    .font(InstrumentoType.grotesk(13))
                    .foregroundStyle(theme.dataHeart)
                Text("resting vagal reserve")
                    .font(InstrumentoType.grotesk(13))
                    .foregroundStyle(theme.inkSecondary)
            }
            HStack(alignment: .top, spacing: 8) {
                if let trend = dc.trend {
                    TileSurface(label: String(localized: "vs your base"),
                                value: String(localized: String.LocalizationValue(dcTrendWord(trend))),
                                valueColor: dcTrendColor(trend),
                                valueSize: 15, theme: theme)
                }
                TileSurface(label: String(localized: "read"),
                            value: String(localized: String.LocalizationValue(
                                dc.confidence == .solid ? "Solid" : "Estimate")),
                            valueSize: 15, theme: theme)
            }
            BarraAncla(String(localized: String.LocalizationValue(dcCopyKey(dc.trend))),
                       color: theme.dataSleep, theme: theme)
        }
    }

    private func dcTrendWord(_ t: NocturnalDC.Trend) -> String {
        switch t {
        case .above:  return "Above"
        case .around: return "In range"
        case .below:  return "Below"
        }
    }

    private func dcTrendColor(_ t: NocturnalDC.Trend) -> Color {
        switch t {
        case .above:  return theme.verdict
        case .around: return theme.ink
        case .below:  return theme.warning
        }
    }

    private func dcCopyKey(_ trend: NocturnalDC.Trend?) -> String {
        switch trend {
        case .above:
            return "Last night your heart had more room to ease off the gas than your base. A personal pattern: follow it over time."
        case .below:
            return "Last night your heart had less room to ease off the gas than your base. A personal pattern: follow it over time."
        case .around:
            return "Your resting braking reserve was in your usual range last night. A personal pattern: follow it over time."
        case .none:
            return "Your resting braking reserve last night. It reads best as a personal trend: follow it over time."
        }
    }

    // MARK: - 7. Deuda semanal

    private func weeklyDebtContent(_ debt: Double) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(hoursMinutes(debt))
                    .font(InstrumentoType.groteskNumber(24, weight: .bold))
                    .foregroundStyle(theme.warning)
                    .monospacedDigit()
                Text("behind this week")
                    .font(InstrumentoType.grotesk(13))
                    .foregroundStyle(theme.inkSecondary)
            }
            weeklyDebtBars
            BarraAncla(
                String(localized: "What you missed versus what your body needs. One good night won't clear it."),
                color: theme.warning, theme: theme)
        }
    }

    private var weeklyDebtBars: some View {
        DebtBars(
            nights: model.weeklyDebtNights.map {
                DebtNightBar(date: $0.date, vsNeedMin: $0.vsNeedMin, sleptMin: $0.sleptMin)
            },
            deficitColor: theme.warning,
            surplusColor: theme.verdict,
            ruleColor: theme.hairlineStrong,
            axisLabelColor: theme.inkTertiary,
            height: 96,
            weekdayLabel: Self.weekdayNarrow,
            valueFormat: { vsNeedMin in
                vsNeedMin < 0 ? "−\(hoursMinutes(-vsNeedMin))" : "+\(hoursMinutes(vsNeedMin))"
            },
            sleptFormat: { slept in String(localized: "slept \(hoursMinutes(slept))") }
        )
        .accessibilityElement()
        .accessibilityLabel(Text("Hours above or below your sleep need, each of the last 7 nights"))
    }

    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "UTC")
        f.setLocalizedDateFormatFromTemplate("EEEEE")
        return f
    }()
    private static func weekdayNarrow(_ date: Date) -> String { weekdayFormatter.string(from: date) }

    // MARK: - 8. Historial — SegmentedPillControl + GraficaRangos + tiles

    private var trendContent: some View {
        let window = MetricWindowMath.make(durationParsed, selected: range)
        let stat = ComparisonEngine.stat(window.values)
        let pctChange = range.periodComparison(of: model.durationSeries)?.pctChange
        let lastNightHrs = model.night.map { $0.stages.asleep / 60.0 }
        return VStack(alignment: .leading, spacing: 8) {
            SegmentedPillControl(ExploreRange.allCases, selection: $range, theme: theme) { $0.label }
            if window.values.count >= 2 {
                GraficaRangos(
                    points: window.values,
                    bands: Self.sleepDurationBands(theme),
                    ticks: [.init(v: 10, label: "10"), .init(v: 9, label: "9"),
                            .init(v: 7, label: "7"), .init(v: 5, label: "5")],
                    wash: .init(lo: 7, hi: 9, label: String(localized: "optimal 7–9 h")),
                    hue: theme.dataSleep, ymin: 5, ymax: 10,
                    startLabel: window.rows.first.flatMap { MetricWindowMath.axisLabel($0.day) } ?? "",
                    endLabel: window.rows.last.flatMap { MetricWindowMath.axisLabel($0.day) } ?? "",
                    mediaValue: window.values.count > 1
                        ? String(format: "%.1f h", stat.mean) : "—",
                    mediaNote: String(localized: "average of the \(range.name)"),
                    mediaDelta: pctChange.map {
                        $0 >= 0 ? "+\(Int($0.rounded()))%" : "\(Int($0.rounded()))%"
                    },
                    deltaColor: pctChange.map { $0 >= 0 ? theme.positiveText : theme.warning },
                    countUnit: "n",
                    anchorMedia: String(localized: "Hours asleep per night. The wash is the optimal 7–9 h band."),
                    anchorRangos: String(localized: "How many nights of the period fell in each band. Tap one to see its nights on the chart."),
                    scrub: true,
                    labels: window.rows.map { MetricWindowMath.axisLabel($0.day) ?? "" },
                    fmt: { String(format: "%.1f h", $0) },
                    theme: theme)
                    .padding(.top, 6)
                    .id(range)
                HStack(alignment: .top, spacing: 8) {
                    TileSurface(label: String(localized: "Average"),
                                value: window.values.count > 1
                                    ? String(format: "%.1f h", stat.mean) : "—",
                                theme: theme)
                    TileSurface(label: String(localized: "Range"),
                                value: window.values.count > 1
                                    ? String(format: "%.1f–%.1f", stat.min, stat.max) : "—",
                                theme: theme)
                    TileSurface(label: String(localized: "Last night"),
                                value: lastNightHrs.map { hoursOnly($0 * 60) } ?? "—",
                                valueColor: lastNightHrs != nil ? theme.dataSleep : nil,
                                theme: theme)
                }
                .padding(.top, 4)
            } else {
                ChartWell(theme, icon: "moon.zzz", cornerRadius: CenitMetrics.cardRadius)
                    .empty(text: "Not enough nights yet to draw a trend.")
            }
        }
    }

    /// Three duration lanes for `GraficaRangos`: Suficiente ≥7 · Algo corta 6.3–7 · Corta <6.3.
    static func sleepDurationBands(_ theme: InstrumentoTheme) -> [GraficaRangos.Banda] {
        [
            .init(label: String(localized: "Enough sleep"), lo: 7, hi: nil,
                  color: theme.dataSleep, range: "≥ 7"),
            .init(label: String(localized: "A bit short"), lo: 6.3, hi: 7,
                  color: theme.dataSleepLight, range: "6.3–7"),
            .init(label: String(localized: "Short sleep"), lo: nil, hi: 6.3,
                  color: theme.warning, range: "< 6.3"),
        ]
    }

    // MARK: - 9. Calendario · 90 noches

    private var calendarContent: some View {
        HeatCalendarSection(
            days: sleepHeatCache,
            selected: $selectedSleepNight,
            tint: sleepHeatTint,
            readoutValue: { m in String(format: "%d:%02d", Int(m), Int((m - Double(Int(m))) * 60)) },
            readoutWord: { sleepWord($0) },
            emptyHint: "Tap a night to see its sleep.",
            legend: [(theme.dataSleep, String(localized: "enough")),
                     (theme.dataSleepLight, String(localized: "ok")),
                     (theme.warning, String(localized: "short")),
                     (theme.rangeBand, String(localized: "no data"))],
            theme: theme
        )
    }

    /// The canonical UTC day-key formatter — read side of the day-key contract (FER-754).
    /// FER-978: `nonisolated` so it's reachable from nonisolated contexts (DateFormatter is Sendable
    /// under strict concurrency; the property is immutable).
    nonisolated private static let calDayFmt = DayKey.utcFormatter

    /// Builds the 90-night heat grid from a duration series snapshot (FER-953: pure / off-main-safe).
    /// `todayKey` llega del caller en MainActor (`Repository.localDayKey` es main-isolated). (FER-953)
    private nonisolated static func buildSleepHeat(durationSeries: [(day: String, value: Double)],
                                                   todayKey: String) -> [RecoveryDay] {
        var mins: [String: Double] = [:]
        for r in durationSeries { mins[r.day] = r.value }
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        // Ancla la ventana de 90 dias al dia LOCAL, igual que Recovery.buildHeat. Anclar al dia UTC
        // hace que en husos negativos, por la tarde, la ventana empiece en otro dia de la semana que
        // Recovery y el grid dibuje 13 vs 14 columnas, con celdas de otro tamano. Asi los cuatro
        // calendarios (Recuperacion, Sueno, Esfuerzo, Estres) miden igual. (FER calendarios mismo tamano)
        guard let today = Repository.parseDayKey(todayKey) else { return [] }
        return stride(from: 89, through: 0, by: -1).compactMap { off -> RecoveryDay? in
            guard let date = cal.date(byAdding: .day, value: -off, to: today) else { return nil }
            let key = Self.calDayFmt.string(from: date)
            return RecoveryDay(date: date.addingTimeInterval(12 * 3600), score: mins[key])
        }
    }

    private func sleepHeatTint(_ hours: Double) -> Color {
        if hours >= 7 { return theme.dataSleep }
        if hours >= 6 { return theme.dataSleepLight }
        return theme.warning
    }

    /// A short state word for the calendar read-out (matches the legend rungs and the tint thresholds).
    private func sleepWord(_ hours: Double) -> LocalizedStringKey {
        if hours >= 7 { return "enough" }
        if hours >= 6 { return "ok" }
        return "short"
    }

    // MARK: - 10. Método + sello

    private var metodoBlock: some View {
        Metodo(title: String(localized: "How it's calculated"), theme: theme) {
            Text("Regularity is the night-to-night variability of your mid-sleep point (the midpoint between falling asleep and waking): a steadier schedule predicts health more strongly than how long you sleep. Naps don't count: only your main night (at least 3 h) feeds regularity. Stages are estimated from movement, heart rate and HRV, so they're approximate; deep sleep repairs the body, REM consolidates memory and emotion. \"Need\" is a 7–9 h population target, not a measurement of you.")
                .font(StrandFont.subhead)
                .foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Windred et al., Sleep 2024 (regularity); Miller et al., J Sports Sci 2020 (wrist staging vs PSG); Hirshkowitz et al., 2015 (sleep need).")
                .font(StrandFont.caption)
                .foregroundStyle(theme.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
            Button { showStages = true } label: {
                HStack(spacing: 6) {
                    Text("Sleep stages in detail")
                    StrandIcon.disclosure.image
                        .font(StrandFont.glyph(.chevron, weight: .semibold))
                }
                .font(StrandFont.subhead)
                .foregroundStyle(theme.dataSleep)
            }
            .buttonStyle(.plain)
        }
    }

    private var sourceFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            OriginStamp(origin: model.isAppleHealth ? .apple : .band,
                        when: String(localized: "last night"), theme: theme)
            if let agreement = model.sourceAgreement {
                FusionAgreementRow(point: agreement, theme: theme, format: Self.sleepTotalHM)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 2)
    }

    private static func sleepTotalHM(_ minutes: Double) -> String {
        let m = Int(minutes.rounded())
        return "\(m / 60) h \(String(format: "%02d", m % 60)) m"
    }

    // MARK: - Async loaders (FER-832 / FER-849) — mismos motores, sin math nueva

    private func loadNightShape() async -> (shape: NightAutonomicShape.Result?, curve: [Double]) {
        guard let night = model.night, !model.isAppleHealth, !model.intervals.isEmpty else { return (nil, []) }

        let hr = await loadNightHR(night.startTs, night.endTs)
        guard hr.count >= 2 else { return (nil, []) }

        // FER-953: HR load stays on the caller's path; pure shape/curve derivation hops off-main.
        let intervals = model.intervals
        let rhrBaseline = model.rhrBaseline
        let onsetDate = night.onsetDate
        return await Task.detached(priority: .userInitiated) { () -> (NightAutonomicShape.Result?, [Double]) in
            let asleep = intervals
                .filter { $0.stage != .awake }
                .map { NightAutonomicShape.AsleepSpan(start: Int($0.start), end: Int($0.end)) }
            guard !asleep.isEmpty else { return (nil, []) }

            let awakeSpans = intervals.filter { $0.stage == .awake }
            let awakeHR = hr.filter { s in awakeSpans.contains { Int($0.start) <= s.ts && s.ts < Int($0.end) } }
            let wakingRef: Double? = {
                if awakeHR.count >= 30 {
                    return Double(awakeHR.reduce(0) { $0 + $1.bpm }) / Double(awakeHR.count)
                }
                let sorted = hr.map { Double($0.bpm) }.sorted()
                guard !sorted.isEmpty else { return nil }
                let idx = Int((0.90 * Double(sorted.count - 1)).rounded())
                return sorted[idx]
            }()

            let tz = TimeZone.current.secondsFromGMT(for: onsetDate)
            let shape = NightAutonomicShape.compute(hr: hr, asleep: asleep,
                                                    wakingReferenceHR: wakingRef,
                                                    rhrBaseline: rhrBaseline,
                                                    tzOffsetSeconds: tz)

            let asleepHR = hr.filter { s in asleep.contains { $0.start <= s.ts && s.ts < $0.end } }
                             .sorted { $0.ts < $1.ts }
            let curve = Self.downsampleBpm(asleepHR, maxPoints: 48)
            return (shape, curve)
        }.value
    }

    private nonisolated static func downsampleBpm(_ hr: [HRSample], maxPoints: Int) -> [Double] {
        guard hr.count > maxPoints else { return hr.map { Double($0.bpm) } }
        var out: [Double] = []
        out.reserveCapacity(maxPoints)
        for b in 0..<maxPoints {
            let lo = b * hr.count / maxPoints
            let hi = (b + 1) * hr.count / maxPoints
            guard hi > lo else { continue }
            let sum = hr[lo..<hi].reduce(0) { $0 + $1.bpm }
            out.append(Double(sum) / Double(hi - lo))
        }
        return out
    }

    /// No experimental flag: the handoff promotes DC to a standard section; the view still hides
    /// unreadable nights (`confidence == .unreadable`).
    private func loadNightDC() async -> NocturnalDC.Result? {
        guard let night = model.night, !model.isAppleHealth else { return nil }
        let rr = await loadNightRR(night.startTs, night.endTs)
        guard !rr.isEmpty else { return nil }
        let baseline = await loadDCBaseline()
        // FER-953: RR/baseline loads stay; map + NocturnalDC.compute hop off-main.
        return await Task.detached(priority: .userInitiated) {
            NocturnalDC.compute(rawRR: rr.map { Double($0.rrMs) }, baselineDcMs: baseline)
        }.value
    }

    // MARK: - Formatting helpers

    private func pct(_ minutes: Double, _ total: Double) -> Int {
        total > 0 ? Int((minutes / total * 100).rounded()) : 0
    }

    private func hoursOnly(_ minutes: Double) -> String {
        let m = Swift.max(0, Int(minutes.rounded()))
        return String(format: "%d:%02d", m / 60, m % 60)
    }

    private var napNotice: LocalizedStringKey {
        if let minutes = model.excludedNapMinutes {
            return "We didn't count your \(napDurationText(minutes)) nap, regularity uses only your main night."
        }
        return "We didn't count your naps (under \(napDurationText(Int(SleepMainNight.minDurationMinutes)))), regularity uses only your main night."
    }

    private func napDurationText(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h > 0 && m > 0 { return "\(h) h \(m) min" }
        if h > 0 { return "\(h) h" }
        return "\(m) min"
    }

    private func hoursMinutes(_ minutes: Double) -> String {
        let m = Int(minutes.rounded())
        return m >= 60 ? "\(m / 60) h \(m % 60) m" : "\(m) min"
    }

    private func restorativePct(_ s: SleepDetailModel.Stages) -> Double? {
        guard s.asleep > 0 else { return nil }
        return (s.deep + s.rem) / s.asleep * 100
    }

    private func efficiencyPct(_ night: SleepDetailModel.Night) -> Double? {
        if let stored = night.efficiency {
            return stored <= 1.0 ? stored * 100 : stored
        }
        let bed = night.stages.total
        guard bed > 0 else { return nil }
        return Swift.min(100, night.stages.asleep / bed * 100)
    }
}


// MARK: - SleepStagesInfoSheet — the combined "what the stages mean" card (FER-227)
//
// One bottom sheet explaining all four sleep stages + why they're approximate, opened from the ⓘ next
// to "Last night". It mirrors the `MetricInfoSheet` visual language (warm paper, title, lede, rows,
// footnote) but its content is a list of stages rather than a banded value — so it's its own small
// view, not a contorted `MetricInfo`. Theme passed EXPLICITLY (it doesn't propagate through `.sheet`,
// FER-162); no nested `NavigationStack` (FER-171). The stage hues are the fixed `StrandPalette` sleep
// colors, the same dots the legend uses (color only in the datum).

struct SleepStagesInfoSheet: View {
    var theme: InstrumentoTheme = .base

    private struct StageRow: Identifiable {
        let id = UUID()
        let stage: SleepStage
        let name: LocalizedStringKey
        let detail: LocalizedStringKey
    }

    private let rows: [StageRow] = [
        StageRow(stage: .rem,   name: "REM",   detail: "Dreams and memory. It consolidates what you learned and processes emotion."),
        StageRow(stage: .deep,  name: "Deep",  detail: "Physical repair. Your body restores itself and releases growth hormone."),
        StageRow(stage: .light, name: "Light", detail: "Most of the night. A transition in which your body winds down."),
        StageRow(stage: .awake, name: "Awake", detail: "Brief awakenings. They're normal and don't mean a bad night."),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Sleep stages")
                    .font(InstrumentoType.groteskHeadline(22))
                    .foregroundStyle(theme.ink)
                Text("Your night moves through four phases. The watch estimates them from your movement and heart rate, so they're approximate: it gets about 2 of 3 right.")
                    .font(StrandFont.subhead)
                    .foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                        stageRow(row)
                        if i < rows.count - 1 {
                            Divider().overlay(theme.hairline)
                        }
                    }
                }
                Text("Proportions, not minutes. A clinical measurement needs a sleep study.")
                    .font(StrandFont.caption)
                    .foregroundStyle(theme.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.paper)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .sheetPaper(theme)
    }

    private func stageRow(_ row: StageRow) -> some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 3, style: .continuous) // token-exempt: geometría de dato (swatch de leyenda)
                .fill(StrandPalette.sleepStageColor(row.stage))
                .frame(width: 10, height: 10)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 3) {
                Text(row.name).font(StrandFont.headline).foregroundStyle(theme.ink)
                Text(row.detail)
                    .font(StrandFont.caption)
                    .foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - SleepDetailModel — every derivation the screen draws, built ONCE from the repo
//
// The data layer of the old dark sleep screen, lifted out of the view and merged with the new
// `SleepRegularity` engine. `SleepDetailScreen` is pure presentation over this; the caller (Cuerpo)
// builds it with `SleepDetailModel.build(...)` so the screen stays DB-free. Stage minutes come from
// `stagesJSON` (imported = dict of minutes; on-device = segment array); the "typical" is the mean over
// `repo.days`; the regularity read is computed from `repo.sleeps`' onset/wake, excluding Apple-only
// nights (which have no real clock).

struct SleepDetailModel {

    struct Stages: Equatable {
        var awake: Double
        var light: Double
        var deep: Double
        var rem: Double
        /// All stages (includes awake) — total time-in-bed minutes.
        var total: Double { awake + light + deep + rem }
        /// Asleep time = total minus awake.
        var asleep: Double { light + deep + rem }
    }

    struct Night: Equatable {
        let startTs: Int
        let endTs: Int
        let efficiency: Double?
        let respRate: Double?
        let stages: Stages

        var onsetDate: Date { Date(timeIntervalSince1970: TimeInterval(startTs)) }
        var dateLabel: String { Self.dateFmt.string(from: Date(timeIntervalSince1970: TimeInterval(startTs))) }
        private static let dateFmt: DateFormatter = {
            let f = DateFormatter(); f.dateFormat = "EEE d MMM"; return f
        }()
    }

    /// The latest night (strap session preferred, else Apple Health fallback). `nil` → empty state.
    let night: Night?
    /// Stage intervals for the hypnogram (empty for Apple-only → proportional bar).
    let intervals: [SleepInterval]
    /// The night came from Apple Health (no clock, no per-epoch timeline). Hides the onset–wake clock.
    let isAppleHealth: Bool
    /// FER-670: the fused sleep-total point for the displayed night's day — nil unless BOTH the band
    /// and Apple Health reported that night. Drives the "coinciden / en conflicto" line in the footer.
    let sourceAgreement: FusedMetricPoint?
    /// Whether the repo finished its first load (drives the empty-state copy: loading vs no-data).
    let loaded: Bool
    /// Last night's rest-confidence tier (FER-676), from the persisted `restConfidence` (duration +
    /// resolved stages, H9-guarded). nil when the shown night has no graded row (e.g. Apple-only) → no sello.
    var confidence: ScoreConfidence? = nil

    // Regularity (FER-218 engine)
    let regularity: SleepRegularity.Result?
    /// How many timing nights fed (or would feed) the regularity read — for the "N to go" calibration.
    let regularityNights: Int
    /// Strap naps (shorter than a main night) excluded from the regularity window, so the UI can
    /// disclose that they didn't count (FER-310). 0 when none.
    let excludedNapCount: Int
    /// Duration (minutes) of the single excluded nap when `excludedNapCount == 1`, for the "your 2 h
    /// nap" copy; `nil` otherwise (0 naps, or ≥2 → generic copy).
    let excludedNapMinutes: Int?

    // "Typical" stage shares (percent of asleep, mean over history) for the vs-typical block.
    let typicalDeepPct: Double?
    let typicalRemPct: Double?
    let typicalLightPct: Double?

    // Night metrics
    /// Sleep performance %: imported WHOOP figure when present, else asleep / personal need (capped 100).
    let performancePct: Double?
    /// Need − asleep for last night, in minutes (the "performance" shortfall), floored at 0.
    let shortfallMinutes: Double?
    /// Sleep latency (minutes) — currently nil (the cache carries no onset-latency); shown as "—".
    let latencyMin: Double?
    /// Awakenings count (disturbances) for the latest night.
    let awakenings: Int?
    /// Baseline resting HR (bpm) for the night-shape's "% of the night below your resting HR": median of
    /// recent nightly resting-HR (the sleep nadir the app treats as RHR). `nil` until enough nights. (FER-832)
    let rhrBaseline: Double?

    // Duration trend + debt
    /// The FULL nightly duration series (oldest → newest) as `(day "yyyy-MM-dd", hours)`, so the duration
    /// trend carries its own period selector (W/M/3M/6M/1Y) + «Media móvil ⇄ Rangos» toggle like the
    /// vitals — windowed in the view via `MetricWindowMath`. (FER-573)
    let durationSeries: [(day: String, value: Double)]
    /// Accumulated sleep debt over the trailing 7 days, in minutes (sum of per-night need − asleep,
    /// floored per night). `nil` when there's nothing to sum.
    let weeklyDebtMinutes: Double?
    /// Per-night sleep-vs-need for the trailing 7 days, feeding the debt bars. `vsNeedMin` is signed:
    /// negative = fell short of need (debt), positive = beat it (surplus). (FER-249 v2)
    let weeklyDebtNights: [DebtNight]

    /// One night's sleep relative to your personal need, in minutes (signed). Drives a single debt bar.
    /// `sleptMin` is the night's total sleep, for the scrub tooltip's "slept …" line. (FER-249 v3)
    struct DebtNight: Equatable {
        let date: Date
        let vsNeedMin: Double
        let sleptMin: Double
    }

    // Per-metric 14-day mini-trends for the metric info cards (FER-227). Derived from `repo.days`;
    // empty when there's no series, so the sheet shows its "no data" well rather than a fake line.
    let performanceTrend: [TrendPoint]
    let efficiencyTrend: [TrendPoint]
    let restorativeTrend: [TrendPoint]
    let respirationTrend: [TrendPoint]
    let awakeningsTrend: [TrendPoint]
    /// The full nightly respiratory-rate series (oldest → newest, `nil` = missing night) for the
    /// respiration-trend watch (FER-851). The engine derives its own baseline + deviation from it.
    let respNightly: [Double?]

    // MARK: - Build

    /// Personal sleep need (minutes): mean asleep, never below a 7.5 h floor. Single source of truth
    /// shared with the coach/InsightEngine via `SleepMath` (FER-339), so both show the same debt.
    private static func sleepNeedMin(_ days: [DailyMetric]) -> Double {
        SleepMath.needMinutes(days)
    }

    /// Build the whole model from the repo's in-memory dashboard. Pure (no DB); call from the caller's
    /// view, once per data change. `appleHealthDays` flags which day rows are Apple-sourced (no clock).
    static func build(days: [DailyMetric],
                      sleeps: [CachedSleepSession],
                      appleSleeps: [CachedSleepSession] = [],
                      importedSleep: [String: ImportedSleepFigures],
                      appleHealthDays: Set<String>,
                      loaded: Bool,
                      todayKey: String,
                      fusion: [String: [String: FusedMetricPoint]] = [:]) -> SleepDetailModel {
        // Ignore any future-dated row: a daily can be bucketed under "tomorrow" in UTC (FER-226),
        // and a `.last` read would surface that empty row as "last night". Anchor to the device's
        // local day, mirroring StressModel (FER-224) / ReadinessEngine.
        let days = days.filter { $0.day <= todayKey }
        // --- Latest night: strap session wins, else Apple Health stage minutes (FER-62). ---
        // Respiration for the strap night comes from the latest daily metric (the session doesn't
        // carry it), so the Respiration tile shows anoche's value instead of "—". (FER-234)
        let strap = latestStrapNight(sleeps, respRate: days.last?.respRateBpm)
        // FER-486: an Apple Health session with a real per-epoch stage timeline (watchOS 9+) draws the SAME
        // hypnogram as a strap night. `appleSleeps` only holds nights the band didn't cover (band wins
        // upstream), so pick the most recent night across both — Apple wins only when it's newer / strap is nil.
        let appleNight = latestAppleSessionNight(appleSleeps)
        let useAppleSession: Bool = {
            guard let a = appleNight else { return false }
            guard let s = strap else { return true }
            return a.startTs > s.startTs
        }()
        let night: Night? = useAppleSession ? appleNight
                          : (strap ?? appleHealthNight(days: days, appleHealthDays: appleHealthDays))
        let isApple = useAppleSession || (strap == nil && night != nil)
        let intervals: [SleepInterval] = {
            if useAppleSession, let a = appleSleeps.last {
                return decodeSegments(a.stagesJSON, sessionStart: a.startTs)?.intervals ?? []
            }
            guard !isApple, let s = sleeps.last else { return [] }
            return decodeSegments(s.stagesJSON, sessionStart: s.startTs)?.intervals ?? []
        }()

        // --- Regularity: onset/wake from real strap sessions only (exclude Apple-only nights). ---
        let timing: [SleepRegularity.NightTiming] = sleeps.compactMap { s in
            guard s.endTs > s.startTs else { return nil }   // Apple fallback uses startTs == endTs
            return SleepRegularity.NightTiming(onset: s.startTs, wake: s.endTs)
        }
        let regularity = SleepRegularity.compute(timing)
        // The effective window size the engine would use (so the calibration says "N nights to go").
        let regularityNights = min(timing.count, SleepRegularity.windowNights)

        // --- Naps excluded from the regularity window, for the disclosure line (FER-310). ---
        // The engine keeps only "main nights" (≥ SleepMainNight threshold) and scores the most recent
        // `windowNights` of them. A nap counts as excluded only if it onset at/after the oldest night
        // in that window — older naps are off-window and irrelevant to the current read.
        let napThresholdSec = Int(SleepMainNight.minDurationMinutes * 60)
        let strapSessions = sleeps.filter { $0.endTs > $0.startTs }   // excludes Apple-only (start == end)
        let mainNightWindow = strapSessions
            .filter { $0.endTs - $0.startTs >= napThresholdSec }
            .sorted { $0.startTs > $1.startTs }
            .prefix(SleepRegularity.windowNights)
        let windowStart = mainNightWindow.last?.startTs ?? 0
        let excludedNaps = mainNightWindow.isEmpty ? [] : strapSessions.filter {
            $0.endTs - $0.startTs < napThresholdSec && $0.startTs >= windowStart
        }
        let excludedNapCount = excludedNaps.count
        let excludedNapMinutes = excludedNapCount == 1
            ? (excludedNaps[0].endTs - excludedNaps[0].startTs) / 60 : nil

        // --- Typical stage shares (percent of asleep), mean over days that carry all three stages. ---
        var deepPcts: [Double] = [], remPcts: [Double] = [], lightPcts: [Double] = []
        for d in days {
            guard let deep = d.deepMin, let rem = d.remMin, let light = d.lightMin else { continue }
            let asleep = deep + rem + light
            guard asleep > 0 else { continue }
            deepPcts.append(deep / asleep * 100)
            remPcts.append(rem / asleep * 100)
            lightPcts.append(light / asleep * 100)
        }

        // --- Night metrics for the latest night. ---
        let need = sleepNeedMin(days)
        let latestDay = days.last
        let imported = latestDay.flatMap { importedSleep[$0.day] }
        let asleepLast = night?.stages.asleep
        let performancePct: Double? = {
            if let p = imported?.performancePct { return p }
            guard let asleep = asleepLast, asleep > 0, need > 0 else { return nil }
            return Swift.min(100, asleep / need * 100)
        }()
        let shortfall: Double? = {
            guard let asleep = asleepLast, asleep > 0 else { return nil }
            return Swift.max(0, need - asleep)
        }()
        let awakenings = latestDay?.disturbances

        // RHR baseline for the night-shape (FER-832): median of recent nightly resting-HR (the sleep
        // nadir the app already treats as RHR). Uses the trailing ~28 nights; nil until any exist.
        let recentRHR = sleeps.suffix(28).compactMap { $0.restingHr }.map(Double.init).sorted()
        let rhrBaseline: Double? = {
            guard !recentRHR.isEmpty else { return nil }
            let m = recentRHR.count / 2
            return recentRHR.count % 2 == 1 ? recentRHR[m] : (recentRHR[m - 1] + recentRHR[m]) / 2
        }()

        // --- Duration trend (full nightly series, in hours) + 7-day accumulated debt. ---
        // The FULL nightly duration series (hours), windowed by period in the trend block (FER-573).
        let durationSeries: [(day: String, value: Double)] = days.compactMap { d in
            guard let mins = d.totalSleepMin, mins > 0 else { return nil }
            return (d.day, mins / 60.0)
        }
        let weeklyDebt: Double? = {
            let last7 = days.suffix(7)
            let debts = last7.compactMap { d -> Double? in
                if let debt = importedSleep[d.day]?.debtMin { return debt }
                guard let asleep = d.totalSleepMin, asleep > 0, need > 0 else { return nil }
                return Swift.max(0, need - asleep)
            }
            return debts.isEmpty ? nil : debts.reduce(0, +)
        }()
        // Per-night sleep-vs-need for the debt bars (signed: < 0 = short of need). Derived on-device from
        // total sleep so it carries surplus too; the headline total above still honours imported debt.
        let debtNights: [DebtNight] = days.suffix(7).compactMap { d in
            guard let asleep = d.totalSleepMin, asleep > 0, need > 0,
                  let date = Repository.parseDayKey(d.day) else { return nil }
            return DebtNight(date: date, vsNeedMin: asleep - need, sleptMin: asleep)
        }

        // --- Per-metric 14-day mini-trends for the info cards (FER-227). Same derivations as the tiles,
        // over history; each skips nights missing that value. ---
        let performanceTrend = metricTrend(days) { d in
            if let p = importedSleep[d.day]?.performancePct { return p }
            guard let asleep = d.totalSleepMin, asleep > 0, need > 0 else { return nil }
            return Swift.min(100, asleep / need * 100)
        }
        let efficiencyTrend = metricTrend(days) { d in
            d.efficiency.map { $0 <= 1.0 ? $0 * 100 : $0 }
        }
        let restorativeTrend = metricTrend(days) { d in
            guard let deep = d.deepMin, let rem = d.remMin, let light = d.lightMin else { return nil }
            let asleep = deep + rem + light
            return asleep > 0 ? (deep + rem) / asleep * 100 : nil
        }
        let respirationTrend = metricTrend(days) { $0.respRateBpm }
        let awakeningsTrend = metricTrend(days) { $0.disturbances.map(Double.init) }
        // Full nightly respiration series (oldest → newest) for the respiration-trend watch (FER-851).
        let respNightly: [Double?] = days.map { $0.respRateBpm }

        return SleepDetailModel(
            night: night,
            intervals: intervals,
            isAppleHealth: isApple,
            // FER-670: the source-agreement point for the displayed night's day (the same `latestDay`
            // the other night metrics read) — non-nil only when band AND Apple reported that night.
            sourceAgreement: latestDay.flatMap { fusion[$0.day]?["sleep_total_min"] },
            loaded: loaded,
            // FER-676: the persisted rest tier of the same `latestDay` row the other night metrics
            // read. Apple-only rows never carry it → nil → no sello (honest, nothing was graded).
            confidence: latestDay?.restConfidence.flatMap(ScoreConfidence.init(rawValue:)),
            regularity: regularity,
            regularityNights: regularityNights,
            excludedNapCount: excludedNapCount,
            excludedNapMinutes: excludedNapMinutes,
            typicalDeepPct: mean(deepPcts),
            typicalRemPct: mean(remPcts),
            typicalLightPct: mean(lightPcts),
            performancePct: performancePct,
            shortfallMinutes: shortfall,
            latencyMin: nil,
            awakenings: awakenings,
            rhrBaseline: rhrBaseline,
            durationSeries: durationSeries,
            weeklyDebtMinutes: weeklyDebt,
            weeklyDebtNights: debtNights,
            performanceTrend: performanceTrend,
            efficiencyTrend: efficiencyTrend,
            restorativeTrend: restorativeTrend,
            respirationTrend: respirationTrend,
            awakeningsTrend: awakeningsTrend,
            respNightly: respNightly)
    }

    /// Runs `build` off the MainActor (FER-953): snapshots the inputs from `repo` on the MainActor
    /// (value-type copies), then hops the whole derivation — pure StrandAnalytics engines — to a
    /// background executor; only the finished model returns to main. Single seam for every call-site.
    @MainActor
    static func buildDetached(repo: Repository) async -> SleepDetailModel {
        let days = repo.days, sleeps = repo.sleeps, appleSleeps = repo.appleSleeps
        let importedSleep = repo.importedSleep, appleHealthDays = repo.appleHealthDays
        let loaded = repo.loaded, fusion = repo.fusion
        let todayKey = Repository.localDayKey(Date())
        return await Task.detached(priority: .userInitiated) {
            build(days: days, sleeps: sleeps, appleSleeps: appleSleeps, importedSleep: importedSleep,
                  appleHealthDays: appleHealthDays, loaded: loaded, todayKey: todayKey, fusion: fusion)
        }.value
    }

    /// Placeholder while `buildDetached` runs: renders the screen's existing `!loaded` loading state.
    /// Pure + deterministic, so it's computed once per process.
    static let loading: SleepDetailModel = build(
        days: [], sleeps: [], appleSleeps: [], importedSleep: [:], appleHealthDays: [],
        loaded: false, todayKey: "", fusion: [:])

    /// Trailing 14 nights of a metric, in whatever unit `pick` returns, as `TrendPoint`s. Skips nights
    /// where the value is missing; empty when there's nothing to chart. (FER-227)
    private static func metricTrend(_ days: [DailyMetric], _ pick: (DailyMetric) -> Double?) -> [TrendPoint] {
        // Solo se dibujan los últimos 14 puntos. Recorre desde el final y parsea a lo más ~14 llaves de día
        // en vez de parsear TODO el historial 5 veces en el hilo del tap: `Repository.parseDayKey` usa un
        // `DateFormatter` (caro), y build() antes hacía 5·N parseos síncronos → jank al abrir Sueño. Mismo
        // resultado que `compactMap{…}.suffix(14)` (últimos 14 puntos no nulos, en orden). (perf FER-freeze)
        var pts: [TrendPoint] = []
        for d in days.reversed() {
            guard let v = pick(d), let date = Repository.parseDayKey(d.day) else { continue }
            pts.append(TrendPoint(date: date, value: v))
            if pts.count == 14 { break }
        }
        return pts.reversed()
    }

    // MARK: - Night resolution (ported from the old sleep screen)

    /// The most recent strap sleep, decoded into stage durations + (when on-device) its real timeline.
    /// `respRate` is the night's mean respiration, taken from the matching daily metric — the cached
    /// sleep session itself doesn't carry it, so without this the "Respiration" tile read "—" even
    /// though the 14-day trend (sourced from `repo.days`) had data. (FER-234)
    private static func latestStrapNight(_ sleeps: [CachedSleepSession], respRate: Double?) -> Night? {
        guard let s = sleeps.last, s.endTs > s.startTs else { return nil }
        if let stages = decodeStages(s.stagesJSON), stages.total > 0 {
            return Night(startTs: s.startTs, endTs: s.endTs, efficiency: s.efficiency,
                         respRate: respRate, stages: stages)
        }
        if let seg = decodeSegments(s.stagesJSON, sessionStart: s.startTs), seg.stages.total > 0 {
            return Night(startTs: s.startTs, endTs: s.endTs, efficiency: s.efficiency,
                         respRate: respRate, stages: seg.stages)
        }
        return nil
    }

    /// Fallback Night from the most recent Apple Health day carrying sleep-stage minutes (FER-62). No
    /// real clock (startTs == endTs at noon-UTC), so the screen draws a proportional bar.
    private static func appleHealthNight(days: [DailyMetric], appleHealthDays: Set<String>) -> Night? {
        guard let d = days.last(where: {
            appleHealthDays.contains($0.day) && ($0.totalSleepMin ?? 0) > 0
        }) else { return nil }
        let deep = d.deepMin ?? 0, rem = d.remMin ?? 0, light = d.lightMin ?? 0
        guard deep + rem + light > 0 else { return nil }
        let stages = Stages(awake: 0, light: light, deep: deep, rem: rem)
        let startTs = Int((Repository.parseDayKey(d.day) ?? Date()).timeIntervalSince1970) + 12 * 3600
        return Night(startTs: startTs, endTs: startTs, efficiency: d.efficiency,
                     respRate: d.respRateBpm, stages: stages)
    }

    /// The most recent Apple Health session carrying a REAL stage timeline (FER-486) — drawn as a full
    /// hypnogram, unlike `appleHealthNight` (daily totals → proportional bar). Apple's sleepAnalysis has
    /// no per-session respiration/efficiency, so those tiles fall back to the daily metric / "—".
    private static func latestAppleSessionNight(_ appleSleeps: [CachedSleepSession]) -> Night? {
        guard let s = appleSleeps.last, s.endTs > s.startTs,
              let seg = decodeSegments(s.stagesJSON, sessionStart: s.startTs), seg.stages.total > 0
        else { return nil }
        return Night(startTs: s.startTs, endTs: s.endTs, efficiency: s.efficiency,
                     respRate: nil, stages: seg.stages)
    }

    /// Trailing 14 nights of total sleep, in HOURS — the same window the Today sleep sheet charts, so
    /// both screens read identically (FER-249 v2). Falls back to all nights when the window is sparse.
    // MARK: - Stage decoding (ported from the old sleep screen)

    /// Decode the imported stagesJSON dict of MINUTES {"light","deep","rem","awake"}.
    private static func decodeStages(_ json: String?) -> Stages? {
        guard let json, let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let dict = obj as? [String: Any] else { return nil }
        func val(_ key: String) -> Double {
            if let n = dict[key] as? NSNumber { return n.doubleValue }
            if let d = dict[key] as? Double { return d }
            if let i = dict[key] as? Int { return Double(i) }
            return 0
        }
        let s = Stages(awake: val("awake"), light: val("light"), deep: val("deep"), rem: val("rem"))
        return s.total > 0 ? s : nil
    }

    /// Decode the COMPUTED stagesJSON segment array [{start,end,stage}] into stage totals + the real
    /// timeline (seconds relative to the session start). The on-device SleepStager calls awake "wake".
    private static func decodeSegments(_ json: String?, sessionStart: Int) -> (stages: Stages, intervals: [SleepInterval])? {
        guard let json, let data = json.data(using: .utf8),
              let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]],
              !arr.isEmpty else { return nil }
        var stages = Stages(awake: 0, light: 0, deep: 0, rem: 0)
        var intervals: [SleepInterval] = []
        for seg in arr {
            guard let start = (seg["start"] as? NSNumber)?.intValue,
                  let end = (seg["end"] as? NSNumber)?.intValue, end > start,
                  let name = seg["stage"] as? String else { continue }
            let minutes = Double(end - start) / 60.0
            let stage: SleepStage
            switch name {
            case "wake", "awake": stage = .awake; stages.awake += minutes
            case "light": stage = .light; stages.light += minutes
            case "deep": stage = .deep; stages.deep += minutes
            case "rem": stage = .rem; stages.rem += minutes
            default: continue
            }
            intervals.append(SleepInterval(stage: stage,
                                           start: TimeInterval(start - sessionStart),
                                           end: TimeInterval(end - sessionStart)))
        }
        return stages.total > 0 ? (stages, intervals) : nil
    }

    private static func mean(_ vals: [Double]) -> Double? {
        guard !vals.isEmpty else { return nil }
        return vals.reduce(0, +) / Double(vals.count)
    }
}
#endif
