import SwiftUI

// MARK: - StepChart — a step-rendered series for working weight (FER-F · 2d)
//
// The working weight changes in JUMPS, not slopes — a line chart invents gradients between sessions
// that never happened. This renders the honest shape: horizontal runs at each weight joined by vertical
// steps, a dot at every confirmed raise, and an amber dot where the weight DROPPED (a deload). Pure
// geometry over `[Double]`; the screen owns what the values mean.
public struct StepChart: View {
    let values: [Double]
    let line: Color
    let raiseDot: Color
    let deloadDot: Color

    /// Weight drops smaller than this fraction are noise (unit rounding), not a deload.
    private static let dropThreshold = 0.02

    public init(values: [Double], line: Color, raiseDot: Color, deloadDot: Color) {
        self.values = values; self.line = line; self.raiseDot = raiseDot; self.deloadDot = deloadDot
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack {
                stepPath(in: geo.size)
                    .stroke(line, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                ForEach(1..<max(values.count, 1), id: \.self) { i in
                    let prev = values[i - 1], cur = values[i]
                    if cur > prev + 0.0001 {
                        Circle().fill(raiseDot).frame(width: 5, height: 5)
                            .position(point(i, in: geo.size))
                    } else if cur < prev * (1 - Self.dropThreshold) {
                        Circle().fill(deloadDot).frame(width: 5, height: 5)
                            .position(point(i, in: geo.size))
                    }
                }
            }
        }
    }

    private static let inset: CGFloat = 4

    private func point(_ i: Int, in size: CGSize) -> CGPoint {
        let lo = values.min() ?? 0
        let span = max((values.max() ?? 1) - lo, 0.0001)
        let x = values.count > 1
            ? Self.inset + (size.width - 2 * Self.inset) * CGFloat(i) / CGFloat(values.count - 1)
            : size.width / 2
        let y = Self.inset + (size.height - 2 * Self.inset) * CGFloat(1 - (values[i] - lo) / span)
        return CGPoint(x: x, y: y)
    }

    /// Horizontal run at each weight, then the vertical jump — never a slope between sessions.
    private func stepPath(in size: CGSize) -> Path {
        Path { p in
            guard !values.isEmpty else { return }
            p.move(to: point(0, in: size))
            for i in 1..<values.count {
                let prev = point(i - 1, in: size), cur = point(i, in: size)
                p.addLine(to: CGPoint(x: cur.x, y: prev.y))
                p.addLine(to: cur)
            }
        }
    }
}

#if DEBUG
#Preview("StepChart · raises + deload") {
    StepChart(values: [80, 80, 82.5, 82.5, 85, 85, 85, 78.5, 80, 82.5],
              line: InstrumentoTheme.base.ink,
              raiseDot: InstrumentoTheme.base.dataRecovery,
              deloadDot: InstrumentoTheme.base.warning)
        .frame(width: 340, height: 64)
        .padding()
        .background(InstrumentoTheme.base.paper)
}
#endif
