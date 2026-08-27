import XCTest
@testable import StrandTraining

final class TrainingWeeksTests: XCTestCase {

    /// UTC fijo — nada de `TimeZone.current`, para que el test sea el mismo en cualquier máquina.
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 2
        return c
    }()

    // MARK: - volumeBuckets

    func testVolumeBucketsWeekBoundaryMondayFirst() {
        // Ancla: el lunes 00:00 de una semana cualquiera, derivado del calendario (no adivinado
        // a mano) para no depender de acertar qué día cae en qué fecha.
        let ref = cal.date(from: DateComponents(year: 2026, month: 3, day: 20))!
        let mondayThisWeek = cal.dateInterval(of: .weekOfYear, for: ref)!.start
        let now = cal.date(byAdding: .hour, value: 12, to: mondayThisWeek)!

        let sundayBefore2359 = cal.date(byAdding: .second, value: -60, to: mondayThisWeek)!  // domingo 23:59
        let mondayAfter0001 = cal.date(byAdding: .minute, value: 1, to: mondayThisWeek)!     // lunes 00:01

        let sessions: [(ts: Double, volumeKg: Double)] = [
            (sundayBefore2359.timeIntervalSince1970, 100),
            (mondayAfter0001.timeIntervalSince1970, 200),
        ]
        let buckets = TrainingWeeks.volumeBuckets(sessions: sessions, weeks: 2, now: now, calendar: cal)
        XCTAssertEqual(buckets.count, 2)
        XCTAssertEqual(buckets[0].volumeKg, 100, "domingo 23:59 cae en la semana ANTERIOR")
        XCTAssertEqual(buckets[1].volumeKg, 200, "lunes 00:01 cae en la semana ACTUAL")
        XCTAssertFalse(buckets[0].isCurrent)
        XCTAssertTrue(buckets[1].isCurrent)
    }

    func testVolumeBucketsExactCountWithZeroGapsAndSingleCurrent() {
        let ref = cal.date(from: DateComponents(year: 2026, month: 6, day: 1))!
        let now = cal.dateInterval(of: .weekOfYear, for: ref)!.start.addingTimeInterval(3600)
        let buckets = TrainingWeeks.volumeBuckets(sessions: [], weeks: 8, now: now, calendar: cal)
        XCTAssertEqual(buckets.count, 8)
        XCTAssertTrue(buckets.allSatisfy { $0.volumeKg == 0 && $0.sessionCount == 0 })
        XCTAssertEqual(buckets.filter(\.isCurrent).count, 1)
        XCTAssertTrue(buckets.last!.isCurrent)
    }

    // MARK: - volumeDeltaPercent

    func testVolumeDeltaPercentNilWithFewerThan4CompleteWeeks() {
        // 3 cubetas totales → solo 2 completas (la última es la actual, en curso) → nil.
        let buckets = (0..<3).map { i in
            WeekVolumeBucket(weekStart: Date(timeIntervalSince1970: Double(i) * 604_800),
                             volumeKg: 10, sessionCount: 1, isCurrent: i == 2)
        }
        XCTAssertNil(TrainingWeeks.volumeDeltaPercent(buckets: buckets))
    }

    func testVolumeDeltaPercentWith5Buckets() {
        // 5 cubetas → 4 completas [9, 10, 11, 12] + la actual (su volumen no cuenta).
        // última completa 12.0 vs promedio(9,10,11)=10.0 → (12-10)/10*100 = +20.
        let volumes: [Double] = [9, 10, 11, 12, 999]
        let buckets = volumes.enumerated().map { i, v in
            WeekVolumeBucket(weekStart: Date(timeIntervalSince1970: Double(i) * 604_800), volumeKg: v,
                             sessionCount: 1, isCurrent: i == volumes.count - 1)
        }
        XCTAssertEqual(TrainingWeeks.volumeDeltaPercent(buckets: buckets), 20)
    }

    func testVolumeDeltaPercentNilWhenPreviousThreeSumToZero() {
        let volumes: [Double] = [0, 0, 0, 5, 999]
        let buckets = volumes.enumerated().map { i, v in
            WeekVolumeBucket(weekStart: Date(timeIntervalSince1970: Double(i) * 604_800), volumeKg: v,
                             sessionCount: v > 0 ? 1 : 0, isCurrent: i == volumes.count - 1)
        }
        XCTAssertNil(TrainingWeeks.volumeDeltaPercent(buckets: buckets))
    }

    // MARK: - consistency

    func testConsistencyTruncatesToSlotsPerWeekChronologicallyAndKeepsNil() {
        let ref = cal.date(from: DateComponents(year: 2026, month: 3, day: 20))!
        let weekStart = cal.dateInterval(of: .weekOfYear, for: ref)!.start
        let now = weekStart.addingTimeInterval(12 * 3600)

        let ts0 = weekStart.addingTimeInterval(1 * 3600).timeIntervalSince1970
        let ts1 = weekStart.addingTimeInterval(2 * 3600).timeIntervalSince1970
        let ts2 = weekStart.addingTimeInterval(3 * 3600).timeIntervalSince1970
        let ts3 = weekStart.addingTimeInterval(4 * 3600).timeIntervalSince1970
        let ts4 = weekStart.addingTimeInterval(5 * 3600).timeIntervalSince1970

        // Deliberadamente fuera de orden cronológico en el input — el motor debe ordenar por ts.
        let sessions: [(ts: Double, family: RoutineRegion?)] = [
            (ts3, .fullBody), (ts0, .push), (ts4, .legs), (ts1, .pull), (ts2, nil),
        ]
        let result = TrainingWeeks.consistency(sessions: sessions, weeks: 1, slotsPerWeek: 3,
                                                now: now, calendar: cal)
        XCTAssertEqual(result.count, 1)
        // 5 sesiones recortadas a 3, las primeras cronológicamente: ts0, ts1, ts2 → push, pull, nil.
        XCTAssertEqual(result[0].sessions, [.push, .pull, nil])
        XCTAssertTrue(result[0].isCurrent)
    }

    func testConsistencyOldestColumnFirst() {
        let ref = cal.date(from: DateComponents(year: 2026, month: 3, day: 20))!
        let weekStart = cal.dateInterval(of: .weekOfYear, for: ref)!.start
        let now = weekStart.addingTimeInterval(12 * 3600)

        let thisWeekTs = weekStart.addingTimeInterval(3600).timeIntervalSince1970
        let twoWeeksAgoStart = cal.date(byAdding: .weekOfYear, value: -2, to: weekStart)!
        let twoWeeksAgoTs = twoWeeksAgoStart.addingTimeInterval(3600).timeIntervalSince1970

        let sessions: [(ts: Double, family: RoutineRegion?)] = [
            (thisWeekTs, .legs), (twoWeeksAgoTs, .push),
        ]
        let result = TrainingWeeks.consistency(sessions: sessions, weeks: 3, slotsPerWeek: 3,
                                                now: now, calendar: cal)
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result[0].sessions, [.push], "columna izquierda = la más vieja de las 3")
        XCTAssertEqual(result[1].sessions, [])
        XCTAssertEqual(result[2].sessions, [.legs], "columna derecha = la semana actual")
        XCTAssertFalse(result[0].isCurrent)
        XCTAssertTrue(result[2].isCurrent)
    }

    // MARK: - sessionsThisMonth

    func testSessionsThisMonthExcludesLastMonthCountsToday() {
        let now = cal.date(from: DateComponents(year: 2026, month: 3, day: 15, hour: 12))!
        let today = cal.date(from: DateComponents(year: 2026, month: 3, day: 15, hour: 8))!
        let lastMonth = cal.date(from: DateComponents(year: 2026, month: 2, day: 20, hour: 8))!
        let count = TrainingWeeks.sessionsThisMonth(
            sessionTs: [today.timeIntervalSince1970, lastMonth.timeIntervalSince1970],
            now: now, calendar: cal)
        XCTAssertEqual(count, 1)
    }

    // MARK: - sevenDayAverage

    func testSevenDayAverageNilWithFewerThan3Sessions() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let sessions: [(ts: Double, durationS: Double, volumeKg: Double, kcal: Double?)] = [
            (now.timeIntervalSince1970 - 3600, 1800, 1000, 300),
            (now.timeIntervalSince1970 - 7200, 2400, 1500, nil),
        ]
        XCTAssertNil(TrainingWeeks.sevenDayAverage(sessions: sessions, now: now))
    }

    func testSevenDayAverageKcalNilWhenNoneCarryEnergy() throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let sessions: [(ts: Double, durationS: Double, volumeKg: Double, kcal: Double?)] = [
            (now.timeIntervalSince1970 - 3600, 1800, 1000, nil),
            (now.timeIntervalSince1970 - 7200, 2400, 1500, nil),
            (now.timeIntervalSince1970 - 10800, 3000, 2000, nil),
        ]
        let avg = try XCTUnwrap(TrainingWeeks.sevenDayAverage(sessions: sessions, now: now))
        XCTAssertNil(avg.kcal)
    }

    func testSevenDayAverageRoundingsAndPartialKcal() throws {
        // duraciones 1800/2400/3000 s → prom 2400 s = 40 min exacto.
        // volumen 1000/1500/2000 kg → prom 1500 kg = 1.5 t.
        // kcal 300/400/nil → promedio SOLO de las 2 con dato: (300+400)/2 = 350 (no cuenta la nil como 0).
        let now = Date(timeIntervalSince1970: 1_000_000)
        let sessions: [(ts: Double, durationS: Double, volumeKg: Double, kcal: Double?)] = [
            (now.timeIntervalSince1970 - 3600, 1800, 1000, 300),
            (now.timeIntervalSince1970 - 7200, 2400, 1500, 400),
            (now.timeIntervalSince1970 - 10800, 3000, 2000, nil),
        ]
        let avg = try XCTUnwrap(TrainingWeeks.sevenDayAverage(sessions: sessions, now: now))
        XCTAssertEqual(avg.minutes, 40)
        XCTAssertEqual(avg.kcal, 350)
        XCTAssertEqual(avg.tons, 1.5, accuracy: 0.0001)
    }

    func testSevenDayAverageExcludesSessionsOutsideWindow() throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let justInside = now.timeIntervalSince1970 - 7 * 86_400 + 1
        let justOutside = now.timeIntervalSince1970 - 7 * 86_400 - 1
        let sessions: [(ts: Double, durationS: Double, volumeKg: Double, kcal: Double?)] = [
            (justInside, 1800, 1000, 300),
            (now.timeIntervalSince1970 - 3600, 1800, 1000, 300),
            (now.timeIntervalSince1970 - 7200, 1800, 1000, 300),
            (justOutside, 1800, 999_999, 999),   // debe quedar fuera de la ventana
        ]
        let avg = try XCTUnwrap(TrainingWeeks.sevenDayAverage(sessions: sessions, now: now))
        XCTAssertEqual(avg.tons, 1.0, accuracy: 0.0001, "si contara la sesión de afuera, esto no daría 1.0")
    }
}
