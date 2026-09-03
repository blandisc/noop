#if os(iOS)
import SwiftUI
import CenitDesign
import StrandAnalytics
import CenitStore
import Foundation

// MARK: - StressDetailScreen — el «Detalle de Estrés» en vidrio Liquid (FER-101 · TND-11)
//
// Detalle de Estrés en Liquid Glass · El Eje (FER-342). Calcando el patrón de
// `SleepDetailScreen.swift` (la vara) y de `StrainDetailScreen.swift` (el bloque hermano):
// campo teñido a sangre (`LiquidCampoMetrica`) → costuras de sección (`LiquidFranjaSeccion`) →
// lectura de nivel (`LiquidReadingLine`; los rangos viven en la escalera tocable del historial,
// UX-08) → mapa del día (`StressDayMapBlock`, ya en vidrio) → historial
// (`LiquidRangeSelector` + `LiquidGraficaNiveles` + `LiquidResumenVentana` + `LiquidLevelsList`)
// → calendario (`LiquidCalendario90`) → método + sello (patrón `pieMetodo` de Sueño).
//
// `StressModel` NO CAMBIA (contrato de datos congelado): consume `StrandAnalytics` tal cual —
// cero matemática nueva. El semáforo verde/ámbar/rojo del héroe de papel NO cruza al vidrio:
// en la familia Liquid el estrés ACOMPAÑA, no vota (FER-73 · HJ-09, FER-60) — su identidad es
// la rampa de CALOR `MatrizEscalerita.colorNivel` (tinta500 bajo · ocre medio · siena alto),
// la misma que ya visten la Matriz de Hoy y `LiquidMetricSheetView` (:239-246). El campo se
// tiñe con el calor del nivel de HOY, nunca con el verde del veredicto ni el rojo de alarma.
//
// UNA SOLA ESCALERA (regla de oro TND-10): las tres bandas salen de
// `MetricLevels.displayBands(for: .stress)` (0–1 low · 1–2 medium · 2–3 high) y TODAS las
// representaciones — tabla de niveles, gráfica, escalera del historial, calendario, palabra
// del día tocado, leyenda y el mapa del día — derivan del MISMO arreglo por CLAVE. La pantalla
// de papel traía TRES vocabularios («Calm/Your base/Activated» en la mini-escala,
// «Low/Base/Activated» en la gráfica, «Low/Moderate/High» en calendario y héroe): se unifican
// a la escalera del motor (Low/Medium/High, la misma palabra que la Matriz de Hoy).
//
// Se presenta desde Cuerpo Y desde Hoy vía `.sheet(item:)` (FER-452), SIN `NavigationStack`
// anidado (FER-171).

/// Detalle de Estrés en vidrio Liquid. Se arma desde un `StressModel` (el caller inyecta el
/// modelo para que la pantalla siga sin tocar la base de datos). `model == nil` → vacío honesto.
struct StressDetailScreen: View {
    /// The transparent 0–3 stress model, built by the caller from `repo.displayDays` + the stored series.
    /// `nil` when there's no usable signal at all → the empty hero.
    let model: StressModel?
    /// The «mapa del día» driver (EventKit permission + intraday stress curve + calendar cross), built
    /// by the caller. `nil` in previews / when the block shouldn't show. (FER-377)
    var dayMap: CalendarDayMap? = nil
    /// Loads the cross-day «moment of day» patterns (persists the daily summaries, then detects).
    /// Injected so the screen stays DB-free. `nil` → no pattern line. (FER-378)
    var patternsLoader: (() async -> [StressTimeOfDayPatterns.Pattern])? = nil
    /// Loads the cross-day «by calendar-event» patterns (one on-device EventKit read, nothing persisted).
    /// Runs after `patternsLoader` so the daily summaries it reads are already backfilled. (FER-388)
    var eventPatternsLoader: (() async -> [StressEventPatterns.Pattern])? = nil
    /// `true` cuando Apple Salud NO está autorizado (mismo predicado que Sueño/Esfuerzo, FER-101).
    /// TodayView ya lo pasa; el cabo real es CuerpoView, que cablea FER-100.
    var sinPermiso: Bool = false

    /// The trend block's period window (W/M/3M/6M/1Y/ALL). Defaults to a month.
    @State private var range: ExploreRange = .month
    /// The stress series with each point's `Date` already parsed (from `fullTrend`) — the window math
    /// reads `date` straight from here. Built in `.task`. (FER-216 lesson)
    @State private var parsed: [(day: String, date: Date?, value: Double)] = []
    /// The 90-day heat grid, built ONCE in `.task` (90 `DateFormatter` passes) instead of on every body
    /// eval — the recompute was jank on open. (FER-878+)
    @State private var stressHeatCache: [RecoveryDay] = []
    /// Detected cross-day «moment of day» patterns (loaded in `.task`). Empty → no line. (FER-378)
    @State private var patterns: [StressTimeOfDayPatterns.Pattern] = []
    /// Detected cross-day «by calendar-event» patterns (loaded in `.task`). Empty → no line. (FER-388)
    @State private var eventPatterns: [StressEventPatterns.Pattern] = []
    /// El día tocado en el calendario, por su llave de día. (FER-832)
    @State private var selectedStressDayID: String? = nil
    /// El ⓘ del campo abre la tarjeta «Qué medimos» bajo él. (FER-860)
    @State private var infoOpen = false
    /// El carril del historial que el dedo explora; `nil` = ninguno (paridad Sueño/Esfuerzo).
    @State private var bandaExplorada: Int? = nil

    /// El tono de la pantalla: el CALOR del nivel de hoy (tinta500 bajo · ocre medio · siena
    /// alto), nunca un semáforo — es la identidad Liquid del estrés (FER-73 · HJ-09 / FER-60;
    /// `LiquidMetricSheetView.tono` :239-246 y `MatrizEscalerita.colorNivel` son la misma rampa).
    /// Sin lectura fresca cae a la tinta neutra, como la hoja de Hoy sin dato.
    private var tono: Color {
        guard let model, model.heroIsFresh else { return LiquidColor.tinta500 }
        return MatrizEscalerita.colorNivel(Self.indiceCarril(model.score) ?? 0)
    }

    // MARK: - Body — el esqueleto del bloque, en vidrio

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: .zero) {
                if let model {
                    // Level 1 · campo. Falls back to yesterday's reading (dated sello) when today is
                    // still incomplete; never blanks the screen. (FER-397)
                    if model.heroIsFresh {
                        campoConDato(model)
                    } else {
                        campoSinDato
                    }
                    if infoOpen { whatWeMeasureCard }
                    // Niveles = solo la lectura «Hoy cae en…» (UX-08: los rangos viven en la
                    // escalera tocable del historial). Con ancla en ayer la frase mentiría,
                    // así que la sección entera se oculta (gate `anchorIsToday`).
                    if model.anchorIsToday {
                        seccion(String(localized: "Levels")) { levelsContent(model) }
                    }
                    // Level 1.5 · mapa del día BEFORE «qué lo mueve» (FER-433).
                    if let dayMap {
                        seccion(String(localized: "Stress through the day")) {
                            StressDayMapBlock(model: dayMap, tono: tono)
                        }
                    }
                    if model.heroIsFresh {
                        // B2/UX-05: clave propia, paralela a «Qué mueve tu esfuerzo».
                        seccion(String(localized: "What moves your stress")) { whatMovesContent(model) }
                    }
                    if hasPatternsSection(model) {
                        seccion(String(localized: "Your patterns")) { patternsContent(model) }
                    }
                    // UX-04: la sección monta hasta que el parseo terminó (calco del gate
                    // `durationParsed.count >= 2` de Sueño) — sin brinco del primer frame.
                    if parsed.count >= 2 {
                        seccion(String(localized: "History")) { historyContent(model) }
                    }
                    if parsed.contains(where: { $0.value > 0 }) {
                        seccion(String(localized: "Calendar · 90 days")) { calendarContent }
                    }
                    pieMetodo(model)
                } else {
                    campoSinDato
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // El fondo va en las DOS formas de presentación, como Sueño/Esfuerzo (FER-102/101).
        .background { LiquidSheetFondo(tone: tono).ignoresSafeArea() }
        .presentationBackground { LiquidSheetFondo(tone: tono) }
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(LiquidRadius.hoja)
        // FER-954: hop the parse + 90-day heat build off-main (same seam as Sueño/Recuperación/
        // Esfuerzo, FER-953). The async loaders stay exactly as they were.
        .task {
            range = .month
            let fullTrend = model?.fullTrend ?? []
            let todayKey = Repository.localDayKey(Date())   // main-isolated: resolve before the hop
            let (newParsed, heat) = await Task.detached(priority: .userInitiated) {
                Self.parseAndBuildHeat(fullTrend: fullTrend, todayKey: todayKey)
            }.value
            parsed = newParsed
            stressHeatCache = heat
            if let patternsLoader { patterns = await patternsLoader() }
            if let eventPatternsLoader { eventPatterns = await eventPatternsLoader() }
        }
    }

    /// Off-main parse + heat build (FER-954): the `.task`'s single hop, kept as one `nonisolated`
    /// helper so `Self.dayParser` reads the same static formatter used everywhere else on the screen.
    private nonisolated static func parseAndBuildHeat(
        fullTrend: [TrendPoint], todayKey: String
    ) -> (parsed: [(day: String, date: Date?, value: Double)], heat: [RecoveryDay]) {
        let parsed = fullTrend.map {
            (Self.dayParser.string(from: $0.date), Optional($0.date), $0.value)
        }
        let heat = Self.buildStressHeat(
            values: fullTrend.map { (Self.dayParser.string(from: $0.date), $0.value) },
            todayKey: todayKey)
        return (parsed, heat)
    }

    /// Una sección: la costura a sangre + su contenido con el margen del sistema.
    @ViewBuilder
    private func seccion<Content: View>(_ titulo: String, @ViewBuilder content: () -> Content) -> some View {
        LiquidFranjaSeccion(titulo, tono: tono)
        content().liquidSeccion()
    }

    // MARK: - 1. El campo (héroe) — calor del nivel, nunca semáforo

    /// El campo teñido a sangre con dato: numeral + «de 3», el veredicto es la frase del motor
    /// (`model.explanation`, fuente única de contenido — FER-860) cuando el ancla ES hoy, y una
    /// cláusula datada en pasado cuando el ancla es ayer (UX-06: `model.explanation` habla en
    /// presente/«today» y el modelo está congelado, así que la vista degrada — como Sueño con
    /// «anoche»). Al pie, el sello con fecha cuando el ancla es ayer (FER-397).
    private func campoConDato(_ model: StressModel) -> some View {
        LiquidCampoMetrica(
            tono: tono,
            titulo: String(localized: "Stress"),
            glifo: .estres,
            datos: [.init(valor: fmt(model.score), rotulo: String(localized: "of 3"),
                          a11y: String(localized: "\(fmt(model.score)) out of 3"))],
            veredicto: model.anchorIsToday ? model.explanation : clausulaAncladaAyer(model),
            infoAbierto: infoOpen,
            infoEtiqueta: String(localized: "What we measure"),
            onInfo: { withAnimation(LiquidMotion.lift) { infoOpen.toggle() } }
        ) {
            if !model.anchorIsToday {
                LiquidCampoSello(String(localized: "yesterday · \(chipDate(model.anchorDayKey))"))
            }
        }
    }

    /// La cláusula del campo con ancla en ayer (UX-06): fecha el nivel y no promete «hoy» —
    /// el dato fresco llega cuando el reloj sincroniza.
    private func clausulaAncladaAyer(_ model: StressModel) -> String {
        let nivel = Self.indiceCarril(model.score).map { Self.bandasEstres[$0].label } ?? ""
        return String(localized: "Yesterday's reading fell in \(nivel). Today's refreshes after your Apple Watch syncs.")
    }

    /// El campo APAGADO: sin lectura fresca el numeral es un guion, nunca un cero. Mismo patrón
    /// que `SleepDetailScreen.campoApagado` / `StrainDetailScreen.campoSinDato`.
    private var campoSinDato: some View {
        LiquidCampoMetrica(
            tono: LiquidColor.tinta500,
            titulo: String(localized: "Stress"),
            glifo: .estres,
            datos: [.init(valor: LiquidCajita.sinDato, rotulo: String(localized: "of 3"),
                          a11y: String(localized: "no data"), ausente: true)],
            clausula: clausulaSinDato
        ) {
            if sinPermiso {
                LiquidVerMas(title: String(localized: "Manage Apple Health permissions"),
                             tone: LiquidColor.papelAlto) { Self.abrirAjustesSalud() }
            }
        }
    }

    /// Tres vacíos distintos, no uno: sin permiso · con historia sin dato fresco · vacío total.
    /// Mismo árbol que `SleepDetailScreen.clausulaVacia`. (No hay rama «cargando»: el modelo
    /// llega construido de forma síncrona por el caller — sin flag `loaded` en el contrato.)
    private var clausulaSinDato: String {
        if sinPermiso {
            return String(localized: "Cénit can't read your stress: Apple Health hasn't granted permission. Turn it on and your readings will show up here.")
        }
        if model != nil {
            return String(localized: "No reading in the last couple of days. Wear your Apple Watch to sleep and it refreshes after it syncs: your history is below.")
        }
        return String(localized: "No stress reading yet. Wear your Apple Watch to sleep and open this again after it syncs. Stress is read from your resting heart rate and HRV.")
    }

    /// Abre Ajustes de iOS en la ficha de la app — mismo atajo que Sueño/Esfuerzo (FER-102).
    private static func abrirAjustesSalud() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    /// La tarjeta del ⓘ bajo el campo: qué mide el score, en lenguaje llano. Mismo patrón que
    /// `SleepDetailScreen.queMedimosCard`.
    private var whatWeMeasureCard: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s150) {
            Text(String(localized: "What we measure"))
                .font(LiquidType.tituloFila)
                .foregroundStyle(LiquidColor.tinta900)
            Text(heroExplanation)
                .font(LiquidType.cuerpo)
                .lineSpacing(LiquidType.cuerpoLineSpacing)
                .foregroundStyle(LiquidColor.tinta700)
                .fixedSize(horizontal: false, vertical: true)
        }
        .liquidTarjetaSeccion()
        .liquidSeccion(top: LiquidSpace.s400, bottom: LiquidSpace.s200)
    }

    /// El copy del ⓘ — carga autonómica en 0–3. Texto SIN CAMBIOS (misma clave).
    private var heroExplanation: String {
        String(localized: "Your autonomic load for the day: how activated your body is. We compare today's resting heart rate and HRV with your own 30-day baseline and map the combined shift onto a 0–3 scale (0 calm, 1.5 your baseline, 3 highly activated). It's an estimate, not a diagnosis.")
    }

    /// «sáb 20 jun» para el sello datado. UTC matches the day key. (FER-397)
    private func chipDate(_ dayKey: String) -> String {
        Self.dayParser.date(from: dayKey).map { Self.chipDateFormatter.string(from: $0) } ?? ""
    }

    // MARK: - 2. Niveles — la lectura del ancla contra la escalera única
    //
    // UX-08 (pasada F4/F5): UNA sola escalera visible por pantalla. La `LiquidBandsTable`
    // estática duplicaba los rangos que la `LiquidLevelsList` TOCABLE del historial ya
    // enseña; aquí queda solo «Hoy cae en…», y la sección entera se oculta cuando el ancla
    // no es hoy (gate en el body — con ancla en ayer la frase mentiría).

    @ViewBuilder private func levelsContent(_ model: StressModel) -> some View {
        if model.anchorIsToday, let i = Self.indiceCarril(model.score) {
            let b = Self.bandasEstres[i]
            LiquidReadingLine(
                String(localized: "Today falls in \(b.label) · fixed scale from 0 to 3"),
                highlight: b.label, highlightTone: tono)
        }
    }

    // MARK: - 3. Qué lo mueve — FC reposo + VFC vs base

    private func whatMovesContent(_ model: StressModel) -> some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s300) {
            LiquidCajitaGrid {
                markerCajita(rotulo: String(localized: "Resting HR"),
                             valor: model.rhrToday.map { "\($0)" },
                             delta: model.rhrDelta,
                             tono: LiquidColor.rosa)
                markerCajita(rotulo: String(localized: "HRV"),
                             valor: model.hrvToday.map { "\(Int($0.rounded()))" },
                             delta: model.hrvDelta,
                             tono: LiquidColor.cian)
            }
            LiquidNotaLine(whatMovesAnchor(model))
        }
    }

    /// Un marcador como `LiquidCajita`: el valor de hoy en su hue de dato (rosa corazón / cian
    /// VFC, paridad `LiquidMetricSheetView`), el delta con signo en el pie. |Δ| < 0.5 → «en tu
    /// base» (mismo umbral que la presentación anterior — cero matemática nueva).
    private func markerCajita(rotulo: String, valor: String?, delta: Double?,
                              tono: Color) -> some View {
        let pie: String
        if let delta, abs(delta) >= 0.5 {
            let up = delta > 0
            let mag = Int(abs(delta).rounded())
            let flecha = up ? "▲ +\(mag)" : "▼ −\(mag)"
            let caption = up
                ? String(localized: "above your base")
                : String(localized: "below your base")
            pie = "\(flecha) · \(caption)"
        } else {
            pie = String(localized: "at your base")
        }
        return LiquidCajita(rotulo: rotulo,
                            valor: valor ?? LiquidCajita.sinDato,
                            pie: pie,
                            tono: valor == nil ? nil : tono)
    }

    /// Short anchor from the same RHR/HRV deltas the tiles already show (presentation only).
    private func whatMovesAnchor(_ model: StressModel) -> String {
        let rhrOff = (model.rhrDelta.map { abs($0) >= 0.5 } ?? false)
        let hrvOff = (model.hrvDelta.map { abs($0) >= 0.5 } ?? false)
        let rhrUp = (model.rhrDelta ?? 0) > 0
        let hrvDn = (model.hrvDelta ?? 0) < 0
        if rhrOff && hrvOff && rhrUp && hrvDn {
            return String(localized: "Resting HR up and HRV down from your base: classic signs of activation.")
        }
        if rhrOff || hrvOff {
            // La frase del papel citaba los colores ámbar/verde de sus deltas; el pie de la
            // cajita Liquid es tinta neutra, así que la frase dice la DIRECCIÓN, no un color.
            return String(localized: "Markers vs your base: resting heart rate up or HRV down reads as activation.")
        }
        // «today» solo cuando el ancla ES hoy (TND11-6): los deltas son del día anclado.
        return model.anchorIsToday
            ? String(localized: "Both markers near your base today.")
            : String(localized: "Both markers near your base yesterday.")
    }

    // MARK: - 4. Tus patrones — calma + regularidad + observaciones (FER-378/388)

    /// Calm time / steadiness always when the model has them; observations card only when a pattern
    /// clears its sufficiency gate. If neither tiles nor observations have anything, the section hides.
    private func hasPatternsSection(_ model: StressModel) -> Bool {
        model.calmTimeValue != "—"
            || consistency(model) != nil
            || patterns.first != nil
            || eventPatterns.first != nil
    }

    private func patternsContent(_ model: StressModel) -> some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s300) {
            LiquidCajitaGrid {
                // Sin verde de veredicto en el valor de «tiempo en calma»: el estrés no viste
                // colores de juicio en Liquid (HJ-09) — tinta, como «constancia».
                LiquidCajita(rotulo: String(localized: "Calm time"),
                             valor: model.calmTimeValue,
                             pie: String(localized: "of last month"),
                             compacto: true)
                LiquidCajita(rotulo: String(localized: "Steadiness"),
                             valor: consistency(model).map { consistencyWord($0) } ?? LiquidCajita.sinDato,
                             pie: String(localized: "week to week"),
                             compacto: true)
            }
            if patterns.first != nil || eventPatterns.first != nil {
                observationsCard
            }
        }
    }

    /// «LO QUE VEMOS EN TU HISTORIAL» + chip «TENDENCIA, NO CAUSA» + líneas no causales.
    /// UX-09: la pieza es `LiquidTendenciaCard` (la MISMA que Esfuerzo) — el chip punteado
    /// ya no se copia a mano por pantalla.
    private var observationsCard: some View {
        LiquidTendenciaCard(
            overline: String(localized: "What we see in your history"),
            chip: String(localized: "trend, not cause"),
            lineas: observationLines)
    }

    /// Las MISMAS frases de siempre (claves intactas), resueltas a `String` para la tarjeta.
    private var observationLines: [String] {
        var out: [String] = []
        if let p = patterns.first { out.append(patternSentence(p)) }
        if let e = eventPatterns.first { out.append(eventPatternSentence(e)) }
        return out
    }

    private func patternSentence(_ p: StressTimeOfDayPatterns.Pattern) -> String {
        switch p.family {
        case .partOfDay(let part):
            let noun = partNoun(part)
            return p.higher
                ? String(localized: "Your stress tends to run higher in the \(noun).")
                : String(localized: "Your stress tends to run lower in the \(noun).")
        case .weekday(let wd):
            let name = Calendar.current.weekdaySymbols[max(0, min(6, wd - 1))]
            return p.higher
                ? String(localized: "Your stress tends to run higher on \(name).")
                : String(localized: "Your stress tends to run lower on \(name).")
        case .peakHour(let h):
            let d = Calendar.current.date(bySettingHour: h, minute: 0, second: 0, of: Date()) ?? Date()
            return String(localized: "Your stress usually peaks around \(d.formatted(.dateTime.hour())).")
        }
    }

    private func partNoun(_ part: PartOfDay) -> String {
        switch part {
        case .morning:   return String(localized: "mornings")
        case .afternoon: return String(localized: "afternoons")
        case .evening:   return String(localized: "evenings")
        case .night:     return String(localized: "late nights")
        }
    }

    private func eventPatternSentence(_ e: StressEventPatterns.Pattern) -> String {
        e.higher
            ? String(localized: "«\(e.title)» tends to coincide with higher stress.")
            : String(localized: "«\(e.title)» tends to coincide with lower stress.")
    }

    private func consistencyWord(_ pct: Int) -> String {
        switch pct {
        case ..<8:   return String(localized: "Very steady")
        case 8..<15: return String(localized: "Steady")
        default:     return String(localized: "Variable")
        }
    }

    private func consistency(_ model: StressModel) -> Int? {
        SeriesShape.coefficientOfVariation(model.fullTrend.map(\.value), window: 7)
            .map { Int(($0 * 100).rounded()) }
    }

    // MARK: - 5. Ver tu historial — selector + gráfica + resumen + escalera

    private func historyContent(_ model: StressModel) -> some View {
        let window = MetricWindowMath.make(parsed, selected: range)
        let stat = ComparisonEngine.stat(window.values)
        let seriesPairs = parsed.map { ($0.day, $0.value) }
        let pct = range.periodComparison(of: seriesPairs)?.pctChange
        return VStack(alignment: .leading, spacing: LiquidSpace.s300) {
            LiquidRangeSelector(opciones: ExploreRange.allCases.map(\.label),
                                seleccion: rangeSeleccion, tono: tono)
            if window.values.count > 1 {
                VStack(alignment: .leading, spacing: LiquidSpace.s300) {
                    fraseNivelHistorial(model, window)
                    if let pct {
                        // Menos estrés es mejor: verde cuando baja, ámbar-texto cuando sube
                        // (misma valencia que su fila de Hoy, `betterHigher: false`).
                        LiquidNotaLine(pct >= 0 ? "+\(Int(pct.rounded()))%" : "\(Int(pct.rounded()))%",
                                       tono: pct <= 0 ? LiquidColor.positivo : LiquidColor.atencionTexto)
                    }
                    graficaHistorial(model, window)
                    LiquidNotaLine(String(localized: "Raw daily values, no smoothing: stress is read day to day. Lower is better."))
                    LiquidResumenVentana(celdas: [
                        .init(rotulo: String(localized: "Average"), valor: fmt(stat.mean)),
                        .init(rotulo: String(localized: "Range"),
                              valor: "\(fmt(stat.min))–\(fmt(stat.max))"),
                        // UX-14: con ancla fresca en AYER la celda dice «Ayer» con su score
                        // (no un guion bajo «Hoy» — el dato existe, solo es de ayer, TND11-1);
                        // con ancla más vieja vuelve «Hoy» + guion.
                        .init(rotulo: model.heroIsFresh && !model.anchorIsToday
                                ? String(localized: "Yesterday") : String(localized: "Today"),
                              valor: model.heroIsFresh ? fmt(model.score) : LiquidCajita.sinDato,
                              tono: model.heroIsFresh ? tono : nil),
                    ])
                }
                .liquidTarjetaSeccion()
                LiquidLevelsList(filas: carrilesHistorial(model, window), tono: tono)
                LiquidNotaLine(String(localized: "How many days of the period fell in each band. Tap one to see its days on the chart."))
            } else {
                LiquidGraficaNiveles(puntos: [], bandas: [], dominio: Self.dominioEstres, ticksY: [],
                                     tono: tono,
                                     estadoVacio: String(localized: "Not enough days in this range to draw a trend."),
                                     a11yLabel: String(localized: "Stress history"))
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

    /// El carril de HOY, o nil cuando el ancla es ayer o no hay lectura (TND11-5: lo que
    /// afirma «hoy» — la frase y el chip «· hoy» — usa este predicado `anchorIsToday`, el
    /// mismo de «Hoy cae en…»; el campo, que SÍ fecha su dato con el sello, sigue en
    /// `heroIsFresh`).
    private func indiceAncla(_ model: StressModel) -> Int? {
        model.anchorIsToday ? Self.indiceCarril(model.score) : nil
    }

    /// El carril del ANCLA FRESCA (hoy o ayer) — el resaltado de la gráfica y la escalera
    /// tocable puede marcar el carril de ayer sin afirmar «hoy» (UX-14: el chip «· hoy»
    /// sigue gateado a `anchorIsToday` vía `indiceAncla`).
    private func indiceAnclaFresca(_ model: StressModel) -> Int? {
        model.heroIsFresh ? Self.indiceCarril(model.score) : nil
    }

    /// El carril resaltado: el que el dedo explora, o si no hay ninguno, el del ancla fresca.
    private func destacado(_ model: StressModel) -> Int? {
        bandaExplorada ?? indiceAnclaFresca(model)
    }

    /// El carril de HOY y cuántos días del periodo cayeron con él — mismo contrato que
    /// `SleepDetailScreen.fraseNivelHistorial` / `StrainDetailScreen.fraseNivelHistorial`.
    @ViewBuilder private func fraseNivelHistorial(_ model: StressModel, _ window: MetricWindow) -> some View {
        if let i = indiceAncla(model) {
            let b = Self.bandasEstres[i]
            let n = window.values.filter { v in
                (b.lo == nil || v >= b.lo!) && (b.hi == nil || v < b.hi!)
            }.count
            LiquidFraseNivel(nivel: b.label,
                             conteo: String(localized: "\(n) of your last \(window.values.count) days"),
                             tono: tono)
        } else {
            LiquidFraseNivel(nivel: nil,
                             conteo: String(localized: "\(window.values.count) days with data in this range"),
                             tono: tono,
                             sinLectura: String(localized: "No reading today"))
        }
    }

    /// La gráfica del historial: la serie CRUDA día a día (nunca suavizada — mismo criterio que
    /// «Instrumento»: el estrés se lee día a día), con los carriles fijos detrás.
    private func graficaHistorial(_ model: StressModel, _ window: MetricWindow) -> some View {
        let puntos = MetricWindowMath
            .decimatedPoints(rows: window.rows, values: window.values, maxPoints: 80)
            .map { (fecha: $0.date, valor: $0.value) }
        return LiquidGraficaNiveles(
            puntos: puntos,
            bandas: Self.bandasEstres.enumerated().map { i, b in
                LiquidChartBanda(lo: b.lo, hi: b.hi, color: b.color, activa: i == destacado(model))
            },
            dominio: Self.dominioEstres,
            // Los ticks afirman los CORTES reales del motor (1 y 2) más el techo de la escala.
            ticksY: [(3, "3"), (2, "2"), (1, "1")],
            tono: tono,
            // La joya de «hoy» solo cuando el ancla ES hoy (TND11-4): con ancla en ayer el
            // último punto es ayer y la gráfica lo vestiría de hoy.
            puntoHoy: model.anchorIsToday ? puntos.last : nil,
            hoyAnillo: bandaExplorada != nil && bandaExplorada != indiceAncla(model),
            formatoScrub: { v, f in "\(fmt(v)) · \(Self.ejeFechaFmt.string(from: f))" },
            formatoValorScrub: { fmt($0) },
            formatoFechaScrub: { Self.ejeFechaFmt.string(from: $0) },
            formatoFechaEje: { Self.ejeFechaFmt.string(from: $0) },
            atenuarFuera: bandaExplorada != nil,
            estadoVacio: String(localized: "Not enough days in this range to draw a trend."),
            a11yLabel: String(localized: "Stress history"))
            .id(range)
    }

    /// Los carriles tocables bajo la gráfica: tocar uno resalta sus días; re-tocarlo limpia.
    /// Mismo contrato que `SleepDetailScreen.carrilesHistorial` / `StrainDetailScreen`.
    private func carrilesHistorial(_ model: StressModel, _ window: MetricWindow) -> [LiquidLevelsList.Fila] {
        let hint = String(localized: "Highlights this level on the chart")
        let hoyRotulo = String(localized: "· today")
        let iAncla = indiceAncla(model)
        return Self.bandasEstres.indices.map { i in
            let b = Self.bandasEstres[i]
            let n = window.values.filter { v in
                (b.lo == nil || v >= b.lo!) && (b.hi == nil || v < b.hi!)
            }.count
            return LiquidLevelsList.Fila(
                etiqueta: b.label, rango: b.range,
                conteo: n == 1 ? String(localized: "\(n) day") : String(localized: "\(n) days"),
                // «· hoy» solo cuando el ancla ES hoy — con ancla en ayer sería mentira.
                esHoy: model.anchorIsToday && i == iAncla,
                activa: i == destacado(model),
                hoyEtiqueta: hoyRotulo, a11yHint: hint,
                onTap: {
                    withAnimation(LiquidMotion.lift) {
                        bandaExplorada = (bandaExplorada == i) ? nil : i
                    }
                })
        }
    }

    // MARK: - La escalera única — UNA sola, compartida por niveles/historial/calendario/mapa
    //
    // FER-101 · TND-11: la pantalla de papel traía TRES vocabularios y DOS copias de los cortes
    // (la mini-escala «Calm/Your base/Activated», la gráfica «Low/Base/Activated» con su propio
    // arreglo `stressBands`, y el calendario/héroe «Low/Moderate/High» vía `StressBand.displayWord`).
    // Se deriva UNA vez de `MetricLevels.displayBands(for: .stress)` — la escalera del motor
    // (low 0–1 · medium 1–2 · high 2–3) — y TODO deriva de aquí por CLAVE. La palabra queda
    // Low/Medium/High, la MISMA que la Matriz de Hoy (`palabraStress`). El color por carril es
    // la rampa de calor canónica `MatrizEscalerita.colorNivel` (M35-04: un solo mapa).

    struct BandaEstres {
        let key: String
        let label: String
        let lo: Double?
        let hi: Double?
        let color: Color
        let range: String
    }

    static let bandasEstres: [BandaEstres] = MetricLevels.displayBands(for: .stress)
        .enumerated().map { i, band in
            BandaEstres(key: band.key,
                        label: String(localized: String.LocalizationValue(band.name)),
                        lo: band.lower, hi: band.upper,
                        color: MatrizEscalerita.colorNivel(i),
                        range: band.range)
        }

    /// El carril en que cae un valor. Único predicado numérico de la pantalla (y del mapa del día).
    static func indiceCarril(_ v: Double) -> Int? {
        bandasEstres.firstIndex { b in (b.lo == nil || v >= b.lo!) && (b.hi == nil || v < b.hi!) }
    }

    /// La palabra del carril — la MISMA en niveles, historial, calendario y mapa del día.
    static func palabraEstres(_ v: Double) -> String {
        guard let i = indiceCarril(v) else { return bandasEstres.first?.label ?? "" }
        return bandasEstres[i].label
    }

    /// El calor del carril de un valor — la rampa canónica, también para el mapa del día.
    static func tonoEstres(_ v: Double) -> Color {
        MatrizEscalerita.colorNivel(indiceCarril(v) ?? 0)
    }

    /// El dominio Y del historial: 0–3, la escala entera (como el papel).
    private static let dominioEstres: ClosedRange<Double> = 0...3

    private static let ejeFechaFmt: DateFormatter = {
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("dMMM"); return f
    }()

    // MARK: - 6. Calendario · 90 días

    private var calendarContent: some View {
        LiquidCalendario90(
            dias: calendarioDias,
            tono: Self.tonoCalendario,
            leyenda: Self.leyendaCalendario,
            seleccion: $selectedStressDayID,
            a11yLabel: String(localized: "Calendar · 90 days"),
            pistaVacia: String(localized: "Tap a day to see its stress."),
            sinLectura: String(localized: "no data"),
            a11yConteo: { conDato, total in
                String(localized: "\(conDato) of your last \(total) days")
            })
    }

    /// El tono FIJO de la retícula: el extremo siena de la rampa de calor. La retícula Liquid
    /// gradúa UN tono por alfa (no puede pintar la rampa de tres hues del papel), así que el
    /// calor sube ocre→siena por opacidad y el tono no cambia con el nivel de hoy (recolorear
    /// 90 días de historia según hoy mentiría).
    private static let tonoCalendario = LiquidColor.estresAlto

    /// Los 90 días, ya resueltos desde el heat cache: la retícula no formatea ni una fecha.
    private var calendarioDias: [LiquidCalendario90.Dia] {
        var mesVisto: String? = nil
        return stressHeatCache.map { dia -> LiquidCalendario90.Dia in
            let key = Self.dayParser.string(from: dia.date)
            let mes = Self.mesFmt.string(from: dia.date)
            let rotuloMes: String? = mes == mesVisto ? nil : mes
            mesVisto = mes
            let v = dia.score
            return LiquidCalendario90.Dia(
                id: key, fecha: dia.date,
                intensidad: v.map(Self.intensidadEstres),
                etiqueta: Self.ejeFechaFmt.string(from: dia.date),
                valor: v.map(fmt),
                palabra: v.map(Self.palabraEstres),
                mes: rotuloMes)
        }
    }

    /// La intensidad de la retícula, graduada por la MISMA escalera de 3 carriles que Niveles
    /// e Historial (paridad `StrainDetailScreen.intensidadEsfuerzo`).
    static func intensidadEstres(_ v: Double) -> Double {
        guard let i = indiceCarril(v) else { return 0 }
        return alturaNivel(bandasEstres[i].key)
    }

    /// El peldaño de cada carril en la retícula. ÚNICO mapa: lo leen la celda y la leyenda,
    /// para que el swatch de una palabra sea EXACTAMENTE la tinta de su carril (TND10-1).
    private static func alturaNivel(_ key: String) -> Double {
        switch key {
        case "high":   return 1.0
        case "medium": return 0.55
        default:       return 0        // "low" — el más tenue
        }
    }

    /// La leyenda: los tres carriles + «sin dato». Cada swatch lleva la tinta REAL de su carril
    /// vía `alturaNivel` (TND10-1), y la palabra es LA MISMA de la escalera única, en minúscula
    /// (como la Matriz de Hoy, `palabraStress` — nunca un segundo vocabulario).
    private static var leyendaCalendario: [LiquidCalendario90.NivelLeyenda] {
        var out = bandasEstres.reversed().map { b in
            LiquidCalendario90.NivelLeyenda(
                id: b.key,
                color: tonoCalendario.opacity(LiquidCalendario90.alfa(intensidad: alturaNivel(b.key))),
                etiqueta: b.label.lowercased(with: Locale.current))
        }
        out.append(.init(id: "nodata", color: LiquidColor.tinta7,
                         etiqueta: String(localized: "no data")))
        return out
    }

    /// Builds the 90-day heat grid from a parsed value snapshot (FER-954: pure / off-main-safe, same
    /// shape as `SleepDetailScreen.buildSleepHeat`). `todayKey` llega del caller en MainActor
    /// (`Repository.localDayKey` es main-isolated).
    private nonisolated static func buildStressHeat(values: [(day: String, value: Double)],
                                                     todayKey: String) -> [RecoveryDay] {
        var vals: [String: Double] = [:]
        for r in values { vals[r.day] = r.value }
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        // Ancla la ventana de 90 dias al dia LOCAL, igual que Recovery.buildHeat. Anclar al dia UTC
        // hace que en husos negativos, por la tarde, la ventana empiece en otro dia de la semana que
        // Recovery y el grid dibuje 13 vs 14 columnas, con celdas de otro tamano. Asi los cuatro
        // calendarios (Recuperacion, Sueno, Esfuerzo, Estres) miden igual. (FER calendarios mismo tamano)
        guard let today = Repository.parseDayKey(todayKey) else { return [] }
        return stride(from: 89, through: 0, by: -1).compactMap { off -> RecoveryDay? in
            guard let date = cal.date(byAdding: .day, value: -off, to: today) else { return nil }
            return RecoveryDay(date: date.addingTimeInterval(12 * 3600),
                               score: vals[Self.dayParser.string(from: date)])
        }
    }

    // MARK: - Método + sello — patrón `pieMetodo` de Sueño (capilar sin franja propia)

    private func pieMetodo(_ model: StressModel) -> some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s300) {
            LiquidCapilar(eje: .horizontal)
            LiquidMetodo(title: String(localized: "How it's calculated"),
                         mostrar: String(localized: "Show explanation"),
                         ocultar: String(localized: "Hide explanation")) {
                LiquidNotaLine(model.usingStored
                    ? String(localized: "Today's value is your recorded daily stress score (0–3). The trend, bands and markers are derived the same way.")
                    : String(localized: "We compare today's resting heart rate and HRV with your own 30-day baseline. A higher-than-usual resting HR and a lower-than-usual HRV both push the score up: classic signs the body is activated. The combined shift becomes a z-score sum, squashed onto 0–3 by a logistic curve: 0 calm, 1.5 at your baseline, 3 highly activated."),
                               tono: LiquidColor.tinta700)
                LiquidNotaLine(String(localized: "«Calm time» is the share of the last month that sat in the Low band; «steadiness» is how much your daily index varies week to week (its coefficient of variation: lower is steadier). The Low / Medium / High bands (0–1 / 1–2 / 2–3) are the same for everyone because the index is already adjusted to your own baseline. (Plews 2013)"),
                               tono: LiquidColor.tinta700)
                LiquidNotaLine(String(localized: "Combined resting-HR / HRV z-score through a logistic curve. HRV via RMSSD (Task Force, 1996). An estimate, not a diagnosis."))
            }
            // M1: la MISMA clave de procedencia que la hoja de Hoy usa para el estrés
            // (`LiquidMetricSheetView.origenChipVista` → «Calculated on your phone»).
            LiquidOrigenChip(glyph: .estres, badgeTono: tono,
                             etiqueta: String(localized: "Calculated on your phone"),
                             sufijo: originWhen(model))
        }
        .liquidSeccion(top: LiquidSpace.s200, bottom: LiquidSpace.s800)
    }

    /// Origin stamp «when» — the day's anchor the screen already computes. M2: «ayer · fecha»
    /// SOLO con ancla fresca en ayer; con ancla más vieja el sello dice solo la fecha (no
    /// afirma un «ayer» que ya no es cierto).
    private func originWhen(_ model: StressModel) -> String {
        if model.anchorIsToday {
            return String(localized: "today")
        }
        if model.heroIsFresh {
            return String(localized: "yesterday · \(chipDate(model.anchorDayKey))")
        }
        return chipDate(model.anchorDayKey)
    }

    // MARK: - Format

    private func fmt(_ v: Double) -> String { String(format: "%.1f", v) }

    /// The canonical UTC day-key formatter — read side of the day-key contract (FER-754).
    /// FER-978: `nonisolated` so it's reachable from nonisolated contexts (DateFormatter is Sendable
    /// under strict concurrency; the property is immutable).
    nonisolated static let dayParser = DayKey.utcFormatter

    /// Short localized date for the fallback sello ("sáb 20 jun"). UTC zone matches the day key. (FER-397)
    static let chipDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "UTC")
        f.setLocalizedDateFormatFromTemplate("EEE d MMM")
        return f
    }()

    private static let mesFmt: DateFormatter = {
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("MMM"); return f
    }()
}

// MARK: - Sheet item

/// Identifiable wrapper so the Liquid Detalle de Estrés can ride `.sheet(item:)`. (FER-241)
struct StressDetailItem: Identifiable {
    let id = UUID()
    let model: StressModel?
}

// MARK: - Preview

#if DEBUG
private func sampleStressModel(score: Double) -> StressModel? {
    let cal = Calendar(identifier: .gregorian)
    let today = cal.startOfDay(for: Date())
    let f = StressDetailScreen.dayParser
    let stored: [(day: String, value: Double)] = (0..<60).map { i in
        let date = cal.date(byAdding: .day, value: -(59 - i), to: today)!
        let v = i == 59 ? score : 1.4 + 0.8 * sin(Double(i) / 3.0)
        return (f.string(from: date), Swift.max(0, Swift.min(3, v)))
    }
    let days: [DailyMetric] = stored.map { row in
        DailyMetric(day: row.day, totalSleepMin: nil, efficiency: nil, deepMin: nil,
                    remMin: nil, lightMin: nil, disturbances: nil,
                    restingHr: 54 + Int((row.value - 1.5) * 4),
                    avgHrv: 60 - (row.value - 1.5) * 8,
                    recovery: nil, strain: nil, exerciseCount: nil)
    }
    return StressModel(days: days, stored: stored, todayKey: f.string(from: today))
}

#Preview("Stress detail: moderate") {
    Color.clear.sheet(isPresented: .constant(true)) {
        StressDetailScreen(model: sampleStressModel(score: 1.8))
    }
}

#Preview("Stress detail: empty") {
    Color.clear.sheet(isPresented: .constant(true)) {
        StressDetailScreen(model: nil)
    }
}

#Preview("Stress detail: sin permiso") {
    Color.clear.sheet(isPresented: .constant(true)) {
        StressDetailScreen(model: nil, sinPermiso: true)
    }
}
#endif
#endif
