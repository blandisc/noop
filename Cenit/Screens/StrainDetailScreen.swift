#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore
import Foundation

// MARK: - StrainDetailScreen — el «Detalle de Esfuerzo» en «Instrumento» (FER-238)
//
// Hermana de `MetricDetailScreen` (FER-185), `RecoveryDetailScreen` (FER-225) y `SleepDetailScreen`
// (FER-212): REUSA su lenguaje visual (hero, `InfoAccordion`, `theme: InstrumentoTheme` explícito,
// `SheetPaperBackground`, `ScrollView`→`VStack`, `methodDisclosure`, los wells, la window-math de la
// tendencia) pero con su propio modelo. NO extiende `MetricDetailScreen`/`MetricDetailSpec` (esos son
// para vitales de serie ESCALAR única — HRV/FC/Respiración, con hero = promedio móvil 7d y rango normal
// personal). El esfuerzo es una métrica COMPUESTA con forma propia: el hero es el valor de HOY en escala
// fija 0–21, su visualización firma es la CURVA INTRADÍA acumulada del día, y su referencia son ZONAS
// fijas (no un rango rolling). Reemplaza, para Esfuerzo en Cuerpo, la vieja `MetricInfoSheet`. Hoy
// (TodayView) NO cambia: sigue abriendo `MetricInfo.strain`/`MetricInfoSheet`.
//
// Se presenta vía `.sheet(item:)` con el tema vivo pasado EXPLÍCITO (no propaga por `.sheet`, FER-162) y
// SIN `NavigationStack` anidado (un stack anidado cruzando el path de la tab crasheaba SwiftUI, FER-171).
//
// Bloques, cada uno con su ⓘ (`InfoAccordion`) salvo el método (DisclosureGroup): 1) Hero (valor de hoy
// en `theme.dataStrain`, lectura por zona) · 2) Cómo se acumuló hoy (curva intradía, async) · 3) Zonas
// (las 4 bandas de `MetricInfo.strain`, la activa marcada) · 4) Tendencia 14d (+ Prom/Mín/Máx) · 5) Ver
// el método. Consume `StrandAnalytics`/la curva de `CuerpoView.loadStrainCurve()` TAL CUAL: no crea math.

/// Light «Instrumento» Detalle de Esfuerzo. Built once from a `StrainDetailModel` (the caller injects the
/// model so the screen stays DB-free); the intraday curve is loaded async (it reads HR samples from the
/// DB) the same way `MetricDetailScreen` injects its `seriesLoader`. Themed explicitly for the sheet.
struct StrainDetailScreen: View {
    /// The live «Instrumento» theme, passed explicitly (sheets start a fresh environment). (FER-162)
    var theme: InstrumentoTheme = .base
    /// Everything the screen draws from the in-memory dashboard, derived ONCE by the caller (no DB here).
    let model: StrainDetailModel
    /// Today's accumulated-strain curve, loaded async (it reads HR samples — DB I/O, not pure). Returns
    /// `[]` when there's no score / too little activity yet. Injected by the caller (`loadStrainCurve`).
    var curveLoader: () async -> [TrendPoint] = { [] }

    /// The trend block's period window (W/M/3M/6M/1Y/ALL). Defaults to a month.
    @State private var range: ExploreRange = .month
    /// The strain series with each `day` string parsed to a `Date` exactly ONCE (not per slice / per
    /// render) — the window math reads `date` straight from here. Built in `.task`. (FER-216 lesson)
    @State private var parsed: [(day: String, date: Date?, value: Double)] = []
    /// Today's intraday curve, loaded in `.task` (loading well until then).
    @State private var curve: [TrendPoint] = []
    @State private var curveLoaded = false
    @State private var methodExpanded = false
    /// Level-3 disclosure: the 14-day trend + «What moves your strain» live under «See your history»,
    /// collapsed on open. Strain is the LIGHT cut — no Level 2 — so this is the only re-sequencing
    /// state, and it folds just those two blocks for consistency. (Detalles escalonados)
    @State private var historyExpanded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                // Level 1 · the answer: hero + today's intraday curve + the fixed zones. Already the
                // daily check; Strain needed no condensing (light cut).
                hero
                if !model.loaded {
                    loadingWell(height: 160)
                } else {
                    // The intraday curve needs a score / activity today; it's hidden when there's none.
                    if model.hasData {
                        blockDivider
                        curveBlock
                    }
                    // The F6c level instrument (line + tappable levels + «N de tus últimos M días»)
                    // replaces the old static zones once there's history to count; with no history it
                    // falls back to the FIXED zones reference, honest about the missing score. (FER-572)
                    blockDivider
                    if model.series.count >= 2 {
                        levelsBlock
                    } else {
                        zonesBlock
                    }
                    // Level 3 · «See your history»: what moves your strain, collapsed by default. The trend
                    // chart folded in here moved up into the level instrument above. (FER-572)
                    if model.hasData {
                        blockDivider
                        historySection
                    }
                    blockDivider
                    methodDisclosure
                }
            }
            .padding(NoopMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.paper)
        .presentationDragIndicator(.visible)
        .modifier(StrainSheetPaperBackground(paper: theme.paper))
        .task {
            range = .month
            parsed = model.series.map { ($0.day, Repository.parseDayKey($0.day), $0.value) }
            curve = await curveLoader()
            curveLoaded = true
        }
    }

    /// A subtle 1px rule between blocks (token-only). Mirrors the sibling screens' `blockDivider`.
    private var blockDivider: some View {
        Rectangle().fill(theme.hairline).frame(height: 1)
    }

    // MARK: - 1. Hero — el valor de hoy (0–21) en color del dato

    private var hero: some View {
        let v = model.today
        // Serif in-screen title + ⓘ (the «Instrumento» detail identity, FER-581). Explanation stays behind
        // the ⓘ exactly as the old InfoAccordion had it.
        return VStack(alignment: .leading, spacing: 6) {
            InstrumentoScreenTitle("Day Strain", theme: theme,
                explanation: "Day Strain is your cardiovascular load on a 0–21 scale. Each second your heart rate is recorded, it's placed in an intensity zone (1–5); higher zones weigh more, and the total is compressed logarithmically so 21 is a theoretical maximum — a full day at peak intensity. (Edwards 1993; Banister 1991)")
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(v.map { fmt($0) } ?? "—")
                        .instrumentoHero(46)
                        .foregroundStyle(v == nil ? theme.inkTertiary : theme.dataStrain)
                    if v != nil {
                        Text("/ 21").font(StrandFont.unit).foregroundStyle(theme.inkTertiary)
                    }
                }
                Text(heroReading)
                    .font(StrandFont.subhead)
                    .foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// A plain-language reading of today's strain by zone, or an honest "no strain yet" when there's no
    /// score (strain is strap-only; Apple Health doesn't compute it). The zone is derived from the SAME
    /// `MetricInfo.strain` bands the zones block shows, so the reading and the highlighted zone can never
    /// disagree if a boundary is ever retuned (single source of truth — no second copy of the thresholds).
    /// Source strings are English; the es values live in `Localizable.xcstrings`.
    private var heroReading: LocalizedStringKey {
        guard let v = model.today else {
            if !model.series.isEmpty { return "No strain from today yet — your recent history is below." }
            return "No strain yet. Wear your strap through the day and open this again after it syncs."
        }
        switch MetricInfo.strain(v).bands.firstIndex(where: \.isActive) ?? 0 {
        case 0:  return "Light load today — plenty left in the tank."
        case 1:  return "Moderate effort today."
        case 2:  return "Hard effort today — solid work."
        default: return "All-out day — about as much strain as you carry."
        }
    }

    // MARK: - 2. Cómo se acumuló hoy (curva intradía acumulada)

    private var curveBlock: some View {
        InfoAccordion(
            title: "How today added up",
            explanation: "The line shows how your strain piled up through the day — each second of heart rate adds to the running total, so it only ever rises. It ends on today's score above.",
            accessibilityLabel: "Information about how today's strain added up",
            theme: theme
        ) {
            Group {
                if curve.count > 1 {
                    TrendChart(
                        points: curve,
                        gradient: chartGradient,
                        valueRange: 0...max((curve.map(\.value).max() ?? 1) * 1.15, 1),
                        showsArea: true,
                        height: 160,
                        showsScrub: true,
                        valueFormat: { fmt($0) },
                        dateFormat: { Self.hourString($0) },
                        axisLabelColor: theme.inkTertiary,
                        gridLineColor: theme.hairline
                    )
                    .accessibilityElement()
                    .accessibilityLabel(Text("Accumulated day strain, rising through the day."))
                } else if !curveLoaded {
                    loadingWell(height: 160)
                } else {
                    emptyWell(text: "Not enough activity yet today to chart.")
                }
            }
        }
    }

    // MARK: - 3. Zonas (las 4 bandas fijas, la activa marcada)

    private var zonesBlock: some View {
        // The bands (Rest/Light · Moderate · Hard · Extreme, with the active one flagged for today's
        // value) come straight from the shared `MetricInfo.strain` factory — same source of truth the
        // legacy sheet used — so the zones never disagree across screens.
        let bands = MetricInfo.strain(model.today).bands
        return InfoAccordion(
            title: "Zones",
            explanation: "Your heart rate falls into one of four intensity zones through the day. The highlighted row is where today's score lands on the 0–21 scale.",
            accessibilityLabel: "Information about the strain zones",
            theme: theme
        ) {
            VStack(spacing: 0) {
                ForEach(Array(bands.enumerated()), id: \.offset) { i, band in
                    zoneRow(band)
                    if i < bands.count - 1 {
                        Divider().overlay(theme.hairline).padding(.leading, 22)
                    }
                }
            }
        }
    }

    /// One zone row: a dot (active → the strain hue, else quiet ink) + label + its range, with a subtle
    /// active highlight. Token-only (no hex/spacing literals beyond the layout paddings the siblings use).
    private func zoneRow(_ band: MetricInfo.Band) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(band.isActive ? theme.dataStrain : theme.inkTertiary.opacity(0.45))
                .frame(width: 8, height: 8)
            Text(band.label)
                .font(StrandFont.subhead)
                .foregroundStyle(band.isActive ? theme.ink : theme.inkSecondary)
            Spacer(minLength: 8)
            Text(band.range)
                .font(StrandFont.captionNumber)
                .foregroundStyle(band.isActive ? theme.dataStrain : theme.inkTertiary)
        }
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity)
        .background(band.isActive ? theme.dataStrain.opacity(0.10) : Color.clear)
    }

    // MARK: - 4. Niveles (línea + niveles tocables + «N de tus últimos M días») — patrón F6c

    /// The F6c level instrument: a RAW-value line over the period you pick, the active level's band shaded,
    /// a «{level} · N de tus últimos M días» phrase and a TAPPABLE levels list (Rest / Light / Moderate /
    /// Hard / Extreme, 0–21). Reuses F6a (`MetricLevels.strain`) + the shared `MetricLevelsExplorer`. It
    /// supersedes both the static zones block and the old 7-day-average trend, which it folds into one. (FER-572)
    private var levelsBlock: some View {
        let window = MetricWindowMath.make(parsed, selected: range)
        return MetricLevelsExplorer(
            theme: theme,
            range: $range,
            window: window,
            levels: MetricLevels.levels(for: .strain),
            todayValue: model.today,
            hue: theme.dataStrain,
            unit: "",
            valueFormat: { String(Int($0.rounded())) },
            domain: 0...21,
            accessibilityLabel: "Day strain by level"
        )
    }

    // MARK: - 4.5 Qué mueve tu esfuerzo (correlación direccional, gated — FER-239)

    /// Documented, DIRECTIONAL drivers of strain (same-day recovery, the prior day's strain), computed from
    /// the user's OWN history in `StrandAnalytics` and degraded to a direction — never a coefficient, never
    /// a causal claim (hence the "tendencia, no causa" chip). Mirrors `MetricDetailScreen`'s block. When no
    /// relationship clears the gate it renders an honest empty state instead of vanishing (FER-246).
    private var whatMovesBlock: some View {
        // The ⓘ discloses the correlation method + the sufficiency gate (FER-220 pattern); the chip and the
        // directional sentences live inside the accordion's content.
        InfoAccordion(
            title: "What moves your strain",
            explanation: "We line up your day strain against your own recovery and the prior day's strain, day by day across your history, and read which way it leans (Pearson correlation). We only show a direction once there are enough paired days (about six weeks) and the link is strong enough to be unlikely to be chance — never the number, and never as a cause. (Plews 2013; Vesterinen 2016)",
            accessibilityLabel: "Information about what moves your strain",
            theme: theme
        ) {
            VStack(alignment: .leading, spacing: 10) {
                if model.drivers.isEmpty {
                    // Too few paired days yet, or none strong enough — honest, neutral empty state (FER-246).
                    Text("Not enough data yet — keep wearing your strap and check back in a few weeks.")
                        .font(StrandFont.caption)
                        .foregroundStyle(theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    InlineFlagChip("trend, not cause", color: theme.inkTertiary)
                    ForEach(model.drivers, id: \.driver) { finding in
                        Text(Self.driverPhrase(finding))
                            .font(StrandFont.caption)
                            .foregroundStyle(theme.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    /// The directional sentence for a driver. The direction comes from the user's data; no number is ever
    /// shown. Source strings are English; the es-MX values live in `Localizable.xcstrings`.
    private static func driverPhrase(_ f: StrainDriverFinding) -> LocalizedStringKey {
        switch (f.driver, f.trend) {
        case (.sameDayRecovery, .rises): return "Tends to run higher on days you start more recovered."
        case (.sameDayRecovery, .falls): return "Tends to run lower on days you start more recovered."
        case (.priorDayStrain, .rises):  return "Tends to run higher the day after a hard effort."
        case (.priorDayStrain, .falls):  return "Tends to ease off the day after a hard effort."
        }
    }

    // MARK: - Level 3 · «See your history» — trend + what moves your strain, collapsed by default
    //
    // The analyst's view, one tap down. An in-place disclosure (NOT a navigation push); the chevron and
    // copy mirror «See the method». Holds the period-selector trend and the directional drivers that used
    // to sit always-open in the daily scroll. Strain is the light cut, so this is its only fold and there
    // is no Level 2. (Detalles escalonados)

    @ViewBuilder private var historySection: some View {
        VStack(alignment: .leading, spacing: historyExpanded ? 22 : 0) {
            historyDisclosureHeader(caption: "What moves it")
            if historyExpanded {
                whatMovesBlock
            }
        }
    }

    /// The «See your history» row: a tappable header toggling the Level-3 disclosure in place. The
    /// chevron rotates with the house interactive spring. Shared shape across the four detail screens.
    private func historyDisclosureHeader(caption: LocalizedStringKey) -> some View {
        Button {
            withAnimation(StrandMotion.interactive) { historyExpanded.toggle() }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("See your history").instrumentoOverline().foregroundStyle(theme.ink)
                    Text(caption).font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.inkTertiary)
                    .rotationEffect(.degrees(historyExpanded ? 0 : -90))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(Text(historyExpanded ? "expanded" : "collapsed"))
    }

    // MARK: - Ver el método (DisclosureGroup, patrón de las otras pantallas)

    private var methodDisclosure: some View {
        DisclosureGroup(isExpanded: $methodExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                Divider().overlay(theme.hairline)
                Text("Each second of heart rate is mapped to one of five intensity zones; time in the higher zones counts for much more. The weighted total is compressed onto a 0–21 scale through a logarithmic curve, so the top of the scale represents a theoretical full day at peak intensity.")
                    .font(StrandFont.subhead)
                    .foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Heart-rate-zone load (TRIMP), compressed logarithmically. (Edwards 1993; Banister 1991)")
                    .font(StrandFont.caption)
                    .foregroundStyle(theme.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text("How it's calculated")
                .font(StrandFont.subhead)
                .foregroundStyle(theme.ink)
        }
        .tint(theme.inkTertiary)
        .padding(14)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Wells

    private func loadingWell(height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(theme.surface)
            .frame(height: height)
            .overlay { ProgressView().tint(theme.inkTertiary) }
    }

    private func emptyWell(text: LocalizedStringKey) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 22))
                .foregroundStyle(theme.inkTertiary)
            Text(text)
                .font(StrandFont.subhead)
                .foregroundStyle(theme.inkSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Colour + format

    private var chartGradient: Gradient { Gradient(colors: [theme.dataStrain.opacity(0.5), theme.dataStrain]) }

    /// Strain reads to one decimal (0–21), like the row and the hero.
    private func fmt(_ v: Double) -> String { String(format: "%.1f", v) }

    // MARK: - Chart axis

    /// Locale-aware hour label for the intraday curve's x-axis (12/24h per region).
    private static let hourFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("j")
        return f
    }()

    private static func hourString(_ date: Date) -> String { hourFormatter.string(from: date) }
}

// MARK: - Sheet item

/// Identifiable wrapper so the light «Instrumento» Detalle de Esfuerzo can ride `.sheet(item:)` (the
/// model itself isn't Identifiable). Opened from Cuerpo's «Day Strain» row. (FER-238)
struct StrainDetailItem: Identifiable {
    let id = UUID()
    let model: StrainDetailModel
}

// MARK: - Sheet paper background (iOS 16.4+ presentationBackground)

private struct StrainSheetPaperBackground: ViewModifier {
    let paper: Color
    func body(content: Content) -> some View {
        if #available(iOS 16.4, *) {
            content.presentationBackground(paper)
        } else {
            content
        }
    }
}

// MARK: - StrainDetailModel — every derivation the screen draws, built ONCE from the repo
//
// The data layer of the strain detail, lifted out of the view. `StrainDetailScreen` is pure presentation
// over this; the caller (Cuerpo) builds it with `StrainDetailModel.build(...)` from the in-memory
// dashboard so the screen stays DB-free. It CONSUMES `StrandAnalytics` as-is (no new math): today's score
// from `repo.today.strain`, the 14d+ series from `repo.days`. The intraday curve is NOT here — it reads HR
// samples (DB I/O) and is injected as an async `curveLoader` instead.

struct StrainDetailModel {
    /// Today's Day Strain (0–21), or nil while there's no score yet (strap-only, no Apple fallback).
    let today: Double?
    /// The full strain series (oldest → newest), `(day "yyyy-MM-dd", value)`, for the trend + stats.
    let series: [(day: String, value: Double)]
    /// Whether the repo finished its first load (drives loading vs empty hero copy).
    let loaded: Bool
    /// The gated, directional drivers of strain ("Qué mueve tu esfuerzo"), computed from the user's own
    /// history (FER-239). Empty when nothing clears the sufficiency gate → the block stays hidden.
    let drivers: [StrainDriverFinding]

    /// True when there's a score today or any stored strain history to draw (the rich path); false → empty.
    var hasData: Bool { today != nil || !series.isEmpty }

    /// Build the whole model from the repo's in-memory dashboard. Pure (no DB). `days` is the strap +
    /// on-device dashboard (`repo.days`, the baseline source — FER-149); `today` is `repo.today`. The
    /// drivers are computed here off the same `days` (which carry recovery) via `StrandAnalytics`, keeping
    /// the screen DB-free presentation over a ready-made model.
    static func build(days: [DailyMetric], today: DailyMetric?, loaded: Bool) -> StrainDetailModel {
        let series = days
            .compactMap { d in d.strain.map { (day: d.day, value: $0) } }
            .sorted { $0.day < $1.day }
        let recovery = days
            .compactMap { d in d.recovery.map { (day: d.day, value: $0) } }
            .sorted { $0.day < $1.day }
        let drivers = WhatMovesStrainEngine.drivers(strain: series, recovery: recovery)
        return StrainDetailModel(today: today?.strain, series: series, loaded: loaded, drivers: drivers)
    }
}

// MARK: - Preview

#if DEBUG
private func sampleStrainSeries(days: Int = 60) -> [(day: String, value: Double)] {
    let cal = Calendar(identifier: .gregorian)
    let today = cal.startOfDay(for: Date())
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "yyyy-MM-dd"
    return (0..<days).map { i in
        let date = cal.date(byAdding: .day, value: -(days - 1 - i), to: today)!
        let v = 11 + 5 * sin(Double(i) / 5.0) + Double((i * 7) % 5) - 2
        return (f.string(from: date), Swift.max(1, Swift.min(21, v)))
    }
}

private func sampleCurve() -> [TrendPoint] {
    let cal = Calendar(identifier: .gregorian)
    let midnight = cal.startOfDay(for: Date())
    var acc = 0.0
    return (0...16).map { h in
        acc += Double((h * 13) % 4) * 0.25 + 0.6
        return TrendPoint(date: midnight.addingTimeInterval(Double(h) * 3600), value: Swift.min(21, acc))
    }
}

#Preview("Strain detail — con datos") {
    Color.clear.sheet(isPresented: .constant(true)) {
        StrainDetailScreen(
            model: StrainDetailModel(today: 14.2, series: sampleStrainSeries(), loaded: true,
                                     drivers: [.init(driver: .sameDayRecovery, trend: .rises),
                                               .init(driver: .priorDayStrain, trend: .falls)]),
            curveLoader: { sampleCurve() })
    }
}

#Preview("Strain detail — sin datos") {
    Color.clear.sheet(isPresented: .constant(true)) {
        StrainDetailScreen(
            model: StrainDetailModel(today: nil, series: [], loaded: true, drivers: []),
            curveLoader: { [] })
    }
}
#endif
#endif
