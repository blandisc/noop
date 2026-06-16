import SwiftUI

// MARK: - «Instrumento diurno» — 24-hour Diurnal Dial (FER-134)
//
// The hero marker of the redesigned TodayView: a 24-hour clock face that shows
// the current time, the night's sleep window, and the day's sunrise/sunset. It
// replaces the literal sun glyph (dropped as generic).
//
// It speaks the language (see Instrumento.swift):
//   • Reads the active theme from `\.instrumentoTheme`, so the by-the-hour engine
//     (FER-132) recolors the whole dial for free — the ring quietly warms from day
//     to dusk to night without the dial drawing any colored chrome itself.
//   • COLOR ONLY IN THE DATUM. The face carries no saturated hue: day vs. night,
//     the sleep band, and the now-dot are all drawn in ink/paper tones. The health
//     datum's color belongs to the hero numeral TodayView lays over the centre —
//     which is why the centre is intentionally left empty here.
//
// Dependency-free, like the rest of StrandDesign: the sun and sleep windows are
// INJECTED (`SolarWindow` / `SleepWindow`), never imported. The app computes them
// from `StrandAnalytics.SolarClock` and the on-device sleep record (no new
// permissions) and passes plain values in. Pure + deterministic: the dial reads an
// injected `Date`/`Calendar`, so it never calls `Date()` for its geometry and is
// fully testable.

// MARK: - Injected sleep window (no StrandStore / HealthKit dependency)

/// The night's sleep window as clock hours (e.g. `23.5` == 23:30). The app reads
/// this from the on-device sleep record it already has — no new permission — and
/// injects it, the same way `SolarWindow` carries sunrise/sunset. Keeping it a
/// plain value keeps `StrandDesign` the dependency-free leaf of the package graph.
public struct SleepWindow: Equatable, Sendable {
    public let bedtime: Double   // clock hours, 0...24
    public let wake: Double      // clock hours, 0...24
    public init(bedtime: Double, wake: Double) {
        self.bedtime = bedtime
        self.wake = wake
    }
}

// MARK: - Geometry (pure, testable)

/// The pure math of the 24-hour face, factored out so the "now-dot is at the right
/// place" claim can be unit-tested without rendering anything.
enum DialGeometry {

    /// Clock angle for an hour on the 24h face — **noon (12) up, midnight (0/24)
    /// down**, time advancing **clockwise**. In SwiftUI angle terms (0° points east,
    /// positive sweeps clockwise on the y-down canvas) that is `hour·15° − 270°`:
    /// 12→−90° (up), 18→0° (east), 24/0→90°/−270° (down), 6→−180° (west).
    static func degrees(forHour hour: Double) -> Double { hour * 15.0 - 270.0 }
    static func angle(forHour hour: Double) -> Angle { .degrees(degrees(forHour: hour)) }

    /// The point on a circle of `radius` about `center` for a clock hour.
    static func point(forHour hour: Double, center: CGPoint, radius: CGFloat) -> CGPoint {
        let a = degrees(forHour: hour) * .pi / 180.0
        let r = Double(radius)
        return CGPoint(x: Double(center.x) + r * cos(a), y: Double(center.y) + r * sin(a))
    }

    /// Forward span in hours from `from` to `to` going clockwise, wrapping midnight
    /// (e.g. 23.5 → 7.25 == 7.75h). Used for the sleep band and the day arc.
    static func spanHours(from: Double, to: Double) -> Double {
        var span = to - from
        if span < 0 { span += 24 }
        return span
    }

    /// The rotation offset (degrees) that parks the now-dot back at midnight for the
    /// start of the opening sweep; the sweep animates this to 0 so the dot travels
    /// clockwise along the ring up to the current hour.
    static func sweepStartDegrees(forHour hour: Double) -> Double { -hour * 15.0 }
}

// MARK: - DiurnalDial

public struct DiurnalDial: View {

    /// The instant to mark with the "now" dot. Injected (default `Date()`) so the
    /// geometry stays pure and testable; the dial never reads `Date()` for layout.
    public var now: Date
    /// Supplies the local hour from `now` (carries the time zone). Default `.current`.
    public var calendar: Calendar
    /// Sunrise/sunset as clock hours. `nil` (polar night / midnight sun, or unknown)
    /// → the day arc and sunrise/sunset marks are omitted: a plain, uniform ring with
    /// no day/night crossing.
    public var solar: SolarWindow?
    /// The night's sleep window as clock hours. `nil` → no band is drawn.
    public var sleep: SleepWindow?
    /// Diameter of the dial; every other measure scales from it.
    public var diameter: CGFloat
    /// Whether to play the opening sweep + pulse. Default `true`; pass `false` for a
    /// static render (previews, snapshot harness, or any caller that wants the dot
    /// to sit at the current hour with no entrance). `prefers-reduced-motion` forces
    /// it off regardless.
    public var animated: Bool

    public init(
        now: Date = Date(),
        calendar: Calendar = .current,
        solar: SolarWindow? = nil,
        sleep: SleepWindow? = nil,
        diameter: CGFloat = 240,
        animated: Bool = true
    ) {
        self.now = now
        self.calendar = calendar
        self.solar = solar
        self.sleep = sleep
        self.diameter = diameter
        self.animated = animated
    }

    @Environment(\.instrumentoTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Resting state is the *final* state (sweepDegrees 0, no pulse), so a static
    // render — ImageRenderer, or with reduced motion — already shows the dot at the
    // current hour. The opening sweep is an entrance that runs only when animation
    // is allowed (see `startSweep`).
    @State private var sweepDegrees: Double = 0
    @State private var pulsing: Bool = false

    // MARK: Derived measures (all scale from `diameter`)

    private var ringRadius: CGFloat { diameter * 0.42 }
    private var sleepRadius: CGFloat { diameter * 0.368 }
    private var trackWidth: CGFloat { max(2, diameter * 0.012) }
    private var bandWidth: CGFloat { diameter * 0.030 }
    private var dotDiameter: CGFloat { diameter * 0.044 }
    private var haloDiameter: CGFloat { diameter * 0.12 }

    private var nowHour: Double { InstrumentoThemeEngine.localHour(of: now, calendar: calendar) }

    /// Motion is allowed only when the caller asked for it AND the system isn't in
    /// reduced-motion. When off, the dial rests at its final state (dot at `now`,
    /// halo static) with no entrance.
    private var allowsMotion: Bool { animated && !reduceMotion }

    public var body: some View {
        ZStack {
            staticFace
            nowLayer
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityText))
        .onAppear(perform: startSweep)
    }

    // MARK: Static face — track, day arc, sleep band, ticks, sun marks

    private var staticFace: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let r = ringRadius

            // The full 24h track — a quiet warm rule (the dial's instrument bezel).
            ctx.stroke(circlePath(center: c, radius: r),
                       with: .color(theme.hairlineStrong), lineWidth: trackWidth)

            // Day arc (sunrise → sunset, over the top). Distinguishes day from night
            // by TONE, not color — ink, never a data hue. Omitted in the polar case.
            if let s = solar {
                ctx.stroke(arcPath(center: c, radius: r, fromHour: s.sunrise, toHour: s.sunset),
                           with: .color(theme.inkTertiary.opacity(0.5)),
                           style: StrokeStyle(lineWidth: trackWidth, lineCap: .round))
            }

            // Sleep band — a faint inner segment, crossing midnight as needed.
            if let sl = sleep {
                ctx.stroke(arcPath(center: c, radius: sleepRadius, fromHour: sl.bedtime, toHour: sl.wake),
                           with: .color(theme.ink.opacity(0.12)),
                           style: StrokeStyle(lineWidth: bandWidth, lineCap: .round))
            }

            // Quiet cardinal ticks (00 / 06 / 12 / 18) to orient the face.
            let cardIn = r - diameter * 0.018, cardOut = r + diameter * 0.018
            for h in stride(from: 0.0, to: 24.0, by: 6.0) {
                ctx.stroke(tickPath(center: c, hour: h, inner: cardIn, outer: cardOut),
                           with: .color(theme.hairlineStrong), lineWidth: 1.4)
            }

            // Sunrise / sunset marks — a touch stronger than the cardinals, still ink.
            if let s = solar {
                let sunIn = r - diameter * 0.028, sunOut = r + diameter * 0.028
                for h in [s.sunrise, s.sunset] {
                    ctx.stroke(tickPath(center: c, hour: h, inner: sunIn, outer: sunOut),
                               with: .color(theme.inkSecondary),
                               style: StrokeStyle(lineWidth: 2, lineCap: .round))
                }
            }
        }
        .frame(width: diameter, height: diameter)
    }

    // MARK: Now layer — the dot + breathing halo, swept in on open

    private var nowLayer: some View {
        let c = CGPoint(x: diameter / 2, y: diameter / 2)
        let p = DialGeometry.point(forHour: nowHour, center: c, radius: ringRadius)
        return ZStack {
            // Soft halo that breathes (pulse). Ink, low opacity — a point of light on
            // paper reads as a crisp dark focus, not a glow.
            Circle()
                .fill(theme.ink)
                .frame(width: haloDiameter, height: haloDiameter)
                .scaleEffect(pulsing ? 1.3 : 0.92)
                .opacity(pulsing ? 0.05 : 0.18)
                .animation(allowsMotion ? StrandMotion.breathe : nil, value: pulsing)
                .position(p)
            // The now dot.
            Circle()
                .fill(theme.ink)
                .frame(width: dotDiameter, height: dotDiameter)
                .position(p)
        }
        .frame(width: diameter, height: diameter)
        // Rotating the whole layer about the dial centre sends the dot travelling
        // ALONG the ring (an arc), not across the chord — the opening sweep.
        .rotationEffect(.degrees(sweepDegrees))
        .accessibilityHidden(true)
    }

    private func startSweep() {
        // Motion off (reduced-motion or `animated: false`): leave the resting state —
        // dot already at the current hour, no pulse.
        guard allowsMotion else { return }
        pulsing = true
        // Park the dot at midnight, then settle it to "now" on the next runloop so the
        // two state changes don't coalesce into a no-op.
        sweepDegrees = DialGeometry.sweepStartDegrees(forHour: nowHour)
        DispatchQueue.main.async {
            withAnimation(StrandMotion.drawIn) { sweepDegrees = 0 }
        }
    }

    // MARK: Path builders

    private func circlePath(center: CGPoint, radius: CGFloat) -> Path {
        Path { $0.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius,
                                        width: radius * 2, height: radius * 2)) }
    }

    private func arcPath(center: CGPoint, radius: CGFloat, fromHour: Double, toHour: Double) -> Path {
        let span = DialGeometry.spanHours(from: fromHour, to: toHour)
        var path = Path()
        path.addArc(center: center, radius: radius,
                    startAngle: DialGeometry.angle(forHour: fromHour),
                    endAngle: DialGeometry.angle(forHour: fromHour + span),
                    clockwise: false)
        return path
    }

    private func tickPath(center: CGPoint, hour: Double, inner: CGFloat, outer: CGFloat) -> Path {
        var path = Path()
        path.move(to: DialGeometry.point(forHour: hour, center: center, radius: inner))
        path.addLine(to: DialGeometry.point(forHour: hour, center: center, radius: outer))
        return path
    }

    // MARK: Accessibility

    private func clockString(_ hour: Double) -> String {
        let total = Int((hour.truncatingRemainder(dividingBy: 24) + 24).truncatingRemainder(dividingBy: 24) * 60.0 + 0.5)
        return String(format: "%02d:%02d", (total / 60) % 24, total % 60)
    }

    private var accessibilityText: String {
        var parts = ["Reloj de 24 horas. Son las \(clockString(nowHour))."]
        if let s = solar {
            parts.append("Amanecer \(clockString(s.sunrise)), atardecer \(clockString(s.sunset)).")
        }
        if let sl = sleep {
            parts.append("Ventana de sueño de \(clockString(sl.bedtime)) a \(clockString(sl.wake)).")
        }
        return parts.joined(separator: " ")
    }
}

// MARK: - Previews

#if DEBUG
#Preview("DiurnalDial · por hora") {
    func utc() -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    func at(_ h: Int, _ m: Int = 0) -> Date {
        utc().date(from: DateComponents(year: 2026, month: 6, day: 16, hour: h, minute: m))!
    }
    let sun = SolarWindow(sunrise: 6.2, sunset: 19.8)
    let bed = SleepWindow(bedtime: 23.5, wake: 7.25)

    func panel(_ label: String, _ date: Date, solar: SolarWindow?) -> some View {
        let theme = InstrumentoThemeEngine.theme(at: date, calendar: utc(), solar: solar)
        return VStack(spacing: 10) {
            DiurnalDial(now: date, calendar: utc(), solar: solar, sleep: bed, diameter: 150)
            Text(label).instrumentoOverline().foregroundStyle(theme.inkTertiary)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(theme.paper)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .instrumentoTheme(theme)
    }

    return ScrollView {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                panel("12:30 · día", at(12, 30), solar: sun)
                panel("19:00 · atardecer", at(19), solar: sun)
            }
            HStack(spacing: 14) {
                panel("23:30 · noche", at(23, 30), solar: sun)
                panel("14:00 · sin sol (polar)", at(14), solar: nil)
            }
        }
        .padding(16)
    }
    .background(Color(hex: "#E8E2D6"))
}
#endif
