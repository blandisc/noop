import SwiftUI
import Foundation
import StrandDesign
import StrandAnalytics

// MARK: - LiquidMetricSheetView (épico hoja Liquid, pre-F6 — el COMPOSITOR)
//
// La hoja de resumen Liquid: compone los componentes del DS (`LiquidGlass/*`) con los
// MISMOS datos, loaders y copy que `MetricInfoSheet` — misma firma de datos, mismas
// Montada en TodayView y SleepDetailScreen desde el cutover F6.
// (eso es F6): se verifica por arnés y #Preview.
//
// Paridad (docs/design-system/LIQUID-SHEET-CONTRACT.md):
//  · §1 matriz — el switch de variantes replica `summaryBranch` (MetricInfoSheet:170-182):
//    recovery → vital-template → sueño → strain → clásica; con el skeleton NUEVO de F5
//    para el modelo async de sueño (hoy la hoja vieja cae a la clásica, §1.3).
//  · D3 — origen HONESTO Apple-only: «Apple Health» cuando el valor vino de Salud,
//    «Calculated» para recovery/strain/stress; JAMÁS el legado «Band».
//  · Detents — paridad :274-278 vía `LiquidSheetDetent`: .porContenido para
//    strain/heart_rate/trend/niveles (el cascarón mide su alto), .medio para el resto.
//  · Niveles — `MetricLevelsHostModel` (F3a, paridad numérica testeada) + explorador
//    Liquid (F3b: selector I3, gráfica I1/I2, filas `LiquidLevelRow`).
//  · Copy — TODA frase con `String(localized:)` sobre las MISMAS claves literales que
//    MetricInfoSheet/MetricInfoCatalog (ver `LiquidSheetCopy` abajo: los modelos llevan
//    `LocalizedStringKey`, del que no se puede extraer la clave, así que el compositor
//    replica la clave literal; F6 puede migrar `MetricInfo` a `String` y borrar el mapa).
//
// CERO `InstrumentoTheme` en este archivo.

struct LiquidMetricSheetView: View {
    let info: MetricInfo
    let appleConnectHint: Bool
    let appleSource: Bool
    /// D8 · El esfuerzo de hoy es el ESTIMADO de Apple (FER-883), no el que calculó Cénit.
    /// El tile de Hoy ya lo dice así (`LiquidHoyBuilder`: «Carga del día» + medido) y la
    /// hoja está a un tap: sin esto las dos superficies se contradicen.
    let strainEstimated: Bool
    let heartRateCurveLoader: (() async -> [TrendPoint])?
    let trendLoader: (() async -> [TrendPoint])?
    let onSeeMore: (() -> Void)?
    let levelsSeriesLoader: (() async -> [(day: String, value: Double)])?
    let whatMovesIt: [WhatMovesItFinding]
    let sleepDetail: SleepDetailModel?

    /// El host F3a de niveles: serie parseada una vez + niveles con caché (fold HRV incl.)
    /// + ventana por rango — paridad numérica bit a bit con la hoja Instrumento.
    @State private var levelsHost: MetricLevelsHostModel
    /// El nivel que el usuario explora en la lista (nil = el de hoy) — paridad
    /// `MetricLevelsExplorer.selectedLevelIndex`.
    @State private var nivelExplorado: Int? = nil
    @State private var heartRateCurve: [TrendPoint] = []
    @State private var heartRateLoading = false
    @State private var trendData: [TrendPoint] = []
    @State private var trendLoading = false
    /// B8 · ¿El loader del trend ya CONTESTÓ? `trendLoading` arranca en `false`, así que el
    /// primer frame anunciaba «Sin datos de los últimos 14 días» sobre una hoja que estaba
    /// cargando, y un instante después saltaba al esqueleto. No se puede usar
    /// `trendData.isEmpty` como proxy de «cargando»: una métrica que de verdad no tiene 14
    /// días de historia se quedaría en el esqueleto para siempre.
    @State private var trendIntentado = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.liquidMotionDisabled) private var motionDisabled

    init(info: MetricInfo,
         appleConnectHint: Bool = false,
         appleSource: Bool = false,
         strainEstimated: Bool = false,
         heartRateCurveLoader: (() async -> [TrendPoint])? = nil,
         trendLoader: (() async -> [TrendPoint])? = nil,
         onSeeMore: (() -> Void)? = nil,
         levelsSeriesLoader: (() async -> [(day: String, value: Double)])? = nil,
         whatMovesIt: [WhatMovesItFinding] = [],
         sleepDetail: SleepDetailModel? = nil) {
        self.info = info
        self.appleConnectHint = appleConnectHint
        self.appleSource = appleSource
        self.strainEstimated = strainEstimated
        self.heartRateCurveLoader = heartRateCurveLoader
        self.trendLoader = trendLoader
        self.onSeeMore = onSeeMore
        self.levelsSeriesLoader = levelsSeriesLoader
        self.whatMovesIt = whatMovesIt
        self.sleepDetail = sleepDetail
        _levelsHost = State(initialValue: MetricLevelsHostModel(
            metricID: info.id, levelsMetric: info.levelsMetric,
            levelsRelative: info.levelsRelative))
    }

    // MARK: Modo DEMO en vivo (/inject 2026-07-23) — apagar al cerrar la sesión.

    /// Con `true`, la hoja usa un dato de muestra por métrica y siembra las series de las
    /// gráficas, para pulir el diseño en un simulador sin datos de Apple Salud.
    ///
    /// Gate `#if DEBUG` (la misma disciplina que ya tenía `TodayView.liquidDemo`): el
    /// interruptor quedó commiteado en `true` y, sin gate, cualquier merge publicaba una
    /// hoja que pinta datos fabricados para las 17 métricas ignorando lo que traiga Apple
    /// Salud. En Release la hoja NUNCA puede caer en el modo demo; apagarlo del todo
    /// —volver esta línea a `false`— sigue siendo el último paso antes de mergear.
    /// Computed a propósito: su cuerpo se voltea EN VIVO por inyección (/inject).
    #if DEBUG
    private var demo: Bool { false }  // /inject: ON para pulir; APAGADO para mergear (datos reales de Apple Salud)
    #else
    private var demo: Bool { false }
    #endif

    /// El `MetricInfo` que la hoja MUESTRA: el fixture con dato en modo demo, el real si no.
    private var datoInfo: MetricInfo { demo ? Self.demoInfo(info.id) : info }

    /// Fixture con dato de muestra por id (mismas factories del catálogo → misma variante).
    static func demoInfo(_ id: String) -> MetricInfo {
        switch id {
        case "sleep":     return .sleep(432)
        case "hrv":       return .hrv(56)
        case "rhr":       return .restingHR(52)
        case "strain":    return .strain(10.0)
        case "steps":     return .steps(8432)
        case "spo2":      return .spo2(97)
        case "skin_temp": return .skinTemp(0.1)
        case "resp_rate": return .respiratory(14)
        case "stress":    return .stress(1.2)
        case "heart_rate": return .heartRate(avgBpm: 62)
        case "vo2max":    return .vo2max(42)
        // D2 · Las 5 submétricas del Detalle de Sueño caían al `default` (VFC), así que la
        // variante CLÁSICA —trend de 14 días + tabla de bandas— era inalcanzable en la app
        // corriendo: se estaba puliendo a ciegas.
        case "sleep_performance": return .sleepPerformance(85)
        case "sleep_efficiency":  return .sleepEfficiency(88)
        case "sleep_restorative": return .sleepRestorative(42)
        case "sleep_awakenings":  return .sleepAwakenings(3)
        case "sleep_latency":     return .sleepLatency(14)
        default:          return .hrv(56)
        }
    }

    /// Centro plausible de la serie por id (para niveles y trend de muestra).
    private static func demoCentro(_ id: String) -> (centro: Double, amp: Double) {
        switch id {
        case "sleep":     return (430, 45)
        case "rhr":       return (54, 5)
        case "strain":    return (10, 3)
        case "steps":     return (8000, 1600)
        case "spo2":      return (97, 1.2)
        case "skin_temp": return (0.1, 0.35)
        case "resp_rate": return (14, 1.2)
        case "stress":    return (1.2, 0.5)
        // D2 · Sin estos casos la SERIE de las submétricas de sueño caía al centro de VFC
        // (55 ± 8) mientras la cabecera decía «85 %»: la hoja se contradecía y los conteos
        // de la tabla no se podían leer. Las amplitudes CRUZAN las cotas de cada fábrica
        // (85 → <70/70-85/85+, 88 → <75/75-85/85+, 42 → <30/30-50/50+, 14 → <10/10-20/20+)
        // para que los tres conteos salgan repartidos y sumen 14.
        case "sleep_performance": return (85, 16)
        case "sleep_efficiency":  return (86, 12)
        case "sleep_restorative": return (42, 16)
        case "sleep_awakenings":  return (3, 2)
        case "sleep_latency":     return (14, 8)
        default:          return (55, 8)   // hrv
        }
    }

    /// Formateador de day-key «yyyy-MM-dd» (el que `parseDayKey` entiende).
    private static let demoKeyFmt: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// 30 días de serie diaria de muestra (day-keys válidas), deterministas.
    static func demoRows(_ id: String) -> [(day: String, value: Double)] {
        let (centro, amp) = demoCentro(id)
        let cal = Calendar.current
        let hoy = Date()
        return (0..<30).reversed().map { i in
            let fecha = cal.date(byAdding: .day, value: -i, to: hoy) ?? hoy
            let onda: Double = sin(Double(i) * 0.6)
            let v: Double = centro + amp * onda + Double(i % 4) - 1.5
            return (day: demoKeyFmt.string(from: fecha), value: v)
        }
    }

    /// 14 puntos de tendencia de muestra.
    static func demoTrend(_ id: String) -> [TrendPoint] {
        let (centro, amp) = demoCentro(id)
        let cal = Calendar.current
        let hoy = Date()
        return (0..<14).reversed().map { i in
            let fecha = cal.date(byAdding: .day, value: -i, to: hoy) ?? hoy
            let v: Double = centro + amp * sin(Double(i) * 0.5)
            return TrendPoint(date: fecha, value: v)
        }
    }

    /// La NOCHE de muestra: sin ella la variante rica de sueño (doble dato + etapas +
    /// regularidad) no se puede pulir en un simulador sin datos de Apple Salud, porque
    /// `sleepDetail` lo inyecta TodayView y en demo llega `nil`.
    ///
    /// Los números cuadran entre sí a propósito (si no, la hoja se contradice sola):
    /// 91 profundo + 104 REM + 237 ligero = 432 min dormido = «7h 12m», EXACTAMENTE el
    /// numeral del fixture `.sleep(432)` y su banda «Óptimo» (7-9 h); + 47 despierto =
    /// 479 min en cama = la ventana 23:38 → 7:37.
    static func demoNoche() -> SleepDetailModel.Night {
        let cal: Calendar = Calendar.current
        let medianoche: Date = cal.startOfDay(for: Date())
        let inicio: Date = cal.date(byAdding: .minute, value: -22, to: medianoche) ?? medianoche
        let fin: Date = cal.date(byAdding: .minute, value: 457, to: medianoche) ?? medianoche
        let etapas = SleepDetailModel.Stages(awake: 47, light: 237, deep: 91, rem: 104)
        return SleepDetailModel.Night(
            startTs: Int(inicio.timeIntervalSince1970),
            endTs: Int(fin.timeIntervalSince1970),
            efficiency: 90.2,
            respRate: 14.2,
            stages: etapas)
    }

    /// Curva de FC de un día de muestra (~180 puntos, 5 min).
    static func demoCurva() -> [TrendPoint] {
        let cal = Calendar.current
        let inicio = cal.startOfDay(for: Date())
        return (0..<180).map { (i: Int) -> TrendPoint in
            // Tipos explícitos: el type-checker se atora con expresiones mixtas largas.
            let seg: Double = Double(i) * 300
            let fecha: Date = inicio.addingTimeInterval(seg)
            let hora: Double = seg / 3600
            let circadiano: Double = sin(hora / 24 * 2 * Double.pi - 1.3)
            let ruido: Double = sin(hora * 1.7)
            let v: Double = 62 + 22 * circadiano + 6 * ruido
            return TrendPoint(date: fecha, value: Swift.max(48, v))
        }
    }

    var body: some View {
        // `cargando` incluye los niveles (D7): si la altura se fijara con el explorador
        // todavía en su pozo, la hoja se quedaría del tamaño del esqueleto y el instrumento
        // entraría apretado en cuanto llegara la serie.
        LiquidMetricSheet(tono: tono, detent: detent,
                          cargando: isSleepLoading || trendLoading || heartRateLoading
                              || levelsCargando) {
            cabecera
            cuerpo
            pie
        }
        .task {
            // Modo DEMO (/inject 2026-07-23): siembra datos de muestra para pulir la hoja
            // en un simulador sin datos de Apple Salud. Apagar antes de cerrar la sesión.
            if demo {
                // B7 · El fixture siembra SOLO lo que esta hoja de verdad dibuja. Sembrar
                // el trend para cualquier id hacía que `sleep_latency` —que no lleva
                // gráfica de 14 días— luciera conteos por banda calculados sobre una serie
                // invisible, y la curva de FC se generaba en las 17 hojas. Los dos gates
                // son los MISMOS que deciden si el bloque se pinta (`classicContent`).
                if info.id == "heart_rate" { heartRateCurve = Self.demoCurva() }
                if trendLoader != nil { trendData = Self.demoTrend(info.id) }
                levelsHost.load(rows: Self.demoRows(info.id))
                // B8 · El intento se marca DESPUÉS de sembrar, en la misma tarea: si lo
                // hiciera la otra, un orden de arranque distinto dejaría un frame de
                // «Sin datos de los últimos 14 días» antes de que llegue la serie.
                trendIntentado = true
                return
            }
            // Paridad MetricInfoSheet:128-133 — curva FC solo para heart_rate.
            guard info.id == "heart_rate", let loader = heartRateCurveLoader else { return }
            heartRateLoading = true
            heartRateCurve = await loader()
            heartRateLoading = false
        }
        .task {
            if demo { return }
            // Paridad :134-140 — trend ordenado por fecha al cargar (FER-876).
            guard let loader = trendLoader else { return }
            trendLoading = true
            let loaded: [TrendPoint] = await loader()
            trendData = loaded.sorted { (a: TrendPoint, b: TrendPoint) in a.date < b.date }
            trendLoading = false
            trendIntentado = true
        }
        .task {
            if demo { return }
            // Paridad :141-151 — la serie completa de niveles, parseada UNA vez en el host.
            guard let loader = levelsSeriesLoader else { return }
            let rows: [(day: String, value: Double)] = await loader()
            levelsHost.load(rows: rows)
        }
    }

    // MARK: Variantes (paridad `summaryBranch` :170-182 + skeleton F5)

    private static let vitalTemplateIDs: Set<String> =
        ["hrv", "rhr", "spo2", "skin_temp", "steps", "stress", "resp_rate"]
    private var isVitalTemplate: Bool {
        datoInfo.usesLevels && Self.vitalTemplateIDs.contains(datoInfo.id)
    }
    /// F5 (comportamiento NUEVO, contrato §1.3): el modelo de sueño se construye off-main;
    /// mientras no llega, skeleton — la hoja vieja caía al layout clásico.
    // D9 · En demo el esqueleto no se pinta NUNCA, y no por este `!demo`: `nocheSueno`
    // devuelve la noche de muestra INCONDICIONALMENTE, así que `isSleepRich` ya es cierto
    // en el primer frame. (La prosa anterior prometía una caída a la variante clásica de
    // sueño que el código nunca hace; el código está bien, la mentira era el comentario.)
    private var isSleepLoading: Bool { !demo && datoInfo.id == "sleep" && sleepDetail == nil }
    private var isSleepRich: Bool { datoInfo.id == "sleep" && nocheSueno != nil }

    /// La noche que la hoja PINTA: la de muestra en demo, la real (inyectada por TodayView)
    /// si no. Un solo hogar para las tres lecturas (`isSleepRich`, doble dato, etapas).
    private var nocheSueno: SleepDetailModel.Night? {
        if demo { return Self.demoNoche() }
        return sleepDetail?.night
    }

    /// La regularidad 0–100 que la hoja PINTA; `nil` = aún sin base (el numeral dice «··»).
    private var regularidadSueno: Int? {
        if demo { return 84 }
        return sleepDetail?.regularity?.score
    }
    private var isStrainSummary: Bool { datoInfo.id == "strain" && datoInfo.displayValue != "—" }

    @ViewBuilder private var cuerpo: some View {
        if isVitalTemplate {
            vitalContent
        } else if isSleepLoading {
            LiquidSheetSkeleton(a11yCargando: String(localized: "Loading"))
        } else if isSleepRich {
            sleepContent
        } else if isStrainSummary {
            strainContent
        } else {
            classicContent
        }
    }

    // MARK: Detent (paridad :274-278)

    private var detent: LiquidSheetDetent {
        (datoInfo.id == "strain" || datoInfo.id == "heart_rate" || trendLoader != nil
            || datoInfo.usesLevels) ? .porContenido : .medio
    }

    // MARK: Tono + glifo + tinte (mapa id→hue de `LiquidHoyBuilder.metricas` extendido)

    /// El hue Liquid de la métrica — paridad `metricHue` (:79-100) dicho en `LiquidColor`:
    /// sueño/submétricas → índigo · hrv → cian · fc → rosa · esfuerzo/piel → ámbar ·
    /// pasos → teal · respiración/SpO₂ → azul (familia dataSpO2) · recovery → verde.
    /// Estrés no tiene hue propio: banda 0–3 → verde/ámbar/rojo (paridad :96-97).
    private var tono: Color {
        switch datoInfo.id {
        case "sleep", "sleep_performance", "sleep_efficiency", "sleep_restorative",
             "sleep_awakenings", "sleep_latency":
            return LiquidColor.indigo
        case "hrv":                 return LiquidColor.cian
        case "rhr", "heart_rate":   return LiquidColor.rosa
        case "strain", "skin_temp": return LiquidColor.ambar
        case "steps":               return LiquidColor.teal
        case "resp_rate", "spo2":   return LiquidColor.azul
        case "stress":
            switch datoInfo.headerTint {
            case .good: return LiquidColor.verdePrimario
            case .warn: return LiquidColor.atencion
            case .bad:  return LiquidColor.negativo
            default:    return LiquidColor.tinta500
            }
        default:                    return LiquidColor.verdePrimario   // recovery, vo2max
        }
    }

    /// El glifo de la gota — el mismo SF Symbol que ancla la hoja Instrumento
    /// (`metricGlyphName` :286-298) dicho en `LiquidIcon.Glyph`. spo2 → `.resp`: el set
    /// Liquid no tiene gota («drop»); el oxígeno comparte la familia respiratoria (azul),
    /// mismo criterio que su hue. recovery y vo2max quedan sin glifo (paridad).
    private var glifo: LiquidIcon.Glyph? {
        switch datoInfo.id {
        case "sleep", "sleep_performance", "sleep_efficiency", "sleep_restorative",
             "sleep_awakenings", "sleep_latency":
            return .luna
        case "hrv":               return .onda
        case "rhr", "heart_rate": return .corazon
        case "strain":            return .llama
        case "steps":             return .pasos
        case "skin_temp":         return .termo
        case "resp_rate", "spo2": return .resp
        case "stress":            return .estres
        default:                  return nil
        }
    }

    /// El tinte del numeral — paridad `tintColor` (:103-111) con las voces de TEXTO
    /// Liquid: banda verde → verde/profundo, ámbar → atención/texto (AA), rojo → negativo;
    /// neutral → tinta/500; métrica → su hue.
    private func tinte(_ t: MetricInfo.Tint) -> Color {
        switch t {
        case .metric:  return tono
        case .neutral: return LiquidColor.tinta500
        case .good:    return LiquidColor.verdeProfundo
        case .warn:    return LiquidColor.atencionTexto
        case .bad:     return LiquidColor.negativo
        }
    }

    /// B4 · El mismo tinte dicho para TEXTO (la línea de lectura), no para el numeral.
    /// El ámbar de la familia (`LiquidColor.ambar`, #C4631F) es voz de DATO: sobre el papel
    /// de la hoja mide 3.8:1, por debajo del 4.5:1 que pide AA a los 16 pt en negrita del
    /// destacado de `LiquidReadingLine`. `atencionTexto` (#8F4712) es ese mismo ámbar dicho
    /// para leerse (6.1:1) — la traducción que el DS ya hace en `LiquidLevelRow` con
    /// `.atencion`, y la que `tinte(.warn)` devuelve. Toca las DOS métricas de hue ámbar
    /// (esfuerzo y temperatura de piel), no solo esfuerzo, y deja el ámbar crudo reservado
    /// al numeral: un solo datum con color por hoja.
    private func tinteTexto(_ t: MetricInfo.Tint) -> Color {
        switch t {
        case .metric where tonoEsAmbar: return LiquidColor.atencionTexto
        default:                        return tinte(t)
        }
    }

    /// Las dos métricas cuyo hue (`tono`) ES el ámbar de la familia.
    private var tonoEsAmbar: Bool {
        datoInfo.id == "strain" || datoInfo.id == "skin_temp"
    }

    // MARK: Cabecera

    /// Strain: «/ 21» solo con score real (paridad :369-373). (Recovery ya no tiene hoja — C6.)
    private var sufijo: String? {
        if datoInfo.id == "strain" { return datoInfo.displayValue != "—" ? "/ 21" : nil }
        return nil
    }

    /// D1 · La procedencia en modo DEMO. `appleSource` lo resuelve `TodayView` contra el
    /// `info` REAL (y lo apaga con `displayValue == "—"`), así que en un simulador sin Apple
    /// Salud es `false` SIEMPRE: la cabecera de muestra nunca pintaría de dónde salió el
    /// dato y la variante rica de sueño quedaría sin nada que verificar. Fuera de demo es
    /// `appleSource` tal cual (no-op en producción).
    ///
    /// B7 · Nunca para las submétricas de sueño: rendimiento, eficiencia, reparador,
    /// despertares y latencia los CALCULA Cénit sobre la noche, así que el demo las
    /// rotulaba «Apple Salud» — una procedencia inventada sobre un número nuestro.
    private var origenApple: Bool {
        (demo && !datoInfo.id.hasPrefix("sleep_")) || appleSource
    }

    /// D8 · El esfuerzo ESTIMADO es la carga que MIDIÓ Apple (FER-883), no un cálculo
    /// nuestro: el tile de Hoy ya lo dice así y la hoja está a un tap de distancia.
    private var isStrainEstimado: Bool { datoInfo.id == "strain" && strainEstimated }

    /// D3 — origen honesto Apple-only: calculado en el teléfono (recovery/strain/stress)
    /// o medido por Apple Salud; sin procedencia clara, sin punto (nunca «Band»).
    private var origen: LiquidOrigen? {
        if isStrainEstimado { return .medido }
        if ["recovery", "strain", "stress"].contains(datoInfo.id) { return .calculado }
        if origenApple { return .medido }
        return nil
    }

    private var origenEtiqueta: String? {
        if isStrainEstimado { return String(localized: "Apple Health") }
        if ["recovery", "strain", "stress"].contains(datoInfo.id) {
            return String(localized: "Calculated")
        }
        if origenApple { return String(localized: "Apple Health") }
        return nil
    }

    /// D8 · El título de la hoja. Con esfuerzo estimado dice lo mismo que el tile («Carga
    /// del día»), clave que ya existe en el catálogo (`LiquidHoyBuilder`).
    private var tituloHoja: String {
        isStrainEstimado ? String(localized: "Day load") : LiquidSheetCopy.titulo(datoInfo.id)
    }

    private var cabecera: some View {
        LiquidSheetHeader(
            icono: glifo,
            titulo: tituloHoja,
            tono: tono,
            // La variante rica de sueño (y su skeleton) reemplazan el numeral con el
            // doble dato (paridad :333).
            // Pasada UX H3: durante la carga la hoja de sueño abría SIN número — el usuario
            // tocaba «7:20» y llegaba a una pantalla muda. Solo la variante rica lo cede al
            // doble dato; mientras carga se conserva el numeral que venía del tile.
            numeral: isSleepRich ? nil : datoInfo.displayValue,
            unidad: datoInfo.unit,
            sufijo: sufijo,
            numeralTono: tinte(datoInfo.headerTint),
            origen: origen,
            origenEtiqueta: origenEtiqueta,
            // D1 · La explicación habla del dato que la hoja MUESTRA (`datoInfo`), no del
            // real: con el fixture de demo la cabecera decía «56 ms» y la explicación
            // describía otra métrica. Fuera de demo `datoInfo == info` (no-op).
            explicacion: LiquidSheetCopy.headline(datoInfo),
            // L5.1 — el ⓘ se nombra solo en VoiceOver (antes leía «VFC, uno»).
            infoMostrar: String(localized: "Show explanation"),
            infoOcultar: String(localized: "Hide explanation"))
    }

    // FER-29 · C6 — the recovery sheet body (recoveryContent / recoveryReadingText /
    // recoveryZoneMeter / zonaColor) is deleted along with `MetricInfo.recovery`: the branch was
    // unreachable (`metricDetail` never routes to recovery) and it was the last place restating the
    // recovery score's zone weights.

    // MARK: Vital-template (§1.2 — lectura + niveles + patrón)

    @ViewBuilder private var vitalContent: some View {
        if let frase = vitalReadingText {
            LiquidReadingLine(frase, highlightTone: tinteTexto(datoInfo.headerTint))
        }
        levelsBlock
        if !whatMovesIt.isEmpty {
            LiquidPatternBlock(
                overline: String(localized: "Your pattern"),
                lineas: whatMovesIt.map(Self.fraseHallazgo),
                tono: tono)
        }
    }

    /// El nivel activo de la lectura de hoy (paridad `activeLevelKey` :425-429).
    private var activeLevelKey: String? {
        guard let levels = levelsHost.levels, let v = datoInfo.levelsTodayValue,
              let idx = MetricLevels.activeIndex(for: v, in: levels) else { return nil }
        return levels[idx].key
    }

    /// Paridad `vitalReadingText` (:443-474) — mismas claves, dicho en String.
    private var vitalReadingText: String? {
        guard let key = activeLevelKey else { return nil }
        switch (datoInfo.id, key) {
        case ("hrv", "above"):        return String(localized: "Above your base, a good sign.")
        case ("hrv", "inBase"):       return String(localized: "In your usual range.")
        case ("hrv", "below"):        return String(localized: "Below your base, worth a look.")
        case ("rhr", "athlete"):      return String(localized: "Very low, athlete range.")
        case ("rhr", "excellent"):    return String(localized: "Low, a strong sign.")
        case ("rhr", "normal"):       return String(localized: "In a normal range.")
        case ("rhr", "elevated"):     return String(localized: "Above your usual, worth a look.")
        case ("spo2", "normal"):      return String(localized: "In a normal range.")
        case ("spo2", "low"):         return String(localized: "Below the typical range.")
        case ("steps", "veryActive"): return String(localized: "Very active today.")
        case ("steps", "active"):     return String(localized: "Active, a solid day.")
        case ("steps", "sedentary"):  return String(localized: "Quiet so far today.")
        case ("stress", "low"):       return String(localized: "Low, a calm day so far.")
        case ("stress", "medium"):    return String(localized: "Moderate so far today.")
        case ("stress", "high"):      return String(localized: "Running high today.")
        case ("resp_rate", "normal"):   return String(localized: "In a normal range.")
        case ("resp_rate", "elevated"): return String(localized: "Above your usual.")
        case ("skin_temp", "below"):    return String(localized: "Below your base.")
        case ("skin_temp", "inBase"):   return String(localized: "In your base.")
        case ("skin_temp", "warm"):     return String(localized: "Running warm vs your base.")
        case ("skin_temp", "elevated"): return String(localized: "Well above your base, worth a look.")
        case ("strain", "rest"):     return String(localized: "Very light day so far.")
        case ("strain", "light"):    return String(localized: "A light day so far.")
        case ("strain", "moderate"): return String(localized: "A solid, moderate day.")
        case ("strain", "hard"):     return String(localized: "A hard day of load.")
        case ("strain", "extreme"):  return String(localized: "An all-out day.")
        default: return nil
        }
    }

    /// Paridad `WhatMovesItFinding.phrase` — mismas claves (el modelo entrega
    /// `LocalizedStringKey`; el DS pide String).
    private static func fraseHallazgo(_ f: WhatMovesItFinding) -> String {
        switch (f.relationship, f.trend) {
        case (.sleepDuration, .rises):
            return String(localized: "Tends to run higher on nights you sleep more.")
        case (.sleepDuration, .falls):
            return String(localized: "Tends to run lower on nights you sleep more.")
        case (.priorStrain, .rises):
            return String(localized: "Tends to rise the day after a hard effort.")
        case (.priorStrain, .falls):
            return String(localized: "Tends to dip the day after a hard effort.")
        }
    }

    // MARK: Strain (§1.4 — lectura + niveles)

    @ViewBuilder private var strainContent: some View {
        if let frase = vitalReadingText {
            LiquidReadingLine(frase, highlightTone: tinteTexto(datoInfo.headerTint))
        }
        levelsBlock
    }

    // MARK: Sueño rica (§1.3 — doble dato + lectura + etapas + niveles)

    @ViewBuilder private var sleepContent: some View {
        if let night = nocheSueno {
            // El ⓘ de regularidad (L5.2): la métrica más opaca de la hoja explica su propio
            // método sin abrir otra pantalla; con «··» VoiceOver dice la frase honesta.
            let regularidad: String = regularidadSueno.map { (s: Int) -> String in "\(s)" } ?? "··"
            // Tipado explícito y fuera del call: el type-checker de iOS revienta con
            // ternarios sin ancla dentro de un builder (trampa documentada del repo).
            let a11yRegularidad: String? = regularidadSueno == nil
                ? String(localized: "not enough nights yet")
                : nil
            // Pasada UX H3: el MISMO número que mostró el tile (`displayValue`), no la
            // suma de etapas por otro camino — decían 7:20 y 7:12 para la misma noche.
            // B5 · Y en el MISMO formato: el catálogo escribe «7h 12m» mientras el tile
            // (`LiquidHoyBuilder.sleepClockText`), el eje (`levelsValueFormat`) y el chip
            // del scrub dicen «7:12». Se formatea caller-side desde los MISMOS minutos que
            // clasifican la noche, sin tocar `MetricInfoCatalog` (el tile lo comparte). Sin
            // minutos, el string del catálogo tal cual. Fuera del call y tipado: trampa del
            // type-checker con expresiones mixtas dentro de un builder.
            let dormido: String = datoInfo.levelsTodayValue.map(Self.sleepHM)
                ?? datoInfo.displayValue
            LiquidDobleDato(
                principal: (valor: dormido,
                            etiqueta: String(localized: "hours asleep")),
                secundario: (valor: regularidad,
                             etiqueta: String(localized: "regularity")),
                tono: tono,
                secundarioInfo: String(localized: "How steady your sleep schedule is: we take each night's midpoint (between falling asleep and waking) and measure how much it shifts night to night. Less drift, closer to 100."),
                secundarioA11y: a11yRegularidad,
                infoMostrar: String(localized: "Show explanation"),
                infoOcultar: String(localized: "Hide explanation"))
            if let frase = sleepReadingText {
                // Pedido del dueño (/inject): la frase clave en negrita, como en las demás
                // hojas — la lectura de sueño era la única que salía toda en peso normal.
                LiquidReadingLine(frase, highlight: sleepReadingHighlight,
                                  highlightTone: tono)
            }
            // D10 · La ventana solo se afirma cuando existe: el fallback diario de Apple
            // fabrica la noche con `startTs == endTs` y la hoja imprimía «6:00 → 6:00».
            // Tipado y fuera del call (trampa del type-checker con ternarios en builders).
            let ventanaNoche: String? = night.endTs > night.startTs
                ? "\(Self.clock(night.startTs)) → \(Self.clock(night.endTs))"
                : nil
            // B6 · El overline solo afirma «Anoche» cuando la noche ES de anoche: `night`
            // es «la última noche registrada», así que tras dos días sin reloj la hoja
            // fechaba como de anoche una noche vieja. Tipado y fuera del call (trampa del
            // type-checker con ternarios en builders).
            let overlineNoche: String = nocheEsDeAnoche
                ? String(localized: "Last night")
                : String(localized: "Last recorded night · \(Self.diaCorto(Self.fecha(night.startTs)))")
            // D10 · Y con las CUATRO etapas en 0 (mismo fallback) no hay noche que dibujar:
            // la barra saldría hueca bajo un overline suelto y una leyenda vacía.
            if sleepEtapasMedidas(night) {
                LiquidStageBar(
                    etapas: sleepEtapas(night),
                    overline: overlineNoche,
                    ventana: ventanaNoche)
            }
            // `LiquidLaneLabel` RETIRADO (L3.3): la frase display de los niveles ya dice el
            // nombre del carril en grande — la pastilla lo repetía dos bloques más abajo.
            levelsBlock
            // «Para esta noche» RETIRADO (decisión del dueño, /inject 2026-07-23):
            // la hoja de sueño cierra con los niveles.
        }
    }

    /// D10 · ¿Hubo etapas medidas anoche? Con el fallback diario de Apple las cuatro llegan
    /// en 0 y el componente (que ya filtra las etapas de 0 min, B7) se quedaría sin nada
    /// que pintar: es el caller quien decide no dibujar esa barra.
    private func sleepEtapasMedidas(_ night: SleepDetailModel.Night) -> Bool {
        night.stages.total > 0
    }

    /// Paridad `sleepAnocheBlock` (:561-578): profundo→REM→ligero en un índigo graduado
    /// por opacidad (sin tokens nuevos), despierto en tinta quieta; duraciones «1:31».
    private func sleepEtapas(_ night: SleepDetailModel.Night) -> [LiquidStageBar.Etapa] {
        [
            .init(minutos: night.stages.deep, color: LiquidColor.indigo,
                  etiqueta: String(localized: "Deep"),
                  duracion: Self.sleepHM(night.stages.deep)),
            .init(minutos: night.stages.rem, color: LiquidColor.indigo.opacity(0.78), // token-exempt: rampa graduada de etapas
                  etiqueta: String(localized: "REM"),
                  duracion: Self.sleepHM(night.stages.rem)),
            .init(minutos: night.stages.light, color: LiquidColor.indigo.opacity(0.52), // token-exempt: rampa graduada de etapas
                  etiqueta: String(localized: "Light"),
                  duracion: Self.sleepHM(night.stages.light)),
            // «Despierto» ya no es gris (pedido del dueño /inject): ORO — cálido y distinto de
            // las etapas, y fuera de la familia de `atencion` (pasada UX: 47 min despierto
            // es normal y no debe leerse como aviso). Antes: la
            // única etapa que NO es sueño, y el gris la volvía parte del fondo.
            .init(minutos: night.stages.awake, color: LiquidColor.oro,
                  etiqueta: String(localized: "Awake"),
                  duracion: Self.sleepHM(night.stages.awake)),
        ]
    }

    /// El trozo de la lectura de sueño que va en negrita: el nombre del rango, que es
    /// el dato de la frase (pedido del dueño /inject). Claves del MISMO catálogo.
    private var sleepReadingHighlight: String? {
        switch activeLevelKey {
        case "optimal":  return String(localized: "your target range")
        case "adequate": return String(localized: "close to your target")
        case "short":    return String(localized: "Short of your target")
        case "extended": return String(localized: "Longer than usual")
        default:         return nil
        }
    }

    /// Paridad `sleepReadingText` (:549-557) — mismas claves.
    ///
    /// B6 · Las dos variantes que decían «anoche» tienen gemela sin fecha: si el overline
    /// ya degradó a «Última noche registrada · 20 jul», la lectura no puede seguir
    /// afirmando «anoche» dos líneas más abajo. Las otras dos frases no fechan nada.
    private var sleepReadingText: String? {
        switch activeLevelKey {
        case "optimal":  return String(localized: "Right in your target range.")
        case "adequate": return String(localized: "Enough, close to your target.")
        case "short":
            return nocheEsDeAnoche
                ? String(localized: "Short of your target last night.")
                : String(localized: "Short of your target.")
        case "extended":
            return nocheEsDeAnoche
                ? String(localized: "Longer than usual last night.")
                : String(localized: "Longer than usual.")
        default:         return nil
        }
    }

    /// B6 · ¿La noche que la hoja PINTA es la de anoche? Se ancla en el día en que la noche
    /// EMPEZÓ: dormirse a las 23:38 de ayer o a la 1:00 de hoy son las dos formas normales
    /// de «anoche» (0 o 1 día de distancia); a partir de dos, la noche es vieja.
    private var nocheEsDeAnoche: Bool {
        guard let night = nocheSueno else { return false }
        let cal: Calendar = Calendar.current
        let inicio: Date = Self.fecha(night.startTs)
        let dias: Int? = cal.dateComponents([.day],
                                            from: cal.startOfDay(for: inicio),
                                            to: cal.startOfDay(for: Date())).day
        return (dias ?? 0) <= 1
    }

    /// «7:12» desde minutos (paridad `sleepHM` :510-512).
    private static func sleepHM(_ minutes: Double) -> String {
        let m = Int(minutes.rounded())
        return String(format: "%d:%02d", m / 60, m % 60)
    }

    private static func fecha(_ ts: Int) -> Date {
        Date(timeIntervalSince1970: TimeInterval(ts))
    }

    /// Reloj local «23:38» desde un unix timestamp (paridad `clock` :514-518).
    private static func clock(_ ts: Int) -> String {
        clockFmt.string(from: fecha(ts))
    }
    private static let clockFmt: DateFormatter = {
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("Hmm"); return f
    }()

    // MARK: Clásica (§1.5-1.6 — niveles o trend/curva/bandas + calibración)

    @ViewBuilder private var classicContent: some View {
        if datoInfo.usesLevels {
            levelsBlock
        } else {
            if trendLoader != nil { trendBlock }
            if datoInfo.id == "heart_rate" { heartRateBlock }
            if !datoInfo.bands.isEmpty { bandsTableBlock }
        }
        // La calibración cabalga junto a ambos layouts — solo recovery la trae (:234-236).
        if let cal = datoInfo.calibration {
            LiquidCalibracionCard(
                titulo: String(localized: "Calibrating baseline"),
                leyenda: String(localized: "\(cal.done) of \(cal.needed) nights"),
                hechas: cal.done, necesarias: cal.needed, tono: tono)
        }
    }

    // MARK: Trend 14d (paridad `trendSection` :984-1036)

    private var trendBlock: some View {
        // Fuera del call: el type-checker de iOS se atora con expresiones largas dentro de
        // un builder (ver la nota de `curvaEstado`).
        let puntos: [(fecha: Date, valor: Double)] =
            trendData.map { (p: TrendPoint) in (fecha: p.date, valor: p.value) }
        let ejeFmt: (Date) -> String = Self.ejeFechaFmt(puntos)
        let popupFecha: (Date) -> String = { (d: Date) -> String in Self.popupDiaFmt.string(from: d) }
        let popupValor: (Double) -> String = { (v: Double) -> String in self.trendValueFormat(v) }
        let marcasY: [(valor: Double, etiqueta: String)] =
            Self.ticksY(trendData.map(\.value), cuanto: trendCuanto, formato: popupValor)
        return LiquidTrendChart(
            titulo: String(localized: "Last 14 days"),
            readout: trendReadout,
            puntos: puntos,
            bandas: trendBandas,
            dominio: trendValueRange,
            ticksY: marcasY,
            tono: tono,
            // La frase COMPUESTA es la de VoiceOver (el DS no acuña el « · »); las dos
            // líneas del popup salen de los formateadores sueltos.
            formatoScrub: { (v: Double, f: Date) in
                "\(self.trendValueFormat(v)) · \(Self.diaCorto(f))"
            },
            formatoValorScrub: popupValor,
            formatoFechaScrub: popupFecha,
            formatoFechaEje: ejeFmt,
            estado: trendEstado,
            a11yLabel: String(localized: "14-day trend"))
    }

    /// D13 · Los washes de banda del trend de 14 días. La hoja NOMBRA una banda arriba
    /// (`trendReadout`) y lista las tres con su conteo abajo (`bandsTableBlock`), pero la
    /// GRÁFICA —lo primero que mira el ojo, 140 pt— no mostraba ninguna clasificación
    /// (`bandas: []`): la curva quedaba como una polilínea desnuda, sin nada contra qué
    /// leerse. Con las cotas reales del catálogo (C1) vuelve a tener contexto, dicho con el
    /// MISMO wash de la familia (I1) y no con un área de relleno (E42, descartado por
    /// identidad). Una banda sin cotas no se pinta: lavaría la gráfica entera.
    ///
    /// `sleep` queda fuera a propósito: sus cotas van en HORAS mientras la serie se dibuja
    /// en minutos. Hoy es inalcanzable por aquí (tiene niveles), pero un wash mal escalado
    /// sería una mentira gráfica silenciosa el día que lo sea.
    private var trendBandas: [LiquidChartBanda] {
        guard datoInfo.id != "sleep" else { return [] }
        let activa: Int? = datoInfo.bands.firstIndex(where: { $0.isActive })
        return datoInfo.bands.enumerated().compactMap {
            (i: Int, band: MetricInfo.Band) -> LiquidChartBanda? in
            guard band.lower != nil || band.upper != nil else { return nil }
            return LiquidChartBanda(lo: band.lower, hi: band.upper, color: tono,
                                    activa: i == activa)
        }
    }

    /// B8 · Dos defectos heredados, en orden. (a) La carga se evalúa PRIMERO y por el
    /// intento, no por `trendData.isEmpty`: con `trendLoading` arrancando en `false` el
    /// primer frame anunciaba «Sin datos de los últimos 14 días» y un instante después
    /// saltaba al esqueleto, y usar la serie vacía como proxy colgaría el esqueleto para
    /// siempre en una métrica que de verdad no tiene historia. (b) Con EXACTAMENTE una
    /// lectura la hoja negaba el dato que su propia cabecera acaba de imprimir; se dice lo
    /// honesto, con la clave que el resto de la app ya usa para este caso.
    private var trendEstado: LiquidChartEstado {
        if trendLoading || (trendLoader != nil && !trendIntentado) { return .cargando }
        if trendData.count > 1 { return .datos }
        if trendData.count == 1 {
            return .vacio(String(localized: "Only one reading in this range: not enough to draw a line yet."))
        }
        return .vacio(String(localized: "No data for the last 14 days."))
    }

    /// Paridad `rangeReadout` (:852-867): banda activa = la de hoy (o la última lectura
    /// completada) + cuántos días/noches completados comparten su rango.
    private var trendReadout: (etiqueta: String, tono: Color, frase: String)? {
        guard !datoInfo.bands.isEmpty, !trendData.isEmpty else { return nil }
        let toHours = datoInfo.id == "sleep"
        let isSteps = datoInfo.id == "steps"
        let source = (isSteps && trendData.count > 1) ? Array(trendData.dropLast()) : trendData
        let values = source.map { toHours ? $0.value / 60 : $0.value }
        let bands = datoInfo.bands.map {
            TrendBand(label: $0.label, lower: $0.lower, upper: $0.upper)
        }
        guard let ai = datoInfo.bands.firstIndex(where: { $0.isActive })
            ?? TrendBands.activeBand(values: values, bands: bands)?.index else { return nil }
        let count = values.reduce(0) { $0 + (bands[ai].contains($1) ? 1 : 0) }
        let frase = nightly
            ? String(localized: "\(count) of the last \(values.count) nights in this range")
            : String(localized: "\(count) of the last \(values.count) days in this range")
        return (etiquetaBanda(ai), tono, frase)
    }

    /// Auto-escala del trend (paridad :1096-1102).
    ///
    /// Espejo de B1 en esta gráfica: desde D13 el trend pinta washes de clasificación, y
    /// `LiquidChartPlot.washes` los CLAMPEA al dominio. Con el dominio hecho solo de los
    /// datos, una banda activa fuera de la serie salía de alto 0 (invisible) y una que
    /// solapaba a medias pintaba una astilla cuyo borde NO era su umbral — la gráfica y la
    /// tabla de bandas de abajo decían cosas distintas en las 5 submétricas de sueño. Se
    /// unen al pool las cotas finitas de la banda ACTIVA (las mismas que se dibujan, así
    /// que sueño —cuyas cotas van en horas y su serie en minutos— queda fuera solo).
    private var trendValueRange: ClosedRange<Double> {
        let vals = trendData.map(\.value)
        guard !vals.isEmpty else { return 0...100 }
        let cotasActiva: [Double] = trendBandas.first(where: { $0.activa })
            .map { (b: LiquidChartBanda) -> [Double] in [b.lo, b.hi].compactMap { $0 } } ?? []
        let pool: [Double] = vals + cotasActiva
        guard let lo = pool.min(), let hi = pool.max() else { return 0...100 }
        let span = max(hi - lo, 1)
        let pad = span * 0.15
        return max(0, lo - pad)...hi + pad
    }

    /// B2 · El PASO con que esta métrica escribe su valor (espejo de `trendValueFormat`):
    /// una décima donde el formato imprime decimal, un entero (o un minuto, en sueño) en el
    /// resto. `ticksY` cuantiza con él ANTES de posicionar la marca.
    private var trendCuanto: Double {
        switch datoInfo.id {
        case "strain", "stress", "resp_rate": return 0.1
        default:                              return 1
        }
    }

    /// Paridad `trendValueFormat` (:1104-1121) — mismos formatos por métrica.
    private func trendValueFormat(_ v: Double) -> String {
        switch datoInfo.id {
        case "strain", "stress", "resp_rate":
            return String(format: "%.1f", v)
        case "sleep":
            return Self.formatSleep(Int(v.rounded()))
        case "sleep_performance", "sleep_efficiency", "sleep_restorative":
            return "\(Int(v.rounded()))%"
        case "sleep_awakenings":
            return "\(Int(v.rounded()))"
        case "rhr":
            return "\(Int(v.rounded())) \(String(localized: "bpm"))"
        case "spo2":
            return String(format: "%.0f%%", v)
        case "steps":
            return Self.stepFmt.string(from: NSNumber(value: Int(v.rounded())))
                ?? "\(Int(v.rounded()))"
        default:
            return "\(Int(v.rounded()))"
        }
    }

    // MARK: Fechas de las gráficas (L3.1)
    //
    // TODOS por PLANTILLA (`setLocalizedDateFormatFromTemplate`), nunca con `dateFormat`
    // duro: el orden y los separadores los decide el locale («14 jul» en es-MX, «Jul 14»
    // en en-US; 24 h vs a. m./p. m.). Cacheados en `static let` porque construir un
    // `DateFormatter` por punto de la serie es caro y estos se llaman en el scrub.

    /// Eje X de una serie DIARIA corta («14 jul»).
    private static let ejeDiaFmt: DateFormatter = {
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("dMMM"); return f
    }()
    /// Eje X de una ventana LARGA (> 300 días): el día deja de importar («jul 25»).
    private static let ejeMesFmt: DateFormatter = {
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("MMMyy"); return f
    }()
    /// Segunda línea del popup del scrub en series diarias («mar, 14 jul»).
    private static let popupDiaFmt: DateFormatter = {
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("EEEdMMM"); return f
    }()
    /// Eje X de la curva de FC: solo la hora («7 a. m.»).
    private static let ejeHoraFmt: DateFormatter = {
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("ha"); return f
    }()
    /// Segunda línea del popup de la curva de FC: hora y minuto en el ciclo del locale.
    private static let popupHoraFmt: DateFormatter = {
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("jmm"); return f
    }()

    private static func diaCorto(_ date: Date) -> String { ejeDiaFmt.string(from: date) }

    /// El formateador del eje X de una serie diaria, elegido por el SPAN de la ventana:
    /// con más de 300 días las etiquetas «14 jul» se repiten de año a año y engañan.
    private static func ejeFechaFmt(_ puntos: [(fecha: Date, valor: Double)]) -> (Date) -> String {
        let primero: Date? = puntos.first?.fecha
        let ultimo: Date? = puntos.last?.fecha
        var largo: Bool = false
        if let a = primero, let b = ultimo {
            largo = b.timeIntervalSince(a) > 300 * 86_400
        }
        let fmt: DateFormatter = largo ? ejeMesFmt : ejeDiaFmt
        return { (d: Date) -> String in fmt.string(from: d) }
    }

    /// 3 marcas del eje Y (mín · medio · máx de los DATOS, no del dominio: sus bordes son
    /// puro respiro y etiquetarlos imprimiría valores que nunca ocurrieron).
    ///
    /// B2 · El valor se CUANTIZA al mismo paso con que se escribe (`cuanto`) ANTES de
    /// posicionarlo: la etiqueta redondeaba («86 %») pero la línea se dibujaba en el valor
    /// crudo (85.5), justo encima del borde de la banda «85 – 100 %», así que el eje
    /// señalaba un umbral que no era el suyo. Tras cuantizar, el tick medio se omite si
    /// cayó sobre un extremo (una serie plana no gana nada con la marca repetida).
    private static func ticksY(_ vals: [Double], cuanto: Double,
                               formato: (Double) -> String) -> [(valor: Double, etiqueta: String)] {
        guard let lo = vals.min(), let hi = vals.max(), hi > lo else { return [] }
        let q: (Double) -> Double = { (v: Double) -> Double in
            guard cuanto > 0 else { return v }
            return (v / cuanto).rounded() * cuanto
        }
        let qLo: Double = q(lo), qHi: Double = q(hi), qMedio: Double = q((lo + hi) / 2)
        var valores: [Double] = [qLo]
        if qMedio > qLo && qMedio < qHi { valores.append(qMedio) }
        if qHi > qLo { valores.append(qHi) }
        return valores.map { (v: Double) -> (valor: Double, etiqueta: String) in
            (valor: v, etiqueta: formato(v))
        }
    }

    private static let stepFmt: NumberFormatter = {
        let f = NumberFormatter(); f.numberStyle = .decimal; return f
    }()

    private static func formatSleep(_ totalMinutes: Int) -> String {
        let h = totalMinutes / 60, m = totalMinutes % 60
        return m > 0 ? "\(h)h \(m)m" : "\(h)h"
    }

    // MARK: Tabla de bandas (paridad `bandsTable` :786-846)

    private var bandsTableBlock: some View {
        let counts = bandCounts
        return LiquidBandsTable(
            filas: datoInfo.bands.enumerated().map { (i, band) in
                LiquidBandsTable.Fila(
                    etiqueta: etiquetaBanda(i),
                    rango: band.range,
                    conteo: counts.flatMap { i < $0.count ? conteoLabel($0[i]) : nil },
                    activa: band.isActive)
            },
            tono: tono)
    }

    /// Paridad `bandSummary` (:832-846): conteos por banda cuando el trend cargó.
    private var bandCounts: [Int]? {
        guard !datoInfo.bands.isEmpty, !trendData.isEmpty else { return nil }
        let toHours = datoInfo.id == "sleep"
        let isSteps = datoInfo.id == "steps"
        let source = (isSteps && trendData.count > 1) ? Array(trendData.dropLast()) : trendData
        let values = source.map { toHours ? $0.value / 60 : $0.value }
        let bands = datoInfo.bands.map {
            TrendBand(label: $0.label, lower: $0.lower, upper: $0.upper)
        }
        let todayIndex = isSteps ? nil : datoInfo.bands.firstIndex(where: { $0.isActive })
        return TrendBands.summarize(values: values, bands: bands, todayIndex: todayIndex)?.counts
    }

    /// La etiqueta de una banda como String. `MetricInfo.Band.label` es
    /// `LocalizedStringKey` (clave inaccesible), así que el mapa replica las claves de
    /// las factories del catálogo para los ÚNICOS ids que alcanzan la tabla clásica
    /// (bandas no vacías ∧ sin niveles = las submétricas de sueño). Fallback honesto:
    /// el rango numérico, que ya es String.
    private func etiquetaBanda(_ index: Int) -> String {
        let labels: [String]
        switch datoInfo.id {
        case "sleep_performance", "sleep_efficiency":
            labels = [String(localized: "Low"), String(localized: "Adequate"),
                      String(localized: "Optimal")]
        case "sleep_restorative":
            labels = [String(localized: "Low"), String(localized: "Typical"),
                      String(localized: "High")]
        case "sleep_latency":
            labels = [String(localized: "Quick"), String(localized: "Healthy"),
                      String(localized: "Prolonged")]
        default:
            labels = []
        }
        return index < labels.count ? labels[index] : datoInfo.bands[index].range
    }

    // MARK: Curva FC 24h (paridad `heartRateSection` :889-976)

    @ViewBuilder private var heartRateBlock: some View {
        let v: [Double] = heartRateCurve.map(\.value)
        // El eje X de esta curva es el RELOJ: el motor mapea x por tiempo (`mapeoPorTiempo`),
        // así que las horas caen donde de verdad ocurrieron aunque falten buckets.
        let ejeFmt: (Date) -> String = { (d: Date) -> String in Self.ejeHoraFmt.string(from: d) }
        let popupFecha: (Date) -> String = { (d: Date) -> String in Self.popupHoraFmt.string(from: d) }
        let popupValor: (Double) -> String = { (val: Double) -> String in
            "\(Int(val.rounded())) \(String(localized: "bpm"))"
        }
        // B2 · La curva de FC sufría el mismo desajuste que el trend: el tick medio se
        // etiquetaba «72» y se dibujaba en 71.5. Su paso es el latido entero.
        let marcasY: [(valor: Double, etiqueta: String)] =
            Self.ticksY(v, cuanto: 1,
                        formato: { (val: Double) -> String in "\(Int(val.rounded()))" })
        LiquidCurvaFC(
            titulo: String(localized: "Beats per minute"),
            subtitulo: String(localized: "5-minute average · since midnight"),
            ultimo: v.last.map { String(localized: "\(Int($0.rounded())) bpm") },
            puntos: heartRateCurve.map { (p: TrendPoint) in (fecha: p.date, valor: p.value) },
            dominio: Self.hrRange(v),
            stats: hrStats(v),
            statsEtiquetas: (min: String(localized: "Min"),
                             prom: String(localized: "Avg"),
                             max: String(localized: "Max")),
            ticksY: marcasY,
            formatoScrub: { (val: Double, f: Date) in
                "\(Int(val.rounded())) \(String(localized: "bpm")) · \(Self.popupHoraFmt.string(from: f))"
            },
            formatoValorScrub: popupValor,
            formatoFechaScrub: popupFecha,
            formatoFechaEje: ejeFmt,
            estado: curvaEstado,
            a11yLabel: LiquidSheetCopy.titulo("heart_rate"))
    }

    /// Estados de la curva (paridad :924-928) — fuera del call para no anidar ternarios
    /// (trampa conocida del type-checker en iOS).
    private var curvaEstado: LiquidChartEstado {
        if heartRateCurve.count > 1 { return .datos }
        if heartRateLoading { return .cargando }
        return .vacio(String(localized: "No readings yet today."))
    }

    /// Min / prom / max ya formateados (paridad `hrFooter` :933-941).
    private func hrStats(_ v: [Double]) -> (min: String, prom: String, max: String)? {
        guard !v.isEmpty else { return nil }
        let loRaw: Double = v.min() ?? 0.0
        let hiRaw: Double = v.max() ?? 0.0
        let sum: Double = v.reduce(0.0, +)
        let denom: Double = Double(max(v.count, 1))
        return (min: String(Int(loRaw.rounded())),
                prom: String(Int((sum / denom).rounded())),
                max: String(Int(hiRaw.rounded())))
    }

    /// Rango del eje con respiro (paridad `hrRange` :967-972).
    private static func hrRange(_ v: [Double]) -> ClosedRange<Double> {
        guard let lo = v.min(), let hi = v.max() else { return 40...120 }
        if hi <= lo { return (lo - 5)...(hi + 5) }
        let span = hi - lo
        return (lo - span * 0.12)...(hi + span * 0.12)
    }

    // MARK: Niveles (F3a host + F3b explorador Liquid; paridad `levelsBlock` :716-742)

    @ViewBuilder private var levelsBlock: some View {
        if levelsHost.levels != nil,
           let d = levelsHost.clasificacion(today: datoInfo.levelsTodayValue) {
            let window = levelsHost.window
            VStack(alignment: .leading, spacing: LiquidSpace.s300) {
                LiquidRangeSelector(opciones: ExploreRange.allCases.map(\.label),
                                    seleccion: rangeSeleccion)
                if levelsCargando {
                    // D7 · La serie todavía no llega. Los carriles y sus rangos SÍ se
                    // conocen (son umbrales), pero los conteos no: imprimir «Óptimo · 0 de
                    // tus últimas 0 noches» y «0 noches» en cada fila desde el primer frame
                    // es una mentira momentánea (defecto heredado §13.24). Se omiten la
                    // frase y los conteos, y el instrumento espera en su esqueleto.
                    esqueletoNiveles
                    nivelesLista(d, conteos: false)
                } else {
                    if window.fellBack { avisoVentana(window) }
                    nivelesFrase(d)
                    nivelesGrafica(d, window: window)
                    nivelesLista(d)
                }
            }
        } else if datoInfo.levelsRelative {
            // D4 · HRV sin base propia todavía. La explicación honesta OCUPA el hueco del
            // instrumento (paridad NIV-09: un pozo con presencia), en vez de degradarse a
            // una línea de letra chica que pesa menos que la nota al pie de abajo — y que
            // dejaba el cuerpo de la hoja VACÍO entre cabecera y pie.
            pozoNiveles(String(localized: "Your levels come from your own baseline: a few more nights and they'll appear."))
        }
    }

    /// D7 · ¿La serie de niveles sigue en camino? Gate por la PRESENCIA del loader: quien
    /// presenta la hoja SIN serie (el Detalle de Sueño, para respiración) no la va a cargar
    /// nunca y no debe quedarse en un pozo eterno. Residual conocido y anotado: por esa
    /// ruta la frase sigue arrancando en «0 de tus últimos 0 días».
    private var levelsCargando: Bool { levelsSeriesLoader != nil && !levelsHost.cargado }

    /// El pozo del explorador dicho con la gráfica PÚBLICA: con la serie vacía
    /// `LiquidGraficaNiveles` ya pinta el pozo del sistema (alto del explorador, papel y
    /// radio del DS) y lo dice en VoiceOver. Sin ícono, por decisión de sistema (E45).
    private func pozoNiveles(_ mensaje: String) -> some View {
        LiquidGraficaNiveles(puntos: [], bandas: [], dominio: 0.0...1.0, ticksY: [],
                             tono: tono, estadoVacio: mensaje, a11yLabel: tituloHoja)
    }

    /// D7 · El esqueleto del explorador mientras la serie viene en camino: el MISMO estado
    /// `.cargando` que ya usa el trend de 14 días, del alto del instrumento, así que la
    /// hoja no cambia de tamaño cuando llegan los datos. Sin copy inventado — un esqueleto
    /// no se anuncia, y el rótulo de la gráfica ya dice de qué métrica hablamos.
    private var esqueletoNiveles: some View {
        LiquidGraficaNiveles(puntos: [], bandas: [], dominio: 0.0...1.0, ticksY: [],
                             tono: tono, estado: .cargando, estadoVacio: "",
                             a11yLabel: tituloHoja)
    }

    /// D6 · El aviso de auto-ensanchado, con dos correcciones. (a) Cuenta los DÍAS de la
    /// ventana efectiva: `window.rows.count` son las filas CON DATO, así que tras ensanchar
    /// a 30 días con 12 lecturas decía «Mostrando los últimos 12 días», que es falso.
    /// (b) En las hojas nocturnas dice «noches», como la frase de nivel y los conteos de las
    /// filas del MISMO bloque (antes el aviso decía «días» junto a ellos).
    @ViewBuilder private func avisoVentana(_ window: MetricWindow) -> some View {
        let dias: Int = window.range.days ?? window.rows.count
        let texto: String = nightly
            ? String(localized: "Showing the last \(dias) nights")
            : String(localized: "Showing the last \(dias) days")
        // Va en `atencionTexto`, no en tinta quieta: AVISA que la ventana que estás
        // leyendo no es la que pediste en el selector.
        LiquidNotaLine(texto, tono: LiquidColor.atencionTexto)
    }

    /// El índice del selector ⇄ `ExploreRange` del host; cambiar de rango limpia la
    /// exploración (paridad `onChange(of: range)` del explorador).
    private var rangeSeleccion: Binding<Int> {
        Binding(
            get: { ExploreRange.allCases.firstIndex(of: levelsHost.range) ?? 0 },
            set: { idx in
                levelsHost.range = ExploreRange.allCases[idx]
                nivelExplorado = nil
            })
    }

    /// El nivel que la gráfica/frase destacan: la exploración del usuario o el de hoy
    /// (paridad `displayLevelIndex`).
    private func nivelDestacado(_ d: MetricLevels.Classification) -> Int? {
        if let s = nivelExplorado, d.levels.indices.contains(s) { return s }
        return d.activeIndex
    }

    /// La frase DISPLAY del explorador (paridad `phrase` :112-127, MISMAS claves de copy):
    /// el nivel destacado en grande y en el tono, con su conteo debajo en voz de lectura.
    /// El primer pase Liquid la había aplanado a una sola línea; `LiquidFraseNivel` (L2)
    /// devuelve los dos escalones de jerarquía.
    @ViewBuilder private func nivelesFrase(_ d: MetricLevels.Classification) -> some View {
        if let i = nivelDestacado(d) {
            let nombre: String = nombreNivel(d.levels[i].key)
            let conteo: String = nightly
                ? String(localized: "\(d.counts[i]) of your last \(d.total) nights")
                : String(localized: "\(d.counts[i]) of your last \(d.total) days")
            // B9 · Sin serie (la ruta del Detalle de Sueño, que presenta la hoja sin
            // `levelsSeriesLoader` y por eso no pasa por `levelsCargando`) el conteo
            // arrancaba en «0 de tus últimos 0 días». Se calla el conteo, NO el nivel: el
            // nombre del carril es verdad —son umbrales, no datos— y es la respuesta
            // literal a «¿en qué carril caigo?», el segundo elemento más grande de la hoja.
            LiquidFraseNivel(nivel: nombre,
                             conteo: d.total == 0 ? "" : conteo,
                             tono: tono)
        } else {
            let total: String = nightly
                ? String(localized: "\(d.total) nights with data in this range")
                : String(localized: "\(d.total) days with data in this range")
            LiquidFraseNivel(nivel: nil, conteo: total, tono: tono,
                             sinLectura: String(localized: "No reading today"))
        }
    }

    private func nivelesGrafica(_ d: MetricLevels.Classification,
                                window: MetricWindow) -> some View {
        let highlight = nivelDestacado(d)
        // La MISMA decimación del explorador (MetricTrendChart:196, maxPoints 80).
        let puntos = MetricWindowMath
            .decimatedPoints(rows: window.rows, values: window.values, maxPoints: 80)
            .map { (fecha: $0.date, valor: $0.value) }
        let ejeFmt: (Date) -> String = Self.ejeFechaFmt(puntos)
        let popupFecha: (Date) -> String = { (d: Date) -> String in Self.popupDiaFmt.string(from: d) }
        let popupValor: (Double) -> String = { (v: Double) -> String in self.scrubValor(v) }
        // B1 · UNA sola evaluación: el dominio y sus marcas tienen que salir del mismo
        // cálculo o el eje termina etiquetando una escala que la gráfica no dibuja.
        let dominio: ClosedRange<Double> = nivelesDominio(d, values: window.values)
        return LiquidGraficaNiveles(
            puntos: puntos,
            bandas: d.levels.enumerated().map { (i, lvl) in
                LiquidChartBanda(lo: lvl.lower, hi: lvl.upper, color: tono,
                                 activa: i == highlight)
            },
            dominio: dominio,
            ticksY: nivelesMarcasY(d, dominio: dominio),
            tono: tono,
            // Hoy = el último punto dibujado (paridad marksLastPoint/markedPointHollow
            // :144-145): anillo hueco mientras exploras un nivel que no es el de hoy.
            puntoHoy: d.activeIndex != nil ? puntos.last : nil,
            hoyAnillo: nivelExplorado != nil && nivelExplorado != d.activeIndex,
            formatoScrub: { (v: Double, f: Date) in
                "\(self.scrubValor(v)) · \(Self.diaCorto(f))"
            },
            formatoValorScrub: popupValor,
            formatoFechaScrub: popupFecha,
            formatoFechaEje: ejeFmt,
            // D12 (A4) · Los puntos se apagan SOLO cuando el usuario explora un carril
            // (paridad `GraficaRangos`). Antes se apagaban con la sola existencia de una
            // lectura de hoy, sin que nadie hubiera pedido nada.
            atenuarFuera: nivelExplorado != nil,
            estadoVacio: String(localized: "No readings in this range."),
            a11yLabel: tituloHoja)
    }

    /// Dominio Y del explorador (paridad `chartDomain` :163-173: umbrales + serie con
    /// respiro 10/12 %; la hoja siempre pasa dominio automático).
    private func nivelesDominio(_ d: MetricLevels.Classification,
                                values: [Double]) -> ClosedRange<Double> {
        // El dominio cubre TUS DATOS más los cortes de la banda ACTIVA — no toda la
        // escala (/inject: en FC en reposo los umbrales llegan a 80 mientras los datos
        // viven en 50–62, así que la mitad de arriba de la gráfica salía vacía y la
        // línea aplastada abajo). Con esto la pregunta que la gráfica contesta —«¿dónde
        // caigo dentro de mi banda?»— se sigue leyendo, y sin desperdiciar alto.
        //
        // B1 · «La banda ACTIVA» son DOS: la del usuario (el carril que TOCÓ) unida a la de
        // hoy. Con solo la de hoy, tocar «Elevada ≥ 80» sobre una serie de 50–62 dejaba el
        // dominio en 48.8–63.4 y `LiquidChartPlot.washes` clampeaba esa franja a alto 0:
        // el toque encendía `atenuarFuera`, todos los puntos bajaban al 25 % y la gráfica
        // quedaba gris y vacía mientras el a11yHint prometía «Resalta este nivel en la
        // gráfica». La unión (y no el reemplazo) también evita que la escala se dispare al
        // explorar y vuelva de golpe: crece una sola vez y regresa al soltar.
        let indices: [Int] = Set([nivelDestacado(d), d.activeIndex].compactMap { $0 }).sorted()
        let destacados: [MetricLevels.Level] = indices
            .filter { d.levels.indices.contains($0) }
            .map { d.levels[$0] }
        let bounds: [Double] = destacados.isEmpty
            ? d.levels.flatMap { [$0.lower, $0.upper].compactMap { $0 } }
            : destacados.flatMap { [$0.lower, $0.upper].compactMap { $0 } }
        let pool = bounds + values
        guard let lo0 = pool.min(), let hi0 = pool.max(), hi0 > lo0 else {
            let v = values.first ?? bounds.first ?? 0
            return (v - 1)...(v + 1)
        }
        let span = max(hi0 - lo0, 0.0001)
        return (lo0 - span * 0.1)...(hi0 + span * 0.12)
    }

    /// Ticks en los umbrales de nivel (paridad `yTicks` :175-178).
    private func nivelesTicks(_ d: MetricLevels.Classification) -> [Double] {
        Set(d.levels.flatMap { [$0.lower, $0.upper].compactMap { $0 } }).sorted()
    }

    /// D3 · Las marcas del eje Y. La UNIDAD vuelve al eje —se había perdido: decía «60»
    /// donde la hoja vieja decía «60 lpm»— pero SOLO en la marca de arriba: repetirla en
    /// cada tick es ruido de gráfica y la canaleta se ensancha por la etiqueta más larga.
    /// El signo de temperatura de piel lo trae ya `levelsValueFormat` («+0.4»).
    private func nivelesMarcasY(_ d: MetricLevels.Classification,
                                dominio: ClosedRange<Double>)
        -> [(valor: Double, etiqueta: String)] {
        // Solo las marcas que CAEN en el dominio visible (/inject): al acotar el dominio,
        // los umbrales de fuera se dibujaban pegados al borde y el eje mentía («18» en una
        // gráfica que llega a 14.5).
        let ticks: [Double] = nivelesTicks(d).filter { dominio.contains($0) }
        let ultimo: Int = ticks.count - 1
        return ticks.indices.map { (i: Int) -> (valor: Double, etiqueta: String) in
            let v: Double = ticks[i]
            let etiqueta: String = i == ultimo ? scrubValor(v) : levelsValueFormat(v)
            return (valor: v, etiqueta: etiqueta)
        }
    }

    /// La lista de carriles. El chrome (separadores sangrados, esquinas, vidrio) vive en
    /// `LiquidLevelsList`, del DS: estaba copiado aquí, en los previews y en el arnés de
    /// renders, y las copias se separaron (los PNG enseñaban filas sueltas con el wash a
    /// sangre). Aquí queda solo la traducción de `MetricLevels` a filas.
    private func nivelesLista(_ d: MetricLevels.Classification,
                              conteos: Bool = true) -> some View {
        let highlight: Int? = nivelDestacado(d)
        let hoyRotulo: String = String(localized: "· today")
        let hint: String = String(localized: "Highlights this level on the chart")
        let filas: [LiquidLevelsList.Fila] = d.levels.indices
            .map { (i: Int) -> LiquidLevelsList.Fila in
                let nivel: MetricLevels.Level = d.levels[i]
                return LiquidLevelsList.Fila(
                    etiqueta: nombreNivel(nivel.key),
                    rango: rangoNivel(nivel),
                    // D7 · Sin serie todavía, la columna queda VACÍA (su ancho mínimo ya
                    // está reservado, así que no salta cuando llegan los conteos).
                    conteo: conteos ? conteoLabel(d.counts[i]) : "",
                    esHoy: i == d.activeIndex,
                    activa: i == highlight,
                    // El rótulo que marca EN LA LISTA dónde cayó hoy (clave existente).
                    hoyEtiqueta: hoyRotulo,
                    a11yHint: hint,
                    onTap: {
                        // Tocar la fila destacada limpia de vuelta a hoy (paridad :197-200).
                        // Reduce Motion / renders congelados: el cambio es instantáneo.
                        if reduceMotion || motionDisabled {
                            nivelExplorado = (nivelExplorado == i) ? nil : i
                        } else {
                            withAnimation(LiquidMotion.lift) {
                                nivelExplorado = (nivelExplorado == i) ? nil : i
                            }
                        }
                    })
            }
        return LiquidLevelsList(filas: filas, tono: tono)
    }

    /// Rango numérico de un nivel, half-open (paridad `rangeText` :240-247).
    private func rangoNivel(_ nivel: MetricLevels.Level) -> String {
        switch (nivel.lower, nivel.upper) {
        case let (nil, hi?):  return "< \(levelsValueFormat(hi))"
        case let (lo?, nil):  return "≥ \(levelsValueFormat(lo))"
        case let (lo?, hi?):  return "\(levelsValueFormat(lo))–\(levelsValueFormat(hi))"
        case (nil, nil):      return ""
        }
    }

    /// «N días/noches» (paridad `BandSummaryCopy.countLabel`, dicho en String — mismas
    /// claves con singular/plural).
    private func conteoLabel(_ n: Int) -> String {
        if nightly {
            return n == 1 ? String(localized: "\(n) night") : String(localized: "\(n) nights")
        }
        return n == 1 ? String(localized: "\(n) day") : String(localized: "\(n) days")
    }

    /// D6 · Las cinco submétricas de sueño hablan EXCLUSIVAMENTE de anoche, pero no están en
    /// `BandSummaryCopy.isNightly`, así que la hoja entera —frase de nivel, conteos por fila
    /// y el aviso de ventana— decía «días». Se extiende aquí, caller-side: el archivo
    /// compartido es de otro carril y esta hoja es hoy su único consumidor.
    private var nightly: Bool {
        BandSummaryCopy.isNightly(metricID: datoInfo.id) || datoInfo.id.hasPrefix("sleep_")
    }

    /// El nombre localizado de un nivel, del único hogar clave→nombre (FER-731; la clave
    /// inglesa ES la del catálogo, paridad `label` del explorador :253-255).
    private func nombreNivel(_ key: String) -> String {
        String(localized: String.LocalizationValue(MetricLevels.name(for: key)))
    }

    /// Formato del valor en el explorador (paridad :727-732): sueño h/min, piel una
    /// décima, resto entero.
    /// Enteros con separador de miles en el locale del usuario.
    private static let milesFmt: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f
    }()

    private func levelsValueFormat(_ v: Double) -> String {
        switch datoInfo.id {
        case "sleep":
            // Reloj SIEMPRE con horas y minutos (pedido del dueño /inject): «7:00», no
            // «7h» — y es el mismo formato del numeral de la hoja, así el eje y el dato
            // hablan igual.
            let h = Int(v) / 60, m = Int(v) % 60
            return String(format: "%d:%02d", h, m)
        case "skin_temp":
            // D3 · CON signo: la temperatura de piel es una DESVIACIÓN de tu base, y el
            // numeral del héroe la imprime «+0.4» (`MetricInfoCatalog`). Sin el «+», el eje,
            // el popup del scrub y los rangos de las filas decían «0.4» y la hoja se
            // contradecía consigo misma.
            return String(format: "%+.1f", v)
        case "steps":
            // Con separador de miles, igual que el numeral (/inject: el dato decía «8,432»
            // y el eje «10000» — el mismo número escrito de dos maneras).
            return Self.milesFmt.string(from: NSNumber(value: Int(v.rounded())))
                ?? "\(Int(v.rounded()))"
        case "stress":
            // B3 · Con una décima, como el numeral del héroe («1.2 / 3»): redondeado a
            // entero, la hoja decía «1.2 / 3» arriba, «1–2» en las filas y «1 / 3» en el
            // chip del scrub — el mismo número escrito de tres maneras sobre una escala de
            // 0 a 3, donde la décima ES la resolución del dato. (Respiración se queda en
            // entero a propósito: sus cortes son enteros y «< 20.0» sería precisión falsa.)
            return String(format: "%.1f", v)
        default:
            return "\(Int(v.rounded()))"
        }
    }

    /// El valor del chip de scrub: formato + unidad (paridad explorador :139).
    private func scrubValor(_ v: Double) -> String {
        "\(levelsValueFormat(v)) \(datoInfo.unit ?? "")"
            .trimmingCharacters(in: .whitespaces)
    }

    // MARK: Pie (paridad `sheetFoot` :251-269)

    // D1 · TODO el pie lee `datoInfo`, el dato que la hoja MUESTRA. Con el `info` real, en
    // demo la cabecera decía «56 ms» y la nota «No hubo VFC anoche» dos bloques más abajo
    // (`nota(_:)` re-deriva la variante con/sin dato de `displayValue == "—"`). Fuera de
    // demo `datoInfo == info`: el cambio es un no-op en producción.
    @ViewBuilder private var pie: some View {
        if let metodo = LiquidSheetCopy.metodo(datoInfo) {
            LiquidMetodo(title: String(localized: "How it's calculated"),
                         // D11 (B6) · Etiquetas propias de VoiceOver: antes leía «Cómo se
                         // calcula, uno». Distintas de las del ⓘ de la cabecera a propósito
                         // — son dos plegables diferentes en la misma hoja.
                         mostrar: String(localized: "Show method"),
                         ocultar: String(localized: "Hide method")) {
                LiquidNotaLine(metodo.prosa)
                if let cita = metodo.cita {
                    LiquidNotaLine(cita)
                }
            }
        }
        // D1 · `appleConnectHint` lo resuelve TodayView contra el `info` REAL, así que en
        // demo el aviso salía junto a un dato visible («conéctalo desde Hoy» bajo «56 ms»).
        if appleConnectHint && !demo {
            avisoConectarApple
        } else if let nota = LiquidSheetCopy.nota(datoInfo) {
            LiquidNotaLine(nota)
        }
        if let disclaimer = LiquidSheetCopy.disclaimer(datoInfo) {
            LiquidNotaLine(disclaimer)
        }
        // Línea de procedencia del pie RETIRADA (decisión del dueño /inject 2026-07-23):
        // el origen ya se dice arriba, en la etiqueta del header («Apple Salud · anoche»).
        if let onSeeMore { verMas(onSeeMore) }
    }

    /// D5 · El ÚNICO aviso accionable de la hoja: «esto puede venir de Apple Salud y no
    /// está conectado». Compartía el `LiquidNotaLine` de la nota, la cita del método y el
    /// disclaimer, así que se leía como letra chica. Recupera su superficie propia —gota de
    /// corazón + tinta de atención sobre vidrio—, como la tarjeta con glifo y borde de la
    /// hoja vieja. Todo caller-side, con API pública existente.
    private var avisoConectarApple: some View {
        HStack(alignment: .firstTextBaseline, spacing: LiquidSpace.s300) {
            LiquidIconDrop(.corazon, tone: LiquidColor.rosa, size: 20, iconSize: 11)
            LiquidNotaLine(String(localized: "This reading can come from Apple Health. Connect it from Today to see it here."),
                           tono: LiquidColor.atencionTexto)
        }
        .padding(LiquidSpace.s300)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(.superficie)
    }

    /// «Ver más» (paridad `seeMoreLink` :1186-1231): ancho completo hacia Tendencias
    /// para métricas con niveles, pastilla compacta para el resto.
    @ViewBuilder private func verMas(_ action: @escaping () -> Void) -> some View {
        if datoInfo.usesLevels {
            LiquidVerMas(title: String(localized: "See more in Trends"),
                         hint: String(localized: "Opens the full detail"),
                         tone: tono, anchoCompleto: true, action: action)
        } else {
            LiquidVerMas(title: String(localized: "See more"),
                         hint: String(localized: "Opens the full detail"),
                         tone: tono, action: action)
        }
    }
}

// MARK: - LiquidSheetCopy — claves del catálogo dichas en String
//
// `MetricInfo` entrega `LocalizedStringKey` (name/headline/note/method), del que no se
// puede extraer la clave. El compositor replica las MISMAS claves literales de
// `MetricInfoCatalog` con `String(localized:)` — cero copy nuevo, cero entradas nuevas
// en el catálogo. La PRESENCIA (qué hoja lleva nota/método/disclaimer) la decide el
// modelo (`info.note != nil`, …); este mapa solo resuelve el contenido.
// F6 puede migrar `MetricInfo` a String y borrar este archivo de claves.

private enum LiquidSheetCopy {

    /// `info.name` — mismas claves (en es-MX «HRV» ya dice «VFC»).
    static func titulo(_ id: String) -> String {
        switch id {
        case "sleep":             return String(localized: "Sleep")
        case "hrv":               return String(localized: "HRV")
        case "rhr":               return String(localized: "Resting HR")
        case "strain":            return String(localized: "Day Strain")
        case "steps":             return String(localized: "Steps")
        case "skin_temp":         return String(localized: "Skin Temperature")
        case "resp_rate":         return String(localized: "Respiratory Rate")
        case "stress":            return String(localized: "Stress")
        case "spo2":              return String(localized: "Blood Oxygen")
        case "heart_rate":        return String(localized: "Heart Rate")
        case "vo2max":            return String(localized: "VO₂ Max")
        case "sleep_performance": return String(localized: "Performance")
        case "sleep_efficiency":  return String(localized: "Efficiency")
        case "sleep_restorative": return String(localized: "Restorative")
        case "sleep_awakenings":  return String(localized: "Awakenings")
        case "sleep_latency":     return String(localized: "Latency")
        default:
            // B10 · Este `default` es un bug silencioso, no un fallback: una fábrica nueva
            // imprimiría «vo2max» como TÍTULO de la hoja y nadie se enteraría hasta verlo
            // en pantalla. Se avisa, no se aborta: un `assertionFailure` dentro de algo que
            // se evalúa en `body` mata la app en DEBUG — justo el build de las sesiones
            // /inject. (La migración de fondo es F6.)
            #if DEBUG
            print("LiquidSheetCopy · id sin titulo: \(id)")
            #endif
            return id
        }
    }

    /// `info.headline` — mismas claves.
    static func headline(_ info: MetricInfo) -> String {
        switch info.id {
        case "strain":
            return String(localized: "Cardiovascular load scored 0–21. Each second of the day your heart rate is recorded, it's assigned to a zone (1–5). Higher zones carry more weight. The total is compressed logarithmically so 21 represents a theoretical maximum: a full day at peak intensity.")
        case "sleep":
            return String(localized: "Total time asleep last night, estimated from movement and heart rate. Sleep is one of the signals behind your daily verdict.")
        case "hrv":
            return String(localized: "HRV is how much the time between your heartbeats varies, in milliseconds, while you sleep. More variation usually means a nervous system that's better rested. What matters isn't the number itself, but how it compares with your own average.")
        case "rhr":
            return String(localized: "Your heart rate when your body is fully at rest: how hard your heart has to work doing nothing. Lower generally means a stronger, more efficient cardiovascular system. Cénit reads it against your own norm as part of your daily verdict; a rise can signal fatigue or that something's coming on.")
        case "resp_rate":
            return String(localized: "How many breaths you take per minute while you sleep. It's one of the steadiest signals your body has, so even a small rise from your own normal can be an early sign of strain, illness, or a late, heavy meal.")
        case "sleep_performance":
            return String(localized: "How much you slept versus what your body needs. At 100% you fully covered last night's need.")
        case "sleep_efficiency":
            return String(localized: "Of the time you spent in bed, how much you actually spent asleep. Above about 85% is considered healthy.")
        case "sleep_restorative":
            return String(localized: "The share of your sleep spent in deep and REM: the stages that physically and mentally restore you. Around 40–50% is typical for a healthy adult.")
        case "sleep_awakenings":
            return String(localized: "How many times you briefly woke during the night. A few are completely normal: everyone surfaces between sleep cycles.")
        case "sleep_latency":
            return String(localized: "How long it took you to fall asleep after lights out. Ten to twenty minutes is a healthy range.")
        case "spo2":
            return String(localized: "Percentage of haemoglobin carrying oxygen in your blood. Healthy adults typically stay above 95%. A drop can indicate altitude effects, sleep apnea, or respiratory illness.")
        case "skin_temp":
            return String(localized: "The temperature of your skin, read at your wrist while you sleep. It shifts with your circadian rhythm. What matters isn't the number itself, but how far it sits from your own baseline. A sustained rise can be an early sign of inflammation or a coming illness; that's why it's one of the signals behind your daily verdict.")
        case "vo2max":
            return String(localized: "The most oxygen your body can use during hard exercise, per kilo of body weight. It's the single best measure of cardiorespiratory fitness, and one of the best-evidenced predictors of long-term health.")
        case "steps":
            return String(localized: "Daily step count. Consistent activity, even a 30-minute walk, supports cardiovascular health and mood. It's context for your day: it doesn't move your daily verdict or your load balance.")
        case "stress":
            return String(localized: "Your autonomic load today, from 0 to 3. We estimate it by comparing today's resting heart rate and HRV with your own 30-day baseline: a higher-than-usual resting HR and a lower-than-usual HRV both push the number up: classic signs your body is activated.")
        case "heart_rate":
            return String(localized: "Your heart rate across the day, averaged in 5-minute buckets.")
        default:
            return ""
        }
    }

    /// `info.note` — mismas claves; la variante con/sin dato se re-deriva del
    /// `displayValue` (así eligió la factory). Presencia gobernada por `info.note != nil`.
    static func nota(_ info: MetricInfo) -> String? {
        guard info.note != nil else { return nil }
        let sinDato = info.displayValue == "—"
        switch info.id {
        case "hrv":
            return sinDato
                ? String(localized: "No HRV from last night. That can happen if you didn't wear your Apple Watch to sleep, or the night was too short for it to record.")
                : String(localized: "HRV is personal. There are no universal good/bad thresholds: only your trend over time.")
        case "rhr":
            return String(localized: "Measured overnight from your Apple Watch's heart rate; when it isn't worn to sleep, Cénit uses Apple Health's resting heart rate instead.")
        case "resp_rate":
            return String(localized: "Measured overnight from your heart rate during sleep. What matters is the change from your own baseline, not the absolute number.")
        case "sleep_performance":
            return String(localized: "Your need is your own rolling average of recent nights, never under 7.5 h.")
        case "sleep_awakenings":
            return String(localized: "Brief awakenings are normal and often not remembered. What matters is the trend, not a single night.")
        case "sleep_latency":
            return sinDato
                ? String(localized: "Onset time isn't available for this night yet. The range above is the healthy reference.")
                : String(localized: "One night says little on its own. What matters is whether your typical onset drifts over weeks.")
        case "spo2":
            return String(localized: "Blood oxygen comes from Apple Health. Wrist-based sensors have lower accuracy than medical pulse oximeters: treat values as a trend, not a clinical reading.")
        case "skin_temp":
            return sinDato
                ? String(localized: "No skin temperature last night. That can happen if you didn't wear your Apple Watch to sleep, or it hasn't gathered enough nights to set your baseline yet.")
                : String(localized: "Measured at your wrist; the deviation from your personal baseline matters more than the absolute value. An isolated reading is usually noise, like a cold room or how the sensor sat. A sustained run is what's worth a look.")
        case "vo2max":
            return String(localized: "Measured by your Apple Watch during outdoor walks and runs.")
        case "steps":
            return String(localized: "Steps come from Apple Health.")
        case "stress":
            return String(localized: "Derived from your overnight resting heart rate and HRV: a transparent proxy for autonomic load, not a clinical stress measure.")
        default:
            return nil
        }
    }

    /// `info.disclaimer` — solo recovery la trae hoy.
    static func disclaimer(_ info: MetricInfo) -> String? {
        guard info.disclaimer != nil else { return nil }
        return String(localized: "It's an estimate, not a diagnosis.")
    }

    /// `info.method` — mismas claves (prosa + cita). Presencia gobernada por
    /// `info.method != nil` (recovery calibrando NO lo trae, paridad de la factory).
    static func metodo(_ info: MetricInfo) -> (prosa: String, cita: String?)? {
        guard info.method != nil else { return nil }
        switch info.id {
        case "hrv":
            return (String(localized: "The number you see is the HRV Apple records: SDNN, the overall spread of the time between your heartbeats. Your daily verdict reads this same signal against your own baseline. The trend uses a different HRV measure, RMSSD, recomputed from the beat-to-beat intervals of your densest nights; RMSSD tracks the vagal, rest-and-repair branch specifically, while SDNN blends both branches, so the two won't always move together."),
                    String(localized: "SDNN and RMSSD (Task Force, 1996); RMSSD is the vagal recovery measure (Shaffer & Ginsberg, 2017)."))
        case "resp_rate":
            return (String(localized: "We count your breaths across the night from the slow rise and fall in your heart-rate signal (respiratory sinus arrhythmia) and report the nightly mean."),
                    String(localized: "Respiration from RSA in the overnight inter-beat intervals; reported as the nightly mean."))
        case "spo2":
            return (String(localized: "Cénit reads your blood oxygen from Apple Health; the Apple Watch senses it optically at the wrist. A healthy adult typically sits at 95–100%; readings below 90% are considered low (hypoxemia). Isolated low nights are usually noise, altitude, a cold, or how the sensor sat. A sustained run of low nights is what's worth a look with a finger pulse oximeter."),
                    String(localized: "Wrist optical sensors are less accurate than medical pulse oximeters: read this as a trend, not a clinical measurement. Cénit is not a medical device."))
        case "skin_temp":
            return (String(localized: "Your Apple Watch reads your skin temperature through the night; Cénit averages the worn, asleep portion and compares it with your own recent baseline, so what you see is the deviation in °C, not a raw temperature. Around your base is normal; a sustained rise of roughly +0.4 °C or more is a classic early illness marker, so Cénit flags it as running warm (~+0.4 °C) or well above (~+0.8 °C)."),
                    String(localized: "Baseline-relative skin temperature as an early illness signal (cf. Oura ~+0.5 °C). A wrist trend, not a clinical thermometer. Cénit is not a medical device."))
        case "vo2max":
            return (String(localized: "Your Apple Watch estimates VO₂max from your heart rate and pace during brisk outdoor walks and runs with a good GPS signal, so it updates every so often rather than daily. We read where it sits among healthy adults of your age and sex (the FRIEND reference median), and translate that into a plain band. A higher VO₂max is associated with a lower risk of all-cause mortality: it's one of the best-evidenced markers of long-term health."),
                    String(localized: "Reference: Kaminsky et al., FRIEND Registry (Mayo Clin Proc 2015). Longevity association: Mandsager et al. (JAMA 2018), Kodama et al. (JAMA 2009). A coarse population reference, not a clinical measurement: Cénit is not a medical device."))
        case "steps":
            return (String(localized: "Steps come from Apple Health. The detail reads each day's total and smooths it into a 7-day trend, so weekday/weekend swings don't drown out the direction you're heading. Research links roughly 7,000–9,000 steps a day with lower mortality, with the benefit leveling off beyond that: there is nothing magic about exactly 10,000."),
                    String(localized: "Paluch et al. 2022, Lancet Public Health."))
        case "stress":
            return (String(localized: "We take today's resting heart rate and HRV and express each as how far it sits from your 30-day average (a z-score). A resting HR above your norm and an HRV below it both add to the load; the two are summed and squashed onto a 0–3 scale where 0 is calm, 1.5 is your baseline, and 3 is highly activated."),
                    String(localized: "Combined resting-HR / HRV z-score through a logistic curve; HRV via RMSSD (Task Force, 1996)."))
        case "heart_rate":
            return (String(localized: "We average your heart rate in 5-minute buckets across the day, from midnight. Your resting heart rate, the low while you sleep, is its own metric. The zones split the day by how hard your heart worked, as a percentage of your estimated maximum heart rate (zone 1 is 50–60%, zone 5 is 90–100%)."),
                    String(localized: "Max HR estimated by Tanaka et al. (2001): 208 − 0.7 × age."))
        default:
            return nil
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("LiquidMetricSheetView: HRV") {
    Color.clear.sheet(isPresented: .constant(true)) {
        LiquidMetricSheetView(info: .hrv(56))
    }
}
#endif
