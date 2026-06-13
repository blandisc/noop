import XCTest
@testable import StrandImport

/// FER-33 — the Apple Health XML parse polls `isCancelled` at each progress tick (every 50k
/// elements) and aborts with `CancellationError`, so a user who leaves mid-import stops the
/// multi-minute parse promptly instead of letting it run to completion.
final class AppleHealthCancellationTests: XCTestCase {

    /// One `<HealthData>` doc with `count` identical heart-rate records on a single day (they fold
    /// into one per-day aggregate, so memory stays bounded even at 60k elements).
    private func xml(records count: Int) -> Data {
        var s = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<HealthData>\n"
        s.reserveCapacity(count * 140 + 64)
        let line = #"<Record type="HKQuantityTypeIdentifierHeartRate" sourceName="W" unit="count/min" startDate="2024-01-02 08:00:00 +0000" endDate="2024-01-02 08:00:00 +0000" value="70"/>"#
        for _ in 0..<count { s += line; s += "\n" }
        s += "</HealthData>"
        return Data(s.utf8)
    }

    func testCancelDuringParseThrowsCancellationError() throws {
        // Just over the 50k progress tick — the smallest input that reaches a cancellation poll.
        let data = xml(records: 50_001)
        XCTAssertThrowsError(
            try AppleHealthImporter().importXML(data: data, isCancelled: { true })
        ) { error in
            XCTAssertTrue(error is CancellationError, "expected CancellationError, got \(error)")
        }
    }

    func testNotCancelledParsesEveryRecord() throws {
        // Same input, no cancellation → the full parse completes (the tick fires but never aborts).
        let data = xml(records: 50_001)
        let r = try AppleHealthImporter().importXML(data: data, isCancelled: { false })
        let day = try XCTUnwrap(r.daily.first)
        XCTAssertEqual(try XCTUnwrap(day.avgHr), 70, accuracy: 1e-9)
    }
}
