import WatchKit

/// The three distinct haptic signatures of a mirrored strength session (FER-741). Each maps to a
/// `WKHapticType` so the wrist can speak even with the screen off: `WKInterfaceDevice.play(_:)` is
/// suppressed in the background *except* for apps with an active `HKWorkoutSession`, which is exactly the
/// mirrored session the watch is running — so `restEnded` fires muñeca-abajo, which is the whole point.
///
/// The three types are deliberately different so the wrist can tell them apart without looking: a soft
/// tap to open, a strong double-pulse to call you back from the rest, and the rising success pattern to
/// close.
enum WatchHaptic {
    /// The session began — a soft `.start` tap.
    case sessionStart
    /// The rest window closed — `.notification`, the insistent double-pulse. The primary signal.
    case restEnded
    /// The session ended and saved — the rising `.success` pattern.
    case sessionEnded

    var type: WKHapticType {
        switch self {
        case .sessionStart: return .start
        case .restEnded:    return .notification
        case .sessionEnded: return .success
        }
    }

    /// Play the signature on the wrist. A no-op off-device; on-device it engages the Taptic engine.
    func play() { WKInterfaceDevice.current().play(type) }
}
