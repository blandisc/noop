import XCTest
@testable import StrandTraining

final class SessionEffortDisplayTests: XCTestCase {
    func testStrainWins() {
        XCTAssertEqual(SessionEffortDisplay.resolve(strain: 8.5, avgHr: 130), .effort(8.5))
    }

    func testDurationWithHRWhenNoStrain() {
        XCTAssertEqual(SessionEffortDisplay.resolve(strain: nil, avgHr: 130), .durationWithHR(130))
    }

    func testDurationOnlyWhenNeither() {
        XCTAssertEqual(SessionEffortDisplay.resolve(strain: nil, avgHr: nil), .durationOnly)
    }
}
