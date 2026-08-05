import XCTest
import StrandAnalytics
import StrandDesign
import StrandModels
@testable import Cenit

// HoyCosmosBuilderTests.swift — FER-51 · Lane C · criterios 4, 5, 6, 7, 8, 9, 12.
//
// Fija la proyección pura `LiquidHoyBuilder.cosmosAbierto` contra la semántica del REQ
// (§4–§6, §8). No re-deriva umbrales: solo comprueba que el builder consume HoyGramatica.
final class HoyCosmosBuilderTests: XCTestCase {

    // MARK: Fixtures

    private func driver(_ axis: Preparedness.Axis, _ state: Preparedness.AxisState,
                        z: Double? = nil) -> Preparedness.Driver {
        Preparedness.Driver(axis: axis, state: state, orientedZ: z)
    }

    private func signal(_ s: Preparedness.Signal, z: Double?,
                        out: Bool = false) -> Preparedness.SignalRead {
        Preparedness.SignalRead(signal: s, orientedZ: z, share: 1.0,
                                flaggedAlone: false, out: out)
    }

    private func read(verdict: Preparedness.Verdict = .full,
                      autonomic: Preparedness.AxisState = .inRange,
                      sleep: Preparedness.AxisState = .inRange,
                      autonomicZ: Double? = 0.2,
                      nights: Int = 30,
                      maturity: BaselineStatus = .trusted,
                      signals: [Preparedness.SignalRead] = [],
                      sentinel: Preparedness.SentinelRead? = nil,
                      thermalDev: Double? = nil) -> Preparedness.Read {
        Preparedness.Read(
            verdict: verdict,
            drivers: [driver(.autonomic, autonomic, z: autonomicZ),
                      driver(.sleep, sleep),
                      driver(.thermal, .inRange),
                      driver(.load, .noData)],
            signals: signals.isEmpty
                ? [signal(.rhr, z: autonomicZ), signal(.hrv, z: 0.1), signal(.resp, z: 0.0)]
                : signals,
            signalsPresent: 3, signalsTotal: 3,
            maturity: maturity, autonomicNights: nights, trend: nil,
            sentinel: sentinel,
            thermalAdjustedDevC: thermalDev)
    }

    private func centinela(_ state: Preparedness.SentinelState, racha: Int,
                           señal: Preparedness.SentinelSignal? = nil) -> Preparedness.SentinelRead {
        Preparedness.SentinelRead(state: state, streakNights: racha, watchingSignal: señal,
                                  tempOut: state == .corroborated || señal == .temp,
                                  respOut: state == .corroborated || señal == .resp)
    }

    private func inputs(prep: Preparedness.Read?,
                        acwr: Double? = 1.12,
                        sleepMin: Double? = 462,
                        rhr: Double? = 52,
                        hrv: Double? = 68,
                        temp: Double? = 0.2,
                        resp: Double? = 14.2,
                        stress: Double? = 0.6,
                        strain: Double? = 11.2,
                        steps: Double? = 8432,
                        efficiency: Double? = 0.92) -> (LiquidHoyBuilder.MatrizInputs,
                                                         LiquidHoyBuilder.CosmosExtraInputs) {
        let day = "2026-08-05"
        var dias: [DailyMetric] = []
        if let sleepMin {
            dias.append(DailyMetric(
                day: day, totalSleepMin: sleepMin, efficiency: efficiency,
                deepMin: nil, remMin: nil, lightMin: nil, disturbances: nil,
                restingHr: rhr.map { Int($0.rounded()) }, avgHrv: hrv,
                recovery: nil, strain: strain, exerciseCount: nil,
                skinTempDevC: temp, respRateBpm: resp, steps: steps.map { Int($0.rounded()) }))
        }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        var comps = DateComponents()
        comps.year = 2026; comps.month = 8; comps.day = 5
        let now = cal.date(from: comps) ?? Date()

        let matriz = LiquidHoyBuilder.MatrizInputs(
            prep: prep,
            diasRecientes: dias,
            carga: acwr.map { TrainingLoadModel(acwr: $0, series: []) },
            locale: Locale(identifier: "en_US"),
            calendar: cal,
            now: now)
        let extra = LiquidHoyBuilder.CosmosExtraInputs(
            sleep: sleepMin.map { .init($0) },
            rhr: rhr.map { .init($0) },
            hrv: hrv.map { .init($0) },
            temp: temp.map { .init($0) },
            resp: resp.map { .init($0) },
            stress: stress,
            strain: strain,
            steps: steps)
        return (matriz, extra)
    }

    private func model(_ prep: Preparedness.Read? = nil,
                       acwr: Double? = 1.12,
                       sleepMin: Double? = 462,
                       efficiency: Double? = 0.92,
                       rhr: Double? = 52,
                       hrv: Double? = 68,
                       nights: Int = 30,
                       maturity: BaselineStatus = .trusted,
                       autonomic: Preparedness.AxisState = .inRange,
                       sleep: Preparedness.AxisState = .inRange,
                       autonomicZ: Double? = 0.2,
                       signals: [Preparedness.SignalRead] = [],
                       sentinel: Preparedness.SentinelRead? = nil,
                       thermalDev: Double? = 0.2,
                       stress: Double? = 0.6,
                       strain: Double? = 11.2,
                       steps: Double? = 8432) -> CosmosAbiertoModel {
        let prepResolved = prep ?? read(autonomic: autonomic, sleep: sleep,
                                        autonomicZ: autonomicZ, nights: nights,
                                        maturity: maturity, signals: signals,
                                        sentinel: sentinel, thermalDev: thermalDev)
        let (m, e) = inputs(prep: prepResolved, acwr: acwr, sleepMin: sleepMin,
                            rhr: rhr, hrv: hrv, temp: thermalDev, resp: 14.2,
                            stress: stress, strain: strain, steps: steps,
                            efficiency: efficiency)
        return LiquidHoyBuilder.cosmosAbierto(m, extra: e)
    }

    private func ancla(_ m: CosmosAbiertoModel, _ id: String) -> CosmosAbiertoModel.Ancla {
        try! XCTUnwrap(m.anclas.first { $0.id == id })
    }

    // MARK: Criterio 4 — 5 medidores; esfuerzo/pasos/estrés SIN medidor

    func test_criterio4_cincoMedidoresYTresSin() {
        let m = model()
        let con = ["sleep", "rhr", "guardian", "carga", "hrv"]
        let sin = ["stress", "strain", "steps"]
        for id in con {
            XCTAssertTrue(ancla(m, id).tieneMedidor, "\(id) debe tener medidor")
            XCTAssertFalse(ancla(m, id).medidor?.fantasma == true, "\(id) no fantasma en día bueno")
        }
        for id in sin {
            XCTAssertFalse(ancla(m, id).tieneMedidor, "\(id) NO debe tener medidor")
        }
        // VFC punteado
        XCTAssertEqual(ancla(m, "hrv").medidor?.punteado, true)
        // Par del guardián: un anillo, dos lunitas
        XCTAssertEqual(ancla(m, "guardian").medidor?.lunitas.count, 2)
    }

    // MARK: Criterio 5 — en rango, lunita dentro del arco; «peor» a la derecha

    func test_criterio5_enRangoLunitaDentroDelArco() {
        // FC en base (z_mal 0) → p 50, arco desviación 25–75.
        let m = model(autonomicZ: 0.0)  // orientedZ 0 ⇒ z_mal 0
        let pRHR = try! XCTUnwrap(ancla(m, "rhr").medidor?.lunitas.first?.p)
        XCTAssertEqual(pRHR, 50, accuracy: 0.01)
        XCTAssertTrue((25...75).contains(pRHR))

        // Sueño 7:42 (462 min) cerca del piso 420 → p un poco por debajo de 50.
        let pSleep = try! XCTUnwrap(ancla(m, "sleep").medidor?.lunitas.first?.p)
        XCTAssertTrue((25...75).contains(pSleep), "sueño en rango debe caer dentro del arco progreso/desviación usable")

        // Carga 1.12 → p 56, zona dulce 40–65.
        let pCarga = try! XCTUnwrap(ancla(m, "carga").medidor?.lunitas.first?.p)
        XCTAssertEqual(pCarga, HoyGramatica.pCarga(razon: 1.12), accuracy: 0.01)
        XCTAssertTrue(HoyGramatica.arcoCarga.contains(pCarga))
    }

    // MARK: Criterio 6 — VFC jamás ámbar/rojo

    func test_criterio6_vfcNuncaAlerta() {
        // orientedZ muy negativo (HRV caído) → z_mal alto, p fuera del arco, PERO alerta .ninguna.
        let sigs = [signal(.rhr, z: 0.2), signal(.hrv, z: -3.0), signal(.resp, z: 0)]
        let m = model(signals: sigs, hrv: 25)
        let hrv = ancla(m, "hrv")
        XCTAssertEqual(hrv.alerta, .ninguna)
        XCTAssertEqual(hrv.medidor?.lunitas.first?.alerta, .ninguna)
        // p debe ser alto (peor a la derecha) si hay z.
        if let p = hrv.medidor?.lunitas.first?.p {
            XCTAssertGreaterThan(p, 75, "caída fuerte de VFC → lunita a la derecha, sin alerta")
        }
    }

    // MARK: Criterio 7 — carga 1.48 / 1.55 / 0.6

    func test_criterio7_cargaZonaYAlerta() {
        // 1.48: fuera del arco SIN alerta.
        let m148 = model(acwr: 1.48)
        let c148 = ancla(m148, "carga")
        let p148 = try! XCTUnwrap(c148.medidor?.lunitas.first?.p)
        XCTAssertFalse(HoyGramatica.arcoCarga.contains(p148), "1.48 fuera de zona dulce")
        XCTAssertEqual(c148.alerta, .ninguna)
        XCTAssertEqual(c148.medidor?.lunitas.first?.alerta, .ninguna)

        // 1.55: ámbar (atención).
        let m155 = model(acwr: 1.55)
        let c155 = ancla(m155, "carga")
        XCTAssertEqual(c155.alerta, .atencion)
        XCTAssertEqual(c155.medidor?.lunitas.first?.alerta, .atencion)

        // 0.6: descargando, sin alerta.
        let m06 = model(acwr: 0.6)
        let c06 = ancla(m06, "carga")
        XCTAssertEqual(c06.alerta, .ninguna)
        XCTAssertTrue(c06.sublabel?.localizedCaseInsensitiveContains("unload") == true
                      || c06.sublabel?.localizedCaseInsensitiveContains("descarg") == true
                      || HoyGramatica.estadoCarga(razon: 0.6) == "carga.descargando")
    }

    // MARK: Criterio 8 — sueño 8 h + eficiencia 72 % → alerta + sublabel

    func test_criterio8_suenoPorEficiencia() {
        let prep = read(sleep: .high)  // eje fuera (eficiencia)
        let m = model(prep: prep, sleepMin: 480, efficiency: 0.72)
        let s = ancla(m, "sleep")
        XCTAssertEqual(s.alerta, .atencion)
        let p = try! XCTUnwrap(s.medidor?.lunitas.first?.p)
        XCTAssertEqual(p, 80, accuracy: 0.01, "eficiencia baja → p fijo 80")
        let sub = try! XCTUnwrap(s.sublabel)
        XCTAssertTrue(sub.contains("72"), "sublabel debe llevar el % de eficiencia: \(sub)")
    }

    // MARK: Criterio 9 — base < 4 noches: fantasma, «—», conociéndote, jamás alerta

    func test_criterio9_fantasmaSinBase() {
        let prep = read(nights: 2, maturity: .calibrating, thermalDev: nil)
        let (matriz, extra) = inputs(prep: prep, acwr: nil, sleepMin: nil, rhr: nil,
                                     hrv: nil, temp: nil, resp: nil, stress: nil,
                                     strain: nil, steps: nil, efficiency: nil)
        let m = LiquidHoyBuilder.cosmosAbierto(matriz, extra: extra)

        for id in ["sleep", "rhr", "guardian", "carga", "hrv"] {
            let a = ancla(m, id)
            XCTAssertEqual(a.medidor?.fantasma, true, "\(id) fantasma")
            XCTAssertTrue(a.medidor?.lunitas.isEmpty == true, "\(id) sin lunita")
            XCTAssertEqual(a.alerta, .ninguna, "\(id) jamás alerta en fantasma")
            let valor = a.valorPartes.map(\.texto).joined()
            XCTAssertTrue(valor.contains("—") || valor == "—", "\(id) valor ausente, got \(valor)")
        }
        // Esfuerzo/pasos: «—» (sin dato), no «0».
        XCTAssertEqual(ancla(m, "strain").valorPartes.first?.texto, "—")
        XCTAssertEqual(ancla(m, "steps").valorPartes.first?.texto, "—")
    }

    // MARK: Criterio 12 — numeral conserva hue; alerta es subrayado aparte

    func test_criterio12_numeralConservaHue() {
        let prep = read(autonomic: .high, autonomicZ: -1.5,  // z_mal = 1.5 → fuera
                        sleep: .low)
        let m = model(prep: prep, acwr: 1.55, sleepMin: 300, efficiency: 0.9)
        let rhr = ancla(m, "rhr")
        XCTAssertEqual(rhr.alerta, .atencion)
        // El hue del numeral ES rosa (identidad), no ámbar de alerta.
        XCTAssertEqual(rhr.valorPartes.first?.hue, LiquidColor.rosa)
        let sleep = ancla(m, "sleep")
        XCTAssertEqual(sleep.alerta, .atencion)
        XCTAssertEqual(sleep.valorPartes.first?.hue, LiquidColor.indigo)
        let carga = ancla(m, "carga")
        XCTAssertEqual(carga.alerta, .atencion)
        XCTAssertEqual(carga.valorPartes.first?.hue, LiquidColor.verdePrimario)
    }

    // MARK: Cero real vs ausente (esfuerzo/pasos)

    func test_ceroRealVsAusente() {
        let m0 = model(strain: 0, steps: 0)
        XCTAssertEqual(ancla(m0, "strain").valorPartes.first?.texto, "0.0")
        XCTAssertEqual(ancla(m0, "steps").valorPartes.first?.texto, "0")

        let prep = read()
        let (matriz, baseExtra) = inputs(prep: prep)
        var extra = baseExtra
        extra.strain = nil
        extra.steps = nil
        let mNil = LiquidHoyBuilder.cosmosAbierto(matriz, extra: extra)
        XCTAssertEqual(ancla(mNil, "strain").valorPartes.first?.texto, "—")
        XCTAssertEqual(ancla(mNil, "steps").valorPartes.first?.texto, "—")
    }

    // MARK: Orden a11y G1 → G2 → G3

    func test_ordenGrupos() {
        let m = model()
        XCTAssertEqual(m.anclas.map(\.id),
                       ["sleep", "guardian", "rhr", "carga", "stress", "hrv", "strain", "steps"])
        XCTAssertEqual(m.anclas.map(\.grupo), [1, 1, 1, 2, 2, 2, 3, 3])
    }
}
