import Foundation

/// Single source of truth for the in-app "What's New" screen and the expectation-setting copy used
/// in onboarding. This is the RECENT window, not the archive: the full history lives in the repo
/// CHANGELOG.md. (FER-994 E2 truncated the 81-release Mac/Android archive that shipped here: none
/// of it described the iOS app, and none of it was localized.)
enum AppChangelog {

    /// Bump this when you add a release below. The "What's New" sheet shows automatically when the
    /// stored last-seen version is behind this. (Decoupled from the bundle version on purpose.)
    static let currentVersion = "1.80"

    struct Release: Identifiable {
        let version: String
        let title: String
        let date: String
        let items: [String]
        var id: String { version }
    }

    /// Newest first.
    static let releases: [Release] = [
        Release(
            version: "1.80",
            title: "Journal logging + an Imperial/Metric units toggle",
            date: "June 2026",
            items: [
                "New: log how you're living: a journal card on the Insights screen with quick yes/no chips for behaviours (caffeine, alcohol, a late meal, screen time, and your own custom questions). Your entries stay on-device and are never overwritten by an import.",
                "New: an Imperial / Metric units toggle in Settings: distance (km / mi), weight (kg / lb), height (cm / ft-in) and temperature (°C / °F), with a separate temperature override. Everything stays stored the same; this only changes how it's shown.",
            ]),
        Release(
            version: "1.79",
            title: "Manual workouts, edit/dismiss auto-detected ones, and CSV export",
            date: "June 2026",
            items: [
                "New: add a workout by hand, and edit, re-label, or dismiss the ones Cénit auto-detects: so a misread bout or a duplicate no longer sticks around with no way to remove it. Dismissals are remembered, so a re-detected session stays hidden.",
                "New: export all your data as a CSV bundle (cycles, sleeps, workouts, journal) from Settings: yours to keep, and it imports straight back into Cénit.",
            ]),
        Release(
            version: "1.78",
            title: "Fewer false daytime sleeps",
            date: "June 2026",
            items: [
                "Fixed: a long sedentary daytime stretch, at your desk, on the couch, in a long meeting, no longer gets logged as sleep. Daytime periods now need a longer, genuinely low-heart-rate window before they count, while overnight sleep and real naps are unchanged.",
            ]),
    ]

    /// Expectation-setting points shown during onboarding and at the top of "What's New". This is the
    /// “what is this and what should I expect” story, so people don't have to go read GitHub.
    struct Expectation: Identifiable {
        let icon: String      // SF Symbol
        let title: String
        let body: String
        var id: String { title }
    }

    static let expectations: [Expectation] = [
        Expectation(
            icon: "flask",
            title: "Independent, and experimental",
            body: "Cénit is a personal, open project. It reads a strap you own, on your own device. Treat it as a capable work-in-progress rather than a finished product."),
        Expectation(
            icon: "checkmark.seal",
            title: "The 4.0 strap is the supported path",
            body: "A 4.0 strap is tested and works end to end. The 5.0/MG straps are newer: live heart rate works today, but deeper metrics (recovery, strain, sleep) for 5/MG are still being figured out. Cénit always tells you what's live versus still building."),
        Expectation(
            icon: "hourglass",
            title: "Your scores build over a few nights",
            body: "Live heart rate is instant. Recovery, strain and sleep sharpen as Cénit learns your baseline over your first nights of wear. Want your history now? Import your strap export in Data Sources and it backfills in about a minute."),
        Expectation(
            icon: "lock.shield",
            title: "Everything stays on your device",
            body: "No account, no cloud, no sync. Cénit talks only to your strap and keeps everything local. Your data is yours alone."),
    ]
}
