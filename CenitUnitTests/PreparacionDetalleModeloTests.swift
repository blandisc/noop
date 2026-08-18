import XCTest
import SwiftUI
import StrandAnalytics
import StrandDesign
@testable import Cenit

/// El modelo de «Preparación · detalle»: la densificación de la rejilla y los estados.
@MainActor
final class PreparacionDetalleModeloTests: XCTestCase {

    private let cal = Calendar.current

    private func noche(_ day: String, _ v: Preparedness.Verdict,
                       auto: Bool = false, sleep: Bool = false,
                       sent: Bool = false) -> Preparedness.VerdictNight {
        .init(day: day, verdict: v, autonomicOut: auto, sleepOut: sleep, sentinelOut: sent)
    }

    private func read(_ historia: [Preparedness.VerdictNight],
                      verdict: Preparedness.Verdict = .full,
                      autonomicPossible: Bool = true,
                      autonomicNights: Int = 30,
                      anclada: Bool = true) -> Preparedness.Read {
        // `isNightAnchored` NO sale de `bodyHistory`: se deriva del driver de SUEÑO
        // (`drivers.first{ .sleep }?.state.hasData`). Sin sesión de sueño grabada ese eje es
        // `.noData`, que es lo que la app lee para degradar a «lectura de día».
        .init(verdict: verdict,
              drivers: [.init(axis: .autonomic, state: .inRange, orientedZ: nil),
                        .init(axis: .sleep, state: anclada ? .inRange : .noData, orientedZ: nil)],
              signalsPresent: 3, signalsTotal: 3,
              maturity: .trusted, autonomicNights: autonomicNights, trend: nil,
              sentinel: .init(state: .quiet, streakNights: 0, watchingSignal: nil,
                              tempOut: false, respOut: false),
              sentinelHistory: [],
              bodyHistory: [.init(day: Repository.localDayKey(Date()), rhrResolved: 55,
                                  autonomicOrientedZ: 0.1, autonomicOut: false, sleepOut: false,
                                  rhrBaseCenter: 55, hrvBaseCenter: 45, rhrBand: 53...57)],
              verdictHistory: historia,
              autonomicPossible: autonomicPossible)
    }

    // MARK: - El contrato de la clave de día

    /// 🔴 EL DEFECTO SILENCIOSO MÁS CARO DE ESTA PANTALLA. `VerdictNight.day` sale de la fila
    /// guardada, cuya clave la escribe `Repository.localDayKey`. Si la rejilla generara sus
    /// claves con OTRO formato, otra zona u otro calendario, las 30 búsquedas fallarían y el
    /// mosaico saldría vacío sin lanzar un solo error: la pantalla diría «0 con lectura» a un
    /// usuario con 30 noches. Esta prueba amarra las dos funciones.
    func testLasClavesDeLaRejillaSonLasMismasQueEscribeElRepositorio() {
        let hoy = Date()
        let claves = PreparacionDetalleModelo.dayKeys(endingAt: hoy, calendar: cal, count: 30)
        XCTAssertEqual(claves.count, 30)
        XCTAssertEqual(claves.last, Repository.localDayKey(hoy),
                       "la última celda es HOY, con la clave que el repositorio escribe")
        for atras in 0..<30 {
            let d = cal.date(byAdding: .day, value: -atras, to: cal.startOfDay(for: hoy))!
            XCTAssertEqual(claves[29 - atras], Repository.localDayKey(d),
                           "la celda de hace \(atras) días no coincide con la clave guardada")
        }
    }

    /// Las claves van del más viejo al más nuevo, sin repetir ni saltar.
    func testLasClavesSonConsecutivasYOrdenadas() {
        let claves = PreparacionDetalleModelo.dayKeys(
            endingAt: Date(), calendar: cal, count: PreparacionDetalleModelo.ventana)
        XCTAssertEqual(Set(claves).count, claves.count, "no se repite ningún día")
        XCTAssertEqual(claves, claves.sorted(), "van del más viejo al más nuevo")
    }

    // MARK: - La rejilla densa

    /// La serie del motor es DISPERSA. Con un hueco real a media ventana, la rejilla tiene que
    /// conservar 30 celdas y poner cada día en SU lugar — no comprimir el hueco.
    func testUnHuecoDeCalendarioNoCorreLaRejilla() {
        let claves = PreparacionDetalleModelo.dayKeys(endingAt: Date(), calendar: cal, count: 30)
        // 30 noches menos un hueco de 10 días a media ventana.
        let dispersa = claves.enumerated()
            .filter { !(10..<20).contains($0.offset) }
            .map { noche($0.element, .full) }
        let m = PreparacionDetalleModelo.build(prep: read(dispersa), healthConnected: true,
                                               asOf: Date(), calendario: cal)
        XCTAssertEqual(m.rejilla.count, 30, "la ventana son 30 celdas, pase lo que pase")
        for i in 10..<20 { XCTAssertNil(m.rejilla[i], "el hueco se conserva en su lugar") }
        XCTAssertNotNil(m.rejilla[9])
        XCTAssertNotNil(m.rejilla[20], "el día después del hueco NO se corre hacia atrás")
        XCTAssertEqual(m.conteos["full"], 20)
        XCTAssertEqual(m.conteos["none"], 10, "los 10 días sin fila caen en el cuarto peldaño")
    }

    /// Un día con veredicto `lowSignal` y un día SIN fila caen en el MISMO peldaño: el usuario
    /// no puede distinguirlos mirando su calendario.
    func testSinFilaYSinLecturaCompartenPeldano() {
        let claves = PreparacionDetalleModelo.dayKeys(endingAt: Date(), calendar: cal, count: 30)
        let dispersa = claves.dropLast(5).enumerated().map {
            noche($0.element, $0.offset < 5 ? .lowSignal : .caution)
        }
        let m = PreparacionDetalleModelo.build(prep: read(Array(dispersa)), healthConnected: true,
                                               asOf: Date(), calendario: cal)
        XCTAssertEqual(m.conteos["none"], 10, "5 sin lectura + 5 sin fila = un solo peldaño")
        XCTAssertEqual(m.conteos["caution"], 20)
        XCTAssertEqual(m.rejilla.count, 30)
    }

    /// El denominador son 30 días de calendario SIEMPRE, aunque el motor traiga menos noches.
    func testElDenominadorEsLaVentanaNoLasNochesQueLlegaron() {
        let claves = PreparacionDetalleModelo.dayKeys(endingAt: Date(), calendar: cal, count: 30)
        let m = PreparacionDetalleModelo.build(
            prep: read(claves.suffix(7).map { noche($0, .full) }),
            healthConnected: true, asOf: Date(), calendario: cal)
        XCTAssertEqual(LiquidMosaicoVeredictos.conteo(m.rejilla).total, 30)
        XCTAssertEqual(LiquidMosaicoVeredictos.conteo(m.rejilla).conDato, 7)
    }

    // MARK: - Los estados de pantalla

    func testSinPermisoGanaSobreTodoLoDemas() {
        let claves = PreparacionDetalleModelo.dayKeys(endingAt: Date(), calendar: cal, count: 30)
        let m = PreparacionDetalleModelo.build(prep: read(claves.map { noche($0, .full) }),
                                               healthConnected: false, asOf: Date(), calendario: cal)
        XCTAssertEqual(m.estado, .sinPermiso)
    }

    func testSinPreparacionNoSeDibujaLaVentana() {
        let m = PreparacionDetalleModelo.build(prep: nil, healthConnected: true,
                                               asOf: Date(), calendario: cal)
        XCTAssertEqual(m.estado, .sinHistoria)
        XCTAssertNil(m.palabraHoy)
    }

    /// 🔴 Con permiso pero SIN una sola noche, no se dibuja un mosaico de 30 huecos: eso no es
    /// información, es un reproche. Va la bienvenida. Distinto de la ventana sin veredicto de
    /// abajo, donde SÍ hay noches y el mosaico sí tiene algo que contar.
    func testConPermisoYSinUnaSolaNocheVaLaBienvenidaNoElMosaico() {
        let m = PreparacionDetalleModelo.build(prep: read([]), healthConnected: true,
                                               asOf: Date(), calendario: cal)
        XCTAssertEqual(m.estado, .sinHistoria, "sin historia no se dibuja mosaico")
    }

    /// Una ventana ENTERA sin veredicto SÍ dibuja el mosaico —todo en el peldaño vacío— y lo
    /// dice. Nunca «0 de 0»: el denominador sigue siendo 30.
    func testVentanaEnteraSinVeredictoSeDibujaYLoDice() {
        let claves = PreparacionDetalleModelo.dayKeys(endingAt: Date(), calendar: cal, count: 30)
        let m = PreparacionDetalleModelo.build(
            prep: read(claves.map { noche($0, .lowSignal) }, verdict: .lowSignal),
            healthConnected: true, asOf: Date(), calendario: cal)
        XCTAssertEqual(m.estado, .conVentana, "el mosaico se dibuja, vacío pero presente")
        XCTAssertEqual(m.rejilla.count, 30)
        XCTAssertEqual(m.conteos["none"], 30)
        XCTAssertNotNil(m.avisoVentanaSinVeredicto)
        XCTAssertTrue(m.atribucion.isEmpty, "sin días leídos no hay nada que atribuir")
    }

    /// 🔴 A quien nunca duerme con reloj el motor advierte que «tu base se está formando» NO se
    /// cumple nunca. La pantalla no puede prometérselo.
    func testSinSenalPosibleNoSePrometeQueLaBaseSeEstaFormando() {
        let claves = PreparacionDetalleModelo.dayKeys(endingAt: Date(), calendar: cal, count: 30)
        let m = PreparacionDetalleModelo.build(
            prep: read(claves.map { noche($0, .lowSignal) }, verdict: .lowSignal,
                       autonomicPossible: false, autonomicNights: 0),
            healthConnected: true, asOf: Date(), calendario: cal)
        let aviso = try? XCTUnwrap(m.avisoVentanaSinVeredicto)
        XCTAssertEqual(aviso, String(localized: "prep.vacio.imposible",
                                     defaultValue: "None of these 30 mornings had enough signal. Preparation needs your resting signals while you sleep, and they haven't come in — if you don't wear your watch at night, I won't be able to read them."),
                       "sin señal posible NO se promete una base que nunca va a formarse")
    }

    /// Con señal posible pero base corta, la promesa SÍ es válida y se hace.
    func testConBaseCortaSiSePrometeQueSigueAprendiendo() {
        let claves = PreparacionDetalleModelo.dayKeys(endingAt: Date(), calendar: cal, count: 30)
        let m = PreparacionDetalleModelo.build(
            prep: read(claves.map { noche($0, .lowSignal) }, verdict: .lowSignal,
                       autonomicPossible: true, autonomicNights: 4),
            healthConnected: true, asOf: Date(), calendario: cal)
        XCTAssertNotEqual(m.avisoVentanaSinVeredicto,
                          String(localized: "prep.vacio.imposible",
                                 defaultValue: "None of these 30 mornings had enough signal. Preparation needs your resting signals while you sleep, and they haven't come in — if you don't wear your watch at night, I won't be able to read them."))
        XCTAssertTrue(m.avisoVentanaSinVeredicto?.contains("4") == true,
                      "le dice cuántas noches lleva")
    }

    /// El MISMO gate que Hoy: sin noche anclada no se pronuncia la palabra del veredicto.
    func testSinNocheAncladaNoSePronunciaElVeredicto() {
        let claves = PreparacionDetalleModelo.dayKeys(endingAt: Date(), calendar: cal, count: 30)
        let m = PreparacionDetalleModelo.build(
            prep: read(claves.map { noche($0, .full) }, anclada: false),
            healthConnected: true, asOf: Date(), calendario: cal)
        XCTAssertNil(m.palabraHoy, "sin noche grabada no hay veredicto que decir")
        XCTAssertNil(m.selloConfianza)
        XCTAssertTrue(m.ejesHoy.isEmpty, "ni «por qué hoy» de un día que no se leyó")
    }

    // MARK: - La atribución

    /// La atribución solo mira días CON veredicto: contar ejes sobre días que no se leyeron
    /// inventaría noches que nunca existieron.
    func testLaAtribucionIgnoraLosDiasSinVeredicto() {
        let claves = PreparacionDetalleModelo.dayKeys(endingAt: Date(), calendar: cal, count: 30)
        // 10 sin lectura (con los ejes marcados, que NO deben contar) + 20 leídos con 6 fuera.
        let historia = claves.enumerated().map { i, k -> Preparedness.VerdictNight in
            i < 10 ? noche(k, .lowSignal, auto: true, sleep: true, sent: true)
                   : noche(k, i < 16 ? .caution : .full, auto: i < 16)
        }
        let m = PreparacionDetalleModelo.build(prep: read(historia), healthConnected: true,
                                               asOf: Date(), calendario: cal)
        let auto = m.atribucion.first { $0.id == "autonomic" }
        XCTAssertEqual(auto?.dias, 6, "los 10 días sin lectura no entran aunque traigan el eje")
        XCTAssertEqual(m.atribucion.first { $0.id == "sleep" }?.dias, 0)
        XCTAssertEqual(m.atribucion.first { $0.id == "leidas" }?.dias, 20)
    }

    /// La palabra del mosaico es NEUTRA y en tercera persona: «Hoy ve leve» sobre un día de
    /// hace tres semanas se contradice a sí mismo, y «Recupera» es una orden a un día pasado.
    func testLosPeldanosNoUsanElVocabularioDeConsejoDeHoy() {
        for v in [Preparedness.Verdict.full, .caution, .easy, .lowSignal] {
            let neutra = PreparacionDetalleModelo.peldano(v)
            XCTAssertNotEqual(neutra, LiquidHoyBuilder.palabraVeredicto(v),
                              "el peldaño de \(v) no puede ser la palabra de consejo de Hoy")
        }
    }

    // MARK: - El gate de ciencia, convertido en prueba

    /// El texto ESPAÑOL que de verdad se le muestra al usuario. `String(localized:)` no sirve
    /// aquí: la suite corre en inglés, así que resolvería el valor `en` y una aserción sobre
    /// frases en español pasaría en vacío. (Lo comprobé: la primera versión de estas dos
    /// pruebas pasaba con el copy viejo, que es exactamente lo que venían a impedir.)
    private func es(_ clave: String) throws -> String {
        let ruta = try XCTUnwrap(Bundle.main.path(forResource: "es", ofType: "lproj"),
                                 "el bundle no trae español")
        let bundleES = try XCTUnwrap(Bundle(path: ruta))
        let v = bundleES.localizedString(forKey: clave, value: "‹AUSENTE›", table: nil)
        XCTAssertNotEqual(v, "‹AUSENTE›", "la clave \(clave) no llegó al catálogo en español")
        return v
    }

    /// El allow-list de `docs/ANALYTICS.md` es PR-blocking y prohíbe tres cosas que este copy
    /// dijo en su primera versión, todas cazadas por el gate de ciencia:
    ///   · que la VFC vota (`wHRV = 0`; la RMSSD nocturna nunca sola y NUNCA históricamente,
    ///     así que sobre 30 días este eje es solo la FC en reposo),
    ///   · que el sueño se juzga contra la base del usuario (es un piso poblacional fijo),
    ///   · el marco de «tres señales», prohibido por nombre desde la hoja del eje autonómico.
    func testElMetodoNoReintroduceLasAfirmacionesQueElGateProhibe() throws {
        let metodo = try es("prep.metodo.como")
        XCTAssertFalse(metodo.localizedCaseInsensitiveContains("tres señales"),
                       "el marco de «tres señales» está prohibido en el allow-list")
        XCTAssertFalse(metodo.localizedCaseInsensitiveContains("señales en reposo contra tu propia base"),
                       "el sueño NO se compara contra la base del usuario, sino contra un piso fijo")

        let auto = try es("prep.atr.auto")
        XCTAssertFalse(auto.localizedCaseInsensitiveContains("VFC"),
                       "la atribución de 30 días es SOLO FC en reposo: la VFC de Apple no vota y la RMSSD nocturna nunca cuenta históricamente")
    }

    /// La atribución del sueño no puede decir solo «dormiste menos»: el eje vota con
    /// `shortVsNeed || poorEfficiency`, así que una noche fragmentada de duración normal
    /// vota igual y quedaría sin explicación.
    func testLaAtribucionDeSuenoNombraLasDosFormasDeVotar() throws {
        let pie = try es("prep.atr.sueno")
        XCTAssertTrue(pie.localizedCaseInsensitiveContains("continua"),
                      "falta la noche fragmentada, que vota igual que la corta")
    }

    /// El héroe más visto de la app prometía un «rango» de sueño personal que el motor no
    /// tiene: el eje se juzga contra un piso poblacional fijo (Hirshkowitz 2015).
    func testElHeroeNoPrometeUnRangoDeSuenoPersonal() throws {
        let sub = try es("hero.sub.full.nombrado")
        XCTAssertFalse(sub.localizedCaseInsensitiveContains("sueño y tu FC en reposo amanecieron en tu rango"),
                       "el sueño no tiene «tu rango»: se compara contra el piso recomendado")
    }
}
