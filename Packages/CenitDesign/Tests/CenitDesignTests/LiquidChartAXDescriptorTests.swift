import XCTest
import Accessibility
@testable import CenitDesign

/// FER-29 · `AXChartDescriptor` del plot Liquid (rotor «Gráficas» / audio graph).
/// Run: `swift test --filter LiquidChartAXDescriptorTests`
final class LiquidChartAXDescriptorTests: XCTestCase {

    private static let ancla = Date(timeIntervalSinceReferenceDate: 774_500_000)

    private static func serie(_ n: Int) -> [(fecha: Date, valor: Double)] {
        var out: [(fecha: Date, valor: Double)] = []
        out.reserveCapacity(n)
        for i in 0..<n {
            let fecha = ancla.addingTimeInterval(Double(i - (n - 1)) * 86_400)
            out.append((fecha: fecha, valor: 50.0 + Double(i) * 2.0))
        }
        return out
    }

    private static func fechaCorta(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM d"
        return f.string(from: d)
    }

    /// Número Y de un `AXDataPoint` (API ObjC refinada; se lee por KVC).
    private static func yNumber(_ p: AXDataPoint) -> Double? {
        guard let yv = p.yValue as? NSObject else { return nil }
        if let d = yv.value(forKey: "number") as? Double { return d }
        if let n = yv.value(forKey: "number") as? NSNumber { return n.doubleValue }
        return nil
    }

    /// El descriptor expone un punto por muestra, con el dominio Y del plot y la misma
    /// cabeza de valor que el scrub (`formatoValorScrub`).
    func test_descriptor_serieYFormatoCoincidenConScrub() {
        let puntos = Self.serie(5)
        let ax = LiquidChartAXDescriptor(
            puntos: puntos,
            dominio: 30...95,
            formatoValorScrub: { "\(Int($0)) ms" },
            formatoFechaScrub: Self.fechaCorta,
            formatoScrub: { v, _ in "\(Int(v)) ms" }
        )
        let desc = ax.makeChartDescriptor()

        XCTAssertEqual(desc.series.count, 1)
        let serie = desc.series[0]
        XCTAssertEqual(serie.dataPoints.count, puntos.count,
                       "un AXDataPoint por muestra de la serie")
        for (i, p) in serie.dataPoints.enumerated() {
            guard let y = Self.yNumber(p) else {
                XCTFail("punto \(i) sin valor Y"); continue
            }
            XCTAssertEqual(y, puntos[i].valor, accuracy: 0.0001,
                           "Y del punto \(i) = valor de la serie")
        }

        // Eje Y: dominio del plot (audio graph normaliza el tono a este rango).
        guard let y = desc.yAxis else {
            return XCTFail("yAxis debe existir")
        }
        XCTAssertEqual(y.range.lowerBound, 30, accuracy: 0.001)
        XCTAssertEqual(y.range.upperBound, 95, accuracy: 0.001)
        XCTAssertEqual(y.valueDescriptionProvider(56), "56 ms",
                       "el formateador Y es el mismo que formatoValorScrub del scrub")

        // Label por punto = frase compuesta del caller (misma cabeza que accessibilityValue).
        XCTAssertEqual(serie.dataPoints.first?.label, "50 ms")
        XCTAssertEqual(serie.dataPoints.last?.label, "58 ms")
    }

    /// Serie vacía: el plot no ancla descriptor (ver `liquidChartAXDescriptor`); si alguien
    /// construyera el representable a mano, la serie sale vacía — el rotor no tiene puntos.
    func test_descriptor_serieVacia_sinPuntos() {
        let desc = LiquidChartAXDescriptor(
            puntos: [],
            dominio: 0...1,
            formatoValorScrub: { "\($0)" }
        ).makeChartDescriptor()
        XCTAssertEqual(desc.series.first?.dataPoints.count ?? 0, 0)
    }

    /// Categorías X usan el formato de fecha del caller (popup/eje), no un invento del DS.
    func test_descriptor_ejeX_usaFormatoFechaDelCaller() {
        let puntos = Self.serie(3)
        let expected: [String] = puntos.map { Self.fechaCorta($0.fecha) }
        let desc = LiquidChartAXDescriptor(
            puntos: puntos,
            dominio: 40...70,
            formatoValorScrub: { "\(Int($0))" },
            formatoFechaScrub: Self.fechaCorta
        ).makeChartDescriptor()

        let x = desc.xAxis as? AXCategoricalDataAxisDescriptor
        XCTAssertNotNil(x, "eje X categórico de fechas")
        let cats = x?.categoryOrder ?? []
        XCTAssertEqual(cats.count, 3)
        XCTAssertEqual(cats, expected)
    }
}
