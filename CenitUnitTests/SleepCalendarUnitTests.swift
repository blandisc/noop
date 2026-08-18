#if os(iOS)
import XCTest
import StrandDesign
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

// MARK: - Latencia

/// La latencia se deriva del hipnograma: el tramo despierto con el que abre la noche, antes
/// del primer sueño. Estos casos salen del arnés de la auditoría numérica, que probó en frío
/// que la primera versión reportaba 480 min sobre una noche donde nunca hubo sueño.
extension SleepCalendarUnitTests {

    private func iv(_ s: SleepStage, _ desdeMin: Double, _ hastaMin: Double) -> SleepInterval {
        SleepInterval(stage: s, start: desdeMin * 60, end: hastaMin * 60)
    }

    func test_latencia_abreDespiertoYLuegoDuerme() {
        XCTAssertEqual(SleepDetailScreen.latenciaMin([iv(.awake, 0, 12), iv(.light, 12, 300)])!,
                       12, accuracy: 0.001)
    }

    func test_latencia_uneTramosDespiertosContiguos() {
        let n = [iv(.awake, 0, 5), iv(.awake, 5, 18), iv(.light, 18, 300)]
        XCTAssertEqual(SleepDetailScreen.latenciaMin(n)!, 18, accuracy: 0.001)
    }

    /// El defecto que motiva estas pruebas: 8 h de vigilia NO son una latencia.
    func test_latencia_esNil_siLaNocheNuncaLlegaADormirse() {
        XCTAssertNil(SleepDetailScreen.latenciaMin([iv(.awake, 0, 480)]),
                     "480 min de vigilia se reportaban como latencia")
        XCTAssertNil(SleepDetailScreen.latenciaMin([iv(.awake, 0, 100), iv(.awake, 100, 400)]),
                     "dos tramos despiertos sin sueño tampoco son latencia")
    }

    /// Dos fuentes escribiendo a la vez producen tramos solapados; sin tope, un despierto
    /// 0–30 que solapa un sueño que arrancó en el 10 reportaba 30 — el triple.
    func test_latencia_noSobreReportaConTramosSolapados() {
        let n = [iv(.awake, 0, 30), iv(.light, 10, 300)]
        XCTAssertEqual(SleepDetailScreen.latenciaMin(n)!, 10, accuracy: 0.001)
    }

    func test_latencia_esNil_siLaNocheAbreDormida() {
        XCTAssertNil(SleepDetailScreen.latenciaMin([iv(.light, 0, 300)]))
    }

    func test_latencia_toleraDesordenYTramosDeCeroSegundos() {
        let n = [iv(.light, 12, 300), iv(.awake, 0, 0), iv(.awake, 0, 12)]
        XCTAssertEqual(SleepDetailScreen.latenciaMin(n)!, 12, accuracy: 0.001)
    }

    func test_latencia_vacio() {
        XCTAssertNil(SleepDetailScreen.latenciaMin([]))
    }

    // MARK: - El formateador no depende de que lo protejan

    func test_horasReloj_clampeaNegativosYNoTruenaConInfinito() {
        XCTAssertEqual(SleepDetailScreen.horasReloj(-0.5), "0:00", "imprimía «0:-30»")
        XCTAssertEqual(SleepDetailScreen.horasReloj(.infinity), "—", "hacía TRAP")
        XCTAssertEqual(SleepDetailScreen.horasReloj(.nan), "—")
    }

    // MARK: - La unión que las pruebas dicen proteger

    /// Los peldaños del calendario se derivan de `bandasSueno`, no de números re-escritos:
    /// mover la escalera del historial dejaba el calendario divergente con la suite en verde.
    func test_losPeldañosSalenDeLaEscaleraDelHistorial() {
        let b = SleepDetailScreen.bandasSueno
        XCTAssertEqual(SleepDetailScreen.intensidadSueno(b[0].lo!), 1)
        XCTAssertEqual(SleepDetailScreen.sleepWord(b[0].lo!), b[0].label)
        XCTAssertEqual(SleepDetailScreen.intensidadSueno(b[1].lo!), 0.5)
        XCTAssertEqual(SleepDetailScreen.sleepWord(b[1].lo!), b[1].label)
        XCTAssertEqual(SleepDetailScreen.intensidadSueno(b[1].lo! - 0.01), 0)
        XCTAssertEqual(SleepDetailScreen.sleepWord(b[1].lo! - 0.01), b[2].label)
    }
}
#endif
