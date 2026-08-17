import XCTest
import SwiftUI
@testable import StrandDesign

/// FER-51 §12 — los valores en hue sobre `papelMatriz` deben leer: los tonos que se usan
/// como TEXTO normal (temp 13 pt) exigen AA 4.5:1; los votantes grandes (20–26 pt) AA-large
/// 3:1. `doradoTemp` nació oscurecido justo para pasar este gate (no bajarlo sin rojo aquí).
final class MatrizContrasteTests: XCTestCase {

    private func luminance(_ c: Color) -> Double {
        let k = c.rgbaComponents
        return 0.2126 * OKLab.srgbToLinear(k.r) + 0.7152 * OKLab.srgbToLinear(k.g) + 0.0722 * OKLab.srgbToLinear(k.b)
    }
    private func contrast(_ a: Color, _ b: Color) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// Texto normal (el valor de temp del guardián va a 13 pt): AA pleno.
    func testDoradoTempPasaAATextoNormalSobrePapelMatriz() {
        XCTAssertGreaterThanOrEqual(contrast(LiquidColor.doradoTemp, LiquidColor.papelMatriz), 4.5)
    }

    /// Los hues de los votantes se usan a 20–26 pt (large text): AA-large.
    func testHuesDeVotantesPasanAALargeSobrePapelMatriz() {
        for (nombre, hue) in [("indigo", LiquidColor.indigo),
                              ("rosa", LiquidColor.rosa),
                              ("verdePrimario", LiquidColor.verdePrimario),
                              ("azul", LiquidColor.azul),
                              ("cian", LiquidColor.cian)] {
            XCTAssertGreaterThanOrEqual(contrast(hue, LiquidColor.papelMatriz), 3.0,
                                        "\(nombre) por debajo de AA-large sobre papelMatriz")
        }
    }

    /// La identidad de temp y el ámbar de ATENCIÓN no pueden confundirse: exige una
    /// separación mínima de luminancia entre `doradoTemp` y `atencion`.
    /// Los cuatro tonos que los sellos reasignaron (ago-2026): siguen pintando el numeral
    /// de su fila, así que tienen que aguantar el mismo piso que el resto de los datos.
    /// `verdeCarga` y `ambarEstres` se acuñaron aquí y pasan incluso AA de texto normal.
    func testHuesReasignadosPorLosSellosPasanAALargeSobrePapelMatriz() {
        for (nombre, hue) in [("verdeCarga · carga", LiquidColor.verdeCarga),
                              ("ambarEstres · estrés", LiquidColor.ambarEstres),
                              ("ambar · esfuerzo", LiquidColor.ambar),
                              ("teal · pasos", LiquidColor.teal)] {
            XCTAssertGreaterThanOrEqual(contrast(hue, LiquidColor.papelMatriz), 3.0,
                                        "\(nombre) no pasa AA-large sobre el papel de la Matriz")
        }
    }

    /// La identidad de CARGA no puede ser la voz de marca: `verdePrimario` es el CTA y el
    /// veredicto, y además es la zona «bajo» del medidor de estrés — el mismo hex diciendo
    /// dos cosas a tres sellos de distancia.
    func testCargaNoVisteLaVozDeMarca() {
        XCTAssertNotEqual(LiquidColor.verdeCarga, LiquidColor.verdePrimario)
    }

    func testDoradoTempNoEsElAmbarDeAtencion() {
        let dl = abs(luminance(LiquidColor.doradoTemp) - luminance(LiquidColor.atencion))
        XCTAssertGreaterThan(dl, 0.03, "doradoTemp y atencion quedaron demasiado cerca")
    }
}
