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

    init(info: MetricInfo,
         appleConnectHint: Bool = false,
         appleSource: Bool = false,
         heartRateCurveLoader: (() async -> [TrendPoint])? = nil,
         trendLoader: (() async -> [TrendPoint])? = nil,
         onSeeMore: (() -> Void)? = nil,
         levelsSeriesLoader: (() async -> [(day: String, value: Double)])? = nil,
         whatMovesIt: [WhatMovesItFinding] = [],
         sleepDetail: SleepDetailModel? = nil) {
        self.info = info
        self.appleConnectHint = appleConnectHint
        self.appleSource = appleSource
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
    private var demo: Bool { true }

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
        case "recovery":  return .recovery(score: 78, calibrationNights: nil, nightsNeeded: 4)
        case "vo2max":    return .vo2max(42)
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
        LiquidMetricSheet(tono: tono, detent: detent) {
            cabecera
            cuerpo
            pie
        }
        .task {
            // Modo DEMO (/inject 2026-07-23): siembra datos de muestra para pulir la hoja
            // en un simulador sin datos de Apple Salud. Apagar antes de cerrar la sesión.
            if demo {
                heartRateCurve = Self.demoCurva()
                trendData = Self.demoTrend(info.id)
                levelsHost.load(rows: Self.demoRows(info.id))
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

    private var isRecoverySummary: Bool {
        datoInfo.id == "recovery" && datoInfo.calibration == nil && datoInfo.displayValue != "—"
    }
    private static let vitalTemplateIDs: Set<String> =
        ["hrv", "rhr", "spo2", "skin_temp", "steps", "stress", "resp_rate"]
    private var isVitalTemplate: Bool {
        datoInfo.usesLevels && Self.vitalTemplateIDs.contains(datoInfo.id)
    }
    /// F5 (comportamiento NUEVO, contrato §1.3): el modelo de sueño se construye off-main;
    /// mientras no llega, skeleton — la hoja vieja caía al layout clásico.
    // En demo NO se queda en el esqueleto: sin modelo de noche cae a la variante clásica
    // de sueño (numeral + niveles), que sí se puede pulir.
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
        if isRecoverySummary {
            recoveryContent
        } else if isVitalTemplate {
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

    // MARK: Cabecera

    /// Recovery y strain: «/ 100» · «/ 21» solo con score real (paridad :369-373).
    private var sufijo: String? {
        if datoInfo.id == "recovery" { return isRecoverySummary ? "/ 100" : nil }
        if datoInfo.id == "strain" { return datoInfo.displayValue != "—" ? "/ 21" : nil }
        return nil
    }

    /// D3 — origen honesto Apple-only: calculado en el teléfono (recovery/strain/stress)
    /// o medido por Apple Salud; sin procedencia clara, sin punto (nunca «Band»).
    private var origen: LiquidOrigen? {
        if ["recovery", "strain", "stress"].contains(datoInfo.id) { return .calculado }
        if appleSource { return .medido }
        return nil
    }

    private var origenEtiqueta: String? {
        if ["recovery", "strain", "stress"].contains(datoInfo.id) {
            return String(localized: "Calculated")
        }
        if appleSource { return String(localized: "Apple Health") }
        return nil
    }

    private var cabecera: some View {
        LiquidSheetHeader(
            icono: glifo,
            titulo: LiquidSheetCopy.titulo(datoInfo.id),
            tono: tono,
            // La variante rica de sueño (y su skeleton) reemplazan el numeral con el
            // doble dato (paridad :333).
            numeral: (isSleepRich || isSleepLoading) ? nil : datoInfo.displayValue,
            unidad: datoInfo.unit,
            sufijo: sufijo,
            numeralTono: tinte(datoInfo.headerTint),
            origen: origen,
            origenEtiqueta: origenEtiqueta,
            explicacion: LiquidSheetCopy.headline(info),
            // L5.1 — el ⓘ se nombra solo en VoiceOver (antes leía «VFC, uno»).
            infoMostrar: String(localized: "Show explanation"),
            infoOcultar: String(localized: "Hide explanation"))
    }

    // MARK: Recovery (§1.1 — lectura + medidor de zonas + niveles)

    @ViewBuilder private var recoveryContent: some View {
        if let frase = recoveryReadingText {
            LiquidReadingLine(frase)
        }
        recoveryZoneMeter
        levelsBlock
    }

    /// Paridad `recoveryReadingText` (:615-622) — mismas claves.
    private var recoveryReadingText: String? {
        switch datoInfo.headerTint {
        case .good: return String(localized: "Above your baseline, ready for a strong day.")
        case .warn: return String(localized: "Recovering, train but keep it controlled.")
        case .bad:  return String(localized: "Low, prioritize rest today.")
        default:    return nil
        }
    }

    /// Paridad `recoveryZoneMeter` (:629-659): las 5 zonas canónicas de `MetricLevels`
    /// (pesos 25/25/20/18/12) sobre los 3 roles de color, tick en score/100 y rótulos
    /// del único hogar clave→nombre (FER-731/638).
    private var recoveryZoneMeter: some View {
        let niveles = MetricLevels.levels(for: .recovery)
        let score = datoInfo.levelsTodayValue ?? 0
        let activo = MetricLevels.activeIndex(for: score, in: niveles)
        let segmentos = niveles.enumerated().map { (i, lvl) in
            LiquidZoneMeter.Segmento(
                peso: (lvl.upper ?? 100) - (lvl.lower ?? 0),
                color: Self.zonaColor(i),
                activa: i == activo,
                etiqueta: nombreNivel(lvl.key).localizedUppercase)
        }
        return LiquidZoneMeter(segmentos: segmentos, fraccion: score / 100)
    }

    /// Paridad `recoveryZoneColor` (:645-651): agotado/bajo → negativo, moderado →
    /// atención, alto/pleno → positivo — 5 zonas sobre 3 roles, sin tokens nuevos.
    private static func zonaColor(_ index: Int) -> Color {
        switch index {
        case 0, 1: return LiquidColor.negativo
        case 2:    return LiquidColor.atencion
        default:   return LiquidColor.positivo
        }
    }

    // MARK: Vital-template (§1.2 — lectura + niveles + patrón)

    @ViewBuilder private var vitalContent: some View {
        if let frase = vitalReadingText {
            LiquidReadingLine(frase)
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
            LiquidReadingLine(frase)
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
            LiquidDobleDato(
                principal: (valor: Self.sleepHM(night.stages.asleep),
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
            LiquidStageBar(
                etapas: sleepEtapas(night),
                overline: String(localized: "Last night"),
                ventana: "\(Self.clock(night.startTs)) → \(Self.clock(night.endTs))")
            // `LiquidLaneLabel` RETIRADO (L3.3): la frase display de los niveles ya dice el
            // nombre del carril en grande — la pastilla lo repetía dos bloques más abajo.
            levelsBlock
            // «Para esta noche» RETIRADO (decisión del dueño, /inject 2026-07-23):
            // la hoja de sueño cierra con los niveles.
        }
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
            // «Despierto» ya no es gris (pedido del dueño /inject): ámbar claro — es la
            // única etapa que NO es sueño, y el gris la volvía parte del fondo.
            .init(minutos: night.stages.awake, color: LiquidColor.ambarClaro,
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
    private var sleepReadingText: String? {
        switch activeLevelKey {
        case "optimal":  return String(localized: "Right in your target range.")
        case "adequate": return String(localized: "Enough, close to your target.")
        case "short":    return String(localized: "Short of your target last night.")
        case "extended": return String(localized: "Longer than usual last night.")
        default:         return nil
        }
    }

    /// «7:12» desde minutos (paridad `sleepHM` :510-512).
    private static func sleepHM(_ minutes: Double) -> String {
        let m = Int(minutes.rounded())
        return String(format: "%d:%02d", m / 60, m % 60)
    }

    /// Reloj local «23:38» desde un unix timestamp (paridad `clock` :514-518).
    private static func clock(_ ts: Int) -> String {
        clockFmt.string(from: Date(timeIntervalSince1970: TimeInterval(ts)))
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
        // Nota de paridad: `bandedTrend` (:1056-1093) es INALCANZABLE aquí — su set
        // {sleep, stress, spo2, rhr, steps} es subconjunto de `usesLevels`, que va por
        // niveles; toda métrica que llega al trend clásico (submétricas de sueño, vo2max)
        // pinta la curva plana auto-escalada, igual que hoy. Las bandas viven en la tabla.
        // Fuera del call: el type-checker de iOS se atora con expresiones largas dentro de
        // un builder (ver la nota de `curvaEstado`).
        let puntos: [(fecha: Date, valor: Double)] =
            trendData.map { (p: TrendPoint) in (fecha: p.date, valor: p.value) }
        let ejeFmt: (Date) -> String = Self.ejeFechaFmt(puntos)
        let popupFecha: (Date) -> String = { (d: Date) -> String in Self.popupDiaFmt.string(from: d) }
        let popupValor: (Double) -> String = { (v: Double) -> String in self.trendValueFormat(v) }
        let marcasY: [(valor: Double, etiqueta: String)] =
            Self.ticksY(trendData.map(\.value), formato: popupValor)
        return LiquidTrendChart(
            titulo: String(localized: "Last 14 days"),
            readout: trendReadout,
            puntos: puntos,
            bandas: [],
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

    private var trendEstado: LiquidChartEstado {
        if trendData.count > 1 { return .datos }
        if trendLoading { return .cargando }
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
    private var trendValueRange: ClosedRange<Double> {
        let vals = trendData.map(\.value)
        guard let lo = vals.min(), let hi = vals.max() else { return 0...100 }
        let span = max(hi - lo, 1)
        let pad = span * 0.15
        return max(0, lo - pad)...hi + pad
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
    private static func ticksY(_ vals: [Double],
                               formato: (Double) -> String) -> [(valor: Double, etiqueta: String)] {
        guard let lo = vals.min(), let hi = vals.max(), hi > lo else { return [] }
        let medio: Double = (lo + hi) / 2
        return [lo, medio, hi].map { (v: Double) -> (valor: Double, etiqueta: String) in
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
        let marcasY: [(valor: Double, etiqueta: String)] =
            Self.ticksY(v, formato: { (val: Double) -> String in "\(Int(val.rounded()))" })
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
                if window.fellBack {
                    // Auto-widen (paridad MetricLevelsExplorer:105-108). Va en
                    // `atencionTexto`, no en tinta quieta: AVISA que la ventana que estás
                    // leyendo no es la que pediste en el selector.
                    LiquidNotaLine(String(localized: "Showing the last \(window.rows.count) days"),
                                   tono: LiquidColor.atencionTexto)
                }
                nivelesFrase(d)
                nivelesGrafica(d, window: window)
                nivelesLista(d)
            }
        } else if datoInfo.levelsRelative {
            // HRV sin base propia todavía — nota honesta (paridad :737-741).
            LiquidNotaLine(String(localized: "Your levels come from your own baseline: a few more nights and they'll appear."))
        }
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
            LiquidFraseNivel(nivel: nombre, conteo: conteo, tono: tono)
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
        return LiquidGraficaNiveles(
            puntos: puntos,
            bandas: d.levels.enumerated().map { (i, lvl) in
                LiquidChartBanda(lo: lvl.lower, hi: lvl.upper, color: tono,
                                 activa: i == highlight)
            },
            dominio: nivelesDominio(d, values: window.values),
            ticksY: nivelesTicks(d).map { (valor: $0, etiqueta: levelsValueFormat($0)) },
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
            estadoVacio: String(localized: "No readings in this range."),
            a11yLabel: LiquidSheetCopy.titulo(datoInfo.id))
    }

    /// Dominio Y del explorador (paridad `chartDomain` :163-173: umbrales + serie con
    /// respiro 10/12 %; la hoja siempre pasa dominio automático).
    private func nivelesDominio(_ d: MetricLevels.Classification,
                                values: [Double]) -> ClosedRange<Double> {
        let bounds = d.levels.flatMap { [$0.lower, $0.upper].compactMap { $0 } }
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

    private func nivelesLista(_ d: MetricLevels.Classification) -> some View {
        let highlight = nivelDestacado(d)
        return VStack(spacing: 0) {
            ForEach(Array(d.levels.enumerated()), id: \.offset) { (i, nivel) in
                LiquidLevelRow(
                    etiqueta: nombreNivel(nivel.key),
                    rango: rangoNivel(nivel),
                    conteo: conteoLabel(d.counts[i]),
                    esHoy: i == d.activeIndex,
                    activa: i == highlight,
                    tono: tono,
                    // El rótulo que marca EN LA LISTA dónde cayó hoy (clave existente).
                    hoyEtiqueta: String(localized: "· today"),
                    a11yHint: String(localized: "Highlights this level on the chart"),
                    onTap: {
                        // Tocar la fila destacada limpia de vuelta a hoy (paridad :197-200).
                        withAnimation(LiquidMotion.lift) {
                            nivelExplorado = (nivelExplorado == i) ? nil : i
                        }
                    })
                if i < d.levels.count - 1 {
                    Rectangle()
                        .fill(LiquidColor.tinta10)
                        .frame(height: 1)
                        .padding(.leading, LiquidSpace.s400 + 8 + LiquidSpace.s300)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: LiquidRadius.tarjeta, style: .continuous))
        .liquidGlass(.superficie)
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

    private var nightly: Bool { BandSummaryCopy.isNightly(metricID: datoInfo.id) }

    /// El nombre localizado de un nivel, del único hogar clave→nombre (FER-731; la clave
    /// inglesa ES la del catálogo, paridad `label` del explorador :253-255).
    private func nombreNivel(_ key: String) -> String {
        String(localized: String.LocalizationValue(MetricLevels.name(for: key)))
    }

    /// Formato del valor en el explorador (paridad :727-732): sueño h/min, piel una
    /// décima, resto entero.
    private func levelsValueFormat(_ v: Double) -> String {
        switch datoInfo.id {
        case "sleep":
            let h = Int(v) / 60, m = Int(v) % 60
            return m == 0 ? "\(h)h" : "\(h)h \(m)m"
        case "skin_temp":
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

    @ViewBuilder private var pie: some View {
        if let metodo = LiquidSheetCopy.metodo(info) {
            LiquidMetodo(title: String(localized: "How it's calculated")) {
                LiquidNotaLine(metodo.prosa)
                if let cita = metodo.cita {
                    LiquidNotaLine(cita)
                }
            }
        }
        if appleConnectHint {
            LiquidNotaLine(String(localized: "This reading can come from Apple Health. Connect it from Today to see it here."))
        } else if let nota = LiquidSheetCopy.nota(info) {
            LiquidNotaLine(nota)
        }
        if let disclaimer = LiquidSheetCopy.disclaimer(info) {
            LiquidNotaLine(disclaimer)
        }
        // Línea de procedencia del pie RETIRADA (decisión del dueño /inject 2026-07-23):
        // el origen ya se dice arriba, en la etiqueta del header («Apple Salud · anoche»).
        if let onSeeMore { verMas(onSeeMore) }
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
        case "recovery":          return String(localized: "Recovery")
        case "vo2max":            return String(localized: "VO₂ Max")
        case "sleep_performance": return String(localized: "Performance")
        case "sleep_efficiency":  return String(localized: "Efficiency")
        case "sleep_restorative": return String(localized: "Restorative")
        case "sleep_awakenings":  return String(localized: "Awakenings")
        case "sleep_latency":     return String(localized: "Latency")
        default:                  return id
        }
    }

    /// `info.headline` — mismas claves; recovery calibrando replica la interpolación.
    static func headline(_ info: MetricInfo) -> String {
        if info.id == "recovery", let cal = info.calibration {
            return String(localized: "We can't score your recovery yet. We need at least \(cal.needed) nights of sleep to learn your baseline; you're at \(cal.done) of \(cal.needed). We'd rather not show you a made-up number.")
        }
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
        case "recovery":
            return String(localized: "Your recovery sums up how ready your body is today, from 0 to 100. It blends several signals from your night, your HRV above all, and compares them with your own average from recent weeks, not anyone else's.")
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
        case "recovery":
            return (String(localized: "Each signal becomes a score of how far above or below your personal average it sits (a z-score, in σ). They're averaged with fixed weights, HRV 60%, resting heart rate 20%, sleep 15%, skin temperature 10%, respiration 5%, and mapped onto a 0–100 scale, calibrated so a typical day lands near 58. If a signal is missing on a given night, its weight is shared among the others."),
                    String(localized: "A composite of z-scores through a logistic curve. HRV via RMSSD (Task Force, 1996)."))
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
