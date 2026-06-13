import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore
import Foundation

// MARK: - Control Center (the home dashboard) — HomeDensity rewrite
//
// The owner's complaint was "cards then random space". This rebuild is a tight,
// GAPLESS dashboard grid: one column of uniform sections, every gap == NoopMetrics.gap,
// every section break == NoopMetrics.sectionGap, equal margins from ScreenScaffold.
//
// Composition (top → bottom):
//   (a) HERO  — full-width HStack that fills the width EQUALLY: RecoveryRing (left card)
//               + InsightCard "Today's Synthesis" (right card). No lone card, no gap.
//   (b) METRICS — one adaptive LazyVGrid of fixed-104pt StatTiles (Recovery, Strain,
//               Sleep, HRV, RHR, SpO2, Respiratory, Steps, Weight, Calories) each with
//               a 14-day sparkline so the grid tiles perfectly with no empty cells.
//   (c) LAST WORKOUTS — the SAME adaptive grid of fixed-104pt workout StatTiles.
//   (d) DATA SOURCES — one full-width NoopCard footer of SourceBadges + counts.
//
// Sparse series (weight) fall back to ALL history so a tile never shows an empty
// state when data exists. Only locked StrandDesign components are used.

struct TodayView: View {
    @EnvironmentObject var repo: Repository
    @EnvironmentObject var live: LiveState

    // Imperial/Metric display preference (D#103). Only the Weight tile carries a convertible unit here.
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    private var unitSystem: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }

    // 14-day sparkline series, keyed by metric key. Loaded once in .task.
    @State private var sparks: [String: [Double]] = [:]
    @State private var workouts: [WorkoutRow] = []
    @State private var appleDays: [AppleDaily] = []

    // Today's heart rate as 5-minute bucket means (midnight → now), for the 24h trend chart.
    @State private var hrPoints: [TrendPoint] = []

    // Support sheet (donate + contact) — always reachable from the home toolbar.
    @State private var showingSupport = false

    // THE single grid definition — every tile group reuses it so margins line up.
    private let grid = [GridItem(.adaptive(minimum: 168), spacing: NoopMetrics.gap)]

    /// Recovery cold-start: recovery is nil until the HRV baseline crosses the seed gate
    /// (Baselines.minNightsSeed valid nights). While calibrating, this is the count of nights
    /// banked so far — it drives an honest "Calibrating — N of 4 nights" on the recovery ring,
    /// the synthesis card and the Key Metrics tile instead of a bare empty state. It self-clears
    /// the moment recovery populates, and never claims "calibrating" at/above the seed gate.
    /// Mirrors Android TodayScreen.recoveryCalibrationNights (7b5f212).
    private var recoveryCalibration: Int? {
        RecoveryScorer.calibrationNights(nightlyHrv: repo.days.map(\.avgHrv),
                                         hasRecovery: repo.today?.recovery != nil)
    }

    /// Synthesis-card copy while the recovery baseline calibrates; nil otherwise. Built as
    /// LocalizedStringKey literals so the String Catalog picks up the %lld patterns.
    private var calibrationStatus: LocalizedStringKey? {
        recoveryCalibration == nil ? nil : "Calibrating"
    }
    private var calibrationDetail: LocalizedStringKey? {
        guard let n = recoveryCalibration else { return nil }
        return "Learning your baseline — \(n) of \(Baselines.minNightsSeed) nights."
    }

    var body: some View {
        platformBody
            .task(id: repo.refreshSeq) { await loadAll() }
            .toolbar {
                ToolbarItem {
                    Button { showingSupport = true } label: {
                        Image(systemName: "heart.fill")
                            .foregroundStyle(StrandPalette.metricRose)
                            .attentionWiggle(period: 4)
                    }
                    .help("Support NOOP — donate or get in touch")
                    .accessibilityLabel("Support NOOP — donate or get in touch")
                }
            }
            .overlay {
                if showingSupport {
                    SupportModalOverlay(isPresented: $showingSupport)
                }
            }
            .animation(.easeOut(duration: 0.18), value: showingSupport)
    }

    @ViewBuilder private var platformBody: some View {
        #if os(iOS)
        iosBody
        #else
        macBody
        #endif
    }

    /// macOS / fallback: the original "gapless" dashboard grid (one column of uniform sections,
    /// preview-sized for a wide window). iPhone uses `iosBody` below.
    private var macBody: some View {
        ScreenScaffold(title: greetingKey, subtitle: "\(dateLine)") {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                HealthAlertBanner()
                if repo.today?.recovery == nil {
                    // While the strap is mid-offload, say so — empty tiles read as final otherwise (#77).
                    if live.backfilling { SyncingHistoryNote(chunks: live.syncChunksThisSession) }
                    DataPendingNote(
                        title: "Live now. Your scores are building.",
                        message: "Your live heart rate is working from the strap, and recovery, strain and sleep build from it over your next few nights of wear, sharpening as it learns your baseline. Want your full history instantly? Import your WHOOP export in Data Sources and it backfills in about a minute."
                    )
                }
                heroSection
                heartRateTrendSection
                readinessSection
                metricsSection
                workoutsSection
                sourcesSection
            }
        }
    }

    // MARK: - iOS Today (verdict-first · live HR pill · 2-up glance grid)
    //
    // iPhone-only layout (gated `#if os(iOS)`; macOS keeps `macBody`'s grid). It leads with
    // the on-device READINESS verdict — the answer NOOP can give that the strap maker can't —
    // instead of a score to interpret, carries a LIVE heart-rate pill in the top utility row
    // (real `LiveState.heartRate`, never faked), and pins the metric grid to two columns
    // (the desktop `.adaptive(minimum:168)` grid collapses to one column on a phone).

    #if os(iOS)
    private var iosGrid: [GridItem] {
        [GridItem(.flexible(), spacing: NoopMetrics.gap),
         GridItem(.flexible(), spacing: NoopMetrics.gap)]
    }

    private var iosBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                utilityRow
                HealthAlertBanner()
                if repo.today?.recovery == nil {
                    if live.backfilling { SyncingHistoryNote(chunks: live.syncChunksThisSession) }
                    DataPendingNote(
                        title: "Live now. Your scores are building.",
                        message: "Your live heart rate is working from the strap, and recovery, strain and sleep build from it over your next few nights of wear, sharpening as it learns your baseline. Want your full history instantly? Import your WHOOP export in Data Sources and it backfills in about a minute."
                    )
                }
                verdictSection
                whySection
                iosMetricsSection
                workoutsSection
                heartRateTrendSection
                sourcesSection
            }
            .padding(NoopMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(StrandPalette.surfaceBase)
    }

    /// Top utility row: a compact date (the greeting is gone — the verdict greets with substance)
    /// and the live heart-rate pill.
    @ViewBuilder private var utilityRow: some View {
        HStack(alignment: .center) {
            Text(shortDate)
                .font(StrandFont.overline)
                .tracking(StrandFont.overlineTracking)
                .foregroundStyle(StrandPalette.textTertiary)
            Spacer()
            if let bpm = liveBpm {
                LiveHRPill(bpm: bpm, isLive: isLiveHR)
            }
        }
    }

    /// Readiness promoted to the hero: NOOP's reason to exist over the strap maker is on-device
    /// synthesis, so the home answers "should you push today?" instead of posing a number. The
    /// card tints to the readiness level. Falls back to the recovery ring while the baseline seeds.
    @ViewBuilder private var verdictSection: some View {
        let r = readiness
        if r.level != .insufficient {
            let lc = readinessColor(r.level)
            VStack(alignment: .leading, spacing: 6) {
                // Overline + load share one row — the load no longer claims its own line at the
                // bottom, so the card loses the dead band beneath it.
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Should you push today?")
                        .font(StrandFont.overline).tracking(StrandFont.overlineTracking)
                        .foregroundStyle(lc)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    // Training load as a glanceable, flag-colored word — not a raw "load 1.05" the
                    // user can't read, and not a `.help()` tooltip (dead on iOS touch). The exact
                    // ratio still reaches VoiceOver via the accessibility label.
                    if let acwr = r.acwr {
                        let band = ReadinessEngine.loadBand(forACWR: acwr)
                        Text(band.shortLabel)
                            .font(StrandFont.captionNumber)
                            .foregroundStyle(flagColor(band.flag))
                            .lineLimit(1)
                            .accessibilityLabel(Text("Training load: \(band.shortLabel) (acute:chronic \(String(format: "%.2f", acwr)))"))
                    }
                }
                Text(r.headline)
                    .font(StrandFont.title1)
                    .foregroundStyle(StrandPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(r.summary)
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(lc.opacity(0.08), in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous)
                .strokeBorder(lc.opacity(0.30), lineWidth: 1))
        } else {
            heroSection
        }
    }

    /// "Why" evidence strip behind the verdict — recovery + HRV + sleep as THREE UNIFORM flat-stat
    /// tiles (the Whoop/Apple pattern). No ring in the row: mixing a circular gauge with flat numbers
    /// is what made the trio read at three different sizes. Recovery keeps its identity through its
    /// state COLOR + a status dot, not a ring — the ring's signature moment is the verdict hero above.
    /// All three values share one font size and clamp to a single line.
    @ViewBuilder private var whySection: some View {
        let d = repo.today
        VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            SectionHeader("Today’s Synthesis", overline: "At a glance")
            HStack(spacing: NoopMetrics.gap) {
                synthTile(label: "Recovery",
                          value: d?.recovery.map { "\(Int($0.rounded()))" } ?? "—",
                          unit: "",
                          color: d?.recovery.map { StrandPalette.recoveryColor($0) } ?? StrandPalette.textTertiary)
                synthTile(label: "HRV",
                          value: d?.avgHrv.map { "\(Int($0.rounded()))" } ?? "—",
                          unit: "ms",
                          color: StrandPalette.metricPurple)
                synthTile(label: "Sleep",
                          value: sleepValue(d),
                          unit: "",
                          color: StrandPalette.metricPurple)
            }
        }
    }

    /// One uniform flat-stat tile: label + status dot on top, then one big value (+ optional unit).
    /// Same structure and number size for all three; a snug fixed height keeps them perfectly aligned.
    private func synthTile(label: LocalizedStringKey, value: String, unit: String, color: Color) -> some View {
        NoopCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 4) {
                    Text(label)
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .lineLimit(1)
                        // Long localized labels (e.g. ES "Recuperación") must shrink to fit
                        // the narrow 1/3-width tile rather than truncate to "Recupera…".
                        // The label claims all width left by the fixed status dot; without an
                        // explicit width constraint here, minimumScaleFactor never engages and
                        // the text clips instead of scaling (the bug behind FER-40).
                        .minimumScaleFactor(0.6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Circle().fill(color).frame(width: 7, height: 7)
                }
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(value)
                        .font(StrandFont.number(20, weight: .bold))
                        .foregroundStyle(color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if !unit.isEmpty {
                        Text(unit).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 54, alignment: .top)
            .frame(maxWidth: .infinity)
        }
    }

    /// "Key Metrics" — six tiles pinned to a true two-column grid for the phone.
    @ViewBuilder private var iosMetricsSection: some View {
        let d = repo.today
        let aLatest = appleDays.last
        VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            SectionHeader("Key Metrics", overline: "Today", trailing: String(localized: "14-day trend"))
            LazyVGrid(columns: iosGrid, alignment: .leading, spacing: NoopMetrics.gap) {
                StatTile(label: "Day Strain",
                         value: d?.strain.map { String(format: "%.1f", $0) } ?? "—",
                         caption: String(localized: "of 21"),
                         accent: d?.strain.map { StrandPalette.strainColor($0) } ?? StrandPalette.textPrimary,
                         sparkline: sparks["strain"], sparkColor: StrandPalette.strain066)
                StatTile(label: "Sleep",
                         value: sleepValue(d),
                         caption: d?.efficiency.map { String(format: String(localized: "%.0f%% eff"), $0) },
                         accent: StrandPalette.textPrimary,
                         sparkline: sparks["sleep_total_min"], sparkColor: StrandPalette.metricPurple)
                StatTile(label: "HRV",
                         value: d?.avgHrv.map { "\(Int($0.rounded()))" } ?? "—",
                         caption: "ms", accent: StrandPalette.metricPurple,
                         sparkline: sparks["hrv"], sparkColor: StrandPalette.metricPurple)
                StatTile(label: "Resting HR",
                         value: d?.restingHr.map { "\($0)" } ?? "—",
                         caption: "bpm", accent: StrandPalette.metricRose,
                         sparkline: sparks["rhr"], sparkColor: StrandPalette.metricRose)
                StatTile(label: "Blood Oxygen",
                         value: d?.spo2Pct.map { String(format: "%.0f%%", $0) } ?? "—",
                         caption: "SpO₂", accent: StrandPalette.metricCyan,
                         sparkline: sparks["spo2"], sparkColor: StrandPalette.metricCyan)
                StatTile(label: "Steps",
                         value: aLatest?.steps.map { intString(Double($0)) } ?? latestString("steps", decimals: 0),
                         caption: String(localized: "today"), accent: StrandPalette.metricCyan,
                         sparkline: sparks["steps"], sparkColor: StrandPalette.metricCyan)
            }
        }
    }

    /// On-device readiness for the verdict hero (same engine the macOS `readinessSection` uses).
    private var readiness: ReadinessEngine.Readiness {
        ReadinessEngine.evaluate(days: repo.days, today: Repository.localDayKey(Date()))
    }

    /// True only when the strap is worn AND streaming live HR — gates the beating animation so a
    /// last-known reading never pretends to be a live pulse.
    private var isLiveHR: Bool { live.heartRate != nil && live.worn }

    /// bpm for the pill: the live strap value when worn, else today's last 5-minute HR bucket.
    /// Returns nil when there is no recent HR at all, so the pill hides rather than show a zero.
    private var liveBpm: Int? {
        if isLiveHR, let hr = live.heartRate { return hr }
        if let last = hrPoints.last?.value { return Int(last.rounded()) }
        return nil
    }

    /// Compact localized date for the utility row, e.g. "THU 12 JUN" — context without the greeting.
    private var shortDate: String {
        let f = DateFormatter()
        f.locale = .autoupdatingCurrent
        f.setLocalizedDateFormatFromTemplate("EEEdMMM")
        let date: Date
        if let day = repo.today?.day, let parsed = Self.dayParser.date(from: day) { date = parsed }
        else { date = Date() }
        return f.string(from: date).uppercased()
    }
    #endif

    // MARK: Readiness — on-device training-readiness synthesis (HRV / resting-HR / load).

    @ViewBuilder
    private var readinessSection: some View {
        let r = ReadinessEngine.evaluate(days: repo.days, today: Repository.localDayKey(Date()))
        if r.level != .insufficient {
            VStack(alignment: .leading, spacing: NoopMetrics.gap) {
                SectionHeader("Readiness", overline: "Should you push today?")
                NoopCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            Circle().fill(readinessColor(r.level)).frame(width: 10, height: 10)
                            Text(r.headline).font(StrandFont.headline)
                                .foregroundStyle(StrandPalette.textPrimary)
                            Spacer()
                            if let acwr = r.acwr {
                                Text("load \(String(format: "%.2f", acwr))")
                                    .font(StrandFont.captionNumber)
                                    .foregroundStyle(StrandPalette.textTertiary)
                                    .help("Acute (7-day) vs chronic (28-day) training load. 0.8–1.3 is the sweet spot.")
                            }
                        }
                        Text(r.summary).font(StrandFont.subhead)
                            .foregroundStyle(StrandPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if !r.signals.isEmpty {
                            Divider().overlay(StrandPalette.hairline)
                            ForEach(r.signals, id: \.key) { s in
                                HStack(alignment: .top, spacing: 8) {
                                    Circle().fill(flagColor(s.flag)).frame(width: 7, height: 7)
                                        .padding(.top, 5)
                                    Text(s.label).font(StrandFont.caption)
                                        .foregroundStyle(StrandPalette.textSecondary)
                                        .frame(width: 104, alignment: .leading)
                                    Text(s.detail).font(StrandFont.caption)
                                        .foregroundStyle(StrandPalette.textTertiary)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Spacer(minLength: 0)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func readinessColor(_ l: ReadinessEngine.Level) -> Color {
        switch l {
        case .primed:       return StrandPalette.accent
        case .balanced:     return StrandPalette.statusPositive
        case .strained:     return StrandPalette.statusWarning
        case .rundown:      return StrandPalette.metricRose
        case .insufficient: return StrandPalette.textTertiary
        }
    }

    private func flagColor(_ f: ReadinessEngine.Flag) -> Color {
        switch f {
        case .good:    return StrandPalette.accent
        case .neutral: return StrandPalette.textTertiary
        case .watch:   return StrandPalette.statusWarning
        case .bad:     return StrandPalette.metricRose
        }
    }

    // MARK: (a) HERO — RecoveryRing + Synthesis, filling the width equally.

    @ViewBuilder
    private var heroSection: some View {
        let d = repo.today
        let score = d?.recovery
        VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            SectionHeader("Today’s Synthesis", overline: "At a glance")
            HStack(alignment: .top, spacing: NoopMetrics.gap) {
                // Left: the signature ring in a card. When recovery is nil the ring's own center
                // label (which would read "0 · DEPLETED") and hover are hidden and an honest
                // overlay takes over: "Calibrating · N of 4 nights" while the baseline seeds,
                // else "No Data". Mirrors Android TodayScreen.TodayRecoveryRing (7b5f212).
                NoopCard {
                    ZStack {
                        RecoveryRing(
                            score: score ?? 0,
                            supporting: ringSupporting(d),
                            diameter: 168,
                            showsLabel: score != nil,
                            showsHover: score != nil
                        )
                        if score == nil {
                            VStack(spacing: 4) {
                                if let n = recoveryCalibration {
                                    Text("Calibrating")
                                        .font(StrandFont.title2)
                                        .foregroundStyle(StrandPalette.textTertiary)
                                    Text("\(n) of \(Baselines.minNightsSeed) nights")
                                        .font(StrandFont.footnote)
                                        .foregroundStyle(StrandPalette.textSecondary)
                                } else {
                                    Text("No data")
                                        .font(StrandFont.title2)
                                        .foregroundStyle(StrandPalette.textTertiary)
                                    Text(ringSupporting(d))
                                        .font(StrandFont.footnote)
                                        .foregroundStyle(StrandPalette.textSecondary)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity, alignment: .center)

                // Right: the plain-English read-out, equal width.
                InsightCard(
                    category: "Recovery",
                    status: calibrationStatus ?? "\(synthesisWord(score))",
                    detail: calibrationDetail ?? "\(synthesisDetail(d))",
                    statusColor: score.map { StrandPalette.recoveryColor($0) } ?? StrandPalette.textTertiary
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: HEART RATE — today's continuous HR, off the strap's own ~1Hz history.

    /// A full-width 24-hour heart-rate trend, plotted from 5-minute bucket means of the strap's
    /// `hrSample` history (offloaded even while the app was closed, so the day reads continuously).
    /// Hidden until there are at least two buckets — a strap-only user with no wear today sees nothing
    /// rather than an empty axis. Mirrored on Android (TodayScreen.kt HeartRateTrendCard).
    @ViewBuilder
    private var heartRateTrendSection: some View {
        if hrPoints.count > 1 {
            let v = hrPoints.map(\.value)
            VStack(alignment: .leading, spacing: NoopMetrics.gap) {
                SectionHeader("Heart Rate", overline: "Today")
                ChartCard(
                    title: "Beats per minute",
                    subtitle: String(localized: "5-minute average · since midnight"),
                    trailing: v.last.map { "\(Int($0.rounded())) bpm" }
                ) {
                    TrendChart(
                        points: hrPoints,
                        gradient: Gradient(colors: [StrandPalette.metricRose.opacity(0.55), StrandPalette.metricRose]),
                        valueRange: hrRange(v),
                        showsArea: true,
                        height: NoopMetrics.chartHeight,
                        valueFormat: { "\(Int($0.rounded())) bpm" },
                        dateFormat: { Self.hrTimeFmt.string(from: $0) }
                    )
                } footer: {
                    ChartFooter([
                        ("Min", "\(Int((v.min() ?? 0).rounded()))"),
                        ("Avg", "\(Int((v.reduce(0, +) / Double(v.count)).rounded()))"),
                        ("Max", "\(Int((v.max() ?? 0).rounded()))"),
                    ])
                }
            }
        }
    }

    /// Padded HR axis range so the line never sits flush against an edge (mirrors MetricExplorer.valueRange).
    private func hrRange(_ v: [Double]) -> ClosedRange<Double> {
        guard let lo = v.min(), let hi = v.max() else { return 40...120 }
        if hi <= lo { return (lo - 5)...(hi + 5) }
        let span = hi - lo
        return (lo - span * 0.12)...(hi + span * 0.12)
    }

    // MARK: (b) METRICS — one uniform grid of 104pt StatTiles, every cell filled.

    @ViewBuilder
    private var metricsSection: some View {
        let d = repo.today
        let aLatest = appleDays.last
        VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            SectionHeader("Key Metrics", overline: "Today", trailing: String(localized: "14-day trend"))
            LazyVGrid(columns: grid, alignment: .leading, spacing: NoopMetrics.gap) {
                StatTile(
                    label: "Recovery",
                    value: d?.recovery.map { "\(Int($0.rounded()))%" }
                        ?? recoveryCalibration.map { "\($0)/\(Baselines.minNightsSeed)" } ?? "—",
                    caption: d?.recovery.map { StrandPalette.recoveryState($0).capitalized }
                        ?? recoveryCalibration.map { _ in "Calibrating" },
                    accent: d?.recovery.map { StrandPalette.recoveryColor($0) } ?? StrandPalette.textPrimary,
                    sparkline: sparks["recovery"],
                    sparkColor: StrandPalette.accent
                )
                StatTile(
                    label: "Day Strain",
                    value: d?.strain.map { String(format: "%.1f", $0) } ?? "—",
                    caption: String(localized: "of 21"),
                    accent: d?.strain.map { StrandPalette.strainColor($0) } ?? StrandPalette.textPrimary,
                    sparkline: sparks["strain"],
                    sparkColor: StrandPalette.strain066
                )
                StatTile(
                    label: "Sleep",
                    value: sleepValue(d),
                    caption: d?.efficiency.map { String(format: String(localized: "%.0f%% eff"), $0) },
                    accent: StrandPalette.textPrimary,
                    sparkline: sparks["sleep_total_min"],
                    sparkColor: StrandPalette.metricPurple
                )
                StatTile(
                    label: "HRV",
                    value: d?.avgHrv.map { "\(Int($0.rounded()))" } ?? "—",
                    caption: "ms",
                    accent: StrandPalette.metricPurple,
                    sparkline: sparks["hrv"],
                    sparkColor: StrandPalette.metricPurple
                )
                StatTile(
                    label: "Resting HR",
                    value: d?.restingHr.map { "\($0)" } ?? "—",
                    caption: "bpm",
                    accent: StrandPalette.metricRose,
                    sparkline: sparks["rhr"],
                    sparkColor: StrandPalette.metricRose
                )
                StatTile(
                    label: "Blood Oxygen",
                    value: d?.spo2Pct.map { String(format: "%.0f%%", $0) } ?? "—",
                    caption: "SpO₂",
                    accent: StrandPalette.metricCyan,
                    sparkline: sparks["spo2"],
                    sparkColor: StrandPalette.metricCyan
                )
                StatTile(
                    label: "Respiratory",
                    value: d?.respRateBpm.map { String(format: "%.1f", $0) } ?? latestString("resp_rate", decimals: 1),
                    caption: "rpm",
                    accent: StrandPalette.accent,
                    sparkline: sparks["resp_rate"],
                    sparkColor: StrandPalette.accent
                )
                StatTile(
                    label: "Steps",
                    value: aLatest?.steps.map { intString(Double($0)) } ?? latestString("steps", decimals: 0),
                    caption: String(localized: "today"),
                    accent: StrandPalette.metricCyan,
                    sparkline: sparks["steps"],
                    sparkColor: StrandPalette.metricCyan
                )
                StatTile(
                    label: "Weight",
                    value: weightString(aLatest?.weightKg),
                    caption: String(localized: "latest"),
                    accent: StrandPalette.accent,
                    sparkline: sparks["weight"],
                    sparkColor: StrandPalette.accent
                )
                StatTile(
                    label: "Calories",
                    value: caloriesValue(aLatest),
                    caption: String(localized: "active"),
                    accent: StrandPalette.metricAmber,
                    sparkline: sparks["active_kcal"],
                    sparkColor: StrandPalette.metricAmber
                )
            }
        }
    }

    // MARK: (c) LAST WORKOUTS — SAME grid, uniform 104pt workout tiles.

    @ViewBuilder
    private var workoutsSection: some View {
        if !workouts.isEmpty {
            VStack(alignment: .leading, spacing: NoopMetrics.gap) {
                SectionHeader("Last Workouts", overline: "Activity",
                              trailing: String(localized: "\(workouts.count) total"))
                LazyVGrid(columns: grid, alignment: .leading, spacing: NoopMetrics.gap) {
                    ForEach(Array(workouts.prefix(6).enumerated()), id: \.offset) { _, w in
                        StatTile(
                            label: "\(w.sport)",
                            value: workoutDuration(w),
                            caption: workoutCaption(w),
                            accent: StrandPalette.strainColor(w.strain ?? 0),
                            delta: w.energyKcal.map { "\(Int($0.rounded())) kcal" },
                            deltaColor: StrandPalette.metricAmber
                        )
                    }
                }
            }
        }
    }

    // MARK: (d) DATA SOURCES — one full-width footer card.

    @ViewBuilder
    private var sourcesSection: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            SectionHeader("Data Sources", overline: "Provenance")
            NoopCard {
                VStack(alignment: .leading, spacing: 12) {
                    sourceRow(
                        badge: "Whoop",
                        tint: StrandPalette.accent,
                        present: !repo.days.isEmpty,
                        detail: String(localized: "\(repo.days.count) days · \(repo.sleeps.count) sleeps")
                    )
                    Divider().overlay(StrandPalette.hairline)
                    sourceRow(
                        badge: "Apple Health",
                        tint: StrandPalette.metricCyan,
                        present: !appleDays.isEmpty,
                        detail: String(localized: "\(appleDays.count) days · \(workouts.filter { $0.source == "apple-health" }.count) workouts")
                    )
                    Divider().overlay(StrandPalette.hairline)
                    strapSyncRow
                }
            }
        }
    }

    @ViewBuilder
    private func sourceRow(badge: String, tint: Color, present: Bool, detail: String) -> some View {
        HStack(spacing: 10) {
            SourceBadge("\(badge)", tint: present ? tint : StrandPalette.textTertiary)
            Spacer()
            Text(present ? detail : String(localized: "Not connected"))
                .font(StrandFont.captionNumber)
                .foregroundStyle(present ? StrandPalette.textSecondary : StrandPalette.textTertiary)
        }
    }

    /// Honest strap-sync outcome for a cloud-free app (ports the Android Live line, ed6a31d): the
    /// stalled-offload error when the last one died, else "History synced N ago". Hidden while an
    /// offload runs — SyncingHistoryNote already says so. TimelineView re-renders the relative label
    /// each minute so "5 min ago" can't go stale while the window sits open with no strap connected
    /// (LiveState publishes nothing then).
    @ViewBuilder
    private var strapSyncRow: some View {
        if !live.backfilling {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                HStack(alignment: .top, spacing: 10) {
                    SourceBadge("Strap sync",
                                tint: live.lastSyncError != nil ? StrandPalette.statusWarning
                                    : live.lastSyncedAt != nil ? StrandPalette.accent
                                    : StrandPalette.textTertiary)
                    Spacer()
                    if let error = live.lastSyncError {
                        Text(error)
                            .font(StrandFont.captionNumber)
                            .foregroundStyle(StrandPalette.statusWarning)
                            .multilineTextAlignment(.trailing)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if let at = live.lastSyncedAt {
                        Text("History synced \(relativeAgo(at, now: context.date.timeIntervalSince1970))")
                            .font(StrandFont.captionNumber)
                            .foregroundStyle(StrandPalette.textSecondary)
                    } else {
                        Text("Not synced yet")
                            .font(StrandFont.captionNumber)
                            .foregroundStyle(StrandPalette.textTertiary)
                    }
                }
            }
        }
    }

    // MARK: - Loading

    private func loadAll() async {
        // Issue every query concurrently, then collect — instead of 14 serial awaits that each
        // suspended back to the main actor before issuing the next. The store is a serial
        // DatabaseQueue so I/O still serializes, but the memoized ensureStore() makes the parallel
        // first-callers share ONE open, and the queries run back-to-back with no main-actor ping-pong.
        async let recovery   = sparkValues("recovery", source: "my-whoop", window: 14)
        async let strain     = sparkValues("strain", source: "my-whoop", window: 14)
        async let sleepTotal = sparkValues("sleep_total_min", source: "my-whoop", window: 14)
        async let hrv        = sparkValues("hrv", source: "my-whoop", window: 14)
        async let rhr        = sparkValues("rhr", source: "my-whoop", window: 14)
        async let spo2       = sparkValues("spo2", source: "my-whoop", window: 14)
        async let respRate   = sparkValues("resp_rate", source: "apple-health", window: 14)
        async let steps      = sparkValues("steps", source: "apple-health", window: 14)
        async let weight     = sparkValues("weight", source: "apple-health", window: 90)
        async let activeKcal = sparkValues("active_kcal", source: "apple-health", window: 14)
        async let wkRows     = repo.workoutRows()
        async let adRows     = repo.appleDailyRows()

        // Today's HR trend — 5-minute bucket means from local midnight → now.
        let startOfToday = Int(Calendar.current.startOfDay(for: Date()).timeIntervalSince1970)
        let nowTs = Int(Date().timeIntervalSince1970)
        async let hrBucketRows = repo.hrBuckets(from: startOfToday, to: nowTs, bucketSeconds: 300)

        sparks["recovery"]        = await recovery
        sparks["strain"]          = await strain
        sparks["sleep_total_min"] = await sleepTotal
        sparks["hrv"]             = await hrv
        sparks["rhr"]             = await rhr
        sparks["spo2"]            = await spo2
        sparks["resp_rate"]       = await respRate
        sparks["steps"]           = await steps
        sparks["weight"]          = await weight
        sparks["active_kcal"]     = await activeKcal
        workouts  = await wkRows
        appleDays = await adRows
        hrPoints  = await hrBucketRows
            .map { TrendPoint(date: Date(timeIntervalSince1970: TimeInterval($0.ts)), value: $0.bpm) }
    }

    /// Trailing-window values for a metric — NO fall back to all history. The section is labelled a
    /// current trend ("14-day trend"), so a stale import must not render months-old points as if they
    /// were recent (same spirit as the #23 trailing-window fix). The window is generous enough that a
    /// genuinely sparse-but-recent series still renders — weight uses 90 days — and the Sparkline view
    /// already handles 0/1 points (empty / a single head dot), so no fallback is needed for layout.
    /// `latestString` reads `.last` of this windowed series, so a value older than the window shows
    /// "—" rather than a stale number under a Today tile (#49).
    private func sparkValues(_ key: String, source: String, window: Int) async -> [Double] {
        // Scope the SQL to the window we actually render (+a small margin so trailingWindow's
        // calendar-day cutoff has headroom). Was fetching the FULL history (days: 4000) only to
        // drop all but the last 14/90 in memory — wasted rows scanned per metric, ×10 on every load.
        let all = await repo.series(key: key, source: source, days: window + 2)
        guard !all.isEmpty else { return [] }
        return trailingWindow(all, days: window).map { $0.value }
    }

    /// Keep only points within the trailing `days` CALENDAR days ending TODAY (the phone's local date).
    /// Was anchored to the most-recent point, which on a stale import pinned the window to months-old
    /// data shown as a current trend (issue #23). ISO yyyy-MM-dd compares chronologically.
    private func trailingWindow(_ points: [(day: String, value: Double)], days: Int) -> [(day: String, value: Double)] {
        let cutoffKey = Repository.localDayKey(Calendar.current.date(byAdding: .day, value: -(days - 1), to: Date()) ?? Date())
        return points.filter { $0.day >= cutoffKey }
    }

    /// Latest value of a loaded sparkline series, formatted — for tiles whose hero
    /// can't be read off `appleDailyRows` (e.g. respiratory from apple-health).
    private func latestString(_ key: String, decimals: Int, unit: String = "") -> String {
        guard let last = sparks[key]?.last else { return "—" }
        let n = decimals == 0 ? intString(last) : String(format: "%.\(decimals)f", last)
        return unit.isEmpty ? n : "\(n) \(unit)"
    }

    /// Weight in kg → the active mass unit. Prefers the Apple Health latest reading, falling back to the
    /// "weight" series' newest point so a sparse-but-recent value still renders.
    private func weightString(_ appleWeightKg: Double?) -> String {
        let kg = appleWeightKg ?? sparks["weight"]?.last
        guard let kg else { return "—" }
        return UnitFormatter.massFromKilograms(kg, system: unitSystem)
    }

    // MARK: - Derived text

    /// Time-of-day greeting shown as the screen title (localized by SwiftUI).
    private var greetingKey: LocalizedStringKey {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case ..<12:   return "Good morning"
        case 12..<17: return "Good afternoon"
        default:      return "Good evening"
        }
    }

    private var dateLine: String {
        let f = DateFormatter()
        f.locale = .autoupdatingCurrent
        f.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
        if let day = repo.today?.day, let date = Self.dayParser.date(from: day) {
            return f.string(from: date)
        }
        return f.string(from: Date())
    }

    /// A short recovery state word for the synthesis hero.
    private func synthesisWord(_ score: Double?) -> String {
        guard let s = score else { return String(localized: "No Data") }
        switch s {
        case ..<25:  return String(localized: "Depleted")
        case ..<50:  return String(localized: "Low")
        case ..<70:  return String(localized: "Steady")
        case ..<88:  return String(localized: "Primed")
        default:     return String(localized: "Peak")
        }
    }

    /// Plain-English synthesis of recovery + sleep.
    private func synthesisDetail(_ d: DailyMetric?) -> String {
        guard let d, let rec = d.recovery else {
            return String(localized: "No metrics yet. Import your Whoop export or wear the strap to begin.")
        }
        let recPart: String
        switch rec {
        case ..<50:  recPart = String(localized: "Recovery is low")
        case ..<70:  recPart = String(localized: "Recovery is steady")
        default:     recPart = String(localized: "Recovery is strong")
        }
        let sleepPart: String
        if let mins = d.totalSleepMin {
            let h = mins / 60.0
            sleepPart = h >= 7
                ? String(localized: " and sleep was consistent")
                : String(localized: " but sleep ran short")
        } else {
            sleepPart = ""
        }
        return recPart + sleepPart + "."
    }

    private func ringSupporting(_ d: DailyMetric?) -> String {
        let hrv = d?.avgHrv.map { "\(Int($0.rounded())) ms" } ?? "— ms"
        let rhr = d?.restingHr.map { "\($0)" } ?? "—"
        return "HRV \(hrv) · RHR \(rhr)"
    }

    private func sleepValue(_ d: DailyMetric?) -> String {
        guard let m = d?.totalSleepMin else { return "—" }
        let h = Int(m) / 60, mm = Int(m) % 60
        return "\(h)h \(mm)m"
    }

    /// Active calories (Apple) for the latest day, falling back to the sparkline tail.
    private func caloriesValue(_ a: AppleDaily?) -> String {
        if let kcal = a?.activeKcal { return intString(kcal) }
        return latestString("active_kcal", decimals: 0)
    }

    private func workoutDuration(_ w: WorkoutRow) -> String {
        let secs = w.durationS ?? Double(max(w.endTs - w.startTs, 0))
        let mins = Int((secs / 60).rounded())
        if mins >= 60 { return "\(mins / 60)h \(mins % 60)m" }
        return "\(mins)m"
    }

    private func workoutCaption(_ w: WorkoutRow) -> String {
        let f = DateFormatter()
        f.locale = .autoupdatingCurrent
        f.setLocalizedDateFormatFromTemplate("dMMM")
        let date = f.string(from: Date(timeIntervalSince1970: TimeInterval(w.startTs)))
        if let hr = w.avgHr { return "\(date) · \(hr) bpm" }
        return date
    }

    /// Thousands-grouped integer string (steps / calories).
    private func intString(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? "\(Int(v.rounded()))"
    }

    // MARK: - Date parsing (yyyy-MM-dd, en_US_POSIX, UTC)

    static let dayParser: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Local wall-clock time ("HH:mm") for the HR trend's x-axis / tooltip — the chart spans one day,
    /// so it must show times, not the day-granularity default ("EEE d MMM").
    static let hrTimeFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f
    }()
}

// MARK: - Live heart-rate pill (iOS)

#if os(iOS)
/// A compact live heart-rate pill for the Today utility row. The heart beats in time with the
/// real rate (period 60/bpm — a 74 bpm pulse beats every 0.81 s) ONLY when the strap is actively
/// streaming (`isLive`), and honors Reduce Motion. When the value is a last-known reading rather
/// than a live stream it renders static — the animation is reserved for genuinely live data.
private struct LiveHRPill: View {
    let bpm: Int
    let isLive: Bool
    @State private var beat = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var animate: Bool { isLive && !reduceMotion }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "heart.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(StrandPalette.metricRose)
                .scaleEffect(beat ? 1.18 : 1.0)
                .animation(animate ? .easeInOut(duration: 30.0 / Double(max(bpm, 30)))
                            .repeatForever(autoreverses: true) : nil,
                           value: beat)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(bpm)")
                    .font(StrandFont.number(15, weight: .bold))
                    .foregroundStyle(StrandPalette.textPrimary)
                Text("bpm")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(StrandPalette.metricRose.opacity(0.10), in: Capsule())
        .overlay(Capsule().strokeBorder(StrandPalette.metricRose.opacity(0.30), lineWidth: 1))
        .onAppear { if animate { beat = true } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(isLive ? "Live heart rate" : "Heart rate"))
        .accessibilityValue(Text("\(bpm) bpm"))
    }
}
#endif

// MARK: - Preview

#if DEBUG
#Preview("Control Center") {
    let repo = Repository(deviceId: "preview")
    let cal = Calendar(identifier: .gregorian)
    let today = cal.startOfDay(for: Date())
    var sample: [DailyMetric] = []
    for i in stride(from: 39, through: 0, by: -1) {
        let date = cal.date(byAdding: .day, value: -i, to: today)!
        let day = Repository.dayString(date)
        let phase = Double(i)
        let rec = 48 + 34 * sin(phase / 5.0) + Double((i * 7) % 11)
        let strain = 8 + 7 * abs(sin(phase / 4.0))
        let total = 380 + 70 * sin(phase / 6.0)
        sample.append(DailyMetric(
            day: day, totalSleepMin: total, efficiency: 88 + 6 * sin(phase / 3.0),
            deepMin: 95, remMin: 110, lightMin: total - 200, disturbances: 4,
            restingHr: 50 + (i % 6), avgHrv: 58 + 16 * sin(phase / 4.0),
            recovery: min(max(rec, 8), 99), strain: strain, exerciseCount: i % 3,
            spo2Pct: 96, skinTempDevC: 33.4, respRateBpm: 14.6
        ))
    }
    repo.setDashboard(days: sample)

    return TodayView()
        .environmentObject(repo)
        .frame(width: 920, height: 940)
        .preferredColorScheme(.dark)
}
#endif
