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

    // MARK: Entrenar v3 session (FER-716)

    /// The one always-on pulse of the app: the live BPM dot in the strength session header
    /// (1.1 s breath). Everything else on the session screen is still. Callers must gate it off
    /// under Reduce Motion (fall back to a static dot) — this preset does not self-disable.
    public static var livePulse: Animation {
        .easeInOut(duration: 1.1).repeatForever(autoreverses: true)
    }

    /// The receipt's numerals counting 0 → value, ONCE, on save (paired with
    /// `.contentTransition(.numericText())` and an "already-played" flag so re-opening never re-animates).
    public static let countUp = Animation.easeOut(duration: 0.75)
}

// MARK: - Entrada «Detalle de Tendencias Final» (FER-856) — los 3 keyframes canónicos
//
// Las cuatro pantallas de detalle animan su ENTRADA con exactamente tres movimientos (README del
// handoff): `recGrow` (una barra crece desde su punto de partida), `recRise` (un numeral sube 4px
// apareciendo) y `recFade` (un área de gráfica aparece). Siempre «backwards» (el estado inicial se
// aplica antes del delay — aquí, el `@State` arranca apagado), ease-out, sin bounce; el cromo no
// anima. Nada más anima en esas pantallas.
//
// La entrada arranca cuando la PANTALLA aterriza, no cuando se inserta el numeral: un detalle que ya
// trae su dato desde el primer frame (Estrés, Temp. de piel, Carga) montaba el héroe a la vez que el
// panel entraba deslizándose, y el rise se perdía dentro del movimiento del panel. Los detalles que
// sí se veían (Recuperación / Sueño / Esfuerzo) sólo lo lograban de rebote: su modelo entra tarde
// (el swap de FER-953/954), así que su `onAppear` ya caía con la pantalla quieta. `recEntranceGate`
// hace explícito ese compás para todos; sin gate (Entrenar, Hoy) el entorno vale `true` y la entrada
// corre al aparecer, como siempre.

/// Whether the presented screen has finished arriving. `false` holds every entrance keyframe.
/// Defaults to `true` so anything outside a gated presentation animates on appear, unchanged.
private struct RecEntranceSettledKey: EnvironmentKey { static let defaultValue = true }

public extension EnvironmentValues {
    var recEntranceSettled: Bool {
        get { self[RecEntranceSettledKey.self] }
        set { self[RecEntranceSettledKey.self] = newValue }
    }
}

/// Holds the entrance for `settle` seconds after the presented screen is inserted.
private struct RecEntranceGate: ViewModifier {
    let settle: Double
    @State private var settled = false

    func body(content: Content) -> some View {
        content
            .environment(\.recEntranceSettled, settled)
            .task {
                try? await Task.sleep(for: .seconds(settle))
                settled = true
            }
    }
}

private struct RecEntrance: ViewModifier {
    /// scaleX 0→1 (grow), or opacity+translateY (rise), or opacity (fade).
    enum Kind { case grow(UnitPoint), rise, fade }
    let kind: Kind
    let delay: Double
    let duration: Double
    @State private var shown = false
    @Environment(\.recEntranceSettled) private var settled

    func body(content: Content) -> some View {
        Group {
            switch kind {
            case .grow(let origin):
                content.scaleEffect(x: shown ? 1 : 0, y: 1, anchor: origin)
            case .rise:
                content.opacity(shown ? 1 : 0).offset(y: shown ? 0 : 4)
            case .fade:
                content.opacity(shown ? 1 : 0)
            }
        }
        // Whichever comes last — the view appearing, or the screen landing — starts the keyframe.
        .onAppear { play() }
        .onChange(of: settled) { _, _ in play() }
    }

    private func play() {
        guard settled, !shown else { return }
        withAnimation(.easeOut(duration: duration).delay(delay)) { shown = true }
    }
}

public extension View {
    /// `recGrow` — a data bar grows from its start point: scaleX 0→1, 0.35s ease-out, staggered
    /// 60ms per index starting at 150ms. `origin` is the bar's start (`.leading`/`.trailing`).
    func recGrow(index: Int = 0, origin: UnitPoint = .leading) -> some View {
        modifier(RecEntrance(kind: .grow(origin), delay: 0.15 + 0.06 * Double(index), duration: 0.35))
    }

    /// `recRise` — a hero numeral appears rising 4px, 0.5s ease-out. The second numeral of a
    /// double-datum hero passes `second: true` (+80ms).
    func recRise(second: Bool = false) -> some View {
        modifier(RecEntrance(kind: .rise, delay: second ? 0.08 : 0, duration: 0.5))
    }

    /// `recFade` — a chart area fades in, 0.4s ease-out after 250ms.
    func recFade() -> some View {
        modifier(RecEntrance(kind: .fade, delay: 0.25, duration: 0.4))
    }

    /// Holds the three entrance keyframes inside until the presented screen has landed. Apply on the
    /// PRESENTER's side (the layer / the sheet's root), where the arrival duration is known — a detail
    /// that already has its datum would otherwise animate under the panel's own slide and read as still.
    func recEntranceGate(_ settle: Double = StrandMotion.durationStandard) -> some View {
        modifier(RecEntranceGate(settle: settle))
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
        .preferredColorScheme(.light)
    }
}

#Preview("Motion") { MotionDemo() }
#endif
