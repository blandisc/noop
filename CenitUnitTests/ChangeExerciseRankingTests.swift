import XCTest
@testable import Cenit

/// FER-89 — `ChangeExerciseSheet` gana orden por uso reciente (antes: solo coincidencia de músculo
/// primario, sin ningún orden). `ChangeExerciseRanking` es la lógica pura detrás, extraída para
/// probarla sin `Repository` ni montar la vista.
final class ChangeExerciseRankingTests: XCTestCase {

    // MARK: - mostRecentUse

    /// El caso base: cada ejercicio se queda con la marca de tiempo de su fila. Las filas llegan
    /// DESC por `startTs` (como las entrega `Repository.recentWorkSets`), así que no hace falta
    /// ordenar aquí — solo quedarse con la primera aparición de cada id.
    func testMostRecentUseKeepsFirstOccurrenceSinceInputIsDescending() {
        let rows: [(exerciseId: String, startTs: Int)] = [
            ("bench", 300), ("squat", 250), ("bench", 100),   // «bench» aparece dos veces: 300 y 100
        ]
        let out = ChangeExerciseRanking.mostRecentUse(rows)
        // Código viejo que se quedara con la ÚLTIMA aparición en vez de la primera (p. ej. un
        // diccionario armado con `Dictionary(rows, uniquingKeysWith: { _, new in new })`) tronaría
        // aquí: «bench» quedaría en 100, no en 300.
        XCTAssertEqual(out["bench"], 300)
        XCTAssertEqual(out["squat"], 250)
    }

    /// Sin filas (nunca entrenado nada, o `recentWorkSets` vacío) → diccionario vacío, no un crash.
    func testMostRecentUseWithNoRowsIsEmpty() {
        XCTAssertTrue(ChangeExerciseRanking.mostRecentUse([]).isEmpty)
    }

    // MARK: - sortByRecentUse

    private struct Candidate { let id: String }

    /// Más reciente primero. Código viejo que comparara con `<` en vez de `>` invertiría el orden
    /// (el menos reciente aparecería arriba).
    func testSortByRecentUsePutsMostRecentFirst() {
        let items = [Candidate(id: "a"), Candidate(id: "b"), Candidate(id: "c")]
        let recency = ["a": 100, "b": 300, "c": 200]
        let sorted = ChangeExerciseRanking.sortByRecentUse(items, id: \.id, recency: recency)
        XCTAssertEqual(sorted.map(\.id), ["b", "c", "a"])
    }

    /// Los nunca-usados (sin entrada en `recency`) se quedan al FINAL, en su orden relativo
    /// original — no se descartan ni se mezclan al azar. Código viejo que tratara «sin uso» como
    /// 0 en vez de un centinela negativo confundiría un ejercicio sin historial con uno usado el
    /// día époch.
    func testNeverUsedExercisesKeepRelativeOrderAtTheEnd() {
        let items = [Candidate(id: "used"), Candidate(id: "never1"), Candidate(id: "never2")]
        let recency = ["used": 500]
        let sorted = ChangeExerciseRanking.sortByRecentUse(items, id: \.id, recency: recency)
        XCTAssertEqual(sorted.map(\.id), ["used", "never1", "never2"])
    }

    /// Sin ningún historial (biblioteca fresca), el orden original se conserva tal cual — el
    /// ordenamiento es estable, no reprocesa la lista al azar.
    func testAllNeverUsedKeepsOriginalOrder() {
        let items = [Candidate(id: "x"), Candidate(id: "y"), Candidate(id: "z")]
        let sorted = ChangeExerciseRanking.sortByRecentUse(items, id: \.id, recency: [:])
        XCTAssertEqual(sorted.map(\.id), ["x", "y", "z"])
    }
}
