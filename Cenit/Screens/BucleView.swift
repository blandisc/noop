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

/// Theme wrapper: anchors `\.instrumentoTheme` to the single warm day paper (`.base`), then hands off
/// to `BucleLanding`. (FER-398 retired the by-the-hour tint.)
struct BucleView: View {
    var body: some View {
        BucleLanding()
            .instrumentoTheme(.base)
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
    /// Yesterday's verdict level, shown as context in the «esperando la lectura de hoy» hero (FER-340).
    @State private var yesterdayVerdict: ReadinessEngine.Level? = nil
    @State private var journalAnswered = 0
    @State private var journalTotal = 0
    /// Recent recovery series (last 14 nights) for the trend-finding sparkline — trends are recovery.
    @State private var trendSpark: [Double] = []
    /// The compact, engine-grounded fact summary "Pregúntale a tus datos" answers from (FER-308).
    @State private var grounding: CoachGrounding? = nil
    @State private var loaded = false

    // N-of-1 experiment state (FER-307). One at a time (MVP): either a running experiment, or the
    // most-recent finished verdict the user hasn't dismissed, or neither.
    @State private var running: ExperimentVM? = nil
    @State private var finished: ExperimentRow? = nil
    /// The completed experiment the user has acknowledged — so its verdict card stops showing. Local,
    /// per-device; the «probado» promotion in "Lo que funciona" is the durable record either way.
    @AppStorage("fer307.dismissedExperimentId") private var dismissedExperimentId = ""

    // Sheets.
    @State private var showPreguntale = false
    /// One lever/finding detail sheet — fed by both «Lo que funciona» and «Hallazgos» (same screen).
    @State private var detail: InsightItem? = nil
    /// The candidate lever a start-experiment confirmation sheet is open for.
    @State private var startLever: InsightItem? = nil
    @State private var showHallazgos = false
    @State private var showEfectos = false
    @State private var showAnota = false
    /// Generic info explainer (On-device pill + the ⓘ on each section). FER-312.
    @State private var info: BucleInfo? = nil
    /// «Decisión de hoy» explainer — opens on tapping the hero (what to do + why). FER-312.
    @State private var showDecision = false
    /// A tapped HRV / FC-en-reposo signal — opens its explainer (qué es + qué significa el σ). FER-437.
    @State private var signalInfo: SignalItem? = nil

    // Meta + simulador (FER-311).
    @EnvironmentObject private var goalStore: GoalStore
    @State private var goalSheet: GoalSheetKind? = nil

    /// Which goal sheet is open. Item-based so .picker ↔ .simulator swap cleanly.
    private enum GoalSheetKind: Int, Identifiable { case picker, simulator; var id: Int { rawValue } }

    /// Nights of own history the engine needs before it speaks with confidence.
    private static let calibrationTarget = 14

    /// Genuine cold-start: not enough own history yet for ANY verdict. The onboarding hero shows and
    /// the registro stays hidden — only «Pregúntale» (which needs no calibration) is offered.
    private var genuineColdStart: Bool {
        !loaded || usableNights < Self.calibrationTarget
    }

    /// History is sufficient, but today's reading hasn't landed yet: between local midnight and the
    /// morning sync there's no complete row for today, so readiness reads `.insufficient`. The Decisión
    /// waits, while the findings/levers — built from history, not today — stay visible (FER-340).
    private var awaitingToday: Bool {
        !genuineColdStart && (readiness == nil || readiness?.level == .insufficient)
    }

    /// Nights still needed before the first verdict (cold-start copy). ≥1 while genuinely cold.
    private var nightsRemaining: Int { max(0, Self.calibrationTarget - usableNights) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                if genuineColdStart {
                    coldStartHero
                    preguntaleEntry
                    pruebaSection
                } else {
                    // History is sufficient. Show the real Decisión, or — when today's reading hasn't
                    // synced yet (midnight → morning) — a waiting hero. EITHER WAY the findings, levers
                    // and correlations below stay: they come from history, not today's reading (FER-340).
                    if awaitingToday {
                        awaitingDecisionHero
                    } else {
                        decisionSection
                        senalesSection
                        trayectoriaSection
                    }
                    metaSection
                    preguntaleEntry
                    loQueFuncionaSection
                    pruebaSection
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
            PreguntaleView(grounding: grounding ?? CoachGrounding.from(
                insights: insights, readiness: readiness, recovery: recovery,
                referenceDay: Repository.localDayKey(Date())),
                           behaviorInsights: behaviorInsights)
                .instrumentoTheme(theme)
                .environmentObject(coach)
                .environmentObject(repo)
        }
        .sheet(item: $detail) { item in
            PalancaDetailSheet(insight: item.insight, theme: theme,
                               canStartExperiment: canStartExperiment(item.insight)) {
                detail = nil
                startLever = item
            }
        }
        .sheet(item: $startLever) { item in
            StartExperimentSheet(insight: item.insight, theme: theme) { behavior, outcome, sign in
                await repo.startExperiment(behavior: behavior, outcome: outcome, expectedSign: sign)
                startLever = nil
                await load()
            }
            .instrumentoTheme(theme)
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
        .sheet(item: $info) { i in
            BucleInfoSheet(info: i, theme: theme)
        }
        .sheet(isPresented: $showDecision) {
            if let r = readiness {
                DecisionExplainerSheet(readiness: r, recovery: recovery, theme: theme)
            }
        }
        .sheet(item: $signalInfo) { item in
            SignalExplainerSheet(signal: item.signal, theme: theme)
                .instrumentoTheme(theme)
        }
        .sheet(item: $goalSheet) { kind in
            switch kind {
            case .picker:
                GoalPickerSheet(theme: theme,
                                initialMetric: goalStore.metric, initialDate: goalStore.targetDate,
                                onSave: { metric, date in goalStore.set(metric: metric, targetDate: date) },
                                onClear: goalStore.isSet ? { goalStore.clear() } : nil)
                    .instrumentoTheme(theme)
            case .simulator:
                if let m = goalStore.metric {
                    SimulatorScreen(theme: theme, metric: m, targetDate: goalStore.targetDate,
                                    onEdit: { goalSheet = .picker })
                        .instrumentoTheme(theme)
                        .environmentObject(repo)
                }
            }
        }
    }

    // MARK: On-device chip

    /// The «On-device» affordance — opens the «qué significa on-device» explainer. Lives in the top
    /// row of each Decisión state (the date header was retired in FER-436), so it's never lost.
    private var onDeviceChip: some View {
        Button { info = .onDevice } label: {
            HStack(spacing: 4) {
                Image(systemName: "cpu").font(.system(size: 11, weight: .medium))
                Text("On-device").font(StrandFont.captionNumber)
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(theme.inkTertiary)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .overlay(Capsule().stroke(theme.hairlineStrong, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Qué significa on-device")
    }

    // MARK: Decisión de hoy (héroe)

    private var decisionSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top row: the overline + the On-device chip (the date header was retired, FER-436). The chip
            // is its own button, so it stays OUTSIDE the hero button below (no nested tap targets).
            HStack(spacing: 6) {
                Text("Decisión de hoy").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                Spacer()
                onDeviceChip
            }
            Button { showDecision = true } label: {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .center, spacing: 18) {
                        RecoveryZoneGauge(score: recovery, label: "RECUPERACIÓN", theme: theme)
                        VStack(alignment: .leading, spacing: 9) {
                            Text(verdictWord)
                                .font(.system(size: 30, weight: .semibold))
                                .foregroundStyle(theme.ink)
                                .fixedSize(horizontal: false, vertical: true)
                            // The recovery figure lives in the gauge now, so the reading drops the «Recuperación X%»
                            // prefix and shows just the engine's one-line summary (the «why» is the Señales row +
                            // the explainer sheet). FER-292 v2.
                            if let summary = readiness?.summary, !summary.isEmpty {
                                Text(summary)
                                    .font(StrandFont.subhead)
                                    .foregroundStyle(theme.inkSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.top, 14)
                    // Visible affordance that the hero opens the «por qué / qué hacer hoy» explainer (FER-436).
                    HStack(spacing: 4) {
                        Text("Ver por qué").font(StrandFont.captionNumber)
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(theme.inkSecondary)
                    .padding(.top, 12)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Toca para ver por qué y qué hacer hoy")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var verdictWord: String { BucleFormat.verdictWord(readiness?.level) }

    // MARK: Señales de hoy (drivers of the verdict, FER-292 v2)

    /// The up-to-3 leading signals behind the verdict, each a glanceable chip: label · flag dot · the
    /// engine's compact read-out (σ / °C / load ratio) · a short lead clause of its read. Hidden when
    /// there are no signals (cold start / awaiting). The full list lives in the explainer sheet.
    @ViewBuilder private var senalesSection: some View {
        if let r = readiness, !r.signals.isEmpty {
            VStack(alignment: .leading, spacing: 13) {
                Text("Señales de hoy").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                HStack(alignment: .top, spacing: 0) {
                    let lead = Array(r.signals.prefix(3))
                    ForEach(Array(lead.enumerated()), id: \.offset) { i, s in
                        if i > 0 {
                            Rectangle().fill(theme.hairline).frame(width: 1)
                                .padding(.vertical, 2).padding(.horizontal, 13)
                        }
                        if Self.isExplainable(s) {
                            Button { signalInfo = SignalItem(signal: s) } label: { signalCell(s) }
                                .buttonStyle(.plain)
                                .accessibilityHint("Toca para saber qué es \(s.label) y qué significa")
                        } else {
                            signalCell(s)
                        }
                    }
                }
            }
            .padding(.top, 16)
            .overlay(alignment: .top) { Rectangle().fill(theme.hairline).frame(height: 0.5) }
        }
    }

    private func signalCell(_ s: ReadinessEngine.Signal) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(s.label).font(.system(size: 9.5, weight: .semibold)).tracking(0.7).textCase(.uppercase)
                .foregroundStyle(theme.inkTertiary)
                .lineLimit(1).minimumScaleFactor(0.8)
            HStack(spacing: 5) {
                Circle().fill(signalFlagColor(s.flag)).frame(width: 8, height: 8)
                Text(s.value ?? "—").font(StrandFont.mono(13, weight: .semibold)).foregroundStyle(theme.ink)
                    .lineLimit(1).minimumScaleFactor(0.7)
                // Visible «tap me» cue on the explainable signals (HRV / FC en reposo). FER-445.
                if Self.isExplainable(s) {
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(theme.inkTertiary)
                }
            }
            Text(BucleFormat.signalShortDetail(s.detail))
                .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// HRV and resting-HR are the z-score signals that get a per-signal explainer (FER-437); the
    /// others (training load) stay non-tappable.
    private static func isExplainable(_ s: ReadinessEngine.Signal) -> Bool { s.key == "hrv" || s.key == "rhr" }

    private func signalFlagColor(_ flag: ReadinessEngine.Flag) -> Color {
        switch flag {
        case .good:    return theme.dataRecovery
        case .neutral: return theme.inkTertiary
        case .watch:   return theme.warning
        case .bad:     return theme.critical
        }
    }

    // MARK: Trayectoria · 14 días (FER-292 v2)

    /// The 14-night recovery trajectory: a paper sparkline with a faint area, plus a «↑ N% vs media»
    /// delta of today vs the window mean. Hidden until there are at least 2 nights to draw.
    @ViewBuilder private var trayectoriaSection: some View {
        if trendSpark.count >= 2 {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Tu recuperación · 14 días").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                    Spacer()
                    if let d = trajectoryDelta {
                        Text(d.text).font(StrandFont.captionNumber)
                            .foregroundStyle(d.positive ? theme.positiveText : theme.critical)
                    }
                }
                Sparkline(values: trendSpark,
                          gradient: Gradient(colors: [theme.dataRecovery, theme.dataRecovery]),
                          lineWidth: 2, showsArea: true, showsHead: true, showsScrub: true,
                          // Scrub read-out: the recovery value + which day it was, so dragging reads
                          // «Hace 5 días · 71», not «muestra 9». The newest point is today. (FER-445)
                          valueFormat: { "\(Int($0.rounded()))" },
                          indexLabel: { idx in
                              switch trendSpark.count - 1 - idx {
                              case 0: return "Hoy"
                              case 1: return "Ayer"
                              case let d: return "Hace \(d) días"
                              }
                          })
                    .frame(height: 54)
            }
        }
    }

    /// Today's recovery vs the 14-day mean, as a signed «↑/↓ N% vs media». nil when the mean is ~0.
    private var trajectoryDelta: (text: String, positive: Bool)? {
        guard let last = trendSpark.last, trendSpark.count >= 2 else { return nil }
        let mean = trendSpark.reduce(0, +) / Double(trendSpark.count)
        guard mean > 0.5 else { return nil }
        let pct = Int(((last - mean) / mean * 100).rounded())
        if pct == 0 { return ("· en su media", true) }
        let arrow = pct > 0 ? "↑" : "↓"
        return ("\(arrow) \(abs(pct))% vs media", pct > 0)
    }

    // MARK: Tu meta (ancla del simulador, FER-311)

    /// A quiet line under the hero: with a goal it shows the focus (+ date) and opens the simulator;
    /// without one it invites "Ponte una meta". No surface card (hierarchy by space), no color (chrome).
    private var metaSection: some View {
        Button { goalSheet = goalStore.isSet ? .simulator : .picker } label: {
            HStack(spacing: 11) {
                Image(systemName: "target")
                    .font(.system(size: 18))
                    .foregroundStyle(goalStore.isSet ? theme.inkSecondary : theme.inkTertiary)
                if let m = goalStore.metric {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Tu meta").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                        Text(metaLine(m)).font(StrandFont.subhead).foregroundStyle(theme.ink)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 15)).foregroundStyle(theme.inkTertiary)
                } else {
                    Text("Ponte una meta").font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                    Spacer()
                    Image(systemName: "arrow.right").font(.system(size: 15)).foregroundStyle(theme.inkTertiary)
                }
            }
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) { Rectangle().fill(theme.hairline).frame(height: 0.5) }
    }

    private func metaLine(_ m: GoalMetric) -> String {
        if let d = goalStore.targetDate { return "\(m.focus.title) · \(Self.metaDate.string(from: d))" }
        return m.focus.title
    }

    private static let metaDate: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "es_MX"); f.dateFormat = "d MMM"; return f
    }()

    // MARK: Cold start

    private var coldStartHero: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text("Decisión de hoy").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                Spacer()
                onDeviceChip
            }
            Text("Aún reuniendo señal")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(theme.ink)
                .padding(.top, 10)
            Text("\(min(usableNights, Self.calibrationTarget)) de \(Self.calibrationTarget) noches")
                .font(StrandFont.subhead)
                .foregroundStyle(theme.inkTertiary)
                .monospacedDigit()
                .padding(.top, 6)
            ProgressView(value: Double(min(usableNights, Self.calibrationTarget)),
                         total: Double(Self.calibrationTarget))
                .tint(theme.inkTertiary)
                .frame(maxWidth: 200, alignment: .leading)
                .padding(.top, 12)
            Text(nightsRemaining == 1
                 ? "Falta 1 noche con la banda para tu primera decisión, tus palancas y tus hallazgos."
                 : "Faltan \(nightsRemaining) noches con la banda para tu primera decisión, tus palancas y tus hallazgos.")
                .font(StrandFont.subhead)
                .foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 16)
        }
    }

    /// History is sufficient but today's reading hasn't synced yet (midnight → morning). The Decisión
    /// waits — it arrives with tonight's sleep — while «Lo que funciona», los hallazgos y las
    /// correlaciones de abajo siguen visibles (vienen del historial, no de hoy). FER-340.
    private var awaitingDecisionHero: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text("Decisión de hoy").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                Spacer()
                onDeviceChip
            }
            Text("Esperando la lectura de hoy")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(theme.ink)
                .padding(.top, 10)
            if let level = yesterdayVerdict {
                (Text("Ayer: ")
                    + Text(BucleFormat.verdictWord(level)).bold()
                    + Text(" · se actualiza al sincronizar"))
                    .font(StrandFont.subhead)
                    .foregroundStyle(theme.inkTertiary)
                    .padding(.top, 6)
            }
            Text("Tu decisión llega cuando uses la banda y sincronices tras dormir. Se afina con la información de hoy.")
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
                                    ? "Ver las \(behaviorCount)" : nil,
                                 info: .loQueFunciona) { showEfectos = true }
                    ForEach(Array(levers.enumerated()), id: \.offset) { _, insight in
                        leverRow(insight)
                    }
                }
            }
        }
    }

    private func leverRow(_ insight: Insight) -> some View {
        Button { detail = InsightItem(insight: insight) } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(BucleFormat.behaviorName(insight)).font(StrandFont.headline).foregroundStyle(theme.ink)
                        // The metric this lever moves is now visible (was just «exploratorio · n»). FER-292 v2.
                        Text("\(insight.datum.metric) · \(insight.evidence.n) noches")
                            .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                    }
                    Spacer()
                    effectBadge(insight)
                    Image(systemName: "chevron.right").font(.system(size: 15))
                        .foregroundStyle(theme.inkTertiary).padding(.leading, 10)
                }
                // With / without comparison — the means the engine measured, drawn as a dumbbell. The
                // metric name above carries the unit, so the values stay bare numbers (no unit mismatch).
                if let bd = insight.behaviorBreakdown {
                    BehaviorDumbbell(
                        meanWith: bd.meanWith, meanWithout: bd.meanWithout,
                        withText: formatMean(bd.meanWith), withoutText: formatMean(bd.meanWithout),
                        withIsBetter: BucleFormat.withIsBetter(metric: insight.datum.metric,
                                                               meanWith: bd.meanWith, meanWithout: bd.meanWithout),
                        hue: BucleFormat.metricColor(insight.datum.metric, theme), theme: theme)
                }
            }
            .padding(.vertical, 13)
            .overlay(alignment: .top) { Rectangle().fill(theme.hairline).frame(height: 0.5) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// A behaviour-breakdown mean as a bare figure: one decimal when it isn't a whole number, else an
    /// integer. The unit lives in the lever's «<métrica> · n noches» subtitle, so no suffix here.
    private func formatMean(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v.rounded())) : String(format: "%.1f", v)
    }

    // MARK: Prueba (experimentos N-of-1, FER-307)
    //
    // The cycle's third beat (Descubre → PRUEBA → Actúa → Aprende). One section that changes identity
    // by state: a running experiment («Tu experimento»), the most-recent verdict, or an invitation to
    // test the top candidate lever («Idea por probar»). Color stays in the datum — the verdict's
    // measured effect is the only place a hue is earned (and only when it «se sostuvo»).

    @ViewBuilder private var pruebaSection: some View {
        if let vm = running {
            experimentRunningSection(vm)
        } else if let fin = finished {
            experimentVerdictSection(fin)
        } else if let idea = ideaPorProbar {
            ideaPorProbarSection(idea)
        } else {
            pruebaInvitation
        }
    }

    /// No experiment, no candidate yet — the «sin experimento» invitation. Shows even at cold start
    /// (it teaches the mechanic and routes to the journal that creates candidates). Informational, so
    /// no surface card and no color: hierarchy by space, ink only.
    private var pruebaInvitation: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Prueba").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            Text("Pon a prueba una idea").font(StrandFont.headline).foregroundStyle(theme.ink)
            Text("Cuando Cénit encuentre un hábito ligado a tu recuperación, te propondrá probarlo una semana para confirmar su efecto en tu cuerpo. Empieza por anotar tus días.")
                .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button { showAnota = true } label: {
                HStack(spacing: 5) {
                    Image(systemName: "square.and.pencil").font(.system(size: 14))
                    Text("Anota tu día").font(StrandFont.subhead)
                    Image(systemName: "arrow.right").font(.system(size: 13))
                }
                .foregroundStyle(theme.ink)
            }
            .buttonStyle(.plain).padding(.top, 4)
        }
    }

    /// The top candidate lever not yet under test or proven — the idea worth confirming next.
    private var ideaPorProbar: Insight? {
        behaviorInsights.first { $0.confidence == .candidate && $0.lever != nil }
    }

    // MARK: Idea por probar (no experiment running)

    private func ideaPorProbarSection(_ idea: Insight) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Idea por probar").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            Button { startLever = InsightItem(insight: idea) } label: {
                HStack(spacing: 13) {
                    Image(systemName: "flask").font(.system(size: 20)).foregroundStyle(theme.inkSecondary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Prueba “\(BucleFormat.behaviorName(idea))” una semana")
                            .font(StrandFont.headline).foregroundStyle(theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Confirma si \(idea.datum.value < 0 ? "baja" : "sube") tu \(idea.datum.metric)")
                            .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                    }
                    Spacer()
                    HStack(spacing: 4) {
                        Text("Probar").font(StrandFont.footnote)
                        Image(systemName: "arrow.right").font(.system(size: 14))
                    }
                    .foregroundStyle(theme.ink)
                }
                .padding(16)
                .background(theme.surface, in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous)
                    .stroke(theme.hairlineStrong, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Tu experimento (running)

    private func experimentRunningSection(_ vm: ExperimentVM) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Tu experimento").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            Text(BucleFormat.behaviorName(insightStub(vm.row)))
                .font(StrandFont.title2).foregroundStyle(theme.ink).padding(.top, 10)
            Text("a prueba sobre tu \(vm.row.outcome)")
                .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary).padding(.top, 3)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Día \(vm.elapsedDay)").font(.system(size: 30, weight: .semibold)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.6)   // FER-394
                    .foregroundStyle(theme.ink)
                Text("de \(vm.row.windowDays)").font(StrandFont.subhead).foregroundStyle(theme.inkTertiary)
            }
            .padding(.top, 16)

            ProgressView(value: Double(vm.elapsedDay), total: Double(vm.row.windowDays))
                .tint(theme.inkTertiary).padding(.top, 12)

            (Text("Cumpliste ")
                + Text("\(vm.adherent) de \(vm.elapsedDay)").foregroundColor(theme.ink).bold()
                + Text(" días."))
                .font(StrandFont.body).foregroundStyle(theme.inkSecondary).monospacedDigit().padding(.top, 16)
            Text("Veredicto el \(vm.verdictDate)")
                .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary).padding(.top, 6)

            Button { Task { await repo.cancelExperiment(vm.row); await load() } } label: {
                Text("Cancelar experimento").font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
            }
            .buttonStyle(.plain).padding(.top, 18)
        }
    }

    // MARK: Tu experimento (verdict)

    private func experimentVerdictSection(_ exp: ExperimentRow) -> some View {
        let v = Verdict(rawValue: exp.result ?? "") ?? .insufficient
        return VStack(alignment: .leading, spacing: 0) {
            Text("Tu experimento").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            Text(BucleFormat.verdictHeadline(v))
                .font(.system(size: v == .sustained ? 26 : 24, weight: .semibold))
                .foregroundStyle(theme.ink).fixedSize(horizontal: false, vertical: true).padding(.top, 10)

            // Color only on a sustained effect — a confirmed measured value.
            if v == .sustained, let delta = exp.effectDelta {
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    Text(BucleFormat.signedDelta(delta, unit: outcomeUnit(exp.outcome)))
                        .font(.system(size: 40, weight: .semibold)).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.6)   // FER-394
                        .foregroundStyle(theme.dataRecovery)
                    Text(exp.outcome).font(StrandFont.subhead).foregroundStyle(theme.inkTertiary)
                }
                .padding(.top, 12)
            }

            Text(BucleFormat.verdictReading(v, behavior: BucleFormat.behaviorName(insightStub(exp)),
                                            outcome: exp.outcome, adherent: exp.nWith ?? 0,
                                            window: exp.windowDays))
                .font(StrandFont.body).foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 14)

            Button {
                dismissedExperimentId = exp.id
                finished = nil
            } label: {
                HStack(spacing: 5) {
                    Text("Listo").font(StrandFont.headline).foregroundStyle(theme.ink)
                    Image(systemName: "checkmark").font(.system(size: 14)).foregroundStyle(theme.ink)
                }
            }
            .buttonStyle(.plain).padding(.top, 18)
        }
    }

    /// Whether tapping «Probar» on a lever may start an experiment: it's a candidate behavior lever and
    /// nothing is in flight (MVP one-at-a-time).
    private func canStartExperiment(_ insight: Insight) -> Bool {
        running == nil && insight.kind == .behavior && insight.lever != nil && insight.confidence != .proven
    }

    /// Build a throwaway `Insight` carrying only the title an experiment row implies, so
    /// `BucleFormat.behaviorName` (which parses the ‘…’ title) can name the lever from a stored row.
    private func insightStub(_ row: ExperimentRow) -> Insight {
        Insight(kind: .behavior, title: "‘\(row.behavior)’", reading: "",
                datum: InsightDatum(value: 0, unit: "", metric: row.outcome),
                evidence: InsightEvidence(n: 0, pValue: nil, pAdjusted: nil, effectSize: nil, significant: false),
                confidence: .candidate, relevance: 0, lever: Lever(behavior: row.behavior, outcome: row.outcome))
    }

    /// Native unit for an experiment's outcome path, via the single typed source (`InsightEngine.Outcome`,
    /// FER-353) instead of a second copy of the es-MX units; `pts` covers Recuperación and any unknown label.
    private func outcomeUnit(_ metric: String) -> String {
        InsightEngine.Outcome(label: metric)?.unit ?? "pts"
    }

    // MARK: Hallazgos

    private var hallazgosSection: some View {
        let shown = Array(hallazgosInsights.prefix(2))
        return VStack(alignment: .leading, spacing: 0) {
            sectionLabel("Hallazgos",
                         trailing: hallazgosInsights.count > shown.count
                            ? "Ver los \(hallazgosInsights.count)" : nil,
                         info: .hallazgos) { showHallazgos = true }
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
            HStack(spacing: 13) {
                // A drawn mark per finding type (relación / tendencia / anomalía); other kinds show none.
                BucleFormat.findingGlyph(insight, trendSpark: trendSpark, theme: theme)
                VStack(alignment: .leading, spacing: 3) {
                    Text(BucleFormat.kindLabel(insight.kind)).instrumentoOverline().foregroundStyle(theme.inkTertiary)
                    Text(insight.title).font(StrandFont.headline).foregroundStyle(theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.system(size: 15))
                    .foregroundStyle(theme.inkTertiary)
            }
            .padding(.vertical, 13)
            .overlay(alignment: .top) { Rectangle().fill(theme.hairline).frame(height: 0.5) }
            .contentShape(Rectangle())
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
                    VStack(alignment: .leading, spacing: 7) {
                        Text(journalAnswered > 0 ? "\(journalAnswered) de \(journalTotal) anotados hoy" : "Marca qué pasó hoy")
                            .font(StrandFont.headline).foregroundStyle(theme.ink).monospacedDigit()
                        if journalAnswered > 0 {
                            // Progress segments: answered in ink, the rest in the warm divider tone (FER-292 v2 §D).
                            HStack(spacing: 5) {
                                ForEach(0..<max(journalTotal, 1), id: \.self) { i in
                                    Capsule().fill(i < journalAnswered ? theme.ink : theme.hairline)
                                        .frame(width: 22, height: 5)
                                }
                            }
                        } else {
                            Text("Alimenta tus palancas").font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                        }
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
                HStack(spacing: 6) {
                    Text("Efectos de tus hábitos").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                    Button { info = .efectos } label: {
                        Image(systemName: "info.circle").font(.system(size: 12)).foregroundStyle(theme.inkTertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cómo funciona esta sección")
                }
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
                              info infoItem: BucleInfo? = nil,
                              action: @escaping () -> Void) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title).instrumentoOverline().foregroundStyle(theme.inkTertiary)
            if let infoItem {
                Button { info = infoItem } label: {
                    Image(systemName: "info.circle").font(.system(size: 12)).foregroundStyle(theme.inkTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cómo funciona esta sección")
            }
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

    // MARK: Load

    private func load() async {
        let days = repo.days
        let todayKey = Repository.localDayKey(Date())

        // Close a due experiment first, so its verdict is ready to show and to promote its lever.
        await repo.closeDueExperiment(today: todayKey)

        async let entriesTask = repo.journalEntries()
        async let importedTask = repo.importedJournalEntries()
        async let answersTask = repo.nativeJournalAnswers(day: todayKey)

        let entries = await entriesTask
        let imported = await importedTask
        let todayAnswers = await answersTask

        var behaviors: [String: Set<String>] = [:]
        for e in entries where e.answeredYes { behaviors[e.question, default: []].insert(e.day) }

        // Diet adherence as a Coach behavior (FER-385): «Seguí mi dieta» = days the plan was followed
        // (adherence ≥ threshold), restricted to the days actually tracked (its eligible universe) so
        // untracked days don't read as "didn't follow the plan". Flows into «Lo que funciona en ti» and
        // the N-of-1 experiment like any journal behavior.
        var eligibleDaysByBehavior: [String: Set<String>] = [:]
        if let from = days.map(\.day).min() {
            let dietByDay = await repo.dietAdherenceByDay(from: from, to: todayKey)
            let dietKey = JournalCatalogStore.dietBehaviorKey
            if !dietByDay.isEmpty, behaviors[dietKey] == nil {
                behaviors[dietKey] = DietAdherence.adherentDays(percentByDay: dietByDay)
                eligibleDaysByBehavior[dietKey] = Set(dietByDay.keys)
            }
        }

        let inputs = InsightEngine.Inputs(days: days, behaviors: behaviors,
                                          eligibleDaysByBehavior: eligibleDaysByBehavior, referenceDay: todayKey)
        let proven = await repo.provenLevers()
        let generated = InsightEngine.promoteProven(InsightEngine.generate(inputs), provenLevers: proven)
        let r = ReadinessEngine.evaluate(days: days, today: todayKey)
        // When today's verdict isn't in yet (awaiting state), surface yesterday's as context — but only
        // if yesterday actually produced one. One extra evaluate; no change to the engine. (FER-340)
        var yVerdict: ReadinessEngine.Level? = nil
        if r.level == .insufficient,
           let yDate = Calendar.current.date(byAdding: .day, value: -1, to: Date()) {
            let ry = ReadinessEngine.evaluate(days: days, today: Repository.localDayKey(yDate))
            if ry.level != .insufficient { yVerdict = ry.level }
        }

        let importedQs = NSOrderedSet(array: imported.map(\.question)).array as? [String] ?? []
        let catalog = JournalCatalogStore.mergeCatalog(imported: importedQs, custom: [])
        let nights = days.filter { $0.avgHrv != nil }.count
        let spark = Array(days.compactMap { $0.recovery }.suffix(14))

        let g = CoachGrounding.from(insights: generated, readiness: r,
                                    recovery: repo.today?.recovery, referenceDay: todayKey)

        // Experiment state: a running one (with live progress + adherence), else the latest finished
        // verdict the user hasn't dismissed.
        let active = await repo.activeExperiment()
        var runVM: ExperimentVM? = nil
        if let active { runVM = await runningVM(active, today: todayKey) }
        let allExp = await repo.allExperiments()
        let latestFinished = active == nil
            ? allExp.first { $0.status == .completed && $0.id != dismissedExperimentId }
            : nil

        await MainActor.run {
            self.insights = generated
            self.readiness = r
            self.recovery = repo.today?.recovery
            self.grounding = g
            self.usableNights = nights
            self.yesterdayVerdict = yVerdict
            self.journalAnswered = todayAnswers.count
            self.journalTotal = max(catalog.count, 1)
            self.trendSpark = spark
            self.running = runVM
            self.finished = latestFinished
            self.loaded = true
        }
    }

    /// Build the running-experiment view model: day N of M, adherent-day count so far, verdict date.
    private func runningVM(_ row: ExperimentRow, today: String) async -> ExperimentVM? {
        let elapsed = max(1, min(row.windowDays, Self.dayspan(from: row.startDay, to: today) + 1))
        let adherent = await repo.nativeAdherence(behavior: row.behavior, from: row.startDay, to: today)
        let verdictDate = Repository.experimentEndDay(row).flatMap(Self.dayLongLabel) ?? "—"
        return ExperimentVM(row: row, elapsedDay: elapsed, adherent: adherent, verdictDate: verdictDate)
    }

    /// Whole days from `a` to `b` ("yyyy-MM-dd"), 0 when same day, clamped at 0.
    private static func dayspan(from a: String, to b: String) -> Int {
        guard let da = dayParse.date(from: a), let db = dayParse.date(from: b) else { return 0 }
        return max(0, Calendar.current.dateComponents([.day], from: da, to: db).day ?? 0)
    }

    /// "vie 26 jun" for a day key.
    private static func dayLongLabel(_ key: String) -> String? {
        dayParse.date(from: key).map { dateFormatter.string(from: $0) }
    }

    private static let dayParse: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// es-MX «EEE d MMM» (e.g. «vie 26 jun») for `dayLongLabel`. (Was shared with the retired date
    /// header; now the experiment-end label is its only user. FER-436.)
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_MX")
        f.dateFormat = "EEE d MMM"
        return f
    }()
}

/// Running-experiment display model (computed once per refresh).
private struct ExperimentVM {
    let row: ExperimentRow
    let elapsedDay: Int
    let adherent: Int
    let verdictDate: String
}

// MARK: - Insight sheet item

/// Identifiable wrapper so an `Insight` can ride `.sheet(item:)` (it isn't Identifiable).
private struct InsightItem: Identifiable {
    let id = UUID()
    let insight: Insight
}

/// Identifiable wrapper so a `ReadinessEngine.Signal` can ride `.sheet(item:)`. FER-437.
private struct SignalItem: Identifiable {
    let signal: ReadinessEngine.Signal
    var id: String { signal.key }
}
#endif
