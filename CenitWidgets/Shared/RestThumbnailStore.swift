// FER-789 — the shared App Group location of the rest Live Activity's exercise thumbnail.
//
// Shared source: compiled into BOTH the app (which writes the file, via `RestThumbnailProvider`) and the
// widget extension (which reads it, in `RestLiveActivity`). Keeping the path in one place means the two
// processes can never disagree on where the image lives. A single file, overwritten each rest, so the
// group container never accumulates. The «no thumbnail» state is first-class: every accessor returns nil
// when there's no image, and the card then omits the circle entirely (no placeholder).

import Foundation

enum RestThumbnailStore {
    private static let dirName = "RestThumb"

    /// The directory in the shared App Group container, or nil when the container is unavailable.
    static var directory: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: RestActivityBridge.appGroup)?
            .appendingPathComponent(dirName, isDirectory: true)
    }

    /// The file URL for a prepared thumbnail name, only when the file actually exists (else nil → omit).
    static func url(for name: String?) -> URL? {
        guard let name, !name.isEmpty, let dir = directory else { return nil }
        let u = dir.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: u.path) ? u : nil
    }

    /// Remove the thumbnail directory — called when the rest/session ends so no stale image lingers.
    static func clear() {
        guard let dir = directory else { return }
        try? FileManager.default.removeItem(at: dir)
    }
}
