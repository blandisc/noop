import SwiftUI
import StrandDesign
import StrandAnalytics
import StrandTraining
import WhoopStore
import Foundation

/// Publica el offset vertical del tope del contenido de Hoy para el pull-to-refresh propio (FER-222).
/// En el tope vale 0; al jalar hacia abajo (overscroll) crece > 0; con scroll normal es < 0. Solo se
/// conserva el último valor (un único productor), así que `reduce` toma el más reciente.
private struct TodayScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

// MARK: - Hoy «Instrumento diurno» (FER-135 redesign)
//
// The home screen, written in the «Instrumento diurno» language (warm paper, theme by hour,
// one dominant number, color only in the datum, hierarchy by space — see DESIGN.md §8).
//
// Composition (top → bottom), all inside `iosBody`:
//   (a) HEADER — compact date overline + strap battery (`headerBlock`).
//   (b) DIAL   — the fixed instrument head (`dialHeader`): a 24h `DiurnalDial` with the recovery numeral
//                concentric inside it. `heroNumeral`/`heroState` still pick the numeral per mode (verdict /
//                Apple-seeded base / calibrating / waiting). The verdict WORD moved out of the dial.
//   (c) PAGER  — a 2-page horizontal pager (`todayPager`) below the dial, with page dots (FER-465):
//                · Page 1 (`verdictPage`) — the day's verdict in words (`heroBody` + `heroFooter`).
//                · Page 2 (`metricsPage`) — «Métricas de hoy» (`iosMetricsSection`): a 2×4 grid of themed
//                  tiles, each value in its data colour with a Δ-vs-7-day-average and a p25–p75 mini-band.
//
// The dark legacy dashboard (RecoveryRing/StatTile grid/workouts) was removed once the redesign
// shipped; this file is now «Instrumento»-only.

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
    /// El tema activo de «Instrumento diurno» (FER-135). El `iosBody` lo ancla al papel de día con
    /// `.instrumentoTheme(.base)`; cada sub-vista lo lee de aquí para colorear en TINTA del tema.
    @Environment(\.instrumentoTheme) private var theme
    /// Presents the live beat-to-beat monitor (LiveView) over Today when the calibration card's
    /// "See it beat by beat" affordance is tapped.
    @State private var showLiveMonitor = false
    /// Live Apple Health bridge (iOS only). Today reads `health.auth` to nudge the user to connect
    /// Apple Salud when the measured Key Metrics are empty; `showDataSources` presents Data Sources
    /// so they can connect in one tap instead of hunting through the More tab. (FER-94)
    @EnvironmentObject var health: HealthKitBridge
    /// Tab switcher — the «Explóralo en el Coach» handoff from the Detalle de Estrés (FER-452, mirrors Cuerpo).
    @EnvironmentObject var tabRouter: TabRouter
    @State private var showDataSources = false
    /// Cuenta cada pull-to-refresh para disparar la háptica declarativa (`.sensoryFeedback`) al
    /// provocar el gesto de sincronización (FER-204).
    @State private var syncHaptic = 0

    /// El usuario ya hizo al menos un pull-to-sync con strap (FER-270): apaga para siempre la pista
    /// «Desliza para sincronizar» del héroe — ya aprendió el gesto. Persiste entre lanzamientos.
    @AppStorage("today.didFirstPullSync") private var didFirstPullSync = false

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
    /// Enciende el rebote de la pista del pull-to-refresh (FER-293). Se pone en `true` al aparecer;
    /// con la animación `bob` (repeatForever autoreverses) eso basta para que el chevron oscile.
    @State private var hintBob = false
    #endif

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

    // «Hoy en tu plan» — el bloque puente con Entrenar al pie del brief (FER-613). Cargados en `loadAll`
    // desde el store: si hay split, la rutina de hoy (nil = descanso) y la racha COMPARTIDA con Entrenar.
    @State private var hasSplit = false
    @State private var todayRoutineName: String? = nil
    @State private var trainingStreak = 0

    // «La conexión de hoy» — la correlación más relevante del día (FER-614). Cargados en `loadAll` vía el
    // loader compartido `InsightsProvider`, así la conexión del brief == la que muestra Patrones (mismo FDR).
    @State private var insights: [Insight] = []

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
    /// The «mapa del día» driver (EventKit + intraday curve), built fresh when the Detalle de Estrés opens
    /// from Today — so it shows the SAME chart + moments + patterns as Cuerpo (FER-452).
    @State private var stressDayMap: CalendarDayMap? = nil
    @State private var metricSpec: MetricDetailSpec? = nil

    /// Página activa del pager de 2 páginas (FER-465): 0 = veredicto (Daily Brief) · 1 = «Métricas de hoy».
    /// Optional porque es el binding de `.scrollPosition(id:)` (puede quedar nil a media transición); los
    /// page dots lo leen con `?? 0`. Arranca en la página 1 del veredicto.
    @State private var pagerPage: Int? = 0

    /// Ya se aplicó UNA vez el aterrizaje inicial en Métricas cuando no había veredicto (FER-475): de
    /// madrugada, sin lectura de hoy, el pager abre en la página 2 (Métricas) porque el Brief aún no tiene
    /// nada que decir. Una sola vez por aparición — luego respeta dónde deslice el usuario y no re-salta
    /// cuando llega el veredicto matutino.
    @State private var didAutoLandMetrics = false

    /// Arma el latido del punto «Ahora» del Daily Brief (FER-549/handoff): al aparecer pasa a `true` con una
    /// animación `repeatForever`, de modo que el halo concéntrico pulse. Estático bajo Reduce Motion.
    @State private var briefDotPulse = false

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
    /// El nivel del veredicto de AYER, memoizado (FER-475): da continuidad en la página 1 «en espera»
    /// («Ayer cerraste en Equilibrado») cuando aún no hay lectura de hoy. `nil`/insufficient → no se muestra.
    @State private var memoYesterdayLevel: ReadinessEngine.Level?

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
        // FER-475: el veredicto de ayer, para la línea de continuidad de la página 1 «en espera». Una vez
        // por refresh (no por frame), junto al de hoy.
        let yKey = Repository.localDayKey(Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date())
        memoYesterdayLevel = ReadinessEngine.evaluate(days: repo.days, today: yKey).level
        #if DEBUG
        // FER-172: prueba de que el veredicto se recalcula UNA vez por refresh. En scroll/animación/
        // ticks de HR esta línea NO debe reaparecer; solo sale una vez por `seq`. Compila fuera en release.
        print("[FER-172] readiness recomputed · seq=\(repo.refreshSeq) · days=\(repo.days.count)")
        #endif
    }

    /// Los conteos memoizados; cae a un cálculo en línea solo el primer frame (memo aún nil).
    private var hrvCounts: DerivedHrvCounts { memoCounts ?? computeHrvCounts() }

    /// El nivel del veredicto de ayer, o `nil` si no hubo veredicto (sin historial suficiente). Para la
    /// línea «Ayer cerraste en …» de la página 1 «en espera» (FER-475).
    private var yesterdayVerdict: ReadinessEngine.Level? {
        guard let l = memoYesterdayLevel, l != .insufficient else { return nil }
        return l
    }

    /// La explicación honesta para la hoja «¿Por qué?» (la «i») cuando NO hay lectura de hoy (FER-475):
    /// QUÉ falta según el estado real, en vez del genérico «¿Por qué preparación?» con el chip gris. `nil`
    /// con veredicto → la hoja muestra el porqué normal.
    private var whyEmptyExplanation: LocalizedStringKey? {
        let state = heroState
        guard state != .verdict else { return nil }
        switch state {
        case .calibrating:
            return "Tu base aún se afina: con un par de noches más de sueño sincronizado con la banda, tu veredicto del día empieza a aparecer aquí."
        case .downloading:
            return "Estamos descargando tu noche. En cuanto termine el sync, calculamos tu veredicto del día y aparece aquí."
        default:   // waiting / importedBaseline
            return strapSeen
                ? "Tu lectura del día sale de cómo dormiste. Aún no hay datos de esta noche — cuando duermas con tu banda y sincronices en la mañana, tu veredicto aparece aquí."
                : "Conecta tu banda o Apple Salud y, con tu sueño de la noche, tu veredicto del día empieza a leerse aquí."
        }
    }

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
            // «Hoy» nunca pedía la carga del strap por su cuenta: dependía del sondeo del keep-alive
            // (cada ~60 s, y SUSPENDIDO durante el offload), así que tras el sync matutino la batería
            // quedaba en `nil` y el header no la mostraba. Refresca la lectura al aparecer y cuando el
            // enlace queda libre —recién conectado o terminó el backfill—, respetando no picar al strap
            // a mitad del offload (la WHOOP 4.0 la trae por GET_BATTERY_LEVEL, el mismo comando que ya
            // usan el keep-alive y Live; no se agrega ninguno nuevo al set seguro).
            .task(id: "\(live.connected)|\(live.backfilling)") { refreshStrapBatteryIfIdle() }
            .toolbar {
                ToolbarItem {
                    Button { showingSupport = true } label: {
                        // Rojo del TEMA, no `StrandPalette.metricRose` (token del sistema oscuro #FF4F73,
                        // ≈2.7:1 sobre el papel claro de Hoy → falla 3:1 no-textual y rompe la disciplina
                        // «Instrumento»). `theme.critical` es un rojo contenido theme-native (4.9:1) que
                        // sigue leyéndose como corazón. (FER-273)
                        Image(systemName: "heart.fill")
                            .foregroundStyle(theme.critical)
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
                WhyVerdictSheet(readiness: readiness, theme: theme,
                                sleepMinutes: repo.today?.totalSleepMin,
                                emptyStateExplanation: whyEmptyExplanation,
                                isRecoveryEstimated: repo.isRecoveryEstimated(Repository.localDayKey(Date())),
                                recoveryConfidence: repo.recoveryConfidence(Repository.localDayKey(Date())))
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
                // SAME rich detail Cuerpo presents — the «mapa del día» (chart + moments) + patterns,
                // wired through the shared `StressDayMapPresenter` (FER-452). The cross-day pattern line
                // is read-only (the Coach handoff was removed, Pase v2 #7).
                StressDetailScreen(theme: theme, model: item.model, dayMap: stressDayMap,
                                   patternsLoader: { await StressDayMapPresenter.timeOfDayPatterns(
                                       repo: repo, maxHR: model.profile.hrMax, restingHR: stressRestingHR) },
                                   eventPatternsLoader: { await StressDayMapPresenter.eventPatterns(
                                       repo: repo, map: stressDayMap) })
            }
            .sheet(item: $metricSpec) { spec in
                MetricDetailScreen(
                    spec: spec,
                    depth: .full,
                    theme: theme,
                    // FER-487: seal today's datum «Apple» when it came from Apple Health, matching the tile.
                    todayFromApple: todayVitalFromApple(spec.descriptor.key),
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
        // ¿El valor que se muestra vino de Apple Salud (no del strap)? MISMA resolución que el tile de Hoy,
        // por métrica: HRV/FCrep/SpO₂ usan `latestFromDisplay` (el último de la gráfica, FER-546) y Sueño
        // `resolveMeasured(todayOnly:)` — así el badge coincide con el valor mostrado. Los pasos son
        // Apple-only. Strap-only (esfuerzo, FC, recuperación, estrés) → false. Sólo se badgea cuando hay valor.
        let fromApple: Bool = {
            switch info.id {
            case "steps": return true
            case "hrv":   return latestFromDisplay { $0.avgHrv }?.fromApple == true
            case "rhr":   return latestFromDisplay { $0.restingHr.map(Double.init) }?.fromApple == true
            // Sueño es day-scoped (todayOnly, FER-341): la tarjeta muestra SÓLO el valor de hoy, así que el
            // badge de fuente debe resolverse igual. Sin todayOnly caía al strap de AYER (no-Apple) y el
            // corazón desaparecía dentro de la tarjeta aunque el número mostrado SÍ venía de Apple Salud.
            case "sleep": return resolveMeasured(todayOnly: true) { $0.totalSleepMin }?.fromApple == true
            case "spo2":  return latestFromDisplay { $0.spo2Pct }?.fromApple == true
            default:      return false
            }
        }()
        return MetricInfoSheet(
            info: info,
            theme: theme,
            appleConnectHint: appleCapable && notConnected && info.displayValue == "—",
            appleSource: fromApple && info.displayValue != "—",
            strainCurveLoader: info.id == "strain" ? { await loadStrainCurve() } : nil,
            heartRateCurveLoader: info.id == "heart_rate" ? { hrPoints } : nil,
            trendLoader: trendLoader(for: info.id),
            onSeeMore: seeMoreAction(for: info.id),
            levelsSeriesLoader: levelsSeriesLoader(for: info.id)
        )
    }

    /// Today's resting HR for the «mapa del día» (resolved, with the engine's default as the floor) — the
    /// one input the shared `StressDayMapPresenter` can't derive itself. Same resolution Cuerpo uses. (FER-452)
    private var stressRestingHR: Double {
        resolveMeasured { $0.restingHr.map(Double.init) }?.value ?? StrainScorer.defaultRestingHR
    }

    /// The "Ver más" hand-off for a metric: returns nil only for metrics without a rich detail
    /// destination (the `default` case). Otherwise returns a closure that defers presenting
    /// the rich detail until the summary dismisses (`pendingSeeMore` + `metricDetail = nil`). The detail
    /// reuses the SAME static factories / specs Cuerpo uses, so it's identical from both tabs. (FER-251)
    private func seeMoreAction(for id: String) -> (() -> Void)? {
        let present: (() -> Void)?
        switch id {
        case "recovery":
            present = {
                recoveryDetail = RecoveryDetailItem(model: RecoveryDetailModel.build(repo: repo))
            }
        case "sleep":
            present = {
                sleepDetail = SleepDetailItem(model: SleepDetailModel.build(
                    days: repo.days, sleeps: repo.sleeps, appleSleeps: repo.appleSleeps,
                    importedSleep: repo.importedSleep,
                    appleHealthDays: repo.appleHealthDays, loaded: repo.loaded,
                    todayKey: Repository.localDayKey(Date())))
            }
        case "strain":
            present = {
                strainDetail = StrainDetailItem(model: StrainDetailModel.build(
                    days: repo.days, today: repo.today, loaded: repo.loaded))
            }
        case "stress":
            present = {
                stressDayMap = StressDayMapPresenter.make(
                    repo: repo, maxHR: model.profile.hrMax, restingHR: stressRestingHR)
                stressDetail = StressDetailItem(model: stress)
            }
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
    // Escrito en el lenguaje «Instrumento diurno» (FER-135): tema claro de papel cálido
    // (`.instrumentoTheme(.base)`), un solo número dominante (la recuperación), jerarquía por ESPACIO
    // (sin card-in-card), y COLOR SOLO en el dato — el número de recuperación, la palabra del veredicto
    // y la línea+punto de cada gráfica; todo lo demás (labels, valores, dial, iconos, chevrons,
    // overlines) en TINTA del tema. Conserva toda la lógica de estados/datos previa; solo reacomoda y
    // recolorea.
    //
    // El tema se aplica UNA vez envolviendo el iosBody (acotado a TodayView, NUNCA en RootTabView). El
    // `SolarWindow` (de `SolarClock`) ya solo alimenta el `DiurnalDial`. Cada sub-vista lee
    // `@Environment(\.instrumentoTheme)`. (FER-398 retiró el tinte por hora del día.)

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
        // tematizado). El tema se ancla aquí al papel de día `.base`, acotado a TodayView (NUNCA en
        // RootTabView): todo el árbol de abajo lee `\.instrumentoTheme`. FER-398 retiró el tinte por hora;
        // el momento del día ya solo vive en el `DiurnalDial` (posición del «ahora», arco solar, sueño).
        .background(PaperBackground())
        .instrumentoTheme(.base)
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
            // without sending the user to dig through the More tab. Reskinned to the light «Instrumento»
            // language (FER-338): a light sheet with its own NavigationStack (so «Ver datos importados»
            // pushes the Apple Health viewer), the theme injected at the root (it doesn't cross the
            // `.sheet` boundary, FER-162). A sheet starts a fresh environment branch, so re-inject the
            // objects DataSourcesView needs (same pattern as the cover above).
            NavigationStack {
                DataSourcesView()
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbarBackground(theme.paper, for: .navigationBar)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showDataSources = false }
                                .foregroundStyle(theme.ink)
                        }
                    }
            }
            .instrumentoTheme(theme)
            .environmentObject(model)
            .environmentObject(repo)
            .environmentObject(live)
            .environmentObject(health)
            .preferredColorScheme(.light)
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
                // Cabecera FIJA del instrumento (FER-465): fecha + alerta + dial 24h con numeral. Sigue
                // dentro del scroll vertical, así que el pull-to-refresh propio (FER-222) NO cambia. La
                // palabra del veredicto ya NO vive aquí: se mudó a la página 1 del pager (`verdictPage`).
                VStack(alignment: .leading, spacing: NoopMetrics.sectionGapCompact) {
                    headerBlock
                    HealthAlertBanner()
                    dialHeader
                }
                // Caption «toca para saber por qué» bajo el dial (handoff): SOLO en la vista Brief con
                // veredicto. En los demás estados/página la página 1 ya trae su copy honesto.
                if (pagerPage ?? 0) == 0, heroState == .verdict { whyCaption }
                // Gap FLEXIBLE dial→pager: el sobrante vertical se reparte por igual ARRIBA y abajo del
                // pager (este `Spacer` + el de abajo), así la rejilla de métricas baja a ocupar la pantalla
                // en vez de quedar pegada al dial con todo el aire desperdiciado al fondo. El dial sigue
                // fijo arriba y los page dots fijos cerca del dock; solo el bloque del pager flota al
                // centro. El mínimo conserva el gap compacto de antes para que en pantalla chica (contenido
                // que llena o excede) no se separe de más y el scroll siga igual.
                Spacer(minLength: NoopMetrics.sectionGapCompact)
                // Pager horizontal de 2 páginas (FER-465): ① el veredicto del día en palabras · ② «Métricas
                // de hoy» tal cual. Ancho de página = ancho de contenido (proxy − screenPadding lateral) para
                // que el snap pagine de a una. Ejes ortogonales al scroll vertical → el swipe horizontal y el
                // pull-to-refresh no se pelean.
                todayPager(width: max(0, proxy.size.width - NoopMetrics.screenPadding * 2))
                // La otra mitad del sobrante vive AQUÍ: mantiene los page dots al fondo, cerca del dock,
                // mientras el `Spacer` de arriba baja la rejilla al centro.
                Spacer(minLength: NoopMetrics.space2)
                todayPageDots
            }
            // FER-274/FER-293: la pista del pull-to-refresh (chevron + microcopy) flota en el TOPE como
            // overlay — NO ocupa alto de layout, así que no empuja el héroe ni desborda la pantalla (a
            // diferencia del renglón de texto de FER-270). Centrada arriba, donde se inicia el tirón.
            // Entra/sale con un desvanecido; estática bajo Reduce Motion.
            .overlay(alignment: .top) {
                if showsSyncHint { syncHint }
            }
            .animation(reduceMotion ? nil : StrandMotion.fade, value: showsSyncHint)
            // Inset superior `gap` (FER-202): el héroe queda alto pero respira.
            .padding(.horizontal, NoopMetrics.screenPadding)
            // Margen inferior compacto (FER-475): los page dots (último elemento) quedan pegados al dock,
            // no flotando con 24pt de aire. La rejilla de métricas mantiene su aire propio (cards + gap).
            .padding(.bottom, NoopMetrics.space2)
            .padding(.top, NoopMetrics.space2)
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
    /// de FER-204; el offload largo sigue en segundo plano, reflejado en el dial girando + la cápsula de pulso.
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
        // FER-293: el usuario ya ejecutó un pull-to-sync → ya aprendió el gesto; retira el microcopy y el
        // rebote (con desvanecido salvo Reduce Motion). El chevron permanece como cue sutil, así el gesto
        // sigue siendo descubrible (a diferencia de FER-270, que lo apagaba por completo para siempre).
        if !didFirstPullSync {
            withAnimation(reduceMotion ? nil : StrandMotion.fade) { didFirstPullSync = true }
        }
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

    /// Pide una lectura de batería del strap SOLO cuando el enlace está libre (conectado y sin offload
    /// en curso) — nunca a mitad del backfill, igual que el keep-alive evita picar al strap entonces
    /// (`guard !backfilling`, BLEManager). `refreshBattery()` es agnóstico al modelo (4.0 → comando
    /// GET_BATTERY_LEVEL; 5/MG → lectura 0x2A19) y no introduce ningún comando nuevo.
    @MainActor private func refreshStrapBatteryIfIdle() {
        guard live.connected, !live.backfilling else { return }
        model.getBattery()
    }

    /// Recovery score driving the hero numeral (0–100). nil while calibrating.
    private var recoveryScore: Int? { repo.today?.recovery.map { Int($0.rounded()) } }

    /// El lienzo: el papel del tema, leído DENTRO del subárbol tematizado para que también recolore por
    /// hora. (El `.background(theme.paper)` del propio `iosBody` resolvería contra el tema base, no el de
    /// la hora — por eso esta vista hija lo lee del entorno.)
    private struct PaperBackground: View {
        @Environment(\.instrumentoTheme) private var theme
        var body: some View {
            // Papel con profundidad (handoff «Hoy · Estados»): un gradiente radial cálido —pozo de luz
            // arriba-centro (`paperHi`), papel medio y un borde un poco más hondo (`paperLo`)— en vez del
            // relleno plano de antes. Los stops se derivan del `paper` vivo, así que el lienzo también
            // amanece/anochece por hora. Elíptico (no circular) para cubrir el alto del teléfono como el
            // `radial-gradient(125% 78% at 50% 16%)` del handoff.
            EllipticalGradient(
                stops: [
                    .init(color: theme.paperHi, location: 0),
                    .init(color: theme.paper,   location: 0.44),
                    .init(color: theme.paperLo, location: 1.0)
                ],
                center: UnitPoint(x: 0.5, y: 0.16),
                startRadiusFraction: 0,
                endRadiusFraction: 0.9
            )
            .ignoresSafeArea()
        }
    }

    /// Ventana solar (amanecer/atardecer) para HOY, en horas reloj, derivada de `SolarClock` para la
    /// zona horaria actual SIN GPS ni permisos. Mapeada al `SolarWindow` de StrandDesign que consume
    /// el `DiurnalDial` para su arco solar. `nil` en los casos polares (sin cruce de horizonte).
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
        // Hogar 1 de estado/procedencia (FER-278): UNA línea arriba reúne todo el estado del
        // instrumento — fecha a la izquierda; a la derecha la sincronización (sube del encabezado de
        // métricas, FER-265) + la batería del strap. Antes la frescura de sync vivía a media pantalla y
        // la batería suelta arriba-derecha; aquí quedan juntas como «qué tan al día está tu instrumento».
        HStack(alignment: .center, spacing: NoopMetrics.space2) {
            utilityRow
            // FER-590: la batería del strap va junto a la fecha (izquierda), con un divisor hairline entre
            // ambas; la píldora de pulso queda sola a la derecha. El acento del glifo va POR NIVEL
            // (`theme.batteryColor`: verde / ámbar ≤20% / rojo ≤10%); el «%» en tinta. Sin batería no se
            // muestra ni el divisor.
            if let pct = live.batteryPct {
                Rectangle().fill(theme.hairlineStrong)
                    .frame(width: 1, height: 11)
                    .accessibilityHidden(true)
                HStack(spacing: 4) {
                    Image(systemName: batteryIcon(pct: pct, charging: live.charging == true))
                        .font(StrandFont.overline)
                        .foregroundStyle(theme.batteryColor(forLevel: pct))
                    Text("\(Int(pct.rounded()))%")
                        .font(StrandFont.overline)
                        .tracking(StrandFont.overlineTracking)
                        .foregroundStyle(theme.inkTertiary)
                }
                .accessibilityLabel(live.charging == true
                    ? Text("Batería del strap: \(Int(pct.rounded()))%, cargando")
                    : Text("Batería del strap: \(Int(pct.rounded()))%"))
            }
            Spacer(minLength: NoopMetrics.space2)
            // La cápsula de pulso se mantiene SIEMPRE (reposo y sync); solo cambia su texto de frescura
            // (⟳ hace 30 s → ⟳ Sincronizando… / N paquetes). Sin strap visto no hay cápsula. (FER-550/583)
            if strapSeen || live.backfilling || live.draining {
                pulsePill
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: Text("Sincronizar")) { triggerPullSync() }
    }

    /// SF Symbol del nivel de batería. Al CARGAR devuelve `battery.100.bolt` — el ÚNICO glifo
    /// batería-con-rayo que SF Symbols realmente trae. Las variantes parciales (`battery.75/.50/.25.bolt`)
    /// NO existen, y `Image(systemName:)` no dibuja NADA con un nombre desconocido → por eso el ícono
    /// desaparecía al cargar por debajo de 75%. El rayo comunica «cargando»; el nivel exacto lo lleva el
    /// «%» de al lado.
    private func batteryIcon(pct: Double, charging: Bool) -> String {
        if charging { return "battery.100.bolt" }
        switch pct {
        case 75...:   return "battery.100"
        case 50..<75: return "battery.75"
        case 25..<50: return "battery.50"
        default:      return "battery.25"
        }
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
        case downloading                // pre-veredicto: la banda está drenando el historial de la noche (FER-286)
        case importedBaseline           // pre-veredicto: base sembrada por Apple Health (FER-106)
        case calibrating(nights: Int)   // pre-veredicto: strap visto, ownNights < seed
        case waiting                    // pre-veredicto: sin strap nunca, o base propia sin lectura de hoy
    }

    private var heroState: HeroState {
        if repo.today?.recovery != nil { return .verdict }
        // FER-286: mientras la banda drena el historial de la noche y aún no hay recovery, el Hero dice la
        // verdad —«Descargando la noche…»— en vez de «Falta la lectura de hoy»: el dato viene en camino,
        // no falta. Reusa la misma señal que ya hace girar el dial (FER-221), sin agregar otra.
        if isSyncing { return .downloading }
        if hasImportedBaseline { return .importedBaseline }
        let strapSeen = live.lastSyncedAt != nil || liveBpm != nil
        if strapSeen && ownNights < Baselines.minNightsSeed { return .calibrating(nights: ownNights) }
        return .waiting
    }

    /// Whether a strap has ever been seen (drives the foot affordance: Scan before, live pulse after).
    private var strapSeen: Bool { live.lastSyncedAt != nil || liveBpm != nil }

    /// Cabecera FIJA del instrumento (FER-465): overline + dial 24h con el numeral concéntrico. El cuerpo
    /// del veredicto en palabras (`heroBody` + `heroFooter`) ya NO vive aquí — se mudó a `verdictPage`
    /// (página 1 del pager), así que arriba queda solo el dial + número. Conserva el giro del sync
    /// (FER-221) y el «armado» del arco con el tirón (FER-222), intactos.
    @ViewBuilder private var dialHeader: some View {
        let state = heroState
        // Ritmo vertical compacto (FER-205): gap a `space2` (8) entre overline y dial.
        VStack(spacing: NoopMetrics.space2) {
            // FER-283/284: la overline del héroe usa `instrumentoOverlineProminent` (14/medium) en tinta
            // secundaria — más presencia sin competir con el numeral. Un nudge de aire arriba la baja un
            // poco del estado/fecha, y queda centrada (también si el texto envuelve).
            Text(heroOverline(state)).instrumentoOverlineProminent().foregroundStyle(theme.inkSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, NoopMetrics.space1)
            // Instrumento concéntrico (FER-169): el numeral domina el CENTRO del dial de 24h. Sin número que
            // medir (em-dash) el dial es el protagonista; con número, el dato vive dentro del reloj.
            // `sleepWindow` ya es nil cuando anoche no hubo registro de strap, así que el dial omite la banda
            // de sueño sola: contexto honesto en cada modo. Escala (FER-205): dial 180 con el numeral 60.
            ZStack {
                // Viñeta radial cálida detrás del dial (handoff «Hoy · Estados», el
                // `radial-gradient(circle, rgba(255,255,255,.8) 0% … 72%)` del mock): un pozo de luz
                // suave que asienta el dial sobre el papel sin una caja. Se deriva del papel vivo
                // (`paperHi`, ya aclarado hacia blanco en OKLab y hora-consciente) → cálido, NUNCA blanco
                // puro, así no destella de noche. Decorativa, detrás del dial y del numeral.
                RadialGradient(
                    gradient: Gradient(stops: [
                        .init(color: theme.paperHi, location: 0),
                        .init(color: theme.paperHi.opacity(0), location: 0.72)
                    ]),
                    center: .center, startRadius: 0, endRadius: 80
                )
                .frame(width: 160, height: 160)
                .accessibilityHidden(true)
                // FER-221: mientras la banda descarga (`backfilling`) el dial cobra vida —un arco
                // verde gira sobre el bezel— y el numeral se atenúa («recalculando»). La honesty line
                // del header no cambia. Al terminar, vuelve al reposo.
                // FER-222: el mismo arco se «arma» con el tirón (`pullProgress`, 0→1) antes de girar; al
                // disparar el sync por el gesto (`pullSyncing`) el dial gira de inmediato, sin esperar a
                // que arranque el offload. `syncing` manda sobre `armProgress` cuando ambos coinciden.
                DiurnalDial(now: Date(), solar: solarWindow, sleep: sleepWindow,
                            diameter: 180, syncing: isSyncing,
                            armProgress: pullProgress)
                heroNumeral(state)
            }
            // FER-545: sello «estimado · confianza» bajo el dial cuando el veredicto de hoy es un estimado
            // de Apple (noche sin banda). Vive en el camino PRINCIPAL (cabecera fija, ambas páginas), no
            // solo en el fallback de página 1 — así el veredicto estimado nunca se ve idéntico al de banda.
            if state == .verdict, repo.isRecoveryEstimated(Repository.localDayKey(Date())) {
                estimatedTodayMarker
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Pager de 2 páginas (FER-465)

    /// Página 1 del pager. Con veredicto (FER-470) muestra el **Daily Brief** —titular en palabras +
    /// porqué + 2–3 viñetas, armado por `DailyBriefEngine`—; en los demás estados (descargando / base
    /// Apple / calibrando / espera) conserva el copy honesto de `heroBody` + `heroFooter`. El motor
    /// devuelve `nil` sin veredicto, así que el `else` cubre también ese caso de forma natural.
    @ViewBuilder private var verdictPage: some View {
        let state = heroState
        if state == .verdict, let brief = dailyBrief {
            dailyBriefView(brief)
        } else {
            transitionalBriefView(state)
        }
    }

    /// Página 1 cuando aún no hay veredicto (FER-475). Para los estados de «aún no hay lectura» (`waiting`/
    /// `importedBaseline`) muestra un Brief «en espera» ENRIQUECIDO: encabezado + titular honesto + por qué
    /// llega + la continuidad «Ayer cerraste en …» + el puente a Métricas (NADA del copy viejo de «base
    /// lista / strap»). Para `downloading` (la noche está bajando) y `calibrating` (onboarding de las
    /// primeras noches) conserva su copy honesto de `heroBody` —siguen siendo precisos— + el puente.
    @ViewBuilder private func transitionalBriefView(_ state: HeroState) -> some View {
        switch state {
        case .waiting, .importedBaseline:
            waitingBrief(state)
        default:   // downloading / calibrating (y .verdict no llega aquí)
            VStack(spacing: NoopMetrics.gap) {
                heroBody(state)
                heroFooter(state)
                metricsBridge
            }
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }

    /// El Brief «en espera» enriquecido (FER-475): encabezado «DAILY BRIEF · EN ESPERA» + «Aún no hay
    /// lectura de hoy» + cuándo llega + «Ayer cerraste en …» (si hubo veredicto ayer) + el puente a
    /// Métricas. Sin el copy viejo de «tu base está lista / usa el strap».
    private func waitingBrief(_ state: HeroState) -> some View {
        VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            briefHeader(now: false)
            Text("Aún no hay lectura de hoy")
                .font(StrandFont.title2).fontWeight(.semibold).foregroundStyle(theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(strapSeen
                 ? "Tu veredicto llega con el primer sync de la mañana, cuando sincronices la noche."
                 : "Conecta tu banda o Apple Salud y tu veredicto empezará a leerse cada mañana.")
                .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let y = yesterdayVerdict { yesterdayLine(y) }
            heroFooter(state)   // conserva el CTA «Buscar strap» en base-Apple sin banda; vacío en espera
            metricsBridge
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// El puente a «Métricas de hoy» desde la página 1 transicional: desliza el pager a la página 2 (donde
    /// hay datos que ver mientras llega el veredicto). Cápsula en tinta — chrome, no dato (sin verde).
    private var metricsBridge: some View {
        Button {
            withAnimation(reduceMotion ? nil : StrandMotion.interactive) { pagerPage = 1 }
        } label: {
            HStack(spacing: NoopMetrics.space2) {
                Text("Ver tus métricas de hoy").font(StrandFont.subhead.weight(.semibold))
                Image(systemName: "arrow.right").font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(theme.inkSecondary)
            .padding(.horizontal, NoopMetrics.cardPadding).padding(.vertical, NoopMetrics.gap)
            .overlay(Capsule().strokeBorder(theme.hairlineStrong, lineWidth: 1))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, NoopMetrics.space2)
        .accessibilityHint(Text("Abre la página de métricas de hoy"))
    }

    /// Aterrizaje inicial del pager (FER-475): UNA sola vez, cuando los datos ya cargaron (`repo.loaded`),
    /// si no hay veredicto abre en Métricas (página 2). Se llama desde `loadAll` tras sembrar el veredicto,
    /// así que `heroState` ya es definitivo. El flag evita re-saltar cuando llega el veredicto matutino o el
    /// usuario desliza a propósito — solo decide el destino de apertura, no pelea con sus gestos.
    @MainActor private func maybeAutoLandMetrics() {
        guard !didAutoLandMetrics, repo.loaded else { return }
        didAutoLandMetrics = true
        if heroState != .verdict { pagerPage = 1 }
    }

    /// El Daily Brief del día (FER-470), armado desde el veredicto memoizado + la recuperación de hoy y su
    /// media reciente (derivada con el MISMO `baselineDays()`/`history()` que los tiles) + el sueño de
    /// anoche. `nil` sin veredicto → la página 1 cae al copy honesto.
    private var dailyBrief: DailyBrief? {
        let recBase = history(baselineDays()) { $0.recovery }
        let recoveryBaseline = recBase.isEmpty ? nil : recBase.reduce(0, +) / Double(recBase.count)
        let sleepMin = resolveMeasured(todayOnly: true) { $0.totalSleepMin }?.value
        return DailyBriefEngine.make(readiness: readiness,
                                     recovery: repo.today?.recovery,
                                     recoveryBaseline: recoveryBaseline,
                                     sleepMinutes: sleepMin)
    }

    /// El bloque «Hoy en tu plan» (FER-613): puente con Entrenar al pie del brief. `nil` sin split (se omite).
    private var trainingBlock: DailyBrief.TrainingBlock? {
        DailyBriefEngine.trainingBlock(hasSplit: hasSplit,
                                       todayRoutineName: todayRoutineName,
                                       streakDays: trainingStreak,
                                       recovery: repo.today?.recovery)
    }

    /// «La conexión de hoy» (FER-614): la correlación significativa más relevante, o `nil` (la UI omite el
    /// renglón). Misma fuente que Patrones, así el deep-link abre exactamente ese patrón.
    private var connection: DailyBrief.Connection? {
        DailyBriefEngine.connection(insights: insights)
    }

    /// El Daily Brief renderizado: titular en TINTA (el color vive en el dato, no en la palabra) que
    /// abre el porqué (`WhyVerdictSheet`, como antes la palabra del veredicto), el porqué, las viñetas
    /// tocables (FER-475) y el bloque atenuado «Más tarde hoy».
    private func dailyBriefView(_ brief: DailyBrief) -> some View {
        VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            // El Daily Brief vive en una TARJETA `surface` (handoff): envuelve SOLO las filas pobladas —
            // encabezado + titular + porqué + viñetas—. «Más tarde hoy» queda FUERA, debajo, sobre el papel.
            // Mismo fondo/borde/sombra que los tiles de Métricas (surface + hairline + sombra sutil).
            VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                briefHeader(now: true)
                Button { showWhyVerdict = true } label: {
                    HStack(alignment: .firstTextBaseline, spacing: NoopMetrics.space2) {
                        Text(brief.titular)
                            // §2 «Instrumento»: el veredicto va en serif (Instrument Serif, Regular 400).
                            // Sin `.semibold` — la cara es solo Regular y forzar peso sintetiza un falso-bold.
                            .font(StrandFont.serifVerdict)
                            .foregroundStyle(theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Image(systemName: "info.circle").font(.system(size: 15))
                            .foregroundStyle(theme.inkTertiary)
                        Spacer(minLength: 0)
                    }
                    // FER-608 polish: sin `minHeight: 44` — el titular en serif grande ya da un blanco
                    // táctil cómodo y el `minHeight` le metía aire muerto arriba/abajo dentro de la card.
                    // El mismo «¿Por qué?» sigue accesible desde la palabra del dial y la caption.
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text("Abre por qué el veredicto se lee así"))

                Text(brief.why).font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let conn = connection { connectionLineView(conn) }

                VStack(spacing: 0) {
                    ForEach(Array(brief.bullets.enumerated()), id: \.offset) { i, b in
                        briefBulletRow(b, showTopHairline: i > 0)
                    }
                }
                .padding(.top, NoopMetrics.space1)
            }
            .padding(NoopMetrics.cardPadding)
            .background {
                RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous)
                    .fill(theme.surface)
                    .shadow(color: theme.ink.opacity(0.05), radius: 1.5, x: 0, y: 1)
            }
            .overlay(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous)
                .strokeBorder(theme.hairline, lineWidth: 1))

            if let tb = trainingBlock { trainingBlockView(tb) }

            laterTodaySection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - «La conexión de hoy» (FER-614)

    /// El renglón «La conexión de hoy» dentro de la card del brief: acento verde a la izquierda, la frase sin
    /// jerga y «Ver patrón». Toca → abre el detalle de esa correlación en Patrones vía `TabRouter` (deep-link
    /// por la `InsightFreshness.key` del insight, la misma identidad que usa Patrones).
    private func connectionLineView(_ conn: DailyBrief.Connection) -> some View {
        Button {
            tabRouter.openInsight(key: InsightFreshness.key(for: conn.insight))
        } label: {
            VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                Text("La conexión de hoy").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                HStack(alignment: .firstTextBaseline, spacing: NoopMetrics.space2) {
                    Text(conn.text).font(StrandFont.subhead).foregroundStyle(theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: NoopMetrics.space2)
                    HStack(spacing: 2) {
                        Text("Ver patrón").font(StrandFont.caption)
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(theme.verdict)
                    .fixedSize()
                }
            }
            .padding(.leading, NoopMetrics.gap)
            .padding(.trailing, NoopMetrics.space2)
            .padding(.vertical, NoopMetrics.space2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.paper)
            .overlay(alignment: .leading) { Rectangle().fill(theme.verdict).frame(width: 2.5) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, NoopMetrics.space2)
        .accessibilityHint(Text("Abre este patrón en Patrones"))
    }

    // MARK: - Bloque «Hoy en tu plan» (FER-613)

    /// El bloque puente con Entrenar al pie del brief: su propia tarjeta `surface`, fiel al preview aprobado.
    /// Día de entreno → rutina + chip de racha + línea de ritmo (color por `pace`) + «Empezar»; descanso →
    /// «Hoy descansas». El color del ritmo (verde sube / ámbar baja) es el único dato con color, como el resto
    /// del «Instrumento». «Empezar» enruta a Entrenar y arranca la sesión vía `TabRouter` (reusa el prefetch).
    private func trainingBlockView(_ tb: DailyBrief.TrainingBlock) -> some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space2) {
            Text("Hoy en tu plan").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            switch tb.state {
            case .training:
                HStack(alignment: .firstTextBaseline, spacing: NoopMetrics.space2) {
                    Text(tb.routineName ?? "").font(StrandFont.title2).foregroundStyle(theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    streakChip(tb.streakDays)
                    Spacer(minLength: 0)
                }
                if let copy = tb.paceCopy {
                    HStack(spacing: NoopMetrics.space2) {
                        Image(systemName: paceGlyph(tb.pace)).font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(paceColor(tb.pace))
                        Text(copy).font(StrandFont.subhead).foregroundStyle(paceColor(tb.pace))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }
                Button { tabRouter.startTodayTraining() } label: {
                    Text("Empezar").font(StrandFont.headline).foregroundStyle(theme.paperHi)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(theme.ink, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, NoopMetrics.space1)
                .accessibilityHint(Text("Abre Entrenar y arranca la sesión de hoy"))
            case .rest:
                HStack(spacing: NoopMetrics.gap) {
                    Image(systemName: "moon.fill").font(.system(size: 16)).foregroundStyle(theme.inkSecondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Hoy descansas").font(StrandFont.subhead.weight(.semibold)).foregroundStyle(theme.ink)
                        Text("tu split no asigna rutina hoy").font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(NoopMetrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous)
                .fill(theme.surface)
                .shadow(color: theme.ink.opacity(0.05), radius: 1.5, x: 0, y: 1)
        }
        .overlay(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous)
            .strokeBorder(theme.hairline, lineWidth: 1))
    }

    /// El chip de racha: glifo de llama + «racha N días» (singular «día» en 1). Mismo número que Entrenar.
    private func streakChip(_ days: Int) -> some View {
        let unit = days == 1 ? "día" : "días"
        return HStack(spacing: 4) {
            Image(systemName: "flame.fill").font(.system(size: 11)).foregroundStyle(theme.warning)
            Text("racha \(days) \(unit)").font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
        }
        .padding(.horizontal, NoopMetrics.space2).padding(.vertical, 2)
        .background(theme.paper, in: Capsule())
        .overlay(Capsule().strokeBorder(theme.hairline, lineWidth: 0.5))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Racha de \(days) \(unit) en tu plan"))
    }

    /// El color del ajuste de ritmo: verde «sube», ámbar «baja», tinta secundaria «mantén» — color en el dato.
    private func paceColor(_ pace: DailyBrief.TrainingBlock.Pace?) -> Color {
        switch pace {
        case .up:   return theme.verdict
        case .down: return theme.warning
        case .hold, .none: return theme.inkSecondary
        }
    }

    /// El glifo del ajuste de ritmo (flecha diagonal arriba/abajo; horizontal en «mantén»).
    private func paceGlyph(_ pace: DailyBrief.TrainingBlock.Pace?) -> String {
        switch pace {
        case .up:   return "arrow.up.right"
        case .down: return "arrow.down.right"
        case .hold, .none: return "arrow.right"
        }
    }

    /// Caption «toca para saber por qué» bajo el dial (handoff, SOLO en la vista Brief con veredicto).
    /// Toca → el mismo «¿Por qué?» (`WhyVerdictSheet`) que la palabra del dial.
    private var whyCaption: some View {
        Button { showWhyVerdict = true } label: {
            Text("toca para saber por qué")
                .font(StrandFont.caption)
                .foregroundStyle(theme.inkTertiary)
                .frame(maxWidth: .infinity, alignment: .center)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, NoopMetrics.space2)
        .accessibilityHint(Text("Abre por qué el veredicto se lee así"))
    }

    /// El encabezado de la página 1 (FER-475): overline «DAILY BRIEF» · punto · «AHORA» (verde, con
    /// veredicto) o «EN ESPERA» (tinta, sin lectura) + una regla hairline. Fiel al handoff.
    private func briefHeader(now: Bool) -> some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space2) {
            HStack(spacing: NoopMetrics.space2) {
                Text("Daily Brief").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                Spacer(minLength: 0)
                // FER-549/handoff: el estado va a la DERECHA (space-between) y el punto «Ahora» PULSA (halo)
                // cuando hay veredicto; estático en espera o bajo Reduce Motion.
                nowDot(now: now)
                Text(now ? "Ahora" : "En espera").instrumentoOverline()
                    .foregroundStyle(now ? theme.verdict : theme.inkTertiary)
            }
            Rectangle().fill(theme.hairline).frame(height: 0.5)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// El punto «Ahora» del Daily Brief: un círculo en el color de estado (verde con veredicto, tinta en
    /// espera). Con veredicto, un halo concéntrico RESPIRA detrás con el MISMO token que el punto «ahora»
    /// del dial (`StrandMotion.breathe`), para que los dos indicadores de «en vivo» pulsen igual; estático
    /// bajo Reduce Motion. El latido se arma con `briefDotPulse` al aparecer (lo anima el `.animation` por
    /// cambio de valor, no un `withAnimation`).
    @ViewBuilder private func nowDot(now: Bool) -> some View {
        let c = now ? theme.verdict : theme.inkTertiary
        ZStack {
            if now {
                Circle().fill(c)
                    .frame(width: 14, height: 14)
                    .scaleEffect(briefDotPulse ? 1.3 : 0.92)
                    .opacity(briefDotPulse ? 0.05 : 0.20)
                    .animation(reduceMotion ? nil : StrandMotion.breathe, value: briefDotPulse)
            }
            Circle().fill(c).frame(width: 6, height: 6)
        }
        .frame(width: 6, height: 6)
        .onAppear { if now && !reduceMotion { briefDotPulse = true } }
        .accessibilityHidden(true)
    }

    /// La línea de continuidad «Ayer cerraste en …» (FER-475): el nivel del veredicto de ayer en su color.
    private func yesterdayLine(_ level: ReadinessEngine.Level) -> some View {
        HStack(spacing: NoopMetrics.space2) {
            Text("Ayer cerraste en").font(StrandFont.subhead).foregroundStyle(theme.inkTertiary)
            Text(stateLabel(level)).font(StrandFont.subhead.weight(.semibold))
                .foregroundStyle(verdictDataColor(level))
        }
        .accessibilityElement(children: .combine)
    }

    /// El bloque «Más tarde hoy» (FER-475): un adelanto ATENUADO de lo que vendrá (tu comida, tu
    /// entrenamiento del día). Son placeholders —no datos reales— con etiqueta «PRONTO», borde punteado
    /// y `opacity .5`, no tocables. Separado del brief por una regla hairline arriba.
    private var laterTodaySection: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            Rectangle().fill(theme.hairline).frame(height: 0.5)
            Text("Más tarde hoy").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            VStack(spacing: NoopMetrics.space2) {
                teaserCard(time: "13:00", title: "Tu comida de hoy")
                // El teaser «Tu entrenamiento de hoy» se retiró: el bloque real «Hoy en tu plan» lo reemplaza
                // (FER-613) — un placeholder «PRONTO» justo encima del bloque vivo era contradictorio.
            }
            .opacity(0.5)
            .allowsHitTesting(false)
            .accessibilityHidden(true)   // adelanto no accionable: fuera del recorrido de VoiceOver
        }
        .padding(.top, NoopMetrics.space2)
    }

    /// Una tarjeta-teaser de «Más tarde hoy»: etiqueta de hora + título + «PRONTO», con borde PUNTEADO
    /// (la señal visual de «aún no disponible»). Sin datos reales — es un adelanto de diseño.
    private func teaserCard(time: String, title: LocalizedStringKey) -> some View {
        HStack(spacing: NoopMetrics.gap) {
            Text(time)
                .font(StrandFont.captionNumber).foregroundStyle(theme.inkSecondary)
                .padding(.horizontal, NoopMetrics.space2).padding(.vertical, NoopMetrics.space1)
                .background(theme.surface, in: RoundedRectangle(cornerRadius: NoopMetrics.chipRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: NoopMetrics.chipRadius, style: .continuous)
                    .strokeBorder(theme.hairline, lineWidth: 0.5))
            Text(title).font(StrandFont.subhead).foregroundStyle(theme.ink)
            Spacer(minLength: 0)
            Text("Pronto").instrumentoOverline().foregroundStyle(theme.inkTertiary)
        }
        .padding(.horizontal, NoopMetrics.cardPadding).padding(.vertical, NoopMetrics.gap)
        .overlay(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous)
            .strokeBorder(theme.hairlineStrong, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
    }

    /// Una viñeta del Daily Brief: glifo SF tintado por el flag (misma fuente de color que la palabra del
    /// veredicto, vía `flagColor`) + lead semibold + sub con la cifra + chevron. Toda la fila es tocable
    /// (FER-475): abre `WhyVerdictSheet` —«tus señales de hoy» en σ— el detalle compartido de cualquier
    /// viñeta (el handoff usa una hoja con cuerpo común). Separador hairline entre viñetas.
    private func briefBulletRow(_ b: DailyBrief.Bullet, showTopHairline: Bool) -> some View {
        Button { openBriefBullet(b.kind) } label: {
            HStack(spacing: NoopMetrics.gap) {
                Image(systemName: briefGlyph(b.kind))
                    .font(.system(size: 18))
                    .foregroundStyle(flagColor(b.flag))
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(b.lead).font(StrandFont.subhead.weight(.semibold)).foregroundStyle(theme.ink)
                    Text(b.sub).font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.inkTertiary)
            }
            .padding(.vertical, NoopMetrics.space2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) {
            if showTopHairline { Rectangle().fill(theme.hairline).frame(height: 0.5) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Abre el detalle de tus señales de hoy"))
    }

    /// FER-589: cada viñeta del Brief abre el DETALLE de su señal (el mismo destino que la pill/tile de
    /// esa métrica), no la hoja genérica del veredicto. `skinTemp`/`acwr` no tienen detalle propio (son
    /// contexto del veredicto) → ahí sí cae a `WhyVerdictSheet`, a propósito.
    private func openBriefBullet(_ kind: DailyBrief.BulletKind) {
        switch kind {
        case .sleep:
            metricDetail = .sleep(resolveMeasured(todayOnly: true) { $0.totalSleepMin }.map { Int($0.value.rounded()) })
        case .recovery:
            metricDetail = .recovery(score: recoveryScore,
                                     calibrationNights: recoveryCalibration,
                                     nightsNeeded: Baselines.minNightsSeed)
        case .hrv:
            metricDetail = .hrv(latestFromDisplay { $0.avgHrv }?.value)
        case .rhr:
            metricDetail = .restingHR(latestFromDisplay { $0.restingHr.map(Double.init) }.map { Int($0.value.rounded()) })
        case .respRate:
            metricDetail = .respiratory(latestFromDisplay { $0.respRateBpm }?.value)
        case .skinTemp, .acwr:
            showWhyVerdict = true   // sin detalle de métrica propio → el porqué del veredicto
        }
    }

    /// SF Symbol por tema de viñeta (la presentación vive en la app, no en el motor puro).
    private func briefGlyph(_ kind: DailyBrief.BulletKind) -> String {
        switch kind {
        case .sleep:    return "moon.fill"
        case .recovery: return "arrow.up"
        case .hrv:      return "waveform.path.ecg"
        case .rhr:      return "bed.double.fill"
        case .respRate: return "lungs.fill"
        case .skinTemp: return "thermometer.medium"
        case .acwr:     return "bolt.fill"
        }
    }

    /// Color por `Flag`, la MISMA fuente que `WhyVerdictSheet`/la palabra del veredicto: good→verdict,
    /// watch→warning, bad→critical, neutral→tinta terciaria. (FER-470)
    private func flagColor(_ f: ReadinessEngine.Flag) -> Color {
        switch f {
        case .good:    return theme.verdict
        case .neutral: return theme.inkTertiary
        case .watch:   return theme.warning
        case .bad:     return theme.critical
        }
    }

    /// Página 2 del pager: «Métricas de hoy» tal cual — o la tarjeta de fuentes si no hay ninguna
    /// (FER-364). El grid de tiles NO cambia (decisión del dueño en FER-464).
    @ViewBuilder private var metricsPage: some View {
        if noSources { emptySourcesCard } else { iosMetricsSection }
    }

    /// El pager horizontal de 2 páginas. `ScrollView(.horizontal)` con `.scrollTargetBehavior(.paging)`
    /// (snap a página) + `.scrollPosition` para reflejar la página activa en los dots; `.scrollTargetLayout()`
    /// en el riel. Cada página mide `width` (= ancho de contenido) para que el snap pagine de a una. El alto
    /// lo fija la página más alta (Métricas); en la página 1 el resto queda en blanco hasta que F3 la llene
    /// con el Daily Brief. Ejes ortogonales al scroll vertical → no se pelea con el pull-to-refresh.
    @ViewBuilder private func todayPager(width: CGFloat) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 0) {
                verdictPage.frame(width: width).id(0)
                metricsPage.frame(width: width).id(1)
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $pagerPage)
    }

    /// Page dots: punto 6×6 inactivo (`hairlineStrong`) · barra 18×6 activa (`ink`), centrados. Tocar un
    /// punto navega a su página (`StrandMotion.interactive`, omitida bajo Reduce Motion). El acento verde
    /// NO se usa en el chrome: la página activa es TINTA, no verde (handoff). Área tocable de 28pt.
    private var todayPageDots: some View {
        HStack(spacing: NoopMetrics.space2) {
            ForEach(0..<2, id: \.self) { i in
                let active = (pagerPage ?? 0) == i
                Button {
                    withAnimation(reduceMotion ? nil : StrandMotion.interactive) { pagerPage = i }
                } label: {
                    Capsule(style: .continuous)
                        .fill(active ? theme.ink : theme.hairlineStrong)
                        .frame(width: active ? 18 : 6, height: 6)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(i == 0 ? "Veredicto del día" : "Métricas de hoy"))
                .accessibilityAddTraits(active ? [.isButton, .isSelected] : .isButton)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        // Sin padding superior propio: el `Spacer(minLength: space2)` que precede a los dots ya da esa
        // separación. Sumar aquí otro `space2` duplicaba el gap (8 + 8) y empujaba ~8pt de scroll fantasma.
        .animation(reduceMotion ? nil : StrandMotion.interactive, value: pagerPage)
    }

    /// Muestra la pista del pull-to-refresh (FER-293): en reposo (sin tirón en curso) y mientras NO se
    /// está sincronizando ya (el dial girando — FER-221 — comunica ese estado). Se muestra SIEMPRE en
    /// reposo —con o sin strap— porque jalar igual recarga los datos locales (`repo.refresh()`), no solo
    /// sincroniza la banda. Se desvanece al iniciar el gesto (`pullProgress > 0`), revelando el arco del
    /// dial. (Antes —FER-270/FER-274— solo aparecía con strap y se apagaba para siempre al primer pull;
    /// eso la volvía indescubrible para quien ya había jalado una vez.)
    /// El instrumento está sincronizando: offload en curso, su puente async (FER-480 `draining`) o el
    /// pull-to-sync manual. Fuente única para las señales del héroe (estado, dial, numeral, pista).
    private var isSyncing: Bool { live.backfilling || live.draining || pullSyncing }

    private var showsSyncHint: Bool {
        pullProgress == 0 && !isSyncing
    }

    /// La pista del pull-to-refresh (FER-293): un `chevron.down` que rebota suave y, mientras el usuario
    /// aún no aprende el gesto (`!didFirstPullSync`), el microcopy «Desliza para actualizar». Tras el
    /// primer pull-to-sync el texto y el rebote se retiran, pero el chevron PERMANECE como cue sutil —
    /// así el gesto sigue siendo descubrible en vez de desaparecer para siempre (FER-270). Se monta como
    /// `.overlay` en el tope del scroll, así que NO ocupa alto de layout (no empuja el héroe ni desborda
    /// la pantalla). Bajo Reduce Motion no rebota (estático). Oculta a VoiceOver — su equivalente
    /// accesible es la acción «Sincronizar» del encabezado (FER-222).
    private var syncHint: some View {
        let learning = !didFirstPullSync
        let bobbing = learning && !reduceMotion && hintBob
        return VStack(spacing: NoopMetrics.space1) {
            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.inkTertiary)
                .offset(y: bobbing ? 4 : 0)
                .animation(bobbing ? StrandMotion.bob : nil, value: bobbing)
            if learning {
                Text("Desliza para actualizar")
                    .font(StrandFont.caption)
                    .foregroundStyle(theme.inkTertiary)
            }
        }
        .transition(.opacity)
        .accessibilityHidden(true)
        .onAppear { hintBob = true }
    }

    private func heroOverline(_ s: HeroState) -> LocalizedStringKey {
        switch s {
        case .calibrating: return "Tu base se afina"
        default:           return "El veredicto de hoy"
        }
    }

    /// El color del numeral del héroe — tinta normal, atenuado a tertiary mientras sincroniza
    /// (FER-221): «recalculando», en sintonía con el dial girando. Vuelve a tinta al terminar.
    private var heroNumeralInk: Color { isSyncing ? theme.inkTertiary : theme.ink }

    /// El numeral dominante — lo único que “grita” el estado. Veredicto (FER-549): número Y palabra van en
    /// el MISMO color de nivel, así nunca se contradicen (a diferencia del caso que evitó FER-206: número
    /// en color de banda ≠ color de nivel de la palabra). Sin palabra (`insufficient`) el número se queda
    /// en tinta. Calibrando → «N/4» en tinta (progreso, no dato). Espera/base Apple → em-dash «—» en tinta.
    /// Numeral 60 limpio (sin «/100», FER-608) con la palabra del nivel apilada bajo él (FER-549); solo
    /// el modo calibrando conserva un denominador («/seed») por ser progreso, no dato.
    @ViewBuilder private func heroNumeral(_ s: HeroState) -> some View {
        switch s {
        case .verdict:
            let score = recoveryScore
            let lvl = readiness.level
            // FER-549 (B1): la PALABRA del veredicto regresa al centro del dial, apilada bajo el numeral.
            // Con palabra, el número se tiñe por nivel (MISMO color que la palabra — no se contradicen, a
            // diferencia del caso FER-206 donde el número iba en color de banda ≠ color de nivel). Sin
            // palabra (`insufficient`) el número se queda en tinta como antes.
            let hasWord = lvl != .insufficient
            let numColor = isSyncing ? theme.inkTertiary
                : (hasWord ? verdictDataColor(lvl) : heroNumeralInk)
            VStack(spacing: NoopMetrics.space2) {
                // Concéntrico (FER-169): el NÚMERO queda centrado en el eje del dial (limpio, sin «/100»
                // desde FER-608). El número abre la hoja RESUMIDA de recuperación (MetricInfoSheet), igual
                // que las demás métricas de Hoy (FER-232).
                Group {
                    if let score {
                        // FER-549/handoff: solo el numeral limpio en el centro del dial — sin el «/100» (su
                        // denominador descentraba el número y el handoff lo muestra sin él). El número sigue
                        // tocable (abre el resumen de Recuperación), solo pierde la pista en línea.
                        Text("\(score)").instrumentoHero(60)
                            .foregroundStyle(numColor)
                    } else {
                        Text("—").instrumentoHero(60).foregroundStyle(theme.inkTertiary)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    metricDetail = .recovery(score: recoveryScore,
                                             calibrationNights: recoveryCalibration,
                                             nightsNeeded: Baselines.minNightsSeed)
                }
                // La palabra del nivel en su color; toca → «¿Por qué?» (`WhyVerdictSheet`), la misma hoja
                // que abren la «i» de Métricas y el titular del Brief. `insufficient` no tiene palabra.
                if hasWord {
                    Button { showWhyVerdict = true } label: {
                        Text(stateLabel(lvl)).font(StrandFont.subhead).fontWeight(.semibold)
                            .foregroundStyle(isSyncing ? theme.inkTertiary : verdictDataColor(lvl))
                            .multilineTextAlignment(.center)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(Text("Abre por qué el veredicto se lee así"))
                }
            }
        case .calibrating(let nights):
            // Apilado (FER-202), igual que el veredicto: «N» centrado en el eje del dial con el «/seed»
            // pequeño y centrado debajo (antes a un lado con un «/seed» espejo invisible).
            VStack(spacing: NoopMetrics.space1) {
                Text("\(nights)").instrumentoHero(60).foregroundStyle(heroNumeralInk)
                Text("/\(Baselines.minNightsSeed)").font(StrandFont.subhead)
                    .foregroundStyle(theme.inkTertiary)
            }
        case .importedBaseline, .waiting, .downloading:
            Text("—").instrumentoHero(60).foregroundStyle(theme.inkTertiary)
        }
    }

    /// El cuerpo bajo el numeral: la palabra del veredicto + «i» + modificadores (veredicto), o la línea
    /// honesta de qué falta (resto de modos).
    @ViewBuilder private func heroBody(_ s: HeroState) -> some View {
        switch s {
        case .verdict:
            verdictBody
        case .downloading:
            // FER-286: el dial ya gira (FER-221); aquí el copy honesto de que el dato viene en camino.
            VStack(alignment: .center, spacing: NoopMetrics.space2) {
                Text("Downloading last night…")
                    .font(StrandFont.headline).foregroundStyle(theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Your data from last night is arriving. The first sync of the day can take a few minutes.")
                    .font(StrandFont.body).foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
        case .importedBaseline:
            VStack(alignment: .center, spacing: NoopMetrics.space2) {
                appleBaseChip   // FER-467: el pulso vivo se mudó al encabezado de Métricas (página 2)
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
                calibrationDots(nights: nights)   // FER-467: pulso vivo movido al encabezado de Métricas
                Text(calibrationDetailCopy(nights: nights))
                    .font(StrandFont.body).foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
        case .waiting:
            VStack(alignment: .center, spacing: NoopMetrics.space2) {
                // FER-467: el pulso vivo se mudó al encabezado de Métricas (página 2); aquí solo el titular.
                Text(strapSeen ? "Aún no hay lectura de hoy" : "Aún no hay lectura")
                    .font(StrandFont.headline).foregroundStyle(theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(strapSeen
                     ? "Tu base está lista. Usa el strap esta noche y la recuperación, el esfuerzo y el sueño de la mañana aparecen al sincronizar."
                     : "Connect Apple Health to start. Your WHOOP strap sharpens the reading.")
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
            // FER-549 (B1): la palabra del veredicto + el «¿por qué?» ya viven en el CENTRO del dial; aquí
            // (el fallback de página 1 sin Daily Brief) ya no se repiten. FER-545: el sello «estimado» también
            // subió al dial (camino principal), así que aquí solo quedan los modificadores de puente/confianza.
            if let bridge = r.bridge {
                Text(bridge).font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if r.confidenceLow {
                // FER-285: en el Hero, una línea CORTA; la explicación con las horas reales de anoche
                // vive en WhyVerdictSheet (la «i» de arriba la abre). El `confidenceNote` del engine se
                // conserva (a11y / otros consumidores), pero el Hero ya no lo muestra entero.
                HStack(spacing: NoopMetrics.space2) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 10))
                    Text("Short night — low confidence").font(StrandFont.caption)
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

    /// FER-153: «Estimado · confianza X» bajo el veredicto cuando la lectura del día es un estimado de Apple
    /// (noche sin banda). Token-only; reusa la frase localizada del Detalle de recuperación.
    private var estimatedTodayMarker: some View {
        HStack(spacing: NoopMetrics.space2) {
            Image(systemName: "applewatch").font(.system(size: 10, weight: .semibold))
                .accessibilityHidden(true)
            Text(RecoveryDetailScreen.confidenceLabel(repo.recoveryConfidence(Repository.localDayKey(Date()))))
                .font(StrandFont.caption)
        }
        .foregroundStyle(theme.inkSecondary)
    }

    /// El pie del héroe — solo afordancias de onboarding (FER-189): el CTA «Buscar strap» cuando nunca se
    /// ha visto uno, o el atajo «¿Tienes historial en Apple Salud?…» mientras calibra. El renglón de pulso
    /// vivo «Verlo latido a latido» se MUDÓ al pie de la pantalla (`iosBody`), así que el héroe queda
    /// limpio: número + veredicto. En veredicto / espera-con-strap el pie del héroe no muestra nada.
    @ViewBuilder private func heroFooter(_ s: HeroState) -> some View {
        switch s {
        case .verdict, .downloading, .waiting:
            // En espera sin fuentes el CTA vive en la tarjeta de fuentes (`emptySourcesCard`), no en
            // el pie del héroe. (FER-364)
            EmptyView()
        case .calibrating:
            appleHealthShortcut { showDataSources = true }
        case .importedBaseline:
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

    /// Cero fuentes: ni strap visto, ni datos de Apple Health, ni permiso de Health concedido. (FER-364)
    private var noSources: Bool {
        !strapSeen && repo.appleHealthDays.isEmpty && health.auth != .authorized
    }

    /// La tarjeta de «conecta tus fuentes» del estado vacío: Apple Health como base, la banda como capa
    /// opcional. Reemplaza el botón verde y el viejo link de Apple Salud, y deja que Hoy quepa de una. (FER-364)
    private var emptySourcesCard: some View {
        VStack(spacing: 0) {
            sourceRow(icon: "heart.fill", tint: theme.dataSpO2,
                      title: "Conectar Apple Health", subtitle: "the base of your data") { showDataSources = true }
            Divider().overlay(theme.hairline).padding(.leading, NoopMetrics.cardPadding)
            sourceRow(icon: "applewatch.side.right", tint: theme.inkTertiary,
                      title: "Pair WHOOP strap", subtitle: "sharpens the signal · optional") { model.scan() }
        }
        .background(theme.surface, in: RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous)
            .strokeBorder(theme.hairline, lineWidth: 1))
        .shadow(color: theme.ink.opacity(0.08), radius: 8, y: 3)
    }

    private func sourceRow(icon: String, tint: Color, title: LocalizedStringKey,
                           subtitle: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: NoopMetrics.gap) {
                Image(systemName: icon).font(.system(size: 15)).foregroundStyle(tint).frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(StrandFont.subhead.weight(.semibold)).foregroundStyle(theme.ink)
                    Text(subtitle).font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(theme.inkTertiary)
            }
            .padding(NoopMetrics.cardPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
        /// FER-549 (B6): instante del último sync, para mostrar «hace cuánto» dentro de la píldora.
        var lastSyncedAt: Double?
        /// FER-583: estado de sincronización. La cápsula se MANTIENE durante el sync (antes cedía su lugar a
        /// una línea suelta sin bpm); solo su frescura pasa a «Sincronizando…» / «N paquetes» con el ⟳ girando.
        var backfilling: Bool = false
        var chunks: Int = 0
        let onTap: () -> Void
        @Environment(\.instrumentoTheme) private var theme
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        /// Tiempo relativo en unidades de UNA letra (FER-575/583): «hace 30 s / 5 m / 2 h / 3 d». Núcleo
        /// neutro («30 s», idéntico es/en) envuelto en la clave bilingüe «%@ ago» (es: «hace %@»).
        private static func compactAgo(_ secondsAgo: Double) -> String {
            let s = Int(secondsAgo.rounded())
            let core: String
            if s < 60 { core = "\(s) s" }
            else if s < 3600 { core = "\(s / 60) m" }
            else if s < 86_400 { core = "\(s / 3600) h" }
            else { core = "\(s / 86_400) d" }
            return String(localized: "\(core) ago")
        }

        var body: some View {
            Button(action: onTap) {
                // Chip compacto (FER-265): punto que late + bpm + frescura/estado de sync + chevron. La
                // cápsula + el chevron son el lenguaje iOS de «esto se toca»; el punto en color de dato
                // (vivo) es el único color.
                HStack(alignment: .center, spacing: NoopMetrics.space1) {
                    Circle().fill(isLiveHR ? theme.dataHeart : theme.inkTertiary)
                        .frame(width: 7, height: 7)
                    Text(liveBpm.map { "\($0)" } ?? "—").font(StrandFont.number(13, weight: .semibold))
                        .foregroundStyle(liveBpm == nil ? theme.inkTertiary : theme.ink)
                    Text("bpm").font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                    // FER-549 (B6) + FER-583: separador + ⟳ + frescura/estado. El ⟳ gira mientras `backfilling`;
                    // el texto es «Sincronizando…»/«N paquetes» en sync, o «hace 30 s» en reposo.
                    if backfilling || lastSyncedAt != nil {
                        Rectangle().fill(theme.hairline).frame(width: 1, height: 10)
                            .padding(.horizontal, NoopMetrics.space1)
                            .accessibilityHidden(true)
                        syncGlyph
                        freshness
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold)).foregroundStyle(theme.inkTertiary)
                }
                .padding(.leading, NoopMetrics.space2).padding(.trailing, NoopMetrics.space1)
                .padding(.vertical, 3)
                .background(theme.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(theme.hairline, lineWidth: 1))
                // Objetivo táctil HIG de 44pt SIN agrandar la cápsula (FER-273): la cápsula compacta de
                // FER-265 queda centrada en un área tocable de ≥44pt de alto. `contentShape` hace tocable
                // todo el marco, no solo la cápsula.
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(Text(isLiveHR ? "Frecuencia cardiaca en vivo" : "Frecuencia cardiaca"))
            .accessibilityValue(backfilling
                ? Text("Sincronizando")
                : Text(liveBpm.map { "\($0) bpm" } ?? "Sin lectura"))
            .accessibilityHint(Text("Abre el monitor latido a latido"))
        }

        /// El glifo ⟳: gira a velocidad constante mientras `backfilling` (ángulo = tiempo × 240°/s, ~1.5 s/
        /// vuelta, como el header viejo de FER-267); estático en reposo o bajo Reduce Motion.
        @ViewBuilder private var syncGlyph: some View {
            let base = Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(backfilling ? theme.verdict : theme.inkTertiary)
            if backfilling && !reduceMotion {
                TimelineView(.animation) { context in
                    let angle = (context.date.timeIntervalSinceReferenceDate * 240)
                        .truncatingRemainder(dividingBy: 360)
                    base.rotationEffect(.degrees(angle))
                }
            } else {
                base
            }
        }

        /// La frescura/estado a la derecha del ⟳: en sync, «N paquetes» (o «Sincronizando…» con 0) en verde;
        /// en reposo, «hace 30 s» en una letra. Mismas claves que el header viejo para conservar es/en.
        @ViewBuilder private var freshness: some View {
            if backfilling {
                Text(chunks > 0 ? String(localized: "\(chunks) packets") : String(localized: "Syncing…"))
                    .font(StrandFont.caption).monospacedDigit()
                    .foregroundStyle(theme.verdict)
            } else if let at = lastSyncedAt {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    let secondsAgo = Swift.max(context.date.timeIntervalSince1970 - at, 1)
                    Text(verbatim: Self.compactAgo(secondsAgo))
                        .font(StrandFont.number(11, weight: .regular)).monospacedDigit()
                        .foregroundStyle(theme.inkTertiary)
                }
            }
        }
    }

    /// Top utility row: compact date only — la sincronización + batería viven a su derecha en la línea
    /// de estado del `headerBlock` (FER-278).
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
        .padding(.top, NoopMetrics.space2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Confianza de calibración"))
        .accessibilityValue(Text(baselineFromApple
            ? "Afinando con tu strap, \(ownNights) de \(Baselines.minNightsTrust) noches. Tu base viene de Apple Salud."
            : "Afinando con tu strap, \(ownNights) de \(Baselines.minNightsTrust) noches."))
    }

    /// El rótulo de la sección «Métricas de hoy» (handoff «Hoy · Estados»): un overline en tinta seguido de
    /// una regla hairline que llena la línea. FER-282 lo había quitado para pegar los tiles al héroe; el
    /// handoff lo reintroduce como ancla de lectura. El texto va en tinta terciaria AA —el #8a8372 del mock
    /// no pasa AA a 11pt, así que se usa el token terciario (#6F6857), visualmente equivalente—. Marcado
    /// como encabezado para VoiceOver.
    // MARK: - Encabezado de estado de «Métricas de hoy» (FER-467)
    //
    // El handoff rodea el grid con el ESTADO del día: el overline + la palabra del estado (en su color
    // de nivel) a la izquierda, y a la derecha el pulso vivo (traído del héroe) + el botón «i» que abre
    // la explicación. Debajo, una escala de 4 segmentos sitúa el estado en el continuo
    // Desgastado→A punto. Color SOLO en el dato (el punto, la palabra, el segmento activo); todo lo
    // demás en tinta. El acento verde no se usa en chrome: la página activa de los dots es tinta.

    /// El label es-MX por nivel, derivado del `level` (no del `headline` de la página 1, que F3 va a
    /// cambiar). Reusa las MISMAS claves del catálogo que `ReadinessEngine` (`Primed`/`Balanced`/…), así
    /// que «A punto / Equilibrado / Exigido / Desgastado» ya están traducidas. `insufficient` no tiene
    /// palabra (el encabezado se queda solo con el overline).
    private func stateLabel(_ level: ReadinessEngine.Level) -> LocalizedStringKey {
        switch level {
        case .primed:       return "Primed"
        case .balanced:     return "Balanced"
        case .strained:     return "Strained"
        case .rundown:      return "Run down"
        case .insufficient: return "Readiness"
        }
    }

    // FER-550: `metricsHeader` (estado + escala) + `infoStateButton` se retiraron — el dial ya lleva la
    // palabra del veredicto (FER-549) y el «¿por qué?» se abre tocándola; el pulso vivo se mudó al header
    // de arriba (`headerBlock`). `stateLabel` se conserva: lo usa el numeral del dial.

    /// "Métricas de hoy" — la lectura intradía del día como rejilla 2×4 de 8 tiles (valor + Δ vs ayer),
    /// en el lenguaje «Instrumento diurno». Sustituye a la lista de tendencia 14d (FER-155/161): la
    /// tendencia es entre-días y migra a «Cuerpo»; aquí queda la foto de HOY. Cada tile es tematizado
    /// (papel `surface` + hairline, NUNCA el `NoopCard` oscuro), con etiqueta en tinta, valor en su
    /// color de dato y la variación contra ayer con semántica por métrica (mejora→`verdict`,
    /// empeora→`critical`, sin valencia/igual→`inkTertiary`). Recuperación NO es tile: ya es el numeral
    /// del héroe (no se duplica el número dominante). La tendencia 14d sigue accesible al tocar un tile
    /// (la hoja la trae). (FER-180)
    @ViewBuilder private var iosMetricsSection: some View {
        // Señales medidas: el número del tile = el ÚLTIMO punto de su propia gráfica (`latestFromDisplay`
        // sobre `displayDays`), badgeado por su fuente real, para que el número grande y la gráfica nunca
        // discrepen (FER-546). Sueño sigue day-scoped (`resolveMeasured(todayOnly:)`, FER-341). El esfuerzo
        // es strap-only (Apple no lo computa); los pasos, Apple-only.
        let hrvR    = latestFromDisplay { $0.avgHrv }
        let rhrR    = latestFromDisplay { $0.restingHr.map(Double.init) }
        let sleepR  = resolveMeasured(todayOnly: true) { $0.totalSleepMin }
        let spo2R   = latestFromDisplay { $0.spo2Pct }
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
        // Verde AA-en-texto-chico para el delta «mejora» (auditoría Hoy · P1): `theme.verdict` es
        // AA-grande (3:1 ≥18pt) pero el delta va en caption 12pt, donde hace falta 4.5:1.
        // `positiveText` oscurece el verdict lo justo para pasar AA contra el papel de la hora. Se
        // resuelve UNA vez por render (su bisección OKLab no debe correr por-tile) y se pasa a cada tile.
        let positiveDelta = theme.positiveText
        // FER-550: recuperación y respiración para el Vistazo / la rejilla de 6. Como los demás vitales,
        // el número = el último punto de su gráfica (`latestFromDisplay`), badgeado por su fuente (FER-546);
        // la recuperación de hoy sale de `repo.today` (el mismo dato que el dial).
        let recR    = repo.today?.recovery
        let respR   = latestFromDisplay { $0.respRateBpm }

        // FER-581: ritmo vertical un poco más apretado (gap→space2) para recortar el scroll de la página.
        VStack(alignment: .leading, spacing: NoopMetrics.space2) {
            // FER-550 (fiel al handoff): «Vistazo» — Recuperación / HRV / Sueño en 3 pills compactas (el
            // dato de un vistazo, sin mini-banda). El estado del día y la escala de 4 segmentos se retiraron
            // de aquí (el dial ya lleva la palabra del veredicto, FER-549) y el pulso vivo se mudó al header
            // de arriba; el «¿por qué?» se alcanza tocando la palabra del dial.
            glanceRow(recovery: recR, hrv: hrvR, sleep: sleepR, base: base, positive: positiveDelta)
            // Overline de la sección: la rejilla de hoy. Cada tile trae su tendencia de 14 días como
            // mini-gráfica de área (FER-551) + su «vs media».
            // FER-581: el rótulo de la sección y la leyenda de fuente comparten renglón. El lado derecho
            // del overline estaba vacío y la leyenda al pie sumaba un renglón (con su gap) que empujaba el
            // scroll; subirla aquí recupera ese alto sin perder la explicación de los puntos.
            HStack(spacing: NoopMetrics.space2) {
                Text("Métricas de hoy").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                    .lineLimit(1)
                Spacer(minLength: NoopMetrics.space2)
                sourceLegend
            }
            .padding(.top, NoopMetrics.space1)
            LazyVGrid(columns: tileGrid, alignment: .leading, spacing: NoopMetrics.gap) {
                // Esfuerzo del día — carga del día, sin valencia (Δ en tinta neutra).
                metricTile(TodayMetricTile(
                    label: "Day Strain",
                    icon: "bolt.fill",
                    value: strainT.map { String(format: "%.1f", $0) } ?? "—",
                    valueColor: theme.dataStrain,
                    context: tileContext(today: strainT, history: history(base) { $0.strain },
                                         betterHigher: nil, deadband: 0.3, positive: positiveDelta) { String(format: "%.1f", $0) },
                    series: areaSeries(base, today: strainT) { $0.strain }
                )) { metricDetail = .strain(strainT) }
                // FC en reposo — más alta es PEOR.
                metricTile(TodayMetricTile(
                    label: "Resting HR",
                    icon: "bed.double.fill",
                    value: rhrR.map { "\(Int($0.value.rounded()))" } ?? "—", unit: String(localized: "bpm"),
                    valueColor: theme.dataHeart,
                    source: rhrR?.fromApple == true ? .apple : .band,
                    context: tileContext(today: rhrR?.value, history: history(base) { $0.restingHr.map(Double.init) },
                                         betterHigher: false, deadband: 1, positive: positiveDelta) { "\(Int($0.rounded())) \(String(localized: "bpm"))" },
                    series: areaSeries(base, today: rhrR?.value) { $0.restingHr.map(Double.init) }
                )) { metricDetail = .restingHR(rhrR.map { Int($0.value.rounded()) }) }
                // Oxígeno en sangre — más alto es mejor.
                metricTile(TodayMetricTile(
                    label: "Blood Oxygen",
                    icon: "drop.fill",
                    value: spo2R.map { String(format: "%.0f", $0.value) } ?? "—", unit: "%",
                    valueColor: theme.dataSpO2,
                    source: spo2R?.fromApple == true ? .apple : .band,
                    context: tileContext(today: spo2R?.value, history: history(base) { $0.spo2Pct },
                                         betterHigher: true, deadband: 0.5, positive: positiveDelta) { "\(Int($0.rounded())) %" },
                    series: areaSeries(base, today: spo2R?.value) { $0.spo2Pct }
                )) { metricDetail = .spo2(spo2R?.value) }
                // Pasos — sin meta (no existe en la app); más es mejor.
                metricTile(TodayMetricTile(
                    label: "Steps",
                    icon: "figure.walk",
                    value: stepsT.map { intString($0) } ?? "—",
                    valueColor: theme.dataSteps,
                    source: .apple,
                    context: tileContext(today: stepsT, history: history(base) { $0.steps.map(Double.init) },
                                         betterHigher: true, deadband: 100, positive: positiveDelta) { intString($0) },
                    series: areaSeries(base, today: stepsT) { $0.steps.map(Double.init) }
                )) { metricDetail = .steps(stepsFresh) }
                // Estrés — más alto es PEOR; valor bandeado por nivel 0–3 (verde/ámbar/rojo).
                metricTile(TodayMetricTile(
                    label: "Stress",
                    icon: "gauge.medium",
                    value: stressT.map { String(format: "%.1f", $0) } ?? "—",
                    unit: stressT == nil ? nil : "/ 3",
                    valueColor: stressT.map(stressDataColor) ?? theme.inkTertiary,
                    source: .calculated,
                    context: tileContext(today: stressT, history: stressHistory,
                                         betterHigher: false, deadband: 0.1, positive: positiveDelta) { String(format: "%.1f", $0) },
                    // El estrés no es campo de DailyMetric: su serie sale del proxy diario 0–3 (incluye hoy).
                    series: Array((stress?.fullTrend ?? []).suffix(14).map { $0.value })
                )) { metricDetail = .stress(stressT) }
                // Respiración — «en rango» es lo normal; sin valencia simple (Δ en tinta neutra). FER-550.
                metricTile(TodayMetricTile(
                    label: "Respiration",
                    icon: "lungs.fill",
                    value: respR.map { String(format: "%.1f", $0.value) } ?? "—", unit: String(localized: "rpm"),
                    valueColor: theme.dataSpO2,
                    source: respR?.fromApple == true ? .apple : .band,
                    context: tileContext(today: respR?.value, history: history(base) { $0.respRateBpm },
                                         betterHigher: nil, deadband: 0.5, positive: positiveDelta) { String(format: "%.1f", $0) },
                    series: areaSeries(base, today: respR?.value) { $0.respRateBpm }
                )) { metricDetail = .respiratory(respR?.value) }
            }
        }
    }

    /// Leyenda de fuente (FER-575, reubicada en FER-581 al renglón del rótulo «Métricas de hoy»): mapea
    /// cada punto de color a su fuente. Oculta a VoiceOver — cada pill/tile ya anuncia su fuente vía el
    /// `accessibilityLabel` del punto (`SourceChip`), así que repetirla aquí sería ruido.
    private var sourceLegend: some View {
        HStack(spacing: NoopMetrics.space2) {
            legendDot(theme.dataRecovery, "Band")
            legendDot(theme.dataSpO2, "Apple Health source")
            legendDot(theme.inkTertiary, "Calculated")
        }
        .accessibilityHidden(true)
    }

    private func legendDot(_ color: Color, _ label: LocalizedStringKey) -> some View {
        HStack(spacing: NoopMetrics.space1) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
    }

    /// La pastilla de pulso vivo (FER-194), en el encabezado de «Métricas de hoy» (FER-467). Solo aparece
    /// con strap visto; tocarla abre el monitor latido-a-latido. (El anclaje `withPulsePill` a la línea
    /// del veredicto, FER-282, se retiró: el pulso ya no vive en el héroe / página 1.)
    private var pulsePill: some View {
        LivePulsePill(liveBpm: liveBpm, isLiveHR: isLiveHR, lastSyncedAt: live.lastSyncedAt,
                      backfilling: live.backfilling || live.draining,
                      chunks: live.syncChunksThisSession,
                      onTap: { showLiveMonitor = true })
    }

    // MARK: - Vistazo (FER-550)

    /// El «Vistazo» del handoff: Recuperación · HRV · Sueño en 3 pills compactas (icono + chevron arriba,
    /// valor en color de métrica, «±N vs media»), cada una tocable hacia su detalle. Reusa el mismo cálculo
    /// de delta vs media de 7 días que los tiles (`tileContext`), sin la mini-banda.
    @ViewBuilder
    private func glanceRow(recovery: Double?, hrv: (value: Double, fromApple: Bool)?,
                           sleep: (value: Double, fromApple: Bool)?, base: [DailyMetric], positive: Color) -> some View {
        // FER-552: la recuperación de hoy es de banda salvo que sea un estimado de Apple (noche sin banda).
        let recSource: MetricSource = repo.isRecoveryEstimated(Repository.localDayKey(Date())) ? .apple : .band
        return HStack(alignment: .top, spacing: NoopMetrics.gap) {
            glancePill(label: "Recovery", icon: "heart.fill", color: theme.dataRecovery,
                       value: recovery.map { "\(Int($0.rounded()))" } ?? "—", unit: nil, source: recSource,
                       today: recovery, history: history(base) { $0.recovery },
                       betterHigher: true, deadband: 2, positive: positive, format: { "\(Int($0.rounded()))" }) {
                metricDetail = .recovery(score: recoveryScore,
                                         calibrationNights: recoveryCalibration,
                                         nightsNeeded: Baselines.minNightsSeed)
            }
            glancePill(label: "HRV", icon: "waveform.path.ecg", color: theme.dataHrv,
                       value: hrv.map { "\(Int($0.value.rounded()))" } ?? "—", unit: String(localized: "ms"),
                       source: hrv?.fromApple == true ? .apple : .band,
                       today: hrv?.value, history: history(base) { $0.avgHrv },
                       betterHigher: true, deadband: 1, positive: positive, format: { "\(Int($0.rounded()))" }) {
                metricDetail = .hrv(hrv?.value)
            }
            glancePill(label: "Sleep", icon: "moon.fill", color: theme.dataSleep,
                       value: sleep.map { sleepText($0.value) } ?? "—", unit: nil,
                       source: sleep?.fromApple == true ? .apple : .band,
                       today: sleep?.value, history: history(base) { $0.totalSleepMin },
                       betterHigher: true, deadband: 5, positive: positive, format: { sleepDeltaText($0) }) {
                metricDetail = .sleep(sleep.map { Int($0.value.rounded()) })
            }
        }
    }

    /// Una pill del Vistazo, envuelta en su `Button` tocable (mismo realce que los tiles). El delta vs media
    /// se computa con `tileContext` (se ignora su banda) para no duplicar la lógica.
    private func glancePill(label: LocalizedStringKey, icon: String, color: Color,
                            value: String, unit: String?, source: MetricSource,
                            today: Double?, history: [Double], betterHigher: Bool?, deadband: Double,
                            positive: Color, format: @escaping (Double) -> String,
                            onTap: @escaping () -> Void) -> some View {
        let ctx = tileContext(today: today, history: history, betterHigher: betterHigher,
                              deadband: deadband, positive: positive, format)
        return Button(action: onTap) {
            GlancePill(label: label, icon: icon, color: color, value: value, unit: unit, source: source, delta: ctx)
        }
        .buttonStyle(TileButtonStyle(liftBorder: theme.hairlineStrong))
        .accessibilityHint(Text("Abre el detalle"))
    }

    /// Una pill compacta del Vistazo: icono + chevron arriba, valor grande en color de métrica, y «±N vs
    /// media» (reusa las claves `vs avg` / `At your average` de los tiles → es «vs media» / «En tu media»).
    private struct GlancePill: View {
        let label: LocalizedStringKey
        let icon: String
        let color: Color
        let value: String
        var unit: String? = nil
        var source: MetricSource = .band
        let delta: TileContext?
        @Environment(\.instrumentoTheme) private var theme

        private var isEmpty: Bool { value == "—" }

        /// El valor con los DÍGITOS al tamaño grande y las LETRAS de unidad inline (la «h»/«m» de «5h 31m»)
        /// en chico — igual que el «ms» de HRV (FER-575 follow-up). Así un valor ancho como el de sueño
        /// conserva sus dígitos al MISMO tamaño que «71»/«58» en vez de encoger toda la cadena por no caber
        /// (el `minimumScaleFactor` solo encogía a sueño, rompiendo la paridad). Sin letras («71») = Text
        /// normal. Las corridas se concatenan en un solo `Text`, así baseline-alinean como «58 ms».
        private var valueText: Text {
            var out = Text(verbatim: "")
            var run = ""
            var runIsLetter = false
            func flush() {
                guard !run.isEmpty else { return }
                let f = runIsLetter ? StrandFont.caption : StrandFont.number(21, weight: .semibold)
                out = out + Text(verbatim: run).font(f)
                run = ""
            }
            for ch in value {
                if !run.isEmpty && ch.isLetter != runIsLetter { flush() }
                runIsLetter = ch.isLetter
                run.append(ch)
            }
            flush()
            return out
        }

        var body: some View {
            VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                // FER-575: ícono + TÍTULO de la métrica (antes solo el ícono, con un chevron). El título da
                // contexto sin depender de reconocer el glifo; en tinta (color solo en el dato). El chevron
                // se retiró: en pills de 3-por-fila competía por el ancho con el título (la pill sigue siendo
                // un botón tappable, igual que los tiles, que tampoco lo llevan).
                HStack(spacing: NoopMetrics.space1) {
                    Image(systemName: icon).font(.system(size: 12, weight: .medium))
                        .foregroundStyle(isEmpty ? theme.inkDim : color)
                        .accessibilityHidden(true)
                    Text(label).instrumentoOverline()
                        .foregroundStyle(theme.inkSecondary)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Spacer(minLength: 0)
                }
                HStack(alignment: .firstTextBaseline, spacing: NoopMetrics.space1) {
                    valueText
                        .foregroundStyle(isEmpty ? theme.inkDim : color)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    if let unit {
                        Text(unit).font(StrandFont.caption).foregroundStyle(isEmpty ? theme.inkDim : theme.inkTertiary)
                    }
                }
                HStack(spacing: NoopMetrics.space1) {
                    deltaView
                    Spacer(minLength: 0)
                    if !isEmpty { SourceChip(source: source) }   // FER-552: fuente real del dato
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, NoopMetrics.gap).padding(.vertical, NoopMetrics.space2)
            .background {
                RoundedRectangle(cornerRadius: NoopMetrics.tileRadius, style: .continuous)
                    .fill(theme.surface)
                    .shadow(color: theme.ink.opacity(0.05), radius: 1.5, x: 0, y: 1)
            }
            .overlay(RoundedRectangle(cornerRadius: NoopMetrics.tileRadius, style: .continuous)
                .strokeBorder(theme.hairline, lineWidth: 1))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(label))
        }

        /// «+N vs media» / «−N vs media» / «En tu media». Mientras no hay base (≥4 días) o no hay valor de
        /// hoy, reserva el alto con un renglón vacío para que las 3 pills queden parejas.
        @ViewBuilder private var deltaView: some View {
            switch delta {
            case let .ready(change):
                switch change {
                case let .above(magnitude, c, _):
                    HStack(spacing: NoopMetrics.space1) { Text(verbatim: "+\(magnitude)"); Text("vs avg") }
                        .font(StrandFont.caption).foregroundStyle(c).lineLimit(1).minimumScaleFactor(0.6)
                case let .below(magnitude, c, _):
                    HStack(spacing: NoopMetrics.space1) { Text(verbatim: "−\(magnitude)"); Text("vs avg") }
                        .font(StrandFont.caption).foregroundStyle(c).lineLimit(1).minimumScaleFactor(0.6)
                case let .equal(c):
                    Text("At your average").font(StrandFont.caption).foregroundStyle(c)
                        .lineLimit(1).minimumScaleFactor(0.6)
                }
            case .building:
                // Paridad con los tiles: aún sin ≥4 días de base para una media honesta.
                Text("Still building your average").font(StrandFont.caption)
                    .foregroundStyle(theme.inkTertiary).lineLimit(1).minimumScaleFactor(0.6)
            case .none:
                // Sin valor de hoy: el «—» del valor ya lo dice; el renglón vacío mantiene parejas las 3.
                Text(verbatim: " ").font(StrandFont.caption)
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
                             positive: Color, _ format: (Double) -> String) -> TileContext? {
        guard let t = today else { return nil }
        let valid = history.filter { $0.isFinite }
        guard valid.count >= 4 else { return .building }
        let mean = valid.reduce(0, +) / Double(valid.count)
        let change = t - mean
        if abs(change) <= deadband { return .ready(change: .equal(color: theme.inkTertiary)) }
        let up = change > 0
        // Mejora → `positive` (verde AA-en-texto-chico); empeora → `negativeText` (= critical, ya pasa
        // 4.5:1); sin valencia (carga / FC) → tinta neutra. Ambos son los tokens de texto tintado <24pt.
        // Solo las métricas CON valencia (mejora/empeora) llevan la pastilla tintada del handoff; las sin
        // valencia (carga / FC, `betterHigher == nil`) van en tinta neutra sin pastilla (= «NEU» transparente
        // del mock).
        let valenced = betterHigher != nil
        let color: Color = betterHigher.map { (up == $0) ? positive : theme.negativeText } ?? theme.inkTertiary
        let mag = format(abs(change))
        return .ready(change: up ? .above(magnitude: mag, color: color, tinted: valenced)
                                 : .below(magnitude: mag, color: color, tinted: valenced))
    }

    /// FER-551: la serie de hasta 14 días para la mini-gráfica de ÁREA del tile — valores diarios válidos
    /// (sin huecos: `compactMap` los salta, así no se dibujan valles en cero falsos) terminando en el valor
    /// de hoy cuando existe (la cabeza de la línea). Lee de la misma base de display que el delta.
    private func areaSeries(_ base: [DailyMetric], today: Double?, _ pick: (DailyMetric) -> Double?) -> [Double] {
        let prior = Array(base.compactMap(pick).suffix(today == nil ? 14 : 13))
        return today.map { prior + [$0] } ?? prior
    }

    /// Δ de sueño en unidades de una letra: «18m» bajo una hora, «1h 5m» a partir de una (FER-575 follow-up:
    /// «18 min» era más ancho que «+27» y el `minimumScaleFactor` encogía solo el delta de sueño).
    private func sleepDeltaText(_ minutes: Double) -> String {
        let m = Int(minutes.rounded())
        return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)m"
    }

    /// El color del valor de Estrés por banda 0–3, en roles del tema (regla: color saturado solo en el
    /// dato). Bajo → `verdict`, medio → `warning`, alto → `critical`. Reusa `StressBand` (StressView).
    private func stressDataColor(_ score: Double) -> Color {
        StressBand(score: score).dataColor(theme)
    }

    /// El contexto de un tile/pill vs su media de 7 días (FER-258): el cambio en lenguaje. `building` = aún
    /// no hay ≥4 días de base para una media honesta. La ausencia (sin valor de hoy) se modela con el
    /// Optional: nil → sin delta. (La mini-gráfica de área del tile va por su propia serie, FER-551.)
    private enum TileContext {
        case building
        case ready(change: TileChange)
    }

    /// El cambio de hoy contra la media de 7 días, ya formateado + con color por polaridad. `equal` es
    /// «En tu media de 7 días» (dentro del deadband).
    private enum TileChange {
        case above(magnitude: String, color: Color, tinted: Bool)
        case below(magnitude: String, color: Color, tinted: Bool)
        case equal(color: Color)
    }


    /// Un tile de «Métricas de hoy»: etiqueta (overline en tinta) · valor en color de dato + unidad ·
    /// mini-banda del rango típico (p25–p75) con el tick de hoy · pie partido — cambio vs tu media de
    /// 7 días (izquierda, FER-258) + badge de fuente (derecha): W = banda, ♥ = Apple Salud (FER-233).
    /// Tematizado con tokens de `InstrumentoTheme` sobre el papel `surface` con hairline — sin el
    /// `NoopCard` oscuro, que no lee sobre el papel claro. Lee el tema del entorno.
    /// FER-552 (A1): de dónde vino un dato ESE día. Dinámico por-dato; lo resuelve cada call site desde
    /// `fromApple` (ya filtrado por el modo activo) o, para los derivados, fijo. No toca el motor de fuentes.
    private enum MetricSource { case band, apple, calculated }

    /// Indicador de fuente como PUNTO de color (FER-575): banda (verde) · Apple (azul) · calculado (gris),
    /// reusando los mismos colores que el chip-palabra anterior. Sustituir la palabra por un punto libera
    /// el ancho que truncaba «+27 vs media»; su significado lo define la leyenda al pie de la sección.
    /// Conserva la fuente para VoiceOver (etiqueta accesible) — la lee el `children: .combine` del padre.
    private struct SourceChip: View {
        let source: MetricSource
        @Environment(\.instrumentoTheme) private var theme
        private var dotColor: Color {
            switch source {
            case .band:       return theme.dataRecovery
            case .apple:      return theme.dataSpO2
            case .calculated: return theme.inkTertiary
            }
        }
        private var sourceName: LocalizedStringKey {
            switch source {
            case .band:       return "Band"
            case .apple:      return "Apple Health source"
            case .calculated: return "Calculated"
            }
        }
        var body: some View {
            Circle().fill(dotColor).frame(width: 7, height: 7)
                .accessibilityElement()
                .accessibilityLabel(sourceName)
        }
    }

    private struct TodayMetricTile: View {
        let label: LocalizedStringKey
        /// SF Symbol de la métrica (handoff «Hoy · Estados»): un glifo junto a la etiqueta, en el color
        /// del dato. Es otra licencia consciente sobre «color solo en el dato» (como las pastillas),
        /// fiel al handoff; refuerza la identidad de la métrica de un vistazo. Declarado aquí (tras
        /// `label`) para que el init sintetizado case con el orden de los call sites (icon tras label).
        var icon: String? = nil
        let value: String
        var unit: String? = nil
        let valueColor: Color
        /// FER-552: la fuente real del dato de hoy (banda / Apple / calculado) → chip dinámico en el pie.
        var source: MetricSource = .band
        var context: TileContext? = nil
        /// FER-551: los hasta 14 valores diarios para la mini-gráfica de área (la cabeza = hoy). Vacío o
        /// con <3 puntos → no se dibuja el área (cae al placeholder/«armando»).
        var series: [Double] = []
        /// Hint shown in the footer when there's no value/context (e.g. «Esta noche» for a day-scoped
        /// tile with no reading for today yet). FER-341.
        var placeholder: LocalizedStringKey? = nil
        @Environment(\.instrumentoTheme) private var theme

        /// Sin lectura de hoy → el valor es el em-dash «—». En ese caso el tile «no tiene nada»: el ícono
        /// y el valor (y la unidad) se atenúan a `inkDim` (gris apagado del handoff) en vez del color de
        /// la métrica. Es por-tile, así que en «Base Apple Salud» las filas prestadas siguen a color y las
        /// strap-only se apagan. (handoff «Hoy · Estados»)
        private var isEmpty: Bool { value == "—" }

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                // Glifo de la métrica + etiqueta a UNA línea (FER-189): el ícono en el color del dato
                // (handoff) y un nombre largo (Frecuencia cardíaca) se encoge un poco en vez de envolver
                // a 2 líneas y crecer el alto.
                HStack(spacing: NoopMetrics.space1) {
                    if let icon {
                        Image(systemName: icon)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(isEmpty ? theme.inkDim : valueColor)
                            .accessibilityHidden(true)
                    }
                    Text(label).instrumentoOverline()
                        .foregroundStyle(theme.inkSecondary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                Spacer(minLength: NoopMetrics.space1)
                HStack(alignment: .firstTextBaseline, spacing: NoopMetrics.space1) {
                    // Valor 23 (handoff «Hoy · Estados», antes 22). Piso de escala = 18/23 (FER-273): el
                    // valor lleva color de DATO (3.5–3.6:1), que solo cumple AA como texto GRANDE (≥18pt,
                    // 3:1). El piso nunca lo baja de 18pt, así el color de dato siempre cumple AA-grande.
                    Text(value).font(StrandFont.number(23)).foregroundStyle(isEmpty ? theme.inkDim : valueColor)
                        .lineLimit(1).minimumScaleFactor(18.0 / 23.0)
                    if let unit {
                        Text(unit).font(StrandFont.subhead).foregroundStyle(isEmpty ? theme.inkDim : theme.inkTertiary)
                    }
                }
                Spacer(minLength: NoopMetrics.space1)
                // FER-551: mini-gráfica de ÁREA de 14 días (línea + relleno tenue), tintada por el hue de la
                // métrica, con la cabeza en el valor de hoy. Reemplaza la banda p25–p75 de 7 días. Con <3
                // puntos no se dibuja (el footer muestra «armando»/placeholder en su lugar).
                if series.count >= 3 {
                    MetricArea(series: series, color: isEmpty ? theme.inkDim : valueColor)
                    Spacer(minLength: NoopMetrics.space1)
                }
                footer
            }
            .padding(.horizontal, NoopMetrics.gap).padding(.vertical, NoopMetrics.space2)
            // Alto base 92: el área de 14 días (FER-551) suma un renglón sobre el layout compacto previo
            // (label + valor + área + pie). Sigue siendo PISO, no tope (FER-394): el tile crece con Dynamic
            // Type grande en vez de cortar texto.
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
            // Tarjeta blanca con elevación sutil (handoff «Hoy · Estados»): radio 17 + una sombra cálida
            // tenue (`ink` al 5 %, y:1) sobre el papel — la sombra va en la SILUETA del tile (la forma del
            // fondo), no en el contenido, así no proyecta el texto. El relleno sigue siendo el `surface`
            // del tema (blanco cálido por el día, hora-consciente — no `#fff` literal, que destellaría de
            // noche). Borde hairline al ras.
            .background {
                RoundedRectangle(cornerRadius: NoopMetrics.tileRadius, style: .continuous)
                    .fill(theme.surface)
                    .shadow(color: theme.ink.opacity(0.05), radius: 1.5, x: 0, y: 1)
            }
            .overlay(RoundedRectangle(cornerRadius: NoopMetrics.tileRadius, style: .continuous)
                .strokeBorder(theme.hairline, lineWidth: 1))
            .accessibilityElement(children: .combine)
        }

        /// El pie del tile en UNA línea: el cambio vs la media de 7 días (izquierda, FER-258 — el dueño lo
        /// pidió conservado) + el badge de fuente (derecha). La mini-gráfica ya no vive aquí: subió a su
        /// propio renglón como ÁREA de 14 días (FER-551). Sin base → «armando»; sin valor → placeholder.
        @ViewBuilder private var footer: some View {
            HStack(spacing: NoopMetrics.space1) {
                switch context {
                case let .ready(change):
                    changeText(change)
                    Spacer(minLength: 0)
                case .building:
                    Text("Still building your average")
                        .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                case .none:
                    if let placeholder {
                        Text(placeholder)
                            .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    Spacer(minLength: 0)
                }
                sourceBadge
            }
        }

        /// El cambio vs la media: deadband → «En tu media»; subir/bajar → flecha + magnitud + «vs media».
        /// VoiceOver lee la frase completa «sobre/bajo tu media de 7 días» (la flecha va oculta).
        @ViewBuilder private func changeText(_ change: TileChange) -> some View {
            switch change {
            case let .above(magnitude, color, tinted): deltaLabel(up: true, magnitude: magnitude, color: color, tinted: tinted)
            case let .below(magnitude, color, tinted): deltaLabel(up: false, magnitude: magnitude, color: color, tinted: tinted)
            case let .equal(color):
                Text("At your average")
                    .font(StrandFont.caption).foregroundStyle(color)
                    .lineLimit(1).minimumScaleFactor(0.7).layoutPriority(1)
            }
        }

        /// El cambio vs la media, en la pastilla tintada del handoff: flecha + magnitud + «vs avg». Con
        /// valencia (`tinted`) el texto va en su color de delta sobre un lavado del mismo color al 12 % en
        /// cápsula (verde para mejora, rojo para empeora); sin valencia va en tinta neutra SIN pastilla
        /// (= «NEU» transparente del mock). La cápsula es la única excepción a «color solo en el dato» que
        /// el dueño aprobó para este handoff.
        private func deltaLabel(up: Bool, magnitude: String, color: Color, tinted: Bool) -> some View {
            HStack(spacing: NoopMetrics.space1) {
                Image(systemName: up ? "arrow.up" : "arrow.down")
                    .font(.system(size: 10, weight: .semibold))
                Text(verbatim: magnitude)
                Text("vs avg")
            }
            .font(StrandFont.caption)
            .foregroundStyle(color)
            .lineLimit(1).minimumScaleFactor(0.7)
            .padding(.horizontal, tinted ? 6 : 0)
            .padding(.vertical, tinted ? 2 : 0)
            .background { if tinted { Capsule().fill(color.opacity(0.12)) } }
            // `layoutPriority` va en el modifier MÁS EXTERNO (tras el padding/cápsula): así el HStack del pie
            // le da al pastillón su ancho intrínseco completo y la mini-banda cede — sin esto el pie partía
            // el texto («17… vs…»). El piso de escala 0.7 sigue degradando con gracia en Dynamic Type grande.
            .layoutPriority(1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(up ? "\(magnitude) above your 7-day average"
                                         : "\(magnitude) below your 7-day average"))
        }

        /// Badge de fuente (FER-552, opción A): chip explícito BANDA / APPLE / CALCULADO con la fuente real
        /// del dato del día. Se oculta sin lectura de hoy («—»): un dato ausente no tiene fuente que marcar.
        @ViewBuilder private var sourceBadge: some View {
            if !isEmpty { SourceChip(source: source) }
        }
    }

    /// La mini-gráfica de ÁREA del tile (FER-551, handoff «Hoy · tendencia 14 días»): la línea de los
    /// hasta 14 valores diarios + un relleno tenue del mismo hue, con un punto-cabeza en el último valor
    /// (hoy). Normaliza al rango real (min…max) de la serie; con la serie plana traza una línea al centro.
    /// Decorativa para VoiceOver (el delta del pie ya narra la tendencia en lenguaje).
    private struct MetricArea: View {
        let series: [Double]
        let color: Color
        private let vInset: CGFloat = 2

        var body: some View {
            GeometryReader { geo in content(size: geo.size) }
                .frame(height: 22)
                .accessibilityHidden(true)
        }

        private func content(size: CGSize) -> some View {
            let pts = points(in: size)
            let line = Path { p in
                for (i, c) in pts.enumerated() { i == 0 ? p.move(to: c) : p.addLine(to: c) }
            }
            let fill = Path { p in
                guard let first = pts.first, let last = pts.last else { return }
                p.move(to: CGPoint(x: first.x, y: size.height))
                for c in pts { p.addLine(to: c) }
                p.addLine(to: CGPoint(x: last.x, y: size.height))
                p.closeSubpath()
            }
            return ZStack {
                fill.fill(color.opacity(0.12))
                line.stroke(color, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                if let last = pts.last {
                    Circle().fill(color).frame(width: 3.5, height: 3.5).position(last)
                }
            }
        }

        /// Mapea la serie a puntos en el rectángulo, normalizando al rango real (min…max) con un inset
        /// vertical para que el trazo y el punto-cabeza no se recorten. Serie plana → línea al centro.
        private func points(in size: CGSize) -> [CGPoint] {
            let lo = series.min() ?? 0, hi = series.max() ?? 1
            let flat = (hi - lo) <= .ulpOfOne
            let span = Swift.max(hi - lo, .ulpOfOne)
            let n = series.count
            return series.indices.map { i in
                let x = n <= 1 ? size.width / 2 : size.width * CGFloat(i) / CGFloat(n - 1)
                // Serie plana → línea al CENTRO (sin un valle al fondo por un span de ~cero).
                let frac = flat ? 0.5 : CGFloat((series[i] - lo) / span)
                let y = (size.height - vInset) - frac * (size.height - 2 * vInset)
                return CGPoint(x: x, y: y)
            }
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
                .overlay(RoundedRectangle(cornerRadius: NoopMetrics.tileRadius, style: .continuous)
                    .strokeBorder(configuration.isPressed ? liftBorder : Color.clear, lineWidth: 1))
                .scaleEffect(configuration.isPressed ? 1.03 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.72), value: configuration.isPressed)
        }
    }

    /// On-device readiness for the verdict hero (`ReadinessEngine`).
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

    // MARK: - Loading

    private func loadAll() async {
        // Siembra el veredicto + los conteos derivados de HRV una sola vez por refresh, ANTES de los
        // awaits de abajo, para que el body deje de recalcular `ReadinessEngine.evaluate` en cada frame
        // (FER-172). `recomputeDerived()` es síncrono y lee `repo.days`/`today`/`appleHealthDays`, ya
        // disponibles sin esperar las consultas de sparklines.
        recomputeDerived()
        // FER-475: con los datos ya sembrados, decide UNA vez el aterrizaje del pager — si no hay veredicto
        // (madrugada / esperando el sync), abre en Métricas (página 2), donde sí hay algo que ver.
        maybeAutoLandMetrics()
        // Issue every query concurrently, then collect. The store is a serial DatabaseQueue so I/O still
        // serializes, but the memoized ensureStore() makes the parallel first-callers share ONE open, and
        // the queries run back-to-back with no main-actor ping-pong.
        async let adRows     = repo.appleDailyRows()
        async let amRows     = repo.appleDailyMetricRows()
        // Stored daily "stress" series (0–3) — the model prefers it, else derives from RHR/HRV. (FER-180)
        async let stressRows = repo.series(key: "stress", source: "my-whoop")

        // Today's HR trend — 5-minute bucket means from local midnight → now.
        let startOfToday = Int(Calendar.current.startOfDay(for: Date()).timeIntervalSince1970)
        let nowTs = Int(Date().timeIntervalSince1970)
        async let hrBucketRows = repo.hrBuckets(from: startOfToday, to: nowTs, bucketSeconds: 300)

        appleDays = await adRows
        appleMetricDays = (await amRows).sorted { $0.day < $1.day }
        hrPoints  = await hrBucketRows
            .map { TrendPoint(date: Date(timeIntervalSince1970: TimeInterval($0.ts)), value: $0.bpm) }
        // Build today's stress model from the day rows + stored series (nil when there's no usable
        // signal yet — the tile then placeholders "—"). Reads `displayDays` (Apple-health fallback,
        // FER-149) so a strap-partial night still derives, and anchors "today" to the local day so a
        // UTC-bucketed "tomorrow" row (FER-226) can't blank the tile.
        stress = StressModel(days: repo.displayDays, stored: await stressRows, todayKey: Repository.localDayKey(Date()))
        await loadTrainingPlan()
        // «La conexión de hoy» (FER-614): los hallazgos rankeados, misma fuente que Patrones.
        insights = await InsightsProvider.generate(repo: repo, today: Repository.localDayKey(Date()))
    }

    /// Carga los insumos del bloque «Hoy en tu plan» (FER-613): el split, la rutina de hoy y la racha de
    /// días cumpliendo el plan — esta última vía el helper compartido `TrainingStreak`, así sale EXACTAMENTE
    /// igual que la que muestra Entrenar. Lee del mismo store que `EntrenarView.load()`.
    private func loadTrainingPlan() async {
        guard let store = await repo.storeHandle() else { return }
        let sched = (try? await store.routineSchedule()) ?? []
        let split = Dictionary(sched.map { ($0.weekday, $0.routineId) }, uniquingKeysWith: { a, _ in a })
        let byId = Dictionary((await repo.routines()).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let sessions = await repo.recentSessions(limit: 200)
        let tid = WeeklySplit.todayRoutineId(split: split, todayWeekday: Calendar.current.component(.weekday, from: Date()))
        hasSplit = !split.isEmpty
        todayRoutineName = tid.flatMap { byId[$0]?.name }
        trainingStreak = TrainingStreak.streak(sessions: sessions, split: split)
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
                  let date = Repository.parseDayKey(row.day) else { return nil }
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

    /// Full-history `(day, value)` series for a migrated metric's levels instrument (FER-607) — the SAME
    /// `displayDays` source as the 14-day trend but with NO cutoff, so `MetricInfoSheet`'s range selector
    /// can re-window across S/M/3M/6M/1A/Todo. Supplied only for migrated metrics (pilot: resting HR);
    /// every other metric returns nil and keeps the classic 14-day summary.
    private func levelsSeriesLoader(for id: String) -> (() async -> [(day: String, value: Double)])? {
        // Stress isn't a stored `DailyMetric` field — its daily 0–3 series lives in `StressModel.fullTrend`
        // (the same source as its trend). Map each point's date to a day key for the levels math. (FER-621)
        if id == "stress" {
            return { (self.stress?.fullTrend ?? []).map { (day: Repository.localDayKey($0.date), value: $0.value) } }
        }
        let pick: (DailyMetric) -> Double?
        switch id {
        case "rhr":       pick = { $0.restingHr.map(Double.init) }
        case "hrv":       pick = { $0.avgHrv }
        case "spo2":      pick = { $0.spo2Pct }
        case "resp_rate": pick = { $0.respRateBpm }
        case "sleep":     pick = { $0.totalSleepMin }
        case "steps":     pick = { $0.steps.map(Double.init) }
        case "strain":    pick = { $0.strain }
        default:          return nil
        }
        // Steps and Day Strain accumulate through the day — drop today's still-in-progress point so the
        // levels count completed days only (same guard `bandSummary` uses, FER-264). Nightly metrics
        // (rhr/spo2/sleep/resp) are already complete each morning, so they keep every point.
        let dropInProgressToday = (id == "steps" || id == "strain")
        return {
            var series = repo.displayDays.compactMap { row in pick(row).map { (day: row.day, value: $0) } }
            if dropInProgressToday, series.count > 1, series.last?.day == Repository.localDayKey(Date()) {
                series.removeLast()
            }
            return series
        }
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

    // MARK: - Derived text

    /// Sleep minutes → "Xh Ym".
    private func sleepText(_ mins: Double) -> String {
        "\(Int(mins) / 60)h \(Int(mins) % 60)m"
    }

    /// FER-546: the value a measured tile (HRV / resting HR / SpO₂) shows MUST match the LAST point of its
    /// own 14-day chart — both read `repo.displayDays` (the layered Apple-base + strap source `loadTrend`
    /// plots) — so the big number and the graph never disagree. Returns the most recent `displayDays` row
    /// within the chart's 14-day window that has a value, plus whether that day is Apple-sourced (so the tile
    /// badges it right). Distinct from `resolveMeasured` (strap-first, capped at yesterday), which still feeds
    /// the recovery / stress path — `latestFromDisplay` only governs the measured tiles + their summary sheet.
    private func latestFromDisplay(_ pick: (DailyMetric) -> Double?) -> (value: Double, fromApple: Bool)? {
        let cutoff = Repository.localDayKey(Calendar.current.date(byAdding: .day, value: -13, to: Date()) ?? Date())
        let candidates = repo.displayDays.filter { $0.day >= cutoff && pick($0) != nil }
        guard let row = candidates.max(by: { $0.day < $1.day }), let v = pick(row) else { return nil }
        return (v, repo.appleHealthDays.contains(row.day))
    }

    /// Resolve a measured signal (HRV / sleep / resting HR / SpO₂) for the Today tiles. Today's row
    /// wins; otherwise the most recent value within the freshness window (today/yesterday) so a fresh
    /// Apple-Health import or sync still reads on the tile — but never older, since a stale value under
    /// a "Today" header would misrepresent it (same spirit as the #23/#49 trailing-window fixes).
    /// `fromApple` flags Apple-sourced values so the row badges them instead of passing them off as a
    /// live strap reading. Returns nil when nothing fresh exists → the row placeholders. (FER-62 follow-up)
    /// `todayOnly` drops the yesterday fallback: a day-scoped tile (Sueño) shows ONLY today's value, so it
    /// never passes yesterday's off as today's at the midnight boundary (FER-341).
    private func resolveMeasured(todayOnly: Bool = false,
                                 _ pick: (DailyMetric) -> Double?) -> (value: Double, fromApple: Bool)? {
        let todayKey = Repository.localDayKey(Date())
        if let d = repo.today, let v = pick(d) { return (v, repo.appleHealthDays.contains(todayKey)) }
        let cutoff = todayOnly ? todayKey
            : Repository.localDayKey(Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date())
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

    /// Thousands-grouped integer string (steps / calories).
    private func intString(_ v: Double) -> String { StrandFormat.groupedInt(v) }

    /// FER-487: did TODAY's reading for a narrative vital come from Apple Health (not the band)? Mirrors
    /// the per-reading `fromApple` resolution behind the Key Metrics source badge so the detail's «Apple»
    /// seal matches the tile that opened it. From Hoy only hrv/rhr/spo2 open this detail; Heart Rate
    /// (intraday, band-only) and Steps stay unsealed.
    private func todayVitalFromApple(_ key: String) -> Bool {
        switch key {
        case "hrv":       return resolveMeasured { $0.avgHrv }?.fromApple == true
        case "rhr":       return resolveMeasured { $0.restingHr.map(Double.init) }?.fromApple == true
        case "spo2":      return resolveMeasured { $0.spo2Pct }?.fromApple == true
        case "resp_rate": return resolveMeasured { $0.respRateBpm }?.fromApple == true
        default:          return false
        }
    }

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
        .environmentObject(TabRouter())
        #if os(iOS)
        // iOS TodayView reads AppModel (first-launch "Scan for strap" CTA) and HealthKitBridge (the
        // Apple Health connect nudge); inject both so the iOS canvas renders instead of trapping on a
        // missing environment object.
        .environmentObject(AppModel())
        .environmentObject(HealthKitBridge(repo: repo, appleDeviceId: "preview-apple", noopDeviceId: "preview"))
        #endif
        .frame(width: 920, height: 940)
        .preferredColorScheme(.light)
}
#endif
