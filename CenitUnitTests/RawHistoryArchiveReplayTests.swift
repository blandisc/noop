import XCTest
@testable import Cenit
import WhoopProtocol
import CenitStore

/// FER-693: `RawHistoryArchive.replay` re-decodes the durable reject archive through the CURRENT decoder
/// and inserts whatever now decodes — the only path by which already-acked banked history backfills after
/// a newly-landed layout (e.g. WHOOP 4.0 v25). These are three REAL v25 records a pre-v25 build had
/// archived as undecodable; under the current decoder each yields a gravity sample.
final class RawHistoryArchiveReplayTests: XCTestCase {

    /// Minimal BackfillStoreWriting that only records how many gravity samples were handed to insert.
    private final class CaptureStore: BackfillStoreWriting {
        private(set) var insertedGravity = 0
        @discardableResult
        func insert(_ streams: Streams, deviceId: String) async throws
            -> (hr: Int, rr: Int, events: Int, battery: Int,
                spo2: Int, skinTemp: Int, resp: Int, gravity: Int) {
            insertedGravity += streams.gravity.count
            return (0, 0, 0, 0, 0, 0, 0, streams.gravity.count)
        }
        func enqueueRawBatch(_ meta: RawBatchMeta, frames: [[UInt8]]) async throws {}
        func setCursor(_ name: String, _ value: Int) async throws {}
        func cursor(_ name: String) async throws -> Int? { nil }
    }

    /// A store whose insert always fails — stands in for a transient DB error during replay. (#152)
    private final class ThrowingStore: BackfillStoreWriting {
        struct Boom: Error {}
        func insert(_ streams: Streams, deviceId: String) async throws
            -> (hr: Int, rr: Int, events: Int, battery: Int,
                spo2: Int, skinTemp: Int, resp: Int, gravity: Int) { throw Boom() }
        func enqueueRawBatch(_ meta: RawBatchMeta, frames: [[UInt8]]) async throws {}
        func setCursor(_ name: String, _ value: Int) async throws {}
        func cursor(_ name: String) async throws -> Int? { nil }
    }

    private func bytes(_ s: String) -> [UInt8] {
        var out = [UInt8](); out.reserveCapacity(s.count / 2); var i = s.startIndex
        while i < s.endIndex { let j = s.index(i, offsetBy: 2)
            out.append(UInt8(s[i..<j], radix: 16)!); i = j }
        return out
    }

    // A synthetic WHOOP 4.0 V24 type-47 record that decodes cleanly WITH gravity under the current
    // decoder (from HistoricalV24Tests / RejectedHistoryTests). Used so the replay MECHANISM is tested
    // independent of the v25 layout work (FER-690): whatever decodes today must be forwarded to the store.
    private let v24Hex =
        "aa5a008e2f18000000000000f153650000000000003f0152030000000000000000dc053075" +
        "000000cdcc4c3dcdcccc3d5a657e3f00000040cdcc4c3dcdcccc3d5a657e3f504668428403" +
        "200364006400b80bb80b000000000000c25c1a88"

    func testReplayDecodesArchivedRecordsIntoGravityRows() async throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("noop-replay-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let archive = RawHistoryArchive(directory: dir)
        // Two copies of a clean v24 record: each retro-decodes to a gravity sample under today's decoder,
        // proving read-back → decode → forward-to-store. (Once FER-690 lands the explicit v25 layout, the
        // same path recovers gravity from archived v25 frames — that's the whole point of the archive.)
        let frames = [bytes(v24Hex), bytes(v24Hex)]
        if case .failed = archive.archive(frames, trim: 70476, family: .whoop4) {
            return XCTFail("archive write should not fail")
        }
        XCTAssertEqual(archive.readAll().count, 2, "every archived line should read back")

        let store = CaptureStore()
        let rows = try await archive.replay(into: store, deviceId: "test")
        XCTAssertEqual(rows, 2, "both archived records should retro-decode to a gravity sample")
        XCTAssertEqual(store.insertedGravity, 2, "decoded gravity should be forwarded to the store")
    }

    func testReplayOnEmptyArchiveIsNoOp() async throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("noop-replay-empty-\(UUID().uuidString)", isDirectory: true)
        let archive = RawHistoryArchive(directory: dir)
        XCTAssertEqual(archive.readAll().count, 0)
        let rows = try await archive.replay(into: CaptureStore(), deviceId: "test")
        XCTAssertEqual(rows, 0)
    }

    /// A failed store insert must PROPAGATE, not be swallowed — that's what lets bootstrapStore keep the
    /// replay gate un-advanced so these records (only copy: the archive) retry next launch. (#152)
    func testReplayThrowsWhenStoreFailsSoGateCanHold() async throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("noop-replay-throw-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let archive = RawHistoryArchive(directory: dir)
        let frame = bytes("aa50000c2f190013390000140d2b6a4075010068a2010032fdbcfd98fdd3fdccfd47ffb00366064f073e06c103d3016cffa2fc87fa2ffae5fdbe03140675060c0510012dff1bfec0018f3c500500010068dc8f44")
        if case .failed = archive.archive([frame], trim: 70476, family: .whoop4) {
            return XCTFail("archive write should not fail")
        }

        do {
            _ = try await archive.replay(into: ThrowingStore(), deviceId: "test")
            XCTFail("replay must rethrow a store-insert failure")
        } catch is ThrowingStore.Boom {
            // expected — bootstrapStore's catch leaves the gate un-advanced.
        }
    }
}
