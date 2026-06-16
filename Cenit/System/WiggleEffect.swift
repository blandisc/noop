import SwiftUI

/// A periodic attention "wiggle" — a small rotation burst every `period` seconds that settles back
/// to rest. Used on the home Support button as a gentle, recurring nudge that people can donate.
struct WiggleEffect: ViewModifier {
    var period: Double = 4
    @State private var angle: Double = 0

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(angle))
            .onReceive(Timer.publish(every: period, on: .main, in: .common).autoconnect()) { _ in
                withAnimation(.spring(response: 0.16, dampingFraction: 0.22)) { angle = 16 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.55)) { angle = 0 }
                }
            }
    }
}

extension View {
    /// Gentle recurring wiggle to draw the eye (e.g. the Support/donate button).
    func attentionWiggle(period: Double = 4) -> some View { modifier(WiggleEffect(period: period)) }
}
