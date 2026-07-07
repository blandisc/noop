// FER-789 — copies the active exercise's already-cached thumbnail into the shared App Group so the rest
// Live Activity's widget extension can render it. The widget can't read the app-local
// `applicationSupportDirectory` where `MediaCache` lives; this bridges one small JPG into the group
// container (`RestThumbnailStore`) and hands back its file name. Offline throughout: it only copies a
// file that the opt-in media download already fetched — it never hits the network. Returns nil whenever
// there's no honest image, so the caller clears the reference and the card omits the circle («no
// thumbnail» is the common, first-class case).

import Foundation

enum RestThumbnailProvider {
    /// Copy the exercise's thumb into the App Group and return its file name, or nil (media off, not
    /// cached, or the copy failed). Overwrites the single slot so the group never accumulates. Cheap (a
    /// small JPG) — runs while building the rest snapshot on the main actor.
    static func prepare(exerciseId: String, mediaEnabled: Bool) -> String? {
        guard mediaEnabled,
              let dir = RestThumbnailStore.directory,
              let cache = try? MediaCache(), cache.hasThumb(for: exerciseId) else {
            RestThumbnailStore.clear()
            return nil
        }
        let name = "\(sanitize(exerciseId)).jpg"
        RestThumbnailStore.clear()   // drop the previous rest's slot before writing the new one
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: cache.thumbPath(exerciseId),
                                             to: dir.appendingPathComponent(name))
            return name
        } catch {
            return nil
        }
    }

    /// The same filesystem-safe transform `MediaCache` applies, so the group file name matches the on-disk thumb.
    private static func sanitize(_ id: String) -> String {
        id.map { "/\\:".contains($0) ? "_" : $0 }.map(String.init).joined()
    }
}
