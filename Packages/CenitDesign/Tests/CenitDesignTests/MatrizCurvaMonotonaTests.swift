import XCTest
import SwiftUI
@testable import CenitDesign

/// Auditoría de estrés (gráficas, Sev-4): la curva de la Matriz (FC/VFC en «Hoy») usaba Catmull-Rom,
/// que sobrepasa la caja de cada tramo y dibuja picos/valles que NINGÚN dato midió. `MatrizChartDraw.curva`
/// es ahora Hermite monótona (Fritsch–Carlson): la curva nunca sale del rango vertical de sus puntos —
/// el mismo arreglo que `TrendChart` hizo con `.interpolationMethod(.monotone)`.
///
/// Estos tests FALLAN con el Catmull-Rom viejo (un escalón hundía el control del primer tramo de 50 a
/// ~49.2) y pasan con la monótona. `boundingRect` cubre tanto la curva real como sus controles, así que
/// sirve para cualquiera de las dos semánticas: en Catmull-Rom la curva misma rebasa, no solo el control.
final class MatrizCurvaMonotonaTests: XCTestCase {

    private func caja(_ ys: [CGFloat]) -> CGRect {
        let pts = ys.enumerated().map { CGPoint(x: CGFloat($0.offset) * 24, y: $0.element) }
        return MatrizChartDraw.curva(pts).boundingRect
    }

    /// Un escalón `[50,50,55,55]`: el caso clásico donde Catmull-Rom hunde el control por debajo de 50.
    func test_curva_no_rebasa_la_caja_en_un_escalon() {
        let ys: [CGFloat] = [50, 50, 55, 55]
        let box = caja(ys)
        let eps: CGFloat = 0.01
        XCTAssertGreaterThanOrEqual(box.minY, ys.min()! - eps, "la curva bajó de \(ys.min()!) — overshoot")
        XCTAssertLessThanOrEqual(box.maxY, ys.max()! + eps, "la curva subió de \(ys.max()!) — overshoot")
    }

    /// Oscilación apretada (FC en reposo 50↔55, el caso que cita TrendChart) — tampoco debe rebasar.
    func test_curva_no_rebasa_en_oscilacion_apretada() {
        let ys: [CGFloat] = [52, 50, 55, 51, 54, 50]
        let box = caja(ys)
        let eps: CGFloat = 0.01
        XCTAssertGreaterThanOrEqual(box.minY, ys.min()! - eps)
        XCTAssertLessThanOrEqual(box.maxY, ys.max()! + eps)
    }

    /// Serie de un punto o vacía: no debe crashear ni producir una caja inválida.
    func test_curva_degenerada_no_crashea() {
        XCTAssertTrue(MatrizChartDraw.curva([]).isEmpty)
        _ = MatrizChartDraw.curva([CGPoint(x: 10, y: 20)])   // un punto: solo el move, sin tramos
    }
}
