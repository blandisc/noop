#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore
import Foundation

// MARK: - RecoveryDetailScreen — el «Detalle de Recuperación» en «Instrumento» (FER-225)
//
// Hermana de `MetricDetailScreen` (FER-185), igual que `SleepDetailScreen` (FER-212): REUSA su lenguaje
// visual (el scaffold `DetailBlock`, el hero, `InfoAccordion`, `theme: InstrumentoTheme` explícito,
// `sheetPaper`, `ScrollView`→`VStack`, `methodDisclosure`, los wells) pero con su propio modelo.
// NO extiende `MetricDetailScreen`/`MetricDetailSpec` (esos son para vitales de serie ESCALAR única —
// HRV/FC/Respiración); la recuperación es un SCORE COMPUESTO con bloques propios (desglose por driver,
// calendario, carga). Reemplaza, para recovery, la vieja `MetricInfoSheet` que abrían Cuerpo y Hoy.
//
// Se presenta vía `.sheet(item:)` con el tema vivo pasado EXPLÍCITO (no propaga por `.sheet`, FER-162) y
// SIN `NavigationStack` anidado (un stack anidado cruzando el path de la tab crasheaba SwiftUI, FER-171).
//
// Ocho bloques, cada uno con su ⓘ (`InfoAccordion`) salvo el método (DisclosureGroup): 1) Hero (score en
// color de banda) · 2) Qué lo explica (estado por driver vs tu base + peso) · 3) Tu rango normal · 4)
// Selector de periodo + Tendencia (+ Prom/Mediana/Mín/Máx/σ) · 5) Consistencia (CV) · 6) Calendario 90d
// (`YearHeatStrip` re-tintado, a todo el ancho) · 7) Carga reciente (ACWR/monotonía como CONTEXTO, sin
// claim de lesión — Impellizzeri 2020) · 8) Ver el método.
//
// Consume `StrandAnalytics` TAL CUAL: el score y la banda de `RecoveryScorer`, el estado por driver y la
// carga de `ReadinessEngine` (sus señales comparten la misma línea base que el scorer, así que recovery y
// readiness nunca cuentan dos historias distintas), la calibración de `RecoveryScorer.calibrationNights`,
// y las estadísticas de `ComparisonEngine`. No crea matemática nueva (el pronóstico es FER-188).

extension ReadinessEngine.Flag {
    /// The one flag → «Instrumento» color mapping, shared by every recovery surface (the Detalle's
    /// driver rows and the summary's «Qué la movió hoy», FER-628): good → verdict, neutral → quiet
    /// ink, watch → warning, bad → critical.
    func color(_ theme: InstrumentoTheme) -> Color {
        switch self {
        case .good:    return theme.verdict
        case .neutral: return theme.inkSecondary
        case .watch:   return theme.warning
        case .bad:     return theme.critical
        }
    }
}

/// Light «Instrumento» Detalle de Recuperación. Built once from a `RecoveryDetailModel` (the caller injects
/// the model so the screen stays DB-free), themed explicitly for the sheet boundary.
struct RecoveryDetailScreen: View {
    /// The live «Instrumento» theme, passed explicitly (sheets start a fresh environment). (FER-162)
    var theme: InstrumentoTheme = .base
    /// Everything the screen draws, derived ONCE by the caller from `repo` (no DB access here).
    let model: RecoveryDetailModel

    /// The trend block's period window (W/M/3M/6M/1Y/ALL). Defaults to a month.
    @State private var range: ExploreRange = .month
    /// The recovery series with each `day` string parsed to a `Date` exactly ONCE (not per slice / per
    /// render) — the window math reads `date` straight from here. Built in `.task`. (FER-216 lesson)
    @State private var parsed: [(day: String, date: Date?, value: Double)] = []
    /// Measured available width for the calendar, so the heat grid can size its cells to fill it. (FER-225)
    @State private var calWidth: CGFloat = 0
    @State private var methodExpanded = false
    /// «Media ⇄ Rangos» toggle for the levels block (handoff v2, FER-803): the moving-average line vs the
    /// population lanes. Starts on «Media» (the line).
    @State private var levelsMode: TrendMode = .media
    /// The calendar day the user tapped, for the read-out below the grid (touch — FER-235).
    @State private var selectedHeatDay: RecoveryDay? = nil
    /// Level-3 disclosure: the calendar + trend live under «See your history», collapsed on open. The only
    /// new state the re-sequencing adds; everything else is unchanged. (Detalles escalonados)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                hero
                if !model.loaded {
                    ChartWell(theme).loading(height: 160)
                } else if model.calibration != nil {
                    blockDivider
                    calibrationBlock
                    blockDivider
                    methodDisclosure
                    sourceFooter
                } else if model.hasData {
                    // Level 1 · the answer: what's pushing it, then what changed since yesterday.
                    if let impact = model.impact, !impact.signals.isEmpty {
                        blockDivider
                        levelAttributionBlock(impact)
                    } else if model.isEstimated {
                        // Apple-only day: the band-baseline points decomposition is nil (dishonest to fake).
                        // The coverage attribution stands in — direction per signal vs your own Apple norm,
                        // never a point magnitude, so the block is always present without overstating precision.
                        blockDivider
                        estimatedAttributionBlock
                    }
                    if let change = model.change {
                        blockDivider
                        changeSinceYesterdayBlock(change)
                    }
                    // Forward-looking, so it reads high — right after what drives today's score. Fuses the
                    // 1-day forecast with your normal range, steadiness and load into one 2×2 grid. (FER-831)
                    if hasPanorama {
                        blockDivider
                        panoramaBlock
                    }
                    // The screen's SINGLE recovery line: the level instrument (line + tappable levels +
                    // «N de tus últimos M días») over the FIXED recovery levels (Agotado / Bajo / Moderado /
                    // Alto / Pico, 0–100), with the period-average caption below it. FER-703 removed the
                    // separate 7-day-MA «Trend» chart — a second line of the same metric that read as
                    // redundant and made «average of what?» ambiguous; its «Media …» caption moved here. (FER-572 · FER-703)
                    if model.series.count >= 2 {
                        blockDivider
                        levelsBlock
                    }
                    // Level 3 · «See your history»: the 90-day calendar, collapsed by default. (FER-594; the
                    // period-selector trend that used to live here was removed in FER-703)
                    blockDivider
                    historySection
                    blockDivider
                    methodDisclosure
                    sourceFooter
                }
                // Empty (loaded, no calibration, no data): the hero's reading already says it.
            }
            .padding(NoopMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.paper)
        .presentationDragIndicator(.visible)
        .sheetPaper(theme)
        .task {
            range = .month
            parsed = model.series.map { ($0.day, Repository.parseDayKey($0.day), $0.value) }
        }
    }

    /// A subtle 1px rule between blocks (token-only). Mirrors MetricDetailScreen's `blockDivider`.
    private var blockDivider: some View {
        Rectangle().fill(theme.hairline).frame(height: 1)
    }

    // MARK: - 1. Hero — el score en color de banda (+ dirección fundida: mini-sparkline 14 d + flecha)

    private var hero: some View {
        // Serif in-screen title + ⓘ (the «Instrumento» detail identity, FER-581). Replaces the InfoAccordion
        // wrapper; the explanation stays behind the ⓘ exactly as before — only the title turns serif.
        return VStack(alignment: .leading, spacing: 10) {
            InstrumentoScreenTitle("Recovery", theme: theme, explanation: heroExplanation, glyph: .recovery)
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(model.score.map { "\($0)" } ?? "—")
                        .instrumentoHero(46)
                        .foregroundStyle(model.score == nil ? theme.inkTertiary : bandColor)
                    if model.score != nil {
                        Text("/ 100").font(StrandFont.unit).foregroundStyle(theme.inkTertiary)
                    }
                }
                // FER-153: a band-less Apple night reads «estimado · confianza X» right under the number, so
                // it never looks identical to a band recovery; the line below explains where it comes from.
                if model.isEstimated, model.score != nil { estimatedNote }
                // The reading is the answer, lifted above the «/100» — headline weight, ink. (FER-476 #7)
                Text(heroReading)
                    .font(StrandFont.headline)
                    .foregroundStyle(theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The hero ⓘ copy: the standard recovery explanation, plus — for an Apple estimate — the honest
    /// caveat that it comes from Apple's SDNN against your own Apple norm, a lower grade than the band. (FER-153)
    private var heroExplanation: LocalizedStringKey {
        // FER-545: el caveat del estimado vive ahora en `WhyVerdictSheet` (un solo hogar); aquí se referencia
        // para no duplicar el texto SDNN-vs-RMSSD.
        if model.isColdStartEstimate { return WhyVerdictSheet.estimatedCaveat(coldStart: true) }
        if model.isEstimated { return WhyVerdictSheet.estimatedCaveat(coldStart: false) }
        return "Recovery blends several signals from your nervous system — your HRV above all, plus resting heart rate, sleep and breathing — and compares them with your own baseline from recent weeks. It's an estimate of how ready your body is today, not a diagnosis. (Buchheit 2014)"
    }

    /// The «estimado · confianza X» marker + coverage («N de 3 señales») + one honest line, shown only for
    /// an Apple-Health estimate. Coverage says WHY the number is conservative (how many primary drivers
    /// backed it, FER-700); confidence says how settled the baseline is — two different honest facts. Token-only.
    private var estimatedNote: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: "applewatch")
                    .font(StrandFont.glyph(.chevron, weight: .semibold))
                    .accessibilityHidden(true)
                Text(Self.confidenceLabel(model.confidence))
                    .font(StrandFont.caption)
            }
            .foregroundStyle(theme.inkSecondary)
            if let coverage = Self.coverageLabel(model.presentPrimaryDrivers) {
                Text(coverage)
                    .font(StrandFont.caption)
                    .foregroundStyle(theme.inkSecondary)
            }
            Text("From your Apple Watch (HRV SDNN), a lower grade than your band.")
                .font(StrandFont.footnote)
                .foregroundStyle(theme.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    /// «Estimated · {alta|media|baja} confidence» as one localizable phrase per grade (English source;
    /// es/de in the String Catalog). Shared with the Hoy hero marker. (FER-153)
    static func confidenceLabel(_ c: ScoreConfidence?) -> LocalizedStringKey {
        switch c {
        case .solid:                return "Estimated · high confidence"
        case .building:             return "Estimated · medium confidence"
        case .calibrating, .none:   return "Estimated · low confidence"
        }
    }

    /// «Estimado — N de 3 señales»: how many of the 3 primary drivers (HRV, resting HR, sleep) backed an
    /// Apple estimate (FER-700), so the user sees WHY the number is conservative. English source; es/de in
    /// the String Catalog. Shared with the Hoy hero marker. nil when the day isn't an estimate (a band day
    /// with full coverage shows no count).
    static func coverageLabel(_ present: Int?) -> LocalizedStringKey? {
        guard let present else { return nil }
        return "Estimated — \(present) of \(AppleRecoveryEstimator.DayEstimate.totalPrimaryDrivers) signals"
    }

    private func heroDirectionSymbol(_ d: RecoveryForecast.Direction) -> String {
        switch d {
        case .rising:  return "arrow.up.right"
        case .steady:  return "arrow.right"
        case .falling: return "arrow.down.right"
        }
    }

    /// The score's band color: green ≥67 → verdict, yellow 34–67 → warning, red <34 → critical. The hero
    /// numeral is the datum, so it's the one element that carries saturated hue.
    private var bandColor: Color {
        guard let s = model.score else { return theme.inkTertiary }
        switch RecoveryScorer.band(Double(s)) {
        case "green":  return theme.verdict
        case "yellow": return theme.warning
        default:       return theme.critical
        }
    }

    private var heroReading: LocalizedStringKey {
        if let s = model.score {
            switch RecoveryScorer.band(Double(s)) {
            case "green":  return "Above your baseline — your body is ready for a strong day."
            case "yellow": return "Recovering — train, but keep it controlled."
            default:       return "Low — prioritize rest today."
            }
        }
        if model.calibration != nil { return "Calibrating — we need a few more nights of your strap." }
        // Offline / no reading today but history exists: be honest the day's number is missing without
        // implying a brand-new user (the trend and calendar below are populated). (FER-225, QA O1)
        if !model.series.isEmpty { return "No reading from last night yet — your recent history is below." }
        return "No recovery yet. Wear your strap overnight and open this again after it syncs — or import your WHOOP history in Data Sources."
    }

    // MARK: - 2. Hoy, vs tu normal — atribución unificada por nivel (FER-642)

    // ONE section, ONE model, ONE axis, identical to the recovery summary («Hoy, vs tu normal»): the same
    // `RecoveryImpact` decomposition of today's score, rendered as a plain-language headline naming the
    // day's dominant signal, then a row per present signal — overline label · position-vs-base word ·
    // `· N%` weight — with a divergent bar below whose length is the signal's CONTRIBUTION to the score
    // (right = holds it up, left = holds it back). No σ, no ⓘ; the jargon lives under «See the method».

    /// |contribution| below this reads as "barely moved it" in the headline — the same threshold the
    /// summary uses, so both surfaces pick the all-near-base fallback on the same days. (FER-628/FER-642)
    private static let impactBarely = 0.12

    /// Level-attribution block, shown only when `RecoveryImpact` is present (band-only; calibrating and
    /// Apple-only days hide it, keeping the `calibrationBlock` as the stand-in).
    private func levelAttributionBlock(_ impact: RecoveryImpact.Result) -> some View {
        DetailBlock("Today, vs your normal", theme: theme) {
            VStack(alignment: .leading, spacing: 16) {
                levelHeadline(impact)
                    .font(StrandFont.body)
                    .foregroundStyle(theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(impact.signals) { levelSignalRow($0) }
                }
                levelLegend
            }
        }
    }

    /// The plain-language headline naming the LARGEST-contribution signal: «Your HRV, above your base, is
    /// what holds your recovery up most today.» The metric name carries its flag hue; the rest is ink. Falls
    /// back to the all-near-base line. Mirrors the summary's `impactHeadline` word-for-word. (FER-642)
    private func levelHeadline(_ impact: RecoveryImpact.Result) -> Text {
        guard let top = impact.top, abs(top.contribution) >= Self.impactBarely else {
            return Text("All your signals sat near your base today.")
        }
        let flag = ReadinessEngine.Flag(orientedZ: top.orientedZ)
        let tail: LocalizedStringKey = top.contribution < 0
            ? ", is what holds your recovery back most today."
            : ", is what holds your recovery up most today."
        return Text("Your ")
            + Text(Self.driverLabel(top.key)).foregroundColor(flagColor(flag)).fontWeight(.semibold)
            + Text(Self.positionPhrase(top))
            + Text(tail)
    }

    /// One signal row: overline label · position-vs-base word (flag hue) · `· N%` weight, and the divergent
    /// contribution bar below. Identical layout to the summary's `impactRow`. (FER-642)
    private func levelSignalRow(_ s: RecoveryImpact.Signal) -> some View {
        let flag = ReadinessEngine.Flag(orientedZ: s.orientedZ)
        let color = flag == .neutral ? theme.inkSecondary : flagColor(flag)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Self.driverLabel(s.key)).instrumentoOverline().foregroundStyle(theme.inkTertiary)
                Spacer(minLength: 8)
                Text(Self.baseBandWord(s: s))
                    .font(StrandFont.captionNumber)
                    .foregroundStyle(color)
                Text(verbatim: "· \(Int((s.weight * 100).rounded()))%")
                    .font(StrandFont.captionNumber)
                    .foregroundStyle(theme.inkTertiary)
            }
            impactBar(contribution: s.contribution, color: color)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }

    /// The divergent «vs your base» bar: a center base tick, capsule extending right (holds recovery up) or
    /// left (holds it back), length ∝ |contribution| clamped at ~1.5 composite-z units. Family thickness
    /// (6px). Same construction and clamp as the summary's `impactBar`. (FER-642)
    private func impactBar(contribution: Double, color: Color) -> some View {
        GeometryReader { geo in
            let half = geo.size.width / 2
            let maxC: CGFloat = 1.5
            let mag = Swift.max(4, Swift.min(abs(CGFloat(contribution)) / maxC, 1.0) * half)
            // FER-836 «pista + zona base»: the capsule now rides a full-width track with a shaded
            // central «tu base» zone, so today's value reads against the WHOLE range, not floating
            // next to a lone tick. Colors stay token-only; the math is unchanged (position = sign of
            // the real oriented-z, length ∝ |contribution|) — no additive claim.
            let trackH: CGFloat = 12
            let baseZoneW = geo.size.width * 0.24
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(theme.trackWarm)
                    .frame(width: geo.size.width, height: trackH)
                RoundedRectangle(cornerRadius: 2, style: .continuous)  // token-exempt: geometría de dato
                    .fill(theme.hairline)
                    .frame(width: baseZoneW, height: trackH)
                    .offset(x: half - baseZoneW / 2)
                Capsule()
                    .fill(color)
                    .frame(width: mag, height: 6)
                    .offset(x: contribution >= 0 ? half : half - mag)
                Rectangle()
                    .fill(theme.hairlineStrong)
                    .frame(width: 1.5, height: 16)
                    .offset(x: half - 0.75)
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .frame(height: 16)
    }

    /// The unified axis legend: «◀ la frena · tu base · la sostiene ▶» — decorative, hidden from VoiceOver.
    private var levelLegend: some View {
        HStack {
            Text("◀ holds it back").font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
            Spacer()
            Text("your base").font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
            Spacer()
            Text("holds it up ▶").font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
        }
        .accessibilityHidden(true)
    }

    /// The flag → theme color (shared with the recovery summary's «Hoy, vs tu normal» rows, FER-628/FER-642).
    private func flagColor(_ flag: ReadinessEngine.Flag) -> Color { flag.color(theme) }

    /// The signal's display name — the same catalog keys the summary's rows use. (FER-642)
    private static func driverLabel(_ key: String) -> LocalizedStringKey {
        switch key {
        case "hrv":      return "HRV"
        case "rhr":      return "Resting HR"
        case "sleep":    return "Sleep"
        case "skinTemp": return "Skin temp"
        case "respRate": return "Respiration"
        default:         return LocalizedStringKey(key)
        }
    }

    /// The position-vs-base word for a signal, oriented BY SIGNAL: it uses the ORIENTED z, so a low resting
    /// HR / respiration / skin-temp reads «Below your base» while still being the helpful direction (the row
    /// color, from the oriented flag, carries the valence). |orientedZ| < 1 reads «In your base». (FER-642)
    private static func baseBandWord(s: RecoveryImpact.Signal) -> LocalizedStringKey {
        // `z` is the RAW physical deviation (+ = the metric itself is above your average); that's the
        // honest word for where the value sits, independent of whether higher or lower is better.
        if s.z >= 1 { return "Above your base" }
        if s.z <= -1 { return "Below your base" }
        return "In your base"
    }

    /// The headline's inline position clause, «, above your base, » etc., built from the RAW deviation with
    /// a «well» qualifier past 1σ. Matches the vocabulary of `baseBandWord`. (FER-642)
    private static func positionPhrase(_ s: RecoveryImpact.Signal) -> LocalizedStringKey {
        let above = s.z >= 0
        let strong = abs(s.z) >= 1.0
        return strong
            ? (above ? ", well above your base" : ", well below your base")
            : (above ? ", above your base"      : ", below your base")
    }

    // MARK: - 2-estimado. Hoy, vs tu normal (por cobertura) — el stand-in cuando el día es un estimado de Apple
    //
    // On an Apple-only day the band-baseline points decomposition (`RecoveryImpact`) is nil ON PURPOSE:
    // decomposing an SDNN estimate into precise per-signal points would overstate its precision. But the
    // estimator DOES know, honestly, where each present signal sat vs the user's OWN Apple norm — that's how
    // it built the score. So instead of hiding the section, we show COVERAGE: one row per primary driver —
    // present ones carry a direction (Apple-vs-own-Apple-norm) and its valence color; absent ones show,
    // attenuated, WHY they didn't back the number (the same story as «N de 3 señales»). No point magnitude.

    /// The three primary drivers, in fixed display order (HRV first — it's the required, dominant signal).
    private static let estimatedDriverOrder = ["hrv", "rhr", "sleep"]

    /// The estimated coverage-attribution block, shown in place of `levelAttributionBlock` on an Apple-only
    /// day. Always present (that's the point) — every primary driver gets a row, present or not.
    private var estimatedAttributionBlock: some View {
        let byKey = Dictionary(model.estimatedDirections.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        return DetailBlock("Today, vs your normal", theme: theme) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Where the signals Apple recorded sat vs your usual. Today's number is an estimate, so there's no point-by-point breakdown.")
                    .font(StrandFont.body)
                    .foregroundStyle(theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Self.estimatedDriverOrder, id: \.self) { key in
                        if let dir = byKey[key] {
                            estimatedSignalRow(dir)
                        } else {
                            estimatedAbsentRow(key)
                        }
                    }
                }
            }
        }
    }

    /// A present signal: overline label · position-vs-usual word (valence hue) · a direction arrow. Position
    /// is the RAW direction (arrow + word); the color reads `helps`, so a resting HR «Above your usual» reads
    /// amber even though it points up — matching the band block's word/valence split. No σ, no points.
    private func estimatedSignalRow(_ dir: AppleRecoveryEstimator.SignalDirection) -> some View {
        // Sleep has no personal Apple norm (its position is vs a fixed population center), so it shows as
        // PRESENCE-ONLY — «Recorded», no above/below — and the «vs your usual» claim is never overstated for
        // it. HRV / resting HR are measured against your own Apple baseline, so they carry a direction. (CSO)
        let color: Color = dir.position == .inRange ? theme.inkSecondary : (dir.helps ? theme.verdict : theme.warning)
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(Self.driverLabel(dir.key)).instrumentoOverline().foregroundStyle(theme.inkTertiary)
            Spacer(minLength: 8)
            if dir.hasPersonalNorm {
                Text(Self.estimatedPositionWord(dir.position))
                    .font(StrandFont.captionNumber)
                    .foregroundStyle(color)
                Image(systemName: Self.estimatedPositionSymbol(dir.position))
                    .font(StrandFont.footnote)
                    .foregroundStyle(color)
                    .accessibilityHidden(true)
            } else {
                Text("Recorded")
                    .font(StrandFont.captionNumber)
                    .foregroundStyle(theme.inkSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// An absent primary driver: the label + the honest reason it didn't back the estimate, attenuated. This
    /// is «N de 3 señales» told row-by-row, so the user sees WHY the number is conservative.
    private func estimatedAbsentRow(_ key: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(Self.driverLabel(key)).instrumentoOverline().foregroundStyle(theme.inkTertiary)
            Spacer(minLength: 8)
            Text(Self.estimatedAbsentReason(key))
                .font(StrandFont.captionNumber)
                .foregroundStyle(theme.inkTertiary)
        }
        .opacity(0.55)  // token-exempt: fila atenuada (señal estimada ausente)
        .accessibilityElement(children: .combine)
    }

    /// The position-vs-usual word for an estimated signal (raw physical direction; the row color carries
    /// whether that helps). English source; es/de in the String Catalog.
    private static func estimatedPositionWord(_ p: AppleRecoveryEstimator.SignalDirection.Position) -> LocalizedStringKey {
        switch p {
        case .above:   return "Above your usual"
        case .below:   return "Below your usual"
        case .inRange: return "Around your usual"
        }
    }

    private static func estimatedPositionSymbol(_ p: AppleRecoveryEstimator.SignalDirection.Position) -> String {
        switch p {
        case .above:   return "arrow.up.right"
        case .below:   return "arrow.down.right"
        case .inRange: return "arrow.right"
        }
    }

    /// Why a primary driver didn't back the estimate. HRV is required (never absent), so it falls to a
    /// generic line. English source; es/de in the String Catalog.
    private static func estimatedAbsentReason(_ key: String) -> LocalizedStringKey {
        switch key {
        case "rhr":   return "No resting HR last night"
        case "sleep": return "No sleep data last night"
        default:      return "Not recorded last night"
        }
    }

    // MARK: - 2b. Qué cambió vs ayer — el movimiento día-a-día (FER-642, motor RecoveryChange)

    /// The day-over-day block: a headline «Subiste N puntos / Bajaste N puntos / Igual que ayer» plus the
    /// 1–2 signals that moved most, each as «label · ayer → hoy · ▲/▼». Hidden when `change` is nil.
    private func changeSinceYesterdayBlock(_ change: RecoveryChange.Result) -> some View {
        DetailBlock("What changed since yesterday", theme: theme) {
            VStack(alignment: .leading, spacing: 14) {
                changeHeadline(change)
                    .font(StrandFont.body)
                    .foregroundStyle(theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if !change.movers.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(change.movers) { changeMoverRow($0) }
                    }
                }
            }
        }
    }

    /// The change headline, colored by direction: up → verdict, down → critical, flat → ink.
    private func changeHeadline(_ change: RecoveryChange.Result) -> Text {
        let n = abs(change.deltaScore)
        if change.deltaScore > 0 {
            return Text("You're up \(n) points.").foregroundColor(theme.verdict)
        } else if change.deltaScore < 0 {
            return Text("You're down \(n) points.").foregroundColor(theme.critical)
        }
        return Text("Same as yesterday.")
    }

    /// One mover: overline label · «ayer → hoy» with its unit · a ▲/▼ glyph colored by whether it moved the
    /// helpful way. VoiceOver reads the row combined. (FER-642)
    private func changeMoverRow(_ m: RecoveryChange.Change) -> some View {
        let color = m.improved ? theme.verdict : theme.critical
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(Self.driverLabel(m.key)).instrumentoOverline().foregroundStyle(theme.inkTertiary)
            Spacer(minLength: 8)
            Text(verbatim: "\(Self.moverValue(m.yesterday, m.unit)) → \(Self.moverValue(m.today, m.unit))")
                .font(StrandFont.captionNumber)
                .foregroundStyle(theme.inkSecondary)
            Text(verbatim: m.improved ? "▲" : "▼")
                .font(StrandFont.footnote)
                .foregroundStyle(color)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }

    /// Format a signal's displayed value with its unit («61 ms», «52 bpm», «91 %», «14 br», «+0.3 °C»). The
    /// sleep signal shows EFFICIENCY %, the quantity the score reads — not duration. (FER-642)
    private static func moverValue(_ v: Double, _ unit: RecoveryChange.Unit) -> String {
        switch unit {
        case .millis:  return "\(Int(v.rounded())) ms"
        case .bpm:     return "\(Int(v.rounded())) bpm"
        case .breaths: return "\(Int(v.rounded())) br"
        case .percent: return "\(Int(v.rounded())) %"
        case .celsius: return String(format: "%+.1f °C", v)
        }
    }

    // MARK: - 2.5 Panorama — pronóstico + rango normal + estabilidad + carga, en un grid 2×2 (handoff v2, FER-831)
    //
    // Fuses the former «Tomorrow, if you rest the same» (forecast) and «Your patterns» (normal range +
    // steadiness + load) blocks into one 2×2 «Panorama» grid, per the Tendencias v2 handoff. No new math:
    // the forecast is `RecoveryForecast` (presentation-only), the range is `ComparisonEngine.stat` ± σ,
    // steadiness is the CV word, the load cell is `model.load.bandLabel`. The σ/CV/ACWR jargon that lived in
    // the «Your patterns» ⓘ is dropped from the face; «See the method» remains its home.

    /// Whether there's anything to show in the Panorama (otherwise the whole block is skipped).
    private var hasPanorama: Bool {
        model.forecast != nil || normalRange != nil || consistency != nil || model.load != nil
    }

    private var panoramaBlock: some View {
        DetailBlock("Panorama", theme: theme) {
            VStack(alignment: .leading, spacing: 16) {
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .topLeading),
                                    GridItem(.flexible(), alignment: .topLeading)],
                          alignment: .leading, spacing: 14) {
                    panoramaTomorrowCell
                    panoramaCell(label: "Usually",
                                 value: normalRange.map { "\($0.lo)–\($0.hi)" } ?? "—")
                    panoramaCell(label: "Steadiness",
                                 value: consistency.map { consistencyWord($0) } ?? "—")
                    panoramaCell(label: "Load",
                                 value: model.load?.bandLabel ?? "—",
                                 valueColor: model.load.map { flagColor($0.bandFlag) })
                }
                Text("A forecast is a projection, not a guarantee.")
                    .font(StrandFont.caption)
                    .foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The «Tomorrow» cell: a trend arrow + word + the center of your normal range («Rising · ~73»); it
    /// reads «Calibrating» when there isn't enough base to project. The `RecoveryForecast` engine is
    /// untouched — this is presentation-only. (FER-831)
    private var panoramaTomorrowCell: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Tomorrow").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            if let f = model.forecast {
                HStack(spacing: 4) {
                    Image(systemName: heroDirectionSymbol(f.direction))
                        .font(StrandFont.glyph(.chevron, weight: .semibold))
                        .foregroundStyle(theme.dataRecovery)
                        .accessibilityHidden(true)
                    Text(panoramaForecastValue(f)).font(StrandFont.bodyNumber).foregroundStyle(theme.ink)
                }
            } else {
                Text("Calibrating").font(StrandFont.bodyNumber).foregroundStyle(theme.inkTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// «{Rising|Steady|Falling} · ~N» — the trend word plus the center of the normal range (the «· ~N»
    /// clause is dropped when there's no range yet).
    private func panoramaForecastValue(_ f: RecoveryForecast.Result) -> String {
        let word: String
        switch f.direction {
        case .rising:  word = String(localized: "Rising")
        case .steady:  word = String(localized: "Steady")
        case .falling: word = String(localized: "Falling")
        }
        guard let r = normalRange else { return word }
        let mid = Int(((Double(r.lo) + Double(r.hi)) / 2).rounded())
        return "\(word) · ~\(mid)"
    }

    /// One Panorama cell: a quiet overline label above a plain-language value (the datum — coloured when a
    /// hue is given). Token-only.
    private func panoramaCell(label: LocalizedStringKey, value: String, valueColor: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).instrumentoOverline().foregroundStyle(theme.inkTertiary)
            Text(value).font(StrandFont.bodyNumber).foregroundStyle(valueColor ?? theme.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// The normal-range pair (lo, hi, n) over the last 30 days, or nil when there aren't enough days.
    private var normalRange: (lo: Int, hi: Int, n: Int)? {
        let vals = Array(model.series.suffix(30)).map(\.value)
        let s = ComparisonEngine.stat(vals)
        guard s.n >= 2 else { return nil }
        return (Int(Swift.max(0, s.mean - s.stdev).rounded()),
                Int(Swift.min(100, s.mean + s.stdev).rounded()),
                s.n)
    }

    /// A plain word for steadiness from the CV percent (the number itself stays in «See the method»).
    private func consistencyWord(_ pct: Int) -> String {
        switch pct {
        case ..<8:   return String(localized: "Very steady")
        case 8..<15: return String(localized: "Steady")
        default:     return String(localized: "Variable")
        }
    }

    // MARK: - 4. Recuperación por nivel (línea + niveles tocables + «N de tus últimos M días» + «Media …»)
    //
    // FER-703 collapsed the two recovery line charts into one. The separate 7-day-MA «Trend» block was
    // removed (redundant second line of the same metric, and its moving average clashed with this block's
    // period-average caption — «average of what?»). This is now the ONLY recovery line; it carries the
    // period-average caption («Media …») that used to sit with the trend. (FER-572 · FER-594 · FER-703)

    /// The level instrument: a recovery line over the period you pick, the active level's band shaded, a
    /// «{level} · N de tus últimos M días» phrase and a TAPPABLE levels list (Agotado / Bajo / Moderado /
    /// Alto / Pico, 0–100), with the period-average caption below it. Reuses `MetricLevels.recovery` + the
    /// shared `MetricLevelsExplorer`; its W/M/3M/6M/1Y/ALL selector is the screen's single period selector.
    private var levelsBlock: some View {
        let window = MetricWindowMath.make(parsed, selected: range)
        return VStack(alignment: .leading, spacing: 14) {
            MetricLevelsExplorer(
                theme: theme,
                range: $range,
                window: window,
                levels: MetricLevels.levels(for: .recovery),
                todayValue: model.score.map(Double.init),
                hue: theme.dataRecovery,
                unit: "",
                valueFormat: { "\(Int($0.rounded()))" },
                domain: 0...100,
                mode: $levelsMode,
                accessibilityLabel: "Recovery by level"
            )
            averageCaption
        }
    }

    /// The handoff's period-average caption + range, now under the level instrument (moved from the removed
    /// trend block, FER-703). Recovery rises = good; the score is unitless (/100). Δ vs the previous equal
    /// window. It's the screen's ONE «promedio», so no other block presents an average. (FER-587, option ii)
    @ViewBuilder private var averageCaption: some View {
        let window = MetricWindowMath.make(parsed, selected: range)
        if window.values.count > 1 {
            let s = ComparisonEngine.stat(window.values)
            DynamicAverageCaption(
                windowName: range.name,
                average: "\(Int(s.mean.rounded()))",
                pctChange: range.periodComparison(of: model.series)?.pctChange,
                polarity: .higherIsBetter,
                rangeText: "\(Int(s.min.rounded()))–\(Int(s.max.rounded()))",
                theme: theme)
        }
    }

    // MARK: - 5. Consistencia (coeficiente de variación)

    /// CV of the full recovery series (nil when there aren't enough points). Feeds the «Your patterns»
    /// steadiness line; the standalone «Consistency» block folded into it (Detalles escalonados).
    private var consistency: Int? {
        SeriesShape.coefficientOfVariation(model.series.map(\.value), window: 7).map { Int(($0 * 100).rounded()) }
    }

    // MARK: - Level 3 · «See your history» — the 90-day calendar, collapsed by default
    //
    // The analyst's view, one tap down. An in-place disclosure (NOT a navigation push); the chevron and
    // copy mirror «See the method». Holds the 90-day calendar. (The period-selector trend that used to sit
    // here alongside it was removed in FER-703.)

    // Handoff v2 (reconciliación): el calendario 90d va VISIBLE, no colapsado bajo «Ver tu historial».
    @ViewBuilder private var historySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            calendarBlock
        }
    }

    /// The «See your history» row: a tappable header that toggles the Level-3 disclosure in place. The
    // MARK: - Calendario · 90 días (YearHeatStrip re-tintado, a todo el ancho) — en «See your history»

    private var calendarBlock: some View {
        DetailBlock("Calendar · 90 days", theme: theme) {
            VStack(alignment: .leading, spacing: 10) {
                heatGrid
                heatReadout
            }
        }
    }

    /// The read-out under the calendar: the tapped day's date + score (in its band color) + state word,
    /// or an honest "no reading" for an in-range gap; a quiet hint until the user taps a day. (FER-235)
    @ViewBuilder private var heatReadout: some View {
        if let day = selectedHeatDay {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Self.heatDateFmt.string(from: day.date))
                    .instrumentoOverline()
                    .foregroundStyle(theme.inkTertiary)
                Spacer(minLength: 8)
                if let score = day.score {
                    Text("\(Int(score.rounded()))")
                        .font(StrandFont.number(20))
                        .foregroundStyle(heatTint(score))
                    Text(bandWord(score))
                        .font(StrandFont.subhead)
                        .foregroundStyle(theme.inkSecondary)
                } else {
                    Text("—")
                        .font(StrandFont.number(20))
                        .foregroundStyle(theme.inkTertiary)
                    Text("no reading")
                        .font(StrandFont.subhead)
                        .foregroundStyle(theme.inkTertiary)
                }
            }
            .accessibilityElement(children: .combine)
        } else {
            Text("Tap a day to see its recovery.")
                .font(StrandFont.caption)
                .foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// A short band word for the calendar read-out (matches the hero's band coloring).
    private func bandWord(_ score: Double) -> LocalizedStringKey {
        switch RecoveryScorer.band(score) {
        case "green":  return "Ready"
        case "yellow": return "Recovering"
        default:       return "Low"
        }
    }

    /// The 90-day heat strip, sized to fill the available width: measure the content width once, then
    /// pick a cell size so the week columns span it (re-tinted to warm paper). (FER-225)
    private var heatGrid: some View {
        let cols = Swift.max(1, YearHeatStrip.weekColumns(for: model.heat))
        let spacing: CGFloat = 4
        let gutter: CGFloat = 24
        let cell: CGFloat = calWidth > 0
            ? Swift.max(8, Swift.min(22, (calWidth - gutter - spacing - CGFloat(cols - 1) * spacing) / CGFloat(cols)))
            : 14
        return YearHeatStrip(
            days: model.heat,
            cellSize: cell,
            spacing: spacing,
            showsScrub: false,
            tint: heatTint,
            emptyFill: theme.hairline,
            emptyStroke: theme.hairlineStrong,
            labelColor: theme.inkTertiary,
            onSelect: { selectedHeatDay = $0 },
            selectionColor: theme.ink
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GeometryReader { g in
            Color.clear.preference(key: CalWidthKey.self, value: g.size.width)
        })
        .onPreferenceChange(CalWidthKey.self) { calWidth = $0 }
    }

    /// The cell tint in «Instrumento» colors: the same three band roles the hero uses (green/amber/red),
    /// so the calendar and the hero never disagree, and only theme tokens carry color. (FER-225)
    private func heatTint(_ score: Double) -> Color {
        switch RecoveryScorer.band(score) {
        case "green":  return theme.verdict
        case "yellow": return theme.warning
        default:       return theme.critical
        }
    }

    // MARK: - Ver el método (DisclosureGroup, patrón de las otras pantallas)

    private var methodDisclosure: some View {
        DisclosureGroup(isExpanded: $methodExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                Divider().overlay(theme.hairline)
                Text("Each signal becomes a score of how far above or below your personal average it sits (a z-score, in σ). They're combined with the weights shown and mapped onto a 0–100 scale through a logistic curve, calibrated so a typical day lands near 58. It's an estimate, not a diagnosis.")
                    .font(StrandFont.subhead)
                    .foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("The «vs your base» bars show each signal's deviation in σ (above your base = right). HRV, resting heart rate and respiration are z-scored that way; sleep and skin temperature carry no σ, so they show their state, not a position. Your normal range is your recent average ± one σ. Steadiness is the coefficient of variation (CV). Training load is the acute:chronic workload ratio (ACWR) — context for recovery, never an injury claim.")
                    .font(StrandFont.subhead)
                    .foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("A composite of z-scores through a logistic curve. HRV via RMSSD (Task Force, 1996; Plews 2013; Buchheit 2014; Impellizzeri 2020).")
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
        .background(theme.surface, in: RoundedRectangle(cornerRadius: NoopMetrics.controlRadius, style: .continuous))
    }

    // MARK: - Calibrando (no hay score todavía)

    private var calibrationBlock: some View {
        let n = model.calibration ?? 0
        let needed = model.nightsNeeded
        return VStack(alignment: .leading, spacing: 12) {
            Text("Not enough history yet")
                .font(StrandFont.headline)
                .foregroundStyle(theme.ink)
            HStack(alignment: .firstTextBaseline) {
                Text("Calibrating").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                Spacer()
                Text("\(n) / \(needed) nights")
                    .font(StrandFont.captionNumber)
                    .foregroundStyle(theme.inkSecondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(theme.hairline).frame(height: 6)
                    Capsule().fill(theme.dataRecovery)
                        .frame(width: max(6, geo.size.width * CGFloat(n) / CGFloat(max(needed, 1))), height: 6)
                }
            }
            .frame(height: 6)
            Text("We need a few more nights with your strap to learn your baseline before we score your recovery. We'd rather not show a made-up number.")
                .font(StrandFont.caption)
                .foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: NoopMetrics.controlRadius, style: .continuous))
    }

    // MARK: - Source footer

    private var sourceFooter: some View {
        // Recovery is a score computed on-device from your signals → «Calculado». (FER-803)
        OriginStamp(origin: .computed, when: String(localized: "today"), theme: theme)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 2)
    }

    /// The canonical UTC day-key formatter — read side of the day-key contract (FER-754).
    static let dayParser = DayKey.utcFormatter

    /// Locale-aware "Wed 14 May" for the calendar read-out (orders/abbreviates per device locale). (FER-235)
    static let heatDateFmt: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEEdMMM")
        return f
    }()
}

// MARK: - Width preference (size the calendar to fill the content width)

private struct CalWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

// MARK: - Sheet item

/// Identifiable wrapper so the light «Instrumento» Detalle de Recuperación can ride `.sheet(item:)` (the
/// model itself isn't Identifiable). Shared by Cuerpo (the hero) and Hoy (the verdict numeral). (FER-225)
struct RecoveryDetailItem: Identifiable {
    let id = UUID()
    let model: RecoveryDetailModel
}

// MARK: - RecoveryDetailModel — every derivation the screen draws, built ONCE from the repo
//
// The data layer of the recovery detail, lifted out of the view. `RecoveryDetailScreen` is pure
// presentation over this; the caller (Cuerpo / Hoy) builds it with `RecoveryDetailModel.build(...)` from
// the in-memory dashboard so the screen stays DB-free. It CONSUMES `StrandAnalytics` as-is: the score from
// `repo.today.recovery`, the band from `RecoveryScorer`, the per-driver state and load from `ReadinessEngine`
// (whose signals share the recovery scorer's baseline, so they never disagree), the calibration progress
// from `RecoveryScorer.calibrationNights`. No new math (the forecast is FER-188).

struct RecoveryDetailModel {

    /// Recent training load, as honest context (never an injury claim — Impellizzeri 2020).
    struct LoadState: Equatable {
        let acwr: Double
        let monotony: Double?
        /// The load-band's short label (localized) + the flag that colors it.
        let bandLabel: String
        let bandFlag: ReadinessEngine.Flag
    }

    /// Today's recovery score (0–100, rounded), or nil while calibrating / offline with no reading.
    let score: Int?
    /// Cold-start progress: nights banked toward the seed gate (1..<seed) while recovery is unscored; nil
    /// once recovery exists or there's no night data yet. Drives the calibrating state.
    let calibration: Int?
    /// The seed gate (`Baselines.minNightsSeed`), for the "N / seed nights" copy.
    let nightsNeeded: Int
    /// FER-642 · «Hoy, vs tu normal»: today's per-signal contributions to the score (the SAME
    /// `RecoveryImpact` the summary draws), band-only. nil while calibrating / on an Apple-only day —
    /// then the block is hidden (the `calibrationBlock` stands in).
    let impact: RecoveryImpact.Result?
    /// FER-642 · «Qué cambió vs ayer»: the day-over-day change + its top movers. nil with no band
    /// yesterday — then that block is hidden.
    let change: RecoveryChange.Result?
    /// The full recovery series (oldest → newest), `(day "yyyy-MM-dd", value)`, for trend / normal range / CV.
    let series: [(day: String, value: Double)]
    /// The trailing 90 calendar days as `RecoveryDay` (score nil for days with no reading) for the heat grid.
    let heat: [RecoveryDay]
    /// Recent load context (nil when there isn't enough strain history for an ACWR).
    let load: LoadState?
    /// Whether the repo finished its first load (drives the loading vs empty hero copy).
    let loaded: Bool
    /// Whether today's reading is Apple-sourced (for the source footer).
    let isAppleHealth: Bool
    /// Tomorrow's one-day recovery projection (estimate + range + direction), or nil while there isn't
    /// enough base (< ~2 weeks of valid days) — then the block shows its "still calibrating" state. (FER-277)
    let forecast: RecoveryForecast.Result?
    /// FER-153: true when today's surfaced recovery is an Apple-Health ESTIMATE (a band-less night scored
    /// from SDNN vs the user's own Apple norm) — the hero labels it «estimado» + grade so it never reads
    /// identical to a band recovery.
    let isEstimated: Bool
    /// The estimate's confidence grade (nil unless `isEstimated`).
    let confidence: ScoreConfidence?
    /// FER-700: how many of the 3 primary drivers (HRV, resting HR, sleep) backed the estimate — the
    /// coverage the FER-698 shrinkage keys on. nil unless `isEstimated`. Surfaced as «N de 3 señales»
    /// so the user sees WHY the number is conservative, not just a shrunk score.
    let presentPrimaryDrivers: Int?
    /// The present primary drivers' directions vs the user's own Apple norm (HRV first) for an estimate —
    /// powers the coverage-attribution block that stands in for `impact` on an Apple-only day. Empty unless
    /// `isEstimated`. Deliberately position-only (no point magnitude): decomposing an SDNN estimate into the
    /// band path's precise per-signal points would overstate its precision (why `RecoveryImpact` returns nil).
    let estimatedDirections: [AppleRecoveryEstimator.SignalDirection]

    /// True when there's a score or any stored recovery history to draw (the rich path); false → empty.
    var hasData: Bool { score != nil || !series.isEmpty }

    /// FER-529: an estimate shown WHILE THE BAND IS WORN but its RMSSD baseline isn't seeded yet
    /// (cold-start), vs a band-less Apple night (`isAppleHealth`). Drives reason-aware copy — «while your
    /// band is still calibrating» instead of «on a night your band didn't record».
    var isColdStartEstimate: Bool { isEstimated && !isAppleHealth }

    // MARK: - Build

    /// Convenience: build the whole model straight from the repo. Hoy and Cuerpo both open the recovery
    /// detail the same way, so they share this instead of each assembling the argument list (incl. the
    /// FER-153 estimate flags). (`@MainActor` to read the repo's published state on the main actor.)
    @MainActor
    static func build(repo: Repository) -> RecoveryDetailModel {
        let key = Repository.localDayKey(Date())
        return build(days: repo.days, today: repo.today, todayKey: key,
                     appleHealthDays: repo.appleHealthDays, loaded: repo.loaded,
                     importedSleep: repo.importedSleep,
                     isEstimated: repo.isRecoveryEstimated(key),
                     confidence: repo.recoveryConfidence(key),
                     presentPrimaryDrivers: repo.recoveryPrimaryDrivers(key),
                     estimatedDirections: repo.recoveryEstimateDirections(key))
    }

    /// Build the whole model from the repo's in-memory dashboard. Pure (no DB). `days` is the strap +
    /// on-device dashboard (`repo.days`, the baseline source — FER-149); `today` is `repo.today`; `todayKey`
    /// is the device's local day key.
    static func build(days: [DailyMetric],
                      today: DailyMetric?,
                      todayKey: String,
                      appleHealthDays: Set<String>,
                      loaded: Bool,
                      importedSleep: [String: ImportedSleepFigures] = [:],
                      isEstimated: Bool = false,
                      confidence: ScoreConfidence? = nil,
                      presentPrimaryDrivers: Int? = nil,
                      estimatedDirections: [AppleRecoveryEstimator.SignalDirection] = []) -> RecoveryDetailModel {
        let hasRecovery = today?.recovery != nil
        let score = today?.recovery.map { Int($0.rounded()) }
        let calibration = RecoveryScorer.calibrationNights(
            nightlyHrv: days.map(\.avgHrv), hasRecovery: hasRecovery)

        // Sort once; both the UI series (nils dropped) and the forecast input (nils kept for spacing) read it.
        let sortedDays = days.sorted { $0.day < $1.day }
        let series = sortedDays.compactMap { d in d.recovery.map { (day: d.day, value: $0) } }

        // FER-632: score the detail's σ against the BAND-only baseline — the same history the recovery
        // SCORE uses (`IntelligenceEngine.strapOnlyHistory`). Raw `days` measured HRV/RHR/resp against a
        // baseline contaminated with Apple SDNN/offsets, so the σ the user saw (e.g. HRV −0.72σ, RHR
        // «normal») diverged from the score's own (−3.56σ, +3.05σ). `maskForBaseline` (FER-631) is the
        // column-level equivalent of the scorer's row drop — pinned to the same z by test. On an Apple-only
        // day today's own row is masked too (the band didn't measure it; the estimate carries its own
        // caveat), so no band σ is invented for a reading the band never took.
        let bandDays = SourceLens.maskForBaseline(days, keep: .band, appleDays: appleHealthDays)
        let readiness = ReadinessEngine.evaluate(days: bandDays, today: todayKey)
        let load: LoadState? = readiness.acwr.map { acwr in
            LoadState(acwr: acwr,
                      monotony: readiness.monotony,
                      bandLabel: readiness.loadBand?.shortLabel ?? "",
                      bandFlag: readiness.loadBand?.flag ?? .neutral)
        }

        let heat = buildHeat(days: days, todayKey: todayKey)

        // Tomorrow's projection: the recovery series (oldest → newest, nils kept so the engine respects
        // missing-day spacing) plus any imported WHOOP sleep debt for today. The engine filters/gates and
        // returns nil below ~2 weeks of base; we never recompute its math here. (FER-277, FER-188)
        let forecast = RecoveryForecast.compute(
            recovery: sortedDays.map(\.recovery),
            sleepDebtMin: importedSleep[todayKey]?.debtMin)

        // FER-642 · unified level attribution: the SAME `RecoveryImpact` the summary draws, computed
        // band-only (Apple-only rows dropped whole-row) so the Detalle and the summary tell one story.
        let impact = RecoveryImpact.compute(days: days, todayKey: todayKey, appleDays: appleHealthDays)

        // FER-642 · «Qué cambió vs ayer»: the day-over-day change vs the previous CALENDAR day (D2 — «ayer»
        // means literally yesterday, not the last band night). Resolved from the same band-only slice, the
        // app's OWN displayed scores (`.recovery`), and the change in each signal's contribution. nil (block
        // hidden) when there's no band row / score for yesterday. Keys are date-only; ±1 day arithmetic runs
        // in a single UTC calendar so it never crosses a zone boundary.
        let change: RecoveryChange.Result? = {
            let byDay = Dictionary(days.map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
            guard let todayDate = RecoveryDetailScreen.dayParser.date(from: todayKey),
                  var cal = Optional(Calendar(identifier: .gregorian)) else { return nil }
            cal.timeZone = TimeZone(identifier: "UTC")!
            guard let yDate = cal.date(byAdding: .day, value: -1, to: todayDate) else { return nil }
            let yesterdayKey = RecoveryDetailScreen.dayParser.string(from: yDate)
            guard let todayRow = byDay[todayKey], !appleHealthDays.contains(todayKey),
                  let yestRow = byDay[yesterdayKey], !appleHealthDays.contains(yesterdayKey)
            else { return nil }
            return RecoveryChange.compute(
                today: todayRow, yesterday: yestRow,
                todayScore: todayRow.recovery.map { Int($0.rounded()) },
                yesterdayScore: yestRow.recovery.map { Int($0.rounded()) },
                todayImpact: impact,
                yesterdayImpact: RecoveryImpact.compute(days: days, todayKey: yesterdayKey,
                                                        appleDays: appleHealthDays))
        }()

        return RecoveryDetailModel(
            score: score,
            calibration: calibration,
            nightsNeeded: Baselines.minNightsSeed,
            impact: impact,
            change: change,
            series: series,
            heat: heat,
            load: load,
            loaded: loaded,
            isAppleHealth: appleHealthDays.contains(todayKey),
            forecast: forecast,
            isEstimated: isEstimated,
            confidence: confidence,
            presentPrimaryDrivers: presentPrimaryDrivers,
            estimatedDirections: estimatedDirections)
    }

    /// The trailing 90 calendar days as `RecoveryDay`, one per day (score nil where there's no reading), so
    /// the heat grid is contiguous and `YearHeatStrip.weekColumns` is deterministic. Dates are stamped at
    /// noon UTC so the weekday never crosses a day boundary across time zones.
    static func buildHeat(days: [DailyMetric], todayKey: String) -> [RecoveryDay] {
        var rec: [String: Double] = [:]
        for d in days { if let r = d.recovery { rec[d.day] = r } }
        guard let today = Repository.parseDayKey(todayKey) else { return [] }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        var out: [RecoveryDay] = []
        out.reserveCapacity(90)
        for offset in stride(from: 89, through: 0, by: -1) {
            guard let date = cal.date(byAdding: .day, value: -offset, to: today) else { continue }
            let key = RecoveryDetailScreen.dayParser.string(from: date)
            out.append(RecoveryDay(date: date.addingTimeInterval(12 * 3600), score: rec[key]))
        }
        return out
    }
}

// MARK: - Preview

#if DEBUG
private func sampleRecoverySeries(days: Int = 120) -> [(day: String, value: Double)] {
    let cal = Calendar(identifier: .gregorian)
    let today = cal.startOfDay(for: Date())
    let f = RecoveryDetailScreen.dayParser
    return (0..<days).map { i in
        let date = cal.date(byAdding: .day, value: -(days - 1 - i), to: today)!
        let v = 62 + 24 * sin(Double(i) / 9.0) + Double((i * 17) % 13) - 6
        return (f.string(from: date), Swift.max(8, Swift.min(98, v)))
    }
}

private func sampleModel(score: Int?, calibration: Int?,
                         isEstimated: Bool = false, confidence: ScoreConfidence? = nil,
                         presentPrimaryDrivers: Int? = nil,
                         estimatedDirections: [AppleRecoveryEstimator.SignalDirection] = []) -> RecoveryDetailModel {
    let series = score == nil && calibration != nil ? [] : sampleRecoverySeries()
    let cal = Calendar(identifier: .gregorian)
    let today = cal.startOfDay(for: Date())
    let heat: [RecoveryDay] = (0..<90).reversed().map { off in
        let date = cal.date(byAdding: .day, value: -off, to: today)!
        let v = 60 + 26 * sin(Double(off) / 8.0) + Double((off * 13) % 17) - 8
        return RecoveryDay(date: date, score: (off % 16 == 0) ? nil : Swift.max(8, Swift.min(98, v)))
    }
    // An Apple estimate has no band-baseline decomposition (mirrors reality: `RecoveryImpact` returns nil),
    // so the estimated coverage block stands in for the points block.
    let impact: RecoveryImpact.Result? = (isEstimated || (score == nil && calibration != nil)) ? nil
        : RecoveryImpact.Result(signals: [
            .init(key: "hrv",      z: 1.4,  orientedZ: 1.4,  weight: 0.60 / 1.10),
            .init(key: "rhr",      z: -0.6, orientedZ: 0.6,  weight: 0.20 / 1.10),
            .init(key: "sleep",    z: 0.4,  orientedZ: 0.4,  weight: 0.15 / 1.10),
            .init(key: "skinTemp", z: 0.1,  orientedZ: -0.1, weight: 0.10 / 1.10),
            .init(key: "respRate", z: 0.3,  orientedZ: -0.3, weight: 0.05 / 1.10),
        ])
    let change: RecoveryChange.Result? = (score == nil && calibration != nil) ? nil
        : RecoveryChange.Result(deltaScore: 9, movers: [
            .init(key: "hrv",   unit: .millis,  yesterday: 48, today: 61, deltaContribution: 0.42),
            .init(key: "sleep", unit: .percent, yesterday: 84, today: 91, deltaContribution: 0.10),
        ])
    return RecoveryDetailModel(
        score: score,
        calibration: calibration,
        nightsNeeded: 4,
        impact: impact,
        change: change,
        series: series,
        heat: calibration != nil ? [] : heat,
        load: calibration != nil ? nil : .init(acwr: 1.05, monotony: 1.4, bandLabel: "In balance", bandFlag: .good),
        loaded: true,
        isAppleHealth: isEstimated,
        forecast: RecoveryForecast.compute(recovery: series.map { $0.value }),
        isEstimated: isEstimated,
        confidence: confidence,
        presentPrimaryDrivers: presentPrimaryDrivers,
        estimatedDirections: estimatedDirections)
}

#Preview("Recovery detail — con datos") {
    Color.clear.sheet(isPresented: .constant(true)) {
        RecoveryDetailScreen(model: sampleModel(score: 78, calibration: nil))
    }
}

#Preview("Recovery detail — calibrando") {
    Color.clear.sheet(isPresented: .constant(true)) {
        RecoveryDetailScreen(model: sampleModel(score: nil, calibration: 3))
    }
}

#Preview("Recovery detail — sin datos") {
    Color.clear.sheet(isPresented: .constant(true)) {
        RecoveryDetailScreen(model: RecoveryDetailModel(
            score: nil, calibration: nil, nightsNeeded: 4, impact: nil, change: nil,
            series: [], heat: [], load: nil, loaded: true, isAppleHealth: false, forecast: nil,
            isEstimated: false, confidence: nil, presentPrimaryDrivers: nil, estimatedDirections: []))
    }
}

#Preview("Recovery detail — estimado (Apple)") {
    Color.clear.sheet(isPresented: .constant(true)) {
        RecoveryDetailScreen(model: sampleModel(score: 64, calibration: nil,
                                                isEstimated: true, confidence: .building,
                                                presentPrimaryDrivers: 2,
                                                estimatedDirections: [
                                                    .init(key: "hrv", position: .above, helps: true),
                                                    .init(key: "rhr", position: .above, helps: false),
                                                ]))
    }
}
#endif
#endif
