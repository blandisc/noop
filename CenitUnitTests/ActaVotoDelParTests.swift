import XCTest
import StrandAnalytics
@testable import Cenit

// MARK: - El acta y el voto del par (FER-81 · adversarial H3)
//
// El motor cuenta TRES votantes (FC en reposo, sueño y el par temperatura+respiración) pero la
// boleta solo DIBUJA dos filas. Sumar el voto del par al conteo sin decírselo a la prosa hacía
// que el acta nombrara una señal que estaba dentro. Cada test es una de esas frases falsas.

@MainActor
final class ActaVotoDelParTests: XCTestCase {

    private func read(verdict: Preparedness.Verdict,
                      autonomicOut: Bool, sleepOut: Bool,
                      par: Bool) -> Preparedness.Read {
        Preparedness.Read(
            verdict: verdict,
            drivers: [.init(axis: .autonomic, state: autonomicOut ? .low : .inRange, orientedZ: nil),
                      .init(axis: .sleep, state: sleepOut ? .low : .inRange, orientedZ: nil)],
            signalsPresent: 3, signalsTotal: 3, maturity: .trusted, autonomicNights: 30,
            trend: nil,
            sentinel: par ? .init(state: .corroborated, streakNights: 2, watchingSignal: nil,
                                  tempOut: true, respOut: true)
                          : .init(state: .quiet, streakNights: 0, watchingSignal: nil,
                                  tempOut: false, respOut: false),
            sentinelHistory: [.init(day: Repository.localDayKey(Date()), tempOut: par, respOut: par,
                                    tempMissing: false, respMissing: false, respJudged: true,
                                    gapBefore: false)],
            bodyHistory: [.init(day: Repository.localDayKey(Date()), rhrResolved: 55,
                                autonomicOrientedZ: 0.1, autonomicOut: autonomicOut,
                                sleepOut: sleepOut, rhrBaseCenter: 55, hrvBaseCenter: 45,
                                rhrBand: 53...57)])
    }

    /// El resfriado clásico: los dos ejes DENTRO y el par fuera. La prosa decía «la FC en reposo
    /// votó fuera» con las dos filas en «dentro».
    func test_parSolo_noNombraUnEjeQueEstaDentro() {
        let acta = LiquidHoyBuilder.acta(prep: read(verdict: .caution, autonomicOut: false,
                                                    sleepOut: false, par: true))
        XCTAssertFalse(acta.conteo.contains(String(localized: "acta.resumen.caution.auto",
                                                   defaultValue: "Resting HR voted outside; sleep, inside.")),
                       "ningún eje votó fuera: no se puede nombrar uno")
        XCTAssertTrue(acta.conteo.lowercased().contains("temperature")
                      || acta.conteo.lowercased().contains("temperatura"),
                      "la prosa nombra al par, que es quien votó: \\(acta.conteo)")
        // Y los vigilantes ya no dicen «no votan» el día que votaron.
        XCTAssertEqual(acta.vigilantesLabel,
                       String(localized: "acta.vigilantes.votaron", defaultValue: "Watching · they voted today"))
    }

    /// H3-b: un eje fuera + el par ⇒ el motor cuenta dos votos y da `.easy`, pero «los dos votos
    /// cayeron fuera» es falso: uno lo puso el par.
    func test_easyConParYUnEje_noDiceQueLosDosEjesVotaronFuera() {
        let acta = LiquidHoyBuilder.acta(prep: read(verdict: .easy, autonomicOut: false,
                                                    sleepOut: true, par: true))
        XCTAssertNotEqual(acta.conteo, String(localized: "Both of your votes fell outside."))
        XCTAssertTrue(acta.conteo.lowercased().contains("sleep")
                      || acta.conteo.lowercased().contains("sueño"))
        XCTAssertTrue(acta.conteo.lowercased().contains("together")
                      || acta.conteo.lowercased().contains("juntas"))
    }

    // MARK: Segunda vuelta adversarial — la rama del par contra la histéresis

    /// El DESFASE manda: con veredicto verde sostenido por la histéresis y el par corroborado
    /// hoy, la rama del par (que vivía ARRIBA del bloque de desfase) devolvía «se salieron
    /// juntas» y se comía la única explicación de por qué el veredicto NO se movió.
    func test_desfaseConPar_siempreExplicaLaHisteresis() {
        // .full con un voto fuera ⇒ el veredicto mostrado viene de ayer.
        let acta = LiquidHoyBuilder.acta(prep: read(verdict: .full, autonomicOut: false,
                                                    sleepOut: false, par: true))
        let t = acta.conteo.lowercased()
        XCTAssertTrue(t.contains("two days") || t.contains("dos días"),
                      "el desfase es lo que se está viendo: tiene que decirse: \(acta.conteo)")
        XCTAssertTrue(t.contains("together") || t.contains("juntas"),
                      "y sigue nombrando al par, que es quien votó: \(acta.conteo)")
    }

    /// Y cuando ADEMÁS un eje se salió, la frase corta lo escondía: era la única alcanzable.
    func test_desfaseConParYEjeFuera_nombraALosDos() {
        let acta = LiquidHoyBuilder.acta(prep: read(verdict: .full, autonomicOut: false,
                                                    sleepOut: true, par: true))
        let t = acta.conteo.lowercased()
        XCTAssertTrue(t.contains("together") || t.contains("juntas"))
        XCTAssertTrue(t.contains("one of your votes") || t.contains("uno de tus votos"),
                      "el voto que sí cayó fuera no puede desaparecer: \(acta.conteo)")
    }

    /// Sin FC nocturna posible, la tarjeta de calibración cuenta noches de reloj que jamás van a
    /// llegar — el héroe acaba de decir «todavía no puedo leer tus mañanas».
    func test_sinFCNocturnaPosible_elActaNoPrometeNochesDeReloj() {
        let base = read(verdict: .lowSignal, autonomicOut: false, sleepOut: false, par: false)
        let sinReloj = Preparedness.Read(
            verdict: .lowSignal, drivers: base.drivers, signalsPresent: 1, signalsTotal: 3,
            maturity: .calibrating, autonomicNights: 0, trend: nil,
            sentinel: base.sentinel, sentinelHistory: base.sentinelHistory,
            bodyHistory: base.bodyHistory, autonomicPossible: false)
        let acta = LiquidHoyBuilder.acta(prep: sinReloj)
        if case .calibrando = acta.confianza {
            XCTFail("prometer «0 de 4 noches» a quien no puede acumularlas es una promesa falsa")
        }
        XCTAssertFalse(acta.notas.contains { $0.id == "calibrando" },
                       "ni la nota de «N noches más con tu Apple Watch»")
    }

    /// Sin par, la prosa de siempre no cambia (no se rompió el camino normal).
    func test_sinPar_laProsaDeSiempre() {
        let acta = LiquidHoyBuilder.acta(prep: read(verdict: .easy, autonomicOut: true,
                                                    sleepOut: true, par: false))
        XCTAssertEqual(acta.conteo, String(localized: "Both of your votes fell outside."))
        XCTAssertEqual(acta.vigilantesLabel, String(localized: "Watching, not voting"))
    }
}
