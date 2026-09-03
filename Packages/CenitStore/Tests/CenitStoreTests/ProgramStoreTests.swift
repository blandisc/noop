import XCTest
@testable import CenitStore
import StrandTraining

/// Ola 1 · E10 (FER-329): la fila `program` (v43) y las exclusiones de la semana ligera.
final class ProgramStoreTests: XCTestCase {

    private func routine(_ store: CenitStore) async throws {
        let r = Routine(id: "rt1", name: "Pierna", createdTs: 0, updatedTs: 0)
        let re = RoutineExercise(id: "re1", routineId: "rt1", exerciseId: "ex1", position: 0,
                                 targetSets: 4, targetReps: 8,
                                 sets: (0..<4).map { RoutineSet(id: "s\($0)", position: $0, kind: .work,
                                                                reps: 8, weightKg: 100) })
        try await store.saveRoutine(r, exercises: [re])
    }

    private func session(_ store: CenitStore, id: String, startTs: Int, kg: Double,
                         deload: Bool? = nil, programWeek: Int? = nil) async throws {
        let s = StrengthSession(id: id, routineId: "rt1", startTs: startTs, endTs: startTs + 3_600,
                                programWeek: programWeek, deload: deload)
        let sets = (0..<2).map { i in
            SetEntry(id: "\(id)-\(i)", sessionId: id, exerciseId: "ex1", position: i, kind: .work,
                     weightKg: kg, reps: 8, done: true, ts: startTs + i * 60)
        }
        try await store.saveSession(s, sets: sets)
    }

    // MARK: - CRUD del programa

    func testProgramCRUD() async throws {
        let store = try await CenitStore.inMemory()
        let none = try await store.program()
        XCTAssertNil(none, "sin programa, no hay fila")

        let p = Program(name: "Lineal", weeks: 5, startTs: 1_000, deloadRule: .volumeAndLoad,
                        endMode: .single, templateId: "linear-novice", createdTs: 900)
        try await store.setProgram(p)
        let back = try await store.program()
        XCTAssertEqual(back, p)

        // Cambiar de programa es un upsert sobre el mismo id: sigue habiendo UNO.
        var other = p
        other.name = "PPL"
        other.weeks = 6
        other.deloadRule = .volumeOnly
        other.endMode = .repeat
        other.templateId = "ppl-6"
        other.startTs = 2_000
        try await store.setProgram(other)
        let reread = try await store.program()
        XCTAssertEqual(reread, other)

        try await store.deleteProgram()
        let gone = try await store.program()
        XCTAssertNil(gone)
    }

    func testEndingTheProgramLeavesRoutinesAndScheduleIntact() async throws {
        let store = try await CenitStore.inMemory()
        try await routine(store)
        try await store.setRoutineSchedule(weekday: 2, routineId: "rt1")
        try await store.setProgram(Program(name: "P", weeks: 5, startTs: 0, createdTs: 0))

        try await store.deleteProgram()
        let after = try await store.program()
        let routines = try await store.routines()
        let schedule = try await store.routineSchedule()
        XCTAssertNil(after)
        XCTAssertEqual(routines.map(\.id), ["rt1"])
        XCTAssertEqual(schedule.map(\.weekday), [2])
    }

    // MARK: - La semana ligera nunca toca el plan guardado

    func testSavingALightWeekSessionDoesNotTouchTheRoutinePlan() async throws {
        let store = try await CenitStore.inMemory()
        try await routine(store)
        let before = try await store.routineExercises(routineId: "rt1")

        // La sesión se sirvió ligera: 2 series (de 4) a −7,5 %. Se guarda tal cual se hizo…
        try await session(store, id: "s-light", startTs: 10_000, kg: 92.5,
                          deload: true, programWeek: 5)

        let after = try await store.routineExercises(routineId: "rt1")
        XCTAssertEqual(before, after, "el plan guardado queda idéntico, serie por serie")
        // … y byte a byte sobre el JSON del plan, por si un día `Equatable` deja de mirar algún campo.
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        XCTAssertEqual(try enc.encode(before.map(\.sets)), try enc.encode(after.map(\.sets)))
        XCTAssertEqual(after.first?.sets.count, 4)
        XCTAssertEqual(after.first?.sets.map(\.weightKg), [100, 100, 100, 100])
    }

    func testProgramWeekAndDeloadRoundTripOnTheSessionRow() async throws {
        let store = try await CenitStore.inMemory()
        try await routine(store)
        try await session(store, id: "s1", startTs: 10_000, kg: 92.5, deload: true, programWeek: 5)
        try await session(store, id: "s2", startTs: 20_000, kg: 100)

        let rows = try await store.recentSessions()
        let light = rows.first { $0.id == "s1" }
        XCTAssertEqual(light?.deload, true)
        XCTAssertEqual(light?.programWeek, 5)
        let plain = rows.first { $0.id == "s2" }
        XCTAssertNil(plain?.deload, "sin programa la columna sigue NULL, no un false inventado")
        XCTAssertNil(plain?.programWeek)
    }

    // MARK: - Exclusiones

    func testLastWorkSetsIgnoresTheLightWeek() async throws {
        let store = try await CenitStore.inMemory()
        try await routine(store)
        try await session(store, id: "s-normal", startTs: 10_000, kg: 100)
        try await session(store, id: "s-light", startTs: 20_000, kg: 92.5, deload: true, programWeek: 5)

        let last = try await store.lastWorkSets(exerciseId: "ex1")
        XCTAssertFalse(last.isEmpty)
        XCTAssertTrue(last.allSatisfy { $0.sessionId == "s-normal" },
                      "la semilla del próximo peso no puede salir de la semana ligera")
        XCTAssertEqual(last.first?.weightKg, 100)
    }

    func testWorkSetHistoryReportsTheLightWeekInsteadOfHidingIt() async throws {
        let store = try await CenitStore.inMemory()
        try await routine(store)
        try await session(store, id: "s-normal", startTs: 10_000, kg: 100)
        try await session(store, id: "s-light", startTs: 20_000, kg: 92.5, deload: true, programWeek: 5)

        let history = try await store.workSetHistory(exerciseId: "ex1")
        XCTAssertEqual(Set(history.map(\.sessionId)), ["s-normal", "s-light"])
        XCTAssertTrue(history.filter { $0.sessionId == "s-light" }.allSatisfy(\.deload))
        XCTAssertTrue(history.filter { $0.sessionId == "s-normal" }.allSatisfy { !$0.deload })
    }

    func testSessionStartTimesFeedTheWeekCounter() async throws {
        let store = try await CenitStore.inMemory()
        try await routine(store)
        try await session(store, id: "s1", startTs: 10_000, kg: 100, programWeek: 1)
        try await session(store, id: "s2", startTs: 20_000, kg: 100, programWeek: 1)
        // Una sesión sin terminar no cuenta como semana entrenada.
        try await store.saveSession(StrengthSession(id: "open", routineId: "rt1", startTs: 30_000,
                                                    programWeek: 1), sets: [])
        // Una sesión que el programa NO sirvió (movilidad, rápida, repetir del historial) no acumula el
        // estrés que la semana ligera disipa: no avanza el contador (gate /biomecanico FER-329 #4).
        try await session(store, id: "mobility", startTs: 25_000, kg: 0)

        let all = try await store.sessionStartTimes(sinceTs: 0)
        let recent = try await store.sessionStartTimes(sinceTs: 15_000)
        XCTAssertEqual(Set(all), [10_000, 20_000])
        XCTAssertEqual(recent, [20_000])
    }
}
