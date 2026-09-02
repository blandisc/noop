import SwiftUI

// MARK: - Sello del dial (handoff «Hoy» 2026-07 · FER-709)
//
// The 24-hour dial reduced to its signature: a 34 pt mini dial that lives in the «Hoy» header
// (and doubles as the pull-to-refresh spinner — the CALLER rotates it, this face is static).
// Same clock convention as `DiurnalDial` (`DialGeometry`: noon up, midnight down, clockwise):
// a hairline ring, the day arc in `LiquidColor.ambarClaro` (ex-dataSun peach; oro is yellow
// dawn — FER-316), the night's sleep band in `indigo`, and the «now» dot in `verdePrimario`.
// Arcs are omitted when their window is unknown — an honest blank, never a fabricated sun.
// Pure: the hour is injected, never read from a clock. Paints with `LiquidColor` (FER-316).

public struct DialSeal: View {
    /// The current clock hour (0…24) — places the «now» dot.
    public var hour: Double
    /// Sunrise/sunset window; nil omits the day arc (polar edge cases).
    public var solar: SolarWindow?
    /// Last night's sleep window; nil omits the sleep band (no record).
    public var sleep: SleepWindow?
    public var diameter: CGFloat

    public init(hour: Double, solar: SolarWindow? = nil, sleep: SleepWindow? = nil,
                diameter: CGFloat = 34) {
        self.hour = hour; self.solar = solar; self.sleep = sleep; self.diameter = diameter
    }

    public var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let r = min(size.width, size.height) / 2 - 2
            // Base ring — quiet chrome.
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                       with: .color(LiquidColor.tinta10), lineWidth: 1)
            // Day arc (sunrise → sunset) in the sun hue.
            if let s = solar {
                ctx.stroke(DialGeometry.arc(center: c, radius: r, fromHour: s.sunrise, toHour: s.sunset),
                           with: .color(LiquidColor.ambarClaro),
                           style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
            }
            // Sleep band (bedtime → wake), drawn slightly inset so both arcs read at 34 pt.
            if let s = sleep {
                ctx.stroke(DialGeometry.arc(center: c, radius: r - 3, fromHour: s.bedtime, toHour: s.wake),
                           with: .color(LiquidColor.indigo),
                           style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
            // The «now» dot, on the ring.
            let p = DialGeometry.point(forHour: hour, center: c, radius: r)
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - 2.4, y: p.y - 2.4, width: 4.8, height: 4.8)),
                     with: .color(LiquidColor.fondoAlto))
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - 1.7, y: p.y - 1.7, width: 3.4, height: 3.4)),
                     with: .color(LiquidColor.verdePrimario))
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)   // decorative signature; the header text carries the state
    }
}

#if DEBUG
#Preview("Sello del dial") {
    HStack(spacing: 32) {
        DialSeal(hour: 10.5,
                 solar: SolarWindow(sunrise: 6.2, sunset: 19.8),
                 sleep: SleepWindow(bedtime: 23.5, wake: 7.25))
        DialSeal(hour: 18,
                 solar: SolarWindow(sunrise: 6.2, sunset: 19.8),
                 sleep: nil)
        DialSeal(hour: 2, solar: nil, sleep: nil, diameter: 44)
    }
    .padding(48)
    .background(LiquidColor.fondoAlto)
    .preferredColorScheme(.light)
}
#endif
