import XCTest
@testable import CenitDesign

/// FER-59 — la fila gemela de «Contexto» (VFC | Estrés) no debe quedar con el borde
/// inferior dentado: sus charts deben medir lo mismo. `chartAltura` es `static internal`
/// justo para poder afirmarlo aquí sin depender de snapshots (que no son gate de CI).
final class MatrizChartAlturaTests: XCTestCase {

    func test_gemela_contexto_vfc_estres_misma_altura() {
        let vfc: MatrizChartPayload = .lineaRellena(puntos: [], base: nil,
                                                    dominio: 20...80, alfa: 0.6, alertaHoy: .ninguna)
        let estres: MatrizChartPayload = .escalerita(niveles: [])
        XCTAssertEqual(MatrizHoyFace.chartAltura(vfc), MatrizHoyFace.chartAltura(estres),
                       "VFC (lineaRellena) y Estrés (escalerita) son gemelas en Contexto")
    }

    /// La otra fila gemela (Carga | Esfuerzo) ya estaba alineada — no la rompemos.
    func test_gemela_carga_esfuerzo_misma_altura() {
        let carga: MatrizChartPayload = .colina(p: 1.0, zona: 0.8...1.3, estela: [])
        let esf: MatrizChartPayload = .barrasMini(valores: [])
        XCTAssertEqual(MatrizHoyFace.chartAltura(carga), MatrizHoyFace.chartAltura(esf),
                       "Carga (colina) y Esfuerzo (barrasMini) son gemelas en Contexto")
    }
}
