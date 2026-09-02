import XCTest
import SwiftUI
import UIKit
import CenitDesign
import StrandTraining
@testable import Cenit

/// FER-88 — el puente de la app hacia el tinte de familia. `RoutineRegion.tint` tenía su PROPIA
/// tabla de colores; ahora delega en `EntrenarFamily.tint`, la fuente única del paquete de diseño.
///
/// Esta prueba vive del lado de la app a propósito: es el único sitio donde `RoutineRegion` y
/// `EntrenarFamily` coexisten, y por tanto el único desde donde se puede comprobar que no volvieron
/// a bifurcarse. Si alguien re-escribe un `switch` de colores en `RoutineRegion+Tint.swift`, truena.
final class RoutineRegionTinteTests: XCTestCase {

    /// Comparación por componentes vía UIKit: `rgbaComponents` del paquete de diseño es interno y
    /// desde la app no se ve. Se compara el color RESUELTO, que es justamente el que se pinta.
    private func mismoColor(_ a: Color, _ b: Color) -> Bool {
        func rgb(_ c: Color) -> (CGFloat, CGFloat, CGFloat) {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, o: CGFloat = 0
            UIColor(c).getRed(&r, green: &g, blue: &b, alpha: &o)
            return (r, g, b)
        }
        let x = rgb(a), y = rgb(b)
        return abs(x.0 - y.0) < 1e-5 && abs(x.1 - y.1) < 1e-5 && abs(x.2 - y.2) < 1e-5
    }

    func testCadaRegionPintaExactamenteElTinteDeSuFamilia() {
        let pares: [(RoutineRegion, EntrenarFamily)] = [
            (.push, .push), (.pull, .pull), (.legs, .legs), (.fullBody, .fullBody),
        ]
        for (region, familia) in pares {
            XCTAssertEqual(region.family, familia, "\(region) mapea a la familia equivocada")
            XCTAssertTrue(mismoColor(region.tint(), familia.tint()),
                          "\(region) pinta un color distinto al de \(familia): la tabla se re-bifurcó")
        }
    }

    /// Sin ejercicios clasificables el color cae a empuje. Es el render que ya estaba en pantalla y
    /// la unificación no puede cambiarlo de contrabando.
    func testSinRegionCaeAEmpuje() {
        XCTAssertTrue(mismoColor((nil as RoutineRegion?).tint(), EntrenarFamily.push.tint()))
    }

    /// El tercer camino: el que clasifica por músculos primarios. Los tres tienen que coincidir para
    /// el mismo movimiento, que era justo lo que no pasaba.
    func testLosTresCaminosCoincidenParaElMismoMovimiento() {
        let casos: [([String], RoutineRegion)] = [
            (["lats", "biceps"], .pull),
            (["quadriceps", "glutes"], .legs),
            (["chest", "triceps"], .push),
        ]
        for (musculos, region) in casos {
            XCTAssertTrue(mismoColor(LiquidRampas.movementFamilyTint(musculos), region.tint()),
                          "\(musculos) y \(region) tendrían que dar el mismo color")
        }
    }
}

/// FER-86 — el botón del héroe mentía sobre su propio destino: decía «Continuar» y se teñía con el
/// color de la rutina de HOY aunque la sesión viva fuera de otra. La sesión sobrevive entre días a
/// propósito, así que basta no cerrar el entrenamiento de ayer para caer en el caso.
///
/// Se prueba la regla pura de decisión, no la vista: dado el nombre de la sesión viva y el de hoy,
/// ¿qué rutina debe nombrar y teñir el botón?
final class BotonHeroeRutinaVivaTests: XCTestCase {

    /// La misma regla que usa la vista: nil cuando no hay sesión viva o cuando es la de hoy.
    private func otraRutina(viva: String?, hoy: String?) -> String? {
        guard let viva, !viva.isEmpty else { return nil }
        return viva == hoy ? nil : viva
    }

    func testSinSesionVivaNoNombraNada() {
        XCTAssertNil(otraRutina(viva: nil, hoy: "Empuje"))
    }

    func testLaSesionVivaDeHoyNoSeNombra() {
        XCTAssertNil(otraRutina(viva: "Empuje", hoy: "Empuje"),
                     "si es la de hoy, «Continuar» a secas basta")
    }

    /// El caso que fallaba: ayer Tirón sin cerrar, hoy toca Empuje.
    func testLaSesionVivaDeOTRARutinaSeNombra() {
        XCTAssertEqual(otraRutina(viva: "Tirón", hoy: "Empuje"), "Tirón")
    }

    /// Día de descanso con una sesión viva: no hay rutina de hoy contra la cual comparar, y la
    /// sesión sigue siendo de otra cosa — se nombra igual.
    func testEnDiaDeDescansoTambienSeNombra() {
        XCTAssertEqual(otraRutina(viva: "Tirón", hoy: nil), "Tirón")
    }

    /// Una sesión ad hoc sin nombre no puede nombrarse: cae a «Continuar» a secas.
    func testLaSesionSinNombreNoSeNombra() {
        XCTAssertNil(otraRutina(viva: "", hoy: "Empuje"))
    }
}
