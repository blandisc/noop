import XCTest
@testable import CenitDesign

/// Los dos contratos que `LiquidBarrasDeuda` mejora sobre el papel (`DebtBars`), afirmados en
/// frío sobre `alturaFraccion` — el punto exacto donde el render se bifurca, sin snapshots.
/// Run: `swift test --filter LiquidBarrasDeudaTests`
final class LiquidBarrasDeudaTests: XCTestCase {

    // MARK: (a) «sin dato» ≠ «sin deuda»

    /// El papel recibe `vsNeedMin: Double` y no puede distinguirlos: los dos llegan como 0 y
    /// los dos se dibujan igual, así que una noche sin medir se lee como una noche perfecta.
    /// Aquí `nil` devuelve `nil` (rama del riel vacío) y `0` devuelve `0` (rama de la barra a
    /// cero): son RAMAS DISTINTAS del render, no dos caminos al mismo pixel.
    func test_sinDato_y_sinDeuda_son_ramas_distintas() throws {
        XCTAssertNil(LiquidBarrasDeuda.alturaFraccion(minutos: nil, maximo: 180),
                     "«no se midió» no tiene altura: se pinta el riel vacío")

        let sinDeuda = try XCTUnwrap(
            LiquidBarrasDeuda.alturaFraccion(minutos: 0, maximo: 180),
            "«se midió y no debiste» SÍ tiene barra, asentada en la regla")
        XCTAssertEqual(sinDeuda, 0, accuracy: 1e-9)
    }

    /// El cero cuenta como SUPERÁVIT (paridad literal del papel: `vsNeedMin < 0 ? deficit :
    /// surplus`). Cumplir tu necesidad no es deberla, así que la barra a cero no se tiñe del
    /// tono de la deuda.
    func test_el_cero_cuenta_como_superavit() {
        XCTAssertFalse(LiquidBarrasDeuda.esDeficit(0))
        XCTAssertFalse(LiquidBarrasDeuda.esDeficit(18))
        XCTAssertTrue(LiquidBarrasDeuda.esDeficit(-1))
    }

    // MARK: (b) la escala es la del caller, no la local

    /// Dos semanas con el MISMO `maximo` y máximos locales distintos dibujan barras distintas.
    /// Si el componente normalizara contra su propio máximo, la peor noche de cada semana
    /// mediría 1.0 y una semana mala se vería idéntica a una buena.
    func test_escala_usa_el_maximo_del_caller_no_el_local() throws {
        let semanaMala = try XCTUnwrap(
            LiquidBarrasDeuda.alturaFraccion(minutos: -180, maximo: 180))
        let semanaBuena = try XCTUnwrap(
            LiquidBarrasDeuda.alturaFraccion(minutos: -60, maximo: 180))

        XCTAssertEqual(semanaMala, -1.0, accuracy: 1e-9)
        XCTAssertEqual(semanaBuena, -1.0 / 3.0, accuracy: 1e-9,
                       "−60 min contra un tope de 180 es un tercio, no «el peor de mi semana»")
        XCTAssertNotEqual(semanaMala, semanaBuena)
    }

    /// El mismo dato con topes distintos cambia de altura: la escala la manda `maximo`.
    func test_mismo_dato_distinto_maximo_distinta_altura() throws {
        let conTope180 = try XCTUnwrap(LiquidBarrasDeuda.alturaFraccion(minutos: -90, maximo: 180))
        let conTope360 = try XCTUnwrap(LiquidBarrasDeuda.alturaFraccion(minutos: -90, maximo: 360))

        XCTAssertEqual(conTope180, -0.5, accuracy: 1e-9)
        XCTAssertEqual(conTope360, -0.25, accuracy: 1e-9)
    }

    // MARK: Bordes de la escala

    /// Una noche por encima del tope se recorta al tope (nunca se sale del marco), y el signo
    /// se conserva en los dos sentidos.
    func test_recorta_al_tope_conservando_el_signo() throws {
        let deudaEnorme = try XCTUnwrap(
            LiquidBarrasDeuda.alturaFraccion(minutos: -600, maximo: 180))
        let superavitEnorme = try XCTUnwrap(
            LiquidBarrasDeuda.alturaFraccion(minutos: 600, maximo: 180))

        XCTAssertEqual(deudaEnorme, -1.0, accuracy: 1e-9)
        XCTAssertEqual(superavitEnorme, 1.0, accuracy: 1e-9)
    }

    /// Sin escala (un `maximo` de 0 o negativo) la noche se asienta en la BASE, no en el tope:
    /// una división degenerada no puede convertirse en «la peor noche de tu vida».
    func test_sin_escala_la_noche_se_asienta_en_la_base() throws {
        let topeCero = try XCTUnwrap(LiquidBarrasDeuda.alturaFraccion(minutos: -120, maximo: 0))
        let topeNegativo = try XCTUnwrap(LiquidBarrasDeuda.alturaFraccion(minutos: -120, maximo: -5))

        XCTAssertEqual(topeCero, 0, accuracy: 1e-9)
        XCTAssertEqual(topeNegativo, 0, accuracy: 1e-9)
        // …pero «sin dato» sigue siendo «sin dato» aunque falte la escala.
        XCTAssertNil(LiquidBarrasDeuda.alturaFraccion(minutos: nil, maximo: 0))
    }
}
