import XCTest
import SwiftUI
@testable import CenitDesign

/// A1/FER-345 — `OKLab.lightened` es el espejo de `OKLab.darkened` para suelo OSCURO: sube la
/// luminosidad hasta alcanzar el contraste pedido contra negro. Misma disciplina y misma autoridad
/// (`OKLab.contrastRatio`) que los tests OLED. Sin esto, `contrastTuned` no puede rescatar un tono de
/// dato que reprueba AA sobre negro (rosa/rojo/ámbar del iPhone: ver el análisis de D1).
final class OKLabLightenedTests: XCTestCase {

    /// Tonos del iPhone que reprueban AA sobre negro (medidos): rosa 4.39, rojo 3.79, ámbar 4.02.
    private var huesQueReprueban: [(String, Color)] {
        [("rosa", Color(hex: "#B85068")), ("rojo", Color(hex: "#BC3A34")), ("ámbar", Color(hex: "#9C5E10"))]
    }

    /// Aclarar alcanza el ratio pedido sobre negro para cada hue que hoy reprueba.
    func testAlcanzaElRatioSobreNegro() {
        let negro = Color.black
        for (nombre, hue) in huesQueReprueban {
            let out = OKLab.lightened(hue, toContrast: 4.5, against: negro)
            let cr = OKLab.contrastRatio(out, negro)
            XCTAssertGreaterThanOrEqual(cr, 4.5 - 0.02,
                "lightened(\(nombre)) debe alcanzar ≥4.5 sobre negro, dio \(cr)")
        }
    }

    /// Si el hue ya pasa, `lightened` lo deja intacto (no lo aclara de más — conserva el tono).
    func testDejaIntactoSiYaPasa() {
        let negro = Color.black
        let verde = Color(hex: "#2EB27D")   // ya pasa (~7.78 sobre negro)
        let out = OKLab.lightened(verde, toContrast: 4.5, against: negro)
        let a = verde.rgbaComponents, b = out.rgbaComponents
        XCTAssertEqual(a.r, b.r, accuracy: 1.0 / 255)
        XCTAssertEqual(a.g, b.g, accuracy: 1.0 / 255)
        XCTAssertEqual(a.b, b.b, accuracy: 1.0 / 255)
    }

    /// Monotonía: subir L nunca BAJA el contraste sobre negro (la propiedad que hace válida la bisección).
    func testMonotonoSobreNegro() {
        let negro = Color.black
        let base = OKLab.contrastRatio(Color(hex: "#7A3048"), negro)
        let masClaro = OKLab.contrastRatio(Color(hex: "#B85068"), negro)   // mismo tono, más claro
        XCTAssertGreaterThanOrEqual(masClaro, base)
    }
}
