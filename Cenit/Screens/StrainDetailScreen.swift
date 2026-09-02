#if os(iOS)
import SwiftUI
import CenitDesign
import StrandAnalytics
import CenitStore
import Foundation

// MARK: - StrainDetailScreen — el «Detalle de Esfuerzo» en vidrio Liquid (FER-101 · TND-10)
//
// Migración PURAMENTE VISUAL del esqueleto «Tendencias Final» (papel «Instrumento») a los legos
// Liquid, calcando el patrón de `SleepDetailScreen.swift` (la vara de medir de esta migración):
// campo teñido a sangre (`LiquidCampoMetrica`) → costuras de sección (`LiquidFranjaSeccion`) →
// lectura de nivel (`LiquidReadingLine`; los rangos viven en la escalera tocable del historial,
// UX-08) → historial (`LiquidRangeSelector` + `LiquidGraficaNiveles` +
// `LiquidResumenVentana` + `LiquidLevelsList`) → calendario (`LiquidCalendario90`) → método + sello
// (`LiquidCapilar` + `LiquidMetodo` + `LiquidOrigenChip`, patrón `pieMetodo` de Sueño). Segunda
// referencia: `PreparacionDetailScreen.swift` (estados vacíos, skeleton, sin-permiso).
//
// `StrainDetailModel` NO CAMBIA (contrato de datos congelado para esta tarea): consume
// `StrandAnalytics` tal cual (hoy, la serie, los drivers) — cero math nueva. El esfuerzo sigue
// siendo DESCRIPTIVO, sin semáforo: el tono es SIEMPRE `LiquidColor.ambar` (identidad de esfuerzo,
// no juicio — ver el swatch «ámbar · esfuerzo/piel» en `LiquidColor.swift`).
//
// Se presenta vía `.sheet(item:)`, SIN `NavigationStack` anidado (FER-171).

/// Detalle de Esfuerzo en vidrio Liquid. Se arma UNA vez desde un `StrainDetailModel` (el caller
/// inyecta el modelo para que la pantalla siga sin tocar la base de datos).
struct StrainDetailScreen: View {
    /// Todo lo que la pantalla dibuja, derivado UNA vez por el caller desde `repo`. Contrato
    /// congelado para esta migración: NO se toca.
    let model: StrainDetailModel
    /// FER-885: el «Day load» de hoy es un estimado de FC de entrenamiento de Apple (modo
    /// solo-Apple, FER-883), no un Day Strain medido por banda. Cambia el sello del pie al de
    /// Apple y añade el hedge honesto de sub-conteo.
    var estimated: Bool = false
    /// `true` cuando Apple Salud NO está autorizado. Mismo predicado que Sueño/Hoy. (FER-101)
    var sinPermiso: Bool = false

    /// La ventana del historial (S/M/3M/6M/1A/TODO). Por omisión, un mes.
    @State private var range: ExploreRange = .month
    /// La serie de esfuerzo con cada llave de día parseada UNA vez en el `.task`.
    @State private var parsed: [(day: String, date: Date?, value: Double)] = []
    /// El día tocado en el calendario, por su llave de día. (FER-830)
    @State private var selectedStrainDayID: String? = nil
    /// El ⓘ del campo abre la tarjeta «Qué medimos» bajo él. (FER-859)
    @State private var infoOpen = false
    /// El carril del historial que el dedo explora; `nil` = ninguno (paridad Sueño/Carga).
    @State private var bandaExplorada: Int? = nil

    /// El tono de la pantalla: el esfuerzo es SIEMPRE ámbar-identidad, nunca un semáforo — esta
    /// hoja es descriptiva. (§8.9 DESIGN.md; swatch «ámbar · esfuerzo/piel» en `LiquidColor.swift`)
    private static let tono = LiquidColor.ambar

    // MARK: - Body

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: .zero) {
                if let v = shownToday {
                    campoConDato(v)
                } else {
                    campoSinDato
                }
                if infoOpen { whatWeMeasureCard }
                if !model.loaded {
                    LiquidSheetSkeleton(a11yCargando: String(localized: "Reading your day strain…"))
                        .liquidSeccion()
                } else if model.hasData {
                    // Niveles = solo la lectura del ancla (UX-08: los rangos viven en la
                    // escalera tocable del historial); sin lectura, la sección se oculta.
                    if indiceHoy != nil {
                        seccion(String(localized: "Levels")) { levelsContent }
                    }
                    // «Qué mueve tu esfuerzo» — franja propia entre Niveles e Historial
                    // (UX-09: una anatomía y una posición en las tres gemelas).
                    if !model.drivers.isEmpty {
                        seccion(String(localized: "What moves your strain")) { whatMovesCard }
                    }
                    // La sección monta hasta que el parseo terminó (UX-04, calco del gate
                    // `durationParsed.count >= 2` de Sueño): sin esto, el primer frame
                    // pinta la gráfica vacía y brinca al llegar `parsed`.
                    if parsed.count >= 2 {
                        seccion(String(localized: "History")) { historyContent }
                    }
                    if parsed.contains(where: { $0.value > 0 }) {
                        seccion(String(localized: "Calendar · 90 days")) { calendarContent }
                    }
                    pieMetodo
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background { LiquidSheetFondo(tone: Self.tono).ignoresSafeArea() }
        .presentationBackground { LiquidSheetFondo(tone: Self.tono) }
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(LiquidRadius.hoja)
        // FER-954: re-corre cuando el modelo placeholder se cambia por el real; parseo off-main.
        .task(id: model.loaded) {
            guard model.loaded else { return }   // pasada placeholder — nada que parsear (FER-954)
            range = .month
            let series = model.series
            parsed = await Task.detached(priority: .userInitiated) {
                series.map { ($0.day, Repository.parseDayKey($0.day), $0.value) }
            }.value
        }
    }

    /// Una sección: la costura a sangre + su contenido con el margen del sistema.
    @ViewBuilder
    private func seccion<Content: View>(_ titulo: String, @ViewBuilder content: () -> Content) -> some View {
        LiquidFranjaSeccion(titulo, tono: Self.tono)
        content().liquidSeccion()
    }

    // MARK: - 1. El campo (héroe) — un solo numeral, descriptivo, sin semáforo

    /// El valor mostrado como esfuerzo de hoy: el score asentado del día (`repo.today.strain`,
    /// estimado de FC de entrenamiento de Apple en modo solo-Apple). Contrato sin tocar.
    private var shownToday: Double? { model.today }

    /// El carril (de `bandasEsfuerzo`) en el que cae `shownToday`, o `nil` sin dato. Único
    /// predicado de la pantalla: lo leen el campo, la tabla de niveles, el historial y el
    /// calendario — nunca una segunda copia de los cortes (paridad `SleepDetailScreen.indiceCarril`).
    private var indiceHoy: Int? { shownToday.flatMap(Self.indiceCarril) }

    /// El campo teñido a sangre con dato: numeral + «de 21», veredicto de una frase, y al pie el
    /// aviso de «en curso» + el sello de confianza — la ranura libre que el campo existe para
    /// cargar (paridad `SleepDetailScreen.pieCampo`).
    private func campoConDato(_ v: Double) -> some View {
        LiquidCampoMetrica(
            tono: Self.tono,
            titulo: String(localized: "Effort"),
            glifo: .llama,
            datos: [.init(valor: fmt(v), rotulo: String(localized: "of 21"),
                         a11y: String(localized: "\(fmt(v)) out of 21"))],
            veredicto: heroReadingConDato(v),
            infoAbierto: infoOpen,
            infoEtiqueta: String(localized: "What we measure"),
            onInfo: { withAnimation(LiquidMotion.lift) { infoOpen.toggle() } }
        ) {
            VStack(alignment: .leading, spacing: LiquidSpace.s150) {
                // El score de hoy SIEMPRE está acumulándose (el esfuerzo se lee segundo a
                // segundo mientras el día corre) — el mismo aviso que la cápsula «en curso»
                // llevaba pegada al numeral en «Instrumento». (FER-101)
                LiquidCampoSello(String(localized: "in progress"))
                if let tier = model.confidence {
                    LiquidCampoSello(tier.confidenceLabelText, a11y: tier.confidenceA11yText)
                }
            }
        }
    }

    /// El campo APAGADO: sin dato de hoy (cargando, sin permiso, o con historia pero sin score
    /// de hoy) el numeral es un guion, nunca un cero. Mismo patrón que
    /// `SleepDetailScreen.campoApagado`.
    private var campoSinDato: some View {
        LiquidCampoMetrica(
            tono: Self.tono,
            titulo: String(localized: "Effort"),
            glifo: .llama,
            datos: [.init(valor: LiquidCajita.sinDato, rotulo: String(localized: "of 21"),
                         a11y: String(localized: "no data"), ausente: true)],
            clausula: clausulaSinDato
        ) {
            if sinPermiso {
                LiquidVerMas(title: String(localized: "Manage Apple Health permissions"),
                             tone: LiquidColor.papelAlto) { Self.abrirAjustesSalud() }
            }
        }
    }

    /// Tres vacíos distintos, no uno: cargando · sin permiso · con permiso y sin score de hoy.
    /// Mismo árbol de tres ramas que `SleepDetailScreen.clausulaVacia`.
    private var clausulaSinDato: String {
        guard model.loaded else { return String(localized: "Reading your day strain…") }
        if sinPermiso {
            return String(localized: "Cénit can't read your strain: Apple Health hasn't granted permission. Turn it on and today's workouts will show up here.")
        }
        if !model.series.isEmpty {
            return String(localized: "No strain from today yet: your recent history is below.")
        }
        return String(localized: "No strain yet. Day Strain builds from your workout heart rate: open this again after your next workout syncs from Apple Health.")
    }

    /// Abre Ajustes de iOS en la ficha de la app — mismo atajo que Sueño (FER-102).
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

    /// El copy del ⓘ — la explicación estándar del día (Edwards/Banister). Texto SIN CAMBIOS.
    private var heroExplanation: String {
        String(localized: "Day Strain is your cardiovascular load on a 0–21 scale. Each second your heart rate is recorded, it's placed in an intensity zone (1–5); higher zones weigh more, and the total is compressed logarithmically so 21 is a theoretical maximum: a full day at peak intensity. (Edwards 1993; Banister 1991)")
    }

    /// La frase de una línea bajo el numeral, por CLAVE de carril — las MISMAS cuatro frases de
    /// siempre, realineadas a la escalera única (TND10-2: el `switch` por índice venía de la era
    /// de 4 bandas y nunca se reordenó al pasar a 5, así que un día «Light» decía «Moderate
    /// effort» — un peldaño corrido en toda la escalera). Cuatro lecturas para cinco carriles:
    /// «rest» y «light» comparten la primera, igual que la hoja de Hoy nombra suave lo suave.
    private func heroReadingConDato(_ v: Double) -> String {
        // `indiceHoy` nunca es nil aquí (solo se llama con dato y la escalera es partición
        // total), pero el guion cae al carril más bajo, no al más alto.
        Self.fraseCarril(indiceHoy.map { Self.bandasEsfuerzo[$0].key } ?? "rest")
    }

    /// La frase por CLAVE, separada para que la guarda (`StrainEscaleraUnicaTests`) pueda fijar
    /// el mapeo carril→frase sin montar la vista.
    static func fraseCarril(_ key: String) -> String {
        switch key {
        case "rest", "light": return String(localized: "Light load today: plenty left in the tank.")
        case "moderate":      return String(localized: "Moderate effort today.")
        case "hard":          return String(localized: "Hard effort today: solid work.")
        default:              return String(localized: "All-out day: about as much strain as you carry.")
        }
    }

    // MARK: - 2. Niveles — la lectura del ancla contra la escalera única
    //
    // UX-08 (pasada F4/F5): UNA sola escalera visible por pantalla. La `LiquidBandsTable`
    // estática duplicaba los rangos que la `LiquidLevelsList` TOCABLE del historial ya
    // enseña; aquí queda solo la lectura «Hoy cae en…». La sección entera se oculta sin
    // lectura del ancla (gate en el body).

    @ViewBuilder private var levelsContent: some View {
        if let i = indiceHoy {
            let b = Self.bandasEsfuerzo[i]
            LiquidReadingLine(
                String(localized: "Today falls in \(b.label) · fixed scale from 0 to 21"),
                highlight: b.label, highlightTone: Self.tono)
        }
    }

    // MARK: - 3. Ver tu historial (SIEMPRE abierto) — selector + gráfica + resumen + escalera

    private var historyContent: some View {
        let window = MetricWindowMath.make(parsed, selected: range)
        let smoothed = SeriesShape.movingAverage(window.values, window: 7)
        let rawStat = ComparisonEngine.stat(window.values)
        let pct = range.periodComparison(of: model.series)?.pctChange
        return VStack(alignment: .leading, spacing: LiquidSpace.s300) {
            LiquidRangeSelector(opciones: ExploreRange.allCases.map(\.label),
                                seleccion: rangeSeleccion, tono: Self.tono)
            if window.values.count > 1 {
                VStack(alignment: .leading, spacing: LiquidSpace.s300) {
                    fraseNivelHistorial(window)
                    if let pct {
                        LiquidNotaLine(pct >= 0 ? "+\(Int(pct.rounded()))%" : "\(Int(pct.rounded()))%",
                                       tono: pct >= 0 ? LiquidColor.positivo : LiquidColor.atencionTexto)
                    }
                    graficaHistorial(window, smoothed: smoothed)
                    LiquidNotaLine(String(localized: "7-day moving average: day-to-day strain is noisy."))
                    // M4: el trío es crudo/crudo/crudo — la gráfica sigue suavizada con su
                    // nota, pero el promedio del resumen es de la serie SIN suavizar.
                    LiquidResumenVentana(celdas: [
                        .init(rotulo: String(localized: "Average"), valor: fmt(rawStat.mean)),
                        .init(rotulo: String(localized: "Range"),
                              valor: "\(fmt(rawStat.min))–\(fmt(rawStat.max))"),
                        .init(rotulo: String(localized: "Today"),
                              valor: shownToday.map(fmt) ?? LiquidCajita.sinDato,
                              tono: shownToday != nil ? Self.tono : nil),
                    ])
                }
                .liquidTarjetaSeccion()
                LiquidLevelsList(filas: carrilesHistorial(window), tono: Self.tono)
                LiquidNotaLine(String(localized: "How many days of the period fell in each band. Tap one to see its days on the chart."))
            } else {
                LiquidGraficaNiveles(puntos: [], bandas: [], dominio: Self.dominioEsfuerzo, ticksY: [],
                                     tono: Self.tono,
                                     estadoVacio: String(localized: "Not enough days in this range to draw a trend."),
                                     a11yLabel: String(localized: "Strain history"))
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
    /// ninguno, el de hoy.
    private var destacado: Int? { bandaExplorada ?? indiceHoy }

    /// El carril de HOY y cuántos días del periodo cayeron con él — el mismo contrato que
    /// `SleepDetailScreen.fraseNivelHistorial`, con `LiquidFraseNivel`.
    @ViewBuilder private func fraseNivelHistorial(_ window: MetricWindow) -> some View {
        if let i = indiceHoy {
            let b = Self.bandasEsfuerzo[i]
            let n = window.values.filter { v in
                (b.lo == nil || v >= b.lo!) && (b.hi == nil || v < b.hi!)
            }.count
            LiquidFraseNivel(nivel: b.label,
                             conteo: String(localized: "\(n) of your last \(window.values.count) days"),
                             tono: Self.tono)
        } else {
            LiquidFraseNivel(nivel: nil,
                             conteo: String(localized: "\(window.values.count) days with data in this range"),
                             tono: Self.tono,
                             sinLectura: String(localized: "No reading today"))
        }
    }

    /// La gráfica del historial: la serie SUAVIZADA a 7 días (día a día el esfuerzo es ruidoso —
    /// mismo criterio que «Instrumento»), con los carriles fijos detrás.
    private func graficaHistorial(_ window: MetricWindow, smoothed: [Double]) -> some View {
        let puntos = MetricWindowMath
            .decimatedPoints(rows: window.rows, values: smoothed, maxPoints: 80)
            .map { (fecha: $0.date, valor: $0.value) }
        return LiquidGraficaNiveles(
            puntos: puntos,
            bandas: Self.bandasEsfuerzo.enumerated().map { i, b in
                LiquidChartBanda(lo: b.lo, hi: b.hi, color: b.color, activa: i == destacado)
            },
            dominio: Self.dominioEsfuerzo,
            // Los ticks del eje afirman los CUATRO cortes reales del motor (6/10/14/18), no la
            // escalera vieja 14/8 (TND10-3): un eje que marca 8 y 13 se lee como si fueran
            // fronteras. Con el dominio 0–19 (UX-03) el carril Descanso ya no se clampea.
            ticksY: [(18, "18"), (14, "14"), (10, "10"), (6, "6")],
            tono: Self.tono,
            puntoHoy: shownToday != nil ? puntos.last : nil,
            hoyAnillo: bandaExplorada != nil && bandaExplorada != indiceHoy,
            formatoScrub: { v, f in "\(fmt(v)) · \(Self.ejeFechaFmt.string(from: f))" },
            formatoValorScrub: { fmt($0) },
            formatoFechaScrub: { Self.ejeFechaFmt.string(from: $0) },
            formatoFechaEje: { Self.ejeFechaFmt.string(from: $0) },
            atenuarFuera: bandaExplorada != nil,
            estadoVacio: String(localized: "Not enough days in this range to draw a trend."),
            a11yLabel: String(localized: "Strain history"))
            .id(range)
    }

    /// Los carriles tocables bajo la gráfica: tocar uno resalta sus días; re-tocarlo limpia.
    /// Mismo contrato que `SleepDetailScreen.carrilesHistorial` / `TrainingLoadSheet.nivelesLista`.
    private func carrilesHistorial(_ window: MetricWindow) -> [LiquidLevelsList.Fila] {
        let hint = String(localized: "Highlights this level on the chart")
        let hoyRotulo = String(localized: "· today")
        return Self.bandasEsfuerzo.indices.map { i in
            let b = Self.bandasEsfuerzo[i]
            let n = window.values.filter { v in
                (b.lo == nil || v >= b.lo!) && (b.hi == nil || v < b.hi!)
            }.count
            return LiquidLevelsList.Fila(
                etiqueta: b.label, rango: b.range,
                conteo: n == 1 ? String(localized: "\(n) day") : String(localized: "\(n) days"),
                esHoy: i == indiceHoy, activa: i == destacado,
                hoyEtiqueta: hoyRotulo, a11yHint: hint,
                onTap: {
                    withAnimation(LiquidMotion.lift) {
                        bandaExplorada = (bandaExplorada == i) ? nil : i
                    }
                })
        }
    }

    /// «Qué mueve tu esfuerzo» — drivers direccionales, ya gateados por el motor (FER-239). La
    /// tarjeta desaparece entera cuando nada cruza el umbral de suficiencia (sin mensaje vacío).
    /// UX-09: la pieza es `LiquidTendenciaCard` (overline + chip «tendencia, no causa»), la
    /// MISMA que Estrés — el chip punteado ya no se copia a mano por pantalla.
    private var whatMovesCard: some View {
        LiquidTendenciaCard(
            overline: String(localized: "What we see in your history"),
            chip: String(localized: "trend, not cause"),
            lineas: model.drivers.map(Self.driverPhrase))
    }

    /// La frase direccional de un driver — el dato es siempre una DIRECCIÓN, nunca un número.
    /// Texto SIN CAMBIOS (mismas 4 claves).
    private static func driverPhrase(_ f: StrainDriverFinding) -> String {
        switch (f.driver, f.trend) {
        case (.sameDayRecovery, .rises): return String(localized: "Tends to run higher on days you start more recovered.")
        case (.sameDayRecovery, .falls): return String(localized: "Tends to run lower on days you start more recovered.")
        case (.priorDayStrain, .rises):  return String(localized: "Tends to run higher the day after a hard effort.")
        case (.priorDayStrain, .falls):  return String(localized: "Tends to ease off the day after a hard effort.")
        }
    }

    // MARK: - Los carriles fijos — UNA sola escalera, compartida por niveles/historial/calendario
    //
    // FER-101: antes esta pantalla tenía DOS ladders distintas para la misma métrica —
    // `MetricInfo.strain(_:).bands` (5 carriles) para la tabla estática, y una `strainBands`
    // propia que colapsaba «rest»+«light» en una sola etiqueta «Rest / Light» de 4 carriles para la
    // gráfica (con un desfase de índice real: el carril «hard» clampeaba a la palabra/color de
    // «extreme» — ver el `.enumerated().reversed()` + `Swift.min(i, words.count - 1)` del original).
    // Se deriva UNA vez de `MetricLevels.displayBands(for: .strain)` — la misma fuente que ya
    // alimentaba `MetricInfo.strain` por debajo — y las CINCO bandas (rest/light/moderate/hard/
    // extreme) se usan tal cual en los tres bloques. Decisión anotada para el orquestador: el
    // conteo de carriles visibles en la tabla y en la gráfica del historial pasa de 4 a 5 (más
    // fiel al motor); las 4 frases del héroe NO cambian (se preservó el mismo `switch` de 4 casos
    // sobre el mismo índice 0-4, así que «hard» y «extreme» siguen leyendo la MISMA frase, como
    // en «Instrumento»).

    struct BandaEsfuerzo {
        let key: String
        let label: String
        let lo: Double?
        let hi: Double?
        let color: Color
        let range: String
    }

    static let bandasEsfuerzo: [BandaEsfuerzo] = MetricLevels.displayBands(for: .strain).map { band in
        BandaEsfuerzo(key: band.key,
                     label: String(localized: String.LocalizationValue(band.name)),
                     lo: band.lower, hi: band.upper,
                     color: colorNivel(band.key),
                     range: band.range)
    }

    /// El tono de cada carril: un solo ámbar graduado por opacidad, rest→extreme — la misma
    /// idea que la rampa de etapas de Sueño (`SleepDetailScreen.coloresEtapa`) o de duración
    /// (`colorCarril`), nunca un semáforo (esta hoja es descriptiva).
    private static func colorNivel(_ key: String) -> Color {
        switch key {
        case "rest":     return Self.tono.opacity(0.24)  // token-exempt(dato): rampa graduada de esfuerzo
        case "light":    return Self.tono.opacity(0.42)  // token-exempt(dato): rampa graduada de esfuerzo
        case "moderate": return Self.tono.opacity(0.62)  // token-exempt(dato): rampa graduada de esfuerzo
        case "hard":     return Self.tono.opacity(0.82)  // token-exempt(dato): rampa graduada de esfuerzo
        default:         return Self.tono                 // "extreme"
        }
    }

    /// El carril en que cae un valor. Único predicado numérico de la pantalla.
    static func indiceCarril(_ v: Double) -> Int? {
        bandasEsfuerzo.firstIndex { b in (b.lo == nil || v >= b.lo!) && (b.hi == nil || v < b.hi!) }
    }

    /// El dominio Y del historial: 0–19 (UX-03) — el piso 6 de «Instrumento» clampeaba el
    /// carril Descanso: un día de 2.3 se dibujaba pegado al borde como si fuera un 6.
    private static let dominioEsfuerzo: ClosedRange<Double> = 0...19

    private static let ejeFechaFmt: DateFormatter = {
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("dMMM"); return f
    }()

    // MARK: - 4. Calendario · 90 días

    private var calendarContent: some View {
        LiquidCalendario90(
            dias: calendarioDias,
            tono: Self.tono,
            leyenda: Self.leyendaCalendario,
            seleccion: $selectedStrainDayID,
            a11yLabel: String(localized: "Calendar · 90 days"),
            pistaVacia: String(localized: "Tap a day to see its strain."),
            sinLectura: String(localized: "no data"),
            a11yConteo: { conDato, total in
                String(localized: "\(conDato) of your last \(total) days")
            })
    }

    /// Los 90 días, ya resueltos desde `model.strainHeat` (RETIENE el mismo `buildHeat` compartido
    /// con otras pantallas — sin tocar).
    private var calendarioDias: [LiquidCalendario90.Dia] {
        var mesVisto: String? = nil
        return model.strainHeat.map { dia -> LiquidCalendario90.Dia in
            let key = Self.calDayFmt.string(from: dia.date)
            let mes = Self.mesFmt.string(from: dia.date)
            let rotuloMes: String? = mes == mesVisto ? nil : mes
            mesVisto = mes
            let v = dia.score
            return LiquidCalendario90.Dia(
                id: key, fecha: dia.date,
                intensidad: v.map(Self.intensidadEsfuerzo),
                etiqueta: Self.ejeFechaFmt.string(from: dia.date),
                valor: v.map(fmt),
                palabra: v.map(Self.strainWord),
                mes: rotuloMes)
        }
    }

    /// La intensidad de la retícula, graduada por la MISMA escalera de 5 carriles que Niveles e
    /// Historial (paridad `SleepDetailScreen.intensidadSueno`).
    private static func intensidadEsfuerzo(_ v: Double) -> Double {
        guard let i = indiceCarril(v) else { return 0 }
        return alturaNivel(bandasEsfuerzo[i].key)
    }

    /// El peldaño de cada carril en la retícula (rest→extreme). ÚNICO mapa: lo leen la celda y
    /// la leyenda, para que el swatch de una palabra sea EXACTAMENTE la tinta de su carril
    /// (TND10-1: la leyenda a `alfa(1/0.5/0)` decía «hard» con la tinta de «extreme»).
    private static func alturaNivel(_ key: String) -> Double {
        switch key {
        case "extreme":  return 1.0
        case "hard":     return 0.8
        case "moderate": return 0.55
        case "light":    return 0.3
        default:         return 0        // "rest"
        }
    }

    /// La leyenda: TRES peldaños de muestra + «sin dato», el mismo tratamiento impresionista que
    /// `SleepDetailScreen.leyendaCalendario` (tres muestras para cinco tintas — «extreme» queda
    /// más oscuro que el peldaño más oscuro de la leyenda, a propósito). Cada swatch lleva la
    /// tinta REAL de su carril vía `alturaNivel` (TND10-1), y su palabra ES la etiqueta del
    /// carril de la escalera única en minúscula (UX-15, calco de
    /// `StressDetailScreen.leyendaCalendario`) — nunca una segunda copia de las palabras.
    private static var leyendaCalendario: [LiquidCalendario90.NivelLeyenda] {
        var out = ["hard", "moderate", "light"].compactMap { key -> LiquidCalendario90.NivelLeyenda? in
            guard let b = bandasEsfuerzo.first(where: { $0.key == key }) else { return nil }
            return .init(id: b.key,
                         color: tono.opacity(LiquidCalendario90.alfa(intensidad: alturaNivel(b.key))),
                         etiqueta: b.label.lowercased(with: Locale.current))
        }
        out.append(.init(id: "nodata", color: LiquidColor.tinta7,
                         etiqueta: String(localized: "no data")))
        return out
    }

    /// La palabra del día tocado — la MISMA etiqueta que Niveles y la escalera del historial,
    /// por CLAVE de la escalera única (paridad `SleepDetailScreen.sleepWord`; TND10-1: los
    /// cortes viejos 14/8 contradecían la tinta de la celda, p. ej. 8.5 se teñía «light» y
    /// decía «moderate»).
    static func strainWord(_ v: Double) -> String {
        guard let i = indiceCarril(v) else { return bandasEsfuerzo.first?.label ?? "" }
        return bandasEsfuerzo[i].label
    }

    private static let calDayFmt = DayKey.utcFormatter
    private static let mesFmt: DateFormatter = {
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("MMM"); return f
    }()

    // MARK: - Método + sello — patrón `pieMetodo` de Sueño (capilar sin franja propia)

    private var pieMetodo: some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s300) {
            LiquidCapilar(eje: .horizontal)
            LiquidMetodo(title: String(localized: "How it's calculated"),
                         mostrar: String(localized: "Show explanation"),
                         ocultar: String(localized: "Hide explanation")) {
                LiquidNotaLine(String(localized: "Each second of heart rate is mapped to one of five intensity zones; time in the higher zones counts for much more. The weighted total is compressed onto a 0–21 scale through a logarithmic curve, so the top of the scale represents a theoretical full day at peak intensity."),
                               tono: LiquidColor.tinta700)
                LiquidNotaLine(String(localized: "Heart-rate-zone load (TRIMP), compressed logarithmically. (Edwards 1993; Banister 1991)"))
                if estimated {
                    LiquidNotaLine(String(localized: "Estimated from your Apple Watch workout heart rate. It doesn't include activity outside those workouts, so it can read a little low."))
                }
            }
            // M1: las MISMAS claves de procedencia que la hoja de Hoy usa por métrica
            // (`LiquidMetricSheetView.origenChipVista`): esfuerzo = calculado en el teléfono;
            // estimado = la carga que midió Apple (FER-883/D8). M2 · contrato 2 de la hoja:
            // el sufijo «hoy, en curso» solo cuando HAY score de hoy — con puro historial no
            // se estampa un «en curso» sobre un guion.
            LiquidOrigenChip(glyph: .llama, badgeTono: Self.tono,
                             etiqueta: estimated ? String(localized: "Apple Health")
                                                 : String(localized: "Calculated on your phone"),
                             sufijo: model.today != nil ? String(localized: "today, in progress") : nil)
        }
        .liquidSeccion(top: LiquidSpace.s200, bottom: LiquidSpace.s800)
    }

    // MARK: - Format

    /// El esfuerzo se lee a un decimal (0–21), como la fila y el campo.
    private func fmt(_ v: Double) -> String { String(format: "%.1f", v) }
}

// MARK: - Sheet item

/// Envoltura `Identifiable` para que el detalle Liquid de Esfuerzo viaje en `.sheet(item:)` (el
/// modelo mismo no es `Identifiable`). Se abre desde la fila «Day Strain» de Cuerpo. (FER-238)
struct StrainDetailItem: Identifiable {
    let id: UUID
    let model: StrainDetailModel
    /// FER-885: la carga de hoy es un estimado de FC de entrenamiento de Apple (modo solo-Apple),
    /// capturado cuando se abre la hoja.
    var estimated: Bool = false
    /// FER-954: un `id` explícito deja que el modelo ya construido entre bajo la MISMA identidad
    /// de presentación (mismo patrón que `SleepDetailItem`, FER-953).
    init(id: UUID = UUID(), model: StrainDetailModel, estimated: Bool = false) {
        self.id = id; self.model = model; self.estimated = estimated
    }
}

// MARK: - StrainDetailModel — every derivation the screen draws, built ONCE from the repo
//
// The data layer of the strain detail, lifted out of the view. `StrainDetailScreen` is pure presentation
// over this; the caller (Cuerpo) builds it with `StrainDetailModel.build(...)` from the in-memory
// dashboard so the screen stays DB-free. It CONSUMES `StrandAnalytics` as-is (no new math): today's score
// from `repo.today.strain`, the 14d+ series from `repo.days`.
//
// FER-101: this contract is UNCHANGED by the Liquid migration — kept verbatim.

struct StrainDetailModel {
    /// Today's Day Strain (0–21), or nil while there's no score yet (strap-only, no Apple fallback).
    let today: Double?
    /// The full strain series (oldest → newest), `(day "yyyy-MM-dd", value)`, for the trend + stats.
    let series: [(day: String, value: Double)]
    /// Whether the repo finished its first load (drives loading vs empty hero copy).
    let loaded: Bool
    /// The gated, directional drivers of strain ("Qué mueve tu esfuerzo"), computed from the user's own
    /// history (FER-239). Empty when nothing clears the sufficiency gate → the block stays hidden.
    let drivers: [StrainDriverFinding]
    /// Today's effort-confidence tier (FER-676), from the persisted `effortConfidence` — how much of the
    /// active day HR actually covered. nil when today has no score (nothing to grade → no sello).
    var confidence: ScoreConfidence? = nil
    /// The trailing 90 calendar days as `RecoveryDay` (score = strain 0–21, nil where there's no
    /// reading), precomputed here (FER-976) instead of a per-render view computed property — same
    /// seam as `StrainDetailModel.heat`/`.buildHeat`. Defaulted so existing call sites/previews that
    /// don't pass it keep compiling.
    var strainHeat: [RecoveryDay] = []

    /// True when there's a score today or any stored strain history to draw (the rich path); false → empty.
    var hasData: Bool { today != nil || !series.isEmpty }

    /// Build the whole model from the repo's in-memory dashboard. Pure (no DB). `days` is the strap +
    /// on-device dashboard (`repo.days`, the baseline source — FER-149); `today` is `repo.today`; `todayKey`
    /// is the device's local day key (passed by the caller — `Repository.localDayKey` is main-isolated,
    /// FER-976). The drivers are computed here off the same `days` (which carry recovery) via
    /// `StrandAnalytics`, keeping the screen DB-free presentation over a ready-made model.
    static func build(days: [DailyMetric], today: DailyMetric?, loaded: Bool,
                      todayKey: String) -> StrainDetailModel {
        let series = days
            .compactMap { d in d.strain.map { (day: d.day, value: $0) } }
            .sorted { $0.day < $1.day }
        let recovery = days
            .compactMap { d in d.recovery.map { (day: d.day, value: $0) } }
            .sorted { $0.day < $1.day }
        let drivers = WhatMovesStrainEngine.drivers(strain: series, recovery: recovery)
        return StrainDetailModel(today: today?.strain, series: series, loaded: loaded, drivers: drivers,
                                 confidence: today?.effortConfidence.flatMap(ScoreConfidence.init(rawValue:)),
                                 strainHeat: buildHeat(series: series, todayKey: todayKey))
    }

    /// Runs `build` off the MainActor (FER-954, same seam as `SleepDetailModel.buildDetached` /
    /// FER-953): snapshots `repo.days`/`repo.today`/`repo.loaded` on the MainActor (value-type
    /// copies) plus `Repository.localDayKey(Date())` (main-isolated, resolved BEFORE the hop), then
    /// hops the pure derivation to a background executor; only the finished model returns to main.
    @MainActor
    static func buildDetached(repo: Repository) async -> StrainDetailModel {
        let days = repo.days, today = repo.today, loaded = repo.loaded
        let todayKey = Repository.localDayKey(Date())
        return await Task.detached(priority: .userInitiated) {
            build(days: days, today: today, loaded: loaded, todayKey: todayKey)
        }.value
    }

    /// Placeholder while `buildDetached` runs: renders the screen's existing `!model.loaded` loading
    /// state (FER-954).
    static let loading: StrainDetailModel = build(days: [], today: nil, loaded: false, todayKey: "")

    /// The trailing 90 calendar days as `RecoveryDay` (score = strain 0–21, nil where there's no
    /// reading). Moved from the view's per-render `strainHeat` computed property (FER-976) — same
    /// UTC-anchored-to-local-day math as the retired recovery detail's `buildHeat`, unchanged, just relocated +
    /// reading `series` (day,value — the model already has it) instead of the view's `parsed`.
    private static let calDayFmt = DayKey.utcFormatter

    static func buildHeat(series: [(day: String, value: Double)], todayKey: String) -> [RecoveryDay] {
        var vals: [String: Double] = [:]
        for r in series { vals[r.day] = r.value }
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        guard let today = Repository.parseDayKey(todayKey) else { return [] }
        return stride(from: 89, through: 0, by: -1).compactMap { off -> RecoveryDay? in
            guard let date = cal.date(byAdding: .day, value: -off, to: today) else { return nil }
            return RecoveryDay(date: date.addingTimeInterval(12 * 3600),
                               score: vals[Self.calDayFmt.string(from: date)])
        }
    }
}

// MARK: - Preview

#if DEBUG
private func sampleStrainSeries(days: Int = 60) -> [(day: String, value: Double)] {
    let cal = Calendar(identifier: .gregorian)
    let today = cal.startOfDay(for: Date())
    let f = DayKey.utcFormatter
    return (0..<days).map { i in
        let date = cal.date(byAdding: .day, value: -(days - 1 - i), to: today)!
        let v = 11 + 5 * sin(Double(i) / 5.0) + Double((i * 7) % 5) - 2
        return (f.string(from: date), Swift.max(1, Swift.min(21, v)))
    }
}

#Preview("Strain detail: con datos") {
    Color.clear.sheet(isPresented: .constant(true)) {
        StrainDetailScreen(
            model: StrainDetailModel(today: 14.2, series: sampleStrainSeries(), loaded: true,
                                     drivers: [.init(driver: .sameDayRecovery, trend: .rises),
                                               .init(driver: .priorDayStrain, trend: .falls)]))
    }
}

#Preview("Strain detail: sin datos") {
    Color.clear.sheet(isPresented: .constant(true)) {
        StrainDetailScreen(
            model: StrainDetailModel(today: nil, series: [], loaded: true, drivers: []))
    }
}

#Preview("Strain detail: sin permiso") {
    Color.clear.sheet(isPresented: .constant(true)) {
        StrainDetailScreen(
            model: StrainDetailModel(today: nil, series: [], loaded: true, drivers: []),
            sinPermiso: true)
    }
}
#endif
#endif
