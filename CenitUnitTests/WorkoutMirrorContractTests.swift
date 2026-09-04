import XCTest
import StrandTraining   // C1 (FER-361): the wire now carries StrengthSessionSnapshot / SetSnapshot
@testable import Cenit

/// Pins the FER-740 Apple Watch mirroring contract: the wire messages round-trip through JSON, the
/// idempotency key is exactly the one `HealthKitBridge` uses, and the one-HKWorkout invariant gate
/// behaves across the four scenarios. All pure — verifies headless, no watch or HealthKit needed.
final class WorkoutMirrorContractTests: XCTestCase {

    // MARK: INV-1 — every message round-trips through JSON unchanged

    func testAllMessagesRoundTrip() throws {
        let snapshot = RestActivitySnapshot(
            sessionId: "s1", routineName: "Empuje", setNumber: 2, setTotal: 4,
            exerciseName: "Press banca", returnDetail: "60 kg × 8",
            restStartedAt: Date(timeIntervalSince1970: 1_000),
            restEndsAt: Date(timeIntervalSince1970: 1_090),
            isHRMode: false, hrTarget: nil, bpm: 118,
            // FER-806 — the mirror payload now carries the session-phase fields too; the watch decodes and
            // ignores what it doesn't render, but they must survive the round-trip unchanged.
            sessionPhaseRaw: "resting", sessionStartedAt: Date(timeIntervalSince1970: 900),
            setsDone: 8, setsTotal: 18)

        // C1 (FER-361) fixtures for the standalone-logger wire cases.
        let c1Set = StrengthSessionSnapshot.SetSnapshot(
            id: "set1", weightKg: 60, reps: 8, done: true, doneTs: 1_700_000_100, mode: .standard)
        let c1Run = StrengthSessionSnapshot.RunSnapshot(
            id: "r1", exerciseId: "sq", name: "Sentadilla", type: .weightReps,
            restSeconds: 120, restMode: .fixed, hrRestReference: .restingMargin, hrRestValue: 0,
            sets: [c1Set], currentSet: 0, skipped: false)
        let c1Snapshot = StrengthSessionSnapshot(
            id: "s1", routineId: "push", routineName: "Empuje", startTs: 900,
            runs: [c1Run], currentIndex: 0, updatedTs: 1_700_000_100, programWeek: 3, deload: false)

        let messages: [WorkoutMirrorMessage] = [
            .start(sessionId: "s1", routineName: "Empuje", startedAt: Date(timeIntervalSince1970: 900)),
            .rest(snapshot),
            .restEnded(sessionId: "s1", recovered: false),
            .end(sessionId: "s1", endedAt: Date(timeIntervalSince1970: 2_000), save: true,
                 externalUUID: "noop:strength:s1"),
            .watchDidSaveWorkout(sessionId: "s1", externalUUID: "noop:strength:s1"),
            .watchWillNotSave(sessionId: "s1", reason: .noPermission),
            // FER-808 — wrist-initiated actions (watch → iPhone).
            .completeSet(sessionId: "s1", ts: Date(timeIntervalSince1970: 1_700_000_000)),
            .skipRest(sessionId: "s1", ts: nil),
            .adjustRest(sessionId: "s1", deltaS: 30, ts: Date(timeIntervalSince1970: 1_700_000_000)),
            .adjustRest(sessionId: "s1", deltaS: -30, ts: nil),
            // FER-809 — capture context (iPhone → watch), with and without a load.
            .capture(WorkoutCaptureSnapshot(sessionId: "s1", routineName: "Empuje", setNumber: 3, setTotal: 4,
                                            exerciseName: "Press banca", returnDetail: "60 kg × 8", bpm: 118,
                                            hrMax: 185)),   // FER-811 — with a max HR for the zone label
            .capture(WorkoutCaptureSnapshot(sessionId: "s1", routineName: "Empuje", setNumber: 1, setTotal: 3,
                                            exerciseName: "Plancha", returnDetail: "", bpm: nil, hrMax: nil)),
            // FER-810 — plan rotor snapshot (iPhone → watch).
            .plan(WorkoutPlanSnapshot(sessionId: "s1", routineName: "Empuje", exercises: [
                .init(name: "Press banca", setsDone: 2, setsTotal: 4, isCurrent: true),
                .init(name: "Aperturas", setsDone: 0, setsTotal: 3, isCurrent: false),
            ])),
            .plan(WorkoutPlanSnapshot(sessionId: "s1", routineName: "Empuje", exercises: [])),
            // FER-810 — «Ver recibo en iPhone» (watch → iPhone).
            .openReceipt(sessionId: "s1"),
            // FER-96 — the resting-face verdict (iPhone → watch, over updateApplicationContext) and the
            // wrist-initiated start ask (watch → iPhone), all four idleContext fields populated.
            .idleContext(word: "En rango", toneRaw: "clear", advice: "tu plan de hoy, tal cual",
                        routineName: "Empuje"),
            .startFromWrist(sessionId: nil),
            // C1 (FER-361) — the standalone-logger cases: the full session model (iPhone → watch seed),
            // one logged set (watch → iPhone), and the reconciliation snapshot + measured energy (avgHr /
            // kcal both present, and both absent).
            .sessionModel(c1Snapshot),
            .logSet(sessionId: "s1", runId: "r1", set: c1Set),
            .syncSnapshot(snapshot: c1Snapshot, avgHr: 132, energyKcal: 410.5),
            .syncSnapshot(snapshot: c1Snapshot, avgHr: nil, energyKcal: nil),
        ]

        for message in messages {
            let data = try XCTUnwrap(message.encoded(), "encode \(message)")
            let decoded = try XCTUnwrap(WorkoutMirrorMessage.decode(data), "decode \(message)")
            XCTAssertEqual(decoded, message)
        }
    }

    // MARK: INV-2 — RestActivitySnapshot is Codable and round-trips (it left the ActivityKit gate)

    /// Nancy · ronda 7: un reloj viejo manda las acciones SIN `ts` — deben decodificar con `ts = nil`
    /// (el iPhone aplica sin candado de staleness, como antes), nunca fallar el decode.
    func testLegacyWatchActionsWithoutTsDecodeToNil() throws {
        let legacy = #"{"adjustRest":{"sessionId":"s1","deltaS":30}}"#
        let decoded = WorkoutMirrorMessage.decode(Data(legacy.utf8))
        XCTAssertEqual(decoded, .adjustRest(sessionId: "s1", deltaS: 30, ts: nil))

        let legacyComplete = #"{"completeSet":{"sessionId":"s1"}}"#
        XCTAssertEqual(WorkoutMirrorMessage.decode(Data(legacyComplete.utf8)),
                       .completeSet(sessionId: "s1", ts: nil))
    }

    func testRestSnapshotCodable() throws {
        let snapshot = RestActivitySnapshot(
            sessionId: "abc", routineName: "Piernas", setNumber: 1, setTotal: 3,
            exerciseName: "Sentadilla", returnDetail: "100 kg × 5",
            restStartedAt: Date(timeIntervalSince1970: 10), restEndsAt: Date(timeIntervalSince1970: 100),
            isHRMode: true, hrTarget: 120, bpm: nil)
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(RestActivitySnapshot.self, from: data)
        XCTAssertEqual(decoded, snapshot)
    }

    // MARK: FER-808 — the wrist-action cases map to the shared WatchWorkoutAction and degrade gracefully

    /// A garbage / unknown payload decodes to nil (not a crash) — the additive cases never wedge a peer
    /// that can't understand them; `decode` is `try?`, so an out-of-contract message is simply dropped.
    func testUnknownPayloadDecodesToNilNotCrash() {
        XCTAssertNil(WorkoutMirrorMessage.decode(Data("{\"bogus\":1}".utf8)))
        XCTAssertNil(WorkoutMirrorMessage.decode(Data("not json".utf8)))
    }

    // MARK: INV-3 — the shared idempotency key matches HealthKitBridge's format exactly

    func testExternalUUIDFormat() {
        XCTAssertEqual(WorkoutMirrorKey.externalUUID(for: "42"), "noop:strength:42")
        // Same session id ⇒ same key on both devices (the whole point of the invariant).
        XCTAssertEqual(WorkoutMirrorKey.externalUUID(for: "xyz"),
                       WorkoutMirrorKey.externalUUID(for: "xyz"))
    }

    // MARK: INV-4 — the one-HKWorkout gate across the four scenarios

    func testSaveGateScenarios() {
        // A. watch recorded OK → iPhone omits.
        XCTAssertFalse(WorkoutSaveGate.iPhoneShouldSaveWorkout(watchDidSaveWorkout: true))
        // B/C/D. mirror failed / no permission / out of range (no ack) → iPhone saves.
        XCTAssertTrue(WorkoutSaveGate.iPhoneShouldSaveWorkout(watchDidSaveWorkout: false))
    }

    // MARK: FER-96 — the injected `.start` carries the real routine name

    /// Regression for `WorkoutMirroringBridge.swift:98` (pre-fix): the mirroring-start handler used to
    /// hardcode `routineName: ""` even though `pendingStart.routineName` already held the real name.
    /// The OLD code — `.start(sessionId: sid, routineName: "", startedAt: Date())` — would fail this:
    /// `routineName` would read `""`, not `"Empuje"`.
    func testInjectedStartMessageCarriesThePendingRoutineName() {
        let message = WorkoutMirroringBridge.injectedStartMessage(
            sessionId: "s1", pendingRoutineName: "Empuje", startedAt: Date(timeIntervalSince1970: 0))
        guard case let .start(sessionId, routineName, _) = message else {
            return XCTFail("expected .start, got \(message)")
        }
        XCTAssertEqual(sessionId, "s1")
        XCTAssertEqual(routineName, "Empuje")
    }

    /// With no pending start (shouldn't happen in practice — `attemptMirror` always sets it first), the
    /// fallback is the same empty string the old code always sent, never a crash.
    func testInjectedStartMessageFallsBackToEmptyRoutineNameWithNoPendingStart() {
        let message = WorkoutMirroringBridge.injectedStartMessage(
            sessionId: "s1", pendingRoutineName: nil, startedAt: Date(timeIntervalSince1970: 0))
        guard case let .start(_, routineName, _) = message else {
            return XCTFail("expected .start, got \(message)")
        }
        XCTAssertEqual(routineName, "")
    }

    // MARK: FER-96 — idleContext / startFromWrist are additive: every field optional, old↔new decode safely

    /// An `idleContext` with every field absent (the shape an OLDER phone build would send, before this
    /// phase added the fourth field, or simply a phone that hasn't resolved a verdict yet) still decodes
    /// — the watch falls to its existing «sin lectura» look, never a crash.
    func testIdleContextWithAllFieldsAbsentDecodes() throws {
        let data = Data("{\"idleContext\":{}}".utf8)
        let decoded = try XCTUnwrap(WorkoutMirrorMessage.decode(data))
        XCTAssertEqual(decoded, .idleContext(word: nil, toneRaw: nil, advice: nil, routineName: nil))
    }

    /// A `startFromWrist` with no `sessionId` key at all (today's only sender shape) decodes to nil,
    /// matching `.startFromWrist(sessionId: nil)` — the reserved field degrades gracefully.
    func testStartFromWristWithNoSessionIdKeyDecodes() throws {
        let data = Data("{\"startFromWrist\":{}}".utf8)
        let decoded = try XCTUnwrap(WorkoutMirrorMessage.decode(data))
        XCTAssertEqual(decoded, .startFromWrist(sessionId: nil))
    }

    /// A message from a hypothetical NEWER peer — an unrecognized case name alongside the ones this
    /// build knows — drops cleanly (`decode` is `try?`), never crashes the receiver. Same contract
    /// `testUnknownPayloadDecodesToNilNotCrash` pins for garbage payloads, here for a well-formed-JSON,
    /// unknown-CASE payload specifically (the shape a future case addition would produce for an older peer).
    func testUnknownCaseNameDecodesToNilNotCrash() {
        XCTAssertNil(WorkoutMirrorMessage.decode(Data("{\"someFutureCase\":{}}".utf8)))
    }
}
