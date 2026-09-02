import SwiftUI

// MARK: - Geometría del dial de 24 h (FER-134, adelgazado en FER-711)
//
// La matemática pura del cuadrante de 24 horas y la ventana de sueño inyectada. Antes vivían junto
// al `DiurnalDial` grande (el marcador héroe del TodayView original); el rediseño «Hoy» 2026-07
// (FER-707) retiró ese dial de la pantalla —el 24 h vive ahora en el sello del header (`DialSeal`)—
// así que en F3 (FER-711) el `DiurnalDial` y sus previews/tests se borraron y solo sobrevive esto:
// lo que `DialSeal` sigue necesitando (`SleepWindow` + `DialGeometry`). `SolarWindow` vive en
// `InstrumentoThemeEngine.swift`.
//
// Sin dependencias, como el resto de CenitDesign: las ventanas de sol y sueño se INYECTAN, nunca se
// importan. La app las calcula desde `StrandAnalytics.SolarClock` + el registro de sueño on-device y
// pasa valores planos. Puro y determinista: la geometría lee horas de reloj, nunca llama a `Date()`.

// MARK: - Injected sleep window (no StrandStore / HealthKit dependency)

/// The night's sleep window as clock hours (e.g. `23.5` == 23:30). The app reads this from the
/// on-device sleep record it already has — no new permission — and injects it, the same way
/// `SolarWindow` carries sunrise/sunset. Keeping it a plain value keeps `CenitDesign` the
/// dependency-free leaf of the package graph.
public struct SleepWindow: Equatable, Sendable {
    public let bedtime: Double   // clock hours, 0...24
    public let wake: Double      // clock hours, 0...24
    public init(bedtime: Double, wake: Double) {
        self.bedtime = bedtime
        self.wake = wake
    }
}

// MARK: - Geometry (pure, testable)

/// The pure math of the 24-hour face, factored out so the "now-dot is at the right place" claim can
/// be unit-tested without rendering anything. Shared by `DialSeal` (the header seal + pull spinner).
enum DialGeometry {

    /// Clock angle for an hour on the 24h face — **noon (12) up, midnight (0/24) down**, time
    /// advancing **clockwise**. In SwiftUI angle terms (0° points east, positive sweeps clockwise on
    /// the y-down canvas) that is `hour·15° − 270°`: 12→−90° (up), 18→0° (east), 24/0→90°/−270°
    /// (down), 6→−180° (west).
    static func degrees(forHour hour: Double) -> Double { hour * 15.0 - 270.0 }
    static func angle(forHour hour: Double) -> Angle { .degrees(degrees(forHour: hour)) }

    /// The point on a circle of `radius` about `center` for a clock hour.
    static func point(forHour hour: Double, center: CGPoint, radius: CGFloat) -> CGPoint {
        let a = degrees(forHour: hour) * .pi / 180.0
        let r = Double(radius)
        return CGPoint(x: Double(center.x) + r * cos(a), y: Double(center.y) + r * sin(a))
    }

    /// Forward span in hours from `from` to `to` going clockwise, wrapping midnight (e.g. 23.5 → 7.25
    /// == 7.75h). Used for the sleep band and the day arc.
    static func spanHours(from: Double, to: Double) -> Double {
        var span = to - from
        if span < 0 { span += 24 }
        return span
    }

    /// A clockwise arc between two clock hours (the seal's day arc + sleep band). Wraps midnight via
    /// `spanHours`, so `from > to` sweeps forward through 0. The arc geometry lives in exactly one place.
    static func arc(center: CGPoint, radius: CGFloat, fromHour: Double, toHour: Double) -> Path {
        let span = spanHours(from: fromHour, to: toHour)
        var path = Path()
        path.addArc(center: center, radius: radius,
                    startAngle: angle(forHour: fromHour),
                    endAngle: angle(forHour: fromHour + span),
                    clockwise: false)
        return path
    }
}
