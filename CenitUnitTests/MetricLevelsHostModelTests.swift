import XCTest
import StrandAnalytics
@testable import Cenit

/// Paridad F3a (LIQUID-SHEET-CONTRACT §6): `MetricLevelsHostModel` reproduce BIT A BIT el
/// wiring del instrumento de niveles de `MetricInfoSheet` — niveles resueltos (incl. el
/// fold personal de HRV), ventana por rango y disciplina de caché — con series sintéticas
/// fijas. Si estos tests fallan, la hoja Liquid mostraría OTROS números que la Instrumento.
final class MetricLevelsHostModelTests: XCTestCase {

    /// 40 días sintéticos de HRV (log-normal plausible, valores fijos deterministas).
    private static let hrvRows: [(day: String, value: Double)] = {
        let base = 55.0
        return (0..<40).map { i in
            let day = String(format: "2026-06-%02d", (i % 30) + 1)
            // Oscilación determinista ±8 ms sin aleatoriedad.
            let value = base + 8 * sin(Double(i) * 0.7) + Double(i % 5) - 2
            return (day: "\(day)#\(i)", value: value)
        }
    }()

    /// Réplica LITERAL del camino de la hoja (MetricInfoSheet.computeResolvedLevels +
    /// resolvedLevelsKey) para comparar contra el host.
    private func sheetLevels(parsed: MetricWindowMath.Parsed,
                             levelsMetric: MetricLevels.FixedMetric?,
                             levelsRelative: Bool) -> [MetricLevels.Level]? {
        if let metric = levelsMetric { return MetricLevels.levels(for: metric) }
        guard levelsRelative else { return nil }
        let state = Baselines.foldHistory(parsed.map { Optional($0.value) }, cfg: Baselines.hrvCfg)
        guard state.nValid >= 1 else { return nil }
        let band = Baselines.normalRange(state)
        return [
            MetricLevels.Level(key: "below",  lower: nil,             upper: band.lowerBound),
            MetricLevels.Level(key: "inBase", lower: band.lowerBound, upper: band.upperBound),
            MetricLevels.Level(key: "above",  lower: band.upperBound, upper: nil),
        ]
    }

    func test_paridad_nivelesFijos() {
        // Umbrales fijos (FER-570): el host devuelve EXACTAMENTE MetricLevels.levels(for:).
        for metric in [MetricLevels.FixedMetric.restingHR, .strain, .steps] {
            let host = MetricLevelsHostModel(metricID: "x", levelsMetric: metric,
                                             levelsRelative: false)
            host.load(rows: Self.hrvRows)
            let expected = MetricLevels.levels(for: metric)
            XCTAssertEqual(host.levels?.map(\.key), expected.map(\.key))
            XCTAssertEqual(host.levels?.map(\.lower), expected.map(\.lower))
            XCTAssertEqual(host.levels?.map(\.upper), expected.map(\.upper))
        }
    }

    func test_paridad_hrvBandaPersonal() {
        // HRV (levelsRelative): la banda personal del host == la del camino de la hoja,
        // bit a bit (mismo foldHistory + normalRange sobre la MISMA serie).
        let host = MetricLevelsHostModel(metricID: "hrv", levelsMetric: nil,
                                         levelsRelative: true)
        host.load(rows: Self.hrvRows)
        let esperado = sheetLevels(parsed: host.parsed, levelsMetric: nil, levelsRelative: true)
        XCTAssertNotNil(host.levels)
        XCTAssertEqual(host.levels?.map(\.key), esperado?.map(\.key))
        XCTAssertEqual(host.levels?.map(\.lower), esperado?.map(\.lower))
        XCTAssertEqual(host.levels?.map(\.upper), esperado?.map(\.upper))
    }

    func test_paridad_hrvSinBase() {
        // Sin noches válidas → nil (guard nValid >= 1, FER-571): ni el host ni la hoja
        // inventan banda.
        let host = MetricLevelsHostModel(metricID: "hrv", levelsMetric: nil,
                                         levelsRelative: true)
        host.load(rows: [])
        XCTAssertNil(host.levels)
    }

    func test_paridad_ventanaPorRango() {
        // La ventana del host == MetricWindowMath.make sobre la misma serie parseada,
        // para cada rango del selector.
        let host = MetricLevelsHostModel(metricID: "rhr", levelsMetric: .restingHR,
                                         levelsRelative: false)
        host.load(rows: Self.hrvRows)
        for range in ExploreRange.allCases {
            host.range = range
            let esperada = MetricWindowMath.make(host.parsed, selected: range)
            XCTAssertEqual(host.window.rows.count, esperada.rows.count, "\(range)")
            XCTAssertEqual(host.window.values,
                           esperada.values, "\(range)")
            XCTAssertEqual(host.window.fellBack, esperada.fellBack, "\(range)")
        }
    }

    func test_cache_estableTrasCargar() {
        // La caché sirve el MISMO array tras load (la clave no cambia sin nueva serie) y
        // se invalida al cargar una serie distinta — paridad refreshResolvedLevelsCache.
        let host = MetricLevelsHostModel(metricID: "hrv", levelsMetric: nil,
                                         levelsRelative: true)
        host.load(rows: Self.hrvRows)
        let primera = host.levels
        XCTAssertEqual(host.levels?.map(\.lower), primera?.map(\.lower))
        host.load(rows: Array(Self.hrvRows.prefix(10)))
        XCTAssertNotEqual(host.levels?.map(\.lower), primera?.map(\.lower),
                          "otra serie debe re-plegar la banda")
    }

    func test_parseo_unaVez() {
        // Cada fila conserva su day-key y el Date parseado (la memoización FER-607).
        let host = MetricLevelsHostModel(metricID: "rhr", levelsMetric: .restingHR,
                                         levelsRelative: false)
        let rows = [(day: "2026-07-01", value: 50.0), (day: "2026-07-02", value: 52.0)]
        host.load(rows: rows)
        XCTAssertEqual(host.parsed.map(\.day), rows.map(\.day))
        XCTAssertEqual(host.parsed.map(\.value), rows.map(\.value))
        XCTAssertEqual(host.parsed[0].date, Repository.parseDayKey("2026-07-01"))
    }
}
