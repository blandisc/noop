#if os(iOS)
import SwiftUI
import CenitDesign
import StrandAnalytics
import CenitStore
import Foundation

// MARK: - SkinTempDetailScreen — el «Detalle de Temperatura de la piel» en vidrio Liquid (FER-101 · TND-12)
//
// Migración PURAMENTE VISUAL del esqueleto «Tendencias Final» (papel «Instrumento») a los legos
// Liquid, calcando el patrón de `SleepDetailScreen.swift` (la vara de esta migración) y de
// `StrainDetailScreen.swift` / `StressDetailScreen.swift` (los bloques hermanos ya firmados):
// campo teñido a sangre (`LiquidCampoMetrica`) → costuras de sección (`LiquidFranjaSeccion`) →
// lectura de nivel (`LiquidReadingLine`; los rangos viven en la escalera tocable del historial,
// UX-08) → historial (`LiquidRangeSelector` + `LiquidGraficaNiveles` +
// `LiquidResumenVentana` + `LiquidLevelsList`) → método + sello (patrón `pieMetodo` de Sueño).
//
// `SkinTempDetailModel` NO CAMBIA (contrato de datos congelado): consume `repo.displayDays`
// tal cual — cero matemática nueva. La identidad es el DORADO propio de la temperatura de piel
// (`LiquidColor.doradoTemp` + glifo `.termo`), el MISMO par que ya visten la hoja de Hoy
// (`LiquidMetricSheetView.swift:235` / `:264`) y el guardián (`LiquidHoyBuilder+Matriz.swift:404-405`)
// — nunca el ámbar de juicio (FER-79 · D2). El campo se tiñe por identidad, no por veredicto.
//
// UNA SOLA ESCALERA (regla de oro TND-10): las cuatro bandas salen de
// `MetricLevels.displayBands(for: .skinTemp)` (< −0.4 bajo tu base · −0.4–+0.4 en tu base ·
// +0.4–+0.8 ligeramente elevada · ≥ +0.8 elevada — los cortes de `ReadinessEngine`) y TODAS
// las representaciones — tabla de niveles, gráfica, escalera tocable, frase del campo y gate
// del streak — derivan del MISMO arreglo por CLAVE. El papel traía DOS vocabularios para la
// misma métrica a un tap de distancia: aquí «Normal/Unusual for you» con cortes ±1 SD
// personales, y en la hoja de Hoy la escalera fija del motor (`LiquidMetricSheetView:319`).
// Se unifican al motor; el ±SD personal no se pierde — vive en la celda «Variación» del
// resumen (la DE de la ventana del selector, UX-10/M5).
//
// La temperatura de piel es una DESVIACIÓN (±°C) contra la base nocturna propia, de polaridad
// NEUTRAL, y el delta vs el periodo anterior va en DELTA ABSOLUTO (°C), nunca en %: sobre una
// media ≈0 el porcentaje miente (razón original FER-256, conservada — la nota bajo la gráfica,
// UX-11). Sin calendario de
// 90 días a propósito, como el papel: una retícula de intensidad sobre una desviación con
// signo diría que «más frío» y «sin dato» se parecen.
//
// Se presenta vía `.sheet(item:)` desde Hoy y como capa desde Cuerpo, con el tema vivo pasado
// EXPLÍCITO (FER-162 — la hoja Liquid ya no lo referencia; se conserva por compatibilidad de
// firma con los call sites) y SIN `NavigationStack` anidado (FER-171).

/// Detalle de Temperatura de la piel en vidrio Liquid. Se arma desde un `SkinTempDetailModel`
/// (el caller inyecta el modelo para que la pantalla siga sin tocar la base de datos).
struct SkinTempDetailScreen: View {
    /// El tema vivo «Instrumento», retenido por compatibilidad con los call sites — la hoja
    /// Liquid ya no lo referencia (mismo trato que `SleepDetailScreen`/`StrainDetailScreen`).
    var theme: InstrumentoTheme = .base
    /// Everything the screen draws from the in-memory dashboard, derived ONCE by the caller (no DB here).
    let model: SkinTempDetailModel
    /// Loads the recent per-night distal warming magnitudes (°C) for the nocturnal thermal-stability read
    /// (FER-850), behind the experimental toggle. The heavy multi-night skin-temp read lives in the repo.
    var loadWarmingMagnitudes: () async -> [Double?] = { [] }
    /// `true` cuando Apple Salud NO está autorizado (mismo predicado que Sueño/Esfuerzo/Estrés,
    /// FER-101). TodayView ya lo pasa; el cabo real es CuerpoView, que cablea FER-100.
    var sinPermiso: Bool = false

    /// The trend block's period window (W/M/3M/6M/1Y/ALL). Defaults to a month.
    @State private var range: ExploreRange = .month
    /// The series with each `day` string parsed to a `Date` exactly ONCE (not per slice / per render) — the
    /// window math reads `date` straight from here. Built in `.task`. (FER-216 lesson)
    @State private var parsed: [(day: String, date: Date?, value: Double)] = []
    /// The nocturnal thermal-stability read (typical warming + night-to-night consistency), loaded async
    /// behind the experimental toggle; `nil` until loaded or when off. (FER-850)
    @State private var thermal: ThermalStabilityEngine.Result? = nil
    /// El ⓘ del campo abre la tarjeta «Qué medimos» bajo él (patrón Sueño/Esfuerzo).
    @State private var infoOpen = false
    /// El carril del historial que el dedo explora; `nil` = ninguno (paridad Sueño/Esfuerzo).
    @State private var bandaExplorada: Int? = nil

    /// El tono de la pantalla: el dorado PROPIO de la temperatura de piel — la identidad que ya
    /// visten la hoja de Hoy (`LiquidMetricSheetView.swift:235`) y el guardián
    /// (`LiquidHoyBuilder+Matriz.swift:404`). Existe justamente para no confundirse con el
    /// ámbar de atención (FER-79 · D2; `MatrizContrasteTests` fija la separación).
    private static let tono = LiquidColor.doradoTemp

    // MARK: - Body — el esqueleto del bloque, en vidrio

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: .zero) {
                if let v = model.today {
                    campoConDato(v)
                } else {
                    campoSinDato
                }
                if infoOpen { whatWeMeasureCard }
                if !model.loaded {
                    LiquidSheetSkeleton(a11yCargando: String(localized: "Reading your skin temperature…"))
                        .liquidSeccion()
                } else if model.hasData {
                    // Niveles = solo la lectura del ancla (UX-08: los rangos viven en la
                    // escalera tocable del historial); sin lectura, la sección se oculta.
                    if indiceAncla != nil {
                        seccion(String(localized: "Levels")) { levelsContent }
                    }
                    // UX-04: la sección monta hasta que el parseo terminó (calco del gate
                    // `durationParsed.count >= 2` de Sueño) — sin brinco del primer frame.
                    if parsed.count >= 2 {
                        seccion(String(localized: "History")) { historyContent }
                    }
                    if WhitespaceMetricsExperiment.isEnabled, let t = thermal {
                        seccion(String(localized: "Nightly thermal stability")) { thermalBlock(t) }
                    }
                    // UX-13: sin franja «Qué la mueve» en Temp — no hay motor de hallazgos
                    // propio, así que no se promete uno; la frase poblacional (alcohol,
                    // fiebre, calor) vive como nota del pie de método.
                    pieMetodo
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // El fondo va en las DOS formas de presentación: `background` para la capa de Cuerpo
        // y `presentationBackground` para la hoja de Hoy (mismo par que Sueño, FER-102).
        .background { LiquidSheetFondo(tone: Self.tono).ignoresSafeArea() }
        .presentationBackground { LiquidSheetFondo(tone: Self.tono) }
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(LiquidRadius.hoja)
        // FER-954: hop the day-key parse off-main (same seam as the other detail screens, FER-953).
        .task(id: model.loaded) {
            guard model.loaded else { return }   // pasada placeholder — nada que parsear
            range = .month
            let series = model.series
            parsed = await Task.detached(priority: .userInitiated) {
                series.map { ($0.day, Repository.parseDayKey($0.day), $0.value) }
            }.value
        }
        // Load the nocturnal thermal-stability read once, only when the experimental toggle is on. The
        // heavy multi-night skin-temp read lives behind `loadWarmingMagnitudes`. (FER-850)
        .task {
            guard WhitespaceMetricsExperiment.isEnabled else { return }
            let mags = await loadWarmingMagnitudes()
            thermal = mags.isEmpty ? nil : ThermalStabilityEngine.evaluate(magnitudes: mags)
        }
    }

    /// Una sección: la costura a sangre + su contenido con el margen del sistema.
    @ViewBuilder
    private func seccion<Content: View>(_ titulo: String, @ViewBuilder content: () -> Content) -> some View {
        LiquidFranjaSeccion(titulo, tono: Self.tono)
        content().liquidSeccion()
    }

    // MARK: - 1. El campo (héroe) — desviación con signo, identidad dorada, sin semáforo

    /// El carril (de `bandasTemp`) en que cae la última lectura, o `nil` sin lectura. Único
    /// predicado de la pantalla: lo leen el campo, la tabla de niveles, el historial y el gate
    /// del streak — nunca una segunda copia de los cortes (paridad `StrainDetailScreen.indiceHoy`).
    private var indiceAncla: Int? { model.today.flatMap(Self.indiceCarril) }

    /// El campo teñido a sangre con dato: la desviación con signo + «°C vs tu base», la frase
    /// de lectura por CLAVE de carril y, en la ranura libre, el chip de racha (noches seguidas
    /// derivando hacia el mismo lado — la señal que la temperatura de piel de verdad carga).
    private func campoConDato(_ v: Double) -> some View {
        LiquidCampoMetrica(
            tono: Self.tono,
            titulo: String(localized: "Skin temp"),
            glifo: .termo,
            // B7: a11y deletreado (calco del patrón de las hermanas «%@ out of 21») — «+0.5»
            // a secas se dicta ambiguo; la voz dice grados y contra qué base.
            datos: [.init(valor: Self.fmt(v), unidad: "°C",
                          rotulo: String(localized: "vs your base"),
                          a11y: String(localized: "\(Self.fmt(v)) degrees vs your base"))],
            veredicto: Self.fraseCarril(indiceAncla.map { Self.bandasTemp[$0].key } ?? "inBase"),
            infoAbierto: infoOpen,
            infoEtiqueta: String(localized: "What we measure"),
            onInfo: { withAnimation(LiquidMotion.lift) { infoOpen.toggle() } }
        ) {
            // El streak chip del papel (:210) vive aquí, como sello del campo — la ranura que
            // el componente existe para cargar (paridad `StrainDetailScreen` «in progress»).
            // El tinte ámbar de alarma del papel no cruza: el sello habla en papel, la
            // dirección la dicen las palabras «más cálida / más fría».
            if let s = streak {
                LiquidCampoSello(streakTexto(s))
            }
        }
    }

    /// El campo APAGADO: sin lectura el numeral es un guion, nunca un cero. Mismo patrón que
    /// `SleepDetailScreen.campoApagado` / `StrainDetailScreen.campoSinDato`.
    private var campoSinDato: some View {
        LiquidCampoMetrica(
            tono: Self.tono,
            titulo: String(localized: "Skin temp"),
            glifo: .termo,
            datos: [.init(valor: LiquidCajita.sinDato,
                          rotulo: String(localized: "vs your base"),
                          a11y: String(localized: "no data"), ausente: true)],
            clausula: clausulaSinDato
        ) {
            if sinPermiso {
                LiquidVerMas(title: String(localized: "Manage Apple Health permissions"),
                             tone: LiquidColor.papelAlto) { Self.abrirAjustesSalud() }
            }
        }
    }

    /// Cuatro vacíos distintos, no uno: cargando · sin permiso · con historia sin lectura
    /// fresca · vacío total. Mismo árbol que `StrainDetailScreen.clausulaSinDato`.
    private var clausulaSinDato: String {
        guard model.loaded else { return String(localized: "Reading your skin temperature…") }
        if sinPermiso {
            return String(localized: "Cénit can't read your skin temperature: Apple Health hasn't granted permission. Turn it on and your nights will show up here.")
        }
        if !model.series.isEmpty {
            return String(localized: "No reading from last night yet: your recent history is below.")
        }
        return String(localized: "No skin-temperature reading yet. Wear your Apple Watch to sleep and open this again after it syncs.")
    }

    /// Abre Ajustes de iOS en la ficha de la app — mismo atajo que Sueño/Esfuerzo (FER-102).
    private static func abrirAjustesSalud() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    /// La tarjeta del ⓘ bajo el campo: qué mide el número, en lenguaje llano. El MISMO texto
    /// que el papel enseñaba al tocar la barra del vaivén (misma clave) — la explicación no se
    /// pierde, cambia de puerta (patrón `SleepDetailScreen.queMedimosCard`).
    private var whatWeMeasureCard: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s150) {
            Text(String(localized: "What we measure"))
                .font(LiquidType.tituloFila)
                .foregroundStyle(LiquidColor.tinta900)
            Text(String(localized: "How far last night's skin temperature ran from your own recent baseline, in °C. We learn your normal over recent nights, so 0 is your usual and the number is the shift up or down. A single warm or cool night rarely means much: what's worth noticing is several nights in a row drifting the same way. It's a comfort signal, not a thermometer or a diagnosis."))
                .font(LiquidType.cuerpo)
                .lineSpacing(LiquidType.cuerpoLineSpacing)
                .foregroundStyle(LiquidColor.tinta700)
                .fixedSize(horizontal: false, vertical: true)
        }
        .liquidTarjetaSeccion()
        .liquidSeccion(top: LiquidSpace.s400, bottom: LiquidSpace.s200)
    }

    /// La frase de una línea bajo el numeral, por CLAVE de carril — realineada a la escalera
    /// única: el gate pasa del ±0.3 suelto del papel al corte ±0.4 del motor (una sola fuente
    /// de cortes). UX-12: «elevated» tiene frase PROPIA — un +0.9 no es «a touch warmer»;
    /// directa y sin diagnóstico, derivada por CLAVE (nunca un segundo corte).
    static func fraseCarril(_ key: String) -> String {
        switch key {
        case "below":    return String(localized: "A touch cooler than your baseline last night.")
        case "warm":     return String(localized: "A touch warmer than your baseline last night.")
        case "elevated": return String(localized: "Notably warmer than your base last night.")
        default:         return String(localized: "Right around your usual nighttime baseline.")
        }
    }

    // MARK: - Streak (noches seguidas derivando al mismo lado)

    /// A run of recent nights drifting the same side of the baseline — the signal skin temp actually
    /// carries. nil cuando la última lectura cae EN TU BASE (el carril del motor, antes un ±0.3
    /// propio) o no hay lectura. La racha misma sigue contando por SIGNO, como siempre.
    private var streak: (count: Int, warmer: Bool)? {
        guard let today = model.today, let i = Self.indiceCarril(today),
              Self.bandasTemp[i].key != "inBase" else { return nil }
        let warmer = today > 0
        var n = 0
        for v in model.series.map(\.value).reversed() {
            if (warmer && v > 0) || (!warmer && v < 0) { n += 1 } else { break }
        }
        return n >= 1 ? (n, warmer) : nil
    }

    /// Las MISMAS cuatro claves del chip del papel, resueltas a `String` para el sello.
    private func streakTexto(_ s: (count: Int, warmer: Bool)) -> String {
        switch (s.count, s.warmer) {
        case (1, true):  return String(localized: "First night warmer")
        case (_, true):  return String(localized: "\(s.count) nights warmer")
        case (1, false): return String(localized: "First night cooler")
        default:         return String(localized: "\(s.count) nights cooler")
        }
    }

    // MARK: - 2. Niveles — la lectura del ancla contra la escalera única
    //
    // UX-08 (pasada F4/F5): UNA sola escalera visible por pantalla. La `LiquidBandsTable`
    // estática duplicaba los rangos que la `LiquidLevelsList` TOCABLE del historial ya
    // enseña; aquí queda solo «Anoche cae en…» (la MISMA pregunta del vaivén ±SD del papel,
    // con la escalera del motor). La sección entera se oculta sin lectura (gate en el body).

    @ViewBuilder private var levelsContent: some View {
        if let i = indiceAncla {
            let b = Self.bandasTemp[i]
            LiquidReadingLine(
                String(localized: "Last night falls in \(b.label) · 0 is your own base"),
                highlight: b.label, highlightTone: Self.tono)
        }
    }

    // MARK: - 3. Ver tu historial — selector + gráfica + resumen + escalera

    private var historyContent: some View {
        let window = MetricWindowMath.make(parsed, selected: range)
        let stat = ComparisonEngine.stat(window.values)
        let comparison = window.range.periodComparison(of: model.series)
        // Absolute °C delta vs the previous period — only when there IS one. A percentage would be
        // unstable on a near-zero mean, so we never compute one. (FER-264 / FER-256, conservado;
        // UX-11: el delta vive en la nota bajo la gráfica, en °C — nunca un «+12%».)
        let periodDelta: Double? = (comparison?.previous.n ?? 0) > 0 ? comparison?.delta : nil
        return VStack(alignment: .leading, spacing: LiquidSpace.s300) {
            LiquidRangeSelector(opciones: ExploreRange.allCases.map(\.label),
                                seleccion: rangeSeleccion, tono: Self.tono)
            if window.values.count > 1 {
                VStack(alignment: .leading, spacing: LiquidSpace.s300) {
                    fraseNivelHistorial(window)
                    graficaHistorial(window)
                    // UX-11: el «Cambio» vs el periodo anterior baja del trío a esta nota —
                    // como el «+12%» de las hermanas pero en °C absolutos (sobre una media
                    // ≈0 el porcentaje miente, FER-256). Sin periodo previo, no hay nota.
                    if let periodDelta {
                        LiquidNotaLine(String(localized: "\(Self.fmt(periodDelta)) °C vs previous period"))
                    }
                    LiquidNotaLine(String(localized: "Each night's deviation in °C · 0 is your own base."))
                    // UX-10/M5: el trío habla de la VENTANA — «Variación» es la DE de los
                    // valores del rango del selector (no el `typicalSD` global de toda la
                    // serie, que no cambiaba con el selector); «Anoche» es el ancla, con
                    // guion honesto si no hay lectura (paridad de la celda «Hoy» de las
                    // hermanas). Nunca un CV%: dividir entre una media ≈0 no significa nada.
                    LiquidResumenVentana(celdas: [
                        .init(rotulo: String(localized: "Average"),
                              valor: "\(Self.fmt(stat.mean)) °C"),
                        .init(rotulo: String(localized: "Variation"),
                              valor: "±\(String(format: "%.1f", stat.stdev)) °C"),
                        .init(rotulo: String(localized: "Last night"),
                              valor: model.today.map { "\(Self.fmt($0)) °C" } ?? LiquidCajita.sinDato,
                              tono: model.today != nil ? Self.tono : nil),
                    ])
                }
                .liquidTarjetaSeccion()
                LiquidLevelsList(filas: carrilesHistorial(window), tono: Self.tono)
                LiquidNotaLine(String(localized: "How many nights of the period fell in each band. Tap one to see its nights on the chart."))
            } else {
                LiquidGraficaNiveles(puntos: [], bandas: [], dominio: Self.dominioTemp([]), ticksY: [],
                                     tono: Self.tono,
                                     estadoVacio: String(localized: "Not enough nights in this range to draw a trend."),
                                     a11yLabel: String(localized: "Skin temp history"))
            }
        }
    }

    /// El índice del selector ⇄ `ExploreRange`; cambiar de rango suelta el carril explorado.
    private var rangeSeleccion: Binding<Int> {
        Binding(
            get: { ExploreRange.allCases.firstIndex(of: range) ?? 0 },
            set: { idx in
                range = ExploreRange.allCases[idx]
                bandaExplorada = nil
            })
    }

    /// El carril resaltado en la gráfica y en la escalera: el que el dedo explora, o si no hay
    /// ninguno, el del ancla.
    private var destacado: Int? { bandaExplorada ?? indiceAncla }

    /// El carril de la última noche y cuántas noches del periodo cayeron con ella — el mismo
    /// contrato que `SleepDetailScreen.fraseNivelHistorial` (voz en NOCHES: la temperatura de
    /// piel es una lectura nocturna, `BandSummaryCopy.isNightly`).
    @ViewBuilder private func fraseNivelHistorial(_ window: MetricWindow) -> some View {
        if let i = indiceAncla {
            let b = Self.bandasTemp[i]
            let n = window.values.filter { v in
                (b.lo == nil || v >= b.lo!) && (b.hi == nil || v < b.hi!)
            }.count
            LiquidFraseNivel(nivel: b.label,
                             conteo: String(localized: "\(n) of your last \(window.values.count) nights"),
                             tono: Self.tono)
        } else {
            LiquidFraseNivel(nivel: nil,
                             conteo: String(localized: "\(window.values.count) nights with data in this range"),
                             tono: Self.tono,
                             sinLectura: String(localized: "No reading last night"))
        }
    }

    /// La gráfica del historial: la serie CRUDA noche a noche (los huecos son el dato — la
    /// piel se mide a ratos), con los carriles del motor detrás y los ticks afirmando los
    /// CORTES reales (−0.4 / +0.4 / +0.8) más el 0 de tu base.
    private func graficaHistorial(_ window: MetricWindow) -> some View {
        let puntos = MetricWindowMath
            .decimatedPoints(rows: window.rows, values: window.values, maxPoints: 80)
            .map { (fecha: $0.date, valor: $0.value) }
        return LiquidGraficaNiveles(
            puntos: puntos,
            bandas: Self.bandasTemp.enumerated().map { i, b in
                LiquidChartBanda(lo: b.lo, hi: b.hi, color: b.color, activa: i == destacado)
            },
            dominio: Self.dominioTemp(window.values),
            ticksY: [(0.8, Self.fmt(0.8)), (0.4, Self.fmt(0.4)), (0, "0"), (-0.4, Self.fmt(-0.4))],
            tono: Self.tono,
            puntoHoy: model.today != nil ? puntos.last : nil,
            hoyAnillo: bandaExplorada != nil && bandaExplorada != indiceAncla,
            formatoScrub: { v, f in "\(Self.fmt(v)) · \(Self.ejeFechaFmt.string(from: f))" },
            formatoValorScrub: { Self.fmt($0) },
            formatoFechaScrub: { Self.ejeFechaFmt.string(from: $0) },
            formatoFechaEje: { Self.ejeFechaFmt.string(from: $0) },
            atenuarFuera: bandaExplorada != nil,
            estadoVacio: String(localized: "Not enough nights in this range to draw a trend."),
            a11yLabel: String(localized: "Skin temp history"))
            .id(range)
    }

    /// Los carriles tocables bajo la gráfica: tocar uno resalta sus noches; re-tocarlo limpia.
    /// Mismo contrato que `SleepDetailScreen.carrilesHistorial` / `StrainDetailScreen`.
    private func carrilesHistorial(_ window: MetricWindow) -> [LiquidLevelsList.Fila] {
        let hint = String(localized: "Highlights this level on the chart")
        let hoyRotulo = String(localized: "· last night")
        let iAncla = indiceAncla
        return Self.bandasTemp.indices.map { i in
            let b = Self.bandasTemp[i]
            let n = window.values.filter { v in
                (b.lo == nil || v >= b.lo!) && (b.hi == nil || v < b.hi!)
            }.count
            return LiquidLevelsList.Fila(
                etiqueta: b.label, rango: b.range,
                conteo: n == 1 ? String(localized: "\(n) night") : String(localized: "\(n) nights"),
                esHoy: i == iAncla, activa: i == destacado,
                hoyEtiqueta: hoyRotulo, a11yHint: hint,
                onTap: {
                    withAnimation(LiquidMotion.lift) {
                        bandaExplorada = (bandaExplorada == i) ? nil : i
                    }
                })
        }
    }

    // MARK: - La escalera única — UNA sola, compartida por campo/niveles/historial/streak
    //
    // FER-101 · TND-12: el papel traía DOS copias de cortes para la misma métrica — los
    // «Normal/Unusual for you» de ±1 SD personales de esta pantalla y la escalera fija del
    // motor que la hoja de Hoy ya enseña (`LiquidMetricSheetView:319` → `FixedMetric.skinTemp`),
    // más un ±0.3 suelto duplicado en el héroe y en el gate del streak. Se deriva UNA vez de
    // `MetricLevels.displayBands(for: .skinTemp)` — los cortes de `ReadinessEngine`, citados en
    // `MetricLevels.swift:104-106` — y TODO sale de aquí por CLAVE. El rango se compone con el
    // MISMO formato ASCII con signo que la hoja de Hoy usa para esta métrica
    // (`LiquidMetricSheetView.swift:1494-1510`), para que las dos superficies digan el mismo
    // número byte a byte.

    struct BandaTemp {
        let key: String
        let label: String
        let lo: Double?
        let hi: Double?
        let color: Color
        let range: String
    }

    static let bandasTemp: [BandaTemp] = MetricLevels.displayBands(for: .skinTemp).map { band in
        BandaTemp(key: band.key,
                  label: String(localized: String.LocalizationValue(band.name)),
                  lo: band.lower, hi: band.upper,
                  color: colorNivel(band.key),
                  range: rangoNivel(lo: band.lower, hi: band.upper))
    }

    /// El tono de cada carril: un solo dorado graduado por opacidad, del más tenue (bajo tu
    /// base) al pleno (elevada) — la tinta sube con el calor, literal. Misma idea que la rampa
    /// de esfuerzo (`StrainDetailScreen.colorNivel`), nunca un semáforo: el ámbar de alarma que
    /// el papel ponía en «Unusual for you» no cruza al vidrio — la palabra del carril lo dice.
    private static func colorNivel(_ key: String) -> Color {
        switch key {
        case "below":  return Self.tono.opacity(0.24)  // token-exempt(dato): rampa graduada de temperatura
        case "inBase": return Self.tono.opacity(0.45)  // token-exempt(dato): rampa graduada de temperatura
        case "warm":   return Self.tono.opacity(0.72)  // token-exempt(dato): rampa graduada de temperatura
        default:       return Self.tono                 // "elevated"
        }
    }

    /// «< -0.4» · «-0.4–+0.4» · «≥ +0.8» — los cortes con el signo SIEMPRE visible, en el
    /// mismo formato bespoke que la hoja de Hoy (`rangoNivel` de `LiquidMetricSheetView`).
    private static func rangoNivel(lo: Double?, hi: Double?) -> String {
        switch (lo, hi) {
        case let (nil, .some(h)):      return "< \(fmt(h))"
        case let (.some(l), nil):      return "≥ \(fmt(l))"
        case let (.some(l), .some(h)): return "\(fmt(l))–\(fmt(h))"
        default:                       return ""
        }
    }

    /// El carril en que cae un valor. Único predicado numérico de la pantalla.
    static func indiceCarril(_ v: Double) -> Int? {
        bandasTemp.firstIndex { b in (b.lo == nil || v >= b.lo!) && (b.hi == nil || v < b.hi!) }
    }

    /// El dominio Y del historial: siempre abre los cortes del motor con aire (piso −0.9,
    /// techo +1.0) e incluye el dato — así el carril «elevada» se lee como carril y no como
    /// borde recortado. Presentación pura, cero matemática de datos.
    private static func dominioTemp(_ values: [Double]) -> ClosedRange<Double> {
        let lo = Swift.min(values.min() ?? 0, -0.9)
        let hi = Swift.max(values.max() ?? 0, 1.0)
        let pad = Swift.max((hi - lo) * 0.06, 0.05)
        return (lo - pad)...(hi + pad)
    }

    private static let ejeFechaFmt: DateFormatter = {
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("dMMM"); return f
    }()

    // MARK: - 4. Estabilidad térmica nocturna (FER-850) — tras el toggle experimental

    /// The «Nightly thermal stability» block: the typical distal warming (°C) into sleep as the datum, a
    /// night-to-night consistency word, and an honest one-liner. Framed as an ASSOCIATION — never a full
    /// 24-hour circadian amplitude (we only have the night). Only shown with the experimental toggle on.
    /// La palabra de constancia habla en tinta neutra (el verde/ámbar de juicio del papel no
    /// cruza al vidrio — mismo trato que «constancia» en Estrés).
    @ViewBuilder private func thermalBlock(_ t: ThermalStabilityEngine.Result) -> some View {
        if t.stability == .learning {
            LiquidNotaLine(String(localized: "Still learning how consistent your nightly warming is: keep wearing it to bed."),
                           tono: LiquidColor.tinta700)
        } else {
            VStack(alignment: .leading, spacing: LiquidSpace.s300) {
                LiquidCajitaGrid {
                    // B8: compactas, como las cajitas de palabra de Estrés — «Consistente»
                    // a `valorL` desbordaba la rejilla de 2.
                    LiquidCajita(rotulo: String(localized: "typical warming into sleep"),
                                 valor: String(format: "%.1f", t.typicalWarmingC),
                                 unidad: "°C",
                                 tono: Self.tono,
                                 compacto: true)
                    LiquidCajita(rotulo: String(localized: "night to night"),
                                 valor: thermalWord(t.stability),
                                 compacto: true)
                }
                LiquidNotaLine(thermalCopy(t), tono: LiquidColor.tinta700)
            }
        }
    }

    private func thermalWord(_ s: ThermalStabilityEngine.Stability) -> String {
        switch s {
        case .consistent: return String(localized: "Consistent")
        case .moderate:   return String(localized: "Moderate")
        case .variable:   return String(localized: "Variable")
        case .learning:   return String(localized: "Learning")
        }
    }

    /// Honest, localized one-liner — composed in the UI (not the engine's English `copy`) so it localizes
    /// with the app catalog. ASSOCIATION framing, never a 24-hour circadian-amplitude claim. (FER-850)
    private func thermalCopy(_ t: ThermalStabilityEngine.Result) -> String {
        switch t.stability {
        case .consistent: return String(localized: "Your body's warming as you fall asleep is steady night-to-night. A consistent wind-down: an association, not a full 24-hour rhythm.")
        case .moderate:   return String(localized: "Your nightly warming into sleep varies a moderate amount night-to-night. An association, not a full 24-hour rhythm.")
        case .variable:   return String(localized: "Your nightly warming into sleep swings a fair amount night-to-night. A steadier wind-down tends to settle it. An association, not a full 24-hour rhythm.")
        case .learning:   return ""
        }
    }

    // MARK: - Método + sello — patrón `pieMetodo` de Sueño (capilar sin franja propia)
    //
    // UX-13: la frase poblacional («alcohol, fiebre, calor ambiente») NO es un hallazgo del
    // usuario — vive aquí como nota de método, no bajo una franja «Qué la mueve» que
    // prometería un motor de hallazgos que la piel no tiene.

    private var pieMetodo: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s300) {
            LiquidCapilar(eje: .horizontal)
            LiquidMetodo(title: String(localized: "How it's calculated"),
                         mostrar: String(localized: "Show explanation"),
                         ocultar: String(localized: "Hide explanation")) {
                LiquidNotaLine(String(localized: "Each night your Apple Watch records skin temperature. We compare it with a rolling baseline of your own recent nights and report the difference in °C: so the value is always relative to you, not an absolute temperature. The trend and the spread are computed from that same nightly deviation."),
                               tono: LiquidColor.tinta700)
                LiquidNotaLine(String(localized: "Tends to rise with alcohol, fever, and ambient heat."),
                               tono: LiquidColor.tinta700)
                LiquidNotaLine(String(localized: "Nightly skin-temperature deviation from a personal rolling baseline. A comfort signal, not a thermometer or a diagnosis."))
            }
            // SIEMPRE Apple Watch: el sello de papel decía «Medido por tu banda» (`.band`) y
            // eso es una MENTIRA — la app es solo-Apple y ningún usuario tuvo banda (axioma
            // «cero banda»). M1: la MISMA clave que la hoja de Hoy declara para esta métrica
            // (`LiquidMetricSheetView.origen` → `.appleWatch` para `skin_temp`, :365) — el
            // reloj es quien la mide, no «Apple Salud» a secas.
            LiquidOrigenChip(glyph: .termo, badgeTono: Self.tono,
                             etiqueta: String(localized: "Apple Watch"),
                             sufijo: String(localized: "last night"))
        }
        .liquidSeccion(top: LiquidSpace.s200, bottom: LiquidSpace.s800)
    }

    // MARK: - Format

    /// Skin-temp reads as a SIGNED deviation at one decimal ("+0.3", "-0.2"), like the row, the
    /// hero and the hoja de Hoy (ASCII «-», paridad `LiquidMetricSheetView.levelsValueFormat`).
    private static func fmt(_ v: Double) -> String { String(format: "%+.1f", v) }

    /// The canonical UTC day-key formatter — read side of the day-key contract (FER-754).
    static let dayParser = DayKey.utcFormatter
}

// MARK: - SkinTempDetailModel — the data the screen draws, built ONCE from the repo (DB-free presentation)

struct SkinTempDetailModel {
    /// The latest skin-temperature deviation (°C) — today's if present, else the most recent (Apple
    /// fallback resolved by the caller). Drives the hero; nil → the empty hero.
    let today: Double?
    /// The full nightly deviation series (oldest → newest), `(day "yyyy-MM-dd", value °C)`.
    let series: [(day: String, value: Double)]
    /// Whether the repo finished its first load (drives loading vs empty hero copy).
    let loaded: Bool

    /// Sample standard deviation of the whole series in °C — the «Consistency» datum. nil with <2 points so
    /// the block is skipped (mirrors how the siblings gate consistency).
    var consistencySD: Double? {
        let vals = series.map(\.value)
        guard vals.count >= 2 else { return nil }
        return ComparisonEngine.stat(vals).stdev
    }

    /// The typical night-to-night swing (±1 SD) used for the «Variation» cell; 0 when there
    /// isn't enough history.
    var typicalSD: Double { consistencySD ?? 0 }

    /// True when there's a reading or any stored history to draw (the rich path); false → empty.
    var hasData: Bool { today != nil || !series.isEmpty }

    /// Build the whole model from the repo's in-memory dashboard. Pure (no DB). `latest` is the resolved
    /// most-recent deviation (the caller runs `resolveMeasured`); `series` is the full `displayDays` series.
    static func build(latest: Double?, series: [(day: String, value: Double)], loaded: Bool) -> SkinTempDetailModel {
        SkinTempDetailModel(today: latest, series: series.sorted { $0.day < $1.day }, loaded: loaded)
    }
}

// MARK: - Sheet item

/// Identifiable wrapper so the Liquid Detalle de Temperatura de la piel can ride `.sheet(item:)`
/// (the model itself isn't Identifiable). Built fresh on tap in Cuerpo. (FER-256)
struct SkinTempDetailItem: Identifiable {
    let id = UUID()
    let model: SkinTempDetailModel
}

// MARK: - Preview

#if DEBUG
private func sampleSkinTempSeries(days: Int = 60) -> [(day: String, value: Double)] {
    let cal = Calendar(identifier: .gregorian)
    let today = cal.startOfDay(for: Date())
    let f = SkinTempDetailScreen.dayParser
    return (0..<days).map { i in
        let date = cal.date(byAdding: .day, value: -(days - 1 - i), to: today)!
        let v = 0.25 * sin(Double(i) / 4.0) + Double((i * 7) % 3 - 1) * 0.08
        return (f.string(from: date), v)
    }
}

#Preview("Skin temp detail: con datos") {
    Color.clear.sheet(isPresented: .constant(true)) {
        SkinTempDetailScreen(
            model: SkinTempDetailModel.build(latest: 0.5, series: sampleSkinTempSeries(), loaded: true))
    }
}

#Preview("Skin temp detail: sin datos") {
    Color.clear.sheet(isPresented: .constant(true)) {
        SkinTempDetailScreen(
            model: SkinTempDetailModel.build(latest: nil, series: [], loaded: true))
    }
}

#Preview("Skin temp detail: sin permiso") {
    Color.clear.sheet(isPresented: .constant(true)) {
        SkinTempDetailScreen(
            model: SkinTempDetailModel.build(latest: nil, series: [], loaded: true),
            sinPermiso: true)
    }
}
#endif
#endif
