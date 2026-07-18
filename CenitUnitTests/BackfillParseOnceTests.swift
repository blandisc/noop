import XCTest
import WhoopProtocol
import CenitStore
@testable import Cenit

/// Pins **parse-once + safe-trim ordering** on the historical-offload path (FER-752): the
/// `ParsedFrame` produced by BLEManager's single per-frame parse (FER-183) travels with the raw
/// bytes into `Backfiller.ingest`, so the Backfiller must never call `parseFrame` again — not for
/// `classifyHistoricalMeta`, not for the chunk decode in `finishChunk` (which used to re-parse the
/// whole ~50-frame chunk synchronously on the main actor). Verified through the same
/// `ParseInstrumentation.onParse` seam as `ParseOnceTests`.

/// Thread-safe counter (same shape as ParseOnceTests' — that one is fileprivate). `onParse` and the
/// detached-extract closure are `@Sendable`, so they can't mutate a plain captured `var`.
private final class BackfillCountBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func increment() { lock.withLock { value += 1 } }
    var count: Int { lock.withLock { value } }
}

@MainActor
final class BackfillParseOnceTests: XCTestCase {

    // MARK: - Spy store

    /// Records the ORDER of store operations so the safe-trim invariant
    /// (insert durable → setCursor → ack) is assertable.
    private final class SpyBackfillStore: BackfillStoreWriting {
        var events: [String] = []
        var failInsert = false
        struct InsertFailed: Error {}

        func insert(_ streams: Streams, deviceId: String) async throws
            -> (hr: Int, rr: Int, events: Int, battery: Int,
                spo2: Int, skinTemp: Int, resp: Int, gravity: Int) {
            if failInsert { throw InsertFailed() }
            events.append("insert")
            return (0, 0, 0, 0, 0, 0, 0, 0)
        }
        func enqueueRawBatch(_ meta: RawBatchMeta, frames: [[UInt8]]) async throws {
            events.append("raw")
        }
        func setCursor(_ name: String, _ value: Int) async throws {
            events.append("cursor")
        }
        func cursor(_ name: String) async throws -> Int? { nil }
    }

    // MARK: - Frame fixtures (same layout as HistoricalMetaTests)

    private func le32(_ v: UInt32) -> [UInt8] {
        [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 24) & 0xFF)]
    }

    /// type 49 = METADATA, cmd 1 = HISTORY_START.
    private var startFrame: [UInt8] { frameFromPayload([], type: 49, seq: 0, cmd: 1) }
    /// type 49 = METADATA, cmd 2 = HISTORY_END; payload = unix(4) + subsec(2) + unk0(4) + trim(4).
    /// The resulting 25-byte frame is exactly long enough for `Backfiller.endData` (frame[17..<25]).
    private var endFrame: [UInt8] {
        frameFromPayload(le32(1_700_000_000) + [0x00, 0x00] + le32(0) + le32(42),
                         type: 49, seq: 0, cmd: 2)
    }
    /// type 47 = HISTORICAL_DATA — a chunk data frame (content irrelevant; only routing matters).
    private var dataFrame: [UInt8] { frameFromPayload([0x01, 0x02, 0x03, 0x04], type: 47, seq: 0, cmd: 0) }

    override func tearDown() {
        ParseInstrumentation.onParse = nil   // never leak the hook into another test
        super.tearDown()
    }

    /// Drive one full START → data → END chunk through `ingest`, mirroring BLEManager's drain loop:
    /// each frame is parsed ONCE up front and handed over pre-parsed.
    private func runChunk(store: SpyBackfillStore,
                          ackLog: ((UInt32) -> Void)? = nil,
                          extract: Backfiller.Extractor? = nil) async {
        let backfiller: Backfiller
        let ackTrim: (UInt32, [UInt8]) -> Void = { trim, _ in ackLog?(trim) }
        if let extract {
            backfiller = Backfiller(store: store, deviceId: "test", ackTrim: ackTrim, extract: extract)
        } else {
            backfiller = Backfiller(store: store, deviceId: "test", ackTrim: ackTrim)
        }
        backfiller.begin(family: .whoop4)
        for frame in [startFrame, dataFrame, dataFrame, endFrame] {
            let parsed = parseFrame(frame, family: .whoop4, annotate: false)   // the single parse
            await backfiller.ingest(frame, parsed: parsed)
        }
    }

    /// The Backfiller must reuse the caller's ParsedFrame — zero parses inside ingest/finishChunk.
    func testBackfillerNeverReparses() async {
        let store = SpyBackfillStore()
        let frames = [startFrame, dataFrame, dataFrame, endFrame]
        let parsedUpFront = frames.map { parseFrame($0, family: .whoop4, annotate: false) }

        let counter = BackfillCountBox()
        ParseInstrumentation.onParse = { counter.increment() }

        let backfiller = Backfiller(store: store, deviceId: "test", ackTrim: { _, _ in })
        backfiller.begin(family: .whoop4)
        for (frame, parsed) in zip(frames, parsedUpFront) {
            await backfiller.ingest(frame, parsed: parsed)
        }
        XCTAssertEqual(counter.count, 0,
                       "Backfiller re-parsed offload bytes — ingest/finishChunk must reuse the ParsedFrame (FER-752)")
        XCTAssertEqual(store.events, ["insert", "cursor"], "the chunk must still commit")
    }

    /// Safe-trim ordering: the ack must come strictly AFTER the insert + cursor are durable,
    /// even though the decode now hops off the main actor (FER-752).
    func testAckNeverPrecedesInsert() async {
        let store = SpyBackfillStore()
        var order: [String] = []
        await runChunk(store: store, ackLog: { trim in
            order = store.events + ["ack(\(trim))"]
        })
        XCTAssertEqual(order, ["insert", "cursor", "ack(42)"],
                       "safe-trim invariant broken: ack must follow insert → setCursor")
    }

    /// If the insert throws, the chunk aborts exactly as before: no cursor advance, no ack.
    func testFailedInsertAbortsChunkWithoutAck() async {
        let store = SpyBackfillStore()
        store.failInsert = true
        var acked = false
        await runChunk(store: store, ackLog: { _ in acked = true })
        XCTAssertFalse(acked, "a chunk whose insert failed must NOT be acked (strap would trim unsaved data)")
        XCTAssertEqual(store.events, [], "no cursor advance after a failed insert")
    }

    /// The chunk decode must run OFF the main actor (the jank this issue fixes), while the
    /// insert/ack that follow stay on it.
    func testChunkDecodeRunsOffMainActor() async {
        let store = SpyBackfillStore()
        let sawMainThread = BackfillCountBox()   // reused as a locked flag: >0 = extract ran on main
        await runChunk(store: store, extract: { _, _, _, _, _ in
            if Thread.isMainThread { sawMainThread.increment() }
            return Streams()
        })
        XCTAssertEqual(sawMainThread.count, 0, "finishChunk's decode must not run on the main thread (FER-752)")
        XCTAssertEqual(store.events, ["insert", "cursor"], "insert still runs after the detached decode")
    }
}
