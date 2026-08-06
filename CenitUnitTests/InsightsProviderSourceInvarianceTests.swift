import XCTest
import CenitStore
import StrandAnalytics
@testable import Cenit

/// `InsightsProvider` (Patrones + «La conexión de hoy» del Daily Brief) y lo que su lente deja pasar.
///
/// Historia de este archivo, porque explica qué fija y qué no: nació en el mundo FER-639 (banda vs
/// Apple), se pudrió sin ejecutarse nunca (FER-49), y en FER-48 se reescribió otra vez cuando el gate
/// de ciencia cambió la política. Hoy fija la política VIGENTE:
///
/// · La lente es `clearBandHrv`: nila SOLO el HRV. Antes era `clearBandColumns`, que también nilaba
///   `restingHr` y `respRateBpm` — justo las columnas que sondea el detector de anomalías —, así que
///   NINGUNA anomalía de vital podía aflorar jamás. Era código vivo incapaz de producir nada.
/// · HRV sigue callado, y no por la fuente: Apple graba SDNN y la base está calibrada en RMSSD
///   (constructos distintos, sin conversión publicada). Su probe se BORRÓ del motor, no se enmascaró.
/// · Respiración sigue callada hasta que la ingesta se acote a la ventana de sueño (FER-52): hoy es un
///   promedio de día completo que mezcla sesiones de Respirar y entradas manuales.
/// · FC en reposo SÍ habla, sobre el último día CERRADO y contra una base madura (14 noches).
@MainActor
final class InsightsProviderSourceInvarianceTests: XCTestCase {

    private func key(_ i: Int) -> String { String(format: "2026-06-%02d", i) }

    private func dm(_ day: String, hrv: Double?, rhr: Int?, resp: Double? = 14,
                    recovery: Double? = 60) -> DailyMetric {
        DailyMetric(day: day, totalSleepMin: 420, efficiency: 0.9, deepMin: 90, remMin: 90,
                    lightMin: 240, disturbances: 2, restingHr: rhr, avgHrv: hrv, recovery: recovery,
                    strain: 10, exerciseCount: 1, spo2Pct: 97, skinTempDevC: 0.1, respRateBpm: resp)
    }

    /// 30 noches estables + hoy. El día 30 es el último CERRADO (hoy = 31, parcial).
    private func history(lastClosedRHR: Int = 52, lastClosedResp: Double = 14,
                         lastClosedHRV: Double = 50) -> (days: [DailyMetric], todayKey: String) {
        var days: [DailyMetric] = []
        for i in 1...29 { days.append(dm(key(i), hrv: 50, rhr: 52)) }
        days.append(dm(key(30), hrv: lastClosedHRV, rhr: lastClosedRHR, resp: lastClosedResp))
        days.append(dm(key(31), hrv: 50, rhr: 52))   // hoy, parcial
        return (days, key(31))
    }

    private func anomalias(_ xs: [Insight], _ metric: String) -> [Insight] {
        xs.filter { $0.kind == .nightAnomaly && $0.datum.metric == metric }
    }

    private func rank(_ days: [DailyMetric], today: String) -> [Insight] {
        InsightsProvider.rank(days: days, appleDays: [], behaviors: [:],
                              eligibleDaysByBehavior: [:], proven: [], today: today)
    }

    // MARK: Lo que el usuario SÍ puede ver ahora

    /// El caso que FER-48 vino a desbloquear: un salto real de FC en reposo aflora como anomalía.
    /// Antes de FER-48 esto era imposible por construcción.
    func testRestingHRJumpSurfacesAsAnomaly() {
        let (days, todayKey) = history(lastClosedRHR: 70)   // 70 contra una base de 52
        let out = anomalias(rank(days, today: todayKey), "FC en reposo")
        XCTAssertFalse(out.isEmpty, "un salto de 18 lpm sobre la base tiene que aflorar")
        // El copy no dice «anoche»: la FC en reposo de Apple es un promedio de día, no un dato nocturno.
        let reading = out.first?.reading ?? ""
        XCTAssertFalse(reading.lowercased().contains("anoche"),
                       "la FC en reposo de Apple NO es nocturna: el copy no puede decir «anoche»")
        XCTAssertFalse(reading.contains("z="), "el z es jerga: la desviación va en lpm")
    }

    /// Una FC en reposo en su base no dispara nada.
    func testRestingHRAtBaselineRaisesNothing() {
        let (days, todayKey) = history(lastClosedRHR: 52)
        XCTAssertTrue(anomalias(rank(days, today: todayKey), "FC en reposo").isEmpty)
    }

    // MARK: Lo que sigue callado A PROPÓSITO

    /// HRV no habla aunque el dato exista y se salga: su probe se borró del motor.
    func testHRVNeverSurfaces() {
        let (days, todayKey) = history(lastClosedHRV: 120)   // SDNN muy fuera de base
        XCTAssertTrue(anomalias(rank(days, today: todayKey), "HRV").isEmpty,
                      "Apple graba SDNN y la base es de RMSSD: el probe se borró, no se enmascaró")
    }

    /// Respiración tampoco, hasta que la ingesta se acote a la ventana de sueño (FER-52).
    func testRespirationNeverSurfacesYet() {
        let (days, todayKey) = history(lastClosedResp: 25)   // muy fuera de una base de 14
        XCTAssertTrue(anomalias(rank(days, today: todayKey), "Respiración").isEmpty,
                      "la ingesta mezcla sesiones de Respirar y entradas manuales: aún no es honesto")
    }

    // MARK: Los candados que hacen honesta a la que sí habla

    /// El día de REFERENCIA (hoy) no se juzga: Apple sigue refinando su FC en reposo durante el día,
    /// así que un valor parcial no se compara contra una base de días completos.
    func testTodayIsNotJudged() {
        var days: [DailyMetric] = []
        for i in 1...30 { days.append(dm(key(i), hrv: 50, rhr: 52)) }
        days.append(dm(key(31), hrv: 50, rhr: 70))   // el salto está SOLO en hoy (parcial)
        XCTAssertTrue(anomalias(rank(days, today: key(31)), "FC en reposo").isEmpty,
                      "hoy es parcial: no se juzga")
    }

    /// Con base tierna no se declara nada anómalo: con pocas noches el propio spread es ruido, así que
    /// el z no tiene denominador calibrado. Se exigen 14 noches (`minNightsTrust`), no 4.
    func testThinBaselineStaysQuiet() {
        var days: [DailyMetric] = []
        for i in 1...6 { days.append(dm(key(i), hrv: 50, rhr: 52)) }   // 5 cerradas: provisional, no trusted
        days.append(dm(key(7), hrv: 50, rhr: 70))
        XCTAssertTrue(anomalias(rank(days, today: key(7)), "FC en reposo").isEmpty,
                      "una base provisional no puede declarar una anomalía")
    }

    /// `appleDays` ya no selecciona nada (todo es Apple): pasarlo lleno o vacío da lo mismo.
    func testAppleDaysArgumentNoLongerChangesAnything() {
        let (days, todayKey) = history(lastClosedRHR: 70)
        let sin = rank(days, today: todayKey)
        let con = InsightsProvider.rank(days: days, appleDays: Set(days.map(\.day)), behaviors: [:],
                                        eligibleDaysByBehavior: [:], proven: [], today: todayKey)
        XCTAssertEqual(sin.map(\.title), con.map(\.title))
    }
}
