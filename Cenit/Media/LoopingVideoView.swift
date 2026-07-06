#if os(iOS)
import SwiftUI
import AVFoundation

/// Silently loops a locally-cached exercise clip (FER-722). No controls, no network — `url` is
/// always a file already on disk (`MediaCache`), never streamed.
struct LoopingVideoView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PlayerLoopingView {
        PlayerLoopingView(url: url)
    }

    func updateUIView(_ uiView: PlayerLoopingView, context: Context) {}

    final class PlayerLoopingView: UIView {
        private var looper: AVPlayerLooper?
        private let queuePlayer = AVQueuePlayer()

        init(url: URL) {
            super.init(frame: .zero)
            let item = AVPlayerItem(url: url)
            looper = AVPlayerLooper(player: queuePlayer, templateItem: item)
            queuePlayer.isMuted = true
            let layer = AVPlayerLayer(player: queuePlayer)
            layer.videoGravity = .resizeAspectFill
            self.layer.addSublayer(layer)
            playerLayer = layer
            queuePlayer.play()
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        private var playerLayer: AVPlayerLayer?
        override func layoutSubviews() {
            super.layoutSubviews()
            playerLayer?.frame = bounds
        }
    }
}
#endif
