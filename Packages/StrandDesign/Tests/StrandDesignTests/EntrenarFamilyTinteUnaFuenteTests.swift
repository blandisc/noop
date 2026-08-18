import XCTest
import SwiftUI
@testable import StrandDesign

/// FER-88 — el tinte de familia estaba definido TRES veces y una de las tres se había ido por su
/// lado: `EntrenarFamily.tint` decía `dataSteps` (#4C8998) para tirón mientras `RoutineRegion.tint`
/// y `movementFamilyTint` decían `dataHrv` (#147C8C). El mismo tirón salía de dos colores según
/// quién lo dibujara — que es exactamente lo que la caja de piezas existía para impedir.
///
/// Estas pruebas no comprueban «que se vea bien»: comprueban que solo hay UNA tabla, y que la
/// clasificación por músculo sigue diciendo lo mismo que antes de separarla del color.
final class EntrenarFamilyTinteUnaFuenteTests: XCTestCase {

    private let theme = InstrumentoTheme.base

    /// Igualdad de color por componentes, no por luminancia: dos colores distintos pueden compartir
    /// luminancia y colarse por una comparación floja.
    private func mismoColor(_ a: Color, _ b: Color) -> Bool {
        let x = a.rgbaComponents, y = b.rgbaComponents
        return abs(x.r - y.r) < 1e-6 && abs(x.g - y.g) < 1e-6 && abs(x.b - y.b) < 1e-6
    }

    /// LA TABLA, clavada por valor. Esta es la prueba que de verdad puede fallar: si alguien cambia
    /// el color de una familia, truena aquí y tiene que ser una decisión, no un descuido.
    ///
    /// Un intento anterior comparaba el puente contra la familia — y como el puente ya DELEGA en la
    /// familia, la igualdad se cumplía sola: la prueba no podía reprobar. El canario lo destapó.
    func testLaTablaDeTintesEsLaQueSeAcordo() {
        let esperado: [(EntrenarFamily, Color, String)] = [
            (.push,     theme.dataStrain, "ámbar"),
            (.pull,     theme.dataHrv,    "cian"),
            (.legs,     theme.dataSleep,  "índigo"),
            (.fullBody, theme.dataSleep,  "índigo"),
        ]
        for (familia, token, nombre) in esperado {
            XCTAssertTrue(mismoColor(familia.tint(theme), token),
                          "\(familia) dejó de ser \(nombre)")
        }
        // Y el que se había ido por su lado: tirón NO es `dataSteps` (#4C8998). Lo fue en el
        // paquete mientras la app pintaba `dataHrv`, y ese desacuerdo es el defecto que FER-88 cerró.
        XCTAssertFalse(mismoColor(EntrenarFamily.pull.tint(theme), theme.dataSteps),
                       "tirón volvió a dataSteps: la tabla se re-bifurcó")
    }

    /// El puente por músculos no tiene tabla propia: clasifica y delega. Lo que se comprueba aquí es
    /// la CLASIFICACIÓN, que sí es lógica suya y sí puede romperse.
    func testElPuenteClasificaCadaMusculoEnSuFamilia() {
        let casos: [(String, EntrenarFamily)] = [
            ("lats", .pull), ("back", .pull), ("biceps", .pull), ("traps", .pull), ("forearms", .pull),
            ("quadriceps", .legs), ("hamstrings", .legs), ("glutes", .legs), ("calves", .legs),
            ("abductors", .legs), ("adductors", .legs),
            ("chest", .push), ("shoulders", .push), ("triceps", .push),
        ]
        for (musculo, esperada) in casos {
            XCTAssertEqual(theme.movementFamily(primaryMuscles: [musculo]), esperada, musculo)
        }
    }

    /// Sin músculos clasificables cae a empuje, igual que antes de la unificación: es el
    /// comportamiento que ya estaba en pantalla y no se cambia de contrabando.
    func testSinMusculosClasificablesCaeAEmpuje() {
        XCTAssertEqual(theme.movementFamily(primaryMuscles: []), .push)
        XCTAssertEqual(theme.movementFamily(primaryMuscles: ["cardio", "unknown"]), .push)
    }

    /// Las cuatro familias son distinguibles entre sí, salvo el par que el diseño decidió compartir
    /// (pierna y cuerpo completo van en el mismo índigo). Sin esto, unificar la tabla podría
    /// aplanar dos identidades en una sin que nadie lo notara.
    func testLasFamiliasSonDistinguiblesSalvoElParQueComparteIndigo() {
        XCTAssertTrue(mismoColor(EntrenarFamily.legs.tint(theme), EntrenarFamily.fullBody.tint(theme)),
                      "pierna y completo comparten índigo por diseño")
        let pares: [(EntrenarFamily, EntrenarFamily)] = [(.push, .pull), (.push, .legs), (.pull, .legs)]
        for (a, b) in pares {
            XCTAssertFalse(mismoColor(a.tint(theme), b.tint(theme)), "\(a) y \(b) tienen que distinguirse")
        }
    }

    /// El par obligatorio: el hue es para bolitas y numerales grandes; el tono de LECTURA es el que
    /// puede tocar texto. Las cuatro familias tienen que cumplir AA en su tono de lectura.
    func testElTonoDeLecturaDeCadaFamiliaCumpleAA() {
        for f in EntrenarFamily.allCases {
            XCTAssertGreaterThanOrEqual(OKLab.contrastRatio(f.reading(theme), theme.paper), 4.5, "\(f)")
        }
    }
}
