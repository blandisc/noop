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

    static func magnitudeWord(_ d: Double) -> String {
        switch abs(d) {
        case ..<0.2:  return "insignificante"
        case ..<0.5:  return "chico"
        case ..<0.8:  return "moderado"
        default:      return "grande"
        }
    }
}
#endif
