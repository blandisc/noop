import XCTest
@testable import CenitDesign

/// FER-91 (E10) — «Tu cuerpo» fusiona el mapa muscular y el volumen en una sola pantalla, y adopta
/// `MuscleLoadRow` (FER-83 · E2) para su lista de músculos con dos lecturas. La pieza creció para
/// poder sustituir las filas hechas a mano (`ranking`/`peekCard`): esta prueba clava la única parte
/// de ese crecimiento que un render no puede comprobar — el formato del número de series.
///
/// `CenitDesign` es la raíz del grafo de paquetes (cero dependencias, ni siquiera StrandAnalytics),
/// así que no puede importar `MuscleFatigueMap.formattedSets` para compararse contra él: la fórmula
/// vive duplicada a propósito, y esta prueba es lo que mantiene las dos copias honestas. Si alguien
/// cambia una sin la otra, un test equivalente en `StrandAnalyticsTests` (que sí puede importar el
/// motor) truena con los mismos valores.
final class MuscleLoadRowGrowthTests: XCTestCase {

    /// Entero cuando el valor es entero: un músculo que solo recibió trabajo PRIMARIO en la semana
    /// (`Exercise.primaryWeight = 1.0`) siempre suma a un entero.
    func testWholeSetsHaveNoDecimal() {
        XCTAssertEqual(MuscleLoadRow.formattedSets(12), "12")
        XCTAssertEqual(MuscleLoadRow.formattedSets(0), "0")
        XCTAssertEqual(MuscleLoadRow.formattedSets(30), "30")
    }

    /// Un decimal cuando no lo es: un músculo SECUNDARIO (`Exercise.secondaryWeight = 0.5`) puede
    /// aterrizar en «.5» — truncarlo a entero (el bug que la auditoría previa a esta fase encontró)
    /// perdía justo el dato que distingue «trabajado de refilón» de «trabajado directo».
    func testHalfSetsKeepOneDecimal() {
        XCTAssertEqual(MuscleLoadRow.formattedSets(8.5), "8.5")
        XCTAssertEqual(MuscleLoadRow.formattedSets(0.5), "0.5")
        XCTAssertEqual(MuscleLoadRow.formattedSets(11.5), "11.5")
    }

    /// Nunca más de un decimal, aunque el número de entrada traiga más (no debería, pero la fila no
    /// debe reventar la columna si algún día lo hace).
    func testNeverMoreThanOneDecimal() {
        XCTAssertEqual(MuscleLoadRow.formattedSets(8.55), "8.6")
    }
}
