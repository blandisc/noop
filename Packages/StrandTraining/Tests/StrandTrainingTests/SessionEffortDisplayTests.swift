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

    /// Ola 1 · E3: only `.rpe` is estimated; nil (legacy) and `.hr` are measured.
    func testIsEstimatedOnlyForRpeSource() {
        XCTAssertTrue(SessionEffortDisplay.isEstimated(strainSource: .rpe))
        XCTAssertFalse(SessionEffortDisplay.isEstimated(strainSource: .hr))
        XCTAssertFalse(SessionEffortDisplay.isEstimated(strainSource: nil))
    }

    func testEstimatedNumeralAddsTildeOnce() {
        XCTAssertEqual(SessionEffortDisplay.estimatedNumeral("11.4"), "~11.4")
        XCTAssertEqual(SessionEffortDisplay.estimatedNumeral("~11.4"), "~11.4")
    }
}
