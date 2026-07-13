import XCTest
@testable import StrandTraining

/// FER-798: the in-progress-session snapshot must survive a JSON round-trip bit-for-bit, since it's the
/// only thing that rebuilds a live session after a crash. If a field is dropped in encode/decode, the
/// recovered session would silently lose it (a logged set, the in-flight rest, the focus).
final class StrengthSessionSnapshotTests: XCTestCase {

    private func sample() -> StrengthSessionSnapshot {
        let set1 = StrengthSessionSnapshot.SetSnapshot(
            id: "s1", weightKg: 60, reps: 8, done: true, doneTs: 1000,
            rest: RestConfig(mode: .fixed, seconds: 90, hrReference: .restingMargin, hrValue: 0),
            kind: .work)
        let set2 = StrengthSessionSnapshot.SetSnapshot(
            id: "s2", weightKg: 60, reps: 8, done: false, kind: .warmup)
        let run = StrengthSessionSnapshot.RunSnapshot(
            id: "r1", exerciseId: "bench", name: "Press de banca", type: .weightReps,
            restSeconds: 90, restMode: .heartRate, hrRestReference: .restingMargin, hrRestValue: 12,
            lastWeightKg: 57.5, lastReps: 8, lastTimeS: nil, lastDistanceM: nil,
            sets: [set1, set2], currentSet: 1, skipped: false, raiseOptedOut: true,
            supersetGroup: 1)
        return StrengthSessionSnapshot(
            id: "sess-1", routineId: "push-a", routineName: "Push A", startTs: 900,
            runs: [run], currentIndex: 0,
            restEndsAt: Date(timeIntervalSince1970: 1090),
            restStartedAt: Date(timeIntervalSince1970: 1000),
            currentRestTarget: 110, currentRestMode: .heartRate,
            timerStart: nil,
            paused: true, pausedAccumulatedS: 45, pausedAt: Date(timeIntervalSince1970: 1002),
            updatedTs: 1005)
    }

    func testRoundTripPreservesEverything() throws {
        let original = sample()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(StrengthSessionSnapshot.self, from: data)
        XCTAssertEqual(decoded, original, "snapshot changed across a JSON round-trip")
    }

    func testPreservesLoggedSetsAndRestState() throws {
        let decoded = try JSONDecoder().decode(
            StrengthSessionSnapshot.self, from: try JSONEncoder().encode(sample()))
        XCTAssertEqual(decoded.runs.first?.sets.first?.done, true)
        XCTAssertEqual(decoded.runs.first?.sets.first?.doneTs, 1000)
        XCTAssertEqual(decoded.runs.first?.sets.last?.kind, .warmup)
        XCTAssertEqual(decoded.currentRestTarget, 110)
        XCTAssertEqual(decoded.currentRestMode, .heartRate)
        XCTAssertEqual(decoded.restEndsAt, Date(timeIntervalSince1970: 1090))
        XCTAssertEqual(decoded.paused, true)                                   // FER-823
        XCTAssertEqual(decoded.pausedAccumulatedS, 45)
        XCTAssertEqual(decoded.pausedAt, Date(timeIntervalSince1970: 1002))
        XCTAssertEqual(decoded.runs.first?.raiseOptedOut, true)                 // FER-835
    }

    /// FER-835: a snapshot persisted BEFORE the field existed (no `raiseOptedOut` key) still decodes —
    /// the mark is optional, absent = no opt-out.
    func testPreFer835SnapshotDecodesWithoutRaiseOptedOut() throws {
        var snap = sample()
        snap.runs[0].raiseOptedOut = nil
        let data = try JSONEncoder().encode(snap)   // optional nil → key absent, like an old snapshot
        XCTAssertFalse(String(data: data, encoding: .utf8)!.contains("raiseOptedOut"))
        let decoded = try JSONDecoder().decode(StrengthSessionSnapshot.self, from: data)
        XCTAssertNil(decoded.runs.first?.raiseOptedOut)
    }

    /// FER-931: the superset grouping rides the snapshot so a crash mid-superset restores the same
    /// A1/A2 pairing rather than falling back to standalone.
    func testPreservesSupersetGroup() throws {
        let decoded = try JSONDecoder().decode(
            StrengthSessionSnapshot.self, from: try JSONEncoder().encode(sample()))
        XCTAssertEqual(decoded.runs.first?.supersetGroup, 1)
    }

    /// FER-931: a snapshot persisted BEFORE the field existed (no `supersetGroup` key) still decodes —
    /// absent means standalone (nil), never a false grouping.
    func testPreFer931SnapshotDecodesWithoutSupersetGroup() throws {
        var snap = sample()
        snap.runs[0].supersetGroup = nil
        let data = try JSONEncoder().encode(snap)   // optional nil → key absent, like a pre-931 snapshot
        XCTAssertFalse(String(data: data, encoding: .utf8)!.contains("supersetGroup"))
        let decoded = try JSONDecoder().decode(StrengthSessionSnapshot.self, from: data)
        XCTAssertNil(decoded.runs.first?.supersetGroup)
    }
}
