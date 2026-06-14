import Foundation
import GRDB

// MARK: - v8 cache: journal entries, workouts, and Apple-Health daily aggregates
// Mirrors the MetricsCache pattern: Codable structs, idempotent ON CONFLICT upserts keyed by
// natural key, and range-read accessors. All write/read GRDB work runs via the actor's
// syncWrite/syncRead helpers (off the main thread).

/// One journal answer. Natural key (deviceId, day, question).
public struct JournalEntry: Equatable, Codable {
    public let day: String          // YYYY-MM-DD
    public let question: String
    public let answeredYes: Bool
    public let notes: String?
    public init(day: String, question: String, answeredYes: Bool, notes: String?) {
        self.day = day; self.question = question
        self.answeredYes = answeredYes; self.notes = notes
    }
}

/// One workout. Natural key (deviceId, startTs, sport). All metric columns nullable.
/// `zonesJSON` is verbatim JSON of HR-zone percentages, stored as a string so the cache stays
/// schema-agnostic about the zone shape.
public struct WorkoutRow: Equatable, Codable {
    public let startTs: Int          // unix seconds
    public let endTs: Int            // unix seconds
    public let sport: String
    public let source: String
    public let durationS: Double?
    public let energyKcal: Double?
    public let avgHr: Int?
    public let maxHr: Int?
    public let strain: Double?
    public let distanceM: Double?
    public let zonesJSON: String?
    public let notes: String?
    public init(startTs: Int, endTs: Int, sport: String, source: String, durationS: Double?,
                energyKcal: Double?, avgHr: Int?, maxHr: Int?, strain: Double?, distanceM: Double?,
                zonesJSON: String?, notes: String?) {
        self.startTs = startTs; self.endTs = endTs; self.sport = sport; self.source = source
        self.durationS = durationS; self.energyKcal = energyKcal; self.avgHr = avgHr
        self.maxHr = maxHr; self.strain = strain; self.distanceM = distanceM
        self.zonesJSON = zonesJSON; self.notes = notes
    }
}

/// One Apple-Health daily-aggregate row. Natural key (deviceId, day). All metric columns nullable.
public struct AppleDaily: Equatable, Codable {
    public let day: String           // YYYY-MM-DD
    public let steps: Int?
    public let activeKcal: Double?
    public let basalKcal: Double?
    public let vo2max: Double?
    public let avgHr: Int?
    public let maxHr: Int?
    public let walkingHr: Int?
    public let weightKg: Double?
    public init(day: String, steps: Int?, activeKcal: Double?, basalKcal: Double?, vo2max: Double?,
                avgHr: Int?, maxHr: Int?, walkingHr: Int?, weightKg: Double?) {
        self.day = day; self.steps = steps; self.activeKcal = activeKcal; self.basalKcal = basalKcal
        self.vo2max = vo2max; self.avgHr = avgHr; self.maxHr = maxHr
        self.walkingHr = walkingHr; self.weightKg = weightKg
    }
}

/// Per-metric import coverage for an Apple-Health source. For each metric: how many days carry a
/// value; plus the first/last day and the distinct-day count across both daily tables. Powers the
/// FER-70 live-sync status panel so a silent import becomes legible ("28 days of HRV, none of SpO₂")
/// instead of the user guessing whether anything landed. Metric keys mirror `AppleHealthView`'s
/// series keys so the status panel and the charts speak the same vocabulary.
public struct AppleHealthCoverage: Sendable, Equatable {
    /// MIN(day) across appleDaily ∪ dailyMetric for this source — nil when nothing has imported.
    public let firstDay: String?
    /// MAX(day) across the same union.
    public let lastDay: String?
    /// Distinct days carrying any Apple-Health row (deduped across both tables).
    public let totalDays: Int
    /// Days-with-data per metric key; only keys with ≥1 day are present, so a missing metric is a
    /// missing key (not a zero).
    public let daysByMetric: [String: Int]
    public init(firstDay: String? = nil, lastDay: String? = nil,
                totalDays: Int = 0, daysByMetric: [String: Int] = [:]) {
        self.firstDay = firstDay; self.lastDay = lastDay
        self.totalDays = totalDays; self.daysByMetric = daysByMetric
    }
}

extension WhoopStore {

    // MARK: - Upserts (idempotent by natural key; latest value wins on conflict)

    /// Keep only the LAST row per natural key, preserving the row-by-row "last wins" semantics.
    /// A single multi-row `INSERT … ON CONFLICT DO UPDATE` cannot upsert the same conflict key twice
    /// within one statement (SQLite errors), so the batched upserts below dedup their input first.
    private static func dedupLast<T, K: Hashable>(_ rows: [T], by key: (T) -> K) -> [T] {
        var byKey: [K: T] = [:]
        var order: [K] = []
        for r in rows {
            let k = key(r)
            if byKey[k] == nil { order.append(k) }
            byKey[k] = r
        }
        return order.map { byKey[$0]! }
    }

    /// Upsert journal entries. Natural key (deviceId, day, question). Returns rows changed.
    ///
    /// Batched into multi-row INSERTs (≤150 rows / 750 bound vars per statement, SQLite's limit is
    /// 999) instead of one INSERT per row — a large import was tens of thousands of statement
    /// round-trips inside the transaction, stalling the store actor. Mirrors `upsertMetricSeries`.
    @discardableResult
    public func upsertJournal(_ rows: [JournalEntry], deviceId: String) async throws -> Int {
        let rows = Self.dedupLast(rows) { "\($0.day)\u{1}\($0.question)" }
        return try syncWrite { db in
            var n = 0
            let perRow = "(?, ?, ?, ?, ?)"
            for chunk in stride(from: 0, to: rows.count, by: 150).map({ Array(rows[$0..<min($0 + 150, rows.count)]) }) {
                let values = Array(repeating: perRow, count: chunk.count).joined(separator: ", ")
                var args: [DatabaseValueConvertible?] = []
                args.reserveCapacity(chunk.count * 5)
                for r in chunk {
                    args.append(deviceId)
                    args.append(r.day)
                    args.append(r.question)
                    args.append(r.answeredYes ? 1 : 0)
                    args.append(r.notes)
                }
                try db.execute(sql: """
                    INSERT INTO journal
                        (deviceId, day, question, answeredYes, notes)
                    VALUES \(values)
                    ON CONFLICT(deviceId, day, question) DO UPDATE SET
                        answeredYes = excluded.answeredYes,
                        notes = excluded.notes
                    """, arguments: StatementArguments(args))
                n += db.changesCount
            }
            return n
        }
    }

    /// Delete one journal answer by natural key (the native logging card's "clear"). Source-scoped
    /// by deviceId, so clearing a native ("noop-journal") answer never removes an identical imported
    /// row. Returns rows deleted.
    @discardableResult
    public func deleteJournal(deviceId: String, day: String, question: String) async throws -> Int {
        try syncWrite { db in
            try db.execute(sql: """
                DELETE FROM journal WHERE deviceId = ? AND day = ? AND question = ?
                """, arguments: [deviceId, day, question])
            return db.changesCount
        }
    }

    /// Upsert workouts. Natural key (deviceId, startTs, sport). Returns rows changed.
    ///
    /// Batched into multi-row INSERTs (≤70 rows / 910 bound vars per statement; 13 vars/row, SQLite's
    /// limit is 999) instead of one INSERT per row. Mirrors `upsertMetricSeries`.
    @discardableResult
    public func upsertWorkouts(_ rows: [WorkoutRow], deviceId: String) async throws -> Int {
        let rows = Self.dedupLast(rows) { "\($0.startTs)\u{1}\($0.sport)" }
        return try syncWrite { db in
            var n = 0
            let perRow = "(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
            for chunk in stride(from: 0, to: rows.count, by: 70).map({ Array(rows[$0..<min($0 + 70, rows.count)]) }) {
                let values = Array(repeating: perRow, count: chunk.count).joined(separator: ", ")
                var args: [DatabaseValueConvertible?] = []
                args.reserveCapacity(chunk.count * 13)
                for r in chunk {
                    args.append(deviceId)
                    args.append(r.startTs)
                    args.append(r.endTs)
                    args.append(r.sport)
                    args.append(r.source)
                    args.append(r.durationS)
                    args.append(r.energyKcal)
                    args.append(r.avgHr)
                    args.append(r.maxHr)
                    args.append(r.strain)
                    args.append(r.distanceM)
                    args.append(r.zonesJSON)
                    args.append(r.notes)
                }
                try db.execute(sql: """
                    INSERT INTO workout
                        (deviceId, startTs, endTs, sport, source, durationS, energyKcal,
                         avgHr, maxHr, strain, distanceM, zonesJSON, notes)
                    VALUES \(values)
                    ON CONFLICT(deviceId, startTs, sport) DO UPDATE SET
                        endTs = excluded.endTs,
                        source = excluded.source,
                        durationS = excluded.durationS,
                        energyKcal = excluded.energyKcal,
                        avgHr = excluded.avgHr,
                        maxHr = excluded.maxHr,
                        strain = excluded.strain,
                        distanceM = excluded.distanceM,
                        zonesJSON = excluded.zonesJSON,
                        notes = excluded.notes
                    """, arguments: StatementArguments(args))
                n += db.changesCount
            }
            return n
        }
    }

    /// Delete one source's workouts of a given sport whose startTs is in [from, to]
    /// (makes detected-workout re-derivation idempotent). Returns rows deleted.
    /// Port of Android WhoopDao.deleteWorkoutsBySport (#78).
    @discardableResult
    public func deleteWorkouts(deviceId: String, sport: String, from: Int, to: Int) async throws -> Int {
        try syncWrite { db in
            try db.execute(sql: """
                DELETE FROM workout
                WHERE deviceId = ? AND sport = ? AND startTs >= ? AND startTs <= ?
                """, arguments: [deviceId, sport, from, to])
            return db.changesCount
        }
    }

    /// Upsert Apple-Health daily aggregates. Natural key (deviceId, day). Returns rows changed.
    ///
    /// Batched into multi-row INSERTs (≤90 rows / 900 bound vars per statement; 10 vars/row, SQLite's
    /// limit is 999) instead of one INSERT per row. Mirrors `upsertMetricSeries`.
    @discardableResult
    public func upsertAppleDaily(_ rows: [AppleDaily], deviceId: String) async throws -> Int {
        let rows = Self.dedupLast(rows) { $0.day }
        return try syncWrite { db in
            var n = 0
            let perRow = "(?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
            for chunk in stride(from: 0, to: rows.count, by: 90).map({ Array(rows[$0..<min($0 + 90, rows.count)]) }) {
                let values = Array(repeating: perRow, count: chunk.count).joined(separator: ", ")
                var args: [DatabaseValueConvertible?] = []
                args.reserveCapacity(chunk.count * 10)
                for r in chunk {
                    args.append(deviceId)
                    args.append(r.day)
                    args.append(r.steps)
                    args.append(r.activeKcal)
                    args.append(r.basalKcal)
                    args.append(r.vo2max)
                    args.append(r.avgHr)
                    args.append(r.maxHr)
                    args.append(r.walkingHr)
                    args.append(r.weightKg)
                }
                try db.execute(sql: """
                    INSERT INTO appleDaily
                        (deviceId, day, steps, activeKcal, basalKcal, vo2max,
                         avgHr, maxHr, walkingHr, weightKg)
                    VALUES \(values)
                    ON CONFLICT(deviceId, day) DO UPDATE SET
                        steps = excluded.steps,
                        activeKcal = excluded.activeKcal,
                        basalKcal = excluded.basalKcal,
                        vo2max = excluded.vo2max,
                        avgHr = excluded.avgHr,
                        maxHr = excluded.maxHr,
                        walkingHr = excluded.walkingHr,
                        weightKg = excluded.weightKg
                    """, arguments: StatementArguments(args))
                n += db.changesCount
            }
            return n
        }
    }

    // MARK: - Reads

    /// Journal entries for days in [from, to] (lexicographic YYYY-MM-DD compare),
    /// oldest day first, then by question.
    public func journalEntries(deviceId: String, from: String, to: String) async throws -> [JournalEntry] {
        try syncRead { db in
            try Row.fetchAll(db, sql: """
                SELECT day, question, answeredYes, notes FROM journal
                WHERE deviceId = ? AND day >= ? AND day <= ?
                ORDER BY day ASC, question ASC
                """, arguments: [deviceId, from, to])
                .map {
                    JournalEntry(day: $0["day"], question: $0["question"],
                                 answeredYes: ($0["answeredYes"] as Int) != 0,
                                 notes: $0["notes"])
                }
        }
    }

    /// Workouts overlapping [from, to] (by startTs), oldest first.
    public func workouts(deviceId: String, from: Int, to: Int, limit: Int) async throws -> [WorkoutRow] {
        try syncRead { db in
            try Row.fetchAll(db, sql: """
                SELECT startTs, endTs, sport, source, durationS, energyKcal, avgHr, maxHr,
                       strain, distanceM, zonesJSON, notes FROM workout
                WHERE deviceId = ? AND startTs >= ? AND startTs <= ?
                ORDER BY startTs ASC LIMIT ?
                """, arguments: [deviceId, from, to, limit])
                .map {
                    WorkoutRow(startTs: $0["startTs"], endTs: $0["endTs"], sport: $0["sport"],
                               source: $0["source"], durationS: $0["durationS"],
                               energyKcal: $0["energyKcal"], avgHr: $0["avgHr"], maxHr: $0["maxHr"],
                               strain: $0["strain"], distanceM: $0["distanceM"],
                               zonesJSON: $0["zonesJSON"], notes: $0["notes"])
                }
        }
    }

    /// Apple-Health daily aggregates for days in [from, to] (lexicographic compare), oldest first.
    public func appleDaily(deviceId: String, from: String, to: String) async throws -> [AppleDaily] {
        try syncRead { db in
            try Row.fetchAll(db, sql: """
                SELECT day, steps, activeKcal, basalKcal, vo2max, avgHr, maxHr, walkingHr, weightKg
                FROM appleDaily
                WHERE deviceId = ? AND day >= ? AND day <= ?
                ORDER BY day ASC
                """, arguments: [deviceId, from, to])
                .map {
                    AppleDaily(day: $0["day"], steps: $0["steps"], activeKcal: $0["activeKcal"],
                               basalKcal: $0["basalKcal"], vo2max: $0["vo2max"], avgHr: $0["avgHr"],
                               maxHr: $0["maxHr"], walkingHr: $0["walkingHr"], weightKg: $0["weightKg"])
                }
        }
    }

    /// Per-metric coverage for the Apple-Health source under `deviceId`: the non-NULL day count of
    /// each metric in `appleDaily` (steps, active energy, VO₂max, avg HR) and `dailyMetric` (sleep,
    /// HRV, resting HR, SpO₂, respiration), plus the distinct-day span across both tables. Cheap
    /// enough to call on view-appear — three aggregate scans over the small per-day tables. Metric
    /// keys match `AppleHealthView.seriesKeys` (e.g. "hrv", "asleep_min", "resting_hr").
    public func appleHealthCoverage(deviceId: String) async throws -> AppleHealthCoverage {
        try syncRead { db in
            var byMetric: [String: Int] = [:]
            // COUNT(col) counts non-NULL values — one aggregate row per table. Keep only metrics that
            // actually landed (>0) so the UI renders "missing" purely by key absence.
            func tally(_ row: Row?, _ keys: [String]) {
                guard let row else { return }
                for k in keys {
                    let n: Int = row[k] ?? 0
                    if n > 0 { byMetric[k] = n }
                }
            }
            tally(try Row.fetchOne(db, sql: """
                SELECT COUNT(steps) AS steps, COUNT(activeKcal) AS active_kcal,
                       COUNT(vo2max) AS vo2max, COUNT(avgHr) AS avg_hr
                FROM appleDaily WHERE deviceId = ?
                """, arguments: [deviceId]),
                ["steps", "active_kcal", "vo2max", "avg_hr"])
            tally(try Row.fetchOne(db, sql: """
                SELECT COUNT(totalSleepMin) AS asleep_min, COUNT(avgHrv) AS hrv,
                       COUNT(restingHr) AS resting_hr, COUNT(spo2Pct) AS spo2,
                       COUNT(respRateBpm) AS resp_rate
                FROM dailyMetric WHERE deviceId = ?
                """, arguments: [deviceId]),
                ["asleep_min", "hrv", "resting_hr", "spo2", "resp_rate"])

            var firstDay: String?, lastDay: String?, totalDays = 0
            // UNION (not UNION ALL) dedups the day across both tables, so COUNT(*) is distinct days.
            if let span = try Row.fetchOne(db, sql: """
                SELECT MIN(day) AS firstDay, MAX(day) AS lastDay, COUNT(*) AS totalDays FROM (
                    SELECT day FROM appleDaily WHERE deviceId = ?
                    UNION
                    SELECT day FROM dailyMetric WHERE deviceId = ?
                )
                """, arguments: [deviceId, deviceId]) {
                firstDay = span["firstDay"]
                lastDay = span["lastDay"]
                totalDays = span["totalDays"] ?? 0
            }
            return AppleHealthCoverage(firstDay: firstDay, lastDay: lastDay,
                                       totalDays: totalDays, daysByMetric: byMetric)
        }
    }
}
