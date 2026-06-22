import SwiftUI

// MARK: - ExperimentEffectChart — «tu recuperación durante el experimento» (FER-462 / 2b)
//
// The experiment-detail chart: your outcome (recovery / HRV / …) over the days of the experiment,
// drawn as a solid accent line with a faint area and a head dot, against a dashed «media antes» rule —
// your level before you started. Color only on the datum (the measured line); the baseline rule is a
// quiet hairline. Pure SwiftUI Paths, token-driven; no axes (the footer carries the read-out).

public struct ExperimentEffectChart: View {
    private let values: [Double]
    private let baseline: Double?
    private let accent: Color
    private let theme: InstrumentoTheme
    private let height: CGFloat

    public init(values: [Double], baseline: Double?, accent: Color,
                theme: InstrumentoTheme, height: CGFloat = 76) {
        self.values = values
        self.baseline = baseline
        self.accent = accent
        self.theme = theme
        self.height = height
    }

    public var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let pts = points(in: size)
            ZStack {
                if let baseY = baseline.map({ y($0, h: size.height) }) {
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: baseY))
                        p.addLine(to: CGPoint(x: size.width, y: baseY))
                    }
                    .stroke(theme.hairlineStrong, style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                }
                if pts.count >= 2 {
                    Path { p in
                        p.move(to: CGPoint(x: pts[0].x, y: size.height))
                        for pt in pts { p.addLine(to: pt) }
                        p.addLine(to: CGPoint(x: pts[pts.count - 1].x, y: size.height))
                        p.closeSubpath()
                    }
                    .fill(accent.opacity(0.09))

                    Path { p in
                        p.move(to: pts[0])
                        for pt in pts.dropFirst() { p.addLine(to: pt) }
                    }
                    .stroke(accent, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                    Circle().fill(accent).frame(width: 7, height: 7).position(pts[pts.count - 1])
                }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }

    /// Vertical range across the values and the baseline, with a floor so a flat series doesn't divide by zero.
    private var range: (lo: Double, hi: Double) {
        var lo = values.min() ?? 0
        var hi = values.max() ?? 1
        if let b = baseline { lo = Swift.min(lo, b); hi = Swift.max(hi, b) }
        if hi - lo < 1 { hi = lo + 1 }
        return (lo, hi)
    }

    private func y(_ v: Double, h: CGFloat) -> CGFloat {
        let (lo, hi) = range
        let frac = CGFloat((v - lo) / (hi - lo))
        let inset: CGFloat = 6
        return inset + (1 - frac) * (h - inset * 2)
    }

    private func points(in size: CGSize) -> [CGPoint] {
        guard values.count >= 2 else { return [] }
        let stepX = size.width / CGFloat(values.count - 1)
        return values.enumerated().map { i, v in CGPoint(x: CGFloat(i) * stepX, y: y(v, h: size.height)) }
    }
}

#if DEBUG
#Preview("ExperimentEffectChart") {
    VStack(spacing: 24) {
        ExperimentEffectChart(values: [54, 56, 55, 59, 61, 63, 66, 68, 71, 74],
                              baseline: 58, accent: InstrumentoTheme.base.dataRecovery, theme: .base)
        ExperimentEffectChart(values: [70, 68, 69, 66, 64, 63],
                              baseline: 71, accent: InstrumentoTheme.base.dataHrv, theme: .base)
    }
    .padding(24)
    .frame(width: 340)
    .background(InstrumentoTheme.base.paper)
}
#endif
