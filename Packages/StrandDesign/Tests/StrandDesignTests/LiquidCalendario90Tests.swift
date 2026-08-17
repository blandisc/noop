import XCTest
import SwiftUI
@testable import StrandDesign

/// Pruebas del calendario de 90 días Liquid (FER-98 · F0a).
///
/// Cubren los tres invariantes que el papel NO garantizaba y que esta pieza sí:
///   (a) un día SIN dato jamás recibe el tono de la métrica — se distingue del día de valor 0;
///   (b) la selección alterna al re-tocar el mismo día (y el vecino solo camina sobre días con dato);
///   (c) el conteo del valor de accesibilidad cuadra con los días que de verdad traen lectura.
///
/// Determinista: fechas fijas, sin `Date()`.
/// Run: swift test --filter LiquidCalendario90Tests
final class LiquidCalendario90Tests: XCTestCase {

    // MARK: - Fixtures

    /// Lunes 1 de enero de 2024, 12:00 UTC — ancla fija para que la retícula sea reproducible.
    private static let ancla: Date = {
        var c = DateComponents()
        c.year = 2024; c.month = 1; c.day = 1; c.hour = 12
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: c)!
    }()

    private func dia(_ offset: Int, _ intensidad: Double?) -> LiquidCalendario90.Dia {
        LiquidCalendario90.Dia(
            id: "d\(offset)",
            fecha: Self.ancla.addingTimeInterval(TimeInterval(offset) * 86_400),
            intensidad: intensidad,
            etiqueta: "día \(offset)"
        )
    }

    /// 14 días: los pares con dato, los impares sin él.
    private var quincena: [LiquidCalendario90.Dia] {
        (0..<14).map { dia($0, $0 % 2 == 0 ? Double($0) / 13 : nil) }
    }

    // MARK: - (a) Sin dato ≠ intensidad 0

    /// El corazón de la pieza. `alfa` solo se consulta para días CON dato, y su piso está muy
    /// por encima de cero: si el alfa mínimo cayera a ~0, un día de intensidad 0 se volvería
    /// indistinguible del track neutro y la retícula mentiría sobre dónde hubo lectura.
    func test_intensidadCero_sigueSiendoVisible() {
        let alfaCero = LiquidCalendario90.alfa(intensidad: 0)
        XCTAssertGreaterThan(alfaCero, 0.2,
                             "un día medido en 0 debe verse; si el piso baja, se confunde con «sin lectura»")
        XCTAssertLessThan(alfaCero, LiquidCalendario90.alfa(intensidad: 1),
                          "el alfa tiene que crecer con la intensidad")
    }

    func test_alfa_esMonotonaYSeClampea() {
        XCTAssertEqual(LiquidCalendario90.alfa(intensidad: -5),
                       LiquidCalendario90.alfa(intensidad: 0), accuracy: 0.0001)
        XCTAssertEqual(LiquidCalendario90.alfa(intensidad: 9),
                       LiquidCalendario90.alfa(intensidad: 1), accuracy: 0.0001)
        XCTAssertEqual(LiquidCalendario90.alfa(intensidad: 1), 1.0, accuracy: 0.0001)
        for t in stride(from: 0.0, through: 0.9, by: 0.1) {
            XCTAssertLessThan(LiquidCalendario90.alfa(intensidad: t),
                              LiquidCalendario90.alfa(intensidad: t + 0.1))
        }
    }

    /// Un día sin lectura no entra al conteo: es el mismo dato que decide si se le pinta tono.
    func test_diaSinDato_noCuentaComoLectura() {
        let c = LiquidCalendario90.conteo(quincena)
        XCTAssertEqual(c.total, 14)
        XCTAssertEqual(c.conDato, 7, "solo los 7 pares traen intensidad")
    }

    // MARK: - (b) La selección alterna

    func test_seleccion_alternaAlReTocarElMismoDia() {
        XCTAssertEqual(LiquidCalendario90.alterna(seleccion: nil, toca: "d4"), "d4")
        XCTAssertEqual(LiquidCalendario90.alterna(seleccion: "d4", toca: "d4"), nil,
                       "re-tocar el día ya seleccionado lo limpia")
        XCTAssertEqual(LiquidCalendario90.alterna(seleccion: "d4", toca: "d6"), "d6",
                       "tocar otro día mueve la selección, no la apaga")
    }

    /// El recorrido por teclado/VoiceOver solo debe pisar días con lectura: parar en un hueco
    /// dejaría al usuario en una celda que no tiene nada que anunciar.
    func test_vecino_soloCaminaSobreDiasConDato() {
        XCTAssertEqual(LiquidCalendario90.vecino(dias: quincena, desde: nil, paso: 1), "d0")
        XCTAssertEqual(LiquidCalendario90.vecino(dias: quincena, desde: nil, paso: -1), "d12")
        XCTAssertEqual(LiquidCalendario90.vecino(dias: quincena, desde: "d0", paso: 1), "d2",
                       "salta el impar d1, que no tiene lectura")
        XCTAssertEqual(LiquidCalendario90.vecino(dias: quincena, desde: "d12", paso: 1), "d12",
                       "en el extremo se queda, no da la vuelta")
    }

    func test_vecino_sinNingunDato_devuelveNil() {
        let secos = (0..<7).map { dia($0, nil) }
        XCTAssertNil(LiquidCalendario90.vecino(dias: secos, desde: nil, paso: 1))
    }

    // MARK: - (c) El valor de accesibilidad dice la verdad

    func test_a11yValor_reportaElConteoReal() {
        let v = LiquidCalendario90.a11yValor(dias: quincena, seleccion: nil) { conDato, total in
            "\(conDato) de \(total)"
        }
        XCTAssertTrue(v.contains("7 de 14"), "el resumen debe citar los días con lectura, no el total")
    }

    func test_a11yValor_conSeleccion_mencionaElDia() {
        let v = LiquidCalendario90.a11yValor(dias: quincena, seleccion: "d4") { c, t in "\(c) de \(t)" }
        XCTAssertTrue(v.contains("día 4"),
                      "con un día tocado, su etiqueta entra al valor anunciado")
    }

    func test_a11yValor_listaVacia_noRevienta() {
        let v = LiquidCalendario90.a11yValor(dias: [], seleccion: nil) { c, t in "\(c) de \(t)" }
        XCTAssertTrue(v.contains("0 de 0"))
    }

    // MARK: - Retícula

    /// La semana empieza en LUNES: el ancla es lunes, así que cae en la fila 0.
    func test_semanaEmpiezaEnLunes() {
        let cal = LiquidCalendario90.calendarioLunes
        XCTAssertEqual(cal.firstWeekday, 2)
        XCTAssertEqual(LiquidCalendario90.fila(de: Self.ancla, en: cal), 0,
                       "el 1 de enero de 2024 fue lunes")
        XCTAssertEqual(LiquidCalendario90.fila(de: Self.ancla.addingTimeInterval(6 * 86_400), en: cal), 6,
                       "seis días después es domingo, la última fila")
    }

    /// Los huecos fuera de la ventana se rellenan con `nil` para que la columna conserve sus
    /// 7 filas — si se compactaran, los días cambiarían de renglón y la retícula mentiría.
    func test_semanas_conservanSieteFilas() {
        let semanas = LiquidCalendario90.semanas(de: quincena)
        XCTAssertFalse(semanas.isEmpty)
        for s in semanas {
            XCTAssertEqual(s.celdas.count, 7, "toda columna tiene 7 filas, con huecos si hace falta")
        }
        let colocados = semanas.flatMap { $0.celdas }.compactMap { $0 }.count
        XCTAssertEqual(colocados, quincena.count, "no se pierde ni se duplica ningún día")
    }

    func test_semanas_listaVacia_devuelveVacio() {
        XCTAssertTrue(LiquidCalendario90.semanas(de: []).isEmpty)
    }

    /// La celda se clampea: ni invisible en pantallas angostas ni desproporcionada en anchas.
    func test_tamanoCelda_seClampeaYNoDependeDelPrimerFrame() {
        XCTAssertEqual(LiquidCalendario90.tamanoCelda(ancho: 0), 14,
                       "sin medida todavía, cae al fallback y no a cero")
        for ancho in [CGFloat(320), 390, 430] {
            let c = LiquidCalendario90.tamanoCelda(ancho: ancho)
            XCTAssertGreaterThanOrEqual(c, 8)
            XCTAssertLessThanOrEqual(c, 22)
        }
        XCTAssertLessThan(LiquidCalendario90.tamanoCelda(ancho: 320),
                          LiquidCalendario90.tamanoCelda(ancho: 430),
                          "más ancho, celda más grande — hasta el techo")
        XCTAssertEqual(LiquidCalendario90.tamanoCelda(ancho: 4000), 22, accuracy: 0.001,
                       "el techo evita celdas gigantes en iPad")
    }

    /// Las iniciales de día son 7 y siguen al locale; el papel las dejaba a medias (L·—·M·—·V·—·D).
    func test_inicialesDeDia_sonSiete() {
        XCTAssertEqual(LiquidCalendario90.inicialesPorLocale(LiquidCalendario90.calendarioLunes).count, 7)
    }
}
