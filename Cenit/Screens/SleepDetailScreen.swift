#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore
import Foundation

// MARK: - SleepDetailScreen — el «Detalle de Sueño» en lenguaje «Instrumento» (FER-212)
//
// Hermana de `MetricDetailScreen` (FER-185): REUSA su lenguaje visual (el scaffold `DetailBlock`, el
// patrón `hero`, `theme: InstrumentoTheme` explícito, `SheetPaperBackground`, `ScrollView`→`VStack`,
// `methodDisclosure`) pero con su propio modelo rico. REEMPLAZA la vieja pantalla de sueño oscura (ya
// retirada) y es un SUPERSET de ella + un bloque NUEVO de regularidad del horario.
//
// NO extiende `MetricDetailScreen`/`MetricDetailSpec` (esos son para vitales de serie única). Se presenta
// desde Cuerpo vía `.sheet(item:)` con el tema vivo del landing pasado EXPLÍCITO (no propaga por `.sheet`,
// FER-162) y SIN `NavigationStack` anidado (un stack anidado cruzando el path de la tab crasheaba SwiftUI,
// FER-171).
//
// Las 8 secciones (orden exacto): 1) Hero · 2) Anoche (hipnograma + etapas en %) · 3) Regularidad del
// horario (destacado, `SleepRegularity`) · 4) Anoche vs lo típico (por etapa, en %) · 5) Tendencia de
// duración (`TrendChart` 30d + deuda) · 6) Métricas de la noche (grid) · 7) Ver el método · 8) Footer.
//
// La ciencia por métrica está documentada en `sleep-detail-science` (memoria): regularidad = SD del
// punto medio (Windred 2024) > duración; etapas en % aproximadas (Miller 2020); una sola suficiencia +
// faltante en horas; la deuda no se salda con una sola noche.

/// Light «Instrumento» Detalle de Sueño. Built once from a `SleepDetailModel` (the caller injects the
/// model so the screen stays DB-free), themed explicitly for the sheet boundary.
struct SleepDetailScreen: View {
    /// The live «Instrumento» theme, passed explicitly (sheets start a fresh environment). (FER-162)
    var theme: InstrumentoTheme = .base
    /// Everything the screen draws, derived ONCE by the caller from `repo` (no DB access here).
    let model: SleepDetailModel

    /// The metric whose info card is open (tap a Tonight's-metrics tile). (FER-227)
    @State private var metricInfo: MetricInfo?
    /// Whether the combined "Sleep stages" explainer card is open (opened from «See the method»). (FER-227)
    @State private var showStages = false
    /// Whether the hero's in-place "what we measure" note is open (the ⓘ by the «Sleep» overline).
    @State private var heroInfoOpen = false
    /// Level-3 disclosure: duration trend + weekly debt + the night sub-metrics live under «See your
    /// history», collapsed on open. The only new state the re-sequencing adds. (Detalles escalonados)
    @State private var historyExpanded = false

    var body: some View {
        ScrollView {
            // Rhythm by space: sections breathe on `sectionGap`, with NO rule between them — the
            // hairline only divides WITHIN a group now (DESIGN.md §8: hierarchy by space, not boxes).
            // (FER-227)
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                if let night = model.night {
                    // Level 1 · the answer: the hero's double datum (hours + regularity) + the hypnogram.
                    hero(night)
                    lastNightBlock(night)
                    // Level 2 · «Your patterns»: how well + stages + debt, fused to plain lines.
                    patternsBlock(night)
                    // Level 3 · «See your history»: duration trend + weekly debt + the night sub-metrics.
                    historySection(night)
                    methodDisclosure
                    sourceFooter
                } else {
                    emptyState
                }
            }
            .padding(NoopMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.paper)
        .presentationDragIndicator(.visible)
        .modifier(SleepSheetPaperBackground(paper: theme.paper))
        // Tap a tile → its MetricInfoSheet; tap the ⓘ by "Last night" → the stages explainer. Both are
        // nested sheets themed EXPLICITLY (the theme doesn't propagate through `.sheet`, FER-162) and
        // with NO nested NavigationStack (FER-171). (FER-227)
        .sheet(item: $metricInfo) { info in
            MetricInfoSheet(info: info, theme: theme, trendLoader: trendLoader(for: info.id))
        }
        .sheet(isPresented: $showStages) {
            SleepStagesInfoSheet(theme: theme)
        }
    }

    // MARK: - 1. Hero — doble dato (horas + regularidad) + frase-veredicto
    //
    // The headline is now TWO numerals — hours asleep and schedule regularity — split by a vertical
    // hairline, because the mid-sleep point predicts health better than total hours (the regularity
    // co-datum, lifted out of its old mid-page surface). Under it, a plain-language verdict built from
    // sufficiency + regularity, then a context line. A single ⓘ toggles an in-place "what we measure"
    // note (the only ⓘ on the sheet now). No new math: hours, performance % and regularity are the model's.

    @ViewBuilder
    private func hero(_ night: SleepDetailModel.Night) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Sleep").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                Spacer(minLength: 8)
                Button {
                    withAnimation(StrandMotion.interactive) { heroInfoOpen.toggle() }
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 17))
                        .foregroundStyle(theme.inkTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("What we measure"))
            }
            heroDoubleDatum(night)
            Text(heroVerdict(night))
                .font(StrandFont.headline)
                .foregroundStyle(theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(heroContextLine())
                .font(StrandFont.caption)
                .foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if model.excludedNapCount > 0 {
                heroNapNotice
            }
            if heroInfoOpen {
                heroInfoNote
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The two headline numerals — hours asleep and regularity /100 — split by a vertical hairline. The
    /// regularity side honestly shows "—" + a calibration meter until the engine has enough nights.
    @ViewBuilder
    private func heroDoubleDatum(_ night: SleepDetailModel.Night) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(hoursOnly(night.stages.asleep)).instrumentoHero(40).foregroundStyle(theme.dataSleep)
                Text("hours").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Rectangle().fill(theme.hairline).frame(width: 1, height: 52)
            regularityCoDatum
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The regularity co-datum: the score over /100 once the engine has enough nights, otherwise an
    /// honest calibration — "—", a meter (N of `minNights`), and "N nights to go". No fake number.
    @ViewBuilder
    private var regularityCoDatum: some View {
        if let r = model.regularity {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(r.score)").instrumentoHero(40).foregroundStyle(theme.dataSleep)
                    Text(verbatim: "/100").font(StrandFont.subhead).foregroundStyle(theme.inkTertiary)
                }
                Text("regularity").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            }
        } else {
            let done = max(0, min(model.regularityNights, SleepRegularity.minNights))
            let missing = max(0, SleepRegularity.minNights - model.regularityNights)
            VStack(alignment: .leading, spacing: 7) {
                Text(verbatim: "—").instrumentoHero(30).foregroundStyle(theme.inkTertiary)
                Text("regularity").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                calibrationMeter(done: done, total: SleepRegularity.minNights)
                Text("Settling in · \(missing) nights to go")
                    .font(StrandFont.footnote)
                    .foregroundStyle(theme.warning)
            }
        }
    }

    /// A row of `total` segments, the first `done` filled (verdict hue), the rest hairline — the honest
    /// "N of minNights" progress shown while regularity is still settling.
    private func calibrationMeter(done: Int, total: Int) -> some View {
        HStack(spacing: 5) {
            ForEach(0..<total, id: \.self) { i in
                Capsule(style: .continuous)
                    .fill(i < done ? theme.verdict : theme.hairline)
                    .frame(height: 5)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text("\(done) of \(total) nights"))
    }

    /// A plain-language verdict built from sufficiency (% of need) + regularity — "Enough and right on
    /// schedule — 95% of your need, very regular timing." While calibrating it narrows to what we know:
    /// "Enough — 95% of your need."
    private func heroVerdict(_ night: SleepDetailModel.Night) -> String {
        let perf = model.performancePct.map { Int(min(100, $0).rounded()) }
        let suff = sufficiencyWord(perf)
        if let r = model.regularity, let p = perf {
            return String(localized: "\(suff) and \(scheduleWord(r.score)) — \(p)% of your need, \(regularityWordText(r.score)) timing.")
        }
        if let r = model.regularity {
            return String(localized: "\(scheduleWord(r.score)) — \(regularityWordText(r.score)) timing.")
        }
        if let p = perf {
            return String(localized: "\(suff) — \(p)% of your need.")
        }
        return String(localized: "Last night, logged.")
    }

    /// The line under the verdict: the mid-sleep-regularity context (+ weekend shift) when we have a
    /// score, or — while calibrating — what we're still learning.
    private func heroContextLine() -> String {
        guard let r = model.regularity else {
            let missing = max(0, SleepRegularity.minNights - model.regularityNights)
            return String(localized: "I'm still learning your schedule: \(missing) more nights and I'll know how regular your mid-sleep point is — the figure that predicts your health better than hours.")
        }
        var s = (r.score >= 80)
            ? String(localized: "Your mid-sleep point is among your steadiest — it predicts your health better than total hours.")
            : String(localized: "Your mid-sleep point still shifts night to night — it predicts your health better than total hours.")
        if let shift = r.weekendShiftMinutes, shift >= 1 {
            s += " " + String(localized: "Weekend +\(hoursMinutes(shift)) later.")
        }
        return s
    }

    /// The FER-310 nap disclosure, preserved from the old regularity block: a quiet line noting the
    /// naps the regularity window dropped (it only counts your main night).
    private var heroNapNotice: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "zzz")
                .font(StrandFont.footnote)
                .foregroundStyle(theme.inkTertiary)
            Text(napNotice)
                .font(StrandFont.footnote)
                .foregroundStyle(theme.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The in-place note the hero ⓘ toggles — what the screen measures, in one quiet paragraph.
    private var heroInfoNote: some View {
        Text("Sleep is measured in hours asleep and in how regular your mid-sleep point is (the midpoint between falling asleep and waking). Stages are estimated from movement and heart rate, so they're approximate. \"Need\" is a 7–9 h target, not a measurement of you.")
            .font(StrandFont.caption)
            .foregroundStyle(theme.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(NoopMetrics.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
    }

    /// The sufficiency clause of the verdict, from performance %. nil performance → a neutral "Logged".
    private func sufficiencyWord(_ perf: Int?) -> String {
        guard let p = perf else { return String(localized: "Logged") }
        if p >= 90 { return String(localized: "Enough") }
        if p >= 75 { return String(localized: "Almost enough") }
        return String(localized: "Short on sleep")
    }

    /// The "on schedule" head adjective of the verdict, from the regularity score.
    private func scheduleWord(_ score: Int) -> String {
        switch score {
        case 80...:   return String(localized: "right on schedule")
        case 55..<80: return String(localized: "fairly on schedule")
        default:      return String(localized: "on a shifting schedule")
        }
    }

    /// The "very regular / regular / variable" tail word of the verdict, from the regularity score.
    private func regularityWordText(_ score: Int) -> String {
        switch score {
        case 80...:   return String(localized: "very regular")
        case 55..<80: return String(localized: "regular")
        default:      return String(localized: "variable")
        }
    }

    // MARK: - 2. Anoche — hipnograma + etapas en %

    @ViewBuilder
    private func lastNightBlock(_ night: SleepDetailModel.Night) -> some View {
        let s = night.stages
        // The hypnogram is now the clean protagonist of «Last night» (the headline double datum moved up
        // to the hero). Its lanes are labelled down the left edge; onset/wake anchor the trace below it.
        // No ⓘ here now — the only one is the hero's; the stages explainer opens from «See the method».
        DetailBlock("Last night", theme: theme) {
            VStack(alignment: .leading, spacing: 14) {
                if model.intervals.count >= 2 {
                    Hypnogram(intervals: model.intervals,
                              height: 150,
                              showsStageAxis: true,
                              showsScrub: true,   // finger-drag scrub → stage + clock range + duration (FER-234)
                              nightStart: night.onsetDate)
                    // Anchor the trace: onset on the left, wake on the right, under the plotted timeline
                    // (the leading inset matches the hypnogram's stage-axis column). (#7)
                    HStack {
                        Text(night.onsetText).font(StrandFont.captionNumber).foregroundStyle(theme.inkTertiary)
                        Spacer()
                        Text(night.wakeText).font(StrandFont.captionNumber).foregroundStyle(theme.inkTertiary)
                    }
                    .padding(.leading, 56)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(Text("Asleep \(night.onsetText), awake \(night.wakeText)"))
                } else {
                    // Apple Health / no per-epoch timeline → proportional stacked bar.
                    stageBar(s)
                    HStack(spacing: 6) {
                        Image(systemName: "heart.fill").font(.system(size: 10)).foregroundStyle(theme.dataSpO2)
                        Text("Apple Health").font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                    }
                }
                // Stage breakdown in PERCENT (not exact minutes — wrist staging is ~2/3 accurate), each
                // with its delta in points vs your typical inline (#4).
                stagePercents(s)
                Text("% of the night · Δ vs your typical")
                    .font(StrandFont.footnote)
                    .foregroundStyle(theme.inkTertiary)
            }
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
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Sleep stages: deep \(pct(s.deep, s.total)) percent, light \(pct(s.light, s.total)) percent, REM \(pct(s.rem, s.total)) percent, awake \(pct(s.awake, s.total)) percent"))
    }

    @ViewBuilder
    private func stageSegment(_ stage: SleepStage, _ minutes: Double, _ total: Double, _ width: CGFloat) -> some View {
        Rectangle()
            .fill(StrandPalette.sleepStageColor(stage))
            .frame(width: max(0, CGFloat(minutes / total) * width))
    }

    /// REM / Deep / Light / Awake as a row of "color dot · LABEL · NN% Δ" — percentages, never minutes,
    /// each with the delta in points vs your typical inline (Awake has no typical, so no delta).
    @ViewBuilder
    private func stagePercents(_ s: SleepDetailModel.Stages) -> some View {
        HStack(alignment: .top, spacing: 0) {
            stagePercentCell(.rem, "REM", s.rem, s.total, typicalPct: model.typicalRemPct)
            Spacer(minLength: 0)
            stagePercentCell(.deep, "Deep", s.deep, s.total, typicalPct: model.typicalDeepPct)
            Spacer(minLength: 0)
            stagePercentCell(.light, "Light", s.light, s.total, typicalPct: model.typicalLightPct)
            Spacer(minLength: 0)
            stagePercentCell(.awake, "Awake", s.awake, s.total, typicalPct: nil)
        }
    }

    @ViewBuilder
    private func stagePercentCell(_ stage: SleepStage, _ label: LocalizedStringKey, _ minutes: Double, _ total: Double, typicalPct: Double?) -> some View {
        let p = pct(minutes, total)
        let delta = stageDelta(pctOfTotal: p, typicalPct: typicalPct)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(StrandPalette.sleepStageColor(stage))
                    .frame(width: 8, height: 8)
                Text(label).instrumentoOverline().foregroundStyle(theme.inkTertiary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(p)%")
                    .font(StrandFont.bodyNumber)
                    .foregroundStyle(theme.ink)
                if let delta {
                    Text(delta.text)
                        .font(StrandFont.captionNumber)
                        .foregroundStyle(delta.positive ? theme.verdict : theme.inkTertiary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(stagePercentAccessibility(label, pct: p, delta: delta))
    }

    /// The delta in points between last night's stage share (% of the night) and your typical. Uses the
    /// same mixed basis the vs-typical bars already draw — last %-of-night minus typical %-of-asleep —
    /// so the screen stays internally consistent (and matches the design). "+3" / "−2" / "~0"; a gain
    /// reads in the verdict hue, flat/below stays quiet. nil when there's no personal typical yet.
    private func stageDelta(pctOfTotal: Int, typicalPct: Double?) -> (text: String, positive: Bool)? {
        guard let typicalPct else { return nil }
        let d = Int((Double(pctOfTotal) - typicalPct).rounded())
        if d == 0 { return ("~0", false) }
        return d > 0 ? ("+\(d)", true) : ("−\(abs(d))", false)
    }

    /// VoiceOver for a stage cell: "{stage}, {pct}% of the night" plus a "{n} points above/below typical"
    /// clause when there's a delta.
    private func stagePercentAccessibility(_ label: LocalizedStringKey, pct: Int, delta: (text: String, positive: Bool)?) -> Text {
        let head = Text("\(Text(label)), \(pct)% of the night")
        guard let delta, delta.text != "~0" else { return head }
        return delta.positive
            ? head + Text(", \(delta.text) points above typical")
            : head + Text(", \(delta.text) points below typical")
    }

    // MARK: - 4. Anoche vs lo típico (por etapa, en %) — en «See your history»

    @ViewBuilder
    private func stagesVsTypicalBlock(_ night: SleepDetailModel.Night) -> some View {
        let s = night.stages
        DetailBlock("Last night vs your typical", theme: theme) {
            VStack(alignment: .leading, spacing: 14) {
                stageVsTypicalRow("Deep", lastMin: s.deep, total: s.total,
                                  typicalPct: model.typicalDeepPct, color: StrandPalette.sleepDeep)
                Divider().overlay(theme.hairline)
                stageVsTypicalRow("REM", lastMin: s.rem, total: s.total,
                                  typicalPct: model.typicalRemPct, color: StrandPalette.sleepREM)
                Divider().overlay(theme.hairline)
                stageVsTypicalRow("Light", lastMin: s.light, total: s.total,
                                  typicalPct: model.typicalLightPct, color: StrandPalette.sleepLight)
            }
        }
    }

    /// One stage as a % of last night, with the delta in points vs the typical and a bar carrying a
    /// marker at the personal average. Everything is in PERCENT (porting `stageRow` to Instrumento + %).
    @ViewBuilder
    private func stageVsTypicalRow(_ label: LocalizedStringKey, lastMin: Double, total: Double,
                                   typicalPct: Double?, color: Color) -> some View {
        let lastPct = total > 0 ? lastMin / total * 100 : 0
        // Scale against a shared per-row max so the marker reads meaningfully.
        let scaleMax = max(lastPct, typicalPct ?? 0) * 1.18
        let denom = scaleMax > 0 ? scaleMax : 1
        let deltaText: LocalizedStringKey? = {
            guard let typicalPct else { return nil }
            let diff = Int((lastPct - typicalPct).rounded())
            // Two explicit signed keys so each localizes cleanly (no "%@%lld pts" nested-sign key).
            return diff >= 0 ? "+\(abs(diff)) pts" : "−\(abs(diff)) pts"
        }()
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(label).instrumentoOverline().foregroundStyle(theme.inkTertiary)
                Spacer()
                Text("\(Int(lastPct.rounded()))%")
                    .font(StrandFont.captionNumber).foregroundStyle(theme.ink)
                if let deltaText {
                    Text(deltaText)
                        .font(StrandFont.footnote)
                        .foregroundStyle(lastPct >= (typicalPct ?? lastPct) ? theme.verdict : theme.warning)
                }
            }
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous).fill(theme.hairline)
                    Capsule(style: .continuous)
                        .fill(color)
                        .frame(width: w * CGFloat(min(1, lastPct / denom)))
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

    /// VoiceOver label for a stage row: "{stage}, {last}% last night" plus a "typical {x}%" clause when
    /// there's a personal average. Two clean keys (no nested optional interpolation).
    private func stageAccessibilityLabel(_ label: LocalizedStringKey, lastPct: Double, typicalPct: Double?) -> Text {
        let head = Text("\(Text(label)), \(Int(lastPct.rounded()))% last night")
        guard let typicalPct else { return head }
        return head + Text(", typical \(Int(typicalPct.rounded()))%")
    }

    // MARK: - Level 2 · «Your patterns» — how well + stages + debt, fused to plain lines
    //
    // The re-sequencing (Detalles escalonados) folds the three redundant "did I sleep well?" framings —
    // Performance, Efficiency, the vs-typical stages and the debt line — into one condensed strip. The
    // jargon stays in the ⓘ; the face is plain language. No new math: every value comes straight from
    // the model (performance %, efficiency %, the typical-stage means, the weekly debt). The full
    // vs-typical bars and the duration/debt charts live one level down in «See your history».

    @ViewBuilder
    private func patternsBlock(_ night: SleepDetailModel.Night) -> some View {
        DetailBlock("Your patterns", theme: theme) {
            VStack(alignment: .leading, spacing: 12) {
                patternLine(label: "How well", value: howWellText(), note: nil)
                if let stages = stagesVsTypicalText(night) {
                    patternLine(label: "Stages", value: stages, note: nil)
                }
                if let debt = model.weeklyDebtMinutes, debt >= 15 {
                    patternLine(label: "Sleep debt",
                                value: hoursMinutes(debt),
                                valueColor: theme.warning,
                                note: "behind this week")
                }
            }
        }
    }

    /// "95% of your need" — performance leads «How well» with the share of your need you slept.
    /// Efficiency is no longer fused here; it lives once, as a sub-metric tile in «See your history» (#3).
    private func howWellText() -> String {
        guard let p = model.performancePct else { return "—" }
        return String(localized: "\(Int(min(100, p).rounded()))% of your need")
    }

    /// A one-phrase read of last night's stage mix vs your typical — "Deep & REM where you usually are"
    /// when both are within a few points, else names the one that's notably off. nil when there's no
    /// personal typical yet. Reads the SAME percentages the vs-typical bars draw (no new math).
    private func stagesVsTypicalText(_ night: SleepDetailModel.Night) -> String? {
        let s = night.stages
        guard s.total > 0, model.typicalDeepPct != nil || model.typicalRemPct != nil else { return nil }
        func diff(_ minutes: Double, _ typical: Double?) -> Double? {
            guard let typical else { return nil }
            return (minutes / s.total * 100) - typical
        }
        let deepDelta = diff(s.deep, model.typicalDeepPct)
        let remDelta = diff(s.rem, model.typicalRemPct)
        let near = 4.0
        let deepOff = (deepDelta.map { abs($0) > near }) ?? false
        let remOff = (remDelta.map { abs($0) > near }) ?? false
        if !deepOff && !remOff { return String(localized: "Deep & REM where you usually are") }
        if deepOff, let d = deepDelta {
            return d > 0 ? String(localized: "More deep sleep than usual")
                         : String(localized: "Less deep sleep than usual")
        }
        if let r = remDelta {
            return r > 0 ? String(localized: "More REM than usual")
                         : String(localized: "Less REM than usual")
        }
        return String(localized: "Deep & REM where you usually are")
    }

    /// One «Your patterns» line: a quiet overline label, a plain value (the datum), an optional note.
    private func patternLine(label: LocalizedStringKey, value: String,
                             valueColor: Color? = nil, note: LocalizedStringKey?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label).instrumentoOverline().foregroundStyle(theme.inkTertiary)
            Spacer(minLength: 8)
            Text(value).font(StrandFont.bodyNumber).foregroundStyle(valueColor ?? theme.ink)
            if let note {
                Text(note).font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Level 3 · «See your history» — duration trend + weekly debt + night sub-metrics
    //
    // The analyst's view, one tap down. An in-place disclosure (NOT a navigation push). Holds the
    // duration trend (with its bands), the weekly-debt bars, the full vs-typical stage bars, and the
    // four night sub-metric tiles (each still opens its `MetricInfoSheet` on tap). (Detalles escalonados)

    @ViewBuilder
    private func historySection(_ night: SleepDetailModel.Night) -> some View {
        VStack(alignment: .leading, spacing: historyExpanded ? NoopMetrics.sectionGap : 0) {
            historyDisclosureHeader(caption: "trends · debt · sub-metrics")
            if historyExpanded {
                stagesVsTypicalBlock(night)
                durationTrendBlock
                weeklyDebtBlock
                nightMetricsBlock(night)
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

    // MARK: - Tendencia de duración (14 noches + 4 bandas de clasificación) — en «See your history»
    //
    // Misma lectura que la hoja de Sueño en Hoy (`MetricInfoSheet`, FER-244): 14 noches, las bandas
    // Short/Adequate/Optimal/Extended con la activa resaltada, un encabezado de conteo y ticks en los
    // umbrales 6/7/9 h. Unifica las dos gráficas de sueño que antes divergían (Hoy 14d/4-bandas vs.
    // Cuerpo 30d/1-banda). (FER-249 v2)

    @ViewBuilder
    private var durationTrendBlock: some View {
        let pts = model.trendPoints
        DetailBlock("Duration trend", theme: theme) {
            VStack(alignment: .leading, spacing: 10) {
                if pts.count >= 2, let bt = bandedDuration(pts) {
                    // Active-band header: which band the latest nights sit in, and how many of the
                    // window land there — the same one-liner the Today sheet shows.
                    HStack(spacing: 6) {
                        Text(bt.activeLabel).foregroundStyle(theme.dataSleep)
                        Text(verbatim: "·").foregroundStyle(theme.inkTertiary)
                        Text("\(bt.count) of the last \(bt.total) nights in this range")
                            .foregroundStyle(theme.inkSecondary)
                    }
                    .font(StrandFont.subhead)
                    TrendChart(
                        points: pts,
                        gradient: Gradient(colors: [theme.dataSleep.opacity(0.5), theme.dataSleep]),
                        valueRange: bt.range,
                        // No area fill: the soft gradient under the line muddied the classification
                        // bands so you couldn't tell which one you were in. The line alone reads the
                        // band cleanly. (FER-249 v3)
                        showsArea: false,
                        height: 160,
                        showsScrub: true,
                        valueFormat: bt.valueFormat,
                        axisLabelColor: theme.inkTertiary,
                        gridLineColor: theme.hairline,
                        bands: bt.bands,
                        bandColor: theme.dataSleep,
                        yAxisValues: bt.yTicks
                    )
                    .accessibilityElement()
                    .accessibilityLabel(Text("Hours asleep per night, last 14 nights, with classification bands"))
                    durationStats(pts)
                } else {
                    emptyWell(text: "Not enough nights yet to draw a trend.")
                }
            }
        }
    }

    // MARK: - 5b. Deuda semanal (cifra dominante + barras por noche)
    //
    // La deuda dejó de ser una línea de texto suelta: ahora es su propio bloque con la cifra acumulada
    // de la semana como dato dominante (en `warning`) y, debajo, una barra por noche que muestra qué
    // noche se quedó corta (`warning`, abajo de tu necesidad) o la superó (`verdict`, arriba). Se oculta
    // cuando no hay deuda significativa que mostrar. (FER-249 v2)

    @ViewBuilder
    private var weeklyDebtBlock: some View {
        if let debt = model.weeklyDebtMinutes, debt >= 15, model.weeklyDebtNights.count >= 2 {
            DetailBlock("Weekly debt", theme: theme) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(hoursMinutes(debt))
                            .font(StrandFont.number(30))
                            .foregroundStyle(theme.warning)
                        Text("behind this week")
                            .font(StrandFont.subhead)
                            .foregroundStyle(theme.inkTertiary)
                    }
                    weeklyDebtBars
                    Text("What you missed versus what your body needs. One good night won't clear it.")
                        .font(StrandFont.caption)
                        .foregroundStyle(theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// One bar per night for the trailing week: hours above (`verdict`) or below (`warning`) your need,
    /// with the need itself as the zero rule. Scrubbable like every other chart — drag to read a night's
    /// debt and how much you slept (`DebtBars`). The dates are UTC day-keys (FER-226), so the weekday
    /// label formats in UTC to avoid an off-by-one shift. (FER-249 v3)
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

    /// Single-letter weekday in UTC (matches the UTC day-keys the model stores). "L M M J V S D" in es-MX.
    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "UTC")
        f.setLocalizedDateFormatFromTemplate("EEEEE")
        return f
    }()
    private static func weekdayNarrow(_ date: Date) -> String { weekdayFormatter.string(from: date) }

    /// The shared «Instrumento» trend summary — average as the protagonist + the night range — in hours.
    /// Sleep's duration trend is a fixed 30-night view with no month-over-month series, so no trend chip
    /// (`pctChange: nil` hides it); higher sleep is better, which colours the chip on the screens that have it.
    @ViewBuilder
    private func durationStats(_ pts: [TrendPoint]) -> some View {
        let vals = pts.map(\.value)
        let avg = vals.isEmpty ? nil : vals.reduce(0, +) / Double(vals.count)
        TrendStatSummary(
            average: avg.map { String(format: "%.1f", $0) } ?? "—",
            unit: "h",
            pctChange: nil,
            polarity: .higherIsBetter,
            rangeLow: vals.min().map { String(format: "%.1f", $0) } ?? "—",
            rangeHigh: vals.max().map { String(format: "%.1f h", $0) } ?? "—",
            theme: theme
        )
    }

    // MARK: - 6. Métricas de la noche (grid 2-col)

    @ViewBuilder
    private func nightMetricsBlock(_ night: SleepDetailModel.Night) -> some View {
        DetailBlock("Tonight's metrics", theme: theme) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: NoopMetrics.gap), GridItem(.flexible(), spacing: NoopMetrics.gap)],
                      alignment: .leading, spacing: NoopMetrics.gap) {
                // Performance: asleep / need, capped at 100%, with the shortfall in real hours.
                metricTile(
                    label: "Performance",
                    value: model.performancePct.map { "\(Int(min(100, $0).rounded()))%" } ?? "—",
                    caption: performanceCaption,
                    color: model.performancePct != nil ? theme.dataSleep : theme.inkTertiary,
                    info: .sleepPerformance(model.performancePct))
                metricTile(
                    label: "Efficiency",
                    value: efficiencyPct(night).map { "\(Int($0.rounded()))%" } ?? "—",
                    caption: "vs time in bed",
                    color: efficiencyPct(night) != nil ? theme.dataSleep : theme.inkTertiary,
                    info: .sleepEfficiency(efficiencyPct(night)))
                // Restorative = (deep + REM) / asleep, the literal WHOOP definition.
                metricTile(
                    label: "Restorative",
                    value: restorativePct(night.stages).map { "\(Int($0.rounded()))%" } ?? "—",
                    caption: "Deep + REM",
                    color: restorativePct(night.stages) != nil ? theme.dataSleep : theme.inkTertiary,
                    info: .sleepRestorative(restorativePct(night.stages)))
                // Latency: the cache carries no onset-latency, so omit the tile rather than show a permanent "—".
                if let latency = model.latencyMin {
                    metricTile(
                        label: "Latency",
                        value: "\(Int(latency.rounded())) min",
                        caption: "10–20 healthy",
                        color: theme.dataSleep,
                        info: .sleepLatency(latency))
                }
                metricTile(
                    label: "Respiration",
                    value: night.respRate.map { String(format: "%.1f", $0) } ?? "—",
                    caption: "rpm",
                    color: night.respRate != nil ? theme.dataSpO2 : theme.inkTertiary,
                    info: .respiratory(night.respRate))
                metricTile(
                    label: "Awakenings",
                    value: model.awakenings.map { "\($0)" } ?? "—",
                    caption: "times",
                    color: model.awakenings != nil ? theme.dataSleep : theme.inkTertiary,
                    info: .sleepAwakenings(model.awakenings))
            }
        }
    }

    /// One metric tile in Instrumento: label overline · value in its data hue · quiet caption. The whole
    /// tile is a button that opens the metric's `MetricInfoSheet` (like Today); a quiet ⓘ in the corner
    /// signals "tap to learn what this means". Never the dark `StatTile`. (FER-227)
    private func metricTile(label: LocalizedStringKey, value: String,
                            caption: LocalizedStringKey, color: Color, info: MetricInfo) -> some View {
        Button {
            metricInfo = info
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(label).instrumentoOverline().foregroundStyle(theme.inkTertiary)
                Text(value).font(StrandFont.number(22)).foregroundStyle(color)
                Text(caption).font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(NoopMetrics.cardPadding)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous).strokeBorder(theme.hairline, lineWidth: 1))
            .overlay(alignment: .topTrailing) {
                Image(systemName: "info.circle")
                    .font(.system(size: 15))
                    .foregroundStyle(theme.inkTertiary)
                    .padding(11)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(Text("Shows what this means"))
    }

    /// The precomputed 14-day mini-trend for a metric sheet, wrapped as the loader `MetricInfoSheet`
    /// expects (it runs lazily on appear). nil for ids we don't chart; an empty series makes the sheet
    /// show its "no data" well rather than a fake line. (FER-227)
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

    // MARK: - 7. Ver el método (DisclosureGroup, patrón de MetricDetailScreen)

    @State private var methodExpanded = false

    private var methodDisclosure: some View {
        DisclosureGroup(isExpanded: $methodExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                Divider().overlay(theme.hairline)
                Text("Regularity is the night-to-night variability of your mid-sleep point (the midpoint between falling asleep and waking) — a steadier schedule predicts health more strongly than how long you sleep. Naps don't count: only your main night (at least 3 h) feeds regularity. Stages are estimated from movement, heart rate and HRV, so they're approximate; deep sleep repairs the body, REM consolidates memory and emotion. \"Need\" is a 7–9 h population target, not a measurement of you.")
                    .font(StrandFont.subhead)
                    .foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Windred et al., Sleep 2024 (regularity); Miller et al., J Sports Sci 2020 (wrist staging vs PSG); Hirshkowitz et al., 2015 (sleep need).")
                    .font(StrandFont.caption)
                    .foregroundStyle(theme.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                // The full per-stage explainer (kept available, FER-227) opens here from the method.
                Button { showStages = true } label: {
                    HStack(spacing: 6) {
                        Text("Sleep stages in detail")
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                    }
                    .font(StrandFont.subhead)
                    .foregroundStyle(theme.dataSleep)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text("How it's calculated")
                .font(StrandFont.subhead)
                .foregroundStyle(theme.ink)
        }
        .tint(theme.inkTertiary)
        .padding(NoopMetrics.cardPadding)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
    }

    // MARK: - 8. Footer — fuente del dato (la fuente migró aquí desde el contexto del héroe)

    private var sourceFooter: some View {
        HStack(spacing: 6) {
            Image(systemName: model.isAppleHealth ? "heart.fill" : "antenna.radiowaves.left.and.right")
                .font(.system(size: 10))
                .foregroundStyle(theme.inkTertiary)
            Text(model.isAppleHealth ? "From Apple Health" : "From your band, on your device")
                .font(StrandFont.footnote)
                .foregroundStyle(theme.inkTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Empty state (ported from the old sleep screen)

    @ViewBuilder
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sleep").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            Text("—").instrumentoHero(44).foregroundStyle(theme.inkTertiary)
            Text(model.loaded
                 ? "No nights yet. Import your WHOOP export — or connect Apple Health — in Data Sources to see your sleep stages and trends. Or wear the strap to bed and open it again after the strap syncs."
                 : "Loading your sleep history…")
                .font(StrandFont.subhead)
                .foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Wells (mirror MetricDetailScreen)

    private func emptyWell(text: LocalizedStringKey) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "moon.zzz")
                .font(.system(size: 22))
                .foregroundStyle(theme.inkTertiary)
            Text(text)
                .font(StrandFont.subhead)
                .foregroundStyle(theme.inkSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
    }

    // MARK: - Formatting helpers

    private func pct(_ minutes: Double, _ total: Double) -> Int {
        total > 0 ? Int((minutes / total * 100).rounded()) : 0
    }

    /// Hours-and-minutes as a hero figure ("7:24") so the dominant numeral reads like a clock read-out.
    private func hoursOnly(_ minutes: Double) -> String {
        let m = Swift.max(0, Int(minutes.rounded()))
        return String(format: "%d:%02d", m / 60, m % 60)
    }

    /// The disclosure line shown under the regularity figure when the window dropped one or more naps
    /// (FER-310): names the duration for a single nap, generic otherwise. The "main night" threshold
    /// comes from `SleepMainNight`, so the copy never hardcodes 3 h.
    private var napNotice: LocalizedStringKey {
        if let minutes = model.excludedNapMinutes {
            return "We didn't count your \(napDurationText(minutes)) nap — regularity uses only your main night."
        }
        return "We didn't count your naps (under \(napDurationText(Int(SleepMainNight.minDurationMinutes)))) — regularity uses only your main night."
    }

    /// A minutes count as natural-language duration with no trailing zero minutes: "3 h", "1 h 30 min",
    /// "45 min" — for the nap-disclosure copy.
    private func napDurationText(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h > 0 && m > 0 { return "\(h) h \(m) min" }
        if h > 0 { return "\(h) h" }
        return "\(m) min"
    }

    /// A minutes count as a compact duration: "1h 20m" past the hour, "45 min" under it.
    private func hoursMinutes(_ minutes: Double) -> String {
        let m = Int(minutes.rounded())
        return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m) min"
    }

    private var performanceCaption: LocalizedStringKey {
        guard let missing = model.shortfallMinutes, missing >= 5 else { return "vs your need" }
        return "−\(hoursMinutes(missing)) vs your need"
    }

    /// Restorative % = (deep + REM) / asleep — the share of the night that does the work.
    private func restorativePct(_ s: SleepDetailModel.Stages) -> Double? {
        guard s.asleep > 0 else { return nil }
        return (s.deep + s.rem) / s.asleep * 100
    }

    /// Efficiency in percent. Prefer the stored session value, else asleep / time-in-bed.
    private func efficiencyPct(_ night: SleepDetailModel.Night) -> Double? {
        if let stored = night.efficiency {
            return stored <= 1.0 ? stored * 100 : stored
        }
        let bed = night.stages.total
        guard bed > 0 else { return nil }
        return Swift.min(100, night.stages.asleep / bed * 100)
    }

    /// The 4-band classification config for the duration trend — the same reading as the Today sleep
    /// sheet (`MetricInfoSheet.bandedTrend`, FER-244): Short/Adequate/Optimal/Extended, the active band
    /// the latest night sits in, the Y range anchored to the 6/7/9 h thresholds, ticks at those
    /// thresholds, and an hours-and-minutes value format. `nil` when the latest value matches no band,
    /// so the chart falls back to its empty well. (FER-249 v2)
    private struct BandedDuration {
        var bands: [TrendBand]
        var range: ClosedRange<Double>
        var yTicks: [Double]
        var valueFormat: (Double) -> String
        var activeLabel: LocalizedStringKey
        var count: Int
        var total: Int
    }


    private func bandedDuration(_ pts: [TrendPoint]) -> BandedDuration? {
        let values = pts.map(\.value)
        // Half-open bounds [lower, upper) match TrendBand.contains and the Today sheet's bands exactly.
        var bands: [TrendBand] = [
            TrendBand(label: "Short",    lower: nil, upper: 6),
            TrendBand(label: "Adequate", lower: 6,   upper: 7),
            TrendBand(label: "Optimal",  lower: 7,   upper: 9),
            TrendBand(label: "Extended", lower: 9,   upper: nil),
        ]
        guard let active = TrendBands.activeBand(values: values, bands: bands) else { return nil }
        bands[active.index].isActive = true
        let thresholds: [Double] = [6, 7, 9]
        let lo = Swift.min(values.min() ?? 6, 6)
        let hi = Swift.max(values.max() ?? 9, 9)
        let pad = Swift.max((hi - lo) * 0.08, 0.25)
        let range = Swift.max(0, lo - pad)...(hi + pad)
        let fmt: (Double) -> String = { v in
            let m = Int((v * 60).rounded())
            return m % 60 > 0 ? "\(m / 60)h \(m % 60)m" : "\(m / 60)h"
        }
        return BandedDuration(bands: bands, range: range, yTicks: thresholds, valueFormat: fmt,
                              activeLabel: bands[active.index].label, count: active.count, total: values.count)
    }
}

// MARK: - Sheet paper background (iOS 16.4+ presentationBackground)

private struct SleepSheetPaperBackground: ViewModifier {
    let paper: Color
    func body(content: Content) -> some View {
        if #available(iOS 16.4, *) {
            content.presentationBackground(paper)
        } else {
            content
        }
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
                    .font(StrandFont.title2)
                    .foregroundStyle(theme.ink)
                Text("Your night moves through four phases. The watch estimates them from your movement and heart rate, so they're approximate — it gets about 2 of 3 right.")
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
        .modifier(SleepSheetPaperBackground(paper: theme.paper))
    }

    private func stageRow(_ row: StageRow) -> some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
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
        var onsetText: String { Self.timeFmt.string(from: Date(timeIntervalSince1970: TimeInterval(startTs))) }
        var wakeText: String { Self.timeFmt.string(from: Date(timeIntervalSince1970: TimeInterval(endTs))) }
        var dateLabel: String { Self.dateFmt.string(from: Date(timeIntervalSince1970: TimeInterval(startTs))) }

        private static let timeFmt: DateFormatter = {
            let f = DateFormatter(); f.dateFormat = "H:mm"; return f
        }()
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
    /// Whether the repo finished its first load (drives the empty-state copy: loading vs no-data).
    let loaded: Bool

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

    // Duration trend + debt
    let trendPoints: [TrendPoint]
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
                      importedSleep: [String: ImportedSleepFigures],
                      appleHealthDays: Set<String>,
                      loaded: Bool,
                      todayKey: String) -> SleepDetailModel {
        // Ignore any future-dated row: a daily can be bucketed under "tomorrow" in UTC (FER-226),
        // and a `.last` read would surface that empty row as "last night". Anchor to the device's
        // local day, mirroring StressModel (FER-224) / ReadinessEngine.
        let days = days.filter { $0.day <= todayKey }
        // --- Latest night: strap session wins, else Apple Health stage minutes (FER-62). ---
        // Respiration for the strap night comes from the latest daily metric (the session doesn't
        // carry it), so the Respiration tile shows anoche's value instead of "—". (FER-234)
        let strap = latestStrapNight(sleeps, respRate: days.last?.respRateBpm)
        let night: Night? = strap ?? appleHealthNight(days: days, appleHealthDays: appleHealthDays)
        let isApple = (strap == nil) && (night != nil)
        let intervals: [SleepInterval] = {
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

        // --- Duration trend (trailing 30 nights, in hours) + 7-day accumulated debt. ---
        let trend = durationTrendPoints(days)
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

        return SleepDetailModel(
            night: night,
            intervals: intervals,
            isAppleHealth: isApple,
            loaded: loaded,
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
            trendPoints: trend,
            weeklyDebtMinutes: weeklyDebt,
            weeklyDebtNights: debtNights,
            performanceTrend: performanceTrend,
            efficiencyTrend: efficiencyTrend,
            restorativeTrend: restorativeTrend,
            respirationTrend: respirationTrend,
            awakeningsTrend: awakeningsTrend)
    }

    /// Trailing 14 nights of a metric, in whatever unit `pick` returns, as `TrendPoint`s. Skips nights
    /// where the value is missing; empty when there's nothing to chart. (FER-227)
    private static func metricTrend(_ days: [DailyMetric], _ pick: (DailyMetric) -> Double?) -> [TrendPoint] {
        let pts = days.compactMap { d -> TrendPoint? in
            guard let v = pick(d), let date = Repository.parseDayKey(d.day) else { return nil }
            return TrendPoint(date: date, value: v)
        }
        return Array(pts.suffix(14))
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

    /// Trailing 14 nights of total sleep, in HOURS — the same window the Today sleep sheet charts, so
    /// both screens read identically (FER-249 v2). Falls back to all nights when the window is sparse.
    private static func durationTrendPoints(_ days: [DailyMetric]) -> [TrendPoint] {
        func build(_ slice: ArraySlice<DailyMetric>) -> [TrendPoint] {
            slice.compactMap { d -> TrendPoint? in
                guard let mins = d.totalSleepMin, mins > 0,
                      let date = Repository.parseDayKey(d.day) else { return nil }
                return TrendPoint(date: date, value: mins / 60.0)
            }
        }
        let recent = build(days.suffix(14))
        if recent.count >= 2 { return recent }
        return build(days[...])
    }

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
