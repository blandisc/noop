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
    /// «Diseña tu propio experimento» builder. FER-468.
    @State private var showDisena = false
    /// «Relaciona dos métricas tú mismo» (§5) → the Compare overlay, the same screen as Cuerpo. FER (Patrones v2).
    @State private var showCompare = false
    /// «Empezar de cero» confirmation — wipes the user-contributed journal + experiments. Irreversible.
    @State private var showResetConfirm = false
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

    var body: some View {
        ScrollView {
            // One narrative ordered by the six goals (Patrones v2). §1 is the serif revelation hero;
            // §2–§6 are numbered sections each opened by a hairline + numbered dot. The hero swaps to the
            // calibrating state until there's enough history; §6 (the archive) hides while it's empty.
            VStack(alignment: .leading, spacing: 0) {
                header
                if genuineColdStart {
                    calibratingHero
                } else {
                    heroSection
                }
                correlacionesSection   // §2 · Correlaciones que no veías
                pruebaSection          // §3 · Pon a prueba algo nuevo
                confirmadoSection      // §4 · Confirmado · funciona en ti
                aportaSection          // §5 · Aporta lo tuyo
                expedienteSection      // §6 · Tu expediente
                if hasContributed { resetFooter }
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
        .sheet(isPresented: $showDisena) {
            DisenaExperimentoSheet(theme: theme) { behavior, outcome, sign, window in
                await repo.startExperiment(behavior: behavior, outcome: outcome,
                                           expectedSign: sign, windowDays: window)
                showDisena = false
                await load()
            }
            .instrumentoTheme(theme)
            .environmentObject(repo)
        }
        .sheet(isPresented: $showCompare) {
            // §5 «Relaciona dos métricas tú mismo» reuses the Compare overlay (same as Cuerpo): the theme
            // is injected at the root (it doesn't cross the `.sheet` boundary) and `repo` is re-supplied.
            CompareView()
                .instrumentoTheme(theme)
                .environmentObject(repo)
        }
        .confirmationDialog("Start from scratch?", isPresented: $showResetConfirm, titleVisibility: .visible) {
            Button("Delete what I logged", role: .destructive) {
                Task {
                    await repo.resetContributedPatrones()
                    dismissedExperimentId = ""
                    await load()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This erases everything you contributed — your day journal and all your experiments (with their verdicts). The patterns detected from your body stay, and your imported WHOOP history is untouched. This can't be undone.")
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
                .font(StrandFont.number(11, weight: .regular)).foregroundStyle(theme.inkTertiary)
                .textCase(.uppercase)
        }
        .padding(.bottom, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Patrones")
    }

    /// Today as «JUE 12 JUN» — follows the app language (es → «JUE», en → «THU»). FER-472.
    private static var dateLabel: String { dateHeader.string(from: Date()) }

    private static let dateHeader: DateFormatter = {
        let f = DateFormatter(); f.locale = .current; f.dateFormat = "EEE d MMM"; return f
    }()

    // MARK: §1 · Lo que no sabías de ti (the revelation hero — never empty)
    //
    // The screen's lead: the single strongest passive revelation, in serif, framed «sin que lo anotaras».
    // Prefers a fresh finding, then any non-behavior finding, then the top insight; a behavior lever is
    // only the fallback (when nothing passive has surfaced), and keeps its own framing. When the engine
    // has nothing yet (history sufficient, no finding cleared the bar), a quiet «sigo observando» shows.

    /// The freshest non-behavior finding still within the «new» window — an anomaly/trend/correlation
    /// that just surfaced from your data, so the hero can lead with it. FER-466.
    private var heroNewFinding: Insight? {
        insights.first { $0.kind != .behavior && newInsightKeys.contains(InsightFreshness.key(for: $0)) }
    }

    /// The lead finding: a fresh finding, else the top non-behavior finding, else the top-ranked insight.
    private var heroInsight: Insight? {
        heroNewFinding ?? insights.first { $0.kind != .behavior } ?? insights.first
    }

    private var heroSection: some View {
        Group {
            if let hero = heroInsight {
                if hero.kind == .behavior, hero.lever != nil {
                    leverHero(hero)
                } else {
                    revelationHero(hero)
                }
            } else {
                observingHero
            }
        }
        .padding(.top, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A passive revelation: «Lo que no sabías de ti» overline (spark, green) → serif headline → the
    /// signed datum + «sin que lo anotaras» → «Ver por qué».
    private func revelationHero(_ insight: Insight) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: "sparkles").font(.system(size: 13, weight: .semibold))
                Text("What you didn't know about yourself").instrumentoOverline()
            }
            .foregroundStyle(theme.dataRecovery)
            Text(insight.title)
                .font(StrandFont.serif(28)).lineSpacing(1)
                .foregroundStyle(theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 11)
            heroDatumRow(insight, context: String(localized: "without you logging it · \(insight.evidence.n) days"))
                .padding(.top, 12)
            heroActions(insight, canProbar: false).padding(.top, 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The behavior-lever fallback hero — its own framing (it came from your logging, not «sin anotar»),
    /// serif headline, with a «Probar 1 semana» CTA when an experiment can start.
    private func leverHero(_ insight: Insight) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: "arrow.up").font(.system(size: 12, weight: .semibold))
                Text("Your strongest lever").instrumentoOverline()
            }
            .foregroundStyle(theme.inkTertiary)
            Text(heroLeverHeadline(insight))
                .font(StrandFont.serif(28)).lineSpacing(1)
                .foregroundStyle(theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 11)
            heroDatumRow(insight, context: String(localized: "\(insight.evidence.n) nights measured"))
                .padding(.top, 12)
            heroActions(insight, canProbar: running == nil && insight.confidence != .proven)
                .padding(.top, 14)
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
                    .font(StrandFont.number(21, weight: .semibold))
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
                        Text("Try 1 week").font(StrandFont.headline)
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
                    Text("See why").font(StrandFont.subhead)
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(theme.inkSecondary)
            }
            .buttonStyle(.plain)
        }
    }

    /// History is sufficient but no finding has cleared the bar yet — keep the hero non-empty.
    private var observingHero: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: "binoculars").font(.system(size: 12, weight: .semibold))
                Text("Still watching").instrumentoOverline()
            }
            .foregroundStyle(theme.inkTertiary)
            Text("No clear pattern in your body yet.")
                .font(StrandFont.serif(27))
                .foregroundStyle(theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 11)
            Text("I'm still reviewing your nights. Log your days so I find what moves you sooner.")
                .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
        }
    }

    /// A natural-language headline for a lever: «<habit> raises/lowers <metric>.» The habit name is data
    /// (its localized label); the sentence template is localized per direction × metric. FER-472.
    private func heroLeverHeadline(_ insight: Insight) -> String {
        let name = BucleFormat.behaviorName(insight)
        let up = insight.datum.value >= 0
        switch insight.datum.metric {
        case "Recuperación": return up ? String(localized: "\(name) raises your recovery.")
                                       : String(localized: "\(name) lowers your recovery.")
        case "HRV":          return up ? String(localized: "\(name) raises your HRV.")
                                       : String(localized: "\(name) lowers your HRV.")
        case "Sueño":        return up ? String(localized: "\(name) improves your sleep.")
                                       : String(localized: "\(name) worsens your sleep.")
        case "FC en reposo": return up ? String(localized: "\(name) raises your resting HR.")
                                       : String(localized: "\(name) lowers your resting HR.")
        default:             return up ? String(localized: "\(name) raises your \(insight.datum.metric).")
                                       : String(localized: "\(name) lowers your \(insight.datum.metric).")
        }
    }

    // MARK: §2 · Correlaciones que no veías (passive findings)

    private var correlacionesSection: some View {
        section(2, "Correlations you couldn't see") {
            let rels = correlationInsights
            if rels.isEmpty {
                emptyBox("I haven't found clear links yet. They'll show up here as soon as I see them.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(rels.enumerated()), id: \.offset) { _, insight in
                        relationRow(insight)
                    }
                }
                .padding(.top, 4)
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
                    Text(strong ? String(localized: "Strong relationship") : String(localized: "Medium relationship"))
                        .font(StrandFont.footnote)
                        .foregroundStyle(strong ? theme.positiveText : theme.inkTertiary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.system(size: 15)).foregroundStyle(theme.inkTertiary)
            }
            .padding(.vertical, 13)
            .overlay(alignment: .top) { Rectangle().fill(theme.hairline).frame(height: 0.5) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: §3 · Pon a prueba algo nuevo (the running experiment + builder)
    //
    // The «Prueba» beat. A running journal experiment shows a compact card — chip, title, 7-segment streak
    // bar, the inline Sí/No check-in (or its «registrado» record once marked) — tappable into the racha +
    // effect-chart detail. With nothing running, a «Sugerido para ti» card (seeded from a candidate lever)
    // or, on a verdict, the result card. A dashed «Diseña un experimento» row always closes the section.

    private var pruebaSection: some View {
        section(3, "Put something new to the test") {
            Text(pruebaIntro)
                .font(StrandFont.subhead).foregroundStyle(theme.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
            if let p = running {
                if p.supportsStreak { streakCard(p) } else { dietProgressCard(p) }
            } else if let fin = finished {
                verdictCard(fin)
            } else if let s = suggestedLever {
                suggestedCard(s)
            }
            disenaRow
        }
    }

    private var pruebaIntro: LocalizedStringKey {
        if genuineColdStart { return "You don't have to wait — an experiment speeds up what I learn about you." }
        if running != nil { return "Turn a hunch into a correlation of your own." }
        return "You don't have any experiment running right now."
    }

    /// The running journal experiment, as the compact card (Option A): tappable into the racha + effect
    /// detail via the footer row.
    private func streakCard(_ p: ExperimentProgress) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                recChip(String(localized: "On trial · \(p.streakCurrent)/\(p.row.windowDays)"))
                Spacer()
                Text("Verdict \(p.verdictDate)")
                    .font(StrandFont.number(11, weight: .regular)).foregroundStyle(theme.inkTertiary)
            }
            Text(BucleFormat.behaviorLabel(p.row.behavior))
                .font(StrandFont.title2).foregroundStyle(theme.ink).padding(.top, 10)
            streakBar(filled: min(p.streakCurrent, p.row.windowDays), total: p.row.windowDays)
                .padding(.top, 11)
            if p.pendingCheckIn {
                checkInRow(p).padding(.top, 13)
            } else if let yes = p.markedYesToday {
                markedRecord(yes: yes, behavior: p.row.behavior).padding(.top, 13)
            }
            detailFooter(p.row, leading: String(localized: "Best streak \(p.streakBest) · see effect chart"))
        }
        .pruebaCard(theme, border: theme.dataRecovery)
    }

    /// Diet (no Sí/No log) keeps a plain progress card — day N of M + adherence — also tappable to detail.
    private func dietProgressCard(_ p: ExperimentProgress) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                recChip(String(localized: "On trial · \(p.elapsedDay)/\(p.row.windowDays)"))
                Spacer()
                Text("Verdict \(p.verdictDate)")
                    .font(StrandFont.number(11, weight: .regular)).foregroundStyle(theme.inkTertiary)
            }
            Text(BucleFormat.behaviorLabel(p.row.behavior))
                .font(StrandFont.title2).foregroundStyle(theme.ink).padding(.top, 10)
            ProgressView(value: Double(p.elapsedDay), total: Double(p.row.windowDays))
                .tint(theme.dataRecovery).padding(.top, 12)
            Text("Kept **\(p.adherent) of \(p.elapsedDay)** days.")
                .font(StrandFont.body).foregroundStyle(theme.inkSecondary).monospacedDigit().padding(.top, 12)
            detailFooter(p.row, leading: String(localized: "See effect chart"))
        }
        .pruebaCard(theme, border: theme.dataRecovery)
    }

    /// 7-segment streak bar — one segment per window day, filled green for the current streak.
    private func streakBar(filled: Int, total: Int) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<max(total, 1), id: \.self) { i in
                Capsule().fill(i < filled ? theme.dataRecovery : theme.hairline).frame(height: 7)
            }
        }
        .accessibilityLabel("\(filled) of \(total)")
    }

    /// The inline daily check-in (today within the window, unmarked): a tap writes the answer and reloads.
    private func checkInRow(_ p: ExperimentProgress) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Did you keep it today?").font(StrandFont.subhead).foregroundStyle(theme.ink)
            Spacer(minLength: 8)
            HStack(spacing: 7) {
                checkInToggle("Yes", answeredYes: true, behavior: p.row.behavior)
                checkInToggle("No", answeredYes: false, behavior: p.row.behavior)
            }
        }
    }

    private func checkInToggle(_ label: LocalizedStringKey, answeredYes: Bool, behavior: String) -> some View {
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
        .accessibilityLabel(label)
    }

    /// The «check-in marcado» record (State 4): today's answer is in, with an inline Deshacer that clears it.
    private func markedRecord(yes: Bool, behavior: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: yes ? "checkmark.circle" : "circle.slash")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(yes ? theme.dataRecovery : theme.inkTertiary)
            VStack(alignment: .leading, spacing: 1) {
                Text(yes ? String(localized: "Kept today · logged") : String(localized: "Missed today · logged"))
                    .font(StrandFont.subhead).foregroundStyle(theme.ink)
                Text("You can still change it").font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
            }
            Spacer(minLength: 8)
            Button {
                Task {
                    await repo.clearJournalAnswer(day: Repository.localDayKey(Date()), question: behavior)
                    await load()
                }
            } label: {
                Text("Undo").font(StrandFont.footnote).foregroundStyle(theme.inkTertiary).underline()
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(yes ? theme.dataRecovery.opacity(0.08) : theme.paperLo,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(yes ? theme.dataRecovery.opacity(0.25) : theme.hairline, lineWidth: 1))
    }

    /// The card footer (Option A) — a quiet tappable row into the experiment's racha + effect-chart detail.
    private func detailFooter(_ row: ExperimentRow, leading: String) -> some View {
        Button { experimentDetail = ExperimentItem(row: row) } label: {
            HStack(spacing: 6) {
                Text(leading).font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.inkTertiary)
            }
            .padding(.top, 12)
            .overlay(alignment: .top) { Rectangle().fill(theme.hairline).frame(height: 0.5) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// The experiment verdict (State 3): a result card. «Funcionó» graduates to §4 (the engine already
    /// auto-promotes the lever) with a Repeat; «sin efecto» offers a one-more-week or discard.
    private func verdictCard(_ exp: ExperimentRow) -> some View {
        let v = Verdict(rawValue: exp.result ?? "") ?? .insufficient
        let worked = v == .sustained
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: worked ? "checkmark.circle" : "minus.circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(worked ? theme.dataRecovery : theme.inkTertiary)
                Text(worked ? String(localized: "Verdict · it worked") : String(localized: "Verdict · no clear effect"))
                    .instrumentoOverline().foregroundStyle(worked ? theme.dataRecovery : theme.inkTertiary)
            }
            Text(BucleFormat.behaviorLabel(exp.behavior))
                .font(StrandFont.title2).foregroundStyle(theme.ink).padding(.top, 11)
            if worked {
                Text(BucleFormat.verdictHeadline(v))
                    .font(StrandFont.serifVerdict).foregroundStyle(theme.ink)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 6)
                verdictStats(exp).padding(.top, 13)
                HStack(spacing: 9) {
                    Button { dismissVerdict(exp) } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark").font(.system(size: 14, weight: .semibold))
                            Text("Save to Confirmed").font(StrandFont.headline)
                        }
                        .foregroundStyle(theme.paper)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(theme.ink, in: RoundedRectangle(cornerRadius: NoopMetrics.controlRadius, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    quietButton("Repeat") { restartExperiment(exp) }
                }
                .padding(.top, 15)
            } else {
                Text(BucleFormat.verdictReading(v, behavior: BucleFormat.behaviorLabel(exp.behavior),
                                                outcome: exp.outcome, adherent: exp.nWith ?? 0,
                                                window: exp.windowDays))
                    .font(StrandFont.body).foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 8)
                HStack(spacing: 9) {
                    Button { restartExperiment(exp) } label: {
                        Text("Try 1 more week").font(StrandFont.headline).foregroundStyle(theme.ink)
                            .frame(maxWidth: .infinity).padding(.vertical, 11)
                            .background(theme.paperLo, in: RoundedRectangle(cornerRadius: NoopMetrics.controlRadius, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: NoopMetrics.controlRadius, style: .continuous)
                                .stroke(theme.hairlineStrong, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    Button { dismissVerdict(exp) } label: {
                        Text("Discard").font(StrandFont.headline).foregroundStyle(theme.inkTertiary)
                            .padding(.horizontal, 14).padding(.vertical, 11)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 14)
            }
        }
        .pruebaCard(theme, border: worked ? theme.dataRecovery : theme.hairlineStrong,
                    fill: worked ? theme.dataRecovery.opacity(0.05) : theme.surface)
    }

    /// The «funcionó» stat row — effect (colored), days kept, confidence.
    private func verdictStats(_ exp: ExperimentRow) -> some View {
        HStack(spacing: 16) {
            verdictStat(String(localized: "Effect"),
                        BucleFormat.signedDelta(exp.effectDelta ?? 0, unit: outcomeUnit(exp.outcome)),
                        color: theme.dataRecovery)
            Rectangle().fill(theme.hairline).frame(width: 1, height: 34)
            verdictStat(String(localized: "Kept"), "\(exp.nWith ?? 0)/\(exp.windowDays)", color: theme.ink)
            Rectangle().fill(theme.hairline).frame(width: 1, height: 34)
            verdictStat(String(localized: "Confidence"), String(localized: "High"), color: theme.ink, big: false)
        }
    }

    private func verdictStat(_ label: String, _ value: String, color: Color, big: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
            Text(value)
                .font(big ? StrandFont.number(22, weight: .semibold) : StrandFont.headline)
                .foregroundStyle(color)
                .padding(.top, big ? 0 : 3)
        }
    }

    /// «Sugerido para ti» (State 2) — a candidate lever offered as a one-tap experiment to start.
    private func suggestedCard(_ insight: Insight) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                recChip(String(localized: "Suggested for you"))
                Spacer()
                Image(systemName: "sparkles").font(.system(size: 15)).foregroundStyle(theme.dataRecovery)
            }
            Text(BucleFormat.behaviorName(insight))
                .font(StrandFont.title2).foregroundStyle(theme.ink).padding(.top, 10)
            Text("I spotted a hunch in your data. Try it 7 nights and I'll tell you if it's real for you.")
                .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 6)
            HStack {
                Spacer()
                Button { startLever = InsightItem(insight: insight) } label: {
                    Text("Start trial").font(StrandFont.headline).foregroundStyle(theme.paper)
                        .padding(.horizontal, 16).padding(.vertical, 9)
                        .background(theme.ink, in: RoundedRectangle(cornerRadius: NoopMetrics.controlRadius, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 13)
        }
        .pruebaCard(theme, border: theme.hairlineStrong)
    }

    /// The dashed «Diseña un experimento» / «Diseña uno tú mismo» row — opens the free builder.
    private var disenaRow: some View {
        Button { showDisena = true } label: {
            HStack(spacing: 11) {
                Image(systemName: "flask").font(.system(size: 18)).foregroundStyle(theme.inkSecondary).frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(running != nil ? String(localized: "Design an experiment") : String(localized: "Design one yourself"))
                        .font(StrandFont.body).foregroundStyle(theme.ink)
                    Text("Pick a habit and measure it for a week")
                        .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: "plus").font(.system(size: 16, weight: .semibold)).foregroundStyle(theme.inkTertiary)
            }
            .padding(.horizontal, 14).padding(.vertical, 13)
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(theme.hairlineStrong, style: StrokeStyle(lineWidth: 1, dash: [4])))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 11)
    }

    private var suggestedLever: Insight? {
        insights.first { $0.kind == .behavior && $0.lever != nil && $0.confidence != .proven }
    }

    private func restartExperiment(_ exp: ExperimentRow) {
        Task {
            dismissedExperimentId = exp.id
            _ = await repo.startExperiment(behavior: exp.behavior, outcome: exp.outcome,
                                           expectedSign: exp.expectedSign, windowDays: exp.windowDays)
            await load()
        }
    }

    private func dismissVerdict(_ exp: ExperimentRow) {
        dismissedExperimentId = exp.id
        finished = nil
    }

    /// A quiet bordered secondary button (paperLo fill) for the verdict actions.
    private func quietButton(_ label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(StrandFont.headline).foregroundStyle(theme.inkSecondary)
                .padding(.horizontal, 16).padding(.vertical, 11)
                .background(theme.paperLo, in: RoundedRectangle(cornerRadius: NoopMetrics.controlRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: NoopMetrics.controlRadius, style: .continuous)
                    .stroke(theme.hairlineStrong, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: §4 · Confirmado · funciona en ti (proven levers)

    private var confirmadoSection: some View {
        let levers = curatedLevers
        return section(4, "Confirmed · works for you",
                       trailing: behaviorInsights.count > levers.count ? String(localized: "See all") : nil,
                       trailingAction: { showEfectos = true }) {
            if levers.isEmpty {
                emptyBox("Nothing proven yet — your experiments will land here.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(levers.enumerated()), id: \.offset) { _, insight in
                        confirmadoRow(insight)
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private func confirmadoRow(_ insight: Insight) -> some View {
        let good = BucleFormat.isGood(insight)
        return Button { detail = InsightItem(insight: insight) } label: {
            HStack(spacing: 12) {
                Image(systemName: "checkmark").font(.system(size: 14, weight: .bold))
                    .foregroundStyle(theme.dataRecovery).frame(width: 18)
                Text(heroLeverHeadline(insight)).font(StrandFont.body).foregroundStyle(theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text(BucleFormat.signedDelta(insight.datum.value, unit: insight.datum.unit))
                    .font(StrandFont.number(15, weight: .semibold))
                    .foregroundStyle(good ? theme.positiveText : theme.critical)
            }
            .padding(.vertical, 13)
            .overlay(alignment: .top) { Rectangle().fill(theme.hairline).frame(height: 0.5) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: §5 · Aporta lo tuyo (journal + relate-two-metrics)

    private var aportaSection: some View {
        section(5, "Add your own") {
            anotaRow.padding(.top, 11)
            relacionaRow.padding(.top, 10)
        }
    }

    private var anotaRow: some View {
        Button { showAnota = true } label: {
            HStack(spacing: 13) {
                Image(systemName: "square.and.pencil").font(.system(size: 20)).foregroundStyle(theme.inkSecondary)
                VStack(alignment: .leading, spacing: 7) {
                    Text("Log your day").font(StrandFont.headline).foregroundStyle(theme.ink)
                    if journalAnswered > 0 {
                        HStack(spacing: 5) {
                            ForEach(0..<max(journalTotal, 1), id: \.self) { i in
                                Capsule().fill(i < journalAnswered ? theme.ink : theme.hairline)
                                    .frame(width: 22, height: 5)
                            }
                        }
                    } else {
                        Text("The more you log, the more patterns I find")
                            .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 15)).foregroundStyle(theme.inkTertiary)
            }
            .surfaceRow(theme)
        }
        .buttonStyle(.plain)
    }

    private var relacionaRow: some View {
        Button { showCompare = true } label: {
            HStack(spacing: 13) {
                Image(systemName: "chart.xyaxis.line").font(.system(size: 20)).foregroundStyle(theme.inkSecondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Relate two metrics yourself").font(StrandFont.headline).foregroundStyle(theme.ink)
                    Text("Feel like something affects you? Put it to the test")
                        .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 15)).foregroundStyle(theme.inkTertiary)
            }
            .surfaceRow(theme)
        }
        .buttonStyle(.plain)
    }

    // MARK: §6 · Tu expediente (the archive)

    @ViewBuilder private var expedienteSection: some View {
        if !behaviorInsights.isEmpty {
            section(6, "Your record · everything found", info: .efectos) {
                Button { showEfectos = true } label: {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 13) {
                            Image(systemName: "tablecells").font(.system(size: 20)).foregroundStyle(theme.inkSecondary)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Text("\(behaviorInsights.count)")
                                        .font(StrandFont.number(20, weight: .semibold)).foregroundStyle(theme.ink)
                                    Text("effects measured").font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                                }
                                Text("Every habit, lever and experiment, archived")
                                    .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 15)).foregroundStyle(theme.inkTertiary)
                        }
                        .padding(16)
                        Rectangle().fill(theme.hairline).frame(height: 0.5)
                        HStack(spacing: 7) {
                            ForEach(expedienteChips, id: \.self) { chip in
                                Text(chip).font(StrandFont.footnote).foregroundStyle(theme.inkSecondary)
                                    .padding(.horizontal, 11).padding(.vertical, 4)
                                    .background(theme.paperLo, in: Capsule())
                            }
                        }
                        .padding(.horizontal, 16).padding(.vertical, 12)
                    }
                    .background(theme.surface, in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous)
                        .stroke(theme.hairlineStrong, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .padding(.top, 11)
            }
        }
    }

    /// The metric chips under «Tu expediente» — the outcomes the explorer can break down (those present
    /// in the user's data), in the engine's canonical order so the list can't drift.
    private var expedienteChips: [String] {
        let present = Set(behaviorInsights.map { $0.datum.metric })
        return InsightEngine.Outcome.allCases.map(\.label).filter { present.contains($0) }
    }

    // MARK: §1 · Calibrating hero (cold start)

    private var calibratingHero: some View {
        let pct = Int((Double(min(usableNights, Self.calibrationTarget)) / Double(Self.calibrationTarget) * 100).rounded())
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: "clock").font(.system(size: 13, weight: .semibold))
                Text("Still watching").instrumentoOverline()
            }
            .foregroundStyle(theme.inkTertiary)
            Text("I'm still learning how your body works.")
                .font(StrandFont.serif(27))
                .foregroundStyle(theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 11)
            Text("I need about two weeks of data to reveal your first pattern with confidence.")
                .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
            VStack(spacing: 6) {
                HStack {
                    Text("\(min(usableNights, Self.calibrationTarget)) of \(Self.calibrationTarget) days")
                        .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                    Spacer()
                    Text(verbatim: "\(pct)%").font(StrandFont.number(11, weight: .regular)).foregroundStyle(theme.inkTertiary)
                }
                calibrationBar
            }
            .padding(.top, 14)
        }
        .padding(.top, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A thin paper progress bar for the calibration count (matches the handoff's full-width rule).
    private var calibrationBar: some View {
        GeometryReader { geo in
            let frac = min(1, max(0, Double(usableNights) / Double(Self.calibrationTarget)))
            ZStack(alignment: .leading) {
                Capsule().fill(theme.hairline)
                Capsule().fill(theme.inkTertiary).frame(width: max(6, geo.size.width * CGFloat(frac)))
            }
        }
        .frame(height: 7)
        .accessibilityLabel("\(usableNights) of \(Self.calibrationTarget) nights")
    }

    // MARK: Section scaffold

    /// A numbered section: a top hairline, a numbered dot + overline label (with optional ⓘ and a trailing
    /// link), then the content. The shared rhythm for §2–§6.
    private func section<Content: View>(_ n: Int, _ title: LocalizedStringKey,
                                        info infoItem: BucleInfo? = nil,
                                        trailing: String? = nil,
                                        trailingAction: (() -> Void)? = nil,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                numberDot(n)
                Text(title).instrumentoOverline().foregroundStyle(theme.inkTertiary)
                if let infoItem {
                    Button { info = infoItem } label: {
                        Image(systemName: "info.circle").font(.system(size: 12)).foregroundStyle(theme.inkTertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("How this section works")
                }
                Spacer()
                if let trailing, let trailingAction {
                    Button(action: trailingAction) {
                        HStack(spacing: 2) {
                            Text(trailing).font(StrandFont.footnote)
                            Image(systemName: "chevron.right").font(.system(size: 11))
                        }
                        .foregroundStyle(theme.inkTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            content()
        }
        .padding(.top, 18)
        .overlay(alignment: .top) { Rectangle().fill(theme.hairline).frame(height: 0.5) }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func numberDot(_ n: Int) -> some View {
        Text("\(n)")
            .font(.system(size: 10, weight: .semibold)).foregroundStyle(theme.inkTertiary)
            .frame(width: 18, height: 18)
            .background(Circle().fill(theme.paperLo))
            .overlay(Circle().stroke(theme.hairlineStrong, lineWidth: 1))
    }

    private func recChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold)).textCase(.uppercase).tracking(0.5)
            .foregroundStyle(theme.dataRecovery)
            .padding(.horizontal, 9).padding(.vertical, 3)
            .background(theme.dataRecovery.opacity(0.12), in: Capsule())
    }

    // MARK: «Empezar de cero» (reset what the user contributed)

    /// True when there's anything the user contributed to clear (journal-derived levers, an experiment,
    /// or a logged day) — so the reset footer only shows when it would do something.
    private var hasContributed: Bool {
        !curatedLevers.isEmpty || running != nil || finished != nil || journalAnswered > 0
    }

    /// A quiet, understated reset at the foot of the screen — destructive, so it opens a confirmation
    /// that spells out exactly what's erased (and what isn't). Tertiary ink per the DNA (no loud color).
    private var resetFooter: some View {
        Button(role: .destructive) { showResetConfirm = true } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.counterclockwise").font(.system(size: 12, weight: .semibold))
                Text("Start from scratch").font(StrandFont.footnote)
            }
            .foregroundStyle(theme.inkTertiary)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .padding(.top, 26)
    }

    /// An honest, dashed empty box for a section with no data yet (calibrating / pre-finding).
    private func emptyBox(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .padding(16)
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(theme.hairlineStrong, style: StrokeStyle(lineWidth: 1, dash: [4])))
            .padding(.top, 11)
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

// MARK: - §3 card / surface-row chrome (Patrones v2)

private extension View {
    /// The §3 experiment card: surface fill, 1px colored border, rounded, with the section's top spacing.
    func pruebaCard(_ theme: InstrumentoTheme, border: Color, fill: Color? = nil) -> some View {
        self.padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill ?? theme.surface,
                        in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous)
                .stroke(border, lineWidth: 1))
            .padding(.top, 11)
    }

    /// A §5 surface row: surface fill, hairline border, rounded.
    func surfaceRow(_ theme: InstrumentoTheme) -> some View {
        self.padding(14)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous)
                .stroke(theme.hairlineStrong, lineWidth: 1))
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
    /// Today's check-in answer once given (nil = not yet answered) → the «registrado» record. FER (Patrones v2).
    let markedYesToday: Bool?
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
        var markedYes: Bool? = nil
        if !isDiet {
            let todayAnswer = (await nativeJournalAnswers(day: today))[row.behavior]
            let answeredToday = todayAnswer != nil
            // Eligible = the window's calendar days up to today; drop a still-pending today so an unmarked
            // today reads as «not broken yet», not as a miss.
            var eligible = ExperimentDates.dayKeys(from: row.startDay, to: today)
            if !answeredToday { eligible.removeAll { $0 == today } }
            let s = StreakMath.streaks(eligibleDays: eligible, adherent: adherentSet)
            current = s.current
            best = s.best
            let withinWindow = Repository.experimentEndDay(row).map { today < $0 } ?? true
            pending = withinWindow && !answeredToday
            // Today already answered while still inside the window → show the «registrado» record.
            if withinWindow, let yes = todayAnswer { markedYes = yes }
        }
        return ExperimentProgress(row: row, elapsedDay: elapsed, adherent: adherentSet.count,
                                  verdictDate: verdictDate, streakCurrent: current, streakBest: best,
                                  pendingCheckIn: pending, markedYesToday: markedYes, supportsStreak: !isDiet)
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

    /// «vie 26 jun» / «Fri Jun 26» for a day key — follows the app language (FER-472).
    static func longLabelES(_ key: String) -> String? {
        parse.date(from: key).map { longES.string(from: $0) }
    }

    static let parse: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static let longES: DateFormatter = {
        let f = DateFormatter(); f.locale = .current; f.dateFormat = "EEE d MMM"
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
