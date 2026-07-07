#if os(iOS)
import SwiftUI
import UIKit
import StrandDesign
import StrandTraining

// MARK: - ExerciseThumbView — the row thumbnail, filled with the cached GIF's still (FER-790)
//
// `ExerciseThumbnail` (StrandDesign) reserves the slot and draws the paper placeholder; this wraps it
// and, when the exercise's GIF is ALREADY cached, fills it with the GIF's first frame. It never
// downloads (rows scroll through ~1500 exercises — a per-row GET is out of the question): it asks the
// coordinator for a cached path only, decodes the still off the main thread, and memoizes it in a
// bounded cache so scrolling back doesn't re-decode. Toggle off, no cache, or an exercise with no
// media → the plain placeholder, exactly as before.
struct ExerciseThumbView: View {
    let exercise: Exercise
    let side: CGFloat

    @EnvironmentObject private var mediaCoordinator: MediaDownloadCoordinator
    @State private var image: Image?

    var body: some View {
        ExerciseThumbnail(side: side, image: image)
            .task(id: exercise.id) { await load() }
    }

    private func load() async {
        guard image == nil, mediaCoordinator.isEnabled,
              let url = mediaCoordinator.cachedMediaURL(for: exercise) else { return }
        if let ui = await ExerciseThumbStillCache.shared.still(at: url, id: exercise.id) {
            image = Image(uiImage: ui)
        }
    }
}

/// Bounded in-memory cache of decoded GIF first-frames, keyed by exercise id. `UIImage(contentsOfFile:)`
/// on a GIF yields its first frame; decoding happens off the main actor. `NSCache` is thread-safe and
/// evicts under memory pressure, so the still catalog never pins unbounded memory.
final class ExerciseThumbStillCache {
    static let shared = ExerciseThumbStillCache()
    private let cache = NSCache<NSString, UIImage>()

    private init() { cache.countLimit = 300 }

    func still(at url: URL, id: String) async -> UIImage? {
        if let hit = cache.object(forKey: id as NSString) { return hit }
        let decoded = await Task.detached(priority: .utility) { UIImage(contentsOfFile: url.path) }.value
        if let decoded { cache.setObject(decoded, forKey: id as NSString) }
        return decoded
    }
}
#endif
