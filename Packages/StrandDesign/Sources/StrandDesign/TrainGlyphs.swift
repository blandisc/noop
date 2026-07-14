import SwiftUI

// MARK: - TrainGlyphs — the five «Formas de entrenar» disc glyphs, each with its own gesture (FER-944)
//
// Custom-drawn (not SF Symbols) so each can perform its one entrance move: the bolt DRAWS itself,
// live PULSES from its dot, the interval hand SWEEPS one turn, mobility RUNS IN from the left and
// stops standing, and breath INHALES/EXHALES its lines. The gesture runs ONCE (after the disc
// settles) and then the
// glyph rests as a static icon — never a loop. With `play == false` (Reduce Motion, or an entrance
// the screen suppressed) the glyph renders its rest state immediately, so it is never invisible.
// Stroke color comes from the caller (paper knockout on the tinted discs).

public enum TrainGlyph: String, CaseIterable {
    case quick, live, interval, mobility, breathe
}

/// One disc glyph. `play` says the screen's entrance animation is running (already resolved against
/// Reduce Motion by the caller); `active` flips true when the entrance starts; `delay` is this
/// glyph's own start offset (its disc's settle time). Drawn to fit its frame (square, ~20pt).
public struct TrainGlyphView: View {
    private let glyph: TrainGlyph
    private let play: Bool
    private let active: Bool
    private let delay: Double
    private let color: Color
    @State private var performed = false

    public init(_ glyph: TrainGlyph, color: Color, play: Bool, active: Bool, delay: Double = 0) {
        self.glyph = glyph
        self.color = color
        self.play = play
        self.active = active
        self.delay = delay
    }

    public var body: some View {
        Group {
            switch glyph {
            case .quick:    BoltDraw(color: color, pending: pending)
            case .live:     LivePulse(color: color, pending: pending)
            case .interval: IntervalSweep(color: color, pending: pending)
            case .mobility: MobilityRun(color: color, pending: pending)
            case .breathe:  BreatheBlow(color: color, pending: pending)
            }
        }
        .onChange(of: active) { _, on in trigger(on) }
        .onAppear { trigger(active) }
    }

    /// `true` while the glyph should hold its pre-gesture state (only when the entrance really plays).
    private var pending: Bool { play && !performed }

    private func trigger(_ on: Bool) {
        guard on, play, !performed else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            performed = true
        }
    }
}

// MARK: Rápido — the bolt draws itself (stroke trim 0→1)

private struct BoltDraw: View {
    let color: Color
    let pending: Bool
    var body: some View {
        BoltShape()
            .trim(from: 0, to: pending ? 0 : 1)
            .stroke(color, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
            .animation(.easeOut(duration: 0.55), value: pending)
    }
}

private struct BoltShape: Shape {
    func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x / 18 * rect.width, y: rect.minY + y / 18 * rect.height)
        }
        var path = Path()
        path.move(to: p(10, 2))
        path.addLine(to: p(4.5, 10))
        path.addLine(to: p(8.5, 10))
        path.addLine(to: p(7.5, 16))
        path.addLine(to: p(13.5, 7.5))
        path.addLine(to: p(9.5, 7.5))
        path.closeSubpath()
        return path
    }
}

// MARK: En vivo — pulses: rings ripple out from the dot 3 times, then settle visible

private struct LivePulse: View {
    let color: Color
    let pending: Bool
    @State private var ringScale: CGFloat = 1
    @State private var ringOpacity: Double = 1
    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            ZStack {
                Circle().fill(color).frame(width: s * 0.24, height: s * 0.24)
                ring(s * 0.58)
                ring(s * 0.92)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .onChange(of: pending) { was, now in
            if was, !now { Task { await pulse() } }
        }
    }

    private func ring(_ d: CGFloat) -> some View {
        Circle().strokeBorder(color, lineWidth: 1.4)
            .frame(width: d, height: d)
            .scaleEffect(ringScale)
            .opacity(ringOpacity)
    }

    @MainActor private func pulse() async {
        for _ in 0..<3 {
            var snap = Transaction(); snap.disablesAnimations = true
            withTransaction(snap) { ringScale = 0.55; ringOpacity = 0.95 }
            withAnimation(.easeOut(duration: 0.5)) { ringScale = 1.35; ringOpacity = 0 }
            try? await Task.sleep(nanoseconds: 560_000_000)
        }
        withAnimation(.easeOut(duration: 0.25)) { ringScale = 1; ringOpacity = 1 }
    }
}

// MARK: Intervalos — the minute hand sweeps one full turn

private struct IntervalSweep: View {
    let color: Color
    let pending: Bool
    @State private var angle: Angle = .zero
    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            ZStack {
                Circle().strokeBorder(color, lineWidth: 1.6)
                // The short hand rests at 3 o'clock; the long hand is the one that sweeps.
                Hand(length: 0.16).stroke(color, style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                    .rotationEffect(.degrees(90))
                    .opacity(0.75)
                Hand(length: 0.26).stroke(color, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                    .rotationEffect(angle)
            }
            .frame(width: s, height: s)
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .onChange(of: pending) { was, now in
            if was, !now {
                withAnimation(.easeInOut(duration: 1.1)) { angle = .degrees(360) }
            }
        }
    }

    /// A hand from the center straight up, `length` in unit-of-side terms.
    private struct Hand: Shape {
        let length: CGFloat
        func path(in rect: CGRect) -> Path {
            var p = Path()
            let c = CGPoint(x: rect.midX, y: rect.midY)
            p.move(to: c)
            p.addLine(to: CGPoint(x: c.x, y: c.y - rect.height * length * 2))
            return p
        }
    }
}

// MARK: Movilidad — the little figure RUNS IN from the left, strides swapping, and stops standing

private struct MobilityRun: View {
    let color: Color
    let pending: Bool
    /// .stand at rest; .runA/.runB alternate as sprite frames while the figure slides in.
    @State private var pose: FigurePose = .stand
    @State private var entered = true   // false only while the gesture holds the figure offscreen

    var body: some View {
        GeometryReader { geo in
            FigureShape(pose: pose)
                .stroke(color, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                .offset(x: entered ? 0 : -(geo.size.width * 1.2))
                .opacity(entered ? 1 : 0)
        }
        .onAppear {
            // Armed from the first frame: hold the figure just off the left edge, mid-stride.
            if pending { entered = false; pose = .runA }
        }
        .onChange(of: pending) { was, now in
            if was, !now { Task { await runIn() } }
        }
    }

    @MainActor private func runIn() async {
        withAnimation(.easeOut(duration: 0.7)) { entered = true }
        // Sprite-style stride swaps while it slides in — snapped, not tweened.
        for i in 0..<5 {
            try? await Task.sleep(nanoseconds: 120_000_000)
            var snap = Transaction(); snap.disablesAnimations = true
            withTransaction(snap) { pose = i.isMultiple(of: 2) ? .runB : .runA }
        }
        withAnimation(.easeOut(duration: 0.25)) { pose = .stand }
    }
}

private enum FigurePose { case stand, runA, runB }

/// A small stick figure — clearly a person: head, torso, two arms, two legs. `stand` is the resting
/// icon; `runA`/`runB` are the two stride frames (leaning, legs and arms scissored) for the run-in.
private struct FigureShape: Shape {
    let pose: FigurePose
    func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x / 18 * rect.width, y: rect.minY + y / 18 * rect.height)
        }
        var path = Path()
        func head(cx: CGFloat, cy: CGFloat) {
            let r = 1.9 / 18 * rect.width
            let c = p(cx, cy)
            path.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        }
        func line(_ a: CGPoint, _ b: CGPoint) { path.move(to: a); path.addLine(to: b) }
        switch pose {
        case .stand:
            head(cx: 9, cy: 3.6)
            line(p(9, 5.7), p(9, 11))             // torso
            line(p(9, 7), p(6.2, 9.6))            // arms, relaxed
            line(p(9, 7), p(11.8, 9.6))
            line(p(9, 11), p(6.8, 15.6))          // legs, slightly apart
            line(p(9, 11), p(11.2, 15.6))
        case .runA:
            head(cx: 10.6, cy: 3.8)
            line(p(10.2, 5.9), p(8.6, 10.8))      // torso leaning forward
            line(p(9.6, 7.2), p(13, 6.4))         // front arm up
            line(p(9.6, 7.2), p(6.4, 9))          // back arm
            line(p(8.6, 10.8), p(12.4, 13.4))     // front leg reaching
            line(p(8.6, 10.8), p(5.2, 14.6))      // back leg trailing
        case .runB:
            head(cx: 10.6, cy: 3.8)
            line(p(10.2, 5.9), p(8.6, 10.8))      // torso leaning forward
            line(p(9.6, 7.2), p(12.6, 9.2))       // front arm low
            line(p(9.6, 7.2), p(6.6, 6.2))        // back arm up
            line(p(8.6, 10.8), p(10.6, 15))       // legs gathered under
            line(p(8.6, 10.8), p(7, 14.2))
        }
        return path
    }
}

// MARK: Respira — gusts of AIR: curled wind lines that stream out to the right, twice

private struct BreatheBlow: View {
    let color: Color
    let pending: Bool
    /// Per-line draw progress (0 = hidden, 1 = fully streamed). The three gusts flow in sequence.
    @State private var drawn: [CGFloat] = [1, 1, 1]
    /// A small horizontal glide added while a gust streams, so the air reads as MOVING, not just drawn.
    @State private var glide: CGFloat = 0
    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(0..<3, id: \.self) { i in
                    WindGust(row: i)
                        .trim(from: 0, to: drawn[i])
                        .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                        .offset(x: glide * geo.size.width * 0.06 * (i == 1 ? 1.4 : 1))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .onChange(of: pending) { was, now in
            if was, !now { Task { await gust() } }
        }
    }

    /// Two gusts: each streams the three curled lines left→right in quick succession with a light
    /// forward glide, then eases back — clearly moving air, not a breathing chest.
    @MainActor private func gust() async {
        for _ in 0..<2 {
            var snap = Transaction(); snap.disablesAnimations = true
            withTransaction(snap) { drawn = [0, 0, 0]; glide = 0 }
            withAnimation(.easeOut(duration: 0.9)) { glide = 1 }
            for i in 0..<3 {
                withAnimation(.easeOut(duration: 0.5)) { drawn[i] = 1 }
                try? await Task.sleep(nanoseconds: 140_000_000)
            }
            withAnimation(.easeInOut(duration: 0.5)) { glide = 0 }
            try? await Task.sleep(nanoseconds: 620_000_000)
        }
    }
}

/// One gust line: a long horizontal stream that ends in a small upward CURL — the universal "wind /
/// air" mark. The middle row runs longer with a deeper curl so the three read as a blowing cluster.
private struct WindGust: Shape {
    let row: Int
    func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x / 18 * rect.width, y: rect.minY + y / 18 * rect.height)
        }
        let y = CGFloat(5 + row * 4)
        let long = row == 1
        var path = Path()
        // The streaming stroke, drawn left→right with a gentle waft.
        path.move(to: p(1.5, y))
        let endX: CGFloat = long ? 13.5 : 11.5
        path.addCurve(to: p(endX, y), control1: p(5, y - 1.2), control2: p(endX - 4, y + 1.2))
        // The curl at the tip — a little hook that reads as swirling air.
        path.addCurve(to: p(endX - 0.4, y - 2.4),
                      control1: p(endX + 2.6, y - 0.4),
                      control2: p(endX + 2.2, y - 2.6))
        return path
    }
}

// MARK: - Preview

#if DEBUG
#Preview("TrainGlyphs · los cinco gestos") {
    struct Demo: View {
        @State private var go = false
        let t = InstrumentoTheme.base
        var body: some View {
            VStack(spacing: 28) {
                HStack(spacing: 14) {
                    disc(.quick, t.dataStrain)
                    disc(.live, t.dataHeart)
                    disc(.interval, t.dataSleep)
                    disc(.mobility, t.dataHrv)
                    disc(.breathe, t.dataRecovery)
                }
                Button(go ? "Otra vez" : "Reproducir") { go.toggle() }
            }
            .padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(t.paper)
        }
        func disc(_ g: TrainGlyph, _ tint: Color) -> some View {
            TrainGlyphView(g, color: t.paper, play: true, active: go,
                           delay: 0.1 + Double(TrainGlyph.allCases.firstIndex(of: g) ?? 0) * 0.04)
                .frame(width: 22, height: 22)
                .padding(14)
                .background(tint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .id(go)   // re-mount per run so the one-shot gesture can replay in the preview
        }
    }
    return Demo()
}
#endif
