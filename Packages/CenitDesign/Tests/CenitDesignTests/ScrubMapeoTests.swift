import XCTest
import SwiftUI
@testable import CenitDesign

/// FER-62 — el mapeo dedo→índice del scrub, extraído a puro para fijar el bug que destapó
/// el `/arquitecto`: `.barrasMini` son BINS (como columnas), NO una serie. Vivían en la rama
/// de serie (i/(n−1), redondeo) cuando debían partir el ancho en `n` cajones (floor) — el
/// índice se desfasaba hasta un día. Nunca se ejerció porque barrasMini no tenía scrub…
/// hasta Folio D, que le da scrub a Esfuerzo. Este test es el contrato que lo impide volver.
final class ScrubMapeoTests: XCTestCase {

    // MARK: Clasificación de forma

    func testBarrasMiniSonBins() {
        XCTAssertFalse(ScrubMapeo.esSerie(.barrasMini(valores: [1, 2, 3])),
                       "barrasMini son bins de ancho igual, no una serie")
    }

    func testColumnasSonBins() {
        XCTAssertFalse(ScrubMapeo.esSerie(.columnas(noches: [], referencia: 7,
                                                    referenciaTag: "7 h", dominio: 4...10)))
    }

    func testSeriesDeContextoRedondean() {
        XCTAssertTrue(ScrubMapeo.esSerie(.escalerita(niveles: [0, 1, 2])))
        XCTAssertTrue(ScrubMapeo.esSerie(.lineaRellena(puntos: [1, 2], base: nil,
                                                       dominio: 0...10, alfa: 1, alertaHoy: .ninguna)))
        XCTAssertTrue(ScrubMapeo.esSerie(.regla(puntos: [1, 2], banda: nil,
                                                dominio: 0...10, alertaHoy: .ninguna)))
    }

    // MARK: Índice bajo el dedo

    private let n = 14
    private let ancho: CGFloat = 140
    private let inset: CGFloat = 4

    func testBordesAterrizanIgualEnAmbosModos() {
        // Extremo izquierdo → primer día; extremo derecho → último — sin importar el modo.
        for esSerie in [true, false] {
            XCTAssertEqual(ScrubMapeo.indice(x: inset, inset: inset, ancho: ancho,
                                             count: n, esSerie: esSerie), 0)
            XCTAssertEqual(ScrubMapeo.indice(x: inset + ancho, inset: inset, ancho: ancho,
                                             count: n, esSerie: esSerie), n - 1)
        }
    }

    func testFueraDeRangoSeClampa() {
        XCTAssertEqual(ScrubMapeo.indice(x: -50, inset: inset, ancho: ancho, count: n, esSerie: true), 0)
        XCTAssertEqual(ScrubMapeo.indice(x: 9_999, inset: inset, ancho: ancho, count: n, esSerie: false), n - 1)
    }

    func testDegeneradosNoRevientan() {
        XCTAssertEqual(ScrubMapeo.indice(x: 10, inset: 0, ancho: 0, count: 14, esSerie: true), 13)
        XCTAssertEqual(ScrubMapeo.indice(x: 10, inset: 0, ancho: 100, count: 1, esSerie: false), 0)
        XCTAssertEqual(ScrubMapeo.indice(x: 10, inset: 0, ancho: 100, count: 0, esSerie: false), 0)
    }

    /// EL BUG, fijado: a la misma x, bins y serie aterrizan en días distintos. Tratar barras
    /// como serie (lo viejo) leería el día equivocado; el contrato exige que barras use bins.
    func testBinsYSerieDivergen_yBarrasUsaBins() {
        let x = inset + ancho * 0.93
        let comoBin = ScrubMapeo.indice(x: x, inset: inset, ancho: ancho, count: n, esSerie: false)
        let comoSerie = ScrubMapeo.indice(x: x, inset: inset, ancho: ancho, count: n, esSerie: true)
        XCTAssertNotEqual(comoBin, comoSerie, "a 0.93 del ancho los modos difieren")
        // Y para una forma de barras, el modo correcto (bins) es el que se elige.
        let barras = MatrizChartPayload.barrasMini(valores: Array(repeating: 1.0, count: n))
        let elegido = ScrubMapeo.indice(x: x, inset: inset, ancho: ancho, count: n,
                                        esSerie: ScrubMapeo.esSerie(barras))
        XCTAssertEqual(elegido, comoBin, "barrasMini debe leerse como bins, no como serie")
    }
}
