#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore
import Foundation

// MARK: - Cuerpo (the «between-days / history» landing) — FER-186
//
// The «Cuerpo» tab of the 3-layer IA redesign (FER-182 placed it; this screen replaces its interim
// `TrendsView`). An Apple-Health-Summary-style curated landing in the light «Instrumento diurno»
// language: warm paper, color ONLY on the datum, hierarchy by space. One column of grouped sections —
// Recuperación (hero) · Descanso & carga · Vitales · Actividad · Longevidad — each row a `MetricRow`
// (label · 14-day sparkline · value in its data hue · chevron) that opens a detail. The sparklines
// carry NO p25–p75 reference band: at 60×26 pt the band read as a grey box behind the line, not as
// context (it fought the «color only in the datum» DNA). The `Sparkline`/`MetricRow` band API stays
// for any future large-chart caller; these dense rows just don't pass it.
//
// Detail bridge: every vital now opens a light «Instrumento» sheet — the scalar vitals (HRV / Resting HR /
// Respiración / SpO₂) through the unified `MetricDetailScreen` (FER-185), and the composite/own-shaped ones
// through their dedicated screens (Recovery / Sueño / Esfuerzo / Estrés, and Temp. de piel via
// `SkinTempDetailScreen`, FER-256). Entrenamientos, Comparar and «Ver todas» (Explore, FER-272) now also
// open light «Instrumento» sheets. Only Data Sources still opens the legacy dark screen as a `.sheet`
// pinned to `.dark` (a light tab pushing a dark screen would leave the status bar's dark ink on a
// near-black panel, so a self-contained dark sheet is the honest bridge, same pattern Today uses for
// Live / Data Sources).
//
// Values + sparklines read from `repo.displayDays` (the merged dashboard), NOT `series()`: the
// on-device computed scores live in daily-metrics under `my-whoop-noop`, so `series("my-whoop")` is
// empty for a BLE user — `displayDays` resolves for both import and strap users (FER-149).

/// Theme wrapper: drives `\.instrumentoTheme` by the hour (like Today) so the landing warms with the
/// real sun, then hands off to `CuerpoLanding`, which reads the resolved theme from the environment.
struct CuerpoView: View {
    var body: some View {
        CuerpoLanding()
            .instrumentoThemeByHour(solar: Self.solarWindow())
    }

    /// Sunrise/sunset for today, GPS- and permission-free (same `SolarClock` source Today uses), so
    /// the paper tracks the sun. `nil` in polar cases falls back to fixed hours.
    private static func solarWindow() -> SolarWindow? {
        guard let w = SolarClock.sunWindow(on: Date(), in: .current) else { return nil }
        return SolarWindow(sunrise: w.sunrise, sunset: w.sunset)
    }
}

// MARK: - Sheet routing

/// A dark, existing screen presented as a self-contained sheet (pinned to `.dark`).
private enum CuerpoScreen: Hashable { case dataSources }

/// Identifiable wrapper so the light «Instrumento» Detalle de Sueño can ride `.sheet(item:)`
/// (the model itself isn't Identifiable). One per presentation. (FER-212)
private struct SleepDetailItem: Identifiable {
    let id = UUID()
    let model: SleepDetailModel
}

/// The dark-sheet driver — the remaining legacy dark screen without a light sheet yet (Data Sources).
private enum CuerpoSheet: Identifiable {
    case screen(CuerpoScreen)
    var id: String {
        switch self {
        case .screen(let s): return "screen-\(s)"
        }
    }
}

// MARK: - Landing

private struct CuerpoLanding: View {
    @EnvironmentObject var repo: Repository
    @EnvironmentObject var live: LiveState
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var health: HealthKitBridge
    @Environment(\.instrumentoTheme) private var theme

    /// Light metric sheet (the same one Today opens), for metrics that have a `MetricInfo` factory.
    @State private var metricInfo: MetricInfo? = nil
    /// Unified Detalle de Métrica (FER-185): the three vitals (HRV / FC reposo / Respiración) open this
    /// at `.full` depth instead of the legacy `MetricInfoSheet` / dark `MetricDetailView` bridge.
    @State private var metricSpec: MetricDetailSpec? = nil
    /// Light «Instrumento» Detalle de Recuperación (FER-225): the recovery hero now opens this rich detail
    /// (superset of the old `MetricInfoSheet`), built fresh on tap from the in-memory dashboard, theme
    /// passed explicitly.
    @State private var recoveryDetail: RecoveryDetailItem? = nil
    /// Dark screen / catalog-detail sheet, for everything without a light sheet yet.
    @State private var darkSheet: CuerpoSheet? = nil
    /// Light «Instrumento» Comparar (FER-268) — the «Compare» row now opens the reskinned overlay screen
    /// as a light sheet (theme injected at the root; it doesn't cross the `.sheet` boundary, FER-162), NO
    /// nested NavigationStack (FER-171). Replaces the old dark `.screen(.compare)` bridge.
    @State private var showCompare = false
    /// Light «Instrumento» Explore (FER-272) — the «See all metrics» row now opens the reskinned metric
    /// catalog as a light sheet with its OWN NavigationStack (so a metric row pushes its detail), theme
    /// injected at the sheet root (it doesn't cross the `.sheet` boundary, FER-162). Replaces the old dark
    /// `.screen(.explore)` bridge.
    @State private var showExplore = false
    /// Light «Instrumento» Entrenamientos (FER-260) — the «Workouts» row now opens the reskinned list as a
    /// light sheet with its own NavigationStack (so a session row can push the detail), theme injected at
    /// the sheet root. Replaces the old dark `.screen(.workouts)` bridge.
    @State private var showWorkouts = false
    /// Light «Instrumento» Detalle de Sueño (FER-212) — the «Sueño» row now opens this superset of the
    /// old dark sleep screen (built fresh on tap from the in-memory dashboard), theme passed explicitly.
    @State private var sleepDetail: SleepDetailItem? = nil
    /// Light «Instrumento» Detalle de Esfuerzo (FER-238) — the «Day Strain» row now opens this rich detail
    /// (curva intradía + zonas + tendencia + método) instead of the legacy `MetricInfoSheet`. Hoy unchanged.
    @State private var strainDetail: StrainDetailItem? = nil
    /// Light «Instrumento» Detalle de Estrés (FER-241) — the «Stress» row now opens this dedicated screen
    /// (valor de hoy + bandas universales + qué lo mueve + ⓘ por concepto), theme passed explicitly. SOLO
    /// en Cuerpo: el tile de Estrés en Hoy NO cambia.
    @State private var stressDetail: StressDetailItem? = nil
    /// Light «Instrumento» Detalle de Temperatura de la piel (FER-256) — the «Skin Temperature» row now
    /// opens this dedicated screen (última lectura + tendencia con banda ±típica + consistencia en SD °C +
    /// método) instead of the legacy dark catalog sheet; theme passed explicitly.
    @State private var skinTempDetail: SkinTempDetailItem? = nil
    /// «How you wake after each sport» — ranked ActivityCost per sport (FER-139); empty = "gathering data".
    @State private var activityCosts: [ActivityCost] = []
    /// Presents the light Activity-recovery detail sheet.
    @State private var showActivityCost = false
    /// Body Age + Vitality (FER-145): computed in `loadAll` from a window of nightly signals; nil until
    /// ≥3 factors are present. `vitalityInputs` drives the detail's "what's built from" checklist.
    @State private var vitalityResult: VitalityEngine.Result? = nil
    @State private var vitalityInputs: VitalityEngine.Inputs? = nil
    /// Presents the light Body-age detail sheet.
    @State private var showBodyAge = false

    // Loaded once per refresh (memoized in `loadAll`) so the body never re-scans history per render.
    @State private var sparks: [String: [Double]] = [:]
    @State private var hrPoints: [TrendPoint] = []
    @State private var appleDays: [AppleDaily] = []
    @State private var appleMetricDays: [DailyMetric] = []
    @State private var workoutCount: Int = 0
    /// Sessions in the trailing 14 days — the «Entrenamientos» row's protagonist (recent training, not
    /// the unbounded all-time total). `workoutCount` stays the lifetime count for the Apple-connect hint.
    @State private var recentWorkoutCount: Int = 0
    /// Today's stress model (0–3 autonomic proxy + markers + trend) — the same transparent model Hoy builds.
    /// Held whole (not just the score) so the «Stress» row can open the dedicated detail (FER-241).
    @State private var stressModel: StressModel? = nil
    /// Recovery cold-start: nights banked toward the seed gate while the baseline calibrates; nil once
    /// recovery is scored. Drives the hero's "N/4" + "Calibrating" copy instead of a fake number.
    @State private var recoveryCalibration: Int? = nil
    /// Fitness Age (FER-141): the 7-day orchestration snapshot, memoized once per refresh in `loadAll`.
    @State private var fitnessAge: FitnessAgeSnapshot? = nil
    /// Drives the Fitness Age detail sheet (the light «Instrumento» sheet for «Edad física»).
    @State private var showFitnessAge = false

    private static let recoverySeed = Baselines.minNightsSeed

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                Text("Body").font(StrandFont.title1).foregroundStyle(theme.ink)
                    .padding(.bottom, -8)

                recoveryHero

                section("Rest & load") {
                    sleepRow
                    divider
                    strainRow
                    divider
                    stressRow
                }

                section("Vitals") {
                    hrvRow;  divider
                    rhrRow;  divider
                    spo2Row; divider
                    heartRow; divider
                    respRow; divider
                    skinTempRow
                }

                section("Activity") {
                    stepsRow
                    divider
                    workoutsRow
                }

                activityCostBlock

                section("Longevity") {
                    physicalAgeRow
                    divider
                    bodyAgeRow
                    divider
                    vo2maxRow
                }

                connectNudge
                footerActions
            }
            .padding(.horizontal, NoopMetrics.screenPadding)
            .padding(.top, 20)
            .padding(.bottom, NoopMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(PaperBackground())
        .task(id: repo.refreshSeq) { await loadAll() }
        .sheet(item: $metricInfo) { info in metricSheet(for: info) }
        .sheet(item: $metricSpec) { spec in
            MetricDetailScreen(
                spec: spec,
                depth: .full,
                theme: theme,
                // VO₂max is Apple-only: invite connecting Apple Health from its empty state when nothing's
                // connected and there's no reading (mirrors the Fitness Age VO₂max nudge). (FER-257)
                appleConnectHint: spec.descriptor.key == "vo2max"
                    && health.auth != .authorized && health.auth != .unavailable
                    && latestAppleVO2max == nil,
                seriesLoader: { vitalSeries(for: spec.descriptor.key) },
                nightVitalsLoader: spec.blocks.contains(.nightVitals) ? { await loadNightVitals() } : nil,
                whatMovesItLoader: spec.blocks.contains(.whatMovesIt)
                    ? { whatMovesItFindings(for: spec.descriptor.key) }
                    : nil,
                intradayCurveLoader: spec.blocks.contains(.intradayCurve) ? { hrPoints } : nil,
                hrMax: Double(model.profile.hrMax),
                restingHR: resolveMeasured { $0.restingHr.map(Double.init) }?.value,
                todayKey: Repository.localDayKey(Date())
            )
        }
        .sheet(item: $recoveryDetail) { item in
            // Light «Instrumento» Detalle de Recuperación — theme passed explicitly (it doesn't propagate
            // through `.sheet`), NO nested NavigationStack (FER-171). (FER-225)
            RecoveryDetailScreen(theme: theme, model: item.model)
        }
        .sheet(item: $darkSheet) { sheet in darkSheetContent(sheet) }
        .sheet(isPresented: $showCompare) {
            // Light «Instrumento» Comparar — the theme is injected at the root (it doesn't cross the
            // `.sheet` boundary, FER-162) and the env objects are re-supplied (a sheet starts a fresh
            // environment branch). No nested NavigationStack (FER-171); you drag to dismiss. (FER-268)
            CompareView()
                .instrumentoTheme(theme)
                .environmentObject(repo)
                .environmentObject(live)
                .environmentObject(model)
                .environmentObject(health)
        }
        .sheet(isPresented: $showWorkouts) {
            // Light «Instrumento» Entrenamientos — its OWN NavigationStack lives inside the sheet so each
            // session row pushes the detail (NOT a stack nested across the tab path, FER-171). The theme is
            // injected at the root (it doesn't cross the `.sheet` boundary, FER-162), and the screen's env
            // objects are re-supplied (a sheet starts a fresh environment branch). (FER-260)
            NavigationStack { WorkoutsView() }
                .instrumentoTheme(theme)
                .environmentObject(repo)
                .environmentObject(live)
                .environmentObject(model)
                .environmentObject(health)
        }
        .sheet(isPresented: $showExplore) {
            // Light «Instrumento» Explore (FER-272) — its OWN NavigationStack lives inside the sheet so a
            // metric row pushes its detail (NOT a stack nested across the tab path, FER-171). The theme is
            // passed explicitly to the screen AND injected at the root (it doesn't cross the `.sheet`
            // boundary, FER-162); the env objects are re-supplied (a sheet starts a fresh environment).
            // A light sheet from a light tab keeps the status bar honest (no dark pin needed).
            NavigationStack {
                MetricExplorerView(theme: theme)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showExplore = false }.foregroundStyle(theme.ink)
                        }
                    }
            }
            .instrumentoTheme(theme)
            .environmentObject(repo)
            .environmentObject(live)
            .environmentObject(model)
            .environmentObject(health)
        }
        .sheet(item: $strainDetail) { item in
            // Light «Instrumento» Detalle de Esfuerzo — theme passed explicitly (it doesn't propagate
            // through `.sheet`), NO nested NavigationStack (FER-171). The intraday curve is loaded the
            // same way the legacy sheet did (`loadStrainCurve`). (FER-238)
            StrainDetailScreen(theme: theme, model: item.model,
                               curveLoader: { await loadStrainCurve() })
        }
        .sheet(item: $sleepDetail) { item in
            // Light «Instrumento» sheet — pass the resolved theme explicitly (it doesn't propagate
            // through `.sheet`), NO nested NavigationStack (FER-171). (FER-212)
            SleepDetailScreen(theme: theme, model: item.model)
        }
        .sheet(item: $stressDetail) { item in
            // Light «Instrumento» Detalle de Estrés — theme passed explicitly (it doesn't propagate
            // through `.sheet`), NO nested NavigationStack (FER-171). SOLO Cuerpo. (FER-241)
            StressDetailScreen(theme: theme, model: item.model)
        }
        .sheet(item: $skinTempDetail) { item in
            // Light «Instrumento» Detalle de Temperatura de la piel — theme passed explicitly (it doesn't
            // propagate through `.sheet`), NO nested NavigationStack (FER-171). (FER-256)
            SkinTempDetailScreen(theme: theme, model: item.model)
        }
        .sheet(isPresented: $showActivityCost) { activityRecoverySheet }
        .sheet(isPresented: $showFitnessAge) {
            // Light «Instrumento» sheet — pass the resolved theme explicitly (it doesn't propagate
            // through `.sheet`), same as the metric sheet above.
            FitnessAgeDetailView(snapshot: fitnessAge ?? computeFitnessAge(),
                                 chronoAge: model.profile.age, sex: model.profile.sex,
                                 appleVO2max: latestAppleVO2max,
                                 appleConnectHint: health.auth != .authorized && health.auth != .unavailable
                                     && latestAppleVO2max == nil,
                                 theme: theme)
        }
        .sheet(isPresented: $showBodyAge) {
            BodyAgeSheet(
                result: vitalityResult,
                inputs: vitalityInputs ?? VitalityEngine.Inputs(chronoAge: Double(model.profile.age)),
                theme: theme)
        }
    }

    /// The canvas — read inside the themed subtree so it recolors by hour too.
    private struct PaperBackground: View {
        @Environment(\.instrumentoTheme) private var theme
        var body: some View { theme.paper.ignoresSafeArea() }
    }

    // MARK: - Section scaffolding

    /// A section: a quiet overline + a column of rows, grouped by space + hairlines on the paper
    /// (no card-in-card — Instrumento rule 3).
    @ViewBuilder
    private func section<Rows: View>(_ title: LocalizedStringKey, @ViewBuilder rows: () -> Rows) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).instrumentoOverline().foregroundStyle(theme.inkTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 4)
            rows()
        }
    }

    private var divider: some View { Divider().overlay(theme.hairline) }

    // MARK: - Generic metric row

    /// One `MetricRow` wired to the light theme: value in its data hue (ink when absent), 14-day
    /// sparkline, chevron, whole row tappable. `value == nil` shows an honest "—".
    private func metricRow(_ label: LocalizedStringKey, value: String?, unit: String? = nil,
                           color: Color, sparkKey: String, fromApple: Bool = false,
                           open: @escaping () -> Void) -> some View {
        let spark = sparks[sparkKey]
        let validSpark = (spark?.count ?? 0) > 1 ? spark : nil
        return Button(action: open) {
            MetricRow(
                label: label,
                value: value ?? "—",
                unit: value == nil ? nil : unit,
                valueColor: value == nil ? theme.inkTertiary : color,
                labelColor: theme.inkSecondary,
                unitColor: theme.inkTertiary,
                flag: fromApple ? "Apple Health" : nil,
                flagColor: theme.inkTertiary,
                sparkline: validSpark,
                sparkColor: color,
                isPlaceholder: value == nil,
                showsChevron: true,
                chevronColor: theme.inkTertiary
            )
        }
        .buttonStyle(MetricRowButtonStyle(pressedFill: theme.ink.opacity(0.05)))
    }

    // MARK: - Recovery hero (the dominant, highlighted row)

    private var recoveryHero: some View {
        let score = repo.today?.recovery.map { Int($0.rounded()) }
        let cal = recoveryCalibration
        let spark = sparks["recovery"]
        let showSpark = (spark?.count ?? 0) > 1 && score != nil
        let color = score.map(recoveryColor) ?? theme.inkTertiary
        return Button {
            recoveryDetail = RecoveryDetailItem(model: RecoveryDetailModel.build(
                days: repo.days,
                today: repo.today,
                todayKey: Repository.localDayKey(Date()),
                appleHealthDays: repo.appleHealthDays,
                loaded: repo.loaded,
                importedSleep: repo.importedSleep))
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Recovery").font(StrandFont.headline).foregroundStyle(theme.ink)
                    Text(recoverySubtitle(score: score, calibrating: cal))
                        .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                }
                Spacer(minLength: 8)
                if showSpark, let spark {
                    Sparkline(values: spark,
                              gradient: Gradient(colors: [color.opacity(0.55), color]),
                              lineWidth: 2, showsArea: false, showsHead: false, showsScrub: false)
                        .frame(width: 64, height: 28)
                }
                recoveryNumeral(score: score, calibrating: cal, color: color)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.inkTertiary)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous)
                .strokeBorder(theme.hairline, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func recoveryNumeral(score: Int?, calibrating: Int?, color: Color) -> some View {
        if let score {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(score)").font(StrandFont.number(30)).foregroundStyle(color)
                Text("/100").font(StrandFont.subhead).foregroundStyle(theme.inkTertiary)
            }
        } else if let calibrating {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(calibrating)").font(StrandFont.number(30)).foregroundStyle(theme.ink)
                Text("/\(Self.recoverySeed)").font(StrandFont.subhead).foregroundStyle(theme.inkTertiary)
            }
        } else {
            Text("—").font(StrandFont.number(30)).foregroundStyle(theme.inkTertiary)
        }
    }

    // MARK: - Rows

    private var sleepRow: some View {
        let r = resolveMeasured { $0.totalSleepMin }
        return metricRow("Sleep", value: r.map { sleepText($0.value) }, color: theme.dataSleep,
                         sparkKey: "sleep_total_min", fromApple: r?.fromApple == true) {
            sleepDetail = SleepDetailItem(model: SleepDetailModel.build(
                days: repo.days,
                sleeps: repo.sleeps,
                importedSleep: repo.importedSleep,
                appleHealthDays: repo.appleHealthDays,
                loaded: repo.loaded,
                todayKey: Repository.localDayKey(Date())))
        }
    }

    private var strainRow: some View {
        let v = repo.today?.strain
        return metricRow("Day Strain", value: v.map { String(format: "%.1f", $0) },
                         color: theme.dataStrain, sparkKey: "strain") {
            // Opens the rich Detalle de Esfuerzo (FER-238) — built fresh from the in-memory dashboard;
            // the intraday curve loads async in the screen via `loadStrainCurve`. (Hoy still uses
            // `MetricInfo.strain`/`MetricInfoSheet`.)
            strainDetail = StrainDetailItem(model: StrainDetailModel.build(
                days: repo.days, today: repo.today, loaded: repo.loaded))
        }
    }

    private var stressRow: some View {
        let s = stressModel?.score
        return metricRow("Stress", value: s.map { String(format: "%.1f", $0) },
                         unit: s == nil ? nil : "/ 3",
                         color: s.map(stressDataColor) ?? theme.inkTertiary, sparkKey: "stress") {
            stressDetail = StressDetailItem(model: stressModel)
        }
    }

    private var hrvRow: some View {
        let r = resolveMeasured { $0.avgHrv }
        return metricRow("HRV", value: r.map { "\(Int($0.value.rounded()))" }, unit: "ms",
                         color: theme.dataHrv, sparkKey: "hrv", fromApple: r?.fromApple == true) {
            metricSpec = .hrv(r?.value)
        }
    }

    private var rhrRow: some View {
        let r = resolveMeasured { $0.restingHr.map(Double.init) }
        return metricRow("Resting HR", value: r.map { "\(Int($0.value.rounded()))" }, unit: String(localized: "bpm"),
                         color: theme.dataHeart, sparkKey: "rhr", fromApple: r?.fromApple == true) {
            metricSpec = .restingHR(r.map { Int($0.value.rounded()) })
        }
    }

    private var spo2Row: some View {
        let r = resolveMeasured { $0.spo2Pct }
        return metricRow("Blood Oxygen", value: r.map { String(format: "%.0f", $0.value) }, unit: "%",
                         color: theme.dataSpO2, sparkKey: "spo2", fromApple: r?.fromApple == true) {
            metricSpec = .spo2(r?.value)
        }
    }

    private var heartRow: some View {
        let avg = hrTodayAvg
        return metricRow("Heart Rate", value: avg.map { "\($0)" }, unit: String(localized: "bpm"),
                         color: theme.dataHeart, sparkKey: "_none") {
            metricSpec = .heartRate(avg)
        }
    }

    private var respRow: some View {
        let r = resolveMeasured { $0.respRateBpm }
        return metricRow("Respiratory Rate", value: r.map { String(format: "%.1f", $0.value) }, unit: "rpm",
                         color: theme.dataSpO2, sparkKey: "resp_rate", fromApple: r?.fromApple == true) {
            metricSpec = .respiratory(r?.value)
        }
    }

    private var skinTempRow: some View {
        let r = resolveMeasured { $0.skinTempDevC }
        return metricRow("Skin Temperature", value: r.map { String(format: "%+.1f", $0.value) }, unit: "°C",
                         color: theme.dataStrain, sparkKey: "skin_temp", fromApple: r?.fromApple == true) {
            // Opens the rich light Detalle de Temperatura de la piel (FER-256) — built fresh from the
            // in-memory dashboard (última lectura resuelta + serie completa de `displayDays`).
            skinTempDetail = SkinTempDetailItem(model: SkinTempDetailModel.build(
                latest: r?.value, series: vitalSeries(for: "skin_temp"), loaded: repo.loaded))
        }
    }

    private var stepsRow: some View {
        let steps = freshSteps
        return metricRow("Steps", value: steps.map { intString(Double($0)) },
                         color: theme.dataSteps, sparkKey: "steps") {
            metricSpec = .steps(steps)
        }
    }

    /// «Entrenamientos» — now consistent with the other Activity rows: the recent-session count tinted in
    /// the effort hue (`dataStrain`), not the neutral ink it used before. No sparkline — workout volume is
    /// too sparse/spiky to read as a trend at this size, so the number carries it alone (like Heart Rate).
    /// No recent sessions → honest "—"; VoiceOver says it plainly, not "dash". (FER-259)
    @ViewBuilder private var workoutsRow: some View {
        let n = recentWorkoutCount
        let row = metricRow("Workouts", value: n > 0 ? "\(n)" : nil,
                            color: theme.dataStrain, sparkKey: "_none") {
            showWorkouts = true
        }
        if n > 0 {
            row
        } else {
            row.accessibilityLabel(Text("sin entrenamientos aún"))
        }
    }

    // MARK: - Physical age (Fitness Age, FER-141)

    /// The Longevity row that opens the Fitness Age detail. Custom (not `MetricRow`): the delta lives
    /// UNDER the label and there's no sparkline — the number is tinted by DIRECTION (verde younger /
    /// ámbar older / ink even / faint when there's no reading yet). The whole row taps into the detail.
    private var physicalAgeRow: some View {
        let snap = fitnessAge
        let estimate = snap?.readiness.confidence == .estimate
        return Button {
            showFitnessAge = true
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Physical age").font(StrandFont.body).foregroundStyle(theme.inkSecondary)
                        if estimate { InlineFlagChip("Estimate", color: theme.warning) }
                    }
                    Text(physicalAgeSubtitle(snap))
                        .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                physicalAgeValue(snap)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.inkTertiary)
                    .accessibilityHidden(true)   // decorative — the whole row is the button
            }
            .padding(.vertical, 15)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(MetricRowButtonStyle(pressedFill: theme.ink.opacity(0.05)))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func physicalAgeValue(_ snap: FitnessAgeSnapshot?) -> some View {
        if let result = snap?.result {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(Int(result.fitnessAge.rounded()))")
                    .font(StrandFont.number(20)).foregroundStyle(physicalAgeColor(result))
                Text("years").font(StrandFont.unit).foregroundStyle(theme.inkTertiary)
            }
        } else {
            // Honest "no reading yet" — VoiceOver says it plainly, not "dash" (mirrors MetricRow).
            Text("—").font(StrandFont.number(20)).foregroundStyle(theme.inkTertiary)
                .accessibilityLabel(Text("sin dato de hoy"))
        }
    }

    /// Direction hue: younger → recovery green, older → warning amber, even → ink. The ±0.5-yr
    /// deadband lives on `FitnessAgeResult.direction` (StrandAnalytics) so the row and the sheet agree.
    private func physicalAgeColor(_ result: FitnessAgeResult) -> Color {
        switch result.direction {
        case .younger: return theme.dataRecovery
        case .older:   return theme.warning
        case .even:    return theme.ink
        }
    }

    private func physicalAgeSubtitle(_ snap: FitnessAgeSnapshot?) -> LocalizedStringKey {
        guard let snap else { return " " }   // still loading: keep the row's height stable
        if let result = snap.result {
            let yrs = Int(abs(result.deltaYears).rounded())
            let chrono = Int(result.chronoAge.rounded())
            switch result.direction {
            case .younger: return "\(yrs) years younger than your \(chrono)"
            case .older:   return "\(yrs) years above your \(chrono)"
            case .even:    return "Right at your \(chrono)"
            }
        }
        // notReady — RHR coverage is the real blocker (age/sex come from the profile defaults).
        return "Missing resting-HR nights (\(snap.rhrNights) of 4)"
    }

    /// Build the Fitness Age snapshot from the trailing 7-day display window + profile. Pure + cheap;
    /// memoized into `fitnessAge` by `loadAll`, recomputed on demand as the sheet's fallback.
    private func computeFitnessAge() -> FitnessAgeSnapshot {
        let last7 = trailingDisplay(7)
        return FitnessAgeEngine.snapshot(
            rhrLast7: last7.map { $0.restingHr },
            strainLast7: last7.map { $0.strain },
            age: model.profile.age, sex: model.profile.sex,
            hasHeightWeight: true)
    }

    /// «Body age» (Vitality/Body Age, FER-145): the years datum, tinted by the SIGN of the delta, opening
    /// the longevity detail. No sparkline — Body Age isn't a daily-stored series (its trend lives in the
    /// detail's ±5 band); the row still opens the detail with no reading yet (the honest checklist).
    private var bodyAgeRow: some View {
        let r = vitalityResult
        let color = r.map { BodyAgeSheet.tint(forDelta: $0.deltaYears, theme: theme) } ?? theme.inkTertiary
        return metricRow("Body age", value: r.map { "\(Int($0.bodyAge.rounded()))" },
                         unit: r == nil ? nil : String(localized: "yrs"),
                         color: color, sparkKey: "_none") {
            showBodyAge = true
        }
    }

    /// VO₂max (Apple Health, measured · FER-257): the Longevity row opening the rich detail. Apple-only and
    /// SPARSELY measured, so there's no sparkline (`sparkKey: "vo2max"` stays unpopulated) and the value
    /// uses the most recent reading (`latestAppleVO2max`), no today/yesterday freshness gate. «—» + no
    /// badge when there's no reading; the detail then shows the explanatory empty state.
    ///
    /// No unit in the dense row: `MetricRow`'s value column is a fixed 88pt (to align decimals across
    /// rows), and "ml/kg/min" is far too long for it — it truncated the number itself ("35…"). The unit
    /// lives in full in the detail (hero + blocks), so the row shows just the number. (FER-263)
    private var vo2maxRow: some View {
        let v = latestAppleVO2max
        return metricRow("VO₂ Max", value: v.map { String(format: "%.1f", $0) },
                         color: theme.dataSpO2, sparkKey: "vo2max", fromApple: v != nil) {
            metricSpec = .vo2max(value: v, age: model.profile.age, sex: model.profile.sex)
        }
    }

    // MARK: - Connect nudge + footer

    /// Apple-only metrics (Steps) invite connecting Apple Health when it isn't authorized and there's no
    /// stored value — without promising data that doesn't exist. Opens Data Sources.
    @ViewBuilder private var connectNudge: some View {
        let notConnected = health.auth != .authorized && health.auth != .unavailable
        if notConnected && freshSteps == nil {
            Button { darkSheet = .screen(.dataSources) } label: {
                HStack(spacing: 8) {
                    Image(systemName: "heart.fill").font(.system(size: 12)).foregroundStyle(theme.dataSpO2)
                    Text("Connect Apple Health to fill steps and more.")
                        .font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
                    Spacer(minLength: 6)
                    Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(theme.inkTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var footerActions: some View {
        VStack(spacing: 0) {
            actionRow("Compare", icon: "arrow.left.arrow.right") { showCompare = true }
            Divider().overlay(theme.hairline).padding(.leading, 46)
            actionRow("See all metrics", icon: "square.grid.2x2") { showExplore = true }
        }
        .background(theme.surface, in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous)
            .strokeBorder(theme.hairline, lineWidth: 1))
    }

    private func actionRow(_ label: LocalizedStringKey, icon: String, open: @escaping () -> Void) -> some View {
        Button(action: open) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 16, weight: .medium))
                    .foregroundStyle(theme.inkSecondary).frame(width: 22)
                Text(label).font(StrandFont.body).foregroundStyle(theme.ink)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.inkTertiary)
            }
            .padding(.horizontal, 16).padding(.vertical, 15)
            .contentShape(Rectangle())
        }
        .buttonStyle(MetricRowButtonStyle(pressedFill: theme.ink.opacity(0.05)))
    }

    // MARK: - Activity recovery (FER-139)

    /// «How you wake after each sport» — the Variant-C mini-block: a `theme.surface` card (same mold as
    /// `recoveryHero` / `footerActions`, no card-in-card) holding up to three top sports from the
    /// engine's ranking, each as `sport · N pts lower/higher` (colour only on the datum). A `delta < 3`
    /// sport reads «no clear link». When the engine returns nothing the block stays, showing «Gathering
    /// data» — it never hides. The whole block opens the detail.
    private var activityCostBlock: some View {
        Button { showActivityCost = true } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text("How you wake after each sport")
                        .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                    Spacer(minLength: 8)
                    if activityCosts.isEmpty {
                        Text("Gathering data").font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.inkTertiary)
                }
                if !activityCosts.isEmpty {
                    VStack(spacing: 10) {
                        ForEach(Array(activityCosts.prefix(3).enumerated()), id: \.offset) { _, c in
                            activityCostRow(c)
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous)
                .strokeBorder(theme.hairline, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(MetricRowButtonStyle(pressedFill: theme.ink.opacity(0.05)))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the per-sport detail.")
    }

    /// One summary row inside the block: sport name (ink) · its direction/points. Colour on the datum:
    /// the gap is `dataStrain` when there's a real link, quiet ink when it's under the engine's noise
    /// floor (then it reads «no clear link»). Localized; "pts" stays plural (a reported gap is ≥ 3).
    private func activityCostRow(_ c: ActivityCost) -> some View {
        let meaningful = abs(c.delta) >= ActivityCostEngine.barelyMovesPoints
        let pts = Int(abs(c.delta).rounded())
        let summary: LocalizedStringKey = !meaningful ? "no clear link"
            : (c.delta >= 0 ? "\(pts) pts lower" : "\(pts) pts higher")
        return HStack(spacing: 8) {
            Text(verbatim: c.sport).font(StrandFont.body).foregroundStyle(theme.ink)
            Spacer(minLength: 8)
            Text(summary)
                .font(StrandFont.subhead)
                .foregroundStyle(meaningful ? theme.dataStrain : theme.inkTertiary)
                .multilineTextAlignment(.trailing)
        }
    }

    /// The light Activity-recovery detail (FER-139), theme passed explicitly (it doesn't cross the
    /// `.sheet` boundary). The Apple-connect line appears only when nothing's connected and there are no
    /// sessions to draw from.
    private var activityRecoverySheet: some View {
        ActivityRecoverySheet(
            costs: activityCosts,
            theme: theme,
            appleConnectHint: health.auth != .authorized && health.auth != .unavailable && workoutCount == 0
        )
    }

    // MARK: - Detail sheets

    /// The light metric sheet (the same one Today opens), with the live theme passed explicitly (it
    /// does NOT propagate through `.sheet`'s fresh environment) and the matching trend / curve loaders.
    private func metricSheet(for info: MetricInfo) -> some View {
        let appleCapable = ["sleep", "hrv", "rhr", "spo2", "steps"].contains(info.id)
        let notConnected = health.auth != .authorized && health.auth != .unavailable
        return MetricInfoSheet(
            info: info,
            theme: theme,
            appleConnectHint: appleCapable && notConnected && info.displayValue == "—",
            strainCurveLoader: info.id == "strain" ? { await loadStrainCurve() } : nil,
            heartRateCurveLoader: info.id == "heart_rate" ? { hrPoints } : nil,
            trendLoader: trendLoader(for: info.id)
        )
    }

    /// A dark, existing screen presented self-contained: its own NavigationStack + Done button, pinned
    /// to `.dark` (a light tab can't host a dark screen without breaking the status bar), with the
    /// environment objects re-injected (a sheet starts a fresh environment branch).
    private func darkSheetContent(_ sheet: CuerpoSheet) -> some View {
        NavigationStack {
            Group {
                switch sheet {
                case .screen(.dataSources): DataSourcesView()
                }
            }
            .background(StrandPalette.surfaceBase.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(StrandPalette.surfaceBase, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { darkSheet = nil }.foregroundStyle(StrandPalette.accent)
                }
            }
        }
        .environmentObject(repo)
        .environmentObject(live)
        .environmentObject(model)
        .environmentObject(health)
        .preferredColorScheme(.dark)
    }

    // MARK: - Loading (memoize once per refresh)

    private func loadAll() async {
        recoveryCalibration = RecoveryScorer.calibrationNights(
            nightlyHrv: repo.days.map(\.avgHrv),
            hasRecovery: repo.today?.recovery != nil)

        // Sparklines from the merged display dashboard (in memory) so they resolve for both import and
        // BLE users — `series()` is import-only for computed metrics (FER-149).
        let w = trailingDisplay(14)
        sparks["recovery"]        = w.compactMap(\.recovery)
        sparks["sleep_total_min"] = w.compactMap(\.totalSleepMin)
        sparks["strain"]          = w.compactMap(\.strain)
        sparks["hrv"]             = w.compactMap(\.avgHrv)
        sparks["rhr"]             = w.compactMap { $0.restingHr.map(Double.init) }
        sparks["spo2"]            = w.compactMap(\.spo2Pct)
        sparks["resp_rate"]       = w.compactMap(\.respRateBpm)
        sparks["skin_temp"]       = w.compactMap(\.skinTempDevC)

        // Steps live in the apple-health series, not the daily dashboard; today's HR is bucketed.
        async let steps      = sparkValues("steps", source: "apple-health", window: 14)
        async let adRows     = repo.appleDailyRows()
        async let amRows     = repo.appleDailyMetricRows()
        async let wkRows     = repo.workoutRows()
        // Stored daily "stress" series (0–3) — the model prefers it, else derives from RHR/HRV.
        async let stressRows = repo.series(key: "stress", source: "my-whoop")
        let startOfToday = Int(Calendar.current.startOfDay(for: Date()).timeIntervalSince1970)
        let nowTs = Int(Date().timeIntervalSince1970)
        async let hrRows = repo.hrBuckets(from: startOfToday, to: nowTs, bucketSeconds: 300)

        sparks["steps"] = await steps
        appleDays = await adRows
        appleMetricDays = (await amRows).sorted { $0.day < $1.day }
        let workouts = await wkRows
        workoutCount = workouts.count
        // Sessions in the trailing 14 calendar days for the «Entrenamientos» row (FER-259) — start-of-day
        // 13 days ago through now, matching the app's standard trailing-14 window.
        let recentCutoff = Calendar.current.startOfDay(
            for: Calendar.current.date(byAdding: .day, value: -13, to: Date()) ?? Date())
        let recentCutoffTs = Int(recentCutoff.timeIntervalSince1970)
        recentWorkoutCount = workouts.filter { $0.startTs >= recentCutoffTs }.count
        activityCosts = repo.activityCosts(from: workouts)   // reuses the rows above — no second query
        hrPoints = await hrRows.map {
            TrendPoint(date: Date(timeIntervalSince1970: TimeInterval($0.ts)), value: $0.bpm)
        }
        // displayDays = Apple-health fallback (FER-149); local todayKey ignores a UTC "tomorrow" row (FER-226).
        let stress = StressModel(days: repo.displayDays, stored: await stressRows, todayKey: Repository.localDayKey(Date()))
        stressModel = stress
        sparks["stress"] = stress.map { Array($0.fullTrend.suffix(14).map(\.value)) } ?? []

        fitnessAge = computeFitnessAge()

        // Longevity (FER-145 + FER-214): Body Age + Vitality from a 28-night window. Regularity uses the
        // real Sleep Regularity Index when there's coverage (FER-214), else the documented duration proxy;
        // VO₂max needs a waist the profile doesn't collect, so the cardio signal flows through resting HR.
        let recent = trailingDisplay(28)
        let vInputs = VitalityInputsBuilder.build(.init(
            chronoAge: Double(model.profile.age),
            nightlyRestingHR: recent.compactMap { $0.restingHr.map(Double.init) },
            nightlyRMSSD: recent.compactMap { $0.avgHrv },
            nightlySleepHours: recent.compactMap { $0.totalSleepMin.map { $0 / 60 } },
            dailySteps: recent.compactMap { $0.steps.map(Double.init) },
            sleepRegularity: computeSleepRegularity()))
        vitalityInputs = vInputs
        vitalityResult = VitalityEngine.compute(vInputs)
    }

    /// The real Sleep Regularity Index (FER-214) over a trailing window of persisted sleep sessions, as a
    /// 0–1 input for the engine (SRI/100). The session→timeline mapping is the pure
    /// `SleepRegularityIndex.fromSessions`; the view only supplies the window. nil → the builder's proxy.
    private func computeSleepRegularity() -> Double? {
        let cutoff = Int(Date().timeIntervalSince1970) - 35 * 86_400
        return SleepRegularityIndex.fromSessions(repo.sleeps.filter { $0.startTs >= cutoff }).map { $0 / 100 }
    }

    // MARK: - Trend / curve loaders for the light sheet (mirror Today)

    /// Trailing 14-day trend from `repo.displayDays` — the same layered source the rows draw from.
    private func loadTrend(pick: @escaping (DailyMetric) -> Double?, window: Int = 14) async -> [TrendPoint] {
        let cutoff = Repository.localDayKey(Calendar.current.date(byAdding: .day, value: -(window - 1), to: Date()) ?? Date())
        return repo.displayDays.compactMap { row -> TrendPoint? in
            guard row.day >= cutoff, let value = pick(row),
                  let date = Repository.parseDayKey(row.day) else { return nil }
            return TrendPoint(date: date.addingTimeInterval(12 * 3600), value: value)
        }
    }

    /// The FULL daily series (oldest → newest) for a vital, from `repo.displayDays` — the unified
    /// Detalle de Métrica (FER-185) carries its own range selector, so it needs all history. Same
    /// layered source the rows draw from (resolves for both import and BLE users; FER-149).
    private func vitalSeries(for key: String) -> [(day: String, value: Double)] {
        // VO₂max isn't a nightly dashboard metric — it lives in the Apple daily rows, measured sparsely
        // (FER-257). Every reading is a real measurement, so no freshness gate / no displayDays merge.
        if key == "vo2max" {
            return appleDays
                .compactMap { row in row.vo2max.map { (row.day, $0) } }
                .sorted { $0.day < $1.day }
        }
        let pick: (DailyMetric) -> Double?
        switch key {
        case "hrv":       pick = { $0.avgHrv }
        case "rhr":       pick = { $0.restingHr.map(Double.init) }
        case "resp_rate": pick = { $0.respRateBpm }
        case "spo2":      pick = { $0.spo2Pct }
        case "skin_temp": pick = { $0.skinTempDevC }
        case "steps":     pick = { $0.steps.map(Double.init) }
        default:          return []
        }
        return repo.displayDays
            .compactMap { row in pick(row).map { (row.day, $0) } }
            .sorted { $0.day < $1.day }
    }

    /// The gated, directional "Qué la mueve" findings (FER-209) for a vital, computed from the user's
    /// own history (`repo.displayDays`). Empty → the detail screen hides the block.
    private func whatMovesItFindings(for key: String) -> [WhatMovesItFinding] {
        WhatMovesItEngine.findings(forMetricKey: key, days: repo.displayDays)
    }

    /// Last night's companion vitals (respiration + resting HR) for the detail's "Vitales de la noche"
    /// block. Reuses `resolveMeasured` (today wins, else most recent within today/yesterday).
    private func loadNightVitals() async -> MetricDetailScreen.NightVitals {
        MetricDetailScreen.NightVitals(
            respiration: resolveMeasured { $0.respRateBpm }?.value,
            restingHR: resolveMeasured { $0.restingHr.map(Double.init) }?.value)
    }

    /// The 14-day trend loader the `MetricInfoSheet` runs lazily. Strain returns nil (it has its own
    /// intraday "How today added up" curve); resp/skin_temp aren't routed here (they open the catalog).
    private func trendLoader(for id: String) -> (() async -> [TrendPoint])? {
        let pick: (DailyMetric) -> Double?
        switch id {
        case "recovery": pick = { $0.recovery }
        case "sleep":    pick = { $0.totalSleepMin }
        case "hrv":      pick = { $0.avgHrv }
        case "rhr":      pick = { $0.restingHr.map(Double.init) }
        case "spo2":     pick = { $0.spo2Pct }
        case "steps":    pick = { $0.steps.map(Double.init) }
        default:         return nil
        }
        return { await self.loadTrend(pick: pick) }
    }

    /// Today's accumulated-strain curve for the Day Strain sheet — same parameters as the daily score
    /// so the curve's last point lands on the header value. [] when there's no score / too little data.
    private func loadStrainCurve() async -> [TrendPoint] {
        guard repo.today?.strain != nil else { return [] }
        let startOfToday = Int(Calendar.current.startOfDay(for: Date()).timeIntervalSince1970)
        let nowTs = Int(Date().timeIntervalSince1970)
        let samples = await repo.hrSamples(from: startOfToday, to: nowTs, limit: 100_000)
        let restHR = repo.today?.restingHr.map(Double.init) ?? StrainScorer.defaultRestingHR
        let curve = StrainScorer.cumulativeStrain(
            samples, maxHR: Double(model.profile.hrMax), restingHR: restHR, sex: model.profile.sex
        ).map { TrendPoint(date: $0.date, value: $0.strain) }
        guard !curve.isEmpty else { return [] }
        let midnight = TrendPoint(date: Date(timeIntervalSince1970: TimeInterval(startOfToday)), value: 0)
        return [midnight] + curve
    }

    // MARK: - Value resolution + helpers (mirror Today)

    /// Trailing-N-day window of the display dashboard (most recent calendar days ending today).
    private func trailingDisplay(_ days: Int) -> [DailyMetric] {
        let cutoff = Repository.localDayKey(Calendar.current.date(byAdding: .day, value: -(days - 1), to: Date()) ?? Date())
        return repo.displayDays.filter { $0.day >= cutoff }
    }

    /// Resolve a measured signal: today's row wins; else the most recent value within today/yesterday
    /// (so a fresh sync/import still reads, but never older). `fromApple` badges Apple-sourced values.
    private func resolveMeasured(_ pick: (DailyMetric) -> Double?) -> (value: Double, fromApple: Bool)? {
        let todayKey = Repository.localDayKey(Date())
        if let d = repo.today, let v = pick(d) { return (v, repo.appleHealthDays.contains(todayKey)) }
        let cutoff = Repository.localDayKey(Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date())
        for day in repo.days.reversed() {
            guard day.day >= cutoff else { break }
            if let v = pick(day) { return (v, repo.appleHealthDays.contains(day.day)) }
        }
        for day in appleMetricDays.reversed() {
            guard day.day >= cutoff else { break }
            if let v = pick(day) { return (v, true) }
        }
        return nil
    }

    /// Today's step total from the Apple daily rows, within the freshness window (today/yesterday).
    private var freshSteps: Int? {
        let cutoff = Repository.localDayKey(Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date())
        return appleDays.last(where: { $0.day >= cutoff })?.steps
    }

    /// Most recent Apple Health VO₂max (ml/kg/min) — NOT a daily metric (Apple updates it occasionally
    /// after outdoor workouts), so the latest available reading wins, no today/yesterday freshness gate.
    private var latestAppleVO2max: Double? {
        appleDays.last(where: { $0.vo2max != nil })?.vo2max
    }

    /// Today's mean HR from the 5-minute buckets (nil when there are no readings).
    private var hrTodayAvg: Int? {
        guard hrPoints.count > 1 else { return nil }
        let v = hrPoints.map(\.value)
        return Int((v.reduce(0, +) / Double(v.count)).rounded())
    }

    private func recoveryColor(_ score: Int) -> Color {
        switch RecoveryScorer.band(Double(score)) {
        case "green":  return theme.dataRecovery
        case "yellow": return theme.warning
        default:       return theme.critical
        }
    }

    /// Stress value color by band 0–3 (low → verdict, medium → warning, high → critical). Reuses
    /// `StressBand` (StressView), matching Today's stress tile semantics.
    private func stressDataColor(_ score: Double) -> Color {
        StressBand(score: score).dataColor(theme)
    }

    private func recoverySubtitle(score: Int?, calibrating: Int?) -> LocalizedStringKey {
        if let score {
            switch RecoveryScorer.band(Double(score)) {
            case "green":  return "Ready to train"
            case "yellow": return "Recovering"
            default:       return "Prioritize rest"
            }
        }
        if calibrating != nil { return "Calibrating your baseline" }
        return "No reading yet"
    }

    private func sleepText(_ mins: Double) -> String { "\(Int(mins) / 60)h \(Int(mins) % 60)m" }

    private func intString(_ v: Double) -> String { StrandFormat.groupedInt(v) }

    private static func descriptor(_ key: String) -> MetricDescriptor? {
        MetricCatalog.all.first { $0.key == key }
    }

    /// Trailing-window series values from the metric-series table (apple-health metrics like steps).
    private func sparkValues(_ key: String, source: String, window: Int) async -> [Double] {
        let all = await repo.series(key: key, source: source, days: window + 2)
        guard !all.isEmpty else { return [] }
        let cutoff = Repository.localDayKey(Calendar.current.date(byAdding: .day, value: -(window - 1), to: Date()) ?? Date())
        return all.filter { $0.day >= cutoff }.map { $0.value }
    }

}

// MARK: - Preview

#if DEBUG
#Preview("Cuerpo") {
    let repo = Repository(deviceId: "preview")
    let cal = Calendar(identifier: .gregorian)
    let today = cal.startOfDay(for: Date())
    var sample: [DailyMetric] = []
    for i in stride(from: 27, through: 0, by: -1) {
        let date = cal.date(byAdding: .day, value: -i, to: today)!
        let day = Repository.dayString(date)
        let phase = Double(i)
        sample.append(DailyMetric(
            day: day, totalSleepMin: 420 + 60 * sin(phase / 5), efficiency: 88,
            deepMin: 95, remMin: 110, lightMin: 200, disturbances: 4,
            restingHr: 52 + (i % 5), avgHrv: 46 + 12 * sin(phase / 4),
            recovery: min(max(60 + 30 * sin(phase / 6), 10), 99), strain: 9 + 5 * abs(sin(phase / 4)),
            exerciseCount: i % 2, spo2Pct: 96 + sin(phase / 3),
            skinTempDevC: 0.2 * sin(phase / 5), respRateBpm: 14 + sin(phase / 4)
        ))
    }
    repo.setDashboard(days: sample)

    return CuerpoView()
        .environmentObject(repo)
        .environmentObject(LiveState())
        .environmentObject(AppModel())
        .environmentObject(HealthKitBridge(repo: repo, appleDeviceId: "preview-apple", noopDeviceId: "preview"))
        .frame(width: 390, height: 900)
}
#endif
#endif
