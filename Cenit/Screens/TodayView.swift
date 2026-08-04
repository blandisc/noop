import SwiftUI
import StrandDesign
import StrandAnalytics
import StrandTraining
import CenitStore
import Foundation
import Inject   // recarga en caliente (dev-only, inerte en Release)


// MARK: - Hoy «Instrumento» evolucionado (FER-709, handoff 2026-07)
//
// The home screen in the EVOLVED «Instrumento diurno» voice (Space Grotesk numerals, warm paper,
// one dominant number, arithmetic transparency — see DESIGN.md §8.7).
//
// Composition (top → bottom), all inside `iosBody`:
//   (a) HEADER — date · strap battery · live BPM (tap → Latidos) · the 34pt `DialSeal` (the 24h
//                signature AND the pull-to-refresh spinner), plus the freshness line (`headerBlock`).
//   (b) HERO   — last night's SLEEP as the dominant numeral (`appleTrendHero`). FER-1029: this is the
//                ONLY hero. The 0–100 recovery verdict (band era) and the classic «Preparación» hero
//                (verdict word + needles) were retired as unreachable dead code (FER-35). The big
//                `DiurnalDial` was retired earlier; the 24h lives in the header seal.
//   (c) SEÑALES — the classic surface (`senalesPage`) now renders ONLY in the empty state (`noSources`):
//                the training-load strip + the «connect Apple Health» card. FER-1039 retired the
//                SEÑALES/BRIEF tabs and the pager; FER-35 removed the 2×4 tile grid (`iosMetricsSection`)
//                as unreachable dead code. With data, the surface is `liquidSurface` (the Liquid Glass
//                composition), not this branch.
//
// Pull-to-refresh: the seal winds up with the pull and spins while syncing; the tile values settle
// straight to their numbers (no count-up or reveal sequence on completion).

/// Identifiable wrapper so the light «Instrumento» Detalle de Sueño can ride `.sheet(item:)` from Today
/// (the model itself isn't Identifiable). Mirrors the one Cuerpo uses. (FER-251)
private struct SleepDetailItem: Identifiable {
    let id: UUID
    let model: SleepDetailModel
    /// FER-953: an explicit `id` lets the built model swap in under the SAME presentation identity.
    init(id: UUID = UUID(), model: SleepDetailModel) { self.id = id; self.model = model }
}

#if os(iOS)
/// FER-972 P-09: progreso del overscroll del pull-to-sync, aislado del árbol de `TodayView`.
/// `@Observable` invalida por-lectura: solo las subvistas que leen `progress` se re-evalúan por frame
/// durante el gesto; el padre (héroe + dial + tiles) no se reconstruye.
@MainActor
@Observable
private final class PullProgressModel {
    var progress: Double = 0
}

/// Sello del dial (34 pt): se «da cuerda» con el tirón y gira al sincronizar.
/// Lee `pullProgress.progress` en SU body — no en el de `TodayView`.
private struct PullIndicator: View {
    let pullProgress: PullProgressModel
    let isSyncing: Bool
    let reduceMotion: Bool
    let hour: Double
    let solar: SolarWindow?
    let sleep: SleepWindow?

    var body: some View {
        let seal = DialSeal(hour: hour, solar: solar, sleep: sleep)
        if isSyncing && !reduceMotion {
            TimelineView(.animation) { context in
                let angle = (context.date.timeIntervalSinceReferenceDate * 257)
                    .truncatingRemainder(dividingBy: 360)
                seal.rotationEffect(.degrees(angle))
            }
        } else {
            seal.rotationEffect(.degrees(pullProgress.progress * 270))
        }
    }
}

/// Pista del pull-to-refresh (chevron + microcopy). Se oculta al armar el tirón sin invalidar Hoy.
private struct PullSyncHint: View {
    let pullProgress: PullProgressModel
    let isSyncing: Bool
    let didFirstPullSync: Bool
    let reduceMotion: Bool
    @Environment(\.instrumentoTheme) private var theme
    @State private var hintBob = false

    private var shows: Bool { pullProgress.progress == 0 && !isSyncing }

    var body: some View {
        Group {
            if shows {
                let learning = !didFirstPullSync
                let bobbing = learning && !reduceMotion && hintBob
                VStack(spacing: CenitMetrics.space1) {
                    // Vestida de Liquid (/inject 2026-07-22): el chevron del sistema nuevo
                    // en tinta/500 — el único chrome no-Liquid que quedaba en Hoy.
                    LiquidIcon(.chevron, size: 11, color: LiquidColor.tinta500)
                        .rotationEffect(.degrees(90))
                        .offset(y: bobbing ? 4 : 0)
                        .animation(bobbing ? LiquidMotion.glassSpring(0.9).repeatForever(autoreverses: true) : nil,
                                   value: bobbing)
                    if learning {
                        Text("Pull to refresh")
                            .font(LiquidType.captionLectura)
                            .foregroundStyle(LiquidColor.tinta500)
                    }
                }
                .transition(.opacity)
                .accessibilityHidden(true)
                .onAppear { hintBob = true }
            }
        }
        .strandAnimation(StrandMotion.fade, value: shows)
    }
}
#endif

struct TodayView: View {
    // Inject: el hook vive en el struct NO privado más externo del archivo (regla PR#1036);
    // interponer el `body` global arma la copia fresca del archivo completo, privados incluidos.
    @ObserveInjection private var inject
    @EnvironmentObject var repo: Repository

    #if os(iOS)
    // iOS-only: the root app state, so the first-launch empty state's "Scan for strap" CTA can kick
    // off a real BLE scan (`AppModel.scan()`). macOS never renders the iOS body, so it never reads this.
    @Environment(AppModel.self) var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// El tema activo de «Instrumento diurno» (FER-135). El `iosBody` lo ancla al papel de día con
    /// `.instrumentoTheme(.base)`; cada sub-vista lo lee de aquí para colorear en TINTA del tema.
    @Environment(\.instrumentoTheme) private var theme
    /// Live Apple Health bridge (iOS only). Today reads `health.auth` to nudge the user to connect
    /// Apple Salud when the measured Key Metrics are empty; `showDataSources` presents Data Sources
    /// so they can connect in one tap instead of hunting through the More tab. (FER-94)
    @EnvironmentObject var health: HealthKitBridge
    /// Tab switcher — the «Explóralo en el Coach» handoff from the Detalle de Estrés (FER-452, mirrors Cuerpo).
    @EnvironmentObject var tabRouter: TabRouter
    @State private var showDataSources = false
    /// La hoja «Cómo llegué a esto» — el acta del veredicto, nuevo destino del tap del héroe.
    @State private var showVeredictoActa = false
    /// La hoja del eje AUTONÓMICO — destino del tap del orbe «Autonómico» (el desglose de sus
    /// tres señales). Reemplaza el placeholder que abría la métrica de VFC (pasada UX H2).
    @State private var showAutonomicoHoja = false
    /// Cuenta cada pull-to-refresh para disparar la háptica declarativa (`.sensoryFeedback`) al
    /// provocar el gesto de sincronización (FER-204).
    @State private var syncHaptic = 0

    /// El usuario ya hizo al menos un pull-to-sync con strap (FER-270): apaga para siempre la pista
    /// «Desliza para sincronizar» del héroe — ya aprendió el gesto. Persiste entre lanzamientos.
    @AppStorage("today.didFirstPullSync") private var didFirstPullSync = false
    // «El Ecosistema» (FER-10): la fusión de apertura es el ritual de «tu veredicto llegó»
    // — corre UNA vez por día LOCAL (dayKey local, no UTC: trampa conocida de la fila
    // fantasma). El hint «Toca para separar» se retira tras 3 separaciones acumuladas.
    @AppStorage("today.ecosistemaFusionDay") private var ecosistemaFusionDay = ""
    /// La hoja del guardián («¿qué es VIGILANDO?», FER-10 / FER-33 · F3).
    @State private var showGuardianHoja = false
    @AppStorage("today.ecosistemaSeparaciones") private var ecosistemaSeparaciones = 0

    // MARK: - Pull-to-refresh propio (FER-222)
    //
    // Reemplaza el `.refreshable` nativo (su ruedita gris de ~1 s) por un gesto que DIBUJA el
    // sello: al jalar Hoy hacia abajo, `pullProgressModel.progress` (0→1) le «da cuerda» al
    // `DialSeal` proporcional al desplazamiento; al cruzar `pullThreshold` se dispara UNA vez la
    // misma sincronización de antes (`pullToSync`) y el sello pasa a girar (modo `syncing` de
    // FER-221). El offset del tope del scroll se lee con `onScrollGeometryChange` / preference
    // (no toca el scroll normal). Bajo Reduce Motion no se dibuja el armado (el progreso se
    // queda en 0), pero el gesto sigue armando + disparando con su háptica.
    //
    // FER-972 P-09: el progreso NO es `@State` de la raíz — vive en `PullProgressModel`
    // (`@Observable`). Solo `PullIndicator` / `PullSyncHint` lo leen, así el árbol grande
    // (héroe + tiles) no se reconstruye a 60–120 Hz durante el overscroll.

    /// Progreso del tirón (0→1) en un modelo observable aislado. Se queda en 0 bajo Reduce Motion.
    @State private var pullProgressModel = PullProgressModel()
    /// El tirón ya cruzó el umbral en ESTE gesto (ya disparó el sync) — evita re-disparar hasta
    /// que el scroll vuelve al tope. Se queda en la raíz: dispara el sync una vez por gesto.
    @State private var pullCommitted = false
    /// Sync en curso DISPARADO por el tirón: hace girar el dial de inmediato (sin esperar a que
    /// `live.backfilling` arranque, p. ej. offline). Se apaga al terminar `pullToSync()`; para
    /// entonces, si arrancó un offload real, `live.backfilling` releva el giro.
    @State private var pullSyncing = false
    /// Distancia de tirón (pt) para armar y disparar. Calibrado para sentirse deliberado sin
    /// agotar el pulgar (el dial mide 180); el «feel» fino se confirma en el iPhone (FER-222).
    private let pullThreshold: CGFloat = 96
    #endif

    @State private var appleDays: [AppleDaily] = []
    // FER-663: la estimación de pasos on-device por día (key "steps_est", fuente computada "-noop"),
    // oldest→newest. Solo la escribe el motor para una WHOOP 4.0 calibrada (en 5/MG el contador nativo
    // manda y la serie queda vacía). El tile de Pasos cae a ella únicamente cuando el día no tiene
    // conteo real de Apple Salud — y siempre rotulada «est.» para que nunca se lea como conteo medido.
    @State private var stepsEst: [(day: String, value: Double)] = []
    // Apple-Health daily metric rows (sleep/HRV/RHR/SpO₂) read straight from the apple-health source,
    // so Key Metrics can fall back to them when a strap row clobbered Apple's row for the day in the
    // dashboard merge (e.g. a WHOOP 4.0 that didn't decode HRV/sleep). (FER-98)
    @State private var appleMetricDays: [DailyMetric] = []

    // Today's heart rate as 5-minute bucket means (midnight → now), for the 24h trend chart.
    @State private var hrPoints: [TrendPoint] = []

    // Today's stress (0–3 autonomic proxy) for the «Estrés» tile — the same transparent model
    // StressView builds, computed once per load from `repo.displayDays` + the stored "stress" series. (FER-180)
    @State private var stress: StressModel? = nil

    // FER-1045 «Hoy Liquid»: la ventana de la sesión de sueño de anoche (horas locales
    // 0–24) para el dial-sello; nil = sin sesión → el dial solo marca la hora.
    @State private var liquidNight: (start: Double, end: Double)? = nil
    // Pausa las animaciones ambientales Liquid (drift/pulsos) cuando Hoy no está activo.
    @Environment(\.scenePhase) private var scenePhase


    // Insights del día (FER-614), cargados en `loadAll` vía el loader compartido `InsightsProvider` (mismo
    // FDR que muestra Patrones). FER-1039: retirado el brief, el único consumidor vivo aquí es la franja de
    // carga de SEÑALES (`insights.first { .trainingLoad }`).
    @State private var insights: [Insight] = []
    // FER-872: memo de los insights por (refreshSeq, díaLocal). `loadAll` se dispara por `refreshSeq`, pero
    // un re-`.task` con el MISMO seq (misma data) no debe recomputar la correlación+FDR de nuevo — se
    // conserva el resultado. Un seq nuevo (data nueva) o el rollover de día invalidan el memo.
    @State private var memoInsightsKey: String?

    // Support sheet (donate + contact) — always reachable from the home toolbar.
    @State private var showingSupport = false

    // Metric-info sheet — tapping any Key Metrics row presents this.
    @State private var metricDetail: MetricInfo? = nil
    /// FER-953: sleep summary para la hoja de resumen Liquid, built off-main when the sleep info sheet opens.
    @State private var sleepSummaryModel: SleepDetailModel? = nil

    // Rich «Instrumento» Detalle drilled into via the summary sheet's "Ver más" (FER-251). These mirror the
    // ones Cuerpo presents — Today reuses the SAME static `.build()` factories / specs, so the detail is
    // identical from both tabs. `pendingSeeMore` defers presenting until the summary fully dismisses, so the
    // sheet-over-sheet hand-off never gets swallowed (it runs in the summary sheet's `onDismiss`).
    @State private var pendingSeeMore: (() -> Void)? = nil
    @State private var sleepDetail: SleepDetailItem? = nil
    @State private var strainDetail: StrainDetailItem? = nil
    @State private var stressDetail: StressDetailItem? = nil
    @State private var skinTempDetail: SkinTempDetailItem? = nil
    /// The «mapa del día» driver (EventKit + intraday curve), built fresh when the Detalle de Estrés opens
    /// from Today — so it shows the SAME chart + moments + patterns as Cuerpo (FER-452).
    @State private var stressDayMap: CalendarDayMap? = nil
    @State private var metricSpec: MetricDetailSpec? = nil
    /// Carga de entrenamiento (FER-705 · handoff «Carga»): el ACWR + la serie band-masked que alimenta la
    /// franja fija bajo las pestañas y su hoja. Se siembra en `recomputeDerived` (misma fuente que la
    /// tarjeta de Tendencias, `CuerpoView.loadAll`, para que nunca discrepen de la banda).
    @State private var trainingLoad: TrainingLoadModel? = nil
    /// La hoja de carga (montada al tocar la franja).
    @State private var trainingLoadItem: TrainingLoadItem? = nil



    // MARK: - Memoización de conteos derivados (FER-172)
    //
    // `ReadinessEngine.evaluate` (nivel de ayer + carga) y los conteos de noches de HRV ordenan/mapean
    // los ~4000 días de historia. Antes eran computed properties que el `body` invocaba varias veces POR
    // RENDER (héroe, métricas, sheet), así que corrían completos en CADA repintado —cada tick de HR en
    // vivo, cada frame de animación—, congelando el hilo principal hasta el riesgo de watchdog. Ahora
    // se calculan UNA vez por cambio de datos y se cachean en `@State`: `recomputeDerived()` los siembra
    // desde el `.task(id: repo.refreshSeq)` (mismo patrón de memoización que StressView). El gate es
    // `repo.refreshSeq` —un Int que sube en cada `refresh()`, mientras `days`/`today`/`appleHealthDays`
    // viven en el MISMO valor publicado `dashboard`—, así que es O(1) por render en vez de comparar el
    // arreglo completo. Los accesores caen a un cálculo en línea solo si el memo aún es nil (el primer
    // body antes de que `.task` siembre), nunca en el camino caliente.

    /// Los días de base para las medias de 7 días, memoizados (ver `baselineDays()`): el `filter+sort`
    /// sobre `repo.displayDays` lo comparten el delta del héroe y los tiles.
    @State private var memoBaselineDays: [DailyMetric]?

    /// Los derivados que `recomputeDerived` computa fuera del MainActor y luego asigna a los `@State memo*`.
    private struct DerivedState: Sendable {
        let baselineDays: [DailyMetric]
        let trainingLoad: TrainingLoadModel
    }

    /// Siembra el veredicto + los conteos UNA vez por refresh. La llama el `.task(id: repo.refreshSeq)`
    /// (vía `loadAll()`). FER-982: la derivación pesada (3–4× `ReadinessEngine.evaluate`, cada uno ordena
    /// TODO `repo.days`, + máscaras) ya NO corre en el MainActor — se snapshotean los
    /// inputs value-type en main y el cómputo puro hopea a un executor de fondo (mismo patrón que
    /// `RecoveryDetailModel.buildDetached`, FER-953/954). Solo los resultados vuelven a main; el body
    /// sigue sin recalcular en cada frame gracias a los `@State memo*` (FER-172), con el fallback en frío
    /// (memo aún nil) cubriendo el breve hueco del hop, igual que en el primer paint.
    private func recomputeDerived() async {
        let todayKey = Repository.localDayKey(Date())
        let days = repo.days, displayDays = repo.displayDays
        let seq = repo.refreshSeq
        let state = await Task.detached(priority: .userInitiated) {
            Self.computeDerived(days: days, displayDays: displayDays, todayKey: todayKey)
        }.value
        // FER-982: si un refresh más nuevo ya superó a este mientras el cómputo estaba en vuelo, no pises
        // sus memos con un snapshot viejo — el `.task(id: refreshSeq)` más nuevo los sembrará. (El `.task`
        // cancela a su predecesor, pero el `Task.detached` es independiente y podría aterrizar después.)
        guard seq == repo.refreshSeq else { return }
        memoBaselineDays = state.baselineDays
        trainingLoad = state.trainingLoad
        #if DEBUG
        // FER-172: prueba de que el veredicto se recalcula UNA vez por refresh (ahora off-main). En
        // scroll/animación/ticks de HR esta línea NO debe reaparecer; solo sale una vez por `seq`.
        print("[FER-172] readiness recomputed off-main · seq=\(seq) · days=\(days.count)")
        #endif
    }

    /// Derivación pura de los memos desde un snapshot value-type — corre FUERA del MainActor (FER-982).
    /// Byte-idéntica al body síncrono anterior; solo cambió el hilo. Reusa los helpers `static` puros para
    /// que el memo y el fallback en frío de instancia compartan UNA fuente de verdad (deben coincidir —
    /// ver `readiness`). `todayKey`/`yKey` se snapshotean una vez (idéntico: las llamadas originales a
    /// `localDayKey(Date())` ocurrían microsegundos aparte en la misma pasada síncrona).
    private nonisolated static func computeDerived(days: [DailyMetric], displayDays: [DailyMetric],
                                           todayKey: String) -> DerivedState {
        // FER-709: la base de 7 días (filter+sort sobre displayDays).
        let baselineDays = computeBaselineDays(displayDays: displayDays, todayKey: todayKey)
        // Carga de entrenamiento (FER-705): el ACWR + serie desde el dashboard BAND-masked — el mismo corte
        // que la tarjeta de Tendencias y el detalle de recuperación (FER-632), para que la franja, la
        // tarjeta y el veredicto nunca discrepen. `acwr == nil` → la franja muestra «calibrando» sin punto.
        let acwrMasked = SourceLens.clearBandColumns(days)
        let acwrReadiness = ReadinessEngine.evaluate(days: acwrMasked, today: todayKey)
        let trainingLoad = TrainingLoadModel(
            acwr: acwrReadiness.acwr,
            series: ReadinessEngine.acwrSeries(days: acwrMasked).map { (day: $0.day, value: $0.ratio) },
            days: acwrMasked)
        return DerivedState(baselineDays: baselineDays,
                            trainingLoad: trainingLoad)
    }


    var body: some View {
        platformBody
            .task(id: repo.refreshSeq) { await loadAll() }
            .task(id: repo.refreshSeq) {
                let start = Int(Calendar.current.startOfDay(for: Date()).timeIntervalSince1970)
                let now   = Int(Date().timeIntervalSince1970)
                let rows  = await repo.hrBuckets(from: start, to: now, bucketSeconds: 300)
                hrPoints  = rows.map { TrendPoint(date: Date(timeIntervalSince1970: TimeInterval($0.ts)), value: $0.bpm) }
            }
            .task(id: repo.refreshSeq) {
                // FER-1045: la sesión de sueño de anoche (desde ayer mediodía) para el dial-sello.
                let calendar = Calendar.current
                let from = Int(calendar.startOfDay(for: Date()).timeIntervalSince1970) - 12 * 3600
                let to = Int(Date().timeIntervalSince1970)
                let sessions = await repo.sleepSessions(from: from, to: to)
                liquidNight = Self.nightWindow(sessions: sessions, calendar: calendar)
            }
            // «Hoy» nunca pedía la carga del strap por su cuenta: dependía del sondeo del keep-alive
            // (cada ~60 s, y SUSPENDIDO durante el offload), así que tras el sync matutino la batería
            // quedaba en `nil` y el header no la mostraba. Refresca la lectura al aparecer y cuando el
            // enlace queda libre —recién conectado o terminó el backfill—, respetando no picar al strap
            // a mitad del offload (la WHOOP 4.0 la trae por GET_BATTERY_LEVEL, el mismo comando que ya
            // usan el keep-alive y Live; no se agrega ninguno nuevo al set seguro).
            .toolbar {
                ToolbarItem {
                    Button { showingSupport = true } label: {
                        // Rojo del TEMA, no `StrandPalette.metricRose` (token del sistema oscuro #FF4F73,
                        // ≈2.7:1 sobre el papel claro de Hoy → falla 3:1 no-textual y rompe la disciplina
                        // «Instrumento»). `theme.critical` es un rojo contenido theme-native (4.9:1) que
                        // sigue leyéndose como corazón. (FER-273)
                        StrandIcon.heart.image
                            .foregroundStyle(theme.critical)
                            .attentionWiggle(period: 4)
                    }
                    // Sin `.help()`: en iOS no dibuja nada (es el tooltip de macOS) pero SwiftUI igual
                    // corre la cadena por `Text.assertUnstyled` → `AttributedString.init(markdown:)`
                    // en CADA evaluación del body — parseo de markdown por pasada de layout, a cambio
                    // de nada. `accessibilityLabel` es lo que de verdad expone el botón en iOS.
                    .accessibilityLabel("Support Cénit · donate or get in touch")
                }
            }
            .overlay {
                if showingSupport {
                    SupportModalOverlay(isPresented: $showingSupport)
                }
            }
            // FER-38: la aparición del panel de soporte usa el token de fade del DS (antes una curva
            // `easeOut(0.18)` suelta) y ahora respeta Reduce Motion vía `StrandMotion.gated`.
            .animation(StrandMotion.gated(StrandMotion.fade, reduceMotion), value: showingSupport)
            // The summary sheet. On dismiss, run any pending "Ver más" hand-off (FER-251): presenting the
            // rich detail only AFTER this one is gone avoids SwiftUI swallowing a sheet-over-sheet present.
            // A plain swipe-to-close leaves `pendingSeeMore` nil, so nothing extra happens.
            .sheet(item: $metricDetail, onDismiss: { pendingSeeMore?(); pendingSeeMore = nil }) { info in
                metricSheet(for: info)
            }
            // FER-953: precompute the sleep summary model off-main when the sleep info sheet opens.
            .task(id: metricDetail?.id) {
                guard metricDetail?.id == "sleep" else {
                    // Solo soltar el modelo cacheado cuando el usuario CAMBIÓ a otra métrica
                    // con una hoja abierta — NUNCA al cerrar (`metricDetail == nil`).
                    // Nulificarlo al cerrar pintaba la tabla de sueño de GRIS a media bajada:
                    // la hoja sigue animándose hacia afuera y se re-dibuja con `sleepDetail ==
                    // nil` (revisión en simulador). Conservarlo evita el flash y hace que la
                    // siguiente apertura de Sueño muestre el dato al instante (el `.task` lo
                    // reconstruye igual). Solo se invalida al abrir OTRA métrica.
                    if metricDetail != nil, sleepSummaryModel != nil { sleepSummaryModel = nil }
                    return
                }
                let model = await SleepDetailModel.buildDetached(repo: repo)
                guard !Task.isCancelled else { return }   // sheet switched away while building
                sleepSummaryModel = model
            }
            // Rich «Instrumento» Detalle, drilled into from a summary sheet's "Ver más" — the SAME screens
            // Cuerpo presents, theme passed explicitly (it doesn't propagate through `.sheet`), NO nested
            // NavigationStack (FER-171). (FER-251)
            //
            // `.recEntranceGate()` on each: the hero's rise (recRise) otherwise plays WHILE the system sheet
            // slides up from the bottom, so a synchronous-datum screen (Estrés, Temp. de piel, Carga) shows
            // the number already in place — the same lost-under-the-motion bug the Tendencias layer fixed
            // (FER-1008). The gate holds the keyframes until the sheet lands; the late-swap screens
            // (Sueño/Esfuerzo) are unaffected (their number appears after the gate flips anyway).
            .sheet(item: $sleepDetail) { item in
                SleepDetailScreen(theme: theme, model: item.model,
                                  loadNightHR: { from, to in await repo.hrSamples(from: from, to: to) },
                                  loadNightRR: { from, to in await repo.rrIntervals(from: from, to: to) },
                                  loadNightThirds: { await repo.nightThirdsDeltas() },
                                  loadDCBaseline: { await repo.nocturnalDCBaseline() })
                    .recEntranceGate()
            }
            .sheet(item: $strainDetail) { item in
                StrainDetailScreen(theme: theme, model: item.model, estimated: item.estimated)
                    .recEntranceGate()
            }
            .sheet(item: $skinTempDetail) { item in
                SkinTempDetailScreen(theme: theme, model: item.model,
                                     loadWarmingMagnitudes: { await repo.nocturnalWarmingMagnitudes() })
                    .recEntranceGate()
            }
            .sheet(item: $stressDetail) { item in
                // SAME rich detail Cuerpo presents — the «mapa del día» (chart + moments) + patterns,
                // wired through the shared `StressDayMapPresenter` (FER-452). The cross-day pattern line
                // is read-only (the Coach handoff was removed, Pase v2 #7).
                // FER-1027: el mapa intradía de estrés es de banda; en Apple-only no se muestra.
                StressDetailScreen(theme: theme, model: item.model,
                                   dayMap: nil,
                                   patternsLoader: { await StressDayMapPresenter.timeOfDayPatterns(
                                       repo: repo, maxHR: model.profile.hrMax, restingHR: stressRestingHR) },
                                   eventPatternsLoader: { await StressDayMapPresenter.eventPatterns(
                                       repo: repo, map: stressDayMap) })
                    .recEntranceGate()
            }
            .sheet(item: $metricSpec) { spec in
                MetricDetailScreen(
                    spec: spec,
                    depth: .full,
                    theme: theme,
                    // FER-487: seal today's datum «Apple» when it came from Apple Health, matching the tile.
                    todayFromApple: todayVitalFromApple(spec.descriptor.key),
                    // FER-635: which nights are Apple-sourced, so the detail folds the baseline/σ, CV and Δ%
                    // on a single source (band-anchored) instead of mixing RMSSD↔SDNN and the band↔Apple offsets.
                    appleDays: repo.appleHealthDays,
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
                .recEntranceGate()
            }
            .sheet(item: $trainingLoadItem) { item in
                // Hoja «Carga de entrenamiento» (FER-705 · handoff «Carga» · FER-33 F2) —
                // tema explícito (no cruza `.sheet`), sin NavigationStack anidado (FER-171).
                // «Ver más en Tendencias» despacha al tab Cuerpo vía `TabRouter`.
                TrainingLoadSheet(model: item.model, theme: theme,
                                  onSeeTrends: item.onSeeTrends)
                    .recEntranceGate()
            }
            .enableInjection()   // Inject: ver la nota en `inject` arriba (no-op en Release)
    }

    /// Arma la hoja de carga desde la franja: «Ver más en Tendencias» al tab Cuerpo vía `TabRouter`.
    /// El hallazgo de carga sigue vivo en Patrones; ya no se asoma en esta hoja (FER-33 · F2).
    private func makeTrainingLoadItem(_ model: TrainingLoadModel) -> TrainingLoadItem {
        TrainingLoadItem(model: model, onSeeTrends: { tabRouter.select(.body) })
    }

    private var platformBody: some View {
        iosBody
    }

    /// Builds the metric detail sheet, passing the live «Instrumento» theme (it does NOT propagate
    /// through `.sheet`'s fresh environment) and deciding the "connect Apple Salud" hint: shown only
    /// for Apple-sourceable metrics that aren't connected and have no value yet — strap-only metrics
    /// (strain, heart rate) never get it. The connect action itself stays in Today. (FER-162)
    /// ¿Los pasos que se muestran hoy vienen de una ESTIMACIÓN en el teléfono y no de un
    /// conteo real de Apple? El tile ya lo rotulaba «est.», pero la hoja del mismo dato
    /// afirmaba Apple Salud sin mirar: dos superficies del mismo número diciendo procedencias
    /// distintas. Vive aquí, en un solo lugar, para que no puedan volver a divergir.
    /// (Revisión Grok r3 · I3.)
    private var pasosEstimadosHoy: Bool { liquidSteps().estimated }

    private func metricSheet(for info: MetricInfo) -> some View {
        // Temp. de piel y respiración también las mide el Apple Watch (los tiles ya las
        // resuelven así), así que entran a la pista «conecta Apple Salud» igual que el resto.
        let appleCapable = ["sleep", "hrv", "rhr", "spo2", "steps",
                            "skin_temp", "resp_rate"].contains(info.id)
        let notConnected = health.auth != .authorized && health.auth != .unavailable
        // ¿El valor que se muestra vino de Apple Salud (no del strap)? MISMA resolución que el tile de Hoy,
        // por métrica: HRV/FCrep/SpO₂ usan `latestFromDisplay` (el último de la gráfica, FER-546) y Sueño
        // `resolveMeasured(todayOnly:)` — así el badge coincide con el valor mostrado. Los pasos son
        // Apple-only. Strap-only (esfuerzo, FC, recuperación, estrés) → false. Sólo se badgea cuando hay valor.
        let fromApple: Bool = {
            switch info.id {
            // Un día sin conteo real de Apple se estima en el teléfono, y el tile ya lo marca
            // «est.». La hoja del MISMO dato afirmaba Apple sin mirar: dos superficies del
            // mismo número diciendo procedencias distintas. (Revisión Grok r3 · I3.)
            case "steps": return !pasosEstimadosHoy
            case "hrv":   return latestFromDisplay { $0.avgHrv }?.fromApple == true
            case "rhr":   return latestFromDisplay { $0.restingHr.map(Double.init) }?.fromApple == true
            // Sueño es day-scoped (todayOnly, FER-341): la tarjeta muestra SÓLO el valor de hoy, así que el
            // badge de fuente debe resolverse igual. Sin todayOnly caía al strap de AYER (no-Apple) y el
            // corazón desaparecía dentro de la tarjeta aunque el número mostrado SÍ venía de Apple Salud.
            case "sleep": return resolveMeasured(todayOnly: true) { $0.totalSleepMin }?.fromApple == true
            case "spo2":  return latestFromDisplay { $0.spo2Pct }?.fromApple == true
            // Temp. de piel y respiración caían al `default` y la hoja se quedaba SIN sello
            // aunque el dato viniera de Apple Salud. Se resuelven igual que sus tiles
            // (:1519 y :1529), nunca con un `true` fijo. Los ids son los de `MetricInfo`
            // («skin_temp» / «resp_rate»), NO los de la superficie Liquid («skintemp» / «resp»).
            case "skin_temp": return latestFromDisplay { $0.skinTempDevC }?.fromApple == true
            case "resp_rate": return latestFromDisplay { $0.respRateBpm }?.fromApple == true
            default:      return false
            }
        }()
        // D8 · FER-883: cuando el esfuerzo de hoy es el ESTIMADO de Apple, el tile dice
        // «Carga del día · medido» mientras la hoja decía «Esfuerzo del día · Calculado», a
        // un tap de distancia. Misma resolución del día que el resto de la pantalla (:1435).
        let strainEstimated: Bool = info.id == "strain"
            && repo.isStrainEstimated(repo.today?.day ?? Repository.localDayKey(Date()))
        // CUTOVER F6 (épico hoja Liquid): la hoja de resumen es la composición Liquid.
        // Mismos loaders, mismos gates de origen; el tema Instrumento ya no viaja.
        return LiquidMetricSheetView(
            info: info,
            appleConnectHint: appleCapable && notConnected && info.displayValue == "—",
            appleSource: fromApple && info.displayValue != "—",
            strainEstimated: strainEstimated,
            heartRateCurveLoader: info.id == "heart_rate" ? { hrPoints } : nil,
            trendLoader: trendLoader(for: info.id),
            onSeeMore: seeMoreAction(for: info.id),
            levelsSeriesLoader: levelsSeriesLoader(for: info.id),
            whatMovesIt: whatMovesItFindings(for: info.id),
            sleepDetail: info.id == "sleep" ? sleepSummaryModel : nil
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
        case "sleep":
            present = {
                // FER-953: present the loading state IMMEDIATELY; the model builds off-main and swaps
                // in under the same id (stable sheet identity — no re-presentation).
                let item = SleepDetailItem(model: .loading)
                sleepDetail = item
                Task {
                    let m = await SleepDetailModel.buildDetached(repo: repo)
                    if sleepDetail?.id == item.id {   // still the same presentation — user didn't close it
                        sleepDetail = SleepDetailItem(id: item.id, model: m)
                    }
                }
            }
        case "strain":
            present = {
                // FER-954: present the loading state IMMEDIATELY; the model builds off-main and swaps
                // in under the same id (same pattern as `sleep` above, FER-953).
                let estimatedNow = repo.isStrainEstimated(repo.today?.day ?? Repository.localDayKey(Date()))
                let item = StrainDetailItem(model: .loading, estimated: estimatedNow)
                strainDetail = item
                Task {
                    let m = await StrainDetailModel.buildDetached(repo: repo)
                    if strainDetail?.id == item.id {
                        strainDetail = StrainDetailItem(id: item.id, model: m, estimated: estimatedNow)
                    }
                }
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
        case "skin_temp":
            // Skin temp has its own rich Detalle (`SkinTempDetailScreen`, the SAME Cuerpo opens), not the
            // generic `MetricDetailScreen`, so «Ver más» presents its dedicated item. (FER-763)
            present = {
                let r = resolveMeasured { $0.skinTempDevC }
                skinTempDetail = SkinTempDetailItem(model: SkinTempDetailModel.build(
                    latest: r?.value,
                    series: repo.displayDays.compactMap { row in row.skinTempDevC.map { (row.day, $0) } }
                        .sorted { $0.day < $1.day },
                    loaded: repo.loaded))
            }
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
        // Alto y anclaje (FER-217 · FER-1039): un `GeometryReader` da el alto visible (`proxy.size.height`)
        // y el contenido se fuerza a medir AL MENOS ese alto (`.frame(minHeight:)`), anclado ARRIBA
        // (`alignment: .topLeading`) para que el header quede pegado al tope en pantallas altas donde
        // SEÑALES no llena. En pantalla chica (contenido que llena o lo excede) crece y hace scroll normal:
        // preserva el compactado de FER-202 y el scroll de siempre. Los modifiers de la pantalla (refresh,
        // tema, hojas) cuelgan del `GeometryReader`, que envuelve al `ScrollView`, así que pull-to-refresh y
        // el papel siguen igual.
        GeometryReader { proxy in
            todayScroll(proxy)
        }
        // Pull-to-refresh propio (FER-222): reemplaza el `.refreshable` nativo (su ruedita gris de
        // ~1 s). El gesto de jalar DIBUJA el dial —`handlePullOffset` arma el arco verde proporcional
        // al tirón— y al cruzar el umbral dispara la MISMA sincronización de antes (`pullToSync`) y el
        // dial pasa a girar (modo `syncing` de FER-221). La háptica `.medium` la dispara
        // `.sensoryFeedback` por el cambio de `syncHaptic` que hace `pullToSync` (heredado de FER-204).
        .sensoryFeedback(.impact(weight: .medium), trigger: syncHaptic)
        // El fondo (FER-1045): la superficie Liquid monta su fondo ambiental (aurora + orbes
        // drift) DETRÁS del scroll — un solo fondo, nunca papel doble; el estado vacío conserva
        // el papel del tema. El velo de status corona la superficie Liquid, y las animaciones
        // ambientales se pausan fuera de `.active` (scenePhase → `liquidAmbientPaused`).
        .background {
            if noSources && !liquidDemo {
                PaperBackground()
            } else {
                LiquidAmbientBackground.hoy(liquidAmbiente)
            }
        }
        .overlay(alignment: .top) {
            if !noSources || liquidDemo {
                LiquidVeil(tone: liquidAmbiente.acento)
                    .frame(height: LiquidSpace.s1400)
                    .ignoresSafeArea(edges: .top)
            }
        }
        .environment(\.liquidAmbientPaused, scenePhase != .active)
        .instrumentoTheme(.base)
        // El color scheme (y con él la barra de estado: Hoy = papel claro → tinta oscura) se decide
        // en ContentView según la pestaña activa, porque `preferredColorScheme` lo resuelve el
        // controlador raíz del WindowGroup y un valor puesto AQUÍ (dentro del TabView) no llega.
        // En vivo se abre como HOJA (FER-190), no pantalla completa: un `.sheet` con grabber, igual que
        // las hojas de métrica. La hoja abre a la altura del contenido — el detente lo fija `LiveView`
        // midiéndose (FER-196). El tema «Instrumento» se pasa explícito (no se propaga por el entorno
        // fresco del sheet) y la hoja se presenta en claro con el papel del tema; cierra con swipe.
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
            .environment(model)
            .environmentObject(repo)
            .environmentObject(health)
            .preferredColorScheme(.light)
        }
        // El acta del veredicto: la hoja que contesta la pregunta que el héroe provoca.
        .sheet(isPresented: $showVeredictoActa) {
            LiquidMetricSheet(tono: liquidActaTono, detent: .porContenido) {
                // La siembra de motas del acta se APAGÓ y el soplo del héroe se retiró
                // (FER-23, dueño): «Cómo llegué a esto» abre a papel directo, sin
                // partículas de ningún lado. LiquidSiembraMotas queda en el DS (opt-in).
                LiquidActaVeredicto(liquidActa, onVerMas: {
                    showVeredictoActa = false
                    tabRouter.select(.body)
                })
            }
            .preferredColorScheme(.light)
        }
        // La hoja del guardián: qué vigila (temp + respiración) y por qué no vota (FER-33 · F3).
        .sheet(isPresented: $showGuardianHoja) {
            let inputs = liquidGuardianInputs
            LiquidMetricSheet(tono: LiquidHoyBuilder.guardianHoja(inputs).tono,
                              detent: .porContenido) {
                LiquidGuardianHojaHost(
                    inputs: inputs,
                    tempLoader: trendLoader(for: "skin_temp"),
                    respLoader: trendLoader(for: "resp_rate"))
            }
            .preferredColorScheme(.light)
        }
        // La hoja del eje autonómico: el desglose de sus tres señales.
        .sheet(isPresented: $showAutonomicoHoja) {
            LiquidMetricSheet(tono: liquidAutonomicoTono, detent: .porContenido) {
                LiquidAutonomicoScreen(liquidAutonomico)
            }
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
            Group {
                // FER-1045 «Hoy Liquid»: la superficie normal es la composición Liquid Glass
                // alimentada por el MISMO estado derivado (builder puro). El estado vacío
                // (cero fuentes) conserva la superficie anterior intacta (criterio 7).
                if noSources && !liquidDemo {
                    VStack(alignment: .leading, spacing: 0) {
                        // Bloque FIJO del instrumento (handoff «Hoy» 2026-07): header + héroe.
                        VStack(alignment: .leading, spacing: CenitMetrics.space1) {
                            headerBlock
                            HealthAlertBanner()
                            heroBlock
                        }
                        // FER-1039: Hoy es UNA sola superficie — SEÑALES.
                        senalesPage
                            .padding(.top, CenitMetrics.space2)
                    }
                    .padding(.horizontal, CenitMetrics.screenPadding)
                } else {
                    liquidSurface
                }
            }
            // FER-274/FER-293: la pista del pull-to-refresh (chevron + microcopy) flota en el TOPE como
            // overlay — NO ocupa alto de layout, así que no empuja el héroe ni desborda la pantalla (a
            // diferencia del renglón de texto de FER-270). Centrada arriba, donde se inicia el tirón.
            // Entra/sale con un desvanecido; estática bajo Reduce Motion.
            // FER-972 P-09: `PullSyncHint` lee el progreso en su propio body (no en la raíz).
            .overlay(alignment: .top) {
                PullSyncHint(
                    pullProgress: pullProgressModel,
                    isSyncing: isSyncing,
                    // /inject 2026-07-22: el microcopy «Desliza para actualizar» se retiró
                    // (queda el chevron como cue sutil; el gesto sigue recalculando local
                    // y releyendo Apple Salud).
                    didFirstPullSync: true,
                    reduceMotion: reduceMotion
                )
            }
            // El padding horizontal vive en cada rama (FER-1045): la superficie Liquid trae su
            // margen de pantalla (LiquidSpace.s550) y la clásica conserva screenPadding.
            // Margen inferior compacto: la retícula de señales respira sobre el dock sin flotar.
            .padding(.bottom, CenitMetrics.space1)
            // /inject 2026-07-22: la superficie Liquid pega su cabecera (fecha + dial) más
            // arriba — el aire superior solo queda en la superficie clásica.
            .padding(.top, noSources ? CenitMetrics.space2 : 0)
            // Llena al menos el alto visible y ancla el contenido ARRIBA (FER-1039): sin el pager ya no hay
            // un `Spacer` que reparta el sobrante, así que la alineación vertical `.top` mantiene el header
            // pegado al tope en vez de centrar la superficie; si el contenido excede el alto, crece y scrollea.
            .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .topLeading)
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
    /// persiste entre lanzamientos); `selectedStrapModel` no sirve aquí (su default pasa el onboarding
    /// aunque el usuario no tenga banda).
    /// El `repo.refresh()` final asegura que la pantalla refleje lo último (los scores se recalculan
    /// solos vía `repo.refreshSeq` → `.task(id:)`). El `sleep` corto conserva el «soltar pronto» (~1.2 s)
    /// de FER-204; el offload largo sigue en segundo plano, reflejado en el dial girando + la cápsula de pulso.
    @MainActor
    private func pullToSync() async {
        syncHaptic += 1                       // dispara la háptica `.medium` al provocar el gesto
        // Ola 2: no band — pull-to-refresh only re-runs local recompute (Apple Health is passive).
        try? await Task.sleep(for: .seconds(1.2))
        await repo.refresh()
        // FER-293: el usuario ya ejecutó un pull-to-sync → ya aprendió el gesto; retira el microcopy y el
        // rebote (con desvanecido salvo Reduce Motion). El chevron permanece como cue sutil, así el gesto
        // sigue siendo descubrible (a diferencia de FER-270, que lo apagaba por completo para siempre).
        if !didFirstPullSync {
            withAnimation(StrandMotion.gated(StrandMotion.fade, reduceMotion)) { didFirstPullSync = true }
        }
    }

    /// Procesa el overscroll del tope del scroll (FER-222) para el pull-to-refresh propio. `overscroll` > 0
    /// = el contenido se jaló hacia abajo (overscroll en el tope): mapea el tirón a
    /// `pullProgressModel.progress` (0→1), que arma el sello, y al cruzar `pullThreshold` dispara la
    /// sincronización UNA vez por gesto. Bajo Reduce Motion NO dibuja el armado (`progress` se queda
    /// en 0), pero el gesto sigue armando y disparando con su háptica. El scroll normal
    /// (`overscroll ≤ 0`) no escribe estado de progreso → sin recomputar. El progreso va al modelo
    /// `@Observable` (FER-972 P-09); solo las subvistas que lo leen se invalidan. `pullCommitted`
    /// sigue en la raíz (write raro: umbral / reset al tope).
    @MainActor
    private func handlePullOffset(_ overscroll: CGFloat) {
        let pull = max(0, overscroll)
        guard pull > 0 else {
            if pullProgressModel.progress != 0 { pullProgressModel.progress = 0 }
            if pullCommitted { pullCommitted = false }   // de vuelta en el tope: listo para re-armar
            return
        }
        if !reduceMotion {
            let progress = Double(min(pull / pullThreshold, 1))
            if progress != pullProgressModel.progress { pullProgressModel.progress = progress }
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
        pullProgressModel.progress = 0
        pullSyncing = true
        Task {
            await pullToSync()
            pullSyncing = false
        }
    }

    /// Pide una lectura de batería del strap SOLO cuando el enlace está libre (conectado y sin offload
    /// en curso) — nunca a mitad del backfill, igual que el keep-alive evita picar al strap entonces
    /// (`guard !backfilling`, the BLE engine). `refreshBattery()` es agnóstico al modelo (4.0 → comando
    /// GET_BATTERY_LEVEL; 5/MG → lectura 0x2A19) y no introduce ningún comando nuevo.

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

    /// El header del handoff «Hoy» 2026-07 (FER-709): fecha · batería de la banda · BPM vivo tocable ·
    /// sello del dial (la firma de 24 h, que también es el spinner del pull-to-refresh). Debajo, en
    /// reposo, la línea de frescura «última lectura hace N min»; sincronizando, «Sincronizando con tu
    /// banda…». FER-222: la acción accesible «Sincronizar» reinstala para VoiceOver el gesto de jalar.
    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: CenitMetrics.space1) {
            HStack(alignment: .center, spacing: CenitMetrics.space2) {
                Text(shortDate)
                    .font(InstrumentoType.grotesk(11, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(theme.inkSecondary)
                Spacer(minLength: CenitMetrics.space2)
            }
            syncStatusLine
        }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: Text("Sync")) { triggerPullSync() }
    }

    /// El BPM del header: punto latiente (solo late con señal EN VIVO) + «62 BPM». Tocarlo abre la
    /// hoja Latidos (el monitor latido a latido), como el resto de los datos de Hoy.

    /// El header cuando la banda se desconectó de día (FER-711): en lugar del BPM vivo, un punto gris
    /// quieto + «SIN SEÑAL». El punto NO late (no hay señal), a diferencia del BPM.

    /// La línea de estado bajo el header: «Sincronizando con tu banda…» durante el sync (con el conteo
    /// de paquetes si ya fluyen), o la frescura «última lectura hace N min» en reposo. Nada sin banda vista.
    // TODO(/pm): la línea de frescura "última lectura hace N min" perdió su fuente (banda); ¿equivalente con Apple Health?
    @ViewBuilder private var syncStatusLine: some View {
        if isSyncing {
            Text("Syncing…")
                .font(StrandFont.caption).monospacedDigit()
                .foregroundStyle(theme.verdict)
        }
    }



    // MARK: - Banners de estado (handoff «Hoy · Estados» · FER-711)
    //
    // La tarjeta estándar reutilizable (`StrandDesign.TodayBanner`) montada bajo el header, sobre el
    // día normal. Se dibuja SOLO el banner de mayor prioridad activo, y SOLO desde señales que la app
    // YA tiene (batería del strap, enlace BLE, antigüedad del último sync + reloj) — sin inventar
    // detección nueva (regla del issue). Los banners que exigen detección/matemática nueva —siesta
    // (re-scoring del numeral), cambio de huso horario (exención de regularidad) y permisos PARCIALES
    // de Apple Salud— se difieren a issues propios de /pm; la tarjeta ya soporta su forma.



    /// La banda se vio antes, ahora está desconectada, es de día y no está sincronizando. Apaga el BPM
    /// del header («SIN SEÑAL») y enciende el banner de banda desconectada.

    /// Días enteros desde el último sync COMPLETO, o nil si nunca hubo. Puro diff de fechas (no math).

    /// El banner de estado activo (mayor prioridad primero), o nada. Presentacional: cada rama arma un
    /// `TodayBanner` con copy es-MX. Orden = urgencia descendente (batería antes que hueco de base).
    // TODO(/pm): sin banda, Hoy no tiene banners de estado propios (bateria/desconexión/antigüedad eran de la banda); ¿banners Apple-equivalentes?

    // MARK: - Superficie Liquid (FER-1045)
    //
    // La composición Liquid Glass de SEÑALES: `LiquidHoyBuilder` proyecta el estado ya
    // derivado (Preparedness, carga, tiles) al modelo del DS y `LiquidHoyContent` lo
    // compone. Paridad total: mismos strings del catálogo, mismas hojas por id estable,
    // misma acción accesible «Sync». El chrome que no es de la composición (línea de sync,
    // banner de alertas, leyenda de origen) vive alrededor, alineado al margen Liquid.

    /// Interruptor de DEMO para la sesión /inject (solo DEBUG): el simulador no tiene datos
    /// de HealthKit, así que la superficie cae honestamente al héroe de sueño; con esto se
    /// fuerza el estado de veredicto con los datos de muestra del ensamble para pulirlo en
    /// vivo. Computed a propósito: su cuerpo se voltea EN VIVO por inyección.
    private var liquidDemo: Bool { false }  // demo /inject apagado: Hoy corre con datos reales

    /// El ambiente semántico que tiñe fondo y pulsos (verde/ámbar/rojo/neutro).
    private var liquidAmbiente: LiquidAmbiente {
        #if DEBUG
        if liquidDemo { return .bien }   // demo VERDE en curso (/inject)
        #endif
        return LiquidHoyBuilder.ambiente(prep: repo.todayPreparedness)
    }

    private var liquidOutput: LiquidHoyBuilder.Output {
        #if DEBUG
        if liquidDemo {
            // Demo VERDE (validación en vivo, /inject): el ensamble completo con arcos.
            return LiquidHoyBuilder.Output(model: .ejemplo, heroRoute: .autonomic)
        }
        #endif
        return LiquidHoyBuilder.build(liquidInputs())
    }

    /// El acta del veredicto — la MISMA `Preparedness.Read` que ya alimenta al héroe.
    private var liquidActa: LiquidActa {
        #if DEBUG
        if liquidDemo { return LiquidHoyBuilder.actaEjemplo }
        #endif
        return LiquidHoyBuilder.acta(prep: repo.todayPreparedness,
                                     healthConnected: health.auth == .authorized)
    }

    private var liquidActaTono: Color {
        #if DEBUG
        if liquidDemo { return LiquidColor.verdePrimario }
        #endif
        return LiquidHoyBuilder.actaTono(repo.todayPreparedness)
    }

    /// El desglose del eje autonómico — la MISMA `Preparedness.Read` del héroe, proyectada a
    /// sus tres señales.
    private var liquidAutonomico: LiquidAutonomico {
        #if DEBUG
        if liquidDemo { return LiquidHoyBuilder.autonomicoEjemplo }
        #endif
        return LiquidHoyBuilder.autonomico(prep: repo.todayPreparedness,
                                           healthConnected: health.auth == .authorized)
    }

    private var liquidAutonomicoTono: Color {
        #if DEBUG
        if liquidDemo { return LiquidColor.verdePrimario }
        #endif
        return LiquidHoyBuilder.autonomicoTono(repo.todayPreparedness)
    }

    /// Entradas de la hoja del guardián (las series las carga el host al aparecer).
    private var liquidGuardianInputs: LiquidHoyBuilder.GuardianHojaInputs {
        return .init(
            guardian: liquidOutput.model.guardian,
            prep: repo.todayPreparedness,
            tempTrend: [],
            respTrend: [],
            now: Date(),
            calendar: .current,
            locale: .current)
    }

    @ViewBuilder private var liquidSurface: some View {
        let output = liquidOutput
        VStack(alignment: .leading, spacing: CenitMetrics.space1) {
            Group {
                syncStatusLine
                HealthAlertBanner()
            }
            .padding(.horizontal, LiquidSpace.s550)
            LiquidHoyContent(
                model: output.model,
                onTapMetric: { openLiquidMetric($0) },
                onTapSenal: { openLiquidSenal($0) },
                onTapCarga: {
                    if let trainingLoad {
                        trainingLoadItem = makeTrainingLoadItem(trainingLoad)
                    }
                },
                // RE-RUTEO del gesto principal de la pantalla (antes: `showAutonomicDetail`
                // → `AutonomicTrendDetailSheet`, tema PAPEL dentro de una superficie
                // Liquid). En el Ecosistema (FER-10) el tap del LIENZO separa/une los
                // orbes; la puerta al ACTA vive en la palabra + la pastilla «Cómo llegué
                // a esto» (este callback).
                onTapHero: {
                    // Sin permiso de Salud la puerta dice «Conectar Salud» y abre el
                    // flujo de conexión (FER-10 estado 8); con permiso, el acta.
                    if output.heroRoute == .salud {
                        showDataSources = true
                    } else {
                        showVeredictoActa = true
                    }
                },
                // El guardián (orbe separado Y franja) abre SU hoja: qué vigila y por
                // qué no vota (FER-10, revisión de usuario).
                onTapGuardian: { showGuardianHoja = true },
                mostrarHintSeparar: ecosistemaSeparaciones < 3,
                fusionInicial: ecosistemaFusionDay != Repository.localDayKey(Date()),
                onFusionArrancada: {
                    ecosistemaFusionDay = Repository.localDayKey(Date())
                },
                onSeparacion: {
                    ecosistemaSeparaciones = min(3, ecosistemaSeparaciones + 1)
                })
            // /inject: la leyenda de origen se retiró de la superficie Liquid a pedido del
            // dueño (los puntos de origen por tile se quedan).
        }
        .accessibilityAction(named: Text("Sync")) { triggerPullSync() }
    }

    /// Los inputs del builder — las MISMAS resoluciones en capas que alimentan los tiles y
    /// el héroe actuales (paridad por construcción; el builder solo mapea/formatea).
    private func liquidInputs() -> LiquidHoyBuilder.Inputs {
        var inputs = LiquidHoyBuilder.Inputs()
        inputs.healthConnected = health.auth == .authorized
        inputs.preparedness = repo.todayPreparedness
        // El veredicto SOLO se calcula en el refresh completo (`Repository`, para no puntuar la FC
        // despierta en el primer pintado y desdecirse segundos después). Mientras eso llega, el héroe
        // debe decir que está leyendo — no «no conozco tu base», que a alguien con años de historia
        // es falso y saldría en CADA arranque en frío.
        inputs.verdictPending = repo.todayPreparedness == nil && !repo.fullyLoaded
        inputs.thermalDeviation = latestFromDisplay({ $0.skinTempDevC })?.value
        inputs.trainingLoad = trainingLoad
        inputs.sleep = resolveMeasured(todayOnly: true, { $0.totalSleepMin })
            .map { .init($0.value, fromApple: $0.fromApple) }
        inputs.hrv = latestFromDisplay({ $0.avgHrv })
            .map { .init($0.value, fromApple: $0.fromApple) }
        inputs.rhr = latestFromDisplay({ $0.restingHr.map(Double.init) })
            .map { .init($0.value, fromApple: $0.fromApple) }
        inputs.strain = model.displayedDayStrain
        inputs.strainEstimated = repo.isStrainEstimated(repo.today?.day ?? Repository.localDayKey(Date()))
        let steps = liquidSteps()
        inputs.steps = steps.value
        inputs.stepsEstimated = steps.estimated
        inputs.skinTemp = latestFromDisplay({ $0.skinTempDevC })
            .map { .init($0.value, fromApple: $0.fromApple) }
        inputs.resp = latestFromDisplay({ $0.respRateBpm })
            .map { .init($0.value, fromApple: $0.fromApple) }
        inputs.stress = stress?.score
        let base = baselineDays()
        inputs.historias.sleep = history(base) { $0.totalSleepMin }
        inputs.historias.hrv = history(base) { $0.avgHrv }
        inputs.historias.rhr = history(base) { $0.restingHr.map(Double.init) }
        inputs.historias.strain = history(base) { $0.strain }
        inputs.historias.steps = steps.estimated ? stepsEstHistory
            : history(base) { $0.steps.map(Double.init) }
        inputs.historias.skinTemp = history(base) { $0.skinTempDevC }
        inputs.historias.resp = history(base) { $0.respRateBpm }
        inputs.historias.stress = stressHistory
        inputs.night = liquidNight
        inputs.sol = solarWindow.map { (start: $0.sunrise, end: $0.sunset) }
        return inputs
    }

    /// Pasos para la superficie Liquid: Apple fresco primero; sin conteo real cae a la estimación
    /// on-device (FER-663), rotulada y con origen calculado.
    private func liquidSteps() -> (value: Double?, estimated: Bool, raw: Int?) {
        let cutoff = Repository.localDayKey(Calendar.current.date(byAdding: .day, value: -13, to: Date()) ?? Date())
        let fresh = appleDays.last(where: { $0.day >= cutoff })?.steps
        let estFresh = fresh == nil
            ? stepsEst.last(where: { $0.day >= cutoff }).map { Int($0.value.rounded()) }
            : nil
        return ((fresh ?? estFresh).map(Double.init), estFresh != nil, fresh ?? estFresh)
    }

    /// Tap de un tile Liquid → la MISMA hoja de métrica de siempre, por id estable.
    private func openLiquidMetric(_ id: String) {
        switch id {
        case "sleep":
            metricDetail = .sleep(resolveMeasured(todayOnly: true) { $0.totalSleepMin }
                .map { Int($0.value.rounded()) })
        case "hrv":
            metricDetail = .hrv(latestFromDisplay { $0.avgHrv }?.value)
        case "rhr":
            metricDetail = .restingHR(latestFromDisplay({ $0.restingHr.map(Double.init) })
                .map { Int($0.value.rounded()) })
        case "strain":
            metricDetail = .strain(model.displayedDayStrain)
        case "steps":
            metricDetail = .steps(liquidSteps().raw)
        case "skintemp":
            metricDetail = .skinTemp(latestFromDisplay({ $0.skinTempDevC })?.value)
        case "resp":
            metricDetail = .respiratory(latestFromDisplay({ $0.respRateBpm })?.value)
        case "stress":
            metricDetail = .stress(stress?.score)
        default:
            break
        }
    }

    /// Tap de un orbe → la hoja de su eje (autonómico / sueño / térmico).
    private func openLiquidSenal(_ id: String) {
        switch id {
        case "autonomico":
            // La hoja propia del eje: el desglose de sus tres señales (VFC/FC en reposo/
            // respiración) con el % del voto que cargó cada una — no una sola métrica.
            showAutonomicoHoja = true
        case "sueno":
            metricDetail = .sleep(resolveMeasured(todayOnly: true) { $0.totalSleepMin }
                .map { Int($0.value.rounded()) })
        case "termico":
            metricDetail = .skinTemp(latestFromDisplay({ $0.skinTempDevC })?.value)
        default:
            break
        }
    }

    /// La ventana de la noche para el dial: la sesión que terminó más tarde en la ventana
    /// consultada, en horas locales 0–24 (medianoche arriba del dial).
    private nonisolated static func nightWindow(sessions: [CachedSleepSession],
                                                calendar: Calendar) -> (start: Double, end: Double)? {
        guard let session = sessions.max(by: { $0.endTs < $1.endTs }) else { return nil }
        func hour(_ ts: Int) -> Double {
            let components = calendar.dateComponents([.hour, .minute],
                                                     from: Date(timeIntervalSince1970: TimeInterval(ts)))
            return Double(components.hour ?? 0) + Double(components.minute ?? 0) / 60
        }
        return (hour(session.startTs), hour(session.endTs))
    }

    // MARK: - Héroe «Instrumento diurno» (FER-160 · FER-1008/FER-1029)
    //
    // Apple-only: el héroe es el SUEÑO de anoche (número dominante). El veredicto 0–100 estilo-banda y
    // sus estados narrados pre-lectura (calibrando / en espera) se retiraron con la banda y el brief
    // (FER-1039); la tarjeta de tendencia autonómica vivía en el héroe «Preparación», retirado como
    // código muerto (FER-35). El numeral de sueño se basta solo.


    // El único héroe de la superficie clásica (estado sin fuentes): el sueño de anoche como número
    // dominante. La «Preparación» categórica (veredicto + agujas) y la «Lectura de día» se retiraron
    // por ser código muerto (FER-35): sólo se pintaban aquí, en el estado `noSources`, donde por
    // definición nunca hay un veredicto real (necesita noches de datos). La superficie con datos es
    // la Liquid (`liquidSurface`), que trae su propio héroe.
    @ViewBuilder private var heroBlock: some View { appleTrendHero }

    /// R4 (FER-1008): el héroe del path Apple-only — el SUEÑO es el número dominante (el 0–100 estilo-WHOOP
    /// se retiró). Toca → detalle de sueño.
    @ViewBuilder private var appleTrendHero: some View {
        let sleepMin = resolveMeasured(todayOnly: true) { $0.totalSleepMin }?.value
        // FER-38: es un control accionable (abre el Detalle de Sueño), así que va como `Button`
        // —no `onTapGesture`— para que VoiceOver anuncie el rol de botón y la pista, y para la
        // afordancia nativa de presión. `.plain` conserva el look «Instrumento» (sin chrome).
        Button {
            metricDetail = .sleep(resolveMeasured(todayOnly: true) { $0.totalSleepMin }.map { Int($0.value.rounded()) })
        } label: {
            VStack(alignment: .leading, spacing: CenitMetrics.space1) {
                Text("LAST NIGHT'S SLEEP").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                if let sleepMin, sleepMin > 0 {
                    let h = Int(sleepMin) / 60, m = Int(sleepMin) % 60
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(h)").font(StrandFont.number(64)).foregroundStyle(theme.ink)
                        Text("h ").font(StrandFont.number(28)).foregroundStyle(theme.inkSecondary)
                        Text("\(m)").font(StrandFont.number(64)).foregroundStyle(theme.ink)
                        Text("m").font(StrandFont.number(28)).foregroundStyle(theme.inkSecondary)
                    }
                    .lineLimit(1).minimumScaleFactor(0.6)
                    Text(sleepMin >= 420 ? LocalizedStringKey("You slept well") : LocalizedStringKey("Sleep was short"))
                        .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                } else {
                    Text("—").font(StrandFont.number(64)).foregroundStyle(theme.inkTertiary)
                    Text("No sleep recorded last night").font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Opens the sleep detail"))
    }

    // MARK: - SEÑALES (superficie clásica · solo estado vacío)

    /// SEÑALES — la superficie CLÁSICA, que ya solo se pinta en el estado sin fuentes (`noSources`):
    /// la franja de carga (si la hay) + la tarjeta de «conectar Apple Health» (FER-364). La retícula 2×4
    /// de tiles se retiró por inalcanzable (FER-35); con datos, la superficie es `liquidSurface`.
    @ViewBuilder private var senalesPage: some View {
        VStack(alignment: .leading, spacing: CenitMetrics.space2) {
            // Franja de carga (FER-705 · handoff «Carga»): vive DENTRO de Señales, así que pertenece solo a
            // esta página y NO viaja al Brief con el swipe. No respira ni participa del pull-to-refresh;
            // tocarla abre la hoja. Si `trainingLoad` aún no sembró (primer refresh) se omite; una vez con
            // datos muestra la banda o «calibrando».
            if let trainingLoad {
                TrainingLoadStrip(model: trainingLoad, theme: theme) {
                    trainingLoadItem = makeTrainingLoadItem(trainingLoad)
                }
            }
            // `senalesPage` sólo se pinta en la rama `noSources`, así que siempre es la tarjeta de
            // conectar fuentes. La retícula 2×4 (`iosMetricsSection`) se retiró por inalcanzable (FER-35).
            emptySourcesCard
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }


    /// El instrumento está sincronizando: offload en curso, su puente async (FER-480 `draining`) o el
    /// pull-to-sync manual. Fuente única para las señales del héroe (estado, dial, numeral, pista).
    /// La pista del pull (FER-293) y el sello armado viven en `PullSyncHint` / `PullIndicator`
    /// (FER-972 P-09): leen el progreso en su propio body para no invalidar Hoy por frame.
    // TODO(/pm): sin banda, "sincronizando" solo refleja el pull-to-refresh del usuario, no un fetch real de Apple Health en curso.
    private var isSyncing: Bool { pullSyncing }

    /// Cero fuentes: ni strap visto, ni datos de Apple Health, ni permiso de Health concedido. (FER-364)
    private var noSources: Bool {
        #if DEBUG
        // Los fixtures de captura (`-noop.fixture …`) siembran el dashboard pero NO
        // `appleHealthDays` ni el permiso de Salud, así que sin conceder HealthKit a mano
        // caían a la superficie CLÁSICA (las agujas «En reposo») en vez de la Liquid que
        // representan. En modo fixture SIEMPRE hay fuentes: el estado sin fuentes se captura
        // con el arg ausente/`empty`, que toma el camino normal. (SIMULADOR-ONLY, ver
        // `ScreenshotFixtures.activeState`.)
        if ScreenshotFixtures.activeState() != nil { return false }
        #endif
        return repo.appleHealthDays.isEmpty && health.auth != .authorized
    }

    /// La tarjeta de «conecta tus fuentes» del estado vacío: Apple Health como base, la banda como capa
    /// opcional. Reemplaza el botón verde y el viejo link de Apple Salud, y deja que Hoy quepa de una. (FER-364)
    private var emptySourcesCard: some View {
        VStack(spacing: 0) {
            sourceRow(icon: "heart.fill", tint: theme.dataSpO2,
                      title: "Connect Apple Health", subtitle: "the base of your data") { showDataSources = true }
        }
        .background(theme.surface, in: RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous)
            .strokeBorder(theme.hairline, lineWidth: 1))
        .strandElevation(.raised, ink: theme.ink)
    }

    private func sourceRow(icon: String, tint: Color, title: LocalizedStringKey,
                           subtitle: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: CenitMetrics.gap) {
                Image(systemName: icon).font(StrandFont.glyph(.inline)).foregroundStyle(tint).frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(StrandFont.subhead.weight(.semibold)).foregroundStyle(theme.ink)
                    Text(subtitle).font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                }
                Spacer(minLength: 0)
                StrandIcon.disclosure.image.font(StrandFont.glyph(.chevron)).foregroundStyle(theme.inkTertiary)
            }
            .padding(CenitMetrics.cardPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Los días de base para la media de 7 días (FER-258): las filas del dashboard de display
    /// ANTERIORES a hoy (la misma fuente en capas que resuelve el valor de hoy y la de la tendencia
    /// 14d), ordenadas y acotadas a las recientes. Excluir hoy hace que el delta sea «hoy vs tu
    /// semana», no «hoy contra sí mismo». Memoizado en `memoBaselineDays` (FER-172): el `filter+sort`
    /// sobre `repo.displayDays` corría 2–3 veces por render (héroe + Brief + tiles); ahora una vez por
    /// refresh. Cae al cálculo en línea solo el primer frame (memo aún nil), nunca en el camino caliente.
    private func baselineDays() -> [DailyMetric] {
        memoBaselineDays ?? computeBaselineDays()
    }

    private func computeBaselineDays() -> [DailyMetric] {
        Self.computeBaselineDays(displayDays: repo.displayDays, todayKey: Repository.localDayKey(Date()))
    }

    private nonisolated static func computeBaselineDays(displayDays: [DailyMetric], todayKey: String) -> [DailyMetric] {
        Array(displayDays.filter { $0.day < todayKey }.sorted { $0.day < $1.day }.suffix(30))
    }


    /// La base de 7 días del estrés, del proxy diario 0–3 de `StressModel.fullTrend` excluyendo hoy
    /// (el último punto). El estrés no es campo de `DailyMetric`, así que va por su propia serie.
    private var stressHistory: [Double] {
        guard let trend = stress?.fullTrend, !trend.isEmpty else { return [] }
        return Array(trend.dropLast().suffix(7).map { $0.value })
    }

    /// La base de 7 días de la estimación de pasos (FER-663), excluyendo hoy — la media del tile en un
    /// día estimado compara estimación-contra-estimación, nunca contra los conteos reales de Apple.
    private var stepsEstHistory: [Double] {
        let todayKey = Repository.localDayKey(Date())
        return Array(stepsEst.filter { $0.day < todayKey }.suffix(7).map { $0.value })
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
        // (FER-172). FER-982: `recomputeDerived()` snapshotea `repo` en main y hopea el cómputo pesado a
        // un `Task.detached`; el fallback en frío (memo aún nil) cubre el breve hueco del hop.
        await recomputeDerived()
        // Issue every query concurrently, then collect. The store is a DatabasePool (2 readers since
        // FER-970) so read I/O can overlap; the memoized ensureStore() makes the parallel first-callers
        // share ONE open, and the queries avoid main-actor ping-pong.
        async let adRows     = repo.appleDailyRows()
        async let amRows     = repo.appleDailyMetricRows()
        // Stored daily "stress" series (0–3) — the model prefers it, else derives from RHR/HRV. (FER-180)
        async let stressRows = repo.series(key: "stress", source: "strap")
        // Estimación de pasos WHOOP 4.0 (FER-663) — vacía salvo que el motor la haya calibrado y escrito.
        async let stepsEstRows = repo.computedSeries(key: "steps_est", days: 60)

        // Today's HR trend — 5-minute bucket means from local midnight → now.
        let startOfToday = Int(Calendar.current.startOfDay(for: Date()).timeIntervalSince1970)
        let nowTs = Int(Date().timeIntervalSince1970)
        async let hrBucketRows = repo.hrBuckets(from: startOfToday, to: nowTs, bucketSeconds: 300)

        appleDays = await adRows
        appleMetricDays = (await amRows).sorted { $0.day < $1.day }
        stepsEst = (await stepsEstRows).sorted { $0.day < $1.day }
        hrPoints  = await hrBucketRows
            .map { TrendPoint(date: Date(timeIntervalSince1970: TimeInterval($0.ts)), value: $0.bpm) }
        // Build today's stress model from the day rows + stored series (nil when there's no usable
        // signal yet — the tile then placeholders "—"). Reads `displayDays` (Apple-health fallback,
        // FER-149) so a strap-partial night still derives, and anchors "today" to the local day so a
        // UTC-bucketed "tomorrow" row (FER-226) can't blank the tile.
        stress = StressModel(days: repo.displayDays, stored: await stressRows,
                             todayKey: Repository.localDayKey(Date()), appleDays: repo.appleHealthDays)
        // Ola 2: live day-strain fold retired with the band; settled daily strain via repo.today is enough.
        // «La conexión de hoy» (FER-614): los hallazgos rankeados, misma fuente que Patrones. Memoizado
        // por (refreshSeq, díaLocal) — FER-872: si el mismo seq re-dispara `loadAll`, no repite la
        // correlación+FDR (que ya corre off-main dentro de `generate`).
        let insightsKey = "\(repo.refreshSeq)|\(Repository.localDayKey(Date()))"
        if memoInsightsKey != insightsKey {
            insights = await InsightsProvider.generate(repo: repo, today: Repository.localDayKey(Date()))
            memoInsightsKey = insightsKey
        }
    }

    // MARK: - 14-day trend loader (all platforms)

    /// Builds the trailing 14-day trend from the DISPLAY dashboard rows (`repo.displayDays`) — the same
    /// layered source the Today tiles draw their values from (`resolveMeasured`/`baselineDays`): Apple Health is the base,
    /// on-device computed scores (`strap-noop`) fill the strap's days, imported strap rows win, and a
    /// strap-covered day with a nil field back-fills from Apple Health so the line has no gap (FER-149).
    /// Reading `repo.series(source: "strap")` instead returned EMPTY for a BLE + Apple Health user,
    /// because the computed recovery/HRV/RHR/strain/sleep live in the daily-metrics table under
    /// `strap-noop`, never in the `metricSeries` table that `series()` queries — that was the
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
    /// returns nil: it shows its verdict + levels instrument, not a 14-day line chart.
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
        case "hrv":       pick = { $0.avgHrv }
        case "rhr":       pick = { $0.restingHr.map(Double.init) }
        case "spo2":      pick = { $0.spo2Pct }
        case "skin_temp": pick = { $0.skinTempDevC }
        // FER-33 · F3: sin este case, NINGUNA hoja podía dibujar serie de respiración
        // (caía al default → nil). Mismo campo que `levelsSeriesLoader`.
        case "resp_rate": pick = { $0.respRateBpm }
        case "steps":     pick = { $0.steps.map(Double.init) }
        default:          return nil   // strain (verdict + levels only) and anything else: no 14-day trend
        }
        return { await self.loadTrend(pick: pick) }
    }

    /// Full-history `(day, value)` series for a migrated metric's levels instrument (FER-607) — the SAME
    /// `displayDays` source as the 14-day trend but with NO cutoff, so `MetricInfoSheet`'s range selector
    /// can re-window across S/M/3M/6M/1A/Todo. Supplied only for migrated metrics (pilot: resting HR);
    /// every other metric returns nil and keeps the classic 14-day summary.
    private func levelsSeriesLoader(for id: String) -> (() async -> [(day: String, value: Double)])? {
        // Stress isn't a stored `DailyMetric` field — its daily 0–3 series lives in `StressModel.fullTrend`
        // (the same source as its trend). Map each point's date to a day key for the levels math. The
        // dates are UTC-midnight anchored (`parseDayKey`), so the key must be read back in UTC —
        // `localDayKey` shifted every point one day back west of UTC (FER-630). (FER-621)
        if id == "stress" {
            return { (self.stress?.fullTrend ?? []).map { (day: Repository.utcDayKey($0.date), value: $0.value) } }
        }
        let pick: (DailyMetric) -> Double?
        switch id {
        case "recovery":  pick = { $0.recovery }
        case "rhr":       pick = { $0.restingHr.map(Double.init) }
        case "hrv":       pick = { $0.avgHrv }
        case "spo2":      pick = { $0.spo2Pct }
        case "skin_temp": pick = { $0.skinTempDevC }
        case "resp_rate": pick = { $0.respRateBpm }
        case "sleep":     pick = { $0.totalSleepMin }
        case "steps":     pick = { $0.steps.map(Double.init) }
        case "strain":    pick = { $0.strain }
        default:          return nil
        }
        // Drop today's partial point ONLY for a running daily total (steps) — the same "who drops today"
        // policy the rich detail reads, from the single source so the two can't diverge (FER-630). Day
        // Strain KEEPS today: its sheet's hero shows the in-progress score, so a line ending yesterday
        // contradicted it. Nightly metrics (rhr/spo2/sleep/resp) are complete each morning anyway.
        let dropsIncompleteToday = MetricDetailSpec.accumulatesToday(id)
        return {
            Self.levelsSeries(rows: repo.displayDays, todayKey: Repository.localDayKey(Date()),
                              dropsIncompleteToday: dropsIncompleteToday, pick: pick)
        }
    }

    /// The full-history levels series for a metric, from the layered daily rows. Pure, so the
    /// series↔current-day contract is pinned by `TrendCurrentDayTests` (FER-630). `dropsIncompleteToday`
    /// removes today's still-accumulating partial point (running totals only — see
    /// `MetricDetailSpec.accumulatesToday`); every other metric keeps every point.
    nonisolated static func levelsSeries(rows: [DailyMetric], todayKey: String,
                                         dropsIncompleteToday: Bool,
                                         pick: (DailyMetric) -> Double?) -> [(day: String, value: Double)] {
        var series = rows.compactMap { row in pick(row).map { (day: row.day, value: $0) } }
        if dropsIncompleteToday, series.count > 1, series.last?.day == todayKey {
            series.removeLast()
        }
        return series
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

    // MARK: - Loaders for the rich vital Detalle drilled into via "Ver más" (FER-251)
    //
    // The unified Detalle de Métrica (FER-185) for HRV / Resting HR needs the same three loaders Cuerpo
    // feeds it, so the screen is identical from either tab. They read the same layered source the rows
    // already use (`repo.displayDays` / `resolveMeasured`); mirror of `CuerpoView`.

    /// Today's step total from the Apple daily rows, within the same freshness window the tile uses, so
    /// «Ver más» opens the steps detail on the value the tile shows. (FER-254)
    private var freshSteps: Int? { liquidSteps().estimated ? nil : liquidSteps().raw }

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
        // FER-635: the cross-source vitals read `repo.days` (un-backfilled) so each reading truly belongs to
        // its day's source — `displayDays` would fill a band night's missing HRV/RHR/resp from Apple, slipping
        // an SDNN/offset value onto a band day and defeating the detail's per-source fold. Single-source
        // metrics keep `displayDays` for continuous coverage (FER-149). Mirrors CuerpoView.
        let source = ["hrv", "rhr", "resp_rate"].contains(key) ? repo.days : repo.displayDays
        return source
            .compactMap { row in pick(row).map { (row.day, $0) } }
            .sorted { $0.day < $1.day }
    }

    /// The gated, directional "Qué la mueve" findings (FER-209), computed from the user's own history.
    /// Empty → the detail hides the block.
    private func whatMovesItFindings(for key: String) -> [WhatMovesItFinding] {
        WhatMovesItEngine.findings(forMetricKey: key, days: repo.displayDays, appleDays: repo.appleHealthDays)
    }

    /// Last night's companion vitals (respiration + resting HR) for the detail's "Vitales de la noche".
    private func loadNightVitals() async -> MetricDetailScreen.NightVitals {
        MetricDetailScreen.NightVitals(
            respiration: resolveMeasured { $0.respRateBpm }?.value,
            restingHR: resolveMeasured { $0.restingHr.map(Double.init) }?.value)
    }

    // MARK: - Derived text

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

// MARK: - Host de la hoja del guardián (FER-33 · F3)
//
// Carga las series de 14 noches al aparecer y recompone la hoja. Vive DENTRO del
// cascarón `LiquidMetricSheet` para que su `@State` actualice las mini-gráficas sin
// reabrir la hoja.

private struct LiquidGuardianHojaHost: View {
    let inputs: LiquidHoyBuilder.GuardianHojaInputs
    let tempLoader: (() async -> [TrendPoint])?
    let respLoader: (() async -> [TrendPoint])?

    @State private var tempTrend: [(fecha: Date, valor: Double)] = []
    @State private var respTrend: [(fecha: Date, valor: Double)] = []

    var body: some View {
        var i = inputs
        i.tempTrend = tempTrend
        i.respTrend = respTrend
        return LiquidGuardianScreen(LiquidHoyBuilder.guardianHoja(i))
            .task {
                if let load = tempLoader {
                    let pts = await load()
                    tempTrend = pts.map { (fecha: $0.date, valor: $0.value) }
                }
                if let load = respLoader {
                    let pts = await load()
                    respTrend = pts.map { (fecha: $0.date, valor: $0.value) }
                }
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
        .environment(AppModel.preview)
        .environmentObject(HealthKitBridge(repo: repo, appleDeviceId: "preview-apple", noopDeviceId: "preview"))
        #endif
        .frame(width: 920, height: 940)
        .preferredColorScheme(.light)
}

// FER-38: la MISMA superficie viva al tamaño de texto más grande (AX5). Ejercita Dynamic Type
// en el canvas para cazar truncados/aplastamientos antes de que lleguen al iPhone (deuda de
// ACCESIBILIDAD.md: no había snapshot que estirara la superficie a AX5).
#Preview("Texto grande · AX5") {
    let repo = Repository(deviceId: "preview")
    let cal = Calendar(identifier: .gregorian)
    let today = cal.startOfDay(for: Date())
    var sample: [DailyMetric] = []
    for i in stride(from: 39, through: 0, by: -1) {
        let date = cal.date(byAdding: .day, value: -i, to: today)!
        let phase = Double(i)
        let total = 380 + 70 * sin(phase / 6.0)
        sample.append(DailyMetric(
            day: Repository.dayString(date), totalSleepMin: total, efficiency: 88,
            deepMin: 95, remMin: 110, lightMin: total - 200, disturbances: 4,
            restingHr: 50 + (i % 6), avgHrv: 58 + 16 * sin(phase / 4.0),
            recovery: 60, strain: 10, exerciseCount: i % 3,
            spo2Pct: 96, skinTempDevC: 33.4, respRateBpm: 14.6))
    }
    repo.setDashboard(days: sample)

    return TodayView()
        .environmentObject(repo)
        .environmentObject(TabRouter())
        #if os(iOS)
        .environment(AppModel.preview)
        .environmentObject(HealthKitBridge(repo: repo, appleDeviceId: "preview-apple", noopDeviceId: "preview"))
        #endif
        .frame(width: 920, height: 940)
        .preferredColorScheme(.light)
        .dynamicTypeSize(.accessibility5)
}
#endif

