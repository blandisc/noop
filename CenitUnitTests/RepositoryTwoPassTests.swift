import XCTest
import CenitStore
@testable import Cenit

/// Pins the two-pass launch refresh coordination: `shouldPublish` (a stale
/// generation never publishes; a first-paint pass never overwrites a fully loaded dashboard) and the
/// `fullyLoaded` gate that keeps the engine's baselines off the ~90-day first-paint window.
@MainActor
final class RepositoryTwoPassTests: XCTestCase {

    // MARK: shouldPublish matrix

    func testNewestGenerationPublishes() {
        XCTAssertTrue(Repository.shouldPublish(gen: 2, latestGen: 2, isFirstPaint: false, alreadyFull: false))
        XCTAssertTrue(Repository.shouldPublish(gen: 2, latestGen: 2, isFirstPaint: true, alreadyFull: false))
    }

    func testStaleGenerationNeverPublishes() {
        // An old refresh finishing late (launch full pass vs a newer pull-to-refresh) drops its result.
        XCTAssertFalse(Repository.shouldPublish(gen: 1, latestGen: 2, isFirstPaint: false, alreadyFull: false))
        XCTAssertFalse(Repository.shouldPublish(gen: 1, latestGen: 2, isFirstPaint: true, alreadyFull: true))
    }

    func testFirstPaintNeverOverwritesFullDashboard() {
        XCTAssertFalse(Repository.shouldPublish(gen: 3, latestGen: 3, isFirstPaint: true, alreadyFull: true))
        // …but a FULL pass over a full dashboard is fine (that's every steady-state refresh).
        XCTAssertTrue(Repository.shouldPublish(gen: 3, latestGen: 3, isFirstPaint: false, alreadyFull: true))
    }

    // MARK: fullyLoaded plumbing

    func testSetDashboardDefaultsToFullyLoaded() {
        // Previews/fixtures seed via setDashboard and must behave as a settled dashboard.
        let repo = Repository(deviceId: "test-device")
        XCTAssertFalse(repo.fullyLoaded)                 // fresh repo: nothing published yet
        repo.setDashboard(days: [])
        XCTAssertTrue(repo.fullyLoaded)
        XCTAssertTrue(repo.loaded)
    }

    func testEngineSkipsWhileNotFullyLoaded() async {
        // The gate fires BEFORE the engine touches the store (it returns ahead of `storeHandle()`,
        // which on a device would open the real DB): with a first-paint dashboard the pass returns
        // empty, writes nothing, and leaves `note` nil. The true-side contrast isn't asserted here —
        // on the test host `ensureStore()` would open a real database.
        let repo = Repository(deviceId: "test-device")
        repo.setDashboard(days: [], fullyLoaded: false)
        let engine = IntelligenceEngine(repo: repo, profile: ProfileStore(), deviceId: "test-device")
        let written = await engine.analyzeRecent(force: true)
        XCTAssertTrue(written.isEmpty)
        XCTAssertNil(engine.note)
    }
}
