import XCTest
import StrandTraining
@testable import Cenit

/// FER-973 (T-04) — `TrainingStreak`, the single source both Entrenar and the Daily Brief's
/// «Hoy en tu plan» read. Pins: local-day attribution of sessions (late-evening sessions land on
/// their local day), rest days riding through the streak, and a missed training day cutting it.
final class TrainingStreakTests: XCTestCase {

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Mexico_City")!
        return c
    }

    /// A completed session starting at `hour` local on the day `daysAgo` before `now`.
    private func session(daysAgo: Int, hour: Int, now: Date, cal: Calendar, id: String) -> StrengthSession {
        let day = cal.date(byAdding: .day, value: -daysAgo, to: cal.startOfDay(for: now))!
        let start = Int(cal.date(bySettingHour: hour, minute: 30, second: 0, of: day)!.timeIntervalSince1970)
        return StrengthSession(id: id, startTs: start, endTs: start + 3600)
    }

    /// Mon/Wed/Fri split in Calendar weekday convention (1 = Sun … 7 = Sat).
    private let split: [Int: String] = [2: "push", 4: "pull", 6: "legs"]

    func testStreakCountsFulfilledTrainingDaysAndRestDaysRideThrough() {
        let cal = self.cal
        // Anchor "now" on a Friday noon so the recent window shape is deterministic.
        var comps = DateComponents(); comps.year = 2026; comps.month = 7; comps.day = 10; comps.hour = 12
        comps.timeZone = cal.timeZone
        let now = cal.date(from: comps)!
        XCTAssertEqual(cal.component(.weekday, from: now), 6, "precondition: it's a Friday")

        // Fulfilled Mon (4 days ago), Wed (2 days ago) and today Fri — a full plan week.
        let sessions = [
            session(daysAgo: 4, hour: 19, now: now, cal: cal, id: "mon"),
            session(daysAgo: 2, hour: 23, now: now, cal: cal, id: "wed-late"),  // 23:30 local still Wednesday
            session(daysAgo: 0, hour: 7, now: now, cal: cal, id: "fri"),
        ]
        // El calendario se INYECTA: las fechas se arman en CDMX, así que el bucketeo por día local
        // tiene que usar ese mismo calendario. Sin esto la prueba pasaba en CDMX y fallaba en UTC
        // (la sesión de 19:30 cae al día siguiente y parte la racha) — lo cazó CI (FER-50).
        let streak = TrainingStreak.streak(sessions: sessions, split: split, now: now, calendar: cal)
        XCTAssertGreaterThanOrEqual(streak, 3, "Mon+Wed+Fri fulfilled — rest days must not cut the run")
    }

    func testMissedTrainingDayCutsTheStreak() {
        let cal = self.cal
        var comps = DateComponents(); comps.year = 2026; comps.month = 7; comps.day = 10; comps.hour = 12
        comps.timeZone = cal.timeZone
        let now = cal.date(from: comps)!

        // Wednesday (a plan day, 2 days ago) has NO session; Mon and Fri do.
        let sessions = [
            session(daysAgo: 4, hour: 19, now: now, cal: cal, id: "mon"),
            session(daysAgo: 0, hour: 7, now: now, cal: cal, id: "fri"),
        ]
        let streak = TrainingStreak.streak(sessions: sessions, split: split, now: now, calendar: cal)
        // La racha cuenta DÍAS cumplidos, no días de entreno: el jueves es descanso del plan y cuenta
        // igual que el viernes entrenado (es la misma regla que fija `testStreak…RestDaysRideThrough`,
        // y está documentada en `WeeklySplit.adherenceStreak`). Así que el miércoles fallado corta en
        // 2, no en 1. La expectativa original decía 1 porque se escribió sin correr nunca la prueba.
        XCTAssertEqual(streak, 2, "el miércoles fallado corta la racha: solo sobreviven jueves (descanso) y viernes")
    }

    func testLateEveningSessionLandsOnItsLocalDay() {
        let cal = self.cal
        var comps = DateComponents(); comps.year = 2026; comps.month = 7; comps.day = 8; comps.hour = 12
        comps.timeZone = cal.timeZone
        let now = cal.date(from: comps)!
        let s = session(daysAgo: 0, hour: 23, now: now, cal: cal, id: "late")
        let done = TrainingStreak.completedDayStarts([s], calendar: cal)
        XCTAssertEqual(done, [cal.startOfDay(for: now)],
                       "23:30 local is the SAME local day (a UTC bucketing would misfile it)")
    }

    /// Sin plan no hay racha. Antes salía `windowDays` (120): sin días asignados, cada día contaba
    /// como «descanso cumplido», y el tope de la ventana se presentaba como logro a quien nunca
    /// configuró un plan.
    func testEmptySplitHasNoStreak() {
        XCTAssertEqual(TrainingStreak.streak(sessions: [], split: [:], now: Date(), calendar: cal), 0)
        // Y tampoco aparece por tener sesiones sueltas sin plan que las respalde.
        let suelta = session(daysAgo: 0, hour: 7, now: Date(), cal: cal, id: "suelta")
        XCTAssertEqual(TrainingStreak.streak(sessions: [suelta], split: [:], now: Date(), calendar: cal), 0)
    }
}
