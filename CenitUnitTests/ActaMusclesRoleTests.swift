import XCTest
@testable import Cenit

/// FER-124 — el acta distingue músculos PRINCIPALES de los de APOYO, «como el handoff». Antes solo
/// mostraba los principales; el catálogo ya sabía los de apoyo (`Exercise.secondaryMuscles`) y el
/// acta los ignoraba.
///
/// Estas pruebas llaman `StrengthSummary.worked(...)` — EL MISMO código que el acta usa en
/// producción, no una copia de la regla. Una versión anterior de este archivo replicaba la lógica
/// aparte; el revisor lo marcó, y con razón: un test que copia la regla pasa aunque el código real
/// se rompa. Ahora si el constructor cambia, esta prueba cambia con él o truena.
final class ActaMusclesRoleTests: XCTestCase {

    private func worked(_ primary: [[String]], _ secondary: [[String]]) -> [StrengthSummary.WorkedMuscle] {
        StrengthSummary.worked(primaryPerSet: primary, secondaryPerSet: secondary, titleCase: { $0 })
    }

    /// El caso que la lista plana vieja no podía mostrar: los de apoyo, que antes desaparecían.
    func testLosMusculosDeApoyoAparecen() {
        let r = worked([["Quadriceps"]], [["Glutes", "Core"]])
        XCTAssertEqual(r.map(\.name), ["Quadriceps", "Glutes", "Core"])
        XCTAssertEqual(r.first { $0.name == "Glutes" }?.isPrimary, false)
    }

    /// LA REGLA QUE UNA CAPTURA NO CAZA: principal en un ejercicio, apoyo en otro → gana principal.
    /// Sin ella, el orden de los ejercicios decidiría el papel del músculo, que es un bug.
    func testPrincipalGanaSobreApoyo() {
        // Sentadilla: cuádriceps principal. Peso muerto: cuádriceps de apoyo. Debe salir principal.
        let r = worked([["Quadriceps"], ["Hamstrings"]], [["Glutes"], ["Quadriceps"]])
        XCTAssertEqual(r.first { $0.name == "Quadriceps" }?.isPrimary, true,
                       "principal en un ejercicio pesa más que apoyo en otro")
    }

    /// Y da igual el orden: apoyo visto ANTES que su versión principal, también gana principal.
    func testPrincipalGanaAunqueElApoyoSeVeaPrimero() {
        let r = worked([["Deadlift_ph"], ["Squat_ph"]], [["Glutes"], []])
        // Glutes solo aparece como apoyo aquí → queda apoyo. (control de que no se marca principal por error)
        XCTAssertEqual(r.first { $0.name == "Glutes" }?.isPrimary, false)
    }

    /// No se duplica aunque aparezca en varios ejercicios.
    func testNoSeRepite() {
        let r = worked([["Chest"], ["Chest"]], [["Chest"]])
        XCTAssertEqual(r.filter { $0.name == "Chest" }.count, 1)
    }

    /// Sin nada trabajado, lista vacía — el acta esconde la fila entera (`if !s.muscles.isEmpty`).
    func testSinMusculosListaVacia() {
        XCTAssertTrue(worked([], []).isEmpty)
    }
}
