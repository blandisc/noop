import XCTest
import StrandModels
@testable import StrandAnalytics

/// FER-119 · `Read.verdictHistory`: las mañanas de la ventana con SU veredicto y sus tres ejes.
///
/// El contrato que estas pruebas fijan salió de SEIS rondas de ataque adversarial sobre el
/// requerimiento. Tres de ellas tumbaron un criterio que parecía obvio y no lo era:
///
/// 1. «el último elemento es `Read.verdict`» — falso si se compara contra `stable`: un empujón de
///    tendencia modifica el veredicto DESPUÉS del pliegue.
/// 2. «en los tres caminos» — falso en el camino sin fila de hoy: no hay celda que amarrar, y
///    fabricarla violaría el contrato ya probado de «no se inventa un día que no llegó».
/// 3. La histéresis cuenta días consecutivos POR POSICIÓN, no por fecha. Es preexistente y aquí
///    solo se documenta: el mosaico es la primera superficie que lo hace visible.
final class PreparednessVerdictHistoryTests: XCTestCase {

    // MARK: Fixtures (misma forma que PreparednessBodyHistoryTests)

    private func dm(_ day: String, hrv: Double? = 55, rhr: Int? = 55, resp: Double? = 14,
                    sleep: Double? = 450, temp: Double? = 0.0) -> DailyMetric {
        DailyMetric(day: day, totalSleepMin: sleep, efficiency: nil, deepMin: nil, remMin: nil,
                    lightMin: nil, disturbances: nil, restingHr: rhr, avgHrv: hrv, recovery: nil,
                    strain: nil, exerciseCount: nil, spo2Pct: nil, skinTempDevC: temp,
                    respRateBpm: resp)
    }

    private func baseline(_ count: Int = 20) -> [DailyMetric] {
        (1...count).map { i in
            dm(String(format: "2026-06-%02d", i),
               hrv: 52 + Double(i % 5), rhr: 54 + i % 3, resp: 13 + Double(i % 3))
        }
    }

    private func read(_ days: [DailyMetric], asOf: String,
                      trend: AutonomicTrend.Read? = nil,
                      nocturnalRestingHr: [String: Double] = [:]) -> Preparedness.Read {
        Preparedness.evaluate(.init(days: days, strainByDay: [:], trend: trend, asOf: asOf,
                                    nocturnalRestingHr: nocturnalRestingHr,
                                    cyclePhase: nil, nocturnalRmssd: nil))
    }

    /// La tendencia cayendo, como la arma `PreparednessTests`.
    private var cayendo: AutonomicTrend.Read {
        AutonomicTrend.Read(direction: .below, confidence: .solid, nightsUsable: 20,
                            nightsToTrend: 0, recentDenseNights: 5, z7d: -1.3,
                            spark: [], asOfWasDense: true)
    }

    // MARK: - El pliegue desenrollado

    /// El elemento `i` de la serie es idéntico a plegar el prefijo `[0...i]` por separado. Es la
    /// propiedad que hace que emitir `stable` en cada paso sea legítimo y no una aproximación.
    func testLaSerieEquivaleAPlegarCadaPrefijo() {
        let raws: [Preparedness.Verdict] = [.full, .full, .caution, .caution, .full, .easy, .easy]
        let serie = Preparedness.hysteresedSeries(raws, hysteresisDays: 2)
        XCTAssertEqual(serie.count, raws.count)
        // Contra `hysteresed`, NO contra sí misma: comparar la serie con sus propios prefijos es
        // una propiedad que satisface CUALQUIER pliegue causal — un pliegue mutante con umbral
        // h+1 la cumple al 100 % dando el resultado equivocado. (Lo demostró la revisión.)
        for i in raws.indices {
            XCTAssertEqual(serie[i],
                           Preparedness.hysteresed(Array(raws[0...i]), hysteresisDays: 2),
                           "el paso \(i) no equivale a plegar su propio prefijo")
        }
    }

    /// Un día aislado distinto NO mueve el estable; dos consecutivos SÍ. Es la histéresis misma,
    /// vista a lo largo de la serie en vez de solo en su resultado final.
    func testUnDiaAisladoNoMueveElEstable_dosConsecutivosSi() {
        let aislado: [Preparedness.Verdict] = [.full, .full, .caution, .full, .full]
        XCTAssertEqual(Preparedness.hysteresedSeries(aislado, hysteresisDays: 2),
                       [.full, .full, .full, .full, .full],
                       "un solo día distinto no puede voltear el estado")

        let dos: [Preparedness.Verdict] = [.full, .full, .caution, .caution, .full]
        XCTAssertEqual(Preparedness.hysteresedSeries(dos, hysteresisDays: 2),
                       [.full, .full, .full, .caution, .caution],
                       "dos consecutivos sí mueven, y el cambio persiste hasta el siguiente run")
    }

    func testSerieVaciaYDeUnSoloElemento() {
        XCTAssertEqual(Preparedness.hysteresedSeries([], hysteresisDays: 2), [])
        XCTAssertEqual(Preparedness.hysteresedSeries([.easy], hysteresisDays: 2), [.easy])
        XCTAssertEqual(Preparedness.hysteresedSeries([.full, .easy], hysteresisDays: 5),
                       [.full, .full],
                       "una serie más corta que hysteresisDays no puede moverse")
    }

    // MARK: - El amarre con el veredicto que la app muestra

    /// El defecto que este amarre existe para evitar: el mosaico diciendo una cosa y el héroe otra
    /// el mismo día.
    func testElUltimoElementoEsElVeredictoQueLaAppMuestra() {
        let r = read(baseline(), asOf: "2026-06-20")
        XCTAssertFalse(r.verdictHistory.isEmpty, "con historia completa la serie existe")
        XCTAssertEqual(r.verdictHistory.last?.verdict, r.verdict,
                       "la última celda del mosaico DEBE ser lo que dice el héroe")
        XCTAssertEqual(r.verdictHistory.last?.day, "2026-06-20")
    }

    /// `Read.verdict` no siempre sale del pliegue: un empujón de tendencia lo modifica después.
    /// Comparar la serie contra `stable` habría fallado aquí — fue un criterio tumbado en la v2.
    func testElEmpujonDeTendenciaViajaAlUltimoElemento() {
        // DOS días malos, no uno: con hysteresisDays = 2 un solo día no mueve el estable, y el
        // empujón nunca dispara — la primera versión de esta prueba comparaba `.full == .full`
        // y pasaba trivialmente.
        var dias = baseline()
        dias.append(dm("2026-06-21", hrv: 30, rhr: 75, resp: 20, sleep: 450))
        dias.append(dm("2026-06-22", hrv: 30, rhr: 75, resp: 20, sleep: 450))

        let sinTendencia = read(dias, asOf: "2026-06-22")
        XCTAssertEqual(sinTendencia.verdict, .caution,
                       "el fixture tiene que producir un `caution` — si no, no hay qué empujar")

        let conTendencia = read(dias, asOf: "2026-06-22", trend: cayendo)
        XCTAssertEqual(conTendencia.verdict, .easy, "el empujón degrada caution → easy")
        XCTAssertEqual(conTendencia.verdictHistory.last?.verdict, .easy,
                       "y la serie tiene que moverse con él, no quedarse en `stable`")
        XCTAssertNotEqual(conTendencia.verdictHistory.last?.verdict,
                          sinTendencia.verdictHistory.last?.verdict,
                          "si las dos lecturas dieran lo mismo, la prueba no probaría nada")
    }

    /// El contrato que la ronda 3 rescató: sin fila de hoy NO se fabrica una celda de hoy.
    /// Gemelo exacto de `testRutaLowSignalSinFilaConservaLaHistoriaJuzgada` para `bodyHistory`.
    func testSinFilaDeHoyLaSerieNoLlegaAHoy() {
        let dias = baseline()
        let r = read(dias, asOf: "2026-07-15")   // asOf muy posterior a la última fila
        XCTAssertEqual(r.verdict, .lowSignal)
        XCTAssertFalse(r.verdictHistory.isEmpty, "la historia juzgada no se borra")
        XCTAssertEqual(r.verdictHistory.last?.day, dias.last?.day,
                       "termina en la última noche que SÍ existe, no en asOf")
        XCTAssertNotEqual(r.verdictHistory.last?.day, "2026-07-15",
                          "no se inventa un día que no llegó")
    }

    /// Dos campos hermanos del mismo `Read` no pueden discrepar sobre hasta dónde llega la
    /// historia.
    func testLaSerieYBodyHistoryTerminanElMismoDia() {
        for asOf in ["2026-06-20", "2026-07-15"] {
            let r = read(baseline(), asOf: asOf)
            XCTAssertEqual(r.verdictHistory.last?.day, r.bodyHistory.last?.day,
                           "asOf \(asOf): la serie y bodyHistory discrepan")
        }
    }

    // MARK: - Causalidad y ventana

    /// Agregar días posteriores no repinta los veredictos anteriores. Es la propiedad que hace
    /// honesto mostrar la historia.
    func testAgregarDiasPosterioresNoRepintaLaHistoria() {
        let corta = baseline(15)
        let larga = baseline(20)
        let a = read(corta, asOf: corta.last!.day)
        let b = read(larga, asOf: larga.last!.day)
        // Los días comunes tienen que decir lo mismo en las dos lecturas.
        let comunes = Set(corta.map(\.day))
        let enA = a.verdictHistory.filter { comunes.contains($0.day) }
        let enB = b.verdictHistory.filter { comunes.contains($0.day) }
        for x in enA {
            guard let y = enB.first(where: { $0.day == x.day }) else { continue }
            // El ÚLTIMO día de la ventana corta es el asOf de esa lectura: ahí sí puede diferir,
            // porque lleva el amarre al veredicto de hoy y los ajustes que solo valen para hoy.
            if x.day == corta.last?.day { continue }
            XCTAssertEqual(x.verdict, y.verdict, "el día \(x.day) se repintó al crecer la historia")
        }
    }

    func testLaVentanaSeCapeaYNoExcedeSuTope() {
        let largo = (1...60).map { i -> DailyMetric in
            let d = Date(timeIntervalSince1970: 1_750_000_000 + Double(i) * 86_400)
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
            f.timeZone = TimeZone(identifier: "UTC")
            return dm(f.string(from: d), hrv: 52 + Double(i % 5), rhr: 54 + i % 3)
        }
        let r = read(largo, asOf: largo.last!.day)
        XCTAssertLessThanOrEqual(r.verdictHistory.count, Preparedness.verdictHistoryWindow)
        XCTAssertEqual(r.verdictHistory.last?.day, largo.last?.day)
    }

    /// El cap va DESPUÉS del pliegue. Plegar sobre la ventana podada haría que el primer día
    /// visible se volviera «estable» de golpe, ignorando el momentum que traía desde fuera.
    func testCapearAntesDelPliegueDariaOtroResultado() {
        // 30 días de `easy` seguidos de 5 de `full`: con hysteresisDays=2, el estable al entrar a
        // la ventana de los últimos 5 todavía viene de la corrida larga.
        let raws: [Preparedness.Verdict] = Array(repeating: .easy, count: 30)
                                         + Array(repeating: .full, count: 5)
        let completo = Preparedness.hysteresedSeries(raws, hysteresisDays: 2)
        let podado = Preparedness.hysteresedSeries(Array(raws.suffix(5)), hysteresisDays: 2)
        XCTAssertNotEqual(Array(completo.suffix(5)), podado,
                          "si esto fuera igual, capear antes del pliegue sería inofensivo — no lo es")
        XCTAssertEqual(completo.suffix(5).first, .easy,
                       "el primer día visible conserva el momentum de fuera de la ventana")
        XCTAssertEqual(podado.first, .full,
                       "podado, ese mismo día arranca «estable» de golpe: el resultado equivocado")
    }

    // MARK: - Lo que se documenta sin corregir

    /// La histéresis cuenta «2 consecutivos» POR POSICIÓN, no por fecha — a diferencia de
    /// `sentinelStreak`, que sí rompe la racha ante un hueco de calendario. Es preexistente y
    /// este issue NO lo corrige; queda escrito porque el mosaico es la primera superficie que lo
    /// hace visible: dos celdas separadas por un hueco real cuentan como consecutivas.
    func testLaHisteresisEsCiegaAlCalendario_documentado() {
        // Con FECHAS de verdad: la primera versión de esta prueba no tenía ninguna y era un
        // duplicado del umbral. Doce días buenos, y luego dos malos separados por OCHO días.
        var dias = (1...12).map { i in
            dm(String(format: "2026-06-%02d", i), hrv: 55, rhr: 55, resp: 14)
        }
        dias.append(dm("2026-06-20", hrv: 30, rhr: 75, resp: 20, sleep: 450))
        dias.append(dm("2026-06-28", hrv: 30, rhr: 75, resp: 20, sleep: 450))

        let r = read(dias, asOf: "2026-06-28")
        XCTAssertEqual(r.verdict, .caution,
                       "ocho días de hueco se cuentan como consecutivos: `hysteresed` no mira fechas")
        // Queda ESCRITO, no corregido: `sentinelStreak` sí rompe la racha por fecha, y el
        // mosaico será la primera superficie que exponga la asimetría.
    }

    // MARK: - Los tres ejes

    /// El centinela vota como CONJUNCIÓN: temperatura y respiración juntas, nunca una sola.
    func testElCentinelaViajaCombinado() {
        var dias = baseline()
        // Última noche con temperatura alta pero respiración normal: el centinela NO vota.
        dias[dias.count - 1] = dm(dias.last!.day, hrv: 55, rhr: 55, resp: 14, temp: 1.2)
        let r = read(dias, asOf: dias.last!.day)
        XCTAssertEqual(r.verdictHistory.last?.sentinelOut, false,
                       "una sola señal fuera no es el voto del centinela")
    }

    // MARK: - Una noche sin lectura no hereda el veredicto de ayer

    /// El defecto que la revisión adversarial del paso A destapó: la histéresis pide 2 días para
    /// moverse, así que una noche suelta sin reloj se quedaba PEGADA al veredicto anterior. En una
    /// sonda de 30 días con reloj un día sí y otro no, **11 de 12 noches sin señal salían «En
    /// rango»** — exactamente lo que el requerimiento prohíbe («no se rellena, no se interpola»).
    func testUnaNocheSinLecturaNoHeredaElVeredictoDeAyer() {
        var dias = baseline(12)                       // doce noches buenas y maduras
        dias.append(dm("2026-06-13", hrv: nil, rhr: nil, resp: nil))   // sin reloj
        dias.append(dm("2026-06-14", hrv: 55, rhr: 55, resp: 14))      // vuelve el reloj

        let r = read(dias, asOf: "2026-06-14")
        let sinReloj = r.verdictHistory.first { $0.day == "2026-06-13" }
        XCTAssertNotNil(sinReloj)
        XCTAssertEqual(sinReloj?.verdict, .lowSignal,
                       "una noche sin señal no puede salir pintada con el veredicto de ayer")
    }

    /// Con cobertura intermitente, la proporción de celdas con veredicto real no puede inflarse.
    func testCoberturaIntermitenteNoInflaLosDiasBuenos() {
        var dias: [DailyMetric] = []
        for i in 1...24 {
            let day = String(format: "2026-06-%02d", i)
            dias.append(i % 2 == 0 ? dm(day, hrv: nil, rhr: nil, resp: nil)
                                   : dm(day, hrv: 55, rhr: 55, resp: 14))
        }
        let r = read(dias, asOf: dias.last!.day)
        let sinLectura = r.verdictHistory.filter { $0.verdict == .lowSignal }.count
        XCTAssertGreaterThanOrEqual(sinLectura, 12,
                                    "las 12 noches sin reloj tienen que contarse como sin lectura")
    }

    // MARK: - Los huecos que la revisión encontró sin red

    /// El camino `autonomic.state == .noData`: el Read se fuerza a `.lowSignal` sin plegar, y la
    /// serie tiene que decir lo mismo en su última celda — no quedarse pegada al veredicto de ayer.
    func testCaminoEjeSinDato_laUltimaCeldaNoSeQuedaPegada() {
        var dias = baseline(12)
        dias.append(dm("2026-06-13", hrv: nil, rhr: nil, resp: nil))   // hoy sin señal
        let r = read(dias, asOf: "2026-06-13")
        XCTAssertEqual(r.verdict, .lowSignal)
        XCTAssertEqual(r.verdictHistory.last?.verdict, .lowSignal,
                       "el héroe dice «baja señal»: el mosaico no puede decir otra cosa ese día")
        XCTAssertEqual(r.verdictHistory.last?.day, "2026-06-13")
    }

    /// El cap va DESPUÉS del pliegue, comprobado a través de `evaluate()` y no solo del pliegue
    /// suelto: si alguien invirtiera el orden, ninguna prueba anterior fallaba.
    func testElCapSeAplicaDespuesDelPliegue_viaEvaluate() {
        // 40 días: los primeros malos, el resto buenos. La ventana visible son los últimos 30,
        // y su primer día conserva el momentum de los 10 que quedaron fuera.
        var dias: [DailyMetric] = []
        for i in 1...40 {
            let d = Date(timeIntervalSince1970: 1_750_000_000 + Double(i) * 86_400)
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
            f.timeZone = TimeZone(identifier: "UTC")
            dias.append(i <= 12 ? dm(f.string(from: d), hrv: 30, rhr: 75, resp: 20)
                                : dm(f.string(from: d), hrv: 55, rhr: 55, resp: 14))
        }
        let r = read(dias, asOf: dias.last!.day)
        XCTAssertEqual(r.verdictHistory.count, Preparedness.verdictHistoryWindow,
                       "la ventana es EXACTAMENTE 30, no «hasta 30»")
        XCTAssertEqual(r.verdictHistory.first?.day, dias[dias.count - 30].day,
                       "la ventana empieza donde debe: se capa después de plegar todo")
    }

    func testVentanaVaciaNoCrashea() {
        let r = read([], asOf: "2026-06-20")
        XCTAssertTrue(r.verdictHistory.isEmpty, "sin días, la serie es vacía — sin celda fantasma")
    }

    // MARK: - Causalidad: el hueco REAL, demostrado y no escondido

    /// 🔴 LA PRUEBA QUE EL REQUERIMIENTO PIDE POR NOMBRE, y que un fixture que solo mueve HRV
    /// jamás habría cazado.
    ///
    /// `nocturnalUsable` decide **para TODA la ventana** si la FC corre sobre el constructo
    /// nocturno o el despierto, y una de sus condiciones es que **la noche de HOY sea
    /// nocturna**. Quitar la lectura nocturna de hoy —sin tocar un solo dato viejo— voltea la
    /// serie entera y **repinta veredictos ya mostrados**.
    ///
    /// El fixture importa: con una serie plana (todos los días en rango) cambiar de constructo
    /// no voltea nada y la prueba pasaría en vacío. Aquí la FC despierta es plana y la nocturna
    /// trae un pico real en un día viejo, así que ese día es «fuera» bajo un constructo y
    /// «dentro» bajo el otro. Es la diferencia entre documentar el hueco y solo decir que existe.
    ///
    /// Esta prueba NO corrige la limitación: la DEMUESTRA, y por eso la pantalla no puede
    /// afirmar que cada cuadro es la foto de lo que el usuario vio esa mañana.
    func testQuitarLaLecturaNocturnaDeHoyRepintaLaHistoria() {
        // FC despierta PLANA: bajo este constructo ningún día se sale.
        let dias = (1...20).map { i in
            dm(String(format: "2026-06-%02d", i), hrv: 55, rhr: 55, resp: 14)
        }
        // FC nocturna plana SALVO un pico gordo en un día viejo (el 8).
        var nocturna: [String: Double] = [:]
        for (i, d) in dias.enumerated() { nocturna[d.day] = (i == 7) ? 70 : 46 }

        let conHoy = read(dias, asOf: dias.last!.day, nocturnalRestingHr: nocturna)
        var sinHoy = nocturna
        sinHoy.removeValue(forKey: dias.last!.day)
        let sinLaDeHoy = read(dias, asOf: dias.last!.day, nocturnalRestingHr: sinHoy)

        XCTAssertEqual(conHoy.verdictHistory.count, sinLaDeHoy.verdictHistory.count)

        // El día 8 es un día VIEJO: su dato no se tocó, y aun así cambia de lectura.
        let clave = dias[7].day
        let antes = conHoy.verdictHistory.first { $0.day == clave }
        let despues = sinLaDeHoy.verdictHistory.first { $0.day == clave }
        XCTAssertNotNil(antes); XCTAssertNotNil(despues)
        XCTAssertTrue(antes?.autonomicOut == true,
                      "con el constructo nocturno el pico del día 8 se sale")
        XCTAssertFalse(despues?.autonomicOut == true,
                       "LIMITACIÓN DEMOSTRADA: al perder la lectura nocturna de HOY, la ventana entera cae al constructo despierto y un día VIEJO deja de estar fuera, sin que su propio dato cambiara")
    }

    /// Cruzar `Baselines.minNightsSeed` por abajo es la OTRA mitad del mismo gate: con pocas
    /// noches nocturnas la ventana corre despierta aunque hoy sí traiga la suya.
    func testConPocasNochesNocturnasLaVentanaNoUsaElConstructoNocturno() {
        let dias = baseline(20)
        var pocas: [String: Double] = [:]
        for d in dias.suffix(2) { pocas[d.day] = 46 }   // 2 noches: por debajo del semillero

        let a = read(dias, asOf: dias.last!.day, nocturnalRestingHr: pocas)
        let b = read(dias, asOf: dias.last!.day, nocturnalRestingHr: [:])
        XCTAssertEqual(a.verdictHistory.map(\.verdict), b.verdictHistory.map(\.verdict),
                       "por debajo del semillero, un puñado de noches nocturnas no cambia nada: la ventana corre entera sobre el constructo despierto")
    }
}
