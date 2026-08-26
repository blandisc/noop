import XCTest
import CoreGraphics
@testable import StrandDesign

// MARK: - A′ · los rótulos de las señales despegan del orbe (FER-157)
//
// El rótulo de cada señal cuelga de su cuerpo orbital; cuando el cuerpo cruza la cara del orbe
// fundido, su rótulo caía SOBRE los puntos. `rotuloAlFilo` lo empuja radialmente hasta el filo
// (`radioOrbe + margenRotuloOrbe`). Es geometría pura, así que se prueba sin Canvas — y el
// mismo helper sirve al estado con veredicto y al estado sin lectura (comparten el plan).

final class EcosistemaRotuloAlFiloTests: XCTestCase {
    typealias Sim = EcosistemaSimulacion
    typealias G = EcosistemaSimulacion.Geometria

    private func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        ((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)).squareRoot()
    }

    /// Un rótulo YA fuera del filo no se toca: es el caso de los flancos, que dominan el look del
    /// veredicto aprobado. Si esta prueba se rompe, el arreglo está moviendo rótulos que ya estaban bien.
    func test_fueraDelFiloNoSeMueve() {
        let centro = G.centro
        let lejos = CGPoint(x: centro.x + G.radioOrbe + G.margenRotuloOrbe + 30, y: centro.y)
        let r = Sim.rotuloAlFilo(lejos, centroOrbe: centro, radioOrbe: G.radioOrbe)
        XCTAssertEqual(r.x, lejos.x, accuracy: 0.001)
        XCTAssertEqual(r.y, lejos.y, accuracy: 0.001)
    }

    /// Un rótulo que cae DENTRO del disco se empuja EXACTAMENTE al filo, en la misma dirección
    /// (radial desde el centro del orbe) — nunca queda sobre las partículas.
    func test_dentroDelDiscoSeEmpujaAlFilo() {
        let centro = G.centro
        // Un punto bajo el orbe, a mitad del radio (claramente sobre el disco).
        let dentro = CGPoint(x: centro.x, y: centro.y + G.radioOrbe * 0.5)
        let r = Sim.rotuloAlFilo(dentro, centroOrbe: centro, radioOrbe: G.radioOrbe)
        XCTAssertEqual(dist(r, centro), G.radioOrbe + G.margenRotuloOrbe, accuracy: 0.001,
                       "queda exactamente en el filo")
        XCTAssertEqual(r.x, centro.x, accuracy: 0.001, "misma dirección (recto abajo)")
        XCTAssertGreaterThan(r.y, centro.y, "hacia el mismo lado del cuerpo")
    }

    /// La dirección se conserva en diagonal: el rótulo se aleja del centro por su propio radio,
    /// no salta a otro cuadrante.
    func test_conservaLaDireccionEnDiagonal() {
        let centro = G.centro
        let dentro = CGPoint(x: centro.x - 10, y: centro.y - 10)   // arriba-izquierda, dentro
        let r = Sim.rotuloAlFilo(dentro, centroOrbe: centro, radioOrbe: G.radioOrbe)
        XCTAssertLessThan(r.x, centro.x, "sigue a la izquierda")
        XCTAssertLessThan(r.y, centro.y, "sigue arriba")
        XCTAssertEqual(dist(r, centro), G.radioOrbe + G.margenRotuloOrbe, accuracy: 0.001)
    }

    /// Degenerado (rótulo justo en el centro del orbe): no hay dirección, se baja al filo inferior
    /// en vez de dividir por cero.
    func test_enElCentroCaeAlFiloInferior() {
        let centro = G.centro
        let r = Sim.rotuloAlFilo(centro, centroOrbe: centro, radioOrbe: G.radioOrbe)
        XCTAssertEqual(r.x, centro.x, accuracy: 0.001)
        XCTAssertEqual(r.y, centro.y + G.radioOrbe + G.margenRotuloOrbe, accuracy: 0.001)
    }

    /// El contrato universal: pase lo que pase, el punto resultante NUNCA queda dentro del filo.
    func test_invarianteNuncaDentroDelFilo() {
        let centro = G.centro
        let filo = G.radioOrbe + G.margenRotuloOrbe
        for dx in stride(from: -80, through: 80, by: 13) {
            for dy in stride(from: -80, through: 80, by: 13) {
                let p = CGPoint(x: centro.x + CGFloat(dx), y: centro.y + CGFloat(dy))
                let r = Sim.rotuloAlFilo(p, centroOrbe: centro, radioOrbe: G.radioOrbe)
                XCTAssertGreaterThanOrEqual(dist(r, centro), filo - 0.001,
                                            "dx=\(dx) dy=\(dy) quedó dentro del filo")
            }
        }
    }

    /// Integración: en el estado FUNDIDO con veredicto, NINGÚN rótulo del plan se dibuja sobre el
    /// disco del orbe — el punto de cada `.rotulo` cae en (o más allá de) el filo. Es el criterio
    /// de aceptación de A′, verificado sobre el plan real (`still` = cuadro asentado, sin animación).
    func test_enFundidoNingunRotuloSobreElDisco() {
        let escena = Sim.Escena(coreo: .enRango, fase: .viva(desde: 0), still: true,
                                niveles: [0.7, 0.6], fuera: [false, false],
                                guardianJuntas: false, guardianHueco: false, eclipse: 0)
        let trazos = Sim.plan(t: 0, escena: escena)
        let puntos: [CGPoint] = trazos.compactMap {
            if case .rotulo(_, let en, _) = $0 { return en } else { return nil }
        }
        XCTAssertFalse(puntos.isEmpty, "el estado fundido sí dibuja rótulos")
        // El centro fundido asentado ≈ G.centro (apertura ≈ 0). El disco llega a `radioOrbe`;
        // el filo lo protege con `margenRotuloOrbe`. Toleramos 1 pt por el settle del orbe.
        for p in puntos {
            XCTAssertGreaterThanOrEqual(dist(p, G.centro), G.radioOrbe - 1,
                                        "rótulo en \(p) quedó sobre el disco del orbe")
        }
    }
}
