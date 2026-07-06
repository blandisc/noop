import Foundation

// MARK: - Exercise media cache (disk · FER-722)
//
// "Downloaded" = the file exists on disk. No GRDB table, no metadata — presence of
// `thumbs/{id}.jpg` / `videos/{id}.mp4` is the whole record, following the same
// `applicationSupportDirectory`-based pattern as `StorePaths.swift`. Writes land in a `.tmp` file
// first and are atomically renamed into place, so an interrupted download never leaves a corrupt
// file that reads as "cached".

struct MediaCache {
    private let thumbsDir: URL
    private let videosDir: URL

    init() throws {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                 appropriateFor: nil, create: true)
            .appendingPathComponent("OpenWhoop/MediaCache", isDirectory: true)
        thumbsDir = base.appendingPathComponent("thumbs", isDirectory: true)
        videosDir = base.appendingPathComponent("videos", isDirectory: true)
        try FileManager.default.createDirectory(at: thumbsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: videosDir, withIntermediateDirectories: true)
    }

    func hasThumb(for exerciseId: String) -> Bool {
        FileManager.default.fileExists(atPath: thumbPath(exerciseId).path)
    }

    func thumbPath(_ exerciseId: String) -> URL {
        thumbsDir.appendingPathComponent("\(Self.sanitize(exerciseId)).jpg")
    }

    func videoURL(for exerciseId: String) -> URL? {
        let path = videosDir.appendingPathComponent("\(Self.sanitize(exerciseId)).mp4")
        return FileManager.default.fileExists(atPath: path.path) ? path : nil
    }

    /// Write `data` as the thumb for `exerciseId`, atomically.
    func storeThumb(_ data: Data, for exerciseId: String) throws {
        try Self.writeAtomically(data, to: thumbPath(exerciseId))
    }

    /// Download `url` and store it as the video/loop for `exerciseId`, atomically; returns the
    /// final on-disk location.
    func storeVideo(from url: URL, for exerciseId: String, session: URLSession) async throws -> URL {
        let (data, _) = try await session.data(from: url)
        let destination = videosDir.appendingPathComponent("\(Self.sanitize(exerciseId)).mp4")
        try Self.writeAtomically(data, to: destination)
        return destination
    }

    /// Clears everything cached so far. Independent of the download toggle — turning downloads off
    /// never calls this; only the explicit "Borrar media descargada" action does.
    func deleteAll() throws {
        try? FileManager.default.removeItem(at: thumbsDir)
        try? FileManager.default.removeItem(at: videosDir)
        try FileManager.default.createDirectory(at: thumbsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: videosDir, withIntermediateDirectories: true)
    }

    private static func writeAtomically(_ data: Data, to destination: URL) throws {
        let tmp = destination.appendingPathExtension("tmp")
        try data.write(to: tmp, options: .atomic)
        _ = try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: tmp, to: destination)
    }

    /// Exercise catalog ids are already filesystem-safe (`3_4_Sit-Up`), but normalize defensively
    /// since they come from a bundled JSON, not a controlled enum.
    private static func sanitize(_ id: String) -> String {
        id.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
            .replacingOccurrences(of: ":", with: "_")
    }
}
