import Foundation
import GRDB

// MARK: - v14 cache: prescribed-diet plan + daily adherence (FER-370)
//
// A nutritionist's plan, captured once (noop.diet.v1, via the BYO-LLM / import path in
// StrandImport) and tracked for adherence — NOT a calorie counter. CenitStore stores the plan as
// an OPAQUE JSON payload: it never decodes the nested meals/options (that's StrandImport's
// `DietPlan`); denormalized columns (nombre, idioma, ciclo, createdAt) allow listing without
// decoding. Adherence mirrors the `journal` table — one row per (deviceId, day, mealId).
//
// Mirrors the established store pattern exactly: Codable structs, idempotent ON CONFLICT upserts
// keyed by natural key, reads, all via the actor's syncWrite/syncRead helpers (off the main
// thread). MVP is one active plan at a time — `activeDietPlan` returns the most recently created
// one; the table keeps the full history.

/// Whether a planned meal was followed on a given day. Tri-state, mirroring the journal's
/// yes/no/skip. `sustitui` (an equivalent substitution) counts as adherent — the % rule lives in
/// StrandAnalytics (FER-372); this enum only records the raw status.
public enum DietMealStatus: String, Sendable, Equatable, Codable, CaseIterable {
    case cumpli      // ate it as planned
    case sustitui    // substituted with an equivalent
    case salte       // skipped
}

/// One persisted diet plan. Natural key `id` (app-generated UUID). `payloadJSON` is the canonical
/// `noop.diet.v1` document; the other columns are denormalized from it for listing.
public struct DietPlanRow: Equatable, Codable, Sendable {
    public let id: String
    public let name: String          // denormalized "nombre"
    public let language: String      // denormalized "idioma": es | en
    public let cycle: String         // denormalized "ciclo": diario
    public let payloadJSON: String   // canonical noop.diet.v1
    public let createdAt: Int        // unix seconds

    public init(id: String, name: String, language: String, cycle: String,
                payloadJSON: String, createdAt: Int) {
        self.id = id; self.name = name; self.language = language; self.cycle = cycle
        self.payloadJSON = payloadJSON; self.createdAt = createdAt
    }
}

/// One day's adherence mark for one planned meal. Natural key (deviceId, day, mealId).
public struct DietAdherenceRow: Equatable, Codable, Sendable {
    public let day: String           // YYYY-MM-DD (local civil day)
    public let mealId: String        // references a DietPlan meal id
    public let status: DietMealStatus
    /// Which equivalent option was eaten — the 0-based index into the plan meal's `opciones` (v16,
    /// FER-401). nil = not recorded (a `sustitui`/`salte` mark, or any pre-v16 row).
    public let optionIndex: Int?
    public let note: String?

    public init(day: String, mealId: String, status: DietMealStatus,
                optionIndex: Int? = nil, note: String? = nil) {
        self.day = day; self.mealId = mealId; self.status = status
        self.optionIndex = optionIndex; self.note = note
    }
}

extension CenitStore {

    // MARK: - Plan (upsert idempotent by id; latest value wins on conflict)

    /// Insert or update one diet plan by its `id`. Returns rows changed.
    @discardableResult
    public func upsertDietPlan(_ r: DietPlanRow, deviceId: String) async throws -> Int {
        try syncWrite { db in
            try db.execute(sql: """
                INSERT INTO dietPlan (id, deviceId, nombre, idioma, ciclo, payloadJSON, createdAt)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    nombre = excluded.nombre,
                    idioma = excluded.idioma,
                    ciclo = excluded.ciclo,
                    payloadJSON = excluded.payloadJSON,
                    createdAt = excluded.createdAt
                """, arguments: [r.id, deviceId, r.name, r.language, r.cycle, r.payloadJSON, r.createdAt])
            return db.changesCount
        }
    }

    /// The active plan for `deviceId` — the most recently created one. nil when none. MVP is one
    /// active plan; the table keeps history.
    public func activeDietPlan(deviceId: String) async throws -> DietPlanRow? {
        try syncRead { db in
            try Row.fetchOne(db, sql: """
                SELECT id, nombre, idioma, ciclo, payloadJSON, createdAt FROM dietPlan
                WHERE deviceId = ?
                ORDER BY createdAt DESC, id DESC LIMIT 1
                """, arguments: [deviceId]).map(Self.dietPlanRow)
        }
    }

    // MARK: - Adherence (upsert idempotent by natural key)

    /// Insert or update one meal's adherence for a day. Natural key (deviceId, day, mealId).
    /// Returns rows changed.
    @discardableResult
    public func upsertDietAdherence(_ r: DietAdherenceRow, deviceId: String) async throws -> Int {
        try syncWrite { db in
            try db.execute(sql: """
                INSERT INTO dietAdherence (deviceId, day, mealId, status, optionIndex, note)
                VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(deviceId, day, mealId) DO UPDATE SET
                    status = excluded.status,
                    optionIndex = excluded.optionIndex,
                    note = excluded.note
                """, arguments: [deviceId, r.day, r.mealId, r.status.rawValue, r.optionIndex, r.note])
            return db.changesCount
        }
    }

    /// All adherence marks for `deviceId` on `day`, ordered by mealId. The % of apego (FER-372) is
    /// computed from these against the active plan's meal count.
    public func dietAdherence(deviceId: String, day: String) async throws -> [DietAdherenceRow] {
        try syncRead { db in
            try Row.fetchAll(db, sql: """
                SELECT day, mealId, status, optionIndex, note FROM dietAdherence
                WHERE deviceId = ? AND day = ?
                ORDER BY mealId ASC
                """, arguments: [deviceId, day]).map(Self.dietAdherenceRow)
        }
    }

    // MARK: - Delete

    /// Delete EVERY diet-adherence mark for `deviceId`. The «empezar de cero» reset uses this so
    /// contributed patrones leave no residual adherence rows. Other partitions are untouched.
    public func deleteAllDietAdherence(deviceId: String) async throws {
        try syncWrite { db in
            try db.execute(sql: "DELETE FROM dietAdherence WHERE deviceId = ?", arguments: [deviceId])
        }
    }

    // MARK: - Row mapping

    private static func dietPlanRow(_ row: Row) -> DietPlanRow {
        DietPlanRow(id: row["id"], name: row["nombre"], language: row["idioma"],
                    cycle: row["ciclo"], payloadJSON: row["payloadJSON"], createdAt: row["createdAt"])
    }

    private static func dietAdherenceRow(_ row: Row) -> DietAdherenceRow {
        DietAdherenceRow(day: row["day"], mealId: row["mealId"],
                         status: DietMealStatus(rawValue: row["status"]) ?? .salte,
                         optionIndex: row["optionIndex"], note: row["note"])
    }
}
