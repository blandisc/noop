import SwiftUI

// MARK: - «Instrumento diurno» — clock helper + OKLab color math
//
// FER-398 RETIRED the by-the-hour theme engine (FER-132): the app no longer tints
// itself by the clock. It now anchors to the single day paper (`InstrumentoTheme.base`)
// everywhere, at every hour. (The owner found the night anchor read as "the brightness
// dropped", and the research said time-of-day colour belongs to content, not chrome.)
//
// What remains in this file are the load-bearing pieces the retirement KEPT, because the
// `DiurnalDial` (Hoy's 24h clock) and the paper derivations still need them:
//   • `SolarWindow` — the injected sunrise/sunset value the dial consumes for its day arc
//     (the app computes it from `StrandAnalytics.SolarClock`; injected, never imported, so
//     `StrandDesign` stays the dependency-free leaf of the package graph).
//   • `OKLab` — the perceptual colour space used across StrandDesign: the «Hoy» paper
//     gradient (`paperHi`/`paperLo`/`inkDim`), `DiurnalDial.dayGold`, `ReferenceRange`,
//     and `positiveText`/`negativeText`.
//
// Removed in FER-398: the dawn/dusk/night anchors, `theme(at:)`, `anchorHours`, the
// per-minute `interpolated(to:)` / `contrastSafeDataHues()`, the 60s `InstrumentoThemeDriver`,
// and the `instrumentoThemeByHour()` modifier. Screens now apply `.instrumentoTheme(.base)`.

// MARK: - Solar window (injected; no StrandAnalytics dependency)

/// Local sunrise / sunset as clock hours (e.g. `6.5` == 06:30). The app computes these
/// from `StrandAnalytics.SolarClock.sunWindow(on:in:)` and injects them so the
/// `DiurnalDial`'s day arc tracks the real sun. Keeping this a plain value here means
/// `StrandDesign` stays dependency-free (the acyclic-graph rule).
public struct SolarWindow: Equatable, Sendable {
    public let sunrise: Double   // clock hours, 0...24
    public let sunset: Double    // clock hours, 0...24
    public init(sunrise: Double, sunset: Double) {
        self.sunrise = sunrise
        self.sunset = sunset
    }
}

// MARK: - OKLab core (pure, Foundation-only math)
//
// Björn Ottosson's OKLab (2020). sRGB transfer + the two 3×3 matrices; round-trips
// to <2e-3 per channel (asserted in tests). Used for perceptually-even colour mixes and
// the WCAG-contrast `darkened(_:toContrast:against:)` that keeps the data hues and
// `positiveText` legible on the warm paper.

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

    // MARK: WCAG contrast helpers (small-text AA for data hues — `positiveText`)

    /// WCAG 2.x relative luminance (0…1) of an sRGB color.
    static func relativeLuminance(_ c: Color) -> Double {
        let p = c.rgbaComponents
        return 0.2126 * srgbToLinear(p.r) + 0.7152 * srgbToLinear(p.g) + 0.0722 * srgbToLinear(p.b)
    }

    /// WCAG 2.x contrast ratio (1…21) between two colors.
    static func contrastRatio(_ a: Color, _ b: Color) -> Double {
        let la = relativeLuminance(a), lb = relativeLuminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// Darken `color` in OKLab — lowering perceptual lightness `L` while keeping its
    /// hue/chroma (`a`,`b`) — only as far as needed to reach `ratio` contrast against
    /// `bg`. Returns `color` unchanged when it already clears `ratio`. Bisects on `L`
    /// (contrast is monotonic in `L` on a light background), so it's deterministic and
    /// converges in a handful of iterations. Lets a data hue become AA-compliant for
    /// SMALL text against whatever paper is live, with no hand-tuned hex per hour.
    static func darkened(_ color: Color, toContrast ratio: Double, against bg: Color) -> Color {
        if contrastRatio(color, bg) >= ratio { return color }
        let c = color.rgbaComponents
        var lab = toLab((c.r, c.g, c.b))
        // L ∈ [0, origL]: lower L = darker = higher contrast on light paper. Find the
        // LIGHTEST L that still passes, so the hue is preserved as much as AA allows.
        var lo = 0.0, hi = lab.L
        for _ in 0..<16 {
            let mid = (lo + hi) / 2
            lab.L = mid
            let rgb = toRGB(lab)
            if contrastRatio(Color(.sRGB, red: rgb.r, green: rgb.g, blue: rgb.b), bg) >= ratio {
                lo = mid          // passes — the threshold is at or above here; try lighter
            } else {
                hi = mid          // fails — go darker
            }
        }
        lab.L = lo
        let rgb = toRGB(lab)
        return Color(.sRGB, red: rgb.r, green: rgb.g, blue: rgb.b)
    }
}
