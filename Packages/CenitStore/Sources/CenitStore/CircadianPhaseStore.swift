import Foundation
import GRDB

// CircadianPhaseStore.swift — persistence for the body-clock phase estimate behind the "Tu reloj
// corporal" experimental surface (FER-712). One structured record per local civil day, written by the
// nightly strap phase pass (dormant under Apple-only) and read back by the app-layer provider. Raw-SQL upsert + read via the
// actor's syncWrite/syncRead helpers (off the main thread), the same house pattern as ExperimentStore.
//
// `confidence` is stored as the raw PhaseConfidence string: CenitStore keeps NO dependency on
// StrandAnalytics — the app layer maps the string back to the enum.

/// One day's persisted body-clock phase. Plain value type; the enum lives in StrandAnalytics, so
/// `confidence` is carried as its raw string here.
public struct CircadianPhaseRow: Equatable, Codable, Sendable {
    public let day: String            // YYYY-MM-DD (local civil day)
    public let tempMinHour: Double     // estimated body-temp minimum clock hour
    public let acrophaseHours: Double  // activity acrophase (peak), 0..<24
    public let offsetMinutes: Double   // centered lean vs schedule (bias removed)
    public let confidence: String      // PhaseConfidence rawValue: unreadable | wide | solid
    public let daysObserved: Int       // days backing the fit
    public let bedtimeHour: Double?    // suggested sleep-window hour
    public let wakeHour: Double?       // habitual wake used
    public let computedAt: Int         // unix seconds

    public init(day: String, tempMinHour: Double, acrophaseHours: Double, offsetMinutes: Double,
                confidence: String, daysObserved: Int, bedtimeHour: Double? = nil,
                wakeHour: Double? = nil, computedAt: Int) {
        self.day = day; self.tempMinHour = tempMinHour; self.acrophaseHours = acrophaseHours
        self.offsetMinutes = offsetMinutes; self.confidence = confidence
        self.daysObserved = daysObserved; self.bedtimeHour = bedtimeHour
        self.wakeHour = wakeHour; self.computedAt = computedAt
    }
}

extension CenitStore {

    // MARK: - Upsert (idempotent by (deviceId, day); latest value wins on conflict)

    /// Insert or update one day's phase record. Recomputing the same day overwrites it. Returns rows changed.
    @discardableResult
    public func upsertCircadianPhase(_ r: CircadianPhaseRow, deviceId: String) async throws -> Int {
        try syncWrite { db in
            try db.execute(sql: """
                INSERT INTO circadianPhase
                    (deviceId, day, tempMinHour, acrophaseHours, offsetMinutes, confidence,
                     daysObserved, bedtimeHour, wakeHour, computedAt)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(deviceId, day) DO UPDATE SET
                    tempMinHour = excluded.tempMinHour,
                    acrophaseHours = excluded.acrophaseHours,
                    offsetMinutes = excluded.offsetMinutes,
                    confidence = excluded.confidence,
                    daysObserved = excluded.daysObserved,
                    bedtimeHour = excluded.bedtimeHour,
                    wakeHour = excluded.wakeHour,
                    computedAt = excluded.computedAt
                """, arguments: [deviceId, r.day, r.tempMinHour, r.acrophaseHours, r.offsetMinutes,
                                 r.confidence, r.daysObserved, r.bedtimeHour, r.wakeHour, r.computedAt])
            return db.changesCount
        }
    }

    // MARK: - Reads

    /// The most recent phase record for `deviceId` (latest `day`). nil when none has been computed yet —
    /// the surface shows "hard to read" in that case.
    public func latestCircadianPhase(deviceId: String) async throws -> CircadianPhaseRow? {
        try syncRead { db in
            try Row.fetchOne(db, sql: """
                SELECT \(Self.circadianPhaseColumns) FROM circadianPhase
                WHERE deviceId = ?
                ORDER BY day DESC LIMIT 1
                """, arguments: [deviceId]).map(Self.circadianPhaseRow)
        }
    }

    private static let circadianPhaseColumns = """
        day, tempMinHour, acrophaseHours, offsetMinutes, confidence, daysObserved,
        bedtimeHour, wakeHour, computedAt
        """

    private static func circadianPhaseRow(_ row: Row) -> CircadianPhaseRow {
        CircadianPhaseRow(
            day: row["day"], tempMinHour: row["tempMinHour"], acrophaseHours: row["acrophaseHours"],
            offsetMinutes: row["offsetMinutes"], confidence: row["confidence"],
            daysObserved: row["daysObserved"], bedtimeHour: row["bedtimeHour"],
            wakeHour: row["wakeHour"], computedAt: row["computedAt"])
    }
}
