import Foundation
import GRDB

// MARK: - v9 cache: generic long-format metric store
// The substrate for a metric explorer. Where MetricsCache / JournalWorkoutAppleCache use a
// WIDE column-per-metric layout (one table per source, typed nullable columns), this is the
// TALL/EAV counterpart: one row per (deviceId, day, key) with a single REAL `value`. Any scalar
// metric — whatever its origin — can be projected into this one table and read back uniformly by
// key, so the explorer can list/compare metrics without knowing each source's schema.
// Mirrors the established pattern exactly: Codable struct, idempotent ON CONFLICT upsert keyed by
// natural key, range-read accessors, all GRDB work via the actor's syncWrite/syncRead helpers.

/// One point in the long-format metric store. Natural key (deviceId, day, key).
public struct MetricPoint: Equatable, Codable, Sendable {
    public let day: String           // YYYY-MM-DD
    public let key: String           // metric identifier, e.g. "restingHr", "steps", "recovery"
    public let value: Double
    public init(day: String, key: String, value: Double) {
        self.day = day; self.key = key; self.value = value
    }
}

extension WhoopStore {

    // MARK: - Upsert (idempotent by natural key; latest value wins on conflict)

    /// Upsert metric points. Natural key (deviceId, day, key). Returns rows changed.
    /// Idempotent: re-upserting the same (deviceId, day, key) updates `value` in place rather than
    /// creating a duplicate.
    @discardableResult
    public func upsertMetricSeries(_ rows: [MetricPoint], deviceId: String) async throws -> Int {
        // An Apple Health import flattens to tens of thousands of points (≈ days ×
        // metric keys). One INSERT-per-row meant tens of thousands of statement
        // round-trips inside the transaction — minutes on a phone. Batch into
        // multi-row INSERTs instead: 4 bound vars/row, SQLite's limit is 999, so
        // 200 rows/statement (800 vars) is a safe, large batch.
        try syncWrite { db in
            var n = 0
            let perRow = "(?, ?, ?, ?)"
            for chunk in stride(from: 0, to: rows.count, by: 200).map({ Array(rows[$0..<min($0 + 200, rows.count)]) }) {
                let values = Array(repeating: perRow, count: chunk.count).joined(separator: ", ")
                var args: [DatabaseValueConvertible?] = []
                args.reserveCapacity(chunk.count * 4)
                for r in chunk {
                    args.append(deviceId)
                    args.append(r.day)
                    args.append(r.key)
                    args.append(r.value)
                }
                try db.execute(sql: """
                    INSERT INTO metricSeries
                        (deviceId, day, key, value)
                    VALUES \(values)
                    ON CONFLICT(deviceId, day, key) DO UPDATE SET
                        value = excluded.value
                    """, arguments: StatementArguments(args))
                n += db.changesCount
            }
            return n
        }
    }

    // MARK: - Reads

    /// Points for a single `key` on days in [from, to] (lexicographic YYYY-MM-DD compare),
    /// oldest day first. Served index-only by idx_metricSeries_device_key_day.
    public func metricSeries(deviceId: String, key: String, from: String, to: String) async throws -> [MetricPoint] {
        // FER-970 (R-03): row SQL/mapping shared with `dashboardSnapshot` via the fetch helper.
        try syncRead { db in
            try Self.fetchMetricSeries(db, deviceId: deviceId, key: key, from: from, to: to)
        }
    }

    /// Points for MULTIPLE `keys` on days in [from, to] in one read (day then key ascending) —
    /// the batched sibling of the single-key accessor, so a caller assembling the 24 hourly
    /// `act_hNN` keys (FER-868) doesn't issue 24 round-trips. Same index as the single-key read.
    public func metricSeries(deviceId: String, keys: [String], from: String, to: String) async throws -> [MetricPoint] {
        guard !keys.isEmpty else { return [] }
        let placeholders = Array(repeating: "?", count: keys.count).joined(separator: ", ")
        var args: [DatabaseValueConvertible?] = [deviceId]
        args.append(contentsOf: keys)
        args.append(contentsOf: [from, to])
        return try syncRead { db in
            try Row.fetchAll(db, sql: """
                SELECT day, key, value FROM metricSeries
                WHERE deviceId = ? AND key IN (\(placeholders)) AND day >= ? AND day <= ?
                ORDER BY day ASC, key ASC
                """, arguments: StatementArguments(args))
                .map { MetricPoint(day: $0["day"], key: $0["key"], value: $0["value"]) }
        }
    }

    /// Distinct metric keys present for a device, sorted ascending.
    public func metricKeys(deviceId: String) async throws -> [String] {
        try syncRead { db in
            try String.fetchAll(db, sql: """
                SELECT DISTINCT key FROM metricSeries
                WHERE deviceId = ?
                ORDER BY key ASC
                """, arguments: [deviceId])
        }
    }

    /// Earliest and latest day for a given metric `key`, or nil if the key has no points.
    public func metricDays(deviceId: String, key: String) async throws -> (earliest: String, latest: String)? {
        try syncRead { db in
            guard let row = try Row.fetchOne(db, sql: """
                SELECT MIN(day) AS earliest, MAX(day) AS latest FROM metricSeries
                WHERE deviceId = ? AND key = ?
                """, arguments: [deviceId, key]),
                let earliest: String = row["earliest"],
                let latest: String = row["latest"]
            else { return nil }
            return (earliest, latest)
        }
    }
}
