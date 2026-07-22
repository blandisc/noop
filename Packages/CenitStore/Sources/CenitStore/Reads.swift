import Foundation
import GRDB
import BiometricStreams

/// One downsampled heart-rate point: the bucket's start (unix seconds) and the mean bpm over it.
/// Returned by the `GROUP BY ts/bucket` aggregate so a day chart plots ~N-minute means instead of
/// loading the raw ~1 Hz rows (a fully-worn 24h is ~86k samples).
public struct HRBucket: Sendable, Equatable {
    public let ts: Int
    public let bpm: Double
    public init(ts: Int, bpm: Double) { self.ts = ts; self.bpm = bpm }
}

extension CenitStore {
    public func hrSamples(deviceId: String, from: Int, to: Int, limit: Int) async throws -> [HRSample] {
        // v21: hrSample stores deviceId as an integer surrogate; translate at the boundary (an unknown
        // id has no rows → []). The SQL is unchanged, so the plan stays SEARCH USING PRIMARY KEY.
        guard let intId = try await resolvedDeviceId(deviceId, createIfMissing: false) else { return [] }
        return try syncRead { db in
            try Row.fetchAll(db, sql: """
                SELECT ts, bpm FROM hrSample
                WHERE deviceId = ? AND ts >= ? AND ts <= ?
                ORDER BY ts ASC LIMIT ?
                """, arguments: [intId, from, to, limit])
                .map { HRSample(ts: $0["ts"], bpm: $0["bpm"]) }
        }
    }

    /// Downsampled HR for charting: mean bpm per `bucketSeconds`-wide bucket over `[from, to]`,
    /// keyed by the bucket's start (floor(ts/bucket)*bucket). Aggregates in SQL so a 24h window
    /// returns ~`(to-from)/bucketSeconds` rows instead of every ~1 Hz sample. Ascending by time.
    public func hrBuckets(deviceId: String, from: Int, to: Int, bucketSeconds: Int) async throws -> [HRBucket] {
        let bucket = max(1, bucketSeconds)
        guard let intId = try await resolvedDeviceId(deviceId, createIfMissing: false) else { return [] }
        return try syncRead { db in
            try Row.fetchAll(db, sql: """
                SELECT (ts / ?) * ? AS bucket, AVG(bpm) AS avgBpm FROM hrSample
                WHERE deviceId = ? AND ts >= ? AND ts <= ?
                GROUP BY ts / ?
                ORDER BY bucket ASC
                """, arguments: [bucket, bucket, intId, from, to, bucket])
                .map { HRBucket(ts: $0["bucket"], bpm: $0["avgBpm"]) }
        }
    }

    public func rrIntervals(deviceId: String, from: Int, to: Int, limit: Int) async throws -> [RRInterval] {
        guard let intId = try await resolvedDeviceId(deviceId, createIfMissing: false) else { return [] }
        return try syncRead { db in
            try Row.fetchAll(db, sql: """
                SELECT ts, rrMs FROM rrInterval
                WHERE deviceId = ? AND ts >= ? AND ts <= ?
                ORDER BY ts ASC, rrMs ASC LIMIT ?
                """, arguments: [intId, from, to, limit])
                .map { RRInterval(ts: $0["ts"], rrMs: $0["rrMs"]) }
        }
    }

    public func skinTempSamples(deviceId: String, from: Int, to: Int, limit: Int) async throws -> [SkinTempSample] {
        guard let intId = try await resolvedDeviceId(deviceId, createIfMissing: false) else { return [] }
        return try syncRead { db in
            try Row.fetchAll(db, sql: """
                SELECT ts, raw FROM skinTempSample
                WHERE deviceId = ? AND ts >= ? AND ts <= ?
                ORDER BY ts ASC LIMIT ?
                """, arguments: [intId, from, to, limit])
                .map { SkinTempSample(ts: $0["ts"], raw: $0["raw"]) }
        }
    }

    public func gravitySamples(deviceId: String, from: Int, to: Int, limit: Int) async throws -> [GravitySample] {
        guard let intId = try await resolvedDeviceId(deviceId, createIfMissing: false) else { return [] }
        return try syncRead { db in
            try Row.fetchAll(db, sql: """
                SELECT ts, x, y, z FROM gravitySample
                WHERE deviceId = ? AND ts >= ? AND ts <= ?
                ORDER BY ts ASC LIMIT ?
                """, arguments: [intId, from, to, limit])
                .map { GravitySample(ts: $0["ts"], x: $0["x"], y: $0["y"], z: $0["z"]) }
        }
    }

    /// Max HR sample timestamp for a device, or nil if there are none. The biometric "data frontier"
    /// used by the stuck-strap watchdog (advances iff the strap is actually logging + offloading).
    public func latestHRSampleTs(deviceId: String) async throws -> Int? {
        guard let intId = try await resolvedDeviceId(deviceId, createIfMissing: false) else { return nil }
        return try syncRead { db in
            try Int.fetchOne(db,
                sql: "SELECT MAX(ts) FROM hrSample WHERE deviceId = ?", arguments: [intId])
        }
    }
}
