import XCTest
import StrandAnalytics
@testable import Cenit

/// La guarda del contrato de TND-10 (FER-101): el detalle de Esfuerzo tiene UNA sola escalera —
/// `MetricLevels.displayBands(for: .strain)` — y TODAS las representaciones (frase del héroe,
/// palabra del calendario, carril activo) salen de ella. La clase de defecto que mata: dos
/// escaleras conviviendo en la misma pantalla (TND10-1: el calendario teñía por 5 carriles pero
/// la palabra cortaba en 14/8; TND10-2: el `switch` del héroe venía de la era de 4 bandas y
/// leía un peldaño corrido).
///
/// La suite corre en inglés: las frases se afirman contra el defaultValue EN, que es el texto
/// fuente del catálogo — la guarda fija el MAPEO carril→texto, no la traducción.
final class StrainEscaleraUnicaTests: XCTestCase {

    /// La escalera es la del motor: cinco carriles, en su orden, con los cortes 6/10/14/18.
    func testEscaleraEsLaDelMotor() {
        let keys = StrainDetailScreen.bandasEsfuerzo.map(\.key)
        XCTAssertEqual(keys, ["rest", "light", "moderate", "hard", "extreme"])
        // Fronteras half-open [lo, hi): el valor exacto del corte cae al carril de ARRIBA.
        let esperados: [(Double, Int)] = [
            (0, 0), (5.9, 0),
            (6, 1), (9.9, 1),
            (10, 2), (13.9, 2),
            (14, 3), (17.9, 3),
            (18, 4), (21, 4), (25, 4),
        ]
        for (v, carril) in esperados {
            XCTAssertEqual(StrainDetailScreen.indiceCarril(v), carril,
                           "\(v) debía caer en el carril \(carril)")
        }
    }

    /// TND10-2: la frase del héroe nombra el MISMO carril que la tabla/el calendario — un día
    /// «light» lee suave, nunca «Moderate effort» (el peldaño corrido del switch viejo).
    func testFraseDelHeroeAlineadaAlCarril() {
        XCTAssertTrue(StrainDetailScreen.fraseCarril("rest").hasPrefix("Light load"))
        XCTAssertTrue(StrainDetailScreen.fraseCarril("light").hasPrefix("Light load"))
        XCTAssertTrue(StrainDetailScreen.fraseCarril("moderate").hasPrefix("Moderate"))
        XCTAssertTrue(StrainDetailScreen.fraseCarril("hard").hasPrefix("Hard effort"))
        XCTAssertTrue(StrainDetailScreen.fraseCarril("extreme").hasPrefix("All-out"))
    }

    /// TND10-1: la palabra del día tocado en el calendario ES la etiqueta del carril de la
    /// escalera única (paridad `SleepDetailScreen.sleepWord`) — nunca una segunda copia de los
    /// cortes. 8.5 era el caso que mentía: se teñía «light» y decía «moderate».
    func testPalabraDelCalendarioEsLaEtiquetaDelCarril() {
        for v in [3.0, 8.5, 12.0, 15.0, 19.0] {
            guard let i = StrainDetailScreen.indiceCarril(v) else {
                return XCTFail("\(v) no cayó en ningún carril (la escalera debe ser partición total)")
            }
            XCTAssertEqual(StrainDetailScreen.strainWord(v),
                           StrainDetailScreen.bandasEsfuerzo[i].label,
                           "la palabra de \(v) debía ser la etiqueta de su carril")
        }
    }
}
