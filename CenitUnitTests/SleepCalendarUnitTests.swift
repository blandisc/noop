#if os(iOS)
import XCTest
@testable import Cenit

/// El calendario de 90 noches del detalle de Sueño consume HORAS, no minutos.
///
/// Estas pruebas nacen de un defecto que estuvo en pantalla y nadie vio: el mapeo dividía
/// entre 60 una serie que ya venía en horas, así que las 90 celdas caían al peldaño más
/// pálido y una noche de 7:30 se leía «0:07 · Sueño corto». La retícula se veía uniforme y
/// eso se explicó como «faltan datos» en vez de comprobarse. Una línea lo cazaba.
final class SleepCalendarUnitTests: XCTestCase {

    // MARK: - La unidad

    func test_horasReloj_formateaHorasDecimales_noMinutos() {
        XCTAssertEqual(SleepDetailScreen.horasReloj(7.5), "7:30")
        XCTAssertEqual(SleepDetailScreen.horasReloj(7.0), "7:00")
        XCTAssertEqual(SleepDetailScreen.horasReloj(6.6), "6:36")
        XCTAssertEqual(SleepDetailScreen.horasReloj(8.25), "8:15")
    }

    /// El modo de falla exacto del defecto: si alguien vuelve a dividir entre 60, esto truena.
    func test_horasReloj_noConfundeHorasConMinutos() {
        XCTAssertNotEqual(SleepDetailScreen.horasReloj(7.5), "0:07",
                          "7.5 horas se está leyendo como 7.5 minutos")
    }

    // MARK: - Los peldaños

    func test_intensidad_usaLosCortesDelHistorial() {
        // Los mismos de la escalera: Suficiente ≥ 7 · Algo corta 6.3–7 · Corta < 6.3.
        XCTAssertEqual(SleepDetailScreen.intensidadSueno(8.0), 1)
        XCTAssertEqual(SleepDetailScreen.intensidadSueno(7.0), 1)
        XCTAssertEqual(SleepDetailScreen.intensidadSueno(6.6), 0.5)
        XCTAssertEqual(SleepDetailScreen.intensidadSueno(6.3), 0.5)
        XCTAssertEqual(SleepDetailScreen.intensidadSueno(5.9), 0)
    }

    /// Una noche buena NO puede caer en el peldaño más pálido. Con el defecto, TODAS caían.
    func test_unaNocheBuenaNoCaeEnElPeldañoMasPalido() {
        for horas in [7.0, 7.5, 8.0, 8.5, 9.0] {
            XCTAssertEqual(SleepDetailScreen.intensidadSueno(horas), 1,
                           "\(horas) h debería ser el peldaño lleno")
        }
    }

    // MARK: - El vocabulario

    /// El calendario y la escalera del historial nombran igual la misma noche: decían «ok»
    /// aquí y «Algo corta» un scroll más arriba.
    func test_palabras_sonLasMismasDeLaEscalera() {
        XCTAssertEqual(SleepDetailScreen.sleepWord(7.5), String(localized: "Enough sleep"))
        XCTAssertEqual(SleepDetailScreen.sleepWord(6.6), String(localized: "A bit short"))
        XCTAssertEqual(SleepDetailScreen.sleepWord(5.5), String(localized: "Short sleep"))
    }

    /// La palabra y el color tienen que contar lo mismo: el peldaño lleno es la palabra de
    /// suficiencia, no una casualidad.
    func test_palabraYPeldaño_concuerdan() {
        for horas in stride(from: 4.0, through: 10.0, by: 0.1) {
            let lleno = SleepDetailScreen.intensidadSueno(horas) == 1
            let suficiente = SleepDetailScreen.sleepWord(horas) == String(localized: "Enough sleep")
            XCTAssertEqual(lleno, suficiente, "a \(horas) h el color y la palabra discrepan")
        }
    }
}
#endif
