#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore

// MARK: - Patrones (formerly «el Bucle» / Coach)
//
// «Patrones» — the Coach tab redesigned (FER-292 → Patrones). The screen exists to tell you things
// about yourself you didn't know — patterns that emerge from your data alone — and to put them to the
// test with experiments. The cycle is Descubre → Prueba → Confirma.
//
// Phase 1 (visual skeleton, over the existing `InsightEngine`): the layout, hierarchy and copy of the
// hi-fi handoff, with NO new persistence. Order:
//   1. Header        — wordmark «Patrones» (linked-circles glyph) + the date.
//   2. Hallazgo hero — the most relevant finding, NEVER empty: the strongest lever, else a finding,
//      else a quiet «sigo observando». A candidate lever offers «Probar 1 semana».
//   3. En prueba     — the running N-of-1 experiment (or its verdict). (The streak/«arco» and the
//      marked daily check-in arrive in Phase 2.)
//   4. Anota tu día  — low-friction journal entry → the Sí/No sheet.
//   5. Lo que funciona en ti — your behavior levers, ranked.
//   6. Cómo se relacionan tus métricas — correlations.
//   7. Tu expediente — the by-metric effects explorer.
//
// Retired from this screen (the verdict/recovery lives on «Hoy», not here): Decisión de hoy, Señales,
// Trayectoria, Meta/simulador, «Pregúntale a tus datos».
//
// DNA «Instrumento diurno»: warm paper, one dominant statement, color SOLO in the datum.

/// Theme wrapper: anchors `\.instrumentoTheme` to the single warm day paper (`.base`), then hands off
/// to `PatronesLanding`. (FER-398 retired the by-the-hour tint.)
struct BucleView: View {
    var body: some View {
        PatronesLanding()
            .instrumentoTheme(.base)
    }
}

// MARK: - Landing

private struct PatronesLanding: View {
    @EnvironmentObject var repo: Repository
    @Environment(\.instrumentoTheme) private var theme

    // Loaded once per refresh (never recomputed per render).
    @State private var insights: [Insight] = []
    @State private var usableNights = 0
    @State private var journalAnswered = 0
    @State private var journalTotal = 0
    /// Recent recovery series (last 14 nights) for the trend-finding glyph.
    @State private var trendSpark: [Double] = []
    /// Identity keys of findings that surfaced recently (≤48 h) — the hero leads with one as «Nuevo». FER-466.
    @State private var newInsightKeys: Set<String> = []
    @State private var loaded = false

    // N-of-1 experiment state (FER-307). One at a time: either a running experiment, or the most-recent
    // finished verdict the user hasn't dismissed, or neither.
    @State private var running: ExperimentProgress? = nil
    @State private var finished: ExperimentRow? = nil
    /// The completed experiment the user has acknowledged — so its verdict card stops showing. Local,
    /// per-device; the «probado» promotion in «Lo que funciona» is the durable record either way.
    @AppStorage("fer307.dismissedExperimentId") private var dismissedExperimentId = ""

    // Sheets.
    /// One lever/finding detail sheet — fed by the hero, «Lo que funciona» and the correlations.
    @State private var detail: InsightItem? = nil
    /// The candidate lever a start-experiment confirmation sheet is open for.
    @State private var startLever: InsightItem? = nil
    @State private var showEfectos = false
    @State private var showAnota = false
    /// Generic info explainer (the ⓘ on a section). FER-312.
    @State private var info: BucleInfo? = nil
    /// The running experiment whose detail sheet is open (racha + effect chart). FER-462/2b.
    @State private var experimentDetail: ExperimentItem? = nil

    /// Nights of own history the engine needs before it speaks with confidence.
    private static let calibrationTarget = 14

    /// Genuine cold-start: not enough own history yet for any finding. The calibrating hero shows.
    private var genuineColdStart: Bool {
        !loaded || usableNights < Self.calibrationTarget
    }

    /// Nights still needed before the first findings (cold-start copy). ≥1 while genuinely cold.
    private var nightsRemaining: Int { max(0, Self.calibrationTarget - usableNights) }

    /// Section rhythm: tighter when an experiment occupies the screen (handoff «comprimido»).
    private var sectionGap: CGFloat { running != nil ? 18 : NoopMetrics.sectionGap }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: sectionGap) {
                header
                if genuineColdStart {
                    coldStartHero
                    coldStartAnota
                    loQueVerasSection
                } else {
                    heroSection
                    enPruebaSection
                    anotaSection
                    loQueFuncionaSection
                    relacionesSection
                    expedienteSection
                }
            }
            .padding(.horizontal, NoopMetrics.screenPadding)
            .padding(.top, 14)
            .padding(.bottom, NoopMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.paper.ignoresSafeArea())
        .task(id: repo.refreshSeq) { await load() }
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
        .sheet(item: $experimentDetail) { item in
            ExperimentDetailSheet(row: item.row, theme: theme) { Task { await load() } }
                .instrumentoTheme(theme)
                .environmentObject(repo)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center) {
            HStack(spacing: 9) {
                PatronesGlyph(color: theme.ink).frame(width: 22, height: 22)
                Text("Patrones")
                    .font(.system(size: 21, weight: .semibold)).tracking(-0.3)
                    .foregroundStyle(theme.ink)
            }
            Spacer()
            Text(Self.dateLabel)
                .font(StrandFont.mono(11)).foregroundStyle(theme.inkTertiary)
                .textCase(.uppercase)
        }
        .padding(.bottom, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Patrones")
    }

    /// Today as «JUE 12 JUN» (es-MX, uppercased by the header).
    private static var dateLabel: String { dateHeader.string(from: Date()) }

    private static let dateHeader: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "es_MX"); f.dateFormat = "EEE d MMM"; return f
    }()

    // MARK: Hallazgo hero (never empty — plan C, over the existing engine)
    //
    // Leads with the single most relevant finding (the engine already ranks by significance × effect ×
    // recency). A behavior lever renders as «Tu palanca más fuerte» with a «Probar 1 semana» CTA; any
    // other finding renders with its datum + «Ver por qué». When nothing has surfaced yet (history is
    // sufficient but no finding cleared the bar), a quiet «sigo observando» keeps the hero non-empty.

    /// The freshest non-behavior finding still within the «new» window — an anomaly/trend/correlation
    /// that just surfaced from your data. It leads the hero with the «Nuevo» badge. Behavior levers are
    /// excluded: the «sin que anotaras» framing is for findings that emerge without you logging. FER-466.
    private var heroNewFinding: Insight? {
        insights.first { $0.kind != .behavior && newInsightKeys.contains(InsightFreshness.key(for: $0)) }
    }

    /// The lead finding: a fresh finding if there is one, else the top-ranked insight.
    private var heroInsight: Insight? { heroNewFinding ?? insights.first }

    @ViewBuilder private var heroSection: some View {
        if let hero = heroInsight {
            if heroNewFinding == hero {
                findingHero(hero, isNew: true)
            } else if hero.kind == .behavior, hero.lever != nil {
                leverHero(hero)
            } else {
                findingHero(hero, isNew: false)
            }
        } else {
            observingHero
        }
    }

    private func leverHero(_ insight: Insight) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: "arrow.up").font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.inkTertiary)
                Text("Tu palanca más fuerte").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            }
            Text(heroLeverHeadline(insight))
                .font(.system(size: 27, weight: .semibold)).tracking(-0.4)
                .lineSpacing(2)
                .foregroundStyle(theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 13)
            heroDatumRow(insight, context: "\(insight.evidence.n) noches medidas")
                .padding(.top, 15)
            heroActions(insight, canProbar: running == nil && insight.confidence != .proven)
                .padding(.top, 18)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func findingHero(_ insight: Insight, isNew: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if isNew {
                HStack(spacing: 7) {
                    Image(systemName: "sparkles").font(.system(size: 12, weight: .semibold))
                    Text("Nuevo · lo notamos sin que anotaras").instrumentoOverline()
                }
                .foregroundStyle(theme.dataRecovery)
            } else {
                Text(BucleFormat.kindLabel(insight.kind)).instrumentoOverline().foregroundStyle(theme.inkTertiary)
            }
            Text(insight.title)
                .font(.system(size: 27, weight: .semibold)).tracking(-0.4)
                .lineSpacing(2)
                .foregroundStyle(theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 13)
            heroDatumRow(insight, context: "\(insight.datum.metric) · visto en \(insight.evidence.n) días")
                .padding(.top, 15)
            heroActions(insight, canProbar: false)
                .padding(.top, 18)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The hero datum: a signed arrow + the magnitude in the data hue + a quiet context clause.
    private func heroDatumRow(_ insight: Insight, context: String) -> some View {
        let good = BucleFormat.isGood(insight)
        let value = insight.datum.value
        let arrow = value > 0 ? "arrow.up" : (value < 0 ? "arrow.down" : "arrow.right")
        return HStack(spacing: 9) {
            HStack(spacing: 4) {
                Image(systemName: arrow).font(.system(size: 13, weight: .heavy))
                Text(BucleFormat.signedDelta(value, unit: insight.datum.unit))
                    .font(StrandFont.mono(21, weight: .semibold))
            }
            .foregroundStyle(good ? theme.positiveText : theme.critical)
            Text(context)
                .font(StrandFont.captionNumber).foregroundStyle(theme.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The hero's action row: an optional filled «Probar 1 semana» (starts an experiment from the lever)
    /// + a quiet «Ver por qué» that opens the finding's evidence.
    private func heroActions(_ insight: Insight, canProbar: Bool) -> some View {
        HStack(spacing: 16) {
            if canProbar {
                Button { startLever = InsightItem(insight: insight) } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "flask").font(.system(size: 14, weight: .semibold))
                        Text("Probar 1 semana").font(StrandFont.headline)
                    }
                    .foregroundStyle(theme.paper)
                    .padding(.horizontal, 20).padding(.vertical, 11)
                    .background(theme.dataRecovery,
                                in: RoundedRectangle(cornerRadius: NoopMetrics.controlRadius, style: .continuous))
                    .shadow(color: theme.dataRecovery.opacity(0.25), radius: 3, x: 0, y: 1)
                }
                .buttonStyle(.plain)
            }
            Button { detail = InsightItem(insight: insight) } label: {
                HStack(spacing: 4) {
                    Text("Ver por qué").font(StrandFont.subhead)
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(theme.inkSecondary)
            }
            .buttonStyle(.plain)
        }
    }

    /// History is sufficient but no finding has cleared the bar yet — keep the hero non-empty with a
    /// quiet observing state that routes to the journal (which creates the candidates).
    private var observingHero: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Sigo observando").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            Text("Aún no hay un patrón claro en tu cuerpo.")
                .font(.system(size: 26, weight: .semibold)).tracking(-0.3)
                .foregroundStyle(theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
            Text("Sigo revisando tus noches. Anota tus días para que encuentre antes lo que te mueve.")
                .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)
        }
    }

    /// A natural-language headline for the strongest lever: «<hábito> sube/baja <métrica>.»
    private func heroLeverHeadline(_ insight: Insight) -> String {
        let name = BucleFormat.behaviorName(insight)
        let verb = insight.datum.value >= 0 ? "sube" : "baja"
        return "\(name) \(verb) \(Self.metricPhrase(insight.datum.metric))."
    }

    private static func metricPhrase(_ metric: String) -> String {
        switch metric {
        case "Recuperación": return "tu recuperación"
        case "HRV":          return "tu HRV"
        case "Sueño":        return "tu sueño"
        case "FC en reposo": return "tu FC en reposo"
        default:             return "tu \(metric)"
        }
    }

    // MARK: En prueba · tu racha (running experiment / verdict, FER-307 + FER-462)
    //
    // The cycle's «Prueba» beat. A running journal experiment shows its racha — the consecutive nights
    // kept (the «arco») + your best run — and the marked daily check-in that keeps it alive. Diet (no
    // Sí/No log) falls back to the plain progress module. The verdict module is unchanged.

    @ViewBuilder private var enPruebaSection: some View {
        if let p = running {
            if p.supportsStreak {
                experimentStreakSection(p)
            } else {
                experimentProgressSection(p)
            }
        } else if let fin = finished {
            experimentVerdictSection(fin)
        }
    }

    /// The racha module: streak number + «arco» + best run + the marked daily check-in.
    private func experimentStreakSection(_ p: ExperimentProgress) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("En prueba · tu racha").instrumentoOverline().foregroundStyle(theme.dataRecovery)
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "flame").font(.system(size: 11, weight: .medium))
                    Text("Mejor: \(p.streakBest)").font(StrandFont.captionNumber)
                }
                .foregroundStyle(theme.inkTertiary)
            }
            .padding(.top, 18)
            .overlay(alignment: .top) { Rectangle().fill(theme.hairline).frame(height: 0.5).padding(.top, -2) }

            Button { experimentDetail = ExperimentItem(row: p.row) } label: {
                VStack(alignment: .leading, spacing: 0) {
                    Text(BucleFormat.behaviorLabel(p.row.behavior))
                        .font(StrandFont.title2).foregroundStyle(theme.ink).padding(.top, 11)
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text("\(p.streakCurrent)").font(StrandFont.number(34)).foregroundStyle(theme.ink)
                        Text(p.streakCurrent == 1 ? "noche seguida" : "noches seguidas")
                            .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                        Spacer(minLength: 8)
                        HStack(spacing: 3) {
                            Text("Ver detalle").font(StrandFont.footnote)
                            Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(theme.inkTertiary)
                    }
                    .padding(.top, 8)
                    StreakArc(filled: p.streakCurrent, total: p.row.windowDays, theme: theme)
                        .padding(.top, 12)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            (Text("Cumpliste ")
                + Text("\(p.adherent) de \(p.elapsedDay)").foregroundColor(theme.ink).bold()
                + Text(" días."))
                .font(StrandFont.body).foregroundStyle(theme.inkSecondary).monospacedDigit().padding(.top, 14)

            if p.pendingCheckIn {
                checkInBox(p).padding(.top, 14)
            }

            Text("Veredicto el \(p.verdictDate)")
                .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary).padding(.top, 14)

            cancelButton(p.row).padding(.top, 16)
        }
    }

    /// The marked daily check-in: today is within the window and unlogged, so a tap writes the answer
    /// to the journal (extending or breaking the racha) and the box disappears on the next load.
    private func checkInBox(_ p: ExperimentProgress) -> some View {
        let question = p.row.behavior.isEmpty ? "¿Lo cumpliste hoy?" : p.row.behavior
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Circle().fill(theme.dataRecovery).frame(width: 8, height: 8)
                Text("Pendiente hoy · Día \(p.elapsedDay)").instrumentoOverline().foregroundStyle(theme.dataRecovery)
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(question).font(StrandFont.headline).foregroundStyle(theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                checkInToggle("Sí", answeredYes: true, behavior: p.row.behavior)
                checkInToggle("No", answeredYes: false, behavior: p.row.behavior)
            }
            .padding(.top, 11)
            Text("Márcalo para no romper la racha.")
                .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary).padding(.top, 8)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(theme.dataRecovery, lineWidth: 1.5))
    }

    private func checkInToggle(_ label: String, answeredYes: Bool, behavior: String) -> some View {
        Button {
            Task {
                await repo.saveJournalAnswer(day: Repository.localDayKey(Date()),
                                             question: behavior, answeredYes: answeredYes)
                await load()
            }
        } label: {
            Text(label).font(StrandFont.captionNumber).foregroundStyle(theme.inkSecondary)
                .frame(minWidth: 30)
                .padding(.horizontal, 15).padding(.vertical, 7)
                .overlay(Capsule().stroke(theme.hairlineStrong, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label), \(behavior)")
    }

    /// The plain progress module (diet, which has no Sí/No check-in): day N of M + adherence count.
    private func experimentProgressSection(_ p: ExperimentProgress) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("En prueba").instrumentoOverline().foregroundStyle(theme.dataRecovery)
                .padding(.top, 18)
                .overlay(alignment: .top) { Rectangle().fill(theme.hairline).frame(height: 0.5).padding(.top, -2) }
            Text(BucleFormat.behaviorLabel(p.row.behavior))
                .font(StrandFont.title2).foregroundStyle(theme.ink).padding(.top, 11)
            Text("a prueba sobre tu \(p.row.outcome)")
                .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary).padding(.top, 3)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Día \(p.elapsedDay)").font(.system(size: 30, weight: .semibold)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .foregroundStyle(theme.ink)
                Text("de \(p.row.windowDays)").font(StrandFont.subhead).foregroundStyle(theme.inkTertiary)
            }
            .padding(.top, 16)

            ProgressView(value: Double(p.elapsedDay), total: Double(p.row.windowDays))
                .tint(theme.dataRecovery).padding(.top, 12)

            (Text("Cumpliste ")
                + Text("\(p.adherent) de \(p.elapsedDay)").foregroundColor(theme.ink).bold()
                + Text(" días."))
                .font(StrandFont.body).foregroundStyle(theme.inkSecondary).monospacedDigit().padding(.top, 16)
            Text("Veredicto el \(p.verdictDate)")
                .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary).padding(.top, 6)

            cancelButton(p.row).padding(.top, 18)
        }
    }

    private func cancelButton(_ row: ExperimentRow) -> some View {
        Button { Task { await repo.cancelExperiment(row); await load() } } label: {
            Text("Cancelar experimento").font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
        }
        .buttonStyle(.plain)
    }

    private func experimentVerdictSection(_ exp: ExperimentRow) -> some View {
        let v = Verdict(rawValue: exp.result ?? "") ?? .insufficient
        return VStack(alignment: .leading, spacing: 0) {
            Text("Tu experimento").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                .padding(.top, 18)
                .overlay(alignment: .top) { Rectangle().fill(theme.hairline).frame(height: 0.5).padding(.top, -2) }
            Text(BucleFormat.verdictHeadline(v))
                .font(.system(size: v == .sustained ? 26 : 24, weight: .semibold))
                .foregroundStyle(theme.ink).fixedSize(horizontal: false, vertical: true).padding(.top, 11)

            // Color only on a sustained effect — a confirmed measured value.
            if v == .sustained, let delta = exp.effectDelta {
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    Text(BucleFormat.signedDelta(delta, unit: outcomeUnit(exp.outcome)))
                        .font(.system(size: 40, weight: .semibold)).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.6)
                        .foregroundStyle(theme.dataRecovery)
                    Text(exp.outcome).font(StrandFont.subhead).foregroundStyle(theme.inkTertiary)
                }
                .padding(.top, 12)
            }

            Text(BucleFormat.verdictReading(v, behavior: BucleFormat.behaviorLabel(exp.behavior),
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

    // MARK: Anota tu día

    private var anotaSection: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(running != nil ? "Anota el resto de tu día" : "Anota tu día")
                .instrumentoOverline().foregroundStyle(theme.ink)
            Button { showAnota = true } label: {
                HStack(spacing: 13) {
                    Image(systemName: "square.and.pencil").font(.system(size: 20)).foregroundStyle(theme.inkSecondary)
                    VStack(alignment: .leading, spacing: 7) {
                        Text(journalAnswered > 0 ? "\(journalAnswered) de \(journalTotal) anotados hoy" : "Marca qué pasó hoy")
                            .font(StrandFont.headline).foregroundStyle(theme.ink).monospacedDigit()
                        if journalAnswered > 0 {
                            HStack(spacing: 5) {
                                ForEach(0..<max(journalTotal, 1), id: \.self) { i in
                                    Capsule().fill(i < journalAnswered ? theme.ink : theme.hairline)
                                        .frame(width: 22, height: 5)
                                }
                            }
                        } else {
                            Text("Entre más sé de tus hábitos, más patrones encuentro")
                                .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                                .fixedSize(horizontal: false, vertical: true)
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

    // MARK: Lo que funciona en ti (palancas curadas)

    @ViewBuilder private var loQueFuncionaSection: some View {
        let levers = curatedLevers
        if !levers.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                sectionLabel("Lo que funciona en ti",
                             trailing: behaviorInsights.count > levers.count ? "Ver todo" : nil,
                             info: .loQueFunciona) { showEfectos = true }
                ForEach(Array(levers.enumerated()), id: \.offset) { _, insight in
                    leverRow(insight)
                }
            }
        }
    }

    private func leverRow(_ insight: Insight) -> some View {
        let good = BucleFormat.isGood(insight)
        return Button { detail = InsightItem(insight: insight) } label: {
            HStack(spacing: 13) {
                Image(systemName: insight.datum.value < 0 ? "arrow.down" : "arrow.up")
                    .font(.system(size: 18, weight: .semibold)).foregroundStyle(theme.dataRecovery)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(BucleFormat.behaviorName(insight)).font(StrandFont.body).foregroundStyle(theme.ink)
                    Text("\(insight.evidence.n) noches medidas")
                        .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                }
                Spacer(minLength: 8)
                Text(BucleFormat.signedDelta(insight.datum.value, unit: insight.datum.unit))
                    .font(StrandFont.mono(16, weight: .semibold))
                    .foregroundStyle(good ? theme.positiveText : theme.critical)
            }
            .padding(.vertical, 14)
            .overlay(alignment: .top) { Rectangle().fill(theme.hairline).frame(height: 0.5) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Cómo se relacionan tus métricas (correlaciones)

    @ViewBuilder private var relacionesSection: some View {
        let rels = correlationInsights
        if !rels.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("Cómo se relacionan tus métricas").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                    .padding(.bottom, 2)
                ForEach(Array(rels.enumerated()), id: \.offset) { _, insight in
                    relationRow(insight)
                }
            }
        }
    }

    private func relationRow(_ insight: Insight) -> some View {
        let strong = abs(insight.evidence.effectSize ?? 0) >= 0.5
        return Button { detail = InsightItem(insight: insight) } label: {
            HStack(spacing: 13) {
                BucleFormat.findingGlyph(insight, trendSpark: trendSpark, theme: theme)
                VStack(alignment: .leading, spacing: 3) {
                    Text(insight.title).font(StrandFont.body).foregroundStyle(theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(strong ? "Relación fuerte" : "Relación media")
                        .font(StrandFont.footnote)
                        .foregroundStyle(strong ? theme.positiveText : theme.inkTertiary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.system(size: 15)).foregroundStyle(theme.inkTertiary)
            }
            .padding(.vertical, 14)
            .overlay(alignment: .top) { Rectangle().fill(theme.hairline).frame(height: 0.5) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Tu expediente (explorador por métrica)

    @ViewBuilder private var expedienteSection: some View {
        if !behaviorInsights.isEmpty {
            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 6) {
                    Text("Tu expediente").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                    Button { info = .efectos } label: {
                        Image(systemName: "info.circle").font(.system(size: 12)).foregroundStyle(theme.inkTertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cómo funciona esta sección")
                }
                Button { showEfectos = true } label: {
                    VStack(alignment: .leading, spacing: 14) {
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
                        HStack(spacing: 7) {
                            ForEach(expedienteChips, id: \.self) { chip in
                                Text(chip).font(StrandFont.footnote).foregroundStyle(theme.inkSecondary)
                                    .padding(.horizontal, 11).padding(.vertical, 4)
                                    .overlay(Capsule().stroke(theme.hairlineStrong, lineWidth: 1))
                            }
                        }
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

    /// The metric chips under «Tu expediente» — the outcomes the explorer can break down (those present
    /// in the user's data), in the engine's canonical order so the list can't drift.
    private var expedienteChips: [String] {
        let present = Set(behaviorInsights.map { $0.datum.metric })
        return InsightEngine.Outcome.allCases.map(\.label).filter { present.contains($0) }
    }

    // MARK: Cold start

    private var coldStartHero: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Aún reuniendo señal").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            Text("Pronto tu cuerpo empezará a enseñarte cosas.")
                .font(.system(size: 26, weight: .semibold)).tracking(-0.3)
                .lineSpacing(2)
                .foregroundStyle(theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
            Text("\(min(usableNights, Self.calibrationTarget)) de \(Self.calibrationTarget) noches")
                .font(StrandFont.captionNumber).foregroundStyle(theme.ink).padding(.top, 18)
            calibrationBar.padding(.top, 10)
            Text(nightsRemaining == 1
                 ? "Falta 1 noche con la banda para tus primeros patrones: qué te recupera, qué te desgasta y qué vale la pena probar."
                 : "Faltan \(nightsRemaining) noches con la banda para tus primeros patrones: qué te recupera, qué te desgasta y qué vale la pena probar.")
                .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 16)
        }
    }

    /// A thin paper progress bar for the calibration count (matches the handoff's full-width rule).
    private var calibrationBar: some View {
        GeometryReader { geo in
            let frac = min(1, max(0, Double(usableNights) / Double(Self.calibrationTarget)))
            ZStack(alignment: .leading) {
                Capsule().fill(theme.hairline)
                Capsule().fill(theme.dataRecovery).frame(width: max(6, geo.size.width * CGFloat(frac)))
            }
        }
        .frame(height: 6)
        .accessibilityLabel("\(usableNights) de \(Self.calibrationTarget) noches")
    }

    private var coldStartAnota: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("Adelántate").instrumentoOverline().foregroundStyle(theme.ink)
                .padding(.top, 18)
                .overlay(alignment: .top) { Rectangle().fill(theme.hairline).frame(height: 0.5).padding(.top, -2) }
            Button { showAnota = true } label: {
                HStack(spacing: 13) {
                    Image(systemName: "square.and.pencil").font(.system(size: 20)).foregroundStyle(theme.inkSecondary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Empieza por anotar tu día").font(StrandFont.headline).foregroundStyle(theme.ink)
                        Text("Entre antes anotes, antes encuentro patrones")
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

    /// «Lo que verás aquí» — the three things Patrones will surface once there's enough history. Quiet
    /// (gray) so it reads as a promise, not data.
    private var loQueVerasSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Lo que verás aquí").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                .padding(.bottom, 2)
            comingRow("sparkles", "Hallazgos que tu data revela sola")
            comingRow("arrow.up", "Lo que funciona en ti, ya probado")
            comingRow("flask", "Experimentos para probar un cambio")
        }
    }

    private func comingRow(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 13) {
            Image(systemName: symbol).font(.system(size: 18)).foregroundStyle(theme.hairlineStrong)
                .frame(width: 22)
            Text(text).font(StrandFont.body).foregroundStyle(theme.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 14)
        .overlay(alignment: .top) { Rectangle().fill(theme.hairline).frame(height: 0.5) }
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

    // MARK: Derived collections

    /// Behavior-kind insights (the «palancas» universe), already ranked, minus whatever leads the hero.
    private var behaviorInsights: [Insight] {
        insights.filter { $0.kind == .behavior && !isHero($0) }
    }

    /// Correlations (top few), minus whatever leads the hero.
    private var correlationInsights: [Insight] {
        Array(insights.filter { $0.kind == .correlation && !isHero($0) }.prefix(3))
    }

    /// Whether an insight is the one currently leading the hero (so the lists don't repeat it).
    private func isHero(_ insight: Insight) -> Bool { heroInsight == insight }

    /// Top 3 levers, deduped by behavior (a behavior can move several metrics — keep its best).
    private var curatedLevers: [Insight] {
        var seen = Set<String>()
        var out: [Insight] = []
        for i in behaviorInsights {
            if seen.insert(BucleFormat.behaviorName(i)).inserted { out.append(i) }
            if out.count == 3 { break }
        }
        return out
    }

    // MARK: Experiment helpers

    /// Whether tapping «Probar» on a lever may start an experiment: a candidate behavior lever and
    /// nothing is in flight (MVP one-at-a-time).
    private func canStartExperiment(_ insight: Insight) -> Bool {
        running == nil && insight.kind == .behavior && insight.lever != nil && insight.confidence != .proven
    }

    /// Native unit for an experiment's outcome path, via the single typed source (`InsightEngine.Outcome`,
    /// FER-353); `pts` covers Recuperación and any unknown label.
    private func outcomeUnit(_ metric: String) -> String {
        InsightEngine.Outcome(label: metric)?.unit ?? "pts"
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
        // (adherence ≥ threshold), restricted to the days actually tracked (its eligible universe).
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

        // Freshness (FER-466): stamp first-seen per finding, decay after ~48 h. The hero leads with a
        // fresh non-behavior finding as «Nuevo». Persisted in UserDefaults — no engine/DB change.
        let freshKeys = InsightFreshness.refresh(
            currentKeys: Set(generated.map { InsightFreshness.key(for: $0) }),
            now: Date().timeIntervalSince1970)

        let importedQs = NSOrderedSet(array: imported.map(\.question)).array as? [String] ?? []
        let catalog = JournalCatalogStore.mergeCatalog(imported: importedQs, custom: [])
        let nights = days.filter { $0.avgHrv != nil }.count
        let spark = Array(days.compactMap { $0.recovery }.suffix(14))

        // Experiment state: a running one (with live progress + adherence), else the latest finished
        // verdict the user hasn't dismissed.
        let active = await repo.activeExperiment()
        var runVM: ExperimentProgress? = nil
        if let active { runVM = await repo.experimentProgress(active, today: todayKey) }
        let allExp = await repo.allExperiments()
        let latestFinished = active == nil
            ? allExp.first { $0.status == .completed && $0.id != dismissedExperimentId }
            : nil

        await MainActor.run {
            self.insights = generated
            self.newInsightKeys = freshKeys
            self.usableNights = nights
            self.journalAnswered = todayAnswers.count
            self.journalTotal = max(catalog.count, 1)
            self.trendSpark = spark
            self.running = runVM
            self.finished = latestFinished
            self.loaded = true
        }
    }

}

// MARK: - Experiment display model + data (FER-462 / 2b)

/// Running-experiment display model (computed once per refresh) — progress + the racha. Internal so the
/// detail sheet (`ExperimentDetailSheet`) can share the same computation.
struct ExperimentProgress {
    let row: ExperimentRow
    let elapsedDay: Int
    let adherent: Int
    let verdictDate: String
    /// Consecutive nights kept (trailing run) and best run so far — derived from the journal history.
    let streakCurrent: Int
    let streakBest: Int
    /// Today is within the window and not yet recorded → show the marked daily check-in.
    let pendingCheckIn: Bool
    /// The racha / «arco» / check-in apply (journal behaviors). Diet falls back to plain progress.
    let supportsStreak: Bool
}

/// The «recuperación durante el experimento» chart data: the outcome line over the window, the «media
/// antes» baseline (the level before it started), and the signed lift since.
struct ExperimentEffect {
    let values: [Double]      // outcome over [startDay, today], ascending
    let beforeMean: Double?   // mean outcome over days before startDay (nil when there's no baseline)
    let delta: Double?        // mean(values) − beforeMean (nil when either is missing)
    let unit: String
}

extension Repository {
    /// Live progress + racha of a running experiment. Journal behaviors get the consecutive/best streak
    /// and the pending check-in; diet (no Sí/No log) gets plain progress (`supportsStreak == false`).
    func experimentProgress(_ row: ExperimentRow, today: String) async -> ExperimentProgress {
        let elapsed = max(1, min(row.windowDays, ExperimentDates.dayspan(from: row.startDay, to: today) + 1))
        let adherentSet = await adherentDays(behavior: row.behavior, from: row.startDay, to: today)
        let verdictDate = Repository.experimentEndDay(row).flatMap(ExperimentDates.longLabelES) ?? "—"

        let isDiet = row.behavior == JournalCatalogStore.dietBehaviorKey
        var current = 0, best = 0, pending = false
        if !isDiet {
            let answeredToday = (await nativeJournalAnswers(day: today))[row.behavior] != nil
            // Eligible = the window's calendar days up to today; drop a still-pending today so an unmarked
            // today reads as «not broken yet», not as a miss.
            var eligible = ExperimentDates.dayKeys(from: row.startDay, to: today)
            if !answeredToday { eligible.removeAll { $0 == today } }
            let s = StreakMath.streaks(eligibleDays: eligible, adherent: adherentSet)
            current = s.current
            best = s.best
            let withinWindow = Repository.experimentEndDay(row).map { today < $0 } ?? true
            pending = withinWindow && !answeredToday
        }
        return ExperimentProgress(row: row, elapsedDay: elapsed, adherent: adherentSet.count,
                                  verdictDate: verdictDate, streakCurrent: current, streakBest: best,
                                  pendingCheckIn: pending, supportsStreak: !isDiet)
    }

    /// The effect-chart data: the outcome over the experiment window vs the mean of the days before it.
    func experimentEffect(_ row: ExperimentRow, today: String) async -> ExperimentEffect {
        let series = InsightEngine.outcomeSeries(days, metric: row.outcome)
        let values = ExperimentDates.dayKeys(from: row.startDay, to: today).compactMap { series[$0] }
        let before = series.filter { $0.key < row.startDay }.map(\.value)
        let beforeMean = before.isEmpty ? nil : before.reduce(0, +) / Double(before.count)
        let windowMean = values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        let delta: Double? = (beforeMean != nil && windowMean != nil) ? windowMean! - beforeMean! : nil
        let unit = InsightEngine.Outcome(label: row.outcome)?.unit ?? "pts"
        return ExperimentEffect(values: values, beforeMean: beforeMean, delta: delta, unit: unit)
    }
}

/// Day-key arithmetic shared by the experiment progress + effect computations.
enum ExperimentDates {
    /// Whole days from `a` to `b` ("yyyy-MM-dd"), 0 when same day, clamped at 0.
    static func dayspan(from a: String, to b: String) -> Int {
        guard let da = parse.date(from: a), let db = parse.date(from: b) else { return 0 }
        return max(0, Calendar.current.dateComponents([.day], from: da, to: db).day ?? 0)
    }

    /// Ascending calendar day-keys from `a` to `b` inclusive; empty if `a` > `b` or parse fails.
    static func dayKeys(from a: String, to b: String) -> [String] {
        guard let da = parse.date(from: a), let db = parse.date(from: b), da <= db else { return [] }
        let cal = Calendar.current
        var out: [String] = []
        var d = da
        while d <= db {
            out.append(parse.string(from: d))
            guard let next = cal.date(byAdding: .day, value: 1, to: d) else { break }
            d = next
        }
        return out
    }

    /// es-MX «vie 26 jun» for a day key.
    static func longLabelES(_ key: String) -> String? {
        parse.date(from: key).map { longES.string(from: $0) }
    }

    static let parse: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static let longES: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "es_MX"); f.dateFormat = "EEE d MMM"
        return f
    }()
}

// MARK: - Insight sheet item

/// Identifiable wrapper so an `Insight` can ride `.sheet(item:)` (it isn't Identifiable).
private struct InsightItem: Identifiable {
    let id = UUID()
    let insight: Insight
}

/// Identifiable wrapper so an `ExperimentRow` can ride `.sheet(item:)` for the detail sheet.
private struct ExperimentItem: Identifiable {
    let id = UUID()
    let row: ExperimentRow
}

// MARK: - Insight freshness (FER-466)

/// Tracks which findings surfaced recently so the hero can lead with «Nuevo». The `InsightEngine` is
/// stateless (it recomputes every run), so freshness lives here: a per-device first-seen timestamp per
/// insight identity, persisted in UserDefaults (no DB migration — it's a UI nicety). A finding stays
/// «new» for `ttl` after it first appears; if it disappears and returns, it reads as new again.
enum InsightFreshness {
    /// How long a finding stays «new» after first surfacing (~2 days).
    static let ttl: TimeInterval = 48 * 3600
    private static let storeKey = "fer466.insightFirstSeen"

    /// A stable identity across engine runs — the title may be LLM-rewritten, so key on structure.
    static func key(for insight: Insight) -> String {
        "\(insight.kind.rawValue)|\(insight.datum.metric)|\(insight.lever?.behavior ?? "")"
    }

    /// Stamp first-seen for any newly-present key, prune keys no longer present, persist, and return the
    /// subset still within `ttl`. `now` is unix seconds; `defaults` is injectable for testing.
    static func refresh(currentKeys: Set<String>, now: Double,
                        defaults: UserDefaults = .standard) -> Set<String> {
        var map = (defaults.dictionary(forKey: storeKey) as? [String: Double]) ?? [:]
        map = map.filter { currentKeys.contains($0.key) }
        for k in currentKeys where map[k] == nil { map[k] = now }
        defaults.set(map, forKey: storeKey)
        return Set(map.filter { now - $0.value < ttl }.keys)
    }
}
#endif
