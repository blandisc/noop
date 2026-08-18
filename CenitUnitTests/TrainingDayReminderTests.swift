import XCTest
@testable import Cenit

// MARK: - TrainingDayReminderTests (FER-95 · E14)
//
// `TrainingDayReminder.plan` decides WHEN to remind — pure, no `UNUserNotificationCenter`, mirroring
// `MorningReadingSchedulerTests`'s split of pure decision / thin effect layer. Three things it defends:
//   1. Apagado, o sin split, siempre da plan vacío — nunca un aviso que nadie pidió o de un día sin
//      rutina.
//   2. Encendido con split da una ocurrencia por cada día asignado dentro del horizonte, con el
//      NOMBRE de la rutina ya congelado (nunca un veredicto: el aviso no lo conoce).
//   3. La hora ya pasada HOY no reprograma para hoy — la primera ocurrencia real es la de mañana.
final class TrainingDayReminderTests: XCTestCase {

    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Mexico_City")!
        return c
    }()

    private func fecha(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    /// 2026-08-17 es lunes.
    private let lunes0800 = { () -> Date in
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Mexico_City")!
        return c.date(from: DateComponents(year: 2026, month: 8, day: 17, hour: 8, minute: 0))!
    }()

    /// weekday: 1=domingo … 7=sábado (convención de `Calendar`). 17-ago-2026 = lunes = 2.
    private let splitLunesYMiercoles = [2: "push", 4: "pull"]
    private let nombres = ["push": "Empuje", "pull": "Tirón"]

    func testApagadoDaPlanVacio() {
        let plan = TrainingDayReminder.plan(split: splitLunesYMiercoles, routineNames: nombres,
                                            enabled: false, hour: 7, minute: 0, now: lunes0800, calendar: cal)
        XCTAssertTrue(plan.isEmpty)
    }

    func testSinSplitDaPlanVacio() {
        let plan = TrainingDayReminder.plan(split: [:], routineNames: [:],
                                            enabled: true, hour: 7, minute: 0, now: lunes0800, calendar: cal)
        XCTAssertTrue(plan.isEmpty)
    }

    /// Encendido con split: una ocurrencia por cada día asignado dentro del horizonte, con la rutina
    /// congelada. `lunes0800` ya pasó la hora 7:00 de HOY, así que la primera ocurrencia del lunes cae
    /// la SIGUIENTE semana, no hoy.
    func testEncendidoConSplitDaUnaOcurrenciaPorDiaAsignado() {
        let plan = TrainingDayReminder.plan(split: splitLunesYMiercoles, routineNames: nombres,
                                            enabled: true, hour: 7, minute: 0, now: lunes0800,
                                            calendar: cal, dias: TrainingDayReminder.horizonteDias)
        // Dentro de los próximos 7 días de calendario (lunes incluido) el split solo marca miércoles
        // (el lunes de HOY ya pasó su 7:00): una sola ocurrencia.
        XCTAssertEqual(plan.count, 1)
        XCTAssertEqual(plan.first?.routineName, "Tirón")
        let comps = cal.dateComponents([.weekday, .hour, .minute], from: plan[0].fecha)
        XCTAssertEqual(comps.weekday, 4)   // miércoles
        XCTAssertEqual(comps.hour, 7)
    }

    /// Una hora que TODAVÍA no ha pasado hoy SÍ arma el aviso de hoy mismo.
    func testHoyTodaviaNoPasaLaHoraArmaHoy() {
        let plan = TrainingDayReminder.plan(split: splitLunesYMiercoles, routineNames: nombres,
                                            enabled: true, hour: 20, minute: 0, now: lunes0800, calendar: cal)
        XCTAssertEqual(plan.first?.routineName, "Empuje")
        let comps = cal.dateComponents([.weekday], from: plan[0].fecha)
        XCTAssertEqual(comps.weekday, 2)   // lunes de hoy
    }

    /// El nombre de la rutina viaja en el título/cuerpo, y NUNCA el veredicto (no hay parámetro para
    /// pasarlo — la firma misma lo prohíbe).
    func testElContenidoNombraLaRutinaSinVeredicto() {
        let texto = TrainingDayReminder.contenido(routineName: "Empuje")
        XCTAssertTrue(texto.cuerpo.contains("Empuje"))
    }

    /// Split incompleto: un weekday apunta a un id sin nombre resuelto (rutina borrada) — ese día se
    /// salta en vez de programar un aviso con un nombre vacío.
    func testDiaConRutinaSinNombreSeSalta() {
        let plan = TrainingDayReminder.plan(split: [2: "borrada"],
                                            routineNames: [:], enabled: true, hour: 20, minute: 0,
                                            now: lunes0800, calendar: cal)
        XCTAssertTrue(plan.isEmpty)
    }
}
