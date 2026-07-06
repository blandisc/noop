import XCTest
@testable import Cenit

final class ExerciseDBClientTests: XCTestCase {
    func testInitFailsWithoutKey() {
        XCTAssertNil(ExerciseDBClient(apiKey: nil))
        XCTAssertNil(ExerciseDBClient(apiKey: ""))
        XCTAssertNil(ExerciseDBClient(apiKey: "   "))
    }

    func testInitSucceedsWithKey() {
        XCTAssertNotNil(ExerciseDBClient(apiKey: "test-key"))
    }
}
