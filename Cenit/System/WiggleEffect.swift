import SwiftUI
import Combine

/// Owns the wiggle's animation state and its Combine subscription, so neither can be duplicated or
/// orphaned when SwiftUI rebuilds the view that carries the modifier (FER-876, then the busy-loop fix).
///
/// This is a SHARED singleton, not `@State`. FER-876 guarded against the modifier's `body` re-running,
/// but not against SwiftUI throwing away the modifier's identity — and this wiggle lives inside a
/// `.toolbar`, which SwiftUI rebuilds often. Each rebuild handed the modifier a fresh holder
/// (`cancellable == nil`) with `fireCount` back at 0, so `onAppear` armed ANOTHER timer. The timers
/// accumulated, each firing its own spring animation, until the main thread was re-rendering non-stop
/// at 100% CPU and the app stopped responding to taps.
///
/// `angle` lives here too, not in `@State`: a timer armed by one instance would otherwise keep driving
/// the binding of an instance SwiftUI had already discarded, and the wiggle would silently stop
/// animating. A shared holder also matches what the nudge actually means — three wiggles per app
/// launch, not three per view instantiation.
/// Sin `@MainActor` a propósito, siguiendo el precedente de `ExerciseThumbStillCache`: todo lo que
/// toca el holder ya vive en el main (el `Timer` publica en `.main`, `onAppear` y `withAnimation`
/// corren ahí), y anotarlo obligaría a aislar el valor por defecto de la propiedad del modifier.
private final class WiggleTimerHold: ObservableObject {
    static let shared = WiggleTimerHold()

    @Published var angle: Double = 0
    private var fireCount = 0
    private var cancellable: AnyCancellable?

    private init() {}

    /// Arm the timer once per app launch. Re-entrant by design: later calls are no-ops while a timer
    /// is live or once the nudge has run its course.
    func armIfNeeded(period: Double, maxFires: Int) {
        guard cancellable == nil, fireCount < maxFires else { return }
        cancellable = Timer.publish(every: period, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                guard self.fireCount < maxFires else { return self.stop() }
                self.fireCount += 1
                withAnimation(.spring(response: 0.16, dampingFraction: 0.22)) { self.angle = 16 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.55)) { self.angle = 0 }
                }
                if self.fireCount >= maxFires { self.stop() }
            }
    }

    private func stop() {
        cancellable?.cancel()
        cancellable = nil
    }
}

/// A periodic attention "wiggle" — a small rotation burst every `period` seconds that settles back
/// to rest. Used on the home Support button as a gentle nudge that people can donate.
/// Fires a fixed number of times (3) per app launch, then cancels the timer so it does not run forever.
struct WiggleEffect: ViewModifier {
    var period: Double = 4
    private let maxFires = 3

    @ObservedObject private var hold = WiggleTimerHold.shared

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(hold.angle))
            // No `.onDisappear` teardown: the holder is shared and self-cancelling, and tearing it down
            // on one view's disappearance would let the next `onAppear` arm a second timer — the very
            // accumulation this fix removes.
            .onAppear { hold.armIfNeeded(period: period, maxFires: maxFires) }
    }
}

extension View {
    /// Gentle recurring wiggle to draw the eye (e.g. the Support/donate button).
    func attentionWiggle(period: Double = 4) -> some View { modifier(WiggleEffect(period: period)) }
}
