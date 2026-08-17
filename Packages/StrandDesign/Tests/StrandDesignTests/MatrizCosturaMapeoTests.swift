import XCTest
@testable import StrandDesign

// MARK: - El mapeo de la costura (FER-81 · revisión adversarial, segunda vuelta)
//
// `fraccionFilo` traduce «cuántas bandas te saliste» a «cuánto se abre el labio». Es la pieza
// donde la primera vuelta de arreglos metió tres bugs de golpe (COS-3, COS-4, COS-5), así que
// cada propiedad que la hace honesta está fijada aquí.

final class MatrizCosturaMapeoTests: XCTestCase {

    /// EL MARCO ES INVIOLABLE (COS-3). El mapeo anterior recortaba en seco a 1.9 y el labio
    /// resultante —2.6 + 1.9·(37·0.58 − 2.6) = 38.4 pt— no cabía en un medio alto de 37: la
    /// orilla se salía del Canvas y el anillo de HOY quedaba medio fuera del marco. Con la
    /// fracción acotada a 1 y `filoFrac` < 1, el labio es menor que el medio alto SIEMPRE,
    /// para cualquier entrada.
    func test_laFraccionNuncaPasaDeUno() {
        for v in [0, 0.5, 1, 1.9, 3, 3.75, 12, 500, -0.5, -3, -900] as [Double] {
            XCTAssertLessThanOrEqual(MatrizCostura.fraccionFilo(v), 1, "v = \(v)")
            XCTAssertGreaterThanOrEqual(MatrizCostura.fraccionFilo(v), 0, "v = \(v)")
        }
    }

    /// DOS NOCHES MUY DISTINTAS NO CAEN EN EL MISMO PIXEL (COS-3). Con el recorte anterior,
    /// 17 rpm (3.75 bandas) y 25 rpm se dibujaban idénticas porque las dos topaban en 1.9 —
    /// justo en las noches que importan.
    func test_dosNochesMuyFueraSiguenDistinguiendose() {
        XCTAssertGreaterThan(MatrizCostura.fraccionFilo(2.5),
                             MatrizCostura.fraccionFilo(1.2) + 0.05)
    }

    /// EL ESCALÓN DEL ANCLA ES UN ESCALÓN, NO UN ACANTILADO (COS-5). El ancla al juicio del
    /// motor empuja una noche marcada fuera a ≥1.02 y una no marcada a ≤0.98; con el mapeo
    /// lineal anterior, dos noches que difieren 0.1 rpm podían quedar a 17 pt una de otra.
    /// El escalón tiene que existir —el motor SÍ las juzgó distinto— pero medirse en unos
    /// pocos puntos, no en media gráfica.
    func test_elAnclaNoAbreUnAcantilado() {
        let dentro = MatrizCostura.fraccionFilo(0.98)
        let fuera = MatrizCostura.fraccionFilo(1.9)      // el peor caso: cruda muy alta, no marcada
        XCTAssertGreaterThan(fuera, dentro, "el escalón existe: el motor las juzgó distinto")
        XCTAssertLessThan(fuera - dentro, 0.3, "pero no puede ser media gráfica")
    }

    /// EL LADO BAJO EXISTE PERO NO GRITA (COS-4). Recortar a 0 aplanaba media serie contra el
    /// eje y afirmaba «justo en el centro de tu banda» sobre noches de −0.4 °C que el scrub sí
    /// distinguía. Ahora se dibuja, apretado: nunca puede leerse como «te saliste».
    func test_elLadoBajoSeDibujaPeroJamasLlegaAlFilo() {
        XCTAssertGreaterThan(MatrizCostura.fraccionFilo(-0.5), MatrizCostura.fraccionFilo(-0.1))
        XCTAssertLessThan(MatrizCostura.fraccionFilo(-3), MatrizCostura.fraccionFilo(1) / 2,
                          "ni la noche más fría del año puede verse tan lejos como tu filo")
        XCTAssertEqual(MatrizCostura.fraccionFilo(0), 0, accuracy: 0.0001)
    }

    /// Monótona: más lejos de tu centro = más lejos del eje. Sin esto el dibujo podría invertir
    /// el orden de dos noches y contradecir al scrub que las anuncia.
    func test_esMonotona() {
        var previa = MatrizCostura.fraccionFilo(0)
        for paso in 1...40 {
            let f = MatrizCostura.fraccionFilo(Double(paso) * 0.1)
            XCTAssertGreaterThanOrEqual(f, previa)
            previa = f
        }
    }
}
