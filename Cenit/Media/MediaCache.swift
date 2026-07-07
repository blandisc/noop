import Foundation

// MARK: - Exercise media cache (disk · FER-722/790)
//
// "Downloaded" = the file exists on disk. No GRDB table, no metadata — presence of
// `media/{id}.gif` is the whole record, following the same `applicationSupportDirectory`-based
// pattern as `StorePaths.swift`. Writes land in a `.tmp` file first and are atomically renamed into
// place, so an interrupted download never leaves a corrupt file that reads as "cached".
//
// One asset per exercise (FER-790): the ExerciseDB media is a single animated GIF that is BOTH the
// still (first frame, via `UIImage`) and the loop (all frames, via `AnimatedGIFView`) — there's no
// separate thumb/video split. `thumbPath`/`hasThumb`/`storeThumb` keep the "thumb" name for the
// callers' sake; the file itself is the whole GIF.

struct MediaCache {
    private let mediaDir: URL

    init() throws {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                 appropriateFor: nil, create: true)
            .appendingPathComponent("OpenWhoop/MediaCache", isDirectory: true)
        mediaDir = base.appendingPathComponent("media", isDirectory: true)
        try FileManager.default.createDirectory(at: mediaDir, withIntermediateDirectories: true)
    }

    func hasThumb(for exerciseId: String) -> Bool {
        FileManager.default.fileExists(atPath: thumbPath(exerciseId).path)
    }

    func thumbPath(_ exerciseId: String) -> URL {
        mediaDir.appendingPathComponent("\(Self.sanitize(exerciseId)).gif")
    }

    /// Write `data` (the GIF bytes) as the media for `exerciseId`, atomically.
    func storeThumb(_ data: Data, for exerciseId: String) throws {
        try Self.writeAtomically(data, to: thumbPath(exerciseId))
    }

    /// Clears everything cached so far. Independent of the download toggle — turning downloads off
    /// never calls this; only the explicit "Borrar media descargada" action does.
    func deleteAll() throws {
        try? FileManager.default.removeItem(at: mediaDir)
        try FileManager.default.createDirectory(at: mediaDir, withIntermediateDirectories: true)
    }

    /// `.atomic` already writes to a temp file and renames into place (same primitive as
    /// `PuffinFrameRecorder`'s capture writes) — no need to hand-roll it.
    private static func writeAtomically(_ data: Data, to destination: URL) throws {
        try data.write(to: destination, options: .atomic)
    }

    /// Exercise catalog ids are already filesystem-safe (`3_4_Sit-Up`), but normalize defensively
    /// since they come from a bundled JSON, not a controlled enum.
    private static func sanitize(_ id: String) -> String {
        id.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
            .replacingOccurrences(of: ":", with: "_")
    }
}
