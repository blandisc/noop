#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

// MARK: - Bucle (Coach)
//
// «El Bucle» — la tab Coach rediseñada como una sola pantalla «Instrumento diurno»
// (FER-292), alimentada por el `InsightEngine` determinista (FER-290). Reemplaza el
// hub de 3 filas (Intelligence · Insights · Coach). El ciclo es
// Descubre → Prueba → Actúa → Aprende; aquí viven sus primeras piezas:
//
//   1. Decisión de hoy   — el héroe es la FRASE-veredicto (qué hacer), el % de
//      recuperación va degradado a evidencia. Deriva de `ReadinessEngine`.
//   2. Pregúntale        — la única puerta al chat LLM externo (`CoachView` preservado).
//   3. Lo que funciona   — palancas curadas (insights de comportamiento), top 2 + «ver».
//   4. Hallazgos         — anomalía / tendencia / relación / pronóstico, topados + «ver».
//   5. Anota tu día      — resumen → hoja Sí/No tri-estado (escribe al journal existente).
//   6. Efectos           — explorador histórico por métrica de todos los hábitos.
//
// DNA «Instrumento diurno»: papel cálido, un dominante, color SOLO en el dato. El color
// con signo en efectos y el datum de los hallazgos es el «más color en tendencias» que
// el dueño pidió, contenido al dato medido (FER-292).

/// Theme wrapper: drives `\.instrumentoTheme` by the hour (like Today / Cuerpo) so the
/// paper warms with the real sun, then hands off to `BucleLanding`.
struct BucleView: View {
    var body: some View {
        BucleLanding()
            .instrumentoThemeByHour(solar: Self.solarWindow())
    }

    private static func solarWindow() -> SolarWindow? {
        guard let w = SolarClock.sunWindow(on: Date(), in: .current) else { return nil }
        return SolarWindow(sunrise: w.sunrise, sunset: w.sunset)
    }
}

// MARK: - Landing

private struct BucleLanding: View {
    @EnvironmentObject var repo: Repository
    @EnvironmentObject var coach: AICoachEngine
    @Environment(\.instrumentoTheme) private var theme

    // Loaded once per refresh (never recomputed per render).
    @State private var insights: [Insight] = []
    @State private var readiness: ReadinessEngine.Readiness? = nil
    @State private var recovery: Double? = nil
    @State private var usableNights = 0
    @State private var journalAnswered = 0
    @State private var journalTotal = 0
    /// Recent recovery series (last 14 nights) for the trend-finding sparkline — trends are recovery.
    @State private var trendSpark: [Double] = []
    @State private var loaded = false

    // Sheets.
    @State private var showPreguntale = false
    /// One lever/finding detail sheet — fed by both «Lo que funciona» and «Hallazgos» (same screen).
    @State private var detail: InsightItem? = nil
    @State private var showHallazgos = false
    @State private var showEfectos = false
    @State private var showAnota = false

    /// Nights of own history the engine needs before it speaks with confidence.
    private static let calibrationTarget = 14

    /// True until there's enough history for a verdict — Decisión and the registro stay hidden,
    /// only «Pregúntale» (which needs no calibration) shows.
    private var coldStart: Bool {
        !loaded || readiness == nil || readiness?.level == .insufficient
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                header

                if coldStart {
                    coldStartHero
                    preguntaleEntry
                } else {
                    decisionSection
                    preguntaleEntry
                    loQueFuncionaSection
                    hallazgosSection
                    anotaResumen
                    efectosEntry
                }
            }
            .padding(.horizontal, NoopMetrics.screenPadding)
            .padding(.top, 20)
            .padding(.bottom, NoopMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.paper.ignoresSafeArea())
        .task(id: repo.refreshSeq) { await load() }
        // Pregúntale — the external LLM chat, preserved. Now «Instrumento» light (FER-309): the theme
        // is injected at the sheet root (it doesn't cross the `.sheet` boundary, FER-162); no `.dark` pin.
        .sheet(isPresented: $showPreguntale) {
            CoachView()
                .instrumentoTheme(theme)
                .environmentObject(coach)
                .environmentObject(repo)
        }
        .sheet(item: $detail) { item in
            PalancaDetailSheet(insight: item.insight, theme: theme)
        }
        .sheet(isPresented: $showHallazgos) {
            HallazgosListSheet(insights: hallazgosInsights, theme: theme, trendSpark: trendSpark) { picked in
                detail = InsightItem(insight: picked)
            }
            .instrumentoTheme(theme)
        }
        .sheet(isPresented: $showEfectos) {
            EfectosExplorerSheet(behaviors: behaviorInsights, theme: theme) { picked in
                detail = InsightItem(insight: picked)
            }
            .instrumentoTheme(theme)
        }
        .sheet(isPresented: $showAnota) {
            AnotaTuDiaSheet(theme: theme) { Task { await load() } }
                .instrumentoTheme(theme)
                .environmentObject(repo)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(headerLabel).instrumentoOverline().foregroundStyle(theme.inkTertiary)
            Spacer()
            HStack(spacing: 4) {
                Image(systemName: "cpu").font(.system(size: 11, weight: .medium))
                Text("On-device").font(StrandFont.captionNumber)
            }
            .foregroundStyle(theme.inkTertiary)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .overlay(Capsule().stroke(theme.hairlineStrong, lineWidth: 1))
        }
    }

    private var headerLabel: String { "Coach · \(Self.dateFormatter.string(from: Date()))" }

    /// Allocated once (DateFormatter init is expensive) — the header date is es-MX «EEE d MMM».
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_MX")
        f.dateFormat = "EEE d MMM"
        return f
    }()

    // MARK: Decisión de hoy (héroe)

    private var decisionSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Decisión de hoy").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            Text(verdictWord)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(theme.ink)
                .padding(.top, 10)
            verdictReading
                .padding(.top, 10)
        }
    }

    /// The reading: the verdict summary, with the recovery datum tinted green (the one colored datum).
    @ViewBuilder private var verdictReading: some View {
        if let rec = recovery {
            (Text("Recuperación ")
                + Text("\(Int(rec.rounded()))%").foregroundColor(theme.dataRecovery).bold()
                + Text(". \(readiness?.summary ?? "")"))
                .font(StrandFont.body)
                .foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(readiness?.summary ?? "")
                .font(StrandFont.body)
                .foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var verdictWord: String {
        switch readiness?.level {
        case .primed:   return "Empuja hoy."
        case .balanced: return "Día parejo."
        case .strained: return "Ve con calma."
        case .rundown:  return "Hoy toca descansar."
        default:        return "Día parejo."
        }
    }

    // MARK: Cold start

    private var coldStartHero: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Decisión de hoy").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            Text("Aún reuniendo señal")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(theme.ink)
                .padding(.top, 10)
            Text("\(usableNights) de \(Self.calibrationTarget) noches")
                .font(StrandFont.subhead)
                .foregroundStyle(theme.inkTertiary)
                .monospacedDigit()
                .padding(.top, 6)
            ProgressView(value: Double(min(usableNights, Self.calibrationTarget)),
                         total: Double(Self.calibrationTarget))
                .tint(theme.inkTertiary)
                .frame(maxWidth: 200, alignment: .leading)
                .padding(.top, 12)
            Text("Cuando tenga \(Self.calibrationTarget) noches verás tu decisión del día, tus palancas y tus hallazgos.")
                .font(StrandFont.subhead)
                .foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 16)
        }
    }

    // MARK: Pregúntale

    private var preguntaleEntry: some View {
        Button { showPreguntale = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "sparkles").font(.system(size: 20)).foregroundStyle(theme.inkSecondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Pregúntale a tus datos")
                        .font(StrandFont.headline).foregroundStyle(theme.ink)
                    Text(coach.hasKey ? "Respuestas más profundas con tu IA" : "Conecta tu IA · opcional")
                        .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 15)).foregroundStyle(theme.inkTertiary)
            }
            .padding(16)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous)
                .stroke(theme.hairlineStrong, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: Lo que funciona en ti (palancas curadas)

    private var loQueFuncionaSection: some View {
        let levers = curatedLevers
        return Group {
            if levers.isEmpty {
                EmptyView()
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    sectionLabel("Lo que funciona en ti",
                                 trailing: behaviorInsights.count > levers.count
                                    ? "Ver las \(behaviorCount)" : nil) { showEfectos = true }
                    ForEach(Array(levers.enumerated()), id: \.offset) { _, insight in
                        leverRow(insight)
                    }
                }
            }
        }
    }

    private func leverRow(_ insight: Insight) -> some View {
        Button { detail = InsightItem(insight: insight) } label: {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(BucleFormat.behaviorName(insight)).font(StrandFont.headline).foregroundStyle(theme.ink)
                    Text(confidenceLabel(insight)).font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                }
                Spacer()
                effectBadge(insight)
                Image(systemName: "chevron.right").font(.system(size: 15))
                    .foregroundStyle(theme.inkTertiary).padding(.leading, 10)
            }
            .padding(.vertical, 13)
            .overlay(alignment: .top) { Rectangle().fill(theme.hairline).frame(height: 0.5) }
        }
        .buttonStyle(.plain)
    }

    // MARK: Hallazgos

    private var hallazgosSection: some View {
        let shown = Array(hallazgosInsights.prefix(2))
        return VStack(alignment: .leading, spacing: 0) {
            sectionLabel("Hallazgos",
                         trailing: hallazgosInsights.count > shown.count
                            ? "Ver los \(hallazgosInsights.count)" : nil) { showHallazgos = true }
            if shown.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark").font(.system(size: 16)).foregroundStyle(theme.inkTertiary)
                    Text("Todo en orden, sin hallazgos nuevos.")
                        .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                }
                .padding(.vertical, 14)
                .overlay(alignment: .top) { Rectangle().fill(theme.hairline).frame(height: 0.5) }
            } else {
                ForEach(Array(shown.enumerated()), id: \.offset) { _, insight in
                    findingRow(insight)
                }
            }
        }
    }

    private func findingRow(_ insight: Insight) -> some View {
        Button { detail = InsightItem(insight: insight) } label: {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(BucleFormat.kindLabel(insight.kind)).instrumentoOverline().foregroundStyle(theme.inkTertiary)
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

    // MARK: Anota tu día (resumen)

    private var anotaResumen: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Anota tu día").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            Button { showAnota = true } label: {
                HStack(spacing: 13) {
                    Image(systemName: "square.and.pencil").font(.system(size: 20)).foregroundStyle(theme.inkSecondary)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(journalAnswered > 0 ? "\(journalAnswered) de \(journalTotal) anotados hoy" : "Marca qué pasó hoy")
                            .font(StrandFont.headline).foregroundStyle(theme.ink).monospacedDigit()
                        Text("Alimenta tus palancas").font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 15)).foregroundStyle(theme.inkTertiary)
                }
                .padding(16)
                .background(theme.surface, in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous)
                    .stroke(theme.hairlineStrong, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Efectos de tus hábitos (explorador)

    @ViewBuilder private var efectosEntry: some View {
        if !behaviorInsights.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Efectos de tus hábitos").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                Button { showEfectos = true } label: {
                    HStack(spacing: 13) {
                        Image(systemName: "chart.bar").font(.system(size: 20)).foregroundStyle(theme.inkSecondary)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Explora por métrica").font(StrandFont.headline).foregroundStyle(theme.ink)
                            Text("Cómo cada hábito te mueve, en todo tu historial")
                                .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 15)).foregroundStyle(theme.inkTertiary)
                    }
                    .padding(16)
                    .background(theme.surface, in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous)
                        .stroke(theme.hairlineStrong, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Shared bits

    private func sectionLabel(_ title: LocalizedStringKey, trailing: String?,
                              action: @escaping () -> Void) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).instrumentoOverline().foregroundStyle(theme.inkTertiary)
            Spacer()
            if let trailing {
                Button(action: action) {
                    HStack(spacing: 2) {
                        Text(trailing).font(StrandFont.footnote)
                        Image(systemName: "chevron.right").font(.system(size: 11))
                    }
                    .foregroundStyle(theme.inkTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, 2)
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

    // MARK: Derived collections

    /// Behavior-kind insights only (the «palancas» universe), already ranked.
    private var behaviorInsights: [Insight] { insights.filter { $0.kind == .behavior } }

    /// Everything that isn't a behavior lever — the «Hallazgos» feed, ranked.
    private var hallazgosInsights: [Insight] { insights.filter { $0.kind != .behavior } }

    /// Distinct behaviors count (for the «Ver las N» label).
    private var behaviorCount: Int { Set(behaviorInsights.map { BucleFormat.behaviorName($0) }).count }

    /// Top 2 levers, deduped by behavior (a behavior can move several metrics — keep its best).
    private var curatedLevers: [Insight] {
        var seen = Set<String>()
        var out: [Insight] = []
        for i in behaviorInsights {
            if seen.insert(BucleFormat.behaviorName(i)).inserted { out.append(i) }
            if out.count == 2 { break }
        }
        return out
    }

    // MARK: Formatting helpers

    private func confidenceLabel(_ insight: Insight) -> String {
        let conf: String
        switch insight.confidence {
        case .candidate: conf = "candidato"
        case .proven:    conf = "probado"
        case .medium:    conf = "exploratorio"
        }
        return "\(conf) · \(insight.evidence.n) noches"
    }

    // MARK: Load

    private func load() async {
        let days = repo.days
        let todayKey = Repository.localDayKey(Date())

        async let entriesTask = repo.journalEntries()
        async let importedTask = repo.importedJournalEntries()
        async let answersTask = repo.nativeJournalAnswers(day: todayKey)

        let entries = await entriesTask
        let imported = await importedTask
        let todayAnswers = await answersTask

        var behaviors: [String: Set<String>] = [:]
        for e in entries where e.answeredYes { behaviors[e.question, default: []].insert(e.day) }

        let inputs = InsightEngine.Inputs(days: days, behaviors: behaviors, referenceDay: todayKey)
        let generated = InsightEngine.generate(inputs)
        let r = ReadinessEngine.evaluate(days: days, today: todayKey)

        let importedQs = NSOrderedSet(array: imported.map(\.question)).array as? [String] ?? []
        let catalog = JournalCatalogStore.mergeCatalog(imported: importedQs, custom: [])
        let nights = days.filter { $0.avgHrv != nil }.count
        let spark = Array(days.compactMap { $0.recovery }.suffix(14))

        await MainActor.run {
            self.insights = generated
            self.readiness = r
            self.recovery = repo.today?.recovery
            self.usableNights = nights
            self.journalAnswered = todayAnswers.count
            self.journalTotal = max(catalog.count, 1)
            self.trendSpark = spark
            self.loaded = true
        }
    }
}

// MARK: - Insight sheet item

/// Identifiable wrapper so an `Insight` can ride `.sheet(item:)` (it isn't Identifiable).
private struct InsightItem: Identifiable {
    let id = UUID()
    let insight: Insight
}
#endif
