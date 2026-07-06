import XCTest
import StrandTraining
@testable import Cenit

// FER-722: the structural guarantee behind "toggle off ⇒ zero network requests" — both entry
// points must never build an `ExerciseDBClient` (and therefore never touch `URLSession`) while
// the toggle is off. `hasBuiltClient` lets the test observe this without mocking HTTP.
@MainActor
final class MediaDownloadCoordinatorTests: XCTestCase {
    private func freshDefaults() -> UserDefaults {
        let suite = UserDefaults(suiteName: "MediaDownloadCoordinatorTests.\(UUID().uuidString)")!
        suite.set(false, forKey: MediaDownloadCoordinator.enabledKey)
        return suite
    }

    func testDisabledNeverBuildsClientOnBulkDownload() async {
        let coordinator = MediaDownloadCoordinator(userDefaults: freshDefaults())
        await coordinator.bulkDownloadThumbsIfNeeded()
        XCTAssertFalse(coordinator.hasBuiltClient)
    }

    func testDisabledNeverBuildsClientOnLoopFetch() async {
        let coordinator = MediaDownloadCoordinator(userDefaults: freshDefaults())
        let exercise = ExerciseCatalog.all.first!
        let result = await coordinator.loopIfNeeded(for: exercise)
        XCTAssertNil(result)
        XCTAssertFalse(coordinator.hasBuiltClient)
    }

    func testDeleteAllCachedMediaDoesNotTouchTheToggle() {
        let defaults = freshDefaults()
        defaults.set(true, forKey: MediaDownloadCoordinator.enabledKey)
        let coordinator = MediaDownloadCoordinator(userDefaults: defaults)
        coordinator.deleteAllCachedMedia()
        XCTAssertTrue(defaults.bool(forKey: MediaDownloadCoordinator.enabledKey))
    }
}
