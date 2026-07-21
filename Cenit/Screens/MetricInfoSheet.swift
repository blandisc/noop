import SwiftUI
import StrandDesign
import StrandAnalytics

// MARK: - MetricInfoSheet

struct MetricInfoSheet: View {
    let info: MetricInfo

    /// The active «Instrumento diurno» theme. Passed explicitly (the theme does NOT propagate through
    /// `.sheet`'s fresh environment), so the sheet renders on the same warm paper as Today, recoloured
    /// by hour. (FER-162)
    var theme: InstrumentoTheme = .base

    /// When true, the metric can be sourced from Apple Health but it isn't connected and there's no
    /// value yet — so the sheet shows a quiet "connect it from Today" line instead of a bare "—".
    /// Strap-only metrics (strain, heart rate) never set this. (FER-162)
    var appleConnectHint: Bool = false

    /// When true, the value currently shown actually came from Apple Health (not the strap) — the sheet
    /// adds a quiet "Apple Health" line with the heart glyph at the foot, so the source reads at a
    /// glance. Resolved dynamically by the caller per reading (never hardcoded per metric), so a strap
    /// reading and an Apple fallback for the same metric badge differently.
    var appleSource: Bool = false

    /// Loads today's 24h HR curve (5-minute buckets). Supplied only for the Heart Rate sheet; nil
    /// elsewhere (and on macOS). Run lazily when the sheet appears. (FER-137)
    var heartRateCurveLoader: (() async -> [TrendPoint])? = nil

    /// Loads the 14-day trend for this metric. Supplied for all key metrics; triggers lazily on appear.
    var trendLoader: (() async -> [TrendPoint])? = nil

    /// "Ver más" affordance: when non-nil, a trailing link at the foot of the sheet opens this metric's
    /// rich Detalle (the same screen Cuerpo opens), so Today can drill from the summary into the full
    /// detail in place. nil → no link (metrics without a rich detail destination yet: SpO₂, Heart Rate,
    /// Steps). (FER-251)
    var onSeeMore: (() -> Void)? = nil

    /// Full-history series for the levels instrument (FER-607): `(day, value)` per day with NO 14-day
    /// cutoff, so the range selector (S/M/3M/6M/1A/Todo) can re-window. Supplied only for metrics whose
    /// `info.usesLevels`; nil otherwise. Loaded lazily on appear.
    var levelsSeriesLoader: (() async -> [(day: String, value: Double)])? = nil

    /// FER-710 · «Tu patrón»: the WhatMovesIt findings for this metric, supplied by the caller. Only HRV
    /// and resting HR carry any (the engine returns [] for the rest), so the block hides itself on the
    /// other vitals. Default empty → hidden.
    var whatMovesIt: [WhatMovesItFinding] = []

    /// FER-710 · the sleep summary's rich data (stages, regularity, times) — the SAME model the detail
    /// builds, supplied by the caller only for the sleep sheet. nil (or a night-less model) → the sheet
    /// falls back to the shared single-value layout, so no-data / Apple-only states stay unchanged.
    var sleepDetail: SleepDetailModel? = nil

    @State private var heartRateCurve: [TrendPoint] = []
    @State private var heartRateLoading = false
    @State private var trendData: [TrendPoint] = []
    @State private var trendLoading = false
    /// Measured natural height of the sheet's content — used to size the Day Strain detent to its
    /// content so it never opens taller than it needs to. (FER-112 follow-up)
    @State private var contentHeight: CGFloat = 0

    /// The plain-language explanation (`info.headline`) is hidden behind the header's ⓘ; collapsed each
    /// time the sheet opens so the card reads clean (number first), one tap from the "why". (FER-243)
    @State private var headlineExpanded = false

    /// Range selection + loaded full-history series for the levels instrument (FER-607). Only used when
    /// `info.usesLevels`; the explorer re-windows the series by `levelsRange`. Each `day` is
    /// parsed to a `Date` exactly ONCE on load (not per render) — the same memoization the detail screens
    /// use, since the explorer re-windows on every range/level tap.
    @State private var levelsRange: ExploreRange = .week
    @State private var levelsParsed: MetricWindowMath.Parsed = []
    @State private var resolvedLevelsCache: [MetricLevels.Level]? = nil
    @State private var resolvedLevelsCacheKey: String = ""

    // MARK: Colour resolution (against the live theme)

    /// The metric's own data hue, from the «Instrumento» theme (the same per-metric colours the
    /// Today rows use for their sparklines). (FER-147 / FER-162)
    private var metricHue: Color {
        switch info.id {
        case "strain":              return theme.dataStrain
        case "sleep":               return theme.dataSleep
        // Detalle de Sueño night metrics share the sleep hue; respiration keeps its SpO₂-family blue
        // (matching its tile). (FER-227)
        case "sleep_performance", "sleep_efficiency", "sleep_restorative",
             "sleep_awakenings", "sleep_latency":
                                    return theme.dataSleep
        case "resp_rate":           return theme.dataSpO2
        case "hrv":                 return theme.dataHrv
        case "heart_rate", "rhr":   return theme.dataHeart
        case "spo2":                return theme.dataSpO2
        case "skin_temp":           return theme.dataStrain
        case "steps":               return theme.dataSteps
        case "recovery":            return theme.dataRecovery
        // Stress has no single data hue: its bands are tinted by level (verdict/warning/critical), so
        // the active-band highlight follows the header tint — green at LOW, amber at MEDIUM, red at HIGH.
        case "stress":              return tintColor(info.headerTint)
        default:                    return theme.dataRecovery
        }
    }

    /// Resolve a semantic header tint to a concrete theme colour.
    private func tintColor(_ tint: MetricInfo.Tint) -> Color {
        switch tint {
        case .metric:  return metricHue
        case .neutral: return theme.inkSecondary
        case .good:    return theme.verdict
        case .warn:    return theme.warning
        case .bad:     return theme.critical
        }
    }

    /// Line/area gradient for this metric's charts — the metric hue, from translucent to solid, so the
    /// curve reads clearly on warm paper.
    private var chartGradient: Gradient {
        ChartWell.fillGradient(metricHue)
    }

    var body: some View {
        ScrollView {
            sheetColumn
        }
        .onPreferenceChange(SheetContentHeightKey.self) { (h: CGFloat) in contentHeight = h }
        .background(theme.paper)
        .presentationDetents(strainDetents)
        .presentationDragIndicator(.visible)
        .sheetPaper(theme)
        .task {
            guard info.id == "heart_rate", let loader = heartRateCurveLoader else { return }
            heartRateLoading = true
            heartRateCurve = await loader()
            heartRateLoading = false
        }
        .task {
            guard let loader = trendLoader else { return }
            trendLoading = true
            let loaded: [TrendPoint] = await loader()
            trendData = loaded.sorted { (a: TrendPoint, b: TrendPoint) in a.date < b.date }
            trendLoading = false
        }
        .task {
            // Full-history series for the levels instrument (FER-607) — no 14-day cutoff, so the range
            // selector can re-window. Parse each day to a `Date` ONCE here, not per render. Supplied only
            // when `info.usesLevels`.
            guard let loader = levelsSeriesLoader else { return }
            let rows: [(day: String, value: Double)] = await loader()
            levelsParsed = rows.map { (row: (day: String, value: Double)) in
                (day: row.day, date: Repository.parseDayKey(row.day), value: row.value)
            }
            refreshResolvedLevelsCache()
        }
    }

    /// Column inside the sheet scroll — extracted so `body`'s type-check stays under the 100 ms budget. (FER-981)
    @ViewBuilder private var sheetColumn: some View {
        VStack(alignment: .leading, spacing: CenitMetrics.gap) {
            header
            summaryBranch
            sheetFoot
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GeometryReader { (g: GeometryProxy) in
            Color.clear.preference(key: SheetContentHeightKey.self, value: g.size.height)
        })
    }

    /// The five summary layouts (recovery / vitals / sleep / strain / classic). Split from `body` so the
    /// type-checker type-checks each branch in isolation. (FER-981)
    @ViewBuilder private var summaryBranch: some View {
        if isRecoverySummary {
            recoverySummaryContent
        } else if isVitalTemplate {
            vitalTemplateContent
        } else if isSleepSummary {
            sleepSummaryContent
        } else if isStrainSummary {
            strainSummaryContent
        } else {
            classicSummaryContent
        }
    }

    /// F2 (FER-710): the redesigned recovery summary — verdict word + zone meter under the
    /// hero, then «Hoy, vs tu normal» ABOVE the level instrument, no vs-ayer line. The
    /// detail (RecoveryDetailScreen, opened by «Ver más en Tendencias») keeps every block.
    @ViewBuilder private var recoverySummaryContent: some View {
        recoveryReading
        recoveryZoneMeter
        headlineText
        if let impact = info.impact, !impact.signals.isEmpty { impactBlock(impact) }
        levelsBlock
    }

    /// F2 (FER-710): the six vitals — data-driven verdict reading under the hero, the level
    /// instrument, then «Tu patrón» (only where WhatMovesIt has an honest finding: HRV / FC).
    @ViewBuilder private var vitalTemplateContent: some View {
        vitalReading
        headlineText
        levelsBlock
        vitalPatternBlock
    }

    /// F2 (FER-710) §4: doble dato (in place of the numeral) + verdict + «Anoche» stage bar,
    /// the active lane label moved above the selector, then the level instrument + «Para esta
    /// noche». No-night / Apple-only-without-stages fall through to the classic layout below.
    @ViewBuilder private var sleepSummaryContent: some View {
        sleepDobleDato
        sleepReading
        headlineText
        sleepAnocheBlock
        sleepActiveLaneLabel
        levelsBlock
        sleepParaEstaNoche
    }

    /// F2 (FER-710): Day Strain — verdict by level, then the level instrument. (The intraday «hora a
    /// hora» curve was retired in FER-1025: without the band there's no per-second pulse to feed it.)
    @ViewBuilder private var strainSummaryContent: some View {
        vitalReading
        headlineText
        levelsBlock
    }

    /// Classic / fallback layout: levels instrument when migrated, else trend / strain / HR charts + bands.
    @ViewBuilder private var classicSummaryContent: some View {
        headlineText
        if info.usesLevels {
            // FER-607: the F6 levels instrument (selector + tappable levels + chart over the
            // active band) replaces the static 14-day trend + bands table for migrated metrics.
            levelsBlock
        } else {
            classicMiddleCharts
        }
        // Recovery's calibration card + today's impact block ride alongside BOTH layouts — only
        // Recovery sets them, so they stay invisible on every other metric. With the levels
        // instrument they sit just below it («qué la movió hoy»). (FER-620 / FER-628)
        if let calibration = info.calibration { calibrationCard(calibration) }
        if let impact = info.impact, !impact.signals.isEmpty { impactBlock(impact) }
    }

    /// Charts + bands for the classic (non-levels) middle slot. (FER-981)
    @ViewBuilder private var classicMiddleCharts: some View {
        if trendLoader != nil { trendSection }
        // Heart Rate's 24h curve sits in the same middle slot (it has no 14-day trendLoader,
        // so the two never both appear). (FER-137)
        if info.id == "heart_rate" { heartRateSection }
        if !info.bands.isEmpty {
            bandsTable
        }
    }

    /// Method / note / disclaimer / Apple source / «Ver más» foot of the sheet. (FER-981)
    @ViewBuilder private var sheetFoot: some View {
        if let method = info.method { methodDisclosure(method) }
        if appleConnectHint {
            appleConnectLine
        } else if let note = info.note {
            Text(note)
                .font(StrandFont.caption)
                .foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        if let disclaimer = info.disclaimer {
            Text(disclaimer)
                .font(StrandFont.footnote)
                .foregroundStyle(theme.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        if appleSource { appleSourceLine }
        if let onSeeMore { seeMoreLink(onSeeMore) }
    }

    /// Sheets with a trend chart (or the strain accumulation curve) are sized to their content so the
    /// chart is never cut off. Falls back to `.large` until the first layout pass measures the height.
    /// Short, band-only sheets stay at `.medium`. (FER-112 follow-up, extended for trend charts)
    private var strainDetents: Set<PresentationDetent> {
        guard info.id == "strain" || info.id == "heart_rate" || trendLoader != nil
                || info.usesLevels else { return [.medium] }
        return contentHeight > 0 ? [.height(contentHeight)] : [.large]
    }

    /// The datum leads: the name drops to a quiet overline and the value becomes the hero numeral
    /// (rule 1 — one dominant element; rule 4 — name as overline), so the two no longer compete on the
    /// same baseline. Tint still resolves through `headerTint` (band/level/neutral), unchanged. (FER-243)
    /// The SF Symbol that anchors each redesigned summary header, mirroring Carga's hill glyph: a small
    /// stroke mark tinted in the metric's own data hue (colour on the datum, quiet everywhere else). One
    /// per Today card; recovery (its own hero score) and any unmapped id stay glyph-less. (standardization)
    private var metricGlyphName: String? {
        switch info.id {
        case "sleep":     return "moon"
        case "hrv":       return "waveform.path.ecg"
        case "rhr":       return "heart"
        case "strain":    return "bolt"
        case "steps":     return "figure.walk"
        case "spo2":      return "drop"
        case "skin_temp": return "thermometer.medium"
        case "resp_rate": return "lungs"
        case "stress":    return "waveform.path"
        default:          return nil
        }
    }

    @ViewBuilder private var metricGlyph: some View {
        if let name = metricGlyphName {
            Image(systemName: name)
                .font(StrandFont.glyph(.chevron, weight: .semibold))
                .foregroundStyle(metricHue)
                .accessibilityHidden(true)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: CenitMetrics.space2) {
            HStack(alignment: .firstTextBaseline) {
                if isRedesignedHeader {
                    // F2 (FER-710): recovery / strain / the six vitals / sleep share the Grotesk uppercase
                    // title + ⓘ, retiring the serif title + boxed source chip. A calculated score shows a
                    // «Calculated» origin dot; a measured signal shows its band/Apple dot. A leading metric
                    // glyph (tinted in the metric's own hue) anchors the header the way Carga's hill does.
                    metricGlyph
                    Text(info.name).groteskSheetTitle().foregroundStyle(theme.ink)
                    infoButton
                    Spacer()
                    if isCalculatedSummary { originDot("Calculated", color: theme.inkTertiary) }
                    else { vitalOriginDot }
                } else {
                    Text(info.name)
                        .groteskOverline()
                        .foregroundStyle(theme.inkTertiary)
                    Spacer()
                    infoButton
                }
            }
            // The rich sleep summary replaces the single numeral with its own doble-dato (in the body). (FER-710)
            if !isSleepSummary {
            HStack(alignment: .firstTextBaseline, spacing: CenitMetrics.space1) {
                if isCalculatedSummary || isVitalTemplate {
                    // Grotesk 56 numeral + suffix: «/ 100» (recovery, scored) · «/ 21» (strain, scored) ·
                    // the unit (a vital). (FER-710)
                    Text(info.displayValue)
                        .groteskSheetNumeral()
                        .foregroundStyle(tintColor(info.headerTint))
                    if let suffix = calculatedNumeralSuffix {
                        Text(verbatim: suffix).font(StrandFont.unit).foregroundStyle(theme.inkTertiary)
                    } else if isVitalTemplate, let unit = info.unit {
                        Text(unit).font(StrandFont.unit).foregroundStyle(theme.inkTertiary)
                    }
                } else {
                    Text(info.displayValue)
                        .instrumentoHero(46)
                        .foregroundStyle(tintColor(info.headerTint))
                    if let unit = info.unit {
                        Text(unit)
                            .font(StrandFont.unit)
                            .foregroundStyle(theme.inkTertiary)
                    }
                }
            }
            }
        }
    }

    /// Recovery + Day Strain: calculated scores that share the Grotesk header with a «Calculated» origin
    /// dot and a «/ max» numeral suffix. (FER-710)
    private var isCalculatedSummary: Bool { info.id == "recovery" || info.id == "strain" }
    /// Any F2-redesigned sheet (recovery / strain / the six vitals / sleep): Grotesk uppercase title, no
    /// serif, an origin dot instead of the boxed source chip. (FER-710)
    private var isRedesignedHeader: Bool { isCalculatedSummary || isVitalTemplate || info.id == "sleep" }
    /// The «/ N» ceiling suffix for a calculated summary's numeral, only when there's a real score. nil for
    /// vitals (they show a unit instead) and for a calibrating/no-data calculated score. (FER-710)
    private var calculatedNumeralSuffix: String? {
        if info.id == "recovery" { return isRecoverySummary ? "/ 100" : nil }
        if info.id == "strain"   { return info.displayValue != "—" ? "/ 21" : nil }
        return nil
    }

    /// The redesigned recovery summary path (F2): a scored recovery reading. Calibrating / no-data
    /// recovery falls through to the shared layout, so those states stay unchanged. (FER-710)
    private var isRecoverySummary: Bool {
        info.id == "recovery" && info.calibration == nil && info.displayValue != "—"
    }

    /// The ⓘ-toggled plain-language explanation, shared by the recovery and classic body layouts.
    @ViewBuilder private var headlineText: some View {
        if headlineExpanded {
            Text(info.headline)
                .font(StrandFont.subhead)
                .foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    /// The redesigned vital template path (F2 §6-11): the six single-signal vitals (HRV · resting HR ·
    /// SpO₂ · steps · stress · respiration) share one Grotesk header + hero skin. Sleep and strain carry
    /// bespoke blocks, so they keep their own layout; recovery has its own path above. (FER-710)
    private static let vitalTemplateIDs: Set<String> = ["hrv", "rhr", "spo2", "skin_temp", "steps", "stress", "resp_rate"]
    private var isVitalTemplate: Bool { info.usesLevels && Self.vitalTemplateIDs.contains(info.id) }

    /// The data-origin dot for a redesigned header: a 6px dot in the origin's colour + a short label. The
    /// dot replaces the boxed source chip on these sheets. (FER-710)
    private func originDot(_ label: LocalizedStringKey, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Source"))
        .accessibilityValue(Text(label))
    }

    /// The vital header's origin dot: the metric hue for a band reading («Band · last night» for a nightly
    /// signal, «Band» otherwise) or the heart hue for an Apple reading — the same provenance signal the
    /// foot line + old chip resolved per reading, so it never lies about where the number came from. (FER-710)
    @ViewBuilder private var vitalOriginDot: some View {
        if appleSource {
            originDot("Apple Health", color: theme.dataHeart)
        } else if BandSummaryCopy.isNightly(metricID: info.id) {
            originDot("Band · last night", color: metricHue)
        } else {
            originDot("Band", color: metricHue)
        }
    }

    /// The active level for today's reading — the same classification the level instrument highlights —
    /// resolved from the metric's levels + today's value. nil with no reading or no levels yet. (FER-710)
    private var activeLevelKey: String? {
        guard let levels = resolvedLevels, let v = info.levelsTodayValue,
              let idx = MetricLevels.activeIndex(for: v, in: levels) else { return nil }
        return levels[idx].key
    }

    /// The vital's data-driven verdict under the hero: a short honest phrase for WHERE today's reading sits
    /// on the metric's own levels — never a fixed direction claim, so it can't contradict the day's data
    /// (repo rule: transparent, honest copy). nil hides it (no reading / no level yet). (FER-710)
    @ViewBuilder private var vitalReading: some View {
        if let phrase = vitalReadingText {
            Text(phrase)
                .font(StrandFont.headline)
                .foregroundStyle(theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var vitalReadingText: LocalizedStringKey? {
        guard let key = activeLevelKey else { return nil }
        switch (info.id, key) {
        case ("hrv", "above"):        return "Above your base, a good sign."
        case ("hrv", "inBase"):       return "In your usual range."
        case ("hrv", "below"):        return "Below your base, worth a look."
        case ("rhr", "athlete"):      return "Very low, athlete range."
        case ("rhr", "excellent"):    return "Low, a strong sign."
        case ("rhr", "normal"):       return "In a normal range."
        case ("rhr", "elevated"):     return "Above your usual, worth a look."
        case ("spo2", "normal"):      return "In a normal range."
        case ("spo2", "low"):         return "Below the typical range."
        case ("steps", "veryActive"): return "Very active today."
        case ("steps", "active"):     return "Active, a solid day."
        case ("steps", "sedentary"):  return "Quiet so far today."
        case ("stress", "low"):       return "Low, a calm day so far."
        case ("stress", "medium"):    return "Moderate so far today."
        case ("stress", "high"):      return "Running high today."
        case ("resp_rate", "normal"):   return "In a normal range."
        case ("resp_rate", "elevated"): return "Above your usual."
        case ("skin_temp", "below"):    return "Below your base."
        case ("skin_temp", "inBase"):   return "In your base."
        case ("skin_temp", "warm"):     return "Running warm vs your base."
        case ("skin_temp", "elevated"): return "Well above your base, worth a look."
        case ("strain", "rest"):     return "Very light day so far."
        case ("strain", "light"):    return "A light day so far."
        case ("strain", "moderate"): return "A solid, moderate day."
        case ("strain", "hard"):     return "A hard day of load."
        case ("strain", "extreme"):  return "An all-out day."
        default: return nil
        }
    }

    /// The Day Strain summary path (F2 §5): a scored day. No-reading falls through to the classic layout.
    private var isStrainSummary: Bool { info.id == "strain" && info.displayValue != "—" }

    /// «Tu patrón» (FER-710): one honest line per WhatMovesIt finding — a paper block with the metric-hue
    /// left bar (the handoff's «patrón/conexión» shape). Only HRV and resting HR carry findings; for the
    /// other vitals `whatMovesIt` is empty and the block disappears. Copy shared with the detail. (FER-209)
    @ViewBuilder private var vitalPatternBlock: some View {
        if !whatMovesIt.isEmpty {
            HStack(spacing: 0) {
                Rectangle().fill(metricHue).frame(width: 2.5)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Your pattern").groteskOverline().foregroundStyle(theme.inkTertiary)
                    ForEach(whatMovesIt) { f in
                        Text(f.phrase)
                            .font(StrandFont.subhead)
                            .foregroundStyle(theme.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(14)
                Spacer(minLength: 0)
            }
            .background(theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: CenitMetrics.controlRadius, style: .continuous))
        }
    }

    // MARK: - Sleep summary (F2 §4, FER-710) — doble dato + stage bar + «para esta noche»

    /// The rich sleep path: a night with stage data. No-night / Apple-only-without-stages fall through to
    /// the shared single-value layout, so those states stay unchanged.
    private var isSleepSummary: Bool { info.id == "sleep" && sleepDetail?.night != nil }

    /// «7:12» from minutes asleep.
    private static func sleepHM(_ minutes: Double) -> String {
        let m = Int(minutes.rounded()); return String(format: "%d:%02d", m / 60, m % 60)
    }

    /// A locale clock «23:38» from a unix timestamp.
    private static func clock(_ ts: Int) -> String { clockFmt.string(from: Date(timeIntervalSince1970: TimeInterval(ts))) }
    private static let clockFmt: DateFormatter = {
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("Hmm"); return f
    }()

    /// The two hero numerals — hours asleep | regularity /100 — split by a vertical hairline. Regularity
    /// reads «··» until the engine has enough nights (the numeral never lies). (FER-710)
    private var sleepDobleDato: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(Self.sleepHM(sleepDetail?.night?.stages.asleep ?? 0))
                    .groteskSheetNumeral().foregroundStyle(theme.dataSleep)
                Text("hours asleep").groteskOverline().foregroundStyle(theme.inkTertiary)
            }
            Rectangle().fill(theme.hairlineStrong).frame(width: 1, height: 46)
            VStack(alignment: .leading, spacing: 4) {
                if let r = sleepDetail?.regularity {
                    Text(verbatim: "\(r.score)").groteskSheetNumeral().foregroundStyle(theme.dataSleep)
                } else {
                    Text(verbatim: "··").groteskSheetNumeral().foregroundStyle(theme.inkTertiary)
                }
                Text("regularity").groteskOverline().foregroundStyle(theme.inkTertiary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// A short honest sleep verdict from the active duration lane, without an em dash. (FER-710)
    @ViewBuilder private var sleepReading: some View {
        if let phrase = sleepReadingText {
            Text(phrase).font(StrandFont.headline).foregroundStyle(theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    private var sleepReadingText: LocalizedStringKey? {
        switch activeLevelKey {
        case "optimal":  return "Right in your target range."
        case "adequate": return "Enough, close to your target."
        case "short":    return "Short of your target last night."
        case "extended": return "Longer than usual last night."
        default:         return nil
        }
    }

    /// «Anoche»: the stage bar (deep / REM / light / awake) + the onset→wake clock. Deep→REM→Light are one
    /// indigo graded by opacity (no new tokens); awake is quiet ink. (FER-710)
    @ViewBuilder private var sleepAnocheBlock: some View {
        if let night = sleepDetail?.night {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Last night").groteskOverline().foregroundStyle(theme.inkTertiary)
                    Spacer()
                    Text(verbatim: "\(Self.clock(night.startTs)) → \(Self.clock(night.endTs))")
                        .font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
                }
                SleepStageBar(stages: [
                    .init(minutes: night.stages.deep,  color: theme.dataSleep,               label: String(localized: "Deep")),
                    .init(minutes: night.stages.rem,   color: theme.dataSleep.opacity(0.78), label: String(localized: "REM")), // token-exempt: rampa graduada de etapas
                    .init(minutes: night.stages.light, color: theme.dataSleep.opacity(0.52), label: String(localized: "Light")), // token-exempt: rampa graduada de etapas
                    .init(minutes: night.stages.awake, color: theme.hairlineStrong,          label: String(localized: "Awake")),
                ], theme: theme)
            }
        }
    }

    /// The active duration lane label, moved just ABOVE the period selector for sleep (owner's call). (FER-710)
    @ViewBuilder private var sleepActiveLaneLabel: some View {
        if let name = sleepLaneName {
            (Text(name) + Text(verbatim: " · ") + Text("last night"))
                .font(InstrumentoType.groteskLane).tracking(InstrumentoType.groteskLaneTracking)
                .textCase(.uppercase).foregroundStyle(theme.dataSleep)
        }
    }
    /// The active sleep lane's label, from the single key→label home (FER-731); nil when there's no
    /// reading. A sleep sheet's `activeLevelKey` only ever resolves to a sleep level, so the name maps 1:1.
    private var sleepLaneName: LocalizedStringKey? {
        activeLevelKey.map { LocalizedStringKey(MetricLevels.name(for: $0)) }
    }

    /// «Para esta noche»: an honest, non-prescriptive line from regularity — the paper block with the sleep
    /// hue left bar. (FER-710)
    private var sleepParaEstaNoche: some View {
        PaperSideBarBlock(overline: "For tonight", text: sleepTonightText, hue: theme.dataSleep, theme: theme)
    }
    private var sleepTonightText: LocalizedStringKey {
        if let r = sleepDetail?.regularity, r.score >= 80 {
            return "Keep to your usual bedtime to hold this rhythm."
        }
        return "A steadier bedtime tonight helps your rhythm."
    }

    /// The plain-language recovery reading under the hero, banded like the detail's (green ready / yellow
    /// controlled / red rest) and written WITHOUT em dashes for the redesigned sheet. (FER-710)
    private var recoveryReading: some View {
        Text(recoveryReadingText)
            .font(StrandFont.headline)
            .foregroundStyle(theme.ink)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var recoveryReadingText: LocalizedStringKey {
        switch info.headerTint {
        case .good: return "Above your baseline, ready for a strong day."
        case .warn: return "Recovering, train but keep it controlled."
        case .bad:  return "Low, prioritize rest today."
        default:    return ""
        }
    }

    /// The zone meter (FER-710): today's score placed on the fixed recovery zones (Agotado / Bajo /
    /// Moderado / Alto / Pleno), segment widths ∝ each zone's span of 0–100, the active zone highlighted,
    /// an ink tick at score/100. Colours map the 5 zones onto recovery's 3 band roles (red / amber /
    /// green) so no new tokens are minted; labels reuse the level list's localized names (FER-638: the
    /// 70–88 zone is «Alto», not «A punto»).
    private var recoveryZoneMeter: some View {
        let levels = MetricLevels.levels(for: .recovery)
        let score = info.levelsTodayValue ?? 0
        let activeIndex = MetricLevels.activeIndex(for: score, in: levels)
        let segments = levels.enumerated().map { i, lvl in
            ZoneMeter.Segment(
                weight: (lvl.upper ?? 100) - (lvl.lower ?? 0),
                color: recoveryZoneColor(i),
                isActive: i == activeIndex,
                label: recoveryLevelLabel(lvl.key))
        }
        return ZoneMeter(segments: segments, fraction: score / 100, theme: theme)
    }

    /// The 5 recovery zones mapped onto the 3 band roles: depleted/low → critical, moderate → warning,
    /// primed/peak → verdict. Keeps colour meaningful (red→amber→green) without minting new tokens.
    private func recoveryZoneColor(_ index: Int) -> Color {
        switch index {
        case 0, 1: return theme.critical
        case 2:    return theme.warning
        default:   return theme.verdict
        }
    }

    /// The localized, uppercased zone label, from the single key→label home (`MetricLevels.name(for:)`,
    /// FER-731) so the meter, the level list and the brief never drift — FER-638 keeps the 70–88 key
    /// "primed" reading «Alto», never «A punto». The English name doubles as the `Localizable.xcstrings`
    /// key, so `String(localized:)` resolves the es-MX at runtime. (FER-710)
    private func recoveryLevelLabel(_ key: String) -> String {
        String(localized: String.LocalizationValue(MetricLevels.name(for: key))).localizedUppercase
    }

    /// The ⓘ that toggles the plain-language explanation in place: quiet ink when closed, the metric hue
    /// when open. Extracted so the serif (migrated) and overline (classic) headers share it. (FER-243)
    private var infoButton: some View {
        Button {
            withAnimation(StrandMotion.interactive) { headlineExpanded.toggle() }
        } label: {
            StrandIcon.info.image
                .font(StrandFont.glyph(.inline))
                .foregroundStyle(headlineExpanded ? metricHue : theme.inkTertiary)
        }
        .buttonStyle(.plain)
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityLabel(Text(headlineExpanded ? "Hide explanation" : "Show explanation"))
    }

    /// Quiet "this can come from Apple Health" line for an Apple-sourced metric that isn't connected
    /// and has no value yet. No button — the connect action lives in Today (single source of truth);
    /// closing the sheet leaves it one tap away. (FER-162)
    private var appleConnectLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            StrandIcon.heart.image
                .font(StrandFont.glyph(.chevron))
                .foregroundStyle(theme.dataHeart)
            Text("This reading can come from Apple Health. Connect it from Today to see it here.")
                .font(StrandFont.caption)
                .foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .instrumentoCard(.control, theme: theme, lineWidth: 0.5)
    }

    /// Quiet provenance line at the foot of the sheet: the displayed reading came from Apple Health (not
    /// the strap). The heart glyph (in the heart data hue) lets the source read at a glance, mirroring the
    /// Today tile's Apple badge. Shown only when `appleSource` — resolved per reading by the caller.
    private var appleSourceLine: some View {
        HStack(spacing: 6) {
            StrandIcon.heart.image
                .font(StrandFont.glyph(.chevron))
                .foregroundStyle(theme.dataHeart)
            Text("Apple Health")
                .font(StrandFont.caption)
                .foregroundStyle(theme.inkTertiary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Source · Apple Health"))
    }

    /// The F6 levels instrument for a migrated metric (FER-607): the shared `MetricLevelsExplorer` — a
    /// range selector, a «{level} · N de tus últimos M días» phrase, the trend drawn over the active
    /// band, and a tappable levels list — fed by the full-history series (re-windowed by `levelsRange`)
    /// and the per-metric thresholds from `MetricLevels` (FER-570). `todayValue` is the same number the
    /// header shows (`info.displayValue`), so the highlighted level matches the hero numeral.
    @ViewBuilder private var levelsBlock: some View {
        if let levels = resolvedLevels {
            let window = MetricWindowMath.make(levelsParsed, selected: levelsRange)
            MetricLevelsExplorer(
                theme: theme,
                range: $levelsRange,
                window: window,
                levels: levels,
                todayValue: info.levelsTodayValue,
                hue: metricHue,
                unit: info.unit ?? "",
                valueFormat: info.id == "sleep"
                    ? { mins in let h = Int(mins) / 60; let m = Int(mins) % 60; return m == 0 ? "\(h)h" : "\(h)h \(m)m" }
                    // Skin temp is a small °C deviation (±0.4 / +0.8 cut points) — integer rounding collapsed
                    // 0.4 and 0.8 to «0» / «1» on the axis and in the scrub. One decimal keeps it honest. (FER-763)
                    : info.id == "skin_temp" ? { String(format: "%.1f", $0) }
                    : { "\(Int($0.rounded()))" },
                nightly: BandSummaryCopy.isNightly(metricID: info.id),
                inkThumb: true,
                accessibilityLabel: info.name
            )
        } else if info.levelsRelative {
            // HRV with no personal baseline yet — an honest note, not an empty levels list.
            ChartWell(theme).empty(icon: "waveform.path.ecg",
                                   text: "Your levels come from your own baseline: a few more nights and they'll appear.")
        }
    }

    /// A fingerprint of `resolvedLevels`' inputs — the metric id + the loaded full history — so the
    /// ≥1-valid-night HRV fold only reruns when either changes, not on every render (FER-976).
    /// `levelsRange` does NOT feed `resolvedLevels` (it always folds the FULL `levelsParsed`, never the
    /// windowed slice), so it's deliberately not part of this key.
    private var resolvedLevelsKey: String {
        "\(info.id)|\(levelsParsed.count)|\(levelsParsed.first?.day ?? "")|\(levelsParsed.last?.day ?? "")"
    }

    /// The levels for the explorer: `MetricLevels`' fixed thresholds (FER-570) for a `levelsMetric`, or —
    /// for HRV — the user's PERSONAL band from their own baseline. HRV is log-normal, so the cut points
    /// come from `Baselines.normalRange` (which back-transforms `exp(lnBaseline ± σ)` to ms: a
    /// multiplicative band, not a raw linear ±SD), over the SAME production baseline engine the recovery
    /// score uses (`foldHistory` + `hrvCfg`, logDomain). The band *structure* (below/inBase/above,
    /// guard `nValid >= 1`) mirrors FER-571. nil for HRV until there's at least one valid night.
    /// (FER-619 · Plews 2013). Memoized (FER-976, same fallback discipline as CompareView.pairResults):
    /// reads the cache when the key matches, else computes once for THIS render (no mid-body mutation).
    private var resolvedLevels: [MetricLevels.Level]? {
        resolvedLevelsKey == resolvedLevelsCacheKey ? resolvedLevelsCache : computeResolvedLevels()
    }

    private func computeResolvedLevels() -> [MetricLevels.Level]? {
        if let metric = info.levelsMetric { return MetricLevels.levels(for: metric) }
        guard info.levelsRelative else { return nil }
        let state = Baselines.foldHistory(levelsParsed.map { Optional($0.value) }, cfg: Baselines.hrvCfg)
        guard state.nValid >= 1 else { return nil }
        let band = Baselines.normalRange(state)
        return [
            MetricLevels.Level(key: "below",  lower: nil,             upper: band.lowerBound),
            MetricLevels.Level(key: "inBase", lower: band.lowerBound, upper: band.upperBound),
            MetricLevels.Level(key: "above",  lower: band.upperBound, upper: nil),
        ]
    }

    /// Persists `resolvedLevels` into the `@State` cache — called after `levelsParsed` loads (see the
    /// `.task` below), so subsequent renders (scrub/hover) hit the cache instead of re-folding.
    private func refreshResolvedLevelsCache() {
        let key = resolvedLevelsKey
        guard key != resolvedLevelsCacheKey else { return }
        resolvedLevelsCacheKey = key
        resolvedLevelsCache = computeResolvedLevels()
    }

    private var bandsTable: some View {
        let counts = bandSummary?.counts
        return VStack(spacing: 0) {
            ForEach(Array(info.bands.enumerated()), id: \.offset) { i, band in
                bandRow(band, count: counts.flatMap { i < $0.count ? $0[i] : nil })
                if i < info.bands.count - 1 {
                    Divider().overlay(theme.hairline).padding(.leading, 36)
                }
            }
        }
        .background(theme.surface, in: RoundedRectangle(cornerRadius: CenitMetrics.controlRadius, style: .continuous))
    }

    /// One reference-band row. `count` (when the trend has loaded) shows how many of the windowed
    /// days/nights fell in this band — the "días en tu rango" readout, now per band. (FER-459)
    private func bandRow(_ band: MetricInfo.Band, count: Int?) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(band.isActive ? metricHue : theme.inkTertiary.opacity(StrandOpacity.dim))
                .frame(width: 8, height: 8)
                .padding(.leading, 14)
            Text(band.label)
                .font(StrandFont.subhead)
                .foregroundStyle(band.isActive ? theme.ink : theme.inkSecondary)
            Spacer()
            Text(band.range)
                .font(StrandFont.captionNumber)
                .foregroundStyle(band.isActive ? metricHue : theme.inkTertiary)
            if let count {
                Text(BandSummaryCopy.countLabel(count, nightly: BandSummaryCopy.isNightly(metricID: info.id)))
                    .font(StrandFont.captionNumber)
                    .foregroundStyle(band.isActive ? metricHue : theme.inkTertiary.opacity(0.85)) // token-exempt: >0.70 (conteo inactivo tenue)
                    .frame(minWidth: 56, alignment: .trailing)
            }
        }
        .padding(.trailing, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity)
        .background(band.isActive ? metricHue.opacity(StrandOpacity.tintFill) : Color.clear)
    }

    // MARK: - Band trend summary (FER-459)

    /// Band classification of the loaded 14-day trend — the per-band counts + the summary sentence.
    /// `nil` until the trend loads, or when the metric carries no bands (HRV). Steps' in-progress day is
    /// excluded from the trend (FER-264), so it gets no "today" band → no today clause.
    private var bandSummary: BandTrendSummary? {
        guard !info.bands.isEmpty, !trendData.isEmpty else { return nil }
        // Sleep's bands are in HOURS but its trend is in minutes — convert so the classification lines up
        // (same `toHours` as `bandedTrend`). Every other metric's trend already matches its band units.
        let toHours = info.id == "sleep"
        // Steps' latest point is the in-progress day (FER-264) — drop it so the counts read completed days
        // only, and it carries no "today" band.
        let isSteps = info.id == "steps"
        // trendData is already date-sorted at load (FER-876).
        let source = (isSteps && trendData.count > 1) ? Array(trendData.dropLast()) : trendData
        let values = source.map { toHours ? $0.value / 60 : $0.value }
        let bands = info.bands.map { TrendBand(label: $0.label, lower: $0.lower, upper: $0.upper) }
        let todayIndex = isSteps ? nil : info.bands.firstIndex(where: { $0.isActive })
        return TrendBands.summarize(values: values, bands: bands, todayIndex: todayIndex)
    }

    /// The standardized «{band} · X of the last N days/nights in this range» readout shown above the ranges
    /// table on every summary sheet — the active band = today's band (matching the highlighted row + the
    /// chart; falls back to the latest completed reading), plus how many completed days share it. One
    /// wording everywhere. Nocturnal metrics (sleep, SpO₂) read "nights". (FER-469 / FER-471)
    private var rangeReadout: (label: LocalizedStringKey, count: Int, total: Int)? {
        guard !info.bands.isEmpty, !trendData.isEmpty else { return nil }
        let toHours = info.id == "sleep"
        let isSteps = info.id == "steps"
        // trendData is already date-sorted at load (FER-876).
        let source = (isSteps && trendData.count > 1) ? Array(trendData.dropLast()) : trendData
        let values = source.map { toHours ? $0.value / 60 : $0.value }
        let bands = info.bands.map { TrendBand(label: $0.label, lower: $0.lower, upper: $0.upper) }
        // Active band = today's band (the highlighted row + the chart's shaded band), so the line agrees
        // with both; the count still comes from completed days. Falls back to the most recent completed
        // reading when there's no today value (e.g. no steps yet). (FER-471)
        guard let ai = info.bands.firstIndex(where: { $0.isActive })
            ?? TrendBands.activeBand(values: values, bands: bands)?.index else { return nil }
        let count = values.reduce(0) { $0 + (bands[ai].contains($1) ? 1 : 0) }
        return (info.bands[ai].label, count, values.count)
    }

    @ViewBuilder private var rangeReadoutLine: some View {
        if let r = rangeReadout {
            let nightly = BandSummaryCopy.isNightly(metricID: info.id)
            HStack(spacing: 6) {
                Text(r.label).foregroundStyle(metricHue)
                Text(verbatim: "·").foregroundStyle(theme.inkTertiary)
                Text(nightly ? "\(r.count) of the last \(r.total) nights in this range"
                             : "\(r.count) of the last \(r.total) days in this range")
                    .foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(StrandFont.subhead)
        }
    }

    // MARK: - Heart-rate 24h chart (FER-137)

    /// Today's continuous HR curve, a bit taller than the standard chart. Built inline with theme
    /// tokens (rather than the shared, dark `ChartCard`) so it reads on warm paper. Empty curve → an
    /// honest "no readings yet" well (a strap-only day with no wear).
    @ViewBuilder private var heartRateSection: some View {
        if heartRateCurve.count > 1 {
            let v = heartRateCurve.map(\.value)
            VStack(alignment: .leading, spacing: CenitMetrics.space2) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Beats per minute")
                            .font(StrandFont.headline)
                            .foregroundStyle(theme.ink)
                        Text("5-minute average · since midnight")
                            .font(StrandFont.footnote)
                            .foregroundStyle(theme.inkTertiary)
                    }
                    Spacer()
                    if let last = v.last {
                        Text("\(Int(last.rounded())) bpm")
                            .font(StrandFont.bodyNumber)
                            .foregroundStyle(theme.ink)
                    }
                }
                TrendChart(
                    points: heartRateCurve,
                    gradient: chartGradient,
                    valueRange: Self.hrRange(v),
                    showsArea: true,
                    height: 260,
                    showsScrub: true,
                    valueFormat: { "\(Int($0.rounded())) \(String(localized: "bpm"))" },
                    dateFormat: { Self.hrClock.string(from: $0) },
                    axisLabelColor: theme.inkTertiary,
                    gridLineColor: theme.hairline,
                    tightTrailing: true
                )
                hrFooter(v)
            }
        } else if heartRateLoading {
            ChartWell(theme).loading(height: 200)
        } else {
            ChartWell(theme).empty(icon: "waveform.path.ecg", text: "No readings yet today.")
        }
    }

    /// Min / avg / max under the 24h HR chart. Stats are pre-computed with explicit Double arithmetic so
    /// the type-checker doesn't thrash on `reduce(0, +)` (Int vs Double). Row UI is a separate piece. (FER-981)
    private func hrFooter(_ v: [Double]) -> some View {
        let loRaw: Double = v.min() ?? 0.0
        let hiRaw: Double = v.max() ?? 0.0
        let sum: Double = v.reduce(0.0, +)
        let denom: Double = Double(max(v.count, 1))
        let lo: Int = Int(loRaw.rounded())
        let avg: Int = Int((sum / denom).rounded())
        let hi: Int = Int(hiRaw.rounded())
        return hrFooterRow(lo: lo, avg: avg, hi: hi)
    }

    @ViewBuilder private func hrFooterRow(lo: Int, avg: Int, hi: Int) -> some View {
        let loText: String = String(lo)
        let avgText: String = String(avg)
        let hiText: String = String(hi)
        HStack {
            footerStat("Min", loText)
            Spacer()
            footerStat("Avg", avgText)
            Spacer()
            footerStat("Max", hiText)
        }
    }

    private func footerStat(_ label: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).textCase(.uppercase)
                .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
            Text(value)
                .font(StrandFont.captionNumber).foregroundStyle(theme.inkSecondary)
        }
    }

    /// Padded HR axis range so the line never sits flush against an edge (mirrors TodayView.hrRange).
    private static func hrRange(_ v: [Double]) -> ClosedRange<Double> {
        guard let lo = v.min(), let hi = v.max() else { return 40...120 }
        if hi <= lo { return (lo - 5)...(hi + 5) }
        let span = hi - lo
        return (lo - span * 0.12)...(hi + span * 0.12)
    }

    private static let hrClock: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "h a"; return f
    }()

    // MARK: - 14-day trend chart

    /// "Last 14 days" trend chart shown in the upper section of every key-metric sheet. The chart
    /// auto-scales to the metric's own range so a narrow RHR window (52–58 bpm) still reads as a
    /// clear curve instead of a flat line pinned to 0–200. Line/area use the metric hue. (FER-115 /
    /// FER-162)
    @ViewBuilder private var trendSection: some View {
        VStack(alignment: .leading, spacing: CenitMetrics.space2) {
            Text("Last 14 days")
                .font(StrandFont.headline)
                .foregroundStyle(theme.ink)
            // The «{band} · X of N days in this range» readout sits right under the title, contextualizing
            // the period before the chart (instead of floating below it). (FER-473)
            rangeReadoutLine
            if trendData.count > 1 {
                if let bt = bandedTrend {
                    // The «{band} · X of N days in this range» readout now lives once, above the ranges
                    // table (`rangeReadoutLine`), standardized across every metric. (FER-469)
                    TrendChart(
                        points: bt.points,
                        gradient: chartGradient,
                        valueRange: bt.range,
                        showsArea: true,
                        height: 140,
                        showsScrub: true,
                        valueFormat: bt.valueFormat,
                        dateFormat: Self.trendDayString,
                        axisLabelColor: theme.inkTertiary,
                        gridLineColor: theme.hairline,
                        bands: bt.bands,
                        bandColor: bt.color,
                        yAxisValues: bt.yTicks,
                        accessibilityLabel: "14-day trend with classification bands"
                    )
                } else {
                    TrendChart(
                        points: trendData,
                        gradient: chartGradient,
                        valueRange: trendValueRange,
                        showsArea: true,
                        height: 140,
                        showsScrub: true,
                        valueFormat: trendValueFormat,
                        dateFormat: Self.trendDayString,
                        axisLabelColor: theme.inkTertiary,
                        gridLineColor: theme.hairline,
                        // HRV has no right-side range labels, so let its curve reach the edge instead of
                        // reserving the band-label gutter. (FER-460)
                        tightTrailing: info.id == "hrv",
                        accessibilityLabel: "14-day trend"
                    )
                }
            } else if trendLoading {
                ChartWell(theme).loading(height: 140)
            } else {
                ChartWell(theme).empty(icon: "chart.xyaxis.line", text: "No data for the last 14 days.")
            }
        }
    }

    /// The banded-chart configuration for the metrics whose trend reads against fixed classification
    /// bands (sleep, stress, SpO₂, FC reposo, steps) — today's band shaded (the same one the ranges table
    /// highlights and the readout names, FER-471), the Y range anchored to the band thresholds, ticks at
    /// those thresholds, and a paper-legible value format. Sleep is converted to HOURS here (its series is
    /// stored in minutes); the others keep their own units. `nil` for every other metric (HRV, VO₂max…),
    /// so they keep the plain auto-scaled chart. (FER-244)
    private struct BandedTrend {
        var points: [TrendPoint]
        var bands: [TrendBand]
        var range: ClosedRange<Double>
        var yTicks: [Double]
        var color: Color
        var valueFormat: (Double) -> String
        var activeLabel: LocalizedStringKey
        var count: Int
        var total: Int
    }

    private var bandedTrend: BandedTrend? {
        // The metrics whose summary-sheet trend reads against fixed classification bands, drawn behind the
        // line like sleep/stress — the same family that already carries the ranges table + readout
        // (FER-459/469). Extending it here gives SpO₂, FC reposo and Pasos the labelled carriles their
        // chart was missing, matching sleep/stress.
        let banded: Set<String> = ["sleep", "stress", "spo2", "rhr", "steps"]
        guard banded.contains(info.id), !info.bands.isEmpty, trendData.count > 1 else { return nil }
        let toHours = info.id == "sleep"
        let isSteps = info.id == "steps"
        // trendData is already date-sorted at load (FER-876).
        let pts = trendData.map { TrendPoint(date: $0.date, value: toHours ? $0.value / 60 : $0.value) }
        let values = pts.map(\.value)
        // Steps' latest point is today's partial total (FER-264): plot every day, but count completed days
        // only so the partial total doesn't inflate the active band's tally.
        let completed = (isSteps && values.count > 1) ? Array(values.dropLast()) : values
        var bands = info.bands.map { TrendBand(label: $0.label, lower: $0.lower, upper: $0.upper) }
        // Shade today's band — the same one the ranges table highlights and the readout names (FER-471);
        // fall back to the latest completed reading when there's no usable today.
        guard let activeIdx = info.bands.firstIndex(where: { $0.isActive })
            ?? TrendBands.activeBand(values: completed, bands: bands)?.index else { return nil }
        bands[activeIdx].isActive = true
        let activeCount = completed.reduce(0) { $0 + (bands[activeIdx].contains($1) ? 1 : 0) }
        let thresholds = Set(info.bands.flatMap { [$0.lower, $0.upper].compactMap { $0 } }).sorted()
        let tLo = thresholds.first ?? (values.min() ?? 0)
        let tHi = thresholds.last ?? (values.max() ?? 1)
        let lo = min(values.min() ?? tLo, tLo)
        let hi = max(values.max() ?? tHi, tHi)
        let pad = max((hi - lo) * 0.08, 0.25)
        let range = max(0, lo - pad)...(hi + pad)
        // Sleep plots in hours (h/m); every other banded metric reuses its standard per-metric formatter
        // (rhr → bpm, spo2 → %, steps → grouped integer, stress → one decimal).
        let fmt: (Double) -> String = toHours
            ? { v in let m = Int((v * 60).rounded()); return m % 60 > 0 ? "\(m / 60)h \(m % 60)m" : "\(m / 60)h" }
            : trendValueFormat
        return BandedTrend(points: pts, bands: bands, range: range, yTicks: thresholds,
                           color: metricHue, valueFormat: fmt,
                           activeLabel: bands[activeIdx].label, count: activeCount, total: completed.count)
    }

    /// Auto-scale: 15% headroom above the max, floor capped at zero.
    private var trendValueRange: ClosedRange<Double> {
        let vals = trendData.map(\.value)
        guard let lo = vals.min(), let hi = vals.max() else { return 0...100 }
        let span = max(hi - lo, 1)
        let pad  = span * 0.15
        return max(0, lo - pad)...hi + pad
    }

    private var trendValueFormat: (Double) -> String {
        switch info.id {
        case "strain":  return { String(format: "%.1f", $0) }
        case "stress":  return { String(format: "%.1f", $0) }   // 0–3 proxy reads with one decimal, not rounded to "2"
        case "sleep":   return { Self.formatSleep(Int($0.rounded())) }
        // Detalle de Sueño night metrics (FER-227): percent shares, a 0.1-rpm respiration, integer wakes.
        case "sleep_performance", "sleep_efficiency", "sleep_restorative":
                        return { "\(Int($0.rounded()))%" }
        case "resp_rate":
                        return { String(format: "%.1f", $0) }
        case "sleep_awakenings":
                        return { "\(Int($0.rounded()))" }
        case "rhr":     return { "\(Int($0.rounded())) \(String(localized: "bpm"))" }
        case "spo2":    return { String(format: "%.0f%%", $0) }
        case "steps":   return { Self.stepFmt.string(from: NSNumber(value: Int($0.rounded()))) ?? "\(Int($0.rounded()))" }
        default:        return { "\(Int($0.rounded()))" }
        }
    }

    private static let trendDayFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "d MMM"; return f
    }()
    private static func trendDayString(_ date: Date) -> String { trendDayFmt.string(from: date) }

    private static let stepFmt: NumberFormatter = {
        let f = NumberFormatter(); f.numberStyle = .decimal; return f
    }()

    private static func formatSleep(_ totalMinutes: Int) -> String {
        let h = totalMinutes / 60, m = totalMinutes % 60
        return m > 0 ? "\(h)h \(m)m" : "\(h)h"
    }

    // MARK: - Recovery weight breakdown + method disclosure (FER-108)

    /// Cold-start progress: "Calibrating baseline" over a thin recovery-tinted track, shown instead of
    /// a score while the recovery baseline is still seeding.
    private func calibrationCard(_ cal: MetricInfo.Calibration) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Calibrating baseline").groteskOverline().foregroundStyle(theme.inkTertiary)
                Spacer()
                Text("\(cal.done) of \(cal.needed) nights")
                    .font(StrandFont.captionNumber)
                    .foregroundStyle(theme.inkSecondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(theme.hairline).frame(height: 6)
                    Capsule().fill(theme.dataRecovery)
                        .frame(width: max(6, geo.size.width * CGFloat(cal.done) / CGFloat(max(cal.needed, 1))),
                               height: 6)
                }
            }
            .frame(height: 6)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: CenitMetrics.controlRadius, style: .continuous))
    }

    // MARK: «Qué la movió hoy» (FER-628)

    /// |contribution| below this reads as "barely moved it" — no arrow, quiet copy. The buckets are
    /// copy thresholds only (the math is `RecoveryImpact`); in composite-z units, where the score's
    /// full Red–Green band spans ≈ ±2 (RecoveryScorer.logisticK).
    private static let impactBarely = 0.12

    /// «Qué la movió hoy»: today's per-signal impact on the recovery score, ordered by REAL
    /// contribution (|z·weight|, the FER-632 ranking — never |z| alone). One plain-language headline
    /// naming the day's driver, then a row per signal: its state word, an impact phrase, and a
    /// divergent vs-your-base bar whose length is the contribution. No σ and no % here — those live
    /// under "How it's calculated".
    private func impactBlock(_ impact: RecoveryImpact.Result) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Today, vs your normal")
                .groteskOverline()
                .foregroundStyle(theme.inkTertiary)
            impactHeadline(impact)
                .font(StrandFont.subhead)
                .foregroundStyle(theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(impact.signals.enumerated()), id: \.element.id) { i, s in
                    impactRow(s, index: i)
                }
            }
            impactLegend
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: CenitMetrics.controlRadius, style: .continuous))
    }

    /// The plain-language headline names the signal with the LARGEST contribution to today's score
    /// (its state word in the flag color, everything else in ink). Built from fragments so it
    /// localizes cleanly, like `RecoveryDetailScreen`'s titular.
    private func impactHeadline(_ impact: RecoveryImpact.Result) -> Text {
        guard let top = impact.top, abs(top.contribution) >= Self.impactBarely else {
            return Text("All your signals sat near your base today.")
        }
        let tail: LocalizedStringKey = top.contribution < 0
            ? ", is what holds your recovery back most today."
            : ", is what holds your recovery up most today."
        return Text("Your ")
            + Text(Self.impactLabel(top.key)).foregroundColor(impactColor(impactFlag(top))).fontWeight(.semibold)
            + Text(Self.positionPhrase(top))
            + Text(tail)
    }

    /// One signal: overline label · position-vs-base word (flag hue) · `· N%` weight, and the divergent
    /// contribution bar below, via the shared `ImpactSignalRow` (FER-975; was a hand-copy of the
    /// Detalle's `levelSignalRow`, now the same component). VoiceOver reads the combined row.
    private func impactRow(_ s: RecoveryImpact.Signal, index: Int) -> some View {
        let flag = impactFlag(s)
        let color = flag == .neutral ? theme.inkSecondary : impactColor(flag)
        return ImpactSignalRow(
            label: Self.impactLabel(s.key),
            word: Self.baseBandWord(s),
            weightPct: Int((s.weight * 100).rounded()),
            contribution: s.contribution,
            color: color,
            index: index,
            theme: theme
        )
    }

    /// The position-vs-base word from the RAW deviation (+ = the metric itself sits above your average),
    /// so the word is honest about where the value is; the row color (oriented flag) carries the valence.
    /// |z| < 1 reads «In your base». Shared vocabulary with the Detalle. (FER-642)
    private static func baseBandWord(_ s: RecoveryImpact.Signal) -> LocalizedStringKey {
        if s.z >= 1 { return "Above your base" }
        if s.z <= -1 { return "Below your base" }
        return "In your base"
    }

    /// The headline's inline position clause, «, above your base, » etc., with a «well» qualifier past 1σ.
    /// Matches `baseBandWord`. (FER-642)
    private static func positionPhrase(_ s: RecoveryImpact.Signal) -> LocalizedStringKey {
        let above = s.z >= 0
        let strong = abs(s.z) >= 1.0
        return strong
            ? (above ? ", well above your base" : ", well below your base")
            : (above ? ", above your base"      : ", below your base")
    }

    /// The axis legend: «◀ te la bajó · tu base · te la subió ▶» — decorative, hidden from VoiceOver.
    private var impactLegend: some View {
        ImpactAxisLegend(theme: theme)
    }

    /// The signal's display name — the same catalog keys the Detalle's driver rows use.
    private static func impactLabel(_ key: String) -> LocalizedStringKey {
        switch key {
        case "hrv":      return "HRV"
        case "rhr":      return "Resting HR"
        case "sleep":    return "Sleep"
        case "skinTemp": return "Skin temp"
        case "respRate": return "Respiration"
        default:         return LocalizedStringKey(key)
        }
    }

    /// State flag from the ORIENTED z (+ = pushed the score up) — the single source of the σ cuts
    /// (`ReadinessEngine.Flag(orientedZ:)`), so the state words agree with the Detalle's and the score.
    private func impactFlag(_ s: RecoveryImpact.Signal) -> ReadinessEngine.Flag {
        ReadinessEngine.Flag(orientedZ: s.orientedZ)
    }

    /// flag → theme color, shared with the Detalle's driver rows so both surfaces color states alike.
    private func impactColor(_ flag: ReadinessEngine.Flag) -> Color { flag.color(theme) }

    /// Progressive disclosure: the technical "how" lives one tap down, collapsed by default. Uses the
    /// shared `Metodo` component (FER-975; was a hand-copy — same DisclosureGroup shape as the Detalle
    /// screens' «Cómo se calcula»). `Metodo` owns its own collapsed state internally.
    private func methodDisclosure(_ method: MetricInfo.Method) -> some View {
        Metodo(title: String(localized: "How it's calculated"), theme: theme) {
            Text(method.prose)
                .font(StrandFont.subhead)
                .foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let citation = method.citation {
                Text(citation)
                    .font(StrandFont.caption)
                    .foregroundStyle(theme.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Trailing "Ver más" link at the foot of the sheet: drills from this summary into the metric's rich
    /// Detalle. Tinted with the metric hue (the one place colour lives on an action here) so it reads as
    /// tappable and ties to the metric. Right-aligned. (FER-251)
    @ViewBuilder private func seeMoreLink(_ action: @escaping () -> Void) -> some View {
        if info.usesLevels {
            // FER-607: full-width «Ver más en Tendencias» with the trend-line glyph and an ink hairline
            // border — drills into the same rich detail Cuerpo opens (the handoff foot button).
            Button(action: action) {
                HStack(spacing: 7) {
                    // The actual «Tendencias» screen glyph (curve-with-nodes), not a generic chart icon. (FER-710)
                    TendenciasGlyph(color: theme.ink, lineWidth: 1.8)
                        .frame(width: 15, height: 15)
                    Text("See more in Trends")
                        .font(StrandFont.subhead.weight(.medium))
                }
                .foregroundStyle(theme.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .overlay(
                    RoundedRectangle(cornerRadius: CenitMetrics.controlRadius, style: .continuous)
                        .strokeBorder(theme.ink, lineWidth: 1.5)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("See more in Trends"))
            .accessibilityHint(Text("Opens the full detail"))
        } else {
            HStack {
                Spacer(minLength: 0)
                Button(action: action) {
                    HStack(spacing: 4) {
                        Text("See more")
                            .font(StrandFont.subhead.weight(.medium))
                        StrandIcon.disclosure.image
                            .font(StrandFont.glyph(.chevron, weight: .semibold))
                    }
                    .foregroundStyle(metricHue)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(metricHue.opacity(StrandOpacity.tintFill), in: Capsule())
                }
                .buttonStyle(.plain)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
                .accessibilityLabel(Text("See more"))
                .accessibilityHint(Text("Opens the full detail"))
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("MetricInfoSheet: Strain") {
    Color.clear.sheet(isPresented: .constant(true)) {
        MetricInfoSheet(info: .strain(3.9))
    }
}

#Preview("MetricInfoSheet: HRV") {
    Color.clear.sheet(isPresented: .constant(true)) {
        MetricInfoSheet(info: .hrv(66))
    }
}

#Preview("MetricInfoSheet: HRV (no data)") {
    Color.clear.sheet(isPresented: .constant(true)) {
        MetricInfoSheet(info: .hrv(nil))
    }
}

#Preview("MetricInfoSheet: Steps (no permission)") {
    Color.clear.sheet(isPresented: .constant(true)) {
        MetricInfoSheet(info: .steps(nil), appleConnectHint: true)
    }
}

#Preview("MetricInfoSheet: SpO₂") {
    Color.clear.sheet(isPresented: .constant(true)) {
        MetricInfoSheet(info: .spo2(97))
    }
}

#Preview("MetricInfoSheet: Skin temp") {
    Color.clear.sheet(isPresented: .constant(true)) {
        MetricInfoSheet(info: .skinTemp(0.3))
    }
}

#Preview("MetricInfoSheet: Skin temp (no data)") {
    Color.clear.sheet(isPresented: .constant(true)) {
        MetricInfoSheet(info: .skinTemp(nil))
    }
}

#Preview("MetricInfoSheet: Recovery") {
    Color.clear.sheet(isPresented: .constant(true)) {
        // The 27-jun-2026 sick-day shape: HRV collapsed (the driver), resting HR way up, the rest quiet.
        MetricInfoSheet(info: .recovery(score: 12, calibrationNights: nil, nightsNeeded: 4,
            impact: RecoveryImpact.Result(signals: [
                .init(key: "hrv",      z: -3.6, orientedZ: -3.6, weight: 0.545),
                .init(key: "rhr",      z:  3.0, orientedZ: -3.0, weight: 0.182),
                .init(key: "skinTemp", z:  2.4, orientedZ: -2.4, weight: 0.091),
                .init(key: "sleep",    z: -0.4, orientedZ: -0.4, weight: 0.136),
                .init(key: "respRate", z:  0.6, orientedZ: -0.6, weight: 0.045),
            ])))
    }
}

#Preview("MetricInfoSheet: Recovery (calibrating)") {
    Color.clear.sheet(isPresented: .constant(true)) {
        MetricInfoSheet(info: .recovery(score: nil, calibrationNights: 2, nightsNeeded: 4))
    }
}

#Preview("MetricInfoSheet: Stress (low)") {
    Color.clear.sheet(isPresented: .constant(true)) {
        MetricInfoSheet(info: .stress(0.8))
    }
}

#Preview("MetricInfoSheet: Stress (high)") {
    Color.clear.sheet(isPresented: .constant(true)) {
        MetricInfoSheet(info: .stress(2.4))
    }
}
#endif
