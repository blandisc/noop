import XCTest
import SwiftUI
@testable import CenitDesign

// MARK: - Los rótulos del héroe se ceden el paso (FER-117)
//
// En español, «TEMPERATURA» y «FC EN REPOSO» —versalitas espaciadas letra a letra— se montaban
// una sobre otra en parte de la órbita y quedaban ilegibles. La regla que lo arregla es pura
// geometría, así que se prueba sin Canvas: cede el de ATRÁS, en proporción al solape.

final class EcosistemaRotulosCesionTests: XCTestCase {

    private func caja(_ x: CGFloat, _ ancho: CGFloat, alfa: Double,
                      y: CGFloat = 100, alto: CGFloat = 12) -> (rect: CGRect, alfa: Double) {
        (CGRect(x: x, y: y, width: ancho, height: alto), alfa)
    }

    /// Separados, nadie cede: el caso de todos los días (y el de inglés, donde las palabras
    /// caben). Si esta prueba se rompe, el arreglo está apagando rótulos que se ven bien.
    func test_sinSolapeNadieCede() {
        let k = EcosistemaCesion.cesionesRotulos([caja(0, 60, alfa: 0.8),
                                                  caja(100, 60, alfa: 0.4)])
        XCTAssertEqual(k, [1, 1])
    }

    /// Encimados, cede el de ATRÁS — el de menor alfa, que en la escena es el que va al fondo
    /// de la órbita. El de adelante se queda intacto: el usuario siempre lee uno completo.
    func test_conSolapeCedeElDeAtras() {
        let k = EcosistemaCesion.cesionesRotulos([caja(0, 60, alfa: 0.9),      // adelante
                                                  caja(40, 60, alfa: 0.3)])    // atrás
        XCTAssertEqual(k[0], 1, "el de adelante no cede")
        XCTAssertLessThan(k[1], 1, "el de atrás sí")
    }

    /// La cesión es GRADUAL: desvanecerse de golpe se leería como un parpadeo en una órbita
    /// que gira todo el tiempo.
    func test_laCesionEsGradual() {
        let poco = EcosistemaCesion.cesionesRotulos([caja(0, 100, alfa: 0.9),
                                                     caja(95, 100, alfa: 0.3)])[1]
        let mucho = EcosistemaCesion.cesionesRotulos([caja(0, 100, alfa: 0.9),
                                                      caja(70, 100, alfa: 0.3)])[1]
        XCTAssertGreaterThan(poco, mucho, "a más solape, más cede")
        XCTAssertGreaterThan(poco, 0, "un roce no lo apaga entero")
    }

    /// Y con el solape franco desaparece: es el estado que el bug producía —dos palabras
    /// impresas una sobre otra— y el único donde apagar una es mejor que dibujar las dos.
    func test_conSolapeFrancoDesaparece() {
        let k = EcosistemaCesion.cesionesRotulos([caja(0, 100, alfa: 0.9),
                                                  caja(20, 100, alfa: 0.3)])
        XCTAssertEqual(k[1], 0, accuracy: 0.001)
    }

    /// Empate de alfa (mismo plano de la órbita): la regla tiene que ser determinista, o los
    /// dos se desvanecerían a la vez y no quedaría ninguno legible.
    func test_conAlfaIgualCedeSoloUno() {
        let k = EcosistemaCesion.cesionesRotulos([caja(0, 100, alfa: 0.5),
                                                  caja(30, 100, alfa: 0.5)])
        XCTAssertEqual(k.filter { $0 < 1 }.count, 1, "cede uno, no los dos")
    }

    /// Los rótulos que se cruzan en HORIZONTAL pero viven en renglones distintos no se estorban
    /// (las lunas orbitan arriba, los vigías abajo).
    func test_enRenglonesDistintosNadieCede() {
        let k = EcosistemaCesion.cesionesRotulos([caja(0, 100, alfa: 0.9, y: 100),
                                                  caja(20, 100, alfa: 0.3, y: 200)])
        XCTAssertEqual(k, [1, 1])
    }

    /// Un solo rótulo (o ninguno) no puede encimarse con nadie.
    func test_unoSoloNoCede() {
        XCTAssertEqual(EcosistemaCesion.cesionesRotulos([caja(0, 60, alfa: 0.5)]), [1])
        XCTAssertEqual(EcosistemaCesion.cesionesRotulos([]), [])
    }
}
