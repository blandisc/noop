import Foundation
import Combine
import SwiftUI

/// The beat-rate slice of the live connection state (FER-755). The strap notifies ~1 Hz while worn,
/// and these are the only properties that change per heartbeat. Isolating them in their own
/// observable keeps that cadence from invalidating every screen that observes LiveState/AppModel
/// (TodayView alone re-evaluated its whole body 2–4×/s all day). Views that DO show the live pulse
/// observe this object — via `PulseReader` — so only their subtree re-renders per beat.
@MainActor
public final class LivePulse: ObservableObject {
    /// Raw strap heart rate (bpm) from the live link; nil when no live HR is flowing.
    @Published public var heartRate: Int? = nil
    /// R-R intervals (ms) from the latest notification; each batch adds to `beatsThisSession`.
    @Published public var rr: [Int] = [] {
        didSet { beatsThisSession += rr.count }  // each notification carries the beats since the last → running session total
    }
    /// Beats captured live this connection session. Zeroed by LiveState on a fresh connect.
    @Published public var beatsThisSession: Int = 0
    /// AppModel's smoothed bpm (median over the raw HR/R-R window) — the value screens display.
    @Published public var smoothedBpm: Int? = nil

    public init() {}
}

/// Renders `content` from the live pulse so ONLY this subtree re-evaluates per heartbeat — the
/// enclosing screen observes LiveState/AppModel, which no longer tick per beat (FER-755).
public struct PulseReader<Content: View>: View {
    @ObservedObject private var pulse: LivePulse
    private let content: (LivePulse) -> Content

    public init(_ pulse: LivePulse, @ViewBuilder content: @escaping (LivePulse) -> Content) {
        self.pulse = pulse
        self.content = content
    }

    public var body: some View { content(pulse) }
}
