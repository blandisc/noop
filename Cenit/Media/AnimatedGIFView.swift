#if os(iOS)
import SwiftUI
import UIKit
import ImageIO

/// Renders a locally-cached animated GIF (FER-790). The catalog's ExerciseDB media is a GIF, not an
/// mp4 (FER-779/786), so it can't go through `AVPlayer` — this decodes the frames with ImageIO and
/// animates them in a `UIImageView`. `isPlaying` drives the hero's external play/pause control
/// (pausing freezes on a frame; playing resumes the loop). Offline by contract: `url` is always a
/// file already on disk (`MediaCache`), never streamed.
struct AnimatedGIFView: UIViewRepresentable {
    let url: URL
    var isPlaying: Bool = true

    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView()
        // `.scaleAspectFit`, not `.fill`: the ExerciseDB media is a square GIF (180×180). Filling a
        // non-square slot cropped the figure's head/feet and zoomed it (FER-790 follow-up); fitting a
        // square slot shows the whole animation with no crop.
        view.contentMode = .scaleAspectFit
        view.clipsToBounds = true
        if let decoded = Self.decode(url) {
            view.animationImages = decoded.frames
            view.animationDuration = decoded.duration
            view.animationRepeatCount = 0          // loop forever
            view.image = decoded.frames.first       // the frozen frame when paused
            if isPlaying { view.startAnimating() }
        }
        return view
    }

    func updateUIView(_ view: UIImageView, context: Context) {
        guard view.animationImages != nil else { return }
        if isPlaying, !view.isAnimating { view.startAnimating() }
        else if !isPlaying, view.isAnimating { view.stopAnimating() }
    }

    /// Decode every frame + the total loop duration from a GIF file with ImageIO. Nil if the file
    /// isn't a decodable image (a corrupt/partial download → the caller falls back to the placeholder).
    private static func decode(_ url: URL) -> (frames: [UIImage], duration: TimeInterval)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { return nil }
        var frames: [UIImage] = []
        var duration: TimeInterval = 0
        for i in 0..<count {
            guard let cg = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
            frames.append(UIImage(cgImage: cg))
            duration += frameDelay(source, i)
        }
        guard !frames.isEmpty else { return nil }
        if duration <= 0 { duration = Double(frames.count) / 20.0 }   // ~20 fps fallback for a still-ish GIF
        return (frames, duration)
    }

    /// Per-frame delay from the GIF metadata. Prefers the unclamped value; floors sub-0.02s delays to
    /// 0.1s the way browsers/UIKit do, so a "0 delay" GIF doesn't render as an unwatchable blur.
    private static func frameDelay(_ source: CGImageSource, _ index: Int) -> TimeInterval {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
              let gif = props[kCGImagePropertyGIFDictionary] as? [CFString: Any] else { return 0.1 }
        let delay = (gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
            ?? (gif[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.1
        return delay < 0.02 ? 0.1 : delay
    }
}
#endif
