import SwiftUI

// MARK: - StreakArc — the «arco» of a running experiment (FER-462)
//
// One cell per night of the experiment window, drawn as a flexible strip. The kept (streak) nights
// fill left→right in a light→dark green ramp — the run growing visibly — and the remaining nights stay
// quiet hairline. Color only on the datum: the green IS the achievement; the empty cells are chrome.
// Theme-driven for the empty tone; the green ramp is fixed (the `dataRecovery` family from the handoff).

public struct StreakArc: View {
    private let filled: Int
    private let total: Int
    private let theme: InstrumentoTheme
    private let height: CGFloat

    public init(filled: Int, total: Int, theme: InstrumentoTheme, height: CGFloat = 28) {
        self.filled = max(0, filled)
        self.total = max(1, total)
        self.theme = theme
        self.height = height
    }

    /// Light→dark green ramp (the racha growing), taken from the design handoff — the `dataRecovery`
    /// family from a pale mint to a deep evergreen.
    private static let rampStops: [Gradient.Stop] = {
        let hexes = ["D3E8DD", "C5E1D2", "B3D9C3", "9ECFB2", "86C5A0", "6DB98D",
                     "54AD7A", "3CA169", "26965A", "138E55", "0C8F62", "07724D"]
        let n = hexes.count
        return hexes.enumerated().map { i, h in
            Gradient.Stop(color: Color(hex: h), location: Double(i) / Double(n - 1))
        }
    }()

    public var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<total, id: \.self) { i in
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(color(for: i))
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel("Racha: \(min(filled, total)) de \(total)")
    }

    /// A kept cell samples the green ramp by its position in the run (oldest pale, newest deep); an
    /// unkept cell is the warm hairline. A lone kept cell takes the deep end so it still reads as «on».
    private func color(for index: Int) -> Color {
        guard index < filled else { return theme.hairline }
        let pos = filled > 1 ? Double(index) / Double(filled - 1) : 1.0
        return StrandPalette.sample(stops: Self.rampStops, at: pos)
    }
}

#if DEBUG
#Preview("StreakArc") {
    VStack(alignment: .leading, spacing: 20) {
        StreakArc(filled: 12, total: 21, theme: .base)
        StreakArc(filled: 7, total: 7, theme: .base)
        StreakArc(filled: 1, total: 14, theme: .base)
        StreakArc(filled: 0, total: 14, theme: .base, height: 22)
    }
    .padding(24)
    .frame(width: 340)
    .background(InstrumentoTheme.base.paper)
}
#endif
