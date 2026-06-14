import Foundation
import Combine
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif
import UniformTypeIdentifiers
import WhoopStore

/// Full-database EXPORT / IMPORT for device migration.
///
/// NOOP keeps everything in one SQLite file (`<AppSupport>/OpenWhoop/whoop.sqlite`, plus the
/// `-wal`/`-shm` WAL sidecars while the store is open). Moving to another Mac is therefore just a
/// matter of moving that file. Export checkpoints the WAL (so the single file is whole) and copies
/// it to a user-chosen location; import validates a chosen backup, snapshots the current DB to a
/// side file, drops the backup in over the live path, and asks the user to relaunch (the store is
/// held open, so the new file can't be swapped in live).
///
/// Sandbox-safe: relies on the `com.apple.security.files.user-selected.read-write` entitlement and
/// security-scoped access on the panel-returned URLs. Every path is best-effort — failures surface
/// as a `.failure` result and never crash.
enum DataBackup {

    // MARK: - Result

    enum BackupResult {
        /// Export wrote the backup to `url`.
        case exported(URL)
        /// Import succeeded; a relaunch is required for it to take effect. `sidecar` is where the
        /// previous database was preserved, in case the user wants to roll back.
        case imported(sidecar: URL)
        /// The user dismissed the save/open panel — nothing happened, show nothing loud.
        case cancelled
        /// Something went wrong; `message` is user-facing.
        case failure(String)
    }

    // MARK: - Export

    /// Checkpoint (if the store is reachable) and copy the live database to a user-chosen file.
    ///
    /// - Parameter checkpoint: invoked first to flush the WAL into the main file. Pass
    ///   `repo.checkpointForBackup`; returns whether a checkpoint actually ran. When it doesn't
    ///   (store not open yet, or it failed), we copy the on-disk files as-is — including any `-wal`
    ///   sidecar — so the backup is still complete, just not consolidated.
    @MainActor
    static func runExport(checkpoint: @escaping () async -> Bool) async -> BackupResult {
        let dbPath: String
        do { dbPath = try StorePaths.defaultDatabasePath() }
        catch { return .failure("Couldn't locate the NOOP database. \(error.localizedDescription)") }

        let dbURL = URL(fileURLWithPath: dbPath)
        guard FileManager.default.fileExists(atPath: dbPath) else {
            return .failure("There's no NOOP data to export yet. Import or record some first.")
        }

        // Flush the WAL so the single .sqlite carries everything. Best-effort.
        let checkpointed = await checkpoint()

        #if os(macOS)
        // Ask where to save.
        let panel = NSSavePanel()
        panel.title = "Export NOOP backup"
        panel.prompt = "Export"
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = defaultBackupName()
        panel.allowedContentTypes = sqliteContentTypes()
        panel.isExtensionHidden = false

        guard panel.runModal() == .OK, let dest = panel.url else { return .cancelled }

        let scoped = dest.startAccessingSecurityScopedResource()
        defer { if scoped { dest.stopAccessingSecurityScopedResource() } }

        let fm = FileManager.default
        do {
            // NSSavePanel already handled the "replace existing?" confirmation; clear the target.
            if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
            try fm.copyItem(at: dbURL, to: dest)

            // If we couldn't checkpoint, fold any pending WAL into the side copy so the backup is
            // self-contained. We can't run SQLite over the destination safely here, so instead we
            // copy the sidecars next to it under the same base name; importing copies only the main
            // file, but at least nothing is silently lost. In practice the store is almost always
            // open and the checkpoint succeeds, leaving no WAL to worry about.
            if !checkpointed {
                copySidecarsIfPresent(from: dbURL, toMainBackup: dest)
            }
            return .exported(dest)
        } catch {
            return .failure("Export failed: \(error.localizedDescription)")
        }
        #else
        // iOS: DocumentPicker.export only carries a single file, so we cannot fall back to copying
        // the -wal/-shm sidecars the way macOS does. If the checkpoint above didn't fold the WAL
        // into the main file, the staged copy would silently omit everything written since the last
        // automatic checkpoint. Fail loudly instead of producing a partial backup.
        guard checkpointed else {
            return .failure("Couldn't safely export right now — recent changes are still in the database's write-ahead log. Close any in-flight sync, then try again.")
        }
        let fm = FileManager.default
        let staged = fm.temporaryDirectory.appendingPathComponent(defaultBackupName())
        do {
            if fm.fileExists(atPath: staged.path) { try fm.removeItem(at: staged) }
            try fm.copyItem(at: dbURL, to: staged)
        } catch {
            return .failure("Export failed: \(error.localizedDescription)")
        }
        guard let dest = await DocumentPicker.export(staged) else { return .cancelled }
        return .exported(dest)
        #endif
    }

    // MARK: - Import

    /// Pick a `.sqlite` backup, validate it, snapshot the current DB to a side file, then copy the
    /// backup over the live database path (removing the `-wal`/`-shm` siblings). The store stays
    /// open, so the swapped-in file only takes effect after a relaunch — the caller informs the user.
    @MainActor
    static func runImport() async -> BackupResult {
        let dbPath: String
        do { dbPath = try StorePaths.defaultDatabasePath() }
        catch { return .failure("Couldn't locate the NOOP database. \(error.localizedDescription)") }

        #if os(macOS)
        let panel = NSOpenPanel()
        panel.title = "Import NOOP backup"
        panel.prompt = "Import"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = sqliteContentTypes()

        guard panel.runModal() == .OK, let source = panel.url else { return .cancelled }

        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        #else
        // iOS: pick the backup through the system document picker (asCopy gives us a readable local
        // copy in our temp dir, so no security-scoped bookkeeping is needed).
        guard let source = await DocumentPicker.importFile(sqliteContentTypes()) else { return .cancelled }
        #endif

        // Validate: must be a real SQLite database (magic header "SQLite format 3\0").
        guard isSQLiteFile(at: source) else {
            return .failure("That file isn't a NOOP backup — it doesn't look like a SQLite database.")
        }

        let fm = FileManager.default
        let dbURL = URL(fileURLWithPath: dbPath)

        do {
            // Snapshot the current DB (+ sidecars) to a timestamped side file so the user can roll back.
            var sidecar = dbURL.deletingLastPathComponent()
                .appendingPathComponent("whoop-replaced-\(timestamp()).sqlite")
            if fm.fileExists(atPath: dbURL.path) {
                if fm.fileExists(atPath: sidecar.path) { try fm.removeItem(at: sidecar) }
                try fm.copyItem(at: dbURL, to: sidecar)
            } else {
                // Nothing to preserve (fresh install); report a placeholder so the message reads sensibly.
                sidecar = dbURL
            }

            // Remove the live DB and its WAL/SHM siblings, then drop the backup in.
            removeIfPresent(dbURL)
            removeIfPresent(URL(fileURLWithPath: dbPath + "-wal"))
            removeIfPresent(URL(fileURLWithPath: dbPath + "-shm"))

            try fm.copyItem(at: source, to: dbURL)
            return .imported(sidecar: sidecar)
        } catch {
            return .failure("Import failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    /// "NOOP-backup-2026-06-07.sqlite"
    private static func defaultBackupName() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return "NOOP-backup-\(f.string(from: Date())).sqlite"
    }

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        return f.string(from: Date())
    }

    /// `.sqlite` UTType if the system knows it, always falling back to the generic database type so
    /// the panels still open on systems without a `.sqlite` declaration.
    private static func sqliteContentTypes() -> [UTType] {
        var types: [UTType] = []
        if let sqlite = UTType(filenameExtension: "sqlite") { types.append(sqlite) }
        types.append(.database)
        types.append(.data)
        return types
    }

    /// Read the first 16 bytes and check for the SQLite magic header.
    private static func isSQLiteFile(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: 16), head.count >= 16 else { return false }
        // "SQLite format 3" + NUL terminator.
        let magic: [UInt8] = Array("SQLite format 3".utf8) + [0x00]
        return Array(head) == magic
    }

    private static func removeIfPresent(_ url: URL) {
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) { try? fm.removeItem(at: url) }
    }

    /// Copy `<db>-wal`/`<db>-shm` next to the main backup, under the backup's base name, if they
    /// exist on disk (only reached when the checkpoint didn't run). Best-effort — failures are ignored.
    private static func copySidecarsIfPresent(from dbURL: URL, toMainBackup dest: URL) {
        let fm = FileManager.default
        for suffix in ["-wal", "-shm"] {
            let side = URL(fileURLWithPath: dbURL.path + suffix)
            guard fm.fileExists(atPath: side.path) else { continue }
            let target = URL(fileURLWithPath: dest.path + suffix)
            if fm.fileExists(atPath: target.path) { try? fm.removeItem(at: target) }
            try? fm.copyItem(at: side, to: target)
        }
    }
}

#if os(iOS)

/// Near-automatic backup of the single NOOP database to a folder in the user's own iCloud Drive.
///
/// Why this is its own thing (vs the manual `DataBackup` export): the strap's offloaded raw streams
/// live ONLY in `whoop.sqlite` — the strap trims its copy the moment NOOP acks the offload (see
/// `Backfiller`). Apple Health re-syncs from the system vault and imported CSVs are re-importable, so
/// the strap history is the one irreplaceable thing. Losing the app's container (a delete, a fresh
/// install, a lost phone) loses it for good.
///
/// On a free Apple ID we can't use an iCloud *container* entitlement, but the user can point us at a
/// folder in their own iCloud Drive once; the resulting security-scoped **bookmark** lets us drop a
/// fresh copy there on later launches with no further prompts and no entitlement. iCloud syncs the
/// file off-device, so it survives a delete or a new phone. Restore reuses `DataBackup.runImport`.
///
/// Honest ceiling: iCloud uploads when the OS decides (usually minutes), and we can only write while
/// the app is awake — which it is right after a strap sync, exactly when new data exists. The
/// bookmark itself lives in `UserDefaults` (wiped on delete), so after a reinstall the user re-picks
/// the folder once; the backup file in iCloud Drive is what carries the data across.
@MainActor
final class AutoBackup: ObservableObject {
    /// Display name of the chosen iCloud Drive folder, or nil if auto-backup isn't set up.
    @Published private(set) var destinationName: String?
    /// When the last successful backup landed. Drives the "Last backup … ago" status line.
    @Published private(set) var lastBackup: Date?
    /// Most recent failure (lost folder access, write error). Cleared on a successful backup.
    @Published private(set) var lastError: String?
    /// True while a copy is in flight — disables the buttons so a double-tap can't race.
    @Published private(set) var busy = false

    private let defaults = UserDefaults.standard
    private let bookmarkKey = "noop.autoBackup.folderBookmark"
    private let nameKey = "noop.autoBackup.folderName"
    private let lastKey = "noop.autoBackup.lastDate"
    /// At most one automatic backup per ~day; the manual "Back up now" ignores this.
    private let minInterval: TimeInterval = 23 * 3_600
    private let fileName = "NOOP-backup.sqlite"

    init() {
        destinationName = defaults.string(forKey: nameKey)
        if let t = defaults.object(forKey: lastKey) as? Double { lastBackup = Date(timeIntervalSince1970: t) }
    }

    /// Whether a destination folder has been chosen (auto-backup is armed).
    var isConfigured: Bool { defaults.data(forKey: bookmarkKey) != nil }

    // MARK: - Setup

    /// Present the folder picker and persist a security-scoped bookmark to the chosen folder.
    /// Guide the user toward an iCloud Drive folder so the backup leaves the device.
    func chooseFolder() async {
        guard let url = await DocumentPicker.pickFolder() else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let bm = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            defaults.set(bm, forKey: bookmarkKey)
            defaults.set(url.lastPathComponent, forKey: nameKey)
            destinationName = url.lastPathComponent
            lastError = nil
        } catch {
            lastError = String(localized: "Couldn't remember that folder. Try a folder in iCloud Drive.")
        }
    }

    /// Forget the destination (stops automatic backups). The backup file already in iCloud Drive is
    /// left untouched, so a later "Restore" still finds it.
    func disable() {
        defaults.removeObject(forKey: bookmarkKey)
        defaults.removeObject(forKey: nameKey)
        destinationName = nil
    }

    // MARK: - Backup

    /// Throttled automatic backup — no-op without a destination or if the last one is recent.
    func backupIfDue(checkpoint: () async -> Bool) async {
        guard isConfigured else { return }
        if let last = lastBackup, Date().timeIntervalSince(last) < minInterval { return }
        await backupNow(checkpoint: checkpoint)
    }

    /// Copy the live database into the chosen iCloud Drive folder now. Safe to call repeatedly.
    func backupNow(checkpoint: () async -> Bool) async {
        guard !busy, isConfigured else { return }
        busy = true
        defer { busy = false }

        guard let folder = resolveFolder() else {
            lastError = String(localized: "Lost access to the backup folder — choose it again.")
            return
        }
        let scoped = folder.startAccessingSecurityScopedResource()   // process-wide; held across the await below
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }

        // Fold the WAL into the main file so a plain copy is whole. The store is open during normal
        // use, so this succeeds; if it doesn't, skip this round rather than ship a half file.
        guard await checkpoint() else {
            lastError = String(localized: "Couldn't snapshot the database just now — will retry.")
            return
        }

        let dbPath: String
        do { dbPath = try StorePaths.defaultDatabasePath() }
        catch { lastError = String(localized: "Couldn't locate the NOOP database."); return }
        let dbURL = URL(fileURLWithPath: dbPath)
        guard FileManager.default.fileExists(atPath: dbPath) else {
            lastError = String(localized: "No database to back up yet.")
            return
        }

        let dest = folder.appendingPathComponent(fileName)
        let prev = folder.appendingPathComponent(fileName + ".prev")
        // Offload the blocking file IO so a multi-MB copy doesn't hitch the UI.
        let error = await Task.detached { AutoBackup.writeCopy(db: dbURL, to: dest, keepingPrev: prev) }.value
        if let error {
            lastError = String(localized: "Backup couldn't be saved: \(error.localizedDescription)")
            return
        }
        let now = Date()
        lastBackup = now
        defaults.set(now.timeIntervalSince1970, forKey: lastKey)
        lastError = nil
    }

    // MARK: - Helpers

    /// Resolve the stored bookmark back to a usable folder URL, refreshing it if iOS marks it stale.
    private func resolveFolder() -> URL? {
        guard let bm = defaults.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bm, options: [], relativeTo: nil,
                                 bookmarkDataIsStale: &stale) else { return nil }
        if stale, url.startAccessingSecurityScopedResource() {
            defer { url.stopAccessingSecurityScopedResource() }
            if let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
                defaults.set(fresh, forKey: bookmarkKey)
            }
        }
        return url
    }

    /// Coordinated copy of the DB into `dest`, rotating the prior backup to `keepingPrev` first as
    /// cheap insurance against a corrupt write. Runs off the main actor. Returns nil on success.
    private nonisolated static func writeCopy(db: URL, to dest: URL, keepingPrev prev: URL) -> Error? {
        let coordinator = NSFileCoordinator()
        var coordError: NSError?
        var writeError: Error?
        coordinator.coordinate(writingItemAt: dest, options: .forReplacing, error: &coordError) { target in
            let fm = FileManager.default
            do {
                if fm.fileExists(atPath: target.path) {
                    try? fm.removeItem(at: prev)
                    do { try fm.moveItem(at: target, to: prev) }
                    catch { try? fm.removeItem(at: target) }   // ensure the path is clear for the copy
                }
                try fm.copyItem(at: db, to: target)
            } catch {
                writeError = error
            }
        }
        return writeError ?? coordError
    }
}
#endif
