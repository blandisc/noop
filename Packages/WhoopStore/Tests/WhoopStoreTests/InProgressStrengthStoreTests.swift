import XCTest
import StrandTraining
@testable import WhoopStore

/// FER-798: the in-progress-session store keeps exactly one snapshot (write is idempotent by id), reads
/// back the latest, and clears cleanly — the contract the crash-recovery path at launch relies on.
final class InProgressStrengthStoreTests: XCTestCase {

    private func snapshot(id: String = "sess-1", updatedTs: Int = 100) -> StrengthSessionSnapshot {
        let set = StrengthSessionSnapshot.SetSnapshot(id: "s1", weightKg: 60, reps: 8, done: true, doneTs: 90)
        let run = StrengthSessionSnapshot.RunSnapshot(
            id: "r1", exerciseId: "bench", name: "Press de banca", type: .weightReps,
            restSeconds: 90, restMode: .fixed, hrRestReference: .restingMargin, hrRestValue: 0,
            sets: [set], currentSet: 0, skipped: false)
        return StrengthSessionSnapshot(id: id, routineId: nil, routineName: "Push A", startTs: 0,
                                       runs: [run], currentIndex: 0, updatedTs: updatedTs)
    }

    func testNilWhenEmpty() async throws {
        let store = try await WhoopStore.inMemory()
        let got = try await store.inProgressSession()
        XCTAssertNil(got)
    }

    func testSaveThenReadRoundTrips() async throws {
        let store = try await WhoopStore.inMemory()
        let snap = snapshot()
        try await store.saveInProgressSession(snap)
        let got = try await store.inProgressSession()
        XCTAssertEqual(got, snap)
    }

    func testSaveIsIdempotentSingleRow() async throws {
        let store = try await WhoopStore.inMemory()
        try await store.saveInProgressSession(snapshot(updatedTs: 100))
        let updated = snapshot(updatedTs: 200)   // same id, newer state
        try await store.saveInProgressSession(updated)
        let got = try await store.inProgressSession()
        XCTAssertEqual(got, updated, "the latest snapshot for the same id must win")
        XCTAssertEqual(got?.updatedTs, 200)
    }

    func testClearRemovesIt() async throws {
        let store = try await WhoopStore.inMemory()
        try await store.saveInProgressSession(snapshot())
        try await store.clearInProgressSession()
        let got = try await store.inProgressSession()
        XCTAssertNil(got)
    }

    func testClearIsIdempotentWhenEmpty() async throws {
        let store = try await WhoopStore.inMemory()
        try await store.clearInProgressSession()   // no throw on empty
        let got = try await store.inProgressSession()
        XCTAssertNil(got)
    }
}
