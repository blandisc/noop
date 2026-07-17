import Foundation
import GRDB
import WhoopProtocol

/// OpenWhoop persistence library — decoded streams are durable; raw frames are a
/// transient, compressed, prunable outbox. Built on GRDB/SQLite.
public enum WhoopStoreInfo {
    /// DERIVADO del migrador (los ids son contiguos v1…vN — fijado por
    /// MigrationTests.testMigratorRegistersContiguousVersions). Nunca se bumpea a mano:
    /// la constante manual llegó a decir 31 con el migrador real en v35.
    public static var schemaVersion: Int { WhoopStore.makeMigrator().migrations.count }
    /// Último identificador de migración registrado, p. ej. "v35". Para diagnóstico.
    public static var latestMigration: String { WhoopStore.makeMigrator().migrations.last ?? "v0" }
}

/// WhoopStore is an `actor`: its public API is `async`, and all GRDB work runs on the
/// actor's serial executor rather than the caller's (the main actor). GRDB calls are
/// synchronous-blocking; the actor moves them off the main thread and keeps WRITES
/// serialized (a single writer per handle) — that part of the old "DatabaseQueue kept, not
/// DatabasePool" rationale still holds. What the single connection also did — and was never
/// the goal — was queue READS behind long writes. FER-970 (R-04): the BLE handle stays a
/// `DatabaseQueue` (default backend); the Repository handle opens a `DatabasePool`, so the
/// nonisolated bulk read (`dashboardSnapshot`) runs on WAL reader connections and never
/// waits behind a long engine/import write on the same handle.
public actor WhoopStore {
    /// Connection backend. `.queue` = the historical single-connection behavior, byte-identical
    /// (BLE handle, in-memory tests). `.pool(maxReaders:)` = WAL reader pool (Repository handle).
    public enum Backend: Sendable {
        case queue
        case pool(maxReaders: Int)
    }

    let dbWriter: any DatabaseWriter

    /// Cache of the source-partition `deviceId` (TEXT) → integer surrogate (`deviceIdMap`) translation
    /// (v21). Actor-isolated so it needs no lock; populated lazily by `resolvedDeviceId`. Tiny (one entry
    /// per source partition; today just "my-whoop").
    private var deviceIdCache: [String: Int64] = [:]

    private init(dbWriter: any DatabaseWriter) throws {
        self.dbWriter = dbWriter
        try WhoopStore.makeMigrator().migrate(dbWriter)
    }

    /// Translate a source-partition `deviceId` String → its integer surrogate (`deviceIdMap`, v21), cached.
    /// READ path (`createIfMissing: false`): returns nil for an unknown id, so the read yields `[]` —
    /// identical to the old behavior of a deviceId with no rows. WRITE path (`createIfMissing: true`):
    /// inserts the mapping on demand and NEVER returns nil, so `insert()` can't throw on a missing mapping
    /// — which is what keeps the Backfiller (it acks+trims history even if `insert` fails) from losing
    /// acked data irreversibly. Actor-serialized → the check-then-insert can't race.
    func resolvedDeviceId(_ deviceId: String, createIfMissing: Bool) async throws -> Int64? {
        if let cached = deviceIdCache[deviceId] { return cached }
        if let existing = try syncRead({ db in
            try Int64.fetchOne(db, sql: "SELECT intId FROM deviceIdMap WHERE deviceId = ?", arguments: [deviceId])
        }) {
            deviceIdCache[deviceId] = existing
            return existing
        }
        guard createIfMissing else { return nil }
        let intId = try syncWrite { db -> Int64 in
            try db.execute(sql: """
                INSERT OR IGNORE INTO deviceIdMap (deviceId, intId)
                VALUES (?, (SELECT COALESCE(MAX(intId), 0) + 1 FROM deviceIdMap))
                """, arguments: [deviceId])
            return try Int64.fetchOne(db, sql: "SELECT intId FROM deviceIdMap WHERE deviceId = ?", arguments: [deviceId])!
        }
        deviceIdCache[deviceId] = intId
        return intId
    }

    /// Open (creating if needed) a database at `path` and run migrations.
    /// Enables WAL journal mode and a 5-second busy timeout so two handles to the same
    /// file (BLEManager + MetricsRepository) don't deadlock on write contention.
    public init(path: String, backend: Backend = .queue) async throws {
        var config = Configuration()
        config.prepareDatabase { db in
            // FER-970 (R-04): a pool runs `prepareDatabase` on its READ-ONLY reader connections
            // too — the write-mode PRAGMAs must be guarded or opening a reader throws and takes
            // every read down with it. The tuning PRAGMAs below apply to all connections.
            if !db.configuration.readonly {
                // INCREMENTAL auto-vacuum so freed pages can be reclaimed without a full file rewrite
                // (FER-511 and the later size work). On a FRESH DB this takes effect immediately (set
                // before any table is created, below); on an EXISTING DB it's a no-op until the one-time
                // VACUUM (AppModel.compactDatabaseAfterSpo2PurgeIfNeeded) converts the file.
                try db.execute(sql: "PRAGMA auto_vacuum = INCREMENTAL")
                try db.execute(sql: "PRAGMA journal_mode = WAL")
                // Bulk-write/read tuning. NORMAL is the durable, recommended pairing with WAL (only an
                // OS crash/power loss can lose the last transaction — acceptable here). Bigger page cache
                // + mmap + in-memory temp tables speed the multi-thousand-row import/backfill writes.
                try db.execute(sql: "PRAGMA synchronous = NORMAL")
            }
            try db.execute(sql: "PRAGMA cache_size = -16000")     // ~16 MB page cache
            try db.execute(sql: "PRAGMA mmap_size = 268435456")   // 256 MB memory-mapped I/O
            try db.execute(sql: "PRAGMA temp_store = MEMORY")
        }
        config.busyMode = .timeout(5)
        switch backend {
        case .queue:
            try self.init(dbWriter: try DatabaseQueue(path: path, configuration: config))
        case .pool(let maxReaders):
            config.maximumReaderCount = max(1, maxReaders)
            try self.init(dbWriter: try DatabasePool(path: path, configuration: config))
        }
    }

    /// An in-memory store (migrations applied). For tests. Always a `DatabaseQueue`
    /// (`DatabasePool` has no in-memory mode).
    public static func inMemory() async throws -> WhoopStore {
        try WhoopStore(dbWriter: try DatabaseQueue())
    }

    // MARK: - Synchronous GRDB helpers
    // GRDB 6 marks its sync read/write overloads @_disfavoredOverload so that in an async
    // context Swift would otherwise pick the async overloads. These thin wrappers are
    // regular (non-async) functions, so overload resolution always selects the synchronous
    // GRDB API — which then blocks on the actor's serial executor (off main thread).

    @inline(__always)
    func syncRead<T>(_ block: (Database) throws -> T) throws -> T {
        try dbWriter.read(block)
    }

    @inline(__always)
    func syncWrite<T>(_ block: (Database) throws -> T) throws -> T {
        try dbWriter.write(block)
    }

    // MARK: - Maintenance

    /// Fully checkpoint the WAL into the main database file and truncate the -wal file.
    /// Used before a file-level backup so the single `whoop.sqlite` carries all committed data
    /// (the -wal/-shm siblings can then be ignored). Runs outside a transaction — `wal_checkpoint`
    /// must. Best-effort: throws on a hard SQLite error so callers can fall back to a plain copy.
    public func checkpointWAL() async throws {
        try checkpointWALImpl()
    }

    /// Non-async so GRDB's synchronous `writeWithoutTransaction` overload is chosen (mirrors the
    /// syncRead/syncWrite pattern). Runs on the actor's executor, off the main thread.
    private func checkpointWALImpl() throws {
        // FER-970 (R-04): barrier — on a pool, `wal_checkpoint(TRUNCATE)` needs no readers alive;
        // on a queue (single connection) it's exactly the old behavior.
        try dbWriter.barrierWriteWithoutTransaction { db in
            try db.execute(sql: "PRAGMA wal_checkpoint(TRUNCATE)")
        }
    }

    /// Rebuild the database file with SQLite `VACUUM`, returning free pages (e.g. those left by the
    /// FER-511 spo2 purge) to the OS so the `.sqlite` actually shrinks — a plain DELETE only marks
    /// pages reusable. Also converts an existing file to the INCREMENTAL auto-vacuum mode set in
    /// `prepareDatabase`. Heavy (rewrites the whole file): callers run it once, gated, off the launch
    /// path. `VACUUM` must run outside a transaction, so this uses `writeWithoutTransaction` (mirrors
    /// `checkpointWALImpl`); it runs on the actor's executor, off the main thread.
    public func vacuum() async throws {
        try vacuumImpl()
    }

    /// Non-async so GRDB's synchronous `writeWithoutTransaction` overload is chosen (mirrors
    /// `checkpointWALImpl`). Runs on the actor's executor, off the main thread.
    private func vacuumImpl() throws {
        // FER-970 (R-04): barrier for the same reason as the checkpoint — VACUUM rewrites the file.
        try dbWriter.barrierWriteWithoutTransaction { db in
            try db.execute(sql: "VACUUM")
        }
    }

    /// SQLite `PRAGMA page_count` — total pages in the main DB file. Tests use it to prove a
    /// purge + `vacuum()` actually shrinks the file (page_count drops), not just frees pages.
    public func pageCountForTest() async throws -> Int {
        try syncRead { db in try Int.fetchOne(db, sql: "PRAGMA page_count") ?? 0 }
    }

    // MARK: - Introspection (used by tests)

    public func tableNames() async throws -> Set<String> {
        try syncRead { db in
            try Set(String.fetchAll(db,
                sql: "SELECT name FROM sqlite_master WHERE type = 'table'"))
        }
    }

    public func primaryKeyColumns(_ table: String) async throws -> [String] {
        try syncRead { db in
            try db.primaryKey(table).columns
        }
    }

    public func columnNamesForTest(table: String) async throws -> [String] {
        try syncRead { db in
            try db.columns(in: table).map(\.name)
        }
    }

    public func indexNamesForTest(table: String) async throws -> Set<String> {
        try syncRead { db in
            try Set(db.indexes(on: table).map(\.name))
        }
    }

    /// The `EXPLAIN QUERY PLAN` detail lines for a statement. Tests use this to assert the hot reads
    /// hit an index (a `SEARCH … USING …` step) rather than a bare full-table `SCAN` (FER-29). The
    /// bound argument *values* don't affect the chosen plan, but the placeholder count must match.
    public func queryPlanForTest(_ sql: String, arguments: StatementArguments = StatementArguments()) async throws -> [String] {
        try syncRead { db in
            try Row.fetchAll(db, sql: "EXPLAIN QUERY PLAN \(sql)", arguments: arguments)
                .map { ($0["detail"] as String?) ?? "" }
        }
    }
}
