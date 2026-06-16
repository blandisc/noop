import SwiftUI
#if canImport(Combine)
import Combine
#endif

// MARK: - «Instrumento diurno» — by-the-hour theme engine (FER-132)
//
// FER-131 shipped the `InstrumentoTheme` role struct and its `.base` daytime
// anchor, plus the `\.instrumentoTheme` Environment channel (default `.base`) that
// `ScreenScaffold` and the loading/empty/error states already read. This file adds
// the *engine* that varies that theme across the day: it interpolates ALL twelve
// roles between four anchors (dawn / day / dusk / night) in the perceptual OKLab
// space and overrides `\.instrumentoTheme` app-wide by the device clock.
//
// Design decisions (signed off by /arquitecto on FER-132):
//   • Reuses `\.instrumentoTheme` — does NOT introduce a second Environment key.
//   • `day == .base`; dawn/dusk/night are derived warm variants.
//   • Interpolation is in OKLab (Björn Ottosson, 2020, https://bottosson.github.io/posts/oklab/)
//     so adjacent minutes transition cleanly — sRGB lerp would dim and hue-shift.
//   • The night anchor is a *dimmed warm parchment*, NOT an inverted dark mode.
//     A dark-mode night would force the interpolation across a point where ink and
//     paper share luminance (contrast 1:1), breaking the "AA at every hour" rule.
//     Keeping ink the dark pole at every anchor preserves AA across the whole sweep.
//   • Sunrise/sunset (FER-133 `SolarClock`, in StrandAnalytics) is consumed by
//     INJECTION, never imported: StrandDesign is the dependency-free leaf of the
//     package graph. The app passes a `SolarWindow`; `nil` falls back to fixed hours.
//   • 100% offline: the engine reads only an injected `Date`/`Calendar` (+ optional
//     solar window). It never calls `Date()` itself, so it is fully deterministic
//     and testable.

// MARK: - Solar window (injected; no StrandAnalytics dependency)

/// Local sunrise / sunset as clock hours (e.g. `6.5` == 06:30). The app computes
/// these from `StrandAnalytics.SolarClock.sunWindow(on:in:)` and injects them so
/// the dawn/dusk anchors track the real sun. Keeping this a plain value here means
/// `StrandDesign` stays dependency-free (the acyclic-graph rule).
public struct SolarWindow: Equatable, Sendable {
    public let sunrise: Double   // clock hours, 0...24
    public let sunset: Double    // clock hours, 0...24
    public init(sunrise: Double, sunset: Double) {
        self.sunrise = sunrise
        self.sunset = sunset
    }
}

// MARK: - Engine

public enum InstrumentoThemeEngine {

    // The four anchors. `day` is FER-131's `.base`; the others are warm variants
    // whose every text/background pair clears WCAG AA at the anchor AND across the
    // interpolated sweep (verified in `InstrumentoThemeEngineTests`). Night is a
    // dimmed parchment with near-black ink — never inverted (see header).
    public static let dawn = InstrumentoTheme(
        paper:          Color(hex: "#F3E8DD"),
        surface:        Color(hex: "#FBF4EC"),
        hairline:       Color(hex: "#E7DBCB"),
        hairlineStrong: Color(hex: "#D8C9B5"),
        ink:            Color(hex: "#241B14"),
        inkSecondary:   Color(hex: "#5E5446"),
        inkTertiary:    Color(hex: "#6E6253"),
        dataRecovery:   Color(hex: "#0B8A5F"),
        dataStrain:     Color(hex: "#BE5A1B"),
        verdict:        Color(hex: "#0B8A5F"),
        warning:        Color(hex: "#985910"),
        critical:       Color(hex: "#BA382F")
    )

    /// Midday anchor — identical to `InstrumentoTheme.base` (FER-131). A test
    /// asserts `day == .base` so a future change to `.base` can't silently drift.
    public static let day = InstrumentoTheme.base

    public static let dusk = InstrumentoTheme(
        paper:          Color(hex: "#F1E2CE"),
        surface:        Color(hex: "#F8EEDD"),
        hairline:       Color(hex: "#E3D3BC"),
        hairlineStrong: Color(hex: "#D2BFA3"),
        ink:            Color(hex: "#241C13"),
        inkSecondary:   Color(hex: "#5C5240"),
        inkTertiary:    Color(hex: "#6B5F4C"),
        dataRecovery:   Color(hex: "#0B7E59"),
        dataStrain:     Color(hex: "#B65216"),
        verdict:        Color(hex: "#0B7E59"),
        warning:        Color(hex: "#8E540D"),
        critical:       Color(hex: "#B2342B")
    )

    /// Night anchor — dimmed warm parchment, near-black ink, accents kept legible
    /// (≥3:1 at numeral size) so the datum doesn't go dead in the dark.
    public static let night = InstrumentoTheme(
        paper:          Color(hex: "#CDBE9F"),
        surface:        Color(hex: "#D6C8AB"),
        hairline:       Color(hex: "#B6A684"),
        hairlineStrong: Color(hex: "#A8966F"),
        ink:            Color(hex: "#191309"),
        inkSecondary:   Color(hex: "#352B1A"),
        inkTertiary:    Color(hex: "#473A24"),
        dataRecovery:   Color(hex: "#0A5C3F"),
        dataStrain:     Color(hex: "#8A3C0E"),
        verdict:        Color(hex: "#0A5C3F"),
        warning:        Color(hex: "#6E3F08"),
        critical:       Color(hex: "#8C271F")
    )

    /// Fixed-hour anchor positions used when no solar window is injected.
    private static let fixedDawn = 6.5, fixedDay = 13.0, fixedDusk = 19.0

    /// The active theme for a moment in time. Pure and deterministic — pass the
    /// clock in; the engine never reads `Date()` itself.
    ///
    /// - Parameters:
    ///   - date: the instant to theme.
    ///   - calendar: supplies the local hour (carries the time zone). Default `.current`.
    ///   - solar: optional sunrise/sunset to anchor dawn/dusk to the real sun;
    ///     `nil` (polar / unknown) falls back to fixed hours.
    public static func theme(at date: Date,
                             calendar: Calendar = .current,
                             solar: SolarWindow? = nil) -> InstrumentoTheme {
        let hour = localHour(of: date, calendar: calendar)
        let (dawnH, dayH, duskH) = anchorHours(for: solar)

        // Circular schedule across the 24-hour clock: night sits at both ends.
        // Stops MUST be strictly increasing; anchorHours guarantees it.
        let stops: [(h: Double, t: InstrumentoTheme)] = [
            (0,     night),
            (dawnH, dawn),
            (dayH,  day),
            (duskH, dusk),
            (24,    night),
        ]
        for i in 0..<(stops.count - 1) {
            let a = stops[i], b = stops[i + 1]
            if hour >= a.h && hour <= b.h {
                let span = b.h - a.h
                let t = span > 0 ? (hour - a.h) / span : 0
                return a.t.interpolated(to: b.t, fraction: t)
            }
        }
        return day   // unreachable (hour ∈ [0,24]); satisfies the compiler
    }

    static func localHour(of date: Date, calendar: Calendar) -> Double {
        let c = calendar.dateComponents([.hour, .minute, .second], from: date)
        return Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60.0 + Double(c.second ?? 0) / 3600.0
    }

    /// Resolve the dawn/day/dusk hour positions, preferring the injected sun. Falls
    /// back to fixed hours if the window is missing or doesn't yield a strictly
    /// increasing 0 < dawn < day < dusk < 24 schedule (extreme longitudes / polar).
    static func anchorHours(for solar: SolarWindow?) -> (dawn: Double, day: Double, dusk: Double) {
        guard let s = solar else { return (fixedDawn, fixedDay, fixedDusk) }
        let dawnH = s.sunrise
        let duskH = s.sunset
        let dayH = (s.sunrise + s.sunset) / 2.0
        if dawnH > 0, dawnH < dayH, dayH < duskH, duskH < 24 {
            return (dawnH, dayH, duskH)
        }
        return (fixedDawn, fixedDay, fixedDusk)
    }
}

// MARK: - OKLab interpolation core (pure, Foundation-only math)
//
// Björn Ottosson's OKLab (2020). sRGB transfer + the two 3×3 matrices; round-trips
// to <2e-3 per channel (asserted in tests). Interpolating L,a,b keeps lightness and
// hue perceptually even between adjacent minutes — the whole point of OKLab here.

extension InstrumentoTheme {
    /// Interpolate every role toward `other` by `fraction` (0...1) in OKLab.
    func interpolated(to other: InstrumentoTheme, fraction: Double) -> InstrumentoTheme {
        let t = min(max(fraction, 0), 1)
        func mix(_ a: Color, _ b: Color) -> Color { OKLab.mix(a, b, t) }
        return InstrumentoTheme(
            paper:          mix(paper, other.paper),
            surface:        mix(surface, other.surface),
            hairline:       mix(hairline, other.hairline),
            hairlineStrong: mix(hairlineStrong, other.hairlineStrong),
            ink:            mix(ink, other.ink),
            inkSecondary:   mix(inkSecondary, other.inkSecondary),
            inkTertiary:    mix(inkTertiary, other.inkTertiary),
            dataRecovery:   mix(dataRecovery, other.dataRecovery),
            dataStrain:     mix(dataStrain, other.dataStrain),
            verdict:        mix(verdict, other.verdict),
            warning:        mix(warning, other.warning),
            critical:       mix(critical, other.critical)
        )
    }
}

enum OKLab {
    struct Lab { var L, a, b: Double }

    static func srgbToLinear(_ c: Double) -> Double {
        c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }
    static func linearToSrgb(_ c: Double) -> Double {
        c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1.0 / 2.4) - 0.055
    }

    static func toLab(_ rgb: (r: Double, g: Double, b: Double)) -> Lab {
        let lr = srgbToLinear(rgb.r), lg = srgbToLinear(rgb.g), lb = srgbToLinear(rgb.b)
        let l = 0.4122214708 * lr + 0.5363325363 * lg + 0.0514459929 * lb
        let m = 0.2119034982 * lr + 0.6806995451 * lg + 0.1073969566 * lb
        let s = 0.0883024619 * lr + 0.2817188376 * lg + 0.6299787005 * lb
        let l_ = cbrt(l), m_ = cbrt(m), s_ = cbrt(s)
        return Lab(L: 0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
                   a: 1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
                   b: 0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_)
    }

    static func toRGB(_ x: Lab) -> (r: Double, g: Double, b: Double) {
        let l_ = x.L + 0.3963377774 * x.a + 0.2158037573 * x.b
        let m_ = x.L - 0.1055613458 * x.a - 0.0638541728 * x.b
        let s_ = x.L - 0.0894841775 * x.a - 1.2914855480 * x.b
        let l = l_ * l_ * l_, m = m_ * m_ * m_, s = s_ * s_ * s_
        let lr =  4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
        let lg = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
        let lb = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
        func enc(_ v: Double) -> Double { min(1, max(0, linearToSrgb(min(1, max(0, v))))) }
        return (enc(lr), enc(lg), enc(lb))
    }

    /// Interpolate two SwiftUI colors in OKLab. Uses the package's existing
    /// `rgbaComponents` bridge (AppKit/UIKit) — the same path `StrandPalette`
    /// already interpolates through.
    static func mix(_ a: Color, _ b: Color, _ t: Double) -> Color {
        let ca = a.rgbaComponents, cb = b.rgbaComponents
        let la = toLab((ca.r, ca.g, ca.b)), lb = toLab((cb.r, cb.g, cb.b))
        let m = Lab(L: la.L + (lb.L - la.L) * t,
                    a: la.a + (lb.a - la.a) * t,
                    b: la.b + (lb.b - la.b) * t)
        let out = toRGB(m)
        return Color(.sRGB, red: out.r, green: out.g, blue: out.b)
    }
}

// MARK: - App-wide driver (@MainActor)
//
// Recomputes the theme on a low-frequency timer (interpolation is continuous, so a
// per-minute tick is visually seamless and cheap) and on demand (foreground). Pure
// SwiftUI + Foundation — no UIKit notification, so it stays package-pure and works
// on macOS and iOS alike.

@MainActor
public final class InstrumentoThemeDriver: ObservableObject {
    @Published public private(set) var theme: InstrumentoTheme
    private var solar: SolarWindow?
    private var timer: Timer?
    private let interval: TimeInterval

    /// - Parameters:
    ///   - solar: optional injected sunrise/sunset; updatable via `update(solar:)`.
    ///   - interval: recompute cadence (default 60s).
    public init(solar: SolarWindow? = nil, interval: TimeInterval = 60) {
        self.solar = solar
        self.interval = interval
        self.theme = InstrumentoThemeEngine.theme(at: Date(), solar: solar)
        startTimer()
    }

    /// Recompute now (call on `scenePhase == .active`).
    public func refresh() {
        theme = InstrumentoThemeEngine.theme(at: Date(), solar: solar)
    }

    /// Swap in a freshly computed solar window (e.g. after a day rollover) and
    /// recompute immediately.
    public func update(solar: SolarWindow?) {
        self.solar = solar
        refresh()
    }

    private func startTimer() {
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    deinit { timer?.invalidate() }
}

// MARK: - View entry point

private struct InstrumentoThemeByHourModifier: ViewModifier {
    @StateObject private var driver: InstrumentoThemeDriver
    @Environment(\.scenePhase) private var scenePhase

    init(solar: SolarWindow?) {
        _driver = StateObject(wrappedValue: InstrumentoThemeDriver(solar: solar))
    }

    func body(content: Content) -> some View {
        content
            .instrumentoTheme(driver.theme)
            .onChange(of: scenePhase) { phase in
                if phase == .active { driver.refresh() }
            }
    }
}

public extension View {
    /// Drive `\.instrumentoTheme` by the device clock for this subtree. Apply ONCE
    /// at the app root; every descendant reading `\.instrumentoTheme` (ScreenScaffold,
    /// state views, …) recolors by time of day for free. Pass `solar` (from the
    /// app's `SolarClock` call) to anchor dawn/dusk to the real sun.
    func instrumentoThemeByHour(solar: SolarWindow? = nil) -> some View {
        modifier(InstrumentoThemeByHourModifier(solar: solar))
    }
}

#if DEBUG
#Preview("Instrumento · por hora") {
    func swatches(_ t: InstrumentoTheme, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.system(size: 11, weight: .medium)).tracking(0.6)
                .textCase(.uppercase).foregroundStyle(t.inkTertiary)
            Text("82").instrumentoHero(56).foregroundStyle(t.dataRecovery)
            HStack(spacing: 8) {
                ForEach([("paper", t.paper), ("ink", t.ink), ("recovery", t.dataRecovery),
                         ("strain", t.dataStrain), ("warning", t.warning)], id: \.0) { _, c in
                    RoundedRectangle(cornerRadius: 6).fill(c).frame(width: 40, height: 32)
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(t.hairlineStrong, lineWidth: 1))
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(t.paper)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    func at(_ h: Int) -> InstrumentoTheme {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        let d = c.date(from: DateComponents(year: 2026, month: 6, day: 16, hour: h))!
        return InstrumentoThemeEngine.theme(at: d, calendar: c)
    }
    return ScrollView {
        VStack(spacing: 12) {
            swatches(at(6),  "06:00 · amanecer")
            swatches(at(12), "12:00 · día")
            swatches(at(19), "19:00 · atardecer")
            swatches(at(23), "23:00 · noche")
        }
        .padding(16)
    }
    .background(Color(hex: "#ECE7DC"))
}
#endif
