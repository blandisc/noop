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
//   (d) DATA SOURCES — a compact "Sources" NoopCard: one row per source (tinted glyph +
//               name + count) over a hairline-divided sync-status footer.
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
    /// El tema activo de «Instrumento diurno» (FER-135). El `iosBody` lo inyecta por hora con
    /// `instrumentoThemeByHour(solar:)`; cada sub-vista lo lee de aquí para colorear en TINTA del tema.
    @Environment(\.instrumentoTheme) private var theme
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
    // Apple-Health daily metric rows (sleep/HRV/RHR/SpO₂) read straight from the apple-health source,
    // so Key Metrics can fall back to them when a strap row clobbered Apple's row for the day in the
    // dashboard merge (e.g. a WHOOP 4.0 that didn't decode HRV/sleep). (FER-98)
    @State private var appleMetricDays: [DailyMetric] = []

    // Today's heart rate as 5-minute bucket means (midnight → now), for the 24h trend chart.
    @State private var hrPoints: [TrendPoint] = []

    // Support sheet (donate + contact) — always reachable from the home toolbar.
    @State private var showingSupport = false

    // Metric-info sheet — tapping any Key Metrics row presents this.
    @State private var metricDetail: MetricInfo? = nil
    @State private var showWhyVerdict = false

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

    /// Nights of usable HRV across the WHOLE merged baseline (Apple Health + strap), 0… Reuses the
    /// same in-range HRV predicate as `ownNights` via a high seed, but over `repo.days` (not just
    /// strap rows), so a full Apple-Health import counts here even though it never counts in `ownNights`.
    private var seededNights: Int {
        RecoveryScorer.calibrationNights(nightlyHrv: repo.days.map(\.avgHrv), hasRecovery: false, seed: .max) ?? 0
    }

    /// True when the recovery baseline is already seeded (≥ `minNightsSeed` valid HRV nights) but the
    /// user's OWN strap nights are still below the seed — i.e. the base came from imported Apple Health
    /// history, not the strap. Drives the "your baseline is ready, the strap just adds today" onboarding
    /// narrative so the pre-verdict states never read "0 of 4" as if no base existed (FER-106). Pure
    /// read of existing signals — no engine math. Naturally false without an import (no permission, no
    /// history → `seededNights < minNightsSeed`), so no state can promise an Apple-Health base it lacks.
    private var hasImportedBaseline: Bool {
        seededNights >= Baselines.minNightsSeed && ownNights < Baselines.minNightsSeed
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
                    .help("Support Cénit — donate or get in touch")
                    .accessibilityLabel("Support Cénit — donate or get in touch")
                }
            }
            .overlay {
                if showingSupport {
                    SupportModalOverlay(isPresented: $showingSupport)
                }
            }
            .animation(.easeOut(duration: 0.18), value: showingSupport)
            .sheet(item: $metricDetail) { info in
                metricSheet(for: info)
            }
            .sheet(isPresented: $showWhyVerdict) {
                WhyVerdictSheet(readiness: readiness, theme: theme)
            }
    }

    private var platformBody: some View {
        iosBody
    }

    /// Builds the metric detail sheet, passing the live «Instrumento» theme (it does NOT propagate
    /// through `.sheet`'s fresh environment) and deciding the "connect Apple Salud" hint: shown only
    /// for Apple-sourceable metrics that aren't connected and have no value yet — strap-only metrics
    /// (strain, heart rate) never get it. The connect action itself stays in Today. (FER-162)
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

    // MARK: - Today (instrumento diurno · veredicto dominante · dial 24h · métricas en tinta)
    //
    // Escrito en el lenguaje «Instrumento diurno» (FER-135): tema claro por hora del día
    // (`instrumentoThemeByHour`), un solo número dominante (la recuperación), jerarquía por ESPACIO
    // (sin card-in-card), y COLOR SOLO en el dato — el número de recuperación, la palabra del veredicto
    // y la línea+punto de cada gráfica; todo lo demás (labels, valores, dial, iconos, chevrons,
    // overlines) en TINTA del tema. Conserva toda la lógica de estados/datos previa; solo reacomoda y
    // recolorea.
    //
    // El tema se aplica UNA vez envolviendo el iosBody (acotado a TodayView, NUNCA en RootTabView): el
    // `SolarWindow` lo computa `SolarClock` para la fecha/zona actuales, de modo que el papel «amanece»
    // y «anochece» con el sol real. Cada sub-vista lee `@Environment(\.instrumentoTheme)`.

    private var iosBody: some View {
        ScrollView {
            // Ritmo de sección estándar (`sectionGap` = 28): con la escala grande de «Instrumento
            // diurno» las secciones respiran y llenan la columna sin que se lean fundidas ni apretadas.
            VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                headerBlock
                HealthAlertBanner()
                // Héroe unificado (FER-160): UN solo instrumento de estado adaptable cubre los cuatro
                // modos (veredicto / base sembrada por Apple Health / calibrando / espera). El árbol de
                // antes —4 sub-vistas con distinto layout (`emptyHero`/`importedBaselineHero`/
                // `CalibrationProgressCard`/`verdictSection`)— colapsó en un mismo esqueleto: overline +
                // numeral dominante + dial + cuerpo + pie. Lo único que cambia entre modos es QUÉ valor
                // lleva el numeral, su color (regla «color = listo / tinta = en espera») y el pie. Ver
                // `heroInstrument` + `heroState`.
                heroInstrument
                // Sube «Métricas clave» pegándola más al pie del héroe («Verlo latido a latido»): recorta
                // el `sectionGap` (28) de esta sección a ~12 con un inset negativo, sin tocar los gaps del
                // héroe ni de Fuentes.
                iosMetricsSection
                    .padding(.top, -16)
                iosSourcesSection
            }
            // Inset superior 20: el héroe queda alto pero respira; márgenes horizontal/inferior estándar.
            .padding(.horizontal, NoopMetrics.screenPadding)
            .padding(.bottom, NoopMetrics.screenPadding)
            .padding(.top, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // El fondo es el papel del tema (`PaperBackground` lee `\.instrumentoTheme` DENTRO del subárbol
        // tematizado, así que el lienzo también se recolorea por hora). El tema por hora se inyecta aquí,
        // acotado a TodayView (NUNCA en RootTabView): todo el árbol de abajo lee `\.instrumentoTheme` y
        // se recolorea según la hora del día gratis.
        .background(PaperBackground())
        .instrumentoThemeByHour(solar: solarWindow)
        // El color scheme (y con él la barra de estado: Hoy = papel claro → tinta oscura) se decide
        // en ContentView según la pestaña activa, porque `preferredColorScheme` lo resuelve el
        // controlador raíz del WindowGroup y un valor puesto AQUÍ (dentro del TabView) no llega.
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

    /// Recovery score driving the hero numeral (0–100). nil while calibrating.
    private var recoveryScore: Int? { repo.today?.recovery.map { Int($0.rounded()) } }

    /// El lienzo: el papel del tema, leído DENTRO del subárbol tematizado para que también recolore por
    /// hora. (El `.background(theme.paper)` del propio `iosBody` resolvería contra el tema base, no el de
    /// la hora — por eso esta vista hija lo lee del entorno.)
    private struct PaperBackground: View {
        @Environment(\.instrumentoTheme) private var theme
        var body: some View { theme.paper.ignoresSafeArea() }
    }

    /// Ventana solar (amanecer/atardecer) para HOY, en horas reloj, derivada de `SolarClock` para la
    /// zona horaria actual SIN GPS ni permisos. Mapeada al `SolarWindow` de StrandDesign que consumen
    /// el motor de tema por hora y el `DiurnalDial`. `nil` en los casos polares (sin cruce de horizonte).
    private var solarWindow: SolarWindow? {
        guard let w = SolarClock.sunWindow(on: Date(), in: .current) else { return nil }
        return SolarWindow(sunrise: w.sunrise, sunset: w.sunset)
    }

    /// Ventana de sueño de la noche más reciente, en horas reloj, desde el registro on-device que ya
    /// tenemos (`repo.sleeps`) — sin permiso nuevo. `SleepWindowClock` hace la selección, el gate de
    /// frescura y la conversión epoch→reloj; aquí solo se mapea a `SleepWindow` para el `DiurnalDial`.
    private var sleepWindow: SleepWindow? {
        guard let s = SleepWindowClock.recent(repo.sleeps, now: Date()) else { return nil }
        return SleepWindow(bedtime: s.bedtime, wake: s.wake)
    }

    /// El color del DATO de recuperación por banda, en roles del tema (regla dura: color saturado solo
    /// en el número de recuperación). Verde → `dataRecovery`, amarillo → `warning`, rojo → `critical`,
    /// reusando el umbral de banda WHOOP que ya usa el resto de la app (`RecoveryScorer.band`: rojo <34,
    /// amarillo 34–67, verde ≥67).
    private func recoveryDataColor(_ score: Int) -> Color {
        switch RecoveryScorer.band(Double(score)) {
        case "green":  return theme.dataRecovery
        case "yellow": return theme.warning
        default:       return theme.critical   // "red"
        }
    }

    /// El color del DATO del veredicto por nivel, en roles del tema (color saturado solo en la palabra
    /// del veredicto). primed/balanced → `verdict`, strained → `warning`, rundown → `critical`.
    private func verdictDataColor(_ level: ReadinessEngine.Level) -> Color {
        switch level {
        case .primed, .balanced: return theme.verdict
        case .strained:          return theme.warning
        case .rundown:           return theme.critical
        case .insufficient:      return theme.inkTertiary
        }
    }

    /// Date + honesty line — the screen's calm header (overline date + quiet sync provenance).
    private var headerBlock: some View {
        utilityRow
    }

    // MARK: - Héroe unificado «Instrumento diurno» (FER-160)
    //
    // Un SOLO esqueleto para los cuatro modos del héroe. Antes había cuatro sub-vistas con layouts
    // distintos; aquí comparten una sola estructura —overline + numeral dominante + dial + cuerpo +
    // pie— y solo cambian el numeral, su color y el pie. La regla «color = listo / tinta = en espera»
    // hace de semáforo de estado: numeral con color de banda = la lectura de hoy está lista; numeral en
    // tinta o em-dash «—» = en espera o sin contexto. Mata el último layout pre-veredicto separado.

    /// Los cuatro modos del héroe, derivados de las MISMAS señales de solo-lectura de antes (sin tocar
    /// el motor). El orden de prioridad replica el árbol previo del `iosBody`.
    private enum HeroState: Equatable {
        case verdict                    // repo.today?.recovery != nil → hay número
        case importedBaseline           // pre-veredicto: base sembrada por Apple Health (FER-106)
        case calibrating(nights: Int)   // pre-veredicto: strap visto, ownNights < seed
        case waiting                    // pre-veredicto: sin strap nunca, o base propia sin lectura de hoy
    }

    private var heroState: HeroState {
        if repo.today?.recovery != nil { return .verdict }
        if hasImportedBaseline { return .importedBaseline }
        let strapSeen = live.lastSyncedAt != nil || liveBpm != nil
        if strapSeen && ownNights < Baselines.minNightsSeed { return .calibrating(nights: ownNights) }
        return .waiting
    }

    /// Whether a strap has ever been seen (drives the foot affordance: Scan before, live pulse after).
    private var strapSeen: Bool { live.lastSyncedAt != nil || liveBpm != nil }

    /// El instrumento: un esqueleto, cuatro modos. Jerarquía por espacio (sin card-in-card); color solo
    /// en el dato (numeral de banda / palabra del veredicto). El dial del momento preside SIEMPRE a la
    /// derecha — incluso en espera — para que la pantalla nunca se vea a medio construir.
    @ViewBuilder private var heroInstrument: some View {
        let state = heroState
        VStack(alignment: .leading, spacing: 12) {
            Text(heroOverline(state)).instrumentoOverline().foregroundStyle(theme.inkTertiary)
            HStack(alignment: .center, spacing: 18) {
                heroNumeral(state)
                Spacer(minLength: 8)
                // `sleepWindow` ya es nil cuando anoche no hubo registro de strap, así que el dial omite
                // la banda de sueño solo (no hay que decidirlo aquí): contexto honesto en cada modo.
                // Escala sistémica «L» (FER-164): dial 104.
                DiurnalDial(now: Date(), solar: solarWindow, sleep: sleepWindow, diameter: 104)
            }
            heroBody(state)
            heroFooter(state)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func heroOverline(_ s: HeroState) -> LocalizedStringKey {
        switch s {
        case .calibrating: return "Tu base se afina"
        default:           return "El veredicto de hoy"
        }
    }

    /// El numeral dominante — lo único que “grita” el estado. Veredicto → recuperación en color de banda
    /// (o en TINTA si el nivel es `insufficient`: hay número, no hay contexto). Calibrando → «N/4» en
    /// tinta (progreso, no dato). Espera/base Apple → em-dash «—» en tinta. Escala sistémica «L»
    /// (FER-164): numeral 88.
    @ViewBuilder private func heroNumeral(_ s: HeroState) -> some View {
        switch s {
        case .verdict:
            let score = recoveryScore
            let insufficient = readiness.level == .insufficient
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                if let score {
                    Text("\(score)").instrumentoHero(88)
                        .foregroundStyle(insufficient ? theme.ink : recoveryDataColor(score))
                    Text("/100").font(StrandFont.subhead).foregroundStyle(theme.inkTertiary)
                } else {
                    Text("—").instrumentoHero(88).foregroundStyle(theme.inkTertiary)
                }
            }
            // El número abre el detalle de recuperación (cómo se calcula, serie, fuente).
            .contentShape(Rectangle())
            .onTapGesture {
                metricDetail = .recovery(score: recoveryScore,
                                         calibrationNights: recoveryCalibration,
                                         nightsNeeded: Baselines.minNightsSeed)
            }
        case .calibrating(let nights):
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(nights)").instrumentoHero(88).foregroundStyle(theme.ink)
                Text("/\(Baselines.minNightsSeed)").font(InstrumentoType.hero(40))
                    .foregroundStyle(theme.inkTertiary)
            }
        case .importedBaseline, .waiting:
            Text("—").instrumentoHero(88).foregroundStyle(theme.inkTertiary)
        }
    }

    /// El cuerpo bajo el numeral: la palabra del veredicto + «i» + modificadores (veredicto), o la línea
    /// honesta de qué falta (resto de modos).
    @ViewBuilder private func heroBody(_ s: HeroState) -> some View {
        switch s {
        case .verdict:
            verdictBody
        case .importedBaseline:
            VStack(alignment: .leading, spacing: 9) {
                appleBaseChip
                Text("Falta la lectura de hoy")
                    .font(StrandFont.headline).foregroundStyle(theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Usa tu banda para sumar lo único que Apple Salud no puede: la lectura de hoy.")
                    .font(StrandFont.body).foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .calibrating(let nights):
            VStack(alignment: .leading, spacing: 10) {
                calibrationDots(nights: nights)
                Text(calibrationDetailCopy(nights: nights))
                    .font(StrandFont.body).foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .waiting:
            VStack(alignment: .leading, spacing: 6) {
                Text(strapSeen ? "Aún no hay lectura de hoy" : "Aún no hay lectura")
                    .font(StrandFont.headline).foregroundStyle(theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(strapSeen
                     ? "Tu base está lista. Usa el strap esta noche y la recuperación, el esfuerzo y el sueño de la mañana aparecen al sincronizar."
                     : "Conecta tu strap WHOOP para ver la disposición, la recuperación y la frecuencia cardiaca de la mañana.")
                    .font(StrandFont.body).foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// El cuerpo del veredicto: la palabra en su color de nivel + la «i» (toda la fila tocable) que abre
    /// el porqué, la frase puente, la salvedad de noche corta y la barra «afinando · N de 14». Cuando el
    /// nivel es `insufficient` hay número pero no palabra: el numeral va en tinta (arriba) y aquí la razón.
    @ViewBuilder private var verdictBody: some View {
        let r = readiness
        if r.level != .insufficient {
            Button { showWhyVerdict = true } label: {
                HStack(spacing: 6) {
                    Text(r.headline).font(StrandFont.title2).fontWeight(.semibold)
                        .foregroundStyle(verdictDataColor(r.level))
                        .fixedSize(horizontal: false, vertical: true)
                    Image(systemName: "info.circle").font(.system(size: 15))
                        .foregroundStyle(theme.inkTertiary)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("Abre por qué el veredicto se lee así"))
            if let bridge = r.bridge {
                Text(bridge).font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if r.confidenceLow, let note = r.confidenceNote {
                HStack(spacing: 7) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 10))
                    Text(note).font(StrandFont.caption)
                }
                .foregroundStyle(theme.warning)
            }
            if (1..<Baselines.minNightsTrust).contains(ownNights) {
                calibrationConfidence
            }
        } else {
            // Hay número pero sin contexto para una palabra (ex-anillo / estado 6). El numeral ya va en
            // tinta; aquí, la razón honesta — nunca un veredicto pintado de color sin respaldo. (FER-160)
            Text("Aún sin contexto suficiente para un veredicto del día.")
                .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// El pie adaptable: pulso vivo (veredicto y modos con strap), atajo Apple Health + pulso (calibrando),
    /// o el CTA «Buscar strap» cuando nunca se ha visto uno.
    @ViewBuilder private func heroFooter(_ s: HeroState) -> some View {
        switch s {
        case .verdict:
            LiveHeartbeatRow(liveBpm: liveBpm, isLiveHR: isLiveHR, onTap: { showLiveMonitor = true })
        case .calibrating:
            appleHealthShortcut { showDataSources = true }
            LiveHeartbeatRow(liveBpm: liveBpm, isLiveHR: isLiveHR, onTap: { showLiveMonitor = true })
        case .importedBaseline, .waiting:
            if strapSeen {
                LiveHeartbeatRow(liveBpm: liveBpm, isLiveHR: isLiveHR, onTap: { showLiveMonitor = true })
            } else {
                scanButton
            }
        }
    }

    /// El único CTA del estado de espera sin strap: texto en el papel sobre el verde del veredicto.
    private var scanButton: some View {
        Button { model.scan() } label: {
            Text("Buscar strap")
                .font(StrandFont.headline)
                .foregroundStyle(theme.paper)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(theme.verdict, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.top, 2)
    }

    /// Chip de procedencia — la base viene de Apple Health, dicho de frente. Tono de dato (azul de Apple
    /// Salud), AA sobre papel.
    private var appleBaseChip: some View {
        HStack(spacing: 6) {
            Image(systemName: "heart.fill").font(.system(size: 12))
            Text("Base · Apple Salud").font(StrandFont.subhead)
        }
        .foregroundStyle(theme.dataSpO2)
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(theme.dataSpO2.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    /// Night-dots de calibración: llenos en el dato (`dataRecovery`), vacíos en `hairline`.
    private func calibrationDots(nights: Int) -> some View {
        let total = Baselines.minNightsSeed
        return HStack(spacing: 8) {
            ForEach(0..<total, id: \.self) { i in
                Circle()
                    .fill(i < nights ? theme.dataRecovery : theme.hairline)
                    .frame(width: 10, height: 10)
            }
            Text("\(nights) de \(total) noches")
                .font(StrandFont.captionNumber)
                .foregroundStyle(theme.inkSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(nights) de \(total) noches calibradas"))
    }

    /// Copy de calibración por momento: noche cero, media calibración, y «todas las noches, computando».
    /// Enmarca el conteo como las noches que tu PROPIA base necesita, nunca «tu veredicto».
    private func calibrationDetailCopy(nights: Int) -> LocalizedStringKey {
        let total = Baselines.minNightsSeed
        if nights == 0 { return "Usa el strap esta noche — la primera de \(total) noches que tu propia base necesita." }
        if nights >= total { return "Las \(total) noches están — computando tu primer veredicto." }
        return "Tu propia base afina cada noche — ya llevas \(nights)."
    }

    /// Atajo de adelanto por Apple Health (solo en calibración): un usuario con historial puede sembrar la
    /// base ahora en vez de esperar las 0→seed noches. Renglón full-width con hairline (mismo chrome que
    /// LiveHeartbeatRow) que abre Fuentes de datos.
    private func appleHealthShortcut(onTap: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            Rectangle().fill(theme.hairline).frame(height: 0.5)
                .padding(.top, 14).padding(.bottom, 10)
            Button(action: onTap) {
                HStack(spacing: 9) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 12)).foregroundStyle(theme.dataSpO2)
                    Text("¿Tienes historial en Apple Salud? Conéctalo y tu base arranca con ventaja.")
                        .font(StrandFont.caption)
                        .foregroundStyle(theme.inkSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 6)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11)).foregroundStyle(theme.inkTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(Text("Conectar Apple Salud"))
            .accessibilityHint(Text("Abre Fuentes de datos para adelantar tu base"))
        }
    }

    /// El renglón de pulso vivo: el glifo de onda + «Verlo latido a latido», la pastilla de bpm vivo (o
    /// una insignia callada «Sin lectura»), y un chevron — un Button que abre el monitor latido a latido.
    /// Anclado al pie de cada héroe con strap (calibración, veredicto, vacío-con-strap). Recoloreado a
    /// TINTA del tema: solo el punto de pulso vivo lleva color (`dataHeart`), el resto es tinta.
    private struct LiveHeartbeatRow: View {
        var liveBpm: Int?
        var isLiveHR: Bool
        let onTap: () -> Void
        @Environment(\.instrumentoTheme) private var theme

        var body: some View {
            VStack(spacing: 0) {
                Rectangle().fill(theme.hairlineStrong).frame(height: 1)
                    .padding(.top, 3).padding(.bottom, 6)
                Button(action: onTap) {
                    HStack(spacing: 9) {
                        Image(systemName: "waveform.path.ecg")
                            .font(StrandFont.headline).foregroundStyle(theme.inkSecondary)
                        Text("Verlo latido a latido")
                            .font(StrandFont.body).fontWeight(.medium)
                            .foregroundStyle(theme.ink)
                        Spacer(minLength: 0)
                        badge
                        Image(systemName: "chevron.right")
                            .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                    }
                    // Objetivo táctil compacto (34, bajo el ideal HIG de 44): es un renglón full-width
                    // (objetivo horizontal amplio) y una acción secundaria, recortado para matar el
                    // espacio muerto. Reversible a 44 si la accesibilidad lo pide.
                    .frame(minHeight: 34)
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(Text(isLiveHR ? "Frecuencia cardiaca en vivo" : "Frecuencia cardiaca"))
                .accessibilityValue(Text(liveBpm.map { "\($0) bpm" } ?? "Sin lectura"))
                .accessibilityHint(Text("Abre el monitor latido a latido"))
            }
        }

        /// La pastilla de bpm vivo (punto en `dataHeart` cuando transmite), o una insignia callada
        /// «Sin lectura» en tinta cuando el strap no está transmitiendo.
        @ViewBuilder private var badge: some View {
            if let bpm = liveBpm {
                // `.center`: el punto se centra ópticamente con el número (antes colgaba bajo la baseline).
                HStack(alignment: .center, spacing: 6) {
                    Circle().fill(isLiveHR ? theme.dataHeart : theme.inkTertiary)
                        .frame(width: 7, height: 7)
                    Text("\(bpm)").font(StrandFont.number(15, weight: .semibold))
                        .foregroundStyle(theme.ink)
                    Text("bpm").font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                }
            } else {
                HStack(alignment: .center, spacing: 6) {
                    Circle().fill(theme.inkTertiary).frame(width: 7, height: 7)
                    Text("Sin lectura").font(StrandFont.subhead).foregroundStyle(theme.inkTertiary)
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
                .foregroundStyle(theme.inkTertiary)
            Spacer(minLength: 8)
            syncMeta
        }
    }

    /// Honesty line — "Synced 2 min ago · strap 87%" / "Last sync — never". Shows "Syncing strap
    /// history…" while a history offload runs so the user gets a quiet, non-intrusive signal without
    /// a prominent pill. Mono + tertiary in all states so it reads as quiet provenance.
    @ViewBuilder private var syncMeta: some View {
        if live.backfilling {
            Text("Sincronizando historial…")
                .font(StrandFont.mono(10))
                .foregroundStyle(theme.inkTertiary)
                .lineLimit(1)
        } else {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                Group {
                    if let at = live.lastSyncedAt {
                        let rel = relativeAgo(at, now: context.date.timeIntervalSince1970)
                        if let pct = live.batteryPct {
                            Text("Sincronizado \(rel) · strap \(Int(pct.rounded()))%")
                        } else {
                            Text("Sincronizado \(rel)")
                        }
                    } else {
                        Text("Última sincronización: nunca")
                    }
                }
                .font(StrandFont.mono(10))
                .foregroundStyle(theme.inkTertiary)
                .lineLimit(1)
            }
        }
    }

    /// Whether the personal baseline draws on imported Apple Health history — drives the
    /// "Your baseline comes from Apple Health" note on the calibration row. (FER-105)
    private var baselineFromApple: Bool { !repo.appleHealthDays.isEmpty }

    /// Quiet calibration-progress row at the foot of the verdict: the read keeps sharpening as the
    /// user's OWN strap nights ramp to the trusted baseline (`minNightsTrust`). Visually distinct
    /// from the 0–100 readiness gauge — a thin accent track with no 0/100 scale and an "N of 14
    /// nights" counter — so the two never read as the same thing twice. When Apple Health seeded the
    /// baseline, a tertiary note names the source so the early verdict never feels unexplained. (FER-105)
    private var calibrationConfidence: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "sparkles").font(.system(size: 10))
                    Text("Afinando con tu strap")
                        .font(StrandFont.caption)
                        .fixedSize(horizontal: false, vertical: true)   // wrap, never truncate, at large Dynamic Type
                }
                .foregroundStyle(theme.inkSecondary)
                Spacer(minLength: 8)
                Text("\(ownNights) de \(Baselines.minNightsTrust) noches")
                    .font(StrandFont.captionNumber)
                    .foregroundStyle(theme.inkSecondary)
                    .fixedSize()
                    .layoutPriority(1)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(theme.ink.opacity(0.10)).frame(height: 6)
                    Capsule().fill(theme.dataRecovery)
                        .frame(width: max(6, geo.size.width * CGFloat(ownNights) / CGFloat(Baselines.minNightsTrust)),
                               height: 6)
                }
            }
            .frame(height: 6)
            if baselineFromApple {
                Text("Tu base viene de Apple Salud.")
                    .font(StrandFont.caption)
                    .foregroundStyle(theme.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Confianza de calibración"))
        .accessibilityValue(Text(baselineFromApple
            ? "Afinando con tu strap, \(ownNights) de \(Baselines.minNightsTrust) noches. Tu base viene de Apple Salud."
            : "Afinando con tu strap, \(ownNights) de \(Baselines.minNightsTrust) noches."))
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
        let hrvFlag: LocalizedStringKey? = hrvR?.fromApple == true ? "Apple Salud"
            : ((hrvR != nil && readiness.confidenceLow) ? "Baja conf." : nil)
        let hrvFlagColor = hrvR?.fromApple == true ? theme.inkTertiary : theme.warning
        // Steps come only from Apple Health; guard the most-recent row to the 14-day window so a stale
        // import can't render months-old steps under a Today tile.
        let stepsCutoff = Repository.localDayKey(Calendar.current.date(byAdding: .day, value: -13, to: Date()) ?? Date())
        let stepsFresh = appleDays.last(where: { $0.day >= stepsCutoff })?.steps
        let stepsStr = stepsFresh.map { intString(Double($0)) } ?? latestString("steps", decimals: 0)
        // Nudge to connect Apple Health only when it isn't connected AND a measured row is actually empty.
        let notConnected = health.auth != .authorized && health.auth != .unavailable
        let anyMeasuredMissing = hrvR == nil || sleepR == nil || rhrR == nil || spo2R == nil || stepsFresh == nil
        // Serie 14d por métrica, calculada UNA vez: alimenta la línea Y su banda de referencia (p25–p75,
        // FER-155). La línea va en el color de la métrica; la banda en tinta (`hairlineStrong`).
        let strainSpark = sparks["strain"]
        let sleepSpark  = measuredSpark("sleep_total_min") { $0.totalSleepMin }
        let hrvSpark    = measuredSpark("hrv") { $0.avgHrv }
        let hrSpark     = hrSparkline
        let rhrSpark    = measuredSpark("rhr") { $0.restingHr.map(Double.init) }
        let spo2Spark   = measuredSpark("spo2") { $0.spo2Pct }
        let stepsSpark  = sparks["steps"]
        // Spacing interno corto (4 en vez de `NoopMetrics.gap` 12): pega la lista de métricas justo bajo
        // el encabezado «Métricas clave».
        VStack(alignment: .leading, spacing: 4) {
            // Encabezado en TINTA del tema (no el `SectionHeader` compartido: su título usa
            // `StrandPalette.textPrimary`, casi blanco, que desaparece sobre el papel claro de
            // «Instrumento diurno»). Mismo patrón overline+título+trailing, recoloreado al tema.
            HStack(alignment: .firstTextBaseline) {
                Text("Métricas clave").font(StrandFont.title1).foregroundStyle(theme.ink)
                Spacer()
                Text("Tendencia 14 días").font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
            }
            VStack(spacing: 0) {
                Button { metricDetail = .strain(d?.strain) } label: {
                    MetricRow(label: "Esfuerzo del día",
                              value: d?.strain.map { String(format: "%.1f", $0) } ?? "—",
                              valueColor: theme.ink, labelColor: theme.inkSecondary, unitColor: theme.inkTertiary,
                              sparkline: strainSpark, sparkColor: theme.dataStrain,
                              referenceBand: strainSpark.flatMap { ReferenceRange.interquartile($0) },
                              bandColor: theme.hairlineStrong,
                              isPlaceholder: d?.strain == nil)
                }.buttonStyle(.plain)
                metricSeparator
                Button { metricDetail = .sleep(sleepR.map { Int($0.value.rounded()) }) } label: {
                    MetricRow(label: "Sueño",
                              value: sleepR.map { sleepText($0.value) } ?? "—",
                              valueColor: theme.ink, labelColor: theme.inkSecondary, unitColor: theme.inkTertiary,
                              flag: sleepR?.fromApple == true ? "Apple Salud" : nil, flagColor: theme.inkTertiary,
                              sparkline: sleepSpark, sparkColor: theme.dataSleep,
                              referenceBand: sleepSpark.flatMap { ReferenceRange.interquartile($0) },
                              bandColor: theme.hairlineStrong,
                              isPlaceholder: sleepR == nil)
                }.buttonStyle(.plain)
                metricSeparator
                Button { metricDetail = .hrv(hrvR?.value) } label: {
                    MetricRow(label: "HRV",
                              value: hrvR.map { "\(Int($0.value.rounded()))" } ?? "—",
                              unit: "ms", valueColor: theme.ink, labelColor: theme.inkSecondary, unitColor: theme.inkTertiary,
                              flag: hrvFlag, flagColor: hrvFlagColor,
                              sparkline: hrvSpark, sparkColor: theme.dataHrv,
                              referenceBand: hrvSpark.flatMap { ReferenceRange.interquartile($0) },
                              bandColor: theme.hairlineStrong,
                              isPlaceholder: hrvR == nil)
                }.buttonStyle(.plain)
                metricSeparator
                // Frecuencia cardíaca — la curva continua de hoy, justo encima de "FC en reposo"
                // (RHR nocturna) para que se lean como par. Tap → sheet con la gráfica 24h. (FER-137)
                Button { metricDetail = .heartRate(avgBpm: hrTodayAvg) } label: {
                    MetricRow(label: "Frecuencia cardíaca",
                              value: hrTodayAvg.map { "\($0)" } ?? "—",
                              unit: "bpm", valueColor: theme.ink, labelColor: theme.inkSecondary, unitColor: theme.inkTertiary,
                              sparkline: hrSpark, sparkColor: theme.dataHeart,
                              referenceBand: hrSpark.flatMap { ReferenceRange.interquartile($0) },
                              bandColor: theme.hairlineStrong,
                              isPlaceholder: hrTodayAvg == nil)
                }.buttonStyle(.plain)
                metricSeparator
                Button { metricDetail = .restingHR(rhrR.map { Int($0.value.rounded()) }) } label: {
                    MetricRow(label: "FC en reposo",
                              value: rhrR.map { "\(Int($0.value.rounded()))" } ?? "—",
                              unit: "bpm", valueColor: theme.ink, labelColor: theme.inkSecondary, unitColor: theme.inkTertiary,
                              flag: rhrR?.fromApple == true ? "Apple Salud" : nil, flagColor: theme.inkTertiary,
                              sparkline: rhrSpark, sparkColor: theme.dataHeart,
                              referenceBand: rhrSpark.flatMap { ReferenceRange.interquartile($0) },
                              bandColor: theme.hairlineStrong,
                              isPlaceholder: rhrR == nil)
                }.buttonStyle(.plain)
                metricSeparator
                Button { metricDetail = .spo2(spo2R?.value) } label: {
                    MetricRow(label: "Oxígeno en sangre",
                              value: spo2R.map { String(format: "%.0f", $0.value) } ?? "—",
                              unit: "%", valueColor: theme.ink, labelColor: theme.inkSecondary, unitColor: theme.inkTertiary,
                              flag: spo2R?.fromApple == true ? "Apple Salud" : nil, flagColor: theme.inkTertiary,
                              sparkline: spo2Spark, sparkColor: theme.dataSpO2,
                              referenceBand: spo2Spark.flatMap { ReferenceRange.interquartile($0) },
                              bandColor: theme.hairlineStrong,
                              isPlaceholder: spo2R == nil)
                }.buttonStyle(.plain)
                metricSeparator
                Button { metricDetail = .steps(stepsFresh) } label: {
                    MetricRow(label: "Pasos",
                              value: stepsStr,
                              valueColor: theme.ink, labelColor: theme.inkSecondary, unitColor: theme.inkTertiary,
                              sparkline: stepsSpark, sparkColor: theme.dataSteps,
                              referenceBand: stepsSpark.flatMap { ReferenceRange.interquartile($0) },
                              bandColor: theme.hairlineStrong,
                              isPlaceholder: stepsStr == "—")
                }.buttonStyle(.plain)
            }
            if notConnected && anyMeasuredMissing {
                Button { showDataSources = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "heart.fill")
                        Text("Conectar Apple Salud")
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .foregroundStyle(theme.inkTertiary)
                    }
                    .font(StrandFont.caption)
                    .foregroundStyle(theme.inkSecondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Rule between metric rows (not above the first — the section header already caps the list).
    /// Un poco más gruesa que el hairline por defecto (1pt vs ~0.5) y en `hairlineStrong` para que la
    /// separación entre métricas se lea con más presencia sobre el papel claro.
    private var metricSeparator: some View {
        Rectangle().fill(theme.hairlineStrong).frame(height: 1)
    }

    /// Carta de Fuentes traída a Hoy (FER-164) en lenguaje «Instrumento diurno»: jerarquía REDUCIDA —
    /// un overline callado «FUENTES» (no un título como Métricas clave) — y una fila por fuente con el
    /// glifo en color del dato (verde WHOOP / azul Apple Salud), nombre en tinta y conteo tabular,
    /// divididas por la misma hairline. SIN la línea de sincronización (ya vive en el header de arriba).
    /// La `SourcesSummaryCard` compartida (macOS Today / Fuentes de datos) queda intacta. Renderiza nada
    /// hasta que haya al menos una fuente con datos.
    @ViewBuilder private var iosSourcesSection: some View {
        let whoopDays = repo.days.count - repo.appleHealthDays.count
        let ahDays    = repo.appleHealthDays.count
        let appleWk   = workouts.filter { $0.source == "apple-health" }.count
        if whoopDays > 0 || ahDays > 0 {
            VStack(alignment: .leading, spacing: NoopMetrics.gap) {
                Text("Fuentes").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                VStack(spacing: 0) {
                    if whoopDays > 0 {
                        sourceRow(symbol: "bolt.heart.fill", name: "WHOOP",
                                  detail: String(localized: "\(whoopDays) días · \(repo.sleeps.count) sueños"),
                                  tint: theme.dataRecovery)
                    }
                    if whoopDays > 0 && ahDays > 0 { metricSeparator }
                    if ahDays > 0 {
                        sourceRow(symbol: "heart.fill", name: "Apple Salud",
                                  detail: String(localized: "\(ahDays) días · \(appleWk) entrenamientos"),
                                  tint: theme.dataSpO2)
                    }
                }
            }
        }
    }

    /// Una fila de fuente: glifo tintado (la identidad de la fuente, único color de la fila) + nombre
    /// en tinta + conteo tabular a la derecha. Quieta a propósito — es un pie, no compite con las métricas.
    private func sourceRow(symbol: String, name: LocalizedStringKey, detail: String, tint: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(StrandFont.headline)
                .foregroundStyle(tint)
                .frame(width: 22)
            Text(name).font(StrandFont.body).foregroundStyle(theme.ink)
            Spacer(minLength: 8)
            Text(detail).font(StrandFont.captionNumber).foregroundStyle(theme.inkSecondary)
        }
        .padding(.vertical, 12)
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

    /// Today's mean HR (nil when there are no readings) — the value on the "Heart Rate" Key-Metrics
    /// row. The day's average summarizes the day without echoing the live bpm that lives in the hero.
    private var hrTodayAvg: Int? {
        guard hrPoints.count > 1 else { return nil }
        let v = hrPoints.map(\.value)
        return Int((v.reduce(0, +) / Double(v.count)).rounded())
    }

    /// The day's HR curve subsampled to a compact sparkline for the Key-Metrics row (≤32 points).
    private var hrSparkline: [Double]? {
        guard hrPoints.count > 1 else { return nil }
        let v = hrPoints.map(\.value)
        guard v.count > 40 else { return v }
        let step = max(1, v.count / 32)
        return stride(from: 0, to: v.count, by: step).map { v[$0] }
    }

    /// Compact localized date for the utility row, e.g. "THU 12 JUN" — context without the greeting.
    private var shortDate: String {
        let f = DateFormatter()
        f.locale = .autoupdatingCurrent
        f.setLocalizedDateFormatFromTemplate("EEEdMMM")
        // Always the real calendar day — never the last data row's day, or the header
        // looks "stuck" on yesterday until today's row exists (FER-151).
        return f.string(from: Date()).uppercased()
    }

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
        case .primed:       return StrandPalette.statusPrimed
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

    // MARK: (d) DATA SOURCES — compact footnote.

    /// The compact "Sources" footnote card, now `SourcesSummaryCard` (FER-137) so the iOS Data Sources
    /// screen can host it too. macOS Today still shows it here; the iPhone Today dropped it.
    private var sourcesSection: some View {
        SourcesSummaryCard()
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
        async let amRows     = repo.appleDailyMetricRows()

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
        appleMetricDays = (await amRows).sorted { $0.day < $1.day }
        hrPoints  = await hrBucketRows
            .map { TrendPoint(date: Date(timeIntervalSince1970: TimeInterval($0.ts)), value: $0.bpm) }
    }

    // MARK: - 14-day trend loader (all platforms)

    /// Builds the trailing 14-day trend from the DISPLAY dashboard rows (`repo.displayDays`) — the same
    /// layered source the Key Metrics tiles draw from (`measuredSpark`): Apple Health is the base,
    /// on-device computed scores (`my-whoop-noop`) fill the strap's days, imported strap rows win, and a
    /// strap-covered day with a nil field back-fills from Apple Health so the line has no gap (FER-149).
    /// Reading `repo.series(source: "my-whoop")` instead returned EMPTY for a BLE + Apple Health user,
    /// because the computed recovery/HRV/RHR/strain/sleep live in the daily-metrics table under
    /// `my-whoop-noop`, never in the `metricSeries` table that `series()` queries — that was the
    /// empty-chart bug. Noon UTC anchors each day so points sit at consistent x-positions.
    private func loadTrend(pick: @escaping (DailyMetric) -> Double?, window: Int = 14) async -> [TrendPoint] {
        let cutoff = Repository.localDayKey(Calendar.current.date(byAdding: .day, value: -(window - 1), to: Date()) ?? Date())
        return repo.displayDays.compactMap { row -> TrendPoint? in
            guard row.day >= cutoff,
                  let value = pick(row),
                  let date = Self.dayParser.date(from: row.day) else { return nil }
            return TrendPoint(date: date.addingTimeInterval(12 * 3600), value: value)
        }
    }

    /// Returns a loader closure for the given metric id, picking the matching `DailyMetric` field.
    /// Called inline when the MetricInfoSheet is created; runs lazily once the sheet appears. Strain
    /// returns nil: its sheet already carries a dedicated intraday "How today added up" curve, so a
    /// second 14-day line chart would be redundant.
    private func trendLoader(for id: String) -> (() async -> [TrendPoint])? {
        let pick: (DailyMetric) -> Double?
        switch id {
        case "recovery": pick = { $0.recovery }
        case "sleep":    pick = { $0.totalSleepMin }
        case "hrv":      pick = { $0.avgHrv }
        case "rhr":      pick = { $0.restingHr.map(Double.init) }
        case "spo2":     pick = { $0.spo2Pct }
        case "steps":    pick = { $0.steps.map(Double.init) }
        default:         return nil   // strain (own intraday curve) and anything else: no 14-day trend
        }
        return { await self.loadTrend(pick: pick) }
    }

    #if os(iOS)
    /// Today's accumulated-strain curve for the Day Strain info sheet (FER-110). Reads today's HR
    /// (local midnight → now) and runs it through the SAME strain parameters as the daily score — the
    /// user's HRmax, today's resting HR, sex — so the curve's last point lands on the Day Strain value
    /// shown in the header. Loaded lazily when the sheet opens. Returns [] when there's no score yet or
    /// too little activity, so the sheet shows its "not enough activity" state.
    private func loadStrainCurve() async -> [TrendPoint] {
        guard repo.today?.strain != nil else { return [] }
        let startOfToday = Int(Calendar.current.startOfDay(for: Date()).timeIntervalSince1970)
        let nowTs = Int(Date().timeIntervalSince1970)
        let samples = await repo.hrSamples(from: startOfToday, to: nowTs, limit: 100_000)
        let restHR = repo.today?.restingHr.map(Double.init) ?? StrainScorer.defaultRestingHR
        let curve = StrainScorer.cumulativeStrain(
            samples,
            maxHR: Double(model.profile.hrMax),
            restingHR: restHR,
            sex: model.profile.sex
        ).map { TrendPoint(date: $0.date, value: $0.strain) }
        guard !curve.isEmpty else { return [] }
        // Anchor the x-axis to local midnight so the curve reads "from 00:00" even when the strap
        // wasn't worn until later — no recorded load before the first sample means strain 0.
        let midnight = TrendPoint(date: Date(timeIntervalSince1970: TimeInterval(startOfToday)), value: 0)
        return [midnight] + curve
    }
    #endif

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
        // Always the real calendar day — never the last data row's day, or the header
        // looks "stuck" on yesterday until today's row exists (FER-151).
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
            guard day.day >= cutoff else { break }
            if let v = pick(day) { return (v, repo.appleHealthDays.contains(day.day)) }
        }
        // mergeDaily replaces a day's Apple row wholesale when the strap also has that day, so a strap
        // day with a nil field (e.g. a WHOOP 4.0 that didn't decode HRV/sleep) hides the value Apple
        // Health does have. Fall back to the Apple-only rows within the SAME today/yesterday window,
        // badged fromApple, so the strap (when it has the value) still wins above but Key Metrics fills
        // from Apple instead of placeholdering. (FER-98)
        for day in appleMetricDays.reversed() {
            guard day.day >= cutoff else { break }
            if let v = pick(day) { return (v, true) }
        }
        return nil
    }

    /// Inline sparkline for a measured tile: the strap series when present (unchanged behaviour),
    /// otherwise a 14-day series rebuilt from the DISPLAY daily rows so Apple-only history still draws —
    /// and so a strap-covered day whose field is nil (partial-connection day) back-fills from Apple
    /// Health instead of leaving a gap, without touching the strap-only `repo.days` the baseline reads
    /// (FER-149).
    private func measuredSpark(_ key: String, _ pick: (DailyMetric) -> Double?) -> [Double]? {
        if let s = sparks[key], s.count > 1 { return s }
        let cutoff = Repository.localDayKey(Calendar.current.date(byAdding: .day, value: -13, to: Date()) ?? Date())
        let apple = repo.displayDays.filter { $0.day >= cutoff }.compactMap(pick)
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
