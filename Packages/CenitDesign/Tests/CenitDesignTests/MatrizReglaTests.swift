import XCTest
import SwiftUI
@testable import CenitDesign

/// FER-55 · geometría pura de MatrizRegla (panel C, DeepSeek BAJA #3): los estáticos
/// que sostienen la paridad gesto↔curva y la escritura por tramos, testeables sin
/// runtime de SwiftUI.
final class MatrizReglaTests: XCTestCase {

    // MARK: tramos — huecos parten la escritura

    func test_tramos_contiguos_y_huecos() {
        let a = CGPoint(x: 1, y: 1), b = CGPoint(x: 2, y: 2)
        let c = CGPoint(x: 4, y: 4), d = CGPoint(x: 5, y: 5)
        XCTAssertEqual(MatrizRegla.tramos([a, b, nil, c, d]), [[a, b], [c, d]])
        XCTAssertEqual(MatrizRegla.tramos([nil, a, nil]), [[a]])
        XCTAssertEqual(MatrizRegla.tramos([]), [])
        XCTAssertEqual(MatrizRegla.tramos([nil, nil]), [])
        XCTAssertEqual(MatrizRegla.tramos([a, b, c, d]), [[a, b, c, d]])
    }

    // MARK: catmull — la receta compartida no degenera

    func test_catmull_recorre_todos_los_puntos() {
        let pts = [CGPoint(x: 0, y: 10), CGPoint(x: 10, y: 0),
                   CGPoint(x: 20, y: 10), CGPoint(x: 30, y: 5)]
        let path = MatrizRegla.catmull(pts)
        XCTAssertFalse(path.isEmpty)
        // El path termina exactamente en el último punto (la gota se posa ahí).
        XCTAssertEqual(path.currentPoint, pts.last)
    }

    func test_catmull_un_punto_no_dibuja() {
        let path = MatrizRegla.catmull([CGPoint(x: 3, y: 3)])
        XCTAssertEqual(path.currentPoint, CGPoint(x: 3, y: 3))
    }

    // MARK: xIndice — LA fórmula única (curva, gemelos, hilo y gesto coinciden)

    func test_xIndice_bordes_y_paridad_con_gesto() {
        let width: CGFloat = 300
        let count = 20
        // Primer punto: en el inset izquierdo; último: al final del ancho útil.
        XCTAssertEqual(MatrizRegla.xIndice(0, count: count, width: width),
                       MatrizTokens.chartInset)
        XCTAssertEqual(MatrizRegla.xIndice(count - 1, count: count, width: width),
                       width - MatrizTokens.reglaZona, accuracy: 0.001)
        // Paridad con el mapeo del gesto (serie): round(rel·(n−1)) recupera el índice
        // exacto cuando el dedo cae en la x del punto.
        for i in [0, 1, 7, 12, count - 1] {
            let x = MatrizRegla.xIndice(i, count: count, width: width)
            let usable = width - MatrizTokens.chartInset - MatrizTokens.reglaZona
            let rel = (x - MatrizTokens.chartInset) / usable
            let recuperado = Int((rel * CGFloat(count - 1)).rounded())
            XCTAssertEqual(recuperado, i, "índice \(i) no se recupera del gesto")
        }
    }

    // MARK: indicePrincipal — el trim escribe el tramo correcto

    func test_indicePrincipal_mas_largo_y_empate_reciente() {
        let a = CGPoint(x: 1, y: 1), b = CGPoint(x: 2, y: 2), c = CGPoint(x: 3, y: 3)
        // El más largo gana.
        XCTAssertEqual(MatrizRegla.indicePrincipal([[a, b], [a, b, c], [a]]), 1)
        // Empate → el MÁS RECIENTE (contiene a HOY).
        XCTAssertEqual(MatrizRegla.indicePrincipal([[a, b], [b, c]]), 1)
        XCTAssertNil(MatrizRegla.indicePrincipal([]))
    }

    func test_xIndice_serie_de_uno_no_divide_por_cero() {
        _ = MatrizRegla.xIndice(0, count: 1, width: 300)   // no crash
    }
}
