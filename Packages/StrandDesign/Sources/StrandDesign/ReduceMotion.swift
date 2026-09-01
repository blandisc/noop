import SwiftUI

public extension StrandMotion {
    /// Returns `animation`, or `nil` when Reduce Motion is on (so callers can pass this
    /// straight into `withAnimation(_:)` or `.animation(_:value:)`).
    @available(*, deprecated, message: "usa LiquidMotion.condicionado(_:_) (mismo comportamiento; FER-280·2e)")
    static func gated(_ animation: Animation?, _ reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }
}

private struct StrandAnimationModifier<V: Equatable>: ViewModifier {
    let animation: Animation?
    let value: V
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}

public extension View {
    /// Like `.animation(_:value:)`, but self-gates on the system Reduce Motion setting —
    /// no animation is applied when the user has Reduce Motion enabled. Prefer this over
    /// hand-rolling `reduceMotion ? nil : x` at every call site.
    func strandAnimation<V: Equatable>(_ animation: Animation?, value: V) -> some View {
        modifier(StrandAnimationModifier(animation: animation, value: value))
    }
}
