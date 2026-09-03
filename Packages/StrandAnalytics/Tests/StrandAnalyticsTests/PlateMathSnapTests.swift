import XCTest
@testable import StrandAnalytics

/// FER-327 · E6 — `PlateMath.snap` es el ÚNICO «redondea a lo construible» del app. Cualquier peso
/// crudo (el escalón de un drop, la semana ligera) tiene que salir de aquí en un número que la persona
/// pueda armar de verdad con lo que tiene.
final class PlateMathSnapTests: XCTestCase {

    /// El caso del drop: 0,8 × 80 kg = 64 kg crudos. Con el inventario default (20/15/10/5/2,5/1,25) y
    /// barra de 20, 64 no es construible; 62,5 sí (20 + 1,25 por lado). Nunca por encima del objetivo.
    func testDropOfEightyLandsOnABuildableBarbellWeight() {
        let raw = 80 * 0.8
        let snapped = PlateMath.snap(targetKg: raw, implement: .barbell)
        XCTAssertEqual(snapped, 62.5, accuracy: 0.0001)
        XCTAssertLessThanOrEqual(snapped, raw)
        // Y es construible: cargar exactamente ese peso no deja faltante.
        XCTAssertEqual(PlateMath.perSide(targetKg: snapped).shortfallKg, 0, accuracy: 0.0001)
    }

    /// El caso de la semana ligera: 0,9 × 100 = 90 kg, que SÍ es exacto (20 + 15 por lado).
    func testDeloadOfOneHundredIsExactlyBuildable() {
        let snapped = PlateMath.snap(targetKg: 100 * 0.9, implement: .barbell)
        XCTAssertEqual(snapped, 90, accuracy: 0.0001)
        XCTAssertEqual(PlateMath.perSide(targetKg: snapped).perSide, [20, 15])
        XCTAssertEqual(PlateMath.perSide(targetKg: snapped).shortfallKg, 0, accuracy: 0.0001)
    }

    /// Mancuerna/máquina: no hay discos, hay un rack con paso fijo — múltiplo inferior del incremento.
    func testDumbbellAndMachineSnapToTheirFixedStep() {
        XCTAssertEqual(PlateMath.snap(targetKg: 20 * 0.8, implement: .dumbbell), 15, accuracy: 0.0001)
        XCTAssertEqual(PlateMath.snap(targetKg: 100 * 0.9, implement: .machine), 90, accuracy: 0.0001)
        XCTAssertEqual(PlateMath.snap(targetKg: 37, implement: .machine, fixedStepKg: 5), 35, accuracy: 0.0001)
        // Un múltiplo exacto se queda donde está (sin caer un escalón por ruido de coma flotante).
        XCTAssertEqual(PlateMath.snap(targetKg: 15, implement: .dumbbell), 15, accuracy: 0.0001)
        XCTAssertEqual(PlateMath.snap(targetKg: 51.2, implement: .dumbbell), 50, accuracy: 0.0001)
    }

    /// Bordes: nada que cargar no inventa peso, y un objetivo por debajo de la barra devuelve la barra.
    func testEdgesNeverInventWeight() {
        XCTAssertEqual(PlateMath.snap(targetKg: 0, implement: .barbell), 0, accuracy: 0.0001)
        XCTAssertEqual(PlateMath.snap(targetKg: -5, implement: .dumbbell), 0, accuracy: 0.0001)
        XCTAssertEqual(PlateMath.snap(targetKg: 12, implement: .barbell), 20, accuracy: 0.0001,
                       "por debajo de la barra: la barra sola es lo mínimo construible")
        XCTAssertEqual(PlateMath.snap(targetKg: 2, implement: .dumbbell), 0, accuracy: 0.0001)
    }
}
