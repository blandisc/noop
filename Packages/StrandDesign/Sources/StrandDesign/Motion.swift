import SwiftUI

// MARK: - Strand Motion (§9.6)
//
// Physiological motion — breathe / pulse / flow, no cartoon bounce.
// Ring draw-in, per-beat ripple, hover lift, sliding sidebar indicator.
//
// Two languages, one catalog (FER-131 handoff · 03). The «Instrumento diurno» light language
// keeps ONLY the physical springs — `interactive` (resp 0.28 / damp 0.82), `gentle` (0.50 / 0.80),
// `hero` (0.85 / 0.85) — plus `breathe` (3.2 s) for loading/listening states (no spinner, no color).
// The AMBIENT-GLOW effects (the RecoveryRing bloom, the additive plus-lighter halos on chart dots /
// the connection dot) are black-screen effects that only muddy a glyph's edge on warm paper, so the
// daytime views drop them: the glow lives in the COMPONENTS, gated off by `\.instrumentoFlat` (which
// `.instrumentoTheme(_:)` sets), not in a motion preset here. The remaining curves below
// (`pulse` / `spin` / `bob` / `drawIn` / `fade`) serve the legacy dark system and specific shipped
// affordances (sync dial spin, pull-to-refresh bob); they are maintained, not extended.

public enum StrandMotion {

    // MARK: Spring presets

    /// Interactive spring — snappy, for direct manipulation (hover, press, sidebar slide).
    public static let interactive = Animation.interactiveSpring(response: 0.28, dampingFraction: 0.82, blendDuration: 0.1)

    /// Gentle spring — the house style for value changes (ring draw-in, gauges).
    /// spring(response: 0.5, damping: 0.8) per the brief.
    public static let gentle = Animation.spring(response: 0.5, dampingFraction: 0.8)

    /// A slower, more deliberate spring for hero transitions (e.g. first ring materialize).
    public static let hero = Animation.spring(response: 0.85, dampingFraction: 0.85)

    // MARK: Durations

    /// Standard transition (card appear, fades).
    public static let durationStandard: Double = 0.30

    /// Slow / draw-in (ring arc, waveform ignite).
    public static let durationSlow: Double = 0.9

    /// One breath cycle for ambient pulsing (bloom, listening flatline).
    public static let breathPeriod: Double = 3.2

    // MARK: Curves

    /// Ease for the ring/gauge draw-in when a value changes.
    public static let drawIn = Animation.easeOut(duration: durationSlow)

    /// Looping breathe animation for ambient glow/pulse.
    public static var breathe: Animation {
        .easeInOut(duration: breathPeriod).repeatForever(autoreverses: true)
    }

    /// A single heartbeat ripple pulse.
    public static let pulse = Animation.easeOut(duration: 0.6)

    /// Standard fade.
    public static let fade = Animation.easeInOut(duration: durationStandard)

    /// Continuous linear spin for indeterminate progress (e.g. the sync dial arc,
    /// FER-221). No autoreverse — a steady rotation, not a wobble.
    public static func spin(period: Double = 1.5) -> Animation {
        .linear(duration: period).repeatForever(autoreverses: false)
    }

    /// Gentle looping vertical bob for an affordance hint that invites a gesture —
    /// e.g. the pull-to-refresh chevron nudging the eye downward (FER-293). Slower
    /// and softer than `pulse`, quieter than `breathe`.
    public static var bob: Animation {
        .easeInOut(duration: 1.2).repeatForever(autoreverses: true)
    }
}

#if DEBUG
private struct MotionDemo: View {
    @State private var on = false
    @State private var breathing = false
    var body: some View {
        VStack(spacing: 32) {
            Circle()
                .fill(StrandPalette.accent)
                .frame(width: 60, height: 60)
                .offset(y: on ? -24 : 24)
                .animation(StrandMotion.gentle, value: on)
            Circle()
                .fill(StrandPalette.recovery100)
                .frame(width: 60, height: 60)
                .scaleEffect(breathing ? 1.12 : 0.9)
                .opacity(breathing ? 0.9 : 0.5)
                .onAppear { breathing = true }
                .animation(StrandMotion.breathe, value: breathing)
            Button("Toggle gentle spring") { on.toggle() }
                .foregroundStyle(InstrumentoTheme.base.ink)
        }
        .frame(width: 360, height: 320)
        .background(InstrumentoTheme.base.paper)
        .preferredColorScheme(.dark)
    }
}

#Preview("Motion") { MotionDemo() }
#endif
