import XCTest
import SwiftUI
@testable import StrandDesign

/// Ancla de los sellos de métrica de Hoy. `SelloMetricaPaths.swift` lo GENERA
/// `Tools/sellos-hoy/forge.py`, así que la garantía no puede ser «lo revisé»: si una corrida
/// del forjador emite un path roto, uno vacío o uno que se sale de la caja, esto rompe CI en
/// vez de llegar a la pantalla como un sello invisible o recortado.
///
/// El área segura y los mínimos a 20 pt los verifica el propio forjador al emitir; aquí se
/// comprueba lo que solo se ve del lado de Swift: que el parser los entienda y que lo
/// parseado siga cayendo donde debe.
final class SelloMetricaTests: XCTestCase {

    /// El viewBox del forjador. La tinta vive en [2,22] con holgura de medio punto para el
    /// redondeo a 2 decimales de la emisión.
    private let caja = CGRect(x: 1.5, y: 1.5, width: 21, height: 21)

    func test_losDiezSellosTienenPartes() {
        XCTAssertEqual(SelloMetrica.allCases.count, 10)
        for sello in SelloMetrica.allCases {
            XCTAssertFalse(sello.partes.isEmpty, "\(sello.rawValue) no emitió ninguna parte")
        }
    }

    /// Todo path parsea a algo con superficie: un `d` malformado devuelve un `Path` vacío y
    /// el sello desaparecería en silencio (es exactamente el modo de fallo que costó los
    /// «iconos invisibles» de SVGPathData en iOS).
    func test_cadaParteParseaYTieneArea() {
        for sello in SelloMetrica.allCases {
            for (i, parte) in sello.partes.enumerated() {
                let path = SVGPathData.path(parte.d)
                XCTAssertFalse(path.isEmpty, "\(sello.rawValue)[\(i)] parseó a un path vacío")
                let caja = path.boundingRect
                XCTAssertGreaterThan(caja.width, 0.5, "\(sello.rawValue)[\(i)] sin ancho")
                XCTAssertGreaterThan(caja.height, 0.5, "\(sello.rawValue)[\(i)] sin alto")
            }
        }
    }

    /// Nada se sale del área segura: un sello que desborda el viewBox se recorta contra el
    /// borde de su gota y se ve mordido.
    func test_todoCaeDentroDelAreaSegura() {
        for sello in SelloMetrica.allCases {
            let union = sello.partes
                .map { SVGPathData.path($0.d).boundingRect }
                .reduce(CGRect.null) { $0.union($1) }
            XCTAssertTrue(caja.contains(union),
                          "\(sello.rawValue) se sale del área segura: \(union)")
        }
    }

    /// El sello se centra en la caja: el forjador centra ópticamente en (12,12) y una deriva
    /// ahí descuadra la fila entera contra el título.
    func test_cadaSelloEstaCentrado() {
        for sello in SelloMetrica.allCases {
            let union = sello.partes
                .map { SVGPathData.path($0.d).boundingRect }
                .reduce(CGRect.null) { $0.union($1) }
            XCTAssertEqual(union.midX, 12, accuracy: 0.15, "\(sello.rawValue) descentrado en x")
            XCTAssertEqual(union.midY, 12, accuracy: 0.15, "\(sello.rawValue) descentrado en y")
        }
    }

    /// Los tres sellos que tallan su lectura en negativo (corazón, termómetro, pesa) tienen
    /// que rellenarse con regla par-impar o el hueco se pinta sólido.
    func test_lasTallasPidenParImpar() {
        let conTalla = Set(SelloMetrica.allCases.filter { s in s.partes.contains { $0.talla } })
        XCTAssertEqual(conTalla, [.reposo, .piel, .carga])
    }

    /// El Guardián conserva su orbe VIVO en la Matriz, pero su sello existe para las hojas
    /// y el specimen: si desapareciera del generado, el catálogo quedaría cojo sin avisar.
    func test_elGuardianTieneSelloAunqueNoLoUseLaMatriz() {
        XCTAssertFalse(SelloMetrica.guardian.partes.isEmpty)
    }
}
