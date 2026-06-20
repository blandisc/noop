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
                        evidenceRow("Significancia", significanceText(p, sig: insight.evidence.significant))
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
        let higherBetter = insight.datum.metric != "FC en reposo"
        let withIsBetter = higherBetter ? (bd.meanWith >= bd.meanWithout) : (bd.meanWith <= bd.meanWithout)
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

    private func significanceText(_ p: Double, sig: Bool) -> String {
        let pStr = p < 0.01 ? "p < 0.01" : String(format: "p = %.2f", p)
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

// MARK: Hallazgos list

struct HallazgosListSheet: View {
    let insights: [Insight]
    let theme: InstrumentoTheme
    /// Recent recovery series for the trend sparkline (passed by the Bucle).
    var trendSpark: [Double] = []
    let onPick: (Insight) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Hallazgos").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                    Text("Lo que tus datos movieron, ordenado por relevancia.")
                        .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.bottom, 8)

                ForEach(Array(insights.enumerated()), id: \.offset) { _, insight in
                    Button { onPick(insight) } label: {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(BucleFormat.kindLabel(insight.kind)).instrumentoOverline()
                                    .foregroundStyle(theme.inkTertiary)
                                Text(insight.title).font(StrandFont.headline).foregroundStyle(theme.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(insight.reading).font(StrandFont.footnote).foregroundStyle(theme.inkSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                if insight.kind == .trend {
                                    BucleFormat.trendSparkline(trendSpark,
                                                               color: BucleFormat.metricColor(insight.datum.metric, theme))
                                        .padding(.top, 4)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 15))
                                .foregroundStyle(theme.inkTertiary).padding(.top, 2)
                        }
                        .padding(.vertical, 13)
                        .overlay(alignment: .top) { Rectangle().fill(theme.hairline).frame(height: 0.5) }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(NoopMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.paper.ignoresSafeArea())
    }
}

// MARK: Efectos de tus hábitos (explorer)

struct EfectosExplorerSheet: View {
    let behaviors: [Insight]
    let theme: InstrumentoTheme
    let onPick: (Insight) -> Void

    @State private var metric: String = "Recuperación"

    /// Outcome metrics present, in the engine's canonical order.
    private var metrics: [String] {
        let present = Set(behaviors.map { $0.datum.metric })
        return ["Recuperación", "HRV", "Sueño", "FC en reposo"].filter { present.contains($0) }
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
        }
        .background(theme.paper.ignoresSafeArea())
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

    @State private var dayOffset = 0           // 0 = hoy, 1 = ayer
    @State private var answers: [String: Bool] = [:]
    @State private var importedQuestions: [String] = []

    private var dayKey: String {
        Repository.localDayKey(Calendar.current.date(byAdding: .day, value: -dayOffset, to: Date()) ?? Date())
    }

    private var questions: [String] {
        JournalCatalogStore.mergeCatalog(imported: importedQuestions, custom: catalog.customQuestions)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoopMetrics.gap) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Anota tu día").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                    Spacer()
                    dayPill("Hoy", offset: 0)
                    dayPill("Ayer", offset: 1)
                }
                Text("Sobre la noche y el día que desembocan en esta mañana.")
                    .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 4)

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
        .task { await reload() }
    }

    private func dayPill(_ label: LocalizedStringKey, offset: Int) -> some View {
        let sel = dayOffset == offset
        return Button {
            dayOffset = offset
            Task { await reload() }
        } label: {
            Text(label).font(StrandFont.captionNumber)
                .foregroundStyle(sel ? theme.paper : theme.inkSecondary)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(sel ? theme.ink : Color.clear, in: Capsule())
                .overlay(Capsule().stroke(sel ? theme.ink : theme.hairlineStrong, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func answerPill(_ label: LocalizedStringKey, q: String, value: Bool) -> some View {
        let sel = answers[q] == value
        return Button {
            Task {
                if sel { await repo.clearJournalAnswer(day: dayKey, question: q) }
                else { await repo.saveJournalAnswer(day: dayKey, question: q, answeredYes: value) }
                await reload()
                onChanged()
            }
        } label: {
            Text(label).font(StrandFont.captionNumber)
                .foregroundStyle(sel ? theme.paper : theme.inkSecondary)
                .frame(minWidth: 30)
                .padding(.horizontal, 13).padding(.vertical, 5)
                .background(sel ? theme.ink : Color.clear, in: Capsule())
                .overlay(Capsule().stroke(sel ? theme.ink : theme.hairlineStrong, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func reload() async {
        async let importedTask = repo.importedJournalEntries()
        async let answersTask = repo.nativeJournalAnswers(day: dayKey)
        let imported = await importedTask
        let a = await answersTask
        let importedQs = NSOrderedSet(array: imported.map(\.question)).array as? [String] ?? []
        await MainActor.run {
            self.importedQuestions = importedQs
            self.answers = a
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

    static func behaviorName(_ insight: Insight) -> String {
        let parts = insight.title.components(separatedBy: "‘")
        if parts.count > 1 {
            let after = parts[1].components(separatedBy: "’")
            if let name = after.first, !name.isEmpty {
                return String(name.prefix(1)).uppercased() + name.dropFirst()
            }
        }
        return insight.title
    }

    /// A shorter chip label for a long journal question ("Did you drink any alcohol?" → the question
    /// verbatim is data; we only trim a trailing "?"-style sentence for display, keeping the key intact).
    static func shortLabel(_ question: String) -> String { question }

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

    /// A compact, single-hue trend sparkline for «Instrumento» rows. Quiet: no area, no hover.
    @ViewBuilder static func trendSparkline(_ values: [Double], color: Color) -> some View {
        if values.count >= 2 {
            Sparkline(values: values, gradient: Gradient(colors: [color, color]),
                      lineWidth: 2, showsArea: false, showsHead: true, showsHover: false)
                .frame(width: 80, height: 24)
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
#endif
