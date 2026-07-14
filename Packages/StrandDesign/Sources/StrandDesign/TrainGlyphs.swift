import SwiftUI

// MARK: - TrainGlyphs — the five «Formas de entrenar» disc glyphs, each with its own gesture (FER-944)
//
// Custom-drawn (not SF Symbols) so each can perform its one entrance move: the bolt DRAWS itself,
// live PULSES from its dot, the interval hand SWEEPS one turn, mobility STRETCHES side to side, and
// breath BLOWS its lines in sequence. The gesture runs ONCE (after the disc settles) and then the
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
            case .mobility: MobilityStretch(color: color, pending: pending)
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

// MARK: Movilidad — the figure stretches side to side twice, then stands

private struct MobilityStretch: View {
    let color: Color
    let pending: Bool
    @State private var tilt: Double = 0
    var body: some View {
        FigureShape()
            .stroke(color, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            .rotationEffect(.degrees(tilt), anchor: .bottom)
            .onChange(of: pending) { was, now in
                if was, !now { Task { await stretch() } }
            }
    }

    @MainActor private func stretch() async {
        for side in [-10.0, 10.0, -10.0, 10.0] {
            withAnimation(.easeInOut(duration: 0.4)) { tilt = side }
            try? await Task.sleep(nanoseconds: 420_000_000)
        }
        withAnimation(.easeInOut(duration: 0.3)) { tilt = 0 }
    }
}

private struct FigureShape: Shape {
    func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x / 18 * rect.width, y: rect.minY + y / 18 * rect.height)
        }
        var path = Path()
        // Head
        path.addEllipse(in: CGRect(x: p(7.2, 1.8).x, y: p(7.2, 1.8).y,
                                   width: rect.width * 3.6 / 18, height: rect.height * 3.6 / 18))
        // Bending torso→leg
        path.move(to: p(9, 6.2))
        path.addCurve(to: p(5.5, 15.5), control1: p(9, 9.5), control2: p(6.8, 11.5))
        // Reaching arm
        path.move(to: p(9, 8.2))
        path.addCurve(to: p(13, 13.5), control1: p(11, 9), control2: p(13, 11))
        return path
    }
}

// MARK: Respira — the wind blows its three lines in sequence, twice

private struct BreatheBlow: View {
    let color: Color
    let pending: Bool
    @State private var drawn: [CGFloat] = [1, 1, 1]
    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(0..<3, id: \.self) { i in
                    WindLine(row: i)
                        .trim(from: 0, to: drawn[i])
                        .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .onChange(of: pending) { was, now in
            if was, !now { Task { await blow() } }
        }
    }

    @MainActor private func blow() async {
        for _ in 0..<2 {
            var snap = Transaction(); snap.disablesAnimations = true
            withTransaction(snap) { drawn = [0, 0, 0] }
            for i in 0..<3 {
                withAnimation(.easeOut(duration: 0.45)) { drawn[i] = 1 }
                try? await Task.sleep(nanoseconds: 130_000_000)
            }
            try? await Task.sleep(nanoseconds: 550_000_000)
        }
    }
}

private struct WindLine: Shape {
    let row: Int
    func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x / 18 * rect.width, y: rect.minY + y / 18 * rect.height)
        }
        let y = CGFloat(5 + row * 4)
        var path = Path()
        path.move(to: p(2, y + 0.5))
        path.addCurve(to: p(16, y - 0.3), control1: p(6, y - 1.7), control2: p(10, y + 1.7))
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
