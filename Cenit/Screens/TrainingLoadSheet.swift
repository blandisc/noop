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
// cascarón `LiquidMetricSheet` (patrón `LiquidActaVeredicto`) con header → lectura → colina
// (`LiquidHill`) → historial (`LiquidGraficaNiveles`) → método. Toda la matemática viene de
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
    /// «Tu patrón» (opcional, solo desde «Hoy»): el texto del hallazgo de carga + a dónde lleva «Ver patrón →».
    var patternText: String? = nil
    var onSeePattern: (() -> Void)? = nil
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

// MARK: - Hoja «Carga de entrenamiento» — Liquid Glass (composición sobre LiquidMetricSheet)

struct TrainingLoadSheet: View {
    let model: TrainingLoadModel
    /// Tema «Instrumento» retenido por compatibilidad con los call sites (la hoja Liquid ya no
    /// lo usa: el cascarón `LiquidMetricSheet` pone su propio fondo). No se referencia.
    var theme: InstrumentoTheme = .base
    /// «Tu patrón» (solo desde «Hoy»): el hallazgo de carga + a dónde lleva «Ver patrón →».
    var patternText: String? = nil
    var onSeePattern: (() -> Void)? = nil
    /// «Ver más en Tendencias» (solo desde «Hoy»).
    var onSeeTrends: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    /// El periodo del historial (S/M/3M/6M/1A/TODO).
    @State private var range: ExploreRange = .month
    /// Serie ACWR con día parseado una sola vez (lección FER-216).
    @State private var parsed: [(day: String, date: Date?, value: Double)] = []

    // MARK: - Body

    var body: some View {
        LiquidMetricSheet(tono: tono, detent: .porContenido) {
            LiquidSheetHeader(
                icono: .carga,
                titulo: String(localized: "Training load"),
                tono: tono,
                numeral: model.acwr.map(fmt) ?? "—",
                numeralTono: tono,
                origen: .calculado,
                origenEtiqueta: String(localized: "Apple Health · last 28 days"),
                explicacion: heroExplanation,
                infoMostrar: String(localized: "Show explanation"),
                infoOcultar: String(localized: "Hide explanation"))

            if let acwr = model.acwr, let band = model.band {
                LiquidReadingLine(readingText(band), highlight: readingHighlight(band),
                                  highlightTone: tono)
                colina(acwr: acwr)
                historial
                if let onSeeTrends {
                    LiquidVerMas(title: String(localized: "See more in Trends"),
                                 hint: String(localized: "Opens the detail"),
                                 tone: tono, anchoCompleto: true) { dismiss(); onSeeTrends() }
                }
            } else {
                LiquidReadingLine(String(localized: "I need about two weeks of recorded strain to read your load."),
                                  highlight: String(localized: "two weeks of recorded strain"),
                                  highlightTone: LiquidColor.tinta900)
                colina(acwr: nil)
            }

            LiquidMetodo(title: String(localized: "How it's calculated"),
                         mostrar: String(localized: "Show how it's calculated"),
                         ocultar: String(localized: "Hide how it's calculated")) {
                LiquidNotaLine(methodProse)
            }
        }
        .task {
            range = .month
            parsed = chartSeriesPairs.map { ($0.day, Repository.parseDayKey($0.day), $0.value) }
        }
    }

    // MARK: - La colina (instrumento firma)

    private func colina(acwr: Double?) -> some View {
        LiquidHill(
            razon: acwr,
            zonas: zonasCarga(),
            maximo: LoadScale.max,
            referencia: 1.0,
            ticks: hillTicks,
            titulo: String(localized: "The hill"),
            hint: String(localized: "Drag to explore"),
            hoyEtiqueta: String(localized: "TODAY"),
            calibrando: acwr == nil,
            calibrandoTitulo: String(localized: "BUILDING YOUR USUAL"),
            calibrandoAncla: String(localized: "Log a few workouts with heart rate on your Apple Watch and this read will appear."),
            a11yTitulo: String(localized: "The hill"),
            a11yValor: { r, z in "\(fmt(r)), \(z.lowercased())" })
    }

    // MARK: - Historial (LiquidRangeSelector + LiquidGraficaNiveles + tiles)

    private var historial: some View {
        let window = MetricWindowMath.make(parsed, selected: range)
        let stat = ComparisonEngine.stat(window.values)
        let puntos = MetricWindowMath
            .decimatedPoints(rows: window.rows, values: window.values, maxPoints: 80)
            .map { (fecha: $0.date, valor: $0.value) }
        return VStack(alignment: .leading, spacing: LiquidSpace.s300) {
            Text(String(localized: "Your history"))
                .font(LiquidType.label).tracking(LiquidType.labelTracking)
                .textCase(.uppercase)
                .foregroundStyle(LiquidColor.tinta500)
            LiquidRangeSelector(opciones: ExploreRange.allCases.map(\.label), seleccion: rangeIndex)
            LiquidGraficaNiveles(
                puntos: puntos,
                bandas: historialBandas,
                dominio: 0.45...1.9,
                ticksY: [(ReadinessEngine.acwrSpikeAt, cutLabel(ReadinessEngine.acwrSpikeAt)),
                         (1.0, "1.0"),
                         (ReadinessEngine.acwrSweetSpotLow, cutLabel(ReadinessEngine.acwrSweetSpotLow))],
                tono: tono,
                puntoHoy: puntos.last,
                formatoScrub: { v, _ in fmt(v) },
                formatoValorScrub: { fmt($0) },
                formatoFechaScrub: { Self.fechaCorta.string(from: $0) },
                formatoFechaEje: { Self.fechaCorta.string(from: $0) },
                estadoVacio: String(localized: "Not enough days in this range to draw a trend."),
                a11yLabel: String(localized: "Training load history"))
            HStack(spacing: LiquidSpace.s200) {
                statTile(String(localized: "Average"), fmt(stat.mean))
                statTile(String(localized: "Range"), "\(fmt(stat.min))–\(fmt(stat.max))")
                statTile(String(localized: "Today"), model.acwr.map(fmt) ?? "—", tono: model.acwr == nil ? nil : tono)
            }
            if let patternText, !patternText.isEmpty {
                LiquidNotaLine(patternText)
            }
        }
    }

    private var historialBandas: [LiquidChartBanda] {
        let lo = ReadinessEngine.acwrSweetSpotLow
        let hi = ReadinessEngine.acwrSweetSpotHigh
        let spike = ReadinessEngine.acwrSpikeAt
        let today = model.band
        return [
            LiquidChartBanda(lo: spike, hi: nil, color: LiquidColor.negativo, activa: today == .spiking),
            LiquidChartBanda(lo: hi, hi: spike, color: LiquidColor.atencion, activa: today == .buildingFast),
            LiquidChartBanda(lo: lo, hi: hi, color: LiquidColor.verdePrimario, activa: today == .sweetSpot),
            LiquidChartBanda(lo: nil, hi: lo, color: LiquidColor.tinta500, activa: today == .rampingDown),
        ]
    }

    private func statTile(_ label: String, _ value: String, tono: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: LiquidSpace.s150) {
            Text(verbatim: label)
                .font(LiquidType.label).tracking(LiquidType.labelTracking).textCase(.uppercase)
                .foregroundStyle(LiquidColor.tinta500)
            Text(verbatim: value)
                .font(LiquidType.valorL)
                .foregroundStyle(tono ?? LiquidColor.tinta700)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, LiquidSpace.s200)
        .padding(.horizontal, LiquidSpace.s300)
        .liquidGlass(.superficie)
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

    private var hillTicks: [LiquidCargaEscala.Tick] {
        [.init(valor: ReadinessEngine.acwrSweetSpotLow, etiqueta: cutLabel(ReadinessEngine.acwrSweetSpotLow)),
         .init(valor: 1.0, etiqueta: "1.0"),
         .init(valor: ReadinessEngine.acwrSweetSpotHigh, etiqueta: cutLabel(ReadinessEngine.acwrSweetSpotHigh)),
         .init(valor: ReadinessEngine.acwrSpikeAt, etiqueta: cutLabel(ReadinessEngine.acwrSpikeAt))]
    }

    /// El tono de la hoja = el color del punto de la colina para la banda de hoy (un solo mapeo
    /// de color en la hoja). Calibrando → tinta neutra.
    private var tono: Color {
        guard let band = model.band else { return LiquidColor.tinta500 }
        return hillColor(band)
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
        let lo = cutLabel(ReadinessEngine.acwrSweetSpotLow)
        let hi = cutLabel(ReadinessEngine.acwrSweetSpotHigh)
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

    /// Frase de veredicto bajo el numeral. Descriptiva, sin imperativo.
    private func readingText(_ band: ReadinessEngine.LoadBand) -> String {
        switch band {
        case .rampingDown:  String(localized: "Less than your body is used to these days.")
        case .sweetSpot:    String(localized: "In line with what your body is used to.")
        case .buildingFast: String(localized: "More than your body is used to these days.")
        case .spiking:      String(localized: "Well above what your body is used to.")
        }
    }

    private func readingHighlight(_ band: ReadinessEngine.LoadBand) -> String {
        switch band {
        case .rampingDown:  String(localized: "Less than your body is used to")
        case .sweetSpot:    String(localized: "In line with what your body is used to")
        case .buildingFast: String(localized: "More than your body is used to")
        case .spiking:      String(localized: "Well above what your body is used to")
        }
    }

    /// ⓘ: 7 vs 28, 1.0 = usual, banda de balance, hedge. La jerga ACWR se queda en el método.
    private var heroExplanation: String {
        String(localized: "We compare your average strain over the last ~7 days against your last ~28. 1.0 means you trained exactly your usual; 0.8 to 1.3 reads as balance. It's context for your recovery, not an injury prediction.")
    }

    private var methodProse: String {
        String(localized: "The ratio compares your average load over the last ~7 days against your last ~28: what science calls ACWR (acute:chronic). 1.0 is training exactly your usual; 0.8 to 1.3 reads as balance (Gabbett 2016). It's a debated heuristic and does not predict injuries (Impellizzeri 2020).")
    }

    // MARK: - Datos derivados

    /// El índice del selector ⇄ `ExploreRange`.
    private var rangeIndex: Binding<Int> {
        Binding(get: { ExploreRange.allCases.firstIndex(of: range) ?? 0 },
                set: { range = ExploreRange.allCases[$0] })
    }

    /// Serie de ratios por día: recomputa desde `days` cuando hay (ventana larga para el selector);
    /// cae a la serie precomputada (28) del modelo.
    private var chartSeriesPairs: [(day: String, value: Double)] {
        if model.days.isEmpty { return model.series }
        return ReadinessEngine.acwrSeries(days: model.days, lastN: 365)
            .map { (day: $0.day, value: $0.ratio) }
    }

    /// Ratio con dos decimales en todos lados.
    private func fmt(_ v: Double) -> String { String(format: "%.2f", v) }

    /// Un decimal para las marcas de corte (0.8 / 1.3 / 1.5) desde las constantes del motor.
    private func cutLabel(_ v: Double) -> String { String(format: "%.1f", v) }

    /// Formato de fecha corta para el scrub y el eje del historial.
    private static let fechaCorta: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("dMMM")
        return f
    }()
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

private func cargaPreview(_ model: TrainingLoadModel, pattern: String? = nil) -> some View {
    Color.clear.sheet(isPresented: .constant(true)) {
        TrainingLoadSheet(model: model, patternText: pattern,
                          onSeePattern: {}, onSeeTrends: {})
    }
}

#Preview("Carga · en equilibrio") {
    cargaPreview(TrainingLoadModel(
        acwr: 1.03,
        series: (0..<28).map { (day: "d\($0)", value: 0.9 + 0.4 * sin(Double($0) / 5)) },
        days: demoDays { 10 + 3 * sin(Double($0) / 5) }),
        pattern: "Tus semanas en equilibrio terminan con mejor recuperación el lunes.")
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
