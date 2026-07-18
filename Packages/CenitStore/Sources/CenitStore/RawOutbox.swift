import Foundation
import Compression
import GRDB
import WhoopProtocol

public struct ClockRef: Equatable, Codable, Sendable {
    public let device: Int
    public let wall: Int
    public init(device: Int, wall: Int) { self.device = device; self.wall = wall }
}

// FER-978: pure value type sent into the CenitStore actor via `enqueueRawBatch` — Sendable so the
// send across the actor boundary is checked-safe (all fields are value types).
public struct RawBatchMeta: Equatable, Sendable {
    public let batchId: String
    public let deviceId: String
    public let clockRef: ClockRef
    public let capturedAt: Int
    public let startTs: Int
    public let endTs: Int
    public let frameCount: Int
    public let byteSize: Int
    public init(batchId: String, deviceId: String, clockRef: ClockRef, capturedAt: Int,
                startTs: Int, endTs: Int, frameCount: Int, byteSize: Int) {
        self.batchId = batchId; self.deviceId = deviceId; self.clockRef = clockRef
        self.capturedAt = capturedAt; self.startTs = startTs; self.endTs = endTs
        self.frameCount = frameCount; self.byteSize = byteSize
    }
}

extension CenitStore {
    // MARK: - frame (de)serialization
    // Layout: [count u32 LE]{ [len u32 LE][bytes] } x count. zlib-compressed as a whole.

    static func packFrames(_ frames: [[UInt8]]) -> Data {
        var buf = Data()
        func appendU32(_ v: Int) {
            let u = UInt32(v)
            buf.append(UInt8(u & 0xFF)); buf.append(UInt8((u >> 8) & 0xFF))
            buf.append(UInt8((u >> 16) & 0xFF)); buf.append(UInt8((u >> 24) & 0xFF))
        }
        appendU32(frames.count)
        for f in frames {
            appendU32(f.count)
            buf.append(contentsOf: f)
        }
        return buf
    }

    static func unpackFrames(_ data: Data) -> [[UInt8]] {
        // Read offsets straight off `data`'s buffer — no intermediate [UInt8](data)
        // copy of the whole (multi-MB) blob; each frame is materialized exactly once.
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> [[UInt8]] in
            let total = raw.count
            var off = 0
            func readU32() -> Int? {
                guard off + 4 <= total else { return nil }
                let v = Int(raw[off]) | (Int(raw[off + 1]) << 8)
                    | (Int(raw[off + 2]) << 16) | (Int(raw[off + 3]) << 24)
                off += 4
                return v
            }
            guard let count = readU32() else { return [] }
            var out: [[UInt8]] = []
            out.reserveCapacity(count)
            for _ in 0..<count {
                guard let len = readU32(), off + len <= total else { break }
                let frame = UnsafeRawBufferPointer(rebasing: raw[off..<off + len])
                out.append([UInt8](frame))
                off += len
            }
            return out
        }
    }

    // MARK: - zlib helpers using Apple Compression framework

    /// Decompress a blob that was produced by `zlibCompressWithLength`.
    /// The first 4 bytes are the uncompressed length (UInt32 LE); the rest is the zlib payload.
    static func zlibDecompressWithLength(_ input: Data) throws -> Data {
        // Read the 4-byte uncompressed-length prefix (UInt32 LE).
        guard input.count >= 4 else { throw CocoaError(.fileReadUnknown) }
        let n = Int(input[input.startIndex])
            | (Int(input[input.startIndex + 1]) << 8)
            | (Int(input[input.startIndex + 2]) << 16)
            | (Int(input[input.startIndex + 3]) << 24)
        let compressed = input.dropFirst(4)
        // n == 0 means packFrames returned empty data; return empty.
        guard n > 0 else { return Data() }
        var dst = [UInt8](repeating: 0, count: n)
        let written: Int = compressed.withUnsafeBytes { src in
            guard let srcPtr = src.baseAddress else { return 0 }
            return compression_decode_buffer(&dst, n, srcPtr, compressed.count, nil, COMPRESSION_ZLIB)
        }
        // If written != n the blob is genuinely corrupt (not a sizing issue).
        guard written == n else { throw CocoaError(.fileReadCorruptFile) }
        return Data(dst)
    }

    /// Compress `input` and prepend its uncompressed length as a UInt32 LE prefix.
    static func zlibCompressWithLength(_ input: Data) throws -> Data {
        let sourceSize = input.count
        let dstCapacity = max(64, sourceSize * 2 + 64)
        var dst = [UInt8](repeating: 0, count: dstCapacity)
        let written: Int = input.withUnsafeBytes { src in
            guard let srcPtr = src.baseAddress else { return 0 }
            return compression_encode_buffer(&dst, dstCapacity, srcPtr, sourceSize, nil, COMPRESSION_ZLIB)
        }
        guard written > 0 else { throw CocoaError(.fileWriteUnknown) }
        // Prepend uncompressed length as UInt32 LE.
        let u = UInt32(sourceSize)
        var blob = Data(capacity: 4 + written)
        blob.append(UInt8(u & 0xFF)); blob.append(UInt8((u >> 8) & 0xFF))
        blob.append(UInt8((u >> 16) & 0xFF)); blob.append(UInt8((u >> 24) & 0xFF))
        blob.append(contentsOf: dst[0..<written])
        return blob
    }

    // MARK: - Public API

    /// Compress raw frames into the outbox and store batch meta.
    public func enqueueRawBatch(_ meta: RawBatchMeta, frames: [[UInt8]]) async throws {
        let packed = CenitStore.packFrames(frames)
        let blob = try CenitStore.zlibCompressWithLength(packed)
        try syncWrite { db in
            try db.execute(sql: """
                INSERT INTO rawBatch
                    (batchId, deviceId, capturedAt, deviceClockRef, wallClockRef,
                     startTs, endTs, frameCount, byteSize, framesBlob, syncedAt)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL)
                ON CONFLICT(batchId) DO NOTHING
                """, arguments: [
                    meta.batchId, meta.deviceId, meta.capturedAt,
                    meta.clockRef.device, meta.clockRef.wall,
                    meta.startTs, meta.endTs, meta.frameCount, meta.byteSize, blob])
        }
    }

    /// Decompress and return the exact frame bytes for a batch (empty if unknown).
    public func rawFrames(batchId: String) async throws -> [[UInt8]] {
        let row: Row? = try syncRead { db in
            try Row.fetchOne(db,
                sql: "SELECT framesBlob FROM rawBatch WHERE batchId = ?",
                arguments: [batchId])
        }
        guard let row = row else { return [] }
        let blob: Data = row["framesBlob"]
        let raw = try CenitStore.zlibDecompressWithLength(blob)
        return CenitStore.unpackFrames(raw)
    }

    private static func metaFromRow(_ row: Row) -> RawBatchMeta {
        RawBatchMeta(
            batchId: row["batchId"], deviceId: row["deviceId"],
            clockRef: ClockRef(device: row["deviceClockRef"], wall: row["wallClockRef"]),
            capturedAt: row["capturedAt"], startTs: row["startTs"], endTs: row["endTs"],
            frameCount: row["frameCount"], byteSize: row["byteSize"])
    }

    /// Un-synced batches (syncedAt IS NULL), oldest first, capped at `limit`.
    public func pendingRawBatches(limit: Int) async throws -> [RawBatchMeta] {
        try syncRead { db in
            try Row.fetchAll(db, sql: """
                SELECT batchId, deviceId, capturedAt, deviceClockRef, wallClockRef,
                       startTs, endTs, frameCount, byteSize
                FROM rawBatch
                WHERE syncedAt IS NULL
                ORDER BY capturedAt ASC
                LIMIT ?
                """, arguments: [limit]).map(CenitStore.metaFromRow)
        }
    }

    /// Mark a batch synced (timestamp in unix seconds).
    public func markRawBatchSynced(batchId: String, at: Int) async throws {
        try syncWrite { db in
            try db.execute(sql: "UPDATE rawBatch SET syncedAt = ? WHERE batchId = ?",
                           arguments: [at, batchId])
        }
    }
}

extension CenitStore {
    /// Prune raw outbox rows. Returns the number of rawBatch rows deleted.
    ///
    /// **Policy 1 (only active policy):** Delete SYNCED batches whose `syncedAt` timestamp
    /// is older than `now - keepWindowSeconds`. Synced raw is safe to drop because the
    /// decoded streams are persisted separately.
    ///
    /// Unsynced raw is NEVER dropped by this method. Under the offline-first hybrid design
    /// the locally-stored raw is the sole copy of the strap's "unknown" bytes after a chunk
    /// is trimmed; dropping it would cause permanent data loss.
    ///
    /// - Parameters:
    ///   - now: Current unix-second timestamp used to compute the prune cutoff.
    ///   - keepWindowSeconds: Synced batches older than `now - keepWindowSeconds` are removed.
    ///   - maxUnsyncedBytes: Intentionally unused — unsynced raw is the sole copy of unknown
    ///     bytes post-trim and must never be dropped. Parameter kept for call-site compatibility.
    @discardableResult
    public func pruneRaw(now: Int, keepWindowSeconds: Int, maxUnsyncedBytes: Int) async throws -> Int {
        // maxUnsyncedBytes intentionally unused: unsynced raw is the sole copy of unknown bytes
        // post-trim and must never be dropped.
        let pruned: Int = try syncWrite { db in
            var pruned = 0
            // Policy 1: aged synced batches.
            let cutoff = now - keepWindowSeconds
            try db.execute(sql: """
                DELETE FROM rawBatch WHERE syncedAt IS NOT NULL AND syncedAt < ?
                """, arguments: [cutoff])
            pruned += db.changesCount
            return pruned
        }
        // Reclaim free pages left by the DELETE above (and prior freelist). Outside a transaction
        // (same rule as VACUUM / wal_checkpoint — see checkpointWALImpl). Cap at 200 pages
        // (~800 KB at 4 KB page size): bounded amortized reclaim on every prune call, not a
        // one-shot unbounded VACUUM that could block on a huge freelist backlog.
        try incrementalVacuumAfterPruneImpl()
        return pruned
    }

    /// Non-async so GRDB's synchronous `writeWithoutTransaction` overload is chosen (mirrors
    /// `checkpointWALImpl` / `vacuumImpl`). Cap N=200 — see `pruneRaw`.
    private func incrementalVacuumAfterPruneImpl() throws {
        try dbWriter.writeWithoutTransaction { db in
            try db.execute(sql: "PRAGMA incremental_vacuum(200)")
        }
    }

    // MARK: - Test helper
    public func allBatchIdsForTest() async throws -> [String] {
        try syncRead { db in
            try String.fetchAll(db, sql: "SELECT batchId FROM rawBatch ORDER BY capturedAt ASC")
        }
    }
}
