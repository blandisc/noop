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

    /// Regression: catalog names with "/" (e.g. "3/4 Sit-Up", a real entry in exercises.json) must
    /// not be truncated at the slash — the whole name is one opaque, percent-encoded path segment.
    func testLookupURLEscapesSlashInName() {
        let url = ExerciseDBClient.lookupURL(forName: "3/4 Sit-Up", host: "exercisedb.p.rapidapi.com")
        // Exactly one path component after ".../name/" — the "/" in the exercise name must be
        // percent-encoded, not parsed as a path separator (which would truncate at "3").
        XCTAssertEqual(url?.pathComponents.count, 4, "expected /exercises/name/<one-segment>, got \(url?.path ?? "nil")")
        XCTAssertEqual(url?.absoluteString, "https://exercisedb.p.rapidapi.com/exercises/name/3%2F4%20sit%20up")
    }

    func testLookupURLHandlesOrdinaryNames() {
        let url = ExerciseDBClient.lookupURL(forName: "Barbell Bench Press", host: "exercisedb.p.rapidapi.com")
        XCTAssertEqual(url?.absoluteString, "https://exercisedb.p.rapidapi.com/exercises/name/barbell%20bench%20press")
    }
}
