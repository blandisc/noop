import XCTest
import GRDB
@testable import CenitStore

final class ScaffoldTests: XCTestCase {
    func testGRDBIsLinkedAndUsable() throws {
        // Proves the GRDB dependency resolved and a DB can be opened.
        let queue = try DatabaseQueue()
        let answer = try queue.read { db in try Int.fetchOne(db, sql: "SELECT 42") }
        XCTAssertEqual(answer, 42)
    }
}
