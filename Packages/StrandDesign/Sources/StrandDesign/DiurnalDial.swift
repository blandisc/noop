import SwiftUI

// MARK: - «Instrumento diurno» — 24-hour Diurnal Dial (FER-134)
//
// The hero marker of the redesigned TodayView: a 24-hour clock face that shows
// the current time, the night's sleep window, and the day's sunrise/sunset. It
// replaces the literal sun glyph (dropped as generic).
//
// It speaks the language (see Instrumento.swift):
//   • Reads the active theme from `\.instrumentoTheme` — now always `InstrumentoTheme.base`
//     (FER-398 retired the by-the-hour engine), so the dial draws in the single warm day
//     palette at every hour. The TIME still shows in the geometry: the now-dot's position,
//     the day arc, and the sleep band all track the real clock — that's the diurnal datum.
//   • COLOR IN THE CHROME, AS DIURNAL CONTEXT (FER-165). The face carries hue to
//     read like the «A color» app icon: the day arc is `dataStrain` amber, the
//     sleep band `dataSleep` indigo, the now-dot `dataRecovery` green, the noon
//     tick ink. This is CONTEXT (sun, sleep, time of day), NOT the health datum —
//     that still belongs to the hero numeral TodayView overlays at the dial's
//     centre (FER-169) — which is why the face itself draws nothing in the middle.
//     (This deliberately supersedes the earlier "color only in the datum" rule for
//     the dial.)
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
    /// Whether to show the «syncing» activity layer (FER-221): a `dataRecovery` arc
    /// that spins over the bezel while the strap's history offload runs. While syncing
    /// the fixed now-dot is hidden (its green moves to the arc) and the rest of the
    /// clock stays put. Indeterminate by design — no percentage (the protocol never
    /// reveals the total pending). `prefers-reduced-motion` rests the arc (no spin).
    public var syncing: Bool
    /// Progreso determinado de «armado» (0…1) del pull-to-refresh propio de Hoy (FER-222):
    /// 0 = en reposo; (0,1] dibuja un arco `dataRecovery` que crece hacia casi todo el aro
    /// conforme el usuario jala, guiado por un punto-cabeza. Al cruzar el umbral el llamador
    /// enciende `syncing` y este arco cede al cometa que gira (FER-221). Se ignora mientras
    /// `syncing` (el giro manda) y el llamador lo deja en 0 bajo reduce-motion (sin dibujo).
    public var armProgress: Double

    public init(
        now: Date = Date(),
        calendar: Calendar = .current,
        solar: SolarWindow? = nil,
        sleep: SleepWindow? = nil,
        diameter: CGFloat = 240,
        syncing: Bool = false,
        armProgress: Double = 0,
        animated: Bool = true
    ) {
        self.now = now
        self.calendar = calendar
        self.solar = solar
        self.sleep = sleep
        self.diameter = diameter
        self.syncing = syncing
        self.armProgress = armProgress
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
    /// Drives the indeterminate sync spin (FER-221). Set from `syncing && allowsMotion`
    /// so reduced-motion rests the arc and the snapshot harness renders it static.
    @State private var spinning: Bool = false

    // MARK: Derived measures (all scale from `diameter`)

    private var ringRadius: CGFloat { diameter * 0.42 }
    private var sleepRadius: CGFloat { diameter * 0.368 }
    private var trackWidth: CGFloat { max(2, diameter * 0.012) }
    /// The day arc is drawn heavier than the bezel track so the amber reads like the
    /// «A color» icon's bold daytime sweep — always at least a hair thicker than it.
    private var dayArcWidth: CGFloat { max(trackWidth + 1, diameter * 0.019) }
    private var bandWidth: CGFloat { diameter * 0.030 }
    private var dotDiameter: CGFloat { diameter * 0.044 }
    private var haloDiameter: CGFloat { diameter * 0.12 }
    /// The paper "moat" behind the now-dot — keeps the green mark legible where it
    /// overlaps the amber day arc (FER-363 polish). A measure, not a token.
    private var nowRingWidth: CGFloat { max(2, diameter * 0.011) }
    /// The day arc's bright midday gold: `dataStrain` lightened toward white in OKLab —
    /// the same first-class technique as `paperHi`/`positiveText`, so it stays a derived
    /// theme color (no invented hex) and dims with the by-the-hour paper.
    private var dayGold: Color { OKLab.mix(theme.dataStrain, Color(.sRGB, red: 1, green: 1, blue: 1), 0.32) }
    /// The spinning sync arc — a hair heavier than the day arc so the green reads as
    /// the live layer riding over the bezel.
    private var syncArcWidth: CGFloat { max(trackWidth + 1, diameter * 0.020) }
    /// Fraction of the ring the sync arc spans (a comet, not a full ring) — a fixed
    /// design constant, not a measure derived from `diameter`.
    private let syncArcFraction: CGFloat = 0.30
    /// Fraction of the ring the determinate «arming» arc reaches at full pull (FER-222) —
    /// nearly a full ring (the owner chose «casi todo el aro»), so the pull reads as charging
    /// the dial before it collapses to the `syncArcFraction` comet that spins. A design
    /// constant, not derived from `diameter`.
    private let armMaxFraction: CGFloat = 0.90

    private var nowHour: Double { InstrumentoThemeEngine.localHour(of: now, calendar: calendar) }

    /// Motion is allowed only when the caller asked for it AND the system isn't in
    /// reduced-motion. When off, the dial rests at its final state (dot at `now`,
    /// halo static) with no entrance.
    private var allowsMotion: Bool { animated && !reduceMotion }

    public var body: some View {
        ZStack {
            staticFace
            // While syncing, the spinning arc replaces the fixed now-dot (the green
            // moves to the arc). While arming (pull-to-refresh, FER-222), a determinate
            // arc grows with the pull. At rest, the now-dot marks the current hour.
            if syncing {
                syncLayer
            } else if armProgress > 0 {
                armingLayer
            } else {
                nowLayer
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityText))
        .onAppear(perform: startSweep)
        // `task(id:)` runs on appear and whenever `syncing` flips — starts/stops the
        // spin without the macOS 14-only two-parameter `onChange`.
        .task(id: syncing) { updateSpin() }
    }

    // MARK: Static face — track, day arc, sleep band, ticks, sun marks

    private var staticFace: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let r = ringRadius

            // The full 24h track — a quiet warm rule (the dial's instrument bezel).
            ctx.stroke(circlePath(center: c, radius: r),
                       with: .color(theme.hairlineStrong), lineWidth: trackWidth)

            // Hour pips — a faint dot at each of the 24 hours so the bezel reads like a
            // real instrument face, not just the 4 cardinals (FER-363 polish). Cardinals
            // get their own heavier ticks below, so skip the multiples of 6 here.
            let pipR = max(0.8, diameter * 0.006)
            for h in stride(from: 0.0, to: 24.0, by: 1.0) where h.truncatingRemainder(dividingBy: 6) != 0 {
                let pc = DialGeometry.point(forHour: h, center: c, radius: r)
                ctx.fill(Path(ellipseIn: CGRect(x: pc.x - pipR, y: pc.y - pipR,
                                                width: pipR * 2, height: pipR * 2)),
                         with: .color(theme.inkTertiary.opacity(0.5)))
            }

            // Day arc (sunrise → sunset, over the top). An amber→gold gradient: brightest
            // gold at the noon peak (top), settling to `dataStrain` amber toward dawn/dusk —
            // the sun's sweep, not a flat band (FER-363 polish). Drawn heavier than the
            // track (`dayArcWidth`) — the «A color» icon's bold daytime sweep. Omitted polar.
            if let s = solar {
                ctx.stroke(arcPath(center: c, radius: r, fromHour: s.sunrise, toHour: s.sunset),
                           with: .linearGradient(Gradient(colors: [dayGold, theme.dataStrain]),
                                                 startPoint: CGPoint(x: c.x, y: c.y - r),
                                                 endPoint: CGPoint(x: c.x, y: c.y)),
                           style: StrokeStyle(lineWidth: dayArcWidth, lineCap: .round))
            }

            // Sleep band — an inner segment in `dataSleep` indigo, crossing midnight as
            // needed. Held back to ~0.55 so it stays the night's quiet context.
            if let sl = sleep {
                ctx.stroke(arcPath(center: c, radius: sleepRadius, fromHour: sl.bedtime, toHour: sl.wake),
                           with: .color(theme.dataSleep.opacity(0.55)),
                           style: StrokeStyle(lineWidth: bandWidth, lineCap: .round))
            }

            // Cardinal ticks (00 / 06 / 12 / 18) to orient the face. Noon is picked out
            // in ink (the icon's top tick); the rest stay a quiet warm rule.
            let cardIn = r - diameter * 0.018, cardOut = r + diameter * 0.018
            for h in stride(from: 0.0, to: 24.0, by: 6.0) {
                let isNoon = h == 12.0
                ctx.stroke(tickPath(center: c, hour: h, inner: cardIn, outer: cardOut),
                           with: .color(isNoon ? theme.ink : theme.hairlineStrong), lineWidth: 1.4)
            }

            // Sunrise / sunset marks — tinted `warning` to ride with the amber day arc.
            if let s = solar {
                let sunIn = r - diameter * 0.028, sunOut = r + diameter * 0.028
                for h in [s.sunrise, s.sunset] {
                    ctx.stroke(tickPath(center: c, hour: h, inner: sunIn, outer: sunOut),
                               with: .color(theme.warning),
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
            // Soft halo that breathes (pulse), in `dataRecovery` green at low opacity —
            // a quiet glow around the "now" mark. Green is FIXED here: it marks the
            // current moment, it does NOT track the day's verdict.
            Circle()
                .fill(theme.dataRecovery)
                .frame(width: haloDiameter, height: haloDiameter)
                .scaleEffect(pulsing ? 1.3 : 0.92)
                .opacity(pulsing ? 0.05 : 0.18)
                .animation(allowsMotion ? StrandMotion.breathe : nil, value: pulsing)
                .position(p)
            // A paper ring behind the dot — a small `paper` disc that separates the green
            // "now" mark from the amber day arc where they overlap (FER-363 polish).
            Circle()
                .fill(theme.paper)
                .frame(width: dotDiameter + nowRingWidth * 2, height: dotDiameter + nowRingWidth * 2)
                .position(p)
            // The now dot — `dataRecovery` green, fixed.
            Circle()
                .fill(theme.dataRecovery)
                .frame(width: dotDiameter, height: dotDiameter)
                .position(p)
        }
        .frame(width: diameter, height: diameter)
        // Rotating the whole layer about the dial centre sends the dot travelling
        // ALONG the ring (an arc), not across the chord — the opening sweep.
        .rotationEffect(.degrees(sweepDegrees))
        .accessibilityHidden(true)
    }

    // MARK: Sync layer — the spinning activity arc (FER-221)

    /// A `dataRecovery` arc that spins over the bezel while a history offload runs,
    /// led by a dot (the «now» green, reused at the arc's head). Indeterminate: no
    /// percentage. Reduced-motion rests it (`spinning` stays false), which also makes
    /// the snapshot harness deterministic. The clock underneath (day arc, sleep band,
    /// ticks) stays put — only this layer moves.
    private var syncLayer: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: syncArcFraction)
                .stroke(theme.dataRecovery,
                        style: StrokeStyle(lineWidth: syncArcWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))                            // start at the top
            Circle()
                .fill(theme.dataRecovery)
                .frame(width: dotDiameter, height: dotDiameter)
                .offset(y: -ringRadius)
                .rotationEffect(.degrees(Double(syncArcFraction) * 360))  // head of the arc
        }
        .frame(width: ringRadius * 2, height: ringRadius * 2)
        .rotationEffect(.degrees(spinning ? 360 : 0))
        .animation(allowsMotion ? StrandMotion.spin() : nil, value: spinning)
        .accessibilityHidden(true)
    }

    // MARK: Arming layer — the determinate pull-to-refresh arc (FER-222)

    /// A determinate `dataRecovery` arc from the top that grows with `armProgress` toward
    /// `armMaxFraction` (nearly a full ring), led by a head dot — the same green that will
    /// spin once the pull commits to `syncing`. Static: the motion IS the gesture driving
    /// `armProgress`, so it follows the finger with no animation of its own (and the caller
    /// keeps `armProgress` at 0 under reduced-motion, resting the dial). Replaces the now-dot
    /// while arming; geometry mirrors `syncLayer` so the handoff to the spinning comet lands
    /// on the same green.
    private var armingLayer: some View {
        let frac = armMaxFraction * CGFloat(min(max(armProgress, 0), 1))
        return ZStack {
            Circle()
                .trim(from: 0, to: frac)
                .stroke(theme.dataRecovery,
                        style: StrokeStyle(lineWidth: syncArcWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))                            // start at the top
            Circle()
                .fill(theme.dataRecovery)
                .frame(width: dotDiameter, height: dotDiameter)
                .offset(y: -ringRadius)
                .rotationEffect(.degrees(Double(frac) * 360))             // head of the arc
        }
        .frame(width: ringRadius * 2, height: ringRadius * 2)
        .accessibilityHidden(true)
    }

    /// Start/stop the spin from the current `syncing` + motion state. Reduced-motion
    /// leaves the arc at rest — an honest, still indicator.
    private func updateSpin() {
        spinning = syncing && allowsMotion
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

    var accessibilityText: String {
        var parts: [String] = []
        if syncing { parts.append(String(localized: "Syncing.", bundle: .main)) }
        parts.append(String(localized: "24-hour clock. It's \(clockString(nowHour)).", bundle: .main))
        if let s = solar {
            parts.append(String(localized: "Sunrise \(clockString(s.sunrise)), sunset \(clockString(s.sunset)).", bundle: .main))
        }
        if let sl = sleep {
            parts.append(String(localized: "Sleep window from \(clockString(sl.bedtime)) to \(clockString(sl.wake)).", bundle: .main))
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
        let theme = InstrumentoTheme.base
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

#Preview("DiurnalDial · armado + sync (FER-222)") {
    func utc() -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    let date = utc().date(from: DateComponents(year: 2026, month: 6, day: 16, hour: 14))!
    let sun = SolarWindow(sunrise: 6.2, sunset: 19.8)
    let bed = SleepWindow(bedtime: 23.5, wake: 7.25)
    let theme = InstrumentoTheme.base

    func panel(_ label: String, armProgress: Double = 0, syncing: Bool = false) -> some View {
        VStack(spacing: 10) {
            DiurnalDial(now: date, calendar: utc(), solar: sun, sleep: bed,
                        diameter: 150, syncing: syncing, armProgress: armProgress)
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
                panel("reposo")
                panel("armando 50%", armProgress: 0.5)
            }
            HStack(spacing: 14) {
                panel("umbral · 100%", armProgress: 1.0)
                panel("sincronizando", syncing: true)
            }
        }
        .padding(16)
    }
    .background(Color(hex: "#E8E2D6"))
}
#endif
