import XCTest
import WhoopProtocol
import CenitStore
@testable import Cenit

/// FER-692 (#150): the `trim=0xFFFFFFFF` "no valid flash cursor" sentinel. A fully-drained WHOOP 4.0
/// with a compromised RTC/charge reports this sentinel instead of real banked history. It must (1) be
/// surfaced once per session as an honest clock/charge diagnostic, and (2) NOT be read as a small
/// "caught-up" chunk — otherwise the sync completes green while the strap has nothing banked.
@MainActor
final class BackfillSentinelTests: XCTestCase {

    private final class NoopStore: BackfillStoreWriting {
        func insert(_ streams: Streams, deviceId: String) async throws
            -> (hr: Int, rr: Int, events: Int, battery: Int,
                spo2: Int, skinTemp: Int, resp: Int, gravity: Int) { (0, 0, 0, 0, 0, 0, 0, 0) }
        func enqueueRawBatch(_ meta: RawBatchMeta, frames: [[UInt8]]) async throws {}
        func setCursor(_ name: String, _ value: Int) async throws {}
        func cursor(_ name: String) async throws -> Int? { nil }
    }

    private func le32(_ v: UInt32) -> [UInt8] {
        [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 24) & 0xFF)]
    }
    private var startFrame: [UInt8] { frameFromPayload([], type: 49, seq: 0, cmd: 1) }
    /// A HISTORY_END whose trim cursor is the 0xFFFFFFFF no-cursor sentinel.
    private var sentinelEnd: [UInt8] {
        frameFromPayload(le32(1_700_000_000) + [0x00, 0x00] + le32(0) + le32(0xFFFFFFFF),
                         type: 49, seq: 0, cmd: 2)
    }

    private func ingest(_ bf: Backfiller, _ frame: [UInt8]) async {
        await bf.ingest(frame, parsed: parseFrame(frame, family: .whoop4, annotate: false))
    }

    func testSentinelLogsOncePerSession() async {
        var lines: [String] = []
        let bf = Backfiller(store: NoopStore(), deviceId: "t", ackTrim: { _, _ in },
                            log: { lines.append($0) })
        bf.begin(family: .whoop4)
        await ingest(bf, startFrame)
        for _ in 0..<3 { await ingest(bf, sentinelEnd) }   // three sentinel ENDs in a row
        let noCursor = lines.filter { $0.contains("0xFFFFFFFF") }
        XCTAssertEqual(noCursor.count, 1, "the no-cursor sentinel must be logged exactly once per session")
    }

    func testSentinelNeverCompletesSyncAsCaughtUp() async {
        let bf = Backfiller(store: NoopStore(), deviceId: "t", ackTrim: { _, _ in })
        bf.begin(family: .whoop4)
        await ingest(bf, startFrame)
        // Feed well past the caught-up run threshold with sentinel-only ENDs.
        for _ in 0..<6 { await ingest(bf, sentinelEnd) }
        XCTAssertTrue(bf.isBackfilling, "a run of no-cursor sentinels must NOT complete the sync as caught-up")
        XCTAssertFalse(bf.didCatchUp)
    }
}
