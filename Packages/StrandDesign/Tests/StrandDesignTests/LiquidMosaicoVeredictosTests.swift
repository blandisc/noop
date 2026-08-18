import XCTest
import SwiftUI
@testable import StrandDesign

/// Los contratos PUROS del mosaico — los mismos que leen la vista y VoiceOver.
final class LiquidMosaicoVeredictosTests: XCTestCase {

    private func dia(_ i: Int, _ peldano: String?) -> LiquidMosaicoVeredictos.Dia {
        .init(id: "d\(i)", fecha: Date(timeIntervalSince1970: 1_700_000_000 + Double(i) * 86_400),
              peldano: peldano, etiqueta: "día \(i)")
    }

    /// El denominador es la VENTANA, no los días con fila. Si contara solo los presentes,
    /// VoiceOver diría «8 de 22» cuando la ventana son 30 — el defecto que motivó la rejilla densa.
    func testConteoUsaLaVentanaCompletaComoDenominador() {
        var dias: [LiquidMosaicoVeredictos.Dia?] = (0..<30).map { _ in nil }
        dias[0] = dia(0, "full")
        dias[15] = dia(15, "caution")
        let c = LiquidMosaicoVeredictos.conteo(dias)
        XCTAssertEqual(c.conDato, 2)
        XCTAssertEqual(c.total, 30, "un día sin fila sigue ocupando su lugar en la ventana")
    }

    /// Un día CON fila pero sin veredicto legible tampoco cuenta como leído.
    func testDiaConFilaSinVeredictoNoCuentaComoLeido() {
        let dias: [LiquidMosaicoVeredictos.Dia?] = [dia(0, "full"), dia(1, nil), nil]
        XCTAssertEqual(LiquidMosaicoVeredictos.conteo(dias).conDato, 1)
        XCTAssertEqual(LiquidMosaicoVeredictos.conteo(dias).total, 3)
    }

    /// El gesto de ajuste de VoiceOver camina SOLO los días con veredicto: detenerse en un
    /// hueco dejaría al usuario oyendo el conteo sin lectura, sin saber por qué.
    func testElAjusteSaltaLosHuecos() {
        let dias: [LiquidMosaicoVeredictos.Dia?] = [dia(0, "full"), nil, dia(2, nil), dia(3, "easy")]
        XCTAssertEqual(LiquidMosaicoVeredictos.vecino(dias: dias, desde: nil, paso: 1), "d0")
        XCTAssertEqual(LiquidMosaicoVeredictos.vecino(dias: dias, desde: "d0", paso: 1), "d3",
                       "salta el hueco y el día sin veredicto")
        XCTAssertEqual(LiquidMosaicoVeredictos.vecino(dias: dias, desde: "d3", paso: 1), "d3",
                       "no se sale por el borde")
        XCTAssertEqual(LiquidMosaicoVeredictos.vecino(dias: dias, desde: "d3", paso: -1), "d0")
    }

    /// Una ventana entera sin veredicto no debe fabricar una selección fantasma.
    func testVentanaSinVeredictoNoSelecciona() {
        let dias: [LiquidMosaicoVeredictos.Dia?] = (0..<30).map { _ in nil }
        XCTAssertNil(LiquidMosaicoVeredictos.vecino(dias: dias, desde: nil, paso: 1))
        XCTAssertEqual(LiquidMosaicoVeredictos.conteo(dias).total, 30)
    }

    func testTocarElYaSeleccionadoLoSuelta() {
        XCTAssertEqual(LiquidMosaicoVeredictos.alterna(seleccion: nil, toca: "d3"), "d3")
        XCTAssertNil(LiquidMosaicoVeredictos.alterna(seleccion: "d3", toca: "d3"))
        XCTAssertEqual(LiquidMosaicoVeredictos.alterna(seleccion: "d3", toca: "d4"), "d4")
    }

    /// VoiceOver dice el conteo y, con un día tocado, además su lectura.
    func testElValorDeVoiceOverComponeConteoYLectura() {
        let dias: [LiquidMosaicoVeredictos.Dia?] = [dia(0, "full"), nil, dia(2, "easy")]
        let fmt: (Int, Int) -> String = { "\($0) de \($1)" }
        XCTAssertEqual(LiquidMosaicoVeredictos.a11yValor(dias: dias, seleccion: nil, conteo: fmt),
                       "2 de 3")
        XCTAssertEqual(LiquidMosaicoVeredictos.a11yValor(dias: dias, seleccion: "d2", conteo: fmt),
                       "2 de 3, día 2")
    }

    /// Una selección que ya no existe (la ventana rodó) no debe romper el valor dictado.
    func testSeleccionHuerfanaCaeAlConteo() {
        let dias: [LiquidMosaicoVeredictos.Dia?] = [dia(0, "full")]
        XCTAssertEqual(
            LiquidMosaicoVeredictos.a11yValor(dias: dias, seleccion: "borrado", conteo: { "\($0)/\($1)" }),
            "1/1")
    }
}
