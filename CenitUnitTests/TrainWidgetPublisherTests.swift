import XCTest
import StrandAnalytics
import StrandTraining
@testable import Cenit

// MARK: - TrainWidgetPublisherTests (FER-95 · E14)
//
// The pure half of what crosses the App Group to `TrainTodayWidget`/`WeekWidget`. What these defend:
//   1. `snapshot(...)` builds exactly what it's handed — no rest day invented when a routine is passed,
//      no routine invented when none is.
//   2. The week strip reuses `WeeklySplit.weekStates` verbatim (StrandAnalytics stays the one place that
//      decides done/today/upcoming/rest) via `TrainWidgetSnapshot.WeekDayState.init(_:)`.
//   3. The verdict's tone maps 1:1 from `LiquidHoyBuilder.HiloEntrenar.Tono` — the SAME four cases the
//      landing's hilo already resolves, never a fifth invented state.
//   4. `TrainWidgetSnapshot` round-trips through `JSONEncoder`/`JSONDecoder` — the actual wire contract
//      that crosses the app→extension process boundary (same discipline as `RestActivityFER789Tests`).
final class TrainWidgetPublisherTests: XCTestCase {

    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Mexico_City")!
        return c
    }()

    // MARK: - snapshot(...)

    func testSnapshotConRutinaLlevaHoyResuelto() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let s = TrainWidgetPublisher.snapshot(todayRoutineName: "Empuje", sessionLive: false,
                                              verdict: nil, week: [], now: now)
        XCTAssertEqual(s.today?.routineName, "Empuje")
        XCTAssertEqual(s.today?.sessionLive, false)
        XCTAssertEqual(s.writtenAt, now)
    }

    func testSnapshotSinRutinaEsDiaDeDescanso() {
        let s = TrainWidgetPublisher.snapshot(todayRoutineName: nil, sessionLive: false,
                                              verdict: nil, week: [], now: Date())
        XCTAssertNil(s.today)
    }

    func testSnapshotConSesionVivaLoLlevaAlPlan() {
        let s = TrainWidgetPublisher.snapshot(todayRoutineName: "Tirón", sessionLive: true,
                                              verdict: nil, week: [], now: Date())
        XCTAssertEqual(s.today?.sessionLive, true)
    }

    // MARK: - week(...)

    /// Lunes con rutina hecha, miércoles descanso, hoy (viernes) con rutina planeada aún no entrenada:
    /// el mapeo debe coincidir EXACTAMENTE con lo que `WeeklySplit.weekStates` ya decide.
    func testWeekReusaWeeklySplitVerbatim() {
        let split = [2: "push", 6: "pull"]   // lunes = push, viernes = pull
        let completadas: Set<Int> = [2]      // lunes ya entrenado
        let orden = [2, 3, 4, 5, 6, 7, 1]
        let labels = orden.map { "\($0)" }
        let week = TrainWidgetPublisher.week(split: split, completedWeekdays: completadas,
                                             todayWeekday: 6, orderedWeekdays: orden, labels: labels)
        let esperado = WeeklySplit.weekStates(split: split, completedWeekdays: completadas,
                                              todayWeekday: 6, orderedWeekdays: orden)
        XCTAssertEqual(week.count, esperado.count)
        for (a, b) in zip(week, esperado) {
            XCTAssertEqual(a.weekday, b.weekday)
            XCTAssertEqual(a.state, TrainWidgetSnapshot.WeekDayState(b.state))
        }
        // Lunes (índice 0) hecho, miércoles (índice 2, weekday 4) descanso, viernes (índice 4, hoy) hoy.
        XCTAssertEqual(week[0].state, .done)
        XCTAssertEqual(week[2].state, .rest)
        XCTAssertEqual(week[4].state, .today)
    }

    // MARK: - thisWeekCompletedWeekdays(...)

    func testThisWeekCompletedWeekdaysSoloCuentaLaSemanaActual() {
        // Lunes 17-ago-2026 08:00, y una sesión completada ESE mismo lunes.
        let lunes = cal.date(from: DateComponents(year: 2026, month: 8, day: 17, hour: 8, minute: 0))!
        let sesion = StrengthSession(routineId: "push",
                                     startTs: Int(lunes.timeIntervalSince1970), endTs: Int(lunes.timeIntervalSince1970) + 1800)
        let completadas = TrainWidgetPublisher.thisWeekCompletedWeekdays(sessions: [sesion], now: lunes, calendar: cal)
        XCTAssertEqual(completadas, [2])   // lunes
    }

    /// La semana se cuenta lunes→domingo aunque el locale empiece en domingo (es_MX/en_US): la
    /// sesión del domingo ANTERIOR no cae en la «D» del final de la tira (FER-128 r14).
    func testThisWeekCompletedWeekdaysSemanaEmpiezaEnLunesAunqueElLocaleNo() {
        var domingoPrimero = cal; domingoPrimero.firstWeekday = 1
        let sabado = domingoPrimero.date(from: DateComponents(year: 2026, month: 8, day: 22, hour: 10))!
        let domingoPasado = domingoPrimero.date(from: DateComponents(year: 2026, month: 8, day: 16, hour: 9))!
        let sesion = StrengthSession(routineId: "push",
                                     startTs: Int(domingoPasado.timeIntervalSince1970),
                                     endTs: Int(domingoPasado.timeIntervalSince1970) + 1800)
        let completadas = TrainWidgetPublisher.thisWeekCompletedWeekdays(sessions: [sesion], now: sabado, calendar: domingoPrimero)
        XCTAssertTrue(completadas.isEmpty, "el domingo 16 es de la semana pasada: \(completadas)")
        // …y el domingo PRÓXIMO (23) sí es de esta semana.
        let domingoProximo = domingoPrimero.date(from: DateComponents(year: 2026, month: 8, day: 23, hour: 9))!
        let s2 = StrengthSession(routineId: "push", startTs: Int(domingoProximo.timeIntervalSince1970),
                                 endTs: Int(domingoProximo.timeIntervalSince1970) + 1800)
        XCTAssertEqual(TrainWidgetPublisher.thisWeekCompletedWeekdays(sessions: [s2], now: sabado, calendar: domingoPrimero), [1])
    }

    func testThisWeekCompletedWeekdaysIgnoraSesionesSinTerminar() {
        let lunes = cal.date(from: DateComponents(year: 2026, month: 8, day: 17, hour: 8, minute: 0))!
        let sesion = StrengthSession(routineId: "push", startTs: Int(lunes.timeIntervalSince1970), endTs: nil)
        let completadas = TrainWidgetPublisher.thisWeekCompletedWeekdays(sessions: [sesion], now: lunes, calendar: cal)
        XCTAssertTrue(completadas.isEmpty)
    }

    // MARK: - Mapeo de tono (la resolución del veredicto a texto/tono)

    func testMapeoDeTonoCubreLosCuatroCasos() {
        XCTAssertEqual(TrainWidgetSnapshot.VerdictTone(.claro), .clear)
        XCTAssertEqual(TrainWidgetSnapshot.VerdictTone(.atencion), .caution)
        XCTAssertEqual(TrainWidgetSnapshot.VerdictTone(.alerta), .ease)
        XCTAssertEqual(TrainWidgetSnapshot.VerdictTone(.hueco), .hollow)
    }

    // MARK: - El contrato de cable (Codable a través del App Group)

    func testSnapshotRoundTripsThroughJSON() throws {
        let original = TrainWidgetSnapshot(
            writtenAt: Date(timeIntervalSince1970: 1_700_000_000),
            today: .init(routineName: "Empuje", sessionLive: true),
            verdict: .init(tone: .caution, word: "Hoy ve leve"),
            week: [.init(weekday: 2, state: .done, label: "L"), .init(weekday: 3, state: .rest, label: "M")])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TrainWidgetSnapshot.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testSnapshotSinHoyNiVeredictoRoundTrips() throws {
        let original = TrainWidgetSnapshot(writtenAt: Date(timeIntervalSince1970: 0), today: nil, verdict: nil, week: [])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TrainWidgetSnapshot.self, from: data)
        XCTAssertEqual(decoded, original)
        XCTAssertNil(decoded.today)
        XCTAssertNil(decoded.verdict)
    }

    // MARK: - Rancio

    func testIsStaleTrasElHorizonte() {
        let ahora = Date(timeIntervalSince1970: 1_700_000_000)
        let fresco = TrainWidgetSnapshot(writtenAt: ahora, today: nil, verdict: nil, week: [])
        XCTAssertFalse(fresco.isStale(asOf: ahora.addingTimeInterval(60)))

        let rancio = TrainWidgetSnapshot(writtenAt: ahora.addingTimeInterval(-TrainWidgetSnapshot.staleAfter - 1),
                                         today: nil, verdict: nil, week: [])
        XCTAssertTrue(rancio.isStale(asOf: ahora))
    }
}
