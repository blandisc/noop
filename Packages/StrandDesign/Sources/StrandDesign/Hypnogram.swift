import SwiftUI

// MARK: - Hypnogram (§9.4 Sleep)
//
// A sleep-stage horizontal banded timeline. Each interval is drawn as a band at
// the height of its stage (awake top → deep bottom), colored per §9.1 (awake
// rose, light periwinkle, deep indigo, REM glowing mint). Adjacent intervals are
// connected by vertical risers so the trace reads as one continuous "staircase".

/// A single stage interval. `start`/`end` are seconds from the start of the night.
public struct SleepInterval: Identifiable, Sendable {
    public let id = UUID()
    public var stage: SleepStage
    public var start: TimeInterval
    public var end: TimeInterval

    public init(stage: SleepStage, start: TimeInterval, end: TimeInterval) {
        self.stage = stage
        self.start = start
        self.end = end
    }

    public var duration: TimeInterval { max(0, end - start) }
}

public struct Hypnogram: View {

    public var intervals: [SleepInterval]
    /// Height of the plotting band.
    public var height: CGFloat
    /// Whether to draw the stage labels down the left edge.
    public var showsStageAxis: Bool
    /// Whether hovering a stage band highlights it and shows a tooltip
    /// (stage name, clock start–end, duration). Defaults on.
    public var showsScrub: Bool
    /// Optional wall-clock time the night began. When set, the tooltip shows
    /// real clock times (e.g. "23:42–00:04"); otherwise it shows elapsed time
    /// from the start of the night (e.g. "0:06–0:28").
    public var nightStart: Date?

    public init(
        intervals: [SleepInterval],
        height: CGFloat = 180,
        showsStageAxis: Bool = true,
        showsScrub: Bool = true,
        nightStart: Date? = nil
    ) {
        self.intervals = intervals.sorted { $0.start < $1.start }
        self.height = height
        self.showsStageAxis = showsStageAxis
        self.showsScrub = showsScrub
        self.nightStart = nightStart
    }

    /// Index of the hovered interval, or nil.
    @State private var hoverIndex: Int? = nil

    /// Flat (no REM glow) when rendered in the «Instrumento diurno» light language (FER-131 · 03).
    @Environment(\.instrumentoFlat) private var flat

    private static let clockFormatter: DateFormatter = {
        // Locale-aware short time ("2:26 a. m." in es-MX, "2:26 AM" in en) so the
        // axis reads like the rest of the app — same as Apple Health's sleep chart.
        let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none; return f
    }()

    /// Format a seconds-from-origin offset either as wall-clock (if nightStart
    /// is set) or as elapsed H:MM from the start of the night.
    private func timeLabel(_ secondsFromOrigin: TimeInterval) -> String {
        if let nightStart {
            let d = nightStart.addingTimeInterval(secondsFromOrigin - origin)
            return Hypnogram.clockFormatter.string(from: d)
        }
        let total = Int((secondsFromOrigin - origin).rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        return String(format: "%d:%02d", h, m)
    }

    private var span: TimeInterval {
        guard let first = intervals.first, let last = intervals.max(by: { $0.end < $1.end }) else { return 1 }
        return max(1, last.end - first.start)
    }
    private var origin: TimeInterval { intervals.first?.start ?? 0 }

    // 4 stage rows; awake = rank 0 (top), deep = rank 3 (bottom).
    private let rowCount = 4

    public var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if showsStageAxis { axis }
            VStack(spacing: 6) {
            GeometryReader { geo in
                ZStack {
                    // faint anchor per stage row — a quiet guide, not a grid of rules
                    ForEach(0..<rowCount, id: \.self) { rank in
                        let y = rowY(rank, in: geo.size.height)
                        Path { p in
                            p.move(to: CGPoint(x: 0, y: y))
                            p.addLine(to: CGPoint(x: geo.size.width, y: y))
                        }
                        .stroke(InstrumentoTheme.base.hairline.opacity(0.6), lineWidth: 1)
                    }

                    // No connecting risers — Apple Health's sleep chart leaves the
                    // filled bars to carry the night; the vertical staircase only
                    // added a picket-fence that competed with the data (FER-610).

                    // stage bands
                    ForEach(Array(intervals.enumerated()), id: \.element.id) { idx, interval in
                        let rect = bandRect(for: interval, in: geo.size)
                        let color = StrandPalette.sleepStageColor(interval.stage)
                        let dimmed = hoverIndex != nil && hoverIndex != idx
                        // glow under REM for the dark "REM glowing" requirement — dropped on warm
                        // paper, where bloom only muddies the band's edge (FER-131 handoff · 03).
                        if !flat, interval.stage == .rem {
                            RoundedRectangle(cornerRadius: rect.height / 2)
                                .fill(color)
                                .frame(width: rect.width, height: rect.height)
                                .blur(radius: 6)
                                .opacity(dimmed ? 0.35 : 0.7)
                                .blendMode(.plusLighter)
                                .position(x: rect.midX, y: rect.midY)
                        }
                        RoundedRectangle(cornerRadius: rect.height / 2)
                            .fill(color)
                            .frame(width: rect.width, height: rect.height)
                            .opacity(dimmed ? 0.45 : 1.0)
                            .position(x: rect.midX, y: rect.midY)
                    }

                    // Hover affordance: crosshair, band highlight ring, tooltip.
                    if showsScrub, let idx = hoverIndex, idx < intervals.count {
                        let interval = intervals[idx]
                        let rect = bandRect(for: interval, in: geo.size)
                        let color = StrandPalette.sleepStageColor(interval.stage)
                        // vertical crosshair across the full height at band centre
                        CrosshairRule(x: rect.midX, height: geo.size.height)
                        // ring around the hovered band
                        RoundedRectangle(cornerRadius: (rect.height + 6) / 2)
                            .stroke(InstrumentoTheme.base.hairlineStrong, lineWidth: 1.5)
                            .frame(width: rect.width + 6, height: rect.height + 6)
                            .position(x: rect.midX, y: rect.midY)
                        PositionedTooltip(
                            anchor: CGPoint(x: rect.midX, y: rect.midY),
                            container: geo.size,
                            tooltip: ChartTooltip(
                                value: interval.stage.label,
                                label: "\(timeLabel(interval.start))–\(timeLabel(interval.end)) · \(Int((interval.duration / 60).rounded()))m",
                                accent: color
                            )
                        )
                    }
                }
                .animation(StrandMotion.fade, value: hoverIndex)
                // Light selection haptic each time the finger snaps onto a new stage band (FER-131 · 10).
                .onChange(of: hoverIndex) { _, idx in if idx != nil { ChartHaptics.datumChanged() } }
                .contentShape(Rectangle())
                // Finger-drag scrub on iOS (pointer-hover on macOS). `highPriorityGesture` wins the
                // touch over the parent sheet's vertical ScrollView while the finger is on the band —
                // same affordance the metric `TrendChart` uses (FER-234, mirrors its `scrubGesture`).
                .hypnogramScrub(enabled: showsScrub, size: geo.size,
                                hoverIndex: $hoverIndex, locate: intervalIndex)
            }
            .frame(height: height)
            timeAxis
            }
        }
    }

    // MARK: Time axis
    //
    // Five evenly spaced ticks across the night's span, labelled in real wall
    // clock when `nightStart` is known, otherwise elapsed H:MM. Anchors the
    // trace in time — the night is no longer floating.
    private var timeAxis: some View {
        GeometryReader { geo in
            ForEach(0..<5, id: \.self) { i in
                let frac = CGFloat(i) / 4
                let x = frac * geo.size.width
                let label = timeLabel(origin + Double(frac) * span)
                // tick mark sits at the exact fractional x
                Rectangle()
                    .fill(InstrumentoTheme.base.hairlineStrong)
                    .frame(width: 1, height: 4)
                    .position(x: x, y: 2)
                // label in a fixed-width box, edge-aligned at the extremes so it
                // reads inward from the plot edge instead of clipping it
                let boxW: CGFloat = 60
                let align: Alignment = i == 0 ? .leading : (i == 4 ? .trailing : .center)
                let boxCenter: CGFloat = i == 0 ? x + boxW / 2 : (i == 4 ? x - boxW / 2 : x)
                Text(label)
                    .font(StrandFont.footnote)
                    .foregroundStyle(InstrumentoTheme.base.inkTertiary)
                    .lineLimit(1)
                    .frame(width: boxW, alignment: align)
                    .position(x: boxCenter, y: 12)
            }
        }
        .frame(height: 18)
        // The first/last ticks are onset/wake — surface that to VoiceOver as one
        // phrase (the screen no longer draws a separate time row).
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Asleep \(timeLabel(origin)), awake \(timeLabel(origin + span))"))
    }

    /// The interval whose horizontal span contains a local x, or the nearest.
    private func intervalIndex(atX x: CGFloat, in size: CGSize) -> Int? {
        guard !intervals.isEmpty, size.width > 0 else { return nil }
        let t = origin + Double(x / size.width) * span
        // First try an exact containment hit.
        for (i, iv) in intervals.enumerated() where t >= iv.start && t <= iv.end {
            return i
        }
        // Otherwise snap to the nearest interval by centre time.
        return intervals.enumerated().min(by: { a, b in
            abs(midTime(a.element) - t) < abs(midTime(b.element) - t)
        })?.offset
    }

    private func midTime(_ iv: SleepInterval) -> TimeInterval { (iv.start + iv.end) / 2 }

    // MARK: Axis

    private var axis: some View {
        VStack(alignment: .trailing, spacing: 0) {
            ForEach(stagesTopToBottom, id: \.self) { stage in
                Text(stage.label)
                    .font(StrandFont.footnote)
                    .foregroundStyle(InstrumentoTheme.base.inkSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            }
        }
        .frame(width: 60, height: height)
    }

    private var stagesTopToBottom: [SleepStage] {
        [.awake, .rem, .light, .deep]
    }

    // MARK: Geometry

    private func rowY(_ rank: Int, in totalHeight: CGFloat) -> CGFloat {
        let usable = totalHeight
        let step = usable / CGFloat(rowCount)
        return step * (CGFloat(rank) + 0.5)
    }

    private func bandRect(for interval: SleepInterval, in size: CGSize) -> CGRect {
        let x0 = CGFloat((interval.start - origin) / span) * size.width
        let x1 = CGFloat((interval.end - origin) / span) * size.width
        let thickness: CGFloat = 22
        let y = rowY(interval.stage.bandRank, in: size.height)
        return CGRect(x: x0, y: y - thickness / 2, width: max(2, x1 - x0), height: thickness)
    }

}

// MARK: - Scrub gesture (touch on iOS, pointer on macOS) — FER-234
//
// Mirrors `TrendChart`'s `scrubGesture`: on iOS a `highPriorityGesture(DragGesture(minimumDistance: 0))`
// so the finger-drag wins over the parent sheet's vertical ScrollView and the tooltip appears on first
// contact; on macOS the pointer `onContinuousHover`. `locate` maps a local x to the hovered band index.
private extension View {
    @ViewBuilder
    func hypnogramScrub(enabled: Bool, size: CGSize, hoverIndex: Binding<Int?>,
                        locate: @escaping (CGFloat, CGSize) -> Int?) -> some View {
        #if os(iOS)
        self.highPriorityGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { v in
                    guard enabled else { return }
                    hoverIndex.wrappedValue = locate(v.location.x, size)
                }
                .onEnded { _ in hoverIndex.wrappedValue = nil }
        )
        #elseif os(macOS)
        self.onContinuousHover(coordinateSpace: .local) { phase in
            guard enabled else { return }
            switch phase {
            case .active(let location): hoverIndex.wrappedValue = locate(location.x, size)
            case .ended:                hoverIndex.wrappedValue = nil
            }
        }
        #else
        // FER-740: watchOS builds the package but never renders the scrubbable hypnogram.
        self
        #endif
    }
}

#if DEBUG
private func sampleNight() -> [SleepInterval] {
    // ~7.5h night, seconds.
    var t: TimeInterval = 0
    func add(_ stage: SleepStage, _ minutes: Double) -> SleepInterval {
        let s = SleepInterval(stage: stage, start: t, end: t + minutes * 60)
        t += minutes * 60
        return s
    }
    return [
        add(.awake, 6),
        add(.light, 22),
        add(.deep, 38),
        add(.light, 18),
        add(.rem, 24),
        add(.light, 14),
        add(.deep, 30),
        add(.rem, 28),
        add(.light, 20),
        add(.awake, 4),
        add(.rem, 32),
        add(.light, 26),
        add(.awake, 8),
    ]
}

#Preview("Hypnogram") {
    let start = Calendar.current.date(bySettingHour: 23, minute: 18, second: 0, of: Date())
    return VStack(alignment: .leading, spacing: 12) {
        Text("Last night").strandOverline()
        Text("Hover a band: stage name, clock start–end and duration.")
            .font(StrandFont.footnote).foregroundStyle(InstrumentoTheme.base.inkTertiary)
        Hypnogram(intervals: sampleNight(), height: 200, nightStart: start)
    }
    .padding(28)
    .frame(width: 720, height: 340)
    .background(InstrumentoTheme.base.paper)
    .preferredColorScheme(.light)
}
#endif
