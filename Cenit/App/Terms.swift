import Foundation

/// The Terms of Use the first-run gate presents. Bump `currentVersion` when the terms MATERIALLY
/// change (risk / liability / medical / affiliation wording) to re-prompt every user for a fresh
/// acknowledgment; leave it for typo fixes. Mirrored on Android by `NoopPrefs.TERMS_VERSION`. The
/// full text lives in `TERMS.md`, shipped with Cénit.
enum Terms {
    static let currentVersion = "2.0"

    /// One load-bearing point the gate lists — plain-English summary of `TERMS.md` §1–§6.
    /// Kept identical in substance to the Android `Terms.points`.
    struct Point: Identifiable {
        let id: String
        let title: String
        let body: String
    }

    /// The four points the user must accept on first launch. Symbolic keys (`terms.pointN.*`) +
    /// English `defaultValue` — the catalog is `sourceLanguage: en`.
    static var points: [Point] {
        [
            Point(
                id: "1",
                title: String(localized: "terms.point1.title",
                              defaultValue: "Reads your data from Apple Health, on your device"),
                body: String(localized: "terms.point1.body",
                             defaultValue: "Cénit reads your health and fitness data directly from Apple Health, on your iPhone — no separate hardware pairing required.")
            ),
            Point(
                id: "2",
                title: String(localized: "terms.point2.title",
                              defaultValue: "Offline and local — no account, no server"),
                body: String(localized: "terms.point2.body",
                             defaultValue: "Every metric is processed and stored only on your device. There is no Cénit server, no Cénit account, and no telemetry — the maintainers cannot see your data and never receive it.")
            ),
            Point(
                id: "3",
                title: String(localized: "terms.point3.title",
                              defaultValue: "General wellness only — not a medical device"),
                body: String(localized: "terms.point3.body",
                             defaultValue: "Cénit is not a medical device and provides no medical advice. Every metric is an unvalidated approximation — don't use Cénit to diagnose, treat, or make any health decision. Always consult a qualified professional.")
            ),
            Point(
                id: "4",
                title: String(localized: "terms.point4.title",
                              defaultValue: "No warranty; liability limited"),
                body: String(localized: "terms.point4.body",
                             defaultValue: "Cénit is free and provided \"as is\", with no warranty. Liability is limited to the maximum extent the law that applies to you allows, and nothing here removes protections your local law won't let us remove.")
            ),
        ]
    }

    // MARK: - Gate chrome (TermsGateView)

    static var title: String {
        String(localized: "terms.title", defaultValue: "Before you use Cénit")
    }
    static var intro: String {
        String(localized: "terms.intro",
               defaultValue: "Please read and accept the points below.")
    }
    static var fine: String {
        String(localized: "terms.fine",
               defaultValue: "The full terms are in TERMS.md, shipped with Cénit. This is not legal advice.")
    }
    static var consent: String {
        String(localized: "terms.consent",
               defaultValue: "I have read and accept these terms, and I'm using Cénit with my own device and my own data, at my own risk.")
    }
    static var cta: String {
        String(localized: "terms.cta", defaultValue: "Accept & Continue")
    }
}
