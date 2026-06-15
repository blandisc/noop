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

    #if os(iOS)
    // iOS-only: the root app state, so the first-launch empty state's "Scan for strap" CTA can kick
    // off a real BLE scan (`AppModel.scan()`). macOS never renders the iOS body, so it never reads this.
    @EnvironmentObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Presents the live beat-to-beat monitor (LiveView) over Today when the calibration card's
    /// "See it beat by beat" affordance is tapped.
    @State private var showLiveMonitor = false
    /// Live Apple Health bridge (iOS only). Today reads `health.auth` to nudge the user to connect
    /// Apple Salud when the measured Key Metrics are empty; `showDataSources` presents Data Sources
    /// so they can connect in one tap instead of hunting through the More tab. (FER-94)
    @EnvironmentObject var health: HealthKitBridge
    @State private var showDataSources = false
    #endif

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

    // Metric-info sheet — tapping any Key Metrics row presents this.
    @State private var metricDetail: MetricInfo? = nil

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

    /// Nights of the user's OWN strap data with usable HRV, 0… (drives the night-dots progress).
    /// Apple-Health days are deliberately EXCLUDED: Apple Health fills Trends/Sleep preliminarily but
    /// it's borrowed data — its rows carry `recovery: nil` and never seed the recovery baseline — so
    /// the dots keep counting toward the 4 nights of YOUR data the verdict actually needs. Reuses the
    /// same in-range HRV filter via a high seed; once this reaches the seed the baseline is genuinely
    /// yours and the verdict path takes over.
    private var ownNights: Int {
        let appleDays = repo.appleHealthDays
        let strapHrv = repo.days.filter { !appleDays.contains($0.day) }.map(\.avgHrv)
        return RecoveryScorer.calibrationNights(nightlyHrv: strapHrv, hasRecovery: false, seed: .max) ?? 0
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
            .task(id: live.hrFlushSeq) {
                guard live.hrFlushSeq > 0 else { return }
                let start = Int(Calendar.current.startOfDay(for: Date()).timeIntervalSince1970)
                let now   = Int(Date().timeIntervalSince1970)
                let rows  = await repo.hrBuckets(from: start, to: now, bucketSeconds: 300)
                hrPoints  = rows.map { TrendPoint(date: Date(timeIntervalSince1970: TimeInterval($0.ts)), value: $0.bpm) }
            }
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
            .sheet(item: $metricDetail) { info in
                MetricInfoSheet(info: info)
            }
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
    private var iosBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                headerBlock
                HealthAlertBanner()
                if repo.today?.recovery == nil {
                    // No readiness yet → one calm, intentional screen from first launch through
                    // calibration. The clean verdict hero adapts its copy to whether a strap has been
                    // seen; the old data-pending gauge ("Sin datos") is gone so the empty state never
                    // looks half-built — even right after the strap connects in onboarding.
                    if (live.lastSyncedAt != nil || liveBpm != nil) && ownNights < Baselines.minNightsSeed {
                        // Still gathering the first `seed` nights of the user's OWN strap data → the
                        // night-dots card from night zero. Apple-Health days don't count (borrowed,
                        // preliminary), so a full Apple Health sync keeps the dots honest at "N of 4"
                        // instead of faking 4/4; a real WHOOP-own history (import/wear) fills them and
                        // hands off to the verdict once today's reading lands.
                        CalibrationProgressCard(nights: ownNights,
                                                total: Baselines.minNightsSeed,
                                                liveBpm: liveBpm,
                                                isLiveHR: isLiveHR,
                                                onTapLive: { showLiveMonitor = true })
                    } else {
                        // No strap ever (→ Scan CTA), OR a seeded baseline (≥seed valid nights, e.g. from
                        // a full account sync) that simply has no reading for TODAY yet — not calibration.
                        // emptyHero tells the honest story for both, never a fabricated calibration count.
                        emptyHero
                    }
                } else {
                    verdictSection
                }
                whySection
                iosMetricsSection
                iosHeartRateSection
                sourcesSection
            }
            .padding(NoopMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(StrandPalette.surfaceBase)
        .fullScreenCover(isPresented: $showLiveMonitor) {
            // No NavigationStack: its nav-bar scroll-edge background painted a bar over the monitor on
            // the slightest scroll. A floating "Done" pill overlays the content and never blocks it.
            LiveView(monitorOnly: true)
                .environmentObject(model)
                .environmentObject(live)
                .environmentObject(repo)
                .overlay(alignment: .topTrailing) {
                    Button { showLiveMonitor = false } label: {
                        Text("Done")
                            .font(StrandFont.subhead).fontWeight(.semibold)
                            .foregroundStyle(StrandPalette.accent)
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(StrandPalette.surfaceRaised, in: Capsule())
                    }
                    .padding(.trailing, 16).padding(.top, 8)
                }
                .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showDataSources) {
            // Present Data Sources directly so the Key Metrics nudge connects Apple Health in one tap,
            // without sending the user to dig through the More tab. A sheet starts a fresh environment
            // branch, so re-inject the objects DataSourcesView needs (same pattern as the cover above).
            NavigationStack {
                DataSourcesView()
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showDataSources = false }
                                .foregroundStyle(StrandPalette.accent)
                        }
                    }
            }
            .environmentObject(model)
            .environmentObject(repo)
            .environmentObject(live)
            .environmentObject(health)
            .preferredColorScheme(.dark)
        }
    }

    /// HR for the phone: the real 24h trend when there's data, an honest "No readings yet" well on
    /// first launch (the design's empty-state HR slot), nothing in between (a strap-only day with no
    /// wear shouldn't render an empty axis).
    @ViewBuilder private var iosHeartRateSection: some View {
        if hrPoints.count > 1 {
            heartRateTrendSection
        } else if isFirstLaunch {
            VStack(alignment: .leading, spacing: NoopMetrics.gap) {
                SectionHeader("Heart Rate", overline: "Since midnight")
                NoopCard {
                    Text("No readings yet")
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
            }
        }
    }

    /// True only on a genuine first launch — no synced history, no stored days, no live reading. The
    /// "calibrating" case (worn a few nights, recovery still seeding) is NOT empty: it keeps the
    /// data-pending note + verdict path so an honest "scores are building" story shows instead.
    private var isFirstLaunch: Bool {
        repo.today?.recovery == nil
            && repo.days.isEmpty
            && live.lastSyncedAt == nil
            && liveBpm == nil
    }

    /// Recovery score driving the readiness gauge (the 0–100 the bar fills to). nil while calibrating.
    private var recoveryScore: Int? { repo.today?.recovery.map { Int($0.rounded()) } }

    /// Date + honesty line — the screen's calm header. The live bpm now lives in each hero's
    /// "beat by beat" row (LiveHeartbeatRow), never here, so the header is just date + sync.
    private var headerBlock: some View {
        utilityRow
    }

    /// Verdict hero for the no-data state. Two honest cases, by whether a strap has ever been seen:
    /// before — a committed "no reading yet" + a single "scan" CTA. After — the baseline is already
    /// seeded (by wear OR a full import) but today's reading hasn't landed, so a calm "no reading for
    /// today yet". The 1…seed−1 calibration window is owned by CalibrationProgressCard, not here, so
    /// this never claims "scores are building" once an account's history is in. No fabricated numbers.
    private var emptyHero: some View {
        let strapSeen = live.lastSyncedAt != nil || liveBpm != nil
        return NoopCard(padding: 18) {
            VStack(alignment: .leading, spacing: 9) {
                Text("Today's verdict").strandOverline()
                Text(strapSeen ? "No reading for today yet" : "No reading yet")
                    .font(StrandFont.title1)
                    .foregroundStyle(StrandPalette.textSecondary)
                Text(strapSeen
                     ? "Your baseline is set. Wear your strap overnight and this morning's recovery, strain and sleep land once it syncs."
                     : "Connect your WHOOP strap to see this morning's readiness, recovery and heart rate.")
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !strapSeen {
                    Button { model.scan() } label: {
                        Text("Scan for strap")
                            .font(StrandFont.headline)
                            .foregroundStyle(StrandPalette.surfaceBase)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(StrandPalette.accent, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 5)
                }
                // Strap seen but no reading for today yet → the live pulse + monitor live here too.
                if strapSeen {
                    LiveHeartbeatRow(liveBpm: liveBpm, isLiveHR: isLiveHR, onTap: { showLiveMonitor = true })
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The live-heartbeat row: the brand pulse glyph + "See it beat by beat", the live bpm pill (or a
    /// muted "No reading" badge), and a chevron — one Button that opens the beat-to-beat monitor.
    /// Anchored at the foot of every hero with a strap (calibration, verdict, empty-with-strap) so the
    /// live pulse and its monitor live in one consistent place instead of floating in the header.
    private struct LiveHeartbeatRow: View {
        var liveBpm: Int?
        var isLiveHR: Bool
        let onTap: () -> Void

        var body: some View {
            VStack(spacing: 0) {
                Rectangle().fill(StrandPalette.hairline).frame(height: 0.5)
                    .padding(.top, 16).padding(.bottom, 12)
                Button(action: onTap) {
                    HStack(spacing: 9) {
                        Image(systemName: "waveform.path.ecg")
                            .font(StrandFont.subhead).foregroundStyle(StrandPalette.accent)
                        Text("See it beat by beat")
                            .font(StrandFont.subhead).fontWeight(.medium)
                            .foregroundStyle(StrandPalette.textPrimary)
                        Spacer(minLength: 0)
                        badge
                        Image(systemName: "chevron.right")
                            .font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                    }
                    .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(Text(isLiveHR ? "Live heart rate" : "Heart rate"))
                .accessibilityValue(Text(liveBpm.map { "\($0) bpm" } ?? "No reading"))
                .accessibilityHint(Text("Opens the beat-to-beat monitor"))
            }
        }

        /// The live bpm pill, or a muted "No reading" badge when the strap isn't streaming.
        @ViewBuilder private var badge: some View {
            if let bpm = liveBpm {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Circle().fill(isLiveHR ? StrandPalette.metricRose : StrandPalette.textTertiary)
                        .frame(width: 6, height: 6)
                        .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                    Text("\(bpm)").font(StrandFont.number(13, weight: .semibold))
                        .foregroundStyle(StrandPalette.textPrimary)
                    Text("bpm").font(.system(size: 10)).foregroundStyle(StrandPalette.textTertiary)
                }
            } else {
                HStack(spacing: 5) {
                    Circle().fill(StrandPalette.textTertiary).frame(width: 6, height: 6)
                    Text("No reading").font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                }
            }
        }
    }

    /// Progress card — the single waiting screen until the first verdict. Shows the night-dots from
    /// night zero (0 of seed) through calibration, so the user always sees how many nights remain.
    /// Copy adapts to three moments: night zero, mid-calibration, and "all nights in, computing".
    private struct CalibrationProgressCard: View {
        let nights: Int
        let total: Int
        /// Live heart rate for the "beat by beat" row (nil → "No reading"); rose dot when streaming.
        var liveBpm: Int? = nil
        var isLiveHR: Bool = false
        /// Tap target for the live monitor; nil hides the "See it beat by beat" row.
        var onTapLive: (() -> Void)? = nil

        private var headline: LocalizedStringKey {
            if nights == 0 { return "Your first night counts" }
            if nights >= total { return "Almost there" }
            return "Your scores are building"
        }
        private var detail: LocalizedStringKey {
            if nights == 0 { return "Wear the strap tonight — the first of \(total) nights your verdict needs." }
            if nights >= total { return "All \(total) nights are in — computing your first verdict." }
            return "The engine gets sharper every night — you already have \(nights)."
        }

        var body: some View {
            StrandCard(padding: 20) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "sparkles")
                            .font(StrandFont.headline)
                            .foregroundStyle(StrandPalette.accent)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(headline)
                                .font(StrandFont.headline)
                                .foregroundStyle(StrandPalette.textPrimary)
                            HStack(spacing: 8) {
                                ForEach(0..<total, id: \.self) { i in
                                    Circle()
                                        .fill(i < nights ? StrandPalette.accent : StrandPalette.hairline)
                                        .frame(width: 10, height: 10)
                                        .shadow(color: i < nights ? StrandPalette.accent.opacity(0.5) : .clear,
                                                radius: 3)
                                }
                                Text("\(nights) of \(total) nights")
                                    .font(StrandFont.captionNumber)
                                    .foregroundStyle(StrandPalette.accent)
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(Text("\(nights) of \(total) nights calibrated"))
                            Text(detail)
                                .font(StrandFont.subhead)
                                .foregroundStyle(StrandPalette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if let onTapLive {
                        LiveHeartbeatRow(liveBpm: liveBpm, isLiveHR: isLiveHR, onTap: onTapLive)
                    }
                }
            }
        }
    }

    /// Top utility row: a compact date (the greeting is gone — the verdict greets with substance)
    /// and the live heart-rate pill.
    @ViewBuilder private var utilityRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(shortDate)
                .font(StrandFont.overline)
                .tracking(StrandFont.overlineTracking)
                .foregroundStyle(StrandPalette.textTertiary)
            Spacer(minLength: 8)
            syncMeta
        }
    }

    /// Honesty line — "Synced 2 min ago · strap 87%" / "Last sync — never". Shows "Syncing strap
    /// history…" while a history offload runs so the user gets a quiet, non-intrusive signal without
    /// a prominent pill. Mono + tertiary in all states so it reads as quiet provenance.
    @ViewBuilder private var syncMeta: some View {
        if live.backfilling {
            Text("Syncing strap history…")
                .font(StrandFont.mono(10))
                .foregroundStyle(StrandPalette.textTertiary)
                .lineLimit(1)
        } else {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                Group {
                    if let at = live.lastSyncedAt {
                        let rel = relativeAgo(at, now: context.date.timeIntervalSince1970)
                        if let pct = live.batteryPct {
                            Text("Synced \(rel) · strap \(Int(pct.rounded()))%")
                        } else {
                            Text("Synced \(rel)")
                        }
                    } else {
                        Text("Last sync — never")
                    }
                }
                .font(StrandFont.mono(10))
                .foregroundStyle(StrandPalette.textTertiary)
                .lineLimit(1)
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
                    Text("Today's verdict")
                        .font(StrandFont.overline).tracking(StrandFont.overlineTracking)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    // Training load as a glanceable, flag-colored word — not a raw "load 1.05" the
                    // user can't read, and not a `.help()` tooltip (dead on iOS touch). The exact
                    // ratio still reaches VoiceOver via the accessibility label.
                    if let acwr = r.acwr {
                        let band = ReadinessEngine.loadBand(forACWR: acwr)
                        HStack(spacing: 5) {
                            Text("Load").font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                            Text(band.shortLabel)
                                .font(StrandFont.captionNumber)
                                .foregroundStyle(flagColor(band.flag))
                        }
                        .lineLimit(1)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text("Training load: \(band.shortLabel) (acute:chronic \(String(format: "%.2f", acwr)))"))
                    }
                }
                // Committed verdict — the headline takes the level's color so the day's tone is
                // legible at a glance (mint Primed → amber Strained → rose Run down).
                Text(r.headline)
                    .font(StrandFont.title1)
                    .foregroundStyle(lc)
                    .fixedSize(horizontal: false, vertical: true)
                Text(r.summary)
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                // Readiness as a 0–100 gauge filled to today's recovery score (hidden while the
                // baseline is still seeding and recovery is nil).
                if let score = recoveryScore {
                    ReadinessGaugeBar(score: score, accent: lc)
                        .padding(.top, 10)
                }
                // Honesty beats a fake CTA: a short night flags the read low-confidence; otherwise a
                // well-backed day earns a single committed nudge.
                if r.confidenceLow, let note = r.confidenceNote {
                    HStack(spacing: 7) {
                        Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 10))
                        Text(note).font(StrandFont.caption)
                    }
                    .foregroundStyle(StrandPalette.statusWarning)
                    .padding(.top, 11)
                } else if r.level == .primed || r.level == .balanced {
                    HStack(spacing: 5) {
                        Text("Plan a hard session").font(StrandFont.captionNumber)
                        Image(systemName: "arrow.right").font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(lc)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(lc.opacity(0.13), in: Capsule())
                    .overlay(Capsule().strokeBorder(lc.opacity(0.30), lineWidth: 1))
                    .padding(.top, 12)
                }
                // Live pulse + beat-to-beat monitor, anchored to the foot of the verdict.
                LiveHeartbeatRow(liveBpm: liveBpm, isLiveHR: isLiveHR, onTap: { showLiveMonitor = true })
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

    /// Synthesis strip behind the verdict — recovery · HRV · sleep as three borderless stats split by
    /// thin vertical hairlines (the Whoop/Apple pattern). No boxes: grouping by whitespace + a single
    /// elevated hero (the verdict) is the design's whole premise. Recovery keeps its identity through
    /// its state COLOR; all three values share one mono size and clamp to a single line.
    @ViewBuilder private var whySection: some View {
        let d = repo.today
        HStack(spacing: 0) {
            synthCell(label: "Recovery",
                      value: d?.recovery.map { "\(Int($0.rounded()))" } ?? "—",
                      unit: nil,
                      color: d?.recovery.map { StrandPalette.recoveryColor($0) } ?? StrandPalette.textTertiary)
            synthDivider
            synthCell(label: "HRV",
                      value: d?.avgHrv.map { "\(Int($0.rounded()))" } ?? "—",
                      unit: "ms",
                      color: StrandPalette.textPrimary)
            synthDivider
            synthCell(label: "Sleep",
                      value: sleepValue(d),
                      unit: nil,
                      color: StrandPalette.textPrimary)
        }
    }

    private var synthDivider: some View {
        Rectangle().fill(StrandPalette.hairline).frame(width: 1, height: 34)
    }

    /// One borderless synthesis stat: small label over one big mono value (+ optional unit), centered
    /// within its equal-width column so the three read as a balanced row (no left-hugging gap).
    private func synthCell(label: LocalizedStringKey, value: String, unit: String?, color: Color) -> some View {
        VStack(alignment: .center, spacing: 8) {
            Text(label)
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(StrandFont.number(24))
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let unit {
                    Text(unit).font(.system(size: 11)).foregroundStyle(StrandPalette.textTertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 8)
    }

    /// "Key Metrics" — a dense borderless list (label · sparkline · value) instead of a tile grid,
    /// so six metrics read as one calm column. HRV carries a "Low conf" flag after a short night;
    /// the first-launch state shows skeleton sparklines and "—" values.
    @ViewBuilder private var iosMetricsSection: some View {
        let d = repo.today
        // Measured signals resolve from today's row first, then fall back to the most recent value
        // within the freshness window (today/yesterday) so Apple-Health data reads on the Today tiles
        // when the strap hasn't covered the day yet — badged "Apple Health" so a fallback value is
        // never passed off as a live strap reading. Day Strain stays strap-only (a computed score Apple
        // doesn't provide), so it placeholders until the strap scores the day. (FER-62 follow-up)
        let hrvR   = resolveMeasured { $0.avgHrv }
        let rhrR   = resolveMeasured { $0.restingHr.map(Double.init) }
        let sleepR = resolveMeasured { $0.totalSleepMin }
        let spo2R  = resolveMeasured { $0.spo2Pct }
        let hrvFlag: LocalizedStringKey? = hrvR?.fromApple == true ? "Apple Health"
            : ((hrvR != nil && readiness.confidenceLow) ? "Low conf" : nil)
        let hrvFlagColor = hrvR?.fromApple == true ? StrandPalette.metricCyan : StrandPalette.statusWarning
        // Steps come only from Apple Health; guard the most-recent row to the 14-day window so a stale
        // import can't render months-old steps under a Today tile (the secondary path was already
        // windowed — this closes the hole in the primary `appleDays.last`, which scanned all history).
        let stepsCutoff = Repository.localDayKey(Calendar.current.date(byAdding: .day, value: -13, to: Date()) ?? Date())
        let stepsFresh = appleDays.last(where: { $0.day >= stepsCutoff })?.steps
        let stepsStr = stepsFresh.map { intString(Double($0)) } ?? latestString("steps", decimals: 0)
        // Nudge to connect Apple Health only when it isn't connected AND a measured row is actually
        // empty — so a strap-covered day never nags and a connected user never sees it. Tapping opens
        // Data Sources; once connected, the launch auto-sync fills these rows on its own. (FER-94)
        let notConnected = health.auth != .authorized && health.auth != .unavailable
        let anyMeasuredMissing = hrvR == nil || sleepR == nil || rhrR == nil || spo2R == nil || stepsFresh == nil
        VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            SectionHeader("Key Metrics", overline: "Today", trailing: String(localized: "14-day trend"))
            VStack(spacing: 0) {
                Button { metricDetail = .strain(d?.strain) } label: {
                    MetricRow(label: "Day Strain",
                              value: d?.strain.map { String(format: "%.1f", $0) } ?? "—",
                              valueColor: d?.strain.map { StrandPalette.strainColor($0) } ?? StrandPalette.textPrimary,
                              sparkline: sparks["strain"], sparkColor: StrandPalette.strain066,
                              isPlaceholder: d?.strain == nil)
                }.buttonStyle(.plain)
                metricSeparator
                Button { metricDetail = .sleep(sleepR.map { Int($0.value.rounded()) }) } label: {
                    MetricRow(label: "Sleep",
                              value: sleepR.map { sleepText($0.value) } ?? "—",
                              flag: sleepR?.fromApple == true ? "Apple Health" : nil,
                              flagColor: StrandPalette.metricCyan,
                              sparkline: measuredSpark("sleep_total_min") { $0.totalSleepMin },
                              sparkColor: StrandPalette.metricPurple,
                              isPlaceholder: sleepR == nil)
                }.buttonStyle(.plain)
                metricSeparator
                Button { metricDetail = .hrv(hrvR?.value) } label: {
                    MetricRow(label: "HRV",
                              value: hrvR.map { "\(Int($0.value.rounded()))" } ?? "—",
                              unit: "ms", valueColor: StrandPalette.metricPurple,
                              flag: hrvFlag, flagColor: hrvFlagColor,
                              sparkline: measuredSpark("hrv") { $0.avgHrv },
                              sparkColor: StrandPalette.metricPurple,
                              isPlaceholder: hrvR == nil)
                }.buttonStyle(.plain)
                metricSeparator
                Button { metricDetail = .restingHR(rhrR.map { Int($0.value.rounded()) }) } label: {
                    MetricRow(label: "Resting HR",
                              value: rhrR.map { "\(Int($0.value.rounded()))" } ?? "—",
                              unit: "bpm", valueColor: StrandPalette.metricRose,
                              flag: rhrR?.fromApple == true ? "Apple Health" : nil,
                              flagColor: StrandPalette.metricCyan,
                              sparkline: measuredSpark("rhr") { $0.restingHr.map(Double.init) },
                              sparkColor: StrandPalette.metricRose,
                              isPlaceholder: rhrR == nil)
                }.buttonStyle(.plain)
                metricSeparator
                Button { metricDetail = .spo2(spo2R?.value) } label: {
                    MetricRow(label: "Blood Oxygen",
                              value: spo2R.map { String(format: "%.0f", $0.value) } ?? "—",
                              unit: "%", valueColor: StrandPalette.metricCyan,
                              flag: spo2R?.fromApple == true ? "Apple Health" : nil,
                              flagColor: StrandPalette.metricCyan,
                              sparkline: measuredSpark("spo2") { $0.spo2Pct },
                              sparkColor: StrandPalette.metricCyan,
                              isPlaceholder: spo2R == nil)
                }.buttonStyle(.plain)
                metricSeparator
                Button { metricDetail = .steps(stepsFresh) } label: {
                    MetricRow(label: "Steps",
                              value: stepsStr,
                              sparkline: sparks["steps"], sparkColor: StrandPalette.metricCyan,
                              isPlaceholder: stepsStr == "—")
                }.buttonStyle(.plain)
            }
            if notConnected && anyMeasuredMissing {
                Button { showDataSources = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "heart.fill")
                        Text("Connect Apple Health")
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .foregroundStyle(StrandPalette.textTertiary)
                    }
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.metricCyan)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Hairline between metric rows (not above the first — the section header already caps the list).
    private var metricSeparator: some View {
        Divider().overlay(StrandPalette.hairline)
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
                            label: "\(WorkoutSource.displaySport(w.sport))",
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
    /// offload runs — syncMeta in the utility row already signals the in-progress state subtly.
    /// TimelineView re-renders the relative label each minute so "5 min ago" can't go stale while
    /// the window sits open with no strap connected (LiveState publishes nothing then).
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
        return sleepText(m)
    }

    /// Sleep minutes → "Xh Ym".
    private func sleepText(_ mins: Double) -> String {
        "\(Int(mins) / 60)h \(Int(mins) % 60)m"
    }

    /// Resolve a measured signal (HRV / sleep / resting HR / SpO₂) for the Today tiles. Today's row
    /// wins; otherwise the most recent value within the freshness window (today/yesterday) so a fresh
    /// Apple-Health import or sync still reads on the tile — but never older, since a stale value under
    /// a "Today" header would misrepresent it (same spirit as the #23/#49 trailing-window fixes).
    /// `fromApple` flags Apple-sourced values so the row badges them instead of passing them off as a
    /// live strap reading. Returns nil when nothing fresh exists → the row placeholders. (FER-62 follow-up)
    private func resolveMeasured(_ pick: (DailyMetric) -> Double?) -> (value: Double, fromApple: Bool)? {
        let todayKey = Repository.localDayKey(Date())
        if let d = repo.today, let v = pick(d) { return (v, repo.appleHealthDays.contains(todayKey)) }
        let cutoff = Repository.localDayKey(Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date())
        for day in repo.days.reversed() {
            guard day.day >= cutoff else { return nil }
            if let v = pick(day) { return (v, repo.appleHealthDays.contains(day.day)) }
        }
        return nil
    }

    /// Inline sparkline for a measured tile: the strap series when present (unchanged behaviour),
    /// otherwise a 14-day series rebuilt from the merged daily rows so Apple-only history still draws.
    private func measuredSpark(_ key: String, _ pick: (DailyMetric) -> Double?) -> [Double]? {
        if let s = sparks[key], s.count > 1 { return s }
        let cutoff = Repository.localDayKey(Calendar.current.date(byAdding: .day, value: -13, to: Date()) ?? Date())
        let apple = repo.days.filter { $0.day >= cutoff }.compactMap(pick)
        return apple.count > 1 ? apple : sparks[key]
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
        #if os(iOS)
        // iOS TodayView reads AppModel (first-launch "Scan for strap" CTA) and HealthKitBridge (the
        // Apple Health connect nudge); inject both so the iOS canvas renders instead of trapping on a
        // missing environment object.
        .environmentObject(AppModel())
        .environmentObject(HealthKitBridge(repo: repo, appleDeviceId: "preview-apple", noopDeviceId: "preview"))
        #endif
        .frame(width: 920, height: 940)
        .preferredColorScheme(.dark)
}
#endif
