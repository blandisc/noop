import XCTest
import StrandAnalytics
@testable import Cenit

// MARK: - OnboardingLandingTests (FER-109)
//
// El desenlace del onboarding se decide CONTANDO lo que aterrizó, nunca por el permiso: HealthKit
// no revela si concedieron LECTURA (`HealthKitBridge.requestAuthorization`), así que quien negó
// todo y quien concedió todo llegan aquí con el mismo `auth == .authorized`. Estos fixtures fijan
// las cuatro salidas y, sobre todo, el TOPE: sin FC en reposo no hay veredicto nunca, y decirle a
// esa persona «te faltan 2 noches» sería una promesa que no se cumple ni esperando un año.

final class OnboardingLandingTests: XCTestCase {

    // MARK: Fixtures

    private func prep(_ verdict: Preparedness.Verdict,
                      noches: Int,
                      maturity: BaselineStatus = .trusted) -> Preparedness.Read {
        Preparedness.Read(verdict: verdict, drivers: [],
                          signalsPresent: 2, signalsTotal: 3,
                          maturity: maturity, autonomicNights: noches, trend: nil)
    }

    /// Cobertura de quien SÍ trae FC en reposo (la llave que abre el veredicto).
    private func conFCReposo(_ dias: Int = 30) -> [String: Int] {
        ["resting_hr": dias, "asleep_min": dias, "steps": dias, "hrv": dias]
    }

    /// Cobertura de quien trae señales pero NINGUNA FC en reposo. Una métrica ausente es una
    /// llave AUSENTE en `AppleHealthCoverage.daysByMetric`, no un cero: por eso no aparece.
    private func sinFCReposo(_ dias: Int = 30) -> [String: Int] {
        ["asleep_min": dias, "steps": dias, "active_kcal": dias]
    }

    private func decidir(totalDays: Int,
                         _ metricas: [String: Int],
                         _ preparedness: Preparedness.Read?) -> OnboardingLanding {
        OnboardingLandingDecider.decidir(totalDays: totalDays,
                                         diasPorMetrica: metricas,
                                         preparedness: preparedness)
    }

    // MARK: Los cuatro desenlaces

    func test_sinDatos_cuandoNoAterrizoNiUnaFila() {
        XCTAssertEqual(decidir(totalDays: 0, [:], nil), .sinDatos)
    }

    /// Ni siquiera una lectura del motor colada por otro lado rescata el caso: sin filas, nada.
    func test_sinDatos_ganaAunConLecturaDelMotor() {
        XCTAssertEqual(decidir(totalDays: 0, [:], prep(.full, noches: 30)), .sinDatos)
    }

    func test_sinRitmoEnReposo_conSuenoYPasosPeroCeroFCEnReposo() {
        XCTAssertEqual(decidir(totalDays: 120, sinFCReposo(120), nil),
                       .sinRitmoEnReposo(diasHistoria: 120))
    }

    func test_calibrando_conFCEnReposoPeroBaseJoven() {
        XCTAssertEqual(decidir(totalDays: 9, conFCReposo(9), prep(.full, noches: 2, maturity: .calibrating)),
                       .calibrando(noches: 2, faltan: 2, diasHistoria: 9))
    }

    func test_lectura_conBaseSembradaYVeredictoReal() {
        XCTAssertEqual(decidir(totalDays: 60, conFCReposo(60), prep(.full, noches: 4)),
                       .lectura(verdict: .full, noches: 4, diasHistoria: 60))
    }

    // MARK: El tope — sin FC en reposo no hay veredicto, nunca

    /// Va ANTES del conteo de noches a propósito: aunque el motor traiga una lectura vieja, si la
    /// señal que la sostiene no existe en la cobertura, el desenlace es el tope y no «calibrando».
    func test_sinRitmoEnReposo_ganaAlConteoDeNoches() {
        XCTAssertEqual(decidir(totalDays: 45, sinFCReposo(45), prep(.lowSignal, noches: 3, maturity: .calibrating)),
                       .sinRitmoEnReposo(diasHistoria: 45))
    }

    /// Y también gana a una lectura completa: la cobertura es la evidencia, el motor es opinión.
    func test_sinRitmoEnReposo_ganaAUnaLecturaCompleta() {
        XCTAssertEqual(decidir(totalDays: 45, sinFCReposo(45), prep(.full, noches: 20)),
                       .sinRitmoEnReposo(diasHistoria: 45))
    }

    /// Un solo día de FC en reposo ya cambia de familia: deja de ser el tope y pasa a contar noches.
    func test_unDiaDeFCEnReposoSacaDelTope() {
        XCTAssertEqual(decidir(totalDays: 12, ["resting_hr": 1, "steps": 12], nil),
                       .calibrando(noches: 0, faltan: Baselines.minNightsSeed, diasHistoria: 12))
    }

    // MARK: Calibrando — las tres formas de «el motor todavía no opina»

    func test_calibrando_cuandoNoHayLecturaDelMotor() {
        XCTAssertEqual(decidir(totalDays: 5, conFCReposo(5), nil),
                       .calibrando(noches: 0, faltan: Baselines.minNightsSeed, diasHistoria: 5))
    }

    /// Si el motor no puede opinar, el onboarding tampoco — aunque la base sea profunda. `faltan`
    /// llega a 0 porque las noches ya están: lo que falta no es tiempo, es una lectura de hoy.
    func test_calibrando_conLowSignalYMuchasNoches() {
        XCTAssertEqual(decidir(totalDays: 200, conFCReposo(200), prep(.lowSignal, noches: 30)),
                       .calibrando(noches: 30, faltan: 0, diasHistoria: 200))
    }

    func test_calibrando_justoDebajoDelSeed() {
        let seed = Baselines.minNightsSeed
        XCTAssertEqual(decidir(totalDays: 10, conFCReposo(10), prep(.caution, noches: seed - 1)),
                       .calibrando(noches: seed - 1, faltan: 1, diasHistoria: 10))
    }

    /// El seed es del MOTOR, no de la pantalla: la frontera está exactamente en `minNightsSeed`.
    func test_fronteraDelSeed_esLaDelMotor() {
        let seed = Baselines.minNightsSeed
        let cobertura = conFCReposo()
        guard case .calibrando = decidir(totalDays: 30, cobertura, prep(.full, noches: seed - 1)) else {
            return XCTFail("Una noche antes del seed todavía calibra")
        }
        guard case .lectura = decidir(totalDays: 30, cobertura, prep(.full, noches: seed)) else {
            return XCTFail("En el seed exacto ya hay palabra")
        }
    }

    // MARK: El reloj de día — el caso que SÍ pasa y NO hay que bloquear

    /// Quien trae el reloj de día y no duerme con él tiene `resting_hr` (el agregado DESPIERTO de
    /// Apple) y cero noches nocturnas. `Preparedness` lo resuelve solo: si la serie nocturna no
    /// cubre `minNightsSeed`, usa la despierta entera («One construct, always»), así que llega con
    /// veredicto y noches reales. Esa persona merece su palabra: no la mandamos al tope.
    func test_relojDeDia_llegaALectura() {
        let landing = decidir(totalDays: 90,
                              ["resting_hr": 88, "steps": 90, "active_kcal": 90],   // sin asleep_min
                              prep(.caution, noches: 12, maturity: .provisional))
        XCTAssertEqual(landing, .lectura(verdict: .caution, noches: 12, diasHistoria: 90))
    }

    /// Y los cuatro veredictos reales viajan intactos (el enum, nunca el copy: la palabra la dice
    /// `LiquidHoyBuilder.veredicto`, que es la única fuente).
    func test_lectura_transportaElVeredictoSinTraducirlo() {
        for v in [Preparedness.Verdict.full, .caution, .easy] {
            XCTAssertEqual(decidir(totalDays: 40, conFCReposo(40), prep(v, noches: 14)),
                           .lectura(verdict: v, noches: 14, diasHistoria: 40))
        }
    }

    // MARK: diasHistoria

    func test_diasHistoria_saleDeLaCoberturaEnTodasLasFamilias() {
        XCTAssertEqual(OnboardingLanding.sinDatos.diasHistoria, 0)
        XCTAssertEqual(OnboardingLanding.sinRitmoEnReposo(diasHistoria: 77).diasHistoria, 77)
        XCTAssertEqual(OnboardingLanding.calibrando(noches: 2, faltan: 2, diasHistoria: 9).diasHistoria, 9)
        XCTAssertEqual(OnboardingLanding.lectura(verdict: .full, noches: 4, diasHistoria: 61).diasHistoria, 61)
    }

    // MARK: densidadHonesta

    func test_densidad_sinDatosEsCero() {
        XCTAssertEqual(OnboardingLanding.sinDatos.densidadHonesta, 0, accuracy: 1e-9)
    }

    /// Hay materia, pero nunca cuaja — y el techo NO depende de cuánta historia haya.
    func test_densidad_sinRitmoEnReposoNuncaCuaja() {
        XCTAssertEqual(OnboardingLanding.sinRitmoEnReposo(diasHistoria: 3).densidadHonesta, 0.34, accuracy: 1e-9)
        XCTAssertEqual(OnboardingLanding.sinRitmoEnReposo(diasHistoria: 3000).densidadHonesta, 0.34, accuracy: 1e-9)
    }

    /// El denominador es del motor (`minNightsTrust` = 14): 8 noches queda poroso, 14 llena.
    func test_densidad_escalaConLasNochesHastaTrust() {
        let trust = Double(Baselines.minNightsTrust)
        XCTAssertEqual(OnboardingLanding.lectura(verdict: .full, noches: 8, diasHistoria: 30).densidadHonesta,
                       8 / trust, accuracy: 1e-9)
        XCTAssertEqual(OnboardingLanding.lectura(verdict: .full, noches: Baselines.minNightsTrust,
                                                 diasHistoria: 30).densidadHonesta,
                       1.0, accuracy: 1e-9)
        XCTAssertEqual(OnboardingLanding.calibrando(noches: 2, faltan: 2, diasHistoria: 9).densidadHonesta,
                       2 / trust, accuracy: 1e-9)
    }

    /// Monótona y topada: más noches nunca baja la densidad, y nada la pasa de 1.0 (el orbe no se
    /// llena solo por esperar, ni se desborda por llevar años).
    func test_densidad_esMonotonaYTopadaEnUno() {
        var previa = -1.0
        for n in 0...40 {
            let d = OnboardingLanding.lectura(verdict: .full, noches: n, diasHistoria: 100).densidadHonesta
            XCTAssertGreaterThanOrEqual(d, previa, "la densidad bajó al pasar de \(n - 1) a \(n) noches")
            XCTAssertLessThanOrEqual(d, 1.0, "la densidad se desbordó en \(n) noches")
            XCTAssertGreaterThanOrEqual(d, 0.0)
            previa = d
        }
        XCTAssertEqual(previa, 1.0, accuracy: 1e-9)
    }

    /// Un conteo imposible (negativo) no puede producir una densidad negativa.
    func test_densidad_conNochesNegativasSeQuedaEnCero() {
        XCTAssertEqual(OnboardingLanding.calibrando(noches: -3, faltan: 7, diasHistoria: 5).densidadHonesta,
                       0, accuracy: 1e-9)
    }

    // MARK: seed inyectable (parámetro para probar, jamás para inventar un umbral propio)

    func test_seedInyectado_mueveLaFrontera() {
        let landing = OnboardingLandingDecider.decidir(totalDays: 30,
                                                       diasPorMetrica: conFCReposo(),
                                                       preparedness: prep(.full, noches: 5),
                                                       seed: 8)
        XCTAssertEqual(landing, .calibrando(noches: 5, faltan: 3, diasHistoria: 30))
    }

    /// El default del decisor ES el del motor: si `Baselines.minNightsSeed` se mueve, esto se mueve.
    func test_seedPorDefecto_esElDelMotor() {
        let conDefault = decidir(totalDays: 30, conFCReposo(), prep(.full, noches: 1))
        let explicito = OnboardingLandingDecider.decidir(totalDays: 30,
                                                         diasPorMetrica: conFCReposo(),
                                                         preparedness: prep(.full, noches: 1),
                                                         seed: Baselines.minNightsSeed)
        XCTAssertEqual(conDefault, explicito)
    }

    /// La llave que el decisor lee es exactamente la que escribe `CenitStore.appleHealthCoverage`.
    func test_claveDeFCEnReposo_esLaDelStore() {
        XCTAssertEqual(OnboardingLandingDecider.claveFCReposo, "resting_hr")
    }
}
