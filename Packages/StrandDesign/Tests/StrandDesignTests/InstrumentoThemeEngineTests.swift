import XCTest
import SwiftUI
@testable import StrandDesign

/// FER-132 — by-the-hour theme engine. Proves the headline claim: WCAG AA on every
/// text/background pair at EVERY minute of the 24h sweep, smooth transitions, and a
/// legible datum at night. Mirrors the /arquitecto PoC, now against the real anchors.
final class InstrumentoThemeEngineTests: XCTestCase {

    // MARK: helpers

    private func utcCalendar() -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    private func midnight(_ cal: Calendar) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 6, day: 16))!
    }
    private func luminance(_ c: Color) -> Double {
        let k = c.rgbaComponents
        return 0.2126 * OKLab.srgbToLinear(k.r) + 0.7152 * OKLab.srgbToLinear(k.g) + 0.0722 * OKLab.srgbToLinear(k.b)
    }
    private func contrast(_ a: Color, _ b: Color) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }
    private func lab(_ c: Color) -> OKLab.Lab {
        let k = c.rgbaComponents
        return OKLab.toLab((k.r, k.g, k.b))
    }
    private func deltaE(_ a: Color, _ b: Color) -> Double {
        let x = lab(a), y = lab(b)
        return (pow(x.L - y.L, 2) + pow(x.a - y.a, 2) + pow(x.b - y.b, 2)).squareRoot()
    }
    /// Text/background pairs and their AA floor (4.5 normal text, 3.0 numeral/large).
    private func pairs(_ t: InstrumentoTheme) -> [(name: String, fg: Color, thr: Double)] {
        [("ink", t.ink, 4.5), ("inkSecondary", t.inkSecondary, 4.5), ("inkTertiary", t.inkTertiary, 4.5),
         ("dataRecovery", t.dataRecovery, 3.0), ("dataStrain", t.dataStrain, 3.0), ("verdict", t.verdict, 3.0),
         ("warning", t.warning, 4.5), ("critical", t.critical, 4.5)]
    }
    private func roles(_ t: InstrumentoTheme) -> [Color] {
        [t.paper, t.surface, t.hairline, t.hairlineStrong, t.ink, t.inkSecondary,
         t.inkTertiary, t.dataRecovery, t.dataStrain, t.verdict, t.warning, t.critical]
    }

    // MARK: OKLab math

    func testOKLabRoundTripIsStable() {
        for hex in ["#F4F1E8", "#221D16", "#0C8F62", "#C4631F", "#CDBE9F", "#191309", "#BC3A34", "#000000", "#FFFFFF"] {
            let k = Color(hex: hex).rgbaComponents
            let rt = OKLab.toRGB(OKLab.toLab((k.r, k.g, k.b)))
            XCTAssertEqual(rt.r, k.r, accuracy: 0.002, "\(hex) R")
            XCTAssertEqual(rt.g, k.g, accuracy: 0.002, "\(hex) G")
            XCTAssertEqual(rt.b, k.b, accuracy: 0.002, "\(hex) B")
        }
    }

    // MARK: anchors

    func testDayAnchorEqualsBase() {
        XCTAssertEqual(InstrumentoThemeEngine.day, InstrumentoTheme.base)
    }

    func testFourDistinctAnchors() {
        let a = [InstrumentoThemeEngine.dawn, InstrumentoThemeEngine.day,
                 InstrumentoThemeEngine.dusk, InstrumentoThemeEngine.night]
        for i in 0..<a.count { for j in (i + 1)..<a.count { XCTAssertNotEqual(a[i], a[j]) } }
    }

    // MARK: headline — AA at every minute of the day

    func testAAOnEveryPairAcrossTheWholeDay() {
        let cal = utcCalendar(), base = midnight(cal)
        var worst: [String: (c: Double, min: Int)] = [:]
        for minute in stride(from: 0, through: 24 * 60, by: 1) {
            let t = InstrumentoThemeEngine.theme(at: base.addingTimeInterval(Double(minute) * 60), calendar: cal)
            for p in pairs(t) {
                let c = contrast(p.fg, t.paper)
                if c < (worst[p.name]?.c ?? .infinity) { worst[p.name] = (c, minute) }
            }
        }
        for p in pairs(InstrumentoTheme.base) {
            let w = worst[p.name]!
            XCTAssertGreaterThanOrEqual(w.c, p.thr,
                "\(p.name): \(String(format: "%.2f", w.c)):1 at \(w.min / 60):\(String(format: "%02d", w.min % 60)) (req \(p.thr))")
        }
    }

    // MARK: headline — no perceptible jumps between adjacent minutes

    func testNoHardJumpsBetweenAdjacentMinutes() {
        let cal = utcCalendar(), base = midnight(cal)
        var prev: InstrumentoTheme?
        var maxDelta = 0.0
        for minute in stride(from: 0, through: 24 * 60, by: 1) {
            let t = InstrumentoThemeEngine.theme(at: base.addingTimeInterval(Double(minute) * 60), calendar: cal)
            if let p = prev {
                for (a, b) in zip(roles(p), roles(t)) { maxDelta = max(maxDelta, deltaE(a, b)) }
            }
            prev = t
        }
        // OKLab ΔE ~0.02 is the just-noticeable step; 0.05 is a comfortable anti-jump ceiling.
        XCTAssertLessThan(maxDelta, 0.05, "max ΔE between adjacent minutes = \(maxDelta)")
    }

    // MARK: 12:00 day vs 23:00 night

    func testNoonIsLightAndNightIsDimmer() {
        let cal = utcCalendar()
        func at(_ h: Int) -> InstrumentoTheme {
            InstrumentoThemeEngine.theme(at: cal.date(from: DateComponents(year: 2026, month: 6, day: 16, hour: h))!, calendar: cal)
        }
        let noon = at(12), night = at(23)
        XCTAssertGreaterThan(lab(noon.paper).L, lab(night.paper).L, "noon paper must be lighter than 23:00 paper")
        XCTAssertGreaterThan(lab(noon.paper).L, 0.85, "noon should read as light paper")
    }

    // MARK: datum stays legible at night

    func testDataAccentsLegibleAtNightAnchor() {
        let n = InstrumentoThemeEngine.night
        XCTAssertGreaterThanOrEqual(contrast(n.dataRecovery, n.paper), 3.0, "recovery dead at night")
        XCTAssertGreaterThanOrEqual(contrast(n.dataStrain, n.paper), 3.0, "strain dead at night")
    }

    // MARK: solar injection (FER-133 by injection, no dependency)

    func testSolarWindowMovesDawnAndDusk() {
        let s = InstrumentoThemeEngine.anchorHours(for: SolarWindow(sunrise: 7, sunset: 20))
        XCTAssertEqual(s.dawn, 7, accuracy: 0.001)
        XCTAssertEqual(s.day, 13.5, accuracy: 0.001)
        XCTAssertEqual(s.dusk, 20, accuracy: 0.001)
    }

    func testNilSolarFallsBackToFixedHours() {
        let f = InstrumentoThemeEngine.anchorHours(for: nil)
        XCTAssertEqual(f.dawn, 6.5, accuracy: 0.001)
        XCTAssertEqual(f.day, 13, accuracy: 0.001)
        XCTAssertEqual(f.dusk, 19, accuracy: 0.001)
    }

    func testDegenerateSolarFallsBackToFixedHours() {
        // sunrise at 0 → not strictly > 0 → reject and use fixed hours.
        let f = InstrumentoThemeEngine.anchorHours(for: SolarWindow(sunrise: 0, sunset: 20))
        XCTAssertEqual(f.dawn, 6.5, accuracy: 0.001)
    }

    /// AA must also hold on the PRODUCTION path, where the app injects a real solar
    /// window that shifts dawn/dusk. Anchor colors don't change with the sun (only
    /// their timing), so this is robust by construction — but pin it so a future
    /// regression in the solar schedule can't silently dip a pair below AA.
    func testAAHoldsUnderInjectedSolarWindows() {
        let cal = utcCalendar(), base = midnight(cal)
        let windows = [SolarWindow(sunrise: 5.0, sunset: 21.0),   // long summer day
                       SolarWindow(sunrise: 8.0, sunset: 16.5),   // short winter day
                       SolarWindow(sunrise: 6.2, sunset: 19.8)]   // temperate
        for w in windows {
            for minute in stride(from: 0, through: 24 * 60, by: 2) {
                let t = InstrumentoThemeEngine.theme(at: base.addingTimeInterval(Double(minute) * 60), calendar: cal, solar: w)
                for p in pairs(t) {
                    XCTAssertGreaterThanOrEqual(contrast(p.fg, t.paper), p.thr,
                        "\(p.name) below AA with sunrise \(w.sunrise) at \(minute / 60):\(String(format: "%02d", minute % 60))")
                }
            }
        }
    }

    // MARK: determinism

    func testEngineIsDeterministic() {
        let cal = utcCalendar()
        let d = cal.date(from: DateComponents(year: 2026, month: 6, day: 16, hour: 15, minute: 20))!
        XCTAssertEqual(InstrumentoThemeEngine.theme(at: d, calendar: cal),
                       InstrumentoThemeEngine.theme(at: d, calendar: cal))
    }
}
