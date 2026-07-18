import Foundation
import GRDB
import WhoopProtocol

/// One downsampled heart-rate point: the bucket's start (unix seconds) and the mean bpm over it.
/// Returned by the `GROUP BY ts/bucket` aggregate so a day chart plots ~N-minute means instead of
/// loading the raw ~1 Hz rows (a fully-worn 24h is ~86k samples).
public struct HRBucket: Sendable, Equatable {
    public let ts: Int
    public let bpm: Double
    public init(ts: Int, bpm: Double) { self.ts = ts; self.bpm = bpm }
}

extension CenitStore {
    /// Shared decoder — JSONDecoder is stateless across decodes and was previously allocated once
    /// per event row. Battery events are dense (~every 8 min), so a multi-year read decodes
    /// thousands of rows; reusing one decoder removes that per-row allocation.
    fileprivate static let eventDecoder = JSONDecoder()

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

    public func events(deviceId: String, from: Int, to: Int, limit: Int) async throws -> [WhoopEvent] {
        try syncRead { db in
            try Row.fetchAll(db, sql: """
                SELECT ts, kind, payloadJSON FROM event
                WHERE deviceId = ? AND ts >= ? AND ts <= ?
                ORDER BY ts ASC, kind ASC LIMIT ?
                """, arguments: [deviceId, from, to, limit])
                .map { row in
                    let json: String = row["payloadJSON"]
                    let payload = (try? CenitStore.eventDecoder.decode(
                        [String: ParsedValue].self,
                        from: Data(json.utf8))) ?? [:]
                    return WhoopEvent(ts: row["ts"], kind: row["kind"], payload: payload)
                }
        }
    }

    public func batterySamples(deviceId: String, from: Int, to: Int, limit: Int) async throws -> [BatterySample] {
        try syncRead { db in
            try Row.fetchAll(db, sql: """
                SELECT ts, soc, mv FROM battery
                WHERE deviceId = ? AND ts >= ? AND ts <= ?
                ORDER BY ts ASC LIMIT ?
                """, arguments: [deviceId, from, to, limit])
                .map { BatterySample(ts: $0["ts"], soc: $0["soc"], mv: $0["mv"]) }
        }
    }

    public func spo2Samples(deviceId: String, from: Int, to: Int, limit: Int) async throws -> [SpO2Sample] {
        try syncRead { db in
            try Row.fetchAll(db, sql: """
                SELECT ts, red, ir FROM spo2Sample
                WHERE deviceId = ? AND ts >= ? AND ts <= ?
                ORDER BY ts ASC LIMIT ?
                """, arguments: [deviceId, from, to, limit])
                .map { SpO2Sample(ts: $0["ts"], red: $0["red"], ir: $0["ir"]) }
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

    public func stepSamples(deviceId: String, from: Int, to: Int, limit: Int) async throws -> [StepSample] {
        try syncRead { db in
            try Row.fetchAll(db, sql: """
                SELECT ts, counter FROM stepSample
                WHERE deviceId = ? AND ts >= ? AND ts <= ?
                ORDER BY ts ASC LIMIT ?
                """, arguments: [deviceId, from, to, limit])
                .map { StepSample(ts: $0["ts"], counter: $0["counter"]) }
        }
    }

    public func respSamples(deviceId: String, from: Int, to: Int, limit: Int) async throws -> [RespSample] {
        guard let intId = try await resolvedDeviceId(deviceId, createIfMissing: false) else { return [] }
        return try syncRead { db in
            try Row.fetchAll(db, sql: """
                SELECT ts, raw FROM respSample
                WHERE deviceId = ? AND ts >= ? AND ts <= ?
                ORDER BY ts ASC LIMIT ?
                """, arguments: [intId, from, to, limit])
                .map { RespSample(ts: $0["ts"], raw: $0["raw"]) }
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

    /// COUNT(*) per LOCAL civil day — epochDay = floor((ts + tzOffset) / 86 400) — for each raw
    /// stream feeding `analyzeDay`, over ts >= `from`. The incremental engine's dirtiness signature
    /// (FER-868): one GROUP BY per table, each served by the (deviceId, ts) primary-key/index order
    /// with no row materialization. Streams keyed "hr", "rr", "resp", "gravity", "steps", "skinTemp".
    ///
    /// Precondition: the stream writers never UPDATE rows in place (`INSERT … ON CONFLICT DO
    /// NOTHING`, StreamStore.insert), so per-day counts are a COMPLETE dirtiness signature — a count
    /// can only move when rows were genuinely inserted (backfill, live) or deleted (safe-trim).
    /// `ts + tzOffset` is assumed non-negative (any real timestamp), so SQL's truncating division
    /// equals floor.
    /// FER-970 (R-02): two windows, one per consumer. The per-night signature only folds days
    /// inside the nights window (~22 d), so hr/rr/resp/skinTemp/steps count from `nightsFrom`;
    /// only the motion block — whose dirtiness reads the *gravity* counts — needs the wide
    /// `motionFrom` (60 d with step estimation, 14 d without). Counting the 1 Hz night tables
    /// over 60 d scanned ~3× the rows every 15-minute pass for signature days nobody folded.
    public func streamDayCounts(deviceId: String, nightsFrom: Int, motionFrom: Int,
                                tzOffsetSeconds: Int) async throws -> [String: [Int: Int]] {
        // hrSample/rrInterval/respSample/gravitySample/skinTempSample store the v21 integer
        // surrogate; stepSample still stores the TEXT deviceId (not migrated in v21).
        let intId = try await resolvedDeviceId(deviceId, createIfMissing: false)
        let gravityFrom = min(nightsFrom, motionFrom)   // gravity feeds BOTH signatures
        return try syncRead { db in
            func counts(table: String, id: DatabaseValueConvertible, from: Int) throws -> [Int: Int] {
                var out: [Int: Int] = [:]
                let rows = try Row.fetchAll(db, sql: """
                    SELECT (ts + ?) / 86400 AS ld, COUNT(*) AS n FROM \(table)
                    WHERE deviceId = ? AND ts >= ?
                    GROUP BY ld
                    """, arguments: [tzOffsetSeconds, id, from])
                for r in rows { out[r["ld"]] = r["n"] }
                return out
            }
            var result: [String: [Int: Int]] = [:]
            if let intId {
                result["hr"] = try counts(table: "hrSample", id: intId, from: nightsFrom)
                result["rr"] = try counts(table: "rrInterval", id: intId, from: nightsFrom)
                result["resp"] = try counts(table: "respSample", id: intId, from: nightsFrom)
                result["gravity"] = try counts(table: "gravitySample", id: intId, from: gravityFrom)
                result["skinTemp"] = try counts(table: "skinTempSample", id: intId, from: nightsFrom)
            }
            result["steps"] = try counts(table: "stepSample", id: deviceId, from: nightsFrom)
            return result
        }
    }

    /// Aggregate storage footprint: total decoded rows, raw batch count, total raw byteSize.
    public func storageStats() async throws -> (decodedRows: Int, rawBatches: Int, rawBytes: Int) {
        try syncRead { db in
            let hr   = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM hrSample") ?? 0
            let rr   = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM rrInterval") ?? 0
            let ev   = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM event") ?? 0
            let bat  = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM battery") ?? 0
            let spo2 = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM spo2Sample") ?? 0
            let skin = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM skinTempSample") ?? 0
            let resp = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM respSample") ?? 0
            let grav = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM gravitySample") ?? 0
            let batches = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM rawBatch") ?? 0
            let bytes   = try Int.fetchOne(db,
                sql: "SELECT COALESCE(SUM(byteSize), 0) FROM rawBatch") ?? 0
            return (hr + rr + ev + bat + spo2 + skin + resp + grav, batches, bytes)
        }
    }
}
