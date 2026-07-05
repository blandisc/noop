#if canImport(SwiftUI)
import SwiftUI

// MARK: - ZoneMeter — the «medidor de zonas» band from the 2026-07 «Hoy» redesign (FER-707/710)
//
// A thin horizontal band that places today's reading on the metric's fixed zones: one rounded
// segment per zone (width ∝ the zone's share of the scale), an ink tick at the reading's position,
// and a row of Grotesk overline labels underneath with the active zone in its own colour. It's the
// «one dominant number, read against your own scale» idea made literal — the datum's position, not a
// second number.
//
// Generic on purpose: the caller (a summary sheet) builds the segments from `MetricLevels` + the
// theme's band roles and passes the reading's `fraction` (0…1 across the scale), so `StrandDesign`
// stays free of `StrandAnalytics`. Colour lives only in the segments + the active label; everything
// structural is hairline/ink.

public struct ZoneMeter: View {
    /// One zone of the meter: how wide it is (its share of the scale), its band colour, whether it's
    /// the reading's zone, and its short label.
    public struct Segment: Identifiable {
        public let id = UUID()
        /// The zone's share of the scale (any positive unit — the row normalises by the sum).
        public let weight: Double
        /// The zone's band colour (a theme role, resolved by the caller).
        public let color: Color
        /// Whether today's reading falls in this zone (drives full vs dimmed opacity + label colour).
        public let isActive: Bool
        /// The zone's short display label (already localized).
        public let label: String

        public init(weight: Double, color: Color, isActive: Bool, label: String) {
            self.weight = weight
            self.color = color
            self.isActive = isActive
            self.label = label
        }
    }

    let segments: [Segment]
    /// The reading's position across the whole scale, 0 (left edge) … 1 (right edge). The ink tick
    /// sits here. nil hides the tick (e.g. no reading yet).
    let fraction: Double?
    let theme: InstrumentoTheme

    private let gap: CGFloat = 3

    public init(segments: [Segment], fraction: Double?, theme: InstrumentoTheme = .base) {
        self.segments = segments
        self.fraction = fraction
        self.theme = theme
    }

    /// Each segment's proportional width for a given available row width, after reserving the gaps
    /// between them, so the widths track the real zone spans (25 / 25 / 20 / 18 / 12) rather than an
    /// even split.
    private func widths(in total: CGFloat) -> [CGFloat] {
        let sum = segments.reduce(0) { $0 + $1.weight }
        guard sum > 0 else { return segments.map { _ in 0 } }
        let usable = max(0, total - gap * CGFloat(segments.count - 1))
        return segments.map { CGFloat($0.weight / sum) * usable }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                let w = widths(in: geo.size.width)
                ZStack(alignment: .leading) {
                    HStack(spacing: gap) {
                        ForEach(Array(segments.enumerated()), id: \.element.id) { i, seg in
                            Capsule()
                                .fill(seg.color)
                                .opacity(seg.isActive ? 0.9 : 0.28)
                                .frame(width: w[i], height: 6)
                        }
                    }
                    if let fraction {
                        Capsule()
                            .fill(theme.ink)
                            .frame(width: 2.5, height: 12)
                            .offset(x: geo.size.width * CGFloat(min(max(fraction, 0), 1)) - 1.25)
                    }
                }
                HStack(spacing: gap) {
                    ForEach(Array(segments.enumerated()), id: \.element.id) { i, seg in
                        Text(seg.label)
                            .font(InstrumentoType.grotesk(8, weight: .semibold))
                            .tracking(0.8)
                            .foregroundStyle(seg.isActive ? seg.color : theme.inkTertiary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .frame(width: w[i], alignment: .leading)
                    }
                }
                .offset(y: 12)
            }
            .frame(height: 24)
        }
        .accessibilityElement(children: .ignore)
    }
}

#if DEBUG
#Preview("ZoneMeter · recuperación 74") {
    let t = InstrumentoTheme.base
    return ZoneMeter(
        segments: [
            .init(weight: 25, color: t.critical, isActive: false, label: "AGOTADO"),
            .init(weight: 25, color: t.warning,  isActive: false, label: "BAJO"),
            .init(weight: 20, color: t.warning,  isActive: false, label: "MODERADO"),
            .init(weight: 18, color: t.verdict,  isActive: true,  label: "ALTO"),
            .init(weight: 12, color: t.verdict,  isActive: false, label: "PLENO"),
        ],
        fraction: 0.74,
        theme: t
    )
    .padding(24)
    .background(t.paper)
}
#endif
#endif
