import SwiftUI

// MARK: - ECG waveform (brand motif)
//
// The NOOP signature: a single heartbeat trace derived from the app's logo mark.
// Pass `flat` for the no-data flatline. Pass `animate: true` when the strap is streaming live HR
// to enable a scrolling-ECG effect (two tiled copies scrolling left on a ~2.4 s loop). Edge-faded
// on both sides so the strip dissolves into the layout instead of ending on a hard stub.
//
// Cross-platform, tokens-only — the first of the redesign primitives the rest of the app will reuse.

public struct ECGWave: View {
    public var color: Color
    public var flat: Bool
    public var lineWidth: CGFloat
    public var animate: Bool

    @State private var phase: CGFloat = 0

    public init(
        color: Color = StrandPalette.accent,
        flat: Bool = false,
        lineWidth: CGFloat = 1.6,
        animate: Bool = false
    ) {
        self.color = color
        self.flat = flat
        self.lineWidth = lineWidth
        self.animate = animate
    }

    private var isScrolling: Bool { animate && !flat }

    public var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            HStack(spacing: 0) {
                trace(width: w)
                if isScrolling { trace(width: w) }
            }
            .offset(x: isScrolling ? -w * phase : 0)
        }
        .frame(height: ECGShape.designHeight)
        .clipped()
        .opacity(flat ? 0.6 : 1)
        .mask(
            LinearGradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.14),
                .init(color: .black, location: 0.86),
                .init(color: .clear, location: 1),
            ], startPoint: .leading, endPoint: .trailing)
        )
        .onAppear { startScrolling() }
        .onChange(of: isScrolling) { scrolling in
            if scrolling {
                phase = 0
                startScrolling()
            }
        }
        .accessibilityHidden(true)
    }

    private func trace(width: CGFloat) -> some View {
        ECGShape(flat: flat)
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            .frame(width: width, height: ECGShape.designHeight)
    }

    private func startScrolling() {
        guard isScrolling else { return }
        withAnimation(.linear(duration: 2.4).repeatForever(autoreverses: false)) {
            phase = 1
        }
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
}

#if DEBUG
#Preview("ECGWave") {
    VStack(alignment: .leading, spacing: 20) {
        Text("Live (scrolling)").font(.caption).foregroundStyle(StrandPalette.textTertiary)
        ECGWave(color: StrandPalette.accent, animate: true).frame(width: 152)
        Text("Static (no data)").font(.caption).foregroundStyle(StrandPalette.textTertiary)
        ECGWave(color: StrandPalette.statusWarning).frame(width: 152)
        Text("Flat (disconnected)").font(.caption).foregroundStyle(StrandPalette.textTertiary)
        ECGWave(color: StrandPalette.textTertiary, flat: true).frame(width: 152)
    }
    .padding(24)
    .frame(width: 320, height: 260)
    .background(StrandPalette.surfaceBase)
    .preferredColorScheme(.dark)
}
#endif
