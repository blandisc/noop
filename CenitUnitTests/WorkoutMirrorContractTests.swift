import XCTest
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
            isHRMode: false, hrTarget: nil, bpm: 118)

        let messages: [WorkoutMirrorMessage] = [
            .start(sessionId: "s1", routineName: "Empuje", startedAt: Date(timeIntervalSince1970: 900)),
            .rest(snapshot),
            .restEnded(sessionId: "s1", recovered: false),
            .end(sessionId: "s1", endedAt: Date(timeIntervalSince1970: 2_000), save: true,
                 externalUUID: "noop:strength:s1"),
            .watchDidSaveWorkout(sessionId: "s1", externalUUID: "noop:strength:s1"),
            .watchWillNotSave(sessionId: "s1", reason: .noPermission),
            // FER-808 — wrist-initiated actions (watch → iPhone).
            .completeSet(sessionId: "s1"),
            .skipRest(sessionId: "s1"),
            .adjustRest(sessionId: "s1", deltaS: 30),
            .adjustRest(sessionId: "s1", deltaS: -30),
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
        ]

        for message in messages {
            let data = try XCTUnwrap(message.encoded(), "encode \(message)")
            let decoded = try XCTUnwrap(WorkoutMirrorMessage.decode(data), "decode \(message)")
            XCTAssertEqual(decoded, message)
        }
    }

    // MARK: INV-2 — RestActivitySnapshot is Codable and round-trips (it left the ActivityKit gate)

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
}
