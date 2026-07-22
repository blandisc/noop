import Foundation
import GRDB
import BiometricStreams

extension CenitStore {
    /// Deterministic JSON for an event payload (sorted keys so the same payload always
    /// serializes byte-identically — important for the natural-key dedupe and parity).
    static func encodePayload(_ payload: [String: ParsedValue]) throws -> String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        let data = try enc.encode(payload)
        return String(decoding: data, as: UTF8.self)
    }

    /// F7 (reduced scope): `device` was dropped in v37 (band device registry, zero live consumer).
    /// KEPT (not deleted) — `Cenit/Data/Repository.swift:242` still calls it (a real, non-test
    /// caller) — but now an inert no-op: writing to a dropped table would throw "no such table" on
    /// every store open. Signature is unchanged so all existing callers (app + tests) keep compiling.
    public func upsertDevice(id: String, mac: String?, name: String?) async throws {
        // no-op — `device` table dropped in v37 (F7)
    }

    /// Idempotent upsert of decoded streams by natural key. Returns the number of rows
    /// ACTUALLY inserted per stream (0 for rows that already existed).
    ///
    /// F7 (reduced scope, "la banda nunca existió"): only `hrSample`/`rrInterval` are written now —
    /// the other `Streams` fields (spo2/skinTemp/resp/gravity/steps/events/battery) fed band-only raw
    /// tables dropped in v37; writing them here would throw "no such table" and abort this WHOLE
    /// transaction (including the still-live hr/rr insert). `Streams` itself is unchanged (shared
    /// with the research-only `WhoopProtocol` package) — its extra fields simply aren't persisted here.
    ///
    /// NOTE: the `synced` column (added by migration v5 for a since-removed server-upload feature)
    /// is intentionally NOT written here — it is unused and defaults to 0. The column is left in the
    /// schema to avoid a DROP COLUMN migration over existing data; nothing reads it.
    @discardableResult
    public func insert(_ streams: Streams, deviceId: String) async throws -> (hr: Int, rr: Int) {
        // v21: hrSample/rrInterval store `deviceId` as an integer surrogate. Resolve it ONCE per call
        // (cached after the first), creating the mapping on demand so this NEVER throws on an unknown
        // id — that's what keeps the Backfiller from acking+trimming history it failed to persist.
        let intId = try await resolvedDeviceId(deviceId, createIfMissing: true)!
        return try syncWrite { db in
            var hr = 0, rr = 0
            if !streams.hr.isEmpty {
                let stmt = try db.cachedStatement(sql: """
                    INSERT INTO hrSample (deviceId, ts, bpm) VALUES (?, ?, ?)
                    ON CONFLICT(deviceId, ts) DO NOTHING
                    """)
                for s in streams.hr {
                    try stmt.execute(arguments: [intId, s.ts, s.bpm])
                    hr += db.changesCount
                }
            }
            if !streams.rr.isEmpty {
                let stmt = try db.cachedStatement(sql: """
                    INSERT INTO rrInterval (deviceId, ts, rrMs) VALUES (?, ?, ?)
                    ON CONFLICT(deviceId, ts, rrMs) DO NOTHING
                    """)
                for r in streams.rr {
                    try stmt.execute(arguments: [intId, r.ts, r.rrMs])
                    rr += db.changesCount
                }
            }
            return (hr, rr)
        }
    }

    // MARK: - Test helpers

    /// Stored raw-sample counts per stream — the on-device "data receipt" (proof Apple's HR/RR
    /// streams landed and persisted). F7 (reduced scope): spo2/skinTemp/resp/gravity tables were
    /// dropped in v37 (band-only, zero live consumer) — their counts are hardcoded 0 rather than
    /// removed from the tuple, because `Repository.dataReceipt()` (Cenit/Data/Repository.swift)
    /// destructures this EXACT 6-field shape and the app layer isn't rebuilt in this pass.
    public func sampleCounts() async throws
        -> (hr: Int, rr: Int, spo2: Int, skinTemp: Int, resp: Int, gravity: Int) {
        try syncRead { db in
            let hr = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM hrSample") ?? 0
            let rr = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM rrInterval") ?? 0
            return (hr, rr, 0, 0, 0, 0)
        }
    }

    /// SQLite's `PRAGMA integrity_check` — the "Verify my data" check. Returns true iff the database
    /// reports "ok" (no corruption). Thorough (full scan); the caller runs it off a button tap.
    public func integrityCheck() async throws -> Bool {
        try syncRead { db in
            let result = try String.fetchOne(db, sql: "PRAGMA integrity_check") ?? ""
            return result == "ok"
        }
    }
}
