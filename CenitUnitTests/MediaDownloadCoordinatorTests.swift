import XCTest
import StrandTraining
@testable import Cenit

// FER-722/786: the structural guarantee behind "toggle off ⇒ zero network requests" — both entry
// points guard on `isEnabled` before touching `URLSession` at all, so with the toggle off a bulk
// download is a no-op (state stays `.idle`) and a loop fetch returns nil without any request.
@MainActor
final class MediaDownloadCoordinatorTests: XCTestCase {
    private func freshDefaults() -> UserDefaults {
        let suite = UserDefaults(suiteName: "MediaDownloadCoordinatorTests.\(UUID().uuidString)")!
        suite.set(false, forKey: MediaDownloadCoordinator.enabledKey)
        return suite
    }

    func testDisabledBulkDownloadIsANoOp() async {
        let coordinator = MediaDownloadCoordinator(userDefaults: freshDefaults())
        await coordinator.bulkDownloadThumbsIfNeeded()
        XCTAssertEqual(coordinator.downloadState, .idle, "a disabled bulk download must not start")
    }

    func testDisabledLoopFetchReturnsNil() async {
        let coordinator = MediaDownloadCoordinator(userDefaults: freshDefaults())
        let exercise = ExerciseCatalog.all.first!
        let result = await coordinator.loopIfNeeded(for: exercise)
        XCTAssertNil(result, "a disabled loop fetch resolves to nil without a request")
    }

    func testDeleteAllCachedMediaDoesNotTouchTheToggle() {
        let defaults = freshDefaults()
        defaults.set(true, forKey: MediaDownloadCoordinator.enabledKey)
        let coordinator = MediaDownloadCoordinator(userDefaults: defaults)
        coordinator.deleteAllCachedMedia()
        XCTAssertTrue(defaults.bool(forKey: MediaDownloadCoordinator.enabledKey))
    }
}
