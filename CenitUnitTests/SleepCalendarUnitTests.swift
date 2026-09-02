#if os(iOS)
import XCTest
import CenitDesign
import StrandAnalytics
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

    func test_intensidad_usaLosCortesDelMotor() {
        // La escalera del motor: < 6:00 corto · 6:00–7:00 adecuado · 7:00–8:30 óptimo · ≥ 8:30 extenso.
        XCTAssertEqual(SleepDetailScreen.intensidadSueno(7.5), 1.0, "óptimo es la celda más llena")
        XCTAssertEqual(SleepDetailScreen.intensidadSueno(7.0), 1.0)
        XCTAssertEqual(SleepDetailScreen.intensidadSueno(6.5), 0.55)
        XCTAssertEqual(SleepDetailScreen.intensidadSueno(5.9), 0, "corto es la más tenue")
    }

    /// Dormir de más NO es mejor que dormir bien: «extenso» no puede pintarse más lleno que
    /// «óptimo». Mapear por índice lo habría hecho, y por eso el mapa va por clave.
    func test_extensoNoSePintaMasLlenoQueOptimo() {
        XCTAssertLessThan(SleepDetailScreen.intensidadSueno(9.0),
                          SleepDetailScreen.intensidadSueno(7.5))
    }

    /// Una noche buena NO puede caer en el peldaño más pálido. Con el defecto de unidad
    /// (horas leídas como minutos), TODAS caían.
    func test_unaNocheBuenaNoCaeEnElPeldañoMasPalido() {
        for horas in [7.0, 7.5, 8.0, 8.5, 9.0] {
            XCTAssertGreaterThan(SleepDetailScreen.intensidadSueno(horas), 0.5,
                                 "\(horas) h no puede quedar en la parte tenue")
        }
    }

    // MARK: - El vocabulario

    /// El calendario y la escalera del historial nombran igual la misma noche: decían «ok»
    /// aquí y «Algo corta» un scroll más arriba.
    func test_palabras_sonLasMismasDeLaEscalera() {
        for b in SleepDetailScreen.bandasSueno {
            let dentro = (b.lo ?? 0) + 0.1
            XCTAssertEqual(SleepDetailScreen.sleepWord(dentro), b.label,
                           "la palabra del carril \(b.key) no es la de su escalera")
        }
    }

    /// La palabra y el color tienen que contar lo mismo: el peldaño lleno es la palabra de
    /// suficiencia, no una casualidad.
    /// El color y la palabra salen del MISMO carril en todo el rango: si discrepan, la celda
    /// dice una cosa y su lectura otra.
    func test_palabraYPeldaño_concuerdan() {
        for horas in stride(from: 4.0, through: 11.0, by: 0.1) {
            guard let i = SleepDetailScreen.indiceCarril(horas) else {
                XCTFail("\(horas) h no cayó en ningún carril"); continue
            }
            XCTAssertEqual(SleepDetailScreen.sleepWord(horas),
                           SleepDetailScreen.bandasSueno[i].label,
                           "a \(horas) h el color y la palabra discrepan")
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
        for banda in b {
            let dentro = (banda.lo ?? 0) + 0.1
            XCTAssertEqual(SleepDetailScreen.sleepWord(dentro), banda.label)
            XCTAssertEqual(SleepDetailScreen.indiceCarril(dentro).map { b[$0].key }, banda.key)
        }
    }
}

// MARK: - Una sola escalera de sueño

/// La app declara por escrito que tiene UNA escalera de sueño, la del motor
/// (`MetricInfoCatalog`: «ONE sleep ladder, the engine's»). Esta pantalla venía usando una
/// propia de tres peldaños con un corte de 6.3 h: una noche de 8.7 h era «Extenso» en la hoja
/// de resumen y «Suficiente» aquí. Estas pruebas cierran esa puerta.
extension SleepCalendarUnitTests {

    func test_laEscaleraSaleDelMotor_noDeNumerosEscritosAMano() {
        let motor = MetricLevels.levels(for: .sleep)
        let pantalla = SleepDetailScreen.bandasSueno
        XCTAssertEqual(pantalla.count, motor.count, "la pantalla inventó peldaños")
        for (i, nivel) in motor.enumerated() {
            // Comparación explícita: `accuracy:` no acepta opcionales, y los bordes abiertos
            // del primer y último peldaño SON nil — que también hay que comprobar.
            switch (pantalla[i].lo, nivel.lower) {
            case (nil, nil): break
            case let (.some(a), .some(b)): XCTAssertEqual(a, b / 60, accuracy: 0.0001, "corte bajo \(i)")
            default: XCTFail("corte bajo del peldaño \(i) difiere en nulidad")
            }
            switch (pantalla[i].hi, nivel.upper) {
            case (nil, nil): break
            case let (.some(a), .some(b)): XCTAssertEqual(a, b / 60, accuracy: 0.0001, "corte alto \(i)")
            default: XCTFail("corte alto del peldaño \(i) difiere en nulidad")
            }
        }
    }

    /// Las dos noches que la escalera vieja clasificaba distinto que el resumen.
    func test_lasNochesQueDiscrepaban_ahoraCoinciden() {
        // 8.7 h: la escalera vieja decía «Suficiente» (≥7); el motor dice «Extenso» (≥8:30).
        XCTAssertEqual(SleepDetailScreen.sleepWord(8.7),
                       String(localized: String.LocalizationValue(MetricLevels.name(for: "extended"))))
        // 6.5 h: la vieja decía «Algo corta» (6.3–7); el motor dice «Adecuado» (6:00–7:00).
        XCTAssertEqual(SleepDetailScreen.sleepWord(6.5),
                       String(localized: String.LocalizationValue(MetricLevels.name(for: "adequate"))))
        // 6.2 h: la vieja la mandaba a «Corta»; el motor la deja en «Adecuado».
        XCTAssertEqual(SleepDetailScreen.sleepWord(6.2),
                       String(localized: String.LocalizationValue(MetricLevels.name(for: "adequate"))))
    }

    func test_elCorte6punto3_yaNoExiste() {
        let cortes = SleepDetailScreen.bandasSueno.compactMap(\.lo)
        XCTAssertFalse(cortes.contains { abs($0 - 6.3) < 0.0001 },
                       "6.3 era un umbral sin fuente que no vivía en ningún otro archivo")
    }
}
#endif
