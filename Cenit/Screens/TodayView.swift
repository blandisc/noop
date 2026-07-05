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

// MARK: - Hoy «Instrumento» evolucionado (FER-709, handoff 2026-07)
//
// The home screen in the EVOLVED «Instrumento diurno» voice (Space Grotesk numerals, warm paper,
// one dominant number, arithmetic transparency — see DESIGN.md §8.7).
//
// Composition (top → bottom), all inside `iosBody`:
//   (a) HEADER — date · strap battery · live BPM (tap → Latidos) · the 34pt `DialSeal` (the 24h
//                signature AND the pull-to-refresh spinner), plus the freshness line (`headerBlock`).
//   (b) HERO   — the 124pt recovery numeral in its verdict color + the right column (overline,
//                verdict word with dotted underline + ⓘ → Recuperación, delta vs your average)
//                (`heroBlock`). `heroState` still picks the numeral per mode: `··` calibrating,
//                `—` no data, `~N` estimated. The big `DiurnalDial` was retired from this screen
//                (owner's call; the component stays in StrandDesign until F3).
//   (c) TABS   — SEÑALES / BRIEF with the elastic underline (`sectionTabs`) over a 2-page pager:
//                · Page 0 (`senalesPage`) — «POR QUÉ N» (the five rules, `FiveRulesView` fed by
//                  `RecoveryRules`) + the 2×4 tile grid with sparkbands (`iosMetricsSection`).
//                · Page 1 (`verdictPage`) — the Daily Brief (headline, connection, actions, CTA).
//
// Pull-to-refresh: the seal winds up with the pull and spins while syncing; on completion the
// numeral counts 0→N and the rule marks light in sequence — ONLY after a refresh, never on open.

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

    // El experimento N-of-1 en curso, espejo de Patrones (FER-615): la 2ª fuente del renglón «La conexión de
    // hoy». Cargado en `loadAll` desde `Repository` (activeExperiment + experimentProgress); `nil` sin experimento.
    @State private var activeExperiment: DailyBriefEngine.ActiveExperiment? = nil

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
    /// La viñeta de HRV estimada (día sin banda) memoizada (FER-623): su cálculo corre un `ReadinessEngine.
    /// evaluate` sobre la historia enmascarada a Apple, así que —como el veredicto (FER-172)— se siembra UNA
    /// vez por `refreshSeq` en `recomputeDerived`, nunca por frame. `nil` si hoy no es estimado o calibra.
    @State private var memoAppleHrvEstimated: DailyBrief.HrvEstimatedBullet?
    /// Las cinco reglas de hoy (FER-709), memoizadas: `RecoveryRules` sobre el `RecoveryImpact` del día
    /// (banda-only) + el score mostrado, de modo que la suma encendida == el numeral. Vacías sin
    /// descomposición honesta (cold-start o día Apple-only estimado).
    @State private var memoRules: [RecoveryRules.Rule]?

    // MARK: - Celebración del pull-to-refresh (FER-709)
    //
    // SOLO tras un pull-to-refresh (nunca al abrir): el numeral cuenta 0→N (750 ms, dígitos tabulares
    // vía `contentTransition(.numericText())`) y las marcas de las reglas se encienden en secuencia
    // (~1.2 s, `FiveRulesView.reveal` animado con un `TimelineView`). Nada de esto corre bajo Reduce
    // Motion ni sin veredicto.

    /// Ancla temporal de la celebración en curso; nil = reposo (las reglas se dibujan asentadas).
    @State private var celebrationStart: Date? = nil
    /// El valor que muestra el numeral durante el conteo 0→N; nil = el score real.
    @State private var countUpScore: Int? = nil

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
        // FER-623: el veredicto mide la HRV solo contra la base de BANDA (RMSSD), vía `bandDays`. Solo-banda → no-op.
        let band = bandDays
        memoReadiness = ReadinessEngine.evaluate(days: band, today: Repository.localDayKey(Date()))
        memoCounts = computeHrvCounts()
        // FER-475: el veredicto de ayer, para la línea de continuidad de la página 1 «en espera». Una vez
        // por refresh (no por frame), junto al de hoy.
        let yKey = Repository.localDayKey(Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date())
        memoYesterdayLevel = ReadinessEngine.evaluate(days: band, today: yKey).level
        // FER-623: la viñeta de HRV estimada (día sin banda) también se siembra aquí, no por frame.
        memoAppleHrvEstimated = computeAppleHrvEstimated()
        // FER-709: las cinco reglas del día — el impacto por señal (banda-only, FER-519) mapeado a
        // marcas cuya suma encendida == el numeral. `RecoveryImpact` devuelve nil en cold-start o en un
        // día Apple-only (estimado): ahí el bloque se oculta en vez de inventar una descomposición.
        let todayKey = Repository.localDayKey(Date())
        if let score = repo.today?.recovery.map({ Int($0.rounded()) }),
           let impact = RecoveryImpact.compute(days: repo.days, todayKey: todayKey,
                                               appleDays: repo.appleHealthDays) {
            memoRules = RecoveryRules.rules(impact: impact, score: score)
        } else {
            memoRules = []
        }
        #if DEBUG
        // FER-172: prueba de que el veredicto se recalcula UNA vez por refresh. En scroll/animación/
        // ticks de HR esta línea NO debe reaparecer; solo sale una vez por `seq`. Compila fuera en release.
        print("[FER-172] readiness recomputed · seq=\(repo.refreshSeq) · days=\(repo.days.count)")
        #endif
    }

    /// FER-623: `repo.days` con la HRV de Apple (SDNN) enmascarada, para medir el veredicto solo contra la
    /// base de BANDA (RMSSD) — igual que Recuperación (FER-519): la σ de «HRV vs tu base» no se contamina
    /// mezclando dos métricas sin conversión. Lee `days` + `appleHealthDays` en una sola expresión síncrona
    /// (mismo dashboard publicado, sin await en medio) para no reintroducir la carrera FER-177. Una sola
    /// fuente de verdad: `recomputeDerived` y el fallback en frío de `readiness` la comparten (deben coincidir).
    private var bandDays: [DailyMetric] {
        SourceLens.maskHrv(repo.days, keep: .band, appleDays: repo.appleHealthDays)
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
                // Keep the Day Strain tile rising in lockstep with fresh HR — same live cadence as the
                // heartbeat trace, so the tile == the Detalle curve's endpoint at all times (FER-650).
                await model.refreshLiveDayStrain()
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
                    todayKey: Repository.localDayKey(Date()),
                    // FER-670: today's source-agreement point (steps) — nil for every non-fused metric.
                    fusion: repo.fusionPoint(day: Repository.localDayKey(Date()), metric: spec.descriptor.key)
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
                    todayKey: Repository.localDayKey(Date()),
                    fusion: repo.fusion))
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
                // Bloque FIJO del instrumento (handoff «Hoy» 2026-07): header + héroe + pestañas. Sigue
                // dentro del scroll vertical, así que el pull-to-refresh propio (FER-222) NO cambia.
                // Todo lo demás desliza con el pager.
                VStack(alignment: .leading, spacing: NoopMetrics.sectionGapCompact) {
                    headerBlock
                    HealthAlertBanner()
                    heroBlock
                }
                sectionTabs
                    .padding(.top, NoopMetrics.sectionGapCompact)
                // Pager horizontal de 2 páginas: ① SEÑALES (por qué + tiles) · ② BRIEF. Ancho de página =
                // ancho de contenido (proxy − screenPadding lateral) para que el snap pagine de a una.
                // Ejes ortogonales al scroll vertical → el swipe horizontal y el pull-to-refresh no se pelean.
                todayPager(width: max(0, proxy.size.width - NoopMetrics.screenPadding * 2))
                    .padding(.top, NoopMetrics.sectionGapCompact)
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
        // FER-709: la celebración de actualización — el conteo 0→N del numeral + las marcas en
        // secuencia — corre SOLO aquí (tras un pull), nunca al abrir la pantalla.
        celebrateSyncCompletion()
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

    /// Arranca la celebración de actualización (FER-709): resetea el numeral a 0 y lo deja rodar a su
    /// valor con `.numericText` (750 ms), y ancla `celebrationStart` para que las marcas de las reglas
    /// se enciendan en secuencia. Solo con veredicto y sin Reduce Motion; se auto-limpia al terminar.
    @MainActor private func celebrateSyncCompletion() {
        guard !reduceMotion, heroState == .verdict, let score = recoveryScore else { return }
        celebrationStart = Date()
        countUpScore = 0
        withAnimation(.easeOut(duration: 0.75)) { countUpScore = score }
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            celebrationStart = nil
            countUpScore = nil
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

    /// The recovery summary sheet's model — the ONE way every entry point (Daily Brief bullet, the
    /// hero numeral, the glance pill) opens it. Includes «Qué la movió hoy» (FER-628), computed
    /// against the band-only slice: `RecoveryImpact` drops `repo.appleHealthDays` whole-row before
    /// folding, the same `strapOnlyHistory` filter the persisted score's baselines use (FER-519), so
    /// the block and the score can never disagree about the same night.
    private var recoveryInfo: MetricInfo {
        let todayKey = Repository.localDayKey(Date())
        let todayImpact = RecoveryImpact.compute(days: repo.days, todayKey: todayKey,
                                                 appleDays: repo.appleHealthDays)
        return .recovery(score: recoveryScore,
                  calibrationNights: recoveryCalibration,
                  nightsNeeded: Baselines.minNightsSeed,
                  impact: todayImpact,
                  change: recoveryChange(todayKey: todayKey, todayImpact: todayImpact))
    }

    /// FER-642 · «Vs ayer» for the recovery summary: the day-over-day change vs the previous CALENDAR day
    /// (D2 — «ayer» must mean literally yesterday, not the last band night). Resolved from the same
    /// band-only slice `RecoveryImpact` uses, keyed on the app's own displayed scores (`.recovery`) and
    /// ranked by the change in each signal's contribution. nil (block hidden) when there's no band row /
    /// score for yesterday.
    private func recoveryChange(todayKey: String, todayImpact: RecoveryImpact.Result?) -> RecoveryChange.Result? {
        let yesterdayKey = Repository.localDayKey(
            Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date())
        let byDay = Dictionary(repo.days.map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
        guard let todayRow = byDay[todayKey], !repo.appleHealthDays.contains(todayKey),
              let yestRow = byDay[yesterdayKey], !repo.appleHealthDays.contains(yesterdayKey)
        else { return nil }
        return RecoveryChange.compute(
            today: todayRow, yesterday: yestRow,
            todayScore: todayRow.recovery.map { Int($0.rounded()) },
            yesterdayScore: yestRow.recovery.map { Int($0.rounded()) },
            todayImpact: todayImpact,
            yesterdayImpact: RecoveryImpact.compute(days: repo.days, todayKey: yesterdayKey,
                                                    appleDays: repo.appleHealthDays))
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
        VStack(alignment: .leading, spacing: NoopMetrics.space1) {
            HStack(alignment: .center, spacing: NoopMetrics.space2) {
                Text(shortDate)
                    .font(InstrumentoType.grotesk(11, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(theme.inkSecondary)
                if let pct = live.batteryPct {
                    Rectangle().fill(theme.hairlineStrong)
                        .frame(width: 1, height: 11)
                        .accessibilityHidden(true)
                    HStack(spacing: 4) {
                        Image(systemName: batteryIcon(pct: pct, charging: live.charging == true))
                            .font(StrandFont.overline)
                            .foregroundStyle(theme.batteryColor(forLevel: pct))
                        Text("\(Int(pct.rounded()))%")
                            .font(InstrumentoType.grotesk(11, weight: .medium).monospacedDigit())
                            .foregroundStyle(theme.inkTertiary)
                    }
                    .accessibilityLabel(live.charging == true
                        ? Text("Batería del strap: \(Int(pct.rounded()))%, cargando")
                        : Text("Batería del strap: \(Int(pct.rounded()))%"))
                }
                Spacer(minLength: NoopMetrics.space2)
                if liveBpm != nil { bpmButton }
                headerSeal
            }
            syncStatusLine
        }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: Text("Sincronizar")) { triggerPullSync() }
    }

    /// El BPM del header: punto latiente (solo late con señal EN VIVO) + «62 BPM». Tocarlo abre la
    /// hoja Latidos (el monitor latido a latido), como el resto de los datos de Hoy.
    private var bpmButton: some View {
        Button { showLiveMonitor = true } label: {
            HStack(spacing: NoopMetrics.space1 + 1) {
                BreathingDot(color: isLiveHR ? theme.dataHeart : theme.inkTertiary,
                             radius: 3, breathes: isLiveHR)
                Text(verbatim: "\(liveBpm ?? 0) BPM")
                    .font(InstrumentoType.grotesk(11, weight: .semibold).monospacedDigit())
                    .tracking(1)
                    .foregroundStyle(theme.ink)
            }
            .frame(minHeight: 34)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(isLiveHR ? "Frecuencia cardiaca en vivo" : "Frecuencia cardiaca"))
        .accessibilityValue(Text(liveBpm.map { "\($0) bpm" } ?? ""))
        .accessibilityHint(Text("Abre el monitor latido a latido"))
    }

    /// El sello del dial (34 pt) — la firma del instrumento Y el spinner: al jalar se le «da cuerda»
    /// (gira con `pullProgress`), sincronizando gira en loop, en reposo queda quieto con el punto
    /// «ahora» en la hora real.
    @ViewBuilder private var headerSeal: some View {
        let seal = DialSeal(hour: clockHourNow, solar: solarWindow, sleep: sleepWindow)
        if isSyncing && !reduceMotion {
            TimelineView(.animation) { context in
                let angle = (context.date.timeIntervalSinceReferenceDate * 257)
                    .truncatingRemainder(dividingBy: 360)
                seal.rotationEffect(.degrees(angle))
            }
        } else {
            seal.rotationEffect(.degrees(pullProgress * 270))
        }
    }

    /// La hora reloj actual (0…24) para el punto «ahora» del sello.
    private var clockHourNow: Double {
        let c = Calendar.current.dateComponents([.hour, .minute], from: Date())
        return Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60.0
    }

    /// La línea de estado bajo el header: «Sincronizando con tu banda…» durante el sync (con el conteo
    /// de paquetes si ya fluyen), o la frescura «última lectura hace N min» en reposo. Nada sin banda vista.
    @ViewBuilder private var syncStatusLine: some View {
        if isSyncing {
            Text(live.syncChunksThisSession > 0
                 ? "Sincronizando con tu banda… \(live.syncChunksThisSession) paquetes"
                 : "Sincronizando con tu banda…")
                .font(StrandFont.caption).monospacedDigit()
                .foregroundStyle(theme.verdict)
        } else if let at = live.lastSyncedAt {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                let secondsAgo = Swift.max(context.date.timeIntervalSince1970 - at, 1)
                Text("última lectura \(Self.compactAgo(secondsAgo))")
                    .font(StrandFont.caption).monospacedDigit()
                    .foregroundStyle(theme.inkTertiary)
            }
        }
    }

    /// Tiempo relativo en unidades de UNA letra: «hace 30 s / 5 m / 2 h / 3 d».
    private static func compactAgo(_ secondsAgo: Double) -> String {
        let s = Int(secondsAgo.rounded())
        let core: String
        if s < 60 { core = "\(s) s" }
        else if s < 3600 { core = "\(s / 60) m" }
        else if s < 86_400 { core = "\(s / 3600) h" }
        else { core = "\(s / 86_400) d" }
        return String(localized: "\(core) ago")
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

    /// El héroe del handoff «Hoy» 2026-07 (FER-709): el numeral de 124 pt en el color del veredicto +
    /// la columna derecha (overline, palabra-veredicto con subrayado punteado + ⓘ que abre la hoja
    /// Recuperación, y el delta «+3 vs tu promedio»). El dial de 240 pt y el numeral concéntrico SE
    /// RETIRAN (decisión del dueño; `DiurnalDial` grande sigue en el paquete hasta F3) — el 24 h vive
    /// ahora en el sello del header. El numeral nunca miente: `··` calibrando, `—` sin datos, `~N`
    /// estimado.
    @ViewBuilder private var heroBlock: some View {
        let state = heroState
        VStack(alignment: .leading, spacing: NoopMetrics.space2) {
            HStack(alignment: .center, spacing: NoopMetrics.gap) {
                heroNumeralText(state)
                VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                    Text(heroOverline(state))
                        .groteskOverline()
                        .foregroundStyle(theme.inkTertiary)
                        .lineSpacing(2)
                    heroVerdictColumn(state)
                }
                Spacer(minLength: 0)
            }
            // FER-545: sello «estimado · confianza» cuando el veredicto de hoy es un estimado de Apple
            // (noche sin banda) — el veredicto estimado nunca se ve idéntico al de banda.
            if state == .verdict, repo.isRecoveryEstimated(Repository.localDayKey(Date())) {
                estimatedTodayMarker
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// El numeral dominante (124/700 tabular, tracking −6). Veredicto → el score en su color de nivel
    /// (con `~` chico si es estimado); calibrando → «··»; descargando / sin lectura → «—». Tocarlo con
    /// veredicto abre la hoja de Recuperación. El conteo 0→N del pull-to-refresh rueda con
    /// `contentTransition(.numericText())` — SOLO al actualizar, nunca al abrir.
    @ViewBuilder private func heroNumeralText(_ s: HeroState) -> some View {
        switch s {
        case .verdict:
            let score = countUpScore ?? recoveryScore ?? 0
            let lvl = readiness.level
            let hasWord = lvl != .insufficient
            let color = isSyncing ? theme.inkTertiary
                : (hasWord ? verdictDataColor(lvl) : theme.ink)
            let estimated = repo.isRecoveryEstimated(Repository.localDayKey(Date()))
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                if estimated {
                    Text(verbatim: "~").groteskSheetNumeral()
                        .foregroundStyle(color.opacity(0.55))
                }
                Text("\(score)").groteskHero()
                    .foregroundStyle(color)
                    .contentTransition(.numericText(value: Double(score)))
            }
            .lineLimit(1).minimumScaleFactor(0.7)
            .contentShape(Rectangle())
            .onTapGesture { metricDetail = recoveryInfo }
            .accessibilityLabel(Text("Recuperación de hoy: \(score)"))
            .accessibilityAddTraits(.isButton)
        case .calibrating:
            Text(verbatim: "··").groteskHero().foregroundStyle(theme.inkTertiary)
        case .importedBaseline, .waiting, .downloading:
            Text(verbatim: "—").groteskHero().foregroundStyle(theme.inkTertiary)
        }
    }

    /// La columna junto al numeral: con veredicto, la palabra del nivel (20/700, subrayado punteado +
    /// ⓘ → hoja Recuperación) y el delta vs tu promedio; en los demás estados, la palabra honesta del
    /// momento con su renglón de contexto.
    @ViewBuilder private func heroVerdictColumn(_ s: HeroState) -> some View {
        switch s {
        case .verdict:
            let lvl = readiness.level
            if lvl != .insufficient {
                Button { metricDetail = recoveryInfo } label: {
                    HStack(alignment: .firstTextBaseline, spacing: NoopMetrics.space1) {
                        Text(stateLabel(lvl))
                            .font(InstrumentoType.groteskVerdict)
                            .foregroundStyle(isSyncing ? theme.inkTertiary : verdictDataColor(lvl))
                            .overlay(alignment: .bottom) {
                                Line()
                                    .stroke(verdictDataColor(lvl).opacity(0.5),
                                            style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                                    .frame(height: 1)
                                    .offset(y: 2)
                            }
                        Image(systemName: "info.circle").font(.system(size: 13))
                            .foregroundStyle(theme.inkTertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text("Abre el detalle de tu recuperación"))
            } else {
                Text("Sin contexto para un veredicto")
                    .font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let delta = recoveryVsAverage {
                Text(verbatim: delta >= 0 ? "+\(delta) vs tu promedio" : "−\(abs(delta)) vs tu promedio")
                    .font(StrandFont.caption).monospacedDigit()
                    .foregroundStyle(delta >= 0 ? theme.positiveText : theme.inkSecondary)
            }
        case .calibrating(let nights):
            Text("Calibrando")
                .font(InstrumentoType.groteskVerdict).foregroundStyle(theme.ink)
            Text("\(nights) de \(Baselines.minNightsSeed) noches")
                .font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
        case .downloading:
            Text("Descargando")
                .font(InstrumentoType.groteskVerdict).foregroundStyle(theme.ink)
            Text("tu noche viene en camino")
                .font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
        case .importedBaseline, .waiting:
            Text("Sin lectura")
                .font(InstrumentoType.groteskVerdict).foregroundStyle(theme.ink)
            Text(strapSeen ? "llega con el sync de la mañana" : "conecta tu banda o Apple Salud")
                .font(StrandFont.caption).foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// El delta del héroe: la recuperación de hoy vs la media de 7 días (misma base que los tiles).
    /// nil sin lectura o sin ≥4 días de base.
    private var recoveryVsAverage: Int? {
        guard let today = repo.today?.recovery else { return nil }
        let base = history(baselineDays()) { $0.recovery }
        guard base.count >= 4 else { return nil }
        return Int((today - base.reduce(0, +) / Double(base.count)).rounded())
    }

    /// Una línea horizontal simple para el subrayado punteado del veredicto.
    private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: 0, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.width, y: rect.midY))
            return p
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

    /// El puente a Señales desde el Brief transicional: desliza el pager a la página de tiles (donde
    /// hay datos que ver mientras llega el veredicto). Cápsula en tinta — chrome, no dato (sin verde).
    private var metricsBridge: some View {
        Button {
            withAnimation(reduceMotion ? nil : StrandMotion.interactive) { pagerPage = 0 }
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
                                     sleepMinutes: sleepMin,
                                     hrvEstimated: memoAppleHrvEstimated)
    }

    /// FER-623: la viñeta de HRV ESTIMADA para un día sin banda. El veredicto mide solo contra la base de
    /// banda (RMSSD), así que un día Apple-only no trae señal de HRV. Aquí se clasifica la SDNN de hoy
    /// contra la PROPIA base SDNN reusando `ReadinessEngine` sobre la historia enmascarada a Apple — el
    /// mismo z-score/banding/cold-start del motor, sin matemática nueva. `nil` si hoy NO es estimado (día de
    /// banda → el veredicto ya trae su HRV) o si la base SDNN aún no madura (el motor calla < minBaseline).
    /// Se siembra en `recomputeDerived` (memo `memoAppleHrvEstimated`), no por frame — corre un `evaluate`.
    private func computeAppleHrvEstimated() -> DailyBrief.HrvEstimatedBullet? {
        guard repo.isRecoveryEstimated(Repository.localDayKey(Date())) else { return nil }
        let appleDays = SourceLens.maskHrv(repo.days, keep: .apple, appleDays: repo.appleHealthDays)
        let r = ReadinessEngine.evaluate(days: appleDays, today: Repository.localDayKey(Date()))
        guard let hrv = r.signals.first(where: { $0.key == "hrv" }), let z = hrv.z else { return nil }
        return DailyBrief.HrvEstimatedBullet(z: z, flag: hrv.flag)
    }

    /// El bloque «Hoy en tu plan» (FER-613): puente con Entrenar al pie del brief. `nil` sin split (se omite).
    private var trainingBlock: DailyBrief.TrainingBlock? {
        DailyBriefEngine.trainingBlock(hasSplit: hasSplit,
                                       todayRoutineName: todayRoutineName,
                                       streakDays: trainingStreak,
                                       recovery: repo.today?.recovery)
    }

    /// «La conexión de hoy» (FER-614/615): la correlación significativa más relevante O el experimento N-of-1
    /// en curso, elegido por la regla de prioridad determinista (`dayConnection`), o `nil` (la UI omite el
    /// renglón). Misma fuente que Patrones, así el deep-link abre exactamente ese patrón / experimento.
    private var dayConnection: DailyBrief.DayConnection? {
        DailyBriefEngine.dayConnection(insights: insights, experiment: activeExperiment)
    }

    /// El Daily Brief renderizado (handoff «Hoy» 2026-07): plano sobre el papel — encabezado con el
    /// punto AHORA, titular 22/700 en grotesk (abre el porqué), cuerpo, «La conexión de hoy» sobre
    /// `patternBlock`, las filas de acción y el CTA de entrenamiento. Las cinco reglas NO viven aquí
    /// (pertenecen solo a Señales). Sin serif: la voz nueva es Space Grotesk (F0).
    private func dailyBriefView(_ brief: DailyBrief) -> some View {
        VStack(alignment: .leading, spacing: NoopMetrics.gap) {
            briefHeader(now: true)
            Button { showWhyVerdict = true } label: {
                HStack(alignment: .firstTextBaseline, spacing: NoopMetrics.space2) {
                    Text(brief.titular)
                        .font(InstrumentoType.grotesk(22, weight: .bold, relativeTo: .title2))
                        .tracking(-0.4)
                        .foregroundStyle(theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Image(systemName: "info.circle").font(.system(size: 15))
                        .foregroundStyle(theme.inkTertiary)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("Abre por qué el veredicto se lee así"))

            Text(brief.why).font(StrandFont.subhead).foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let conn = dayConnection { dayConnectionView(conn) }

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
            connectionLineView(text: c.text, cta: "Ver patrón",
                               hint: "Abre este patrón en Patrones") {
                tabRouter.openInsight(key: InsightFreshness.key(for: c.insight))
            }
        case .experiment(let line):
            connectionLineView(text: line.text,
                               cta: line.pendingCheckIn ? "Registra check-in" : "Ver experimento",
                               hint: line.pendingCheckIn
                                   ? "Abre tu experimento en Patrones para registrar el check-in de hoy"
                                   : "Abre tu experimento en Patrones") {
                tabRouter.openExperiment()
            }
        }
    }

    /// El chrome compartido del renglón «La conexión de hoy»: acento verde a la izquierda, la frase sin jerga y
    /// el CTA con chevron. Toca → `action` (deep-link a Patrones, distinto por fuente).
    private func connectionLineView(text: String, cta: LocalizedStringKey, hint: String,
                                    action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: NoopMetrics.space1) {
                Text("La conexión de hoy").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                HStack(alignment: .firstTextBaseline, spacing: NoopMetrics.space2) {
                    Text(text).font(StrandFont.subhead).foregroundStyle(theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: NoopMetrics.space2)
                    HStack(spacing: 2) {
                        Text(cta).font(StrandFont.caption)
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
        .padding(.top, NoopMetrics.space2)
        .accessibilityHint(Text(hint))
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
                // CTA del handoff: barra en TINTA (radio 14) con la rutina en crema y «EMPEZAR →» en el
                // acento `ctaAccent` — el único lugar donde ese verde eléctrico existe (solo sobre tinta).
                Button { tabRouter.startTodayTraining() } label: {
                    HStack(spacing: NoopMetrics.space2) {
                        Text(tb.routineName ?? String(localized: "Tu entrenamiento"))
                            .font(InstrumentoType.grotesk(13, weight: .bold))
                            .foregroundStyle(theme.paperHi)
                            .lineLimit(1).minimumScaleFactor(0.8)
                        Spacer(minLength: NoopMetrics.space2)
                        HStack(spacing: NoopMetrics.space1) {
                            Text("Empezar")
                                .font(InstrumentoType.grotesk(11, weight: .semibold))
                                .tracking(1.2)
                                .textCase(.uppercase)
                            Image(systemName: "arrow.right").font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(theme.ctaAccent)
                    }
                    .padding(.horizontal, NoopMetrics.cardPadding)
                    .padding(.vertical, 14)
                    .background(theme.ink, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                    HStack(spacing: NoopMetrics.space2) {
                        Text(b.lead).font(StrandFont.subhead.weight(.semibold)).foregroundStyle(theme.ink)
                        // FER-623: cuando la HRV de hoy es un estimado de Apple Salud (SDNN, día sin banda),
                        // se sella «estimado» — espejo del mismo glifo/criterio que el sello del veredicto, así
                        // nunca se ve idéntica a una lectura de banda. Token-only; reusa la frase localizada.
                        if b.kind == .hrv, repo.isRecoveryEstimated(Repository.localDayKey(Date())) {
                            briefEstimatedBadge
                        }
                    }
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

    /// FER-623: el sello «estimado» de la viñeta de HRV cuando hoy salió de Apple Salud (SDNN, día sin
    /// banda). Mismo glifo `applewatch` + confianza que el sello del veredicto (`estimatedTodayMarker`),
    /// en chico junto al encabezado de la viñeta. Token-only, reusa la frase localizada del Detalle.
    private var briefEstimatedBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "applewatch").font(.system(size: 9, weight: .semibold))
                .accessibilityHidden(true)
            Text(RecoveryDetailScreen.confidenceLabel(repo.recoveryConfidence(Repository.localDayKey(Date()))))
                .font(StrandFont.footnote)
        }
        .foregroundStyle(theme.inkTertiary)
        .accessibilityLabel(Text("HRV estimada de Apple Salud"))
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

    /// Página 1 del pager: SEÑALES — el bloque «POR QUÉ N» (las cinco reglas, solo con veredicto) +
    /// la retícula 2×4 de tiles; o la tarjeta de fuentes si no hay ninguna (FER-364).
    @ViewBuilder private var senalesPage: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.sectionGapCompact) {
            if heroState == .verdict, !rulesRows.isEmpty { fiveRulesBlock }
            if noSources { emptySourcesCard } else { iosMetricsSection }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// El bloque «POR QUÉ 74 · las cinco reglas»: la suma visible del score. Overlines arriba
    /// («POR QUÉ N» / «EL LARGO ES EL PESO»), el instrumento de marcas, y la leyenda de origen abajo.
    /// Tras un pull-to-refresh las marcas se encienden en secuencia (`celebrationStart`); al abrir, nunca.
    @ViewBuilder private var fiveRulesBlock: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.space2) {
            HStack {
                Text("Por qué \(recoveryScore ?? 0)")
                    .groteskOverline().foregroundStyle(theme.inkTertiary)
                Spacer(minLength: NoopMetrics.space2)
                Text("El largo es el peso")
                    .groteskOverline(small: true).foregroundStyle(theme.inkMuted)
            }
            if let start = celebrationStart, !reduceMotion {
                TimelineView(.animation) { context in
                    FiveRulesView(rows: rulesRows,
                                  reveal: min(1, context.date.timeIntervalSince(start) / 1.2))
                }
            } else {
                FiveRulesView(rows: rulesRows)
            }
            HStack(spacing: NoopMetrics.space2) {
                Text("Señales").groteskOverline(small: true).foregroundStyle(theme.inkMuted)
                Spacer(minLength: NoopMetrics.space2)
                sourceLegend
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Por qué \(recoveryScore ?? 0): la suma de tus cinco señales"))
    }

    /// Las filas del instrumento, del motor puro (`RecoveryRules`, memoizado en `recomputeDerived`) con
    /// su etiqueta y color de dato por señal.
    private var rulesRows: [FiveRulesView.Row] {
        (memoRules ?? []).map { rule in
            let (label, color): (String, Color) = {
                switch rule.key {
                case "hrv":      return (String(localized: "HRV"), theme.dataHrv)
                case "rhr":      return (String(localized: "FC reposo"), theme.dataHeart)
                case "sleep":    return (String(localized: "Sueño"), theme.dataSleep)
                case "skinTemp": return (String(localized: "Temp. piel"), theme.dataStrain)
                default:         return (String(localized: "Respiración"), theme.dataSpO2)
                }
            }()
            return FiveRulesView.Row(id: rule.key, label: label, color: color,
                                     marks: rule.marks, lit: rule.lit)
        }
    }

    /// El pager horizontal de 2 páginas. `ScrollView(.horizontal)` con `.scrollTargetBehavior(.paging)`
    /// (snap a página) + `.scrollPosition` para reflejar la página activa en los dots; `.scrollTargetLayout()`
    /// en el riel. Cada página mide `width` (= ancho de contenido) para que el snap pagine de a una. El alto
    /// lo fija la página más alta (Métricas); en la página 1 el resto queda en blanco hasta que F3 la llene
    /// con el Daily Brief. Ejes ortogonales al scroll vertical → no se pelea con el pull-to-refresh.
    @ViewBuilder private func todayPager(width: CGFloat) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 0) {
                senalesPage.frame(width: width).id(0)
                verdictPage.frame(width: width).id(1)
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $pagerPage)
    }

    /// Las pestañas SEÑALES / BRIEF sobre el pager (handoff): 11/700 trackeadas, activa en tinta,
    /// inactiva en `inkMuted`, con un subrayado elástico de 2 pt que se desliza con spring y cambia de
    /// ancho entre palabras (`matchedGeometryEffect`). Tocar una pestaña anima el pager a su página.
    @Namespace private var tabUnderlineNS
    private var sectionTabs: some View {
        HStack(spacing: NoopMetrics.cardPadding) {
            tabButton("Señales", page: 0)
            tabButton("Brief", page: 1)
            Spacer(minLength: 0)
        }
        .animation(reduceMotion ? nil : StrandMotion.interactive, value: pagerPage)
    }

    private func tabButton(_ title: LocalizedStringKey, page: Int) -> some View {
        let active = (pagerPage ?? 0) == page
        return Button {
            withAnimation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.62)) {
                pagerPage = page
            }
        } label: {
            VStack(alignment: .leading, spacing: NoopMetrics.space1 + 1) {
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
                .accessibilityLabel(Text(i == 0 ? "Señales" : "Brief"))
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

    /// La overline del héroe (dos líneas, MAYÚSCULAS trackeadas): qué es el numeral, honesto por estado.
    private func heroOverline(_ s: HeroState) -> LocalizedStringKey {
        switch s {
        case .verdict:
            return repo.isRecoveryEstimated(Repository.localDayKey(Date()))
                ? "Recuperación\nestimada" : "Recuperación\nde hoy"
        case .calibrating: return "Tu base\nse afina"
        default:           return "Recuperación\nde hoy"
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

    /// FER-153/FER-700: sello bajo el veredicto cuando la lectura del día es un estimado de Apple (noche
    /// sin banda). Muestra la COBERTURA de señales («Estimado — N de 3 señales») — el porqué de un número
    /// conservador (el shrinkage de FER-698) — en vez del grado de confianza (madurez del baseline, que
    /// vive en el Detalle). Cae al grado de confianza si la cobertura no está (no debería, en un estimado).
    /// Token-only; reusa las frases localizadas del Detalle de recuperación.
    private var estimatedTodayMarker: some View {
        let dayKey = Repository.localDayKey(Date())
        return HStack(spacing: NoopMetrics.space2) {
            Image(systemName: "applewatch").font(.system(size: 10, weight: .semibold))
                .accessibilityHidden(true)
            Text(RecoveryDetailScreen.coverageLabel(repo.recoveryPrimaryDrivers(dayKey))
                 ?? RecoveryDetailScreen.confidenceLabel(repo.recoveryConfidence(dayKey)))
                .font(StrandFont.caption)
        }
        .foregroundStyle(theme.inkSecondary)
        .accessibilityElement(children: .combine)
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
        // Esfuerzo del día en curso: el valor VIVO (fin de la curva intradía), no el score asentado —
        // así el tile, el héroe del Detalle y la curva muestran UN solo número (FER-650). Cae al asentado
        // mientras el vivo aún no se computa. Los días pasados no lo tocan.
        let strainT = model.displayedDayStrain
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

        VStack(alignment: .leading, spacing: NoopMetrics.space2) {
            // La retícula 2×4 del handoff: los MISMOS 8 vitales de hoy, cada tile con su punto de
            // origen, valor 21/700 en color, sparkband de 14 días contra el rango personal y la línea
            // delta explícita. Recuperación NO es tile: ya es el numeral del héroe.
            LazyVGrid(columns: tileGrid, alignment: .leading, spacing: NoopMetrics.space2 + 2) {
                // Sueño — day-scoped (solo hoy); más es mejor dentro de lo razonable.
                metricTile(TodayMetricTile(
                    label: "Sleep",
                    icon: "moon.fill",
                    value: sleepR.map { sleepClockText($0.value) } ?? "—",
                    valueColor: theme.dataSleep,
                    source: sleepR?.fromApple == true ? .apple : .band,
                    context: tileContext(today: sleepR?.value, history: history(base) { $0.totalSleepMin },
                                         betterHigher: true, deadband: 5, positive: positiveDelta) { sleepDeltaText($0) },
                    series: areaSeries(base, today: sleepR?.value) { $0.totalSleepMin },
                    placeholder: "Esta noche"
                )) { metricDetail = .sleep(sleepR.map { Int($0.value.rounded()) }) }
                // HRV — más alta es mejor.
                metricTile(TodayMetricTile(
                    label: "HRV",
                    icon: "waveform.path.ecg",
                    value: hrvR.map { "\(Int($0.value.rounded()))" } ?? "—", unit: String(localized: "ms"),
                    valueColor: theme.dataHrv,
                    source: hrvR?.fromApple == true ? .apple : .band,
                    context: tileContext(today: hrvR?.value, history: history(base) { $0.avgHrv },
                                         betterHigher: true, deadband: 1, positive: positiveDelta) { "\(Int($0.rounded())) ms" },
                    series: areaSeries(base, today: hrvR?.value) { $0.avgHrv }
                )) { metricDetail = .hrv(hrvR?.value) }
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
                // Esfuerzo del día — carga del día, sin valencia (Δ en tinta neutra).
                metricTile(TodayMetricTile(
                    label: "Day Strain",
                    icon: "bolt.fill",
                    value: strainT.map { String(format: "%.1f", $0) } ?? "—",
                    valueColor: theme.dataStrain,
                    source: .calculated,
                    context: tileContext(today: strainT, history: history(base) { $0.strain },
                                         betterHigher: nil, deadband: 0.3, positive: positiveDelta) { String(format: "%.1f", $0) },
                    series: areaSeries(base, today: strainT) { $0.strain }
                )) { metricDetail = .strain(strainT) }
                // Pasos — sin meta (no existe en la app); más es mejor. Con conteo real (Apple) el tile
                // es el de siempre; en un día estimado (WHOOP 4.0, FER-663) el valor lleva «est.», el
                // chip pasa a «calculado» y el contexto/serie comparan estimación-contra-estimación.
                let stepsEstimated = stepsEstFresh != nil
                let stepsTileHistory = stepsEstimated ? stepsEstHistory : history(base) { $0.steps.map(Double.init) }
                let stepsTileSeries  = stepsEstimated
                    ? Array(stepsEst.suffix(14).map { $0.value })
                    : areaSeries(base, today: stepsT) { $0.steps.map(Double.init) }
                metricTile(TodayMetricTile(
                    label: "Steps",
                    icon: "figure.walk",
                    value: stepsT.map { intString($0) } ?? "—",
                    unit: stepsEstimated ? String(localized: "est.") : nil,
                    valueColor: theme.dataSteps,
                    source: stepsEstimated ? .calculated : .apple,
                    context: tileContext(today: stepsT, history: stepsTileHistory,
                                         betterHigher: true, deadband: 100, positive: positiveDelta) { intString($0) },
                    series: stepsTileSeries
                )) { metricDetail = .steps(stepsFresh ?? stepsEstFresh) }
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
                // Respiración — «en rango» es lo normal; sin valencia simple (Δ en tinta neutra).
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
            }
        }
    }

    /// Sueño en formato reloj del handoff: «7:12» (horas:minutos dormidos).
    private func sleepClockText(_ mins: Double) -> String {
        String(format: "%d:%02d", Int(mins) / 60, Int(mins) % 60)
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
            return .ready(text: String(localized: "En tu promedio 7 d"), color: theme.inkSecondary)
        }
        let up = change > 0
        let color: Color = betterHigher.map { (up == $0) ? positive : theme.negativeText } ?? theme.inkSecondary
        let sign = up ? "+" : "\u{2212}"
        return .ready(text: "\(sign)\(format(abs(change))) \(String(localized: "vs promedio 7 d"))",
                      color: color)
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

    /// Un tile de la retícula 2×4 (handoff «Hoy» 2026-07): icono + nombre + punto de origen arriba;
    /// valor 21/700 tabular en el color del dato + unidad; **sparkband** de 14 días (franja de rango
    /// personal + línea + punto final); y la línea delta explícita («+24 min vs promedio 7 d»).
    /// Tematizado con tokens sobre `surface` + hairline; sin lectura el tile se apaga a `inkDim`.
    private struct TodayMetricTile: View {
        let label: LocalizedStringKey
        var icon: String? = nil
        let value: String
        var unit: String? = nil
        let valueColor: Color
        var source: MetricSource = .band
        var context: TileContext? = nil
        /// Los hasta 14 valores diarios del sparkband (la cabeza = hoy). Con <3 puntos no se dibuja.
        var series: [Double] = []
        /// Pie cuando no hay valor/contexto (p. ej. «Esta noche» en el tile day-scoped de Sueño). FER-341.
        var placeholder: LocalizedStringKey? = nil
        @Environment(\.instrumentoTheme) private var theme

        private var isEmpty: Bool { value == "—" }

        var body: some View {
            VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                HStack(spacing: NoopMetrics.space1) {
                    if let icon {
                        Image(systemName: icon)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(isEmpty ? theme.inkDim : valueColor)
                            .accessibilityHidden(true)
                    }
                    Text(label)
                        .font(InstrumentoType.grotesk(9, weight: .semibold))
                        .tracking(1.4)
                        .textCase(.uppercase)
                        .foregroundStyle(theme.inkTertiary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: NoopMetrics.space1)
                    if !isEmpty { SourceChip(source: source) }
                }
                HStack(alignment: .firstTextBaseline, spacing: NoopMetrics.space1) {
                    Text(value)
                        .font(InstrumentoType.groteskTileValue)
                        .foregroundStyle(isEmpty ? theme.inkDim : valueColor)
                        .lineLimit(1).minimumScaleFactor(18.0 / 21.0)
                    if let unit {
                        Text(unit).font(StrandFont.caption)
                            .foregroundStyle(isEmpty ? theme.inkDim : theme.inkTertiary)
                    }
                }
                if series.count >= 3 {
                    TileSparkband(series: series, color: isEmpty ? theme.inkDim : valueColor)
                }
                footer
            }
            .padding(.horizontal, NoopMetrics.gap).padding(.vertical, NoopMetrics.space2 + 2)
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
            .background {
                RoundedRectangle(cornerRadius: NoopMetrics.tileRadius, style: .continuous)
                    .fill(theme.surface)
                    .shadow(color: theme.ink.opacity(0.05), radius: 1.5, x: 0, y: 1)
            }
            .overlay(RoundedRectangle(cornerRadius: NoopMetrics.tileRadius, style: .continuous)
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
                Text("Aún sin promedio propio")
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
        // FER-623: mismo `bandDays` que `recomputeDerived`, para que el fallback en frío coincida con el memo.
        memoReadiness ?? ReadinessEngine.evaluate(days: bandDays, today: Repository.localDayKey(Date()))
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
        // Issue every query concurrently, then collect. The store is a serial DatabaseQueue so I/O still
        // serializes, but the memoized ensureStore() makes the parallel first-callers share ONE open, and
        // the queries run back-to-back with no main-actor ping-pong.
        async let adRows     = repo.appleDailyRows()
        async let amRows     = repo.appleDailyMetricRows()
        // Stored daily "stress" series (0–3) — the model prefers it, else derives from RHR/HRV. (FER-180)
        async let stressRows = repo.series(key: "stress", source: "my-whoop")
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
        // Esfuerzo del día en curso (FER-650): recomputa el valor VIVO en cada refresh del dashboard, para
        // que el tile refleje la carga hasta ahora incluso sin abrir el Detalle.
        await model.refreshLiveDayStrain()
        // «La conexión de hoy» (FER-614): los hallazgos rankeados, misma fuente que Patrones.
        insights = await InsightsProvider.generate(repo: repo, today: Repository.localDayKey(Date()))
        // El experimento N-of-1 en curso (FER-615): la 2ª fuente del mismo renglón.
        await loadActiveExperiment()
    }

    /// Carga el experimento N-of-1 en curso como input plano para el motor (FER-615), espejo de `BucleView`:
    /// cierra primero el experimento cuya ventana ya venció (idempotente) para no mostrar uno rancio, lee el
    /// `activeExperiment` + su `experimentProgress` (día/check-in derivados del historial, sin migración) y
    /// resuelve las etiquetas es-MX con el mismo `BucleFormat` que Patrones. `nil` sin experimento en curso.
    private func loadActiveExperiment() async {
        let todayKey = Repository.localDayKey(Date())
        await repo.closeDueExperiment(today: todayKey)
        guard let row = await repo.activeExperiment() else { activeExperiment = nil; return }
        let progress = await repo.experimentProgress(row, today: todayKey)
        activeExperiment = DailyBriefEngine.ActiveExperiment(
            behaviorLabel: BucleFormat.behaviorLabel(row.behavior),
            outcomeLabel: row.outcome,
            dayNumber: progress.elapsedDay,
            pendingCheckIn: progress.pendingCheckIn)
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

    #if os(iOS)
    /// Today's accumulated-strain curve for the Day Strain info sheet (FER-110). Reads today's HR
    /// (local midnight → now) and runs it through the SAME strain parameters as the daily score — the
    /// user's HRmax, today's resting HR, sex — so the curve's last point lands on the Day Strain value
    /// shown in the header. Loaded lazily when the sheet opens. Returns [] when there's no score yet or
    /// too little activity, so the sheet shows its "not enough activity" state.
    private func loadStrainCurve() async -> [TrendPoint] {
        // Single canonical derivation + builder (FER-650): AppModel owns the params, window and midnight
        // anchor so the tile, the hero and this curve can never disagree. It also publishes
        // `model.liveDayStrain` (= the last point) as a side effect.
        await model.strainCurveTrendPoints()
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
