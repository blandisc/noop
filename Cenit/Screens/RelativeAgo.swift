import Foundation

/// Coarse relative-time label for the "History synced N ago" sync-status line. Pure — `now` is
/// injectable so the bucket edges are unit-testable (RelativeAgoTests) — and deliberately the same
/// buckets as the Android `relativeAgo` (LiveScreen.kt, ed6a31d) so the two apps read identically.
/// Clamps future timestamps (strap-clock skew) to "just now", never negative.
///
/// FER-417 — extracted from the retired dark `ScreenScaffold.swift` so its live consumers (LiveView,
/// DataSourcesView, RelativeAgoTests) keep it after the dark scaffold was removed.
func relativeAgo(_ epochSeconds: TimeInterval,
                 now: TimeInterval = Date().timeIntervalSince1970) -> String {
    let d = max(0, Int(now - epochSeconds))
    switch d {
    case ..<60:     return String(localized: "just now")
    case ..<3600:   return String(localized: "\(d / 60) min ago")
    case ..<86_400: return String(localized: "\(d / 3600) h ago")
    default:        return String(localized: "\(d / 86_400) d ago")
    }
}
