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
                      trend: AutonomicTrend.Read? = nil) -> Preparedness.Read {
        Preparedness.evaluate(.init(days: days, strainByDay: [:], trend: trend, asOf: asOf,
                                    nocturnalRestingHr: [:], cyclePhase: nil, nocturnalRmssd: nil))
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
        for i in raws.indices {
            let prefijo = Preparedness.hysteresedSeries(Array(raws[0...i]), hysteresisDays: 2)
            XCTAssertEqual(serie[i], prefijo.last,
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
        // Con la tendencia cayendo, un `caution` estable se degrada a `easy` DESPUÉS de plegar.
        var dias = baseline()
        // Un día que por sí solo da `caution`, que es donde el empujón actúa.
        dias.append(dm("2026-06-21", hrv: 30, rhr: 75, resp: 20))
        let conTendencia = read(dias, asOf: "2026-06-21", trend: cayendo)
        XCTAssertEqual(conTendencia.verdictHistory.last?.verdict, conTendencia.verdict,
                       "si el empujón mueve el veredicto, la serie tiene que moverse con él")
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
        let raws: [Preparedness.Verdict] = [.full, .full, .caution, .caution]
        let serie = Preparedness.hysteresedSeries(raws, hysteresisDays: 2)
        XCTAssertEqual(serie.last, .caution,
                       "dos `caution` mueven el estable aunque entre ellos hubiera un hueco de días")
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
}
