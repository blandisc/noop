import XCTest
import SwiftUI
import Accessibility
@testable import StrandDesign

// MARK: - Revisión adversarial ronda 8: frontera Matriz↔hojas (FER-128 r7)
//
// Sondeos sobre símbolos públicos / @testable ya existentes. Sin tocar producción.
//
// HALLAZGOS DE RIESGO (no ejecutados — crashearían la suite):
// XG8-01 · `LiquidGraficaNiveles.valorA11y` con `formatoScrub: { v, _ in "\(Int(v)) ms" }`
//         y un punto cuyo valor es `Double.nan`: `Int(Double.nan)` es undefined / trap en
//         runtime. El caller típico de demo usa ese formato. Aquí se prueba con un formato
//         que mira `.isNaN` antes de convertir (ver
//         `test_grafica_nanEnIndiceSeleccionado_valorA11y_formatoSeguro`).
//
// GAP · `LiquidChartCore.x(_:_:)` / `y(_:_:)` siguen `private` — no se abren. Su contrato
//       n=1 «al final» se sondea vía gemelas observables (`MatrizChartDraw.xAt`,
//       `MatrizRegla.xIndice`) y el descriptor AX cuando aplica.

final class MatrizR8Tests: XCTestCase {

    // MARK: Helpers (réplica de MatrizR7 / LiquidCarrilEA11y)

    private static let ancla = Date(timeIntervalSinceReferenceDate: 774_500_000)

    private static func serie(_ n: Int) -> [(fecha: Date, valor: Double)] {
        (0..<n).map { i in
            (fecha: ancla.addingTimeInterval(Double(i - (n - 1)) * 86_400),
             valor: 56.0 + Double(i))
        }
    }

    private static func grafica(
        _ puntos: [(fecha: Date, valor: Double)],
        formatoScrub: @escaping (Double, Date) -> String = { v, _ in
            v.isNaN ? "nan" : "\(Int(v)) ms"
        },
        estado: LiquidChartEstado = .datos
    ) -> LiquidGraficaNiveles {
        LiquidGraficaNiveles(
            puntos: puntos,
            bandas: [.init(lo: 49, hi: 71, color: LiquidColor.cian, activa: true)],
            dominio: 30...95,
            ticksY: [(71, "71"), (49, "49")],
            tono: LiquidColor.cian,
            formatoScrub: formatoScrub,
            estado: estado,
            estadoVacio: "Sin lecturas en este rango.",
            a11yLabel: "VFC, últimos 30 días")
    }

    /// Número Y de un `AXDataPoint` (misma lectura KVC que LiquidChartAXDescriptorTests).
    private static func yNumber(_ p: AXDataPoint) -> Double? {
        guard let yv = p.yValue as? NSObject else { return nil }
        if let d = yv.value(forKey: "number") as? Double { return d }
        if let n = yv.value(forKey: "number") as? NSNumber { return n.doubleValue }
        return nil
    }

    private static func fechaCorta(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM d"
        return f.string(from: d)
    }

    // MARK: 1 · LiquidChartAXDescriptor · un solo punto / NaN / dominio degenerado

    /// Un punto: el descriptor se construye y `categoriasUnicas` produce exactamente 1.
    func test_ax_unPunto_unaCategoriaYUnDatapoint() {
        let puntos = Self.serie(1)
        let desc = LiquidChartAXDescriptor(
            puntos: puntos,
            dominio: 30...95,
            formatoValorScrub: { "\(Int($0)) ms" },
            formatoFechaScrub: Self.fechaCorta
        ).makeChartDescriptor()
        let cats = (desc.xAxis as? AXCategoricalDataAxisDescriptor)?.categoryOrder ?? []
        XCTAssertEqual(cats.count, 1)
        XCTAssertEqual(desc.series.first?.dataPoints.count, 1)
    }

    /// Valor NaN en la serie: el datapoint se construye y su Y no es finito.
    func test_ax_valorNaN_datapointYNoFinito() {
        let puntos: [(fecha: Date, valor: Double)] = [
            (fecha: Self.ancla, valor: Double.nan)
        ]
        let desc = LiquidChartAXDescriptor(
            puntos: puntos,
            dominio: 30...95,
            formatoValorScrub: { $0.isNaN ? "nan" : "\(Int($0))" },
            formatoFechaScrub: Self.fechaCorta,
            formatoScrub: { v, _ in v.isNaN ? "nan" : "\(Int(v))" }
        ).makeChartDescriptor()
        let dp = desc.series.first?.dataPoints.first
        XCTAssertNotNil(dp)
        let y = dp.flatMap(Self.yNumber)
        XCTAssertNotNil(y)
        XCTAssertFalse(y?.isFinite ?? true,
                       "AXDataPoint conserva y=NaN (no lo sanitiza el descriptor)")
    }

    /// Dominio 5...5: el eje Y se construye sin crashear y el rango es degenerado.
    func test_ax_dominioDegenerado_rangeLowerIgualUpper() {
        let desc = LiquidChartAXDescriptor(
            puntos: Self.serie(2),
            dominio: 5...5,
            formatoValorScrub: { "\(Int($0))" },
            formatoFechaScrub: Self.fechaCorta
        ).makeChartDescriptor()
        guard let y = desc.yAxis else {
            return XCTFail("yAxis debe existir con dominio degenerado")
        }
        XCTAssertEqual(y.range.lowerBound, 5, accuracy: 0.0001)
        XCTAssertEqual(y.range.upperBound, 5, accuracy: 0.0001)
    }

    /// Dos puntos con la MISMA etiqueta de fecha: `categoriasUnicas` desambigua (no colapsa).
    func test_ax_fechasDuplicadas_categoriasDesambiguadas() {
        let d = Self.ancla
        let puntos: [(fecha: Date, valor: Double)] = [
            (fecha: d, valor: 40),
            (fecha: d, valor: 50)
        ]
        let label = Self.fechaCorta(d)
        let desc = LiquidChartAXDescriptor(
            puntos: puntos,
            dominio: 0...100,
            formatoValorScrub: { "\(Int($0))" },
            formatoFechaScrub: { _ in label }
        ).makeChartDescriptor()
        let cats = (desc.xAxis as? AXCategoricalDataAxisDescriptor)?.categoryOrder ?? []
        XCTAssertEqual(cats.count, 2)
        XCTAssertEqual(cats[0], label)
        XCTAssertEqual(cats[1], "\(label) (2)")
    }

    // MARK: 2 · LiquidGraficaNiveles.valorA11y · NaN en el índice seleccionado

    /// Con formato seguro (mira `.isNaN`), la voz no truena y dice la marca del formato.
    /// XG8-01 · Un NaN bajo el dedo NO llega al formateador del caller (que con `Int(v)`
    /// tronaría): la voz dice el pozo. Con el código viejo este test devolvía "nan".
    func test_grafica_nanEnIndiceSeleccionado_valorA11y_noLlegaAlFormateador() {
        let puntos: [(fecha: Date, valor: Double)] = [
            (fecha: Self.ancla, valor: Double.nan)
        ]
        let voz = Self.grafica(puntos, formatoScrub: { v, _ in "\(Int(v)) ms" }).valorA11y
        XCTAssertEqual(voz, "Sin lecturas en este rango.")
    }

    // MARK: 3 · LiquidSheetHeader.a11yLabel · «—» / sello / sueño

    /// Con numeral «—», unidad y sufijo NO entran al label.
    func test_a11yLabel_numeralGuion_omiteUnidadYSufijo() {
        XCTAssertEqual(
            LiquidSheetHeader.a11yLabel(titulo: "Título", numeral: "—",
                                        unidad: "ms", sufijo: "prom",
                                        origen: nil),
            "Título, —")
    }

    /// Con «—» el sello SÍ se agrega (la ventana sigue siendo info).
    func test_a11yLabel_numeralGuion_incluyeSelloAnoche() {
        let out = LiquidSheetHeader.a11yLabel(titulo: "Título", numeral: "—",
                                              unidad: "ms", sufijo: "prom",
                                              sello: "ANOCHE", origen: nil)
        XCTAssertEqual(out, "Título, —, ANOCHE")
        XCTAssertTrue(out.contains("ANOCHE"))
    }

    /// Sueño con numeral rico + sello de ventana: string literal exacto.
    func test_a11yLabel_sueno_literalExacto() {
        XCTAssertEqual(
            LiquidSheetHeader.a11yLabel(titulo: "Sueño", numeral: "7 h 25 min",
                                        unidad: nil, sufijo: nil,
                                        sello: "ANOCHE · 22 AGO", origen: nil),
            "Sueño, 7 h 25 min, ANOCHE · 22 AGO")
    }

    // MARK: 4 · MatrizChartDraw.xAt vs MatrizRegla.xIndice · n=1, width 300
    //
    // Ambas dicen «n=1 al final», pero NO son gemelas de margen:
    //   xAt(count:1)     = width − chartInset              = 300 − 4  = 296
    //   xIndice(count:1) = width − reglaZona               = 300 − 24 = 276
    //   (vía chartInset + (width − chartInset − reglaZona))
    // Diferencia = reglaZona − chartInset = 20.
    // La Matriz reserva zona de regla a la derecha; el explorador de niveles (xAt) no.

    func test_xAt_vs_xIndice_n1_width300_difierenEnReglaMenosInset() {
        let width: CGFloat = 300
        let xChart = MatrizChartDraw.xAt(index: 0, count: 1, width: width)
        let xRegla = MatrizRegla.xIndice(0, count: 1, width: width)
        XCTAssertEqual(xChart, width - MatrizTokens.chartInset)
        XCTAssertEqual(xRegla, width - MatrizTokens.reglaZona)
        XCTAssertNotEqual(xChart, xRegla,
                          "n=1 al final: las «gemelas» NO caen en el mismo x")
        XCTAssertEqual(xChart - xRegla, MatrizTokens.reglaZona - MatrizTokens.chartInset)
    }

    // MARK: 5 · MatrizChartDraw.tramos · serie solo-NaN (observable, distinto de R7)

    /// Todo NaN: cero tramos (R7 cubrió nan+nil+finito → un tramo; aquí el pozo total).
    func test_tramos_soloNaN_ceroTramos() {
        let out = MatrizChartDraw.tramos(
            [Double.nan, Double.nan], count: 2, width: 100,
            dominio: 0...5, height: 40
        )
        XCTAssertEqual(out.map(\.count), [])
    }

    // MARK: 6 · LiquidType.filaRango · token del sello (LiquidFraseNivel r7)

    /// El sello de `LiquidFraseNivel` usa `LiquidType.filaRango` (footnote/semibold).
    func test_filaRango_esFootnoteSemibold() {
        XCTAssertEqual(LiquidType.filaRango, Font.system(.footnote, weight: .semibold))
    }
}
