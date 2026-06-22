#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

// MARK: - Bucle sheets (FER-292)
//
// The light «Instrumento» detail surfaces the Bucle opens: the lever/finding detail (where the
// evidence the old `InsightsView` showed now lands), the full Hallazgos list, the «Efectos de tus
// hábitos» explorer (the behaviour-effects half of the old Insights, by metric, historical), and the
// Sí/No journal sheet («Anota tu día»). The theme is passed explicitly — it doesn't cross a `.sheet`
// boundary (FER-162).

// MARK: Lever / finding detail

struct PalancaDetailSheet: View {
    let insight: Insight
    let theme: InstrumentoTheme
    /// True when this lever is a candidate and nothing is in flight — shows the «Probar» CTA (FER-307).
    var canStartExperiment: Bool = false
    /// Invoked when the user taps «Probar esta idea» — the Bucle opens the start-confirmation sheet.
    var onProbar: (() -> Void)? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(BucleFormat.kindLabel(insight.kind).uppercased())
                        .instrumentoOverline().foregroundStyle(theme.inkTertiary)
                    Text(insight.title)
                        .font(StrandFont.title2).foregroundStyle(theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Hero datum.
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(datumText)
                        .font(.system(size: 40, weight: .semibold))
                        .monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.6)   // FER-394
                        .foregroundStyle(datumColor)
                    Text(insight.datum.metric)
                        .font(StrandFont.subhead).foregroundStyle(theme.inkTertiary)
                }

                Text(insight.reading)
                    .font(StrandFont.body).foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                // With / without comparison (behavior findings only) — the means the engine measured.
                if let bd = insight.behaviorBreakdown {
                    breakdownBars(bd)
                }

                // Evidence.
                VStack(spacing: 0) {
                    evidenceRow("Sample", "\(insight.evidence.n)")
                    if let p = insight.evidence.pAdjusted ?? insight.evidence.pValue {
                        evidenceRow("Significance", significanceText(p, sig: insight.evidence.significant, kind: insight.kind))
                    }
                    if let d = insight.evidence.effectSize {
                        evidenceRow("Effect size", String(format: "%.2f · %@", d, BucleFormat.magnitudeWord(d)))
                    }
                }

                // Confidence explainer.
                VStack(alignment: .leading, spacing: 5) {
                    Text(confidenceTitle).font(StrandFont.subhead).foregroundStyle(theme.ink)
                    Text(confidenceBody).font(StrandFont.footnote).foregroundStyle(theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.surface, in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous)
                    .stroke(theme.hairlineStrong, lineWidth: 1))

                // Probar esta idea — only for a candidate lever, only when nothing is in flight (FER-307).
                if canStartExperiment, let onProbar {
                    Button(action: onProbar) {
                        HStack(spacing: 7) {
                            Image(systemName: "flask").font(.system(size: 17))
                            Text("Try this idea for a week").font(StrandFont.headline)
                            Image(systemName: "arrow.right").font(.system(size: 15))
                        }
                        .foregroundStyle(theme.ink)
                        .frame(maxWidth: .infinity)
                        .padding(15)
                        .background(theme.surface, in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous)
                            .stroke(theme.hairlineStrong, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(NoopMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.paper.ignoresSafeArea())
    }

    private func evidenceRow(_ key: LocalizedStringKey, _ value: String) -> some View {
        HStack {
            Text(key).font(StrandFont.subhead).foregroundStyle(theme.inkTertiary)
            Spacer()
            Text(value).font(StrandFont.captionNumber).monospacedDigit().foregroundStyle(theme.ink)
        }
        .padding(.vertical, 11)
        .overlay(alignment: .top) { Rectangle().fill(theme.hairline).frame(height: 0.5) }
    }

    /// Two bars: the outcome mean on days WITH vs WITHOUT the behavior. The better group (respecting
    /// metric direction) carries the data hue; the other stays quiet ink. Color only on the datum.
    @ViewBuilder private func breakdownBars(_ bd: BehaviorBreakdown) -> some View {
        let withIsBetter = BucleFormat.withIsBetter(metric: insight.datum.metric,
                                                    meanWith: bd.meanWith, meanWithout: bd.meanWithout)
        let maxMean = max(bd.meanWith, bd.meanWithout, 1)
        VStack(alignment: .leading, spacing: 12) {
            breakdownBar(label: "With the habit", mean: bd.meanWith, n: bd.nWith,
                         frac: bd.meanWith / maxMean, good: withIsBetter)
            breakdownBar(label: "Without the habit", mean: bd.meanWithout, n: bd.nWithout,
                         frac: bd.meanWithout / maxMean, good: !withIsBetter)
        }
        .padding(.top, 4)
    }

    private func breakdownBar(label: LocalizedStringKey, mean: Double, n: Int, frac: Double, good: Bool) -> some View {
        HStack(spacing: 11) {
            Text(label).font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                .frame(width: 108, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(theme.hairline)
                    Capsule().fill(good ? theme.dataRecovery : theme.inkTertiary.opacity(0.5))
                        .frame(width: max(4, geo.size.width * CGFloat(min(1, frac))))
                }
            }
            .frame(height: 10)
            Text("\(Int(mean.rounded()))").font(StrandFont.captionNumber).monospacedDigit()
                .foregroundStyle(theme.ink).frame(width: 34, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }

    private var datumText: String {
        let v = insight.datum.value
        let sign = v > 0 ? "+" : (v < 0 ? "−" : "")
        let mag = abs(v) >= 10 ? String(Int(abs(v).rounded())) : String(format: "%.1f", abs(v))
        return "\(sign)\(mag) \(insight.datum.unit)"
    }

    private var datumColor: Color {
        guard insight.kind == .behavior else { return theme.ink }
        return BucleFormat.isGood(insight) ? theme.dataRecovery : theme.critical
    }

    private func significanceText(_ p: Double, sig: Bool, kind: InsightKind) -> String {
        let pStr = p < 0.01 ? "p < 0.01" : String(format: "p = %.2f", p)
        // Daily metric series are autocorrelated, so a cross-metric correlation's p overstates certainty:
        // never stamp it "significant" (mirrors InsightsView's discipline). Behavior with/without
        // comparisons are the less-dependent case the engine does flag.
        let word = (kind != .correlation && sig) ? String(localized: "significant") : String(localized: "exploratory")
        return "\(pStr) · \(word)"
    }

    private var confidenceTitle: String {
        switch insight.confidence {
        case .candidate: return String(localized: "Candidate — no experiment yet")
        case .proven:    return String(localized: "Proven by your experiment")
        case .medium:    return String(localized: "A read of your data")
        }
    }

    private var confidenceBody: String {
        switch insight.confidence {
        case .candidate: return String(localized: "It's a strong association in your data, but not proof of cause. An experiment can promote it to «proven».")
        case .proven:    return String(localized: "An N-of-1 experiment confirmed this effect for you.")
        case .medium:    return String(localized: "An observed value from your history, not a claim of cause.")
        }
    }
}

// MARK: Efectos de tus hábitos (explorer)

/// Carries the «Efectos» content's measured natural height up so its detent fits it exactly (FER-438).
private struct EfectosSheetHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct EfectosExplorerSheet: View {
    let behaviors: [Insight]
    let theme: InstrumentoTheme
    let onPick: (Insight) -> Void

    @State private var metric: String = "Recuperación"
    /// Natural height of the content, so the sheet opens just as tall as it needs (FER-438).
    @State private var contentHeight: CGFloat = 0

    /// Outcome metrics present, in the engine's canonical order (`InsightEngine.Outcome.allCases`,
    /// FER-353) so this list can't drift from the typed source.
    private var metrics: [String] {
        let present = Set(behaviors.map { $0.datum.metric })
        return InsightEngine.Outcome.allCases.map(\.label).filter { present.contains($0) }
    }

    private var rows: [Insight] {
        behaviors.filter { $0.datum.metric == metric }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoopMetrics.gap) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Habit effects").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                    Text("How each habit moves a metric, across your whole history. Associations, not cause.")
                        .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if metrics.count > 1 {
                    SegmentedPillControl(metrics, selection: $metric, theme: theme) { $0 }
                        .padding(.vertical, 4)
                }

                ForEach(Array(rows.enumerated()), id: \.offset) { _, insight in
                    Button { onPick(insight) } label: {
                        HStack(alignment: .center) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(BucleFormat.behaviorName(insight)).font(StrandFont.headline)
                                    .foregroundStyle(theme.ink)
                                Text("\(insight.evidence.n) nights").font(StrandFont.footnote)
                                    .foregroundStyle(theme.inkTertiary)
                            }
                            Spacer()
                            effectBadge(insight)
                            Image(systemName: "chevron.right").font(.system(size: 15))
                                .foregroundStyle(theme.inkTertiary).padding(.leading, 10)
                        }
                        .padding(.vertical, 12)
                        .overlay(alignment: .top) { Rectangle().fill(theme.hairline).frame(height: 0.5) }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(NoopMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GeometryReader { g in
                Color.clear.preference(key: EfectosSheetHeightKey.self, value: g.size.height)
            })
        }
        .background(theme.paper.ignoresSafeArea())
        .onPreferenceChange(EfectosSheetHeightKey.self) { contentHeight = $0 }
        // Open at the content's natural height (no full-screen for a few rows); «.large» stays for long lists.
        .presentationDetents(contentHeight > 0 ? [.height(contentHeight), .large] : [.large])
        .presentationDragIndicator(.visible)
        .onAppear { if let first = metrics.first, !metrics.contains(metric) { metric = first } }
    }

    private func effectBadge(_ insight: Insight) -> some View {
        let value = insight.datum.value
        let arrow = value > 0 ? "arrow.up" : (value < 0 ? "arrow.down" : "arrow.right")
        return HStack(spacing: 6) {
            Image(systemName: arrow).font(.system(size: 12, weight: .semibold))
            Text(BucleFormat.effectMagnitude(insight)).font(StrandFont.number(16)).monospacedDigit()
        }
        .foregroundStyle(BucleFormat.isGood(insight) ? theme.positiveText : theme.critical)
    }
}

// MARK: Anota tu día (Sí/No journal)

struct AnotaTuDiaSheet: View {
    let theme: InstrumentoTheme
    let onChanged: () -> Void

    @EnvironmentObject var repo: Repository
    @StateObject private var catalog = JournalCatalogStore()

    /// 0 = hoy … 13 = hace 13 días. Editable solo 0/1; los demás son solo lectura (FER-313).
    @State private var dayOffset = 0
    @State private var answers: [String: Bool] = [:]
    @State private var importedQuestions: [String] = []
    /// Offsets (0…13) con algún hábito anotado — marca el puntito en la tira.
    @State private var daysWithData: Set<Int> = []

    /// Cuántos días hacia atrás muestra la tira (Hoy + 13).
    private static let historyDays = 14
    /// Solo Hoy y Ayer se pueden editar; el resto se ve en solo lectura.
    private var isEditable: Bool { dayOffset <= 1 }

    private func dayKey(_ offset: Int) -> String {
        Repository.localDayKey(Calendar.current.date(byAdding: .day, value: -offset, to: Date()) ?? Date())
    }
    private var dayKey: String { dayKey(dayOffset) }

    private var questions: [String] {
        JournalCatalogStore.mergeCatalog(imported: importedQuestions, custom: catalog.customQuestions)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoopMetrics.gap) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Log your day").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                    Spacer()
                    if !isEditable {
                        Text("Read-only").font(StrandFont.captionNumber).foregroundStyle(theme.inkTertiary)
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .overlay(Capsule().stroke(theme.hairlineStrong, lineWidth: 1))
                    }
                }

                dayStrip

                HStack(spacing: 6) {
                    Image(systemName: isEditable ? "pencil" : "lock")
                        .font(.system(size: 12)).foregroundStyle(theme.inkTertiary)
                    Text(isEditable ? "What you don't mark counts as “No”."
                                    : "Only Today and Yesterday can be edited. Older days stay fixed.")
                        .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 2).padding(.bottom, 4)

                ForEach(questions, id: \.self) { q in
                    HStack {
                        Text(BucleFormat.shortLabel(q)).font(StrandFont.body).foregroundStyle(theme.ink)
                        Spacer()
                        answerPill("Yes", q: q, value: true)
                        answerPill("No", q: q, value: false)
                    }
                    .padding(.vertical, 11)
                    .overlay(alignment: .top) { Rectangle().fill(theme.hairline).frame(height: 0.5) }
                }
            }
            .padding(NoopMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.paper.ignoresSafeArea())
        .task { await reload(scanHistory: true) }
    }

    // MARK: Day strip

    private var dayStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(0..<Self.historyDays, id: \.self) { offset in
                    dayCell(offset)
                }
            }
            .padding(.vertical, 1)
        }
    }

    private func dayCell(_ offset: Int) -> some View {
        let sel = dayOffset == offset
        let date = Calendar.current.date(byAdding: .day, value: -offset, to: Date()) ?? Date()
        return Button {
            dayOffset = offset
            Task { await reload(scanHistory: false) }
        } label: {
            VStack(spacing: 2) {
                Text(dayName(offset, date)).font(.system(size: 11, weight: .medium))
                    .textCase(.uppercase)
                    .foregroundStyle(sel ? theme.paper : theme.inkTertiary)
                Text(Self.dayNumber.string(from: date)).font(StrandFont.captionNumber).monospacedDigit()
                    .foregroundStyle(sel ? theme.paper : theme.ink)
                Circle().fill(daysWithData.contains(offset) ? (sel ? theme.paper : theme.dataRecovery) : .clear)
                    .frame(width: 5, height: 5)
            }
            .frame(minWidth: 38)
            .padding(.horizontal, 9).padding(.vertical, 7)
            .background(sel ? theme.ink : Color.clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(sel ? theme.ink : theme.hairlineStrong, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(dayName(offset, date))
    }

    private func dayName(_ offset: Int, _ date: Date) -> String {
        switch offset {
        case 0:  return String(localized: "Today")
        case 1:  return String(localized: "Yesterday")
        default: return Self.weekday.string(from: date)
        }
    }

    // Dates follow the app language (FER-472): es → «JUE», en → «THU».
    private static let weekday: DateFormatter = {
        let f = DateFormatter(); f.locale = .current; f.dateFormat = "EEE"; return f
    }()
    private static let dayNumber: DateFormatter = {
        let f = DateFormatter(); f.locale = .current; f.dateFormat = "d"; return f
    }()

    // MARK: Answer pill (editable only on Hoy/Ayer)

    private func answerPill(_ label: LocalizedStringKey, q: String, value: Bool) -> some View {
        let sel = answers[q] == value
        return Button {
            guard isEditable else { return }
            Task {
                if sel { await repo.clearJournalAnswer(day: dayKey, question: q) }
                else { await repo.saveJournalAnswer(day: dayKey, question: q, answeredYes: value) }
                await reload(scanHistory: true)
                onChanged()
            }
        } label: {
            Text(label).font(StrandFont.captionNumber)
                .foregroundStyle(sel ? theme.paper : theme.inkSecondary)
                .frame(minWidth: 30)
                .padding(.horizontal, 13).padding(.vertical, 5)
                .background(sel ? theme.ink : Color.clear, in: Capsule())
                .overlay(Capsule().stroke(sel ? theme.ink : theme.hairlineStrong, lineWidth: 1))
                .opacity(isEditable || sel ? 1 : 0.55)
        }
        .buttonStyle(.plain)
        .disabled(!isEditable)
    }

    private func reload(scanHistory: Bool) async {
        async let importedTask = repo.importedJournalEntries()
        async let answersTask = repo.nativeJournalAnswers(day: dayKey)
        let imported = await importedTask
        let a = await answersTask
        let importedQs = NSOrderedSet(array: imported.map(\.question)).array as? [String] ?? []

        // Which of the 14 days carry any logged answer — drives the strip dots. Only scanned when the
        // set may have changed (open / after an edit), not on plain day selection. Sequential: these
        // are cheap SQLite reads run once on open, not a hot path.
        var withData: Set<Int>? = nil
        if scanHistory {
            var out = Set<Int>()
            for offset in 0..<Self.historyDays {
                if !(await repo.nativeJournalAnswers(day: dayKey(offset)).isEmpty) { out.insert(offset) }
            }
            withData = out
        }

        await MainActor.run {
            self.importedQuestions = importedQs
            self.answers = a
            if let withData { self.daysWithData = withData }
        }
    }
}

// MARK: - Shared formatting

enum BucleFormat {
    static func kindLabel(_ kind: InsightKind) -> String {
        switch kind {
        case .behavior:        return String(localized: "Behavior")
        case .correlation:     return String(localized: "Relationship between metrics")
        case .nightAnomaly:    return String(localized: "Anomaly · last night")
        case .trend:           return String(localized: "Trend")
        case .forecast:        return String(localized: "Forecast")
        case .sleepRegularity: return String(localized: "Sleep regularity")
        case .sleepDebt:       return String(localized: "Sleep debt")
        case .activityCost:    return String(localized: "A sport's cost")
        case .trainingLoad:    return String(localized: "Training load")
        case .fitnessAge:      return String(localized: "Fitness age")
        }
    }

    /// The behavior's es-MX display label. Prefers the structured `lever.behavior` (FER-307); falls
    /// back to parsing the engine's title template. The raw behavior is the journal QUESTION (data) →
    /// mapped to a short Spanish label via `JournalCatalogStore.esLabel` (FER-312).
    static func behaviorName(_ insight: Insight) -> String {
        if let raw = insight.lever?.behavior, !raw.isEmpty {
            return JournalCatalogStore.esLabel(for: raw)
        }
        let parts = insight.title.components(separatedBy: "‘")
        if parts.count > 1 {
            let after = parts[1].components(separatedBy: "’")
            if let name = after.first, !name.isEmpty {
                return JournalCatalogStore.esLabel(for: name)
            }
        }
        return insight.title
    }

    /// The es-MX display label for a journal question; the question string itself (the engine's join
    /// key) is never changed (FER-312).
    static func shortLabel(_ question: String) -> String { JournalCatalogStore.esLabel(for: question) }

    /// The es-MX display label for a stored behavior key (an experiment row's `behavior` is the journal
    /// question). Same mapping `behaviorName` uses for a lever, without needing an `Insight` stub.
    static func behaviorLabel(_ raw: String) -> String {
        raw.isEmpty ? "" : JournalCatalogStore.esLabel(for: raw)
    }

    static func isGood(_ insight: Insight) -> Bool {
        let higherBetter = insight.datum.metric != "FC en reposo"
        let up = insight.datum.value > 0
        return up == higherBetter
    }

    /// The unsigned effect magnitude + unit, e.g. "12 pts" / "1.4 ms" (the arrow carries the sign).
    static func effectMagnitude(_ insight: Insight) -> String {
        let v = abs(insight.datum.value)
        let mag = v >= 10 ? String(Int(v.rounded())) : String(format: "%.1f", v)
        return "\(mag) \(insight.datum.unit)"
    }

    /// The per-metric data hue (FER-147) for a finding's datum — color stays on the measured series.
    static func metricColor(_ metric: String, _ theme: InstrumentoTheme) -> Color {
        switch metric {
        case "HRV":                                  return theme.dataHrv
        case "Sueño", "Deuda de sueño",
             "Regularidad de sueño":                 return theme.dataSleep
        case "FC en reposo":                         return theme.dataHeart
        default:                                     return theme.dataRecovery
        }
    }

    /// Whether the WITH-habit mean is the better outcome, respecting the metric's direction (only resting
    /// HR is lower-is-better). The one place this rule lives, shared by the lever dumbbell and the detail
    /// sheet's breakdown bars so they can never disagree about which side wins.
    static func withIsBetter(metric: String, meanWith: Double, meanWithout: Double) -> Bool {
        let higherBetter = metric != "FC en reposo"
        return higherBetter ? (meanWith >= meanWithout) : (meanWith <= meanWithout)
    }

    /// The drawn mark for a finding, by kind: relación (two intertwined curves), tendencia (the recovery
    /// trajectory + head dot), anomalía (a spike on a quiet baseline). Other kinds draw nothing.
    @ViewBuilder static func findingGlyph(_ insight: Insight, trendSpark: [Double],
                                          theme: InstrumentoTheme) -> some View {
        switch insight.kind {
        case .correlation:
            InsightGlyph(kind: .relation, primary: theme.dataRecovery, secondary: theme.dataHrv, theme: theme)
        case .trend:
            InsightGlyph(kind: .trend, values: trendSpark,
                         primary: metricColor(insight.datum.metric, theme), secondary: theme.dataHrv, theme: theme)
        case .nightAnomaly:
            InsightGlyph(kind: .anomaly,
                         primary: metricColor(insight.datum.metric, theme), secondary: theme.dataHrv, theme: theme)
        default:
            EmptyView()
        }
    }

    static func magnitudeWord(_ d: Double) -> String {
        switch abs(d) {
        case ..<0.2:  return String(localized: "negligible")
        case ..<0.5:  return String(localized: "small")
        case ..<0.8:  return String(localized: "moderate")
        default:      return String(localized: "large")
        }
    }

    // MARK: Experiment verdict copy (FER-307)

    static func verdictHeadline(_ v: Verdict) -> String {
        switch v {
        case .sustained:    return String(localized: "It held up.")
        case .notSustained: return String(localized: "It didn't hold up this time.")
        case .insufficient: return String(localized: "Not enough signal.")
        }
    }

    static func verdictReading(_ v: Verdict, behavior: String, outcome: String,
                               adherent: Int, window: Int) -> String {
        switch v {
        case .sustained:
            return String(localized: "“\(behavior)” raised your \(outcome) this week. We marked it as proven in What works for you.")
        case .notSustained:
            return String(localized: "“\(behavior)” didn't move your \(outcome) this week. A week is weak evidence — you can try again.")
        case .insufficient:
            return String(localized: "You kept \(adherent) of \(window) days: not enough days to judge. Try another week, logging daily.")
        }
    }

    /// A signed effect for the verdict datum, e.g. "+8 pts" / "−1.4 ms".
    static func signedDelta(_ v: Double, unit: String) -> String {
        let sign = v > 0 ? "+" : (v < 0 ? "−" : "")
        let mag = abs(v) >= 10 ? String(Int(abs(v).rounded())) : String(format: "%.1f", abs(v))
        return "\(sign)\(mag) \(unit)"
    }
}

// MARK: - Start experiment (confirmation sheet, FER-307)

/// The brief confirmation a candidate lever opens before an experiment begins: why it's worth testing,
/// what's asked of the user over the window, and the verdict date. «Empezar» starts it; nothing runs
/// until then. The only color is the candidate's measured effect (the datum); «Empezar» is ink.
struct StartExperimentSheet: View {
    let insight: Insight
    let theme: InstrumentoTheme
    /// (behavior, outcome, expectedSign) → start. Async so the caller can persist + reload.
    let onStart: (String, String, Int) async -> Void

    @Environment(\.dismiss) private var dismiss
    private static let windowDays = 7

    /// The lever's RAW identity — the journal question and outcome the engine keyed it by. This is
    /// what gets persisted and later matched (adherence, candidate→proven), NOT the display name,
    /// which `BucleFormat.behaviorName` capitalizes (a lowercase question would never match).
    private var leverBehavior: String { insight.lever?.behavior ?? BucleFormat.behaviorName(insight) }
    private var leverOutcome: String { insight.lever?.outcome ?? insight.datum.metric }
    /// The capitalized name for visible copy only.
    private var displayName: String { BucleFormat.behaviorName(insight) }
    private var expectedSign: Int { insight.datum.value < 0 ? -1 : 1 }
    private var verdictDate: String {
        let end = Calendar.current.date(byAdding: .day, value: Self.windowDays, to: Date()) ?? Date()
        return Self.dateFormatter.string(from: end)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("New experiment").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                Text("Test “\(displayName)”")
                    .font(StrandFont.title2).foregroundStyle(theme.ink)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 8)

                (Text("In your data, “\(displayName)” goes with ")
                    + Text(BucleFormat.signedDelta(insight.datum.value, unit: insight.datum.unit))
                        .foregroundColor(theme.positiveText).bold()
                    + Text(" of \(leverOutcome). A week confirms it in your body."))
                    .font(StrandFont.body).foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 10)

                VStack(alignment: .leading, spacing: 13) {
                    stepRow(1, "Log each day whether you kept it, in “Log your day”.")
                    stepRow(2, "When it closes, we compare those days with your baseline.")
                    stepRow(3, "If the effect holds, it becomes proven.")
                }
                .padding(.top, 18)

                HStack(alignment: .firstTextBaseline) {
                    Text("For \(Self.windowDays) days").font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                    Spacer()
                    Text("verdict on \(verdictDate)").font(StrandFont.subhead).foregroundStyle(theme.ink)
                }
                .padding(.top, 18).padding(.top, 14)
                .overlay(alignment: .top) { Rectangle().fill(theme.hairline).frame(height: 0.5) }

                Button {
                    Task { await onStart(leverBehavior, leverOutcome, expectedSign) }
                } label: {
                    Text("Start").font(StrandFont.headline).foregroundStyle(theme.paper)
                        .frame(maxWidth: .infinity).padding(15)
                        .background(theme.ink, in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
                }
                .buttonStyle(.plain).padding(.top, 18)

                Button { dismiss() } label: {
                    Text("Not now").font(StrandFont.subhead).foregroundStyle(theme.inkTertiary)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain).padding(.top, 13)
            }
            .padding(NoopMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.paper.ignoresSafeArea())
    }

    private func stepRow(_ n: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 11) {
            Text("\(n)").font(StrandFont.captionNumber).foregroundStyle(theme.inkTertiary)
                .frame(minWidth: 14, alignment: .leading)
            Text(text).font(StrandFont.body).foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // Date follows the app language (FER-472).
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.locale = .current; f.dateFormat = "EEE d MMM"
        return f
    }()
}

// MARK: - Info explainer (On-device pill + the ⓘ on each section)

/// One friendly es-MX explainer the Bucle opens — for the «On-device» pill and the ⓘ on each
/// section. A glyph, a title and a body, in «Instrumento» (FER-312).
struct BucleInfo: Identifiable {
    let id: String
    let systemImage: String
    let title: LocalizedStringKey
    let body: LocalizedStringKey

    static let onDevice = BucleInfo(
        id: "on-device", systemImage: "cpu", title: "Everything on your phone",
        body: "Cénit computes your recovery, your findings and your levers here, on your iPhone — no cloud, no account, no server.\n\nThe only thing that goes to the internet is «Ask your data», and only if you connect your own AI key.")

    static let loQueFunciona = BucleInfo(
        id: "lo-que-funciona", systemImage: "flask", title: "What works for you",
        body: "We compare your days with and without each habit you log. If the difference is real in your numbers, it shows up here as a lever.\n\nThey're candidates until an experiment proves them. Everything is computed on your phone.")

    static let hallazgos = BucleInfo(
        id: "hallazgos", systemImage: "dot.radiowaves.left.and.right", title: "Findings",
        body: "Your phone reviews your nights and flags three things: what's out of the ordinary (an anomaly), what's trending (up or down), and which metrics move together.\n\nAll from your own data.")

    static let efectos = BucleInfo(
        id: "efectos", systemImage: "chart.bar", title: "Habit effects",
        body: "Here you explore your whole history: pick a metric (recovery, HRV, sleep, resting HR) and see how each habit you log moves it, on average.\n\nIt's the deep version of «What works for you». Associations, not cause.")
}

struct BucleInfoSheet: View {
    let info: BucleInfo
    let theme: InstrumentoTheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Image(systemName: info.systemImage)
                    .font(.system(size: 26)).foregroundStyle(theme.inkTertiary)
                Text(info.title)
                    .font(StrandFont.title2).foregroundStyle(theme.ink)
                    .padding(.top, 12)
                Text(info.body)
                    .font(StrandFont.body).foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
            }
            .padding(NoopMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.paper.ignoresSafeArea())
        .presentationDetents([.medium])
    }
}

// MARK: - Experiment detail (FER-462 / 2b)
//
// The full view of a running experiment: day N of M, the racha + «arco», the «recuperación durante el
// experimento» effect line vs your «media antes», the marked daily check-in, and cancel. Loads its own
// data (so it stays fresh after a check-in) via the shared `Repository.experimentProgress/effect`.

struct ExperimentDetailSheet: View {
    let row: ExperimentRow
    let theme: InstrumentoTheme
    let onChanged: () -> Void

    @EnvironmentObject var repo: Repository
    @Environment(\.dismiss) private var dismiss
    @State private var progress: ExperimentProgress?
    @State private var effect: ExperimentEffect?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                header
                if let p = progress {
                    dayProgress(p)
                    racha(p)
                }
                effectBlock
                if let p = progress, p.pendingCheckIn { checkIn }
                meta
                cancel
            }
            .padding(NoopMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.paper.ignoresSafeArea())
        .presentationDragIndicator(.visible)
        .task { await reload() }
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("On trial").instrumentoOverline().foregroundStyle(theme.dataRecovery)
            Text(BucleFormat.behaviorLabel(row.behavior))
                .font(.system(size: 28, weight: .semibold)).foregroundStyle(theme.ink)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 8)
            Text("on trial against your \(row.outcome)")
                .font(StrandFont.subhead).foregroundStyle(theme.inkTertiary).padding(.top, 4)
        }
    }

    private func dayProgress(_ p: ExperimentProgress) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Day \(p.elapsedDay)").font(.system(size: 40, weight: .semibold)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.6).foregroundStyle(theme.ink)
                Text("of \(row.windowDays)").font(StrandFont.subhead).foregroundStyle(theme.inkTertiary)
            }
            ProgressView(value: Double(p.elapsedDay), total: Double(row.windowDays))
                .tint(theme.dataRecovery).padding(.top, 12)
        }
    }

    @ViewBuilder private func racha(_ p: ExperimentProgress) -> some View {
        if p.supportsStreak {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Your streak").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "flame").font(.system(size: 11, weight: .medium))
                        Text("Best: \(p.streakBest)").font(StrandFont.captionNumber)
                    }
                    .foregroundStyle(theme.inkTertiary)
                }
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text("\(p.streakCurrent)").font(StrandFont.number(30)).foregroundStyle(theme.ink)
                    Text("nights in a row · kept \(p.adherent) of \(p.elapsedDay)")
                        .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 9)
                StreakArc(filled: p.streakCurrent, total: row.windowDays, theme: theme, height: 22)
                    .padding(.top, 12)
            }
        }
    }

    @ViewBuilder private var effectBlock: some View {
        if let e = effect, e.values.count >= 2 {
            VStack(alignment: .leading, spacing: 0) {
                Text("Your \(outcomePhrase) during the experiment")
                    .instrumentoOverline().foregroundStyle(theme.inkTertiary)
                ExperimentEffectChart(values: e.values, baseline: e.beforeMean,
                                      accent: BucleFormat.metricColor(row.outcome, theme), theme: theme)
                    .padding(.top, 12)
                HStack {
                    Text("— — average before").font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                    Spacer()
                    if let d = e.delta {
                        HStack(spacing: 4) {
                            Text(BucleFormat.signedDelta(d, unit: e.unit))
                                .font(StrandFont.mono(15, weight: .semibold))
                                .foregroundStyle(deltaIsGood(d) ? theme.positiveText : theme.critical)
                            Text("vs before").font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
    }

    private var checkIn: some View {
        // The journal QUESTION is data; show its localized short label, never the raw English key (FER-472).
        let question = row.behavior.isEmpty ? String(localized: "Did you keep it today?")
                                            : BucleFormat.behaviorLabel(row.behavior)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Circle().fill(theme.dataRecovery).frame(width: 8, height: 8)
                Text("Pending today").instrumentoOverline().foregroundStyle(theme.dataRecovery)
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(question).font(StrandFont.headline).foregroundStyle(theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                checkInToggle("Yes", answeredYes: true)
                checkInToggle("No", answeredYes: false)
            }
            .padding(.top, 11)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(theme.dataRecovery, lineWidth: 1.5))
    }

    private func checkInToggle(_ label: LocalizedStringKey, answeredYes: Bool) -> some View {
        Button {
            Task {
                await repo.saveJournalAnswer(day: Repository.localDayKey(Date()),
                                             question: row.behavior, answeredYes: answeredYes)
                await reload()
                onChanged()
            }
        } label: {
            Text(label).font(StrandFont.captionNumber).foregroundStyle(theme.inkSecondary)
                .frame(minWidth: 30)
                .padding(.horizontal, 15).padding(.vertical, 7)
                .overlay(Capsule().stroke(theme.hairlineStrong, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var meta: some View {
        HStack(spacing: 8) {
            Image(systemName: "calendar").font(.system(size: 15)).foregroundStyle(theme.inkTertiary)
            Text("Verdict on ").font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                + Text(progress?.verdictDate ?? "—").font(StrandFont.subhead).foregroundStyle(theme.ink).bold()
        }
    }

    private var cancel: some View {
        Button {
            Task { await repo.cancelExperiment(row); onChanged(); dismiss() }
        } label: {
            Text("Cancel experiment").font(StrandFont.subhead).foregroundStyle(theme.inkTertiary)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    // MARK: Data

    private func reload() async {
        let today = Repository.localDayKey(Date())
        let p = await repo.experimentProgress(row, today: today)
        let e = await repo.experimentEffect(row, today: today)
        await MainActor.run { progress = p; effect = e }
    }

    /// Localized phrase for the outcome in «Your <…> during the experiment». Recovery/sleep get a
    /// localized word; HRV / resting HR keep the engine's data label (localized at the engine layer, FER-418).
    private var outcomePhrase: String {
        switch row.outcome {
        case "Recuperación": return String(localized: "recovery")
        case "Sueño":        return String(localized: "sleep")
        default:             return row.outcome   // HRV / FC en reposo stay as-is (engine data)
        }
    }

    /// Whether a delta is an improvement, respecting the metric's direction (only resting HR is lower-better).
    private func deltaIsGood(_ d: Double) -> Bool {
        row.outcome == "FC en reposo" ? d <= 0 : d >= 0
    }
}

// MARK: - Diseña tu propio experimento (free builder, FER-468)
//
// Start an experiment on a habit you choose — not one Cénit detected. Pick a behavior from your journal
// catalog, an outcome metric, and a window (7/14/21 days), then start it. Reuses
// `repo.startExperiment`; the verdict + racha + check-in flow it joins is identical to a lever-born one.
// The expected direction defaults to «improvement» (the builder is framed as adopting a good habit):
// up for recovery/HRV/sleep, down for resting HR.

struct DisenaExperimentoSheet: View {
    let theme: InstrumentoTheme
    /// (behavior, outcome, expectedSign, windowDays) → start. Async so the caller can persist + reload.
    let onStart: (String, String, Int, Int) async -> Void

    @EnvironmentObject var repo: Repository
    @Environment(\.dismiss) private var dismiss
    @StateObject private var catalog = JournalCatalogStore()

    @State private var importedQuestions: [String] = []
    @State private var behavior: String? = nil
    @State private var outcome: String = InsightEngine.Outcome.recovery.label
    @State private var windowDays: Int = 7

    private var behaviors: [String] {
        JournalCatalogStore.mergeCatalog(imported: importedQuestions, custom: catalog.customQuestions)
    }
    private var outcomes: [String] { InsightEngine.Outcome.allCases.map(\.label) }
    /// «Improvement» direction: up for higher-is-better metrics, down for resting HR.
    private var expectedSign: Int { outcome == "FC en reposo" ? -1 : 1 }
    private var verdictDate: String {
        let end = Calendar.current.date(byAdding: .day, value: windowDays, to: Date()) ?? Date()
        return ExperimentDates.longES.string(from: end)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("New experiment").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                    Text("Design your own experiment")
                        .font(StrandFont.title2).foregroundStyle(theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Pick a habit you want to adopt and measure it against a metric. We confirm it by comparing those days with your baseline.")
                        .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Habit
                VStack(alignment: .leading, spacing: 0) {
                    Text("The habit").instrumentoOverline().foregroundStyle(theme.inkTertiary).padding(.bottom, 2)
                    if behaviors.isEmpty {
                        Text("You don't have habits to test yet. Log a few days first.")
                            .font(StrandFont.subhead).foregroundStyle(theme.inkTertiary)
                            .padding(.vertical, 12)
                    } else {
                        ForEach(behaviors, id: \.self) { q in
                            Button { behavior = q } label: {
                                HStack {
                                    Text(BucleFormat.behaviorLabel(q)).font(StrandFont.body).foregroundStyle(theme.ink)
                                    Spacer()
                                    Image(systemName: behavior == q ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 18))
                                        .foregroundStyle(behavior == q ? theme.dataRecovery : theme.hairlineStrong)
                                }
                                .padding(.vertical, 11)
                                .overlay(alignment: .top) { Rectangle().fill(theme.hairline).frame(height: 0.5) }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Metric
                VStack(alignment: .leading, spacing: 8) {
                    Text("The metric").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                    SegmentedPillControl(outcomes, selection: $outcome, theme: theme) { $0 }
                }

                // Window
                VStack(alignment: .leading, spacing: 8) {
                    Text("The window").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                    SegmentedPillControl([7, 14, 21], selection: $windowDays, theme: theme) { String(localized: "\($0) days") }
                }

                HStack {
                    Text("Log each day whether you kept it").font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                    Spacer()
                    Text("verdict on \(verdictDate)").font(StrandFont.subhead).foregroundStyle(theme.ink)
                }
                .padding(.top, 4)

                Button {
                    if let behavior { Task { await onStart(behavior, outcome, expectedSign, windowDays) } }
                } label: {
                    Text("Start").font(StrandFont.headline)
                        .foregroundStyle(behavior == nil ? theme.inkTertiary : theme.paper)
                        .frame(maxWidth: .infinity).padding(15)
                        .background(behavior == nil ? theme.surface : theme.ink,
                                    in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous)
                            .stroke(theme.hairlineStrong, lineWidth: behavior == nil ? 1 : 0))
                }
                .buttonStyle(.plain).disabled(behavior == nil)

                Button { dismiss() } label: {
                    Text("Not now").font(StrandFont.subhead).foregroundStyle(theme.inkTertiary)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
            .padding(NoopMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.paper.ignoresSafeArea())
        .task {
            let imported = await repo.importedJournalEntries()
            let qs = NSOrderedSet(array: imported.map(\.question)).array as? [String] ?? []
            await MainActor.run { importedQuestions = qs }
        }
    }
}

#endif
