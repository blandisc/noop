import SwiftUI
import Combine

/// Holds the Combine subscription so it can be cancelled after a fixed number of fires
/// without re-arming the timer on every `body` re-evaluation (FER-876).
private final class WiggleTimerHold {
    var cancellable: AnyCancellable?
}

/// A periodic attention "wiggle" — a small rotation burst every `period` seconds that settles back
/// to rest. Used on the home Support button as a gentle nudge that people can donate.
/// Fires a fixed number of times (3), then cancels the timer so it does not run forever (FER-876).
struct WiggleEffect: ViewModifier {
    var period: Double = 4
    private let maxFires = 3

    @State private var angle: Double = 0
    @State private var fireCount: Int = 0
    @State private var hold = WiggleTimerHold()

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(angle))
            .onAppear { armIfNeeded() }
            .onDisappear {
                hold.cancellable?.cancel()
                hold.cancellable = nil
            }
    }

    private func armIfNeeded() {
        guard hold.cancellable == nil, fireCount < maxFires else { return }
        let maxFires = self.maxFires
        let angleBinding = $angle
        let countBinding = $fireCount
        let hold = self.hold
        hold.cancellable = Timer.publish(every: period, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                var count = countBinding.wrappedValue
                guard count < maxFires else {
                    hold.cancellable?.cancel()
                    hold.cancellable = nil
                    return
                }
                count += 1
                countBinding.wrappedValue = count
                withAnimation(.spring(response: 0.16, dampingFraction: 0.22)) {
                    angleBinding.wrappedValue = 16
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.55)) {
                        angleBinding.wrappedValue = 0
                    }
                }
                if count >= maxFires {
                    hold.cancellable?.cancel()
                    hold.cancellable = nil
                }
            }
    }
}

extension View {
    /// Gentle recurring wiggle to draw the eye (e.g. the Support/donate button).
    func attentionWiggle(period: Double = 4) -> some View { modifier(WiggleEffect(period: period)) }
}
