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
                    evidenceRow("Muestra", "\(insight.evidence.n)")
                    if let p = insight.evidence.pAdjusted ?? insight.evidence.pValue {
                        evidenceRow("Significancia", significanceText(p, sig: insight.evidence.significant, kind: insight.kind))
                    }
                    if let d = insight.evidence.effectSize {
                        evidenceRow("Tamaño de efecto", String(format: "%.2f · %@", d, BucleFormat.magnitudeWord(d)))
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
                            Text("Probar esta idea una semana").font(StrandFont.headline)
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

    private func evidenceRow(_ key: String, _ value: String) -> some View {
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
            breakdownBar(label: "Con el hábito", mean: bd.meanWith, n: bd.nWith,
                         frac: bd.meanWith / maxMean, good: withIsBetter)
            breakdownBar(label: "Sin el hábito", mean: bd.meanWithout, n: bd.nWithout,
                         frac: bd.meanWithout / maxMean, good: !withIsBetter)
        }
        .padding(.top, 4)
    }

    private func breakdownBar(label: String, mean: Double, n: Int, frac: Double, good: Bool) -> some View {
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
        .accessibilityLabel("\(label): \(Int(mean.rounded())), \(n) días")
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
        // never stamp it "significativo" (mirrors InsightsView's discipline). Behavior with/without
        // comparisons are the less-dependent case the engine does flag.
        if kind == .correlation { return "\(pStr) · exploratorio" }
        return sig ? "\(pStr) · significativo" : "\(pStr) · exploratorio"
    }

    private var confidenceTitle: String {
        switch insight.confidence {
        case .candidate: return "Candidato — aún sin experimento"
        case .proven:    return "Probado por tu experimento"
        case .medium:    return "Lectura de tus datos"
        }
    }

    private var confidenceBody: String {
        switch insight.confidence {
        case .candidate: return "Es una asociación fuerte en tus datos, pero no prueba causa. Un experimento puede ascenderla a «probada»."
        case .proven:    return "Un experimento N-of-1 confirmó este efecto en ti."
        case .medium:    return "Un dato observado de tu historial, no una afirmación de causa."
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
                    Text("Efectos de tus hábitos").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                    Text("Cómo cada hábito mueve una métrica, en todo tu historial. Asociaciones, no causa.")
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
                                Text("\(insight.evidence.n) noches").font(StrandFont.footnote)
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
                    Text("Anota tu día").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                    Spacer()
                    if !isEditable {
                        Text("Solo lectura").font(StrandFont.captionNumber).foregroundStyle(theme.inkTertiary)
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .overlay(Capsule().stroke(theme.hairlineStrong, lineWidth: 1))
                    }
                }

                dayStrip

                HStack(spacing: 6) {
                    Image(systemName: isEditable ? "pencil" : "lock")
                        .font(.system(size: 12)).foregroundStyle(theme.inkTertiary)
                    Text(isEditable ? "Lo que no marques se asume “No”."
                                    : "Solo Hoy y Ayer se pueden editar. Los días viejos quedan fijos.")
                        .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 2).padding(.bottom, 4)

                ForEach(questions, id: \.self) { q in
                    HStack {
                        Text(BucleFormat.shortLabel(q)).font(StrandFont.body).foregroundStyle(theme.ink)
                        Spacer()
                        answerPill("Sí", q: q, value: true)
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
        case 0:  return "Hoy"
        case 1:  return "Ayer"
        default: return Self.weekday.string(from: date)
        }
    }

    private static let weekday: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "es_MX"); f.dateFormat = "EEE"; return f
    }()
    private static let dayNumber: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "es_MX"); f.dateFormat = "d"; return f
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
        case .behavior:        return "Comportamiento"
        case .correlation:     return "Relación entre métricas"
        case .nightAnomaly:    return "Anomalía · anoche"
        case .trend:           return "Tendencia"
        case .forecast:        return "Pronóstico"
        case .sleepRegularity: return "Regularidad de sueño"
        case .sleepDebt:       return "Deuda de sueño"
        case .activityCost:    return "Costo de un deporte"
        case .trainingLoad:    return "Carga de entrenamiento"
        case .fitnessAge:      return "Edad fitness"
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

    /// The short lead clause of a signal's read, for the compact «Señales» chip — the engine's `detail`
    /// is a full clause ("por encima de tu base — bien recuperado" / "en zona buena (agudo:crónico 1.05)");
    /// this trims to the part before the dash / parenthesis / separator so the 3-up row stays glanceable.
    /// Shows the engine's OWN words (no fabricated copy) — the full read lives in the explainer sheet.
    static func signalShortDetail(_ detail: String) -> String {
        var s = detail
        for sep in ["—", " (", "(", " · ", ": "] {
            if let r = s.range(of: sep) { s = String(s[..<r.lowerBound]) }
        }
        return s.trimmingCharacters(in: .whitespaces)
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
        case ..<0.2:  return "insignificante"
        case ..<0.5:  return "chico"
        case ..<0.8:  return "moderado"
        default:      return "grande"
        }
    }

    /// The es-MX verdict phrase for a readiness level — the «Decisión de hoy» hero word. Shared by the
    /// Bucle hero and its explainer. nil (no read yet) reads as «Día parejo.»; the hero never shows it.
    static func verdictWord(_ level: ReadinessEngine.Level?) -> String {
        switch level {
        case .primed:       return "Empuja hoy."
        case .balanced:     return "Día parejo."
        case .strained:     return "Ve con calma."
        case .rundown:      return "Hoy toca descansar."
        case .insufficient: return "Aún calibrando."
        case nil:           return "Día parejo."
        }
    }

    // MARK: Experiment verdict copy (FER-307)

    static func verdictHeadline(_ v: Verdict) -> String {
        switch v {
        case .sustained:    return "Se sostuvo."
        case .notSustained: return "No se sostuvo esta vez."
        case .insufficient: return "Sin señal suficiente."
        }
    }

    static func verdictReading(_ v: Verdict, behavior: String, outcome: String,
                               adherent: Int, window: Int) -> String {
        switch v {
        case .sustained:
            return "“\(behavior)” subió tu \(outcome) en la semana. La marcamos como probada en Lo que funciona en ti."
        case .notSustained:
            return "“\(behavior)” no movió tu \(outcome) en esta semana. Una semana es poca evidencia — puedes volver a intentarlo."
        case .insufficient:
            return "Cumpliste \(adherent) de \(window) días: faltaron días para juzgar. Inténtalo otra semana anotando a diario."
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
                Text("Nuevo experimento").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                Text("Probar “\(displayName)”")
                    .font(StrandFont.title2).foregroundStyle(theme.ink)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 8)

                (Text("En tus datos, “\(displayName)” va con ")
                    + Text(BucleFormat.signedDelta(insight.datum.value, unit: insight.datum.unit))
                        .foregroundColor(theme.positiveText).bold()
                    + Text(" de \(leverOutcome). Una semana lo confirma en tu cuerpo."))
                    .font(StrandFont.body).foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 10)

                VStack(alignment: .leading, spacing: 13) {
                    stepRow(1, "Anota cada día si lo cumpliste, en “Anota tu día”.")
                    stepRow(2, "Al cerrar, comparamos esos días con tu base.")
                    stepRow(3, "Si el efecto se sostiene, queda probada.")
                }
                .padding(.top, 18)

                HStack(alignment: .firstTextBaseline) {
                    Text("Durante \(Self.windowDays) días").font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                    Spacer()
                    Text("veredicto el \(verdictDate)").font(StrandFont.subhead).foregroundStyle(theme.ink)
                }
                .padding(.top, 18).padding(.top, 14)
                .overlay(alignment: .top) { Rectangle().fill(theme.hairline).frame(height: 0.5) }

                Button {
                    Task { await onStart(leverBehavior, leverOutcome, expectedSign) }
                } label: {
                    Text("Empezar").font(StrandFont.headline).foregroundStyle(theme.paper)
                        .frame(maxWidth: .infinity).padding(15)
                        .background(theme.ink, in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
                }
                .buttonStyle(.plain).padding(.top, 18)

                Button { dismiss() } label: {
                    Text("Ahora no").font(StrandFont.subhead).foregroundStyle(theme.inkTertiary)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain).padding(.top, 13)
            }
            .padding(NoopMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.paper.ignoresSafeArea())
    }

    private func stepRow(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 11) {
            Text("\(n)").font(StrandFont.captionNumber).foregroundStyle(theme.inkTertiary)
                .frame(minWidth: 14, alignment: .leading)
            Text(text).font(StrandFont.body).foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "es_MX"); f.dateFormat = "EEE d MMM"
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
        id: "on-device", systemImage: "cpu", title: "Todo en tu teléfono",
        body: "Cénit calcula tu recuperación, tus hallazgos y tus palancas aquí, en tu iPhone — sin nube, sin cuenta, sin servidor.\n\nLo único que sale a internet es «Pregúntale a tus datos», y solo si conectas tu propia clave de IA.")

    static let loQueFunciona = BucleInfo(
        id: "lo-que-funciona", systemImage: "flask", title: "Lo que funciona en ti",
        body: "Comparamos tus días con y sin cada hábito que anotas. Si la diferencia es real en tus números, aparece aquí como una palanca.\n\nSon candidatos hasta que un experimento los pruebe. Todo se calcula en tu teléfono.")

    static let hallazgos = BucleInfo(
        id: "hallazgos", systemImage: "dot.radiowaves.left.and.right", title: "Hallazgos",
        body: "Tu teléfono revisa tus noches y te avisa de tres cosas: lo que se sale de lo normal (una anomalía), lo que viene en tendencia (subiendo o bajando), y qué métricas se mueven juntas.\n\nTodo a partir de tus propios datos.")

    static let efectos = BucleInfo(
        id: "efectos", systemImage: "chart.bar", title: "Efectos de tus hábitos",
        body: "Aquí exploras todo tu historial: elige una métrica (recuperación, HRV, sueño, FC en reposo) y mira cómo cada hábito que anotas la mueve, en promedio.\n\nEs la versión a fondo de «Lo que funciona en ti». Asociaciones, no causa.")
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

#endif
