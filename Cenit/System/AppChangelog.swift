import Foundation

/// Single source of truth for the in-app "What's New" screen and its expectation-setting copy.
/// This is the RECENT window, not the archive: the full history lives in the repo
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

    /// Expectation-setting points shown at the top of "What's New". This is the "what is this and
    /// what should I expect" story, so people don't have to go read GitHub.
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
            body: "Cénit is a personal, open project: a capable work-in-progress rather than a finished product. Its numbers are informed estimates, never clinical readings."),
        Expectation(
            icon: "heart.text.square",
            title: "Apple Health is the data path",
            body: "Cénit reads the samples your Apple Watch and iPhone already save to Apple Health: heart rate, HRV, sleep, workouts. It computes everything on your device, with no separate hardware to pair. Earlier versions read a fitness band directly; that path was retired, and any history it stored stays on your phone, untouched."),
        Expectation(
            icon: "hourglass",
            title: "Your trends build over a few nights",
            body: "The nightly reads are quick, but your baseline sharpens over your first couple of weeks as Cénit learns what's normal for you, and it always tells you when it's still calibrating. Want your history now? Import your Apple Health export in Data Sources and it backfills what you already have."),
        Expectation(
            icon: "lock.shield",
            title: "Everything stays on your device",
            body: "No account, no cloud, no sync. Cénit reads Apple Health on your device and keeps everything local. Your data is yours alone."),
    ]
}
