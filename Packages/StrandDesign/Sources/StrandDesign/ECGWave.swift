import SwiftUI

// MARK: - ECG waveform (brand motif)
//
// The NOOP signature: a single heartbeat trace derived from the app's logo mark.
//
// Two render modes:
//  • Static  — the brand polyline (default), or a centered flatline when `flat` (no data).
//  • Monitor — when `animate: true` + a live `bpm:` is supplied, a hospital-monitor sweep:
//    a head travels left→right at a constant paper-feed speed, *drawing* each QRS the instant the
//    sweep reaches that beat. Spacing between complexes is set by the live BPM (a faster heart packs
//    the beats closer), NOT by playback speed. The strip never blanks to flat: ahead of the head the
//    PREVIOUS pass stays lit (phosphor persistence) and the head wipes it forward behind a short
//    erase gap — exactly like a vital-signs monitor, so successive passes read as one continuous
//    trace instead of a pattern that jumps sideways when the pass length doesn't divide the R–R.
//    The beat itself breathes: per-beat HRV (R–R jitter), ±14% R-height variation and a slow
//    respiratory baseline wander, all derived deterministically from the wall clock so the trace
//    never flickers yet no two beats look identical. (Replaces "scroll one fixed wave faster or
//    slower", and a cut that wiped ahead of the head to a flat baseline — which made the beats jump.)
//
// Cross-platform, tokens-only — a redesign primitive reused across the app.

public struct ECGWave: View {
    public var color: Color
    public var flat: Bool
    public var lineWidth: CGFloat
    public var animate: Bool
    /// Live BPM from the strap. Drives how far apart successive beats are drawn along the sweep.
    public var bpm: Int?

    public init(
        color: Color = StrandPalette.accent,
        flat: Bool = false,
        lineWidth: CGFloat = 1.6,
        animate: Bool = false,
        bpm: Int? = nil
    ) {
        self.color = color
        self.flat = flat
        self.lineWidth = lineWidth
        self.animate = animate
        self.bpm = bpm
    }

    /// Run the live monitor sweep only when we're animating a real, non-flat reading.
    private var isMonitoring: Bool { animate && !flat }

    // Seconds between beats, clamped for safety. Sets the QRS spacing along the sweep.
    private var beatPeriod: Double {
        guard let bpm, bpm > 0 else { return 1.0 }
        return max(0.3, min(3.0, 60.0 / Double(bpm)))
    }

    // Sweep speed in points/second — constant, like a monitor's paper feed. The head crosses the
    // strip in width / sweepSpeed seconds; a faster heart simply packs more complexes per crossing.
    private let sweepSpeed: CGFloat = 38
    // Transparent erase window just ahead of the head — the monitor's tell-tale moving gap.
    private let eraseGap: CGFloat = 9

    public var body: some View {
        Group {
            if isMonitoring {
                monitor
            } else {
                ECGShape(flat: flat)
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(height: ECGShape.designHeight)
        .clipped()
        .opacity(flat ? 0.6 : 1)
        .mask(
            LinearGradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.10),
                .init(color: .black, location: 0.90),
                .init(color: .clear, location: 1),
            ], startPoint: .leading, endPoint: .trailing)
        )
        .accessibilityHidden(true)
    }

    /// Real-time patient-monitor sweep, redrawn each frame straight from the wall clock.
    private var monitor: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                drawSweep(into: &context, size: size,
                          now: timeline.date.timeIntervalSinceReferenceDate)
            }
        }
    }

    private func drawSweep(into ctx: inout GraphicsContext, size: CGSize, now: TimeInterval) {
        let w = size.width
        guard w > 0 else { return }
        let mid = size.height / 2
        let ampScale = size.height / ECGShape.designHeight  // design amps live in a 26-pt space

        // Head position within the current sweep, plus how many whole sweeps have elapsed so far.
        let travelled = CGFloat(now) * sweepSpeed
        let headX = travelled.truncatingRemainder(dividingBy: w)
        let sweepIndex = (travelled / w).rounded(.down)

        // Build the visible trace column by column. Each column maps to the wall-clock instant the
        // head crossed it: this pass behind the head, the PREVIOUS pass ahead of it — so the strip is
        // always fully drawn and the head just overwrites last pass with this one, a moving seam.
        var path = Path()
        var penDown = false
        let step: CGFloat = 0.5
        var x: CGFloat = 0
        while x <= w {
            // Leave the erase gap blank — it sits just ahead of the head and wraps past the edge.
            let aheadDist = (x - headX + w).truncatingRemainder(dividingBy: w)
            if aheadDist > 0, aheadDist <= eraseGap {
                penDown = false
                x += step
                continue
            }
            // Behind the head → this pass; ahead of it → the previous pass still lit (phosphor
            // persistence). Sampling both from the same clock keeps the trace continuous across the
            // wrap, so it no longer jumps sideways when a pass length doesn't divide the R–R.
            let pass = (x <= headX) ? sweepIndex : sweepIndex - 1
            let tCross = (pass * w + x) / sweepSpeed                 // seconds (reference-date based)
            let y = mid - beatAmplitude(at: Double(tCross)) * ampScale
            let pt = CGPoint(x: x, y: y)
            if penDown { path.addLine(to: pt) } else { path.move(to: pt); penDown = true }
            x += step
        }
        ctx.stroke(path, with: .color(color),
                   style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))

        // Glow + bright dot riding the live edge of the trace.
        let headAmp = beatAmplitude(at: Double((sweepIndex * w + headX) / sweepSpeed))
        let head = CGPoint(x: headX, y: mid - headAmp * ampScale)
        ctx.fill(Path(ellipseIn: CGRect(x: head.x - 4, y: head.y - 4, width: 8, height: 8)),
                 with: .color(color.opacity(0.25)))
        ctx.fill(Path(ellipseIn: CGRect(x: head.x - 1.8, y: head.y - 1.8, width: 3.6, height: 3.6)),
                 with: .color(color))
    }

    /// Amplitude (design y-units, + = up from baseline) of the brand QRS complex at wall-clock time
    /// `t`. The beat repeats every `beatPeriod`, but each one is nudged a little so the trace reads
    /// like a living heart, not a looping GIF — see the per-beat HRV/amplitude jitter and the slow
    /// respiratory wander below. All variation is a pure function of `t`, so every frame redraws the
    /// exact same curve (no flicker) while no two beats look identical.
    private func beatAmplitude(at t: Double) -> CGFloat {
        let period = beatPeriod
        let complexDur = min(0.42, period * 0.85)       // compacts the complex at very high BPM
        let phase = t.truncatingRemainder(dividingBy: period)
        let beatIndex = (t / period).rounded(.down)     // identifies this beat for stable jitter

        // HRV: slide each beat's start within its flat slack so the R–R spacing breathes (~±12%),
        // and vary the R height ±14%. Both keyed off the beat index → constant within a beat.
        let slack = max(0, period - complexDur)
        let offset = slack * (0.5 + (hash01(beatIndex) - 0.5) * 0.5)
        let ampMul = 1 + (hash01(beatIndex * 2 + 7) - 0.5) * 0.28

        let localPhase = phase - offset
        var qrs = 0.0
        if localPhase >= 0, localPhase < complexDur {
            qrs = Double(ECGShape.complexAmplitude(at: CGFloat(localPhase / complexDur))) * ampMul
        }
        return CGFloat(qrs + baselineWander(at: t))
    }

    /// Slow two-tone drift (~respiration) added to the baseline so the line is never dead-flat.
    /// Amplitude is ~1 design y-unit — felt, not seen.
    private func baselineWander(at t: Double) -> Double {
        sin(t * 0.8) * 0.8 + sin(t * 2.1 + 1.3) * 0.35
    }

    /// Deterministic pseudo-random in [0,1) from a beat-index seed. Same seed → same value, so the
    /// per-beat jitter holds steady frame-to-frame; the classic fract(sin·k) hash, fine for a motif.
    private func hash01(_ n: Double) -> Double {
        let x = sin(n * 127.1 + 311.7) * 43758.5453
        return x - x.rounded(.down)
    }
}

/// The heartbeat trace as a `Shape`, scaled from the canonical 152×26 design space (the exact
/// vector from the Today prototype). `flat` collapses it to a centered baseline.
struct ECGShape: Shape {
    var flat: Bool

    static let designWidth: CGFloat = 152
    static let designHeight: CGFloat = 26

    func path(in rect: CGRect) -> Path {
        let sx = rect.width / Self.designWidth
        let sy = rect.height / Self.designHeight
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * sx, y: y * sy) }

        var path = Path()
        path.move(to: p(0, 13))
        if flat {
            path.addLine(to: p(152, 13))
            return path
        }
        // M0,13 H40 L46,10 L52,13 H66 L72,13 L76,21 L80,2 L84,24 L88,13 L94,11 L100,13 H152
        for pt in [p(40, 13), p(46, 10), p(52, 13), p(66, 13), p(72, 13), p(76, 21),
                   p(80, 2), p(84, 24), p(88, 13), p(94, 11), p(100, 13), p(152, 13)] {
            path.addLine(to: pt)
        }
        return path
    }

    // The brand QRS complex (the active x∈[40,100] slice of the canonical vector) expressed as
    // control points over a normalized progress u∈[0,1], with amplitude = (13 − y) in design units
    // (+ = up). The monitor sweep samples this to draw each beat in real time.
    private static let complexPoints: [(u: CGFloat, amp: CGFloat)] = [
        (0.000, 0), (0.100, 3), (0.200, 0), (0.433, 0), (0.533, 0),
        (0.600, -8), (0.667, 11), (0.733, -11), (0.800, 0), (0.900, 2), (1.000, 0),
    ]

    /// Linearly-interpolated amplitude of the brand complex at progress `u` (clamped to 0…1).
    static func complexAmplitude(at u: CGFloat) -> CGFloat {
        let u = max(0, min(1, u))
        for i in 0 ..< (complexPoints.count - 1) {
            let a = complexPoints[i], b = complexPoints[i + 1]
            if u >= a.u, u <= b.u {
                let span = b.u - a.u
                guard span > 0 else { return a.amp }
                return a.amp + (b.amp - a.amp) * (u - a.u) / span
            }
        }
        return 0
    }
}

#if DEBUG
#Preview("ECGWave") {
    VStack(alignment: .leading, spacing: 16) {
        Text("60 BPM (monitor en vivo)").font(.caption).foregroundStyle(StrandPalette.textTertiary)
        ECGWave(color: StrandPalette.accent, animate: true, bpm: 60).frame(width: 152)
        Text("120 BPM (latidos más juntos)").font(.caption).foregroundStyle(StrandPalette.textTertiary)
        ECGWave(color: StrandPalette.recovery100, animate: true, bpm: 120).frame(width: 152)
        Text("Sin BPM (estático)").font(.caption).foregroundStyle(StrandPalette.textTertiary)
        ECGWave(color: StrandPalette.statusWarning).frame(width: 152)
        Text("Flatline (sin datos)").font(.caption).foregroundStyle(StrandPalette.textTertiary)
        ECGWave(color: StrandPalette.textTertiary, flat: true).frame(width: 152)
    }
    .padding(24)
    .frame(width: 320, height: 320)
    .background(StrandPalette.surfaceBase)
    .preferredColorScheme(.dark)
}
#endif
