import Foundation

/// Top-level entry points for Strand's data import. Takes a `URL` (a folder,
/// `export.zip`, or `export.xml`) and returns the normalized model arrays plus
/// an `ImportSummary` (record count + date range).
///
/// This layer is **parsing only** — it does not touch the database. Persistence
/// is wired in a later integration step; keeping the coordinator pure makes the
/// whole package unit-testable.
public struct ImportCoordinator {

    private let appleHealth: AppleHealthImporter

    public init(appleHealth: AppleHealthImporter = AppleHealthImporter()) {
        self.appleHealth = appleHealth
    }

    // MARK: - Explicit-kind entry point

    /// Parse an Apple Health export (`export.zip`, `export.xml`, or a folder).
    /// `progress` fires periodically with the element count (off the main thread).
    public func importAppleHealth(
        from url: URL,
        progress: AppleHealthImporter.ProgressHandler? = nil,
        isCancelled: (@Sendable () -> Bool)? = nil
    ) throws -> AppleHealthImportResult {
        try appleHealth.import(from: url, progress: progress, isCancelled: isCancelled)
    }

    // MARK: - Auto-detecting entry point

    /// The detected kind plus its result payload.
    public enum DetectedImport: Sendable, Equatable {
        case appleHealth(AppleHealthImportResult)

        public var kind: DataSourceKind {
            switch self {
            case .appleHealth: return .appleHealth
            }
        }

        public var summary: ImportSummary {
            switch self {
            case .appleHealth(let r): return r.summary
            }
        }
    }

    /// Inspect the input and route to the correct importer.
    ///
    /// Detection heuristics, in order:
    /// - A path/entry named `export.xml` → Apple Health.
    /// - A folder/zip containing any other non-CDA `.xml` → Apple Health (the
    ///   export's filename is localized by device language: `exportación.xml`, …).
    public func detectAndImport(from url: URL) throws -> DetectedImport {
        switch try detectKind(of: url) {
        case .appleHealth:
            return .appleHealth(try appleHealth.import(from: url))
        }
    }

    /// Determine which kind of export a URL points at without parsing it fully.
    public func detectKind(of url: URL) throws -> DataSourceKind {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else {
            throw ImportError.fileNotFound(url.path)
        }

        let ext = url.pathExtension.lowercased()
        if ext == "xml" { return .appleHealth }

        let names = try entryFilenames(of: url, isDirectory: isDir.boolValue)
        if names.contains("export.xml") { return .appleHealth }
        // Apple localizes the export's filename by device language
        // ("exportación.xml", "Export.xml", …) — accept any non-CDA .xml as a
        // fallback, after the exact-name check above.
        if names.contains(where: AppleHealthImporter.isHealthExportXMLName) { return .appleHealth }

        throw ImportError.notAZipOrFolder(url.path)
    }

    // MARK: - Helpers

    /// Lowercased base filenames present in a folder or zip (shallow scan of all
    /// entries; cheap because we only read the zip's central directory or list
    /// the folder).
    private func entryFilenames(of url: URL, isDirectory: Bool) throws -> Set<String> {
        let fm = FileManager.default
        var names: Set<String> = []

        if isDirectory {
            if let e = fm.enumerator(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                for case let u as URL in e {
                    names.insert(u.lastPathComponent.lowercased())
                }
            }
            return names
        }

        // A file: peek into it as a zip via the importer-agnostic helper.
        if let zipNames = try? ZipPeek.filenames(in: url) {
            return zipNames
        }
        // Not a zip — just record the single filename.
        names.insert(url.lastPathComponent.lowercased())
        return names
    }
}

// MARK: - Lightweight zip listing

import ZIPFoundation

/// Reads only the zip central directory to list base filenames — no extraction.
enum ZipPeek {
    static func filenames(in zipURL: URL) throws -> Set<String> {
        let archive = try Archive(url: zipURL, accessMode: .read)
        var names: Set<String> = []
        for entry in archive where entry.type == .file {
            names.insert((entry.path as NSString).lastPathComponent.lowercased())
        }
        return names
    }
}
