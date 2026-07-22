import SwiftUI
import StrandDesign
import StrandAnalytics
import StrandTraining
import CenitStore
import Foundation


// MARK: - Hoy «Instrumento» evolucionado (FER-709, handoff 2026-07)
//
// The home screen in the EVOLVED «Instrumento diurno» voice (Space Grotesk numerals, warm paper,
// one dominant number, arithmetic transparency — see DESIGN.md §8.7).
//
// Composition (top → bottom), all inside `iosBody`:
//   (a) HEADER — date · strap battery · live BPM (tap → Latidos) · the 34pt `DialSeal` (the 24h
//                signature AND the pull-to-refresh spinner), plus the freshness line (`headerBlock`).
//   (b) HERO   — last night's SLEEP as the dominant numeral + the «cómo vienes» autonomic-trend card
//                (`appleTrendHero`). FER-1029: this is the ONLY hero. The 0–100 recovery verdict numeral
//                (band era) was retired — `repo.today.recovery` is always nil on Apple-only, so it was
//                unreachable dead code. The big `DiurnalDial` was retired earlier; the 24h lives in the
//                header seal.
//   (c) TABS   — SEÑALES / BRIEF with the elastic underline (`sectionTabs`) over a 2-page pager:
//                · Page 0 (`senalesPage`) — the 2×4 tile grid with sparkbands (`iosMetricsSection`).
//                · Page 1 (`verdictPage`) — the Daily Brief (headline, connection, actions, CTA).
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
                    StrandIcon.down.image
                        .font(StrandFont.glyph(.chevron, weight: .semibold))
                        .foregroundStyle(theme.inkTertiary)
                        .offset(y: bobbing ? 4 : 0)
                        .animation(bobbing ? StrandMotion.bob : nil, value: bobbing)
                    if learning {
                        Text("Pull to refresh")
                            .font(StrandFont.caption)
                            .foregroundStyle(theme.inkTertiary)
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
    @State private var showAutonomicDetail = false
    /// Cuenta cada pull-to-refresh para disparar la háptica declarativa (`.sensoryFeedback`) al
    /// provocar el gesto de sincronización (FER-204).
    @State private var syncHaptic = 0

    /// El usuario ya hizo al menos un pull-to-sync con strap (FER-270): apaga para siempre la pista
    /// «Desliza para sincronizar» del héroe — ya aprendió el gesto. Persiste entre lanzamientos.
    @AppStorage("today.didFirstPullSync") private var didFirstPullSync = false

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

    // «Hoy en tu plan» — el bloque puente con Entrenar al pie del brief (FER-613). Cargados en `loadAll`
    // desde el store: si hay split, la rutina de hoy (nil = descanso) y la racha COMPARTIDA con Entrenar.
    @State private var hasSplit = false
    @State private var todayRoutineName: String? = nil
    @State private var trainingStreak = 0

    // «La conexión de hoy» — la correlación más relevante del día (FER-614). Cargados en `loadAll` vía el
    // loader compartido `InsightsProvider`, así la conexión del brief == la que muestra Patrones (mismo FDR).
    @State private var insights: [Insight] = []
    // FER-872: memo de los insights por (refreshSeq, díaLocal). `loadAll` se dispara por `refreshSeq`, pero
    // un re-`.task` con el MISMO seq (misma data) no debe recomputar la correlación+FDR de nuevo — se
    // conserva el resultado. Un seq nuevo (data nueva) o el rollover de día invalidan el memo.
    @State private var memoInsightsKey: String?

    // Support sheet (donate + contact) — always reachable from the home toolbar.
    @State private var showingSupport = false

    // Metric-info sheet — tapping any Key Metrics row presents this.
    @State private var metricDetail: MetricInfo? = nil
    /// FER-953: sleep summary for MetricInfoSheet, built off-main when the sleep info sheet opens.
    @State private var sleepSummaryModel: SleepDetailModel? = nil
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

    /// Página activa del pager de 2 páginas (FER-465): 0 = veredicto (Daily Brief) · 1 = «Métricas de hoy».
    /// Optional porque es el binding de `.scrollPosition(id:)` (puede quedar nil a media transición); los
    /// page dots lo leen con `?? 0`. Arranca en la página 1 del veredicto.
    @State private var pagerPage: Int? = 0

    /// El alto natural de cada página del pager, medido por `TodayPageHeightKey` (FER-725). El pager fija
    /// su alto al de la página activa (`pageHeights[pagerPage]`), así Señales no hereda el alto de Brief y
    /// el scroll vertical solo aparece en Brief. Vacío el primer frame → el pager cae a su alto natural.
    @State private var pageHeights: [Int: CGFloat] = [:]

    /// Arma el latido del punto «Ahora» del Daily Brief (FER-549/handoff): al aparecer pasa a `true` con una
    /// animación `repeatForever`, de modo que el halo concéntrico pulse. Estático bajo Reduce Motion.
    @State private var briefDotPulse = false

    // THE single grid definition — every tile group reuses it so margins line up.
    private let grid = [GridItem(.adaptive(minimum: 168), spacing: CenitMetrics.gap)]

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
    /// Los días de base para las medias de 7 días, memoizados (ver `baselineDays()`): el `filter+sort`
    /// sobre `repo.displayDays` lo comparten el delta del héroe, el Daily Brief y los tiles.
    @State private var memoBaselineDays: [DailyMetric]?

    /// Los tres conteos de noches que el héroe/veredicto leen, agrupados para sembrarlos de una sola
    /// pasada sobre `repo.days` (antes cada propiedad remapeaba la historia por su cuenta).
    private struct DerivedHrvCounts: Equatable, Sendable {
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
        Self.computeHrvCounts(days: repo.days, appleDays: repo.appleHealthDays,
                              todayHasRecovery: repo.today?.recovery != nil)
    }

    /// Forma pura — misma matemática desde un snapshot, para que el hop off-main de `recomputeDerived` y
    /// el fallback en frío de instancia (`hrvCounts`) compartan UNA fuente de verdad.
    private nonisolated static func computeHrvCounts(days: [DailyMetric], appleDays: Set<String>,
                                             todayHasRecovery: Bool) -> DerivedHrvCounts {
        let nightlyHrv = days.map(\.avgHrv)
        let strapHrv = days.filter { !appleDays.contains($0.day) }.map(\.avgHrv)
        return DerivedHrvCounts(
            recoveryCalibration: RecoveryScorer.calibrationNights(nightlyHrv: nightlyHrv, hasRecovery: todayHasRecovery),
            ownNights: RecoveryScorer.calibrationNights(nightlyHrv: strapHrv, hasRecovery: false, seed: .max) ?? 0,
            seededNights: RecoveryScorer.calibrationNights(nightlyHrv: nightlyHrv, hasRecovery: false, seed: .max) ?? 0)
    }

    /// Los derivados que `recomputeDerived` computa fuera del MainActor y luego asigna a los `@State memo*`.
    private struct DerivedState: Sendable {
        let readiness: ReadinessEngine.Readiness
        let counts: DerivedHrvCounts
        let yesterdayLevel: ReadinessEngine.Level
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
        let yKey = Repository.localDayKey(Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date())
        let days = repo.days, displayDays = repo.displayDays, appleDays = repo.appleHealthDays
        let todayRecovery = repo.today?.recovery
        let seq = repo.refreshSeq
        let state = await Task.detached(priority: .userInitiated) {
            Self.computeDerived(days: days, displayDays: displayDays, appleDays: appleDays,
                                todayRecovery: todayRecovery,
                                todayKey: todayKey, yKey: yKey)
        }.value
        // FER-982: si un refresh más nuevo ya superó a este mientras el cómputo estaba en vuelo, no pises
        // sus memos con un snapshot viejo — el `.task(id: refreshSeq)` más nuevo los sembrará. (El `.task`
        // cancela a su predecesor, pero el `Task.detached` es independiente y podría aterrizar después.)
        guard seq == repo.refreshSeq else { return }
        memoReadiness = state.readiness
        memoCounts = state.counts
        memoYesterdayLevel = state.yesterdayLevel
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
                                           appleDays: Set<String>, todayRecovery: Double?,
                                           todayKey: String, yKey: String) -> DerivedState {
        // FER-623: el veredicto mide la HRV solo contra la base de BANDA (RMSSD), vía `band`.
        let band = SourceLens.clearBandHrv(days)
        let readiness = ReadinessEngine.evaluate(days: band, today: todayKey)
        let counts = computeHrvCounts(days: days, appleDays: appleDays, todayHasRecovery: todayRecovery != nil)
        // FER-475: el veredicto de ayer, para la línea de continuidad de la página 1 «en espera».
        let yesterdayLevel = ReadinessEngine.evaluate(days: band, today: yKey).level
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
        return DerivedState(readiness: readiness, counts: counts, yesterdayLevel: yesterdayLevel,
                            baselineDays: baselineDays,
                            trainingLoad: trainingLoad)
    }

    /// FER-623: `repo.days` con la HRV de Apple (SDNN) enmascarada, para medir el veredicto solo contra la
    /// base de BANDA (RMSSD) — igual que Recuperación (FER-519): la σ de «HRV vs tu base» no se contamina
    /// mezclando dos métricas sin conversión. Lee `days` + `appleHealthDays` en una sola expresión síncrona
    /// (mismo dashboard publicado, sin await en medio) para no reintroducir la carrera FER-177. Una sola
    /// fuente de verdad: `recomputeDerived` y el fallback en frío de `readiness` la comparten (deben coincidir).
    private var bandDays: [DailyMetric] {
        SourceLens.clearBandHrv(repo.days)
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
        // FER-888 / FER-1003: Solo-Apple — empty states speak of the Apple Watch, not the band.
        switch state {
        case .loading, .verdict:
            return nil   // neutro de carga (o veredicto, ya filtrado arriba): nada que explicar todavía
        case .calibrating:
            return "Your baseline is still settling. A couple more nights of sleep tracked with your Apple Watch, and your day's verdict starts to show here."
        case .waiting:
            // Modificador «descargando» (ex-`.downloading`); si no, espera / base Apple.
            if isSyncing {
                return "We're syncing from Apple Health. As soon as it finishes, your day's verdict shows here."
            }
            return "Your day's reading comes from how you slept. There's no data for last night yet. Wear your Apple Watch to sleep and it reads here in the morning."
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
            .task(id: repo.refreshSeq) {
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
            .animation(.easeOut(duration: 0.18), value: showingSupport)
            // The summary sheet. On dismiss, run any pending "Ver más" hand-off (FER-251): presenting the
            // rich detail only AFTER this one is gone avoids SwiftUI swallowing a sheet-over-sheet present.
            // A plain swipe-to-close leaves `pendingSeeMore` nil, so nothing extra happens.
            .sheet(item: $metricDetail, onDismiss: { pendingSeeMore?(); pendingSeeMore = nil }) { info in
                metricSheet(for: info)
            }
            // FER-953: precompute the sleep summary model off-main when the sleep info sheet opens.
            .task(id: metricDetail?.id) {
                guard metricDetail?.id == "sleep" else {
                    if sleepSummaryModel != nil { sleepSummaryModel = nil }   // avoid gratuitous invalidation
                    return
                }
                let model = await SleepDetailModel.buildDetached(repo: repo)
                guard !Task.isCancelled else { return }   // sheet switched away while building
                sleepSummaryModel = model
            }
            .sheet(isPresented: $showWhyVerdict) {
                WhyVerdictSheet(readiness: readiness, theme: theme,
                                sleepMinutes: repo.today?.totalSleepMin,
                                emptyStateExplanation: whyEmptyExplanation)
            }
            // Rich «Instrumento» Detalle, drilled into from a summary sheet's "Ver más" — the SAME screens
            // Cuerpo presents, theme passed explicitly (it doesn't propagate through `.sheet`), NO nested
            // NavigationStack (FER-171). (FER-251)
            //
            // `.recEntranceGate()` on each: the hero's rise (recRise) otherwise plays WHILE the system sheet
            // slides up from the bottom, so a synchronous-datum screen (Estrés, Temp. de piel, Carga) shows
            // the number already in place — the same lost-under-the-motion bug the Tendencias layer fixed
            // (FER-1008). The gate holds the keyframes until the sheet lands; the late-swap screens
            // (Recuperación/Sueño/Esfuerzo) are unaffected (their number appears after the gate flips anyway).
            .sheet(item: $recoveryDetail) { item in
                RecoveryDetailScreen(theme: theme, model: item.model)
                    .recEntranceGate()
            }
            .sheet(item: $sleepDetail) { item in
                SleepDetailScreen(theme: theme, model: item.model,
                                  loadNightHR: { from, to in await repo.hrSamples(from: from, to: to) },
                                  loadNightRR: { from, to in await repo.rrIntervals(from: from, to: to) },
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
                // Hoja «Carga de entrenamiento» (FER-705 · handoff «Carga») — tema explícito (no cruza `.sheet`),
                // sin NavigationStack anidado (FER-171). «Tu patrón» y «Ver más en Tendencias» llegan como
                // closures que despachan por el `TabRouter` (Patrones / Cuerpo).
                TrainingLoadSheet(model: item.model, theme: theme,
                                  patternText: item.patternText,
                                  onSeePattern: item.onSeePattern,
                                  onSeeTrends: item.onSeeTrends)
                    .recEntranceGate()
            }
    }

    /// Arma la hoja de carga desde la franja: engancha «Tu patrón» al hallazgo de carga (si existe, de la
    /// misma fuente que Patrones) y «Ver más en Tendencias» al tab Cuerpo, ambos vía `TabRouter`.
    private func makeTrainingLoadItem(_ model: TrainingLoadModel) -> TrainingLoadItem {
        let loadInsight = insights.first { $0.kind == .trainingLoad }
        return TrainingLoadItem(
            model: model,
            patternText: loadInsight?.reading,
            // FER-992: CTA to Patrones off — re-enable:
            // onSeePattern: loadInsight.map { i in { tabRouter.openInsight(key: InsightFreshness.key(for: i)) } },
            onSeePattern: nil,
            onSeeTrends: { tabRouter.select(.body) })
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
        case "recovery":
            present = {
                // FER-954: present the loading state IMMEDIATELY; the model builds off-main and swaps
                // in under the same id (same pattern as `sleep` above, FER-953).
                let item = RecoveryDetailItem(model: .loading)
                recoveryDetail = item
                Task {
                    let m = await RecoveryDetailModel.buildDetached(repo: repo)
                    if recoveryDetail?.id == item.id {
                        recoveryDetail = RecoveryDetailItem(id: item.id, model: m)
                    }
                }
            }
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
        .sheet(isPresented: $showAutonomicDetail) {
            AutonomicTrendDetailSheet(theme: theme)
                .presentationDragIndicator(.visible)
                .presentationBackground(theme.paper)
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
                // Bloque FIJO del instrumento (handoff «Hoy» 2026-07): header + héroe + pestañas. Sigue
                // dentro del scroll vertical, así que el pull-to-refresh propio (FER-222) NO cambia.
                // Todo lo demás desliza con el pager.
                // FER-878 follow-up: aire más apretado entre header y héroe (space1) para recuperar el
                // alto que sumaron la cápsula del delta y la leyenda de orígenes, y que SEÑALES vuelva a
                // caber sin scroll.
                VStack(alignment: .leading, spacing: CenitMetrics.space1) {
                    headerBlock
                    HealthAlertBanner()
                    heroBlock
                    autonomicTrendCardBlock
                }
                sectionTabs
                    .padding(.top, CenitMetrics.space1)   // FER-878 follow-up: cromo apretado para caber sin scroll
                // La franja de carga YA NO vive aquí: se movió DENTRO de la página Señales (bajo las cinco
                // reglas) para que pertenezca solo a Señales y no aparezca al deslizar a Brief. Ver `senalesPage`.
                // Pager horizontal de 2 páginas: ① SEÑALES (por qué + tiles) · ② BRIEF. Full-bleed (FER-725):
                // se le pasa el ancho COMPLETO de la pantalla y el pager cancela el margen del padre por
                // dentro, así cada hoja ocupa todo el ancho y se va limpia a un lado. Ejes ortogonales al
                // scroll vertical → el swipe horizontal y el pull-to-refresh no se pelean.
                todayPager(fullWidth: proxy.size.width)
                    .padding(.top, CenitMetrics.space2)
                // La otra mitad del sobrante vive AQUÍ: mantiene los page dots al fondo, cerca del dock,
                // mientras el `Spacer` de arriba baja la rejilla al centro.
                Spacer(minLength: CenitMetrics.space2)
                todayPageDots
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
                    didFirstPullSync: didFirstPullSync,
                    reduceMotion: reduceMotion
                )
            }
            // Inset superior `gap` (FER-202): el héroe queda alto pero respira.
            .padding(.horizontal, CenitMetrics.screenPadding)
            // Margen inferior compacto (FER-475): los page dots (último elemento) quedan pegados al dock,
            // no flotando con 24pt de aire. Bajado 8→4 para asentar los dots un pelín MÁS abajo (más cerca
            // del dock) y, de paso, reclamar altura que compensa el numeral mayor. La rejilla de métricas
            // mantiene su aire propio (cards + gap).
            .padding(.bottom, CenitMetrics.space1)
            .padding(.top, CenitMetrics.space2)
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

    /// Recovery score driving the hero numeral (0–100). nil while calibrating.
    private var recoveryScore: Int? { repo.today?.recovery.map { Int($0.rounded()) } }

    /// The recovery summary sheet's model — the ONE way every entry point (Daily Brief bullet, the
    /// hero numeral, the glance pill) opens it.
    private var recoveryInfo: MetricInfo {
        .recovery(score: recoveryScore,
                  calibrationNights: recoveryCalibration,
                  nightsNeeded: Baselines.minNightsSeed)
    }

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

    // MARK: - Héroe unificado «Instrumento diurno» (FER-160)
    //
    // Un SOLO esqueleto para los cuatro modos del héroe. Antes había cuatro sub-vistas con layouts
    // distintos; aquí comparten una sola estructura —overline + numeral dominante + dial + cuerpo +
    // pie— y solo cambian el numeral, su color y el pie. La regla «color = listo / tinta = en espera»
    // hace de semáforo de estado: numeral con color de banda = la lectura de hoy está lista; numeral en
    // tinta o em-dash «—» = en espera o sin contexto. Mata el último layout pre-veredicto separado.

    /// FER-878: los 3 estados NARRADOS del héroe + el frame de carga, colapsados del árbol de 6 previo.
    /// Las variantes «descargando» (FER-286) y «base Apple» (FER-106) ya NO son estados propios: son
    /// MODIFICADORES de EN ESPERA (`.waiting`), derivados de las mismas señales de solo-lectura de antes
    /// (`isSyncing` narra la descarga vía la línea de sync del header + el sello girando; `hasImportedBaseline`
    /// pinta el chip «Base · Apple Salud» y el CTA «Buscar banda»). El orden de prioridad se conserva
    /// idéntico: solo cambia la etiqueta del caso, no cuándo se entra a él.
    private enum HeroState: Equatable {
        case loading                    // el dashboard aún no publica (repo.loaded == false): esqueleto neutro, sin narrativa
        case verdict                    // LISTO — repo.today?.recovery != nil → hay número
        case calibrating(nights: Int)   // CALIBRANDO — strap visto, ownNights < seed
        case waiting                    // EN ESPERA — absorbe descargando (isSyncing) y base Apple (hasImportedBaseline)
    }

    private var heroState: HeroState {
        if repo.today?.recovery != nil { return .verdict }
        // Arranque frío: mientras el refresh no publica la historia COMPLETA, los conteos de abajo
        // mienten (con `days` vacío ownNights = 0 → «calibrando»; sobre la ventana corta de la primera
        // pasada subcuentan igual). El veredicto no espera nada — sale arriba en cuanto hay recovery de
        // hoy, y la ventana corta siempre trae la fila de hoy; solo los narrativos pre-veredicto
        // aguardan `fullyLoaded` para no narrar un estado falso.
        if !repo.fullyLoaded { return .loading }
        // FER-286/FER-106: descargando la noche o base sembrada por Apple → EN ESPERA (la descarga la
        // narran el header + el sello; la base Apple, el chip de procedencia). Mismo corte y prioridad que
        // antes —solo que ahora ambos ramales caen en `.waiting` en vez de en dos casos propios.
        if isSyncing || hasImportedBaseline { return .waiting }
        // TODO(/pm): revisar si "nunca conectó Apple Health" debería ser un estado distinto de "calibrando"
        if ownNights < Baselines.minNightsSeed { return .calibrating(nights: ownNights) }
        return .waiting
    }


    @ViewBuilder private var heroBlock: some View {
        // FER-1029: Hoy tiene UNA sola cara — la de Apple (Sueño de anoche + la tarjeta de tendencia
        // autonómica). El héroe del veredicto 0–100 (era banda) se retiró: en Apple-only `repo.today.recovery`
        // es siempre nil, así que ese path era inalcanzable (solo lo encendían datos de banda dormidos).
        appleTrendHero
    }

    /// R4 (FER-1008): el héroe del path Apple-only — el SUEÑO es el número dominante (el 0–100 estilo-WHOOP
    /// se retiró). Toca → detalle de sueño.
    @ViewBuilder private var appleTrendHero: some View {
        let sleepMin = resolveMeasured(todayOnly: true) { $0.totalSleepMin }?.value
        VStack(alignment: .leading, spacing: CenitMetrics.space1) {
            Text("SUEÑO DE ANOCHE").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            if let sleepMin, sleepMin > 0 {
                let h = Int(sleepMin) / 60, m = Int(sleepMin) % 60
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(h)").font(StrandFont.number(64)).foregroundStyle(theme.ink)
                    Text("h ").font(StrandFont.number(28)).foregroundStyle(theme.inkSecondary)
                    Text("\(m)").font(StrandFont.number(64)).foregroundStyle(theme.ink)
                    Text("m").font(StrandFont.number(28)).foregroundStyle(theme.inkSecondary)
                }
                .lineLimit(1).minimumScaleFactor(0.6)
                Text(sleepMin >= 420 ? "Dormiste bien" : "Sueño corto")
                    .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
            } else {
                Text("—").font(StrandFont.number(64)).foregroundStyle(theme.inkTertiary)
                Text("Sin registro de sueño anoche").font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { metricDetail = .sleep(resolveMeasured(todayOnly: true) { $0.totalSleepMin }.map { Int($0.value.rounded()) }) }
        .accessibilityElement(children: .combine)
    }

    /// R4 (FER-1008): la tarjeta «cómo vienes» — solo en el path Apple-only (sin recuperación de banda) y
    /// cuando hay una lectura de tendencia. En banda con veredicto no aparece (el veredicto es el héroe).
    @ViewBuilder private var autonomicTrendCardBlock: some View {
        if repo.today?.recovery == nil, let trend = repo.todayAutonomicTrend {
            AutonomicTrendCard(
                read: trend,
                showLowSampleBanner: (resolveMeasured(todayOnly: true) { $0.totalSleepMin }?.value ?? 0) > 0 && trend.asOfWasDense == false,
                onTap: { showAutonomicDetail = true }
            )
            .padding(.top, CenitMetrics.space2)
        }
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
        case .waiting where !isSyncing:
            // EN ESPERA (sin la descarga en curso) y base Apple: el Brief «en espera» enriquecido. La
            // descarga (isSyncing) cae al copy honesto de heroBody de abajo, como antes `.downloading`.
            waitingBrief(state)
        default:   // descargando (waiting+isSyncing) / calibrating — y .verdict SÍ llega aquí cuando
                   // `dailyBrief == nil` (nivel .insufficient o < 2 viñetas): cae al copy honesto (FER-547)
            VStack(spacing: CenitMetrics.gap) {
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
        VStack(alignment: .leading, spacing: CenitMetrics.gap) {
            briefHeader(now: false)
            Text("No reading for today yet")
                .font(StrandFont.title2).fontWeight(.semibold).foregroundStyle(theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("Connect Apple Health and your reading will refresh every morning.")
                .font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let y = yesterdayVerdict { yesterdayLine(y) }
            heroFooter(state)   // FER-1003: solo el atajo de Apple Salud en calibración; vacío en espera
            metricsBridge
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// El puente a Señales desde el Brief transicional: desliza el pager a la página de tiles (donde
    /// hay datos que ver mientras llega el veredicto). Cápsula en tinta — chrome, no dato (sin verde).
    private var metricsBridge: some View {
        Button {
            withAnimation(StrandMotion.gated(StrandMotion.interactive, reduceMotion)) { pagerPage = 0 }
        } label: {
            HStack(spacing: CenitMetrics.space2) {
                Text("See your metrics for today").font(StrandFont.subhead.weight(.semibold))
                Image(systemName: "arrow.right").font(StrandFont.glyph(.chevron, weight: .semibold))
            }
            .foregroundStyle(theme.inkSecondary)
            .padding(.horizontal, CenitMetrics.cardPadding).padding(.vertical, CenitMetrics.gap)
            .overlay(Capsule().strokeBorder(theme.hairlineStrong, lineWidth: 1))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, CenitMetrics.space2)
        .accessibilityHint(Text("Opens today's metrics page"))
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

    /// El Daily Brief renderizado (handoff «Hoy» 2026-07): plano sobre el papel — encabezado con el
    /// punto AHORA, titular 22/700 en grotesk (abre el porqué), cuerpo, «La conexión de hoy» sobre
    /// `patternBlock`, las filas de acción y el CTA de entrenamiento. Las cinco reglas NO viven aquí
    /// (pertenecen solo a Señales). Sin serif: la voz nueva es Space Grotesk (F0).
    private func dailyBriefView(_ brief: DailyBrief) -> some View {
        VStack(alignment: .leading, spacing: CenitMetrics.gap) {
            briefHeader(now: true)
            Button { showWhyVerdict = true } label: {
                HStack(alignment: .firstTextBaseline, spacing: CenitMetrics.space2) {
                    Text(brief.titular)
                        .font(InstrumentoType.grotesk(22, weight: .bold, relativeTo: .title2))
                        .tracking(-0.4)
                        .foregroundStyle(theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    StrandIcon.info.image.font(StrandFont.glyph(.inline))
                        .foregroundStyle(theme.inkTertiary)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("Opens why the verdict reads this way"))

            Text(brief.why).font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            // FER-992: «La conexión de hoy» + CTAs to Patrones off (`dayConnectionView` below stays for re-enable).
            // FER-999: su fuente de datos (`dayConnection` + `activeExperiment` + `loadActiveExperiment`) se borró
            // por estar 100% huérfana; `loadActiveExperiment` además escribía a la DB en cada `loadAll`. Re-enable =
            // restaurarla desde el historial de git y volver a llamar `dayConnectionView(conn)` aquí.

            VStack(spacing: 0) {
                ForEach(Array(brief.bullets.enumerated()), id: \.offset) { i, b in
                    briefBulletRow(b, showTopHairline: i > 0)
                }
            }

            if let tb = trainingBlock { trainingBlockView(tb) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - «La conexión de hoy» (FER-614 correlación · FER-615 experimento)

    /// El renglón «La conexión de hoy»: despacha entre la correlación detectada (F2) y el experimento N-of-1 en
    /// curso (F3), ya elegidos por la regla de prioridad del motor. Ambos comparten el mismo chrome (overline +
    /// acento + frase + CTA); solo cambian la frase, el copy del CTA y el destino del deep-link.
    @ViewBuilder
    private func dayConnectionView(_ conn: DailyBrief.DayConnection) -> some View {
        switch conn {
        case .correlation(let c):
            connectionLineView(text: c.text, cta: "See pattern",
                               hint: "Opens this pattern in Patrones") {
                tabRouter.openInsight(key: InsightFreshness.key(for: c.insight))
            }
        case .experiment(let line):
            connectionLineView(text: line.text,
                               cta: line.pendingCheckIn ? "Log check-in" : "See experiment",
                               hint: line.pendingCheckIn
                                   ? "Opens your experiment in Patrones to log today's check-in"
                                   : "Opens your experiment in Patrones") {
                tabRouter.openExperiment()
            }
        }
    }

    /// El chrome compartido del renglón «La conexión de hoy»: acento verde a la izquierda, la frase sin jerga y
    /// el CTA con chevron. Toca → `action` (deep-link a Patrones, distinto por fuente).
    private func connectionLineView(text: String, cta: LocalizedStringKey, hint: String,
                                    action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: CenitMetrics.space1) {
                Text("Today's connection").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                HStack(alignment: .firstTextBaseline, spacing: CenitMetrics.space2) {
                    Text(text).font(StrandFont.subhead).foregroundStyle(theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: CenitMetrics.space2)
                    HStack(spacing: 2) {
                        Text(cta).font(StrandFont.caption)
                        StrandIcon.disclosure.image.font(StrandFont.glyph(.chevron, weight: .semibold))
                    }
                    .foregroundStyle(theme.verdict)
                    .fixedSize()
                }
            }
            .padding(.leading, CenitMetrics.gap)
            .padding(.trailing, CenitMetrics.space2)
            .padding(.vertical, CenitMetrics.space2)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Bloque «patrón/conexión» del handoff: fondo `patternBlock` con la barra verde a la
            // izquierda y esquinas redondeadas solo del lado derecho (radio 0 8 8 0).
            .background(theme.patternBlock,
                        in: UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0,
                                                   bottomTrailingRadius: 8, topTrailingRadius: 8,
                                                   style: .continuous))
            .overlay(alignment: .leading) { Rectangle().fill(theme.verdict).frame(width: 2.5) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, CenitMetrics.space2)
        .accessibilityHint(Text(hint))
    }

    // MARK: - Bloque «Hoy en tu plan» (FER-613)

    /// El bloque puente con Entrenar al pie del brief: su propia tarjeta `surface`, fiel al preview aprobado.
    /// Día de entreno → rutina + chip de racha + línea de ritmo (color por `pace`) + «Empezar»; descanso →
    /// «Hoy descansas». El color del ritmo (verde sube / ámbar baja) es el único dato con color, como el resto
    /// del «Instrumento». «Empezar» enruta a Entrenar y arranca la sesión vía `TabRouter` (reusa el prefetch).
    private func trainingBlockView(_ tb: DailyBrief.TrainingBlock) -> some View {
        VStack(alignment: .leading, spacing: CenitMetrics.space2) {
            Text("Today in your plan").instrumentoOverline().foregroundStyle(theme.inkTertiary)
            switch tb.state {
            case .training:
                HStack(alignment: .firstTextBaseline, spacing: CenitMetrics.space2) {
                    Text(tb.routineName ?? "").font(StrandFont.title2).foregroundStyle(theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    streakChip(tb.streakDays)
                    Spacer(minLength: 0)
                }
                if let copy = tb.paceCopy {
                    HStack(spacing: CenitMetrics.space2) {
                        Image(systemName: paceGlyph(tb.pace)).font(StrandFont.glyph(.inline, weight: .semibold))
                            .foregroundStyle(paceColor(tb.pace))
                        Text(copy).font(StrandFont.subhead).foregroundStyle(paceColor(tb.pace))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }
                // CTA del handoff: barra en TINTA (radio 14) con la rutina en crema y «EMPEZAR →» en el
                // acento `ctaAccent` — el único lugar donde ese verde eléctrico existe (solo sobre tinta).
                Button { tabRouter.startTodayTraining() } label: {
                    HStack(spacing: CenitMetrics.space2) {
                        Text(tb.routineName ?? String(localized: "Your workout"))
                            .font(InstrumentoType.grotesk(13, weight: .bold))
                            .foregroundStyle(theme.paperHi)
                            .lineLimit(1).minimumScaleFactor(0.8)
                        Spacer(minLength: CenitMetrics.space2)
                        HStack(spacing: CenitMetrics.space1) {
                            Text("Start")
                                .font(InstrumentoType.grotesk(11, weight: .semibold))
                                .tracking(1.2)
                                .textCase(.uppercase)
                            Image(systemName: "arrow.right").font(StrandFont.glyph(.chevron, weight: .semibold))
                        }
                        .foregroundStyle(theme.ctaAccent)
                    }
                    .padding(.horizontal, CenitMetrics.cardPadding)
                    .padding(.vertical, 14)
                    .background(theme.ink, in: RoundedRectangle(cornerRadius: CenitMetrics.ctaRadius, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, CenitMetrics.space1)
                .accessibilityHint(Text("Opens Train and starts today's session"))
            case .rest:
                HStack(spacing: CenitMetrics.gap) {
                    Image(systemName: "moon.fill").font(StrandFont.glyph(.inline)).foregroundStyle(theme.inkSecondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Rest day today").font(StrandFont.subhead.weight(.semibold)).foregroundStyle(theme.ink)
                        Text("your split has no routine today").font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(CenitMetrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous)
                .fill(theme.surface)
                .strandElevation(.hairline, ink: theme.ink)
        }
        .overlay(RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous)
            .strokeBorder(theme.hairline, lineWidth: 1))
    }

    /// El chip de racha: glifo de llama + «racha N días» (singular «día» en 1). Mismo número que Entrenar.
    private func streakChip(_ days: Int) -> some View {
        let unit = days == 1 ? String(localized: "day") : String(localized: "days")
        return HStack(spacing: 4) {
            Image(systemName: "flame.fill").font(StrandFont.glyph(.chevron)).foregroundStyle(theme.warning)
            Text("streak \(days) \(unit)").font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
        }
        .padding(.horizontal, CenitMetrics.space2).padding(.vertical, 2)
        .background(theme.paper, in: Capsule())
        .overlay(Capsule().strokeBorder(theme.hairline, lineWidth: 0.5))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Streak of \(days) \(unit) in your plan"))
    }

    /// El color del ajuste de ritmo: verde «sube», ámbar «baja», tinta secundaria «mantén» — color en el dato.
    private func paceColor(_ pace: DailyBrief.TrainingBlock.Pace?) -> Color {
        switch pace {
        case .up:   return theme.verdict
        case .down: return theme.warning
        case .hold, .none: return theme.inkSecondary
        }
    }


    /// El encabezado de la página 1 (FER-475): overline «DAILY BRIEF» · punto · «AHORA» (verde, con
    /// veredicto) o «EN ESPERA» (tinta, sin lectura) + una regla hairline. Fiel al handoff.
    private func briefHeader(now: Bool) -> some View {
        VStack(alignment: .leading, spacing: CenitMetrics.space2) {
            HStack(spacing: CenitMetrics.space2) {
                Text("Daily Brief").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                Spacer(minLength: 0)
                // FER-549/handoff: el estado va a la DERECHA (space-between) y el punto «Ahora» PULSA (halo)
                // cuando hay veredicto; estático en espera o bajo Reduce Motion.
                nowDot(now: now)
                Text(now ? "Now" : "Waiting").instrumentoOverline()
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
                    .strandAnimation(StrandMotion.breathe, value: briefDotPulse)
            }
            Circle().fill(c).frame(width: 6, height: 6)
        }
        .frame(width: 6, height: 6)
        .onAppear { if now && !reduceMotion { briefDotPulse = true } }
        .accessibilityHidden(true)
    }

    /// La línea de continuidad «Ayer cerraste en …» (FER-475): el nivel del veredicto de ayer en su color.
    private func yesterdayLine(_ level: ReadinessEngine.Level) -> some View {
        HStack(spacing: CenitMetrics.space2) {
            Text("Ayer cerraste en").font(StrandFont.subhead).foregroundStyle(theme.inkTertiary)
            Text(stateLabel(level)).font(StrandFont.subhead.weight(.semibold))
                .foregroundStyle(verdictDataColor(level))
        }
        .accessibilityElement(children: .combine)
    }

    /// Una viñeta del Daily Brief: glifo SF tintado por el flag (misma fuente de color que la palabra del
    /// veredicto, vía `flagColor`) + lead semibold + sub con la cifra + chevron. Toda la fila es tocable
    /// (FER-475): abre `WhyVerdictSheet` —«tus señales de hoy» en σ— el detalle compartido de cualquier
    /// viñeta (el handoff usa una hoja con cuerpo común). Separador hairline entre viñetas.
    private func briefBulletRow(_ b: DailyBrief.Bullet, showTopHairline: Bool) -> some View {
        Button { openBriefBullet(b.kind) } label: {
            HStack(spacing: CenitMetrics.gap) {
                Image(systemName: briefGlyph(b.kind))
                    .font(StrandFont.glyph(.lead))
                    .foregroundStyle(flagColor(b.flag))
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(b.lead).font(StrandFont.subhead.weight(.semibold)).foregroundStyle(theme.ink)
                    Text(b.sub).font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                StrandIcon.disclosure.image.font(StrandFont.glyph(.chevron, weight: .semibold))
                    .foregroundStyle(theme.inkTertiary)
            }
            .padding(.vertical, CenitMetrics.space2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) {
            if showTopHairline { Rectangle().fill(theme.hairline).frame(height: 0.5) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Opens today's signals detail"))
    }

    /// FER-589: cada viñeta del Brief abre el DETALLE de su señal (el mismo destino que la pill/tile de
    /// esa métrica), no la hoja genérica del veredicto. `skinTemp`/`acwr` no tienen detalle propio (son
    /// contexto del veredicto) → ahí sí cae a `WhyVerdictSheet`, a propósito.
    private func openBriefBullet(_ kind: DailyBrief.BulletKind) {
        switch kind {
        case .sleep:
            metricDetail = .sleep(resolveMeasured(todayOnly: true) { $0.totalSleepMin }.map { Int($0.value.rounded()) })
        case .recovery:
            metricDetail = recoveryInfo
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

    /// Página 1 del pager: SEÑALES — el bloque «POR QUÉ N» (las cinco reglas, solo con veredicto) +
    /// la retícula 2×4 de tiles; o la tarjeta de fuentes si no hay ninguna (FER-364).
    @ViewBuilder private var senalesPage: some View {
        // Gap `space2` (8) entre «Por qué N» y la retícula (FER-878 follow-up: 12→8 para recuperar el alto
        // que sumó la leyenda de orígenes y el numeral más grande, y que SEÑALES quepa sin scroll).
        VStack(alignment: .leading, spacing: CenitMetrics.space2) {
            // Franja de carga (FER-705 · handoff «Carga»): ahora vive DENTRO de Señales, bajo las cinco
            // reglas, así que pertenece solo a esta página y NO viaja al Brief con el swipe. No respira ni
            // participa del pull-to-refresh; tocarla abre la hoja. Si `trainingLoad` aún no sembró (primer
            // refresh) se omite; una vez con datos muestra la banda o «calibrando».
            if let trainingLoad {
                TrainingLoadStrip(model: trainingLoad, theme: theme) {
                    trainingLoadItem = makeTrainingLoadItem(trainingLoad)
                }
            }
            if noSources { emptySourcesCard } else { iosMetricsSection }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// El pager horizontal de 2 páginas (FER-465, pulido FER-725). **Full-bleed:** cada página ocupa el
    /// ANCHO COMPLETO de la pantalla (el `.padding(.horizontal, -screenPadding)` cancela el margen del
    /// padre; cada página se re-inseta por dentro), así al deslizar la hoja se va hasta el borde en vez de
    /// recortarse dentro de un «marco». Entre páginas va el `pagerGutter` y el snap es `.viewAligned` para
    /// que respete ese hueco. **Alto por página activa:** el pager mide su alto según la hoja mostrada
    /// (`pageHeights`), no la más alta, de modo que el scroll vertical externo solo crece en Brief; el
    /// recorte de la hoja más alta durante el arrastre queda bajo el borde inferior (invisible). Ejes
    /// ortogonales al scroll vertical → no se pelea con el pull-to-refresh.
    @ViewBuilder private func todayPager(fullWidth: CGFloat) -> some View {
        let activeHeight = pageHeights[pagerPage ?? 0]
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: pagerGutter) {
                pagerPageContent(senalesPage, index: 0, fullWidth: fullWidth)
                pagerPageContent(verdictPage, index: 1, fullWidth: fullWidth)
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $pagerPage)
        .onPreferenceChange(TodayPageHeightKey.self) { new in
            for (k, v) in new where pageHeights[k] != v { pageHeights[k] = v }
        }
        .frame(height: activeHeight, alignment: .top)
        .padding(.horizontal, -CenitMetrics.screenPadding)
        // Anima el alto al CAMBIAR de página (valor discreto y estable), NUNCA con `activeHeight`:
        // ese alto se mide en el layout y tiembla sub-punto en cada pasada, así que animarlo implícito
        // reactiva el layout en bucle infinito → main thread al 99% y la pantalla se congela.
        .strandAnimation(.easeInOut(duration: 0.25), value: pagerPage)
    }

    /// Una página del pager (FER-725): ancho COMPLETO de pantalla con su contenido re-insetado por
    /// `screenPadding` (para alinear con el header/héroe), y su alto natural publicado vía
    /// `TodayPageHeightKey` para el «alto por página activa».
    private func pagerPageContent<P: View>(_ page: P, index: Int, fullWidth: CGFloat) -> some View {
        page
            .padding(.horizontal, CenitMetrics.screenPadding)
            .frame(width: fullWidth, alignment: .top)
            .background(GeometryReader { geo in
                Color.clear.preference(key: TodayPageHeightKey.self, value: [index: geo.size.height])
            })
            .id(index)
    }

    /// Las pestañas SEÑALES / BRIEF sobre el pager (handoff): 11/700 trackeadas, activa en tinta,
    /// inactiva en `inkMuted`, con un subrayado elástico de 2 pt que se desliza con spring y cambia de
    /// ancho entre palabras (`matchedGeometryEffect`). Tocar una pestaña anima el pager a su página.
    @Namespace private var tabUnderlineNS
    private var sectionTabs: some View {
        HStack(spacing: CenitMetrics.cardPadding) {
            tabButton("Signals", page: 0)
            tabButton("Brief", page: 1)
            Spacer(minLength: 0)
        }
        .strandAnimation(StrandMotion.interactive, value: pagerPage)
    }

    private func tabButton(_ title: LocalizedStringKey, page: Int) -> some View {
        let active = (pagerPage ?? 0) == page
        return Button {
            withAnimation(StrandMotion.gated(.spring(response: 0.34, dampingFraction: 0.62), reduceMotion)) {
                pagerPage = page
            }
        } label: {
            VStack(alignment: .leading, spacing: CenitMetrics.space1 + 1) {
                Text(title)
                    .font(InstrumentoType.groteskTab)
                    .tracking(InstrumentoType.groteskTabTracking)
                    .textCase(.uppercase)
                    .foregroundStyle(active ? theme.ink : theme.inkMuted)
                Rectangle()
                    .fill(active ? theme.ink : Color.clear)
                    .frame(height: 2)
                    .modifier(TabUnderlineEffect(active: active, ns: tabUnderlineNS))
            }
            .fixedSize()
            .contentShape(Rectangle())
            .frame(minHeight: 34)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? [.isButton, .isSelected] : .isButton)
    }

    /// El subrayado elástico: `matchedGeometryEffect` UNA sola vez (en la pestaña activa) hace que la
    /// barra viaje y cambie de ancho entre palabras con el spring del tap.
    private struct TabUnderlineEffect: ViewModifier {
        let active: Bool
        let ns: Namespace.ID
        func body(content: Content) -> some View {
            if active {
                content.matchedGeometryEffect(id: "tabUnderline", in: ns)
            } else {
                content
            }
        }
    }

    /// Page dots: punto 7×7 inactivo (`hairlineStrong`) · barra 22×7 activa (`ink`), centrados (un pelín
    /// más grandes para dar más presencia al indicador). Tocar un punto navega a su página
    /// (`StrandMotion.interactive`, omitida bajo Reduce Motion). El acento verde NO se usa en el chrome:
    /// la página activa es TINTA, no verde (handoff). Área tocable de 28pt.
    private var todayPageDots: some View {
        HStack(spacing: CenitMetrics.space2) {
            ForEach(0..<2, id: \.self) { i in
                let active = (pagerPage ?? 0) == i
                Button {
                    withAnimation(StrandMotion.gated(StrandMotion.interactive, reduceMotion)) { pagerPage = i }
                } label: {
                    Capsule(style: .continuous)
                        .fill(active ? theme.ink : theme.hairlineStrong)
                        .frame(width: active ? 22 : 7, height: 7)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(i == 0 ? "Signals" : "Brief"))
                .accessibilityAddTraits(active ? [.isButton, .isSelected] : .isButton)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        // Sin padding superior propio: el `Spacer(minLength: space2)` que precede a los dots ya da esa
        // separación. Sumar aquí otro `space2` duplicaba el gap (8 + 8) y empujaba ~8pt de scroll fantasma.
        .strandAnimation(StrandMotion.interactive, value: pagerPage)
    }

    /// El instrumento está sincronizando: offload en curso, su puente async (FER-480 `draining`) o el
    /// pull-to-sync manual. Fuente única para las señales del héroe (estado, dial, numeral, pista).
    /// La pista del pull (FER-293) y el sello armado viven en `PullSyncHint` / `PullIndicator`
    /// (FER-972 P-09): leen el progreso en su propio body para no invalidar Hoy por frame.
    // TODO(/pm): sin banda, "sincronizando" solo refleja el pull-to-refresh del usuario, no un fetch real de Apple Health en curso.
    private var isSyncing: Bool { pullSyncing }

    /// El cuerpo bajo el numeral: la palabra del veredicto + «i» + modificadores (veredicto), o la línea
    /// honesta de qué falta (resto de modos).
    @ViewBuilder private func heroBody(_ s: HeroState) -> some View {
        switch s {
        case .verdict:
            verdictBody
        case .calibrating(let nights):
            VStack(alignment: .center, spacing: CenitMetrics.gap) {
                calibrationDots(nights: nights)   // FER-467: pulso vivo movido al encabezado de Métricas
                Text(calibrationDetailCopy(nights: nights))
                    .font(StrandFont.body).foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
        case .waiting:
            VStack(alignment: .center, spacing: CenitMetrics.space2) {
                if isSyncing {
                    // Modificador «descargando» (ex-`.downloading`, FER-286): el dial ya gira (FER-221);
                    // aquí el copy honesto de que el dato viene en camino.
                    Text("Downloading last night…")
                        .font(StrandFont.headline).foregroundStyle(theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Your data from last night is arriving. The first sync of the day can take a few minutes.")
                        .font(StrandFont.body).foregroundStyle(theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if hasImportedBaseline {
                    // Modificador «base Apple» (ex-`.importedBaseline`, FER-106): el chip de procedencia.
                    appleBaseChip   // FER-467: el pulso vivo se mudó al encabezado de Métricas (página 2)
                    Text("Today's reading is missing")
                        .font(StrandFont.headline).foregroundStyle(theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Today's reading fills in once last night's sleep syncs from Apple Health.")
                        .font(StrandFont.body).foregroundStyle(theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    // FER-467: el pulso vivo se mudó al encabezado de Métricas (página 2); aquí solo el titular.
                    Text("No reading yet")
                        .font(StrandFont.headline).foregroundStyle(theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Connect Apple Health to start.")
                        .font(StrandFont.body).foregroundStyle(theme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
        case .loading:
            EmptyView()
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
                HStack(spacing: CenitMetrics.space2) {
                    StrandIcon.warning.image.font(StrandFont.glyph(.chevron))
                    Text("Short night · low confidence").font(StrandFont.caption)
                }
                .foregroundStyle(theme.warning)
            }
            if (1..<Baselines.minNightsTrust).contains(ownNights) {
                calibrationConfidence
            }
        } else {
            // Hay número pero sin contexto para una palabra (ex-anillo / estado 6). El numeral ya va en
            // tinta; aquí, la razón honesta — nunca un veredicto pintado de color sin respaldo. (FER-160)
            Text("Not enough context yet for a day's verdict.")
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
        case .verdict, .loading, .waiting:
            // En espera el CTA vive en la tarjeta de fuentes (`emptySourcesCard`), no en el pie del
            // héroe. (FER-364; el CTA «Buscar banda» se retiró con la banda, FER-1003.)
            EmptyView()
        case .calibrating:
            appleHealthShortcut { showDataSources = true }
        }
    }

    /// Cero fuentes: ni strap visto, ni datos de Apple Health, ni permiso de Health concedido. (FER-364)
    private var noSources: Bool {
        repo.appleHealthDays.isEmpty && health.auth != .authorized
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

    /// Chip de procedencia — la base viene de Apple Health, dicho de frente. Tono de dato (azul de Apple
    /// Salud), AA sobre papel.
    private var appleBaseChip: some View {
        HStack(spacing: CenitMetrics.space2) {
            StrandIcon.heart.image.font(StrandFont.glyph(.chevron))
            Text("Baseline · Apple Health").font(StrandFont.subhead)
        }
        .foregroundStyle(theme.dataSpO2)
        .padding(.horizontal, CenitMetrics.space2).padding(.vertical, CenitMetrics.space1)
        .background(theme.dataSpO2.opacity(StrandOpacity.tintFill), in: RoundedRectangle(cornerRadius: CenitMetrics.chipRadius, style: .continuous))
    }

    /// Night-dots de calibración: llenos en el dato (`dataRecovery`), vacíos en `hairline`.
    private func calibrationDots(nights: Int) -> some View {
        let total = Baselines.minNightsSeed
        return HStack(spacing: CenitMetrics.space2) {
            ForEach(0..<total, id: \.self) { i in
                Circle()
                    .fill(i < nights ? theme.dataRecovery : theme.hairline)
                    .frame(width: 10, height: 10)
            }
            Text("\(nights) of \(total) nights")
                .font(StrandFont.captionNumber)
                .foregroundStyle(theme.inkSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(nights) of \(total) nights calibrated"))
    }

    /// Copy de calibración por momento: noche cero, media calibración, y «todas las noches, computando».
    /// Enmarca el conteo como las noches que tu PROPIA base necesita, nunca «tu veredicto».
    private func calibrationDetailCopy(nights: Int) -> LocalizedStringKey {
        let total = Baselines.minNightsSeed
        if nights == 0 { return "Wear your Apple Watch to sleep tonight: the first of \(total) nights your own baseline needs." }
        if nights >= total { return "All \(total) nights are in. Computing your first verdict." }
        return "Your own baseline sharpens each night · you're at \(nights)."
    }

    /// Atajo de adelanto por Apple Health (solo en calibración): un usuario con historial puede sembrar la
    /// base ahora en vez de esperar las 0→seed noches. Renglón full-width con hairline que abre Fuentes de
    /// datos.
    private func appleHealthShortcut(onTap: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            Rectangle().fill(theme.hairline).frame(height: 0.5)
                .padding(.top, CenitMetrics.gap).padding(.bottom, CenitMetrics.gap)
            Button(action: onTap) {
                HStack(spacing: CenitMetrics.space2) {
                    StrandIcon.heart.image
                        .font(StrandFont.glyph(.chevron)).foregroundStyle(theme.dataSpO2)
                    Text("Got history in Apple Health? Connect it and your baseline starts ahead.")
                        .font(StrandFont.caption)
                        .foregroundStyle(theme.inkSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: CenitMetrics.space2)
                    StrandIcon.disclosure.image
                        .font(StrandFont.glyph(.chevron)).foregroundStyle(theme.inkTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(Text("Connect Apple Health"))
            .accessibilityHint(Text("Opens Data Sources to get your baseline ahead"))
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
        VStack(alignment: .leading, spacing: CenitMetrics.space2) {
            HStack(alignment: .firstTextBaseline, spacing: CenitMetrics.space2) {
                HStack(alignment: .firstTextBaseline, spacing: CenitMetrics.space2) {
                    Image(systemName: "sparkles").font(StrandFont.glyph(.chevron))
                    // Compacto (FER-202): la procedencia «base Apple Salud» se pliega aquí, en la misma línea
                    // de la etiqueta, en vez de un tercer renglón aparte — recorta alto para que Hoy quepa.
                    Text("Sharpening your baseline")
                        .font(StrandFont.caption)
                        .fixedSize(horizontal: false, vertical: true)   // wrap, never truncate, at large Dynamic Type
                    if baselineFromApple {
                        Text("· Apple Health baseline")
                            .font(StrandFont.caption)
                            .foregroundStyle(theme.inkTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .foregroundStyle(theme.inkSecondary)
                Spacer(minLength: CenitMetrics.space2)
                Text("\(ownNights) of \(Baselines.minNightsTrust) nights")
                    .font(StrandFont.captionNumber)
                    .foregroundStyle(theme.inkSecondary)
                    .fixedSize()
                    .layoutPriority(1)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(theme.ink.opacity(StrandOpacity.tintFill)).frame(height: 5)
                    Capsule().fill(theme.dataRecovery)
                        .frame(width: max(6, geo.size.width * CGFloat(ownNights) / CGFloat(Baselines.minNightsTrust)),
                               height: 5)
                }
            }
            .frame(height: 5)
        }
        .padding(.top, CenitMetrics.space2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Calibration confidence"))
        .accessibilityValue(Text(baselineFromApple
            ? "Sharpening your baseline, \(ownNights) of \(Baselines.minNightsTrust) nights. Your baseline comes from Apple Health."
            : "Sharpening your baseline, \(ownNights) of \(Baselines.minNightsTrust) nights."))
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
        // Temperatura de piel — la desviación nocturna (°C) vs tu base, tal como la reporta la banda. FER-763:
        // reemplaza a SpO₂ en la retícula (SpO₂ sólo venía de Apple Salud; la temperatura de piel es señal
        // real de la banda en reposo, así que gana el tile). Sigue accesible el Detalle desde Cuerpo.
        let skinTempR = latestFromDisplay { $0.skinTempDevC }
        // Esfuerzo del día: el score asentado (`displayedDayStrain`) — el mismo número que muestra el
        // héroe del Detalle de Esfuerzo (la curva intradía «hora a hora» se retiró en FER-1025). Los
        // días pasados no lo tocan.
        // FER-883: Apple workout-HR estimate → label «Day load» + source .apple; band days unchanged.
        let strainT = model.displayedDayStrain
        let strainEstimated = repo.isStrainEstimated(repo.today?.day ?? Repository.localDayKey(Date()))
        // Pasos: Apple Salud primero; acota a la ventana de 14 días para no mostrar pasos rancios bajo
        // un tile de "hoy". Sin conteo real, cae a la ESTIMACIÓN on-device de la WHOOP 4.0 (steps_est,
        // FER-663) — el real siempre gana; la estimación solo llena el hueco, rotulada «est.».
        let stepsCutoff = Repository.localDayKey(Calendar.current.date(byAdding: .day, value: -13, to: Date()) ?? Date())
        let stepsFresh  = appleDays.last(where: { $0.day >= stepsCutoff })?.steps
        let stepsEstFresh = stepsFresh == nil
            ? stepsEst.last(where: { $0.day >= stepsCutoff }).map { Int($0.value.rounded()) }
            : nil
        let stepsT      = (stepsFresh ?? stepsEstFresh).map(Double.init)
        let stressT     = stress?.score
        let respR       = latestFromDisplay { $0.respRateBpm }
        // Base para la media de 7 días de cada tile (FER-258): días anteriores a hoy, ordenados,
        // computada una vez por render (no por tile).
        let base = baselineDays()
        // Verde AA-en-texto-chico para el delta favorable: `positiveText` (= el #00774B del handoff).
        // Se resuelve UNA vez por render (su bisección OKLab no debe correr por-tile).
        let positiveDelta = theme.positiveText

        VStack(alignment: .leading, spacing: CenitMetrics.space2) {
            // La retícula 2×4 del handoff: los MISMOS 8 vitales de hoy, cada tile con su punto de
            // origen, valor 21/700 en color y la línea delta explícita («+24 min vs promedio 7 d»).
            // Recuperación NO es tile: ya es el numeral del héroe.
            // FER-743: tile de 3 renglones sin sparkband (la tendencia 14 d vive en el Detalle) para que
            // la retícula 2×4 quepa en SEÑALES sin scroll.
            LazyVGrid(columns: tileGrid, alignment: .leading, spacing: CenitMetrics.space2) {
                // Sueño — day-scoped (solo hoy); más es mejor dentro de lo razonable.
                metricTile(TodayMetricTile(
                    label: "Sleep",
                    icon: MetricGlyph.sleep.sfSymbol,
                    value: sleepR.map { sleepClockText($0.value) } ?? "—",
                    valueColor: theme.dataSleep,
                    source: sleepR?.fromApple == true ? .apple : .band,
                    context: tileContext(today: sleepR?.value, history: history(base) { $0.totalSleepMin },
                                         betterHigher: true, deadband: 5, positive: positiveDelta) { sleepDeltaText($0) },
                    placeholder: "Tonight"
                )) { metricDetail = .sleep(sleepR.map { Int($0.value.rounded()) }) }
                // HRV — más alta es mejor.
                metricTile(TodayMetricTile(
                    label: "HRV",
                    icon: MetricGlyph.hrv.sfSymbol,
                    value: hrvR.map { "\(Int($0.value.rounded()))" } ?? "—", unit: String(localized: "ms"),
                    valueColor: theme.dataHrv,
                    source: hrvR?.fromApple == true ? .apple : .band,
                    context: tileContext(today: hrvR?.value, history: history(base) { $0.avgHrv },
                                         betterHigher: true, deadband: 1, positive: positiveDelta) { "\(Int($0.rounded())) ms" }
                )) { metricDetail = .hrv(hrvR?.value) }
                // FC en reposo — más alta es PEOR.
                metricTile(TodayMetricTile(
                    label: "Resting HR",
                    icon: MetricGlyph.restingHR.sfSymbol,
                    value: rhrR.map { "\(Int($0.value.rounded()))" } ?? "—", unit: String(localized: "bpm"),
                    valueColor: theme.dataHeart,
                    source: rhrR?.fromApple == true ? .apple : .band,
                    context: tileContext(today: rhrR?.value, history: history(base) { $0.restingHr.map(Double.init) },
                                         betterHigher: false, deadband: 1, positive: positiveDelta) { "\(Int($0.rounded())) \(String(localized: "bpm"))" }
                )) { metricDetail = .restingHR(rhrR.map { Int($0.value.rounded()) }) }
                // Esfuerzo del día — carga del día, sin valencia (Δ en tinta neutra).
                // FER-883: estimated Apple workout-HR → "Day load" + .apple; band → "Day Strain" + .calculated.
                metricTile(TodayMetricTile(
                    label: strainEstimated ? "Day load" : "Day Strain",
                    icon: MetricGlyph.strain.sfSymbol,
                    value: strainT.map { String(format: "%.1f", $0) } ?? "—",
                    valueColor: theme.dataStrain,
                    source: strainEstimated ? .apple : .calculated,
                    context: tileContext(today: strainT, history: history(base) { $0.strain },
                                         betterHigher: nil, deadband: 0.3, positive: positiveDelta) { String(format: "%.1f", $0) }
                )) { metricDetail = .strain(strainT) }
                // Pasos — sin meta (no existe en la app); más es mejor. Con conteo real (Apple) el tile
                // es el de siempre; en un día estimado (WHOOP 4.0, FER-663) el valor lleva «est.», el
                // chip pasa a «calculado» y el contexto compara estimación-contra-estimación.
                let stepsEstimated = stepsEstFresh != nil
                let stepsTileHistory = stepsEstimated ? stepsEstHistory : history(base) { $0.steps.map(Double.init) }
                metricTile(TodayMetricTile(
                    label: "Steps",
                    icon: MetricGlyph.steps.sfSymbol,
                    value: stepsT.map { intString($0) } ?? "—",
                    unit: stepsEstimated ? String(localized: "est.") : nil,
                    valueColor: theme.dataSteps,
                    source: stepsEstimated ? .calculated : .apple,
                    context: tileContext(today: stepsT, history: stepsTileHistory,
                                         betterHigher: true, deadband: 100, positive: positiveDelta) { intString($0) }
                )) { metricDetail = .steps(stepsFresh ?? stepsEstFresh) }
                // Temperatura de piel — desviación (°C) vs tu base; sin valencia simple (lo sano es estar
                // cerca de tu base, no «más = mejor»), así que Δ en tinta neutra. Valor con signo (+0.3).
                metricTile(TodayMetricTile(
                    label: "Skin temp",
                    icon: MetricGlyph.skinTemp.sfSymbol,
                    value: skinTempR.map { String(format: "%+.1f", $0.value) } ?? "—", unit: "°C",
                    valueColor: theme.dataStrain,
                    source: skinTempR?.fromApple == true ? .apple : .band,
                    context: tileContext(today: skinTempR?.value, history: history(base) { $0.skinTempDevC },
                                         betterHigher: nil, deadband: 0.1, positive: positiveDelta) { String(format: "%.1f °C", $0) }
                )) { metricDetail = .skinTemp(skinTempR?.value) }
                // Respiración — «en rango» es lo normal; sin valencia simple (Δ en tinta neutra).
                metricTile(TodayMetricTile(
                    label: "Respiration",
                    icon: MetricGlyph.respiration.sfSymbol,
                    value: respR.map { String(format: "%.1f", $0.value) } ?? "—", unit: String(localized: "rpm"),
                    valueColor: theme.dataSpO2,
                    source: respR?.fromApple == true ? .apple : .band,
                    context: tileContext(today: respR?.value, history: history(base) { $0.respRateBpm },
                                         betterHigher: nil, deadband: 0.5, positive: positiveDelta) { String(format: "%.1f", $0) }
                )) { metricDetail = .respiratory(respR?.value) }
                // Estrés — más alto es PEOR; valor bandeado por nivel 0–3 (verde/ámbar/rojo).
                metricTile(TodayMetricTile(
                    label: "Stress",
                    icon: MetricGlyph.stress.sfSymbol,
                    value: stressT.map { String(format: "%.1f", $0) } ?? "—",
                    unit: stressT == nil ? nil : "/ 3",
                    valueColor: stressT.map(stressDataColor) ?? theme.inkTertiary,
                    source: .calculated,
                    context: tileContext(today: stressT, history: stressHistory,
                                         betterHigher: false, deadband: 0.1, positive: positiveDelta) { String(format: "%.1f", $0) }
                )) { metricDetail = .stress(stressT) }
            }
            originLegend   // FER-878: la leyenda de puntos de origen vuelve bajo la retícula (FER-743 la retiró).
        }
    }

    /// FER-878: la leyenda de puntos de origen, anclada bajo la retícula 2×4 tras un hairline. Decodifica
    /// el punto de cada tile: banda (verde) · Apple Salud (azul) · calculado en tu teléfono (gris). El
    /// texto en tinta terciaria 11 pt, igual que el sello de origen del header.
    private var originLegend: some View {
        HStack(spacing: CenitMetrics.gap + 2) {
            legendItem(origin: .band, label: "band")
            legendItem(origin: .apple, label: "Apple Health source")
            legendItem(origin: .computed, label: "computed on your phone")
        }
        .padding(.top, CenitMetrics.space1)   // FER-878 follow-up: 8→4, cabe sin scroll
        .overlay(alignment: .top) { Rectangle().fill(theme.hairline).frame(height: 0.5) }
        .accessibilityHidden(true)
    }

    /// El punto de cada origen sale de `DataOrigin.color(theme)` — la MISMA fuente que el sello del
    /// header (`OriginStamp`), para que el color del punto y su significado nunca se separen.
    private func legendItem(origin: DataOrigin, label: LocalizedStringKey) -> some View {
        HStack(spacing: 5) {
            Circle().fill(origin.color(theme)).frame(width: 6, height: 6)
            Text(label).font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
        }
    }


    /// La rejilla de «Métricas de hoy»: dos columnas iguales → 8 tiles en 4 renglones de 2.
    private let tileGrid = [GridItem(.flexible(), spacing: CenitMetrics.gap),
                            GridItem(.flexible(), spacing: CenitMetrics.gap)]

    /// Envuelve un tile en su `Button` tappable (todo el tile es objetivo) + feedback de pulsado, y abre
    /// el `MetricInfoSheet` de la métrica. El detalle trae la tendencia 14d (interino hasta «Cuerpo»).
    private func metricTile(_ tile: TodayMetricTile, open: @escaping () -> Void) -> some View {
        Button(action: open) { tile }
            .buttonStyle(TileButtonStyle(liftBorder: theme.hairlineStrong))
            .accessibilityHint(Text("Opens the detail"))
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

    /// El contexto de un tile: compara hoy contra la media de 7 días de `history` y arma la línea
    /// delta EXPLÍCITA del handoff («+24 min vs promedio 7 d»). nil cuando no hay valor de hoy → el
    /// tile pone «—» sin pie. Con <4 días válidos → `.building`. Dentro del `deadband` → «En tu
    /// promedio 7 d». Favorable → `positiveText` (el verde profundo del handoff); desfavorable →
    /// `negativeText`; sin valencia (carga / respiración) → tinta neutra.
    private func tileContext(today: Double?, history: [Double], betterHigher: Bool?, deadband: Double,
                             positive: Color, _ format: (Double) -> String) -> TileContext? {
        guard let t = today else { return nil }
        let valid = history.filter { $0.isFinite }
        guard valid.count >= 4 else { return .building }
        let mean = valid.reduce(0, +) / Double(valid.count)
        let change = t - mean
        if abs(change) <= deadband {
            return .ready(text: String(localized: "At your baseline"), color: theme.inkSecondary)
        }
        let up = change > 0
        let color: Color = betterHigher.map { (up == $0) ? positive : theme.negativeText } ?? theme.inkSecondary
        let sign = up ? "+" : "\u{2212}"
        return .ready(text: "\(sign)\(format(abs(change))) \(String(localized: "vs your baseline"))",
                      color: color)
    }


    /// El color del valor de Estrés por banda 0–3, en roles del tema (regla: color saturado solo en el
    /// dato). Bajo → `verdict`, medio → `warning`, alto → `critical`. Reusa `StressBand` (StressView).
    private func stressDataColor(_ score: Double) -> Color {
        StressBand(score: score).dataColor(theme)
    }

    /// El contexto de un tile vs su media de 7 días: la línea delta ya formateada. `building` = aún
    /// no hay ≥4 días de base para una media honesta. La ausencia (sin valor de hoy) se modela con el
    /// Optional: nil → sin delta.
    private enum TileContext {
        case building
        case ready(text: String, color: Color)
    }

    /// De dónde vino un dato ESE día (FER-552): banda / Apple / calculado → el punto de origen del tile.
    private enum MetricSource { case band, apple, calculated }

    /// El punto de origen (6 px) del handoff: banda (verde) · Apple (azul) · calculado (gris `inkMuted`).
    /// Su significado lo da la leyenda de la sección; VoiceOver lo lee por su etiqueta.
    private struct SourceChip: View {
        let source: MetricSource
        @Environment(\.instrumentoTheme) private var theme
        private var dotColor: Color {
            switch source {
            case .band:       return theme.originBand
            case .apple:      return theme.originApple
            case .calculated: return theme.originComputed
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
            Circle().fill(dotColor).frame(width: 6, height: 6)
                .accessibilityElement()
                .accessibilityLabel(sourceName)
        }
    }

    /// Un tile de la retícula 2×4 (handoff «Hoy» 2026-07 · compactado FER-743): 3 renglones — icono +
    /// nombre + punto de origen arriba; valor 21/700 tabular en el color del dato + unidad; y la línea
    /// delta explícita («+24 min vs promedio 7 d»). La tendencia 14 d migró al Detalle (sin sparkband en
    /// el resumen). Tematizado con tokens sobre `surface` + hairline; sin lectura el tile se apaga a `inkDim`.
    private struct TodayMetricTile: View {
        let label: LocalizedStringKey
        var icon: String? = nil
        let value: String
        var unit: String? = nil
        let valueColor: Color
        var source: MetricSource = .band
        var context: TileContext? = nil
        /// Pie cuando no hay valor/contexto (p. ej. «Esta noche» en el tile day-scoped de Sueño). FER-341.
        var placeholder: LocalizedStringKey? = nil
        @Environment(\.instrumentoTheme) private var theme

        private var isEmpty: Bool { value == "—" }

        var body: some View {
            VStack(alignment: .leading, spacing: CenitMetrics.space1 + 1) {
                HStack(spacing: CenitMetrics.space1) {
                    if let icon {
                        Image(systemName: icon)
                            .font(StrandFont.glyph(.chevron, weight: .medium))
                            .foregroundStyle(isEmpty ? theme.inkDim : valueColor)
                            .accessibilityHidden(true)
                    }
                    Text(label)
                        .font(InstrumentoType.grotesk(9, weight: .semibold))
                        .tracking(1.4)
                        .textCase(.uppercase)
                        .foregroundStyle(theme.inkTertiary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: CenitMetrics.space1)
                    if !isEmpty { SourceChip(source: source) }
                }
                HStack(alignment: .firstTextBaseline, spacing: CenitMetrics.space1) {
                    Text(value)
                        .font(InstrumentoType.groteskTileValue)
                        .foregroundStyle(isEmpty ? theme.inkDim : valueColor)
                        .lineLimit(1).minimumScaleFactor(18.0 / 21.0)
                    if let unit {
                        Text(unit).font(StrandFont.caption)
                            .foregroundStyle(isEmpty ? theme.inkDim : theme.inkTertiary)
                    }
                }
                footer
            }
            .padding(.horizontal, CenitMetrics.gap).padding(.vertical, CenitMetrics.space2)
            // FER-743: piso de alto 72 (antes 88) y sin sparkband — el tile pasa a 3 renglones (etiqueta /
            // valor / delta explícito) para que SEÑALES quepa sin scroll; la tendencia 14 d vive en el
            // Detalle. Sigue siendo PISO, no tope: el tile crece con Dynamic Type grande.
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
            .background {
                RoundedRectangle(cornerRadius: CenitMetrics.tileRadius, style: .continuous)
                    .fill(theme.surface)
                    .strandElevation(.hairline, ink: theme.ink)
            }
            .overlay(RoundedRectangle(cornerRadius: CenitMetrics.tileRadius, style: .continuous)
                .strokeBorder(theme.hairline, lineWidth: 1))
            .accessibilityElement(children: .combine)
        }

        /// El pie: la línea delta explícita («+24 min vs promedio 7 d» / «En tu promedio 7 d»), en 9.5 pt
        /// tabular; «armando» mientras no hay base; el placeholder sin valor.
        @ViewBuilder private var footer: some View {
            switch context {
            case let .ready(text, color):
                Text(verbatim: text)
                    .font(StrandFont.number(10, weight: .medium)).monospacedDigit()
                    .foregroundStyle(color)
                    .lineLimit(1).minimumScaleFactor(0.75)
            case .building:
                Text("No baseline of your own yet")
                    .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                    .lineLimit(1).minimumScaleFactor(0.75)
            case .none:
                if let placeholder {
                    Text(placeholder)
                        .font(StrandFont.caption).foregroundStyle(theme.inkTertiary)
                        .lineLimit(1).minimumScaleFactor(0.75)
                }
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
                .overlay(RoundedRectangle(cornerRadius: CenitMetrics.tileRadius, style: .continuous)
                    .strokeBorder(configuration.isPressed ? liftBorder : Color.clear, lineWidth: 1))
                .scaleEffect(configuration.isPressed ? 1.03 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.72), value: configuration.isPressed)
        }
    }

    /// On-device readiness for the verdict hero (`ReadinessEngine`).
    /// Memoizado en `memoReadiness` (FER-172): cae a un cálculo en línea solo si el memo aún es nil
    /// (el primer body antes de que `.task` lo siembre), nunca en el camino caliente de cada render.
    private var readiness: ReadinessEngine.Readiness {
        // FER-623: misma base de banda que `recomputeDerived`, para que el fallback en frío coincida con el memo.
        memoReadiness ?? ReadinessEngine.evaluate(days: bandDays, today: Repository.localDayKey(Date()))
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
        await loadTrainingPlan()
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
#endif

