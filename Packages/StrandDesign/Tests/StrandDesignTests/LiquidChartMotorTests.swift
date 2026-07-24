import XCTest
import SwiftUI
@testable import StrandDesign

/// Motor de gráficas Liquid (carril A de la restauración de la hoja): la guarda de la
/// banda sin cotas y el gate de densidad de los puntos por dato.
/// Run: swift test --filter LiquidChartMotorTests
final class LiquidChartMotorTests: XCTestCase {

    // MARK: - A1 · Banda sin cotas

    /// El defecto latente: con AMBAS cotas `nil` los dos lados abiertos se cancelaban y la
    /// banda contenía todo valor. No explotaba solo porque el compositor filtra caller-side
    /// (`guard band.lower != nil || band.upper != nil`); el día que un caller lo olvide,
    /// esa banda lava la gráfica entera, tiñe todos los discos y el anillo del scrub — y
    /// nadie lo nota, porque una clasificación falsa se ve igual que una verdadera.
    /// Es la misma guarda que ya lleva `TrendBand.contains`.
    func test_banda_sinCotas_noContieneNada() {
        let sinCotas = LiquidChartBanda(lo: nil, hi: nil, color: .cyan, activa: true)
        for v in [-1_000.0, -0.1, 0, 0.1, 56, 1_000] {
            XCTAssertFalse(sinCotas.contiene(v),
                           "una banda sin intervalo no clasifica \(v): decir «todo» es mentir")
        }
    }

    /// La guarda NO puede tocar el caso vivo: una sola cota sigue siendo un intervalo real
    /// (`≥ 80` de FC en reposo, `< 49` de VFC) y sigue clasificando como antes.
    func test_banda_unaSolaCota_intacta() {
        let abiertaArriba = LiquidChartBanda(lo: 80, hi: nil, color: .green, activa: false)
        XCTAssertTrue(abiertaArriba.contiene(80), "el borde bajo PERTENECE a la banda")
        XCTAssertTrue(abiertaArriba.contiene(1_000))
        XCTAssertFalse(abiertaArriba.contiene(79.9))

        let abiertaAbajo = LiquidChartBanda(lo: nil, hi: 49, color: .orange, activa: false)
        XCTAssertTrue(abiertaAbajo.contiene(-1_000))
        XCTAssertTrue(abiertaAbajo.contiene(48.9))
        XCTAssertFalse(abiertaAbajo.contiene(49), "el borde alto es de la banda de arriba")

        let cerrada = LiquidChartBanda(lo: 49, hi: 71, color: .cyan, activa: true)
        XCTAssertTrue(cerrada.contiene(49))
        XCTAssertFalse(cerrada.contiene(71))
    }

    // MARK: - A2 · Densidad de los puntos por dato

    /// Ancho útil del plot en un iPhone de 402 pt con el padding s550 de la hoja y la
    /// canaleta del eje Y: ~300. Es el ancho con el que se calibró el gate.
    private static let anchoUtil: CGFloat = 300

    /// Centros repartidos por ÍNDICE (serie diaria sin huecos): el reparto de `x(_:_:)`.
    private func centrosPorIndice(_ n: Int, ancho: CGFloat = LiquidChartMotorTests.anchoUtil) -> [CGFloat] {
        guard n > 1 else { return n == 1 ? [ancho / 2] : [] }
        return (0..<n).map { CGFloat($0) * ancho / CGFloat(n - 1) }
    }

    /// Centros repartidos por TIEMPO real (`mapeoPorTiempo`), con los días de cada lectura
    /// medidos desde la primera.
    private func centrosPorTiempo(dias: [Double], ancho: CGFloat = LiquidChartMotorTests.anchoUtil) -> [CGFloat] {
        guard let t0 = dias.first, let tn = dias.last, tn > t0 else { return [] }
        return dias.map { CGFloat(($0 - t0) / (tn - t0)) * ancho }
    }

    /// El token es una distancia entre CENTROS en puntos, no un múltiplo del radio: dos
    /// radios + el hueco visible. Atarlo al radio fue lo que movió el corte solo cuando el
    /// dueño subió el radio de 2.2 a 3.0.
    func test_separacion_esDosRadiosMasElHueco() {
        XCTAssertEqual(LiquidChart.puntoDatoSeparacion,
                       LiquidChart.puntoDatoRadio * 2 + LiquidChart.puntoDatoHueco)
        XCTAssertEqual(LiquidChart.puntoDatoRadio, 3.0,
                       "el radio 3.0 es pedido del dueño (2.2 → 3.0, «más peso»): no se encoge para ganar densidad")
    }

    /// El arreglo que motiva A2: la ventana «M» (30 lecturas) recupera su disco por día.
    /// Con el gate viejo (`paso >= radio * 4` = 12 pt) el corte caía en n≈26 y «M» salía
    /// desnuda aunque el token declarara 60.
    func test_densidad_ventanaM_recuperaLosDiscos() {
        XCTAssertTrue(LiquidChart.hayEspacioParaPuntos(centros: centrosPorIndice(30)),
                      "30 lecturas en ~300 pt caben (10.3 pt de paso ≥ 9)")
        let gateViejo = Self.anchoUtil / 29 >= LiquidChart.puntoDatoRadio * 4
        XCTAssertFalse(gateViejo, "regresión: el gate viejo sí cortaba en 30 — este test vigila el arreglo")
    }

    /// La escalera completa del gate sobre el ancho fijo: qué se dibuja y qué no.
    func test_densidad_escalera_26_30_41_60() {
        XCTAssertTrue(LiquidChart.hayEspacioParaPuntos(centros: centrosPorIndice(26)))
        XCTAssertTrue(LiquidChart.hayEspacioParaPuntos(centros: centrosPorIndice(30)))
        XCTAssertFalse(LiquidChart.hayEspacioParaPuntos(centros: centrosPorIndice(41)),
                       "41 lecturas caen a 7.5 pt: los discos de 6 pt de diámetro se tocarían")
        XCTAssertFalse(LiquidChart.hayEspacioParaPuntos(centros: centrosPorIndice(60)),
                       "60 es el techo de HONESTIDAD (decimación), nunca el límite que muerde en iPhone")
    }

    /// El corte geométrico real en un iPhone: n≈34, no los 60 del token. El doc-comment de
    /// `puntoDatoUmbral` lo dice; este test lo ancla para que no vuelva a ser letra muerta
    /// sin que nadie se entere.
    func test_densidad_corteGeometricoReal() {
        XCTAssertTrue(LiquidChart.hayEspacioParaPuntos(centros: centrosPorIndice(34)))
        XCTAssertFalse(LiquidChart.hayEspacioParaPuntos(centros: centrosPorIndice(35)))
    }

    /// El conteo sigue mandando por encima de la geometría: aunque el plot fuera enorme,
    /// pasado `puntoDatoUmbral` la serie puede venir decimada y contar discos mentiría.
    func test_densidad_elConteoSigueSiendoTope() {
        let anchisimo = centrosPorIndice(LiquidChart.puntoDatoUmbral + 1, ancho: 5_000)
        XCTAssertFalse(LiquidChart.hayEspacioParaPuntos(centros: anchisimo),
                       "por encima del umbral no se dibuja aunque sobre espacio: la serie puede venir decimada")
        XCTAssertTrue(LiquidChart.hayEspacioParaPuntos(
            centros: centrosPorIndice(LiquidChart.puntoDatoUmbral, ancho: 5_000)))
    }

    /// Serie con HUECOS (las tres gráficas de la familia reparten por TIEMPO): 12 lecturas
    /// en 90 días con dos en días consecutivos. El PROMEDIO dice 27 pt de aire; el paso real
    /// entre esas dos es 3.4 pt, o sea dos discos de 6 pt encimados. Medir el promedio hacía
    /// que el usuario contara 11 donde la fila de nivel afirma 12.
    func test_densidad_serieConHuecos_mideElPasoMinimo() {
        let dias: [Double] = [0, 9, 18, 27, 36, 45, 54, 55, 63, 72, 81, 90]  // 54 y 55 pegadas
        let centros = centrosPorTiempo(dias: dias)
        XCTAssertEqual(centros.count, 12)
        let promedio = Self.anchoUtil / 11
        XCTAssertGreaterThan(promedio, LiquidChart.puntoDatoSeparacion,
                             "el promedio pasaría el gate: por eso no se usa")
        XCTAssertFalse(LiquidChart.hayEspacioParaPuntos(centros: centros),
                       "dos lecturas de días consecutivos en 90 días se encimarían")
    }

    /// La contraparte: las mismas 12 lecturas BIEN repartidas en los mismos 90 días sí
    /// dibujan sus discos. El gate castiga el apiñamiento, no la serie corta.
    func test_densidad_serieEsparcida_siDibuja() {
        let dias: [Double] = (0..<12).map { Double($0) * 90.0 / 11.0 }
        XCTAssertTrue(LiquidChart.hayEspacioParaPuntos(centros: centrosPorTiempo(dias: dias)))
    }

    /// Casos degenerados: sin serie y con un solo punto no hay discos que repartir (con 1
    /// punto la gráfica ya cae al pozo vacío, y `x(_:_:)` lo centra).
    func test_densidad_seriesDegeneradas() {
        XCTAssertFalse(LiquidChart.hayEspacioParaPuntos(centros: []))
        XCTAssertFalse(LiquidChart.hayEspacioParaPuntos(centros: [150]))
    }
}
