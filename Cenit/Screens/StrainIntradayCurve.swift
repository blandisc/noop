import SwiftUI
import StrandDesign
import StrandAnalytics

/// The bespoke intraday accumulated-strain curve (FER-730 §5). Solid through the lived portion, a flat
/// dashed projection from «now» to midnight, an area wash under the lived line, a breathing dot at now,
/// and a fixed 00/6/12/18/24 hour axis. Pure StrandDesign tokens; no invented ceiling/window (§5).
struct StrainIntradayCurve: View {
    let points: [TrendPoint]
    let hue: Color
    let theme: InstrumentoTheme
    /// FER-732 · the recommended day-strain ceiling (0–21), a personal recovery-scaled guardrail. nil hides it.
    var ceiling: Double? = nil
    /// FER-732 · the habitual training window in decimal clock hours [0, 24]. nil hides the amber band.
    var window: TrainingHabit.Window? = nil

    /// The x of the scrubbing finger (nil when not scrubbing) — drives the crosshair + tooltip. (FER-748)
    @State private var hoverX: CGFloat? = nil

    /// Locale-aware hour:minute for the scrub tooltip (12/24h per region).
    private static let hourFmt: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("j:mm")
        return f
    }()

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let startOfDay = Calendar.current.startOfDay(for: points.last?.date ?? Date())
                let peak = points.map(\.value).max() ?? 1
                // The ceiling shares the axis, so keep it in view when it sits above today's peak.
                let vMax = max(max(peak, ceiling ?? 0) * 1.15, 1)
                let pts: [CGPoint] = points.map { p in
                    let f = min(max(p.date.timeIntervalSince(startOfDay) / 86_400, 0), 1)
                    return CGPoint(x: CGFloat(f) * w, y: h - CGFloat(p.value / vMax) * h)
                }
                let nowPt = pts.last ?? CGPoint(x: 0, y: h)

                ZStack(alignment: .topLeading) {
                    // Planned-training window (amber), drawn first so the curve reads over it. (FER-732)
                    if let window {
                        let x0 = CGFloat(min(max(window.start / 24, 0), 1)) * w
                        let x1 = CGFloat(min(max(window.end / 24, 0), 1)) * w
                        theme.warning.opacity(StrandOpacity.tintFillStrong)
                            .frame(width: max(0, x1 - x0), height: h)
                            .position(x: (x0 + x1) / 2, y: h / 2)
                    }
                    Path { p in p.move(to: CGPoint(x: 0, y: h)); p.addLine(to: CGPoint(x: w, y: h)) }
                        .stroke(theme.hairline, lineWidth: 1)
                    // Recommended ceiling: a dashed ink line labelled at the left. (FER-732)
                    if let ceiling {
                        let cy = h - CGFloat(min(ceiling, vMax) / vMax) * h
                        Path { p in p.move(to: CGPoint(x: 0, y: cy)); p.addLine(to: CGPoint(x: w, y: cy)) }
                            .stroke(theme.inkSecondary.opacity(StrandOpacity.muted), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        Text("ceiling")
                            .font(StrandFont.micro)
                            .foregroundStyle(theme.inkTertiary)
                            .padding(.horizontal, 3)
                            .background(theme.paper.opacity(0.85)) // token-exempt: >0.70 (fondo de etiqueta casi opaco)
                            .fixedSize()
                            .position(x: 20, y: max(6, cy - 8))
                    }
                    // Area wash under the lived line.
                    Path { p in
                        guard let first = pts.first else { return }
                        p.move(to: CGPoint(x: first.x, y: h))
                        for pt in pts { p.addLine(to: pt) }
                        p.addLine(to: CGPoint(x: nowPt.x, y: h))
                        p.closeSubpath()
                    }.fill(hue.opacity(StrandOpacity.tintFill))
                    // Lived line (solid).
                    Path { p in
                        guard let first = pts.first else { return }
                        p.move(to: first)
                        for pt in pts.dropFirst() { p.addLine(to: pt) }
                    }.stroke(hue, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                    // Projection: flat, dashed, now → midnight (strain only accumulates).
                    if nowPt.x < w - 0.5 {
                        Path { p in
                            p.move(to: nowPt)
                            p.addLine(to: CGPoint(x: w, y: nowPt.y))
                        }.stroke(hue.opacity(0.75), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [1.5, 4])) // token-exempt: >0.70 (proyección punteada)
                    }
                    BreathingDot(color: hue, radius: 3.4).position(x: nowPt.x, y: nowPt.y)

                    // Scrub: crosshair + handle + tooltip that follow the finger over the LIVED curve.
                    // Beyond «now» the finger anchors to the last real point (the projection is synthetic,
                    // so there is no datum to read there). Reuses the shared StrandDesign scrub. (FER-748)
                    let snapped: Int? = hoverX.flatMap { hx in
                        ChartScrubMath.nearestIndex(toX: min(hx, nowPt.x), xs: pts.map(\.x))
                    }
                    Color.clear
                        .contentShape(Rectangle())
                        .scrubGesture(enabled: pts.count > 1, hoverX: $hoverX)
                        .onChange(of: snapped) { _, now in if now != nil { ChartHaptics.datumChanged() } }
                    if let i = snapped, pts.indices.contains(i) {
                        CrosshairRule(x: pts[i].x, height: h)
                        HighlightDot(color: hue).position(x: pts[i].x, y: pts[i].y)
                        PositionedTooltip(
                            anchor: pts[i],
                            container: geo.size,
                            tooltip: ChartTooltip(
                                value: String(format: "%.1f", points[i].value),
                                label: Self.hourFmt.string(from: points[i].date),
                                accent: hue
                            )
                        )
                    }
                }
                .environment(\.instrumentoTheme, theme)
                .environment(\.instrumentoFlat, true)
                .animation(StrandMotion.fade, value: hoverX)
            }
            HStack(spacing: 0) {
                ForEach(["00", "6", "12", "18", "24"], id: \.self) { label in
                    Text(verbatim: label).font(StrandFont.micro).foregroundStyle(theme.inkTertiary)
                    if label != "24" { Spacer(minLength: 0) }
                }
            }
            .frame(height: 12)
        }
    }
}
