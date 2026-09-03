import XCTest
@testable import StrandAnalytics

/// H1 (auditoría de estrés): fija la regla de selección de fuente de sueño por noche — prioridad a
/// Apple/Watch, y entre candidatas la de más minutos dormidos. Sin esta selección, la ruta live sumaba
/// las etapas de todas las fuentes (doble conteo → eficiencia falsa de 100 %).
final class SleepSourceSelectionTests: XCTestCase {

    /// Apple Watch (com.apple.health) + una app tercera con MÁS minutos: gana Apple igual (estadía el sueño).
    func test_prefiere_fuente_apple_aunque_tenga_menos_minutos() {
        let pick = SleepSourceSelection.pick(asleepMinutesBySource: [
            "com.apple.health.ABC": 300,
            "com.tantsissa.AutoSleep": 480,
        ])
        XCTAssertEqual(pick, "com.apple.health.ABC")
    }

    /// Entre dos fuentes Apple, gana la de más minutos (el registro más completo, típicamente el Watch).
    func test_entre_apple_gana_mas_minutos() {
        let pick = SleepSourceSelection.pick(asleepMinutesBySource: [
            "com.apple.health.WATCH": 470,
            "com.apple.Health": 60,
        ])
        XCTAssertEqual(pick, "com.apple.health.WATCH")
    }

    /// Sin ninguna fuente Apple, gana la de más minutos.
    func test_sin_apple_gana_mas_minutos() {
        let pick = SleepSourceSelection.pick(asleepMinutesBySource: [
            "com.tantsissa.AutoSleep": 420,
            "com.sleepcycle.app": 100,
        ])
        XCTAssertEqual(pick, "com.tantsissa.AutoSleep")
    }

    /// Mapa vacío → nil (no hay noche que emitir).
    func test_vacio_es_nil() {
        XCTAssertNil(SleepSourceSelection.pick(asleepMinutesBySource: [:]))
    }

    /// Empate de minutos → determinista (gana el bundleId menor), para no depender del orden del dict.
    func test_empate_determinista() {
        XCTAssertEqual(SleepSourceSelection.pick(asleepMinutesBySource: ["b.app": 300, "a.app": 300]),
                       "a.app")
    }
}
