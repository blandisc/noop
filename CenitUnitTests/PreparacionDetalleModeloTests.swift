import XCTest
import SwiftUI
import StrandAnalytics
import CenitDesign
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

    /// Un `Read` con los ejes de HOY fijados: `drivers` es lo que `acta()` lee para las filas,
    /// y `sentinel` lo que lee para el par. Calcado de `ActaVotoDelParTests.read`.
    private func readConEjes(_ historia: [Preparedness.VerdictNight],
                             verdict: Preparedness.Verdict,
                             autoOut: Bool, sleepOut: Bool, par: Bool) -> Preparedness.Read {
        .init(verdict: verdict,
              drivers: [.init(axis: .autonomic, state: autoOut ? .low : .inRange, orientedZ: nil),
                        .init(axis: .sleep, state: sleepOut ? .low : .inRange, orientedZ: nil)],
              signalsPresent: 3, signalsTotal: 3,
              maturity: .trusted, autonomicNights: 30, trend: nil,
              sentinel: par ? .init(state: .corroborated, streakNights: 2, watchingSignal: nil,
                                    tempOut: true, respOut: true)
                            : .init(state: .quiet, streakNights: 0, watchingSignal: nil,
                                    tempOut: false, respOut: false),
              sentinelHistory: [],
              bodyHistory: [.init(day: Repository.localDayKey(Date()), rhrResolved: 55,
                                  autonomicOrientedZ: 0.1, autonomicOut: autoOut, sleepOut: sleepOut,
                                  rhrBaseCenter: 55, hrvBaseCenter: 45, rhrBand: 53...57)],
              verdictHistory: historia,
              autonomicPossible: true)
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
        XCTAssertTrue(m.conteosSenal.isEmpty, "sin días leídos no hay nada que contar")
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
                                     defaultValue: "None of these 30 mornings had enough signal. Preparation needs your resting signals while you sleep, and they haven't come in: if you don't wear your watch at night, I won't be able to read them."),
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
                                 defaultValue: "None of these 30 mornings had enough signal. Preparation needs your resting signals while you sleep, and they haven't come in: if you don't wear your watch at night, I won't be able to read them."))
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
        XCTAssertNil(m.actaHoy, "ni boleta de hoy de un día que no se leyó")
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
        let auto = m.conteosSenal.first { $0.id == "autonomic" }
        XCTAssertEqual(auto?.dias, 6, "los 10 días sin lectura no entran aunque traigan el eje")
        XCTAssertEqual(m.conteosSenal.first { $0.id == "sleep" }?.dias, 0)
        XCTAssertEqual(m.conteosSenal.count, 3, "tres señales, ninguna fila de cobertura: la cobertura va en la nota")
        XCTAssertTrue(m.notaConteos.contains("20"), "la nota dice de cuántas mañanas leídas: «\(m.notaConteos)»")
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

        // El rótulo del conteo de FC en reposo es la clave compartida «Resting HR»; lo que
        // NO puede decir «VFC» ahora es la nota ni la a11y de los conteos.
        let nota = try es("prep.conteos.nota.fmt")
        XCTAssertFalse(nota.localizedCaseInsensitiveContains("VFC"),
                       "la atribución de 30 días es SOLO FC en reposo: la VFC de Apple no vota")

        // El marco «tus tres señales» está PROHIBIDO por nombre para esta pantalla en el
        // allow-list (`docs/ANALYTICS.md`): cuenta como tres iguales lo que son dos votos y un
        // par que solo vigila. Lo reintroduje YO como título de sección en la primera versión
        // de FER-129 y lo cazó el verificador. Esta guarda vigila el título de la sección.
        let titulo = try es("prep.votos.titulo")
        XCTAssertFalse(titulo.localizedCaseInsensitiveContains("tres señales"),
                       "el título de la sección no puede ser el marco prohibido: «\(titulo)»")
        XCTAssertFalse(titulo.localizedCaseInsensitiveContains("3 señales"))
    }

    /// El sueño vota fuera por DURACIÓN corta O por continuidad pobre (`shortVsNeed ||
    /// poorEfficiency`). Esa afirmación vivía en la cajita de atribución; al retirarla se fue
    /// con ella y la guarda que la vigilaba se borró en vez de migrarse (lo cazó el QA).
    /// Ahora vive en el método, y esta guarda la sigue ahí.
    func testElMetodoNombraLasDosFormasEnQueVotaElSueno() throws {
        let como = try es("prep.metodo.como")
        XCTAssertTrue(["corto","menos"].contains { como.localizedCaseInsensitiveContains($0) },
                      "falta la noche corta: «\(como.prefix(80))…»")
        XCTAssertTrue(["entrecortado","continua","fragmentad"].contains { como.localizedCaseInsensitiveContains($0) },
                      "falta la noche fragmentada, que vota igual que la corta")
    }

    /// El piso «hoy» es la MISMA boleta que Hoy: el modelo debe LLAMAR a `LiquidHoyBuilder.acta`,
    /// no tener su propia tabla. Comparar una sola llamada contra sí misma sería tautología
    /// (pasaría aunque el modelo armara su tabla a mano con los mismos valores de ese caso).
    /// Lo que muerde es que, para VARIOS `Read` distintos que mueven filas distintas, la boleta
    /// del modelo siga siendo idéntica a la de Hoy en todos: una tabla propia que olvide un caso
    /// (el par corroborado, el sueño fuera, sin veredicto) diverge en alguno.
    func testElPisoHoyEsLaMismaBoletaQueHoyEnTodosLosCasos() throws {
        let claves = PreparacionDetalleModelo.dayKeys(endingAt: Date(), calendar: cal, count: 30)
        let historia = claves.map { noche($0, .caution) }
        let casos: [(String, Preparedness.Read)] = [
            ("todo dentro",   read(historia, verdict: .full)),
            ("FC fuera",      readConEjes(historia, verdict: .caution, autoOut: true, sleepOut: false, par: false)),
            ("sueño fuera",   readConEjes(historia, verdict: .caution, autoOut: false, sleepOut: true, par: false)),
            ("par corroborado", readConEjes(historia, verdict: .caution, autoOut: false, sleepOut: false, par: true)),
            ("dos fuera",     readConEjes(historia, verdict: .easy, autoOut: true, sleepOut: true, par: false)),
        ]
        var firmas = Set<String>()
        for (nombre, prep) in casos {
            let m = PreparacionDetalleModelo.build(prep: prep, healthConnected: true,
                                                   asOf: Date(), calendario: cal)
            let mia = try XCTUnwrap(m.actaHoy, "\(nombre): con veredicto anclado hay boleta")
            let deHoy = LiquidHoyBuilder.acta(prep: prep, healthConnected: true)
            XCTAssertEqual(mia.filas.map(\.id), deHoy.filas.map(\.id), nombre)
            XCTAssertEqual(mia.filas.map(\.palabra), deHoy.filas.map(\.palabra), nombre)
            XCTAssertEqual(mia.filas.map(\.estado), deHoy.filas.map(\.estado), nombre)
            XCTAssertEqual(mia.filas.map(\.fuera), deHoy.filas.map(\.fuera), nombre)
            XCTAssertEqual(mia.vigilantes, deHoy.vigilantes, nombre)
            XCTAssertEqual(mia.vigilantesLabel, deHoy.vigilantesLabel, nombre)
            firmas.insert(mia.filas.map { "\($0.id):\($0.palabra):\($0.fuera)" }.joined(separator: "|"))
        }
        // Y los casos de verdad mueven la boleta: si los cinco dieran la misma firma, la prueba
        // estaría comparando cinco veces lo mismo y no vigilaría nada.
        XCTAssertGreaterThanOrEqual(firmas.count, 3, "los casos deben producir boletas distintas: \(firmas)")
    }

    /// Sin veredicto anclado NO hay boleta en Preparación: el campo ya dice «—» y Hoy pinta
    /// sus propios estados de «sin veredicto»; duplicarlos aquí sería la tabla paralela que la
    /// regla prohíbe.
    func testSinVeredictoNoHayBoleta() {
        let claves = PreparacionDetalleModelo.dayKeys(endingAt: Date(), calendar: cal, count: 30)
        let m = PreparacionDetalleModelo.build(
            prep: read(claves.map { noche($0, .lowSignal) }, verdict: .lowSignal),
            healthConnected: true, asOf: Date(), calendario: cal)
        XCTAssertNil(m.actaHoy)
    }

    /// El héroe más visto de la app prometía un «rango» de sueño personal que el motor no
    /// tiene: el eje se juzga contra un piso poblacional fijo (Hirshkowitz 2015).
    func testElHeroeNoPrometeUnRangoDeSuenoPersonal() throws {
        let sub = try es("hero.sub.full.nombrado")
        XCTAssertFalse(sub.localizedCaseInsensitiveContains("sueño y tu FC en reposo amanecieron en tu rango"),
                       "el sueño no tiene «tu rango»: se compara contra el piso recomendado")
    }

    // MARK: - Tocar un día pasado

    /// Tocar un cuadro rojo y que solo diga «dos o más fuera» deja sin respuesta la pregunta
    /// obvia: ¿cuál de las dos? El motor ya trae los ejes por noche; hay que nombrarlos.
    func testTocarUnDiaPasadoNombraLaSenalQueSeSalio() throws {
        let claves = PreparacionDetalleModelo.dayKeys(endingAt: Date(), calendar: cal, count: 30)
        let historia = claves.enumerated().map { i, k -> Preparedness.VerdictNight in
            i == 5 ? noche(k, .easy, auto: true, sleep: true) : noche(k, .full)
        }
        let m = PreparacionDetalleModelo.build(prep: read(historia), healthConnected: true,
                                               asOf: Date(), calendario: cal)
        let etiqueta = try XCTUnwrap(m.rejilla[5]).etiqueta
        XCTAssertTrue(etiqueta.contains(String(localized: "Resting HR")),
                      "nombra la FC en reposo: «\(etiqueta)»")
        XCTAssertTrue(etiqueta.contains(String(localized: "Sleep")),
                      "y también el sueño, que se salió esa misma noche")

        // Un día limpio no arrastra una cola vacía ni un separador suelto.
        let limpio = try XCTUnwrap(m.rejilla[6]).etiqueta
        XCTAssertFalse(limpio.hasSuffix(" · "), "sin ejes fuera no se cuelga un separador: «\(limpio)»")
    }

    /// El centinela se nombra como PAR, nunca como una señal suelta: una sola alta jamás vota.
    ///
    /// Vigila la AFIRMACIÓN, no la redacción. Atada a la palabra «temperatura» completa, esta
    /// prueba cayó cuando el rótulo se acortó a «Temp y respiración» para que la rejilla
    /// cerrara pareja — un copy que dice exactamente lo mismo. Es la SEGUNDA guarda de esta
    /// suite que se rompe por congelar una palabra en vez del hecho.
    func testElCentinelaSeNombraComoPar() throws {
        let claves = PreparacionDetalleModelo.dayKeys(endingAt: Date(), calendar: cal, count: 30)
        let historia = claves.enumerated().map { i, k -> Preparedness.VerdictNight in
            i == 3 ? noche(k, .caution, sent: true) : noche(k, .full)
        }
        let m = PreparacionDetalleModelo.build(prep: read(historia), healthConnected: true,
                                               asOf: Date(), calendario: cal)
        let etiqueta = try XCTUnwrap(m.rejilla[3]).etiqueta
        // Las DOS mitades del par, en cualquier redacción: «temperatura» o «temp», y
        // «respiración» o «breathing». Nombrar una sola sería decir que vota sola.
        let calor = ["temp"]
        let aire = ["respir", "breath", "resp."]
        XCTAssertTrue(calor.contains { etiqueta.localizedCaseInsensitiveContains($0) },
                      "falta la temperatura: «\(etiqueta)»")
        XCTAssertTrue(aire.contains { etiqueta.localizedCaseInsensitiveContains($0) },
                      "falta la respiración, y sin ella el par se lee como una señal sola: «\(etiqueta)»")
    }

    // MARK: - Lo que cazó la revisión de UX / UI / quisquilloso (FER-126)

    /// 🔴 La canaleta decía «L M M J V S D» fijo, pero la ventana son 30 días consecutivos
    /// terminando HOY, así que la primera columna rota un día cada día. La fila fija acertaba
    /// 1 de cada 7 días del año. La prueba barre los 7 arranques posibles: si alguien vuelve a
    /// clavar la fila, seis de siete fallan.
    func testLaCanaletaDiceElDiaRealDeCadaColumna() throws {
        let simbolos = cal.shortWeekdaySymbols
        for corrimiento in 0..<7 {
            let inicio = try XCTUnwrap(cal.date(byAdding: .day, value: corrimiento,
                                                to: Date(timeIntervalSince1970: 1_755_000_000)))
            let iniciales = PreparacionDetalleModelo.inicialesDesde(inicio, calendario: cal)
            XCTAssertEqual(iniciales.count, 7)
            // Las SIETE columnas dicen su día real. Esta prueba fijaba antes el ritmo disperso
            // de la hermana (impares en blanco); al pasar a siete iniciales cambié el código y
            // olvidé la guarda, y CI la cazó. Es la afirmación más fuerte, no la más débil:
            // ninguna columna puede quedar muda ni decir otro día.
            for col in 0..<7 {
                let dia = try XCTUnwrap(cal.date(byAdding: .day, value: col, to: inicio))
                let esperado = simbolos[cal.component(.weekday, from: dia) - 1]
                XCTAssertEqual(iniciales[col], esperado,
                               "columna \(col) con arranque \(corrimiento): dice «\(iniciales[col])» y ese día es \(esperado)")
            }
        }
    }

    /// La canaleta del modelo sale del PRIMER día de la ventana, no de hoy.
    func testLaCanaletaDelModeloArrancaEnElPrimerDiaDeLaVentana() throws {
        let hoy = Date(timeIntervalSince1970: 1_755_000_000)
        let claves = PreparacionDetalleModelo.dayKeys(endingAt: hoy, calendar: cal, count: 30)
        let m = PreparacionDetalleModelo.build(prep: read(claves.map { noche($0, .full) }),
                                               healthConnected: true, asOf: hoy, calendario: cal)
        let primerDia = try XCTUnwrap(cal.date(byAdding: .day, value: -29,
                                               to: cal.startOfDay(for: hoy)))
        XCTAssertEqual(m.inicialesDia,
                       PreparacionDetalleModelo.inicialesDesde(primerDia, calendario: cal))
    }

    /// 🔴 El veredicto de un día es POST-histéresis y sus ejes son los CRUDOS: con el empujón
    /// de tendencia, un día podía decir «Dos o más fuera» nombrando UNA sola señal.
    func testUnDiaEmpujadoPorLaTendenciaDiceQuienLoEmpujo() throws {
        let claves = PreparacionDetalleModelo.dayKeys(endingAt: Date(), calendar: cal, count: 30)
        // Veredicto `.easy` (dos o más) pero un SOLO eje crudo fuera: eso solo pasa con empujón.
        let historia = claves.enumerated().map { i, k -> Preparedness.VerdictNight in
            i == 4 ? noche(k, .easy, auto: true) : noche(k, .full)
        }
        let m = PreparacionDetalleModelo.build(prep: read(historia), healthConnected: true,
                                               asOf: Date(), calendario: cal)
        let etiqueta = try XCTUnwrap(m.rejilla[4]).etiqueta
        XCTAssertTrue(etiqueta.contains(String(localized: "prep.dia.tendencia",
                                               defaultValue: "downward trend")),
                      "un peldaño que promete más ejes de los que hay tiene que decir quién lo empujó: «\(etiqueta)»")

        // Y un día `.easy` con DOS ejes de verdad no arrastra la coletilla.
        let dos = claves.enumerated().map { i, k -> Preparedness.VerdictNight in
            i == 4 ? noche(k, .easy, auto: true, sleep: true) : noche(k, .full)
        }
        let m2 = PreparacionDetalleModelo.build(prep: read(dos), healthConnected: true,
                                                asOf: Date(), calendario: cal)
        XCTAssertFalse(try XCTUnwrap(m2.rejilla[4]).etiqueta
            .contains(String(localized: "prep.dia.tendencia", defaultValue: "downward trend")),
                       "con dos ejes de verdad no hay nada que explicar")
    }

    /// «1 días» era el resultado de una clave PLANA que yo acuñé teniendo el catálogo una que
    /// sí pluraliza. Se comprueba contra el ESPAÑOL real, no contra el inglés de la suite.
    func testElConteoDeDiasConcuerdaEnSingular() throws {
        XCTAssertEqual(PreparacionDetalleModelo.unidadDias(1),
                       String(format: String(localized: "%lld days"), 1))
        let uno = PreparacionDetalleModelo.unidadDias(1)
        XCTAssertFalse(uno.contains("1 días"), "«1 días» otra vez: \(uno)")
        XCTAssertFalse(uno.contains("1 days"), "«1 days» otra vez: \(uno)")
    }
}
