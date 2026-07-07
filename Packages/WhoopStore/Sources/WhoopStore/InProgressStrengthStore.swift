import Foundation
import GRDB
import StrandTraining

// MARK: - v28: durable snapshot of the in-progress strength session (FER-798)
//
// The iPhone's guided strength session lives in memory in the app (`StrengthSessionModel`); a crash/kill
// used to drop it, so the Apple Watch's `.end` found no session and the workout was lost. This store keeps
// a single-row snapshot of the session while it runs — written on start and on each durable edit, read
// once at launch to rebuild the live session, deleted on save/discard.
//
// The snapshot (`StrengthSessionSnapshot`, defined in StrandTraining) is stored as an OPAQUE JSON string:
// WhoopStore never decodes its nested plan/sets. Mirrors the established store pattern — Codable payload,
// idempotent ON CONFLICT upsert keyed by id, reads via the actor's syncWrite/syncRead helpers.

extension WhoopStore {

    /// Insert or replace the one in-progress session snapshot (idempotent by `id`). A burst of edits that
    /// each call this collapses to a single row — the latest snapshot wins.
    public func saveInProgressSession(_ snapshot: StrengthSessionSnapshot) async throws {
        let json = String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self)
        try syncWrite { db in
            try db.execute(sql: """
                INSERT INTO inProgressStrengthSession (id, snapshot, updatedTs)
                VALUES (?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET snapshot = excluded.snapshot, updatedTs = excluded.updatedTs
                """, arguments: [snapshot.id, json, snapshot.updatedTs])
        }
    }

    /// The most-recent in-progress session snapshot, or nil when there is none (0 or 1 row in practice).
    public func inProgressSession() async throws -> StrengthSessionSnapshot? {
        try syncRead { db in
            guard let row = try Row.fetchOne(db, sql: """
                SELECT snapshot FROM inProgressStrengthSession ORDER BY updatedTs DESC LIMIT 1
                """) else { return nil }
            let json: String = row["snapshot"]
            return try JSONDecoder().decode(StrengthSessionSnapshot.self, from: Data(json.utf8))
        }
    }

    /// Drop the in-progress snapshot (session saved, discarded, or its receipt was dismissed). Idempotent.
    public func clearInProgressSession() async throws {
        try syncWrite { db in
            try db.execute(sql: "DELETE FROM inProgressStrengthSession")
        }
    }
}
