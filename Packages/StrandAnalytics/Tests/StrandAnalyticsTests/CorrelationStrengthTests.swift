import XCTest
@testable import StrandAnalytics

/// Guarda del contrato de fuerza de correlación (FER-104 / TND-29, foco 1): existe UNA sola escalera
/// que nombra un |r|, con cortes únicos y una banda por rango. La clase de defecto que mata: dos
/// escaleras rivales para «la misma cosa» con cortes distintos (la que produjo P1 en gemelas y en el
/// detalle de vital). El efecto (d de Cohen / magnitude word) NO se fija aquí a propósito:
/// es una escala legítimamente distinta y vive en el app con su propia palabra («medium»).
final class CorrelationStrengthTests: XCTestCase {

    // MARK: - Los cortes exactos (half-open), una banda por rango

    func testCortesDeLaEscalera() {
        // Centro de cada tramo.
        XCTAssertEqual(CorrelationStrength.classify(r: 0.05), .negligible)
        XCTAssertEqual(CorrelationStrength.classify(r: 0.20), .weak)
        XCTAssertEqual(CorrelationStrength.classify(r: 0.40), .moderate)
        XCTAssertEqual(CorrelationStrength.classify(r: 0.60), .strong)
        XCTAssertEqual(CorrelationStrength.classify(r: 0.90), .veryStrong)
    }

    /// Los bordes son half-open [lo, hi): el corte pertenece al tramo superior.
    func testBordesHalfOpen() {
        XCTAssertEqual(CorrelationStrength.classify(r: 0.10), .weak,       "0.10 sube a weak")
        XCTAssertEqual(CorrelationStrength.classify(r: 0.30), .moderate,   "0.30 sube a moderate")
        XCTAssertEqual(CorrelationStrength.classify(r: 0.50), .strong,     "0.50 sube a strong")
        XCTAssertEqual(CorrelationStrength.classify(r: 0.70), .veryStrong, "0.70 sube a very strong")
        // Justo por debajo del corte se queda en el tramo inferior.
        XCTAssertEqual(CorrelationStrength.classify(r: 0.4999), .moderate)
    }

    /// La fuerza mira |r|: el signo no cambia la banda (−0.9 es tan fuerte como +0.9).
    func testSignoNoCambiaLaFuerza() {
        XCTAssertEqual(CorrelationStrength.classify(r: -0.60), .strong)
        XCTAssertEqual(CorrelationStrength.classify(r: -0.05), .negligible)
        XCTAssertEqual(CorrelationStrength.classify(r: -1.00), .veryStrong)
        for r in stride(from: -1.0, through: 1.0, by: 0.01) {
            XCTAssertEqual(CorrelationStrength.classify(r: r),
                           CorrelationStrength.classify(r: -r),
                           "classify(\(r)) debe igualar classify(\(-r))")
        }
    }

    /// Una sola palabra por rango: la partición cubre [0, ∞) sin huecos ni solapes — cada |r| cae en
    /// exactamente una banda, y las 5 bandas aparecen a lo largo del rango.
    func testUnaBandaPorRangoSinHuecos() {
        var vistas = Set<CorrelationStrength>()
        var previa = CorrelationStrength.classify(r: 0)
        for milesima in 0...1000 {
            let r = Double(milesima) / 1000.0
            let banda = CorrelationStrength.classify(r: r)
            vistas.insert(banda)
            // Monotonía: la fuerza nunca retrocede al subir |r|.
            XCTAssertGreaterThanOrEqual(orden(banda), orden(previa),
                                        "la escalera no puede retroceder en r=\(r)")
            previa = banda
        }
        XCTAssertEqual(vistas, Set(CorrelationStrength.allCases),
                       "las 5 bandas deben aparecer a lo largo de [0,1]")
    }

    // MARK: - El gate n canónico

    func testGateNCanonico() {
        XCTAssertEqual(CorrelationStrength.minPairs, 3,
                       "n=2 da r=±1 trivial; 3 es el piso (igual que CorrelationEngine.pearson)")
    }

    private func orden(_ b: CorrelationStrength) -> Int {
        switch b {
        case .negligible: return 0
        case .weak:       return 1
        case .moderate:   return 2
        case .strong:     return 3
        case .veryStrong: return 4
        }
    }
}
