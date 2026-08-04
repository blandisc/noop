#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics
import CenitStore
import Foundation

// MARK: - Carga de entrenamiento — franja en «Hoy» + hoja Liquid Glass (FER-705 · migración Liquid)
//
// La carga de entrenamiento (ACWR) entra a «Hoy» como una FRANJA fija bajo las pestañas que al
// tocarla abre esta HOJA. La hoja se migró al sistema Liquid Glass v1: se compone sobre el
// cascarón `LiquidMetricSheet` con las piezas COMPARTIDAS de la familia (FER-33 · F2):
// header con sello → frase de nivel → colina (`LiquidHill`, en el hueco: es su firma) →
// selector → tarjeta de gráfica (`LiquidFraseNivel` + `LiquidGraficaNiveles` +
// `LiquidResumenVentana`) → escalera (`LiquidLevelsList`) → pie con chip de origen.
// Toda la matemática viene de
// `ReadinessEngine` (umbrales 0.8 / 1.3 / 1.5 intactos); estas vistas solo presentan `acwr`,
// `acwrSeries` y `loadBand`. La FRANJA sigue en «Instrumento» (su equivalente Liquid vive en
// la Hoy Liquid); esta migración es de la HOJA.

/// Todo lo que la franja, la hoja y la tarjeta de Tendencias dibujan, construido una vez desde el
/// dashboard band-masked (`CuerpoView.loadAll` / `TodayView.recomputeDerived`). `acwr == nil` → calibrando.
struct TrainingLoadModel: Sendable {
    /// El ratio agudo:crónico de hoy (nil mientras no hay ~2 semanas de esfuerzo).
    let acwr: Double?
    /// El ratio replay por día (viejo → nuevo) para la tarjeta de Tendencias — `ReadinessEngine.acwrSeries` (28).
    let series: [(day: String, value: Double)]
    /// Los días band-masked, para que la hoja recompute la serie por periodo (S/M/3M/6M/1A) y cuente los
    /// carriles sobre los últimos 28 días. Vacío en el fallback (la hoja cae a `series`). No lo usa la franja.
    var days: [DailyMetric] = []

    /// La banda del ratio de hoy — la misma escala `LoadBand` que comparte cada superficie.
    var band: ReadinessEngine.LoadBand? { acwr.map(ReadinessEngine.loadBand(forACWR:)) }
}

/// Wrapper Identifiable para montar la hoja en `.sheet(item:)` (el modelo no es Identifiable).
struct TrainingLoadItem: Identifiable {
    let id = UUID()
    let model: TrainingLoadModel
    /// «Ver más en Tendencias» (opcional, solo desde «Hoy»; redundante desde la propia Tendencias).
    var onSeeTrends: (() -> Void)? = nil
}

// MARK: - La escala de bandas (compartida por la franja y la colina)

/// Los cortes de banda leídos del motor, para que la escala nunca se desfase de `loadBand(forACWR:)`.
private enum LoadScale {
    static let max = 2.0
    static let cuts: [Double] = [ReadinessEngine.acwrSweetSpotLow,
                                 ReadinessEngine.acwrSweetSpotHigh,
                                 ReadinessEngine.acwrSpikeAt]
    /// Los cuatro tramos [lo, hi, banda] sobre la escala 0…2.
    static let bounds: [(lo: Double, hi: Double, band: ReadinessEngine.LoadBand)] = [
        (0, cuts[0], .rampingDown), (cuts[0], cuts[1], .sweetSpot),
        (cuts[1], cuts[2], .buildingFast), (cuts[2], max, .spiking),
    ]
}

// MARK: - Franja de carga (bloque fijo de «Hoy») — Instrumento (sin cambios en esta migración)

/// La franja de dos filas en SEÑALES (única superficie de Hoy): label + palabra de banda + ratio + chevron,
/// y una escala de 4 cápsulas con el punto de hoy. Tocarla abre la hoja. No respira (no es un dato vivo
/// intradía) y no participa del pull-to-refresh; solo el punto se reposiciona si el ratio cambió al sincronizar.
struct TrainingLoadStrip: View {
    let model: TrainingLoadModel
    var theme: InstrumentoTheme = .base
    let onTap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var band: ReadinessEngine.LoadBand? { model.band }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                labelRow
                scaleRow
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Training load"))
        .accessibilityValue(model.acwr == nil ? Text("Calibrating")
                            : Text(band?.shortLabel ?? ""))
        .accessibilityAddTraits(.isButton)
    }

    private var labelRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text("Load")
                .groteskOverline(small: true)
                .foregroundStyle(theme.inkMuted)
            Spacer(minLength: 8)
            if let band, let acwr = model.acwr {
                Text(band.shortLabel)
                    .font(InstrumentoType.grotesk(10, weight: .bold))
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .foregroundStyle(band.flag.color(theme))
                Text(String(format: "%.2f", acwr))
                    .font(InstrumentoType.groteskNumber(10, weight: .medium))
                    .foregroundStyle(theme.inkMuted)
                    .padding(.leading, 6)
                StrandIcon.disclosure.image
                    .font(.system(size: 9, weight: .semibold)) // token-exempt: microtexto <10pt
                    .foregroundStyle(theme.inkMuted)
                    .padding(.leading, 6)
            } else {
                Text("Calibrating")
                    .font(InstrumentoType.grotesk(10, weight: .bold))
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .foregroundStyle(theme.inkMuted)
                Text(verbatim: "··")
                    .font(InstrumentoType.groteskNumber(10, weight: .medium))
                    .foregroundStyle(theme.inkMuted)
                    .padding(.leading, 6)
            }
        }
    }

    private var scaleRow: some View {
        GeometryReader { g in
            let w = g.size.width
            ZStack(alignment: .topLeading) {
                HStack(spacing: 2) {
                    ForEach(LoadScale.bounds, id: \.lo) { seg in
                        Capsule()
                            .fill(seg.band == band ? seg.band.flag.color(theme) : theme.hairline)
                            .frame(width: max(0, w * (seg.hi - seg.lo) / LoadScale.max - 2), height: 6)
                    }
                }
                .frame(height: 12, alignment: .center)
                if let acwr = model.acwr {
                    let x = min(max(acwr / LoadScale.max, 0.05), 0.95)
                    Circle()
                        .fill(theme.surface)
                        .overlay(Circle().strokeBorder(theme.ink, lineWidth: 3))
                        .frame(width: 12, height: 12)
                        .offset(x: w * x - 6, y: 0)
                        .strandAnimation(.spring(response: 0.5, dampingFraction: 0.8), value: acwr)
                }
            }
        }
        .frame(height: 12)
    }
}

// MARK: - Hoja «Carga de entrenamiento» — Liquid Glass (familia, FER-33 · F2)

struct TrainingLoadSheet: View {
    let model: TrainingLoadModel
    /// Tema «Instrumento» retenido por compatibilidad con los call sites (la hoja Liquid ya no
    /// lo usa: el cascarón `LiquidMetricSheet` pone su propio fondo). No se referencia.
    var theme: InstrumentoTheme = .base
    /// «Ver más en Tendencias» (solo desde «Hoy»).
    var onSeeTrends: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.liquidMotionDisabled) private var motionDisabled

    /// Host de niveles: serie parseada una vez + ventana por rango (paridad del compositor).
    @State private var levelsHost: MetricLevelsHostModel
    /// El nivel que el usuario explora en la escalera (nil = el del valor mostrado).
    @State private var nivelExplorado: Int? = nil

    /// Formateador del sistema: numeral a 2 decimales, cotas a 1 (0.8 / 1.3 / 1.5).
    private static let format = MetricFormat(
        valueStyle: .decimal2, boundaryStyle: .decimal1, unit: nil)

    /// Los cuatro niveles de carga, armados en el call site desde las constantes del motor.
    /// Claves = `LoadBand.rawValue` (coinciden con `MetricLevelPhrase` / `reading.vsBase.load.*`).
    private static var loadLevels: [MetricLevels.Level] {
        let lo = ReadinessEngine.acwrSweetSpotLow
        let hi = ReadinessEngine.acwrSweetSpotHigh
        let spike = ReadinessEngine.acwrSpikeAt
        return [
            .init(key: ReadinessEngine.LoadBand.rampingDown.rawValue, lower: nil, upper: lo),
            .init(key: ReadinessEngine.LoadBand.sweetSpot.rawValue, lower: lo, upper: hi),
            .init(key: ReadinessEngine.LoadBand.buildingFast.rawValue, lower: hi, upper: spike),
            .init(key: ReadinessEngine.LoadBand.spiking.rawValue, lower: spike, upper: nil),
        ]
    }

    init(model: TrainingLoadModel,
         theme: InstrumentoTheme = .base,
         onSeeTrends: (() -> Void)? = nil) {
        self.model = model
        self.theme = theme
        self.onSeeTrends = onSeeTrends
        _levelsHost = State(initialValue: MetricLevelsHostModel(
            metricID: "load", fixedLevels: Self.loadLevels))
    }

    // MARK: - Body

    var body: some View {
        LiquidMetricSheet(tono: tono, detent: .porContenido) {
            cabecera
            if let acwr = model.acwr {
                // Frase y tono siguen el valor que el héroe MUESTRA (hoy en S, media en
                // rangos largos) — no el de hoy a ciegas.
                if let band = valorMostrado.map(ReadinessEngine.loadBand(forACWR:)) {
                    LiquidReadingLine(readingText(band), highlightTone: tonoTexto)
                }
                colina(acwr: acwr)
                explorador
            } else {
                LiquidReadingLine(String(localized: "I need about two weeks of recorded strain to read your load."),
                                  highlight: String(localized: "two weeks of recorded strain"),
                                  highlightTone: LiquidColor.tinta900)
                colina(acwr: nil)
            }
            pie
        }
        .task {
            levelsHost.load(rows: chartSeriesPairs)
        }
    }

    // MARK: - Cabecera (sello de ventana; procedencia baja al pie)

    private var cabecera: some View {
        LiquidSheetHeader(
            icono: .carga,
            titulo: String(localized: "Training load"),
            tono: tono,
            numeral: heroVentana.numeral,
            numeralTono: tono,
            sello: heroVentana.sello,
            // FER-33 · F2: la procedencia YA NO viaja en el héroe — va al chip del pie.
            origen: nil,
            origenEtiqueta: nil,
            explicacion: heroExplanation,
            infoMostrar: String(localized: "Show explanation"),
            infoOcultar: String(localized: "Hide explanation"))
    }

    // MARK: - Héroe por ventana (réplica de LiquidMetricSheetView · F0.3)

    /// El valor que el héroe está MOSTRANDO: la media de la ventana en rangos largos, el
    /// dato de hoy en la semana. Frase, titular de tarjeta y fila encendida clasifican
    /// contra ESTE valor.
    private var valorMostrado: Double? {
        let w = levelsHost.window
        guard levelsHost.levels != nil, w.range != .week, !w.values.isEmpty else {
            return model.acwr
        }
        return ComparisonEngine.stat(w.values).mean
    }

    private var heroVentana: (numeral: String?, sello: String?) {
        let w = levelsHost.window
        guard levelsHost.levels != nil, w.range != .week, !w.values.isEmpty else {
            return (model.acwr.map(Self.format.numeral) ?? "—", selloHoy)
        }
        return (Self.format.numeral(ComparisonEngine.stat(w.values).mean), selloMedia(w.range))
    }

    private var selloHoy: String {
        String(localized: "TODAY · \(Self.diaCorto(Date()))")
    }

    private func selloMedia(_ rango: ExploreRange) -> String {
        switch rango {
        case .week:
            return selloHoy
        case .month, .quarter:
            let dias: Int = rango.days ?? 0
            return String(localized: "AVG · \(dias) DAYS")
        case .half:
            return String(localized: "AVG · 6 MONTHS")
        case .year:
            return String(localized: "AVG · 1 YEAR")
        case .all:
            return String(localized: "AVG · ALL")
        }
    }

    /// En qué fila de la escalera cayó HOY — independiente del valor del héroe.
    private var indiceDeHoy: Int? {
        guard let levels = levelsHost.levels, let v = model.acwr else { return nil }
        return MetricLevels.activeIndex(for: v, in: levels)
    }

    // MARK: - La colina (instrumento firma; interior intacto)

    private func colina(acwr: Double?) -> some View {
        LiquidHill(
            razon: acwr,
            zonas: zonasCarga(),
            maximo: LoadScale.max,
            referencia: 1.0,
            // Valores y copy coinciden con `ticksPorDefecto` (0.8 / 1.0 / 1.3 / 1.5).
            ticks: LiquidCargaEscala.ticksPorDefecto,
            titulo: String(localized: "The hill"),
            hint: String(localized: "Drag to explore"),
            hoyEtiqueta: String(localized: "TODAY"),
            calibrando: acwr == nil,
            calibrandoTitulo: String(localized: "Calibrating"),
            calibrandoAncla: String(localized: "I need about two weeks of recorded strain to read your load."),
            a11yTitulo: String(localized: "The hill"),
            a11yValor: { r, z in "\(Self.format.numeral(r)), \(z.lowercased())" })
    }

    // MARK: - Explorador (selector + tarjeta gráfica + escalera)

    @ViewBuilder private var explorador: some View {
        if let d = levelsHost.clasificacion(today: valorMostrado) {
            let window = levelsHost.window
            VStack(alignment: .leading, spacing: LiquidSpace.s300) {
                LiquidRangeSelector(opciones: ExploreRange.allCases.map(\.label),
                                    seleccion: rangeSeleccion)
                if cargando {
                    // La serie llega en el `.task`, o sea DESPUÉS del primer render. Sin este
                    // gate, durante un frame la hoja afirma «0 días con datos en este rango»,
                    // cuatro filas con «0 días» y Promedio/Rango en «—»: una mentira momentánea
                    // sobre datos que sí existen. Los cortes SÍ se conocen (son umbrales), así
                    // que la escalera se muestra sin conteos y el instrumento espera.
                    esqueletoGrafica
                    nivelesLista(d, conteos: false)
                } else {
                    if window.fellBack {
                        avisoVentana(window)
                    }
                    tarjetaGrafica(d, window: window)
                    nivelesLista(d)
                }
            }
        }
    }

    /// ¿La serie de niveles sigue en camino? Mismo gate que el compositor de las otras ocho.
    private var cargando: Bool { !levelsHost.cargado }

    /// El pozo del instrumento mientras la serie viene en camino: el mismo alto que la
    /// gráfica, para que la hoja no cambie de tamaño cuando lleguen los datos.
    private var esqueletoGrafica: some View {
        LiquidGraficaNiveles(puntos: [], bandas: [], dominio: 0.45...1.9, ticksY: [],
                             tono: tono, estado: .cargando, estadoVacio: "",
                             a11yLabel: String(localized: "Training load history"))
    }

    /// Índice del selector ⇄ `ExploreRange` del host; cambiar de rango limpia la exploración.
    private var rangeSeleccion: Binding<Int> {
        Binding(
            get: { ExploreRange.allCases.firstIndex(of: levelsHost.range) ?? 0 },
            set: { idx in
                levelsHost.range = ExploreRange.allCases[idx]
                nivelExplorado = nil
            })
    }

    private func nivelDestacado(_ d: MetricLevels.Classification) -> Int? {
        if let s = nivelExplorado, d.levels.indices.contains(s) { return s }
        return d.activeIndex
    }

    /// Tarjeta de la gráfica: titular (`LiquidFraseNivel`) + `LiquidGraficaNiveles` +
    /// pie de cifras (`LiquidResumenVentana`). Sin rótulo «Tu historial».
    private func tarjetaGrafica(_ d: MetricLevels.Classification,
                                window: MetricWindow) -> some View {
        let highlight = nivelDestacado(d)
        let puntos = MetricWindowMath
            .decimatedPoints(rows: window.rows, values: window.values, maxPoints: 80)
            .map { (fecha: $0.date, valor: $0.value) }
        let stat = ComparisonEngine.stat(window.values)
        let nombre: String? = highlight.map { nombreNivel(d.levels[$0].key) }
        let conteo: String = {
            guard let i = highlight, d.total > 0 else {
                return String(localized: "\(d.total) days with data in this range")
            }
            return String(localized: "\(d.counts[i]) of your last \(d.total) days")
        }()
        // Bandas DERIVADAS de la misma lista de niveles que la escalera (no se desfasen).
        let bandas: [LiquidChartBanda] = d.levels.enumerated().map { (i, lvl) in
            LiquidChartBanda(lo: lvl.lower, hi: lvl.upper, color: tono,
                             activa: i == highlight)
        }
        return VStack(alignment: .leading, spacing: LiquidSpace.s300) {
            LiquidFraseNivel(nivel: nombre,
                             conteo: conteo,
                             tono: tono,
                             sinLectura: String(localized: "No reading today"))
            LiquidGraficaNiveles(
                puntos: puntos,
                bandas: bandas,
                dominio: 0.45...1.9,
                ticksY: [
                    (ReadinessEngine.acwrSpikeAt, Self.format.boundary(ReadinessEngine.acwrSpikeAt)),
                    (1.0, Self.format.boundary(1.0)),
                    (ReadinessEngine.acwrSweetSpotLow,
                     Self.format.boundary(ReadinessEngine.acwrSweetSpotLow)),
                ],
                tono: tono,
                puntoHoy: indiceDeHoy != nil ? puntos.last : nil,
                hoyAnillo: nivelExplorado != nil && nivelExplorado != indiceDeHoy,
                formatoScrub: { v, f in "\(Self.format.numeral(v)) · \(Self.diaCorto(f))" },
                formatoValorScrub: { Self.format.numeral($0) },
                formatoFechaScrub: { Self.popupDiaFmt.string(from: $0) },
                formatoFechaEje: Self.ejeFechaFmt(puntos),
                atenuarFuera: nivelExplorado != nil,
                estadoVacio: String(localized: "Not enough days in this range to draw a trend."),
                a11yLabel: String(localized: "Training load history"))
            LiquidResumenVentana(celdas: [
                .init(rotulo: String(localized: "Average"),
                      valor: window.values.isEmpty ? "—" : Self.format.numeral(stat.mean)),
                .init(rotulo: String(localized: "Range"),
                      valor: window.values.isEmpty
                        ? "—"
                        : "\(Self.format.numeral(stat.min))–\(Self.format.numeral(stat.max))"),
                .init(rotulo: String(localized: "Today"),
                      valor: model.acwr.map(Self.format.numeral) ?? "—",
                      tono: model.acwr == nil ? nil : tono),
            ])
        }
        .padding(LiquidSpace.s400)
        // PAPEL OPACO, no vidrio: es una tarjeta INTERNA de la hoja, y el vidrio sobre vidrio
        // es el defecto que hacía saltar las tablas de gris a blanco al arrastrar la hoja.
        // Mismo criterio que `LiquidRegularityCard` y `LiquidBandsTable`.
        .liquidGlass(.superficieSolida)
    }

    /// `conteos: false` mientras la serie viene en camino: los cortes se conocen (son
    /// umbrales), los conteos no. Imprimir «0 días» en cada fila desde el primer frame es
    /// una mentira momentánea sobre datos que sí existen.
    private func nivelesLista(_ d: MetricLevels.Classification,
                              conteos: Bool = true) -> some View {
        let highlight = nivelDestacado(d)
        let hoyRotulo = String(localized: "· today")
        let hint = String(localized: "Highlights this level on the chart")
        let filas: [LiquidLevelsList.Fila] = d.levels.indices.map { i in
            let nivel = d.levels[i]
            return LiquidLevelsList.Fila(
                etiqueta: nombreNivel(nivel.key),
                rango: rangoNivel(nivel),
                conteo: conteos ? conteoLabel(d.counts[i]) : "",
                esHoy: i == indiceDeHoy,
                activa: i == highlight,
                hoyEtiqueta: hoyRotulo,
                a11yHint: hint,
                onTap: {
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

    private func nombreNivel(_ key: String) -> String {
        // NO `MetricLevels.name(for:)`: las claves de carga no están en ese mapa.
        ReadinessEngine.LoadBand(rawValue: key)?.shortLabel ?? key
    }

    private func rangoNivel(_ nivel: MetricLevels.Level) -> String {
        switch (nivel.lower, nivel.upper) {
        case let (nil, hi?):  return "< \(Self.format.boundary(hi))"
        case let (lo?, nil):  return "≥ \(Self.format.boundary(lo))"
        case let (lo?, hi?):  return "\(Self.format.boundary(lo))–\(Self.format.boundary(hi))"
        case (nil, nil):      return ""
        }
    }

    private func conteoLabel(_ n: Int) -> String {
        n == 1 ? String(localized: "\(n) day") : String(localized: "\(n) days")
    }

    @ViewBuilder private func avisoVentana(_ window: MetricWindow) -> some View {
        let dias: Int = window.range.days ?? window.rows.count
        LiquidNotaLine(String(localized: "Showing the last \(dias) days"),
                       tono: LiquidColor.atencionTexto)
    }

    // MARK: - Pie (método + chip de origen + ver más)

    @ViewBuilder private var pie: some View {
        LiquidMetodo(title: String(localized: "How it's calculated"),
                     mostrar: String(localized: "Show method"),
                     ocultar: String(localized: "Hide method")) {
            LiquidNotaLine(methodProse)
            // Chip DENTRO del plegable (patrón `origenChipVista` del compositor).
            // Carga es un CÁLCULO en el teléfono, no una lectura de Apple.
            if model.acwr != nil {
                LiquidOrigenChip(glyph: .rayo, badgeTono: LiquidColor.tinta500,
                                 etiqueta: String(localized: "Calculated on your phone"))
            }
        }
        if let onSeeTrends {
            LiquidVerMas(title: String(localized: "See more in Trends"),
                         hint: String(localized: "Opens the detail"),
                         tone: tono, anchoCompleto: true) { dismiss(); onSeeTrends() }
        }
    }

    // MARK: - Zonas de la colina (colores de la excepción sancionada)

    /// Cuesta y cresta en verde, descenso en ámbar, caída en rojo — el lenguaje del `LoadHillView`
    /// original, conservado como excepción a «color solo en el dato» (decisión del dueño).
    private func zonasCarga() -> [LiquidHill.Zona] {
        let lo = ReadinessEngine.acwrSweetSpotLow
        let hi = ReadinessEngine.acwrSweetSpotHigh
        let spike = ReadinessEngine.acwrSpikeAt
        return [
            .init(lo: 0, hi: lo, color: LiquidColor.verdePrimario,
                  etiqueta: bandWord(.rampingDown), ancla: anchorText(.rampingDown)),
            .init(lo: lo, hi: hi, color: LiquidColor.verdePrimario,
                  etiqueta: bandWord(.sweetSpot), ancla: anchorText(.sweetSpot)),
            .init(lo: hi, hi: spike, color: LiquidColor.atencion,
                  etiqueta: bandWord(.buildingFast), ancla: anchorText(.buildingFast)),
            .init(lo: spike, hi: LoadScale.max, color: LiquidColor.negativo,
                  etiqueta: bandWord(.spiking), ancla: anchorText(.spiking)),
        ]
    }

    /// El tono de la hoja = el color de la banda del valor que la hoja MUESTRA (un solo mapeo
    /// de color). Calibrando → tinta neutra.
    ///
    /// Seguía siempre al ACWR de hoy, así que en rango largo la frase decía «Subiendo» y la
    /// hoja entera —numeral incluido— se pintaba del verde de hoy: el color contradecía a la
    /// palabra. (Revisión Grok r3 · I2.)
    private var tono: Color {
        guard let v = valorMostrado else { return LiquidColor.tinta500 }
        return hillColor(ReadinessEngine.loadBand(forACWR: v))
    }

    /// El tono para TEXTO CHICO (la lectura honesta): el ámbar de dato falla AA sobre vidrio,
    /// así que se sustituye por su hermano oscurecido. El numeral del héroe sí usa `tono` pleno
    /// (es texto grande, pasa AA). Verde/rojo pasan y no cambian.
    private var tonoTexto: Color {
        tono == LiquidColor.atencion ? LiquidColor.atencionTexto : tono
    }

    private func hillColor(_ band: ReadinessEngine.LoadBand) -> Color {
        switch band {
        case .rampingDown, .sweetSpot: return LiquidColor.verdePrimario
        case .buildingFast:            return LiquidColor.atencion
        case .spiking:                 return LiquidColor.negativo
        }
    }

    private func bandWord(_ band: ReadinessEngine.LoadBand) -> String {
        band.shortLabel.uppercased()
    }

    private func anchorText(_ band: ReadinessEngine.LoadBand) -> String {
        let lo = Self.format.boundary(ReadinessEngine.acwrSweetSpotLow)
        let hi = Self.format.boundary(ReadinessEngine.acwrSweetSpotHigh)
        switch band {
        case .rampingDown:
            return String(localized: "Less than your body is used to: the uphill slope.")
        case .sweetSpot:
            return String(localized: "The crest: your balance \(lo) to \(hi).")
        case .buildingFast:
            return String(localized: "More than usual: coming down from the crest.")
        case .spiking:
            return String(localized: "Well above usual: the drop.")
        }
    }

    // MARK: - Copy

    /// Frase de veredicto bajo el numeral. Descriptiva, sin imperativo. FER-29 · contrato 4:
    /// el copy vive en el catálogo bajo `reading.vsBase.load.*`; `LoadBand.rawValue`
    /// coincide 1:1 con las claves de nivel de `MetricLevelPhrase`.
    private func readingText(_ band: ReadinessEngine.LoadBand) -> String {
        let clave = MetricLevelPhrase.key(metricID: "load", levelKey: band.rawValue)
            ?? "reading.vsBase.load.\(band.rawValue)"   // fallback defensivo; los rawValue coinciden 1:1
        return String(localized: String.LocalizationValue(clave))
    }

    /// ⓘ: 7 vs 28, 1.0 = usual, banda de balance, hedge. La jerga ACWR se queda en el método.
    private var heroExplanation: String {
        String(localized: "We compare your average strain over the last ~7 days against your last ~28. 1.0 means you trained about your usual; 0.8 to 1.3 reads as balance. It's context for your recovery, not an injury prediction.")
    }

    private var methodProse: String {
        String(localized: "The ratio compares your average load over the last ~7 days against your last ~28: what science calls ACWR (acute:chronic). 1.0 is training about your usual; 0.8 to 1.3 reads as balance (Gabbett 2016). It's a debated heuristic and does not predict injuries (Impellizzeri 2020).")
    }

    // MARK: - Datos derivados

    /// Serie de ratios por día: recomputa desde `days` cuando hay (ventana larga para el selector);
    /// cae a la serie precomputada (28) del modelo.
    private var chartSeriesPairs: [(day: String, value: Double)] {
        if model.days.isEmpty { return model.series }
        return ReadinessEngine.acwrSeries(days: model.days, lastN: 365)
            .map { (day: $0.day, value: $0.ratio) }
    }

    // MARK: - Fechas (mismas plantillas del compositor)

    private static let ejeDiaFmt: DateFormatter = {
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("dMMM"); return f
    }()
    private static let ejeMesFmt: DateFormatter = {
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("MMMyy"); return f
    }()
    private static let popupDiaFmt: DateFormatter = {
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("EEEdMMM"); return f
    }()

    private static func diaCorto(_ date: Date) -> String { ejeDiaFmt.string(from: date) }

    private static func ejeFechaFmt(_ puntos: [(fecha: Date, valor: Double)]) -> (Date) -> String {
        let primero = puntos.first?.fecha
        let ultimo = puntos.last?.fecha
        var largo = false
        if let a = primero, let b = ultimo {
            largo = b.timeIntervalSince(a) > 300 * 86_400
        }
        let fmt = largo ? ejeMesFmt : ejeDiaFmt
        return { fmt.string(from: $0) }
    }
}

// MARK: - Preview

#if DEBUG
private func demoDays(strainCurve: (Int) -> Double) -> [DailyMetric] {
    (0..<60).map { i in
        DailyMetric(day: String(format: "2026-%02d-%02d", (i / 28) + 4, (i % 28) + 1),
                    totalSleepMin: nil, efficiency: nil, deepMin: nil, remMin: nil, lightMin: nil,
                    disturbances: nil, restingHr: nil, avgHrv: nil, recovery: nil,
                    strain: strainCurve(i), exerciseCount: nil)
    }
}

private func cargaPreview(_ model: TrainingLoadModel) -> some View {
    Color.clear.sheet(isPresented: .constant(true)) {
        TrainingLoadSheet(model: model, onSeeTrends: {})
    }
}

#Preview("Carga · en equilibrio") {
    cargaPreview(TrainingLoadModel(
        acwr: 1.03,
        series: (0..<28).map { (day: "d\($0)", value: 0.9 + 0.4 * sin(Double($0) / 5)) },
        days: demoDays { 10 + 3 * sin(Double($0) / 5) }))
}

#Preview("Carga · sobrecarga") {
    cargaPreview(TrainingLoadModel(
        acwr: 1.62,
        series: (0..<28).map { (day: "d\($0)", value: 1.0 + Double($0) * 0.025) },
        days: demoDays { 8 + Double($0) * 0.12 }))
}

#Preview("Carga · calibrando") {
    cargaPreview(TrainingLoadModel(acwr: nil, series: []))
}

#Preview("Franja") {
    VStack(spacing: 24) {
        TrainingLoadStrip(model: TrainingLoadModel(acwr: 1.09, series: [], days: []), theme: .base, onTap: {})
        TrainingLoadStrip(model: TrainingLoadModel(acwr: nil, series: [], days: []), theme: .base, onTap: {})
        TrainingLoadStrip(model: TrainingLoadModel(acwr: 1.62, series: [], days: []), theme: .base, onTap: {})
    }
    .padding(24).background(InstrumentoTheme.base.paper)
}
#endif
#endif
