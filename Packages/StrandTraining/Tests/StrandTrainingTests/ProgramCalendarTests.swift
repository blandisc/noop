import XCTest
@testable import StrandTraining

/// Ola 1 · E10 (FER-329): la semana del programa es DERIVADA. Estas pruebas fijan el reloj y el
/// calendario por parámetro, así que no dependen de la fecha en que corren.
final class ProgramCalendarTests: XCTestCase {

    /// Calendario reproducible: GMT y es-MX, para que «lunes» sea lunes en cualquier máquina.
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "GMT")!
        c.locale = Locale(identifier: "es_MX")
        return c
    }()

    private func date(_ iso: String) -> Date {
        let f = DateFormatter()
        f.calendar = cal
        f.timeZone = cal.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: iso)!
    }

    private func ts(_ iso: String) -> Int { Int(date(iso).timeIntervalSince1970) }

    private func mondays(_ isos: [String]) -> Set<Int> {
        ProgramCalendar.trainedWeekStarts(sessionStartTs: isos.map(ts), calendar: cal)
    }

    // 2026-01-06 es MARTES; su lunes es 2026-01-05.
    func testStartsMidWeekAndThatWeekIsWeekOne() {
        let p = ProgramCalendar.position(startTs: ts("2026-01-06 19:00"), trainedWeekStarts: [],
                                         now: date("2026-01-08 07:00"), weeks: 5, calendar: cal)
        XCTAssertEqual(p.week, 1)
        XCTAssertEqual(p.cycle, 0)
        XCTAssertFalse(p.isLight)
        XCTAssertEqual(p.weeksUntilLight, 4)
        XCTAssertFalse(p.ended)
    }

    func testTheCurrentWeekNeverCountsItself() {
        // Se entrenó HOY (misma semana). La semana sigue siendo la 1: contar la semana en curso haría
        // que el programa avanzara a media semana, con la primera sesión.
        let p = ProgramCalendar.position(startTs: ts("2026-01-06 19:00"),
                                         trainedWeekStarts: mondays(["2026-01-08 07:00"]),
                                         now: date("2026-01-09 07:00"), weeks: 5, calendar: cal)
        XCTAssertEqual(p.week, 1)
    }

    func testThreeTrainedWeeksMakeItWeekFour() {
        let p = ProgramCalendar.position(
            startTs: ts("2026-01-06 19:00"),
            trainedWeekStarts: mondays(["2026-01-08 07:00", "2026-01-13 07:00", "2026-01-20 07:00"]),
            now: date("2026-01-28 07:00"), weeks: 5, calendar: cal)
        XCTAssertEqual(p.week, 4)
        XCTAssertEqual(p.cycle, 0)
        XCTAssertFalse(p.isLight)
        XCTAssertEqual(p.weeksUntilLight, 1)
    }

    func testABlankWeekDoesNotAdvanceTheCounter() {
        // Mismas fechas que arriba pero la semana del 20 quedó en blanco: la semana ligera ESPERA.
        let trained = mondays(["2026-01-08 07:00", "2026-01-13 07:00"])
        let p = ProgramCalendar.position(startTs: ts("2026-01-06 19:00"), trainedWeekStarts: trained,
                                         now: date("2026-01-28 07:00"), weeks: 5, calendar: cal)
        XCTAssertEqual(p.week, 3, "una semana en blanco no puede adelantar el programa (D-Q2)")
    }

    func testTheLastWeekOfTheCycleIsTheLightOne() {
        let trained = mondays(["2026-01-08 07:00", "2026-01-13 07:00", "2026-01-20 07:00",
                               "2026-01-27 07:00"])
        let p = ProgramCalendar.position(startTs: ts("2026-01-06 19:00"), trainedWeekStarts: trained,
                                         now: date("2026-02-03 07:00"), weeks: 5, calendar: cal)
        XCTAssertEqual(p.week, 5)
        XCTAssertTrue(p.isLight)
        XCTAssertEqual(p.weeksUntilLight, 0)
    }

    func testNoDeloadRuleMeansNoLightWeekEvenOnTheLastOne() {
        let trained = mondays(["2026-01-08 07:00", "2026-01-13 07:00", "2026-01-20 07:00",
                               "2026-01-27 07:00"])
        let p = ProgramCalendar.position(startTs: ts("2026-01-06 19:00"), trainedWeekStarts: trained,
                                         now: date("2026-02-03 07:00"), weeks: 5,
                                         deloadRule: .none, calendar: cal)
        XCTAssertEqual(p.week, 5)
        XCTAssertFalse(p.isLight)
    }

    private func fiveTrainedWeeks() -> Set<Int> {
        mondays(["2026-01-08 07:00", "2026-01-13 07:00", "2026-01-20 07:00",
                 "2026-01-27 07:00", "2026-02-03 07:00"])
    }

    func testRepeatRestartsAtWeekOneOfCycleTwo() {
        let p = ProgramCalendar.position(startTs: ts("2026-01-06 19:00"),
                                         trainedWeekStarts: fiveTrainedWeeks(),
                                         now: date("2026-02-10 07:00"), weeks: 5,
                                         endMode: .repeat, calendar: cal)
        XCTAssertEqual(p.cycle, 1, "cycle es base 0: 1 = «ciclo 2»")
        XCTAssertEqual(p.week, 1)
        XCTAssertFalse(p.ended)
        XCTAssertFalse(p.isLight)
    }

    func testSingleEndsTheProgramWhenTheCycleCloses() {
        let p = ProgramCalendar.position(startTs: ts("2026-01-06 19:00"),
                                         trainedWeekStarts: fiveTrainedWeeks(),
                                         now: date("2026-02-10 07:00"), weeks: 5,
                                         endMode: .single, calendar: cal)
        XCTAssertTrue(p.ended)
        XCTAssertFalse(p.isLight, "terminado = queda la semana normal, nunca la ligera")
        XCTAssertEqual(p.weeksUntilLight, 0)
    }

    func testYearBoundary() {
        // 2025-12-29 es lunes; 2026-01-05 es el lunes siguiente. Contar por número de semana del año
        // (52 → 1) daría una diferencia negativa; contar por el lunes en segundos no.
        let p = ProgramCalendar.position(startTs: ts("2025-12-29 07:00"),
                                         trainedWeekStarts: mondays(["2025-12-30 07:00"]),
                                         now: date("2026-01-06 07:00"), weeks: 5, calendar: cal)
        XCTAssertEqual(p.cycle, 0)
        XCTAssertEqual(p.week, 2, "la semana entrenada del 29-dic cuenta para la del 5-ene")
    }

    func testWeeksTrainedBeforeTheProgramStartedDoNotCount() {
        let p = ProgramCalendar.position(startTs: ts("2026-01-06 19:00"),
                                         trainedWeekStarts: mondays(["2025-12-30 07:00"]),
                                         now: date("2026-01-13 07:00"), weeks: 5, calendar: cal)
        XCTAssertEqual(p.week, 1, "el historial anterior al programa no adelanta su semana")
    }

    func testPositionOfProgramReadsTheStoredRule() {
        let program = Program(name: "P", weeks: 5, startTs: ts("2026-01-06 19:00"),
                              deloadRule: .volumeAndLoad, endMode: .single, createdTs: 0)
        let p = ProgramCalendar.position(of: program, trainedWeekStarts: fiveTrainedWeeks(),
                                         now: date("2026-02-10 07:00"), calendar: cal)
        XCTAssertTrue(p.ended)
    }
}
