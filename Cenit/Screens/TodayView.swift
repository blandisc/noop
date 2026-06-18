import SwiftUI
import StrandDesign
import StrandAnalytics
import WhoopStore
import Foundation

/// Publica el offset vertical del tope del contenido de Hoy para el pull-to-refresh propio (FER-222).
/// En el tope vale 0; al jalar hacia abajo (overscroll) crece > 0; con scroll normal es < 0. Solo se
/// conserva el último valor (un único productor), así que `reduce` toma el más reciente.
private struct TodayScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

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

/// Identifiable wrapper so the light «Instrumento» Detalle de Sueño can ride `.sheet(item:)` from Today
/// (the model itself isn't Identifiable). Mirrors the one Cuerpo uses. (FER-251)
private struct SleepDetailItem: Identifiable {
    let id = UUID()
    let model: SleepDetailModel
}

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
    /// Cuenta cada pull-to-refresh para disparar la háptica declarativa (`.sensoryFeedback`) al
    /// provocar el gesto de sincronización (FER-204).
    @State private var syncHaptic = 0

    // MARK: - Pull-to-refresh propio (FER-222)
    //
    // Reemplaza el `.refreshable` nativo (su ruedita gris de ~1 s) por un gesto que DIBUJA el
    // dial: al jalar Hoy hacia abajo, `pullProgress` (0→1) arma el arco verde del `DiurnalDial`
    // proporcional al desplazamiento; al cruzar `pullThreshold` se dispara UNA vez la misma
    // sincronización de antes (`pullToSync`) y el dial pasa a girar (modo `syncing` de FER-221).
    // El offset del tope del scroll se lee con un `GeometryReader` en un coordinate space propio
    // (no toca el scroll normal). Bajo Reduce Motion no se dibuja el arco (el llamador deja
    // `pullProgress` en 0), pero el gesto sigue armando + disparando con su háptica.

    /// Progreso del tirón (0→1): arma el arco del dial. Se queda en 0 bajo Reduce Motion.
    @State private var pullProgress: Double = 0
    /// El tirón ya cruzó el umbral en ESTE gesto (ya disparó el sync) — evita re-disparar hasta
    /// que el scroll vuelve al tope.
    @State private var pullCommitted = false
    /// Sync en curso DISPARADO por el tirón: hace girar el dial de inmediato (sin esperar a que
    /// `live.backfilling` arranque, p. ej. offline). Se apaga al terminar `pullToSync()`; para
    /// entonces, si arrancó un offload real, `live.backfilling` releva el giro.
    @State private var pullSyncing = false
    /// Distancia de tirón (pt) para armar y disparar. Calibrado para sentirse deliberado sin
    /// agotar el pulgar (el dial mide 180); el «feel» fino se confirma en el iPhone (FER-222).
    private let pullThreshold: CGFloat = 96
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

    // Today's stress (0–3 autonomic proxy) for the «Estrés» tile — the same transparent model
    // StressView builds, computed once per load from `repo.displayDays` + the stored "stress" series. (FER-180)
    @State private var stress: StressModel? = nil

    // Support sheet (donate + contact) — always reachable from the home toolbar.
    @State private var showingSupport = false

    // Metric-info sheet — tapping any Key Metrics row presents this.
    @State private var metricDetail: MetricInfo? = nil
    @State private var showWhyVerdict = false

    // Rich «Instrumento» Detalle drilled into via the summary sheet's "Ver más" (FER-251). These mirror the
    // ones Cuerpo presents — Today reuses the SAME static `.build()` factories / specs, so the detail is
    // identical from both tabs. `pendingSeeMore` defers presenting until the summary fully dismisses, so the
    // sheet-over-sheet hand-off never gets swallowed (it runs in the summary sheet's `onDismiss`).
    @State private var pendingSeeMore: (() -> Void)? = nil
    @State private var recoveryDetail: RecoveryDetailItem? = nil
    @State private var sleepDetail: SleepDetailItem? = nil
    @State private var strainDetail: StrainDetailItem? = nil
    @State private var stressDetail: StressDetailItem? = nil
    @State private var metricSpec: MetricDetailSpec? = nil

    // THE single grid definition — every tile group reuses it so margins line up.
    private let grid = [GridItem(.adaptive(minimum: 168), spacing: NoopMetrics.gap)]

    // MARK: - Memoización del veredicto + conteos derivados (FER-172)
    //
    // `ReadinessEngine.evaluate` y los conteos de noches de HRV ordenan/mapean los ~4000 días de
    // historia. Antes eran computed properties que el `body` invocaba 3+ veces POR RENDER (héroe,
    // verdictBody, métricas, sheet), así que corrían completos en CADA repintado —cada tick de HR en
    // vivo, cada frame de animación—, congelando el hilo principal hasta el riesgo de watchdog. Ahora
    // se calculan UNA vez por cambio de datos y se cachean en `@State`: `recomputeDerived()` los siembra
    // desde el `.task(id: repo.refreshSeq)` (mismo patrón de memoización que StressView). El gate es
    // `repo.refreshSeq` —un Int que sube en cada `refresh()`, mientras `days`/`today`/`appleHealthDays`
    // viven en el MISMO valor publicado `dashboard`—, así que es O(1) por render en vez de comparar el
    // arreglo completo. Los accesores caen a un cálculo en línea solo si el memo aún es nil (el primer
    // body antes de que `.task` siembre), nunca en el camino caliente.

    /// El veredicto de hoy, memoizado. nil hasta la primera siembra; el accesor `readiness` cae a un
    /// cálculo en línea ese único frame para no parpadear.
    @State private var memoReadiness: ReadinessEngine.Readiness?
    /// Los conteos de noches derivados de HRV, memoizados (ver `DerivedHrvCounts`).
    @State private var memoCounts: DerivedHrvCounts?

    /// Los tres conteos de noches que el héroe/veredicto leen, agrupados para sembrarlos de una sola
    /// pasada sobre `repo.days` (antes cada propiedad remapeaba la historia por su cuenta).
    private struct DerivedHrvCounts: Equatable {
        let recoveryCalibration: Int?
        let ownNights: Int
        let seededNights: Int
        /// La base ya está sembrada (≥ `minNightsSeed` noches válidas) pero las noches PROPIAS del strap
        /// aún no: la base vino de un import de Apple Health, no del strap (FER-106).
        var hasImportedBaseline: Bool {
            seededNights >= Baselines.minNightsSeed && ownNights < Baselines.minNightsSeed
        }
    }

    /// Calcula los conteos de una sola pasada: `nightlyHrv` (toda la historia) se mapea UNA vez y se
    /// reutiliza para `recoveryCalibration` y `seededNights`; `strapHrv` (sin los días de Apple Health)
    /// para `ownNights`. Misma matemática que las propiedades previas, sin el remapeo triple.
    private func computeHrvCounts() -> DerivedHrvCounts {
        let nightlyHrv = repo.days.map(\.avgHrv)
        let appleDays = repo.appleHealthDays
        let strapHrv = repo.days.filter { !appleDays.contains($0.day) }.map(\.avgHrv)
        return DerivedHrvCounts(
            recoveryCalibration: RecoveryScorer.calibrationNights(nightlyHrv: nightlyHrv,
                                                                  hasRecovery: repo.today?.recovery != nil),
            ownNights: RecoveryScorer.calibrationNights(nightlyHrv: strapHrv, hasRecovery: false, seed: .max) ?? 0,
            seededNights: RecoveryScorer.calibrationNights(nightlyHrv: nightlyHrv, hasRecovery: false, seed: .max) ?? 0)
    }

    /// Siembra el veredicto + los conteos UNA vez por refresh. La llama el `.task(id: repo.refreshSeq)`
    /// (vía `loadAll()`), antes de cualquier `await`, así que el body deja de recalcular en cada frame.
    private func recomputeDerived() {
        memoReadiness = ReadinessEngine.evaluate(days: repo.days, today: Repository.localDayKey(Date()))
        memoCounts = computeHrvCounts()
        #if DEBUG
        // FER-172: prueba de que el veredicto se recalcula UNA vez por refresh. En scroll/animación/
        // ticks de HR esta línea NO debe reaparecer; solo sale una vez por `seq`. Compila fuera en release.
        print("[FER-172] readiness recomputed · seq=\(repo.refreshSeq) · days=\(repo.days.count)")
        #endif
    }

    /// Los conteos memoizados; cae a un cálculo en línea solo el primer frame (memo aún nil).
    private var hrvCounts: DerivedHrvCounts { memoCounts ?? computeHrvCounts() }

    /// Recovery cold-start: recovery is nil until the HRV baseline crosses the seed gate
    /// (Baselines.minNightsSeed valid nights). While calibrating, this is the count of nights
    /// banked so far — it drives an honest "Calibrating — N of 4 nights" on the recovery ring,
    /// the synthesis card and the Key Metrics tile instead of a bare empty state. It self-clears
    /// the moment recovery populates, and never claims "calibrating" at/above the seed gate.
    /// Mirrors Android TodayScreen.recoveryCalibrationNights (7b5f212). Memoizado vía `hrvCounts` (FER-172).
    private var recoveryCalibration: Int? { hrvCounts.recoveryCalibration }

    /// Nights of the user's OWN strap data with usable HRV, 0… (drives the night-dots progress).
    /// Apple-Health days are deliberately EXCLUDED: Apple Health fills Trends/Sleep preliminarily but
    /// it's borrowed data — its rows carry `recovery: nil` and never seed the recovery baseline — so
    /// the dots keep counting toward the 4 nights of YOUR data the verdict actually needs. Reuses the
    /// same in-range HRV filter via a high seed; once this reaches the seed the baseline is genuinely
    /// yours and the verdict path takes over. Memoizado vía `hrvCounts` (FER-172).
    private var ownNights: Int { hrvCounts.ownNights }

    /// Nights of usable HRV across the WHOLE merged baseline (Apple Health + strap), 0… Reuses the
    /// same in-range HRV predicate as `ownNights` via a high seed, but over `repo.days` (not just
    /// strap rows), so a full Apple-Health import counts here even though it never counts in `ownNights`.
    /// Memoizado vía `hrvCounts` (FER-172).
    private var seededNights: Int { hrvCounts.seededNights }

    /// True when the recovery baseline is already seeded (≥ `minNightsSeed` valid HRV nights) but the
    /// user's OWN strap nights are still below the seed — i.e. the base came from imported Apple Health
    /// history, not the strap. Drives the "your baseline is ready, the strap just adds today" onboarding
    /// narrative so the pre-verdict states never read "0 of 4" as if no base existed (FER-106). Pure
    /// read of existing signals — no engine math. Naturally false without an import (no permission, no
    /// history → `seededNights < minNightsSeed`), so no state can promise an Apple-Health base it lacks.
    private var hasImportedBaseline: Bool { hrvCounts.hasImportedBaseline }

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
            // The summary sheet. On dismiss, run any pending "Ver más" hand-off (FER-251): presenting the
            // rich detail only AFTER this one is gone avoids SwiftUI swallowing a sheet-over-sheet present.
            // A plain swipe-to-close leaves `pendingSeeMore` nil, so nothing extra happens.
            .sheet(item: $metricDetail, onDismiss: { pendingSeeMore?(); pendingSeeMore = nil }) { info in
                metricSheet(for: info)
            }
            .sheet(isPresented: $showWhyVerdict) {
                WhyVerdictSheet(readiness: readiness, theme: theme)
            }
            // Rich «Instrumento» Detalle, drilled into from a summary sheet's "Ver más" — the SAME screens
            // Cuerpo presents, theme passed explicitly (it doesn't propagate through `.sheet`), NO nested
            // NavigationStack (FER-171). (FER-251)
            .sheet(item: $recoveryDetail) { item in
                RecoveryDetailScreen(theme: theme, model: item.model)
            }
            .sheet(item: $sleepDetail) { item in
                SleepDetailScreen(theme: theme, model: item.model)
            }
            .sheet(item: $strainDetail) { item in
                StrainDetailScreen(theme: theme, model: item.model,
                                   curveLoader: { await loadStrainCurve() })
            }
            .sheet(item: $stressDetail) { item in
                StressDetailScreen(theme: theme, model: item.model)
            }
            .sheet(item: $metricSpec) { spec in
                MetricDetailScreen(
                    spec: spec,
                    depth: .full,
                    theme: theme,
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
            trendLoader: trendLoader(for: info.id),
            onSeeMore: seeMoreAction(for: info.id)
        )
    }

    /// The "Ver más" hand-off for a metric: returns nil when there's no rich detail destination yet
    /// (SpO₂ / Heart Rate → no link shown). Otherwise returns a closure that defers presenting
    /// the rich detail until the summary dismisses (`pendingSeeMore` + `metricDetail = nil`). The detail
    /// reuses the SAME static factories / specs Cuerpo uses, so it's identical from both tabs. (FER-251)
    private func seeMoreAction(for id: String) -> (() -> Void)? {
        let present: (() -> Void)?
        switch id {
        case "recovery":
            present = {
                recoveryDetail = RecoveryDetailItem(model: RecoveryDetailModel.build(
                    days: repo.days, today: repo.today,
                    todayKey: Repository.localDayKey(Date()),
                    appleHealthDays: repo.appleHealthDays, loaded: repo.loaded))
            }
        case "sleep":
            present = {
                sleepDetail = SleepDetailItem(model: SleepDetailModel.build(
                    days: repo.days, sleeps: repo.sleeps, importedSleep: repo.importedSleep,
                    appleHealthDays: repo.appleHealthDays, loaded: repo.loaded,
                    todayKey: Repository.localDayKey(Date())))
            }
        case "strain":
            present = {
                strainDetail = StrainDetailItem(model: StrainDetailModel.build(
                    days: repo.days, today: repo.today, loaded: repo.loaded))
            }
        case "stress":
            present = { stressDetail = StressDetailItem(model: stress) }
        case "hrv":
            present = { metricSpec = .hrv(resolveMeasured { $0.avgHrv }?.value) }
        case "rhr":
            present = { metricSpec = .restingHR(resolveMeasured { $0.restingHr.map(Double.init) }
                .map { Int($0.value.rounded()) }) }
        case "heart_rate":
            present = { metricSpec = .heartRate(hrTodayAvg) }
        case "steps":
            present = { metricSpec = .steps(freshSteps) }
        case "spo2":
            present = { metricSpec = .spo2(resolveMeasured { $0.spo2Pct }?.value) }
        default:
            present = nil
        }
        guard let present else { return nil }
        return { pendingSeeMore = present; metricDetail = nil }
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
        // Reparto del aire sobrante (FER-217): un `GeometryReader` da el alto visible (`proxy.size.height`)
        // y el contenido se fuerza a medir AL MENOS ese alto (`.frame(minHeight:)`), de modo que dos
        // `Spacer(minLength:)` reparten por igual el espacio que sobre —arriba y abajo de «Métricas de
        // hoy»— y el bloque queda equilibrado en pantallas altas. En pantalla chica (contenido que llena
        // o lo excede) los spacers colapsan a su mínimo y NO suman altura: preserva el compactado de
        // FER-202 y el scroll de siempre. Los modifiers de la pantalla (refresh, tema, hojas) cuelgan del
        // `GeometryReader`, que envuelve al `ScrollView`, así que pull-to-refresh y el papel siguen igual.
        GeometryReader { proxy in
            todayScroll(proxy)
        }
        // Pull-to-refresh propio (FER-222): reemplaza el `.refreshable` nativo (su ruedita gris de
        // ~1 s). El gesto de jalar DIBUJA el dial —`handlePullOffset` arma el arco verde proporcional
        // al tirón— y al cruzar el umbral dispara la MISMA sincronización de antes (`pullToSync`) y el
        // dial pasa a girar (modo `syncing` de FER-221). La háptica `.medium` la dispara
        // `.sensoryFeedback` por el cambio de `syncHaptic` que hace `pullToSync` (heredado de FER-204).
        .sensoryFeedback(.impact(weight: .medium), trigger: syncHaptic)
        // El fondo es el papel del tema (`PaperBackground` lee `\.instrumentoTheme` DENTRO del subárbol
        // tematizado, así que el lienzo también se recolorea por hora). El tema por hora se inyecta aquí,
        // acotado a TodayView (NUNCA en RootTabView): todo el árbol de abajo lee `\.instrumentoTheme` y
        // se recolorea según la hora del día gratis.
        .background(PaperBackground())
        .instrumentoThemeByHour(solar: solarWindow)
        // El color scheme (y con él la barra de estado: Hoy = papel claro → tinta oscura) se decide
        // en ContentView según la pestaña activa, porque `preferredColorScheme` lo resuelve el
        // controlador raíz del WindowGroup y un valor puesto AQUÍ (dentro del TabView) no llega.
        // En vivo se abre como HOJA (FER-190), no pantalla completa: un `.sheet` con grabber, igual que
        // las hojas de métrica. La hoja abre a la altura del contenido — el detente lo fija `LiveView`
        // midiéndose (FER-196). El tema «Instrumento» se pasa explícito (no se propaga por el entorno
        // fresco del sheet) y la hoja se presenta en claro con el papel del tema; cierra con swipe.
        .sheet(isPresented: $showLiveMonitor) {
            LiveView(theme: theme, monitorOnly: true)
                .environmentObject(model)
                .environmentObject(live)
                .environmentObject(repo)
                .presentationDragIndicator(.visible)
                .presentationBackground(theme.paper)
                .preferredColorScheme(.light)
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

    /// El `ScrollView` de Hoy + el rastreo del tirón del pull-to-refresh propio (FER-222). El offset del
    /// scroll se lee de la fuente MÁS confiable según versión: en iOS 18+ con `onScrollGeometryChange`
    /// (lee el `contentOffset` real del scroll — robusto), y como respaldo en iOS 17 con el lector por
    /// `GeometryReader`/coordinate space (`TodayScrollOffsetKey`). En ambos casos el valor que se pasa a
    /// `handlePullOffset` es positivo cuando el contenido se jala hacia abajo (overscroll en el tope).
    /// `.scrollBounceBehavior(.always)` garantiza el rebote en el tope aunque el contenido quepa exacto.
    @ViewBuilder
    private func todayScroll(_ proxy: GeometryProxy) -> some View {
        let scroll = ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // El grupo superior conserva el ritmo de sección compacto (FER-202): gap de 16
                // (`NoopMetrics.sectionGapCompact`) entre fecha, alerta y héroe.
                VStack(alignment: .leading, spacing: NoopMetrics.sectionGapCompact) {
                    headerBlock
                    HealthAlertBanner()
                    // Héroe unificado (FER-160): UN solo instrumento de estado adaptable cubre los
                    // cuatro modos (veredicto / base sembrada por Apple Health / calibrando / espera).
                    // Lo único que cambia entre modos es QUÉ valor lleva el numeral, su color (regla
                    // «color = listo / tinta = en espera») y el pie. Ver `heroInstrument` + `heroState`.
                    heroInstrument
                }
                // Gap mínimo héroe→«Métricas de hoy»: 8 (`NoopMetrics.space2`), el mismo ~8 compacto que
                // daba el inset negativo de antes (FER-202/FER-217). Cuando sobra espacio, este Spacer
                // crece a la par del de abajo y despega las métricas del héroe.
                // El acceso al monitor en vivo «latido a latido» vive como pastilla de pulso en el
                // encabezado de «Métricas de hoy» (FER-194), no como fila al pie. Ver `iosMetricsSection`.
                Spacer(minLength: NoopMetrics.space2)
                iosMetricsSection
                // Gap mínimo bajo las métricas: 0 — el margen inferior lo da `.padding(.bottom)`. Cuando
                // sobra espacio, este Spacer crece igual que el de arriba y «Métricas de hoy» queda
                // centrada en el sobrante (opción aprobada por el dueño, FER-217).
                Spacer(minLength: 0)
            }
            // Inset superior `gap` (FER-202): el héroe queda alto pero respira; márgenes h/inferior estándar.
            .padding(.horizontal, NoopMetrics.screenPadding)
            .padding(.bottom, NoopMetrics.screenPadding)
            .padding(.top, NoopMetrics.gap)
            // Llena al menos el alto visible para que los `Spacer` tengan sobrante que repartir; si el
            // contenido lo excede (p. ej. calibrando en pantalla chica), crece y hace scroll igual.
            .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .leading)
            // FER-222 (respaldo iOS 17): el fondo del bloque publica el offset de su tope en el coordinate
            // space propio del scroll. En iOS 18+ esta preferencia se ignora (manda `onScrollGeometryChange`).
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: TodayScrollOffsetKey.self,
                                           value: geo.frame(in: .named("todayPullScroll")).minY)
                }
            )
        }
        // FER-222: el scroll siempre rebota (aunque el contenido quepa exacto), para que el tirón en el
        // tope funcione sin el `.refreshable` nativo que antes forzaba ese rebote.
        .scrollBounceBehavior(.always)

        if #available(iOS 18.0, *) {
            // iOS 18+: lee el `contentOffset` real del scroll. En reposo `contentOffset.y == -contentInsets.top`,
            // así que `-(offset.y + insets.top)` es 0 en el tope y POSITIVO al jalar hacia abajo (overscroll).
            scroll.onScrollGeometryChange(for: CGFloat.self) { geometry in
                -(geometry.contentOffset.y + geometry.contentInsets.top)
            } action: { _, pull in
                handlePullOffset(pull)
            }
        } else {
            // iOS 17: respaldo por coordinate space + el lector de fondo de arriba.
            scroll
                .coordinateSpace(name: "todayPullScroll")
                .onPreferenceChange(TodayScrollOffsetKey.self) { handlePullOffset($0) }
        }
    }

    /// La acción de sincronización del pull-to-refresh de `iosBody` (FER-204; la reusa el gesto
    /// propio de FER-222 vía `triggerPullSync`, y la acción accesible de VoiceOver). Fuerza una
    /// sincronización con la banda según su estado, SIN esperar al offload largo:
    /// - Conectada → `syncNow()` (offload `.manual`, sin rate-limit).
    /// - Banda conocida pero desconectada (hubo un sync previo: `lastSyncedAt != nil`) → `scan()`; el
    ///   handshake de reconexión auto-dispara el sync (`requestSync(.connect)`), sin orquestarlo a mano.
    /// - Sin banda conocida → solo el `repo.refresh()` de abajo (recálculo local), sin escaneo ni error.
    /// `lastSyncedAt` es la señal honesta de "hay/hubo banda" (solo se fija tras un offload completo y
    /// persiste entre lanzamientos); `selectedWhoopModel` no sirve aquí (su default pasa el onboarding
    /// aunque el usuario no tenga banda).
    /// El `repo.refresh()` final asegura que la pantalla refleje lo último (los scores se recalculan
    /// solos vía `repo.refreshSeq` → `.task(id:)`). El `sleep` corto conserva el «soltar pronto» (~1.2 s)
    /// de FER-204; el offload largo sigue en segundo plano, reflejado en el dial girando + `SyncInline`.
    @MainActor
    private func pullToSync() async {
        syncHaptic += 1                       // dispara la háptica `.medium` al provocar el gesto
        if live.connected {
            model.ble.syncNow()               // conectada → offload manual inmediato
        } else if live.lastSyncedAt != nil {
            model.scan()                      // banda conocida pero desconectada → reconecta; al
                                              // conectar, el handshake sincroniza solo
        }
        // Sin banda conocida (`lastSyncedAt == nil`) no se escanea: cae directo al refresh local.
        try? await Task.sleep(for: .seconds(1.2))
        await repo.refresh()
    }

    /// Procesa el overscroll del tope del scroll (FER-222) para el pull-to-refresh propio. `overscroll` > 0
    /// = el contenido se jaló hacia abajo (overscroll en el tope): mapea el tirón a `pullProgress` (0→1),
    /// que arma el arco del dial, y al cruzar `pullThreshold` dispara la sincronización UNA vez por gesto.
    /// Bajo Reduce Motion NO dibuja el arco (`pullProgress` se queda en 0), pero el gesto sigue armando y
    /// disparando con su háptica. El scroll normal (`overscroll ≤ 0`) no escribe estado → sin recomputar el
    /// body. Lo alimenta `todayScroll` desde `onScrollGeometryChange` (iOS 18+) o el lector de offset (iOS 17).
    @MainActor
    private func handlePullOffset(_ overscroll: CGFloat) {
        let pull = max(0, overscroll)
        guard pull > 0 else {
            if pullProgress != 0 { pullProgress = 0 }
            if pullCommitted { pullCommitted = false }   // de vuelta en el tope: listo para re-armar
            return
        }
        if !reduceMotion {
            let progress = Double(min(pull / pullThreshold, 1))
            if progress != pullProgress { pullProgress = progress }
        }
        if pull >= pullThreshold, !pullCommitted, !pullSyncing {
            pullCommitted = true
            triggerPullSync()
        }
    }

    /// Dispara la sincronización desde el gesto propio (FER-222) o desde la acción accesible de VoiceOver.
    /// Enciende `pullSyncing` (el dial gira de inmediato, sin esperar al offload) y corre la MISMA acción
    /// de siempre (`pullToSync`: háptica + `syncNow`/`scan` + «soltar pronto» + refresh local). Al terminar
    /// apaga `pullSyncing`; si arrancó un offload real, `live.backfilling` releva el giro. El guard evita
    /// apilar syncs (gesto + VoiceOver, o un re-cruce de umbral).
    @MainActor
    private func triggerPullSync() {
        guard !pullSyncing else { return }
        pullProgress = 0
        pullSyncing = true
        Task {
            await pullToSync()
            pullSyncing = false
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
    /// FER-222: como el pull-to-refresh propio reemplaza al `.refreshable` nativo (que regalaba una
    /// acción de refrescar accesible), aquí se reinstala esa afordancia para VoiceOver: la línea de
    /// estado de sincronización —su hogar semántico— expone una acción personalizada «Sincronizar»
    /// equivalente al gesto, vía `triggerPullSync`. Se combinan fecha + estado en un solo elemento
    /// para que la acción sea descubrible al enfocar el encabezado.
    private var headerBlock: some View {
        HStack(alignment: .center) {
            utilityRow
            Spacer(minLength: 0)
            if let pct = live.batteryPct {
                HStack(spacing: 4) {
                    Image(systemName: batteryIcon(pct: pct, charging: live.charging == true))
                        .font(StrandFont.overline)
                        .foregroundStyle(theme.inkTertiary)
                    Text("\(Int(pct.rounded()))%")
                        .font(StrandFont.overline)
                        .tracking(StrandFont.overlineTracking)
                        .foregroundStyle(theme.inkTertiary)
                }
                .accessibilityLabel(live.charging == true
                    ? Text("Batería del strap: \(Int(pct.rounded()))%, cargando")
                    : Text("Batería del strap: \(Int(pct.rounded()))%"))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: Text("Sincronizar")) { triggerPullSync() }
    }

    /// SF Symbol name for a battery-level icon at the given percentage, with an
    /// optional charging bolt (uses the `.bolt` suffix variants from SF Symbols 3+).
    private func batteryIcon(pct: Double, charging: Bool) -> String {
        let level: String
        switch pct {
        case 75...: level = "battery.100"
        case 50..<75: level = "battery.75"
        case 25..<50: level = "battery.50"
        default:      level = "battery.25"
        }
        return charging ? "\(level).bolt" : level
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
        VStack(spacing: NoopMetrics.gap) {
            Text(heroOverline(state)).instrumentoOverline().foregroundStyle(theme.inkTertiary)
                .frame(maxWidth: .infinity, alignment: .center)
            // Instrumento concéntrico (FER-169): el numeral domina el CENTRO del dial de 24h, no a su lado.
            // Sin número que medir (em-dash) el dial es el protagonista; con número, el dato vive dentro del
            // reloj. El dial preside SIEMPRE y centrado para que la pantalla nunca se vea a medio construir.
            // `sleepWindow` ya es nil cuando anoche no hubo registro de strap, así que el dial omite la banda
            // de sueño sola: contexto honesto en cada modo. Escala (FER-205): dial 180 con el numeral 60 (como
            // antes de FER-202 — el dueño prefirió el dial grande), conservando el «/100» apilado y centrado
            // debajo (FER-202). Con el dial grande Hoy puede volver a necesitar algo de scroll en calibrando.
            ZStack {
                // FER-221: mientras la banda descarga (`backfilling`) el dial cobra vida —un arco
                // verde gira sobre el bezel— y el numeral se atenúa («recalculando»). La honesty line
                // del header no cambia. Al terminar, vuelve al reposo.
                // FER-222: el mismo arco se «arma» con el tirón (`pullProgress`, 0→1) antes de girar; al
                // disparar el sync por el gesto (`pullSyncing`) el dial gira de inmediato, sin esperar a
                // que arranque el offload. `syncing` manda sobre `armProgress` cuando ambos coinciden.
                DiurnalDial(now: Date(), solar: solarWindow, sleep: sleepWindow,
                            diameter: 180, syncing: live.backfilling || pullSyncing,
                            armProgress: pullProgress)
                heroNumeral(state)
            }
            heroBody(state)
            heroFooter(state)
        }
        .frame(maxWidth: .infinity)
    }

    private func heroOverline(_ s: HeroState) -> LocalizedStringKey {
        switch s {
        case .calibrating: return "Tu base se afina"
        default:           return "El veredicto de hoy"
        }
    }

    /// El color del numeral del héroe — tinta normal, atenuado a tertiary mientras sincroniza
    /// (FER-221): «recalculando», en sintonía con el dial girando. Vuelve a tinta al terminar.
    private var heroNumeralInk: Color { (live.backfilling || pullSyncing) ? theme.inkTertiary : theme.ink }

    /// El numeral dominante — lo único que “grita” el estado. Veredicto → recuperación SIEMPRE en TINTA:
    /// el color por nivel lo lleva la PALABRA del veredicto, no el número, así nunca se contradicen
    /// (FER-206; antes el número iba en color de banda y podía pelearse con la palabra, p. ej. «66» ámbar
    /// bajo «Equilibrado» verde). Calibrando → «N/4» en tinta (progreso, no dato). Espera/base Apple →
    /// em-dash «—» en tinta. Numeral 60 con el denominador («/100» o «/seed») apilado pequeño y centrado
    /// debajo (FER-202).
    @ViewBuilder private func heroNumeral(_ s: HeroState) -> some View {
        switch s {
        case .verdict:
            let score = recoveryScore
            // Concéntrico (FER-169/202): el NÚMERO queda centrado en el eje del dial, con el «/100» apilado
            // pequeño y centrado DEBAJO (antes flotaba a la derecha con un «/100» espejo invisible que lo
            // descentraba y lo desbordaba del aro). La escala también vive en el detalle de recuperación.
            Group {
                if let score {
                    VStack(spacing: NoopMetrics.space1) {
                        Text("\(score)").instrumentoHero(60)
                            .foregroundStyle(heroNumeralInk)
                        Text("/100").font(StrandFont.subhead).foregroundStyle(theme.inkTertiary)
                    }
                } else {
                    Text("—").instrumentoHero(60).foregroundStyle(theme.inkTertiary)
                }
            }
            // El número abre la hoja RESUMIDA de recuperación (MetricInfoSheet), igual que las demás
            // métricas de Hoy — el detalle rico «Instrumento» (RecoveryDetailScreen) vive en Cuerpo (FER-232).
            .contentShape(Rectangle())
            .onTapGesture {
                metricDetail = .recovery(score: recoveryScore,
                                         calibrationNights: recoveryCalibration,
                                         nightsNeeded: Baselines.minNightsSeed)
            }
        case .calibrating(let nights):
            // Apilado (FER-202), igual que el veredicto: «N» centrado en el eje del dial con el «/seed»
            // pequeño y centrado debajo (antes a un lado con un «/seed» espejo invisible).
            VStack(spacing: NoopMetrics.space1) {
                Text("\(nights)").instrumentoHero(60).foregroundStyle(heroNumeralInk)
                Text("/\(Baselines.minNightsSeed)").font(StrandFont.subhead)
                    .foregroundStyle(theme.inkTertiary)
            }
        case .importedBaseline, .waiting:
            Text("—").instrumentoHero(60).foregroundStyle(theme.inkTertiary)
        }
    }

    /// El cuerpo bajo el numeral: la palabra del veredicto + «i» + modificadores (veredicto), o la línea
    /// honesta de qué falta (resto de modos).
    @ViewBuilder private func heroBody(_ s: HeroState) -> some View {
        switch s {
        case .verdict:
            verdictBody
        case .importedBaseline:
            VStack(alignment: .center, spacing: NoopMetrics.space2) {
                appleBaseChip
                Text("Falta la lectura de hoy")
                    .font(StrandFont.headline).foregroundStyle(theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Usa tu banda para sumar lo único que Apple Salud no puede: la lectura de hoy.")
                    .font(StrandFont.body).foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
        case .calibrating(let nights):
            VStack(alignment: .center, spacing: NoopMetrics.gap) {
                calibrationDots(nights: nights)
                Text(calibrationDetailCopy(nights: nights))
                    .font(StrandFont.body).foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
        case .waiting:
            VStack(alignment: .center, spacing: NoopMetrics.space2) {
                Text(strapSeen ? "Aún no hay lectura de hoy" : "Aún no hay lectura")
                    .font(StrandFont.headline).foregroundStyle(theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(strapSeen
                     ? "Tu base está lista. Usa el strap esta noche y la recuperación, el esfuerzo y el sueño de la mañana aparecen al sincronizar."
                     : "Conecta tu strap WHOOP para ver la disposición, la recuperación y la frecuencia cardiaca de la mañana.")
                    .font(StrandFont.body).foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
        }
    }

    /// El cuerpo del veredicto: la palabra en su color de nivel + la «i» (toda la fila tocable) que abre
    /// el porqué, la frase puente, la salvedad de noche corta y la barra «afinando · N de 14». Cuando el
    /// nivel es `insufficient` hay número pero no palabra: el numeral va en tinta (arriba) y aquí la razón.
    @ViewBuilder private var verdictBody: some View {
        let r = readiness
        if r.level != .insufficient {
            Button { showWhyVerdict = true } label: {
                HStack(spacing: NoopMetrics.space2) {
                    Text(r.headline).font(StrandFont.title2).fontWeight(.semibold)
                        .foregroundStyle(verdictDataColor(r.level))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Image(systemName: "info.circle").font(.system(size: 15))
                        .foregroundStyle(theme.inkTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("Abre por qué el veredicto se lee así"))
            if let bridge = r.bridge {
                Text(bridge).font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if r.confidenceLow, let note = r.confidenceNote {
                HStack(spacing: NoopMetrics.space2) {
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
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// El pie del héroe — solo afordancias de onboarding (FER-189): el CTA «Buscar strap» cuando nunca se
    /// ha visto uno, o el atajo «¿Tienes historial en Apple Salud?…» mientras calibra. El renglón de pulso
    /// vivo «Verlo latido a latido» se MUDÓ al pie de la pantalla (`iosBody`), así que el héroe queda
    /// limpio: número + veredicto. En veredicto / espera-con-strap el pie del héroe no muestra nada.
    @ViewBuilder private func heroFooter(_ s: HeroState) -> some View {
        switch s {
        case .verdict:
            EmptyView()
        case .calibrating:
            appleHealthShortcut { showDataSources = true }
        case .importedBaseline, .waiting:
            if !strapSeen { scanButton }
        }
    }

    /// El único CTA del estado de espera sin strap: texto en el papel sobre el verde del veredicto.
    private var scanButton: some View {
        Button { model.scan() } label: {
            Text("Buscar strap")
                .font(StrandFont.headline)
                .foregroundStyle(theme.paper)
                .frame(maxWidth: .infinity)
                .padding(.vertical, NoopMetrics.gap)
                .background(theme.verdict, in: RoundedRectangle(cornerRadius: NoopMetrics.controlRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.top, NoopMetrics.space1)
    }

    /// Chip de procedencia — la base viene de Apple Health, dicho de frente. Tono de dato (azul de Apple
    /// Salud), AA sobre papel.
    private var appleBaseChip: some View {
        HStack(spacing: NoopMetrics.space2) {
            Image(systemName: "heart.fill").font(.system(size: 12))
            Text("Base · Apple Salud").font(StrandFont.subhead)
        }
        .foregroundStyle(theme.dataSpO2)
        .padding(.horizontal, NoopMetrics.space2).padding(.vertical, NoopMetrics.space1)
        .background(theme.dataSpO2.opacity(0.12), in: RoundedRectangle(cornerRadius: NoopMetrics.chipRadius, style: .continuous))
    }

    /// Night-dots de calibración: llenos en el dato (`dataRecovery`), vacíos en `hairline`.
    private func calibrationDots(nights: Int) -> some View {
        let total = Baselines.minNightsSeed
        return HStack(spacing: NoopMetrics.space2) {
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
    /// base ahora en vez de esperar las 0→seed noches. Renglón full-width con hairline que abre Fuentes de
    /// datos.
    private func appleHealthShortcut(onTap: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            Rectangle().fill(theme.hairline).frame(height: 0.5)
                .padding(.top, NoopMetrics.gap).padding(.bottom, NoopMetrics.gap)
            Button(action: onTap) {
                HStack(spacing: NoopMetrics.space2) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 12)).foregroundStyle(theme.dataSpO2)
                    Text("¿Tienes historial en Apple Salud? Conéctalo y tu base arranca con ventaja.")
                        .font(StrandFont.caption)
                        .foregroundStyle(theme.inkSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: NoopMetrics.space2)
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

    /// La pastilla de pulso vivo del encabezado de «Métricas de hoy» (FER-194): corazón en tinta + punto
    /// de pulso + bpm + «bpm», en una cápsula `surface` con hairline. Reemplaza la fila «Verlo latido a
    /// latido» del pie (FER-189); es un Button compacto que abre el monitor latido a latido. Regla «color
    /// solo en el dato»: únicamente el punto lleva color (`dataHeart` al transmitir), el resto va en tinta.
    /// Sin lectura del strap → muestra «—» y el punto en tinta, pero sigue tappable.
    private struct LivePulsePill: View {
        var liveBpm: Int?
        var isLiveHR: Bool
        let onTap: () -> Void
        @Environment(\.instrumentoTheme) private var theme

        var body: some View {
            Button(action: onTap) {
                // Chip compacto (FER-265): punto que late + bpm + chevron. La cápsula + el chevron son
                // el lenguaje iOS de «esto se toca»; el punto en color de dato (vivo) es el único color.
                HStack(alignment: .center, spacing: NoopMetrics.space1) {
                    Circle().fill(isLiveHR ? theme.dataHeart : theme.inkTertiary)
                        .frame(width: 7, height: 7)
                    Text(liveBpm.map { "\($0)" } ?? "—").font(StrandFont.number(13, weight: .semibold))
                        .foregroundStyle(liveBpm == nil ? theme.inkTertiary : theme.ink)
                    Text("bpm").font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold)).foregroundStyle(theme.inkTertiary)
                }
                .padding(.leading, NoopMetrics.space2).padding(.trailing, NoopMetrics.space1)
                .padding(.vertical, 3)
                .background(theme.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(theme.hairline, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(Text(isLiveHR ? "Frecuencia cardiaca en vivo" : "Frecuencia cardiaca"))
            .accessibilityValue(Text(liveBpm.map { "\($0) bpm" } ?? "Sin lectura"))
            .accessibilityHint(Text("Abre el monitor latido a latido"))
        }
    }

    /// Línea de sincronización inline (FER-265): vive junto al sello «Hoy», ya no al pie. Reposo →
    /// glifo + tiempo relativo («hace 3 min»); sincronizando → glifo GIRANDO + conteo de paquetes
    /// («12 paquetes») o «Sincronizando…» con 0. El dial del héroe gira en paralelo (FER-221).
    private struct SyncInline: View {
        let backfilling: Bool
        let chunks: Int
        let lastSyncedAt: Double?
        @Environment(\.instrumentoTheme) private var theme
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var spin = false

        var body: some View {
            HStack(spacing: NoopMetrics.space1) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 10))
                    .foregroundStyle(backfilling ? theme.verdict : theme.inkTertiary)
                    .rotationEffect(.degrees(spin && backfilling ? 360 : 0))
                    .animation(backfilling && !reduceMotion ? StrandMotion.spin() : nil, value: spin)
                label
            }
            .font(StrandFont.caption)
            .foregroundStyle(theme.inkTertiary)
            .lineLimit(1)
            .onAppear { spin = backfilling }
            .onChange(of: backfilling) { _, now in spin = now }
            .accessibilityElement(children: .combine)
        }

        @ViewBuilder private var label: some View {
            if backfilling {
                Text(chunks > 0 ? "\(chunks) packets" : String(localized: "Syncing…")).monospacedDigit()
            } else if let at = lastSyncedAt {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    Text(RelativeDateTimeFormatter().localizedString(
                        fromTimeInterval: at - context.date.timeIntervalSince1970))
                }
            } else {
                Text("Last sync — never")
            }
        }
    }

    /// Top utility row: compact date only — sync status moved to the grid footer (FER-233).
    @ViewBuilder private var utilityRow: some View {
        Text(shortDate)
            .font(StrandFont.overline)
            .tracking(StrandFont.overlineTracking)
            .foregroundStyle(theme.inkTertiary)
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
        VStack(alignment: .leading, spacing: NoopMetrics.space2) {
            HStack(alignment: .firstTextBaseline, spacing: NoopMetrics.space2) {
                HStack(alignment: .firstTextBaseline, spacing: NoopMetrics.space2) {
                    Image(systemName: "sparkles").font(.system(size: 10))
                    // Compacto (FER-202): la procedencia «base Apple Salud» se pliega aquí, en la misma línea
                    // de la etiqueta, en vez de un tercer renglón aparte — recorta alto para que Hoy quepa.
                    Text("Afinando con tu strap")
                        .font(StrandFont.caption)
                        .fixedSize(horizontal: false, vertical: true)   // wrap, never truncate, at large Dynamic Type
                    if baselineFromApple {
                        Text("· base Apple Salud")
                            .font(StrandFont.caption)
                            .foregroundStyle(theme.inkTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .foregroundStyle(theme.inkSecondary)
                Spacer(minLength: NoopMetrics.space2)
                Text("\(ownNights) de \(Baselines.minNightsTrust) noches")
                    .font(StrandFont.captionNumber)
                    .foregroundStyle(theme.inkSecondary)
                    .fixedSize()
                    .layoutPriority(1)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(theme.ink.opacity(0.10)).frame(height: 5)
                    Capsule().fill(theme.dataRecovery)
                        .frame(width: max(6, geo.size.width * CGFloat(ownNights) / CGFloat(Baselines.minNightsTrust)),
                               height: 5)
                }
            }
            .frame(height: 5)
        }
        .padding(.top, NoopMetrics.gap)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Confianza de calibración"))
        .accessibilityValue(Text(baselineFromApple
            ? "Afinando con tu strap, \(ownNights) de \(Baselines.minNightsTrust) noches. Tu base viene de Apple Salud."
            : "Afinando con tu strap, \(ownNights) de \(Baselines.minNightsTrust) noches."))
    }

    /// "Métricas de hoy" — la lectura intradía del día como rejilla 2×4 de 8 tiles (valor + Δ vs ayer),
    /// en el lenguaje «Instrumento diurno». Sustituye a la lista de tendencia 14d (FER-155/161): la
    /// tendencia es entre-días y migra a «Cuerpo»; aquí queda la foto de HOY. Cada tile es tematizado
    /// (papel `surface` + hairline, NUNCA el `NoopCard` oscuro), con etiqueta en tinta, valor en su
    /// color de dato y la variación contra ayer con semántica por métrica (mejora→`verdict`,
    /// empeora→`critical`, sin valencia/igual→`inkTertiary`). Recuperación NO es tile: ya es el numeral
    /// del héroe (no se duplica el número dominante). La tendencia 14d sigue accesible al tocar un tile
    /// (la hoja la trae). (FER-180)
    @ViewBuilder private var iosMetricsSection: some View {
        // Señales medidas: hoy gana, si no el valor fresco (hoy/ayer) o Apple Salud, badgeado cuando
        // viene de Apple para no pasarlo por una lectura del strap (misma lógica `resolveMeasured` que
        // la lista previa). El esfuerzo es strap-only (Apple no lo computa); los pasos, Apple-only.
        let hrvR    = resolveMeasured { $0.avgHrv }
        let rhrR    = resolveMeasured { $0.restingHr.map(Double.init) }
        let sleepR  = resolveMeasured { $0.totalSleepMin }
        let spo2R   = resolveMeasured { $0.spo2Pct }
        let strainT = repo.today?.strain
        // Pasos: sólo Apple Salud; acota a la ventana de 14 días para no mostrar pasos rancios bajo un
        // tile de "hoy".
        let stepsCutoff = Repository.localDayKey(Calendar.current.date(byAdding: .day, value: -13, to: Date()) ?? Date())
        let stepsFresh  = appleDays.last(where: { $0.day >= stepsCutoff })?.steps
        let stepsT      = stepsFresh.map(Double.init)
        let stressT     = stress?.score
        // Base para la media de 7 días de cada tile (FER-258): días anteriores a hoy, ordenados,
        // computada una vez por render (no por tile).
        let base = baselineDays()
        // Nudge para conectar Apple Salud sólo si no está conectado y falta alguna señal medida.
        let notConnected = health.auth != .authorized && health.auth != .unavailable
        let anyMeasuredMissing = hrvR == nil || sleepR == nil || rhrR == nil || spo2R == nil || stepsFresh == nil

        VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            // Encabezado compacto (FER-265): sello «Hoy» + sincronización inline (sube del pie), y el
            // pulso vivo como chip tocable a la derecha. El título grande de 28pt se retiró para que el
            // dato mande y la sección quepa. Ver `metricsHeader`.
            metricsHeader
            // Rejilla fija 2×8 (2 columnas, 8 tiles → 4 renglones), separación `NoopMetrics.gap`.
            LazyVGrid(columns: tileGrid, alignment: .leading, spacing: NoopMetrics.gap) {
                // Esfuerzo del día — carga del día, sin valencia (Δ en tinta neutra).
                metricTile(TodayMetricTile(
                    label: "Day Strain",
                    value: strainT.map { String(format: "%.1f", $0) } ?? "—",
                    valueColor: theme.dataStrain,
                    context: tileContext(today: strainT, history: history(base) { $0.strain },
                                         betterHigher: nil, deadband: 0.3) { String(format: "%.1f", $0) }
                )) { metricDetail = .strain(strainT) }
                // Sueño — dormir más es mejor.
                metricTile(TodayMetricTile(
                    label: "Sleep",
                    value: sleepR.map { sleepText($0.value) } ?? "—",
                    valueColor: theme.dataSleep,
                    fromApple: sleepR?.fromApple == true,
                    context: tileContext(today: sleepR?.value, history: history(base) { $0.totalSleepMin },
                                         betterHigher: true, deadband: 5) { sleepDeltaText($0) }
                )) { metricDetail = .sleep(sleepR.map { Int($0.value.rounded()) }) }
                // HRV — más alto es mejor.
                metricTile(TodayMetricTile(
                    label: "HRV",
                    value: hrvR.map { "\(Int($0.value.rounded()))" } ?? "—", unit: "ms",
                    valueColor: theme.dataHrv,
                    fromApple: hrvR?.fromApple == true,
                    context: tileContext(today: hrvR?.value, history: history(base) { $0.avgHrv },
                                         betterHigher: true, deadband: 1) { "\(Int($0.rounded())) ms" }
                )) { metricDetail = .hrv(hrvR?.value) }
                // Frecuencia cardíaca — promedio continuo del día. Sin Δ: no se guarda un promedio diurno
                // de "ayer" con qué comparar (decisión del dueño, FER-180).
                metricTile(TodayMetricTile(
                    label: "Heart Rate",
                    value: hrTodayAvg.map { "\($0)" } ?? "—", unit: String(localized: "bpm"),
                    valueColor: theme.dataHeart
                )) { metricDetail = .heartRate(avgBpm: hrTodayAvg) }
                // FC en reposo — más alta es PEOR.
                metricTile(TodayMetricTile(
                    label: "Resting HR",
                    value: rhrR.map { "\(Int($0.value.rounded()))" } ?? "—", unit: String(localized: "bpm"),
                    valueColor: theme.dataHeart,
                    fromApple: rhrR?.fromApple == true,
                    context: tileContext(today: rhrR?.value, history: history(base) { $0.restingHr.map(Double.init) },
                                         betterHigher: false, deadband: 1) { "\(Int($0.rounded())) \(String(localized: "bpm"))" }
                )) { metricDetail = .restingHR(rhrR.map { Int($0.value.rounded()) }) }
                // Oxígeno en sangre — más alto es mejor.
                metricTile(TodayMetricTile(
                    label: "Blood Oxygen",
                    value: spo2R.map { String(format: "%.0f", $0.value) } ?? "—", unit: "%",
                    valueColor: theme.dataSpO2,
                    fromApple: spo2R?.fromApple == true,
                    context: tileContext(today: spo2R?.value, history: history(base) { $0.spo2Pct },
                                         betterHigher: true, deadband: 0.5) { "\(Int($0.rounded())) %" }
                )) { metricDetail = .spo2(spo2R?.value) }
                // Pasos — sin meta (no existe en la app); más es mejor.
                metricTile(TodayMetricTile(
                    label: "Steps",
                    value: stepsT.map { intString($0) } ?? "—",
                    valueColor: theme.dataSteps,
                    fromApple: true,
                    context: tileContext(today: stepsT, history: history(base) { $0.steps.map(Double.init) },
                                         betterHigher: true, deadband: 100) { intString($0) }
                )) { metricDetail = .steps(stepsFresh) }
                // Estrés — más alto es PEOR; valor bandeado por nivel 0–3 (verde/ámbar/rojo).
                metricTile(TodayMetricTile(
                    label: "Stress",
                    value: stressT.map { String(format: "%.1f", $0) } ?? "—",
                    unit: stressT == nil ? nil : "/ 3",
                    valueColor: stressT.map(stressDataColor) ?? theme.inkTertiary,
                    context: tileContext(today: stressT, history: stressHistory,
                                         betterHigher: false, deadband: 0.1) { String(format: "%.1f", $0) }
                )) { metricDetail = .stress(stressT) }
            }
            // Pie de cuadrícula (FER-265): solo la leyenda de fuente, a la derecha. La sincronización se
            // mudó al encabezado (`SyncInline` junto al sello «Hoy»), así que el pie queda más limpio.
            HStack(spacing: NoopMetrics.space2) {
                Spacer(minLength: 0)
                HStack(spacing: NoopMetrics.space2) {
                    Text(verbatim: "W Strap")
                    Text("·")
                    HStack(spacing: NoopMetrics.space1) {
                        Image(systemName: "heart.fill").font(.system(size: 9))
                        Text("Apple Salud")
                    }
                }
                .font(StrandFont.caption)
                .foregroundStyle(theme.inkTertiary)
                .accessibilityHidden(true)
            }
            if notConnected && anyMeasuredMissing {
                Button { showDataSources = true } label: {
                    HStack(spacing: NoopMetrics.space2) {
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

    /// El encabezado compacto de «Métricas de hoy» (FER-265): sello «Hoy» (overline discreto) + la
    /// sincronización inline, y el chip de pulso vivo a la derecha. En Dynamic Type grande el chip baja
    /// a una segunda línea (`ViewThatFits`). El sello dice «hoy» sin repetir la palabra que ya traen la
    /// fecha de arriba y el veredicto; la hora vive en `SyncInline` como última sync, no como reloj.
    @ViewBuilder private var metricsHeader: some View {
        let sello = HStack(spacing: NoopMetrics.space1) {
            Text("Today").font(StrandFont.overline).tracking(StrandFont.overlineTracking)
                .foregroundStyle(theme.inkSecondary)
            Text(verbatim: "·").font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
            SyncInline(backfilling: live.backfilling, chunks: live.syncChunksThisSession,
                       lastSyncedAt: live.lastSyncedAt)
        }
        let chip = Group {
            if strapSeen {
                LivePulsePill(liveBpm: liveBpm, isLiveHR: isLiveHR, onTap: { showLiveMonitor = true })
            }
        }
        ViewThatFits(in: .horizontal) {
            HStack(spacing: NoopMetrics.space2) { sello; Spacer(minLength: NoopMetrics.space2); chip }
            VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                HStack(spacing: NoopMetrics.space1) { sello; Spacer(minLength: 0) }
                chip
            }
        }
    }

    /// La rejilla de «Métricas de hoy»: dos columnas iguales → 8 tiles en 4 renglones de 2.
    private let tileGrid = [GridItem(.flexible(), spacing: NoopMetrics.gap),
                            GridItem(.flexible(), spacing: NoopMetrics.gap)]

    /// Envuelve un tile en su `Button` tappable (todo el tile es objetivo) + feedback de pulsado, y abre
    /// el `MetricInfoSheet` de la métrica. El detalle trae la tendencia 14d (interino hasta «Cuerpo»).
    private func metricTile(_ tile: TodayMetricTile, open: @escaping () -> Void) -> some View {
        Button(action: open) { tile }
            .buttonStyle(TileButtonStyle(liftBorder: theme.hairlineStrong))
            .accessibilityHint(Text("Abre el detalle"))
    }

    /// Los días de base para la media de 7 días (FER-258): las filas del dashboard de display
    /// ANTERIORES a hoy (la misma fuente en capas que resuelve el valor de hoy y la de la tendencia
    /// 14d), ordenadas y acotadas a las recientes. Excluir hoy hace que el delta sea «hoy vs tu
    /// semana», no «hoy contra sí mismo». Se computa una vez por render, no por tile.
    private func baselineDays() -> [DailyMetric] {
        let todayKey = Repository.localDayKey(Date())
        return Array(repo.displayDays.filter { $0.day < todayKey }.sorted { $0.day < $1.day }.suffix(30))
    }

    /// Los ≤7 valores válidos más recientes de una métrica sobre los días de base: su ventana de media.
    private func history(_ days: [DailyMetric], _ pick: (DailyMetric) -> Double?) -> [Double] {
        Array(days.compactMap(pick).suffix(7))
    }

    /// La base de 7 días del estrés, del proxy diario 0–3 de `StressModel.fullTrend` excluyendo hoy
    /// (el último punto). El estrés no es campo de `DailyMetric`, así que va por su propia serie.
    private var stressHistory: [Double] {
        guard let trend = stress?.fullTrend, !trend.isEmpty else { return [] }
        return Array(trend.dropLast().suffix(7).map { $0.value })
    }

    /// El contexto de un tile (FER-258): compara hoy contra la media de 7 días de `history` y arma la
    /// mini-banda del rango típico. nil cuando no hay valor de hoy → el tile pone «—» sin pie. Con <4
    /// días válidos → `.building` (aún no hay base honesta). Dentro del `deadband` → `.equal`. Con
    /// `betterHigher` nil la métrica no tiene valencia (carga / FC): dirección en tinta neutra, sin
    /// pintar mejora/empeora.
    private func tileContext(today: Double?, history: [Double], betterHigher: Bool?, deadband: Double,
                             _ format: (Double) -> String) -> TileContext? {
        guard let t = today else { return nil }
        let valid = history.filter { $0.isFinite }
        guard valid.count >= 4 else { return .building }
        let mean = valid.reduce(0, +) / Double(valid.count)
        let band = bandViz(today: t, history: valid)
        let change = t - mean
        if abs(change) <= deadband { return .ready(change: .equal(color: theme.inkTertiary), band: band) }
        let up = change > 0
        let color: Color = betterHigher.map { (up == $0) ? theme.verdict : theme.critical } ?? theme.inkTertiary
        let mag = format(abs(change))
        return .ready(change: up ? .above(magnitude: mag, color: color)
                                 : .below(magnitude: mag, color: color), band: band)
    }

    /// Mapea p25, p75 y el valor de hoy a fracciones 0…1 sobre el rango real (min…max) de la ventana
    /// + hoy, para que el tick de la mini-banda quede visible aun cuando hoy cae fuera de la banda
    /// típica. La banda p25–p75 reusa `ReferenceRange.interquartile` (StrandDesign).
    private func bandViz(today: Double, history: [Double]) -> BandViz {
        let band = ReferenceRange.interquartile(history)
        let all = history + [today]
        let lo = all.min() ?? today
        let hi = all.max() ?? today
        let span = hi - lo
        func frac(_ v: Double) -> Double {
            guard span > 0 else { return 0.5 }
            return Swift.min(1, Swift.max(0, (v - lo) / span))
        }
        guard let band else { return BandViz(lowFrac: 0, highFrac: 1, tickFrac: frac(today)) }
        return BandViz(lowFrac: frac(band.lowerBound), highFrac: frac(band.upperBound), tickFrac: frac(today))
    }

    /// Δ de sueño en lenguaje de tiempo: «18 min» bajo una hora, «1h 5m» a partir de una.
    private func sleepDeltaText(_ minutes: Double) -> String {
        let m = Int(minutes.rounded())
        return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m) min"
    }

    /// El color del valor de Estrés por banda 0–3, en roles del tema (regla: color saturado solo en el
    /// dato). Bajo → `verdict`, medio → `warning`, alto → `critical`. Reusa `StressBand` (StressView).
    private func stressDataColor(_ score: Double) -> Color {
        switch StressBand(score: score) {
        case .low:    return theme.verdict
        case .medium: return theme.warning
        case .high:   return theme.critical
        }
    }

    /// El contexto de un tile vs su media de 7 días (FER-258): el cambio en lenguaje + la mini-banda
    /// del rango típico. `building` = aún no hay ≥4 días de base para una media honesta (sin flecha ni
    /// banda). La ausencia (sin valor de hoy) se modela con el Optional del tile: nil → no dibuja pie.
    private enum TileContext {
        case building
        case ready(change: TileChange, band: BandViz)
    }

    /// El cambio de hoy contra la media de 7 días, ya formateado + con color por polaridad. `equal` es
    /// «En tu media de 7 días» (dentro del deadband).
    private enum TileChange {
        case above(magnitude: String, color: Color)
        case below(magnitude: String, color: Color)
        case equal(color: Color)
    }

    /// Posiciones 0…1 (sobre el ancho del tile) para dibujar la mini-banda: el segmento típico
    /// p25–p75 (`lowFrac…highFrac`) y el tick del valor de hoy (`tickFrac`).
    private struct BandViz {
        let lowFrac: Double
        let highFrac: Double
        let tickFrac: Double
    }

    /// Un tile de «Métricas de hoy»: etiqueta (overline en tinta) · valor en color de dato + unidad ·
    /// mini-banda del rango típico (p25–p75) con el tick de hoy · pie partido — cambio vs tu media de
    /// 7 días (izquierda, FER-258) + badge de fuente (derecha): W = banda, ♥ = Apple Salud (FER-233).
    /// Tematizado con tokens de `InstrumentoTheme` sobre el papel `surface` con hairline — sin el
    /// `NoopCard` oscuro, que no lee sobre el papel claro. Lee el tema del entorno.
    private struct TodayMetricTile: View {
        let label: LocalizedStringKey
        let value: String
        var unit: String? = nil
        let valueColor: Color
        var fromApple: Bool = false
        var context: TileContext? = nil
        @Environment(\.instrumentoTheme) private var theme

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                // Etiqueta a UNA línea (FER-189): mantiene el tile parejo; un nombre largo (Frecuencia
                // cardíaca) se encoge un poco en vez de envolver a 2 líneas y crecer el alto.
                Text(label).instrumentoOverline()
                    .foregroundStyle(theme.inkSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: NoopMetrics.space1)
                HStack(alignment: .firstTextBaseline, spacing: NoopMetrics.space1) {
                    Text(value).font(StrandFont.number(22)).foregroundStyle(valueColor)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    if let unit {
                        Text(unit).font(StrandFont.subhead).foregroundStyle(theme.inkTertiary)
                    }
                }
                Spacer(minLength: NoopMetrics.space1)
                footer
            }
            .padding(.horizontal, NoopMetrics.gap).padding(.vertical, NoopMetrics.space2)
            // Alto fijo (FER-265): 88 → 76 — la mini-banda y el cambio caben en UNA línea de pie, así
            // que el tile vuelve a ser compacto y la sección no se desborda.
            .frame(maxWidth: .infinity, minHeight: 76, maxHeight: 76, alignment: .topLeading)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous)
                .strokeBorder(theme.hairline, lineWidth: 1))
            .accessibilityElement(children: .combine)
        }

        /// El pie del tile en UNA línea (FER-265): la mini-banda (flexible, izquierda) + el cambio vs la
        /// media + el badge de fuente. Con base → banda + cambio; sin base → texto «armando» / vacío,
        /// con la fuente siempre a la derecha. Antes la banda iba en su propio renglón (FER-258).
        @ViewBuilder private var footer: some View {
            HStack(spacing: NoopMetrics.space1) {
                switch context {
                case let .ready(change, band):
                    MetricBand(band: band).frame(maxWidth: .infinity)
                    changeText(change)
                case .building:
                    Text("Still building your average")
                        .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                case .none:
                    Spacer(minLength: 0)
                }
                sourceBadge
            }
        }

        /// El cambio vs la media: deadband → «En tu media»; subir/bajar → flecha + magnitud + «vs media».
        /// VoiceOver lee la frase completa «sobre/bajo tu media de 7 días» (la flecha va oculta).
        @ViewBuilder private func changeText(_ change: TileChange) -> some View {
            switch change {
            case let .above(magnitude, color): deltaLabel(up: true, magnitude: magnitude, color: color)
            case let .below(magnitude, color): deltaLabel(up: false, magnitude: magnitude, color: color)
            case let .equal(color):
                Text("At your average")
                    .font(StrandFont.caption).foregroundStyle(color)
                    .lineLimit(1).minimumScaleFactor(0.7).layoutPriority(1)
            }
        }

        private func deltaLabel(up: Bool, magnitude: String, color: Color) -> some View {
            HStack(spacing: NoopMetrics.space1) {
                Image(systemName: up ? "arrow.up" : "arrow.down")
                    .font(.system(size: 10, weight: .semibold))
                Text(verbatim: magnitude)
                Text("vs avg")
            }
            .font(StrandFont.caption)
            .foregroundStyle(color)
            .lineLimit(1).minimumScaleFactor(0.7).layoutPriority(1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(up ? "\(magnitude) above your 7-day average"
                                         : "\(magnitude) below your 7-day average"))
        }

        /// Badge de fuente (derecha) — solo cuando hay dato; siempre inkTertiary, nunca color de dato.
        @ViewBuilder private var sourceBadge: some View {
            if fromApple {
                Image(systemName: "heart.fill")
                    .font(.system(size: 10)).foregroundStyle(theme.inkTertiary)
                    .accessibilityLabel(Text("de Apple Salud"))
            } else if value != "—" {
                Text(verbatim: "W")
                    .font(.system(size: 9, weight: .semibold)).foregroundStyle(theme.inkTertiary)
                    .accessibilityLabel(Text("de strap"))
            }
        }
    }

    /// La mini-banda del tile (FER-258): el rango típico p25–p75 en `hairlineStrong` sobre la regla
    /// `hairline`, con un tick en `inkTertiary` donde cae el valor de hoy. Chrome en tinta pura — nunca
    /// color de dato (regla del idioma «Instrumento»). Decorativa para VoiceOver (el pie ya lo narra).
    private struct MetricBand: View {
        let band: BandViz
        @Environment(\.instrumentoTheme) private var theme

        var body: some View {
            GeometryReader { geo in
                let w = geo.size.width
                let segW = Swift.max(2, w * (band.highFrac - band.lowFrac))
                ZStack(alignment: .leading) {
                    Capsule().fill(theme.hairline)
                        .frame(height: 2).frame(maxHeight: .infinity, alignment: .center)
                    Capsule().fill(theme.hairlineStrong)
                        .frame(width: segW, height: 2)
                        .offset(x: w * band.lowFrac)
                        .frame(maxHeight: .infinity, alignment: .center)
                    RoundedRectangle(cornerRadius: 1).fill(theme.inkTertiary)
                        .frame(width: 2, height: 8)
                        .offset(x: Swift.min(w - 2, Swift.max(0, w * band.tickFrac - 1)))
                }
            }
            .frame(height: 8)
            .accessibilityHidden(true)
        }
    }

    /// Realce al pulsar (FER-213): la afordancia de «tocable» de los tiles de Hoy. En reposo el tile NO
    /// lleva marca; al pulsar se ELEVA hacia el toque —escala ~1.03 + el borde pasa a `hairlineStrong`—
    /// en vez del darken anterior (FER-180). Plano, sin sombra (regla del idioma «Instrumento»). El
    /// zoom-morph de apertura de FER-210 se revirtió; esto conserva sólo el realce, que el dueño aprobó.
    private struct TileButtonStyle: ButtonStyle {
        let liftBorder: Color
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .overlay(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous)
                    .strokeBorder(configuration.isPressed ? liftBorder : Color.clear, lineWidth: 1))
                .scaleEffect(configuration.isPressed ? 1.03 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.72), value: configuration.isPressed)
        }
    }

    /// On-device readiness for the verdict hero (same engine the macOS `readinessSection` uses).
    /// Memoizado en `memoReadiness` (FER-172): cae a un cálculo en línea solo si el memo aún es nil
    /// (el primer body antes de que `.task` lo siembre), nunca en el camino caliente de cada render.
    private var readiness: ReadinessEngine.Readiness {
        memoReadiness ?? ReadinessEngine.evaluate(days: repo.days, today: Repository.localDayKey(Date()))
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

    /// Compact localized date for the utility row, e.g. "THU 12 JUN" — context without the greeting.
    private static let shortDateFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = .autoupdatingCurrent
        f.setLocalizedDateFormatFromTemplate("EEEdMMM")
        return f
    }()
    private var shortDate: String {
        // Always the real calendar day — never the last data row's day, or the header
        // looks "stuck" on yesterday until today's row exists (FER-151).
        Self.shortDateFmt.string(from: Date()).uppercased()
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
                    trailing: v.last.map { "\(Int($0.rounded())) \(String(localized: "bpm"))" }
                ) {
                    TrendChart(
                        points: hrPoints,
                        gradient: Gradient(colors: [StrandPalette.metricRose.opacity(0.55), StrandPalette.metricRose]),
                        valueRange: hrRange(v),
                        showsArea: true,
                        height: NoopMetrics.chartHeight,
                        valueFormat: { "\(Int($0.rounded())) \(String(localized: "bpm"))" },
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
                    caption: String(localized: "bpm"),
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
        // Siembra el veredicto + los conteos derivados de HRV una sola vez por refresh, ANTES de los
        // awaits de abajo, para que el body deje de recalcular `ReadinessEngine.evaluate` en cada frame
        // (FER-172). `recomputeDerived()` es síncrono y lee `repo.days`/`today`/`appleHealthDays`, ya
        // disponibles sin esperar las consultas de sparklines.
        recomputeDerived()
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
        // Stored daily "stress" series (0–3) — the model prefers it, else derives from RHR/HRV. (FER-180)
        async let stressRows = repo.series(key: "stress", source: "my-whoop")

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
        // Build today's stress model from the day rows + stored series (nil when there's no usable
        // signal yet — the tile then placeholders "—"). Reads `displayDays` (Apple-health fallback,
        // FER-149) so a strap-partial night still derives, and anchors "today" to the local day so a
        // UTC-bucketed "tomorrow" row (FER-226) can't blank the tile.
        stress = StressModel(days: repo.displayDays, stored: await stressRows, todayKey: Repository.localDayKey(Date()))
    }

    // MARK: - 14-day trend loader (all platforms)

    /// Builds the trailing 14-day trend from the DISPLAY dashboard rows (`repo.displayDays`) — the same
    /// layered source the Today tiles draw their values from (`resolveMeasured`/`baselineDays`): Apple Health is the base,
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
        // Stress isn't a stored `DailyMetric` field — it's the derived 0–3 proxy the tile's
        // `StressModel` already computed. Reuse that history so its info sheet shows the same 14-day
        // trend as every other metric; without this branch it fell through to `default → nil` and the
        // sheet rendered no chart at all (stress has no dedicated curve like strain / heart rate do).
        if id == "stress" {
            return { self.stressTrend(window: 14) }
        }
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

    /// Trailing-window slice of the derived 0–3 stress proxy the tile already computed
    /// (`StressModel.fullTrend`). Stress has no stored `DailyMetric` field, so it can't go through
    /// `loadTrend(pick:)`; we reuse the model's own daily history. Windowed by date (not just
    /// `.suffix`) so a stale import doesn't render months-old points under the sheet's "Last 14 days"
    /// label — the same trailing-window guard the other trends use (#23).
    private func stressTrend(window: Int = 14) -> [TrendPoint] {
        guard let trend = stress?.fullTrend else { return [] }
        let cutoff = Calendar.current.date(byAdding: .day, value: -window, to: Date()) ?? Date()
        return trend.filter { $0.date >= cutoff }
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

    // MARK: - Loaders for the rich vital Detalle drilled into via "Ver más" (FER-251)
    //
    // The unified Detalle de Métrica (FER-185) for HRV / Resting HR needs the same three loaders Cuerpo
    // feeds it, so the screen is identical from either tab. They read the same layered source the rows
    // already use (`repo.displayDays` / `resolveMeasured`); mirror of `CuerpoView`.

    /// Today's step total from the Apple daily rows, within the same freshness window the tile uses, so
    /// «Ver más» opens the steps detail on the value the tile shows. (FER-254)
    private var freshSteps: Int? {
        let cutoff = Repository.localDayKey(Calendar.current.date(byAdding: .day, value: -13, to: Date()) ?? Date())
        return appleDays.last(where: { $0.day >= cutoff })?.steps
    }

    /// The FULL daily series (oldest → newest) for a vital — the detail carries its own range selector,
    /// so it needs all history, not just the trailing window.
    private func vitalSeries(for key: String) -> [(day: String, value: Double)] {
        let pick: (DailyMetric) -> Double?
        switch key {
        case "hrv":       pick = { $0.avgHrv }
        case "rhr":       pick = { $0.restingHr.map(Double.init) }
        case "resp_rate": pick = { $0.respRateBpm }
        case "spo2":      pick = { $0.spo2Pct }
        case "steps":     pick = { $0.steps.map(Double.init) }
        default:          return []
        }
        return repo.displayDays
            .compactMap { row in pick(row).map { (row.day, $0) } }
            .sorted { $0.day < $1.day }
    }

    /// The gated, directional "Qué la mueve" findings (FER-209), computed from the user's own history.
    /// Empty → the detail hides the block.
    private func whatMovesItFindings(for key: String) -> [WhatMovesItFinding] {
        WhatMovesItEngine.findings(forMetricKey: key, days: repo.displayDays)
    }

    /// Last night's companion vitals (respiration + resting HR) for the detail's "Vitales de la noche".
    private func loadNightVitals() async -> MetricDetailScreen.NightVitals {
        MetricDetailScreen.NightVitals(
            respiration: resolveMeasured { $0.respRateBpm }?.value,
            restingHR: resolveMeasured { $0.restingHr.map(Double.init) }?.value)
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

    private static let workoutDateFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = .autoupdatingCurrent
        f.setLocalizedDateFormatFromTemplate("dMMM")
        return f
    }()
    private func workoutCaption(_ w: WorkoutRow) -> String {
        let date = Self.workoutDateFmt.string(from: Date(timeIntervalSince1970: TimeInterval(w.startTs)))
        if let hr = w.avgHr { return "\(date) · \(hr) \(String(localized: "bpm"))" }
        return date
    }

    /// Thousands-grouped integer string (steps / calories).
    private static let intFmt: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f
    }()
    private func intString(_ v: Double) -> String {
        Self.intFmt.string(from: NSNumber(value: v)) ?? "\(Int(v.rounded()))"
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
