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
//  · Copy — el título/headline/nota/método/disclaimer salen DIRECTO de `MetricInfo`, que ahora
//    guarda su copy como `LocalizedStringResource` (FER-39 · F13): se resuelve a `String` con
//    `String(localized:)` sin duplicar claves. El viejo `LiquidSheetCopy` (que replicaba a mano
//    las claves del catálogo) se borró.
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
    /// Eco tabla↔gráfica (auditoría 2026-08-03): el valor del punto bajo el dedo mientras
    /// arrastras sobre la gráfica; `nil` al soltar. Resalta la fila de la escalera cuyo rango
    /// lo contiene (mock `.lvl.hit`). NO toca el héroe (contrato §11.3, el scrub es local).
    @State private var scrubValor: Double? = nil
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
    /// si no. Un solo hogar para las lecturas (`isSleepRich`, etapas, regularidad).
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
        case "strain":              return LiquidColor.ambar
        // FER-79 · D2 (dueño): la temperatura de piel conserva su dorado propio también en la
        // hoja — antes compartía el ámbar con Esfuerzo, que además es el color de atención.
        case "skin_temp":           return LiquidColor.doradoTemp
        case "steps":               return LiquidColor.teal
        case "resp_rate", "spo2":   return LiquidColor.azul
        case "stress":
            // FER-73 · HJ-09: el estrés ACOMPAÑA, no vota — Hoy le niega a propósito el verde
            // del veredicto y el rojo de la alarma (FER-59/FER-60). La hoja usa la MISMA rampa
            // de calor de la Matriz: tinta neutra abajo, ocre→siena arriba.
            switch datoInfo.headerTint {
            case .warn: return LiquidColor.estresMedio
            case .bad:  return LiquidColor.estresAlto
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
        // FER-73 · HJ-09: el estrés nunca viste verde/rojo de juicio — habla en su rampa.
        if datoInfo.id == "stress" { return tono }
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
        // FER-79 · D2: solo Esfuerzo. `doradoTemp` ya está oscurecido para leerse como texto
        // sobre el papel (ver LiquidColor.doradoTemp: contraste ≥4.5:1 verificado).
        datoInfo.id == "strain"
    }

    // MARK: Cabecera

    /// El `FixedMetric` de un id de la hoja, o `nil` para las que NO son FixedMetric (hrv,
    /// heart_rate, load y las 5 submétricas de sueño): esas conservan su formato bespoke,
    /// porque `MetricFormat.forMetric` no las cubre. (FER-29 F3b.)
    static func fixedMetric(_ id: String) -> MetricLevels.FixedMetric? {
        switch id {
        case "sleep":     return .sleep
        case "rhr":       return .restingHR
        case "strain":    return .strain
        case "steps":     return .steps
        case "skin_temp": return .skinTemp
        case "resp_rate": return .respiration
        case "stress":    return .stress
        case "spo2":      return .bloodOxygen
        default:          return nil
        }
    }

    /// Strain: «/ 21» solo con score real (paridad :369-373). El sufijo es el mismo de
    /// `MetricFormat.forMetric(.strain).scaleSuffix` (F3b). (Recovery ya no tiene hoja — C6.)
    private var sufijo: String? {
        guard datoInfo.id == "strain", datoInfo.displayValue != "—",
              let fm = Self.fixedMetric("strain") else { return nil }
        return MetricFormat.forMetric(fm).scaleSuffix
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

    /// FER-29 · C2 — la procedencia en el VOCABULARIO CERRADO (`LiquidOrigen`), por métrica,
    /// según el blueprint: sleep/hrv/rhr/steps/spo2 = appleSalud · strain/stress = calculado
    /// en el teléfono · skin_temp/resp_rate = appleWatch. La consume `origenChipVista`, que
    /// pinta el chip de procedencia DENTRO de «Cómo se calcula» (el pie).
    ///
    /// Contrato 2: NUNCA se afirma procedencia sobre un numeral «—». Sin dato ⇒ `sinOrigen`,
    /// y el chip no se pinta — así la clase calculada deja de rotular «Calculated» sobre «—»
    /// (antes lo hacía). `TrainingLoadSheet` ya usa `.calculadoEnTelefono` (no se toca).
    private var origen: LiquidOrigen {
        guard datoInfo.displayValue != "—" else { return .sinOrigen }
        if isStrainEstimado { return .appleSalud }
        switch datoInfo.id {
        case "recovery", "strain", "stress": return .calculadoEnTelefono
        case "skin_temp", "resp_rate":       return .appleWatch
        default:                             return .appleSalud   // sleep, hrv, rhr, steps, spo2
        }
    }

    /// D8 · El título de la hoja. Con esfuerzo estimado dice lo mismo que el tile («Carga
    /// del día»), clave que ya existe en el catálogo (`LiquidHoyBuilder`).
    private var tituloHoja: String {
        // FER-73 · HJ-13: una métrica, un nombre. La Matriz dice «Effort» y la hoja decía «Day
        // Strain» (y «Day load» si venía estimado): tres nombres para lo mismo. El matiz de
        // «estimado por Apple Salud» ya vive en el chip de procedencia, no en el título.
        if datoInfo.id == "strain" { return String(localized: "Effort") }
        return String(localized: datoInfo.name)
    }

    private var cabecera: some View {
        // Una sola lectura de `heroVentana` por render (revisión adversarial Grok): cada
        // acceso camina `levelsHost.window`, el gasto que ya costó caro en FER-216/FER-1040.
        let hv = heroVentana
        return LiquidSheetHeader(
            // El símbolo de sistema de la Matriz encabeza también la hoja (FER-117/125): la
            // fila que tocaste y la hoja que se abre dicen lo mismo con el mismo glifo.
            icono: glifo,
            titulo: tituloHoja,
            tono: tono,
            // F4b · Héroe idéntico a las otras 8: el numeral de duración (reloj «7:12»
            // del tile). La regularidad ya no vive aquí; baja al slot como tarjeta.
            // Durante la carga (`isSleepLoading` → skeleton en el cuerpo) el numeral del
            // tile se conserva — la hoja no abre muda.
            // F0.3 (FER-33): el numeral sigue la VENTANA del selector, y el sello dice cuál.
            numeral: hv.numeral,
            // Sueño cuelga la unidad «h» del reloj «7:25» (mock de sueño); las demás hojas
            // usan la unidad de su catálogo. FER-29 fidelidad (auditoría 2026-08-03).
            unidad: datoInfo.id == "sleep" ? String(localized: "h") : datoInfo.unit,
            sufijo: sufijo,
            numeralTono: tinte(datoInfo.headerTint),
            // FER-29 · Sin fecha/sello a la derecha del numeral (decisión del dueño,
            // auditoría 2026-08-03): «no me gusta la fecha en el título a la derecha, y cómo
            // se calcula es inconsistente» —el sello alternaba entre FECHA («HOY · 3 AGO») en
            // la semana y DESCRIPTOR DE VENTANA («MEDIA · 30 DÍAS») en rangos largos, dos
            // gramáticas distintas en el mismo lugar—. #inject: el dueño lo repide, pero
            // ARRIBA a la izquierda (overline sobre el título), no a la derecha del numeral;
            // cambia con el selector (semana → «HOY · 4 AGO», mes/3M → «MEDIA · N NOCHES»).
            sello: hv.sello,
            // FER-29 · La procedencia YA NO viaja en el héroe: baja al chip del pie, DENTRO
            // de «Cómo se calcula» (mock canónico). El héroe es solo valor + unidad + frase
            // + sello de la ventana, idéntico para las 9 métricas. (Revierte la decisión
            // /inject 2026-07-23 de rotular el origen en la cabecera; el nuevo mock lo pone
            // abajo, en el chip.)
            origen: nil,
            origenEtiqueta: nil,
            // D1 · La explicación habla del dato que la hoja MUESTRA (`datoInfo`), no del
            // real: con el fixture de demo la cabecera decía «56 ms» y la explicación
            // describía otra métrica. Fuera de demo `datoInfo == info` (no-op).
            explicacion: String(localized: datoInfo.headline),
            // L5.1 — el ⓘ se nombra solo en VoiceOver (antes leía «VFC, uno»).
            infoMostrar: String(localized: "Show explanation"),
            infoOcultar: String(localized: "Hide explanation"),
            // Sueño: «7 h 25 min» en vez de «7:25 h» (XC7-01); las demás hojas, la voz normal.
            a11yLabel: hv.a11y.map {
                LiquidSheetHeader.a11yLabel(titulo: tituloHoja, numeral: $0, unidad: nil,
                                            sello: hv.sello, origen: nil)
            })
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

    /// El nivel que describe el HÉROE — clasificado contra `valorMostrado`, el mismo número
    /// que el numeral enseña (la media en rangos largos, el dato de hoy en la semana), NO
    /// contra el de hoy a secas.
    ///
    /// FER-29 · Fidelidad (auditoría Grok 2026-08-03): la frase de lectura bajo el héroe era
    /// la única pieza que seguía clasificándose por `levelsTodayValue` mientras el numeral, la
    /// frase de nivel y la fila encendida ya seguían la ventana (`valorMostrado`). Al pasar a
    /// «MEDIA · 30 días» el numeral decía la media pero la palabra de abajo nombraba la banda
    /// de HOY: la hoja se contradecía en cuanto tu día se salía de tu promedio. La pastilla
    /// «· hoy» de la escalera sí marca el día real —vive en `indiceDeHoy`, intacto—.
    /// (Otra sesión —FER-33/Carga— llegó al mismo fix en paralelo; la hoja de Carga ya lo
    /// hacía bien y era la excepción.)
    private var activeLevelKey: String? {
        guard let levels = levelsHost.levels, let v = valorMostrado,
              let idx = MetricLevels.activeIndex(for: v, in: levels) else { return nil }
        return levels[idx].key
    }

    /// F0.3 · En qué fila de la escalera cayó HOY — independiente de lo que el héroe muestre.
    ///
    /// La escalera dice dos cosas a la vez y las dos son ciertas: cuál fila describe el número
    /// grande (la ENCENDIDA, que en rangos largos es la de la media) y dónde cayó tu día (la
    /// pastilla «· hoy»). Colgar «· hoy» de la fila encendida las confundía en una sola y hacía
    /// que la escalera marcara como «hoy» la banda del promedio.
    private var indiceDeHoy: Int? {
        guard let levels = levelsHost.levels, let v = datoInfo.levelsTodayValue else { return nil }
        return MetricLevels.activeIndex(for: v, in: levels)
    }

    /// La lectura de nivel de hoy (FER-29 · contrato 4): una sola tabla de datos
    /// (`MetricLevelPhrase`) keyeada por `(metricID, levelKey)` reemplaza los 26 `case`
    /// dispersos. `activeLevelKey` entrega la MISMA clave de nivel que el switch consumía
    /// (incluido hrv below/inBase/above), así que el copy queda idéntico — vive en el
    /// catálogo bajo `reading.*`. Un par que no está en el contrato ⇒ `nil` (sin línea).
    private var vitalReadingText: String? {
        guard let key = activeLevelKey,
              let phraseKey = MetricLevelPhrase.key(metricID: datoInfo.id, levelKey: key) else { return nil }
        return String(localized: String.LocalizationValue(phraseKey))
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

    // MARK: Sueño rica (§1.3 — lectura + niveles + etapas + regularidad)

    @ViewBuilder private var sleepContent: some View {
        if let night = nocheSueno {
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
                // La noche se nombra por su día de DESPERTAR (`endTs`), como `displayDays`, el scrub y el
                // sello; por el inicio cambiaba según te durmieras antes o después de medianoche (r6).
                : String(localized: "Last recorded night · \(Self.diaCorto(Self.fecha(night.endTs)))")
            // Héroe → frase → selector → gráfica → ETAPAS → REGULARIDAD → escalera → pie.
            // F0.1 (FER-33): las dos tarjetas propias de Sueño bajan al HUECO del bloque de
            // niveles. Antes colgaban después de la escalera porque no había dónde meterlas;
            // el prototipo canónico las pone entre la gráfica y la escalera, y ahí van.
            levelsBlock {
                // D10 · Con las CUATRO etapas en 0 (fallback diario de Apple) no hay noche
                // que dibujar: la barra saldría hueca bajo un overline suelto y una leyenda
                // vacía.
                if sleepEtapasMedidas(night) {
                    // FER-29 · Etapas en tarjeta de papel propia, como Regularidad y como el
                    // mock canónico de sueño (auditoría 2026-08-03): antes la barra flotaba
                    // sobre el fondo de la hoja bajo un overline suelto, sin superficie.
                    LiquidStageBar(
                        etapas: sleepEtapas(night),
                        overline: overlineNoche,
                        ventana: ventanaNoche)
                    .liquidTarjetaSeccion()
                }
                // F4b · Regularidad como tarjeta propia (ya no en el héroe ni en
                // `LiquidDobleDato`). `puntaje == nil` ⇒ «··» calibrando (lo maneja la tarjeta).
                LiquidRegularityCard(
                    titulo: String(localized: "Regularity"),
                    puntaje: regularidadSueno,
                    leyenda: regularidadLeyenda,
                    tono: LiquidColor.indigo,
                    explicacion: String(localized: "How steady your sleep schedule is: we take each night's midpoint (between falling asleep and waking) and measure how much it shifts night to night. Less drift, closer to 100."),
                    infoMostrar: String(localized: "Show explanation"),
                    infoOcultar: String(localized: "Hide explanation"))
            }
        }
    }

    /// F4b · Leyenda de la tarjeta de regularidad. Mismos cortes que
    /// `SleepDetailScreen.regularityWordText` (80+ / 55–79 / <55); con `nil` la tarjeta
    /// calibra y la frase es honesta.
    private var regularidadLeyenda: String {
        guard let s = regularidadSueno else {
            return String(localized: "Still learning your rhythm")
        }
        // #inject r4 · Solo la palabra-veredicto, sin coletilla (dueño: «te crea esa doble
        // línea») — el puntaje 88 y la palabra ya lo dicen todo; el detalle vive en el ⓘ.
        switch s {
        case 80...:
            return String(localized: "Very regular")
        case 55..<80:
            return String(localized: "Fairly regular")
        default:
            return String(localized: "Variable")
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

    /// La lectura de nivel de sueño (FER-29 · contrato 4/B6): el mismo lookup de
    /// `MetricLevelPhrase` que las vitales, CONSERVANDO la variante «anoche».
    ///
    /// B6 · Las dos variantes que decían «anoche» (short/extended) tienen gemela sin fecha:
    /// si el overline ya degradó a «Última noche registrada · 20 jul», la lectura no puede
    /// seguir afirmando «anoche» dos líneas más abajo. Las claves `.lastNight` viven en el
    /// catálogo; las otras dos frases (adequate/optimal) no fechan nada.
    private var sleepReadingText: String? {
        guard let key = activeLevelKey,
              let baseKey = MetricLevelPhrase.key(metricID: "sleep", levelKey: key) else { return nil }
        // «anoche» solo cuando el héroe muestra la noche REAL (semana). En rangos largos la
        // clave viene de la MEDIA de la ventana (`valorMostrado`), así que fechar esa lectura
        // como «anoche» mentiría (auditoría 2026-08-03).
        let usaAnoche = nocheEsDeAnoche && (key == "short" || key == "extended")
            && levelsHost.window.range == .week
        let clave = usaAnoche ? baseKey + ".lastNight" : baseKey
        return String(localized: String.LocalizationValue(clave))
    }

    /// B6 · ¿La noche que la hoja PINTA es la de anoche? La noche se llama por su día de
    /// DESPERTAR en toda la app (`displayDays`, el scrub, `selloAnoche`, `weekdayLabel(nocturna:)`):
    /// «anoche» es la noche que TERMINÓ hoy. Anclarla al inicio (≤ 1 día) llamaba «anoche» a una
    /// noche que empezó y terminó AYER (00:30→07:30) y la sellaba con la fecha de hoy (FER-128 r8).
    private var nocheEsDeAnoche: Bool {
        guard let night = nocheSueno else { return false }
        return Calendar.current.isDateInToday(Self.fecha(night.endTs))
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
        // Un NaN/±inf no es un dato (la Matriz lo filtra en `finito`; el plot lo clampeaba al
        // TECHO del dominio — FER-128 r7).
        let puntos: [(fecha: Date, valor: Double)] =
            trendData.filter { $0.value.isFinite }.map { (p: TrendPoint) in (fecha: p.date, valor: p.value) }
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

    /// Paridad `trendValueFormat` (:1104-1121) — mismos formatos por métrica (F3b).
    ///
    /// strain/stress/resp_rate (décima) y rhr (entero) pasan por `MetricFormat`. Quedan
    /// BESPOKE (gate /estadistico): sleep imprime «7h 12m» (no el reloj de MetricFormat);
    /// spo2 usa «%.0f» (redondeo banca vs `Int.rounded`, diverge en un promedio diario .5);
    /// steps sigue el locale; las submétricas de sueño no son FixedMetric.
    private func trendValueFormat(_ v: Double) -> String {
        switch datoInfo.id {
        case "strain", "stress", "resp_rate":
            // decimal1 == «%.1f»; el redondeo coincide con `String(format:)`.
            if let fm = Self.fixedMetric(datoInfo.id) { return MetricFormat.forMetric(fm).numeral(v) }
            return String(format: "%.1f", v)
        case "sleep":
            return Self.formatSleep(Int(v.rounded()))
        case "sleep_performance", "sleep_efficiency", "sleep_restorative":
            return "\(Int(v.rounded()))%"
        case "sleep_awakenings":
            return "\(Int(v.rounded()))"
        case "rhr":
            // El número por MetricFormat (entero, mismo `Int.rounded`); la unidad la localiza
            // el caller («bpm» → «lpm»), que MetricFormat NO hace (lleva el símbolo crudo).
            return "\(MetricFormat.forMetric(.restingHR).numeral(v)) \(String(localized: "bpm"))"
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
            a11yLabel: String(localized: "Heart Rate"))
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

    // MARK: F0.3 · El héroe sigue la ventana del selector (FER-33)

    /// El numeral del héroe y su sello, según la ventana que el selector tenga puesta.
    ///
    /// En la semana el héroe es el dato de HOY —el que tocaste en el Tablero para llegar
    /// aquí— y el sello lo fecha. En los rangos largos ese dato ya no describe lo que la
    /// gráfica está contando: ahí el héroe pasa a ser la MEDIA de la ventana, y el sello
    /// dice de cuál. Es el patrón de los prototipos canónicos, y la razón de ser del sello:
    /// sin él, un numeral que cambia al mover el selector sería un número sin dueño.
    ///
    /// El scrub NO toca esto (contrato LIQUID-GLASS §11.3, «el héroe no cambia al hacer
    /// scrub»): la cabeza del scrub vive en el popup de la gráfica. El rango sí; el scrub no.
    /// El valor que el héroe está MOSTRANDO: la media de la ventana en los rangos largos, el
    /// dato de hoy en la semana. Todo lo que describe al héroe —la frase de nivel, el titular
    /// de la tarjeta y la fila encendida de la escalera— tiene que clasificarse contra ESTE
    /// valor, no contra el de hoy: si el numeral dice la media y la palabra de abajo nombra la
    /// banda de hoy, la hoja se contradice sola en cuanto tu día se sale de tu promedio.
    ///
    /// `levelsHost.window` es una propiedad COMPUTADA que recorre la serie para resolver la
    /// ventana efectiva, así que se toma UNA vez por acceso y se deriva todo de ella: leerla
    /// varias veces por render es el gasto que ya costó caro en FER-216/FER-1040.
    private var valorMostrado: Double? {
        let w = levelsHost.window
        guard levelsHost.levels != nil, w.range != .week, !w.values.isEmpty else {
            return datoInfo.levelsTodayValue
        }
        // Un total EN CURSO (pasos) no entra a la media del rango — como el módulo, que excluye hoy
        // de su promedio a propósito (la serie sí lo conserva para la línea) (FER-128 r6).
        let valores = MetricDetailSpec.accumulatesToday(datoInfo.id) && w.values.count > 1
            ? Array(w.values.dropLast()) : w.values
        return ComparisonEngine.stat(valores).mean
    }

    /// `a11y`: la voz del numeral cuando el reloj «7:25» NO se puede leer tal cual (Sueño →
    /// «7 h 25 min», la misma de la Matriz — FER-128 r7: el arreglo r6 llegó a la celda y no a
    /// su hoja gemela). `nil` = la cabecera compone la voz normal.
    private var heroVentana: (numeral: String?, sello: String?, a11y: String?) {
        let w = levelsHost.window
        // El rango EFECTIVO manda, no el seleccionado: cuando la ventana se auto-ensancha
        // porque no había días suficientes, el sello tiene que decir la que de verdad se
        // promedió.
        guard levelsHost.levels != nil, w.range != .week, !w.values.isEmpty else {
            // Sueño en la semana: reloj «7:12» (el mismo formato del eje Y y de los rangos de
            // las filas), no el «7h 12m» del tile —el numeral y su escala tienen que hablar
            // igual (auditoría 2026-08-03)—.
            if datoInfo.id == "sleep", let v = datoInfo.levelsTodayValue {
                return (levelsValueFormat(v), selloHoy, LiquidHoyBuilder.a11ySueno(v))
            }
            // Sin número no hay noche/día que sellar («—» + «ANOCHE · 22 ago» afirmaba una noche
            // que la misma hoja declaraba inexistente — FER-128 r6).
            return (datoInfo.displayValue, datoInfo.displayValue == "—" ? nil : selloHoy, nil)
        }
        // El MISMO número que clasifica el nivel (`valorMostrado`, sin el día parcial de Pasos) —
        // el numeral y su carril no pueden separarse (FER-128 r7).
        return (valorMostrado.map(levelsValueFormat) ?? datoInfo.displayValue, selloMedia(w.range),
                datoInfo.id == "sleep" ? valorMostrado.map(LiquidHoyBuilder.a11ySueno) : nil)
    }

    /// «HOY · 3 AGO» de día; «ANOCHE · 2 AGO» en lo que se mide durmiendo. La fecha la compone
    /// la capa app (el DS no formatea fechas, contrato D3).
    ///
    /// FER-79 · D7 (dueño): lo NOCTURNO se fecha como la noche que fue. Antes el guardián decía
    /// «anoche · 15 ago» y la hoja de la misma señal «hoy · 16 ago»: dos convenciones para la
    /// misma noche. Lo que se mide despierto (pasos, esfuerzo, FC del día) conserva «hoy».
    private var selloHoy: String? {
        guard nightly else { return String(localized: "TODAY · \(Self.diaCorto(Date()))") }
        // La MISMA respuesta que el overline («Última noche registrada · 19 ago»): si la noche que
        // la hoja pinta no es la de anoche, el numeral no se sella «ANOCHE» — el overline ya la
        // fecha (FER-128 r7: dos criterios de «anoche» en la misma hoja).
        if datoInfo.id == "sleep", nocheSueno != nil, !nocheEsDeAnoche { return nil }
        // La noche se llama por su día de DESPERTAR en toda la app (la clave de `displayDays`, el
        // último punto de la gráfica de esta hoja, el scrub de la Matriz): «ANOCHE · 22 ago» es la
        // noche que terminó hoy. «Hoy − 1» apuntaba a otro punto de la misma gráfica (FER-128, r5).
        return String(localized: "LAST NIGHT · \(Self.diaCorto(Date()))")
    }

    /// «MEDIA · 30 DÍAS» / «MEDIA · 30 NOCHES» / «MEDIA · 6 MESES» / «MEDIA · 1 AÑO» /
    /// «MEDIA · TODO», según la ventana EFECTIVA y si la métrica es nocturna.
    ///
    /// Los rangos largos se nombran por su unidad natural, no por su cuenta de días: «1 año»
    /// se lee, «365 días» se calcula. Por eso medio año y año tienen su propia frase.
    private func selloMedia(_ rango: ExploreRange) -> String? {
        switch rango {
        case .week:
            return selloHoy
        case .month, .quarter:
            let dias: Int = rango.days ?? 0
            return nightly
                ? String(localized: "AVG · \(dias) NIGHTS")
                : String(localized: "AVG · \(dias) DAYS")
        case .half:
            return String(localized: "AVG · 6 MONTHS")
        case .year:
            return String(localized: "AVG · 1 YEAR")
        case .all:
            return String(localized: "AVG · ALL")
        }
    }

    /// Sin extras: el bloque de niveles tal cual, para las hojas que no enchufan nada.
    @ViewBuilder private var levelsBlock: some View {
        levelsBlock(extras: { EmptyView() })
    }

    /// FER-33 · F0.1 — el bloque de niveles con un HUECO entre la gráfica y la escalera.
    ///
    /// Los componentes propios de una hoja (las Etapas y la Regularidad de Sueño, la colina
    /// de Carga) colgaban DESPUÉS de todo el bloque, porque este era un `VStack` monolítico
    /// y no había dónde meterlos; el diseño canónico los pone entre la gráfica y la
    /// escalera. Abrir el hueco aquí lo resuelve para las nueve hojas de una vez, que es la
    /// regla de la casa: se cambia la familia, no la pantalla.
    ///
    /// El hueco se emite en TODAS las ramas —incluidas la de carga y la del pozo— porque los
    /// extras no dependen de la serie de niveles: si solo apareciera en la rama feliz, una
    /// hoja perdería sus tarjetas propias justo cuando sus niveles no están listos.
    @ViewBuilder private func levelsBlock<Extras: View>(
        @ViewBuilder extras: () -> Extras) -> some View {
        if levelsHost.levels != nil,
           // F0.3 · Se clasifica contra el valor que el héroe MUESTRA (la media en los rangos
           // largos), no contra el de hoy: así la frase de nivel, el titular y la fila
           // encendida de la escalera hablan del mismo número que está arriba.
           let d = levelsHost.clasificacion(today: valorMostrado) {
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
                    extras()
                    nivelesLista(d, conteos: false)
                    if let caption = datoInfo.bandsCaption {
                        LiquidNotaLine(String(localized: caption))
                    }
                } else {
                    if window.fellBack { avisoVentana(window) }
                    // FER-29 · Fidelidad (auditoría Grok+DeepSeek 2026-08-03): el título de
                    // nivel + su conteo + el plot viven DENTRO de una tarjeta de papel, como
                    // en el mock canónico (`.card`) y como ya hace Carga (`tarjetaGrafica`).
                    // Antes flotaban sueltos sobre el fondo de la hoja, sin superficie.
                    VStack(alignment: .leading, spacing: LiquidSpace.s300) {
                        nivelesFrase(d)
                        nivelesGrafica(d, window: window)
                    }
                    .liquidTarjetaSeccion()
                    extras()
                    nivelesLista(d)
                    if let caption = datoInfo.bandsCaption {
                        LiquidNotaLine(String(localized: caption))
                    }
                }
            }
        } else if datoInfo.levelsRelative {
            // D4 · HRV sin base propia todavía. La explicación honesta OCUPA el hueco del
            // instrumento (paridad NIV-09: un pozo con presencia), en vez de degradarse a
            // una línea de letra chica que pesa menos que la nota al pie de abajo — y que
            // dejaba el cuerpo de la hoja VACÍO entre cabecera y pie.
            VStack(alignment: .leading, spacing: LiquidSpace.s300) {
                pozoNiveles(String(localized: "Your levels come from your own baseline: a few more nights and they'll appear."))
                extras()
            }
        } else {
            extras()
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
            // Singular con UNA noche/día (la tabla de abajo ya lo hacía; el conteo no — FER-128 r6).
            let conteo: String = nightly
                ? (d.total == 1 ? (d.counts[i] == 1 ? String(localized: "conteo.ultima.noche", defaultValue: "your last night")
                                                    : String(localized: "conteo.ultima.noche.no", defaultValue: "not your last night"))
                                : String(localized: "\(d.counts[i]) of your last \(d.total) nights"))
                : (d.total == 1 ? (d.counts[i] == 1 ? String(localized: "conteo.ultimo.dia", defaultValue: "your last day")
                                                    : String(localized: "conteo.ultimo.dia.no", defaultValue: "not your last day"))
                                : String(localized: "\(d.counts[i]) of your last \(d.total) days"))
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
            // Sin NINGUNA fila en la historia no se nombra «anoche»/«hoy»: la celda dice «aún no leo
            // tus noches» y el guardián «Aún no hay lecturas» — la hoja, lo mismo (FER-128 r9).
            let sinLectura: String = levelsHost.parsed.isEmpty
                ? String(localized: "No readings yet")
                : (nightly ? String(localized: "No reading last night") : String(localized: "No reading today"))
            LiquidFraseNivel(nivel: nil, conteo: total, tono: tono, sinLectura: sinLectura)
        }
    }

    private func nivelesGrafica(_ d: MetricLevels.Classification,
                                window: MetricWindow) -> some View {
        let highlight = nivelDestacado(d)
        // La MISMA decimación del explorador (MetricTrendChart:196, maxPoints 80).
        let puntos = MetricWindowMath
            .decimatedPoints(rows: window.rows, values: window.values, maxPoints: 80)
            .filter { $0.value.isFinite }
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
            ticksY: nivelesMarcasY(d, dominio: dominio, valores: window.values),
            tono: tono,
            // Hoy = el último punto dibujado (paridad marksLastPoint/markedPointHollow
            // :144-145): anillo hueco mientras exploras un nivel que no es el de hoy.
            // La joya de hoy se enciende porque HOY tiene lectura, no porque la clasificación
            // tenga un nivel activo: al mostrar la media, `activeIndex` existe siempre y la
            // joya se prendía sobre el último punto aunque hoy no hubiera dato.
            puntoHoy: indiceDeHoy != nil ? puntos.last : nil,
            hoyAnillo: nivelExplorado != nil && nivelExplorado != indiceDeHoy,
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
            // Eco tabla↔gráfica: el valor bajo el dedo resalta la fila de su nivel.
            onScrubValor: { self.scrubValor = $0 },
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
                                dominio: ClosedRange<Double>,
                                valores: [Double])
        -> [(valor: Double, etiqueta: String)] {
        // Solo las marcas que CAEN en el dominio visible (/inject): al acotar el dominio,
        // los umbrales de fuera se dibujaban pegados al borde y el eje mentía («18» en una
        // gráfica que llega a 14.5).
        var ticks: [Double] = nivelesTicks(d).filter { dominio.contains($0) }
        // #inject r3 · «Más elementos en el eje Y» (dueño): además de los umbrales, la
        // CIMA y el PISO reales de la serie entran como marcas — el lector puede fechar
        // hasta dónde llegó la curva. Extremos de los DATOS, no del dominio: el dominio
        // trae 10-12 % de respiro y etiquetarlo pondría números que ninguna noche tocó
        // (revisión adversarial Grok). Solo si no pisan una marca existente (≥ 6 %).
        let span = dominio.upperBound - dominio.lowerBound
        if span > 0, let lo = valores.min(), let hi = valores.max() {
            for extremo in [lo, hi]
            where dominio.contains(extremo)
                && !ticks.contains(where: { abs($0 - extremo) < span * 0.06 }) {
                ticks.append(extremo)
            }
            ticks.sort()
        }
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
        // FER-79 · D7: en las hojas nocturnas el marcador de la fila activa dice «anoche», como
        // el sello de la cabecera — es la misma noche.
        let hoyRotulo: String = nightly
            ? String(localized: "· last night")
            : String(localized: "· today")
        let hint: String = String(localized: "Highlights this level on the chart")
        // Eco del scrub: qué carril contiene el valor bajo el dedo (rango half-open, igual
        // que la clasificación). `nil` cuando no hay scrub. La fila activa gana el wash.
        let resaltadaIdx: Int? = scrubValor.flatMap { (v: Double) -> Int? in
            d.levels.firstIndex { lvl in
                (lvl.lower.map { v >= $0 } ?? true) && (lvl.upper.map { v < $0 } ?? true)
            }
        }
        let filas: [LiquidLevelsList.Fila] = d.levels.indices
            .map { (i: Int) -> LiquidLevelsList.Fila in
                let nivel: MetricLevels.Level = d.levels[i]
                return LiquidLevelsList.Fila(
                    etiqueta: nombreNivel(nivel.key),
                    rango: rangoNivel(nivel),
                    // D7 · Sin serie todavía, la columna queda VACÍA (su ancho mínimo ya
                    // está reservado, así que no salta cuando llegan los conteos).
                    conteo: conteos ? conteoLabel(d.counts[i]) : "",
                    // La pastilla «· hoy» marca dónde cayó TU DÍA, no la fila que el héroe
                    // describe: en rango largo el héroe es la media y las dos filas pueden ser
                    // distintas. Ambas informaciones son ciertas y se ven a la vez.
                    esHoy: i == indiceDeHoy,
                    activa: i == highlight,
                    resaltada: i == resaltadaIdx,
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
        // F3b · Tres casos quedan BESPOKE porque `MetricFormat` normalizaría un dígito
        // visible (gate /estadistico): sleep TRUNCA (`Int(v)`) mientras el reloj de
        // MetricFormat redondea; skin_temp mantiene el «-» ASCII (MetricFormat usa «−»
        // Unicode); steps sigue el separador de miles del LOCALE (MetricFormat mete «,» a
        // mano). stress usa la décima del numeral (no la banda entera). El resto de las
        // FixedMetric enteras pasan por `MetricFormat.boundary` (byte-idéntico); las que no
        // son FixedMetric (hrv, heart_rate, submétricas) caen al entero de siempre.
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
            // MetricFormat.numeral(.stress) es exactamente ese «%.1f».
            return MetricFormat.forMetric(.stress).numeral(v)
        case "strain":
            // La media con la MISMA décima que el numeral de hoy («12.0» hoy vs «11» media — r12).
            return String(format: "%.1f", v)
        default:
            // rhr / spo2 / resp_rate: cotas enteras vía MetricFormat (byte-idéntico
            // a `Int(v.rounded())`). hrv / heart_rate / submétricas: entero de siempre.
            if let fm = Self.fixedMetric(datoInfo.id) {
                return MetricFormat.forMetric(fm).boundary(v)
            }
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
        // FER-29 · «Cómo se calcula» — UN solo bloque para las 9 hojas (mock canónico), con
        // dos rellenos: MÉTODO (prosa + cita) cuando hay fórmula, o NOTA de procedencia
        // cuando es lectura directa. El chip de origen (Apple Salud / Calculado en el
        // teléfono) va SIEMPRE dentro. Antes, unas hojas mostraban método plegable y otras
        // una nota suelta sin título (o nada): esa inconsistencia era el defecto.
        // F13: el método sale directo del catálogo (`info.method`) resuelto a String; antes lo
        // replicaba `LiquidSheetCopy.metodo`, borrado.
        let metodo = datoInfo.method.map { (prosa: String(localized: $0.prose),
                                            cita: $0.citation.map { String(localized: $0) }) }
        if metodo != nil || comoSeObtuvoProsa != nil {
            LiquidMetodo(title: String(localized: "How it's calculated"),
                         // D11 (B6) · Etiquetas propias de VoiceOver: antes leía «Cómo se
                         // calcula, uno». Distintas de las del ⓘ de la cabecera a propósito
                         // — son dos plegables diferentes en la misma hoja.
                         mostrar: String(localized: "Show method"),
                         ocultar: String(localized: "Hide method")) {
                if let metodo {
                    LiquidNotaLine(metodo.prosa)
                    if let cita = metodo.cita { LiquidNotaLine(cita) }
                    // El matiz/caveat de las métricas con fórmula acompaña al método DENTRO
                    // del mismo bloque (antes colgaba como nota suelta bajo el plegable).
                    if let nota = datoInfo.note.map({ String(localized: $0) }) { LiquidNotaLine(nota) }
                } else if let prosa = comoSeObtuvoProsa {
                    LiquidNotaLine(prosa)
                }
                origenChipVista
            }
        }
        // D1 · `appleConnectHint` lo resuelve TodayView contra el `info` REAL, así que en
        // demo el aviso salía junto a un dato visible («conéctalo desde Hoy» bajo «56 ms»).
        // Es un aviso ACCIONABLE: conserva su superficie propia, aparte del bloque de arriba.
        if appleConnectHint && !demo {
            avisoConectarApple
        }
        if let disclaimer = datoInfo.disclaimer.map({ String(localized: $0) }) {
            LiquidNotaLine(disclaimer)
        }
        if let onSeeMore { verMas(onSeeMore) }
    }

    /// FER-29 · La prosa de «cómo se obtuvo» para las hojas de LECTURA DIRECTA (sin fórmula):
    /// la nota del modelo si la trae (rhr, submétricas de sueño), o la procedencia sintetizada
    /// para las dos que el modelo no cubre (sueño, esfuerzo). Las métricas con fórmula usan su
    /// método en el pie, no esta prosa.
    private var comoSeObtuvoProsa: String? {
        if let nota = datoInfo.note.map({ String(localized: $0) }) { return nota }
        switch datoInfo.id {
        case "sleep":
            return String(localized: "Hours and stages come from your Apple Watch when you wear it to sleep; without it, Cénit uses total sleep time from Apple Health, without stages.")
        case "strain":
            // D8 · Coherente con el chip: el estimado ES la carga que midió Apple (FER-883),
            // no un cálculo de Cénit.
            return isStrainEstimado
                ? String(localized: "Today's figure is Apple Health's own workout estimate, not Cénit's calculation.")
                : String(localized: "Cénit works it out on your phone from your heart rate through the day: each second is placed in a zone (1–5) and the total is compressed onto a 0–21 scale.")
        default:
            return nil
        }
    }

    /// FER-29 · El chip de procedencia dentro de «Cómo se calcula». Honestidad (D1/B7): sobre
    /// un dato de Apple solo se afirma Apple cuando el valor VINO de Apple (`origenApple`);
    /// lo calculado lleva su propio chip. Sobre «—» (`.sinOrigen`) no se pinta chip.
    @ViewBuilder private var origenChipVista: some View {
        switch origen {
        case .appleSalud where origenApple || isStrainEstimado:
            LiquidOrigenChip(glyph: .corazon, badgeTono: LiquidColor.rosa,
                             etiqueta: String(localized: "Apple Health"),
                             sufijo: String(localized: "on your device"))
        case .appleWatch where origenApple:
            LiquidOrigenChip(glyph: .corazon, badgeTono: LiquidColor.rosa,
                             etiqueta: String(localized: "Apple Watch"),
                             sufijo: String(localized: "on your device"))
        case .calculadoEnTelefono, .calculado:
            LiquidOrigenChip(glyph: .rayo, badgeTono: LiquidColor.tinta500,
                             etiqueta: String(localized: "Calculated on your phone"))
        default:
            EmptyView()
        }
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
        .liquidTarjetaSeccion(padding: LiquidSpace.s300)
    }

    /// «Ver más» (paridad `seeMoreLink` :1186-1231): ancho completo para métricas con
    /// niveles, pastilla compacta para el resto.
    ///
    /// FER-79 · D6 (dueño): el rótulo dice A DÓNDE va. Desde una hoja de métrica esto abre el
    /// DETALLE COMPLETO encima de Hoy, no la pestaña Tendencias; «en Tendencias» se reserva
    /// para lo que sí cambia de pestaña (la hoja de Carga y el acta).
    @ViewBuilder private func verMas(_ action: @escaping () -> Void) -> some View {
        if datoInfo.usesLevels {
            LiquidVerMas(title: String(localized: "hoja.vermas.detalle",
                                       defaultValue: "See the full detail"),
                         hint: String(localized: "Opens the full detail"),
                         tone: tono, anchoCompleto: true, action: action)
        } else {
            LiquidVerMas(title: String(localized: "See more"),
                         hint: String(localized: "Opens the full detail"),
                         tone: tono, action: action)
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
